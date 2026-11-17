. (Join-Path $PSScriptRoot 'RunInputs.ps1')

function Get-QaFoundryRecoveryArchive {
    param([string]$RunRoot, [string]$RunId, [string]$StageId)
    $manifest = Join-Path $RunRoot 'run-inputs.json'
    $directory = Join-Path $RunRoot 'recovery'
    if (-not (Test-Path $manifest) -or -not (Test-Path $directory)) { return $null }
    $current = Get-Content $manifest -Raw | ConvertFrom-Json -Depth 30
    foreach ($archive in @(Get-ChildItem $directory -Directory | Sort-Object Name -Descending)) {
        $requestPath = Join-Path $archive.FullName 'recovery-request.json'
        $statePath = Join-Path $archive.FullName 'workflow-state.json'
        $inputsPath = Join-Path $archive.FullName 'run-inputs.json'
        if (-not (Test-Path $requestPath) -or -not (Test-Path $statePath) -or -not (Test-Path $inputsPath)) { continue }
        $request = Get-Content $requestPath -Raw | ConvertFrom-Json
        if ($StageId -notin @($request.invalidated)) { continue }
        try { Assert-QaFoundryRunInputs -Recorded (Get-Content $inputsPath -Raw | ConvertFrom-Json -Depth 30) -Current $current }
        catch { return $null }
        $state = Get-Content $statePath -Raw | ConvertFrom-Json -Depth 100
        if ($state.runId -cne $RunId) { return $null }
        # A second recovery may archive only a failed invocation, with no
        # accepted inventory or generated source. Keep looking for the last
        # substantive stage evidence, without crossing an incompatible input.
        $savedStage = @($state.stages | Where-Object id -eq $StageId)
        if ($savedStage.Count -ne 1) { return $null }
        $withArtifacts = @($savedStage[0].attempts | Where-Object {
            $_.PSObject.Properties['artifacts'] -and @($_.artifacts).Count -gt 0
        })
        if ($withArtifacts.Count -eq 0) { continue }
        return [pscustomobject]@{ path = $archive.FullName; state = $state; request = $request }
    }
    return $null
}

function Resolve-QaFoundryRecoveryArtifact {
    param([string]$RunRoot, [object]$Archive, [object]$Record)
    # An upstream artifact can remain in the live run when only downstream stages
    # were archived. Its recorded hash must still agree before it is used.
    foreach ($base in @($Archive.path, $RunRoot)) {
        $path = Join-Path $base ([string]$Record.relativePath)
        if (-not (Test-PathWithinRoot -Candidate $path -Root $base)) { return '' }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        if ((Get-FileHash -LiteralPath $path).Hash -ne $Record.sha256) { return '' }
        return $path
    }
    return ''
}

function Get-QaFoundryRecoveryArtifact {
    param([string]$RunRoot, [string]$RunId, [string]$StageId, [string]$Name)
    $archive = Get-QaFoundryRecoveryArchive -RunRoot $RunRoot -RunId $RunId -StageId $StageId
    if ($null -eq $archive) { return $null }
    $stage = @($archive.state.stages | Where-Object id -eq $StageId)
    if ($stage.Count -ne 1) { return $null }
    foreach ($attempt in @($stage[0].attempts | Sort-Object iteration -Descending)) {
        if ($attempt.status -notin @('completed', 'approved', 'approved_with_dissent')) { continue }
        $record = @($attempt.artifacts | Where-Object name -eq $Name)
        if ($record.Count -ne 1) { continue }
        $path = Resolve-QaFoundryRecoveryArtifact -RunRoot $RunRoot -Archive $archive -Record $record[0]
        if (-not $path) { return $null }
        return [pscustomobject]@{ path = $path; archive = $archive; attempt = $attempt }
    }
    return $null
}

function New-QaFoundryRecoveryContext {
    param([string]$RunRoot, [string]$RunId, [string]$StageId, [string]$OutputPath, [string]$RepositoryRoot = '')
    $archive = Get-QaFoundryRecoveryArchive -RunRoot $RunRoot -RunId $RunId -StageId $StageId
    if ($null -eq $archive -or $archive.request.stageId -ne $StageId) { return '' }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Recovery after downstream verification')
    $lines.Add('This is a revision of the existing deliverable, even though the operator reset the stage counter. Read the supplied previous inventories and the failed verification below. Return only changed or new plannedFiles and explicit removedFiles; unchanged contracts are merged from the previous inventory. Correct the contracts that made verification impossible, rather than regenerating unrelated plans.')
    $lines.Add('The default local verification must execute real assertions without deployed endpoints or credentials. Listing tests, empty suites, skipped tests and weakened assertions do not satisfy it. Preserve deployed coverage with explicit configuration in its own execution selection. Plan the necessary local test files, runner selection, fixtures and commands together. Required resources must exist in the delivered Automation checkout or have an explicit setup contract; do not assume product files are present in the isolated verifier. Product code remains read-only. Use existing local application startup when supported by repository evidence; specify readiness and cleanup and distinguish substituted dependencies from end-to-end coverage.')
    $lines.Add('The verifier uses adapter entry points, not proposedCommands: npm test, and dotnet test or the MTP executable via dotnet run without an added filter. Category labels alone do not create a default selection. Inspect the selected ecosystem adapter and plan the actual runner-supported entry point/configuration plus any missing local tests. Preserve explicit deployed execution and its prerequisite refusal. The negative probe must run in that same local selection. Check all reported compiler locations against the locked dependency APIs; a guessed replacement overload is not a verified fix.')
    foreach ($stage in @($archive.state.stages)) {
        $attempts = @($stage.attempts | Where-Object {
            $_.status -in @('blocked', 'revision_required', 'failed') -and
            $_.PSObject.Properties['artifacts'] -and @($_.artifacts).Count -gt 0
        })
        if ($attempts.Count -eq 0) { continue }
        foreach ($record in @($attempts[-1].artifacts)) {
            if ($record.name -notmatch '^(framework-verification|change-set-batch-.+)\.json$') { continue }
            $path = Resolve-QaFoundryRecoveryArtifact -RunRoot $RunRoot -Archive $archive -Record $record
            if (-not $path) { throw "Recovery evidence cannot be verified: $($record.name)" }
            $document = Get-Content $path -Raw | ConvertFrom-Json -Depth 100
            if ($document.PSObject.Properties['projects']) {
                foreach ($project in @($document.projects | Where-Object outcome -ne verified)) {
                    $lines.Add("Failed project: $($project.projectPath). Evidence: $path")
                    foreach ($step in @($project.steps | Where-Object status -eq failed)) {
                        $lines.Add("$($step.name): $($step.detail)")
                        foreach ($reference in [regex]::Matches([string]$step.detail, 'Full output: (commands/[\w.-]+\.log) \[sha256: ([a-f0-9]{64})\]')) {
                            $logRoot = Split-Path $path -Parent
                            $logPath = Join-Path $logRoot $reference.Groups[1].Value
                            if (-not (Test-PathWithinRoot -Candidate $logPath -Root $logRoot) -or
                                -not (Test-Path -LiteralPath $logPath -PathType Leaf) -or
                                (Get-FileHash -LiteralPath $logPath).Hash -ne $reference.Groups[2].Value) {
                                throw 'Recovery command log failed its integrity check.'
                            }
                            $lines.Add("Read the full original diagnostics before revising contracts: $logPath")
                        }
                    }
                }
            }
            elseif ($document.status -in @('blocked', 'failed')) {
                $lines.Add("Implementation refusal (diagnosis, not an approved remedy): $($document.summary). Evidence: $path")
            }
        }
    }
    $lines.Add('Earlier runtime failures may have been fixed since these logs were recorded. Use them to identify contract inconsistencies; do not rewrite otherwise valid files to work around a repaired runtime fault. Subsequent materialization and real verification remain mandatory.')
    if ($RepositoryRoot -and $env:QA_FOUNDRY_RECOVERY_CANDIDATE -and $env:QA_FOUNDRY_RECOVERY_CANDIDATE -ne 'none') {
        . (Join-Path $PSScriptRoot 'RecoveryCandidate.ps1')
        $candidate = Get-QaFoundryRecoveryCandidate -RunRoot $RunRoot -RunId $RunId -RepositoryRoot $RepositoryRoot
        $lines.Add("The operator supplied exact source repairs after a real local build/test/negative-probe run: $($candidate.path) (SHA256 $($candidate.sha256)). Read this candidate and its verification limitations. Revise the necessary file contracts to account for its default local runners, support tests and SDK fixes; preserve all unrelated inventory. Candidate source is reused only for subsequently approved assignments; it does not waive review or CI verification. Do not invent additional changes merely because a stage was restarted.")
        $lines.Add('Candidate paths: ' + (@($candidate.document.changes.path) -join ', '))
    }
    Set-Content -LiteralPath $OutputPath -Value ($lines -join "`n`n") -Encoding utf8
    return $OutputPath
}

function Get-QaFoundryRecoveryGenerationSeed {
    param([string]$RunRoot, [string]$RunId, [string]$StageId, [string]$PlanName, [object]$CurrentSplit)
    $saved = Get-QaFoundryRecoveryArtifact -RunRoot $RunRoot -RunId $RunId -StageId $StageId -Name $PlanName
    if ($null -eq $saved) { return $null }
    $plan = Get-Content $saved.path -Raw | ConvertFrom-Json -Depth 100
    if ($plan.runId -cne $RunId -or $plan.status -ne 'completed') { return $null }
    $basisRecord = @($saved.attempt.artifacts | Where-Object name -eq 'batch-basis.json')
    if ($basisRecord.Count -ne 1) { return $null }
    $basisPath = Resolve-QaFoundryRecoveryArtifact -RunRoot $RunRoot -Archive $saved.archive -Record $basisRecord[0]
    if (-not $basisPath) { return $null }
    $basis = Get-Content $basisPath -Raw | ConvertFrom-Json -Depth 50
    $inventories = @()
    foreach ($entry in @($basis.inventories)) {
        $path = Resolve-QaFoundryRecoveryArtifact -RunRoot $RunRoot -Archive $saved.archive `
            -Record ([pscustomobject]@{ relativePath = $entry.path; sha256 = $entry.sha256 })
        if (-not $path) { return $null }
        $inventories += $path
    }
    if ($inventories.Count -eq 0) { return $null }
    $oldSplit = & (Join-Path $PSScriptRoot 'New-ChangeSetBatches.ps1') -InventoryPaths $inventories
    $oldFiles = @{}
    foreach ($file in @($oldSplit.approvedFiles)) { $oldFiles[$file.path] = $file.plannedFile }
    $changes = @{}
    foreach ($change in @($plan.changes)) {
        if ($changes.ContainsKey($change.path)) { return $null }
        $changes[$change.path] = $change
    }
    $regenerate = @()
    foreach ($file in @($CurrentSplit.approvedFiles)) {
        if (-not $oldFiles.ContainsKey($file.path) -or -not $changes.ContainsKey($file.path) -or
            [string]::IsNullOrWhiteSpace([string]$changes[$file.path].content) -or
            $changes[$file.path].operation -ne $file.plannedFile.operation -or
            (ConvertTo-Json $oldFiles[$file.path] -Depth 100 -Compress) -cne
                (ConvertTo-Json $file.plannedFile -Depth 100 -Compress)) {
            $regenerate += [string]$file.path
        }
    }
    return [pscustomobject]@{ planPath = $saved.path; paths = @($regenerate); instructions = @(
        [ordered]@{ reviewer = 'controlled-recovery'; paths = @($regenerate); instruction = 'Implement the revised approved contracts using the supplied existing source. Preserve unrelated working code and assertions. Local test selection must execute real checks, not list or skip them.' }
    ) }
}
