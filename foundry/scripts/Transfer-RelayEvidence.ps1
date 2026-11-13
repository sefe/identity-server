[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Seal', 'Validate', 'Restore')][string]$Mode,
    [Parameter(Mandatory)][string]$SourceRoot,
    [Parameter(Mandatory)][string]$BuildId,
    [Parameter(Mandatory)][string]$Leg,
    [string]$ArtifactRoot = '.qa-foundry-artifacts',
    [string]$RunId = ''
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'RelayEvidence.ps1')
$SourceRoot = [IO.Path]::GetFullPath($SourceRoot, (Get-Location).ProviderPath)
if ($Mode -eq 'Seal') {
    $run = Get-QaFoundryRelayRun -ArtifactRoot $SourceRoot -RunId $RunId -AllowIncomplete
    $selectedRunId = if ($null -ne $run) { $run.Name } else { '' }
    if ($selectedRunId) { Set-QaFoundryRelayRun -ArtifactRoot $SourceRoot -RunId $selectedRunId }
    $resumable = $null -ne $run -and (Test-Path -LiteralPath (Join-Path $run.FullName 'workflow-state.json') -PathType Leaf)
    $manifest = [ordered]@{
        version = 1; buildId = $BuildId; leg = $Leg; runId = $selectedRunId; resumable = [bool]$resumable
        files = @(Get-QaFoundryRelayFiles -Root $SourceRoot | Sort-Object path)
    }
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $SourceRoot 'relay-manifest.json') -Encoding utf8
    return
}
$manifest = Test-QaFoundryRelayEvidence -Root $SourceRoot -BuildId $BuildId -Leg $Leg
if ($Mode -eq 'Validate') { return }
if ($manifest.PSObject.Properties['resumable'] -and -not [bool]$manifest.resumable) {
    throw 'This artifact contains diagnostic evidence only; no workflow state exists to resume. Start a fresh run after fixing its prerequisite.'
}
$destination = [IO.Path]::GetFullPath($ArtifactRoot, (Get-Location).ProviderPath)
$workspace = [IO.Path]::GetFullPath((Get-Location).Path)
$relative = [IO.Path]::GetRelativePath($workspace, $destination)
if ([IO.Path]::IsPathRooted($relative) -or $relative -eq '.' -or $relative -eq '..' -or
    $relative.StartsWith('../') -or $relative.StartsWith('..\')) {
    throw 'Relay destination must be a child of the working directory.'
}
if (Test-Path -LiteralPath $destination) {
    # Restore never overlays another run, even if it was left by this build.
    throw "Relay destination must be absent before restore: $destination"
}
$temporary = "$destination.restoring-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temporary -Force | Out-Null
foreach ($entry in @($manifest.files)) {
    $target = Join-Path $temporary ([string]$entry.path)
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $SourceRoot ([string]$entry.path)) -Destination $target
}
Copy-Item -LiteralPath (Join-Path $SourceRoot 'relay-manifest.json') -Destination $temporary
$null = Test-QaFoundryRelayEvidence -Root $temporary -BuildId $BuildId -Leg $Leg
Move-Item -LiteralPath $temporary -Destination $destination
Write-Host "Restored verified run '$($manifest.runId)' from build $BuildId, leg $Leg."
