[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Reason,
    [Parameter(Mandatory)][string[]]$AllowedDecisions,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunId,
    [int]$Iteration = 1,
    [hashtable]$ProviderEnvironment = @{},
    [string]$RepositoryRoot = ""
)

. (Join-Path $PSScriptRoot "Common.ps1")
. (Join-Path $PSScriptRoot 'RunInputs.ps1')
$root = Get-QaFoundryRoot
$statePath = Join-Path $RunRoot workflow-state.json
$state = Get-Content $statePath -Raw | ConvertFrom-Json -Depth 100
$identity = [ordered]@{
    runId = $RunId; iteration = $Iteration; reason = $Reason; allowedDecisions = @($AllowedDecisions)
    currentStage = $state.currentStage; stages = @($state.stages)
}
$signature = Get-QaFoundryInputHash -Text (ConvertTo-Json $identity -Depth 100 -Compress)
$supervisorDirectory = Join-Path $RunRoot "supervisor/$signature"
New-Item -ItemType Directory -Path $supervisorDirectory -Force | Out-Null
$snapshotPath = Join-Path $supervisorDirectory workflow-snapshot.json
if (-not (Test-Path -LiteralPath $snapshotPath)) { Copy-Item -LiteralPath $statePath -Destination $snapshotPath }
$contextPath = Join-Path $supervisorDirectory "escalation-$Iteration.json"
[ordered]@{
    reason = $Reason
    allowedDecisions = $AllowedDecisions
    statePath = $snapshotPath
} | ConvertTo-Json -Depth 10 | Set-Content -Path $contextPath -Encoding utf8

$outputPath = Join-Path $supervisorDirectory "supervisor-decision-$Iteration.json"
$result = & (Join-Path $PSScriptRoot "Invoke-Agent.ps1") `
    -AgentId "supervisor" `
    -StageId "supervisor" `
    -RunId $RunId `
    -PromptPath (Join-Path $root "prompts/supervisor/supervisor.md") `
    -ContextPaths @($contextPath, $snapshotPath) `
    -OutputPath $outputPath `
    -SchemaPath (Join-Path $root "schemas/supervisor/supervisor-decision.schema.json") `
    -Config $Config `
    -StageIteration $Iteration `
    -ProviderEnvironment $ProviderEnvironment `
    -RepositoryRoot $RepositoryRoot `
    -AllowExistingArtifact

if ([string]$result.recommendation -notin $AllowedDecisions) {
    throw "Unsafe supervisor recommendation rejected: $($result.recommendation)"
}
return $result
