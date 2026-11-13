. (Join-Path $PSScriptRoot 'ProductDefects.ps1')

function Get-QaFoundryProductFailureSignature {
    param([string]$Text)
    $plain = $Text -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in @($plain -split '\r?\n' | Select-Object -Skip 1)) {
        $value = $line.Trim()
        if ($value -match '^(Test run summary:|total:|\d+ (failed|passed)|Full output:)') { break }
        if (-not $value -or $value -match '^(at |Stack trace:|Traceback |File ")') { continue }
        $lines.Add($value)
    }
    if ($lines.Count -eq 0) { return '' }
    return Get-QaFoundryInputHash -Text ($lines -join "`n")
}

function Get-QaFoundryQualityProductDefectContext {
    param([string]$RunRoot, [string]$ChangeSetPath, [string]$RepositoryRoot)
    if (-not $RunRoot -or -not $ChangeSetPath) { return $null }
    $state = Get-Content (Join-Path $RunRoot 'workflow-state.json') -Raw | ConvertFrom-Json -Depth 100
    if ($state.status -ne 'completed') { throw 'Product defect evidence requires a completed analysis run.' }
    $materialization = @($state.stages | Where-Object id -eq 'bootstrap-change-materialization')
    $verification = @($state.stages | Where-Object id -eq 'framework-verification')
    if ($materialization.Count -ne 1 -or $verification.Count -ne 1) { throw 'Missing materialization or verification evidence.' }
    $materializedAttempt = @($materialization[0].attempts)[-1]
    $verifiedAttempt = @($verification[0].attempts)[-1]
    if ($materializedAttempt.status -ne 'completed' -or $verifiedAttempt.status -ne 'completed' -or
        -not $materializedAttempt.completedAt -or -not $verifiedAttempt.startedAt -or
        [datetime]$verifiedAttempt.startedAt -lt [datetime]$materializedAttempt.completedAt) {
        throw 'The latest completed verification must follow the delivered materialization.'
    }
    function Read-RecordedArtifact {
        param([object]$Attempt, [string]$Name, [switch]$Raw)
        $records = @($Attempt.artifacts | Where-Object name -CEQ $Name)
        if ($records.Count -ne 1) { throw "Missing unique recorded artifact '$Name'." }
        $path = Resolve-QaFoundryRunArtifactPath -RunRoot $RunRoot -RelativePath $records[0].relativePath -Description $Name
        if ((Get-FileHash -LiteralPath $path).Hash -ne $records[0].sha256) { throw "Recorded artifact '$Name' changed." }
        $text = Get-Content -LiteralPath $path -Raw
        if ($Raw) { return $text }
        return $text | ConvertFrom-Json -Depth 100
    }
    $changeSet = Read-RecordedArtifact $materializedAttempt 'change-set.json'
    $record = @($materializedAttempt.artifacts | Where-Object name -CEQ 'change-set.json')[0]
    if ((Get-FileHash -LiteralPath $ChangeSetPath).Hash -ne $record.sha256) { throw 'Delivered changes differ from the verified materialization.' }
    $proof = Read-RecordedArtifact $verifiedAttempt 'framework-verification.json'
    if ($proof.runId -cne $state.runId -or $changeSet.runId -cne $state.runId -or $proof.outcome -ne 'verified') {
        throw 'The framework was not verified in this analysis run.'
    }
    $candidates = @($proof.projects | Where-Object { $_.outcome -eq 'verified' -and $_.testsFailed -gt 0 })
    if ($candidates.Count -eq 0) { return $null }
    # The final collector runs after installation. Match actual installed bytes,
    # including locks, to the approved source before considering any known Bug.
    foreach ($change in $changeSet.changes) {
        $path = Join-Path $RepositoryRoot $change.path
        if (-not (Test-PathWithinRoot -Candidate $path -Root $RepositoryRoot)) { throw 'Delivered path escapes the repository.' }
        if ($change.operation -eq 'delete') {
            if (Test-Path -LiteralPath $path) { throw "Deleted source still exists: $($change.path)" }
        } elseif (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
            [string](Get-Content -LiteralPath $path -Raw) -cne [string]$change.content) {
            throw "Installed source differs from verified source: $($change.path)"
        }
    }
    $analysis = Read-RecordedArtifact $verifiedAttempt 'product-defect-analysis.json'
    $reviews = @($verifiedAttempt.artifacts | Where-Object name -Match '^product-defect-review-\d+\.json$' |
        ForEach-Object { Read-RecordedArtifact $verifiedAttempt $_.name })
    $receipt = Read-RecordedArtifact $verifiedAttempt 'product-defect-bugs.json'
    $bugPlan = Read-RecordedArtifact $verifiedAttempt 'product-defect-plan.json'
    if ($receipt.runId -cne $state.runId -or $receipt.dryRun -or $receipt.status -ne 'completed') {
        throw 'The product Bug receipt does not record a real completed write.'
    }
    if ($bugPlan.runId -cne $state.runId -or $bugPlan.status -ne 'completed') { throw 'The product Bug plan belongs to another run.' }
    $projects = @()
    foreach ($project in $candidates) {
        if (-not $project.negativeProbe.attempted -or -not $project.negativeProbe.failedAsExpected -or
            @($project.steps | Where-Object { $_.status -eq 'failed' -and $_.name -ne 'test' }).Count) { continue }
        $test = @($project.steps | Where-Object name -eq 'test')
        if ($test.Count -ne 1 -or $test[0].detail -notmatch 'Full output: commands/(command-\d+\.log) \[sha256: ([a-f0-9]{64})\]') { continue }
        $logName = $Matches[1]; $logHash = $Matches[2]
        $logRecord = @($verifiedAttempt.artifacts | Where-Object name -CEQ $logName)
        if ($logRecord.Count -ne 1 -or $logRecord[0].sha256 -ne $logHash) { continue }
        $output = Read-RecordedArtifact $verifiedAttempt $logName -Raw
        $cases = @(Get-QaFoundryFailedTestCases -Text $output -ProjectPath $project.projectPath)
        $confirmed = @(Get-QaFoundryConfirmedProductDefects -Cases $cases -Analysis $analysis -Review $reviews `
            -ChangeSet $changeSet -RepositoryRoot $RepositoryRoot -MinimumConfirmations 3)
        if ($cases.Count -ne $project.testsFailed -or $confirmed.Count -ne $cases.Count) { continue }
        $bugs = @(); $signatures = @{}
        foreach ($case in $cases) {
            $defect = @($confirmed | Where-Object sourceRef -CEQ $case.sourceRef)[0]
            $retained = @($bugPlan.details.retainedTests | Where-Object sourceRef -CEQ $case.sourceRef)
            if ($retained.Count -ne 1 -or $retained[0].testSha256 -cne $defect.testSha256) { continue }
            $sources = @($retained[0].requirementSources)
            if ($sources.Count -ne @($defect.requirementSources).Count -or @($defect.requirementSources | Where-Object {
                $current = $_
                @($sources | Where-Object { $_.path -ceq $current.path -and $_.sha256 -ceq $current.sha256 }).Count -ne 1
            }).Count -gt 0) { continue }
            $actions = @($receipt.actions | Where-Object { $_.sourceRef -ceq ('product-defect:' + $case.sourceRef) -and
                $_.status -in @('executed','duplicate') -and [string]$_.externalId -match '^[1-9][0-9]*$' })
            if ($actions.Count -ne 1) { continue }
            $signature = Get-QaFoundryProductFailureSignature $case.output
            if (-not $signature) { continue }
            $bugs += [string]$actions[0].externalId
            $signatures[$case.sourceRef] = $signature
        }
        if ($bugs.Count -eq $cases.Count) {
            $projects += [pscustomobject]@{ path = $project.projectPath; ecosystem = $project.ecosystem
                total = $project.testsDiscovered; failed = $project.testsFailed; signatures = $signatures; bugs = $bugs }
        }
    }
    return [pscustomobject]@{ projects = $projects }
}

function Get-QaFoundryQualityProductBugIds {
    param([object]$Context, [string]$ProjectPath, [string]$Ecosystem, [string]$Output, [int]$ExitCode)
    if ($null -eq $Context -or $ExitCode -eq 0) { return @() }
    $projects = @($Context.projects | Where-Object { $_.path -ceq $ProjectPath -and $_.ecosystem -ceq $Ecosystem })
    if ($projects.Count -ne 1) { return @() }
    $project = $projects[0]
    $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $Ecosystem
    $summary = & $adapter.ReadTestRunSummary $Output $ExitCode
    if (-not $summary.parsed -or $summary.skipped -ne 0 -or
        $summary.total -ne $project.total -or $summary.failed -ne $project.failed) { return @() }
    $cases = @(Get-QaFoundryFailedTestCases -Text $Output -ProjectPath $ProjectPath)
    if ($cases.Count -ne $project.failed) { return @() }
    foreach ($case in $cases) {
        if (-not $project.signatures.ContainsKey($case.sourceRef) -or
            (Get-QaFoundryProductFailureSignature $case.output) -cne $project.signatures[$case.sourceRef]) { return @() }
    }
    return @($project.bugs)
}
