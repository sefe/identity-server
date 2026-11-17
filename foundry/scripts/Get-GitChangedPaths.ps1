[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepositoryRoot)

$inside = & git -C $RepositoryRoot rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -ne 0 -or [string]$inside -ne "true") {
    throw "Repository mutation requires a Git work tree."
}
$lines = @(& git -C $RepositoryRoot status --porcelain=v1 --untracked-files=all)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect Git work tree status."
}
$paths = [System.Collections.Generic.List[string]]::new()
foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace([string]$line) -or $line.Length -lt 4) {
        continue
    }
    $path = $line.Substring(3).Trim()
    if ($path -match "^.+ -> (.+)$") {
        $path = $Matches[1]
    }
    $paths.Add($path.Replace("\", "/"))
}
return @($paths | Sort-Object -Unique)
