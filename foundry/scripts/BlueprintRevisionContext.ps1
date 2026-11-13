function Get-QaFoundryBlueprintRevisionContext {
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][object]$Stage,
        [Parameter(Mandatory)][int]$BeforeIteration
    )

    $empty = [pscustomobject]@{ basePath = ''; history = @(); revisionOffset = 0 }
    $statePath = Join-Path $RunRoot 'workflow-state.json'
    if ($BeforeIteration -le 1 -or -not (Test-Path -LiteralPath $statePath)) { return $empty }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -Depth 100
    if ($state.runId -cne $RunId) { throw 'Blueprint revision state belongs to another run.' }
    $entries = @($state.stages | Where-Object id -eq $Stage.id)
    if ($entries.Count -ne 1) { throw 'Blueprint revision stage is missing or ambiguous.' }
    $artifactDirectory = if ($Stage.PSObject.Properties['artifact_directory']) {
        [string]$Stage.artifact_directory
    } else { [string]$Stage.id }
    $producerName = Split-Path ([string]$Stage.producer.output) -Leaf
    $history = @()
    $offset = 0
    $basePath = ''
    foreach ($attempt in @($entries[0].attempts | Where-Object {
        [int]$_.iteration -lt $BeforeIteration -and
        $_.status -in @('completed', 'approved', 'approved_with_dissent', 'revision_required')
    } | Sort-Object iteration)) {
        $records = @($attempt.artifacts | Where-Object name -eq $producerName)
        if ($records.Count -eq 0) { continue }
        if ($records.Count -ne 1) { throw 'Blueprint revision base is ambiguous.' }
        $record = $records[0]
        $path = Join-Path $RunRoot ([string]$record.relativePath)
        if (-not (Test-PathWithinRoot -Candidate $path -Root $RunRoot) -or
            -not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash -LiteralPath $path).Hash -ne $record.sha256) {
            throw 'Recorded blueprint revision base failed its integrity check.'
        }
        $base = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
        $producerId = if ($Stage.producer.PSObject.Properties['id']) { [string]$Stage.producer.id } else { [string]$Stage.producer.agent }
        if ($base.runId -cne $RunId -or $base.stageId -cne $Stage.id -or
            $base.agentId -cne $producerId -or $base.status -ne 'completed') {
            throw 'Recorded blueprint revision base has an invalid identity or status.'
        }
        $iterationRoot = Join-Path $RunRoot $artifactDirectory
        if ([int]$attempt.iteration -gt 1) {
            $iterationRoot = Join-Path $iterationRoot "iteration-$($attempt.iteration)"
        }
        # The state names the final producer, not whichever draft is newest. Rebuild
        # only the bounded critic rounds leading to that producer, including legacy
        # runs which did not publish a separate history artifact.
        $lastRound = 0
        for ($round = 1; $round -le [int]$Stage.approval.max_iterations; $round++) {
            $directory = if ($round -eq 1) { $iterationRoot } else { Join-Path $iterationRoot "critic-iteration-$round" }
            if ([IO.Path]::GetFullPath((Join-Path $directory ([string]$Stage.producer.output))) -eq
                [IO.Path]::GetFullPath($path)) { $lastRound = $round; break }
        }
        if ($lastRound -eq 0) { throw 'Recorded blueprint is outside its declared critic rounds.' }
        for ($round = 1; $round -le $lastRound; $round++) {
            $directory = if ($round -eq 1) { $iterationRoot } else { Join-Path $iterationRoot "critic-iteration-$round" }
            foreach ($critic in @($Stage.critics)) {
                $reviewPath = Join-Path $directory ([string]$critic.output)
                if (-not (Test-PathWithinRoot -Candidate $reviewPath -Root $RunRoot)) {
                    throw 'Blueprint review escapes its run.'
                }
                $reviewRecords = @($attempt.artifacts | Where-Object name -eq (Split-Path ([string]$critic.output) -Leaf))
                if ($round -eq $lastRound -and $reviewRecords.Count -eq 0) { continue }
                if ($round -eq $lastRound -and $reviewRecords.Count -gt 0) {
                    if ($reviewRecords.Count -ne 1 -or
                        [IO.Path]::GetFullPath((Join-Path $RunRoot $reviewRecords[0].relativePath)) -ne [IO.Path]::GetFullPath($reviewPath) -or
                        -not (Test-Path -LiteralPath $reviewPath -PathType Leaf) -or
                        (Get-FileHash -LiteralPath $reviewPath).Hash -ne $reviewRecords[0].sha256) {
                        throw 'Recorded blueprint review failed its integrity check.'
                    }
                }
                # An incomplete producer may finish a round without invoking critics.
                if (-not (Test-Path -LiteralPath $reviewPath -PathType Leaf)) { continue }
                $review = Get-Content -LiteralPath $reviewPath -Raw | ConvertFrom-Json -Depth 100
                $criticId = if ($critic.PSObject.Properties['id']) { [string]$critic.id } else { [string]$critic.agent }
                if ($review.runId -cne $RunId -or $review.stageId -cne $Stage.id -or $review.agentId -cne $criticId -or
                    $review.status -ne 'completed' -or $review.decision -notin @('approved', 'revision_required')) {
                    throw 'Blueprint review history has an invalid identity or decision.'
                }
                $history += [pscustomobject]@{
                    revision = $offset + $round; criticId = $criticId; decision = [string]$review.decision
                    findings = @($review.findings); requiredChanges = @($review.requiredChanges)
                }
            }
        }
        $offset += $lastRound
        $basePath = $path
    }
    return [pscustomobject]@{ basePath = $basePath; history = @($history); revisionOffset = $offset }
}
