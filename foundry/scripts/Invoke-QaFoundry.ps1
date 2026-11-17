[CmdletBinding()]
param(
    [string]$ConfigPath = "./config/project.yaml",
    [string]$WorkflowPath = "",
    [string]$PolicyPath = "./policies/default-policy.yaml",
    [string]$TargetRepositoryPath = "",
    [string[]]$DocumentationPath = @(),
    [string]$DocumentationLinks = '',
    [string[]]$RequirementsPath = @(),
    [string[]]$ArchitecturePath = @(),
    [string[]]$AdditionalContextPath = @(),
    [string]$EventPath = "",
    [string]$EventType = "auto",
    [string]$EventId = "",
    [string]$CiBuildId = "",
    [string]$CiRunId = "",
    [string]$SecretsPath = "",
    [string]$AiProfile = "",
    [string]$Model = "",
    [string]$ReasoningEffort = "",
    [string]$ResumeRunRoot = "",
    [string]$RestartStage = "",
    [int]$BudgetMinutes = 0,
    [switch]$Demo,
    [switch]$ValidateOnly
)

. (Join-Path $PSScriptRoot "Common.ps1")
$root = Get-QaFoundryRoot
$launcherRoot = (Get-Location).Path
$resolvedConfig = Resolve-QaFoundryPath -Root $launcherRoot -Path $ConfigPath
$resolvedPolicy = Resolve-QaFoundryPath -Root $launcherRoot -Path $PolicyPath
foreach ($requiredPath in @($resolvedConfig, $resolvedPolicy)) {
    if (-not (Test-Path $requiredPath -PathType Leaf)) {
        throw "Required input does not exist: $requiredPath"
    }
}

$config = Import-QaFoundryYaml -Path $resolvedConfig -Root $root
$policy = Import-QaFoundryYaml -Path $resolvedPolicy -Root $root
$null = & (Join-Path $PSScriptRoot "Validate-QaFoundryConfig.ps1") `
    -Config $config `
    -Root $root
$configDirectory = Split-Path $resolvedConfig -Parent
$route = & (Join-Path $PSScriptRoot "Resolve-EventWorkflow.ps1") `
    -Config $config `
    -ConfigDirectory $configDirectory `
    -LauncherRoot $launcherRoot `
    -WorkflowPath $WorkflowPath `
    -EventPath $EventPath `
    -EventType $EventType
$resolvedWorkflow = [string]$route.workflowPath
$resolvedEventPath = [string]$route.eventPath
$resolvedEventType = [string]$route.eventType
if (-not (Test-Path $resolvedWorkflow -PathType Leaf)) {
    throw "Selected workflow does not exist: $resolvedWorkflow"
}
$workflow = Import-QaFoundryYaml -Path $resolvedWorkflow -Root $root
if ($workflow.name -ne 'bootstrap-automation' -and (Test-QaFoundryDeferredVerification -Config $config)) {
    # Deferred execution is a bootstrap contract, not a bypass for later CI.
    $config.automation.verification.mode = 'execute'
}
$workflow.stages = @(
    & (Join-Path $PSScriptRoot "Resolve-WorkflowStages.ps1") -Workflow $workflow
)
$assuranceValidation = & (Join-Path $PSScriptRoot "Test-WorkflowAssurance.ps1") `
    -Workflow $workflow `
    -Config $config

if ([string]::IsNullOrWhiteSpace([string]$workflow.name) -or
    [int]$workflow.version -lt 1) {
    throw "Workflow name must be non-empty and version must be at least 1."
}
if ($policy.delivery.allow_merge) {
    throw "Policies that allow automatic merge are not supported."
}
if ($policy.delivery.allow_production_deploy) {
    throw "Policies that allow production deployment are not supported."
}

function Resolve-ConfigOrCliPath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][bool]$FromCli
    )
    $base = if ($FromCli) { $launcherRoot } else { $configDirectory }
    return Resolve-QaFoundryPath -Root $base -Path $Path
}
function Resolve-ConfigOrCliPaths {
    param(
        [string[]]$CliValues,
        [object[]]$ConfigValues,
        [Parameter(Mandatory)][bool]$UseCli
    )
    $values = if ($UseCli) { @($CliValues) } else { @($ConfigValues) }
    return @($values | ForEach-Object {
        Resolve-ConfigOrCliPath -Path ([string]$_) -FromCli $UseCli
    } | Select-Object -Unique)
}

$targetFromCli = $PSBoundParameters.ContainsKey("TargetRepositoryPath")
$targetConfiguredPath = if ($targetFromCli) {
    $TargetRepositoryPath
}
else {
    [string]$config.target.repository_path
}
$repositoryRoot = Resolve-ConfigOrCliPath `
    -Path $targetConfiguredPath `
    -FromCli $targetFromCli
if (-not (Test-Path $repositoryRoot -PathType Container)) {
    throw "Target repository directory does not exist: $repositoryRoot"
}
$repositoryRoot = (Resolve-Path $repositoryRoot).Path

$documentationPaths = Resolve-ConfigOrCliPaths `
    -CliValues $DocumentationPath `
    -ConfigValues @($config.target.documentation_paths) `
    -UseCli $PSBoundParameters.ContainsKey("DocumentationPath")
$requirementsPaths = Resolve-ConfigOrCliPaths `
    -CliValues $RequirementsPath `
    -ConfigValues @($config.target.requirements_paths) `
    -UseCli $PSBoundParameters.ContainsKey("RequirementsPath")
$architecturePaths = Resolve-ConfigOrCliPaths `
    -CliValues $ArchitecturePath `
    -ConfigValues @($config.target.architecture_paths) `
    -UseCli $PSBoundParameters.ContainsKey("ArchitecturePath")
$additionalContextPaths = Resolve-ConfigOrCliPaths `
    -CliValues $AdditionalContextPath `
    -ConfigValues @($config.target.additional_context_paths) `
    -UseCli $PSBoundParameters.ContainsKey("AdditionalContextPath")

$profile = & (Join-Path $PSScriptRoot "Resolve-AiProfile.ps1") `
    -Config $config `
    -ProfileName $AiProfile `
    -Model $Model `
    -ReasoningEffort $ReasoningEffort `
    -Demo:$Demo
$singleProfileOverride = $Demo -or
    $PSBoundParameters.ContainsKey("AiProfile") -or
    $PSBoundParameters.ContainsKey("Model") -or
    $PSBoundParameters.ContainsKey("ReasoningEffort")
if ($singleProfileOverride -and
    $config.ai.PSObject.Properties.Name -contains "collaboration") {
    $config.ai.collaboration.enabled = $false
}
$config = Set-QaFoundryResolvedAiProfile -Config $config -Profile $profile
$collaborationProfileNames = @(Get-QaFoundryCollaborationProfileNames -Config $config)
$runProfiles = [System.Collections.Generic.List[object]]::new()
$runProfiles.Add($profile)
foreach ($profileName in $collaborationProfileNames) {
    if ([string]$profileName -eq [string]$profile.name) { continue }
    $runProfiles.Add((& (Join-Path $PSScriptRoot "Resolve-AiProfile.ps1") `
        -Config $config -ProfileName ([string]$profileName)))
}

$resolvedSecretsOverride = if ($SecretsPath) {
    Resolve-ConfigOrCliPath -Path $SecretsPath -FromCli $true
}
else {
    ""
}
$secretsConfig = $config.secrets | ConvertTo-Json -Depth 30 |
    ConvertFrom-Json -Depth 30
if ($SecretsPath) {
    $secretsConfig.source = "file"
    $secretsConfig.format = "auto"
}
$providerEnvironment = if ($Demo) {
    @{}
}
else {
    & (Join-Path $PSScriptRoot "Import-QaFoundrySecrets.ps1") `
        -SecretsConfig $secretsConfig `
        -ConfigDirectory $configDirectory `
        -TargetRoot $repositoryRoot `
        -SecretsPathOverride $resolvedSecretsOverride
}
if ($null -eq $providerEnvironment) {
    $providerEnvironment = @{}
}
foreach ($runProfile in $runProfiles) {
    foreach ($requiredEnvironmentName in @($runProfile.required_secret_env)) {
        if (-not $providerEnvironment.ContainsKey([string]$requiredEnvironmentName) -or
            [string]::IsNullOrWhiteSpace(
                [string]$providerEnvironment[[string]$requiredEnvironmentName]
            )) {
            throw (
                "AI profile '$($runProfile.name)' requires mapped secret environment " +
                "variable '$requiredEnvironmentName'."
            )
        }
    }
}
$modelProviderEnvironment = @{}
foreach ($runProfile in $runProfiles) {
    foreach ($environmentName in @($runProfile.secret_env)) {
        $name = [string]$environmentName
        if ($providerEnvironment.ContainsKey($name)) {
            $modelProviderEnvironment[$name] = [string]$providerEnvironment[$name]
        }
    }
}

if ($Demo) {
    $config.delivery.dry_run = $true
    $config.work_tracking.dry_run = $true
    # A rehearsal that starts a real pipeline is not a rehearsal: the run it starts commits, pushes
    # and opens a pull request of its own, none of which this run would be holding back.
    if (@(Get-QaFoundryPropertyNames -InputObject $config.ci) -contains "dry_run") {
        $config.ci.dry_run = $true
    }
    # Proving the framework means installing packages from a registry and then
    # executing code this run has just written. A rehearsal does neither, and
    # says so in its own artifact rather than reporting a verified framework.
    if (@(Get-QaFoundryPropertyNames -InputObject $config) -contains "automation") {
        if (@(Get-QaFoundryPropertyNames -InputObject $config.automation) -notcontains "verification") {
            $config.automation | Add-Member -NotePropertyName "verification" `
                -NotePropertyValue ([pscustomobject]@{ dry_run = $true }) -Force
        }
        elseif (@(Get-QaFoundryPropertyNames -InputObject $config.automation.verification) -notcontains "dry_run") {
            $config.automation.verification | Add-Member -NotePropertyName "dry_run" `
                -NotePropertyValue $true -Force
        }
        else {
            $config.automation.verification.dry_run = $true
        }
        # Resolving dependencies reaches the same registry and additionally
        # insists that the exact toolchain the decision was settled on is
        # installed here. A rehearsal has to be runnable on any machine, and one
        # that refuses on an agent carrying a different npm has demonstrated
        # nothing except which npm that agent carries.
        if (@(Get-QaFoundryPropertyNames -InputObject $config.automation) -notcontains "materialization") {
            $config.automation | Add-Member -NotePropertyName "materialization" `
                -NotePropertyValue ([pscustomobject]@{ dry_run = $true }) -Force
        }
        elseif (@(Get-QaFoundryPropertyNames -InputObject $config.automation.materialization) -notcontains "dry_run") {
            $config.automation.materialization | Add-Member -NotePropertyName "dry_run" `
                -NotePropertyValue $true -Force
        }
        else {
            $config.automation.materialization.dry_run = $true
        }
    }
}
if ($config.delivery.create_draft_pull_request -and -not $config.delivery.create_branch) {
    throw "Draft pull request creation requires branch creation."
}
if ($config.delivery.commit_changes -and -not $config.delivery.create_branch) {
    throw "Commit creation requires branch creation."
}
if ($config.delivery.push_branch -and -not $config.delivery.commit_changes) {
    throw "Branch push requires commit creation."
}
if ($config.delivery.create_draft_pull_request -and -not $config.delivery.push_branch) {
    throw "Draft pull request creation requires branch push."
}
if ($config.delivery.create_draft_pull_request -and [string]$config.delivery.provider -eq "none") {
    throw "Draft pull request creation requires the Azure DevOps delivery provider."
}
$liveDeliveryRequested = -not [bool]$config.delivery.dry_run -and (
    [bool]$config.delivery.create_branch -or
    [bool]$config.delivery.commit_changes -or
    [bool]$config.delivery.push_branch -or
    [bool]$config.delivery.create_draft_pull_request
)
if ($liveDeliveryRequested -and -not [bool]$config.idempotency.enabled) {
    throw (
        "Live repository delivery requires idempotency.enabled=true so partial writes " +
        "remain detectable."
    )
}
if (-not [bool]$config.delivery.dry_run -and
    [bool]$config.delivery.commit_changes -and
    [string]$config.delivery.provider -notin @("azure-devops", "github")) {
    throw (
        "Live commit creation requires the Azure DevOps delivery provider so the " +
        "authenticated PAT owner supplies the Git identity."
    )
}
if ($config.work_tracking.enabled -and [string]$config.work_tracking.provider -eq "none") {
    throw "Enabled work tracking requires the Azure DevOps provider."
}
if ($ValidateOnly) {
    [pscustomobject]@{
        valid = $true
        configPath = $resolvedConfig
        workflowPath = $resolvedWorkflow
        policyPath = $resolvedPolicy
        targetRepository = $repositoryRoot
        aiProfile = $profile.name
        provider = $profile.provider
        model = $profile.model
        reasoningEffort = $profile.reasoning_effort
        collaborationProfiles = @($collaborationProfileNames)
        workflowName = [string]$workflow.name
        workflowVersion = [int]$workflow.version
        eventType = $resolvedEventType
        workflowRouted = [bool]$route.routed
        ciProvider = [string]$config.ci.provider
        realtimeCiCollection = [bool]$config.ci.collect_realtime
        assuranceMode = [string]$assuranceValidation.mode
        analysisInputCount = (
            @($documentationPaths).Count +
            @($requirementsPaths).Count +
            @($architecturePaths).Count +
            @($additionalContextPaths).Count
        )
        stages = @($workflow.stages).Count
    }
    return
}

$dependency = Join-Path $root "node_modules/yaml/package.json"
if (-not (Test-Path $dependency -PathType Leaf)) {
    throw "Runtime dependencies are missing. Run 'npm ci' in $root."
}

$isResume = -not [string]::IsNullOrWhiteSpace($ResumeRunRoot)
if ($RestartStage -and -not $isResume) { throw '-RestartStage requires -ResumeRunRoot.' }
. (Join-Path $PSScriptRoot 'RunInputs.ps1')
$refreshContext = $false
if ($isResume) {
    if (-not $config.runtime.resume_enabled) {
        throw "Resume is disabled by configuration."
    }
    $runRoot = Resolve-QaFoundryPath -Root $launcherRoot -Path $ResumeRunRoot
    if (-not (Test-PathWithinRoot -Candidate $runRoot -Root $repositoryRoot)) {
        throw "Resume run root must be inside the target repository."
    }
    $existingState = & (Join-Path $PSScriptRoot "Load-WorkflowState.ps1") `
        -Path (Join-Path $runRoot "workflow-state.json")
    $runId = [string]$existingState.runId
    $inputManifestPath = Join-Path $runRoot 'run-inputs.json'
    $refreshContext = $RestartStage -and $RestartStage -eq [string]$workflow.stages[0].id
    if (-not $refreshContext) {
        if (-not (Test-Path -LiteralPath $inputManifestPath)) {
            throw 'Legacy run has no input fingerprint. Restart from the first stage to establish verified inputs.'
        }
    }
}
else {
    $artifactsRoot = Resolve-QaFoundryPath `
        -Root $repositoryRoot `
        -Path ([string]$config.runtime.artifacts_root)
    if (-not (Test-PathWithinRoot -Candidate $artifactsRoot -Root $repositoryRoot)) {
        throw "runtime.artifacts_root must stay inside the target repository."
    }
    $runId = "run-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $runRoot = Join-Path $artifactsRoot $runId
    . (Join-Path $PSScriptRoot 'RelayEvidence.ps1')
    Set-QaFoundryRelayRun -ArtifactRoot $artifactsRoot -RunId $runId
    $workflowDirectories = @($workflow.stages | ForEach-Object {
        if ($_.PSObject.Properties.Name -contains "artifact_directory") {
            [string]$_.artifact_directory
        }
        else {
            [string]$_.id
        }
    })
    $artifactDirectories = @(
        @("context", "supervisor", "logs") + $workflowDirectories
    ) | Select-Object -Unique
    foreach ($directory in $artifactDirectories) {
        New-Item -ItemType Directory -Path (Join-Path $runRoot $directory) -Force | Out-Null
    }

}

Write-QaFoundryLog -Level step -Message 'Checking tools and delivery credentials before collecting CI evidence.'
& (Join-Path $PSScriptRoot 'Test-RunPrerequisites.ps1') -Config $config -RepositoryRoot $repositoryRoot `
    -OutputPath (Join-Path $runRoot 'context/prerequisites.json') -ActionEnvironment $providerEnvironment -Demo:$Demo

$documentationDirectory = Join-Path $runRoot 'documentation'
if (($DocumentationLinks -and $DocumentationLinks -ne 'none') -or (Test-Path -LiteralPath (Join-Path $documentationDirectory 'sources.json'))) {
    Write-QaFoundryLog -Level step -Message 'Reading the supplied project documentation.'
    if (-not $Demo) {
        $documents = & (Join-Path $PSScriptRoot 'Import-DocumentationSources.ps1') `
            -Directory $documentationDirectory -Links $DocumentationLinks -ActionEnvironment $providerEnvironment `
            -AzureDevOpsConfig $(if ($config.ci.PSObject.Properties.Name -contains "azure_devops") { $config.ci.azure_devops } else { $null }) `
            -Resume:($isResume -and (-not $refreshContext -or -not $DocumentationLinks -or $DocumentationLinks -eq 'none'))
        $documentationPaths = @($documentationPaths) + @((Join-Path $documentationDirectory 'sources.json')) + @(
            $documents.sources | Where-Object file | ForEach-Object { Join-Path $documentationDirectory ([string]$_.file) }
        )
        $available = @($documents.sources | Where-Object status -eq 'downloaded').Count
        Write-QaFoundryLog -Level step -Message "Documentation: $available of $(@($documents.sources).Count) sources downloaded. Analysis will record which contents could be read."
        if ($available -lt @($documents.sources).Count) {
            Write-QaFoundryLog -Level warn -Message 'Some documentation could not be retrieved. The report lists the unavailable sources and reasons.'
        }
    }
}
$currentInputs = Get-QaFoundryRunInputs -RepositoryRoot $repositoryRoot -FrameworkRoot $root `
    -Config $config -Workflow $workflow -Policy $policy `
    -InputPaths @(@($documentationPaths) + @($requirementsPaths) + @($architecturePaths) + @($additionalContextPaths))
if ($isResume -and -not $refreshContext) {
    Assert-QaFoundryRunInputs -Recorded (Get-Content -LiteralPath $inputManifestPath -Raw | ConvertFrom-Json -Depth 20) -Current $currentInputs
}
if ($isResume -and $RestartStage) {
    & (Join-Path $PSScriptRoot 'Reset-WorkflowStage.ps1') -RunRoot $runRoot -Workflow $workflow -StageId $RestartStage
}

if (-not $isResume -or $refreshContext) {
    $currentInputs | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $runRoot 'run-inputs.json') -Encoding utf8
    $eventContextPath = Join-Path $runRoot "context/sdlc-event.json"
    $eventContext = & (Join-Path $PSScriptRoot "Collect-SdlcEvent.ps1") `
        -RunId $runId `
        -OutputPath $eventContextPath `
        -EventPath $resolvedEventPath `
        -EventType $resolvedEventType `
        -EventId $EventId `
        -CiBuildId $CiBuildId `
        -CiRunId $CiRunId `
        -RepositoryRoot $repositoryRoot
    $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
        -ArtifactPath $eventContextPath `
        -SchemaPath (Join-Path $root "schemas/runtime/sdlc-event.schema.json") `
        -SchemaRoot (Join-Path $root "schemas")

    $secretsSource = if ($Demo) { "none" } else { [string]$secretsConfig.source }
    $runConfigurationPath = & (Join-Path $PSScriptRoot "New-RunConfiguration.ps1") `
        -RunRoot $runRoot `
        -RunId $runId `
        -Config $config `
        -Workflow $workflow `
        -RepositoryRoot $repositoryRoot `
        -EventContext $eventContext `
        -AiProfile $profile `
        -CollaborationProfileNames @($collaborationProfileNames) `
        -DocumentationPaths @($documentationPaths) `
        -RequirementsPaths @($requirementsPaths) `
        -ArchitecturePaths @($architecturePaths) `
        -AdditionalContextPaths @($additionalContextPaths) `
        -SecretsSource $secretsSource `
        -MappedEnvironmentNames @($providerEnvironment.Keys | Sort-Object) `
        -ModelEnvironmentNames @($modelProviderEnvironment.Keys | Sort-Object)

    $repositoryContextPath = Join-Path $runRoot "context/repository.json"
    $contextExclusions = @()
    if ($config.runtime.context.PSObject.Properties.Name -contains "excluded_directories") {
        $contextExclusions = @($config.runtime.context.excluded_directories)
    }
    Write-QaFoundryLog -Level step -Message "Collecting repository context."
    $null = & (Join-Path $PSScriptRoot "Collect-RepositoryContext.ps1") `
        -RepositoryRoot $repositoryRoot `
        -OutputPath $repositoryContextPath `
        -RunId $runId `
        -DocumentationPaths $documentationPaths `
        -RequirementsPaths $requirementsPaths `
        -ArchitecturePaths $architecturePaths `
        -AdditionalContextPaths $additionalContextPaths `
        -AllowedReadPaths @($config.repository.allowed_read_paths) `
        -MaxFileBytes ([int64]$config.runtime.context.max_file_bytes) `
        -MaxTotalBytes ([int64]$config.runtime.context.max_total_bytes) `
        -ExcludedDirectories $contextExclusions
    $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
        -ArtifactPath $repositoryContextPath `
        -SchemaPath (Join-Path $root "schemas/runtime/repository-context.schema.json") `
        -SchemaRoot (Join-Path $root "schemas")
    $collectedContext = Get-Content -Path $repositoryContextPath -Raw | ConvertFrom-Json -Depth 100
    Write-QaFoundryLog -Message (
        "Scanned $([int]$collectedContext.fileCount) file(s), collected " +
        (Format-QaFoundryBytes ([long]$collectedContext.contextBytes)) + " of content.")

    Write-QaFoundryLog -Level step -Message "Collecting continuous integration evidence."
    $ciEvidencePath = Join-Path $runRoot "context/ci-evidence.json"
    $null = & (Join-Path $PSScriptRoot "collectors/Collect-CiEvidence.ps1") `
        -RunId $runId `
        -EventPath $eventContextPath `
        -CiConfig $config.ci `
        -OutputPath $ciEvidencePath `
        -ProviderEnvironment $providerEnvironment
    $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
        -ArtifactPath $ciEvidencePath `
        -SchemaPath (Join-Path $root "schemas/runtime/ci-evidence.schema.json") `
        -SchemaRoot (Join-Path $root "schemas")

    Write-QaFoundryLog -Level step -Message "Collecting the work item this run implements."
    $workItemContextPath = Join-Path $runRoot "context/work-item.json"
    $null = & (Join-Path $PSScriptRoot "collectors/Collect-WorkItemContext.ps1") `
        -RunId $runId `
        -EventPath $eventContextPath `
        -WorkTrackingConfig $config.work_tracking `
        -OutputPath $workItemContextPath `
        -ProviderEnvironment $providerEnvironment
    $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
        -ArtifactPath $workItemContextPath `
        -SchemaPath (Join-Path $root "schemas/runtime/work-item-context.schema.json") `
        -SchemaRoot (Join-Path $root "schemas")

}

$budgetMinutesEffective = if ($BudgetMinutes -gt 0) {
    $BudgetMinutes
}
elseif (($config.runtime.PSObject.Properties.Name -contains "relay") -and
    ($config.runtime.relay.PSObject.Properties.Name -contains "budget_minutes")) {
    [int]$config.runtime.relay.budget_minutes
}
else { 0 }
$deadline = $null
if ($budgetMinutesEffective -gt 0) {
    # A leg that cannot fit one command plus the time to hand over would stop
    # before every command and pass exactly the same work to the next leg, for
    # as many legs as the relay has. Say so here rather than spend twelve legs
    # discovering it.
    $commandCeilingSeconds = [int]$policy.commands.timeout_seconds
    $legSeconds = $budgetMinutesEffective * 60
    $legSecondsNeeded = $commandCeilingSeconds + $script:QaFoundryHandoverReserveSeconds
    if ($legSeconds -le $legSecondsNeeded) {
        throw (
            "A relay leg is given $budgetMinutesEffective minute(s), which is not enough to run " +
            "one command: the policy allows a command $commandCeilingSeconds second(s) and a leg " +
            "reserves $script:QaFoundryHandoverReserveSeconds second(s) to hand over, so it needs " +
            "more than $legSecondsNeeded second(s). Raise the leg budget or lower " +
            "commands.timeout_seconds.")
    }
    $deadline = [DateTime]::UtcNow.AddMinutes($budgetMinutesEffective)
    Write-QaFoundryLog -Message (
        "This leg may run for $budgetMinutesEffective minute(s), until " +
        $deadline.ToString("HH:mm:ss") + "Z. Work that does not fit is handed to the next leg.")
}

# The relay's allowance spans builds; the ordinary deadline spans one leg.
# Carry the stricter deadline through all existing agent/command admission checks.
if ($env:FOUNDRY_RUN_DEADLINE_UTC) {
    $runDeadline = [DateTime]::Parse($env:FOUNDRY_RUN_DEADLINE_UTC).ToUniversalTime()
    if ($null -eq $deadline -or $runDeadline -lt $deadline) { $deadline = $runDeadline }
}

$workflowArguments = @{
    Workflow = $workflow
    Config = $config
    Policy = $policy
    RepositoryRoot = $repositoryRoot
    RunRoot = $runRoot
    RunId = $runId
    Resume = $isResume
    Deadline = $deadline
    ProviderEnvironment = $modelProviderEnvironment
    ActionEnvironment = $providerEnvironment
}
Write-QaFoundryLog -Level step -Message (
    "Starting workflow '$([string]$workflow.name)' with " +
    "$(@($workflow.stages).Count) stage(s) using profile '$($profile.name)' " +
    "(provider $($profile.provider), model $($profile.model)).")
try {
    $state = & (Join-Path $PSScriptRoot "Invoke-Workflow.ps1") @workflowArguments
}
finally {
    # A failed or paused workflow is still worth reporting. Do not replace its
    # original failure with a presentation error.
    try {
        & (Join-Path $PSScriptRoot 'Export-FoundryReport.ps1') -RepositoryRoot $repositoryRoot `
            -RunRoot $runRoot -OutputPath (Join-Path $runRoot 'report.html')
    }
    catch { Write-QaFoundryLog -Level warn -Message 'The run report could not be generated. Detailed run evidence is still available.' }
}
Write-QaFoundryLog -Level step -Message "Workflow finished with status '$([string]$state.status)'."

[pscustomobject]@{
    runId = $runId
    status = $state.status
    targetRepository = $repositoryRoot
    aiProfile = $profile.name
    provider = $profile.provider
    model = $profile.model
    reasoningEffort = $profile.reasoning_effort
    runRoot = $runRoot
    statePath = (Join-Path $runRoot "workflow-state.json")
    resumable = ([string]$state.status -eq "paused")
}
