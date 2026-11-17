[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../Common.ps1")
$root = (Resolve-Path $RepositoryRoot).Path
$files = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$totalBytes = [int64]0

function Get-ObservabilityKind {
    param([string]$Path)
    $name = [IO.Path]::GetFileName($Path).ToLowerInvariant()
    if ($name -match "trace|span|otel") { return "trace" }
    if ($name -match "metric|prometheus") { return "metric" }
    if ($name -match "event|audit") { return "event" }
    if ($name -match "log|stdout|stderr") { return "log" }
    return "unknown"
}

function Protect-ObservabilityText {
    param([string]$Text)
    if ($null -eq $Text) { return "" }
    $protected = $Text
    $protected = [regex]::Replace($protected, "gh[pousr]_[A-Za-z0-9_]{20,}", "[REDACTED_TOKEN]")
    $protected = [regex]::Replace(
        $protected,
        '(?i)(authorization\s*[:=]\s*(?:bearer|basic)\s+)[^\s,;]+',
        '$1[REDACTED]'
    )
    $protected = [regex]::Replace(
        $protected,
        '(?i)((?:api[_-]?key|secret|password|token)\s*[:=]\s*)[^\s,;]+',
        '$1[REDACTED]'
    )
    return $protected
}

foreach ($configuredPath in @($Config.observability.input_paths)) {
    $candidate = if ([IO.Path]::IsPathRooted([string]$configuredPath)) {
        [IO.Path]::GetFullPath([string]$configuredPath)
    }
    else {
        [IO.Path]::GetFullPath((Join-Path $root ([string]$configuredPath)))
    }
    $prefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($candidate -ne $root -and -not $candidate.StartsWith($prefix, [StringComparison]::Ordinal)) {
        throw "Observability input must stay inside the target repository: $configuredPath"
    }
    $resolvedFiles = if (Test-Path $candidate -PathType Leaf) {
        # A dot-prefixed path is hidden to the provider on Linux, and a hidden
        # item is withheld unless it is forced.
        @(Get-Item -LiteralPath $candidate -Force)
    }
    elseif (Test-Path $candidate -PathType Container) {
        @(Get-ChildItem -LiteralPath $candidate -File -Recurse | Sort-Object FullName)
    }
    else {
        $warnings.Add("Observability input does not exist: $configuredPath")
        @()
    }
    foreach ($file in $resolvedFiles) {
        if ($totalBytes -ge [int64]$Config.observability.max_total_bytes) {
            $warnings.Add("Observability total byte limit reached.")
            break
        }
        $remaining = [int64]$Config.observability.max_total_bytes - $totalBytes
        $readBytes = [Math]::Min(
            [int64]$file.Length,
            [Math]::Min([int64]$Config.observability.max_file_bytes, $remaining)
        )
        $stream = [IO.File]::OpenRead($file.FullName)
        try {
            $buffer = [byte[]]::new([int]$readBytes)
            $actual = $stream.Read($buffer, 0, $buffer.Length)
        }
        finally {
            $stream.Dispose()
        }
        $content = [Text.Encoding]::UTF8.GetString($buffer, 0, $actual)
        $relative = [IO.Path]::GetRelativePath($root, $file.FullName).Replace("\", "/")
        $fileHash = Get-FileSha256Safe -Path $file.FullName
        if (-not $fileHash) {
            continue
        }
        $files.Add([pscustomobject][ordered]@{
            path = $relative
            kind = Get-ObservabilityKind -Path $relative
            sha256 = $fileHash
            bytes = [int64]$file.Length
            content = Protect-ObservabilityText -Text $content
            truncated = $actual -lt [int64]$file.Length
        })
        $totalBytes += $actual
    }
}

$evidence = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    collectedAt = [DateTime]::UtcNow.ToString("o")
    status = if ($files.Count -eq 0) { "no_action_needed" } else { "completed" }
    files = @($files)
    summary = [ordered]@{
        fileCount = $files.Count
        totalBytes = $totalBytes
        truncatedFileCount = @($files | Where-Object { $_.truncated }).Count
    }
    warnings = @($warnings)
}
New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 100 | Set-Content -Path $OutputPath -Encoding utf8
return [pscustomobject]$evidence
