<#
.SYNOPSIS
    Resolves an Azure DevOps pipeline id from its name.

.DESCRIPTION
    Kept apart from queueing because two callers need the id for different reasons: one starts a
    run, and one asks what the previous runs of that pipeline did. Resolving it twice by name would
    let the two disagree about which pipeline they mean.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PipelineName,
    [Parameter(Mandatory)][string]$Organization,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][hashtable]$Headers
)

$ErrorActionPreference = "Stop"

$apiRoot = "$($Organization.TrimEnd('/'))/$([Uri]::EscapeDataString($Project))/_apis/pipelines"
$listResponse = Invoke-RestMethod -Method Get `
    -Uri "${apiRoot}?`$top=10000&api-version=7.1" -Headers $Headers
$candidates = @(@($listResponse.value) | Where-Object { [string]$_.name -eq $PipelineName })
if ($candidates.Count -eq 0) {
    throw (
        "No pipeline named '$PipelineName' exists in project '$Project'. Queueing a pipeline " +
        "that was never registered cannot work, so nothing was queued."
    )
}
# Two pipelines may share a name in different folders. Picking one would be a coin toss over which
# automation runs, so the caller is told to name the id instead.
if ($candidates.Count -gt 1) {
    throw (
        "Project '$Project' has $($candidates.Count) pipelines named '$PipelineName'. Pass " +
        "-PipelineId to say which one should run."
    )
}
return [pscustomobject]@{
    id = [int]$candidates[0].id
    name = [string]$candidates[0].name
}
