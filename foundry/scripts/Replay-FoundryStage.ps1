[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$StageId,
    [string]$ConfigPath = '', [string]$WorkflowPath = '', [string]$PolicyPath = ''
)
# Local reproduction only. It cannot invoke an agent, edit the product, push a
# branch, create a PR or change the original run's status.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$framework = Get-QaFoundryRoot
if (-not $ConfigPath) { $ConfigPath = Join-Path $framework 'config/project.yaml' }
if (-not $WorkflowPath) { $WorkflowPath = Join-Path $framework 'workflows/bootstrap-automation.yaml' }
if (-not $PolicyPath) { $PolicyPath = Join-Path $framework 'policies/bootstrap-policy.yaml' }
$config = Import-QaFoundryYaml -Path $ConfigPath -Root $framework
$workflow = Import-QaFoundryYaml -Path $WorkflowPath -Root $framework
$workflow.stages = @(& (Join-Path $PSScriptRoot 'Resolve-WorkflowStages.ps1') -Workflow $workflow)
$policy = Import-QaFoundryYaml -Path $PolicyPath -Root $framework
$stage = @($workflow.stages | Where-Object id -EQ $StageId)
if ($stage.Count -ne 1 -or $stage[0].type -ne 'deterministic_action' -or
    $stage[0].action.handler -notin @('materialize_change_set', 'verify_framework')) {
    throw 'Replay supports only materialization and framework verification, which run in Automation scratch directories.'
}
$RunRoot = (Resolve-Path -LiteralPath $RunRoot).Path
$state = & (Join-Path $PSScriptRoot 'Load-WorkflowState.ps1') -Path (Join-Path $RunRoot 'workflow-state.json')
$repository = Resolve-QaFoundryPath -Root (Split-Path ([IO.Path]::GetFullPath($ConfigPath, (Get-Location).ProviderPath)) -Parent) `
    -Path ([string]$config.target.repository_path)
$replayRoot = Join-Path (Split-Path $RunRoot -Parent) ('replay-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $replayRoot | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $RunRoot -File -Recurse) {
    $relative = [IO.Path]::GetRelativePath($RunRoot, $file.FullName)
    if ($relative.Replace('\','/').StartsWith('recovery/')) { continue }
    $destination = Join-Path $replayRoot $relative
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination
}
$savedStage = @($state.stages | Where-Object id -EQ $StageId)
$iteration = if ($savedStage.Count) { [int]$savedStage[0].iteration + 1 } else { 1 }
$result = & (Join-Path $PSScriptRoot 'Invoke-Stage.ps1') -Stage $stage[0] -Config $config -Policy $policy `
    -RunRoot $replayRoot -RepositoryRoot $repository -RunId ([string]$state.runId) -Iteration $iteration
[pscustomobject]@{
    status = $result.Status; stage = $StageId; evidenceRoot = $replayRoot
    originalRunRoot = $RunRoot; originalStateChanged = $false
    note = 'Diagnostic replay of saved inputs. This does not certify source compatibility or complete the original workflow.'
}
