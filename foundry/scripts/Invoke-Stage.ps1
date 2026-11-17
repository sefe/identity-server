[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$Stage,
    [AllowNull()][object]$Workflow = $null,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][object]$Policy,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$RunId,
    [int]$Iteration = 1,
    [hashtable]$ProviderEnvironment = @{},
    [hashtable]$ActionEnvironment = @{},
    [AllowNull()][object]$Deadline = $null,
    [switch]$ReuseExistingArtifacts
)

. (Join-Path $PSScriptRoot "Common.ps1")
. (Join-Path $PSScriptRoot 'DependencyEvolution.ps1')
. (Join-Path $PSScriptRoot 'GenerationRepair.ps1')
. (Join-Path $PSScriptRoot 'RecoveryReuse.ps1')
. (Join-Path $PSScriptRoot 'BlueprintRevisionContext.ps1')
$root = Get-QaFoundryRoot
$stageId = [string]$Stage.id
$artifactDirectory = if ($Stage.PSObject.Properties.Name -contains "artifact_directory") {
    [string]$Stage.artifact_directory
}
else {
    $stageId
}
$baseStageDirectory = Join-Path $RunRoot $artifactDirectory
$stageDirectory = if ($Iteration -eq 1) {
    $baseStageDirectory
}
else {
    Join-Path $baseStageDirectory "iteration-$Iteration"
}
New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null

# What a stage actually produced, and where. A later stage that needs the
# blueprint this run approved cannot find it by searching the run directory: a
# critic loop leaves one file per iteration, and the newest is not the approved
# one. So each stage records its own outputs and the run state carries them.
$publishedArtifacts = [System.Collections.Generic.List[object]]::new()
$actionFailureKind = ''
$script:StageContextExclusions = @()

function Add-StageArtifact {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $relative = Get-QaFoundryRunRelativePath -RunRoot $RunRoot -Path $Path
    $name = Split-Path $relative -Leaf
    $record = [pscustomobject][ordered]@{
        name = $name
        relativePath = $relative
        sha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $sameName = @($publishedArtifacts | Where-Object { [string]$_.name -ceq $name })
    if ($sameName.Count -gt 0) {
        if (@($sameName | Where-Object { [string]$_.relativePath -ceq $relative }).Count -gt 0) {
            $publishedArtifacts.Remove(@($sameName | Where-Object { [string]$_.relativePath -ceq $relative })[0]) |
                Out-Null
            $publishedArtifacts.Add($record)
            return
        }
        # Two files with one name is how a later stage ends up resolving the
        # wrong one. A stage that produces the same name twice has to say which
        # copy it stands behind rather than leaving the choice to whoever reads.
        throw ("Stage '$stageId' published '$name' twice, from '$([string]$sameName[0].relativePath)' " +
            "and '$relative'. A stage may record only one artifact per name.")
    }
    $publishedArtifacts.Add($record)
}

# What a recorded execution result is evidence about. Reusing a result across
# relay legs is only honest if the plan it answers is the plan this leg holds,
# so the signature covers every field that changes what a command does: not
# just the executable and its arguments, but where it runs and what it runs
# with. Two plans that differ in any of those are different plans.
function Get-ExecutionPlanSignature {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Commands)

    $canonical = @($Commands | ForEach-Object {
        $command = $_
        $environment = [ordered]@{}
        if (($command.PSObject.Properties.Name -contains "environment") -and
            $null -ne $command.environment) {
            # Member enumeration over an empty property set throws under strict
            # mode, and a command with no environment is the common case.
            foreach ($property in @(
                $command.environment.PSObject.Properties | Sort-Object -Property Name -CaseSensitive
            )) {
                $environment[[string]$property.Name] = [string]$property.Value
            }
        }
        [ordered]@{
            id = [string]$command.id
            executable = [string]$command.executable
            arguments = @($command.arguments | ForEach-Object { [string]$_ })
            workingDirectory = ([string]$command.workingDirectory) -replace "\\", "/"
            environment = $environment
        }
    })
    $json = ConvertTo-Json -InputObject @($canonical) -Depth 100 -Compress
    $stream = [System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($json))
    try {
        return (Get-FileHash -InputStream $stream -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
    }
}

# What this stage was given by identity rather than found by searching. A review
# that follows a revision must judge the document this run carried forward, not
# whichever same-named file happens to be newest on disk.
$declaredStageInputs = @()
if (($Stage.PSObject.Properties.Name -contains "inputs") -and $null -ne $Stage.inputs) {
    $resolvedStageInputs = Resolve-QaFoundryDeclaredInputs `
        -RunRoot $RunRoot -StageId $stageId -Inputs $Stage.inputs -RunId $RunId
    foreach ($key in @($resolvedStageInputs.Keys)) {
        $declaredStageInputs += $resolvedStageInputs[$key]
    }
}

function Assert-AgentBudget {
    param(
        [Parameter(Mandatory)][string[]]$OutputPaths,
        [Parameter(Mandatory)][string]$Description
    )
    # Work already on disk costs nothing to replay, so only a call that would
    # really reach the model has to respect either budget.
    if ($ReuseExistingArtifacts -and -not (@($OutputPaths | Where-Object { -not (Test-Path $_) }))) { return }
    if ($null -ne $Deadline -and (Test-QaFoundryBudgetExhausted -Deadline $Deadline)) {
        Stop-QaFoundryForBudget -Reason (
            "stage '$stageId' stopped before $Description because the time budget for this leg is spent")
    }
    # The clock belongs to this leg; the bill belongs to the whole run, and is
    # read back from the ledger every call has written since the run began.
    $overspend = Test-QaFoundryRunBudgetExhausted -RunRoot $RunRoot -Config $Config
    if ($null -ne $overspend) {
        Stop-QaFoundryForRunBudget -Reason (
            "stage '$stageId' stopped before $Description because the run has spent $overspend")
    }
}

function Get-ContextArtifacts {
    # Some artifacts are carried by reference rather than by value. A resolved
    # lock file is tens of thousands of lines that a person did not write and a
    # reviewer cannot meaningfully read; a deterministic stage has already
    # checked it against the approved profile, and a review subject states what
    # it is. Naming such a file here keeps it out of every request in the stage
    # without hiding that it exists.
    $excluded = @("workflow-state.json")
    # A batched stage writes its own intermediate artifacts into this same run.
    # Left in the context they would be resent to every later call in the stage,
    # which is exactly the growth the batching exists to avoid.
    $excluded += @($script:StageContextExclusions)
    # A resumed or repeated iteration leaves batch artifacts behind under names
    # this iteration no longer produces: a split into four batches does not
    # name change-set-batch-05, so the five to eight the previous iteration
    # wrote would be swept back into every request. The whole family is
    # excluded by shape, and the batches a call genuinely depends on are handed
    # to it by path instead.
    $excludedPatterns = @("change-set-batch-*.json", "assignment-batch-*.json",
        "carried-batch-*.json", "repair-source-batch-*.json", "*.repair.applied.json", "*.revision-input.json", "command-*.log",
        # What a call cost is a fact about the run, not evidence about the
        # product. Swept into the context it would be read back by every later
        # agent, and the ledger that exists to measure prompt growth would become
        # a cause of it.
        "*.provider-metadata.json",
        # The same, one step earlier: a provider that can count tokens leaves
        # them in a sidecar beside its request, which the runtime reads into the
        # record above and then deletes. An interrupted run can leave one behind,
        # and a stray accounting file is not evidence about the product either.
        "*.usage.json",
        # Whether an agent covered everything it was asked to is a fact about
        # that call, written beside its artifact so a resumed run can check the
        # artifact is complete before accepting it. It says nothing about the
        # product, and every stage after it would otherwise carry the record of
        # what every earlier stage deferred - growth caused by the very
        # mechanism that exists to stop work being quietly dropped.
        "*.coverage.json")
    if (($Stage.PSObject.Properties.Name -contains "context") -and
        ($Stage.context.PSObject.Properties.Name -contains "exclude")) {
        $excluded += @($Stage.context.exclude | ForEach-Object { [string]$_ })
    }
    # A declared input is supplied by identity, not by name. Every other file
    # sharing its name is a superseded draft, and leaving those in the context
    # is how a reviewer ends up judging the wrong revision.
    $excluded += @($declaredStageInputs | ForEach-Object { [string]$_.name })
    # Context is the collected snapshot plus the artifacts carried in state.
    # Recursively sweeping the run also included rejected drafts and recovery archives.
    $candidates = [System.Collections.Generic.List[string]]::new()
    $contextRoot = Join-Path $RunRoot 'context'
    if (Test-Path -LiteralPath $contextRoot) {
        foreach ($file in Get-ChildItem -LiteralPath $contextRoot -File -Filter '*.json') {
            if ($file.Name -in @('toolchain-lock.json', 'toolchain-current.json')) { continue }
            $candidates.Add($file.FullName)
        }
    }
    $activeToolchain = Get-QaFoundryActiveToolchainPath -RunRoot $RunRoot
    if (Test-Path -LiteralPath $activeToolchain) { $candidates.Add($activeToolchain) }
    $dependencyReasons = Join-Path (Split-Path $activeToolchain -Parent) 'requests.json'
    if (Test-Path -LiteralPath $dependencyReasons) { $candidates.Add($dependencyReasons) }
    $workflowStatePath = Join-Path $RunRoot 'workflow-state.json'
    if (Test-Path -LiteralPath $workflowStatePath) {
        $contextState = Get-Content -LiteralPath $workflowStatePath -Raw | ConvertFrom-Json -Depth 100
        foreach ($entry in @($contextState.stages)) {
            $attempts = @($entry.attempts | Where-Object {
                $_.status -in @('completed', 'approved', 'approved_with_dissent', 'revision_required', 'blocked')
            })
            if ($attempts.Count -eq 0) { continue }
            foreach ($artifact in @($attempts[-1].artifacts)) {
                $path = Join-Path $RunRoot ([string]$artifact.relativePath)
                if ([string]$artifact.name -eq 'toolchain-lock.json' -and $path -ne $activeToolchain) { continue }
                if (-not (Test-PathWithinRoot -Candidate $path -Root $RunRoot)) { throw 'Context artifact escapes its run.' }
                if (Test-Path -LiteralPath $path -PathType Leaf) { $candidates.Add($path) }
            }
        }
    }
    foreach ($artifact in @($publishedArtifacts)) { $candidates.Add((Join-Path $RunRoot $artifact.relativePath)) }
    if ($Iteration -eq 1 -and $Stage.PSObject.Properties['agents']) {
        foreach ($agent in @($Stage.agents)) {
            $previous = Get-PreviousIterationArtifact -Agent $agent
            if ($previous) { $candidates.Add($previous) }
        }
    }
    $discovered = @($candidates | Select-Object -Unique | ForEach-Object { Get-Item -LiteralPath $_ } |
        Where-Object {
            if ($_.Name -in $excluded) { return $false }
            foreach ($pattern in $excludedPatterns) {
                if ($_.Name -like $pattern) { return $false }
            }
            return $true
        } |
        Sort-Object FullName |
        Select-Object -ExpandProperty FullName)
    return @($discovered + @($declaredStageInputs | ForEach-Object { [string]$_.path }))
}

function Get-AgentArtifactBudget {
    param([Parameter(Mandatory)][object]$Agent)
    if ($Agent.PSObject.Properties.Name -contains "max_artifact_bytes") {
        return [int]$Agent.max_artifact_bytes
    }
    return 0
}

# Configuration says every automation project must document why its stack was
# chosen; the workflow says which agent is the one that has to plan that file.
# Several agents in a run emit an inventory, and only the one that lays the
# foundation is in a position to satisfy it.
function Get-AgentRationaleEnforcement {
    param([Parameter(Mandatory)][object]$Agent)
    if ($Agent.PSObject.Properties.Name -contains "enforce_project_rationale") {
        return [bool]$Agent.enforce_project_rationale
    }
    return $false
}

# Which agent in this stage owns the files this one may only depend on. Declared
# rather than inferred, and resolved to the artifact the owner writes, because
# an agent that defers has to be able to read what it is deferring to. A stage
# runs its agents in order, so the owner has already answered by then.
function Get-AgentPlannedFileOwner {
    param([Parameter(Mandatory)][object]$Agent)
    if ($Agent.PSObject.Properties.Name -notcontains "defers_planned_files_to") {
        return $null
    }
    $ownerId = ([string]$Agent.defers_planned_files_to).Trim()
    if ($ownerId -eq "") { return $null }
    foreach ($candidate in @($Stage.agents)) {
        if ($null -eq $candidate -or [string]$candidate.id -ne $ownerId) { continue }
        return [pscustomobject]@{
            agentId = $ownerId
            artifactPath = (Join-Path $stageDirectory ([string]$candidate.output))
        }
    }
    throw ("Agent '$([string]$Agent.id)' defers its planned files to '$ownerId', which is not " +
        "an agent of stage '$stageId'. The owner has to be in the same stage, and ahead of it, " +
        "or there is nothing to defer to.")
}

function New-AgentConfig {
    param([int]$ProfileOrdinal = 0)

    $agentConfig = Copy-QaFoundryConfig -Config $Config
    if (@(Get-QaFoundryCollaborationProfileNames -Config $agentConfig).Count -eq 0) {
        return $agentConfig
    }
    $profileName = Select-QaFoundryAgentProfileName `
        -Config $agentConfig `
        -RunId $RunId `
        -StageId $stageId `
        -StageIteration $Iteration `
        -AgentOrdinal $ProfileOrdinal
    $profile = & (Join-Path $PSScriptRoot "Resolve-AiProfile.ps1") `
        -Config $agentConfig `
        -ProfileName $profileName
    return (Set-QaFoundryResolvedAiProfile -Config $agentConfig -Profile $profile)
}

function Get-AgentProviderEnvironment {
    param([Parameter(Mandatory)][object]$AgentConfig)

    if ($AgentConfig.ai.PSObject.Properties.Name -notcontains "resolved_secret_env") {
        return $ProviderEnvironment
    }
    $filtered = @{}
    foreach ($name in @($AgentConfig.ai.resolved_secret_env)) {
        $key = [string]$name
        if ($ProviderEnvironment.ContainsKey($key)) {
            $filtered[$key] = [string]$ProviderEnvironment[$key]
        }
    }
    return $filtered
}

function Get-PreviousIterationArtifact {
    # A revision is a change to what the previous iteration produced, so the agent
    # is allowed to name the parts it is leaving alone instead of restating them.
    param([Parameter(Mandatory)][object]$Agent)
    if ($Agent.PSObject.Properties.Name -notcontains "output") { return "" }
    if ($Iteration -le 1) {
        $saved = Get-QaFoundryRecoveryArtifact -RunRoot $RunRoot -RunId $RunId `
            -StageId $stageId -Name ([string]$Agent.output)
        if ($null -ne $saved) {
            $document = Get-Content $saved.path -Raw | ConvertFrom-Json -Depth 100
            if ($document.PSObject.Properties['plannedFiles']) { return $saved.path }
        }
        return ''
    }
    $previousDirectory = if ($Iteration -le 2) {
        $baseStageDirectory
    }
    else {
        Join-Path $baseStageDirectory "iteration-$($Iteration - 1)"
    }
    $candidate = Join-Path $previousDirectory ([string]$Agent.output)
    if (Test-Path -LiteralPath $candidate) { return $candidate }
    return ""
}

# Decides whether the rejection this stage is repeating for can be repaired
# file by file, and returns nothing at all when it cannot. Returning nothing is
# the safe answer: the caller then regenerates the whole approved inventory,
# which is what every run did before this existed.
function Get-TargetedRepair {
    param(
        [Parameter(Mandatory)][string]$BaseStageDirectory,
        [Parameter(Mandatory)][string]$PlanName,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$InventoryBasis,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ApprovedPaths
    )

    # Preserve batch identities when continuing an iteration started by an older runtime.
    # Turning a full split into a targeted split here would reuse other files' batch outputs.
    if (@(Get-ChildItem -LiteralPath $stageDirectory -Filter 'assignment-batch-*.json' -File).Count -gt 0 -and
        -not (Test-Path -LiteralPath (Join-Path $stageDirectory 'repair-instructions.json'))) { return $null }
    $previousIteration = $Iteration - 1
    $previousDirectory = if ($previousIteration -le 1) {
        $BaseStageDirectory
    }
    else {
        Join-Path $BaseStageDirectory "iteration-$previousIteration"
    }
    $planPath = Join-Path $previousDirectory $PlanName
    $basisPath = Join-Path $previousDirectory 'batch-basis.json'
    if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) {
        # A failed repair has no merged plan. The last completed generation is
        # still the source that was materialized and verified; counters need
        # not be adjacent after recovery or an interrupted repair.
        $recordedBase = Get-QaFoundryRecordedGenerationBase -RunRoot $RunRoot -RunId $RunId `
            -StageId $stageId -PlanName $PlanName -BeforeIteration $Iteration
        if ($null -eq $recordedBase) { return $null }
        $planPath = $recordedBase.planPath
        $basisPath = $recordedBase.basisPath
        $previousIteration = $recordedBase.iteration
        Write-QaFoundryLog -Indent 2 -Message "Repair resumes from completed generation $previousIteration; the intervening attempt produced no merged plan."
    }
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 100
    if ([string]$plan.status -ne "completed") { return $null }

    # The rejected plan has to have been built from the same inventory this
    # iteration is batching. A critic loop that revised the inventory in between
    # makes every carried file a file nobody approved.
    if (-not (Test-Path -LiteralPath $basisPath -PathType Leaf)) { return $null }
    $basis = Get-Content -LiteralPath $basisPath -Raw | ConvertFrom-Json -Depth 40
    $previousBasis = @(@($basis.inventories) | ForEach-Object { "$($_.path)=$($_.sha256)" }) -join "|"
    $currentBasis = @(@($InventoryBasis) | ForEach-Object { "$($_.path)=$($_.sha256)" }) -join "|"
    if ($previousBasis -cne $currentBasis) {
        Write-QaFoundryLog -Level warn -Indent 2 -Message (
            "The approved inventory changed since the plan under review was generated, so every " +
            "file is regenerated rather than carried forward.")
        return $null
    }

    # The plan has to already account for the whole inventory, or the files it
    # would carry forward are not the files the reviewers read.
    $planPaths = @(@($plan.changes) | ForEach-Object {
        ([string]$_.path).Replace("\", "/").Trim()
    } | Where-Object { $_ })
    if (@($ApprovedPaths | Where-Object { $planPaths -notcontains $_ }).Count -gt 0) { return $null }

    $reviewStage = ""
    if (($Stage.PSObject.Properties.Name -contains "assurance") -and $null -ne $Stage.assurance -and
        ($Stage.assurance.PSObject.Properties.Name -contains "reviewed_by")) {
        $reviewStage = [string]$Stage.assurance.reviewed_by
    }
    if (-not $reviewStage) { return $null }
    $reviewDirectory = if ($previousIteration -le 1) {
        Join-Path $RunRoot $reviewStage
    }
    else {
        Join-Path (Join-Path $RunRoot $reviewStage) "iteration-$previousIteration"
    }
    $rejections = @(
        foreach ($file in @(if (Test-Path -LiteralPath $reviewDirectory -PathType Container) {
            Get-ChildItem -LiteralPath $reviewDirectory -Filter "*.json" -File
        })) {
            $document = try {
                Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 100
            }
            catch { continue }
            $names = @(Get-QaFoundryPropertyNames -InputObject $document)
            if ($names -notcontains "decision") { continue }
            if ([string]$document.decision -ne "revision_required") { continue }
            $document
        }
    )
    if ($rejections.Count -eq 0) {
        $verificationRepair = Get-QaFoundryVerificationRepair -RunRoot $RunRoot -RunId $RunId `
            -Iteration $previousIteration -Plan $plan -ApprovedPaths $ApprovedPaths
        if ($null -ne $verificationRepair) { $rejections = @($verificationRepair) }
    }
    if ($rejections.Count -eq 0) { return $null }

    $paths = [System.Collections.Generic.List[string]]::new()
    $instructions = [System.Collections.Generic.List[object]]::new()
    foreach ($rejection in $rejections) {
        $names = @(Get-QaFoundryPropertyNames -InputObject $rejection)
        # A reviewer that did not state a scope is treated as asking for
        # everything. Guessing on its behalf would carry forward a file it may
        # well have meant to reject.
        if ($names -notcontains "repairScope") { return $null }
        if ([string]$rejection.repairScope -ne "targeted") { return $null }
        if ($names -notcontains "repairTargets") { return $null }
        foreach ($target in @($rejection.repairTargets)) {
            $targetPaths = @(@($target.paths) | ForEach-Object {
                ([string]$_).Replace("\", "/").Trim()
            } | Where-Object { $_ })
            if ($targetPaths.Count -eq 0) { return $null }
            foreach ($targetPath in $targetPaths) {
                if ($ApprovedPaths -notcontains $targetPath) {
                    Write-QaFoundryLog -Level warn -Indent 2 -Message (
                        "$([string]$rejection.agentId) asked for a repair of '$targetPath', which " +
                        "is not an approved path, so the whole inventory is regenerated instead.")
                    return $null
                }
                if (-not $paths.Contains($targetPath)) { $paths.Add($targetPath) }
            }
            $instructions.Add([ordered]@{
                reviewer = [string]$rejection.agentId
                paths = @($targetPaths)
                instruction = [string]$target.instruction
            })
        }
    }
    if ($paths.Count -eq 0) { return $null }
    # A repair that covers everything is a full regeneration wearing a smaller
    # name, and the carry-forward machinery would only add risk to it.
    if (@($ApprovedPaths | Where-Object { $paths -notcontains $_ }).Count -eq 0) { return $null }

    return [pscustomobject]@{
        planPath = $planPath
        paths = @($paths | Sort-Object)
        instructions = @($instructions)
    }
}

function Invoke-ConfiguredAgentsParallel {
    param(
        [Parameter(Mandatory)][object[]]$Agents,
        [string[]]$AdditionalContext = @(),
        [int]$ProfileOrdinalOffset = 0,
        # Batches share a role but not an assignment: each one is told which
        # files it owns and which earlier batches wrote the files it builds on.
        # A single shared context would hand every batch every assignment and
        # ask each of them to write the whole framework.
        [hashtable]$AdditionalContextByAgentId = @{},
        # A resumed leg recomputes the split and must land on the same model
        # for the same batch, or a rejected attempt is retried against a
        # profile that never saw the feedback.
        [hashtable]$ProfileOrdinalByAgentId = @{}
    )
    if ($Agents.Count -eq 0) { return @() }
    $batchOutputs = @($Agents | ForEach-Object { Join-Path $stageDirectory ([string]$_.output) })
    Assert-AgentBudget -OutputPaths $batchOutputs -Description (
        "starting " + $Agents.Count + " parallel agent(s)")
    $baseContexts = @(Get-ContextArtifacts)
    if ([string]$Stage.type -eq 'batched_agent') {
        # The approved assignment, repair source and direct dependencies are
        # supplied per agent below. Replaying every review and the entire old
        # change set makes a two-file repair re-analyse the whole deliverable.
        $contextRoot = Join-Path $RunRoot 'context'
        $activeLock = Get-QaFoundryActiveToolchainPath -RunRoot $RunRoot
        $dependencyRequests = Join-Path (Split-Path $activeLock -Parent) 'requests.json'
        $baseContexts = @($baseContexts | Where-Object {
            (Test-PathWithinRoot -Candidate $_ -Root $contextRoot) -or $_ -eq $activeLock -or $_ -eq $dependencyRequests
        })
    }
    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(
        1,
        [Math]::Max(1, $Agents.Count)
    )
    $jobs = [System.Collections.Generic.List[object]]::new()
    try {
        $pool.Open()
        for ($agentIndex = 0; $agentIndex -lt $Agents.Count; $agentIndex++) {
            $agent = $Agents[$agentIndex]
            $agentId = if ($agent.PSObject.Properties.Name -contains "id") {
                [string]$agent.id
            } else { [string]$agent.agent }
            $profileOrdinal = if ($ProfileOrdinalByAgentId.ContainsKey($agentId)) {
                [int]$ProfileOrdinalByAgentId[$agentId]
            }
            else { $ProfileOrdinalOffset + $agentIndex }
            # An empty branch of an if-expression yields $null rather than an
            # empty array under StrictMode, and a $null here reaches the agent
            # as an unbound path list. The collection wrapper goes outside.
            $agentContext = @(if ($AdditionalContextByAgentId.ContainsKey($agentId)) {
                $AdditionalContextByAgentId[$agentId]
            }
            else { $AdditionalContext })
            $agentConfig = New-AgentConfig -ProfileOrdinal $profileOrdinal
            $agentProviderEnvironment = Get-AgentProviderEnvironment -AgentConfig $agentConfig
            $outputPath = Join-Path $stageDirectory ([string]$agent.output)
            $promptPath = Resolve-QaFoundryPath -Root $root -Path ([string]$agent.prompt)
            $schemaPath = Resolve-QaFoundryPath -Root $root -Path ([string]$agent.schema)
            $powerShell = [PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            $null = $powerShell.AddCommand((Join-Path $PSScriptRoot "Invoke-Agent.ps1"))
            $null = $powerShell.AddParameter("AgentId", $agentId)
            $null = $powerShell.AddParameter("StageId", $stageId)
            $null = $powerShell.AddParameter("RunId", $RunId)
            $null = $powerShell.AddParameter("PromptPath", $promptPath)
            $null = $powerShell.AddParameter("ContextPaths", [string[]]$baseContexts)
            $null = $powerShell.AddParameter("PriorityContextPaths", [string[]]$agentContext)
            $null = $powerShell.AddParameter("OutputPath", $outputPath)
            $null = $powerShell.AddParameter("SchemaPath", $schemaPath)
            $null = $powerShell.AddParameter("Config", $agentConfig)
            $agentPolicy = $null
            if ($null -ne $Policy) { $agentPolicy = Copy-QaFoundryConfig -Config $Policy }
            $null = $powerShell.AddParameter("Policy", $agentPolicy)
            $null = $powerShell.AddParameter("StageIteration", $Iteration)
            $null = $powerShell.AddParameter("MaxArtifactBytes", (Get-AgentArtifactBudget -Agent $agent))
            $null = $powerShell.AddParameter("ProviderEnvironment", $agentProviderEnvironment)
            $null = $powerShell.AddParameter("RepositoryRoot", $RepositoryRoot)
            $null = $powerShell.AddParameter("PreviousArtifactPath", (Get-PreviousIterationArtifact -Agent $agent))
            $null = $powerShell.AddParameter("Deadline", $Deadline)
            $null = $powerShell.AddParameter("EnforceProjectRationale",
                (Get-AgentRationaleEnforcement -Agent $agent))
            $plannedFileOwner = Get-AgentPlannedFileOwner -Agent $agent
            $null = $powerShell.AddParameter("PlannedFileOwnerArtifactPath",
                $(if ($null -ne $plannedFileOwner) { [string]$plannedFileOwner.artifactPath } else { "" }))
            $null = $powerShell.AddParameter("PlannedFileOwnerAgentId",
                $(if ($null -ne $plannedFileOwner) { [string]$plannedFileOwner.agentId } else { "" }))
            $null = $powerShell.AddParameter("ToolchainLockPath",
                (Get-QaFoundryActiveToolchainPath -RunRoot $RunRoot))
            $null = $powerShell.AddParameter("AllowExistingArtifact", [bool]$ReuseExistingArtifacts)
            $jobs.Add([pscustomobject]@{
                agentId = $agentId
                profileName = if (
                    $agentConfig.ai.PSObject.Properties.Name -contains "resolved_profile"
                ) {
                    [string]$agentConfig.ai.resolved_profile
                }
                else { [string]$agentConfig.ai.active_profile }
                outputPath = $outputPath
                powerShell = $powerShell
                informationIndex = 0
                async = $powerShell.BeginInvoke()
            })
        }
        Write-QaFoundryLog -Level step -Indent 1 -Message (
            "Started $($jobs.Count) agent(s) in parallel: " +
            (@($jobs | ForEach-Object {
                "$($_.agentId)[$($_.profileName)]"
            }) -join ", ") + ".")

        # Runspaces buffer their host output instead of writing to the console,
        # so drain each agent's information stream while the batch is running.
        $pending = [System.Collections.Generic.List[object]]::new()
        foreach ($job in $jobs) { $pending.Add($job) }
        while ($pending.Count -gt 0) {
            for ($pendingIndex = $pending.Count - 1; $pendingIndex -ge 0; $pendingIndex--) {
                $pendingJob = $pending[$pendingIndex]
                $informationStream = $pendingJob.powerShell.Streams.Information
                while ($pendingJob.informationIndex -lt $informationStream.Count) {
                    Write-Host ([string]$informationStream[$pendingJob.informationIndex].MessageData)
                    $pendingJob.informationIndex = $pendingJob.informationIndex + 1
                }
                if ($pendingJob.async.IsCompleted) {
                    $pending.RemoveAt($pendingIndex)
                }
            }
            if ($pending.Count -gt 0) { Start-Sleep -Milliseconds 250 }
        }

        $results = [System.Collections.Generic.List[object]]::new()
        foreach ($job in $jobs) {
            try {
                try {
                    $output = @($job.powerShell.EndInvoke($job.async))
                }
                catch {
                    # A budget stop is a handover signal rather than a defect, and it
                    # has to reach the workflow with its marker still leading the
                    # message or the leg crashes instead of pausing.
                    if (Test-QaFoundryBudgetStop -Message $_) {
                        throw (Get-QaFoundryBudgetStopMessage -Message $_)
                    }
                    # The run's spending limit travels the same way, for the same
                    # reason and to the opposite end: the workflow must be able to
                    # tell a run it should stop from a leg it should resume.
                    if (Test-QaFoundryRunBudgetStop -Message $_) {
                        throw (Get-QaFoundryRunBudgetStopMessage -Message $_)
                    }
                    throw
                }
                # HadErrors stays true once anything has touched the error stream, and a
                # caught, retried failure leaves that mark behind. Build 465 lost leg 1 to
                # it: architecture-critic returned an empty first answer, the retry produced
                # a schema-valid approval, and the stage was still killed afterwards by the
                # noise the recovered attempt had left, with an empty message to explain it.
                # An agent only returns a result once its artifact has passed validation, so
                # a returned result is the fact to trust; a real unhandled failure leaves no
                # result and comes out of EndInvoke instead.
                $errorRecords = @($job.powerShell.Streams.Error)
                $errorMessages = @(
                    foreach ($errorRecord in $errorRecords) {
                        $message = ([string]$errorRecord).Trim()
                        if ($message) { $message }
                    }
                )
                if ($output.Count -eq 0) {
                    foreach ($errorRecord in $errorRecords) {
                        if (Test-QaFoundryBudgetStop -Message $errorRecord) {
                            throw (Get-QaFoundryBudgetStopMessage -Message $errorRecord)
                        }
                        if (Test-QaFoundryRunBudgetStop -Message $errorRecord) {
                            throw (Get-QaFoundryRunBudgetStopMessage -Message $errorRecord)
                        }
                    }
                    $detail = if ($errorMessages.Count -gt 0) {
                        $errorMessages -join "; "
                    }
                    else {
                        "no runspace error detail was recorded"
                    }
                    throw "Parallel agent '$($job.agentId)' returned no result: $detail"
                }
                if ($errorMessages.Count -gt 0) {
                    Write-QaFoundryLog -Level warn -Indent 2 -Scope $job.agentId -Message (
                        "Returned a validated result after recoverable runspace diagnostics: " +
                        (Format-QaFoundryNarrationText -Text ($errorMessages -join "; ") -MaxLength 400))
                }
                $results.Add([pscustomobject]@{
                    agentId = $job.agentId
                    profileName = $job.profileName
                    outputPath = $job.outputPath
                    result = $output[-1]
                })
            }
            finally {
                $job.powerShell.Dispose()
            }
        }
        return @($results)
    }
    finally {
        foreach ($job in $jobs) {
            if ($null -ne $job.powerShell) { $job.powerShell.Dispose() }
        }
        $pool.Dispose()
    }
}

function Invoke-ConfiguredAgent {
    param(
        [Parameter(Mandatory)][object]$Agent,
        [string[]]$AdditionalContext = @(),
        [int]$ProfileOrdinal = 0,
        [string]$RevisionBasePath = ''
    )
    $agentId = if ($Agent.PSObject.Properties.Name -contains "id") {
        [string]$Agent.id
    }
    else {
        [string]$Agent.agent
    }
    $outputPath = Join-Path $stageDirectory ([string]$Agent.output)
    Assert-AgentBudget -OutputPaths @($outputPath) -Description "agent '$agentId'"
    $promptPath = Resolve-QaFoundryPath -Root $root -Path ([string]$Agent.prompt)
    $schemaPath = Resolve-QaFoundryPath -Root $root -Path ([string]$Agent.schema)
    $contexts = @(Get-ContextArtifacts)
    $agentConfig = New-AgentConfig -ProfileOrdinal $ProfileOrdinal
    $agentProviderEnvironment = Get-AgentProviderEnvironment -AgentConfig $agentConfig
    $plannedFileOwner = Get-AgentPlannedFileOwner -Agent $Agent
    return & (Join-Path $PSScriptRoot "Invoke-Agent.ps1") `
        -AgentId $agentId `
        -StageId $stageId `
        -RunId $RunId `
        -PromptPath $promptPath `
        -ContextPaths $contexts `
        -PriorityContextPaths ([string[]]@($AdditionalContext)) `
        -OutputPath $outputPath `
        -SchemaPath $schemaPath `
        -Config $agentConfig `
        -Policy $Policy `
        -StageIteration $Iteration `
        -MaxArtifactBytes (Get-AgentArtifactBudget -Agent $Agent) `
        -ProviderEnvironment $agentProviderEnvironment `
        -RepositoryRoot $RepositoryRoot `
        -PreviousArtifactPath (Get-PreviousIterationArtifact -Agent $Agent) `
        -RevisionBasePath $RevisionBasePath `
        -PlannedFileOwnerArtifactPath $(
            if ($null -ne $plannedFileOwner) { [string]$plannedFileOwner.artifactPath } else { "" }) `
        -PlannedFileOwnerAgentId $(
            if ($null -ne $plannedFileOwner) { [string]$plannedFileOwner.agentId } else { "" }) `
        -ToolchainLockPath (Get-QaFoundryActiveToolchainPath -RunRoot $RunRoot) `
        -Deadline $Deadline `
        -EnforceProjectRationale:(Get-AgentRationaleEnforcement -Agent $Agent) `
        -AllowExistingArtifact:$ReuseExistingArtifacts
}

$agentArtifacts = @()
$decision = $null
if ($Iteration -eq 1 -and $Stage.PSObject.Properties['agents']) {
    $recoveredInventories = @($Stage.agents | ForEach-Object { Get-PreviousIterationArtifact -Agent $_ } |
        Where-Object { $_ })
    if ($recoveredInventories.Count -gt 0) {
        $recoveryContext = New-QaFoundryRecoveryContext -RunRoot $RunRoot -RunId $RunId -RepositoryRoot $RepositoryRoot `
            -StageId $stageId -OutputPath (Join-Path $stageDirectory 'recovery-context.md')
        if ($recoveryContext) { Add-StageArtifact -Path $recoveryContext }
    }
}

switch ([string]$Stage.type) {
    "parallel_with_synthesis" {
        $parallelResults = @(Invoke-ConfiguredAgentsParallel -Agents @($Stage.agents) `
            -ProfileOrdinalOffset 0)
        foreach ($parallelResult in $parallelResults) {
            $agentArtifacts += [string]$parallelResult.outputPath
            Add-StageArtifact -Path ([string]$parallelResult.outputPath)
            if ([string]$parallelResult.result.status -in @("blocked", "failed")) {
                if ([string]$parallelResult.result.status -eq "failed") {
                    Write-QaFoundryLog -Level warn -Indent 1 -Message (
                        "An agent in this stage reports its own result as failed, so the stage " +
                        "stops rather than synthesising a document its author has disowned: " +
                        "$([string]$parallelResult.result.summary)")
                }
                return [pscustomobject]@{
                    Status = "blocked"
                    Decision = $null
                    ArtifactDirectory = $stageDirectory
                    Artifacts = @($publishedArtifacts)
                    Inputs = @()
                }
            }
        }
        $synthesisAgent = [pscustomobject]@{
            agent = [string]$Stage.synthesis.agent
            prompt = [string]$Stage.synthesis.prompt
            schema = [string]$Stage.synthesis.schema
            output = [string]$Stage.synthesis.output
        }
        $synthesis = Invoke-ConfiguredAgent `
            -Agent $synthesisAgent `
            -AdditionalContext $agentArtifacts `
            -ProfileOrdinal @($Stage.agents).Count
        Add-StageArtifact -Path (Join-Path $stageDirectory ([string]$Stage.synthesis.output))
        if ($Stage.synthesis.PSObject.Properties['result_output']) {
            if ($stageId -ne 'discovery') { throw 'Discovery composition is only supported in the discovery stage.' }
            $composedPath = Join-Path $stageDirectory ([string]$Stage.synthesis.result_output)
            $synthesis = & (Join-Path $PSScriptRoot 'actions/New-DiscoveryResult.ps1') `
                -DecisionPath (Join-Path $stageDirectory ([string]$Stage.synthesis.output)) `
                -SourcePaths $agentArtifacts -RunRoot $RunRoot -RunId $RunId -OutputPath $composedPath
            Add-StageArtifact -Path $composedPath
        }
        $status = if ($synthesis.status -eq "completed") { "completed" } else { $synthesis.status }
    }
    "producer_critic_loop" {
        $maximum = [int]$Stage.approval.max_iterations
        $status = "revision_required"
        $criticHistory = @()
        $previousProducerPath = ""
        $revisionOffset = 0
        $incrementalRevisions = $Stage.producer.PSObject.Properties['incremental_revisions'] -and
            $Stage.producer.incremental_revisions
        if ($incrementalRevisions) {
            $revisionContext = Get-QaFoundryBlueprintRevisionContext -RunRoot $RunRoot -RunId $RunId `
                -Stage $Stage -BeforeIteration $Iteration
            $previousProducerPath = $revisionContext.basePath
            $criticHistory = @($revisionContext.history)
            $revisionOffset = [int]$revisionContext.revisionOffset
        }
        $finalProducerPath = ""
        $finalCriticPaths = @()
        for ($criticIteration = 1; $criticIteration -le $maximum; $criticIteration++) {
            $loopDirectory = if ($criticIteration -eq 1) {
                $stageDirectory
            }
            else {
                Join-Path $stageDirectory "critic-iteration-$criticIteration"
            }
            New-Item -ItemType Directory -Path $loopDirectory -Force | Out-Null
            $originalDirectory = $stageDirectory
            $stageDirectory = $loopDirectory
            # Left to itself the producer rewrites the document from scratch each round and
            # quietly undoes what earlier critics accepted, so each revision is handed an
            # explicit account of what is settled and what is still open.
            $producerContext = @()
            $revisionNumber = $revisionOffset + $criticIteration
            if ($revisionNumber -gt 1) {
                $ledgerPath = Join-Path $loopDirectory "revision-ledger.json"
                $ledgerJson = New-QaFoundryRevisionLedger `
                    -RunId $RunId `
                    -StageId $stageId `
                    -Revision $revisionNumber `
                    -History $criticHistory |
                    ConvertTo-Json -Depth 100
                # A resumed run rebuilds the same ledger from the same reviews. Rewriting it
                # would age an artifact the relay is entitled to treat as already produced.
                $existingLedger = if (Test-Path -LiteralPath $ledgerPath) {
                    Get-Content -Path $ledgerPath -Raw
                }
                else { "" }
                if ($existingLedger.Trim() -ne $ledgerJson.Trim()) {
                    Set-Content -Path $ledgerPath -Value $ledgerJson -Encoding utf8
                }
                $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
                    -ArtifactPath $ledgerPath `
                    -SchemaPath (Join-Path $root "schemas/architecture/revision-ledger.schema.json") `
                    -SchemaRoot (Join-Path $root "schemas")
                $producerContext = @($ledgerPath)
                if ($previousProducerPath -and (Test-Path -LiteralPath $previousProducerPath)) {
                    $producerContext += $previousProducerPath
                }
            }
            $revisionBase = if ($previousProducerPath -and $incrementalRevisions) {
                $previousProducerPath
            } else { '' }
            $producerResult = Invoke-ConfiguredAgent `
                -Agent $Stage.producer `
                -AdditionalContext $producerContext `
                -RevisionBasePath $revisionBase `
                -ProfileOrdinal 0
            $producerPath = Join-Path $loopDirectory ([string]$Stage.producer.output)
            $previousProducerPath = $producerPath
            # A producer that reports 'blocked' or 'failed' is saying it did not
            # write the document. Sending critics to review it wastes three model
            # calls and, worse, invites them to approve it.
            if ([string]$producerResult.status -in @("blocked", "failed")) {
                Write-QaFoundryLog -Level warn -Indent 1 -Message (
                    "The producer reports its own result as $([string]$producerResult.status), so " +
                    "the critics are not called on it: $([string]$producerResult.summary)")
                $stageDirectory = $originalDirectory
                $finalProducerPath = $producerPath
                $finalCriticPaths = @()
                $status = "blocked"
                $decision = "blocked"
                break
            }
            . (Join-Path $PSScriptRoot 'CompletionStatus.ps1')
            $producerDeferrals = @(Get-QaFoundryArtifactDeferrals -PublishedPath $producerPath)
            if ($producerDeferrals.Count -gt 0) {
                $stageDirectory = $originalDirectory
                $finalProducerPath = $producerPath
                $finalCriticPaths = @()
                $status = Get-QaFoundryCompletionDisposition -Deferrals $producerDeferrals
                $decision = $status
                Write-QaFoundryLog -Level warn -Indent 1 -Message 'The producer has unfinished work; critics wait for a complete revision within this loop budget.'
                if ($status -eq 'blocked') { break }
                continue
            }
            $decisions = @()
            $criticContext = @($producerPath)
            if ($revisionNumber -gt 1) { $criticContext += $ledgerPath }
            $criticResults = @(Invoke-ConfiguredAgentsParallel `
                -Agents @($Stage.critics) `
                -AdditionalContext $criticContext `
                -ProfileOrdinalOffset 1)
            foreach ($criticResult in $criticResults) {
                # A critic that could not do its job did not approve anything,
                # whatever its decision field happens to say.
                $decisions += if ([string]$criticResult.result.status -in @("blocked", "failed")) {
                    "blocked"
                }
                else { [string]$criticResult.result.decision }
                $criticHistory += [pscustomobject]@{
                    revision = $revisionNumber
                    criticId = [string]$criticResult.agentId
                    decision = [string]$criticResult.result.decision
                    findings = @($criticResult.result.findings)
                    requiredChanges = @($criticResult.result.requiredChanges)
                }
            }
            $stageDirectory = $originalDirectory
            # The document the critics just judged, whatever they decided, and
            # the judgements themselves. Only the round the loop ends on is
            # published: earlier rounds were superseded, and publishing them all
            # under one name is how a later stage ends up resolving a draft.
            $finalProducerPath = $producerPath
            $finalCriticPaths = @($criticResults | ForEach-Object { [string]$_.outputPath })
            if (@($decisions | Where-Object { $_ -ne "approved" }).Count -eq 0) {
                $status = "approved"
                $decision = "approved"
                break
            }
            if ($decisions -contains "blocked") {
                $status = "blocked"
                $decision = "blocked"
                break
            }
        }
        if ($status -eq "revision_required") {
            $decision = "revision_required"
        }
        if ($finalProducerPath) {
            Add-StageArtifact -Path $finalProducerPath
            foreach ($criticPath in $finalCriticPaths) {
                Add-StageArtifact -Path $criticPath
            }
        }
    }
    "sequential" {
        $status = "completed"
        if ($stageId -eq 'execution' -and $null -ne $Workflow -and $Workflow.name -eq 'bootstrap-automation') {
            $assessment = & (Join-Path $PSScriptRoot 'actions/New-BootstrapExecutionAssessment.ps1') `
                -Workflow $Workflow -RunRoot $RunRoot -RunId $RunId -OutputDirectory $stageDirectory `
                -DeferExecution:(Test-QaFoundryDeferredVerification -Config $Config)
            foreach ($path in $assessment.Artifacts) { Add-StageArtifact -Path $path }
            $declaredStageInputs = @($assessment.Inputs)
            Write-QaFoundryLog -Indent 1 -Message 'Bootstrap execution assessment: no generated automation was executed. Materialization follows design review; the configured verification mode determines whether execution is attempted.'
            break
        }
        $sequentialOrdinal = 0
        foreach ($agent in @($Stage.agents)) {
            $result = Invoke-ConfiguredAgent `
                -Agent $agent `
                -ProfileOrdinal $sequentialOrdinal
            $sequentialOrdinal++
            $artifactPath = Join-Path $stageDirectory ([string]$agent.output)
            Add-StageArtifact -Path $artifactPath
            if ($stageId -eq 'implementation' -and $result.PSObject.Properties['dependencyRequests'] -and
                @($result.dependencyRequests).Count -gt 0) {
                $dependencyOutput = Join-Path $stageDirectory ("$($agent.id)-dependency-resolution.json")
                $dependencyResult = & (Join-Path $PSScriptRoot 'actions/Resolve-DependencyRequests.ps1') `
                    -Requests @($result.dependencyRequests) -Config $Config -RunRoot $RunRoot -RunId $RunId `
                    -StageId $stageId -OutputPath $dependencyOutput -Deadline $Deadline
                Add-StageArtifact -Path $dependencyOutput
                if ($dependencyResult.changed -or $dependencyResult.status -ne 'completed') {
                    Write-QaFoundryLog -Level warn -Indent 1 -Message $dependencyResult.detail
                    # Preserve the inventory and unrelated blockers along with resolution evidence.
                    break
                }
            }
            # A dependent agent cannot implement against an incomplete owner inventory.
            # Let the normal completion gate classify and retry the owner's omissions
            # before another agent can turn them into an apparent external blocker.
            . (Join-Path $PSScriptRoot 'CompletionStatus.ps1')
            if (@(Get-QaFoundryArtifactDeferrals -PublishedPath $artifactPath).Count -gt 0) {
                if ($result.status -in @('blocked', 'failed')) { $status = 'blocked' }
                Write-QaFoundryLog -Level warn -Indent 1 -Message (
                    "Agent '$($agent.id)' has unfinished deliverables; dependent agents wait for completion.")
                break
            }
            if ([string]$agent.id -eq "execution") {
                $executionResultPath = Join-Path $stageDirectory "execution-result.json"
                $planSignature = Get-ExecutionPlanSignature -Commands @($result.commands)
                # Replaying an answered model call is free, so the relay reuses
                # one without asking. Replaying the commands that call planned is
                # not free, and nothing checked that. Build 480 spent legs three,
                # four and five on the same thirty minutes of commands: each leg
                # reused the plan in seconds, ran the plan again, and stopped for
                # budget before the failure-analysis agent that was meant to read
                # the results. The relay made no progress at all while every leg
                # reported success. A command that already ran is evidence, not
                # work to redo, so a recorded result is reused like any artifact.
                $recordedExecution = $null
                if ($ReuseExistingArtifacts -and
                    (Test-Path -LiteralPath $executionResultPath -PathType Leaf)) {
                    # A leg can be killed mid-write, and half a JSON document is
                    # not evidence of anything. Reuse only what still validates.
                    try {
                        $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
                            -ArtifactPath $executionResultPath `
                            -SchemaPath (Join-Path $root "schemas/execution/execution-result.schema.json") `
                            -SchemaRoot (Join-Path $root "schemas")
                        $recordedExecution = Get-Content -LiteralPath $executionResultPath -Raw |
                            ConvertFrom-Json -Depth 100
                    }
                    catch {
                        Write-QaFoundryLog -Level warn -Indent 2 -Message (
                            "The recorded execution result is unusable, so the plan is run again: " +
                            $_.Exception.Message)
                        $recordedExecution = $null
                    }
                }
                if ($null -ne $recordedExecution) {
                    # Passing the schema only proves the file is a result. It does
                    # not prove it is the result of this run's plan, and a result
                    # from some other plan would be a lie told with a straight
                    # face. Reuse it only if it accounts for exactly the commands
                    # the plan asks for, in order, and was recorded by this run.
                    $plannedSignature = @($result.commands | ForEach-Object {
                        [string]$_.id + " :: " + (
                            (@([string]$_.executable) +
                                @($_.arguments | ForEach-Object { [string]$_ })) -join " ")
                    })
                    $recordedSignature = @($recordedExecution.commands | ForEach-Object {
                        [string]$_.id + " :: " + [string]$_.command
                    })
                    $mismatch = if ([string]$recordedExecution.runId -ne $RunId) {
                        "it was recorded by run '$($recordedExecution.runId)', not this one"
                    }
                    elseif (
                        (-not ((Get-QaFoundryPropertyNames -InputObject $recordedExecution) -contains "planSignature")) -or
                        [string]$recordedExecution.planSignature -ne $planSignature
                    ) {
                        "it answers a different plan than the one this stage holds"
                    }
                    elseif (
                        $recordedSignature.Count -gt $plannedSignature.Count -or
                        (($plannedSignature | Select-Object -First $recordedSignature.Count) -join "`n") -ne
                            ($recordedSignature -join "`n")
                    ) {
                        "it accounts for $($recordedSignature.Count) command(s) that do not match " +
                        "the $($plannedSignature.Count) the plan asks for"
                    }
                    else { $null }
                    if ($null -ne $mismatch) {
                        Write-QaFoundryLog -Level warn -Indent 2 -Message (
                            "The recorded execution result is not evidence about this plan, so the " +
                            "plan is run again: $mismatch.")
                        $recordedExecution = $null
                    }
                }

                # Commands are recorded one at a time rather than all at the end.
                # A leg that dies partway through a thirty-minute list used to
                # leave nothing behind, so the next leg started the list from the
                # beginning and died in the same place.
                $commandResults = @()
                if ($null -ne $recordedExecution) {
                    $commandResults = @($recordedExecution.commands)
                }
                $remaining = @($result.commands | Select-Object -Skip $commandResults.Count)
                if ($commandResults.Count -gt 0) {
                    Write-QaFoundryLog -Indent 2 -Message (
                        "$($commandResults.Count) command(s) already ran on an earlier leg and " +
                        "their recorded results are reused; $($remaining.Count) remain.")
                }
                if ($remaining.Count -eq 0) {
                    if ($null -eq $recordedExecution) {
                        # An empty plan still needs its own evidence. Otherwise
                        # failure analysis can only see an earlier iteration's failures.
                        [ordered]@{runId=$RunId;stageId='execution';status='completed';planSignature=$planSignature;commands=@()} |
                            ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $executionResultPath -Encoding utf8
                    }
                    Add-StageArtifact -Path $executionResultPath
                }
                else {
                    $writeExecutionResult = {
                        param([object[]]$Results, [string]$ResultStatus)

                        # Written aside and moved into place, so a leg killed
                        # during the write leaves either the previous record or
                        # none — never half of one for the next leg to read as
                        # evidence.
                        $temporaryPath = "$executionResultPath.tmp"
                        [ordered]@{
                            runId = $RunId
                            stageId = "execution"
                            status = $ResultStatus
                            planSignature = $planSignature
                            commands = @($Results)
                        } | ConvertTo-Json -Depth 100 |
                            Set-Content -Path $temporaryPath -Encoding utf8
                        Move-Item -LiteralPath $temporaryPath `
                            -Destination $executionResultPath -Force
                    }
                    $budgetStopReason = $null
                    $policyCommandTimeout = [int]$Policy.commands.timeout_seconds
                    for ($commandIndex = 0; $commandIndex -lt $remaining.Count; $commandIndex++) {
                        # Starting a command the leg cannot afford to finish is
                        # how build 500 lost leg 3 whole: eleven commands were
                        # started after the deadline had passed, each was killed
                        # at the policy timeout, and the record claimed eleven
                        # failures the commands had not earned. The next leg
                        # begins with a full budget and the results recorded so
                        # far, so handing over costs nothing and proves nothing
                        # false.
                        if ($null -ne $Deadline) {
                            $secondsLeft = Get-QaFoundryBudgetSecondsRemaining -Deadline $Deadline
                            $secondsNeeded = $policyCommandTimeout +
                                $script:QaFoundryHandoverReserveSeconds
                            if ($secondsLeft -lt $secondsNeeded) {
                                $budgetStopReason = (
                                    "stage 'execution' stopped with " +
                                    "$($remaining.Count - $commandIndex) command(s) still to run " +
                                    "because this leg has $secondsLeft second(s) left and the next " +
                                    "command may take $policyCommandTimeout of them")
                                break
                            }
                        }
                        $commandResult = & (Join-Path $PSScriptRoot "Invoke-CommandSafely.ps1") `
                            -CommandSpec $remaining[$commandIndex] `
                            -Policy $Policy `
                            -RepositoryRoot $RepositoryRoot `
                            -Isolation (Get-QaFoundryIsolationSetting -Config $Config) `
                            -Deadline $Deadline
                        if ([string]$commandResult.status -eq "blocked") {
                            # A blocked result is not an answer about the command,
                            # so it is dropped rather than recorded. Keeping it
                            # would make the next leg skip the command entirely.
                            $budgetStopReason = (
                                "stage 'execution' stopped with " +
                                "$($remaining.Count - $commandIndex) command(s) still to run " +
                                "because this leg's time ran out while one was running")
                            break
                        }
                        $commandResults += $commandResult
                        # "failed" until the list is finished, because a record
                        # that stops early has not proved the plan succeeded.
                        & $writeExecutionResult @($commandResults) "failed"
                    }
                    if ($null -ne $budgetStopReason) {
                        & $writeExecutionResult @($commandResults) "failed"
                        Stop-QaFoundryForBudget -Reason $budgetStopReason
                    }
                    $executionStatus = if (
                        @($commandResults | Where-Object {
                            $_.status -in @("failed", "rejected")
                        }).Count -eq 0
                    ) { "completed" } else { "failed" }
                    $skippedCount = @($commandResults | Where-Object { $_.status -eq "skipped" }).Count
                    if ($skippedCount -gt 0) {
                        Write-QaFoundryLog -Level warn -Indent 2 -Message (
                            "$skippedCount command(s) had no directory to run in and were recorded " +
                            "as skipped. Nothing is claimed about what they would have proved.")
                    }
                    $rejectedCount = @($commandResults | Where-Object { $_.status -eq "rejected" }).Count
                    if ($rejectedCount -gt 0) {
                        Write-QaFoundryLog -Level warn -Indent 2 -Message (
                            "$rejectedCount command(s) were refused by the execution policy and did " +
                            "not run. The reason is recorded against each one.")
                    }
                    $failedCount = @($commandResults | Where-Object { $_.status -eq "failed" }).Count
                    if ($failedCount -gt 0) {
                        Write-QaFoundryLog -Level warn -Indent 2 -Message (
                            "$failedCount command(s) failed. That is evidence for the " +
                            "failure-analysis agent and the reviewers to weigh, not a reason to end " +
                            "the run: during a bootstrap the automation being built does not exist " +
                            "on disk yet.")
                    }
                    & $writeExecutionResult @($commandResults) $executionStatus
                    $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
                        -ArtifactPath $executionResultPath `
                        -SchemaPath (Join-Path $root "schemas/execution/execution-result.schema.json") `
                        -SchemaRoot (Join-Path $root "schemas")
                    Add-StageArtifact -Path $executionResultPath
                    # The execution result records honestly that commands failed, but the
                    # stage itself succeeded: it ran the plan it was given. Whether the
                    # failures are acceptable is a judgement for the failure-analysis
                    # agent and the reviewers that follow, both of which are unreachable
                    # if the runtime ends the run here.
                }
            }
            # An agent that reports 'failed' has said, in the only words the
            # schema gives it, that it did not do the work. Passing that on as a
            # completed stage hands the next agent a document its author has
            # disowned; a run is stopped on it exactly as it is on 'blocked'.
            if ($result.status -in @("blocked", "failed")) {
                if ([string]$result.status -eq "failed") {
                    Write-QaFoundryLog -Level warn -Indent 1 -Message (
                        "Agent '$([string]$agent.id)' reports its own result as failed, so the " +
                        "stage stops rather than carrying it forward: $([string]$result.summary)")
                }
                $status = "blocked"
                break
            }
        }
    }
    "batched_agent" {
        # One model call cannot carry the bodies of every approved file, and no
        # amount of asking for brevity changes that: the files are the
        # deliverable. The runtime therefore assigns bounded, named subsets of
        # the already-approved inventory, one call each, and checks afterwards
        # that the subsets add up to exactly what was approved.
        $batching = $Stage.batching
        $inventoryNames = @($batching.inventory_inputs | ForEach-Object { [string]$_ })
        $inventoryPaths = @()
        foreach ($inventoryName in $inventoryNames) {
            $match = @($declaredStageInputs | Where-Object { [string]$_.input -eq $inventoryName })
            if ($match.Count -ne 1) {
                throw ("Stage '$stageId' batches over input '$inventoryName', which the stage does " +
                    "not declare. The inventory has to be named, not searched for: a critic loop " +
                    "leaves one file per iteration and the newest is not always the approved one.")
            }
            $inventoryPaths += [string]$match[0].path
        }

        $targetBatchBytes = if ($batching.PSObject.Properties.Name -contains "target_batch_bytes") {
            [int]$batching.target_batch_bytes
        }
        else { 36864 }
        $maxFilesPerBatch = if ($batching.PSObject.Properties.Name -contains "max_files_per_batch") {
            [int]$batching.max_files_per_batch
        }
        else { 6 }

        # A rejection over three files used to cost the regeneration of all
        # forty-seven. The reviewers now state the scope of the repair they are
        # asking for, so a targeted rejection re-batches only the files it
        # names and carries the rest forward from the plan it rejected.
        #
        # Every condition for that has to be verifiable here, because a wrong
        # carry-forward delivers a framework the reviewers never saw. The
        # inventory must be the one the rejected plan was built from, the plan
        # must have completed, and every named path must be one the run
        # approved. Anything else falls back to regenerating the whole tree.
        $inventoryBasis = @($inventoryPaths | ForEach-Object {
            [ordered]@{
                path = (Get-QaFoundryRunRelativePath -RunRoot $RunRoot -Path $_)
                sha256 = (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        } | Sort-Object -Property { [string]$_.path })
        $basisPath = Join-Path $stageDirectory "batch-basis.json"
        [ordered]@{ inventories = @($inventoryBasis) } | ConvertTo-Json -Depth 40 |
            Set-Content -LiteralPath $basisPath -Encoding utf8
        Add-StageArtifact -Path $basisPath

        $carriedPlanPath = ""
        $regeneratePaths = @()
        $carryAllRecovered = $false
        $recoverySeed = $null
        if ($Iteration -eq 1) {
            $fullSplit = & (Join-Path $PSScriptRoot 'New-ChangeSetBatches.ps1') `
                -InventoryPaths $inventoryPaths -TargetBatchBytes $targetBatchBytes -MaxFilesPerBatch $maxFilesPerBatch
            $recoverySeed = Get-QaFoundryRecoveryGenerationSeed -RunRoot $RunRoot -RunId $RunId `
                -StageId $stageId -PlanName ([string]$batching.output) -CurrentSplit $fullSplit
            if ($null -ne $recoverySeed) {
                $carriedPlanPath = $recoverySeed.planPath
                $regeneratePaths = @($recoverySeed.paths)
                $carryAllRecovered = $regeneratePaths.Count -eq 0
                Write-QaFoundryLog -Indent 2 -Message "Recovered existing source: $($regeneratePaths.Count) changed or new file contract(s) require generation; unchanged contracts retain their code."
                if (-not $carryAllRecovered) {
                    $repairInstructionPath = Join-Path $stageDirectory 'repair-instructions.json'
                    [ordered]@{
                        carriedFromPlan = (Get-QaFoundryRunRelativePath -RunRoot $RunRoot -Path $carriedPlanPath)
                        regeneratePaths = @($regeneratePaths)
                        instructions = @($recoverySeed.instructions)
                    } | ConvertTo-Json -Depth 40 | Set-Content $repairInstructionPath -Encoding utf8
                    Add-StageArtifact -Path $repairInstructionPath
                }
            }
        }
        if ($Iteration -gt 1) {
            $repair = Get-TargetedRepair `
                -BaseStageDirectory $baseStageDirectory `
                -PlanName ([string]$batching.output) `
                -InventoryBasis $inventoryBasis `
                -ApprovedPaths @((& (Join-Path $PSScriptRoot "New-ChangeSetBatches.ps1") `
                    -InventoryPaths $inventoryPaths `
                    -TargetBatchBytes $targetBatchBytes `
                    -MaxFilesPerBatch $maxFilesPerBatch).paths)
            if ($null -ne $repair) {
                $carriedPlanPath = [string]$repair.planPath
                $regeneratePaths = @($repair.paths)
                Write-QaFoundryLog -Indent 2 -Message (
                    "The review asked for a targeted repair of $($regeneratePaths.Count) file(s). " +
                    "The rest of the approved inventory is carried forward unchanged from " +
                    "$(Split-Path $carriedPlanPath -Leaf).")
                $repairInstructionPath = Join-Path $stageDirectory "repair-instructions.json"
                [ordered]@{
                    carriedFromPlan = (Get-QaFoundryRunRelativePath -RunRoot $RunRoot -Path $carriedPlanPath)
                    regeneratePaths = @($regeneratePaths)
                    instructions = @($repair.instructions)
                } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $repairInstructionPath -Encoding utf8
                Add-StageArtifact -Path $repairInstructionPath
            }
        }

        $split = & (Join-Path $PSScriptRoot "New-ChangeSetBatches.ps1") `
            -InventoryPaths $inventoryPaths `
            -TargetBatchBytes $targetBatchBytes `
            -MaxFilesPerBatch $maxFilesPerBatch `
            -RegeneratePaths $regeneratePaths
        if ($carryAllRecovered) {
            $split.batches = @(); $split.regeneratedPaths = @(); $split.layerCount = 0
        }
        Write-QaFoundryLog -Indent 2 -Message (
            "$(@($split.regeneratedPaths).Count) of $($split.totalFiles) approved file(s) split into " +
            "$(@($split.batches).Count) batch(es) of at most $maxFilesPerBatch file(s) each, across " +
            "$([int]$split.layerCount) dependency layer(s).")
        if (@($split.resolverOwnedPaths).Count -gt 0) {
            Write-QaFoundryLog -Indent 2 -Message (
                "$(@($split.resolverOwnedPaths).Count) approved path(s) are left to the resolver " +
                "rather than assigned to a batch: $(@($split.resolverOwnedPaths) -join ', ').")
        }

        $generatorAgent = @($Stage.agents | Where-Object { [string]$_.role -eq "batch_generator" })
        if ($generatorAgent.Count -ne 1) {
            throw "Stage '$stageId' needs exactly one agent with role 'batch_generator'."
        }
        $generatorAgent = $generatorAgent[0]
        $plannerAgent = @($Stage.agents | Where-Object { [string]$_.role -eq "materialization_planner" })

        # Every artifact this stage writes is named up front and kept out of the
        # shared context. Otherwise batch five would carry batches one to four in
        # its request, and the requests would grow exactly as the answers shrank.
        $batchOutputs = @($split.batches | ForEach-Object { "change-set-$($_.batchId).json" })
        $assignmentNames = @($split.batches | ForEach-Object { "assignment-$($_.batchId).json" })
        $script:StageContextExclusions = @($batchOutputs + $assignmentNames +
            @("approved-paths.json", "batch-basis.json", "repair-instructions.json",
              [string]$batching.output) +
            @($plannerAgent | ForEach-Object { [string]$_.output }))

        # A repaired file still has to agree with the files that were not
        # repaired. Those are final text now, so the batch is given the bodies
        # it depends on rather than a description of them, and only those: the
        # whole carried plan would put the framework back into one request.
        $carriedContent = @{}
        $previousContent = @{}
        $repairInstructions = @()
        $dependentsByPath = @{}
        foreach ($property in @(Get-QaFoundryPropertyNames -InputObject $split.dependentsByPath)) {
            $dependentsByPath[[string]$property] = @($split.dependentsByPath.$property)
        }
        if ($carriedPlanPath) {
            $carriedPlan = Get-Content -LiteralPath $carriedPlanPath -Raw | ConvertFrom-Json -Depth 100
            foreach ($change in @($carriedPlan.changes)) {
                $carriedPath = ([string]$change.path).Replace("\", "/").Trim()
                if (-not $carriedPath) { continue }
                if ((Get-QaFoundryPropertyNames -InputObject $change) -notcontains "content") { continue }
                $previousContent[$carriedPath] = [string]$change.content
                if ($regeneratePaths -contains $carriedPath) { continue }
                $carriedContent[$carriedPath] = [string]$change.content
            }
            if (-not $carryAllRecovered) { $repairInstructions = @((Get-Content -LiteralPath (
                Join-Path $stageDirectory "repair-instructions.json") -Raw |
                ConvertFrom-Json -Depth 40).instructions) }
        }
        elseif ($Iteration -gt 1) {
            # Even when diagnostics cannot safely narrow the repair, revise the existing
            # source instead of asking the model to invent the same project again.
            $priorDirectory = if ($Iteration -eq 2) { $baseStageDirectory } else {
                Join-Path $baseStageDirectory "iteration-$($Iteration - 1)"
            }
            $priorPlanPath = Join-Path $priorDirectory ([string]$batching.output)
            if (Test-Path -LiteralPath $priorPlanPath -PathType Leaf) {
                $priorPlan = Get-Content -LiteralPath $priorPlanPath -Raw | ConvertFrom-Json -Depth 100
                if ($priorPlan.status -eq 'completed' -and $priorPlan.runId -ceq $RunId) {
                    foreach ($change in @($priorPlan.changes)) {
                        if ('content' -in @(Get-QaFoundryPropertyNames -InputObject $change)) {
                            $previousContent[[string]$change.path] = [string]$change.content
                        }
                    }
                }
            }
        }

        $batchPaths = @()
        $refused = $false
        # An answer names the assignment it fulfils. The name is how the run
        # knows which files the answer is about, so an answer carrying the wrong
        # one would be read as being about somebody else's files.
        $expectedBatchIdOfAgent = @{}
        # Build 498 died on the last of twelve batches. It refused correctly:
        # the contract of a file it owned needed operations that a file it
        # imports, already written and final in a lower layer, did not offer.
        # Owning files is what makes the layering safe, and it is also what
        # leaves a batch with no way out of an inventory whose contracts do not
        # meet. So a refusal that names the approved files it would have needed
        # is answered once, with those files merged into its own assignment,
        # rather than ending four hours of work.
        $escalated = @{}
        $supersededPaths = @()
        # What a later batch should be shown for a file, once an escalation has
        # replaced the version its owner wrote.
        $effectiveArtifactOfBatch = @{}
        $plannedByPath = @{}
        $batchOfPath = @{}
        $bytesByPath = @{}
        # A targeted repair may need a file carried from the previous plan.
        # Ownership of today's batches is narrower than the approved inventory.
        foreach ($approvedFile in @($split.approvedFiles)) {
            $plannedByPath[[string]$approvedFile.path] = $approvedFile.plannedFile
            $bytesByPath[[string]$approvedFile.path] = [int]$approvedFile.estimatedBytes
        }
        foreach ($indexBatch in @($split.batches)) {
            foreach ($indexFile in @($indexBatch.files)) {
                $plannedByPath[[string]$indexFile.path] = $indexFile.plannedFile
                $batchOfPath[[string]$indexFile.path] = [string]$indexBatch.batchId
                $bytesByPath[[string]$indexFile.path] = [int]$indexFile.estimatedBytes
            }
        }
        $maxParallelBatches = if ($batching.PSObject.Properties.Name -contains "max_parallel_batches") {
            [int]$batching.max_parallel_batches
        }
        else { 3 }
        if ($maxParallelBatches -lt 1) { $maxParallelBatches = 1 }

        # Batches ran one after another until build 496, where eight sequential
        # calls of six to thirteen minutes each spent 74 minutes producing work
        # that had no reason to be ordered. Batches in the same layer depend on
        # nothing each other writes, so they are asked at the same time; layers
        # still run in order, because a later layer is written against the text
        # an earlier one produced rather than a guess at it.
        for ($layer = 0; $layer -lt [int]$split.layerCount; $layer++) {
            $layerBatches = @($split.batches | Where-Object { [int]$_.layer -eq $layer })
            if ($layerBatches.Count -eq 0) { continue }

            $layerAgents = @()
            $layerContext = @{}
            $layerOrdinals = @{}
            foreach ($batch in $layerBatches) {
                $assignedPaths = @($batch.files | ForEach-Object { [string]$_.path })
                # A helper with twenty callers would put twenty file bodies into
                # the assignment, and the context manager would then carry the
                # whole assignment by reference — the instructions along with
                # the bodies. The text goes into a file of its own, so the
                # assignment stays small enough to be inlined whatever the
                # repair touches.
                $carriedPaths = @(
                    @($batch.files | ForEach-Object {
                        $plannedFile = $_.plannedFile
                        $assignedPath = [string]$_.path
                        if ((Get-QaFoundryPropertyNames -InputObject $plannedFile) -contains "dependsOn") {
                            @($plannedFile.dependsOn) | ForEach-Object {
                                ([string]$_).Replace("\", "/").Trim()
                            }
                        }
                        # The other direction as well. A repaired helper that
                        # renames an export breaks the callers the review left
                        # alone, and those are final text now: unless the batch
                        # can read them, the run pays another whole review
                        # cycle to learn it.
                        if ($dependentsByPath.ContainsKey($assignedPath)) {
                            @($dependentsByPath[$assignedPath])
                        }
                    }) | Where-Object { $_ } | Sort-Object -Unique |
                            Where-Object {
                                $carriedContent.ContainsKey($_) -and $_ -notin $assignedPaths
                            }
                    )
                $carriedContextPath = ""
                if ($carriedPaths.Count -gt 0) {
                    $carriedContextPath = Join-Path $stageDirectory "carried-$($batch.batchId).json"
                    [ordered]@{
                        batchId = [string]$batch.batchId
                        files = @(
                            foreach ($carriedPath in $carriedPaths) {
                                [ordered]@{
                                    path = $carriedPath
                                    content = [string]$carriedContent[$carriedPath]
                                }
                            }
                        )
                    } | ConvertTo-Json -Depth 100 |
                        Set-Content -LiteralPath $carriedContextPath -Encoding utf8
                    Add-StageArtifact -Path $carriedContextPath
                }
                $assignmentPath = Join-Path $stageDirectory "assignment-$($batch.batchId).json"
                $repairSourcePath = ''
                $repairSourcePaths = @($assignedPaths | Where-Object { $previousContent.ContainsKey($_) })
                if ($repairSourcePaths.Count -gt 0) {
                    $repairSourcePath = Join-Path $stageDirectory "repair-source-$($batch.batchId).json"
                    [ordered]@{
                        batchId = [string]$batch.batchId
                        files = @($repairSourcePaths | ForEach-Object {
                            [ordered]@{ path = $_; content = $previousContent[$_] }
                        })
                    } | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $repairSourcePath -Encoding utf8
                    Add-StageArtifact -Path $repairSourcePath
                }
                [ordered]@{
                    batchId = [string]$batch.batchId
                    ordinal = [int]$batch.ordinal
                    batchCount = @($split.batches).Count
                    layer = [int]$batch.layer
                    estimatedBytes = [int]$batch.estimatedBytes
                    assignedFiles = @($batch.files | ForEach-Object { $_.plannedFile })
                    assignedPaths = @($assignedPaths)
                    # Every approved path, so a batch can import a helper another
                    # batch is writing without inventing it or duplicating it.
                    allApprovedPaths = @($split.paths)
                    # The batches that wrote the files this one depends on. Their
                    # artifacts are supplied alongside this assignment, so the
                    # imports here are checked against text rather than intent.
                    dependsOnBatchIds = @($batch.dependsOnBatchIds)
                    # What the review asked this batch to fix, and the final text
                    # of the files it has to keep agreeing with. Present only on
                    # a targeted repair.
                    repairInstructions = @(
                        foreach ($instruction in $repairInstructions) {
                            if (@(@($instruction.paths) |
                                Where-Object { $assignedPaths -contains $_ }).Count -eq 0) {
                                continue
                            }
                            $instruction
                        }
                    )
                    # Named here, supplied as text in the artifact below. A path
                    # in this list is a file that is already final: it is read,
                    # never rewritten.
                    carriedDependencies = @($carriedPaths)
                    carriedDependencyArtifact = if ($carriedContextPath) {
                        Split-Path $carriedContextPath -Leaf
                    }
                    else { "" }
                    # Named so the generator knows the omission is deliberate. A
                    # lock file left out with no explanation invites the model to
                    # add it back, which is exactly what the schema refuses.
                    resolverOwnedPaths = @($split.resolverOwnedPaths)
                } | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $assignmentPath -Encoding utf8
                Add-StageArtifact -Path $assignmentPath

                $batchAgent = [pscustomobject]@{}
                foreach ($property in $generatorAgent.PSObject.Properties) {
                    $batchAgent | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
                }
                $batchAgent.id = "$([string]$generatorAgent.id)-$($batch.batchId)"
                $batchAgent.output = "change-set-$($batch.batchId).json"
                $expectedBatchIdOfAgent[[string]$batchAgent.id] = [string]$batch.batchId
                $layerAgents += $batchAgent

                $dependencyArtifacts = @(
                    foreach ($sourceId in @($batch.dependsOnBatchIds)) {
                        $sourcePath = Join-Path $stageDirectory "change-set-$sourceId.json"
                        if ($effectiveArtifactOfBatch.ContainsKey($sourceId)) {
                            $sourcePath = [string]$effectiveArtifactOfBatch[$sourceId]
                        }
                        if ($sourcePath -and (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                            $sourcePath
                        }
                    }
                )
                $layerContext[[string]$batchAgent.id] = @(@($assignmentPath) +
                    @(if ($carriedContextPath) { $carriedContextPath }) +
                    @(if ($repairSourcePath) { $repairSourcePath }) + $dependencyArtifacts)
                # Every batch of this stage goes to the same profile the single
                # sequential generator always used. Spreading them across the
                # ordinal list would quietly hand most of the framework to
                # models this stage was never proven against, and a resumed leg
                # has to ask the same batch the same question anyway.
                $layerOrdinals[[string]$batchAgent.id] = 0
            }

            for ($windowStart = 0; $windowStart -lt $layerAgents.Count; $windowStart += $maxParallelBatches) {
                $window = @($layerAgents |
                    Select-Object -Skip $windowStart -First $maxParallelBatches)
                $windowResults = @(Invoke-ConfiguredAgentsParallel `
                    -Agents $window `
                    -AdditionalContextByAgentId $layerContext `
                    -ProfileOrdinalByAgentId $layerOrdinals)
                # Every answered batch is registered before the refusal is acted
                # on. A sibling that succeeded has already been paid for, and the
                # next leg reuses it instead of asking for it again.
                $blockedResults = @()
                foreach ($windowResult in $windowResults) {
                    Add-StageArtifact -Path ([string]$windowResult.outputPath)
                    $batchPaths += [string]$windowResult.outputPath
                    # The batch this answer is about is taken from the answer
                    # itself, and everything after this reads its files, its
                    # layer and its dependants from that name. A name that does
                    # not match the assignment sends all of it to the wrong set
                    # of files, so it is checked before it is used rather than
                    # after something has gone wrong.
                    $answeredNames = @(Get-QaFoundryPropertyNames -InputObject $windowResult.result)
                    $answeredBatchId = @(if ($answeredNames -contains "batchId") {
                        [string]$windowResult.result.batchId
                    })
                    $expectedBatchId = [string]$expectedBatchIdOfAgent[[string]$windowResult.agentId]
                    if ($expectedBatchId -and
                        (@($answeredBatchId)[0] -ne $expectedBatchId)) {
                        Write-QaFoundryLog -Level warn -Indent 2 -Message (
                            "Batch agent $([string]$windowResult.agentId) answered for " +
                            "'$(@($answeredBatchId)[0])' when it was assigned '$expectedBatchId'. " +
                            "An answer about another batch's files cannot be merged as this " +
                            "one's, so the run says so instead of guessing which it meant.")
                        $refused = $true
                        continue
                    }
                    if ([string]$windowResult.result.status -in @("blocked", "failed")) {
                        $blockedResults += $windowResult
                    }
                    elseif ([string]$windowResult.result.status -eq 'completed') {
                        foreach ($change in @($windowResult.result.changes)) {
                            if ('content' -in @(Get-QaFoundryPropertyNames -InputObject $change)) {
                                $previousContent[[string]$change.path] = [string]$change.content
                            }
                        }
                    }
                }
                if ($refused) { break }
                foreach ($blockedResult in $blockedResults) {
                    $blockedDocument = $blockedResult.result
                    $blockedNames = @(Get-QaFoundryPropertyNames -InputObject $blockedDocument)
                    $blockedBatchId = if ($blockedNames -contains "batchId") {
                        [string]$blockedDocument.batchId
                    }
                    else { "" }
                    $requiredPaths = @()
                    if ($blockedNames -contains "details" -and $null -ne $blockedDocument.details) {
                        $detailNames = @(Get-QaFoundryPropertyNames -InputObject $blockedDocument.details)
                        if ($detailNames -contains "requiredRepairPaths") {
                            $requiredPaths = @(@($blockedDocument.details.requiredRepairPaths) |
                                ForEach-Object { ([string]$_).Replace("\", "/").Trim() } |
                                Where-Object { $_ } | Sort-Object -Unique)
                        }
                    }
                    $ownPaths = @($batchOfPath.Keys |
                        Where-Object { $batchOfPath[$_] -eq $blockedBatchId } | Sort-Object)
                    # Only authored paths from the complete approved inventory. A list
                    # that names something else is not a list this run can act on
                    # halfway: acting on the part it recognises would answer a
                    # question the batch did not ask.
                    $wantedPaths = @($requiredPaths | Where-Object { $_ -notin $ownPaths })
                    $unknownPaths = @($wantedPaths | Where-Object { -not $plannedByPath.ContainsKey($_) })
                    $mergedBytes = [int](@($ownPaths + $wantedPaths | ForEach-Object {
                        if ($bytesByPath.ContainsKey($_)) { $bytesByPath[$_] } else { 0 } } |
                        Measure-Object -Sum).Sum)
                    $escalationId = "$blockedBatchId-escalated"
                    $reason = if ($requiredPaths.Count -eq 0) {
                        "it named no approved file that would make the work possible"
                    }
                    elseif ($wantedPaths.Count -eq 0) {
                        "the files it named are ones it already owned"
                    }
                    elseif ($unknownPaths.Count -gt 0) {
                        ("it named $($unknownPaths -join ', '), which the inventory does not approve for generation")
                    }
                    elseif ($escalated.ContainsKey($blockedBatchId)) {
                        "it had already been given the files it asked for once"
                    }
                    else { "" }
                    if ($reason) {
                        Write-QaFoundryLog -Level warn -Indent 2 -Message (
                            ("Batch agent $([string]$blockedResult.agentId) did not produce the " +
                            "changes it was assigned (status: " +
                            "$([string]$blockedDocument.status)), and cannot be asked again because " +
                            "{0}. No further batch is called, because a partly generated framework " +
                            "is worse than a stated refusal.") -f $reason)
                        $refused = $true
                        continue
                    }

                    $escalated[$blockedBatchId] = $true
                    $mergedPaths = @(@($ownPaths + $wantedPaths) | Sort-Object -Unique)

                    # Build 973271 lost leg 5 here. Three batches refused, two
                    # were merged and answered, and the third was abandoned
                    # because its merged assignment came to 74 KB of authored
                    # text -- more than one answer can close, so the whole stage
                    # reported blocked after paying for everything before it.
                    # Size is not a reason to give up on work that has to agree
                    # with itself: the merged set is written in parts instead,
                    # and each part is given the finished text of the parts
                    # before it, so the files still meet. The files the refusing
                    # batch was missing come first, because they are what the
                    # rest was waiting to be written against.
                    $orderedMerged = @(@(@($wantedPaths | Sort-Object) +
                        @($ownPaths | Sort-Object)) | Select-Object -Unique)
                    # What one merged call was always allowed to carry. Only
                    # what exceeds it is split, so an escalation that used to
                    # fit in a single answer still takes exactly one.
                    $escalationPartBytes = $targetBatchBytes * 2
                    $escalationPartFiles = $maxFilesPerBatch * 2
                    $escalationParts = [System.Collections.Generic.List[object]]::new()
                    $partPaths = [System.Collections.Generic.List[string]]::new()
                    $partBytes = 0
                    foreach ($mergedPath in $orderedMerged) {
                        $pathBytes = if ($bytesByPath.ContainsKey($mergedPath)) {
                            [int]$bytesByPath[$mergedPath]
                        }
                        else { 0 }
                        if ($partPaths.Count -gt 0 -and
                            ((($partBytes + $pathBytes) -gt $escalationPartBytes) -or
                             ($partPaths.Count -ge $escalationPartFiles))) {
                            $escalationParts.Add(@($partPaths))
                            $partPaths = [System.Collections.Generic.List[string]]::new()
                            $partBytes = 0
                        }
                        $partPaths.Add($mergedPath)
                        $partBytes += $pathBytes
                    }
                    if ($partPaths.Count -gt 0) { $escalationParts.Add(@($partPaths)) }

                    if ($escalationParts.Count -le 1) {
                        Write-QaFoundryLog -Level warn -Indent 2 -Message (
                            "Batch $blockedBatchId refused its assignment and named " +
                            "$($wantedPaths.Count) approved file(s) it would have to write as well. " +
                            "Asking once for all $($mergedPaths.Count) file(s) together.")
                    }
                    else {
                        Write-QaFoundryLog -Level warn -Indent 2 -Message (
                            "Batch $blockedBatchId refused its assignment and named " +
                            "$($wantedPaths.Count) approved file(s) it would have to write as well. " +
                            "The $($mergedPaths.Count) file(s) come to about $mergedBytes bytes, " +
                            "more than one answer closes, so they are written in " +
                            "$($escalationParts.Count) parts, each given the text of the ones " +
                            "before it.")
                    }

                    $escalationResults = @()
                    $escalationChanges = [System.Collections.Generic.List[object]]::new()
                    $escalationWritten = [System.Collections.Generic.List[string]]::new()
                    $escalationDocument = $null
                    $escalationOutputPaths = [System.Collections.Generic.List[string]]::new()
                    $partFailed = $false

                    for ($partIndex = 0; $partIndex -lt $escalationParts.Count; $partIndex++) {
                        $thisPart = @($escalationParts[$partIndex])
                        $partId = if ($escalationParts.Count -le 1) { $escalationId }
                            else { "$escalationId-part-$($partIndex + 1)" }

                        # Everything already written that these files have to
                        # agree with: their own dependencies and dependants, and
                        # the parts of this escalation that came before.
                        $escalationCarried = @(@(@($thisPart | ForEach-Object {
                            $mergedPlanned = $plannedByPath[$_]
                            @(if ((Get-QaFoundryPropertyNames -InputObject $mergedPlanned) -contains "dependsOn") {
                                @($mergedPlanned.dependsOn) |
                                    ForEach-Object { ([string]$_).Replace("\", "/").Trim() }
                            }) +
                            @(if ($dependentsByPath.ContainsKey($_)) { @($dependentsByPath[$_]) })
                        }) + @($escalationWritten)) | Where-Object { $_ } | Sort-Object -Unique |
                            Where-Object { $carriedContent.ContainsKey($_) -and $_ -notin $thisPart })
                        $escalationCarriedPath = ""
                        if ($escalationCarried.Count -gt 0) {
                            $escalationCarriedPath = Join-Path $stageDirectory "carried-$partId.json"
                            [ordered]@{
                                batchId = $partId
                                files = @(
                                    foreach ($carriedPath in $escalationCarried) {
                                        [ordered]@{
                                            path = $carriedPath
                                            content = [string]$carriedContent[$carriedPath]
                                        }
                                    }
                                )
                            } | ConvertTo-Json -Depth 100 |
                                Set-Content -LiteralPath $escalationCarriedPath -Encoding utf8
                            Add-StageArtifact -Path $escalationCarriedPath
                        }

                        $partInstruction = (
                            ("An earlier call was assigned " +
                            "$($ownPaths -join ', ') and refused, because the work needed " +
                            "changes to files it did not own. Those files are now yours to " +
                            "write as well. Its stated reason was: {0} Write every assigned " +
                            "file so that they agree with one another.") -f
                                [string]$blockedDocument.summary)
                        $partInstruction += ' Preserve the verification requirement: the default local suite must execute real assertions without deployment credentials. Listing or discovering tests is not execution; do not substitute --list, an empty suite, skipped tests or weaker assertions for a passing run.'
                        if ($escalationParts.Count -gt 1) {
                            $partOrder = if ($partIndex -eq 0) {
                                "The remaining files come after this one and will be written " +
                                "against what you produce, so settle the shared contracts here."
                            }
                            else {
                                "The earlier parts are already written and their final text is " +
                                "supplied to you: agree with it exactly rather than restating " +
                                "or redesigning it."
                            }
                            $partInstruction += (
                                " The set is larger than one answer can hold, so it is being " +
                                "written in $($escalationParts.Count) parts and this is part " +
                                "$($partIndex + 1). Write only the files assigned here. " +
                                $partOrder)
                        }

                        $escalationAssignmentPath = Join-Path $stageDirectory "assignment-$partId.json"
                        [ordered]@{
                            batchId = $partId
                            ordinal = @($split.batches).Count + 1 + $partIndex
                            batchCount = @($split.batches).Count + $escalationParts.Count
                            estimatedBytes = [int](@($thisPart | ForEach-Object {
                                if ($bytesByPath.ContainsKey($_)) { $bytesByPath[$_] } else { 0 } } |
                                Measure-Object -Sum).Sum)
                            assignedFiles = @($thisPart | ForEach-Object { $plannedByPath[$_] })
                            assignedPaths = @($thisPart)
                            allApprovedPaths = @($split.paths)
                            dependsOnBatchIds = @()
                            # The refusal itself, as the instruction. The files that
                            # were only in the way are now in the same assignment, so
                            # the contract that did not meet can be made to meet.
                            repairInstructions = @(
                                [ordered]@{
                                    reviewer = $blockedBatchId
                                    paths = @($thisPart)
                                    instruction = $partInstruction
                                }
                            )
                            carriedDependencies = @($escalationCarried)
                            carriedDependencyArtifact = if ($escalationCarriedPath) {
                                Split-Path $escalationCarriedPath -Leaf
                            }
                            else { "" }
                            resolverOwnedPaths = @($split.resolverOwnedPaths)
                        } | ConvertTo-Json -Depth 100 |
                            Set-Content -LiteralPath $escalationAssignmentPath -Encoding utf8
                        Add-StageArtifact -Path $escalationAssignmentPath

                        $escalationAgent = [pscustomobject]@{}
                        foreach ($property in $generatorAgent.PSObject.Properties) {
                            $escalationAgent | Add-Member -NotePropertyName $property.Name `
                                -NotePropertyValue $property.Value
                        }
                        $escalationAgent.id = "$([string]$generatorAgent.id)-$partId"
                        $escalationAgent.output = "change-set-$partId.json"
                        # The merged files still import files other batches have
                        # already written. Without their answers the escalation
                        # writes against the contracts rather than against the
                        # interfaces that exist, which is the same mistake that
                        # blocked the batch in the first place.
                        $escalationDependencies = @(
                            foreach ($mergedPath in $thisPart) {
                                $mergedPlanned = $plannedByPath[$mergedPath]
                                if ((Get-QaFoundryPropertyNames -InputObject $mergedPlanned) -notcontains "dependsOn") {
                                    continue
                                }
                                foreach ($dependency in @($mergedPlanned.dependsOn)) {
                                    $dependencyPath = ([string]$dependency).Replace("\", "/").Trim()
                                    if (-not $dependencyPath -or $dependencyPath -in $thisPart) { continue }
                                    if (-not $batchOfPath.ContainsKey($dependencyPath)) { continue }
                                    $ownerId = [string]$batchOfPath[$dependencyPath]
                                    $ownerArtifact = Join-Path $stageDirectory "change-set-$ownerId.json"
                                    if ($effectiveArtifactOfBatch.ContainsKey($ownerId)) {
                                        $ownerArtifact = [string]$effectiveArtifactOfBatch[$ownerId]
                                    }
                                    if ($ownerArtifact -and
                                        (Test-Path -LiteralPath $ownerArtifact -PathType Leaf)) {
                                        $ownerArtifact
                                    }
                                }
                            }
                        ) | Sort-Object -Unique
                        $escalationContext = @{}
                        $escalationSourcePath = ''
                        $sourcePaths = @($thisPart | Where-Object {
                            $carriedContent.ContainsKey($_) -or $previousContent.ContainsKey($_)
                        })
                        if ($sourcePaths.Count -gt 0) {
                            $escalationSourcePath = Join-Path $stageDirectory "repair-source-$partId.json"
                            [ordered]@{
                                batchId = $partId
                                files = @($sourcePaths | ForEach-Object {
                                    [ordered]@{ path = $_; content = if ($carriedContent.ContainsKey($_)) {
                                        $carriedContent[$_]
                                    } else { $previousContent[$_] } }
                                })
                            } | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $escalationSourcePath -Encoding utf8
                            Add-StageArtifact -Path $escalationSourcePath
                        }
                        $escalationContext[[string]$escalationAgent.id] = @(
                            @($escalationAssignmentPath) +
                            @(if ($escalationCarriedPath) { $escalationCarriedPath }) +
                            @(if ($escalationSourcePath) { $escalationSourcePath }) +
                            @($escalationDependencies))
                        $escalationOrdinals = @{}
                        $escalationOrdinals[[string]$escalationAgent.id] = 0
                        $partResults = @(Invoke-ConfiguredAgentsParallel `
                            -Agents @($escalationAgent) `
                            -AdditionalContextByAgentId $escalationContext `
                            -ProfileOrdinalByAgentId $escalationOrdinals)

                        if ($escalationParts.Count -le 1) {
                            $escalationResults = $partResults
                            break
                        }

                        # A part that does not land makes the parts after it
                        # pointless: they would be written against text that was
                        # never produced.
                        foreach ($partResult in $partResults) {
                            Add-StageArtifact -Path ([string]$partResult.outputPath)
                            $escalationOutputPaths.Add([string]$partResult.outputPath)
                            $partNames = @(Get-QaFoundryPropertyNames -InputObject $partResult.result)
                            $partAnswered = @(if ($partNames -contains "batchId") {
                                [string]$partResult.result.batchId
                            })
                            if (@($partAnswered)[0] -ne $partId) {
                                Write-QaFoundryLog -Level warn -Indent 2 -Message (
                                    "Part $($partIndex + 1) of the escalation answered for " +
                                    "'$(@($partAnswered)[0])' when it was assigned '$partId', so " +
                                    "what it wrote cannot be credited to the files it was given.")
                                $partFailed = $true
                                break
                            }
                            if ([string]$partResult.result.status -in @("blocked", "failed")) {
                                Write-QaFoundryLog -Level warn -Indent 2 -Message (
                                    "Part $($partIndex + 1) of the escalation refused its share of " +
                                    "the merged assignment (status: " +
                                    "$([string]$partResult.result.status)). The plan cannot be " +
                                    "written as approved, and saying so is the answer.")
                                $partFailed = $true
                                break
                            }
                            if ($null -eq $escalationDocument) { $escalationDocument = $partResult.result }
                            foreach ($partChange in @($partResult.result.changes)) {
                                $changePath = ([string]$partChange.path).Replace("\", "/").Trim()
                                if (-not $changePath) { continue }
                                $escalationChanges.Add($partChange)
                                $escalationWritten.Add($changePath)
                                if ((Get-QaFoundryPropertyNames -InputObject $partChange) -contains "content") {
                                    # The next part is written against this text
                                    # rather than against the contract it came
                                    # from, which is the whole point of parts.
                                    $carriedContent[$changePath] = [string]$partChange.content
                                }
                            }
                        }
                        if ($partFailed) { break }
                    }

                    if ($partFailed) {
                        $refused = $true
                        continue
                    }

                    # The parts are one answer as far as everything downstream is
                    # concerned: one artifact for the merged set, checked and
                    # merged exactly as a single escalation always was.
                    if ($escalationParts.Count -gt 1) {
                        if ($null -eq $escalationDocument) {
                            Write-QaFoundryLog -Level warn -Indent 2 -Message (
                                "The escalation of $blockedBatchId produced no answer to merge.")
                            $refused = $true
                            continue
                        }
                        $escalationDocument.batchId = $escalationId
                        $escalationDocument.changes = @($escalationChanges)
                        $combinedPath = Join-Path $stageDirectory "change-set-$escalationId.json"
                        $escalationDocument | ConvertTo-Json -Depth 100 |
                            Set-Content -LiteralPath $combinedPath -Encoding utf8
                        Add-StageArtifact -Path $combinedPath
                        Write-QaFoundryLog -Indent 2 -Message (
                            "The $($escalationParts.Count) parts of $escalationId wrote " +
                            "$($escalationChanges.Count) file(s) and are merged into one change set.")
                        # The parts themselves must not also be merged, or every
                        # file would arrive twice.
                        $batchPaths = @($batchPaths |
                            Where-Object { $_ -notin @($escalationOutputPaths) })
                        $escalationResults = @([pscustomobject]@{
                            agentId = "$([string]$generatorAgent.id)-$escalationId"
                            outputPath = $combinedPath
                            result = $escalationDocument
                        })
                    }
                    foreach ($escalationResult in $escalationResults) {
                        Add-StageArtifact -Path ([string]$escalationResult.outputPath)
                        $escalationNames = @(Get-QaFoundryPropertyNames `
                            -InputObject $escalationResult.result)
                        $escalationAnswered = @(if ($escalationNames -contains "batchId") {
                            [string]$escalationResult.result.batchId
                        })
                        if (@($escalationAnswered)[0] -ne $escalationId) {
                            Write-QaFoundryLog -Level warn -Indent 2 -Message (
                                "The escalation answered for '$(@($escalationAnswered)[0])' when " +
                                "it was assigned '$escalationId', so what it wrote cannot be " +
                                "credited to the files it was given.")
                            $refused = $true
                            continue
                        }
                        if ([string]$escalationResult.result.status -in @("blocked", "failed")) {
                            Write-QaFoundryLog -Level warn -Indent 2 -Message (
                                "Batch $escalationId refused the merged assignment as well " +
                                "(status: $([string]$escalationResult.result.status)). The plan " +
                                "cannot be written as approved, and saying so is the answer.")
                            $refused = $true
                            continue
                        }
                        # The escalation exists to rewrite files another batch
                        # already wrote. If it returns without one of them, the
                        # earlier version stays in the plan and the run ships the
                        # very mismatch the refusal was about, with nothing
                        # anywhere saying so. Silence is the danger here, not
                        # failure.
                        $escalationProduced = @(@($escalationResult.result.changes) |
                            ForEach-Object { ([string]$_.path).Replace("\", "/").Trim() } |
                            Where-Object { $_ })
                        $notWritten = @($mergedPaths |
                            Where-Object { $_ -notin $escalationProduced })
                        $surplus = @($escalationProduced |
                            Where-Object { $_ -notin $mergedPaths } | Sort-Object -Unique)
                        # Twice is as wrong as not at all: the merge keeps the
                        # first and drops the second without a word, so which of
                        # the two versions the run delivers would be decided by
                        # the order they happened to arrive in.
                        $writtenTwice = @($escalationProduced |
                            Group-Object | Where-Object { $_.Count -gt 1 } |
                            ForEach-Object { [string]$_.Name })
                        $wrong = @(
                            @(if ($notWritten.Count -gt 0) {
                                "did not write $($notWritten -join ', ')" }) +
                            @(if ($surplus.Count -gt 0) {
                                "wrote $($surplus -join ', '), which it was not given" }) +
                            @(if ($writtenTwice.Count -gt 0) {
                                "wrote $($writtenTwice -join ', ') more than once" })
                        )
                        if ($wrong.Count -gt 0) {
                            Write-QaFoundryLog -Level warn -Indent 2 -Message (
                                "Batch $escalationId was given $($mergedPaths.Count) file(s) and " +
                                ($wrong -join "; ") + ". Merging it would leave the versions its " +
                                "refusal was about in the plan, so the run says so instead.")
                            $refused = $true
                            continue
                        }
                        # First, so the merge credits these files to the call
                        # that reconciled them rather than reporting the earlier
                        # versions as duplicates of it.
                        $batchPaths = @(@([string]$escalationResult.outputPath) +
                            @($batchPaths | Where-Object { $_ -ne [string]$blockedResult.outputPath }))
                        $supersededPaths = @(@($supersededPaths + $wantedPaths) | Sort-Object -Unique)
                        $split.regeneratedPaths = @(@($split.regeneratedPaths + $wantedPaths) | Sort-Object -Unique)
                        # A batch in a higher layer that imports one of these
                        # files would otherwise be shown the version the
                        # escalation just replaced, and would agree with text
                        # that is no longer in the plan. Its owner's artifact is
                        # rewritten without the superseded files, and the
                        # dependency lookup is pointed at the escalation for
                        # them.
                        foreach ($escalatedChange in @($escalationResult.result.changes)) {
                            $escalatedPath = ([string]$escalatedChange.path).Replace("\", "/").Trim()
                            if (-not $escalatedPath) { continue }
                            if ((Get-QaFoundryPropertyNames -InputObject $escalatedChange) -notcontains "content") {
                                continue
                            }
                            $carriedContent[$escalatedPath] = [string]$escalatedChange.content
                        }
                        $effectiveArtifactOfBatch[$blockedBatchId] = [string]$escalationResult.outputPath
                        foreach ($ownerId in @($wantedPaths |
                            Where-Object { $batchOfPath.ContainsKey($_) } |
                            ForEach-Object { $batchOfPath[$_] } | Sort-Object -Unique)) {
                            $ownerArtifact = Join-Path $stageDirectory "change-set-$ownerId.json"
                            if ($effectiveArtifactOfBatch.ContainsKey($ownerId)) {
                                $ownerArtifact = [string]$effectiveArtifactOfBatch[$ownerId]
                            }
                            if (-not (Test-Path -LiteralPath $ownerArtifact -PathType Leaf)) { continue }
                            $ownerDocument = Get-Content -LiteralPath $ownerArtifact -Raw |
                                ConvertFrom-Json -Depth 100
                            $ownerDocument.changes = @(@($ownerDocument.changes) | Where-Object {
                                ([string]$_.path).Replace("\", "/").Trim() -notin $supersededPaths
                            })
                            if (@($ownerDocument.changes).Count -eq 0) {
                                # Everything it wrote has been replaced. There is
                                # nothing left to show a later batch, and a change
                                # set with no changes is not one the schema allows.
                                $effectiveArtifactOfBatch[$ownerId] = ""
                                continue
                            }
                            $effectivePath = Join-Path $stageDirectory `
                                "change-set-$ownerId-superseded.json"
                            $ownerDocument | ConvertTo-Json -Depth 100 |
                                Set-Content -LiteralPath $effectivePath -Encoding utf8
                            Add-StageArtifact -Path $effectivePath
                            $effectiveArtifactOfBatch[$ownerId] = $effectivePath
                        }
                    }
                }
                if ($refused) { break }
            }
            if ($refused) { break }
        }

        $materializationPath = ""
        # Nothing is being written, so there are no manifests to resolve. Asking
        # anyway spends a model call on a plan the merge is about to discard.
        if ($plannerAgent.Count -eq 1 -and -not $refused) {
            $approvedPathsPath = Join-Path $stageDirectory "approved-paths.json"
            [ordered]@{
                generatedPaths = @($split.paths)
                resolverOwnedPaths = @($split.resolverOwnedPaths)
                batches = @($batchOutputs)
                # Only resolver inputs belong here. Passing the entire previous
                # plan repeats every source file and batch record in this call.
                previousMaterializations = @(if ($carriedPlanPath) {
                    $carriedPlan.materializations | Where-Object { $_.manifestPath -in $split.paths }
                })
                carriedManifests = @(if ($carriedPlanPath) {
                    foreach ($manifest in @($carriedPlan.materializations | ForEach-Object manifestPath | Select-Object -Unique)) {
                        if ($manifest -in $split.paths -and $carriedContent.ContainsKey($manifest)) {
                            [ordered]@{ path = $manifest; content = $carriedContent[$manifest] }
                        }
                    }
                })
            } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $approvedPathsPath -Encoding utf8
            Add-StageArtifact -Path $approvedPathsPath
            $null = Invoke-ConfiguredAgent `
                -Agent $plannerAgent[0] `
                -AdditionalContext @($approvedPathsPath) `
                -ProfileOrdinal 1
            $materializationPath = Join-Path $stageDirectory ([string]$plannerAgent[0].output)
            Add-StageArtifact -Path $materializationPath
        }

        $mergedPath = Join-Path $stageDirectory ([string]$batching.output)
        $merge = & (Join-Path $PSScriptRoot "Merge-ChangeSetBatches.ps1") `
            -BatchPaths $batchPaths `
            -ExpectedPaths @($split.paths) `
            -OutputPath $mergedPath `
            -AgentId ([string]$generatorAgent.id) `
            -StageId $stageId `
            -RunId $RunId `
            -ResolverOwnedPaths @($split.resolverOwnedPaths) `
            -CarriedPlanPath $carriedPlanPath `
            -CarryAll:$carryAllRecovered `
            -RegeneratedPaths @($split.regeneratedPaths) `
            -SupersededPaths @($supersededPaths) `
            -MaterializationPath $materializationPath
        $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
            -ArtifactPath $mergedPath `
            -SchemaPath (Resolve-QaFoundryPath -Root $root -Path ([string]$batching.schema)) `
            -SchemaRoot (Join-Path $root "schemas")
        Add-StageArtifact -Path $mergedPath
        $status = if ([string]$merge.status -eq "blocked") { "blocked" } else { "completed" }
        if ($status -eq "completed") {
            Write-QaFoundryLog -Indent 2 -Message (
                "Merged $($merge.changeCount) file(s) from $(@($batchPaths).Count) batch(es) into " +
                "$([string]$batching.output).")
        }
    }
    "parallel_review" {
        $decisions = @()
        $reviewResults = @(Invoke-ConfiguredAgentsParallel -Agents @($Stage.agents) `
            -ProfileOrdinalOffset 0)
        foreach ($reviewResult in $reviewResults) {
            # A reviewer that reports it could not review has not approved
            # anything, whatever its decision field says.
            $decisions += if ([string]$reviewResult.result.status -in @("blocked", "failed")) {
                "blocked"
            }
            else { [string]$reviewResult.result.decision }
            Add-StageArtifact -Path ([string]$reviewResult.outputPath)
        }
        if ($decisions -contains "blocked") {
            $status = "blocked"
            $decision = "blocked"
        }
        elseif (@($decisions | Where-Object { $_ -ne "approved" }).Count -eq 0) {
            $status = "approved"
            $decision = "approved"
        }
        else {
            $status = "revision_required"
            $decision = "revision_required"
        }
    }
    "deterministic_action" {
        $outputPath = Join-Path $stageDirectory ([string]$Stage.action.output)
        $actionResult = & (Join-Path $PSScriptRoot "Invoke-DeterministicAction.ps1") `
            -Stage $Stage `
            -Config $Config `
            -Policy $Policy `
            -RunRoot $RunRoot `
            -RepositoryRoot $RepositoryRoot `
            -RunId $RunId `
            -OutputPath $outputPath `
            -ActionEnvironment $ActionEnvironment `
            -Deadline $Deadline
        if ($Stage.action.handler -eq 'verify_framework' -and -not $actionResult.dryRun -and
            $actionResult.status -eq 'revision_required') {
            $verificationPath = Join-Path $stageDirectory framework-verification.json
            $analyzer = {
                param($AgentId, $InputPath, $ResultPath)
                if (-not (Test-Path -LiteralPath $ResultPath)) {
                    Assert-AgentBudget -OutputPaths @($ResultPath) -Description "product defect investigation '$AgentId'"
                }
                $agentConfig = New-AgentConfig -ProfileOrdinal $(switch ($AgentId) { 'failure-root-cause-analyst' { 0 }; 'failure-evidence-auditor' { 1 }; default { 2 } })
                & (Join-Path $PSScriptRoot Invoke-Agent.ps1) -AgentId $AgentId -StageId failure-investigation -RunId $RunId `
                    -PromptPath (Join-Path $root "prompts/operations/$AgentId.md") `
                    -SchemaPath (Join-Path $root schemas/operations/failure-investigation.schema.json) `
                    -ContextPaths @((Join-Path $RunRoot context/repository.json)) -PriorityContextPaths @($InputPath) `
                    -OutputPath $ResultPath -Config $agentConfig -Policy $Policy -RepositoryRoot $RepositoryRoot `
                    -ProviderEnvironment (Get-AgentProviderEnvironment -AgentConfig $agentConfig) `
                    -Deadline $Deadline -AllowExistingArtifact
            }
            $verificationInputs = Resolve-QaFoundryDeclaredInputs -RunRoot $RunRoot -StageId $stageId -Inputs $Stage.action.inputs -RunId $RunId
            $report = & (Join-Path $PSScriptRoot actions/Report-ProductDefects.ps1) `
                -VerificationPath $verificationPath -ChangeSetPath ([string]$verificationInputs['changeSet'].path) `
                -RunRoot $RunRoot -RepositoryRoot $RepositoryRoot -RunId $RunId -Config $Config -Policy $Policy `
                -Analyzer $analyzer -ActionEnvironment $ActionEnvironment
            foreach ($path in @($report.artifacts)) { Add-StageArtifact -Path $path }
            $actionResult.evidence = @(@($actionResult.evidence) + @($report.artifacts) | Select-Object -Unique)
            $actionResult.actions = @(@($actionResult.actions) + @($report.bugActions))
            if (@($report.confirmed).Count -gt 0) {
                . (Join-Path $PSScriptRoot ProductDefects.ps1)
                $verification = Get-Content $verificationPath -Raw | ConvertFrom-Json -Depth 100
                foreach ($defect in @($report.confirmed)) {
                    $bug = @($report.bugActions | Where-Object sourceRef -EQ ('product-defect:' + $defect.sourceRef))
                    $verification.findings += [pscustomobject]@{
                        severity = 'warning'; projectPath = $defect.projectPath
                        message = "Keep regression test '$($defect.testName)' and its assertion. Confirmed product defect; Bug ID(s): $(@($bug | ForEach-Object externalId) -join ', ')."
                    }
                }
                if (Complete-QaFoundryProductDefectVerification -Verification $verification -Report $report) {
                    $actionResult.status = if ($verification.outcome -eq 'verified') { 'completed' } else { 'revision_required' }
                    $actionResult | ConvertTo-Json -Depth 100 | Set-Content $outputPath -Encoding utf8
                }
                $verification | ConvertTo-Json -Depth 100 | Set-Content $verificationPath -Encoding utf8
                $null = & (Join-Path $PSScriptRoot Validate-JsonArtifact.ps1) -ArtifactPath $verificationPath `
                    -SchemaPath (Join-Path $root schemas/runtime/framework-verification.schema.json) -SchemaRoot (Join-Path $root schemas)
            }
            $actionResult | ConvertTo-Json -Depth 100 | Set-Content $outputPath -Encoding utf8
            $null = & (Join-Path $PSScriptRoot Validate-JsonArtifact.ps1) -ArtifactPath $outputPath `
                -SchemaPath (Join-Path $root schemas/actions/action-result.schema.json) -SchemaRoot (Join-Path $root schemas)
        }
        $status = [string]$actionResult.status
        if ($actionResult.PSObject.Properties['failureKind']) { $actionFailureKind = [string]$actionResult.failureKind }
        Add-StageArtifact -Path $outputPath
        # An action names the files it read as well as the ones it wrote, and
        # only the latter belong to this stage. A file another stage produced is
        # already recorded there, under the same name; recording it here again
        # would either shadow this stage's own output or, when the names collide,
        # stop the run outright.
        $stageDirectoryPrefix = (Resolve-Path -LiteralPath $stageDirectory).Path.TrimEnd(
            [IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $isProducedHere = {
            param([string]$Path)
            if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
            return (Resolve-Path -LiteralPath $Path).Path.StartsWith(
                $stageDirectoryPrefix, [StringComparison]::OrdinalIgnoreCase)
        }
        # A refusal is a result, not a crash, and it carries no produced files. Build 466
        # reached the materialiser for the first time, the materialiser declined the plan
        # for a stated reason, and reading the absent property turned that clean refusal
        # into "The property 'produced' cannot be found on this object" — losing the reason
        # entirely, which is the failure mode this runtime exists to avoid.
        $actionResultFields = @(Get-QaFoundryPropertyNames -InputObject $actionResult)
        foreach ($field in @("evidence", "produced")) {
            if ($actionResultFields -notcontains $field) { continue }
            foreach ($candidate in @($actionResult.$field)) {
                if (& $isProducedHere ([string]$candidate)) {
                    Add-StageArtifact -Path ([string]$candidate)
                }
            }
        }
    }
    default {
        throw "Unsupported stage type: $($Stage.type)"
    }
}

# An agent that answered under a reduced budget wrote down, item by item, the
# work it did not do. Letting the stage close over that list is exactly the loss
# the list exists to prevent: the run would carry a design, a plan or a review
# that is smaller than the one it asked for, and every check downstream would
# pass on the smaller one. So the stage is sent back instead — a repeated stage
# gets a full budget — and the items are named in the log that says why.
$openDeferrals = [System.Collections.Generic.List[object]]::new()
. (Join-Path $PSScriptRoot 'CompletionStatus.ps1')
foreach ($published in @($publishedArtifacts)) {
    foreach ($deferral in @(Get-QaFoundryArtifactDeferrals -PublishedPath (Join-Path $RunRoot ([string]$published.relativePath)))) {
        $openDeferrals.Add($deferral)
    }
}
if ($openDeferrals.Count -gt 0 -and $status -in @("completed", "approved", "revision_required")) {
    Write-QaFoundryLog -Level warn -Indent 1 -Message (
        "Stage '$stageId' reports '$status', but $($openDeferrals.Count) item(s) it was asked " +
        "for remain unresolved: " +
        ((@($openDeferrals | Select-Object -First 8 |
            ForEach-Object { "$([string]$_.agentId): $([string]$_.item)" }) -join "; ")) +
        ". Only budget omissions or repairable artifact defects can trigger automatic revision.")
    $status = Get-QaFoundryCompletionDisposition -Deferrals @($openDeferrals)
    $decision = $status
}

return [pscustomobject]@{
    Status = $status
    Decision = $decision
    # Told apart from a reviewer's rejection on purpose. A critic that dissents
    # has judged work that exists, and a run may be configured to publish it
    # anyway; work that was never done is not a judgement anybody can overrule,
    # so the caller has to be able to see which of the two it is holding.
    CoverageIncomplete = ($openDeferrals.Count -gt 0)
    BlockedReason = if ($status -eq 'blocked' -and $openDeferrals.Count -gt 0) { 'unresolved_prerequisites' } else { $actionFailureKind }
    Deferrals = @($openDeferrals | ForEach-Object {
        [pscustomobject][ordered]@{
            agentId = [string]$_.agentId
            item = [string]$_.item
            reason = [string]$_.reason
            kind = [string]$_.kind
        }
    })
    ArtifactDirectory = $stageDirectory
    Artifacts = @($publishedArtifacts)
    Inputs = @($declaredStageInputs | ForEach-Object {
        [pscustomobject][ordered]@{
            input = [string]$_.input
            stage = [string]$_.stage
            name = [string]$_.name
            relativePath = [string]$_.relativePath
            sha256 = [string]$_.sha256
        }
    })
}
