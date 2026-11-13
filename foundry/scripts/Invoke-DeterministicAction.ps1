[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$Stage,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][object]$Policy,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$OutputPath,
    [hashtable]$ActionEnvironment = @{},
    [AllowNull()][object]$Deadline = $null
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot 'DependencyEvolution.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$handler = [string]$Stage.action.handler
$stageId = [string]$Stage.id
$mutatingHandlers = @("apply_change_set", "create_work_items", "deliver_changes", "queue_pipeline")
if ($handler -in $mutatingHandlers) {
    $approvedBy = if ($Stage.PSObject.Properties.Name -contains "assurance") {
        [string]$Stage.assurance.approved_by
    } else { "" }
    if ([string]::IsNullOrWhiteSpace($approvedBy)) {
        throw "Mutating deterministic action '$stageId' has no approved_by review."
    }
    $state = Get-Content -LiteralPath (Join-Path $RunRoot "workflow-state.json") -Raw |
        ConvertFrom-Json -Depth 100 -ErrorAction Stop
    $approval = @($state.stages | Where-Object { [string]$_.id -eq $approvedBy })
    if ($approval.Count -ne 1 -or [string]$approval[0].status -ne "approved") {
        throw "Mutating deterministic action '$stageId' requires approved stage '$approvedBy'."
    }
}

if ($handler -eq "apply_change_set" -and -not [bool]$Config.delivery.dry_run -and
    [bool]$Config.delivery.apply_changes -and -not [bool]$Policy.delivery.allow_repository_changes) {
    throw "Policy denies repository change application."
}
if ($handler -eq "create_work_items" -and [bool]$Config.work_tracking.enabled -and
    -not [bool]$Config.work_tracking.dry_run -and -not [bool]$Policy.work_tracking.allow_create) {
    throw "Policy denies work item creation."
}
if ($handler -eq "queue_pipeline") {
    $ciConfig = if (@(Get-QaFoundryPropertyNames -InputObject $Config) -contains "ci") {
        $Config.ci
    } else { $null }
    # Denied only when something would actually be started. Every other mutating handler is gated
    # the same way, and a rehearsal that refuses to rehearse teaches nothing about the real run.
    $ciDryRun = $null -ne $ciConfig -and
        (@(Get-QaFoundryPropertyNames -InputObject $ciConfig) -contains "dry_run") -and
        [bool]$ciConfig.dry_run
    if (-not $ciDryRun) {
        $ciPolicy = if (@(Get-QaFoundryPropertyNames -InputObject $Policy) -contains "ci") {
            $Policy.ci
        } else { $null }
        $allowQueue = $null -ne $ciPolicy -and
            (@(Get-QaFoundryPropertyNames -InputObject $ciPolicy) -contains "allow_pipeline_queue") -and
            [bool]$ciPolicy.allow_pipeline_queue
        if (-not $allowQueue) {
            throw "Policy denies starting other pipelines."
        }
    }
}
if ($handler -eq "deliver_changes" -and -not [bool]$Config.delivery.dry_run) {
    if ([bool]$Config.delivery.create_branch -and -not [bool]$Policy.delivery.allow_branch_creation) {
        throw "Policy denies branch creation."
    }
    if ([bool]$Config.delivery.commit_changes -and -not [bool]$Policy.delivery.allow_commit) {
        throw "Policy denies commits."
    }
    if ([bool]$Config.delivery.push_branch -and -not [bool]$Policy.delivery.allow_push) {
        throw "Policy denies branch pushes."
    }
    if ([bool]$Config.delivery.create_draft_pull_request -and
        -not [bool]$Policy.delivery.allow_draft_pull_request) {
        throw "Policy denies draft pull request creation."
    }
}

function Find-ActionInput {
    if (-not ($Stage.action.PSObject.Properties.Name -contains "input") -or
        [string]::IsNullOrWhiteSpace([string]$Stage.action.input)) {
        return ""
    }
    $matches = @(Get-ChildItem -Path $RunRoot -File -Recurse -Filter ([string]$Stage.action.input) |
        Sort-Object LastWriteTimeUtc, FullName -Descending)
    if ($matches.Count -eq 0) {
        throw "Action '$stageId' cannot find input artifact '$($Stage.action.input)'."
    }
    return $matches[0].FullName
}

# An input named by stage and file name, resolved through what that stage
# recorded producing. Searching the run directory for the newest matching file
# picks the wrong document whenever a stage ran more than once, and a critic
# loop always runs more than once.
$script:declaredInputs = $null
function Resolve-DeclaredInput {
    param([Parameter(Mandatory)][string]$Name)

    if (-not ($Stage.action.PSObject.Properties.Name -contains "inputs")) {
        throw "Action '$stageId' declares no inputs, so '$Name' cannot be resolved."
    }
    if ($null -eq $script:declaredInputs) {
        $script:declaredInputs = Resolve-QaFoundryDeclaredInputs `
            -RunRoot $RunRoot -StageId $stageId -Inputs $Stage.action.inputs -RunId $RunId
    }
    if (-not $script:declaredInputs.Contains($Name)) {
        throw "Action '$stageId' does not declare an input named '$Name'."
    }
    return [string]$script:declaredInputs[$Name].path
}

# A rehearsed materialisation resolves nothing and carries no lock file, so a
# change set it produced describes a framework whose dependencies were never
# proved to exist. Reading one in a rehearsal is the point; committing one is
# how an unresolvable framework reaches a repository with an approval attached.
# The invariant itself lives in Common.ps1, next to the scripts that write, so
# that a caller reaching them directly cannot step around it.
function Assert-NotRehearsedChangeSet {
    param([string]$Path)

    Assert-QaFoundryRehearsalNotDelivered -ChangeSetPath $Path `
        -DeliveryIsLive (Test-QaFoundryDeliveryLeavesMachine -DeliveryConfig $Config.delivery) `
        -Context "Action '$stageId'"
}

$result = switch ($handler) {
    "apply_change_set" {
        $inputPath = Find-ActionInput
        Assert-NotRehearsedChangeSet -Path $inputPath
        & (Join-Path $PSScriptRoot "Apply-ScopedChangeSet.ps1") -PlanPath $inputPath `
            -Config $Config -RepositoryRoot $RepositoryRoot -RunRoot $RunRoot `
            -RunId $RunId -StageId $stageId
        break
    }
    "create_work_items" {
        $inputPath = Find-ActionInput
        & (Join-Path $PSScriptRoot "writers/New-WorkItems.ps1") -PlanPath $inputPath `
            -Config $Config -RepositoryRoot $RepositoryRoot -RunId $RunId `
            -StageId $stageId -ActionEnvironment $ActionEnvironment
        break
    }
    "queue_pipeline" {
        $pipelineName = if ($Stage.action.PSObject.Properties.Name -contains "pipeline") {
            [string]$Stage.action.pipeline
        } else { "" }
        if ([string]::IsNullOrWhiteSpace($pipelineName)) {
            throw "Action '$stageId' must name the pipeline it starts."
        }
        & (Join-Path $PSScriptRoot "writers/New-PipelineRuns.ps1") `
            -PlanPath (Resolve-DeclaredInput -Name "plan") `
            -WorkItemResultPath (Resolve-DeclaredInput -Name "workItems") `
            -PipelineName $pipelineName -Config $Config -RepositoryRoot $RepositoryRoot `
            -RunId $RunId -StageId $stageId -ActionEnvironment $ActionEnvironment
        break
    }
    "quality_suite" {
        $evidencePath = Join-Path (Split-Path $OutputPath -Parent) "quality-evidence.json"
        $quality = & (Join-Path $PSScriptRoot "collectors/Collect-QualityEvidence.ps1") `
            -RunId $RunId -Config $Config -Policy $Policy -RepositoryRoot $RepositoryRoot `
            -OutputPath $evidencePath -Deadline $Deadline
        $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
            -ArtifactPath $evidencePath `
            -SchemaPath (Join-Path $root "schemas/runtime/quality-evidence.schema.json") `
            -SchemaRoot (Join-Path $root "schemas")
        [pscustomobject][ordered]@{
            runId = $RunId; stageId = $stageId; handler = $handler
            status = if ([string]$quality.status -eq "no_action_needed") { "no_action_needed" } else { "completed" }
            dryRun = $false
            actions = @([pscustomobject][ordered]@{
                sourceRef = $RepositoryRoot; type = "evidence.quality"
                idempotencyKey = ""; status = "executed"
                externalId = ""; summary = "Collected deterministic build, test, lint, dependency, and secret-scan evidence."
            })
            evidence = @($evidencePath)
        }
        break
    }
    "collect_observability" {
        $evidencePath = Join-Path (Split-Path $OutputPath -Parent) "observability-evidence.json"
        $observability = & (Join-Path $PSScriptRoot "collectors/Collect-ObservabilityEvidence.ps1") `
            -RunId $RunId -Config $Config -RepositoryRoot $RepositoryRoot -OutputPath $evidencePath
        $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
            -ArtifactPath $evidencePath `
            -SchemaPath (Join-Path $root "schemas/runtime/observability-evidence.schema.json") `
            -SchemaRoot (Join-Path $root "schemas")
        [pscustomobject][ordered]@{
            runId = $RunId; stageId = $stageId; handler = $handler
            status = [string]$observability.status; dryRun = $false
            actions = @([pscustomobject][ordered]@{
                sourceRef = $RepositoryRoot; type = "evidence.observability"
                idempotencyKey = ""; status = "executed"
                externalId = ""; summary = "Collected bounded, redacted observability evidence."
            })
            evidence = @($evidencePath)
        }
        break
    }
    "deliver_changes" {
        # The reviewers approved a specific change set. A stage that declares
        # which one is delivering that one; a stage that declares nothing is
        # left to the fallback, which says out loud that it is guessing.
        $deliverySet = ""
        if (($Stage.action.PSObject.Properties.Name -contains "inputs") -and
            $null -ne $Stage.action.inputs) {
            $deliverySet = Resolve-DeclaredInput -Name "changeSet"
        }
        Assert-NotRehearsedChangeSet -Path $deliverySet
        & (Join-Path $PSScriptRoot "writers/Publish-RepositoryDelivery.ps1") `
            -Config $Config -RepositoryRoot $RepositoryRoot -RunRoot $RunRoot `
            -RunId $RunId -StageId $stageId -ChangeSetPath $deliverySet `
            -ActionEnvironment $ActionEnvironment
        break
    }
    "materialize_change_set" {
        $stageDirectory = Split-Path $OutputPath -Parent
        # The resolver writes a manifest and a lock into its working directory.
        # Anything left inside the run directory becomes context for later agents
        # and an artifact the run-artifact check has no schema for, so the work
        # happens beside the run rather than inside it. The shared temp
        # directory would do the same job at a path anyone on the machine can
        # predict and pre-create, so the scratch area lives next to the runs it
        # belongs to and is named unpredictably.
        $scratchParent = Join-Path (Split-Path $RunRoot -Parent) ".scratch"
        $workRoot = Join-Path $scratchParent ("$RunId-$stageId-" + [guid]::NewGuid().ToString("n"))
        # Named after the run and the stage rather than unpredictably, because
        # this one has to be findable by the next leg: it holds the locks
        # already resolved, and losing it means resolving them all again.
        $checkpointRoot = Join-Path $scratchParent "$RunId-$stageId-locks"
        if (Test-Path -LiteralPath $workRoot) {
            throw "The materialisation scratch directory already exists: $workRoot"
        }
        New-Item -ItemType Directory -Path $workRoot -Force | Out-Null
        try {
            $automationConfig = if (@(Get-QaFoundryPropertyNames -InputObject $Config) -contains "automation") {
                $Config.automation
            } else { $null }
            $materializationConfig = if ($null -ne $automationConfig -and
                @(Get-QaFoundryPropertyNames -InputObject $automationConfig) -contains "materialization") {
                $automationConfig.materialization
            } else { $null }
            $materializationDryRun = $null -ne $materializationConfig -and
                (@(Get-QaFoundryPropertyNames -InputObject $materializationConfig) -contains "dry_run") -and
                [bool]$materializationConfig.dry_run
            # A change set written by the mock provider names dependencies nobody
            # chose. Resolving those against a real registry installs whatever
            # happens to answer to those names and writes a lock as though a
            # decision stood behind it, so a mocked run rehearses whatever the
            # configuration says.
            $aiConfig = if (@(Get-QaFoundryPropertyNames -InputObject $Config) -contains "ai") {
                $Config.ai
            } else { $null }
            if ($null -ne $aiConfig -and
                (@(Get-QaFoundryPropertyNames -InputObject $aiConfig) -contains "provider") -and
                ([string]$aiConfig.provider) -eq "mock") {
                $materializationDryRun = $true
            }
            & (Join-Path $PSScriptRoot "actions/New-MaterializedChangeSet.ps1") `
                -PlanPath (Resolve-DeclaredInput -Name "plan") `
                -RunConfigurationPath (Join-Path $RunRoot "context/run-configuration.json") `
                -BlueprintPath (Resolve-DeclaredInput -Name "blueprint") `
                -ToolchainLockPath (Get-QaFoundryActiveToolchainPath -RunRoot $RunRoot) `
                -RunId $RunId -StageId $stageId `
                -OutputPath (Join-Path $stageDirectory "change-set.json") `
                -ReviewSubjectPath (Join-Path $stageDirectory "change-review-subject.json") `
                -EvidencePath (Join-Path $stageDirectory "resolver-evidence.json") `
                -WorkRoot $workRoot `
                -CheckpointRoot $checkpointRoot `
                -RunRoot $RunRoot `
                -ToolchainRecordPath (Get-QaFoundryToolchainRecordRelativePath -Config $Config) `
                -RepositoryRoot $RepositoryRoot `
                -Deadline $Deadline `
                -DryRun:$materializationDryRun
        }
        finally {
            Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        break
    }
    "resolve_toolchain" {
        $stageDirectory = Split-Path $OutputPath -Parent
        # The lock lands in context rather than in the stage directory. Every
        # later agent has to build against what was actually pinned, not against
        # what the architect proposed, and context is the one place they all
        # read.
        $toolchainResult = & (Join-Path $PSScriptRoot "actions/Resolve-ToolchainLock.ps1") `
            -BlueprintPath (Resolve-DeclaredInput -Name "blueprint") `
            -Config $Config `
            -RunId $RunId -StageId $stageId `
            -OutputPath (Join-Path $RunRoot "context/toolchain-lock.json") `
            -EvidencePath (Join-Path $stageDirectory "toolchain-evidence.json")
        if ($toolchainResult.status -eq 'completed') {
            $probeDryRun = $Config.automation.PSObject.Properties['verification'] -and
                $Config.automation.verification.PSObject.Properties['dry_run'] -and
                [bool]$Config.automation.verification.dry_run
            $scratchParent = Join-Path (Split-Path $RunRoot -Parent) '.scratch'
            $scratch = Join-Path $scratchParent ([guid]::NewGuid().ToString('N'))
            try {
                $probePath = Join-Path $stageDirectory 'toolchain-smoke.json'
                $probe = & (Join-Path $PSScriptRoot 'actions/Test-ToolchainReadiness.ps1') `
                    -ToolchainLockPath (Join-Path $RunRoot 'context/toolchain-lock.json') `
                    -OutputPath $probePath -WorkRoot $scratch -DryRun:$probeDryRun `
                    -DeferExecution:(Test-QaFoundryDeferredVerification -Config $Config) -Deadline $Deadline
                $toolchainResult.evidence += $probePath
                if ($probe.status -ne 'completed') {
                    $toolchainResult.status = if ($probe.failureKind -eq 'artifact_invalid') { 'revision_required' } else { 'blocked' }
                    $toolchainResult | Add-Member -NotePropertyName failureKind -NotePropertyValue $probe.failureKind -Force
                    if ($toolchainResult.status -eq 'revision_required') {
                        $rejectedLock = Join-Path $stageDirectory 'rejected-toolchain-lock.json'
                        Move-Item -LiteralPath (Join-Path $RunRoot 'context/toolchain-lock.json') -Destination $rejectedLock -Force
                        $toolchainResult.evidence += $rejectedLock
                        $toolchainResult.produced = @()
                    }
                }
            }
            finally {
                if ((Test-PathWithinRoot -Candidate $scratch -Root $scratchParent) -and (Test-Path -LiteralPath $scratch)) {
                    Remove-Item -LiteralPath $scratch -Recurse -Force
                }
            }
        }
        $toolchainResult
        break
    }
    "verify_framework" {
        $stageDirectory = Split-Path $OutputPath -Parent
        # Installed tools must execute on the workspace filesystem: /tmp can
        # be mounted noexec. Only IPC needs a short temp path, not the sources.
        # Keep both outside the run evidence directory.
        . (Join-Path $PSScriptRoot 'VerificationScratch.ps1')
        $verificationIsolation = Get-QaFoundryIsolationSetting -Config $Config
        $scratchParent = Join-Path (Split-Path $RunRoot -Parent) '.scratch'
        $workRoot = New-QaFoundryVerificationScratch -Parent $scratchParent -Container:($verificationIsolation.mode -eq 'container')
        $pipeRoot = ''
        try {
            if (-not $IsWindows -and $verificationIsolation.mode -ne 'container') {
                $pipeRoot = New-QaFoundryVerificationScratch
            }
            $automationConfig = if (@(Get-QaFoundryPropertyNames -InputObject $Config) -contains "automation") {
                $Config.automation
            } else { $null }
            $verificationConfig = if ($null -ne $automationConfig -and
                @(Get-QaFoundryPropertyNames -InputObject $automationConfig) -contains "verification") {
                $automationConfig.verification
            } else { $null }
            $verificationDryRun = $null -ne $verificationConfig -and
                (@(Get-QaFoundryPropertyNames -InputObject $verificationConfig) -contains "dry_run") -and
                [bool]$verificationConfig.dry_run
            & (Join-Path $PSScriptRoot "actions/Test-MaterializedFramework.ps1") `
                -ChangeSetPath (Resolve-DeclaredInput -Name "changeSet") `
                -ToolchainLockPath (Get-QaFoundryActiveToolchainPath -RunRoot $RunRoot) `
                -RunId $RunId -StageId $stageId `
                -OutputPath (Join-Path $stageDirectory "framework-verification.json") `
                -WorkRoot $workRoot `
                -DryRun:$verificationDryRun `
                -DeferExecution:(Test-QaFoundryDeferredVerification -Config $Config) `
                -PipeDirectory $pipeRoot `
                -Isolation $verificationIsolation `
                -Deadline $Deadline
        }
        finally {
            Remove-QaFoundryVerificationScratch -Path $workRoot -Parent $scratchParent
            if ($pipeRoot) { Remove-QaFoundryVerificationScratch -Path $pipeRoot }
        }
        break
    }
    default { throw "Unsupported deterministic action handler: $handler" }
}

New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force | Out-Null
$result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding utf8
$null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") -ArtifactPath $OutputPath `
    -SchemaPath (Join-Path $root "schemas/actions/action-result.schema.json") `
    -SchemaRoot (Join-Path $root "schemas")
return $result
