[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DecisionPath,
    [Parameter(Mandatory)][string[]]$SourcePaths,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../Common.ps1')
$root = Get-QaFoundryRoot
$null = & (Join-Path $root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath $DecisionPath `
    -SchemaPath (Join-Path $root 'schemas/discovery/discovery-decision.schema.json') -SchemaRoot (Join-Path $root 'schemas')
$decision = Get-Content -LiteralPath $DecisionPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100
if ($decision.runId -cne $RunId) { throw 'Discovery decision belongs to another run.' }
$sources = [System.Collections.Generic.List[object]]::new()
$repository = $null
foreach ($path in $SourcePaths) {
    if (-not (Test-PathWithinRoot -Candidate $path -Root $RunRoot)) { throw 'Discovery source escapes its run.' }
    $document = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    if ($document.runId -cne $RunId -or $document.stageId -cne 'discovery') { throw 'Discovery source identity does not match this run and stage.' }
    if ($document.status -ne 'completed') { throw 'Cannot compose discovery from an incomplete source.' }
    if ($document.agentId -eq 'repository-discovery') {
        if ($null -ne $repository) { throw 'More than one repository discovery source was supplied.' }
        $repository = $document
    }
    $sources.Add([ordered]@{
        agentId=$document.agentId
        relativePath=[IO.Path]::GetRelativePath($RunRoot,$path).Replace('\','/')
        sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    })
}
if ($null -eq $repository) { throw 'Repository discovery source is required.' }
# Preserve source facts without paying the reconciler to transcribe them, or
# losing fields when a summary reaches the model's output limit.
$decision.details.componentStacks = $repository.details.componentStacks
$decision.details.primaryStack = $repository.details.primaryStack
$decision.details.sourceArtifacts = @($sources)
$decision | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath "$OutputPath.tmp" -Encoding utf8
$null = & (Join-Path $root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath "$OutputPath.tmp" `
    -SchemaPath (Join-Path $root 'schemas/discovery/discovery-result.schema.json') -SchemaRoot (Join-Path $root 'schemas')
Move-Item -LiteralPath "$OutputPath.tmp" -Destination $OutputPath -Force
return (Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -Depth 100)
