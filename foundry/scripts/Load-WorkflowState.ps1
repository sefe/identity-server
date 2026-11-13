[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)

if (-not (Test-Path $Path -PathType Leaf)) {
    throw "Workflow state does not exist: $Path"
}

return (Get-Content -Path $Path -Raw | ConvertFrom-Json -Depth 100)

