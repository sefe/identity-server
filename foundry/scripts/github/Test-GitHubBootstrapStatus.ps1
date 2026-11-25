# Offline wrapper checks: stub the expensive bootstrap; no model, Git or API calls.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$scratch=Join-Path ([IO.Path]::GetTempPath()) ('foundry-status-'+[guid]::NewGuid().ToString('N'))
$scripts=Join-Path $scratch 'foundry/scripts'
$null=New-Item -ItemType Directory -Path (Join-Path $scripts 'github') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Invoke-GitHubBootstrap.ps1') -Destination (Join-Path $scripts 'github')
@'
param($ConfigPath,$PreparedProjectConfigPath,$Phase,$CurrentRef,$BudgetMinutes,$ResumeRunRoot)
[pscustomobject]@{status=$env:FOUNDRY_STATUS_FIXTURE}
'@ | Set-Content -LiteralPath (Join-Path $scripts 'Start-FoundryBootstrap.ps1') -Encoding utf8
$variables=@('GITHUB_OUTPUT','GITHUB_STEP_SUMMARY','GITHUB_RUN_ID','QA_FOUNDRY_ADDITIONAL_USD_LIMIT','FOUNDRY_STATUS_FIXTURE')
$saved=@{}
foreach ($name in $variables) { $saved[$name]=[Environment]::GetEnvironmentVariable($name) }
$checks=0
try {
    $env:GITHUB_RUN_ID='12345'
    $env:QA_FOUNDRY_ADDITIONAL_USD_LIMIT=''
    foreach ($status in @('paused','pull_request_created','plan_applied','dry_run','blocked')) {
        $env:FOUNDRY_STATUS_FIXTURE=$status
        $env:GITHUB_OUTPUT=Join-Path $scratch "$status.output"
        $env:GITHUB_STEP_SUMMARY=Join-Path $scratch "$status.summary"
        $threw=$false
        try { $null=& (Join-Path $scripts 'github/Invoke-GitHubBootstrap.ps1') -RepositoryRoot $scratch }
        catch { $threw=$true }
        if ($threw -ne ($status -eq 'blocked')) { throw "Wrong success/failure result for $status." }
        if ((Get-Content -LiteralPath $env:GITHUB_OUTPUT -Raw).Trim() -ne "status=$status") { throw "Missing output for $status." }
        $summary=Get-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Raw
        if ($status -eq 'paused' -and ($summary -notmatch 'NOT complete' -or $summary -notmatch 'resume_run_id=12345' -or $summary -notmatch 'No PR')) {
            throw 'Paused summary must make incompletion and recovery explicit.'
        }
        if ($status -eq 'pull_request_created' -and $summary -notmatch 'COMPLETE.*draft pull request published') { throw 'Missing delivery confirmation.' }
        if ($status -eq 'blocked' -and $summary -notmatch 'BLOCKED.*no automatic continuation') { throw 'Blocked state must remain distinct from pause.' }
        $checks++
    }
    Write-Host "Bootstrap status checks passed: $checks."
}
finally {
    foreach ($name in $variables) { [Environment]::SetEnvironmentVariable($name,$saved[$name]) }
    # Only remove this test's verified, newly allocated temporary directory.
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    $resolved=[IO.Path]::GetFullPath($scratch)
    if (-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolved -Leaf) -notmatch '^foundry-status-[a-f0-9]{32}$') { throw 'Unsafe test cleanup path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
