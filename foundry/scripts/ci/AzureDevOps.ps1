[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [string]$PolicyPath = "./policies/default-policy.yaml",
    [string]$WorkflowPath = "",
    [string]$EventType = "auto",
    [string]$EventPath = "",
    [string]$CiBuildId = "",
    [string]$CiRunId = ""
)

$root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
$outcome = & (Join-Path $root "scripts/Invoke-Foundry.ps1") `
    -ConfigPath $ConfigPath `
    -PolicyPath $PolicyPath `
    -WorkflowPath $WorkflowPath `
    -EventType $EventType `
    -EventPath $EventPath `
    -CiBuildId $CiBuildId `
    -CiRunId $CiRunId
if ($LASTEXITCODE -ne 0) {
    throw "SDLC Foundry failed in Azure DevOps."
}

# A run that ends 'blocked' has judged the work and stopped: it produced no pull
# request and nothing downstream of it happened. It reports that as a status
# rather than as an exception, deliberately, because it is an answer and not a
# crash - but an answer that reaches Azure DevOps as a green build is read by
# everything here as work delivered. The queue marks the work item implemented,
# the next event is raised against a change that does not exist, and the one
# human step in the whole design - approving the pull request - is skipped
# because there is nothing to approve.
#
# So the status is turned into the build result here, at the boundary where the
# two meanings meet. Only a run that finished is green.
$run = @($outcome | Where-Object {
    $null -ne $_ -and $null -ne $_.PSObject -and
    @($_.PSObject.Properties.Name) -contains "status"
}) | Select-Object -Last 1
if ($null -eq $run) {
    throw ("SDLC Foundry returned no run outcome, so there is nothing to say whether the work " +
        "was done. Treating that as a failure rather than as a delivery.")
}
$status = ([string]$run.status).Trim().ToLowerInvariant()
if ($status -ne "completed") {
    $where = if ("$($run.runRoot)".Trim() -ne "") { " Its evidence is in $($run.runRoot)." } else { "" }
    $why = switch ($status) {
        "blocked" {
            "A stage stopped the run rather than produce something unsafe, so no delivery was made."
        }
        "paused" {
            "The run ran out of its time budget partway through and nothing here resumes it, so " +
            "no delivery was made."
        }
        default { "The run ended with status '$status' rather than finishing." }
    }
    throw ("SDLC Foundry did not finish: $why$where")
}
$outcome
