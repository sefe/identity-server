[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ActionType,
    [Parameter(Mandatory)][string]$SourceRef,
    # Where the reference means what it means. A source reference like 'task-1'
    # or 'finding:3' is only unique inside the repository that produced it, so a
    # key built from the reference alone collides across two repositories
    # delivering into one Azure DevOps project - and a collision here is read as
    # "this work already exists", which silently drops it.
    [string]$Scope = ""
)

$canonical = "$($ActionType.Trim().ToLowerInvariant())`n$($SourceRef.Trim())"
if (-not [string]::IsNullOrWhiteSpace($Scope)) {
    $canonical = "$($ActionType.Trim().ToLowerInvariant())`n$($Scope.Trim().ToLowerInvariant())`n$($SourceRef.Trim())"
}
$bytes = [Text.Encoding]::UTF8.GetBytes($canonical)
$hash = [Security.Cryptography.SHA256]::HashData($bytes)
return [Convert]::ToHexString($hash).ToLowerInvariant()
