[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepositoryRoot,[string]$TargetBranch='main',[switch]$Resume)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $RepositoryRoot).Path
$framework=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$evidence=Join-Path $root '.qa-foundry-artifacts'
$resumeRoot=''
if ($Resume) {
    $runs=@(Get-ChildItem -LiteralPath $evidence -Directory -Filter 'run-*' | Where-Object {
        Test-Path -LiteralPath (Join-Path $_.FullName 'workflow-state.json')
    })
    if ($runs.Count -ne 1) {throw 'Resume requires exactly one saved analysis root; do not guess between runs.'}
    $resumeRoot=$runs[0].FullName
}
$allowance=0.0
$hasAllowance=-not [string]::IsNullOrWhiteSpace($env:QA_FOUNDRY_ADDITIONAL_USD_LIMIT)
if ($hasAllowance -and (-not [double]::TryParse($env:QA_FOUNDRY_ADDITIONAL_USD_LIMIT,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$allowance) -or $allowance -le 0 -or [double]::IsInfinity($allowance) -or [double]::IsNaN($allowance))) {
    throw 'budget_usd must be empty (no spending cap) or a finite positive number.'
}
if (-not $hasAllowance) { $env:QA_FOUNDRY_ADDITIONAL_USD_LIMIT='' }
$result=$null
try {
    $result=@(& (Join-Path $framework 'scripts/Start-FoundryBootstrap.ps1') -ConfigPath (Join-Path $root '.qa-foundry-artifacts/github-bootstrap.json') `
        -PreparedProjectConfigPath (Join-Path $root '.qa-foundry-artifacts/github-project.json') `
        -Phase Plan -CurrentRef "refs/heads/$TargetBranch" -BudgetMinutes 280 -ResumeRunRoot $resumeRoot)[-1]
    if ($result.status -notin @('dry_run','plan_applied','pull_request_created','paused')) {throw "Bootstrap ended as '$($result.status)'."}
}
finally {
    $runs=@(Get-ChildItem -LiteralPath $evidence -Directory -Filter 'run-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending)
    if ($runs.Count) {
        try {
            if ($null -ne $result -and $result.PSObject.Properties.Name -contains 'reportPath' -and (Test-Path -LiteralPath $result.reportPath)) {
                Copy-Item -LiteralPath $result.reportPath -Destination (Join-Path $evidence 'foundry-report.html') -Force
            }
            else {
                & (Join-Path $framework 'scripts/Export-FoundryReport.ps1') -RepositoryRoot $root -RunRoot $runs[0].FullName -OutputPath (Join-Path $evidence 'foundry-report.html')
            }
        } catch {Write-Warning "Report export failed: $($_.Exception.Message)"}
    }
    if ($env:GITHUB_STEP_SUMMARY) {
        $status=if ($null -ne $result){[string]$result.status}else{'failed'}
        $budgetSummary=if ($hasAllowance) {"Estimated additional AI allowance: USD $allowance (not an invoice or hard provider billing cap)."} else {'Foundry AI spending cap: disabled. Model usage and estimated cost remain recorded in the report.'}
        $lines=@("## Foundry bootstrap: $status",'',$budgetSummary,'',
            'Generated tests were not executed during bootstrap. Configure application credentials and run the delivered test workflows afterwards.', '',
            'Download **foundry-evidence** for the HTML report, model usage records, decisions, static review and recovery evidence.',
            'Download **foundry-output** for materialized automation; a dry-run proposal also remains in the evidence change-set JSON.')
        if ($status -eq 'paused') {$lines+=@('',"Resume this analysis with resume_run_id=$env:GITHUB_RUN_ID, the same engine commit, target commit, model, publish setting and allowance.")}
        $lines -join "`n" | Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Encoding utf8
    }
}
return $result
