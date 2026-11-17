[CmdletBinding()]
param(
    [string]$EventType = "auto",
    [string]$EventPath = ""
)

if ($EventType -ne "auto") {
    return $EventType
}
if (-not [string]::IsNullOrWhiteSpace($EventPath)) {
    if (-not (Test-Path $EventPath -PathType Leaf)) {
        throw "SDLC event file does not exist: $EventPath"
    }
    $event = Get-Content -Path $EventPath -Raw |
        ConvertFrom-Json -Depth 50 -ErrorAction Stop
    if ($event.PSObject.Properties.Name -contains "type" -and
        -not [string]::IsNullOrWhiteSpace([string]$event.type)) {
        return [string]$event.type
    }
}

$azureBuild = [Environment]::GetEnvironmentVariable("TF_BUILD")
if ($azureBuild -eq "True") {
    $buildReason = [Environment]::GetEnvironmentVariable("BUILD_REASON")
    if ($buildReason -eq "PullRequest") {
        return "pull_request.updated"
    }
    if ($buildReason -eq "Schedule") {
        return "schedule.tick"
    }
    return "repository.push"
}
return "manual"
