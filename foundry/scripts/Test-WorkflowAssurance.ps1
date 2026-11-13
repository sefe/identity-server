[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$Workflow,
    [Parameter(Mandatory)][object]$Config
)

. (Join-Path $PSScriptRoot "Common.ps1")
$null = @(Get-QaFoundryCollaborationProfileNames -Config $Config)

$mode = [string]$Config.assurance.mode
if ($mode -ne "maximum") {
    return [pscustomobject]@{
        valid = $true
        mode = $mode
        stageCount = @($Workflow.stages).Count
    }
}

if ([int]$Config.assurance.minimum_specialists -lt 2 -or
    [int]$Config.assurance.minimum_reviewers -lt 2 -or
    [int]$Config.assurance.high_risk_minimum_specialists -lt 3 -or
    [int]$Config.assurance.high_risk_minimum_reviewers -lt 3 -or
    [int]$Config.assurance.high_risk_minimum_specialists -lt
        [int]$Config.assurance.minimum_specialists -or
    [int]$Config.assurance.high_risk_minimum_reviewers -lt
        [int]$Config.assurance.minimum_reviewers -or
    -not [bool]$Config.assurance.require_unanimous_reviews -or
    -not [bool]$Config.assurance.require_deterministic_evidence) {
    throw "Maximum assurance requires at least three high-risk perspectives, unanimous reviews, and deterministic evidence."
}

$stages = @($Workflow.stages)
$stageIndex = @{}
$stageById = @{}
for ($index = 0; $index -lt $stages.Count; $index++) {
    $stageIndex[[string]$stages[$index].id] = $index
    $stageById[[string]$stages[$index].id] = $stages[$index]
}
$highRisks = @("high", "critical")

function Get-AgentIdentity {
    param([Parameter(Mandatory)][object]$Agent)
    if ($Agent.PSObject.Properties.Name -contains "id") {
        return [string]$Agent.id
    }
    return [string]$Agent.agent
}

function Assert-UniqueIdentities {
    param(
        [Parameter(Mandatory)][string]$StageId,
        [Parameter(Mandatory)][string[]]$Identities
    )
    if (@($Identities | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_)
    }).Count -gt 0) {
        throw "Maximum assurance stage '$StageId' contains an empty agent identity."
    }
    if (@($Identities | Select-Object -Unique).Count -ne $Identities.Count) {
        throw "Maximum assurance stage '$StageId' must use distinct agent identities."
    }
}

function Assert-IndependentAgentSet {
    param(
        [Parameter(Mandatory)][string]$StageId,
        [Parameter(Mandatory)][object[]]$Agents
    )
    $identities = @($Agents | ForEach-Object {
        Get-AgentIdentity -Agent $_
    })
    Assert-UniqueIdentities -StageId $StageId -Identities $identities
    $prompts = @($Agents | ForEach-Object { [string]$_.prompt })
    if (@($prompts | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_)
    }).Count -gt 0 -or
        @($prompts | Select-Object -Unique).Count -ne $prompts.Count) {
        throw "Maximum assurance stage '$StageId' must use distinct non-empty role prompts."
    }
}

function Test-StageDependsOn {
    param(
        [Parameter(Mandatory)][string]$StageId,
        [Parameter(Mandatory)][string]$RequiredDependency
    )
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($StageId)
    $visited = @{}
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        if ($visited.ContainsKey($current)) {
            continue
        }
        $visited[$current] = $true
        $currentStage = $stageById[$current]
        $dependencies = if ($currentStage.PSObject.Properties.Name -contains "depends_on") {
            @($currentStage.depends_on | ForEach-Object { [string]$_ })
        }
        else {
            @()
        }
        if ($RequiredDependency -in $dependencies) {
            return $true
        }
        foreach ($dependency in $dependencies) {
            $pending.Push($dependency)
        }
    }
    return $false
}

foreach ($stage in $stages) {
    $stageId = [string]$stage.id
    $risk = if ($stage.PSObject.Properties.Name -contains "risk") {
        [string]$stage.risk
    }
    else {
        ""
    }
    if ($risk -notin @("low", "medium", "high", "critical")) {
        throw "Maximum assurance stage '$stageId' must declare low, medium, high, or critical risk."
    }
    $highRisk = $risk -in $highRisks

    # An input names an artifact by the stage that produced it. That stage has
    # to have already run, and this stage has to actually depend on it, or the
    # input resolves against whatever an unrelated branch of the workflow left
    # behind.
    $declaredInputSets = @()
    if (($stage.PSObject.Properties.Name -contains "inputs") -and $null -ne $stage.inputs) {
        $declaredInputSets += $stage.inputs
    }
    if (($stage.PSObject.Properties.Name -contains "action") -and $null -ne $stage.action -and
        ($stage.action.PSObject.Properties.Name -contains "inputs") -and $null -ne $stage.action.inputs) {
        $declaredInputSets += $stage.action.inputs
    }
    foreach ($declaredStageInputs in $declaredInputSets) {
        foreach ($property in @($declaredStageInputs.PSObject.Properties)) {
            $inputName = [string]$property.Name
            $specification = $property.Value
            $sourceStage = [string]$specification.stage
            if ([string]::IsNullOrWhiteSpace($sourceStage) -or
                [string]::IsNullOrWhiteSpace([string]$specification.artifact)) {
                throw "Input '$inputName' of '$stageId' must name both a stage and an artifact."
            }
            if (-not $stageIndex.ContainsKey($sourceStage)) {
                throw ("Input '$inputName' of '$stageId' names stage '$sourceStage', which this " +
                    "workflow does not run.")
            }
            if ([int]$stageIndex[$sourceStage] -ge [int]$stageIndex[$stageId]) {
                throw ("Input '$inputName' of '$stageId' names stage '$sourceStage', which does not " +
                    "run before it.")
            }
            if (-not (Test-StageDependsOn -StageId $stageId -RequiredDependency $sourceStage)) {
                throw ("Input '$inputName' of '$stageId' names stage '$sourceStage', which it does " +
                    "not transitively depend on.")
            }
        }
    }
    $specialistMinimum = if ($highRisk) {
        [int]$Config.assurance.high_risk_minimum_specialists
    }
    else {
        [int]$Config.assurance.minimum_specialists
    }
    $reviewerMinimum = if ($highRisk) {
        [int]$Config.assurance.high_risk_minimum_reviewers
    }
    else {
        [int]$Config.assurance.minimum_reviewers
    }

    switch ([string]$stage.type) {
        "parallel_with_synthesis" {
            $agentIds = @($stage.agents | ForEach-Object {
                Get-AgentIdentity -Agent $_
            })
            if ($agentIds.Count -lt $specialistMinimum) {
                throw "Maximum assurance stage '$stageId' requires at least $specialistMinimum independent specialists."
            }
            $synthesisAgent = [pscustomobject]@{
                agent = [string]$stage.synthesis.agent
                prompt = [string]$stage.synthesis.prompt
            }
            Assert-IndependentAgentSet -StageId $stageId `
                -Agents @(@($stage.agents) + @($synthesisAgent))
        }
        "producer_critic_loop" {
            $criticIds = @($stage.critics | ForEach-Object {
                Get-AgentIdentity -Agent $_
            })
            if ($criticIds.Count -lt $reviewerMinimum) {
                throw "Maximum assurance stage '$stageId' requires at least $reviewerMinimum independent critics."
            }
            Assert-IndependentAgentSet -StageId $stageId `
                -Agents @(@($stage.producer) + @($stage.critics))
            if ($Config.assurance.require_unanimous_reviews -and
                [string]$stage.approval.strategy -ne "unanimous") {
                throw "Maximum assurance stage '$stageId' must use unanimous critic approval."
            }
        }
        "parallel_review" {
            $reviewerIds = @($stage.agents | ForEach-Object {
                Get-AgentIdentity -Agent $_
            })
            if ($reviewerIds.Count -lt $reviewerMinimum) {
                throw "Maximum assurance stage '$stageId' requires at least $reviewerMinimum independent reviewers."
            }
            Assert-IndependentAgentSet -StageId $stageId -Agents @($stage.agents)
            if ($Config.assurance.require_unanimous_reviews -and
                [string]$stage.approval.strategy -ne "unanimous") {
                throw "Maximum assurance stage '$stageId' must use unanimous review approval."
            }
        }
        "sequential" {
            if (-not ($stage.PSObject.Properties.Name -contains "assurance")) {
                throw "Maximum assurance sequential stage '$stageId' must declare its assurance hand-off."
            }
            $reviewedBy = [string]$stage.assurance.reviewed_by
            if ([string]::IsNullOrWhiteSpace($reviewedBy) -or
                -not $stageIndex.ContainsKey($reviewedBy)) {
                throw "Maximum assurance stage '$stageId' has an invalid reviewed_by stage '$reviewedBy'."
            }
            if ([int]$stageIndex[$reviewedBy] -le [int]$stageIndex[$stageId] -or
                [string]$stages[[int]$stageIndex[$reviewedBy]].type -ne "parallel_review") {
                throw "Maximum assurance stage '$stageId' must be followed by its parallel review stage '$reviewedBy'."
            }
            if (-not (Test-StageDependsOn -StageId $reviewedBy `
                -RequiredDependency $stageId)) {
                throw "Maximum assurance review '$reviewedBy' must depend on stage '$stageId'."
            }
            if ($Config.assurance.require_deterministic_evidence) {
                $hasDirectEvidence = (
                    $stage.assurance.PSObject.Properties.Name -contains "deterministic_evidence"
                ) -and [bool]$stage.assurance.deterministic_evidence
                $evidenceFrom = if (
                    $stage.assurance.PSObject.Properties.Name -contains "evidence_from"
                ) { [string]$stage.assurance.evidence_from } else { "" }
                if (-not $hasDirectEvidence -and
                    ([string]::IsNullOrWhiteSpace($evidenceFrom) -or
                    -not $stageIndex.ContainsKey($evidenceFrom))) {
                    throw "Maximum assurance stage '$stageId' must declare deterministic evidence or a valid evidence_from stage."
                }
            }
            $agentIds = @($stage.agents | ForEach-Object {
                Get-AgentIdentity -Agent $_
            })
            Assert-IndependentAgentSet -StageId $stageId -Agents @($stage.agents)
        }
        "deterministic_action" {
            if (-not ($stage.PSObject.Properties.Name -contains "action") -or
                [string]$stage.action.handler -notin @(
                    "apply_change_set", "create_work_items", "quality_suite",
                    "collect_observability", "deliver_changes", "materialize_change_set",
                    "queue_pipeline", "resolve_toolchain", "verify_framework"
                ) -or [string]::IsNullOrWhiteSpace([string]$stage.action.output)) {
                throw "Maximum assurance deterministic action '$stageId' has an invalid action contract."
            }
            # An action that reads artifacts has to say which stage produced each
            # one. Searching the run directory finds the newest matching file,
            # and after a revision that is the wrong document.
            if ([string]$stage.action.handler -eq "materialize_change_set") {
                $declared = if ($stage.action.PSObject.Properties.Name -contains "inputs") {
                    $stage.action.inputs
                } else { $null }
                if ($null -eq $declared) {
                    throw "Deterministic action '$stageId' must declare its inputs by stage and artifact."
                }
                foreach ($required in @("plan", "blueprint")) {
                    $names = @($declared.PSObject.Properties.Name)
                    if ($names -notcontains $required) {
                        throw "Deterministic action '$stageId' must declare an input named '$required'."
                    }
                }
            }
            # A verification that searched the run directory for a change set
            # would find the newest one, and after a repair round that is the
            # attempt nobody approved.
            if ([string]$stage.action.handler -in @("resolve_toolchain", "verify_framework")) {
                $declared = if ($stage.action.PSObject.Properties.Name -contains "inputs") {
                    $stage.action.inputs
                } else { $null }
                if ($null -eq $declared) {
                    throw "Deterministic action '$stageId' must declare its inputs by stage and artifact."
                }
                $required = if ([string]$stage.action.handler -eq "resolve_toolchain") {
                    "blueprint"
                } else { "changeSet" }
                if (@($declared.PSObject.Properties.Name) -notcontains $required) {
                    throw "Deterministic action '$stageId' must declare an input named '$required'."
                }
            }
            # Running the chosen framework is the only stage that can prove the
            # technology decision, so a verification with nowhere to send a
            # failure is a check whose result nothing acts on.
            if ([string]$stage.action.handler -eq "verify_framework") {
                $approval = if ($stage.PSObject.Properties.Name -contains "approval") {
                    $stage.approval
                } else { $null }
                $returnTo = if ($null -ne $approval -and
                    ($approval.PSObject.Properties.Name -contains "on_reject") -and
                    ($approval.on_reject.PSObject.Properties.Name -contains "return_to")) {
                    [string]$approval.on_reject.return_to
                } else { "" }
                if ([string]::IsNullOrWhiteSpace($returnTo) -or -not $stageIndex.ContainsKey($returnTo)) {
                    throw ("Deterministic action '$stageId' must declare approval.on_reject.return_to " +
                        "naming the stage that repairs a framework that failed to run.")
                }
            }
            if ([string]$stage.action.handler -eq "queue_pipeline") {
                if (-not ($stage.action.PSObject.Properties.Name -contains "pipeline") -or
                    [string]::IsNullOrWhiteSpace([string]$stage.action.pipeline)) {
                    throw "Deterministic action '$stageId' must name the pipeline it starts."
                }
                $declared = if ($stage.action.PSObject.Properties.Name -contains "inputs") {
                    $stage.action.inputs
                } else { $null }
                if ($null -eq $declared) {
                    throw "Deterministic action '$stageId' must declare its inputs by stage and artifact."
                }
                foreach ($required in @("plan", "workItems")) {
                    if (@($declared.PSObject.Properties.Name) -notcontains $required) {
                        throw "Deterministic action '$stageId' must declare an input named '$required'."
                    }
                }
            }
            if ([string]$stage.action.handler -in @(
                "apply_change_set", "create_work_items", "deliver_changes", "queue_pipeline"
            )) {
                $approvedBy = if ($stage.PSObject.Properties.Name -contains "assurance") {
                    [string]$stage.assurance.approved_by
                } else { "" }
                if ([string]::IsNullOrWhiteSpace($approvedBy) -or
                    -not $stageIndex.ContainsKey($approvedBy) -or
                    [string]$stageById[$approvedBy].type -ne "parallel_review" -or
                    [int]$stageIndex[$approvedBy] -ge [int]$stageIndex[$stageId] -or
                    -not (Test-StageDependsOn -StageId $stageId -RequiredDependency $approvedBy)) {
                    throw "Mutating deterministic action '$stageId' must transitively depend on a prior parallel review declared in approved_by."
                }
            }
        }
        "batched_agent" {
            # The same hand-off a sequential stage owes, plus the batching
            # contract: the inventory it splits has to be a declared input, so
            # the split is taken from the document this run approved rather than
            # from whichever same-named file is newest on disk.
            if (-not ($stage.PSObject.Properties.Name -contains "assurance")) {
                throw "Maximum assurance batched stage '$stageId' must declare its assurance hand-off."
            }
            $reviewedBy = [string]$stage.assurance.reviewed_by
            if ([string]::IsNullOrWhiteSpace($reviewedBy) -or
                -not $stageIndex.ContainsKey($reviewedBy)) {
                throw "Maximum assurance stage '$stageId' has an invalid reviewed_by stage '$reviewedBy'."
            }
            if ([int]$stageIndex[$reviewedBy] -le [int]$stageIndex[$stageId] -or
                [string]$stages[[int]$stageIndex[$reviewedBy]].type -ne "parallel_review") {
                throw "Maximum assurance stage '$stageId' must be followed by its parallel review stage '$reviewedBy'."
            }
            if (-not (Test-StageDependsOn -StageId $reviewedBy `
                -RequiredDependency $stageId)) {
                throw "Maximum assurance review '$reviewedBy' must depend on stage '$stageId'."
            }
            if (-not ($stage.PSObject.Properties.Name -contains "batching")) {
                throw "Batched stage '$stageId' must declare a batching contract."
            }
            foreach ($required in @("inventory_inputs", "output", "schema")) {
                if (@($stage.batching.PSObject.Properties.Name) -notcontains $required) {
                    throw "Batched stage '$stageId' must declare batching.$required."
                }
            }
            $declaredInputNames = if ($stage.PSObject.Properties.Name -contains "inputs") {
                @($stage.inputs.PSObject.Properties.Name)
            }
            else { @() }
            foreach ($inventoryName in @($stage.batching.inventory_inputs)) {
                if ($declaredInputNames -notcontains [string]$inventoryName) {
                    throw ("Batched stage '$stageId' batches over '$inventoryName', which it does not " +
                        "declare as an input.")
                }
            }
            $roles = @($stage.agents | ForEach-Object { [string]$_.role })
            if (@($roles | Where-Object { $_ -eq "batch_generator" }).Count -ne 1) {
                throw "Batched stage '$stageId' must declare exactly one agent with role 'batch_generator'."
            }
            Assert-IndependentAgentSet -StageId $stageId -Agents @($stage.agents)
        }
        default {
            throw "Maximum assurance does not recognise stage type '$($stage.type)' in '$stageId'."
        }
    }
}

return [pscustomobject]@{
    valid = $true
    mode = $mode
    stageCount = $stages.Count
    highRiskStageCount = @($stages | Where-Object {
        [string]$_.risk -in $highRisks
    }).Count
}
