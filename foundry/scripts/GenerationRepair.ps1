# Runtime helpers; these do not change the approved inventory or verification gates.
function Get-QaFoundryVerificationFailureDigest {
    param([string]$Text)
    $plain = $Text -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $lines = @($plain -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -match '^(?:[\w.]+Exception:|Assertion failed\.|schema=|expected:|actual:|Error:|error\b)' -or
        $_ -match '(?i)(?:error [A-Z]+\d+:|has not been resolved|permission denied)'
    } | Select-Object -Unique)
    if ($lines.Count -eq 0) { return '' }
    $digest = ($lines | Select-Object -First 24) -join "`n"
    if ($digest.Length -gt 6000) { $digest = $digest.Substring(0, 6000) }
    return "Distinct failure details (read the full log for all affected tests):`n$digest"
}

function Test-QaFoundryAssignedBatchCoverage {
    param([object]$Artifact, [AllowNull()][object]$Assignment)
    if ($null -eq $Assignment -or $null -eq $Artifact) { return $false }
    $names = @(Get-QaFoundryPropertyNames -InputObject $Artifact)
    if ('changes' -notin $names -or 'batchId' -notin $names -or
        'deferrals' -notin $names -or 'status' -notin $names -or 'outcome' -notin $names) { return $false }
    if ($Artifact.status -ne 'completed' -or @($Artifact.deferrals).Count -ne 0 -or
        $Artifact.outcome -ne 'proposed' -or [string]$Artifact.batchId -cne [string]$Assignment.batchId) { return $false }
    $expected = @($Assignment.assignedPaths)
    $changes = @($Artifact.changes)
    if ($expected.Count -eq 0 -or $changes.Count -ne $expected.Count) { return $false }
    foreach ($path in $expected) {
        $matching = @($changes | Where-Object { [string]$_.path -ceq [string]$path })
        if ($matching.Count -ne 1 -or $matching[0].operation -notin @('create', 'update') -or
            'content' -notin @(Get-QaFoundryPropertyNames -InputObject $matching[0]) -or
            [string]::IsNullOrWhiteSpace([string]$matching[0].content)) { return $false }
    }
    # This proves delivery of the assignment, not correctness of its source code.
    # Materialization, compilation, actual tests, the negative probe and review still follow.
    return $true
}

function Get-QaFoundryRecordedGenerationBase {
    param([string]$RunRoot, [string]$RunId, [string]$StageId, [string]$PlanName, [int]$BeforeIteration)
    $statePath = Join-Path $RunRoot 'workflow-state.json'
    if (-not (Test-Path -LiteralPath $statePath)) { return $null }
    $state = Get-Content $statePath -Raw | ConvertFrom-Json -Depth 100
    $stage = @($state.stages | Where-Object id -CEQ $StageId)
    if ($stage.Count -ne 1) { return $null }
    $attempts = @($stage[0].attempts | Where-Object {
        $_.status -eq 'completed' -and [int]$_.iteration -lt $BeforeIteration
    } | Sort-Object iteration -Descending)
    if ($attempts.Count -eq 0) { return $null }
    $attempt = $attempts[0]
    $paths = @{}
    foreach ($name in @($PlanName, 'batch-basis.json')) {
        $record = @($attempt.artifacts | Where-Object name -CEQ $name)
        if ($record.Count -ne 1) { throw "Recorded repair base is missing '$name'; refusing full regeneration." }
        $path = Resolve-QaFoundryRunArtifactPath -RunRoot $RunRoot -RelativePath $record[0].relativePath
        if ((Get-FileHash -LiteralPath $path).Hash -ne $record[0].sha256) {
            throw "Recorded repair base '$name' changed; refusing full regeneration."
        }
        $paths[$name] = $path
    }
    $plan = Get-Content $paths[$PlanName] -Raw | ConvertFrom-Json -Depth 100
    if ($plan.runId -cne $RunId -or $plan.status -ne 'completed') {
        throw 'Recorded repair base does not describe a completed plan of this run.'
    }
    return [pscustomobject]@{ planPath = $paths[$PlanName]; basisPath = $paths['batch-basis.json']; iteration = [int]$attempt.iteration }
}

function Get-QaFoundryVerificationRepair {
    param([string]$RunRoot, [string]$RunId, [int]$Iteration, [object]$Plan,
        [string[]]$ApprovedPaths)
    $statePath = Join-Path $RunRoot 'workflow-state.json'
    if (-not (Test-Path -LiteralPath $statePath)) { return $null }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -Depth 100
    $documents = @{}
    $materializationAttempt = $null
    $verificationDirectory = ''
    foreach ($spec in @(
        @{ stage = 'bootstrap-change-materialization'; name = 'change-set.json'; status = 'completed' },
        @{ stage = 'framework-verification'; name = 'framework-verification.json'; status = 'revision_required' }
    )) {
        $stage = @($state.stages | Where-Object { $_.id -eq $spec.stage })
        if ($stage.Count -ne 1) { return $null }
        $attempt = @($stage[0].attempts | Where-Object { [int]$_.iteration -eq $Iteration })
        $latest = @($stage[0].attempts | Select-Object -Last 1)
        if ($spec.stage -eq 'bootstrap-change-materialization' -and $latest.Count -eq 1 -and
            $latest[0].PSObject.Properties['completedAt']) {
            # Generation, materialization and verification have independent
            # counters. Use the latest recorded source, then bind its bodies below.
            $attempt = $latest
        }
        if ($spec.stage -eq 'framework-verification' -and
            $null -ne $materializationAttempt -and $materializationAttempt.PSObject.Properties['completedAt']) {
            # Select only execution after that source was materialized, including
            # when a same-numbered but stale verification also exists.
            $attempt = @($stage[0].attempts | Where-Object {
                $_.PSObject.Properties['startedAt'] -and
                [datetime]$_.startedAt -ge [datetime]$materializationAttempt.completedAt
            })
        }
        if ($attempt.Count -eq 0 -or $attempt[-1].status -ne $spec.status) { return $null }
        if ($spec.stage -eq 'framework-verification' -and
            $materializationAttempt.PSObject.Properties['completedAt'] -and $attempt[-1].PSObject.Properties['startedAt'] -and
            [datetime]$attempt[-1].startedAt -lt [datetime]$materializationAttempt.completedAt) { return $null }
        $record = @($attempt[-1].artifacts | Where-Object { $_.name -eq $spec.name })
        if ($record.Count -ne 1) { return $null }
        $path = Join-Path $RunRoot $record[0].relativePath
        if (-not (Test-PathWithinRoot -Candidate $path -Root $RunRoot) -or
            -not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $record[0].sha256) { return $null }
        $document = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
        if ($document.runId -cne $RunId) { return $null }
        $documents[$spec.name] = $document
        if ($spec.stage -eq 'bootstrap-change-materialization') { $materializationAttempt = $attempt[-1] }
        else { $verificationDirectory = Split-Path $path -Parent }
    }
    # Verification must be about exactly the authored bodies we intend to carry.
    # Resolver-owned lock files may additionally exist in the materialized change set.
    foreach ($change in @($Plan.changes)) {
        $materialized = @($documents['change-set.json'].changes | Where-Object { $_.path -ceq $change.path })
        if ($materialized.Count -ne 1 -or $materialized[0].operation -ne $change.operation -or
            [string]$materialized[0].content -cne [string]$change.content) { return $null }
    }
    $verification = $documents['framework-verification.json']
    if ($verification.outcome -ne 'toolchain_defect') { return $null }
    $targets = @()
    foreach ($project in @($verification.projects)) {
        if ($project.outcome -eq 'verified') { continue }
        if ($project.outcome -ne 'toolchain_defect') { return $null }
        $projectPrefix = ([string]$project.projectPath).Replace('\', '/').TrimEnd('/') + '/'
        $projectPaths = @($ApprovedPaths | Where-Object { $_.StartsWith($projectPrefix, [StringComparison]::Ordinal) })
        if ($projectPaths.Count -eq 0) { return $null }
        $failed = @($project.steps | Where-Object { $_.status -eq 'failed' })
        if ($failed.Count -eq 0) { return $null }
        $diagnostic = (@($failed | ForEach-Object { "$($_.name): $($_.detail)" }) -join "`n").Replace('\', '/')
        if ($verification.PSObject.Properties['findings']) {
            $retained = @($verification.findings | Where-Object {
                $_.projectPath -eq $project.projectPath -and $_.message -like 'Keep regression test*Confirmed product defect*'
            } | ForEach-Object message)
            if ($retained.Count) { $diagnostic = ($retained -join "`n") + "`nRepair the other failures; do not remove, skip or weaken these product-regression assertions.`n" + $diagnostic }
        }
        $fullDiagnostic = $diagnostic
        foreach ($reference in [regex]::Matches($diagnostic, 'Full output: (commands/[\w.-]+\.log) \[sha256: ([a-f0-9]{64})\]')) {
            $logPath = Join-Path $verificationDirectory $reference.Groups[1].Value
            if (-not (Test-PathWithinRoot -Candidate $logPath -Root $verificationDirectory) -or
                -not (Test-Path -LiteralPath $logPath -PathType Leaf) -or
                (Get-FileHash -LiteralPath $logPath).Hash -ne $reference.Groups[2].Value) { return $null }
            $fullDiagnostic += "`n" + (Get-Content -LiteralPath $logPath -Raw).Replace('\', '/')
            $diagnostic += "`nRead all failures before editing: $logPath"
        }
        $digest = Get-QaFoundryVerificationFailureDigest -Text $fullDiagnostic
        if ($digest) { $diagnostic = "$digest`n$diagnostic" }
        $paths = @()
        # A compiler source location is more precise than its trailing project reference.
        if (@($failed | Where-Object { $_.name -ne 'build' }).Count -eq 0) {
            $paths = @($projectPaths | Where-Object {
                $fullDiagnostic -match ([regex]::Escape($_) + '(?:\(\d+(?:,\d+)?\)|:\d+(?::\d+)?):?\s*(?:error|fatal error)')
            })
        }
        elseif (@($failed | Where-Object { $_.name -ne 'test' }).Count -eq 0) {
            $paths = @($projectPaths | Where-Object {
                $fullDiagnostic -match ([regex]::Escape($_) + '(?::line \d+|:\d+(?::\d+)?)')
            })
            if ($fullDiagnostic -match 'not published beside|could not find file|file not found|ENOENT' -and
                $project.manifestPath -in $projectPaths) {
                $paths = @(@($paths) + @([string]$project.manifestPath) | Select-Object -Unique)
            }
        }
        $manifest = @($Plan.changes | Where-Object { $_.path -ceq $project.manifestPath })
        if ($project.ecosystem -eq 'npm' -and $manifest.Count -eq 1 -and
            @($failed | Where-Object { $_.name -eq 'test' }).Count -gt 0) {
            try {
                $package = $manifest[0].content | ConvertFrom-Json -Depth 40
                if ('scripts' -notin @(Get-QaFoundryPropertyNames -InputObject $package) -or
                    'test' -notin @(Get-QaFoundryPropertyNames -InputObject $package.scripts)) {
                    $paths = @([string]$project.manifestPath)
                    $diagnostic += "`nThe verifier invokes npm test, but package.json has no scripts.test. Wire it to the approved runnable suite; preserve assertions and fail on empty or skipped suites. Do not replace execution with listing tests."
                }
                elseif ($fullDiagnostic -match '(?im)(?:Error:|Exception:)[^\r\n]*(?:[A-Z][A-Z0-9_]+ is required|missing (?:required )?(?:environment|configuration|credential))') {
                    # The stack points at the fixture which correctly refused to run.
                    # The command selecting a deployed suite is also part of the repair.
                    $selectionPaths = @($projectPaths | Where-Object { $_ -match '/(?:playwright|vitest|jest)\.config\.[^/]+$' })
                    $paths = @(@($paths) + @([string]$project.manifestPath) + $selectionPaths | Select-Object -Unique)
                    $diagnostic += "`nDefault npm test selected a suite requiring unavailable execution inputs. Repair its selection together with package.json and runner configuration. Keep deployed tests and their fail-closed preflight intact. The default suite needs real environment-free assertions; if those files were not planned, report the contract gap for implementation revision. Do not inject fake deployment values, remove tests or turn missing inputs into skips."
                }
            } catch { $paths = @() }
        }
        # Ambiguous diagnostics require examining the failed project, never unrelated projects.
        if ($paths.Count -eq 0) { $paths = $projectPaths }
        $targets += [pscustomobject]@{
            paths = @($paths)
            instruction = "Repair the existing files using this verification output. Preserve working code and test coverage; do not recreate the project. The default local suite must execute real assertions without deployment credentials; listing tests, empty suites and skipped tests cannot satisfy verification. Request additional approved paths if the fix requires them. If the approved contracts prohibit a runnable local suite, identify those contract conflicts explicitly instead of weakening the verification gate.`n$diagnostic"
        }
    }
    if ($targets.Count -eq 0) { return $null }
    return [pscustomobject]@{ agentId = 'framework-verification'; decision = 'revision_required'; repairScope = 'targeted'; repairTargets = $targets }
}
