[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$BootstrapConfig,
    [Parameter(Mandatory)][object]$ProjectConfig,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$FrameworkRoot,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$ConfigurationHash,
    [string]$AnalysisRunId = "",
    [string]$AnalysisChangeSetPath = "",
    [string]$ReportPath = ""
)

$ErrorActionPreference = "Stop"
if (($BootstrapConfig.PSObject.Properties.Name -contains 'provider') -and $BootstrapConfig.provider -eq 'github') {
    return & (Join-Path $PSScriptRoot 'github/New-GitHubBootstrapChangeSet.ps1') @PSBoundParameters
}
$root = (Resolve-Path $FrameworkRoot).Path
$managedRoot = ([string]$BootstrapConfig.installation.managed_root).Replace("\", "/").Trim("/")
$azureDevOpsAuthEnvironment = [string]$BootstrapConfig.azure_devops.auth_env
# How that credential is sent. The templates hand it to writers that would
# otherwise assume Basic, which silently turns a pipeline access token into a
# sign-in page rather than a refusal anyone can read.
$azureDevOpsAuthScheme = "basic"
if (@(Get-QaFoundryPropertyNames -InputObject $BootstrapConfig.azure_devops) -contains "auth_scheme") {
    $configured = ([string]$BootstrapConfig.azure_devops.auth_scheme).Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($configured)) { $azureDevOpsAuthScheme = $configured }
}
if ($azureDevOpsAuthScheme -notin @("basic", "bearer")) {
    throw ("The installation configures azure_devops.auth_scheme '$azureDevOpsAuthScheme', which " +
        "no writer knows how to send. Use 'basic' for a personal access token or 'bearer' for a " +
        "pipeline access token.")
}
foreach ($configuredAuthEnvironment in @(
    [string]$ProjectConfig.ci.azure_devops.auth_env,
    [string]$ProjectConfig.work_tracking.azure_devops.auth_env,
    [string]$ProjectConfig.delivery.azure_devops.auth_env
)) {
    if ($configuredAuthEnvironment -ne $azureDevOpsAuthEnvironment) {
        throw (
            "Bootstrap and project Azure DevOps providers must use the same configured " +
            "credential environment variable."
        )
    }
}

# One credential is shared by every provider, and a credential can only be sent
# one way. The generated pipelines are rendered from the bootstrap scheme while
# the runtime writers read their own, so a configuration that disagrees does not
# fail: one side encodes a pipeline access token as a password, Azure DevOps
# answers a sign-in page with a 200 on it, and the run reads that as a work item
# that does not exist. Naming the disagreement is the only way it is ever seen.
function Get-ProviderAuthScheme {
    param([Parameter(Mandatory)][object]$Provider)

    if (@(Get-QaFoundryPropertyNames -InputObject $Provider) -contains "auth_scheme") {
        $configured = ([string]$Provider.auth_scheme).Trim().ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($configured)) { return $configured }
    }
    return "basic"
}
foreach ($provider in @(
    @{ name = "ci"; settings = $ProjectConfig.ci.azure_devops },
    @{ name = "work_tracking"; settings = $ProjectConfig.work_tracking.azure_devops },
    @{ name = "delivery"; settings = $ProjectConfig.delivery.azure_devops }
)) {
    $providerScheme = Get-ProviderAuthScheme -Provider $provider.settings
    if ($providerScheme -ne $azureDevOpsAuthScheme) {
        throw (
            "The installation sends '$azureDevOpsAuthEnvironment' as '$azureDevOpsAuthScheme' but " +
            "$($provider.name).azure_devops.auth_scheme is '$providerScheme'. One credential " +
            "cannot be both, and the generated pipelines and the runtime writers would each send " +
            "it their own way. Make every provider that shares this credential agree."
        )
    }
}

# Work items belong to the work-tracking project, which is not always the project
# the pipelines live in. A generated pipeline that asks about a work item through
# its own project gets a 404, which reads as "nothing is there" - the exact
# answer that lets two runs implement one task.
$workItemOrganization = ([string]$ProjectConfig.ci.azure_devops.organization_url).TrimEnd("/")
$workItemProject = [string]$ProjectConfig.ci.azure_devops.project
if ((@(Get-QaFoundryPropertyNames -InputObject $ProjectConfig) -contains "work_tracking") -and
    (@(Get-QaFoundryPropertyNames -InputObject $ProjectConfig.work_tracking) -contains "azure_devops")) {
    $configuredOrganization =
        ([string]$ProjectConfig.work_tracking.azure_devops.organization_url).TrimEnd("/")
    $configuredProject = [string]$ProjectConfig.work_tracking.azure_devops.project
    if (-not [string]::IsNullOrWhiteSpace($configuredOrganization)) {
        $workItemOrganization = $configuredOrganization
    }
    if (-not [string]::IsNullOrWhiteSpace($configuredProject)) { $workItemProject = $configuredProject }
}

function Get-StringHash {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($algorithm.ComputeHash($bytes))).ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function New-DesiredChange {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content,
        [Parameter(Mandatory)][string]$Reason
    )
    $scope = & (Join-Path $PSScriptRoot "Test-RepositoryPathScope.ps1") `
        -Path $Path -Config $ProjectConfig -RepositoryRoot $RepositoryRoot
    $exists = Test-Path -LiteralPath $scope.absolutePath -PathType Leaf
    $expected = if ($exists) {
        (Get-FileHash -LiteralPath $scope.absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    else { "" }
    $contentHash = Get-StringHash -Value $Content
    return [pscustomobject][ordered]@{
        operation = if ($exists) { "update" } else { "create" }
        path = [string]$scope.relativePath
        expectedSha256 = $expected
        content = $Content
        reason = $Reason
        sourceRefs = @("bootstrap:$Path`:$contentHash")
    }
}

$analysisChanges = @()
$analysisWasRehearsed = $false
if (-not [string]::IsNullOrWhiteSpace($AnalysisChangeSetPath)) {
    if (-not (Test-Path -LiteralPath $AnalysisChangeSetPath -PathType Leaf)) {
        throw "Approved analysis change set does not exist: $AnalysisChangeSetPath"
    }
    $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
        -ArtifactPath $AnalysisChangeSetPath `
        -SchemaPath (Join-Path $root "schemas/actions/change-set.schema.json") `
        -SchemaRoot (Join-Path $root "schemas")
    $analysisPlan = Get-Content -LiteralPath $AnalysisChangeSetPath -Raw |
        ConvertFrom-Json -Depth 100 -ErrorAction Stop
    # A rehearsed analysis produced its changes without resolving anything, and
    # the wrapper copies those changes verbatim. Dropping the flag here is what
    # let a rehearsal be delivered as if it had been proved: the wrapper's own
    # change set said nothing about where its contents came from.
    if (@(Get-QaFoundryPropertyNames -InputObject $analysisPlan) -contains "details") {
        $analysisDetails = $analysisPlan.details
        if ($null -ne $analysisDetails -and
            (@(Get-QaFoundryPropertyNames -InputObject $analysisDetails) -contains "dryRun")) {
            $analysisWasRehearsed = [bool]$analysisDetails.dryRun
        }
    }
    $analysisChanges = @($analysisPlan.changes)
    foreach ($change in $analysisChanges) {
        $normalised = ([string]$change.path).Replace("\", "/").TrimStart("/")
        if ($normalised -eq $managedRoot -or $normalised.StartsWith("$managedRoot/")) {
            throw "Agent change set targets reserved bootstrap path: $normalised"
        }
    }
}

$pipelineContents = [ordered]@{}
$managedFiles = [System.Collections.Generic.List[object]]::new()
$pipelinePlan = [System.Collections.Generic.List[object]]::new()
$pipelineIdentities = @{}
$requiredAgentIncludes = [System.Collections.Generic.List[string]]::new()
$targetBranch = ([string]$BootstrapConfig.target.branch).Trim()

# Two configurations name a branch, and they mean the same one: the branch this installation is
# delivered to and watched on, and the branch every later pull request is opened against. When they
# drift, nothing fails - the pipelines are installed on one branch and the work is proposed into
# another, where no pipeline is watching to validate it.
$deliveryBranch = ([string]$ProjectConfig.project.source_branch).Trim()
if ($deliveryBranch -ne $targetBranch) {
    throw (
        "The installation targets branch '$targetBranch' but project.source_branch is " +
        "'$deliveryBranch', so every pull request would be opened against a branch this " +
        "installation does not watch. Make both name the same branch."
    )
}

# The one name an executor pipeline has to know. An executor that fails is the only thing that can
# start triage, and it starts it by name, so the name it uses has to be the name this installation
# registers rather than one an agent remembered.
$triagePipelineName = [string](@($BootstrapConfig.pipelines |
    Where-Object { [string]$_.key -eq "failed-build-triage" } |
    Select-Object -First 1).name)
if ([string]::IsNullOrWhiteSpace($triagePipelineName)) {
    throw "The bootstrap configuration must declare a 'failed-build-triage' pipeline for failures to be handed to."
}

function Convert-BootstrapTemplate {
    param([Parameter(Mandatory)][string]$RelativeTemplatePath)

    $templatePath = [IO.Path]::GetFullPath((Join-Path $root $RelativeTemplatePath))
    if (-not (Test-PathWithinRoot -Candidate $templatePath -Root $root) -or
        -not (Test-Path -LiteralPath $templatePath -PathType Leaf)) {
        throw "Bootstrap pipeline template is missing or outside the framework: $templatePath"
    }
    $content = Get-Content -LiteralPath $templatePath -Raw
    $content = $content.Replace("{{FRAMEWORK_PATH}}", ([string]$BootstrapConfig.framework.path).TrimEnd("/"))
    $content = $content.Replace("{{PROJECT_CONFIG_PATH}}", [string]$BootstrapConfig.framework.project_config_path)
    $content = $content.Replace("{{POLICY_PATH}}", [string]$BootstrapConfig.framework.policy_path)
    $content = $content.Replace("{{AZURE_DEVOPS_AUTH_ENV}}", $azureDevOpsAuthEnvironment)
    $content = $content.Replace("{{AZURE_DEVOPS_AUTH_SCHEME}}", $azureDevOpsAuthScheme)
    $content = $content.Replace("{{WORK_ITEM_ORGANIZATION_URL}}", $workItemOrganization)
    $content = $content.Replace("{{WORK_ITEM_PROJECT}}", $workItemProject)
    $content = $content.Replace("{{TARGET_BRANCH}}", ([string]$BootstrapConfig.target.branch).Trim())
    $content = $content.Replace("{{TRIAGE_PIPELINE_NAME}}", $triagePipelineName)
    # Foundry pushes its own delivery branches. A router that triggers on them
    # reacts to its own work: the branch it just pushed starts another run, which
    # pushes another branch. Excluding the prefix is what keeps the installation
    # from feeding itself.
    $content = $content.Replace("{{DELIVERY_BRANCH_PREFIX}}",
        ([string]$ProjectConfig.delivery.branch_prefix).Replace("\", "/").TrimStart("/"))
    if ($content -match "\{\{[A-Z0-9_]+\}\}") {
        throw "Unresolved bootstrap template token '$($Matches[0])' in $templatePath."
    }
    return $content
}

foreach ($pipeline in @($BootstrapConfig.pipelines)) {
    $content = Convert-BootstrapTemplate -RelativeTemplatePath ([string]$pipeline.template_path)
    $yamlPath = ([string]$pipeline.yaml_path).Replace("\", "/")
    if ($yamlPath -ne $managedRoot -and -not $yamlPath.StartsWith("$managedRoot/")) {
        throw "Managed pipeline path must stay under '$managedRoot': $yamlPath"
    }
    foreach ($identity in @(
        "key:$([string]$pipeline.key)",
        "name:$([string]$pipeline.name)",
        "path:$yamlPath"
    )) {
        if ($pipelineIdentities.ContainsKey($identity)) {
            throw "Duplicate bootstrap pipeline identity: $identity"
        }
        $pipelineIdentities[$identity] = $true
    }
    $null = & (Join-Path $PSScriptRoot "Test-RepositoryPathScope.ps1") `
        -Path $yamlPath -Config $ProjectConfig -RepositoryRoot $RepositoryRoot
    $pipelineContents[$yamlPath] = $content
    $managedFiles.Add([pscustomobject][ordered]@{
        path = $yamlPath
        sha256 = Get-StringHash -Value $content
    })
    $pipelinePlan.Add([pscustomobject][ordered]@{
        key = [string]$pipeline.key
        name = [string]$pipeline.name
        folder = [string]$BootstrapConfig.azure_devops.pipeline_folder
        yamlPath = $yamlPath
        enabled = [bool]$pipeline.enabled
        smoke = [bool]$pipeline.smoke
    })
}

# Steps every executor pipeline includes, owned by the installer rather than by the agents. What an
# executor runs is the agents' decision; what happens when it fails is not - a hand-off written
# freshly each run is a hand-off that can quietly stop working, and a suite whose failures go nowhere
# looks exactly like a suite that passes.
if ((Get-QaFoundryPropertyNames -InputObject $BootstrapConfig) -contains "shared_templates") {
    foreach ($shared in @($BootstrapConfig.shared_templates)) {
        $sharedContent = Convert-BootstrapTemplate -RelativeTemplatePath ([string]$shared.template_path)
        $sharedPath = ([string]$shared.yaml_path).Replace("\", "/")
        if ($sharedPath -ne $managedRoot -and -not $sharedPath.StartsWith("$managedRoot/")) {
            throw "Managed template path must stay under '$managedRoot': $sharedPath"
        }
        if ($pipelineIdentities.ContainsKey("path:$sharedPath")) {
            throw "Duplicate bootstrap managed path: $sharedPath"
        }
        $pipelineIdentities["path:$sharedPath"] = $true
        $null = & (Join-Path $PSScriptRoot "Test-RepositoryPathScope.ps1") `
            -Path $sharedPath -Config $ProjectConfig -RepositoryRoot $RepositoryRoot
        $pipelineContents[$sharedPath] = $sharedContent
        $managedFiles.Add([pscustomobject][ordered]@{
            path = $sharedPath
            sha256 = Get-StringHash -Value $sharedContent
        })
        if ((Get-QaFoundryPropertyNames -InputObject $shared) -contains "required_in_agent_pipelines" -and
            [bool]$shared.required_in_agent_pipelines) {
            $requiredAgentIncludes.Add("/$sharedPath")
        }
    }
}

# The automation pipeline is written by the agents rather than by a template
# here, and rightly so: how many test projects exist and what runs them is their
# decision, not the installer's. But a YAML file in a repository is not a
# pipeline. Until something registers it, its triggers are inert and the file
# only looks like automation. So whatever the approved change set placed under
# the agent pipeline prefix is registered beside the managed ones - registered,
# not owned: its contents stay out of managedFiles, because the agents author it
# and the installer has no business overwriting it later.
if ($BootstrapConfig.PSObject.Properties.Name -contains "agent_pipelines" -and
    $null -ne $BootstrapConfig.agent_pipelines -and
    [bool]$BootstrapConfig.agent_pipelines.register_from_change_set) {
    $agentPipelineSettings = $BootstrapConfig.agent_pipelines
    $agentPrefix = ([string]$agentPipelineSettings.path_prefix).Replace("\", "/").Trim("/")
    if ($agentPrefix -eq "") {
        throw "agent_pipelines.path_prefix must name a directory the agents may write to."
    }
    $agentPrefix += "/"
    $agentNamePrefix = [string]$agentPipelineSettings.name_prefix
    foreach ($change in $analysisChanges) {
        if ([string]$change.operation -eq "delete") { continue }
        $candidate = ([string]$change.path).Replace("\", "/").TrimStart("/")
        if (-not $candidate.StartsWith($agentPrefix, [StringComparison]::Ordinal)) { continue }
        if (-not ($candidate.EndsWith(".yml", [StringComparison]::OrdinalIgnoreCase) -or
            $candidate.EndsWith(".yaml", [StringComparison]::OrdinalIgnoreCase))) { continue }
        $leaf = [IO.Path]::GetFileNameWithoutExtension($candidate)
        if ([string]::IsNullOrWhiteSpace($leaf)) { continue }
        # Named after where the file sits, not just what it is called. Two agent
        # pipelines can perfectly reasonably both be called ci.yml in different
        # directories, and naming them after the leaf alone made the second one
        # a duplicate of the first: it was dropped without a word, and a
        # pipeline the reviewers approved simply never existed.
        $relative = $candidate.Substring($agentPrefix.Length)
        $relative = [IO.Path]::ChangeExtension($relative, $null).TrimEnd(".")
        $slug = ($relative -replace "[\\/]+", "-").Trim("-")
        if ([string]::IsNullOrWhiteSpace($slug)) { $slug = $leaf }
        $agentKey = "agent-$slug"
        $agentName = "$agentNamePrefix$slug"
        if ($pipelineIdentities.ContainsKey("path:$candidate")) { continue }
        foreach ($identity in @("key:$agentKey", "name:$agentName")) {
            if ($pipelineIdentities.ContainsKey($identity)) {
                throw ("The approved change set asks for an agent pipeline at '$candidate', but " +
                    "'$($identity.Split(':', 2)[0])' '$($identity.Split(':', 2)[1])' is already " +
                    "taken by another pipeline in this installation. Registering it would either " +
                    "overwrite that one or silently drop this one, so neither is done. Give the " +
                    "pipeline file a distinct path under '$agentPrefix'.")
            }
        }
        foreach ($identity in @("key:$agentKey", "name:$agentName", "path:$candidate")) {
            $pipelineIdentities[$identity] = $true
        }
        $null = & (Join-Path $PSScriptRoot "Test-RepositoryPathScope.ps1") `
            -Path $candidate -Config $ProjectConfig -RepositoryRoot $RepositoryRoot

        # A pipeline file is only automation if something starts it and something hears it fail.
        # Both are invisible in a review of the YAML - a trigger on a branch that does not exist and
        # a missing hand-off both look exactly like a working file - so they are checked here, while
        # the installation can still be stopped, rather than discovered as silence.
        $body = if ((Get-QaFoundryPropertyNames -InputObject $change) -contains "content") {
            [string]$change.content
        }
        else { "" }
        $pipelineProblems = @(& (Join-Path $PSScriptRoot "Test-AgentPipelineDefinition.ps1") `
            -Path $candidate -Content $body -TargetBranch $targetBranch `
            -RequiredIncludes @($requiredAgentIncludes) -FrameworkRoot $FrameworkRoot)
        if ($pipelineProblems.Count -gt 0) {
            throw ($pipelineProblems -join " ")
        }
        $pipelinePlan.Add([pscustomobject][ordered]@{
            key = $agentKey
            name = $agentName
            folder = [string]$BootstrapConfig.azure_devops.pipeline_folder
            yamlPath = $candidate
            enabled = $true
            # Never smoke-run an agent-authored pipeline during installation: it
            # executes tests against a real environment, and installation is not
            # the moment to discover that.
            smoke = $false
        })
    }

    $required = if ((Get-QaFoundryPropertyNames -InputObject $agentPipelineSettings) -contains
        "require_at_least") {
        [int]$agentPipelineSettings.require_at_least
    }
    else { 0 }
    $registered = @($pipelinePlan | Where-Object { ([string]$_.key).StartsWith("agent-") }).Count
    if ($registered -lt $required) {
        throw (
            "The approved change set contains $registered pipeline file(s) under '$agentPrefix' and " +
            "this installation requires at least $required. A test suite nothing ever runs is " +
            "indistinguishable from a suite that passes, so the installation is not delivered " +
            "without the pipeline that runs it."
        )
    }
}

$installationId = "install-$($ConfigurationHash.Substring(0, 12))"
$plan = [pscustomobject][ordered]@{
    schemaVersion = 1
    installationId = $installationId
    createdAt = [DateTime]::UtcNow.ToString("o")
    targetBranch = [string]$BootstrapConfig.target.branch
    configurationHash = $ConfigurationHash
    analysisRunId = $AnalysisRunId
    managedFiles = @($managedFiles)
    pipelines = @($pipelinePlan)
}
$planJson = $plan | ConvertTo-Json -Depth 100
$planHash = Get-StringHash -Value $planJson
$state = [pscustomobject][ordered]@{
    schemaVersion = 1
    installationId = $installationId
    status = "awaiting_merge"
    updatedAt = [DateTime]::UtcNow.ToString("o")
    targetBranch = [string]$BootstrapConfig.target.branch
    planHash = $planHash
    configurationHash = $ConfigurationHash
    commitSha = ""
    pipelines = @()
    evidence = @("The installation becomes active only after this plan is merged into the target branch.")
}
$stateJson = $state | ConvertTo-Json -Depth 100

New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
$planArtifactPath = Join-Path $RunRoot "installation-plan.json"
$stateArtifactPath = Join-Path $RunRoot "installation-state.json"
$planJson | Set-Content -LiteralPath $planArtifactPath -Encoding utf8 -NoNewline
$stateJson | Set-Content -LiteralPath $stateArtifactPath -Encoding utf8 -NoNewline
$null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
    -ArtifactPath $planArtifactPath `
    -SchemaPath (Join-Path $root "schemas/bootstrap/installation-plan.schema.json") `
    -SchemaRoot (Join-Path $root "schemas")
$null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
    -ArtifactPath $stateArtifactPath `
    -SchemaPath (Join-Path $root "schemas/bootstrap/installation-state.schema.json") `
    -SchemaRoot (Join-Path $root "schemas")

$changes = [System.Collections.Generic.List[object]]::new()
foreach ($change in $analysisChanges) { $changes.Add($change) }
if ($ReportPath) {
    $changes.Add((New-DesiredChange -Path 'foundry-report.html' `
        -Content (Get-Content -LiteralPath $ReportPath -Raw) `
        -Reason 'Publish the evidence-based, interactive automation report.'))
}
foreach ($entry in $pipelineContents.GetEnumerator()) {
    $changes.Add((New-DesiredChange -Path ([string]$entry.Key) `
        -Content ([string]$entry.Value) -Reason "Install managed Azure DevOps pipeline YAML."))
}
$changes.Add((New-DesiredChange -Path "$managedRoot/installation-plan.json" `
    -Content $planJson -Reason "Persist the human-reviewable installation plan."))
$changes.Add((New-DesiredChange -Path "$managedRoot/installation-state.json" `
    -Content $stateJson -Reason "Mark the installation as awaiting merge and finalization."))

$changeSet = [pscustomobject][ordered]@{
    agentId = "bootstrap-installer"
    stageId = "bootstrap-installation-plan"
    runId = $RunId
    status = "completed"
    summary = "Combine the unanimously reviewed automation changes with deterministic Azure DevOps assets."
    evidence = @(
        [pscustomobject][ordered]@{
            source = $planArtifactPath
            description = "Deterministic Azure DevOps installation plan."
        },
        [pscustomobject][ordered]@{
            source = $stateArtifactPath
            description = "Pre-merge installation state."
        }
    ) + $(if (-not [string]::IsNullOrWhiteSpace($AnalysisChangeSetPath)) {
        @([pscustomobject][ordered]@{
            source = $AnalysisChangeSetPath
            description = "Unanimously reviewed agent change set."
        })
    } else { @() })
    assumptions = @()
    unknowns = @()
    warnings = @("Automatic merge and production deployment remain prohibited.")
    details = [pscustomobject][ordered]@{
        analysisRunId = $AnalysisRunId
        managedRoot = $managedRoot
        dryRun = $analysisWasRehearsed
    }
    outcome = if ($changes.Count -gt 0) { "proposed" } else { "no_action_needed" }
    changes = @($changes)
}
$changeSetPath = Join-Path $RunRoot "change-set.json"
$changeSet | ConvertTo-Json -Depth 100 |
    Set-Content -LiteralPath $changeSetPath -Encoding utf8
$null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
    -ArtifactPath $changeSetPath `
    -SchemaPath (Join-Path $root "schemas/actions/change-set.schema.json") `
    -SchemaRoot (Join-Path $root "schemas")

return [pscustomobject][ordered]@{
    installationId = $installationId
    planHash = $planHash
    planPath = $planArtifactPath
    statePath = $stateArtifactPath
    changeSetPath = $changeSetPath
    changeCount = $changes.Count
}
