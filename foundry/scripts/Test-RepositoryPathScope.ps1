[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][string]$RepositoryRoot
)

. (Join-Path $PSScriptRoot "Common.ps1")
if ([IO.Path]::IsPathRooted($Path)) {
    throw "Repository change path must be relative: $Path"
}
$normalised = $Path.Replace("\", "/").TrimStart("/")
if ([string]::IsNullOrWhiteSpace($normalised) -or
    $normalised -match "(^|/)\.\.(/|$)" -or
    $normalised -match "(^|/)\.git(/|$)") {
    throw "Unsafe repository change path: $Path"
}
$candidate = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $normalised))
if (-not (Test-PathWithinRoot -Candidate $candidate -Root $RepositoryRoot)) {
    throw "Repository change escapes the target root: $Path"
}
# The write rules are decided on the canonical path, not on the string that was asked for.
# 'automation/./private/x' and 'automation//private/x' name the file that 'automation/private/x'
# names, and comparing the unresolved spelling is how a forbidden directory gets written to.
$rootFull = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$normalised = $candidate.Substring($rootFull.Length).TrimStart("\", "/").Replace("\", "/")
# A file system that ignores case makes 'Automation/Private' and 'automation/private' the same
# directory, so a rule about one has to apply to the other. Where case matters, it must not.
$comparison = if ($IsWindows) {
    [StringComparison]::OrdinalIgnoreCase
} else {
    [StringComparison]::Ordinal
}
$forbidden = @($Config.repository.forbidden_write_paths | ForEach-Object {
    (([string]$_).Replace("\", "/") -replace "^\./", "").TrimStart("/").TrimEnd("/")
})
$allowed = @($Config.repository.allowed_write_paths | ForEach-Object {
    (([string]$_).Replace("\", "/") -replace "^\./", "").TrimStart("/").TrimEnd("/")
})
foreach ($prefix in $forbidden) {
    if ([string]::Equals($normalised, $prefix, $comparison) -or
        $normalised.StartsWith("$prefix/", $comparison)) {
        throw "Repository change targets a forbidden path: $Path"
    }
}
if (@($allowed | Where-Object {
    [string]::Equals($normalised, $_, $comparison) -or $normalised.StartsWith("$_/", $comparison)
}).Count -eq 0) {
    throw "Repository change is outside allowed_write_paths: $Path"
}

$current = $RepositoryRoot
$segments = @($normalised.Split("/"))
# Every component, including the file itself: a symbolic link in the last position writes through
# to wherever it points, which is the one place these rules were meant to keep the write out of.
for ($index = 0; $index -lt $segments.Count; $index++) {
    $current = Join-Path $current $segments[$index]
    if (Test-Path $current) {
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Repository change path traverses a symbolic link: $Path"
        }
    }
}
return [pscustomobject]@{
    relativePath = $normalised
    absolutePath = $candidate
}
