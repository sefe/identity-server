[CmdletBinding()]
param([ValidateSet('release.candidate','documentation.changed','ci.build.failed')][string]$EventType,
      [string]$CiRunId='', [string]$RepositoryRoot='.')
$ErrorActionPreference='Stop'
$framework=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$root=(Resolve-Path -LiteralPath $RepositoryRoot).Path
$artifactRoot=Join-Path $root '.qa-foundry-artifacts'
New-Item -ItemType Directory -Path $artifactRoot -Force | Out-Null
$config=Get-Content -LiteralPath (Join-Path $root '.foundry/project.json') -Raw | ConvertFrom-Json -Depth 100
# Automatic triage proposes changes. Applying them requires a separately reviewed delivery run.
$config.delivery.dry_run=$true
$config.work_tracking.enabled=$false
$config.work_tracking.dry_run=$true
$config.ci.collect_realtime=($EventType -eq 'ci.build.failed')
$config.ci.dry_run=$false
$config.target.repository_path=$root
$config.target.documentation_paths=@($config.target.documentation_paths | ForEach-Object {[IO.Path]::GetFullPath((Join-Path (Join-Path $root '.foundry') $_))})
foreach ($route in $config.routing.routes) {$route.workflow=[IO.Path]::GetFullPath((Join-Path (Join-Path $root '.foundry') $route.workflow))}
$configPath=Join-Path $artifactRoot 'lifecycle-config.json'
$config | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $configPath -Encoding utf8
$eventPath=Join-Path $artifactRoot 'github-event.json'
$sha=[string](& git -C $root rev-parse HEAD)
if ($LASTEXITCODE) {throw 'Cannot resolve product commit.'}
@{type=$EventType;source='github';eventId="github:$env:GITHUB_RUN_ID`:$EventType";
    repository=@{provider='github';name=$config.delivery.github.repository;url="https://github.com/$($config.delivery.github.repository)";ref="refs/heads/$($config.project.source_branch)";commitSha=$sha.Trim()};
    correlation=@{buildId=$CiRunId;ciRunId=$CiRunId}} | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $eventPath -Encoding utf8
try {
    $result=@(& (Join-Path $framework 'scripts/Invoke-Foundry.ps1') -ConfigPath $configPath -PolicyPath (Join-Path $framework 'policies/default-policy.yaml') `
        -EventPath $eventPath -EventType $EventType -CiRunId $CiRunId -CiBuildId $CiRunId -BudgetMinutes 280)[-1]
    if ($result.status -ne 'completed') {throw "Lifecycle analysis ended as '$($result.status)'; inspect saved evidence."}
    return $result
}
finally {
    $runs=@(Get-ChildItem -LiteralPath $artifactRoot -Directory -Filter 'run-*' | Sort-Object LastWriteTimeUtc -Descending)
    if ($runs.Count) {
        & (Join-Path $framework 'scripts/Export-FoundryReport.ps1') -RepositoryRoot $root -RunRoot $runs[0].FullName -OutputPath (Join-Path $artifactRoot 'foundry-report.html')
    }
}
