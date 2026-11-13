[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet("check", "register")][string]$Operation,
    [Parameter(Mandatory)][string]$RegistryPath,
    [Parameter(Mandatory)][string]$Key,
    [string]$ActionType = "",
    [string]$SourceRef = "",
    [string]$Status = "planned",
    [string]$RunId = "",
    [string]$ExternalId = ""
)

$ErrorActionPreference = "Stop"
if ($Key -notmatch "^[a-f0-9]{64}$") {
    throw "Idempotency key must be a lowercase SHA-256 value."
}
$parent = Split-Path $RegistryPath -Parent
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$lockPath = "$RegistryPath.lock"
$lock = $null
$deadline = [DateTime]::UtcNow.AddSeconds(10)
while ($null -eq $lock -and [DateTime]::UtcNow -lt $deadline) {
    try {
        $lock = [IO.File]::Open(
            $lockPath,
            [IO.FileMode]::OpenOrCreate,
            [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None
        )
    }
    catch [IO.IOException] {
        [Threading.Thread]::Sleep(100)
    }
}
if ($null -eq $lock) {
    throw "Timed out acquiring idempotency registry lock."
}

try {
    $registry = if (Test-Path $RegistryPath -PathType Leaf) {
        Get-Content -Path $RegistryPath -Raw |
            ConvertFrom-Json -Depth 50 -ErrorAction Stop
    }
    else {
        [pscustomobject]@{
            schemaVersion = 1
            updatedAt = [DateTime]::UtcNow.ToString("o")
            records = @()
        }
    }
    $matches = @($registry.records | Where-Object { [string]$_.key -eq $Key })
    if ($Operation -eq "check") {
        return [pscustomobject]@{
            exists = $matches.Count -gt 0
            record = if ($matches.Count -gt 0) { $matches[-1] } else { $null }
        }
    }
    if ([string]::IsNullOrWhiteSpace($ActionType) -or
        [string]::IsNullOrWhiteSpace($SourceRef) -or
        [string]::IsNullOrWhiteSpace($RunId)) {
        throw "Register requires ActionType, SourceRef, and RunId."
    }
    if ($Status -notin @("planned", "executed", "dry_run", "declined", "failed")) {
        throw "Unsupported idempotency status: $Status"
    }
    $now = [DateTime]::UtcNow.ToString("o")
    $records = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($registry.records)) {
        if ([string]$record.key -ne $Key) {
            $records.Add($record)
        }
    }
    $createdAt = if ($matches.Count -gt 0) {
        [string]$matches[-1].createdAt
    }
    else {
        $now
    }
    $newRecord = [pscustomobject][ordered]@{
        key = $Key
        actionType = $ActionType
        sourceRef = $SourceRef
        status = $Status
        runId = $RunId
        externalId = $ExternalId
        createdAt = $createdAt
        updatedAt = $now
    }
    $records.Add($newRecord)
    $registry = [ordered]@{
        schemaVersion = 1
        updatedAt = $now
        records = @($records | Sort-Object key)
    }
    $temporaryPath = "$RegistryPath.$([guid]::NewGuid().ToString('N')).tmp"
    $registry | ConvertTo-Json -Depth 50 |
        Set-Content -Path $temporaryPath -Encoding utf8
    Move-Item -Path $temporaryPath -Destination $RegistryPath -Force
    return [pscustomobject]@{ exists = $matches.Count -gt 0; record = $newRecord }
}
finally {
    $lock.Dispose()
}
