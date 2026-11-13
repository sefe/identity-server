[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][object]$Workflow,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [object]$EventContext = $null,
    [object]$AiProfile = $null,
    [string[]]$CollaborationProfileNames = @(),
    [string[]]$DocumentationPaths = @(),
    [string[]]$RequirementsPaths = @(),
    [string[]]$ArchitecturePaths = @(),
    [string[]]$AdditionalContextPaths = @(),
    [string]$SecretsSource = "none",
    [string[]]$MappedEnvironmentNames = @(),
    [string[]]$ModelEnvironmentNames = @()
)

# The one description of what a run was configured to do. Deterministic stages
# check their work against it rather than against whatever the process that
# started them happens to remember, so it is built in one place and used by
# every caller that needs a run to exist.
. (Join-Path $PSScriptRoot "Common.ps1")
$root = Get-QaFoundryRoot

$resolvedProfile = if ($null -ne $AiProfile) {
    $AiProfile
}
else {
    & (Join-Path $PSScriptRoot "Resolve-AiProfile.ps1") `
        -Config $Config `
        -ProfileName ([string]$Config.ai.active_profile)
}
$resolvedEvent = if ($null -ne $EventContext) {
    $EventContext
}
else {
    [pscustomobject]@{ eventId = $RunId; type = "manual"; source = "local" }
}

$runConfigurationPath = Join-Path $RunRoot "context/run-configuration.json"
New-Item -ItemType Directory -Path (Split-Path $runConfigurationPath -Parent) -Force | Out-Null
[ordered]@{
    runId = $RunId
    projectName = [string]$Config.project.name
    targetRepository = $RepositoryRoot
    workflow = [ordered]@{
        name = [string]$Workflow.name
        version = [int]$Workflow.version
    }
    event = [ordered]@{
        id = [string]$resolvedEvent.eventId
        type = [string]$resolvedEvent.type
        source = [string]$resolvedEvent.source
    }
    assurance = [ordered]@{
        mode = [string]$Config.assurance.mode
        minimumSpecialists = [int]$Config.assurance.minimum_specialists
        highRiskMinimumSpecialists = [int]$Config.assurance.high_risk_minimum_specialists
        minimumReviewers = [int]$Config.assurance.minimum_reviewers
        highRiskMinimumReviewers = [int]$Config.assurance.high_risk_minimum_reviewers
        unanimousReviewsRequired = [bool]$Config.assurance.require_unanimous_reviews
        deterministicEvidenceRequired = [bool]$Config.assurance.require_deterministic_evidence
    }
    inputs = [ordered]@{
        documentation = @($DocumentationPaths)
        requirements = @($RequirementsPaths)
        architecture = @($ArchitecturePaths)
        additionalContext = @($AdditionalContextPaths)
    }
    ai = [ordered]@{
        profile = [string]$resolvedProfile.name
        provider = [string]$resolvedProfile.provider
        model = [string]$resolvedProfile.model
        reasoningEffort = [string]$resolvedProfile.reasoning_effort
        collaborationProfiles = @($CollaborationProfileNames)
    }
    secrets = [ordered]@{
        source = $SecretsSource
        mappedEnvironmentNames = @($MappedEnvironmentNames)
        modelEnvironmentNames = @($ModelEnvironmentNames)
    }
    delivery = [ordered]@{
        provider = [string]$Config.delivery.provider
        dryRun = [bool]$Config.delivery.dry_run
        applyChanges = [bool]$Config.delivery.apply_changes
        createBranch = [bool]$Config.delivery.create_branch
        commitChanges = [bool]$Config.delivery.commit_changes
        pushBranch = [bool]$Config.delivery.push_branch
        createDraftPullRequest = [bool]$Config.delivery.create_draft_pull_request
    }
    workTracking = [ordered]@{
        provider = [string]$Config.work_tracking.provider
        enabled = [bool]$Config.work_tracking.enabled
        dryRun = [bool]$Config.work_tracking.dry_run
    }
    automation = [ordered]@{
        ecosystems = @(Resolve-QaFoundryAutomationEcosystems -Automation $Config.automation)
        packagePolicy = Resolve-QaFoundryPackagePolicy -Automation $Config.automation
    }
} | ConvertTo-Json -Depth 30 |
    Set-Content -Path $runConfigurationPath -Encoding utf8
$null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
    -ArtifactPath $runConfigurationPath `
    -SchemaPath (Join-Path $root "schemas/runtime/run-configuration.schema.json") `
    -SchemaRoot (Join-Path $root "schemas")
return $runConfigurationPath
