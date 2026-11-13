[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$Workflow,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][object]$Policy,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunId,
    [switch]$Resume,
    [AllowNull()][object]$Deadline = $null,
    [hashtable]$ProviderEnvironment = @{},
    [hashtable]$ActionEnvironment = @{}
)

. (Join-Path $PSScriptRoot "Common.ps1")

$statePath = Join-Path $RunRoot "workflow-state.json"
$index = 0
if ($Resume) {
    $state = & (Join-Path $PSScriptRoot "Load-WorkflowState.ps1") -Path $statePath
    # A state written before runs recorded why they stopped has no such field.
    # It is added as unstated rather than assumed, so the checks below can read
    # it without deciding on its behalf.
    if ((Get-QaFoundryPropertyNames -InputObject $state) -notcontains "blockedReason") {
        Add-Member -InputObject $state -MemberType NoteProperty -Name "blockedReason" -Value $null
    }
    if ($state.workflowName -ne $Workflow.name -or
        [int]$state.workflowVersion -ne [int]$Workflow.version) {
        throw "Saved state does not match the requested workflow."
    }
    if ($state.status -eq "completed") {
        return $state
    }
    if ($state.status -eq "blocked") {
        # A run blocked on judgement - a critic that said no, coverage a stage
        # could not complete - is not resumable: the thing that stopped it is a
        # decision only a person can make, and continuing would walk past it.
        #
        # A run blocked on spending is a different case. Nothing was judged
        # wrong; the run was simply not allowed to buy any more. Once the
        # allowance is raised the reason for stopping no longer exists, and
        # refusing to continue would throw away every artifact already paid for
        # - which for build 972449 was twenty-five million tokens of work. So
        # the condition is re-tested rather than the operator taken at their
        # word: if the run is still over its ceiling it stays blocked.
        $budgetBlocked = ((Get-QaFoundryPropertyNames -InputObject $state) -contains "blockedReason") -and
            ([string]$state.blockedReason -eq "run_budget_exhausted")
        if (-not $budgetBlocked -and [string]::IsNullOrWhiteSpace([string]$state.blockedReason)) {
            # An older run never wrote down why it stopped, so its own shape is
            # read instead - narrowly, and only far enough to tell a stage that
            # never ran from a decision that went against it.
            $inferred = Get-QaFoundryConfirmedBudgetBlock -State $state -RunRoot $RunRoot
            if ([bool]$inferred.confirmed) {
                $budgetBlocked = $true
                Write-QaFoundryLog -Level "info" -Message (
                    "This run stopped before it recorded a reason. Its state confirms a stop on " +
                    "spending rather than on a decision: $($inferred.reason).")
            }
            else {
                Write-QaFoundryLog -Level "warn" -Message (
                    "This run stopped before it recorded a reason, and its state does not confirm " +
                    "a stop on spending: $($inferred.reason).")
            }
        }
        $stillOverspent = if ($budgetBlocked) {
            Test-QaFoundryRunBudgetExhausted -RunRoot $RunRoot -Config $Config
        }
        else { "the run was blocked by a decision rather than by its budget" }
        if ($null -ne $stillOverspent) {
            throw "Blocked workflows require an explicit new run after human resolution: $stillOverspent."
        }
        Write-QaFoundryLog -Level "info" -Message (
            "Resuming a run that was blocked on its spending budget: the allowance now covers " +
            "what it has already spent.")
        $state.blockedReason = $null
        $blockedStage = @($state.stages | Where-Object { $_.id -eq [string]$state.currentStage })
        if ($blockedStage.Count -eq 1 -and $blockedStage[0].status -eq "blocked") {
            # The stage never ran, so its iteration was spent on nothing. Rewind
            # it the way a paused leg does, or the stage would come back with one
            # attempt already charged against its limit.
            $blockedStage[0].status = "pending"
            $blockedStage[0].iteration = [Math]::Max(0, [int]$blockedStage[0].iteration - 1)
            $state.stageIteration = [int]$blockedStage[0].iteration
        }
    }
    $matchingIndex = -1
    for ($resumeScan = 0; $resumeScan -lt @($Workflow.stages).Count; $resumeScan++) {
        if ([string]$Workflow.stages[$resumeScan].id -eq [string]$state.currentStage) {
            $matchingIndex = $resumeScan
            break
        }
    }
    if ($matchingIndex -lt 0) {
        throw "Saved currentStage is not present in the workflow."
    }
    $index = $matchingIndex
    # A state left in 'running' means the previous process stopped without
    # reporting a result. Record that gap before the stage is retried.
    if ($state.status -eq "running") {        $abandoned = @($state.stages | Where-Object { $_.id -eq [string]$state.currentStage })
        if ($abandoned.Count -eq 1 -and $abandoned[0].status -eq "running") {
            $abandoned[0].attempts += [pscustomobject][ordered]@{
                iteration = [int]$abandoned[0].iteration
                status = "failed"
                decision = $null
                startedAt = [string]$state.updatedAt
                completedAt = [DateTime]::UtcNow.ToString("o")
                interrupted = $true
                error = "The previous run process stopped before this stage reported a result."
            }
            $abandoned[0].status = "failed"
        }
    }
    $state.status = "running"
}
else {
    $stageStates = @($Workflow.stages | ForEach-Object {
        $entry = [ordered]@{
            id = [string]$_.id
            type = [string]$_.type
            status = "pending"
            iteration = 0
            attempts = @()
        }
        # Whoever decides that an interrupted run may continue has to know what
        # the interrupted stage was doing. Replaying an agent costs time; replaying
        # a handler that already created work items or pushed a branch costs
        # duplicates nobody asked for. The name of the handler is the only thing
        # that tells the two apart, so the state carries it.
        if (($_.PSObject.Properties.Name -contains "action") -and $null -ne $_.action -and
            ($_.action.PSObject.Properties.Name -contains "handler")) {
            $entry["handler"] = [string]$_.action.handler
        }
        [pscustomobject]$entry
    })
    $state = [pscustomobject][ordered]@{
        workflowName = [string]$Workflow.name
        workflowVersion = [int]$Workflow.version
        runId = $RunId
        status = "running"
        currentStage = $null
        stageIteration = 0
        # Why a run stopped, when the reason matters to whoever picks it up. A
        # block for judgement needs a person; a block for spending needs only a
        # larger allowance, and the two must be told apart.
        blockedReason = $null
        startedAt = [DateTime]::UtcNow.ToString("o")
        updatedAt = [DateTime]::UtcNow.ToString("o")
        stages = $stageStates
    }
}
& (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath

$iterationCounts = @{}
$state.stages | ForEach-Object {
    $iterationCounts[[string]$_.id] = [int]$_.iteration
}
$stageIndexById = @{}
for ($scan = 0; $scan -lt @($Workflow.stages).Count; $scan++) {
    $stageIndexById[[string]$Workflow.stages[$scan].id] = $scan
}

$stageState = $null
$runSettled = $false
# Only the stage a leg resumes into may already hold artifacts. Every later
# stage in the same leg must still be produced, so immutability stays in force.
$reuseStageArtifacts = [bool]$Resume
try {

while ($index -lt @($Workflow.stages).Count) {
    $stage = $Workflow.stages[$index]
    $stageId = [string]$stage.id
    if (Test-QaFoundryBudgetExhausted -Deadline $Deadline) {
        $state.status = "paused"
        $state.currentStage = $stageId
        $state.stageIteration = [int]$iterationCounts[$stageId]
        & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath
        Write-QaFoundryLog -Level "warn" -Message (
            "Pausing before stage '$stageId': the time budget for this leg is spent. " +
            "The run keeps every artifact produced so far and can be resumed.")
        $runSettled = $true
        return $state
    }
    if (-not $iterationCounts.ContainsKey($stageId)) {
        $iterationCounts[$stageId] = 0
    }
    $iterationCounts[$stageId] = [int]$iterationCounts[$stageId] + 1
    $iteration = [int]$iterationCounts[$stageId]
    $stageState = @($state.stages | Where-Object { $_.id -eq $stageId })[0]
    $stageState.status = "running"
    $stageState.iteration = $iteration
    $state.currentStage = $stageId
    $state.stageIteration = $iteration
    & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath

    $attemptStarted = [DateTime]::UtcNow.ToString("o")
    $stageStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $iterationLabel = if ($iteration -gt 1) { " (iteration $iteration)" } else { "" }
    Write-QaFoundryLog -Level step -Message (
        "Stage $($index + 1) of $(@($Workflow.stages).Count): $($stageId.Replace('-', ' '))$iterationLabel.")
    try {
        $result = & (Join-Path $PSScriptRoot "Invoke-Stage.ps1") `
            -Stage $stage `
            -Workflow $Workflow `
            -Config $Config `
            -Policy $Policy `
            -RunRoot $RunRoot `
            -RepositoryRoot $RepositoryRoot `
            -RunId $RunId `
            -Iteration $iteration `
            -ProviderEnvironment $ProviderEnvironment `
            -ActionEnvironment $ActionEnvironment `
            -Deadline $Deadline `
            -ReuseExistingArtifacts:$reuseStageArtifacts
        $reuseStageArtifacts = $false
        $stageStopwatch.Stop()
        $stageLevel = if ([string]$result.Status -in @("failed", "blocked")) { "warn" } else { "step" }
        Write-QaFoundryLog -Level $stageLevel -Indent 1 -Message (
            "Stage '$stageId' finished as '$([string]$result.Status)' " +
            "in $(Format-QaFoundryDuration $stageStopwatch.Elapsed).")
        $stageState.status = [string]$result.Status
        $stageState.attempts += [pscustomobject][ordered]@{
            iteration = $iteration
            status = [string]$result.Status
            decision = $result.Decision
            startedAt = $attemptStarted
            completedAt = [DateTime]::UtcNow.ToString("o")
            artifactDirectory = [string]$result.ArtifactDirectory
            artifacts = @($result.Artifacts)
            inputs = @($result.Inputs)
        }
        & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath

        foreach ($proof in @($result.Artifacts | Where-Object name -eq 'framework-verification.json')) {
            $verification = Get-Content -LiteralPath (Join-Path $RunRoot $proof.relativePath) -Raw | ConvertFrom-Json -Depth 50
            foreach ($project in @($verification.projects)) {
                Write-QaFoundryLog -Level step -Audience business -Message (
                    "$($project.projectPath): $($project.testsDiscovered) tests discovered, $($project.testsFailed) failed. Verification: $($project.outcome).")
            }
        }

        # Work that was never done is not a reviewer's opinion, so it is settled
        # before the machinery that exists to weigh reviewers' opinions. A stage
        # that names items it did not produce is repeated on the spot: it needs
        # no earlier stage to return to, because the missing work belongs to
        # this stage, and no 'proceed' setting may wave it through, because
        # there is nothing to proceed with.
        if ($result.Status -eq "revision_required" -and
            ($result.PSObject.Properties.Name -contains "CoverageIncomplete") -and
            [bool]$result.CoverageIncomplete) {
            $coverageApproval = if ($stage.PSObject.Properties.Name -contains "approval") {
                $stage.approval
            }
            else { $null }
            # Producer/critic rounds have already spent their revision allowance
            # inside Invoke-Stage. Do not multiply that allowance by starting the
            # entire loop again when its final artifact still has omissions.
            $coverageMaximum = if ($stage.type -eq 'producer_critic_loop') { 1 }
            elseif ($null -ne $coverageApproval -and
                ($coverageApproval.PSObject.Properties.Name -contains "max_iterations") -and
                $coverageApproval.max_iterations) {
                [int]$coverageApproval.max_iterations
            }
            else {
                [int]$Config.runtime.max_stage_iterations
            }
            $missing = @($result.Deferrals | ForEach-Object {
                "$([string]$_.agentId): $([string]$_.item)"
            })
            if ($iteration -lt $coverageMaximum) {
                Write-QaFoundryLog -Level warn -Indent 1 -Message (
                    "Stage '$stageId' left $($missing.Count) item(s) undone and is repeated with " +
                    "a full output budget (iteration $($iteration + 1) of $coverageMaximum): " +
                    ((@($missing | Select-Object -First 8) -join "; ")) + ".")
                $stageState.status = "revision_required"
                & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath
                continue
            }
            $state.status = "blocked"
            $stageState.status = "blocked"
            $state.currentStage = $stageId
            $state.blockedReason = 'coverage_iteration_limit'
            & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath
            Write-QaFoundryLog -Level "warn" -Indent 1 -Message (
                "Stage '$stageId' still leaves $($missing.Count) item(s) undone after " +
                "$coverageMaximum attempt(s), so the run stops rather than delivering work it " +
                "has written down as missing: " +
                ((@($missing | Select-Object -First 8) -join "; ")) + ".")
            $runSettled = $true
            return $state
        }
        if ($result.Status -eq "revision_required") {
            $approval = if ($stage.PSObject.Properties.Name -contains "approval") {                $stage.approval
            }
            else { $null }
            $maximum = if ($null -ne $approval -and
                ($approval.PSObject.Properties.Name -contains "max_iterations") -and
                $approval.max_iterations) {
                [int]$approval.max_iterations
            }
            else {
                [int]$Config.runtime.max_stage_iterations
            }
            # A producer_critic_loop revises inside the stage, so it has no earlier stage to
            # return to. Reaching here means its own critic iterations were spent without
            # unanimity, which is an outcome to report, not a missing configuration.
            $returnTo = if ($null -ne $approval -and
                ($approval.PSObject.Properties.Name -contains "on_reject") -and
                ($approval.on_reject.PSObject.Properties.Name -contains "return_to")) {
                [string]$approval.on_reject.return_to
            }
            else { "" }
            # Whether a rejecting stage has somewhere to send the work is a
            # different question from whether revised work exists at all. A
            # producer_critic_loop revises inside itself: when its critics run
            # out of rounds, the last revision the producer wrote is on disk and
            # recorded in state. Conflating the two is how build 476 discarded a
            # blueprint that four rounds of critique had already improved.
            $hasReturnTarget = -not [string]::IsNullOrWhiteSpace($returnTo)
            $carriesRevisedArtifact = $hasReturnTarget -or
                ([string]$stage.type -eq "producer_critic_loop")
            if ($iteration -ge $maximum -or -not $hasReturnTarget) {
                $reason = if (-not $carriesRevisedArtifact) {
                    "critics_never_agreed"
                }
                else { "iteration_limit_reached" }
                $onExhaustion = if ($null -ne $approval -and
                    ($approval.PSObject.Properties.Name -contains "on_exhaustion")) {
                    [string]$approval.on_exhaustion
                }
                else { "block" }
                # A reviewer that still dissents has made a judgement about work that
                # exists. Ending the run destroys both the work and the judgement;
                # continuing publishes them together, and the branch this run opens is
                # read by a person before anything merges. A stage that carries no
                # revised work has nothing to continue with, so it still stops. A
                # critic that answered 'blocked' never reaches here: that ends the
                # stage itself and stops the run regardless of this setting.
                if ($onExhaustion -eq "proceed" -and $carriesRevisedArtifact) {
                    $stageState.status = "approved_with_dissent"
                    # A later stage resolves a declared input from an attempt,
                    # not from the stage record, and takes only attempts whose
                    # own status says they succeeded. Marking the stage alone
                    # leaves a run whose architecture succeeded with dissent
                    # while every attempt it made still reads as a rejection.
                    # Build 479 carried that contradiction through six stages
                    # and crashed at stage 10 of 11, after two hours, because
                    # the blueprint it had been building on "never succeeded".
                    # The attempt just recorded is the one holding the revised
                    # artifact, so it carries the same verdict as the stage.
                    $lastAttempt = @($stageState.attempts)[-1]
                    if ($null -ne $lastAttempt) {
                        $lastAttempt.status = "approved_with_dissent"
                    }
                    & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath
                    Write-QaFoundryLog -Level error -Indent 1 -Message (
                        "Stage '$stageId' used all $maximum iteration(s) without unanimous approval. " +
                        "Unanimity is the expected outcome, so this run has a defect upstream of " +
                        "'$stageId' that needs fixing. The run continues rather than discarding the " +
                        "work, the delivery is marked as a draft, and every unresolved finding is " +
                        "published with it.")
                    $index++
                    continue
                }
                if ($Config.supervisor.enabled) {
                    $null = & (Join-Path $PSScriptRoot "Invoke-Supervisor.ps1") `
                        -Reason $reason `
                        -AllowedDecisions @("block", "fail") `
                        -Config $Config `
                        -RunRoot $RunRoot `
                        -RunId $RunId `
                        -Iteration $iteration `
                        -ProviderEnvironment $ProviderEnvironment `
                        -RepositoryRoot $RepositoryRoot
                }
                $state.status = "blocked"
                $stageState.status = "blocked"
                $state.currentStage = $stageId
                & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath
                # Reviewers who never agreed have judged the work, and an iteration
                # limit is a boundary this run was configured to respect. Neither is a
                # defect in the runtime, so both end the run as a terminal blocker that
                # travels back as a status rather than as an exception.
                if (-not $hasReturnTarget) {
                    Write-QaFoundryLog -Level "warn" -Indent 1 -Message (
                        "Stage '$stageId' spent all $maximum critic iteration(s) without unanimous " +
                        "approval and blocked the run. The last artifact and every review are in " +
                        "the run directory.")
                }
                else {
                    Write-QaFoundryLog -Level "warn" -Indent 1 -Message (
                        "Stage '$stageId' reached its iteration limit of $maximum and blocked the run.")
                }
                $runSettled = $true
                return $state
            }

            if (-not $stageIndexById.ContainsKey($returnTo)) {
                throw "Invalid deterministic revision target: $returnTo"
            }
            $returnIndex = [int]$stageIndexById[$returnTo]
            if ($returnIndex -ge $index) {
                throw "Revision target '$returnTo' must precede rejecting stage '$stageId'."
            }
            $index = $returnIndex
            continue
        }
        if ($result.Status -eq "blocked") {
            # A stage that reports 'blocked' has judged the work rather than crashed on
            # it: it read its inputs and reported a terminal blocker instead of
            # producing something unsafe. That judgement is the outcome of the run, so
            # it travels back as a status instead of an exception and the leg reports a
            # stopped run rather than a defect. The run still ends here and is not
            # resumable.
            $state.status = "blocked"
            $state.blockedReason = if ($result.PSObject.Properties['BlockedReason'] -and $result.BlockedReason) {
                [string]$result.BlockedReason
            } else { 'stage_blocked' }
            if ($result.PSObject.Properties['Deferrals']) {
                $state | Add-Member -NotePropertyName blockers -NotePropertyValue @($result.Deferrals) -Force
                foreach ($blocker in @($result.Deferrals)) {
                    Write-QaFoundryLog -Level warn -Message "[$($blocker.kind)] $($blocker.item): $($blocker.reason)"
                }
            }
            $state.currentStage = $stageId
            & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath
            Write-QaFoundryLog -Level "warn" -Indent 1 -Message (
                "Stage '$stageId' blocked the run. Its artifact records why.")
            $runSettled = $true
            return $state
        }
        if ($result.Status -eq "failed") {
            $state.status = "failed"
            & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath
            throw "Stage '$stageId' ended with status 'failed'."
        }
        $index++
    }
    catch {
        if (Test-QaFoundryBudgetStop -Message $_) {
            # The stage stopped on an agent boundary while there was still time
            # to save state. Rewind the iteration counter so the next leg
            # re-enters the same stage directory and reuses finished agents.
            $stageState.status = "pending"
            $stageState.iteration = $iteration - 1
            $state.status = "paused"
            $state.currentStage = $stageId
            $state.stageIteration = $iteration - 1
            & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath
            Write-QaFoundryLog -Level "warn" -Indent 1 -Message (
                "Paused: " + (Get-QaFoundryBudgetStopMessage -Message $_) + ".")
            $runSettled = $true
            return $state
        }
        if (Test-QaFoundryRunBudgetStop -Message $_) {
            # Not a pause. The run has spent what it was allowed to spend, and
            # resuming it would only spend more, so it is blocked: a terminal
            # state the CI wrapper reports as a failed build rather than a
            # handover the next leg would pick up. Everything produced so far
            # stays on disk for a person to judge.
            $stageState.status = "blocked"
            $state.status = "blocked"
            $state.blockedReason = "run_budget_exhausted"
            $state.currentStage = $stageId
            $state.stageIteration = $iteration
            & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath
            Write-QaFoundryLog -Level "warn" -Indent 1 -Message (
                "Blocked: " + (Get-QaFoundryRunBudgetStopMessage -Message $_) + ". " +
                "Reconcile the recorded spending limit or narrow the work before running again; do not automatically raise the allowance.")
            $runSettled = $true
            return $state
        }
        if ($state.status -eq "running") {
            $state.status = "failed"
            $stageState.status = "failed"
            $stageState.attempts += [pscustomobject][ordered]@{
                iteration = $iteration
                status = "failed"
                decision = $null
                startedAt = $attemptStarted
                completedAt = [DateTime]::UtcNow.ToString("o")
                error = $_.Exception.Message
            }
            & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath
        }
        throw
    }
}

$state.status = "completed"
$state.currentStage = $null
$state.stageIteration = 0
& (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath
$runSettled = $true
return $state

}
finally {
    # Ctrl+C, a stopped pipeline or a terminated host must not leave a run
    # advertising 'running' forever. Persist a bounded, auditable failure.
    if (-not $runSettled -and [string]$state.status -eq "running") {
        $state.status = "failed"
        if ($null -ne $stageState) {
            $stageState.status = "failed"
            $stageState.attempts += [pscustomobject][ordered]@{
                iteration = [int]$stageState.iteration
                status = "failed"
                decision = $null
                startedAt = [string]$state.updatedAt
                completedAt = [DateTime]::UtcNow.ToString("o")
                interrupted = $true
                error = "The run was interrupted before stage '$([string]$stageState.id)' reported a result."
            }
        }
        & (Join-Path $PSScriptRoot "Save-WorkflowState.ps1") -State $state -Path $statePath
    }
}
