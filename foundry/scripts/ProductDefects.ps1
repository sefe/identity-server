. (Join-Path $PSScriptRoot 'RunInputs.ps1')

function Get-QaFoundryFailedTestCases {
    param([string]$Text, [string]$ProjectPath)
    $plain = $Text -replace '\x1b\[[0-?]*[ -/]*[@-~]', ''
    $cases = [ordered]@{}
    $current = $null
    foreach ($line in @($plain -split '\r?\n')) {
        $name = ''
        if ($line -match '^\s*(?:failed|Failed)\s+(.+?)(?:\s+\([\d.]+(?:ms|s)\)|\s+\[[^\]]+\])?\s*$') { $name = $Matches[1] }
        elseif ($line -match '^FAILED\s+(\S+)') { $name = $Matches[1] }
        elseif ($line -match '^\s*\d+\)\s+(.+?\s+›\s+.+?)(?:\s+[─━]+)?\s*$') { $name = $Matches[1] }
        if ($name) {
            $id = 'test:' + (Get-QaFoundryInputHash -Text ($ProjectPath + '|' + $name.Replace('\','/')))
            if (-not $cases.Contains($id)) {
                $cases[$id] = [pscustomobject]@{ sourceRef = $id; testName = $name; projectPath = $ProjectPath; output = '' }
            }
            $current = $cases[$id]
        }
        if ($null -ne $current -and $current.output.Length -lt 4000) {
            $current.output += $line + "`n"
        }
    }
    return @($cases.Values)
}

function Get-QaFoundryConfirmedProductDefects {
    param([object[]]$Cases, [object]$Analysis, [object[]]$Review, [object]$ChangeSet, [string]$RepositoryRoot, [int]$MinimumConfirmations = 2)
    $reports = @(@($Analysis) + @($Review))
    if ($reports.Count -lt $MinimumConfirmations -or @($reports | Where-Object status -NE completed).Count) { return @() }
    if (@($reports | ForEach-Object agentId | Select-Object -Unique).Count -ne $reports.Count) { return @() }
    $confirmed = @()
    foreach ($case in $Cases) {
        $votes = @()
        foreach ($report in $reports) {
            $finding = @($report.findings | Where-Object sourceRef -CEQ $case.sourceRef)
            if ($finding.Count -ne 1 -or $finding[0].classification -ne 'product_defect') { continue }
            $votes += $finding[0]
        }
        if ($votes.Count -ne $reports.Count) { continue }
        # Independent reviewers can establish the same requirement from different
        # product documents. Require a common test and valid sources from every
        # reviewer, rather than exactly one identical citation in all reports.
        $tests = @()
        $requirements = @()
        $invalidEvidence = $false
        foreach ($vote in $votes) {
            $testPaths = @($vote.evidence | Where-Object { $_ -clike 'test-path:*' } | ForEach-Object { $_.Substring(10).Trim() } | Select-Object -Unique)
            $sourcePaths = @($vote.evidence | Where-Object { $_ -clike 'requirement-path:*' } | ForEach-Object { $_.Substring(17).Trim() } | Select-Object -Unique)
            if ($testPaths.Count -ne 1 -or $sourcePaths.Count -eq 0) { $invalidEvidence = $true; break }
            $tests += $testPaths
            $requirements += $sourcePaths
        }
        $tests = @($tests | Select-Object -Unique)
        $requirements = @($requirements | Sort-Object -Unique)
        if ($invalidEvidence -or $tests.Count -ne 1) { continue }
        $test = @($ChangeSet.changes | Where-Object path -CEQ $tests[0])
        if ($test.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$test[0].content) -or
            -not $tests[0].StartsWith($case.projectPath.TrimEnd('/') + '/', [StringComparison]::Ordinal)) { continue }
        $sources = @()
        foreach ($relative in $requirements) {
            $requirement = Join-Path $RepositoryRoot $relative
            if (-not (Test-PathWithinRoot -Candidate $requirement -Root $RepositoryRoot) -or
                -not (Test-Path -LiteralPath $requirement -PathType Leaf) -or
                $relative.Replace('\','/') -match '(^|/)(?:\.qa-foundry-artifacts|\.sdlc-foundry|recovery)/' -or
                (Test-PathWithinRoot -Candidate $requirement -Root (Get-QaFoundryRoot)) -or
                $relative -in @($ChangeSet.changes.path)) { $invalidEvidence = $true; break }
            $sources += [pscustomobject]@{ path = $relative; sha256 = (Get-FileHash $requirement).Hash.ToLowerInvariant() }
        }
        if ($invalidEvidence) { continue }
        # The source file must actually occur in this failure's trace, not just
        # be another test the two agents happen to name.
        if (-not $case.output.Replace('\','/').Contains([IO.Path]::GetFileName($tests[0]))) { continue }
        $confirmed += [pscustomobject]@{
            sourceRef = $case.sourceRef; testName = $case.testName; projectPath = $case.projectPath
            testPath = $tests[0]; testSha256 = Get-QaFoundryInputHash -Text $test[0].content
            requirementPath = $sources[0].path; requirementSha256 = $sources[0].sha256; requirementSources = @($sources)
            explanation = $votes[0].hypothesis; confirmation = (@($votes | Select-Object -Skip 1 | ForEach-Object hypothesis) -join "`n")
            signature = $votes[0].signature; output = $case.output
        }
    }
    return @($confirmed)
}

function New-QaFoundryProductBugPlan {
    param([object[]]$Defects, [string]$RunId, [string]$BuildUrl = '')
    $items = @($Defects | ForEach-Object {
        $defect = $_
        $title = 'Product defect: ' + $defect.testName
        if ($title.Length -gt 240) { $title = $title.Substring(0,240) }
        $body = "Test: $($defect.testName)`nAutomation source: $($defect.testPath) (sha256 $($defect.testSha256))`n" +
            "Requirement: $($defect.requirementPath) (sha256 $($defect.requirementSha256))`n" +
            "Diagnosis: $($defect.explanation)`nIndependent confirmation: $($defect.confirmation)`n" +
            "Run: $RunId`nBuild: $BuildUrl`nObserved failure:`n$($defect.output)`n" +
            'Keep the regression test and its failing assertion. Correct the product after team review; do not weaken or skip the test.'
        if ($defect.PSObject.Properties['requirementSources']) {
            $body += "`nRequirement sources:`n" + (@($defect.requirementSources | ForEach-Object { "$($_.path) (sha256 $($_.sha256))" }) -join "`n")
        }
        [ordered]@{
            sourceRef = 'product-defect:' + $defect.sourceRef; type = 'bug'; title = $title
            description = '<pre>' + [System.Net.WebUtility]::HtmlEncode($body) + '</pre>'
            priority = 2; tags = @('foundry-product-defect', 'regression-test-retained')
            acceptanceCriteria = @('The documented product behavior is restored.',
                "The unchanged regression test '$($defect.testName)' passes against the corrected product.")
        }
    })
    return [ordered]@{
        agentId = 'product-defect-reporter'; stageId = 'framework-verification'; runId = $RunId; status = 'completed'
        summary = "$($items.Count) independently confirmed product defect(s); their regression tests are retained."
        evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{ retainedTests = @($Defects) }
        outcome = if ($items.Count) { 'proposed' } else { 'no_action_needed' }; items = @($items)
    }
}

function Complete-QaFoundryProductDefectVerification {
    param([object]$Verification, [object]$Report)
    $changed = $false
    foreach ($project in @($Verification.projects)) {
        if ($project.outcome -ne 'toolchain_defect' -or $project.testsFailed -le 0 -or
            -not $project.negativeProbe.attempted -or -not $project.negativeProbe.failedAsExpected -or
            @($project.steps | Where-Object { $_.status -eq 'failed' -and $_.name -ne 'test' }).Count -gt 0) { continue }
        $cases = @($Report.cases | Where-Object projectPath -CEQ $project.projectPath)
        if ($cases.Count -ne $project.testsFailed) { continue }
        $ids = @()
        foreach ($case in $cases) {
            $defect = @($Report.confirmed | Where-Object sourceRef -CEQ $case.sourceRef)
            $receipt = @($Report.bugActions | Where-Object {
                $_.sourceRef -ceq ('product-defect:' + $case.sourceRef) -and $_.status -in @('executed','duplicate') -and
                [string]$_.externalId -match '^[1-9][0-9]*$'
            })
            if ($defect.Count -eq 1 -and $receipt.Count -eq 1) { $ids += [string]$receipt[0].externalId }
        }
        if ($ids.Count -ne $cases.Count) { continue }
        # Framework readiness is separate from product correctness. Preserve
        # the failed step, nonzero exit code and failed-test count as evidence.
        $project.outcome = 'verified'
        foreach ($finding in @($Verification.findings | Where-Object projectPath -EQ $project.projectPath)) {
            $finding.severity = 'warning'
            $finding.message += " Confirmed product regression(s), tracked by Bug(s) $($ids -join ', '). Tests and failed assertions are retained; framework execution and its negative probe were verified."
        }
        $changed = $true
    }
    if ($changed) {
        $Verification.outcome = if (@($Verification.projects | Where-Object outcome -EQ infrastructure_unavailable).Count) { 'infrastructure_unavailable' }
            elseif (@($Verification.projects | Where-Object outcome -EQ toolchain_defect).Count) { 'toolchain_defect' }
            else { 'verified' }
    }
    return $changed
}
