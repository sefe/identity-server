[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BasePath,
    [Parameter(Mandatory)][string]$RevisionJson,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$AgentId,
    [Parameter(Mandatory)][string]$StageId
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$root = Get-QaFoundryRoot
$temporary = [IO.Path]::GetTempFileName()
try {
    $RevisionJson | Set-Content -LiteralPath $temporary -Encoding utf8
    $null = & (Join-Path $PSScriptRoot 'Validate-JsonArtifact.ps1') -ArtifactPath $temporary `
        -SchemaPath (Join-Path $root 'schemas/architecture/blueprint-revision.schema.json') -SchemaRoot (Join-Path $root 'schemas')
} finally { Remove-Item -LiteralPath $temporary -Force }
$revision = $RevisionJson | ConvertFrom-Json -AsHashtable -Depth 100
if ((Get-FileHash -LiteralPath $BasePath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $revision.baseSha256) {
    throw 'Blueprint revision base hash does not match the supplied artifact.'
}
$result = Get-Content -LiteralPath $BasePath -Raw | ConvertFrom-Json -AsHashtable -Depth 100
if ($result.runId -cne $RunId -or $result.agentId -cne $AgentId -or $result.stageId -cne $StageId) {
    throw 'Blueprint revision base identity does not match the current agent, stage and run.'
}
$edited = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($edit in $revision.edits) {
    $path = [string]$edit.path
    if (-not $edited.Add($path)) { throw "Duplicate blueprint edit: $path" }
    foreach ($other in $edited) {
        if ($other -ceq $path) { continue }
        if ($other.StartsWith("$path/",[StringComparison]::Ordinal) -or $path.StartsWith("$other/",[StringComparison]::Ordinal)) {
            throw 'Overlapping blueprint edits are ambiguous; use disjoint paths.'
        }
    }
    $segments = @($path.Substring(1).Split('/') | ForEach-Object { $_.Replace('~1','/').Replace('~0','~') })
    $parent = $result
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $key = $segments[$index]
        $last = $index -eq $segments.Count - 1
        if ($parent -is [System.Collections.IDictionary]) {
            if ($last) { $parent[$key] = $edit.value }
            elseif ($parent.Contains($key)) { $parent = $parent[$key] }
            else { throw "Blueprint edit has no parent at $path" }
        } elseif ($parent -is [System.Collections.IList]) {
            if ($key -notmatch '^(0|[1-9][0-9]*)$' -or [long]$key -ge $parent.Count) { throw "Invalid array index at $path" }
            if ($last) { $parent[[int]$key] = $edit.value } else { $parent = $parent[[int]$key] }
        } else { throw "Blueprint edit traverses a scalar at $path" }
    }
}
foreach ($old in @($(if ($result.Contains('deferrals')) { $result.deferrals }))) {
    if ($null -eq $old -or @($revision.deferrals | Where-Object item -CEQ $old.item).Count -gt 0) { continue }
    $resolutions = @($revision.resolvedDeferrals | Where-Object item -CEQ $old.item)
    if ($resolutions.Count -ne 1) { throw "Removed deferral requires one explicit resolution: $($old.item)" }
    foreach ($path in $resolutions[0].paths) {
        if (-not $edited.Contains([string]$path)) { throw "Deferral resolution must refer to an actual edit: $path" }
    }
}
$result.summary = $revision.summary
$result.status = $revision.status
$result.deferrals = @($revision.deferrals)
return ($result | ConvertTo-Json -Depth 100)
