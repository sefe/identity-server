[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][string]$ConfigDirectory,
    [Parameter(Mandatory)][string]$LauncherRoot,
    [string]$WorkflowPath = "",
    [string]$EventPath = "",
    [string]$EventType = "auto"
)

. (Join-Path $PSScriptRoot "Common.ps1")
$resolvedEventPath = if ([string]::IsNullOrWhiteSpace($EventPath)) {
    ""
}
else {
    Resolve-QaFoundryPath -Root $LauncherRoot -Path $EventPath
}
$resolvedEventType = & (Join-Path $PSScriptRoot "Resolve-SdlcEventType.ps1") `
    -EventType $EventType `
    -EventPath $resolvedEventPath

if (-not [string]::IsNullOrWhiteSpace($WorkflowPath)) {
    return [pscustomobject]@{
        eventType = $resolvedEventType
        eventPath = $resolvedEventPath
        workflowPath = Resolve-QaFoundryPath -Root $LauncherRoot -Path $WorkflowPath
        routed = $false
    }
}
if (-not [bool]$Config.routing.enabled) {
    throw "No workflow was supplied and automatic event routing is disabled."
}
$matches = @($Config.routing.routes | Where-Object {
    $resolvedEventType -in @($_.event_types | ForEach-Object { [string]$_ })
})
if ($matches.Count -ne 1) {
    throw "Expected exactly one workflow route for event '$resolvedEventType', found $($matches.Count)."
}
$resolvedWorkflow = Resolve-QaFoundryPath `
    -Root $ConfigDirectory `
    -Path ([string]$matches[0].workflow)
return [pscustomobject]@{
    eventType = $resolvedEventType
    eventPath = $resolvedEventPath
    workflowPath = $resolvedWorkflow
    routed = $true
}
