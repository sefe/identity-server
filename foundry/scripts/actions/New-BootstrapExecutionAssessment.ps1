[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$Workflow,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [switch]$DeferExecution
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../Common.ps1')
. (Join-Path $PSScriptRoot '../CompletionStatus.ps1')
$root = Get-QaFoundryRoot

# Bootstrap's implementation artifacts are file contracts. Executing their
# commands against the product checkout tests missing files, not the future suite.
# Assess that phase deterministically; actual execution remains a blocking gate
# over the materialized change set in its isolated verification workspace.
if ($Workflow.name -ne 'bootstrap-automation') { throw 'This assessment applies only to bootstrap automation.' }
$ids = @($Workflow.stages | ForEach-Object { [string]$_.id })
$sequence = @('implementation','execution','bootstrap-change-generation','bootstrap-change-materialization','framework-verification','bootstrap-change-review')
$previous = -1
foreach ($id in $sequence) {
    $index = [Array]::IndexOf($ids, $id)
    if ($index -le $previous) { throw 'Bootstrap assessment requires generation, materialization and verification before final change review.' }
    $previous = $index
}
$gate = @($Workflow.stages | Where-Object id -EQ 'framework-verification')[0]
if ($gate.type -ne 'deterministic_action' -or $gate.action.handler -ne 'verify_framework' -or
    $gate.approval.on_exhaustion -ne 'block' -or
    $gate.action.inputs.changeSet.stage -ne 'bootstrap-change-materialization' -or
    $gate.action.inputs.changeSet.artifact -ne 'change-set.json') {
    throw 'Bootstrap assessment requires a blocking verification gate over the materialized change set.'
}
$inputs = Resolve-QaFoundryDeclaredInputs -RunRoot $RunRoot -StageId execution -RunId $RunId -Inputs ([pscustomobject]@{
    frameworkInventory = [pscustomobject]@{stage='implementation';artifact='framework-implementation.json';schema='schemas/implementation/implementation-result.schema.json'}
    testInventory = [pscustomobject]@{stage='implementation';artifact='test-implementation.json';schema='schemas/implementation/implementation-result.schema.json'}
})
$evidence = @()
$plannedFiles = @()
$plannedCommands = @()
foreach ($inputName in @('frameworkInventory','testInventory')) {
    $inputRecord = $inputs[$inputName]
    if (@(Get-QaFoundryArtifactDeferrals -PublishedPath $inputRecord.path).Count -gt 0) {
        throw 'Bootstrap execution assessment cannot accept an unfinished implementation inventory.'
    }
    $inventory = Get-Content -LiteralPath $inputRecord.path -Raw | ConvertFrom-Json -Depth 100
    $plannedFiles += @($inventory.plannedFiles | ForEach-Object { [string]$_.path })
    $plannedCommands += @($inventory.commandsProposed)
    $evidence += @{source=$inputRecord.relativePath;description="Accepted file contracts from implementation; SHA-256 $($inputRecord.sha256). These are specifications, not executed code."}
}
$warning = 'No generated automation was compiled or tested at this stage. This assessment is not passing test, dependency-audit or product-behaviour evidence.'
if ($DeferExecution) { $warning += ' Bootstrap generation only: execution is deferred until after delivery and environment configuration.' }
$details = @{phase='before_materialization';executionPerformed=$false;requiredVerificationStage='framework-verification';
    plannedFiles=@($plannedFiles | Sort-Object -Unique);commandsAwaitingMaterialization=@($plannedCommands)}
$documents = @(
    @{name='execution-plan.json';schema='schemas/execution/execution-plan.schema.json';body=@{
        agentId='execution';stageId='execution';runId=$RunId;status='completed';
        summary='Deterministic bootstrap assessment: file contracts are ready for generation; no generated-suite commands can execute in the product checkout.';
        evidence=$evidence;assumptions=@();unknowns=@();warnings=@($warning);details=$details;commands=@();deferrals=@()
    }},
    @{name='execution-result.json';schema='schemas/execution/execution-result.schema.json';body=@{
        runId=$RunId;stageId='execution';status='completed';commands=@()
    }},
    @{name='failure-analysis.json';schema='schemas/execution/failure-analysis.schema.json';body=@{
        agentId='failure-analysis';stageId='execution';runId=$RunId;status='completed';
        summary=$(if ($DeferExecution) {'No commands executed. Tests and execution probes are deferred until after delivery; there are no observed test failures to classify.'} else {'No commands executed in this assessment, so there are no observed build or test failures to classify. Mandatory framework verification follows materialization.'});
        evidence=@(@{source='execution-result.json';description='The current assessment records zero executed commands.'});
        assumptions=@();unknowns=@();warnings=@($warning);details=$details;failures=@();deferrals=@()
    }}
)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$paths = @()
foreach ($document in $documents) {
    $path = Join-Path $OutputDirectory $document.name
    $document.body | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding utf8
    $null = & (Join-Path $root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath $path `
        -SchemaPath (Join-Path $root $document.schema) -SchemaRoot (Join-Path $root 'schemas')
    $paths += $path
}
return [pscustomobject]@{Artifacts=$paths;Inputs=@($inputs.Values)}
