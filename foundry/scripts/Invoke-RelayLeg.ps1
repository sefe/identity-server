# One leg of the bootstrap relay, as a script rather than a wall of YAML.
#
# This logic decides whether the relay continues, and it is where six
# consecutive builds died. Inline in the pipeline it could not be tested at all,
# so every mistake in it cost a three-hour live run to discover.
#
# The next leg only starts when this one reports 'paused':
#
#   condition: eq(dependencies.<previous>.outputs['bootstrap.relayStatus'], 'paused')
#
# So an unhandled crash used to end the whole relay silently. Build 453 threw on
# leg 4 and legs 5, 6 and 7 never started, discarding three finished legs and
# 171 minutes of completed stages, while the run itself sat resumable on disk
# the entire time.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][int]$LegIndex,
    [Parameter(Mandatory)][string]$BootstrapConfigPath,
    [Parameter(Mandatory)][string]$Phase,
    [Parameter(Mandatory)][int]$BudgetMinutes,
    [ValidateRange(1, 10080)][int]$RunBudgetMinutes = 720,
    [ValidateRange(1, 20)][int]$MaxNoProgressLegs = 3,
    [switch]$IsFinalLeg,
    [string]$ArtifactRoot = ".qa-foundry-artifacts",
    [string]$RestartStage = "",
    [string]$DocumentationLinks = '',
    [string]$BootstrapScript = ""
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Common.ps1")
. (Join-Path $PSScriptRoot "RelayEvidence.ps1")

if ([string]::IsNullOrWhiteSpace($BootstrapScript)) {
    $BootstrapScript = Join-Path $PSScriptRoot "Start-FoundryBootstrap.ps1"
}

function Get-ResumableRun {
    return Get-QaFoundryRelayRun -ArtifactRoot $ArtifactRoot
}

function Invoke-RelayProgress {
    param([string]$Action, [string]$Status = '')
    $run = Get-ResumableRun
    $runPath = if ($null -ne $run) { $run.FullName } else { $null }
    $null = New-Item -ItemType Directory -Path $ArtifactRoot -Force
    $optionsPath = Join-Path $ArtifactRoot 'relay-progress-options.json'
    @{
        action=$Action; root=[IO.Path]::GetFullPath($ArtifactRoot); runRoot=$runPath
        budgetMinutes=$RunBudgetMinutes; legBudgetMinutes=$BudgetMinutes; maxNoProgressLegs=$MaxNoProgressLegs
        legIndex=$LegIndex; buildId=[string]$env:BUILD_BUILDID; sourceVersion=[string]$env:BUILD_SOURCEVERSION; status=$Status
    } | ConvertTo-Json | Set-Content -LiteralPath $optionsPath -Encoding utf8
    $json = & node (Join-Path $PSScriptRoot 'helpers/relay-progress.mjs') $optionsPath
    if ($LASTEXITCODE -ne 0) { throw 'Relay progress accounting failed; budget cannot be reset safely.' }
    return ($json | ConvertFrom-Json -Depth 30)
}

function Write-RelayContinuation {
    param([string]$Reason)
    $run = Get-ResumableRun
    if ($null -eq $run) { throw 'Cannot publish a continuation without a saved run.' }
    $continuation = @{
        status='continuation_required'; reason=$Reason; runId=$run.Name
        sourceVersion=[string]$env:BUILD_SOURCEVERSION
        evidenceArtifact="foundry-evidence-leg$LegIndex"
        parameters=@{resumeFromBuildId=[string]$env:BUILD_BUILDID;resumeRunId=$run.Name;restartStage='none'
            phase=$Phase;legBudgetMinutes=$BudgetMinutes;runBudgetMinutes=$RunBudgetMinutes;maxNoProgressLegs=$MaxNoProgressLegs}
        instruction='Queue the same pipeline at sourceVersion with these continuation parameters and the same configuration. No stages are skipped; fingerprints are validated. A budget or no-progress stop requires resolving its cause first.'
    }
    $continuation | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $ArtifactRoot 'relay-continuation.json') -Encoding utf8
    Add-Content -LiteralPath (Join-Path $ArtifactRoot 'relay-progress.md') -Value (
        "`nContinuation required: $Reason. Resume build $env:BUILD_BUILDID, run $($run.Name), at source $env:BUILD_SOURCEVERSION. See relay-continuation.json for parameters.")
}

$script:RelayLedgerLost = $false

function Get-RelayIncidents {
    $path = Join-Path $ArtifactRoot "relay-incidents.json"
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try {
        return @(Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 20)
    }
    catch {
        # This file is the only memory the relay has of carrying a stage past a
        # crash. Reading it as "no incidents" would hand every stage a fresh
        # recovery budget and let one broken stage be carried forever. An
        # unreadable ledger means the count is unknown, and unknown is treated
        # as spent; the file itself is kept aside as evidence.
        Write-Host ("##[warning]The relay incident ledger at $path could not be read, so the " +
            "recovery budget is treated as already spent: $($_.Exception.Message)")
        $script:RelayLedgerLost = $true
        $quarantine = "$path.unreadable-" +
            (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")
        try { Move-Item -LiteralPath $path -Destination $quarantine -Force } catch { }
        return @()
    }
}

function Add-RelayIncident {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$RunId = "",
        [string]$Stage = "",
        [bool]$Recovered = $false
    )
    try {
        if (-not (Test-Path -LiteralPath $ArtifactRoot)) {
            New-Item -ItemType Directory -Path $ArtifactRoot -Force | Out-Null
        }
        $path = Join-Path $ArtifactRoot "relay-incidents.json"
        $incidents = @(Get-RelayIncidents)
        $incidents += [pscustomobject]@{
            leg        = $LegIndex
            recordedAt = (Get-Date).ToUniversalTime().ToString("o")
            message    = $Message
            runId      = $RunId
            stage      = $Stage
            recovered  = $Recovered
        }
        # A leg is killed on a timeout, and a leg killed halfway through this
        # write leaves a ledger that cannot be read. Written aside and moved
        # into place, the next leg finds either the previous ledger or this one.
        $temporaryPath = "$path.tmp"
        Set-Content -LiteralPath $temporaryPath `
            -Value (ConvertTo-Json -InputObject @($incidents) -Depth 20)
        Move-Item -LiteralPath $temporaryPath -Destination $path -Force
    }
    catch {
        Write-Host "##[warning]Could not record the crash of leg ${LegIndex}: $($_.Exception.Message)"
    }
}

function Get-RunStatus {
    param([Parameter(Mandatory)][string]$RunDirectory)
    $statePath = Join-Path $RunDirectory "workflow-state.json"
    try {
        return [string](Get-Content -LiteralPath $statePath -Raw |
            ConvertFrom-Json -Depth 100).status
    }
    catch {
        return ""
    }
}

# A crash and a defect are not the same event. Build 474 reached the eleventh
# stage of eleven and threw away four finished legs because one model call came
# back 400; the run was sitting on disk, mid-stage, entirely fit to continue.
# What follows decides whether this leg's crash is the kind the next leg can
# carry on from. It answers no unless it can say yes for a specific reason.
#
# Replaying an interrupted stage is safe only when replaying it changes nothing
# outside this repository. An agent can be asked again. A resolver can resolve
# again. A handler that has already filed work items or pushed a branch cannot
# be replayed by a fresh checkout that knows nothing about what it did.
$script:RelayReplayableHandlers = @(
    "materialize_change_set",
    "quality_suite",
    "collect_observability"
)
$script:RelayRecoveryLimit = 2

function Get-CrashRecovery {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Failure,
        [AllowNull()][object]$RunDirectory
    )
    # Common.ps1 raises the strictness of this script, so every field read here
    # goes through a check first: the state file is written by another process
    # and an older or half-written one must produce a refusal, not a crash in
    # the code whose whole job is to keep crashes from ending the relay.
    $read = {
        param([object]$Object, [string]$Name)
        if ($null -eq $Object) { return "" }
        if ($Object.PSObject.Properties.Name -notcontains $Name) { return "" }
        return [string]$Object.$Name
    }
    $refusal = {
        param([string]$Reason)
        [pscustomobject]@{ canContinue = $false; reason = $Reason; runId = ""; stage = "" }
    }

    if (-not (Test-QaFoundryProviderTransientFailure -Message $Failure)) {
        return (& $refusal "the fault is not one that clears by itself")
    }
    if ($null -eq $RunDirectory) {
        return (& $refusal "no analysis run was left on disk to continue")
    }
    $statePath = Join-Path $RunDirectory.FullName "workflow-state.json"
    $state = $null
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -Depth 100
    }
    catch {
        return (& $refusal "the run state could not be read")
    }
    $status = & $read $state "status"
    if ($status -in @("completed", "blocked", "cancelled")) {
        return (& $refusal "the run had already settled as '$status'")
    }
    $currentStage = & $read $state "currentStage"
    if ([string]::IsNullOrWhiteSpace($currentStage)) {
        return (& $refusal "the run names no stage to continue from, so the crash was outside the analysis")
    }
    $stages = if ($state.PSObject.Properties.Name -contains "stages") { @($state.stages) } else { @() }
    $stage = @($stages | Where-Object { (& $read $_ "id") -eq $currentStage })
    if ($stage.Count -ne 1) {
        return (& $refusal "the run state does not describe stage '$currentStage'")
    }
    if ((& $read $stage[0] "type") -eq "deterministic_action") {
        $handler = & $read $stage[0] "handler"
        if ([string]::IsNullOrWhiteSpace($handler)) {
            return (& $refusal ("stage '$currentStage' acts on the world and does not say how, " +
                "so replaying it is not provably safe"))
        }
        if ($handler -notin $script:RelayReplayableHandlers) {
            return (& $refusal ("stage '$currentStage' runs '$handler', which may already have " +
                "changed something outside this repository"))
        }
    }
    $runId = & $read $state "runId"
    $priorRecoveries = @(Get-RelayIncidents | Where-Object {
        (& $read $_ "runId") -eq $runId -and
        (& $read $_ "stage") -eq $currentStage -and
        (& $read $_ "recovered") -eq "True"
    }).Count
    if ($script:RelayLedgerLost) {
        return (& $refusal ("the record of how often stage '$currentStage' has already been carried " +
            "past a crash could not be read, and carrying it again on an unknown count is how a " +
            "permanently broken stage gets retried until the run runs out of legs"))
    }
    if ($priorRecoveries -ge $script:RelayRecoveryLimit) {
        return (& $refusal ("stage '$currentStage' has already been carried past $priorRecoveries " +
            "crash(es); a fault this persistent is a defect, not weather"))
    }
    return [pscustomobject]@{
        canContinue = $true
        reason = "stage '$currentStage' can be run again without changing anything outside this repository"
        runId = $runId
        stage = $currentStage
    }
}

# Whether a blocked run stopped on money rather than on a judgement. Returns the
# evidence when it did and nothing when it did not, so the caller cannot mistake
# an unreadable state for a licence to continue.
function Get-CarriedBudgetBlock {
    param([Parameter(Mandatory)][object]$RunDirectory)

    $statePath = Join-Path $RunDirectory "workflow-state.json"
    if (-not (Test-Path -LiteralPath $statePath)) { return $null }
    $state = $null
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -Depth 100
    }
    catch {
        # A state that cannot be read is not a state that says 'continue'.
        return $null
    }
    if ($null -eq $state) { return $null }
    if ((@(Get-QaFoundryPropertyNames -InputObject $state) -contains "blockedReason") -and
        ([string]$state.blockedReason -eq "run_budget_exhausted")) {
        return "the run recorded that it stopped on its spending budget"
    }
    $confirmed = Get-QaFoundryConfirmedBudgetBlock -State $state -RunRoot $RunDirectory
    if ([bool]$confirmed.confirmed) { return [string]$confirmed.reason }
    return $null
}

$result = $null
$status = ""
$legFailure = ""
$progressStarted = $false
$progress = $null
$admission = $null
$previousRunDeadline = $env:FOUNDRY_RUN_DEADLINE_UTC
# Nothing below may throw past this script. An exception that escapes leaves
# relayStatus unset, and the next leg's condition then reads an empty string
# instead of a decision, which is how build 453 ended without a diagnosis.
try {
    $resume = Get-ResumableRun
    $resumeRoot = ""
    $carriedStatus = ""
    if ($null -ne $resume) {
        $carriedStatus = Get-RunStatus -RunDirectory $resume.FullName
    }
    # A run that already blocked is finished. Handing it back to the bootstrap
    # would restart a decision that was already made, so the leg reports the
    # blocker it found and stops without calling anything.
    #
    # A stop on spending is the exception, and only that one. Nothing about the
    # work was decided: the run was refused more money, and a larger allowance
    # removes the refusal. So a block that is confirmed to be one - by the state
    # saying so, or by its shape when the state predates saying so - is handed
    # over, and the workflow decides against the ceiling actually configured
    # now. This leg does not do that arithmetic; if the allowance is still too
    # small the workflow blocks again and the relay stops here as before.
    $budgetBlock = $null
    if ($carriedStatus -eq "blocked" -and $null -ne $resume) {
        $budgetBlock = Get-CarriedBudgetBlock -RunDirectory $resume.FullName
    }
    if ($RestartStage -and $null -eq $resume) { throw '-RestartStage requires a selected saved run.' }
    if ($carriedStatus -eq "blocked" -and $null -eq $budgetBlock -and -not $RestartStage) {
        Write-Host ("##[warning]The run in $ArtifactRoot/$($resume.Name) had already blocked. " +
            "This leg carries that result forward rather than restarting it.")
        $status = "blocked"
    }
    else {
        if ($null -ne $budgetBlock) {
            Write-Host ("The run in $ArtifactRoot/$($resume.Name) stopped on its spending budget " +
                "rather than on a decision: $budgetBlock. This leg hands it back so the " +
                "configured allowance decides whether it continues.")
        }
        if ($null -ne $resume) {
            $resumeRoot = Join-Path $ArtifactRoot $resume.Name
            Write-Host "Resuming the analysis run at $resumeRoot"
        }
        else {
            Write-Host "No resumable run on disk; this leg starts the analysis."
        }

        $recoveryArguments = @{}
        if ($RestartStage) { $recoveryArguments.RestartStage = $RestartStage }
        if ($DocumentationLinks -and $DocumentationLinks -ne 'none') { $recoveryArguments.DocumentationLinks = $DocumentationLinks }
        $admission = Invoke-RelayProgress -Action begin
        if (-not $admission.allowed) {
            $status = 'blocked'
            Write-Host "##[warning]Relay stopped: $($admission.reason). Saved work and accounting are retained."
        }
        else {
        $progressStarted = $true
        $env:FOUNDRY_RUN_DEADLINE_UTC = [DateTime]::UtcNow.AddSeconds([double]$admission.remainingSeconds).ToString('o')
        $bootstrapOutput = @(& $BootstrapScript @recoveryArguments `
            -ConfigPath $BootstrapConfigPath `
            -Phase $Phase `
            -ResumeRunRoot $resumeRoot `
            -BudgetMinutes $BudgetMinutes)
        if ($bootstrapOutput.Count -eq 0 -or $null -eq $bootstrapOutput[-1]) {
            $legFailure = "Bootstrap returned no result."
        }
        else {
            $result = $bootstrapOutput[-1]
            $statusProperty = $result.PSObject.Properties["status"]
            if ($null -eq $statusProperty) {
                $legFailure = "Bootstrap result does not contain a status."
            }
            else {
                $status = ([string]$statusProperty.Value).Trim()
                $knownStatuses = @(
                    "paused",
                    "awaiting_merge",
                    "dry_run",
                    "plan_applied",
                    "pull_request_created",
                    "installed",
                    "failed",
                    "blocked",
                    "cancelled"
                )
                if ([string]::IsNullOrWhiteSpace($status)) {
                    $legFailure = "Bootstrap result contains an empty status."
                }
                elseif ($status -notin $knownStatuses) {
                    $legFailure = "Bootstrap returned unknown status '$status'."
                }
            }
        }
        }
    }
}
catch {
    $legFailure = $_.Exception.Message
}
finally {
    $env:FOUNDRY_RUN_DEADLINE_UTC = $previousRunDeadline
}

try {
    if ($progressStarted -or $null -ne $admission) {
        $progressStatus = if ($legFailure) { 'failed' } else { $status }
        $progress = Invoke-RelayProgress -Action finish -Status $progressStatus
        Write-Host ("Progress: $(@($progress.completedStages).Count)/$($progress.totalStages) stages; " +
            "$(@($progress.accepted).Count) accepted artifacts; $($progress.retries) retries; " +
            "$([Math]::Round($progress.remainingSeconds / 60, 1)) work minutes remain.")
        if ($status -eq 'paused' -and $progress.reason) {
            $status = 'blocked'
            Write-RelayContinuation -Reason $progress.reason
            Write-Host "##[warning]Relay stopped: $($progress.reason)."
        }
        elseif ($status -eq 'blocked' -and $null -ne $admission -and -not $admission.allowed) {
            Write-RelayContinuation -Reason $admission.reason
        }
    }
} catch {
    $legFailure = "$legFailure Progress accounting: $($_.Exception.Message)".Trim()
}

# An error used to stop the relay unconditionally. That is right for a defect:
# carrying a run around a crash would build the delivery on top of whatever the
# crash skipped and then report the result as though nothing had happened. It
# was wrong for weather. Build 474 reached the last stage of eleven and threw
# away four finished legs because one model call came back 400, while the run
# sat mid-stage on disk, fit to continue. So a crash is now classified: a fault
# that clears by itself, in a stage that can be run again without touching
# anything outside this repository, hands the run to the next leg, which re-runs
# that stage in full. Anything else still stops the relay, and a stage that has
# been carried twice is treated as the defect it evidently is.
if ($legFailure) {
    $survivor = $null
    try { $survivor = Get-ResumableRun } catch { $survivor = $null }
    $recovery = Get-CrashRecovery -Failure $legFailure -RunDirectory $survivor
    if ($null -ne $progress -and $progress.reason) {
        $recovery.canContinue = $false
        $recovery.reason = [string]$progress.reason
    }
    if ($recovery.canContinue) {
        Add-RelayIncident -Message $legFailure -RunId $recovery.runId `
            -Stage $recovery.stage -Recovered $true
        Write-Host "##[warning]Leg $LegIndex was interrupted: $legFailure"
        Write-Host ("##[warning]The relay continues: $($recovery.reason). " +
            "The next invocation resumes the same run at stage '$($recovery.stage)', which is re-run " +
            "in full rather than skipped.")
        if ($IsFinalLeg) {
            Write-RelayContinuation -Reason 'recoverable_interruption'
            Write-Host '##vso[task.setvariable variable=relayStatus;isOutput=true]continuation_required'
            Write-Host '##vso[task.complete result=SucceededWithIssues;]Saved recoverable interruption; continuation required.'
        } else {
            Write-Host "##vso[task.setvariable variable=relayStatus;isOutput=true]paused"
        }
        exit 0
    }
    Add-RelayIncident -Message $legFailure `
        -RunId ([string]$recovery.runId) -Stage ([string]$recovery.stage) -Recovered $false
    Write-Host "##[error]Leg $LegIndex crashed: $legFailure"
    Write-Host "##[error]The relay stops here because $($recovery.reason)."
    if ($null -ne $survivor) {
        $runStatus = Get-RunStatus -RunDirectory $survivor.FullName
        Write-Host ("##[error]The run was left at status '$runStatus' in $ArtifactRoot/$($survivor.Name). " +
            "This leg publishes its evidence either way, so the crash is diagnosed from the artifact " +
            "rather than from another three-hour run.")
    }
    Write-Host "##vso[task.setvariable variable=relayStatus;isOutput=true]failed"
    exit 1
}

if ($status -eq "paused") {
    Write-Host ("##[warning]This leg spent its budget on an agent boundary. " +
        "The next leg continues the same run.")
    if ($IsFinalLeg) {
        Write-RelayContinuation -Reason 'relay_segment_exhausted'
        $status = 'continuation_required'
        Write-Host '##[warning]This relay segment is complete; the analysis is unfinished. Continue from relay-continuation.json.'
        Write-Host '##vso[task.complete result=SucceededWithIssues;]Continuation required; analysis is not complete.'
    }
}

Write-Host "Leg $LegIndex finished as '$status'."
Write-Host "##vso[task.setvariable variable=relayStatus;isOutput=true]$status"

if ($status -in @("failed", "blocked", "cancelled")) {
    Write-Host "##[error]The analysis ended as '$status'."
    exit 1
}

# Without this the leg inherits whatever exit code the last native command left
# behind. A rejected-and-retried agent artifact makes node exit 1, which failed
# leg 2 of build 455 after it had already paused successfully. Refusing to
# invent a failure that did not happen is not the same as tolerating one.
exit 0
