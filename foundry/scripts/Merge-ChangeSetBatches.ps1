# Merges the per-batch answers into the single plan the rest of the run expects.
#
# The point of this script is the checking, not the concatenation. Splitting the
# work across calls creates a failure the single-call design could not have: a
# batch that quietly drops a file, or invents one nobody approved, would produce
# a plan that looks complete and delivers a framework with a hole in it. So the
# merge refuses anything it cannot account for, and names what was wrong.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$BatchPaths,
    [Parameter(Mandatory)][string[]]$ExpectedPaths,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$AgentId,
    [Parameter(Mandatory)][string]$StageId,
    [Parameter(Mandatory)][string]$RunId,
    [string[]]$ResolverOwnedPaths = @(),
    [string]$MaterializationPath = "",
    # The plan a review rejected. Files outside the repair are taken from it
    # verbatim, so a rejection over three files costs three calls rather than
    # the forty-nine minutes build 496 spent regenerating all eight batches.
    [string]$CarriedPlanPath = "",
    [switch]$CarryAll,
    [string[]]$RegeneratedPaths = @(),
    # Files a blocked batch was allowed to write again, together with its own,
    # because it could not be satisfied without them. The earlier versions are
    # still in the batch artifacts and would otherwise read as duplicates, so
    # the first artifact to claim one of these paths keeps it and the rest are
    # dropped without complaint. The caller orders the escalated batch first.
    [string[]]$SupersededPaths = @()
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common.ps1")
if ($CarryAll -and (-not $CarriedPlanPath -or @($BatchPaths).Count -gt 0 -or @($RegeneratedPaths).Count -gt 0)) {
    throw 'CarryAll requires an existing plan and no generated batches or repair paths.'
}

function Get-Field {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object.PSObject.Properties.Name -notcontains $Name) { return $null }
    return $Object.$Name
}

$expected = @($ExpectedPaths | ForEach-Object { ([string]$_).Replace("\", "/").Trim() } |
    Where-Object { $_ })
if ($expected.Count -eq 0) {
    throw "The merge was given no approved paths to account for."
}

$changes = [System.Collections.Generic.List[object]]::new()
$producedBy = @{}

# Loaded before the batches, so a batch that writes outside its repair is
# caught against the same index the carry-forward reads from.
$carried = @{}
$carriedProvenance = $null
$regenerated = @($RegeneratedPaths | ForEach-Object { ([string]$_).Replace("\", "/").Trim() } |
    Where-Object { $_ } | Sort-Object -Unique)
$superseded = @($SupersededPaths | ForEach-Object { ([string]$_).Replace("\", "/").Trim() } |
    Where-Object { $_ } | Sort-Object -Unique)
if ($CarriedPlanPath) {
    if (-not (Test-Path -LiteralPath $CarriedPlanPath -PathType Leaf)) {
        throw "The plan to carry unchanged files forward from does not exist: $CarriedPlanPath"
    }
    if ($regenerated.Count -eq 0 -and -not $CarryAll) {
        throw ("A plan was offered to carry files forward from, but no path was named as " +
            "regenerated. Carrying every file forward would deliver the plan the review " +
            "just rejected.")
    }
    $carriedPlan = Get-Content -LiteralPath $CarriedPlanPath -Raw | ConvertFrom-Json -Depth 100
    foreach ($change in @(Get-Field -Object $carriedPlan -Name "changes")) {
        $carriedPath = ([string](Get-Field -Object $change -Name "path")).Replace("\", "/").Trim()
        if (-not $carriedPath) { continue }
        if ($regenerated -contains $carriedPath) { continue }
        if ($carriedPath -notin $expected) { continue }
        $carried[$carriedPath] = $change
    }
    $carriedProvenance = [ordered]@{
        plan = (Split-Path $CarriedPlanPath -Leaf)
        sha256 = (Get-FileHash -LiteralPath $CarriedPlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
        fileCount = $carried.Count
        regeneratedPaths = @($regenerated)
    }
}
$evidence = [System.Collections.Generic.List[object]]::new()
$evidenceSeen = [System.Collections.Generic.HashSet[string]]::new()
$assumptions = [System.Collections.Generic.List[string]]::new()
$unknowns = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$blocked = [System.Collections.Generic.List[string]]::new()
$unexpected = [System.Collections.Generic.List[string]]::new()
$duplicated = [System.Collections.Generic.List[string]]::new()

# Evidence entries are objects naming a source and what was read there, not
# sentences. Flattening them to strings produces a plan the schema rejects, and
# it rejects it after every batch has already been paid for.
function Add-MergedNarrative {
    param([Parameter(Mandatory)][object]$Document)

    foreach ($item in @(Get-Field -Object $Document -Name "evidence")) {
        if ($null -eq $item) { continue }
        $key = ([string](Get-Field -Object $item -Name "source") + "|" +
            [string](Get-Field -Object $item -Name "description"))
        if ($evidenceSeen.Add($key)) { $evidence.Add($item) }
    }
    foreach ($entry in @(
        @{ name = "assumptions"; list = $assumptions },
        @{ name = "unknowns"; list = $unknowns },
        @{ name = "warnings"; list = $warnings }
    )) {
        foreach ($item in @(Get-Field -Object $Document -Name ([string]$entry.name))) {
            if ($null -eq $item) { continue }
            $entry.list.Add([string]$item)
        }
    }
}

foreach ($batchPath in @($BatchPaths)) {
    if (-not (Test-Path -LiteralPath $batchPath -PathType Leaf)) {
        throw "Batch artifact does not exist: $batchPath"
    }
    $batch = Get-Content -LiteralPath $batchPath -Raw | ConvertFrom-Json -Depth 100
    $batchId = [string](Get-Field -Object $batch -Name "batchId")
    # A batch that failed is as unusable as one that refused, and it arrives
    # with an empty changes array rather than an error. Treated as ordinary it
    # merges silently, and the run notices only when the merge complains that
    # the files it owned came back from nobody.
    if ([string](Get-Field -Object $batch -Name "status") -in @("blocked", "failed") -or
        [string](Get-Field -Object $batch -Name "outcome") -in @("blocked", "failed")) {
        $blocked.Add(("$batchId" + ": " + [string](Get-Field -Object $batch -Name "summary")))
        continue
    }
    Add-MergedNarrative -Document $batch
    foreach ($change in @(Get-Field -Object $batch -Name "changes")) {
        $path = [string](Get-Field -Object $change -Name "path")
        $normalised = $path.Replace("\", "/").Trim()
        if ($producedBy.ContainsKey($normalised)) {
            if ($normalised -in $superseded) { continue }
            $duplicated.Add("$normalised (in $($producedBy[$normalised]) and $batchId)")
            continue
        }
        if ($normalised -notin $expected) {
            $unexpected.Add("$normalised (from $batchId)")
            continue
        }
        # A repair is bounded by the files it was asked to repair. A batch that
        # rewrites a file the review called correct is silently discarding a
        # judgement the run has already paid a review cycle for.
        if ($regenerated.Count -gt 0 -and $normalised -notin $regenerated) {
            $unexpected.Add("$normalised (from $batchId, which was not asked to repair it)")
            continue
        }
        $producedBy[$normalised] = $batchId
        $changes.Add($change)
    }
}

foreach ($carriedPath in @($carried.Keys | Sort-Object)) {
    if ($producedBy.ContainsKey($carriedPath)) { continue }
    $producedBy[$carriedPath] = "carried"
    $changes.Add($carried[$carriedPath])
}

$missing = @($expected | Where-Object { -not $producedBy.ContainsKey($_) })

# A batch that refused is a judgement about the work and is reported as one. It
# is not merged into a partial plan: half a framework applied to a repository is
# worse than a run that stopped and said why.
if ($blocked.Count -gt 0) {
    $plan = [ordered]@{
        agentId = $AgentId
        stageId = $StageId
        runId = $RunId
        status = "blocked"
        summary = "$($blocked.Count) of $(@($BatchPaths).Count) batch(es) did not propose changes."
        evidence = @($evidence)
        assumptions = @($assumptions)
        unknowns = @($unknowns)
        warnings = @($warnings)
        details = [ordered]@{
            blockedBatches = @($blocked)
            filesWithoutContent = @($missing)
        }
        outcome = "blocked"
        changes = @()
        materializations = @()
    }
    $plan | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    return [pscustomobject]@{
        status = "blocked"
        outputPath = $OutputPath
        changeCount = 0
        blocked = @($blocked)
    }
}

$complaints = @()
if ($missing.Count -gt 0) {
    $complaints += ("$($missing.Count) approved file(s) came back from no batch: " +
        (@($missing | Select-Object -First 10) -join ", "))
}
if ($unexpected.Count -gt 0) {
    $complaints += ("$($unexpected.Count) change(s) name a path the run never approved: " +
        (@($unexpected | Select-Object -First 10) -join ", "))
}
if ($duplicated.Count -gt 0) {
    $complaints += ("$($duplicated.Count) file(s) were written by more than one batch: " +
        (@($duplicated | Select-Object -First 10) -join ", "))
}
if ($complaints.Count -gt 0) {
    throw ("The generated batches do not add up to the approved inventory. " +
        ($complaints -join " ") +
        " The plan is not written, because a plan that is quietly incomplete delivers a " +
        "framework with a hole in it.")
}

$materializations = @()
if ($MaterializationPath) {
    if (-not (Test-Path -LiteralPath $MaterializationPath -PathType Leaf)) {
        throw "Materialization plan does not exist: $MaterializationPath"
    }
    $materializationPlan = Get-Content -LiteralPath $MaterializationPath -Raw |
        ConvertFrom-Json -Depth 100
    if ([string](Get-Field -Object $materializationPlan -Name "status") -eq "blocked") {
        # A planner that refuses has made a judgement, and the run needs to see
        # it as a refusal rather than as a crash in the merge. Raising an
        # exception here ends the leg with a stack trace and loses the reason.
        $refusal = [string](Get-Field -Object $materializationPlan -Name "summary")
        $blockedPlan = [ordered]@{
            agentId = $AgentId
            stageId = $StageId
            runId = $RunId
            status = "blocked"
            summary = "The materialization planner refused: $refusal"
            evidence = @($evidence)
            assumptions = @($assumptions | Select-Object -Unique)
            unknowns = @($unknowns | Select-Object -Unique)
            warnings = @($warnings | Select-Object -Unique)
            outcome = "blocked"
            changes = @()
            materializations = @()
        }
        $blockedPlan | ConvertTo-Json -Depth 100 |
            Set-Content -LiteralPath $OutputPath -Encoding utf8
        return [pscustomobject]@{
            status = "blocked"
            outputPath = $OutputPath
            changeCount = 0
            materializationCount = 0
        }
    }
    $materializations = @(Get-Field -Object $materializationPlan -Name "materializations")
    Add-MergedNarrative -Document $materializationPlan
    # A manifest is only worth resolving if this plan actually writes it.
    foreach ($materialization in @($materializations)) {
        $manifestPath = ([string](Get-Field -Object $materialization -Name "manifestPath")).Replace("\", "/")
        if (-not $producedBy.ContainsKey($manifestPath)) {
            throw ("The materialization plan names manifest '$manifestPath', which no batch wrote. " +
                "A resolver cannot lock a file that the change set does not contain.")
        }
    }
}

# A lock file is withheld from the batches because a model cannot honestly write
# one, not because the change set may go without it. Nothing so far ties the two
# halves together: the batches are complete without the lock, and the plan is
# valid without a materialization that produces it. So a planner that answered
# 'no action needed', or simply forgot, would leave the run delivering a
# framework whose dependencies were never locked, and every check would pass.
$resolverOwned = @($ResolverOwnedPaths | ForEach-Object { ([string]$_).Replace("\", "/").Trim() } |
    Where-Object { $_ } | Sort-Object -Unique)
if ($resolverOwned.Count -gt 0) {
    $lockPaths = @($materializations | ForEach-Object {
        ([string](Get-Field -Object $_ -Name "lockPath")).Replace("\", "/").Trim()
    } | Where-Object { $_ })
    $unlocked = @($resolverOwned | Where-Object { $lockPaths -notcontains $_ })
    if ($unlocked.Count -gt 0) {
        throw ("$($unlocked.Count) path(s) were withheld from the batches for a resolver to " +
            "produce, and the materialization plan does not produce them: " +
            (@($unlocked) -join ", ") +
            ". They were left out of the generated files on the understanding that a resolver " +
            "would write them, so a plan that does not name them delivers a change set with a " +
            "hole where its dependency lock should be.")
    }
}

$planDetails = [ordered]@{
    batches = @($BatchPaths | ForEach-Object { Split-Path $_ -Leaf })
}
if ($null -ne $carriedProvenance) { $planDetails["carriedForward"] = $carriedProvenance }
$planDetails["filesPerBatch"] = @($producedBy.GetEnumerator() | Sort-Object Name | ForEach-Object {
    [ordered]@{ path = $_.Key; batchId = $_.Value }
})

$plan = [ordered]@{
    agentId = $AgentId
    stageId = $StageId
    runId = $RunId
    status = "completed"
    summary = ("$($changes.Count) approved file(s) generated across $(@($BatchPaths).Count) batch(es)" +
        $(if ($null -ne $carriedProvenance) {
            ", of which $($carriedProvenance.fileCount) were carried forward unchanged from the " +
            "previous plan"
        } else { "" }) +
        ", with $(@($materializations).Count) manifest(s) handed to the resolver.")
    evidence = @($evidence)
    assumptions = @($assumptions | Select-Object -Unique)
    unknowns = @($unknowns | Select-Object -Unique)
    warnings = @($warnings | Select-Object -Unique)
    details = $planDetails
    outcome = "proposed"
    changes = @($changes)
    materializations = @($materializations)
}
$plan | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding utf8

return [pscustomobject]@{
    status = "completed"
    outputPath = $OutputPath
    changeCount = $changes.Count
    materializationCount = @($materializations).Count
}
