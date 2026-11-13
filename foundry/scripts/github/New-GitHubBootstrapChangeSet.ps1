[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$BootstrapConfig,[Parameter(Mandatory)][object]$ProjectConfig,
    [Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$FrameworkRoot,
    [Parameter(Mandatory)][string]$RunRoot,[Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$ConfigurationHash,[string]$AnalysisRunId='',
    [string]$AnalysisChangeSetPath='',[string]$ReportPath=''
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../Common.ps1')
$root=$FrameworkRoot
$managedRoot=[string]$BootstrapConfig.installation.managed_root
if ($managedRoot -ne '.foundry') {throw 'GitHub installation metadata must use .foundry.'}
if ($BootstrapConfig.target.branch -cne $ProjectConfig.project.source_branch) {throw 'Bootstrap and delivery target branches differ.'}
if ($BootstrapConfig.github.repository -cne $ProjectConfig.delivery.github.repository) {throw 'Bootstrap and delivery GitHub repositories differ.'}
if ($BootstrapConfig.github.runtime_ref -notmatch '^[a-f0-9]{40}$') {throw 'Pin the Foundry runtime to a complete commit SHA.'}
if ($BootstrapConfig.github.runtime_repository -ine $BootstrapConfig.github.repository) {throw 'Embedded Foundry must be pinned within the product repository.'}

function Get-StringHash {
    param([AllowEmptyString()][string]$Value)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}
function New-DesiredChange {
    param([string]$Path,[AllowEmptyString()][string]$Content,[string]$Reason)
    $scope=& (Join-Path $root 'scripts/Test-RepositoryPathScope.ps1') -Path $Path -Config $ProjectConfig -RepositoryRoot $RepositoryRoot
    $exists=Test-Path -LiteralPath $scope.absolutePath -PathType Leaf
    return [pscustomobject]@{operation=$(if ($exists){'update'}else{'create'});path=$Path;content=$Content;reason=$Reason
        expectedSha256=$(if ($exists){(Get-FileHash -LiteralPath $scope.absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()}else{''})
        sourceRefs=@("bootstrap:$Path")}
}
$analysisChanges=@();$analysisWasRehearsed=$false
if ($AnalysisChangeSetPath) {
    $null=& (Join-Path $root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath $AnalysisChangeSetPath -SchemaPath (Join-Path $root 'schemas/actions/change-set.schema.json') -SchemaRoot (Join-Path $root 'schemas')
    $analysisPlan=Get-Content -LiteralPath $AnalysisChangeSetPath -Raw | ConvertFrom-Json -Depth 100
    if ($analysisPlan.status -ne 'completed' -or $analysisPlan.outcome -ne 'proposed') {throw 'Bootstrap requires a completed proposed change set.'}
    $analysisChanges=@($analysisPlan.changes)
    if ($analysisPlan.PSObject.Properties.Name -contains 'details' -and $analysisPlan.details.PSObject.Properties.Name -contains 'dryRun') {$analysisWasRehearsed=[bool]$analysisPlan.details.dryRun}
}
$pipelineContents=[ordered]@{}
$managedFiles=[Collections.Generic.List[object]]::new()
$pipelinePlan=[Collections.Generic.List[object]]::new()
$reserved=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$null=$reserved.Add('.github/workflows/foundry-bootstrap.yml')
$null=$reserved.Add('.github/workflows/foundry-validate.yml')
$workflowNames=@($analysisChanges | Where-Object { $_.path -match '^\.github/workflows/[^/]+\.ya?ml$' -and $_.operation -ne 'delete' } | ForEach-Object {
    $workflow=ConvertFrom-QaFoundryYamlText -Text $_.content -Root $root
    if (@(Get-QaFoundryPropertyNames $workflow) -notcontains 'name' -or [string]::IsNullOrWhiteSpace([string]$workflow.name)) {throw 'Each automation workflow needs a stable name for failure triage.'}
    [string]$workflow.name | ConvertTo-Json -Compress
})
foreach ($pipeline in @($BootstrapConfig.pipelines | Where-Object enabled)) {
    $template=Resolve-QaFoundryPath -Root $root -Path $pipeline.template_path
    if (-not (Test-PathWithinRoot -Candidate $template -Root $root)) {throw 'Template escapes Foundry root.'}
    $content=Get-Content -LiteralPath $template -Raw
    $replacements=@{
        '{{RUNTIME_REPOSITORY}}'=[string]$BootstrapConfig.github.runtime_repository
        '{{RUNTIME_REF}}'=[string]$BootstrapConfig.github.runtime_ref
        '{{TARGET_BRANCH}}'=[string]$BootstrapConfig.target.branch
        '{{AUTOMATION_WORKFLOW_NAMES}}'=($workflowNames -join ', ')
    }
    foreach ($key in $replacements.Keys) {$content=$content.Replace($key,$replacements[$key])}
    $path=[string]$pipeline.yaml_path
    if ($path -notmatch '^\.github/workflows/[^/]+\.ya?ml$' -or -not $reserved.Add($path)) {throw "Invalid or duplicate managed workflow: $path"}
    $pipelineContents[$path]=$content
    $managedFiles.Add([pscustomobject]@{path=$path;sha256=(Get-StringHash $content)})
    $pipelinePlan.Add([pscustomobject]@{key=$pipeline.key;name=$pipeline.name;folder='.github/workflows';yamlPath=$path;enabled=$true;smoke=$false})
}
# Persist only configuration, never credentials or the transient runtime checkout.
foreach ($configPath in @('.foundry/project.json','.foundry/bootstrap.json')) {
    $sourceName=if ($configPath -eq '.foundry/project.json') {'github-project.json'} else {'github-bootstrap.json'}
    $absolute=Join-Path $RepositoryRoot ".qa-foundry-artifacts/$sourceName"
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {throw "Prepared configuration missing: $configPath"}
    $pipelineContents[$configPath]=Get-Content -LiteralPath $absolute -Raw
    $managedFiles.Add([pscustomobject]@{path=$configPath;sha256=(Get-StringHash $pipelineContents[$configPath])})
}
$agentWorkflowCount=0
foreach ($change in $analysisChanges) {
    $path=([string]$change.path).Replace('\','/')
    if ($path.StartsWith('.foundry/',[StringComparison]::OrdinalIgnoreCase) -or $reserved.Contains($path)) {throw "Agent targets installer-owned path: $path"}
    if ($path -match '^\.github/workflows/') {
        if ($change.operation -eq 'delete') {throw 'Bootstrap cannot delete automation workflows.'}
        $errors=@(& (Join-Path $PSScriptRoot 'Test-GitHubWorkflow.ps1') -Path $path -Content $change.content -TargetBranch $BootstrapConfig.target.branch -FrameworkRoot $root `
            -DeferredTests:(Test-QaFoundryDeferredVerification -Config $ProjectConfig))
        if ($errors.Count) {throw ($errors -join ' ')}
        $agentWorkflowCount++
        $pipelinePlan.Add([pscustomobject]@{key="agent-$agentWorkflowCount";name=[IO.Path]::GetFileNameWithoutExtension($path);folder='.github/workflows';yamlPath=$path;enabled=$true;smoke=$false})
        $managedFiles.Add([pscustomobject]@{path=$path;sha256=(Get-StringHash $change.content)})
    }
}
if ($agentWorkflowCount -lt [int]$BootstrapConfig.agent_pipelines.require_at_least) {throw 'Bootstrap requires at least two executable GitHub Actions workflows for the generated API and UI projects.'}
$installationId="install-$($ConfigurationHash.Substring(0,12))"
$plan=[pscustomobject]@{schemaVersion=1;installationId=$installationId;createdAt=[DateTime]::UtcNow.ToString('o');targetBranch=$BootstrapConfig.target.branch;configurationHash=$ConfigurationHash;analysisRunId=$AnalysisRunId;managedFiles=@($managedFiles);pipelines=@($pipelinePlan)}
$planJson=$plan | ConvertTo-Json -Depth 100
$planHash=Get-StringHash $planJson
$state=[pscustomobject]@{schemaVersion=1;installationId=$installationId;status='awaiting_merge';updatedAt=[DateTime]::UtcNow.ToString('o');targetBranch=$BootstrapConfig.target.branch;planHash=$planHash;configurationHash=$ConfigurationHash;commitSha='';pipelines=@();evidence=@('GitHub discovers workflows after the reviewed PR is merged. No Azure registration is needed.')}
$stateJson=$state | ConvertTo-Json -Depth 100
New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
$planArtifactPath=Join-Path $RunRoot 'installation-plan.json';$stateArtifactPath=Join-Path $RunRoot 'installation-state.json'
[IO.File]::WriteAllText($planArtifactPath,$planJson);[IO.File]::WriteAllText($stateArtifactPath,$stateJson)
$changes=[Collections.Generic.List[object]]::new()
foreach ($change in $analysisChanges) {$changes.Add($change)}
if ($ReportPath) {$changes.Add((New-DesiredChange -Path 'foundry-report.html' -Content (Get-Content -LiteralPath $ReportPath -Raw) -Reason 'Publish test evidence, work summary and estimated AI budget.'))}
foreach ($entry in $pipelineContents.GetEnumerator()) {$changes.Add((New-DesiredChange -Path $entry.Key -Content $entry.Value -Reason 'Install GitHub Actions workflows and portable configuration.'))}
$changes.Add((New-DesiredChange -Path '.foundry/installation-plan.json' -Content $planJson -Reason 'Record reviewed installation hashes.'))
$changes.Add((New-DesiredChange -Path '.foundry/installation-state.json' -Content $stateJson -Reason 'Mark installation awaiting merge.'))
$changeSet=[pscustomobject]@{agentId='bootstrap-installer';stageId='bootstrap-installation-plan';runId=$RunId;status='completed';summary='Reviewed automation with GitHub Actions delivery.';evidence=@(@{source=$planArtifactPath;description='Deterministic GitHub installation plan.'});assumptions=@();unknowns=@();warnings=@('Human merge required.');details=@{analysisRunId=$AnalysisRunId;managedRoot=$managedRoot;dryRun=$analysisWasRehearsed};outcome='proposed';changes=@($changes)}
$changeSetPath=Join-Path $RunRoot 'change-set.json'
$changeSet | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $changeSetPath -Encoding utf8
foreach ($pair in @(@($planArtifactPath,'bootstrap/installation-plan'),@($stateArtifactPath,'bootstrap/installation-state'),@($changeSetPath,'actions/change-set'))) {
    $null=& (Join-Path $root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath $pair[0] -SchemaPath (Join-Path $root "schemas/$($pair[1]).schema.json") -SchemaRoot (Join-Path $root 'schemas')
}
return [pscustomobject]@{installationId=$installationId;planHash=$planHash;planPath=$planArtifactPath;statePath=$stateArtifactPath;changeSetPath=$changeSetPath;changeCount=$changes.Count}
