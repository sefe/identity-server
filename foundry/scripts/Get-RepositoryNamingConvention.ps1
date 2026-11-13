[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [string]$Segment = "Automation",
    [string]$FixedPrefix = "",
    [string[]]$ExcludedDirectories = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$noiseNames = @(
    "src", "source", "lib", "libs", "test", "tests", "spec", "specs", "docs", "doc",
    "build", "dist", "out", "bin", "obj", "tools", "tooling", "scripts", "script",
    "pipelines", "pipeline", "assets", "images", "samples", "examples", "node_modules",
    "packages", "vendor", "target", "infra", "infrastructure", "deploy", "deployment",
    "docker", "config", "configs", "automation", "coverage", "artifacts"
)

function Get-ScannableDirectories {
    param([string]$Root, [int]$MaxDepth, [string[]]$Skip)

    $found = [System.Collections.Generic.List[string]]::new()
    $found.Add($Root)
    $frontier = @($Root)
    for ($depth = 1; $depth -le $MaxDepth; $depth++) {
        $next = [System.Collections.Generic.List[string]]::new()
        foreach ($directory in $frontier) {
            $children = @()
            try { $children = [IO.Directory]::GetDirectories($directory) } catch { continue }
            foreach ($child in $children) {
                $name = [IO.Path]::GetFileName($child)
                if ($name.StartsWith(".")) { continue }
                if ($Skip -contains $name.ToLowerInvariant()) { continue }
                $found.Add($child)
                $next.Add($child)
            }
        }
        $frontier = @($next)
    }
    return @($found)
}

function Get-CandidateNames {
    param([string]$Root)

    # An enumeration that raises suppressed errors still marks the whole runspace as
    # failed, so this walks the tree by hand and skips what it cannot read.
    $skip = @("node_modules", "bin", "obj", "dist", "out", "packages", "vendor", "target") +
        @($ExcludedDirectories | ForEach-Object { ([string]$_).Trim("/", "\").ToLowerInvariant() })
    $directories = Get-ScannableDirectories -Root $Root -MaxDepth 3 -Skip $skip
    $names = [System.Collections.Generic.List[string]]::new()

    foreach ($directory in $directories) {
        $files = @()
        try { $files = [IO.Directory]::GetFiles($directory) } catch { continue }
        foreach ($file in $files) {
            if ([IO.Path]::GetExtension($file) -match "^\.(cs|fs|vb|sql|es)proj$") {
                $names.Add([IO.Path]::GetFileNameWithoutExtension($file))
            }
        }
    }
    if ($names.Count -ge 2) {
        return @{ Names = @($names); Source = "project files" }
    }

    foreach ($directory in $directories) {
        $manifest = Join-Path $directory "package.json"
        if (-not [IO.File]::Exists($manifest)) { continue }
        try {
            $parsed = [IO.File]::ReadAllText($manifest) | ConvertFrom-Json -Depth 20
        }
        catch { continue }
        # An empty manifest is valid JSON, and reading the names of an empty
        # property set throws under strict mode instead of yielding nothing.
        $manifestNames = if ($null -eq $parsed -or $null -eq $parsed.PSObject) {
            @()
        }
        else {
            @($parsed.PSObject.Properties | ForEach-Object { $_.Name })
        }
        if ($manifestNames -contains "name" -and
            -not [string]::IsNullOrWhiteSpace([string]$parsed.name)) {
            $names.Add((([string]$parsed.name) -replace "^@[^/]+/", ""))
        }
    }
    if ($names.Count -ge 2) {
        return @{ Names = @($names); Source = "package manifests" }
    }

    $excluded = @($ExcludedDirectories | ForEach-Object { ([string]$_).Trim("/", "\").ToLowerInvariant() })
    $topLevel = @()
    try { $topLevel = [IO.Directory]::GetDirectories($Root) } catch { $topLevel = @() }
    foreach ($directory in $topLevel) {
        $name = [IO.Path]::GetFileName($directory)
        if ($name.StartsWith(".")) { continue }
        if ($noiseNames -contains $name.ToLowerInvariant()) { continue }
        if ($excluded -contains $name.ToLowerInvariant()) { continue }
        $names.Add($name)
    }
    return @{ Names = @($names); Source = "top-level directories" }
}

function Get-DominantSeparator {
    param([string[]]$Names)

    $best = ""
    $bestCount = 0
    foreach ($separator in @(".", "-", "_")) {
        $count = @($Names | Where-Object { $_.Contains($separator) }).Count
        if ($count -gt $bestCount) {
            $bestCount = $count
            $best = $separator
        }
    }
    if ($bestCount -lt 2) { return "" }
    return $best
}

function Get-CommonPrefix {
    param([string[]]$Names, [string]$Separator)

    $tokenLists = @($Names | ForEach-Object { , @($_.Split($Separator)) })
    $longest = ($tokenLists | ForEach-Object { $_.Count } | Measure-Object -Maximum).Maximum
    $bestPrefix = ""
    $bestCoverage = 0
    for ($length = 1; $length -lt $longest; $length++) {
        $groups = $tokenLists |
            Where-Object { $_.Count -gt $length } |
            ForEach-Object { ($_[0..($length - 1)]) -join $Separator } |
            Group-Object |
            Sort-Object Count -Descending
        if (@($groups).Count -eq 0) { break }
        $top = @($groups)[0]
        if ($top.Count -lt 2 -or $top.Count -lt ($Names.Count / 2)) { break }
        $bestPrefix = [string]$top.Name
        $bestCoverage = [int]$top.Count
    }
    return @{ Prefix = $bestPrefix; Coverage = $bestCoverage }
}

function Get-SegmentCasing {
    param([string]$Prefix, [string]$Separator, [string]$Word)

    $sample = if ([string]::IsNullOrWhiteSpace($Separator)) { $Prefix } else { @($Prefix.Split($Separator))[-1] }
    if ($sample -cmatch "^[A-Z0-9]+$" -and $sample.Length -gt 1) { return $Word.ToUpperInvariant() }
    if ($sample -cmatch "^[a-z0-9]+$") { return $Word.ToLowerInvariant() }
    return $Word.Substring(0, 1).ToUpperInvariant() + $Word.Substring(1)
}

$resolvedRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$result = [ordered]@{
    detected = $false
    prefix = ""
    separator = ""
    segment = $Segment
    template = ""
    example = ""
    evidence = ""
    samples = @()
}

if (-not [string]::IsNullOrWhiteSpace($FixedPrefix)) {
    $separator = if ($FixedPrefix -match "[-_.]") { [string]$Matches[0] } else { "." }
    $segmentWord = Get-SegmentCasing -Prefix $FixedPrefix -Separator $separator -Word $Segment
    $scopeWord = Get-SegmentCasing -Prefix $FixedPrefix -Separator $separator -Word "Api"
    $result.detected = $true
    $result.prefix = $FixedPrefix
    $result.separator = $separator
    $result.segment = $segmentWord
    $result.template = "$FixedPrefix$separator$segmentWord$separator{scope}"
    $result.example = "$FixedPrefix$separator$segmentWord$separator$scopeWord"
    $result.evidence = "configured prefix"
    return [pscustomobject]$result
}

$candidates = Get-CandidateNames -Root $resolvedRoot
$names = @($candidates.Names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
if ($names.Count -lt 2) {
    return [pscustomobject]$result
}

$separator = Get-DominantSeparator -Names $names
if ([string]::IsNullOrWhiteSpace($separator)) {
    return [pscustomobject]$result
}

$common = Get-CommonPrefix -Names $names -Separator $separator
if ([string]::IsNullOrWhiteSpace($common.Prefix)) {
    return [pscustomobject]$result
}

$segmentWord = Get-SegmentCasing -Prefix $common.Prefix -Separator $separator -Word $Segment
$scopeWord = Get-SegmentCasing -Prefix $common.Prefix -Separator $separator -Word "Api"
$result.detected = $true
$result.prefix = $common.Prefix
$result.separator = $separator
$result.segment = $segmentWord
$result.template = "$($common.Prefix)$separator$segmentWord$separator{scope}"
$result.example = "$($common.Prefix)$separator$segmentWord$separator$scopeWord"
$result.evidence = "$($common.Coverage) of $($names.Count) $($candidates.Source) share this prefix"
$result.samples = @($names | Where-Object { $_.StartsWith("$($common.Prefix)$separator") } | Select-Object -First 4)
return [pscustomobject]$result
