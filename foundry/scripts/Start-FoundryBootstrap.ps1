[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [ValidateSet("Auto", "Plan", "Finalize", "Repair")][string]$Phase = "Auto",
    [string]$CurrentRef = "",
    [string]$ResumeRunRoot = "",
    [string]$RestartStage = "",
    [int]$BudgetMinutes = 0,
    [string]$DocumentationLinks = '',
    [string]$PreparedProjectConfigPath = '',
    [switch]$Demo
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common.ps1")
$frameworkRoot = Get-QaFoundryRoot
$launcherRoot = (Get-Location).Path
$resolvedConfigPath = Resolve-QaFoundryPath -Root $launcherRoot -Path $ConfigPath
if (-not (Test-Path -LiteralPath $resolvedConfigPath -PathType Leaf)) {
    throw "Bootstrap configuration does not exist: $resolvedConfigPath"
}
$bootstrapConfig = Import-QaFoundryYaml -Path $resolvedConfigPath -Root $frameworkRoot
$isGitHub = ($bootstrapConfig.PSObject.Properties.Name -contains "provider") -and $bootstrapConfig.provider -eq "github"
$null = & (Join-Path $PSScriptRoot "Validate-BootstrapConfig.ps1") `
    -Config $bootstrapConfig -Root $frameworkRoot
if ($Demo) {
    # A rehearsal has to be a rehearsal in every phase. Registration reads this configuration rather
    # than the project one, and Finalize and Repair never read the project one at all, so setting it
    # here - before any phase is chosen - is what makes -Demo mean the same thing throughout.
    if ($isGitHub) { $bootstrapConfig.github.dry_run = $true } else { $bootstrapConfig.azure_devops.dry_run = $true }
}
$configDirectory = Split-Path $resolvedConfigPath -Parent
$repositoryRoot = Resolve-QaFoundryPath -Root $configDirectory `
    -Path ([string]$bootstrapConfig.target.repository_path)
if (-not (Test-Path -LiteralPath $repositoryRoot -PathType Container)) {
    throw "Bootstrap target repository does not exist: $repositoryRoot"
}
$repositoryRoot = (Resolve-Path $repositoryRoot).Path

function Resolve-RepositoryRelativePath {
    param([Parameter(Mandatory)][string]$Path)
    if ([IO.Path]::IsPathRooted($Path)) {
        throw "Bootstrap repository path must be relative: $Path"
    }
    $resolved = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $Path))
    if (-not (Test-PathWithinRoot -Candidate $resolved -Root $repositoryRoot)) {
        throw "Bootstrap path escapes the target repository: $Path"
    }
    return $resolved
}

$configuredFrameworkRoot = Resolve-RepositoryRelativePath -Path ([string]$bootstrapConfig.framework.path)
if (-not (Test-Path -LiteralPath (Join-Path $configuredFrameworkRoot "scripts/Invoke-Foundry.ps1") -PathType Leaf)) {
    throw "Configured framework.path does not contain SDLC Foundry: $configuredFrameworkRoot"
}
if ((Resolve-Path $configuredFrameworkRoot).Path -ne (Resolve-Path $frameworkRoot).Path) {
    $configuredEntry = Join-Path $configuredFrameworkRoot "scripts/Start-FoundryBootstrap.ps1"
    $executingEntry = Join-Path $frameworkRoot "scripts/Start-FoundryBootstrap.ps1"
    $configuredHash = (Get-FileHash -LiteralPath $configuredEntry -Algorithm SHA256).Hash
    $executingHash = (Get-FileHash -LiteralPath $executingEntry -Algorithm SHA256).Hash
    if ($configuredHash -ne $executingHash) {
        throw "The executing Foundry folder does not match framework.path in the bootstrap configuration."
    }
}
$projectConfigPath = Resolve-RepositoryRelativePath `
    -Path ([string]$bootstrapConfig.framework.project_config_path)
if ($PreparedProjectConfigPath) {
    if (-not $isGitHub -or $Phase -ne 'Plan') {throw 'PreparedProjectConfigPath is only supported for GitHub Plan.'}
    $projectConfigPath = Resolve-QaFoundryPath -Root $launcherRoot -Path $PreparedProjectConfigPath
    if (-not (Test-PathWithinRoot -Candidate $projectConfigPath -Root (Join-Path $repositoryRoot '.qa-foundry-artifacts'))) {
        throw 'Prepared configuration must remain inside the target evidence directory.'
    }
}
$policyPath = Resolve-RepositoryRelativePath `
    -Path ([string]$bootstrapConfig.framework.policy_path)
$workflowPath = Resolve-RepositoryRelativePath `
    -Path ([string]$bootstrapConfig.framework.bootstrap_workflow_path)
foreach ($requiredPath in @($projectConfigPath, $policyPath, $workflowPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Bootstrap input does not exist: $requiredPath"
    }
}

$configurationHash = (Get-FileHash -LiteralPath $resolvedConfigPath -Algorithm SHA256).Hash.ToLowerInvariant()
$managedRoot = ([string]$bootstrapConfig.installation.managed_root).Replace("\", "/").Trim("/")
$committedPlanPath = Join-Path $repositoryRoot "$managedRoot/installation-plan.json"
$targetRef = "refs/heads/$([string]$bootstrapConfig.target.branch)"
if ([string]::IsNullOrWhiteSpace($CurrentRef)) {
    $CurrentRef = if ($isGitHub) { [string]$env:GITHUB_REF } else { [string]$env:BUILD_SOURCEBRANCH }
}
if ([string]::IsNullOrWhiteSpace($CurrentRef)) {
    $gitRef = & git -C $repositoryRoot symbolic-ref -q HEAD 2>$null
    if ($LASTEXITCODE -eq 0) { $CurrentRef = [string]$gitRef }
}

$artifactsRoot = Resolve-RepositoryRelativePath `
    -Path ([string]$bootstrapConfig.installation.artifacts_root)
$runId = "bootstrap-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$runRoot = Join-Path $artifactsRoot $runId
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
if ([Environment]::GetEnvironmentVariable('FOUNDRY_LOG_STYLE') -eq 'summary') {
    $env:FOUNDRY_DIAGNOSTICS_DIRECTORY = Join-Path $runRoot 'logs'
}

function Complete-BootstrapRun {
    param([Parameter(Mandatory)][object]$Result)
    if ($isGitHub) {
        $Result | Add-Member -NotePropertyName provider -NotePropertyValue 'github' -Force
        $Result | Add-Member -NotePropertyName repositoryUrl -NotePropertyValue "https://github.com/$($bootstrapConfig.github.repository)" -Force
    }
    $resultPath = Join-Path $runRoot "bootstrap-result.json"
    $Result | ConvertTo-Json -Depth 100 |
        Set-Content -LiteralPath $resultPath -Encoding utf8
    $Result | Add-Member -NotePropertyName resultPath -NotePropertyValue $resultPath -Force
    $reportRunRoot = if ($analysisRun) { [string]$analysisRun.runRoot } else { $runRoot }
    $reportPath = Join-Path $runRoot 'report.html'
    & (Join-Path $PSScriptRoot 'Export-FoundryReport.ps1') -RepositoryRoot $repositoryRoot `
        -RunRoot $reportRunRoot -OutputPath $reportPath -BootstrapResultPath $resultPath
    $Result | Add-Member -NotePropertyName reportPath -NotePropertyValue $reportPath -Force
    return $Result
}

$analysisRun = $null
$resolvedPhase = $Phase
if ($Phase -eq "Auto") {
    if (Test-Path -LiteralPath $committedPlanPath -PathType Leaf) {
        $resolvedPhase = if ($CurrentRef -eq $targetRef) { "Finalize" } else { "AwaitMerge" }
    }
    else {
        $resolvedPhase = "Plan"
    }
}
Write-QaFoundryLog -Level step -Message "Bootstrap run $runId starting."
Write-QaFoundryLog -Message "Target repository: $repositoryRoot"
Write-QaFoundryLog -Message "Requested phase '$Phase' resolved to '$resolvedPhase'."
Write-QaFoundryLog -Message "Current ref '$CurrentRef', target ref '$targetRef'."
Write-QaFoundryLog -Message "Evidence for this run is written to $runRoot"

if ($resolvedPhase -eq "AwaitMerge") {
    Write-QaFoundryLog -Level warn -Message (
        "An installation plan already exists but this build is not on the target branch. " +
        "Merge the draft pull request, then this pipeline finalises the installation automatically.")
    return Complete-BootstrapRun -Result ([pscustomobject][ordered]@{
        runId = $runId
        phase = "await_merge"
        status = "awaiting_merge"
        currentRef = $CurrentRef
        targetRef = $targetRef
        runRoot = $runRoot
        message = "Installation plan exists, but finalization is allowed only on the target branch."
    })
}

if ($resolvedPhase -eq "Plan") {
    Write-QaFoundryLog -Level step -Message "Validating configuration, policy and workflow."
    $validation = @(& (Join-Path $frameworkRoot "scripts/Invoke-Foundry.ps1") `
        -ConfigPath $projectConfigPath `
        -WorkflowPath $workflowPath `
        -PolicyPath $policyPath `
        -ValidateOnly `
        -Demo:$Demo)[-1]
    Write-QaFoundryLog -Message "Configuration accepted."

    $analysisRun = $null
    $analysisChangeSetPath = ""
    if ([bool]$bootstrapConfig.installation.run_analysis) {
        Write-QaFoundryLog -Level step -Message (
            "Running the multi-agent analysis workflow. " +
            "This is the long part of the bootstrap; each agent reports below as it completes.")
        $analysisStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $analysisRun = @(& (Join-Path $frameworkRoot "scripts/Invoke-Foundry.ps1") `
            -ConfigPath $projectConfigPath `
            -WorkflowPath $workflowPath `
            -PolicyPath $policyPath `
            -EventType manual `
            -ResumeRunRoot $ResumeRunRoot `
            -RestartStage $RestartStage `
            -BudgetMinutes $BudgetMinutes `
            -DocumentationLinks $DocumentationLinks `
            -Demo:$Demo)[-1]
        $analysisStopwatch.Stop()
        Write-QaFoundryLog -Message (
            "Analysis finished as '$([string]$analysisRun.status)' " +
            "in $(Format-QaFoundryDuration $analysisStopwatch.Elapsed).")
        if ([string]$analysisRun.status -eq "paused") {
            # The leg ran out of time on an agent boundary. Everything produced
            # so far is on disk, so the next leg continues instead of restarting.
            Write-QaFoundryLog -Level "warn" -Message (
                "The analysis paused before its time budget ran out. Resume it with " +
                "-ResumeRunRoot '$([string]$analysisRun.runRoot)'.")
            return Complete-BootstrapRun -Result ([pscustomobject][ordered]@{
                runId = $runId
                phase = "plan"
                status = "paused"
                currentRef = $CurrentRef
                targetRef = $targetRef
                runRoot = $runRoot
                analysisRunId = [string]$analysisRun.runId
                resumeRunRoot = [string]$analysisRun.runRoot
                message = "The analysis paused on an agent boundary and can be resumed from resumeRunRoot."
            })
        }
        if ([string]$analysisRun.status -eq "blocked") {
            # A stage reported a terminal blocker rather than deliver something
            # unsafe. The run is over and must not resume, but it ended on a
            # judgement, so the leg reports a stopped run carrying that judgement
            # instead of a crash.
            Write-QaFoundryLog -Level "warn" -Message (
                "The analysis stopped: a stage blocked the run. Its reasoning is in " +
                "'$([string]$analysisRun.runRoot)'.")
            return Complete-BootstrapRun -Result ([pscustomobject][ordered]@{
                runId = $runId
                phase = "plan"
                status = "blocked"
                currentRef = $CurrentRef
                targetRef = $targetRef
                runRoot = $runRoot
                analysisRunId = [string]$analysisRun.runId
                resumeRunRoot = ""
                message = "A stage blocked the run. It cannot be resumed and needs a decision."
            })
        }
        if ([string]$analysisRun.status -ne "completed") {
            throw "Bootstrap analysis did not complete: $([string]$analysisRun.status)"
        }
        $analysisState = Get-Content -LiteralPath ([string]$analysisRun.statePath) -Raw |
            ConvertFrom-Json -Depth 100
        $reviewStage = @($analysisState.stages | Where-Object { $_.id -eq "bootstrap-change-review" })
        if ($reviewStage.Count -ne 1 -or [string]$reviewStage[0].status -ne "approved") {
            throw "Bootstrap change set has no unanimous bootstrap-change-review approval."
        }
        # What the reviewers approved was a specific set of bytes. The review
        # attempt records the review subject it was handed, by hash; the
        # materialisation attempt that published that exact subject is the one
        # whose change set may be applied. Picking the newest change-set.json,
        # or the materialisation nearest in iteration, would apply whatever was
        # written last, which after a revision is not what anyone approved.
        $approvedReviewAttempts = @($reviewStage[0].attempts |
            Where-Object { [string]$_.status -in @("approved", "approved_with_dissent") })
        if ($approvedReviewAttempts.Count -eq 0) {
            throw "Bootstrap change review reports approval but records no approved attempt."
        }
        $approvedInputs = @($approvedReviewAttempts[-1].inputs |
            Where-Object { [string]$_.name -ceq "change-review-subject.json" })
        if ($approvedInputs.Count -ne 1) {
            throw ("The approved bootstrap review does not record which review subject it judged, " +
                "so its approval cannot be tied to a change set.")
        }
        $approvedSubjectSha = [string]$approvedInputs[0].sha256
        $materializationStage = @($analysisState.stages |
            Where-Object { $_.id -eq "bootstrap-change-materialization" })
        if ($materializationStage.Count -ne 1) {
            throw "Bootstrap analysis ran no dependency materialisation stage."
        }
        $materializationAttempts = @($materializationStage[0].attempts |
            Where-Object {
                [string]$_.status -eq "completed" -and
                @($_.artifacts | Where-Object {
                    [string]$_.name -ceq "change-review-subject.json" -and
                    [string]$_.sha256 -ceq $approvedSubjectSha
                }).Count -eq 1
            })
        if ($materializationAttempts.Count -ne 1) {
            throw ("Bootstrap analysis approved review subject $approvedSubjectSha, which " +
                "$($materializationAttempts.Count) materialisation attempt(s) produced.")
        }
        $materializationAttempt = $materializationAttempts[0]
        $reviewSubjectRecord = @($materializationAttempt.artifacts |
            Where-Object { [string]$_.name -ceq "change-review-subject.json" })
        $changeSetRecord = @($materializationAttempt.artifacts |
            Where-Object { [string]$_.name -ceq "change-set.json" })
        if ($reviewSubjectRecord.Count -ne 1 -or $changeSetRecord.Count -ne 1) {
            throw "The approved materialisation attempt did not record both a change set and a review subject."
        }
        $reviewSubjectPath = Resolve-QaFoundryRunArtifactPath `
            -RunRoot ([string]$analysisRun.runRoot) `
            -RelativePath ([string]$reviewSubjectRecord[0].relativePath) `
            -Description "the approved review subject"
        $analysisChangeSetPath = Resolve-QaFoundryRunArtifactPath `
            -RunRoot ([string]$analysisRun.runRoot) `
            -RelativePath ([string]$changeSetRecord[0].relativePath) `
            -Description "the approved change set"
        # Three checks, because a hash written inside a file proves nothing on
        # its own: whoever could rewrite the change set could rewrite the
        # subject that vouches for it. The run state is the record that was not
        # in reach of either edit.
        $subjectHash = (Get-FileHash -LiteralPath $reviewSubjectPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($subjectHash -cne $approvedSubjectSha) {
            throw ("The bootstrap review subject has changed since it was approved. The review " +
                "approved $approvedSubjectSha; this file hashes to $subjectHash.")
        }
        $changeSetHash = (Get-FileHash -LiteralPath $analysisChangeSetPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($changeSetHash -cne [string]$changeSetRecord[0].sha256) {
            throw ("The bootstrap change set has changed since the materialisation stage produced it. " +
                "That stage recorded $([string]$changeSetRecord[0].sha256); this file hashes to $changeSetHash.")
        }
        $reviewSubject = Get-Content -LiteralPath $reviewSubjectPath -Raw | ConvertFrom-Json -Depth 100
        if ($changeSetHash -cne [string]$reviewSubject.finalChangeSetSha256) {
            throw ("The bootstrap change set is not the one the approved review subject names. The " +
                "review approved $([string]$reviewSubject.finalChangeSetSha256); this file hashes to " +
                "$changeSetHash.")
        }
    }

    $projectConfig = Import-QaFoundryYaml -Path $projectConfigPath -Root $frameworkRoot
    $policy = Import-QaFoundryYaml -Path $policyPath -Root $frameworkRoot
    if ($Demo) {
        # A rehearsal still writes the installation to the working tree - that is the thing being
        # rehearsed. What it must not do is anything that leaves this machine, because those are
        # the effects nobody can take back: a pushed branch, a pull request, a filed work item, a
        # pipeline started somewhere else.
        $projectConfig.delivery.push_branch = $false
        $projectConfig.delivery.create_draft_pull_request = $false
        $projectConfig.work_tracking.dry_run = $true
        if (@(Get-QaFoundryPropertyNames -InputObject $projectConfig.ci) -contains "dry_run") {
            $projectConfig.ci.dry_run = $true
        }
    }
    if (-not [bool]$projectConfig.delivery.dry_run -and
        [bool]$projectConfig.delivery.apply_changes -and
        -not [bool]$policy.delivery.allow_repository_changes) {
        throw "Bootstrap policy denies repository change application."
    }
    foreach ($deliveryPermission in @(
        @{ Enabled = [bool]$projectConfig.delivery.create_branch; Allowed = [bool]$policy.delivery.allow_branch_creation; Name = "branch creation" },
        @{ Enabled = [bool]$projectConfig.delivery.commit_changes; Allowed = [bool]$policy.delivery.allow_commit; Name = "commit creation" },
        @{ Enabled = [bool]$projectConfig.delivery.push_branch; Allowed = [bool]$policy.delivery.allow_push; Name = "branch push" },
        @{ Enabled = [bool]$projectConfig.delivery.create_draft_pull_request; Allowed = [bool]$policy.delivery.allow_draft_pull_request; Name = "draft pull request creation" }
    )) {
        if (-not [bool]$projectConfig.delivery.dry_run -and
            [bool]$deliveryPermission.Enabled -and -not [bool]$deliveryPermission.Allowed) {
            throw "Bootstrap policy denies $([string]$deliveryPermission.Name)."
        }
    }
    Write-QaFoundryLog -Level step -Message "Building the installation change set."
    # Only the deterministic installer may add this exact root-level report. The
    # agent configuration still forbids all Foundry runtime and product edits.
    $projectConfig.repository.allowed_write_paths = @($projectConfig.repository.allowed_write_paths) + @('foundry-report.html')
    $reportPath = Join-Path $runRoot 'report.html'
    & (Join-Path $PSScriptRoot 'Export-FoundryReport.ps1') -RepositoryRoot $repositoryRoot `
        -RunRoot $(if ($analysisRun) { [string]$analysisRun.runRoot } else { $runRoot }) -OutputPath $reportPath
    $planResult = & (Join-Path $frameworkRoot "scripts/New-BootstrapChangeSet.ps1") `
        -BootstrapConfig $bootstrapConfig `
        -ProjectConfig $projectConfig `
        -RepositoryRoot $repositoryRoot `
        -FrameworkRoot $frameworkRoot `
        -RunRoot $runRoot `
        -RunId $runId `
        -ConfigurationHash $configurationHash `
        -AnalysisRunId $(if ($analysisRun) { [string]$analysisRun.runId } else { "" }) `
        -AnalysisChangeSetPath $analysisChangeSetPath `
        -ReportPath $reportPath
    Write-QaFoundryLog -Message "Change set written to $([string]$planResult.changeSetPath)"

    $loadedEnvironment = if ($Demo) {
        @{}
    }
    else {
        & (Join-Path $frameworkRoot "scripts/Import-QaFoundrySecrets.ps1") `
            -SecretsConfig $projectConfig.secrets `
            -ConfigDirectory (Split-Path $projectConfigPath -Parent) `
            -TargetRoot $repositoryRoot
    }
    if ($null -eq $loadedEnvironment) { $loadedEnvironment = @{} }
    $actionEnvironment = @{}
    $deliverySecretName = if ($isGitHub) { [string]$projectConfig.delivery.github.auth_env } else { [string]$projectConfig.delivery.azure_devops.auth_env }
    if ($loadedEnvironment.ContainsKey($deliverySecretName)) {
        $actionEnvironment[$deliverySecretName] = [string]$loadedEnvironment[$deliverySecretName]
    }
    Write-QaFoundryLog -Level step -Message "Applying the change set inside the repository scope."
    $apply = & (Join-Path $frameworkRoot "scripts/Apply-ScopedChangeSet.ps1") `
        -PlanPath ([string]$planResult.changeSetPath) `
        -Config $projectConfig `
        -RepositoryRoot $repositoryRoot `
        -RunRoot $runRoot `
        -RunId $runId `
        -StageId "bootstrap-apply"
    Write-QaFoundryLog -Message (
        "Applied $(@($apply.actions | Where-Object status -eq 'executed').Count) action(s), " +
        "dry run: $([bool]$apply.dryRun).")

    $qualityPath = ""
    if (-not [bool]$apply.dryRun -and @($apply.actions | Where-Object status -eq "executed").Count -gt 0) {
        $qualityPath = Join-Path $runRoot "quality-evidence.json"
        $null = & (Join-Path $frameworkRoot "scripts/collectors/Collect-QualityEvidence.ps1") `
            -RunId $runId -Config $projectConfig -Policy $policy `
            -DeferExecution:(Test-QaFoundryDeferredVerification -Config $projectConfig) `
            -RepositoryRoot $repositoryRoot -OutputPath $qualityPath `
            -AnalysisRunRoot $(if ($analysisRun) { [string]$analysisRun.runRoot } else { '' }) `
            -AnalysisChangeSetPath $analysisChangeSetPath `
            -InstallationChangeSetPath ([string]$planResult.changeSetPath)
        $null = & (Join-Path $frameworkRoot "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $qualityPath `
            -SchemaPath (Join-Path $frameworkRoot "schemas/runtime/quality-evidence.schema.json") `
            -SchemaRoot (Join-Path $frameworkRoot "schemas")
    }
    Write-QaFoundryLog -Level step -Message "Publishing the branch and pull request to the configured provider."
    try {
        $delivery = & (Join-Path $frameworkRoot "scripts/writers/Publish-RepositoryDelivery.ps1") `
            -Config $projectConfig -RepositoryRoot $repositoryRoot -RunRoot $runRoot `
            -RunId $runId -StageId "bootstrap-delivery" `
            -ChangeSetPath ([string]$planResult.changeSetPath) `
            -ActionEnvironment $actionEnvironment
    }
    catch {
        $analysisId = if ($analysisRun) { [string]$analysisRun.runId } else { "none" }
        throw (
            "Bootstrap delivery failed for wrapper run '$runId' and analysis run " +
            "'$analysisId'. Delivery discovers the stable branch and pull request from " +
            "Azure DevOps; local Git state may survive on self-hosted agents. Continue " +
            "with the saved analysis after resolving the error. Original error: $($_.Exception.Message)"
        )
    }

    # A YAML file in a repository is not a pipeline. Registering only after the
    # plan is merged would demand a second bootstrap run, and the point of this
    # one is to be the last: from here the work happens in the pipelines. They
    # are pointed at the branch this pull request targets, which is exactly where
    # the files land the moment it is merged.
    $currentBranch = [string]$CurrentRef -replace "^refs/heads/", ""
    $pipelinePlan = @()
    if (Test-Path -LiteralPath ([string]$planResult.planPath) -PathType Leaf) {
        $pipelinePlan = @((Get-Content -LiteralPath ([string]$planResult.planPath) -Raw |
            ConvertFrom-Json -Depth 100).pipelines)
    }
    $registeredPipelines = @()
    if ($isGitHub) {
        $registeredPipelines = @($pipelinePlan | ForEach-Object {
            [pscustomobject]@{key=$_.key;name=$_.name;yamlPath=$_.yamlPath;status='awaiting_merge';provider='github';defaultBranch=$bootstrapConfig.target.branch}
        })
    }
    if ($pipelinePlan.Count -gt 0 -and -not $isGitHub) {
        Write-QaFoundryLog -Level step -Message (
            "Registering $($pipelinePlan.Count) pipeline(s) in Azure DevOps against '$currentBranch'.")
        try {
            $registeredPipelines = @(
                & (Join-Path $frameworkRoot "scripts/writers/Register-AdoPipelines.ps1") `
                    -AzureDevOpsConfig $bootstrapConfig.azure_devops `
                    -Pipelines $pipelinePlan `
                    -TargetBranch $currentBranch `
                    -ActionEnvironment $actionEnvironment)
        }
        catch {
            throw (
                "The branch and pull request were published, but registering the pipelines in " +
                "Azure DevOps failed, so the installed YAML files would sit inert behind a pull " +
                "request that looks complete. Registration is idempotent: fix the cause and run " +
                "this bootstrap again rather than merging as it stands. Original error: " +
                $_.Exception.Message
            )
        }
        foreach ($entry in $registeredPipelines) {
            Write-QaFoundryLog -Message (
                "  - $([string]$entry.name): $([string]$entry.status) " +
                "(id $([string]$entry.pipelineId), default branch $([string]$entry.defaultBranch))")
        }
    }

    $status = if ([bool]$apply.dryRun) {
        "dry_run"
    }
    elseif (@($delivery.actions | Where-Object { $_.type -eq "pull-request.draft" -and $_.status -eq "executed" }).Count -gt 0) {
        "pull_request_created"
    }
    else {
        "plan_applied"
    }
    return Complete-BootstrapRun -Result ([pscustomobject][ordered]@{
        runId = $runId
        phase = "plan"
        status = $status
        currentRef = $CurrentRef
        targetRef = $targetRef
        runRoot = $runRoot
        validation = $validation
        analysisRunId = if ($analysisRun) { [string]$analysisRun.runId } else { "" }
        installationId = [string]$planResult.installationId
        planPath = [string]$planResult.planPath
        changeSetPath = [string]$planResult.changeSetPath
        qualityPath = $qualityPath
        apply = $apply
        delivery = $delivery
        pipelines = $registeredPipelines
    })
}

if ($resolvedPhase -notin @("Finalize", "Repair")) {
    throw "Unsupported resolved bootstrap phase: $resolvedPhase"
}
if ($CurrentRef -ne $targetRef) {
    throw "Bootstrap finalization is allowed only on '$targetRef'; current ref is '$CurrentRef'."
}
if (-not (Test-Path -LiteralPath $committedPlanPath -PathType Leaf)) {
    throw "Merged installation plan does not exist: $committedPlanPath"
}
$plan = Get-Content -LiteralPath $committedPlanPath -Raw |
    ConvertFrom-Json -Depth 100 -ErrorAction Stop
$null = & (Join-Path $frameworkRoot "scripts/Validate-JsonArtifact.ps1") `
    -ArtifactPath $committedPlanPath `
    -SchemaPath (Join-Path $frameworkRoot "schemas/bootstrap/installation-plan.schema.json") `
    -SchemaRoot (Join-Path $frameworkRoot "schemas")
if ([string]$plan.targetBranch -ne [string]$bootstrapConfig.target.branch) {
    throw "Installation plan target branch differs from the bootstrap configuration."
}
if ([string]$plan.configurationHash -ne $configurationHash) {
    throw "Bootstrap configuration changed after planning; create and review a new installation plan."
}
foreach ($file in @($plan.managedFiles)) {
    $path = Resolve-RepositoryRelativePath -Path ([string]$file.path)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Managed installation file is missing: $([string]$file.path)"
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne [string]$file.sha256) {
        throw "Managed installation file failed SHA-256 verification: $([string]$file.path)"
    }
}
if ($isGitHub) {
    return Complete-BootstrapRun -Result ([pscustomobject]@{
        runId=$runId; phase=$resolvedPhase.ToLowerInvariant(); status=$(if ($Demo) {'dry_run'} else {'installed'})
        runRoot=$runRoot; installationId=$plan.installationId; pipelines=@($plan.pipelines)
        message='Reviewed workflow files are present on the target branch and their hashes match. GitHub needs no pipeline registration.'
    })
}
$actionEnvironment = @{}
$secretName = [string]$bootstrapConfig.azure_devops.auth_env
$secretValue = [Environment]::GetEnvironmentVariable($secretName)
if (-not [string]::IsNullOrWhiteSpace($secretValue)) {
    $actionEnvironment[$secretName] = $secretValue
}
$registered = @(& (Join-Path $frameworkRoot "scripts/writers/Register-AdoPipelines.ps1") `
    -AzureDevOpsConfig $bootstrapConfig.azure_devops `
    -Pipelines @($plan.pipelines) `
    -TargetBranch ([string]$bootstrapConfig.target.branch) `
    -ActionEnvironment $actionEnvironment)
$planRaw = Get-Content -LiteralPath $committedPlanPath -Raw
$planHashAlgorithm = [Security.Cryptography.SHA256]::Create()
try {
    $planHash = ([Convert]::ToHexString($planHashAlgorithm.ComputeHash(
        [Text.Encoding]::UTF8.GetBytes($planRaw)
    ))).ToLowerInvariant()
}
finally {
    $planHashAlgorithm.Dispose()
}
$commitSha = [string][Environment]::GetEnvironmentVariable("BUILD_SOURCEVERSION")
if ([string]::IsNullOrWhiteSpace($commitSha)) {
    $commitSha = [string](& git -C $repositoryRoot rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) { $commitSha = "" }
}
$state = [pscustomobject][ordered]@{
    schemaVersion = 1
    installationId = [string]$plan.installationId
    status = if ([bool]$bootstrapConfig.azure_devops.dry_run) { "dry_run" } else { "installed" }
    updatedAt = [DateTime]::UtcNow.ToString("o")
    targetBranch = [string]$bootstrapConfig.target.branch
    planHash = $planHash
    configurationHash = $configurationHash
    commitSha = $commitSha.Trim()
    pipelines = @($registered)
    evidence = @($committedPlanPath) + @($plan.managedFiles | ForEach-Object { [string]$_.path })
}
$statePath = Join-Path $runRoot "installation-state.json"
$state | ConvertTo-Json -Depth 100 |
    Set-Content -LiteralPath $statePath -Encoding utf8
$null = & (Join-Path $frameworkRoot "scripts/Validate-JsonArtifact.ps1") `
    -ArtifactPath $statePath `
    -SchemaPath (Join-Path $frameworkRoot "schemas/bootstrap/installation-state.schema.json") `
    -SchemaRoot (Join-Path $frameworkRoot "schemas")
return Complete-BootstrapRun -Result ([pscustomobject][ordered]@{
    runId = $runId
    phase = $resolvedPhase.ToLowerInvariant()
    status = [string]$state.status
    currentRef = $CurrentRef
    targetRef = $targetRef
    runRoot = $runRoot
    installationId = [string]$state.installationId
    statePath = $statePath
    pipelines = @($registered)
})
