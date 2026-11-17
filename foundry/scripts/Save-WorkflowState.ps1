[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$State,
    [Parameter(Mandatory)][string]$Path
)

$parent = Split-Path $Path -Parent
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$temporary = "$Path.tmp"
$State.updatedAt = [DateTime]::UtcNow.ToString("o")
$State | ConvertTo-Json -Depth 100 | Set-Content -Path $temporary -Encoding utf8
Move-Item -Path $temporary -Destination $Path -Force

