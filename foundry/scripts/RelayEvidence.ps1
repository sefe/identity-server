# Shared by the relay and its artifact transport. Directory ordering is never identity.
function Get-QaFoundryRelayRun {
    param([Parameter(Mandatory)][string]$ArtifactRoot, [string]$RunId = "", [switch]$AllowIncomplete)
    if (-not (Test-Path -LiteralPath $ArtifactRoot)) { return $null }
    $identityPath = Join-Path $ArtifactRoot "active-run.json"
    if (-not $RunId -and (Test-Path -LiteralPath $identityPath)) {
        $identity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
        $RunId = [string]$identity.runId
        if (-not $RunId) { throw "Relay identity has no runId: $identityPath" }
    }
    if ($RunId) {
        if ($RunId -notmatch '^run-[a-zA-Z0-9-]+$') { throw "Invalid relay runId." }
        $run = Join-Path $ArtifactRoot $RunId
        if (-not (Test-Path -LiteralPath (Join-Path $run 'workflow-state.json') -PathType Leaf)) {
            if ($AllowIncomplete -and (Test-Path -LiteralPath $run -PathType Container)) {
                return Get-Item -LiteralPath $run
            }
            throw "The relay's selected run '$RunId' has no workflow state."
        }
        $state = Get-Content -LiteralPath (Join-Path $run 'workflow-state.json') -Raw | ConvertFrom-Json -Depth 100
        if ($state.PSObject.Properties['runId'] -and [string]$state.runId -ne $RunId) {
            throw "Relay runId differs from workflow state in '$run'."
        }
        return Get-Item -LiteralPath $run
    }
    $runs = @(Get-ChildItem -LiteralPath $ArtifactRoot -Directory -Filter 'run-*' |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'workflow-state.json') -PathType Leaf })
    if ($runs.Count -gt 1) {
        throw "Ambiguous relay evidence: $($runs.Count) analysis runs and no active-run.json. Select an explicit RunId; directory age is not ownership."
    }
    if ($runs.Count -eq 1) { return $runs[0] }
    return $null
}

function Set-QaFoundryRelayRun {
    param([Parameter(Mandatory)][string]$ArtifactRoot, [Parameter(Mandatory)][string]$RunId)
    if ($RunId -notmatch '^run-[a-zA-Z0-9-]+$') { throw "Invalid relay runId." }
    New-Item -ItemType Directory -Path $ArtifactRoot -Force | Out-Null
    $path = Join-Path $ArtifactRoot 'active-run.json'
    @{ runId = $RunId } | ConvertTo-Json | Set-Content -LiteralPath "$path.tmp" -Encoding utf8
    Move-Item -LiteralPath "$path.tmp" -Destination $path -Force
}

function Get-QaFoundryRelayFiles {
    param([Parameter(Mandatory)][string]$Root)
    $entries = @(Get-ChildItem -LiteralPath $Root -Force | Where-Object { $_.Name -notin @('command-home', '.scratch') })
    $files = @($entries | Where-Object { -not $_.PSIsContainer })
    foreach ($directory in @($entries | Where-Object PSIsContainer)) {
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Relay directories must not be symbolic links.' }
        $files += @(Get-ChildItem -LiteralPath $directory.FullName -File -Recurse -Force)
    }
    foreach ($file in $files) {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
        if ($relative -eq 'relay-manifest.json' -or $relative -eq '.artifactignore' -or
            $relative.StartsWith('command-home/') -or $relative.StartsWith('.scratch/')) { continue }
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Relay evidence must not contain symbolic links: $relative"
        }
        [pscustomobject]@{ path = $relative; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
    }
}

function Test-QaFoundryRelayEvidence {
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$BuildId,
        [Parameter(Mandatory)][string]$Leg)
    $manifest = Get-Content -LiteralPath (Join-Path $Root 'relay-manifest.json') -Raw | ConvertFrom-Json -Depth 10
    if ($manifest.version -ne 1 -or [string]$manifest.buildId -ne $BuildId -or [string]$manifest.leg -ne $Leg) {
        throw "Relay artifact does not belong to build '$BuildId', leg '$Leg'."
    }
    $actual = @{}
    foreach ($file in @(Get-QaFoundryRelayFiles -Root $Root)) { $actual.Add($file.path, $file.sha256) }
    $seen = @{}
    foreach ($file in @($manifest.files)) {
        $path = [string]$file.path
        if ($seen.ContainsKey($path) -or -not $actual.ContainsKey($path) -or $actual[$path] -ne [string]$file.sha256) {
            throw "Incomplete or changed relay artifact: $path"
        }
        $seen.Add($path, $true)
    }
    if ($actual.Count -ne $seen.Count) { throw "Relay artifact contains files outside its manifest." }
    $diagnosticOnly = $manifest.PSObject.Properties['resumable'] -and -not [bool]$manifest.resumable
    $run = Get-QaFoundryRelayRun -ArtifactRoot $Root -AllowIncomplete:$diagnosticOnly
    $actualRunId = if ($null -ne $run) { $run.Name } else { '' }
    if ($actualRunId -ne [string]$manifest.runId -or ($null -eq $run -and -not $diagnosticOnly)) {
        throw "Relay manifest and active run disagree."
    }
    return $manifest
}
