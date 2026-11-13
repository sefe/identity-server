# Offline integration tests: no provider calls, no GitHub writes, no Pester dependency.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
if ($IsWindows) { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force }
$source=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $source 'scripts/Common.ps1')
$scratch=Join-Path $source ('.qa-foundry-artifacts/github-tests-'+[guid]::NewGuid().ToString('N'))
$target=Join-Path $scratch 'product'
$runtime=Join-Path $target 'foundry'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
foreach ($item in @('scripts','schemas','config','bootstrap','workflows','policies','prompts','node_modules','package.json','package-lock.json','.gitignore')) {
    Copy-Item -LiteralPath (Join-Path $source $item) -Destination (Join-Path $runtime $item) -Recurse
}
$script:assertions=0
function Assert-True([bool]$Condition,[string]$Message) {if (-not $Condition){throw "FAILED: $Message"};$script:assertions++}
function Assert-Throws([scriptblock]$Action,[string]$Message) {$failed=$false;try {& $Action | Out-Null}catch {$failed=$true};Assert-True $failed $Message}
$null=& git -C $target init -b main
if ($LASTEXITCODE) {throw 'Cannot initialize test repository.'}
$null=& git -C $target config core.autocrlf false
if ($LASTEXITCODE) {throw 'Cannot configure deterministic fixture line endings.'}
[IO.File]::WriteAllText((Join-Path $target 'README.md'),'Sample product with API and UI.')
[IO.File]::WriteAllText((Join-Path $target '.gitignore'),"/.qa-foundry-artifacts/`n/.sdlc-foundry/`n")
$null=& git -C $target add README.md .gitignore foundry 2>$null
$null=& git -C $target -c user.name=FoundryTest -c user.email=test@example.invalid commit -m fixture
if ($LASTEXITCODE) {throw 'Cannot commit test fixture.'}
$runtimeRef=([string](& git -C $target rev-parse HEAD)).Trim()
$runtimeConfig=Join-Path $runtime 'config/project.yaml'
$originalConfigHash=(Get-FileHash $runtimeConfig).Hash
Add-Content -LiteralPath $runtimeConfig -Value '# Changed runtime in disposable test checkout'
$null=& git -C $target restore --source $runtimeRef --worktree -- foundry
Assert-True ($LASTEXITCODE -eq 0 -and (Get-FileHash $runtimeConfig).Hash -eq $originalConfigHash) 'Installed workflows can restore only the pinned embedded runtime.'
Assert-True ((Get-Content (Join-Path $target 'README.md') -Raw) -eq 'Sample product with API and UI.') 'Restoring Foundry leaves product files intact.'
Assert-Throws {& (Join-Path $runtime 'scripts/github/Prepare-GitHubProject.ps1') -RepositoryRoot $target -Repository 'example/product' -RuntimeRepository 'example/other' -RuntimeRef $runtimeRef -Model 'claude-opus-5.5'} 'Embedded configuration rejects a separate runtime repository.'
$prepared=& (Join-Path $runtime 'scripts/github/Prepare-GitHubProject.ps1') -RepositoryRoot $target -Repository 'example/product' `
    -RuntimeRepository 'example/product' -RuntimeRef $runtimeRef -Model 'claude-opus-5.5'
$config=Get-Content -LiteralPath $prepared.configPath -Raw | ConvertFrom-Json -Depth 100
$bootstrap=Get-Content -LiteralPath $prepared.bootstrapPath -Raw | ConvertFrom-Json -Depth 100
Assert-True ($config.delivery.provider -eq 'github' -and -not $config.delivery.push_branch -and -not $config.delivery.create_draft_pull_request) 'Preview must materialize locally without publishing.'
Assert-True ($config.automation.min_projects -eq 2) 'API and UI require at least two projects.'
Assert-True (Test-QaFoundryDeferredVerification -Config $config) 'Bootstrap defaults to generation without test execution.'
Assert-True ($config.ai.run_budget.max_total_tokens -eq 0) 'Token spending cap is disabled.'
Assert-True ((& (Join-Path $runtime 'scripts/Get-EcosystemRuntimeVersion.ps1') -ProjectConfigPath $prepared.configPath -Ecosystem npm -RuntimeKey npm_version) -eq $config.automation.ecosystems.npm.runtime.npm_version) 'Runtime preparation reads the prepared configuration before installation.'
Assert-True (@($config.ai.profiles.copilot.secret_env).Count -eq 1 -and $config.ai.profiles.copilot.secret_env[0] -eq 'COPILOT_GITHUB_TOKEN') 'Model must not receive the repository writer token.'
$validation=@(& (Join-Path $runtime 'scripts/Invoke-Foundry.ps1') -ConfigPath $prepared.configPath `
    -WorkflowPath (Join-Path $runtime 'workflows/bootstrap-automation.yaml') -PolicyPath (Join-Path $runtime 'policies/bootstrap-policy.yaml') -ValidateOnly)[-1]
Assert-True $validation.valid 'The full runtime accepts GitHub configuration.'
$template=@'
name: Automation __NAME__
on:
  push:
    branches: [main]
  pull_request:
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - run: npm test
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: results
          path: test-results/
'@
$manualTemplate=$template.Replace("  push:`n    branches: [main]`n  pull_request:", '  workflow_dispatch:').Replace("  push:`r`n    branches: [main]`r`n  pull_request:", '  workflow_dispatch:')
$errors=@(& (Join-Path $runtime 'scripts/github/Test-GitHubWorkflow.ps1') -Path '.github/workflows/manual.yml' -Content $manualTemplate -TargetBranch main -FrameworkRoot $runtime -DeferredTests)
Assert-True ($errors.Count -eq 0) 'Deferred bootstrap accepts manual test execution.'
$errors=@(& (Join-Path $runtime 'scripts/github/Test-GitHubWorkflow.ps1') -Path '.github/workflows/automatic.yml' -Content $template -TargetBranch main -FrameworkRoot $runtime -DeferredTests)
Assert-True ($errors.Count -gt 0) 'Deferred bootstrap rejects automatic test execution on PR or push.'
$changes=@('api','ui') | ForEach-Object {
    @{operation='create';path=".github/workflows/automation-$_.yml";expectedSha256='';content=$manualTemplate.Replace('__NAME__',$_);reason='Run suite after configuration';sourceRefs=@('fixture')}
}
$analysis=@{agentId='fixture';stageId='materialization';runId='test-github';status='completed';summary='Fixture automation';evidence=@();assumptions=@();unknowns=@();warnings=@();outcome='proposed';details=@{dryRun=$false};changes=@($changes)}
$runRoot=Join-Path $target '.qa-foundry-artifacts/test-bootstrap'
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
$analysisPath=Join-Path $runRoot 'analysis.json'
$analysis | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $analysisPath -Encoding utf8
$hash=(Get-FileHash -LiteralPath $prepared.bootstrapPath -Algorithm SHA256).Hash.ToLowerInvariant()
$arguments=@{BootstrapConfig=$bootstrap;ProjectConfig=$config;RepositoryRoot=$target;FrameworkRoot=$runtime;RunRoot=$runRoot;RunId='test-github';ConfigurationHash=$hash;AnalysisRunId='test-analysis';AnalysisChangeSetPath=$analysisPath}
$plan=& (Join-Path $runtime 'scripts/New-BootstrapChangeSet.ps1') @arguments
$output=Get-Content -LiteralPath $plan.changeSetPath -Raw | ConvertFrom-Json -Depth 100
$triage=@($output.changes | Where-Object path -eq '.github/workflows/foundry-triage.yml')[0]
Assert-True ($triage.content.Contains('"Automation api", "Automation ui"')) 'Failure triage must subscribe to actual generated workflow names.'
Assert-True (-not ($triage.content -match '\{\{[A-Z_]+\}\}')) 'No template placeholders may survive.'
Assert-True (@($output.changes | Where-Object path -eq '.foundry/project.json').Count -eq 1) 'Portable configuration must be delivered.'
$bad=$template.Replace('branches: [main]','branches: [other]')
$errors=@(& (Join-Path $runtime 'scripts/github/Test-GitHubWorkflow.ps1') -Path '.github/workflows/bad.yml' -Content $bad -TargetBranch main -FrameworkRoot $runtime)
Assert-True ($errors.Count -gt 0) 'Reject workflows that never run on the target branch.'
$bad=$template.Replace('pull_request:', 'pull_request_target:')
$errors=@(& (Join-Path $runtime 'scripts/github/Test-GitHubWorkflow.ps1') -Path '.github/workflows/bad.yml' -Content $bad -TargetBranch main -FrameworkRoot $runtime)
Assert-True ($errors.Count -gt 0) 'Reject privileged PR execution in generated tests.'
$errors=@(& (Join-Path $runtime 'scripts/github/Test-GitHubWorkflow.ps1') -Path 'pipelines/ado.yml' -Content "trigger: main`npool: ubuntu" -TargetBranch main -FrameworkRoot $runtime)
Assert-True ($errors.Count -gt 0) 'Reject Azure workflow format and location.'
$config.delivery.dry_run=$false;$config.delivery.create_branch=$false;$config.delivery.commit_changes=$false
$config.delivery.push_branch=$false;$config.delivery.create_draft_pull_request=$false
$apply=& (Join-Path $runtime 'scripts/Apply-ScopedChangeSet.ps1') -PlanPath $plan.changeSetPath -Config $config -RepositoryRoot $target -RunRoot $runRoot -RunId test-github
Assert-True (@($apply.actions | Where-Object status -eq executed).Count -eq $output.changes.Count) 'Apply every scoped installer change.'
$installedBootstrap=Join-Path $target '.foundry/bootstrap.json'
$final=@(& (Join-Path $runtime 'scripts/Start-FoundryBootstrap.ps1') -ConfigPath $installedBootstrap -Phase Finalize -CurrentRef refs/heads/main)[-1]
Assert-True ($final.status -eq 'installed') 'Finalize verifies GitHub files without Azure registration.'
Add-Content -LiteralPath (Join-Path $target '.github/workflows/foundry-router.yml') -Value '# drift'
Assert-Throws {& (Join-Path $runtime 'scripts/Start-FoundryBootstrap.ps1') -ConfigPath $installedBootstrap -Phase Finalize -CurrentRef refs/heads/main} 'Finalization must reject modified workflow bytes.'
Assert-Throws {& (Join-Path $runtime 'scripts/writers/Publish-RepositoryDelivery.ps1') -Config $config -RepositoryRoot $target -RunRoot $runRoot -RunId test-github -ChangeSetPath $plan.changeSetPath} 'Delivery must reject modified reviewed bytes.'
. (Join-Path $runtime 'scripts/github/GitHub.ps1')
$settings=[pscustomobject]@{repository='example/product';auth_env='TEST_GITHUB_TOKEN'}
Assert-Throws {Get-FoundryGitHubContext -Settings $settings} 'A missing GitHub credential must fail.'
$context=Get-FoundryGitHubContext -Settings $settings -Environment @{TEST_GITHUB_TOKEN='fixture-token'}
Assert-Throws {Invoke-FoundryGitHub -Context $context -Path 'https://evil.invalid'} 'Do not send tokens to arbitrary hosts.'
Assert-Throws {Invoke-FoundryGitHub -Context $context -Path '../other'} 'Do not traverse GitHub API paths.'
$global:FoundryTestRequests=[Collections.Generic.List[object]]::new()
$global:FoundryTestExistingRemote=$true
function Invoke-RestMethod {
    param($Method,$Uri,$Headers,$TimeoutSec,$MaximumRedirection,$ErrorAction,$ContentType,$Body)
    $global:FoundryTestRequests.Add(@{method=$Method;uri=$Uri;body=$Body;redirects=$MaximumRedirection})
    if ($Uri -match '/git/ref/') {if ($global:FoundryTestExistingRemote) {return @{object=@{sha=('b'*40)}}} else {return $null}}
    if ($Uri -match '/pulls\?') {if ($global:FoundryTestExistingRemote) {return @(@{number=42;state='open';head=@{ref='sdlc-foundry/test'};base=@{ref='main'}})} else {return @()}}
    if ($Uri -match '/pulls$' -and $Method -eq 'POST') {return @{number=43}}
    if ($Uri -match '/actions/runs/123/jobs') {return @{total_count=1;jobs=@(@{id=9;name='API tests';status='completed';conclusion='failure';html_url='https://github.com/example/product/actions/runs/123/job/9'})}}
    if ($Uri -match '/actions/runs/123$') {return @{id=123;name='Automation api';status='completed';conclusion='failure';head_branch='main';head_sha=('b'*40);html_url='https://github.com/example/product/actions/runs/123';created_at='2026-11-10T00:00:00Z';updated_at='2026-11-10T00:01:00Z'}}
    throw "Unexpected network request in offline test: $Uri"
}
$remote=Get-FoundryGitHubDeliveryState -Context $context -Branch sdlc-foundry/test -Base main
Assert-True ($remote.branchExists -and $remote.pullRequestId -eq '42') 'Remote discovery reuses an existing branch and PR.'
Assert-True (@($global:FoundryTestRequests | Where-Object redirects -ne 0).Count -eq 0) 'GitHub credentials must not follow redirects.'
$eventPath=Join-Path $runRoot 'event.json'
@{eventId='github:123';correlation=@{buildId='123';ciRunId='123'}} | ConvertTo-Json | Set-Content -LiteralPath $eventPath
$ci=[pscustomobject]@{provider='github';collect_realtime=$true;fail_on_collection_error=$true;max_failed_tests=10;max_jobs=10;github=$settings}
$ciPath=Join-Path $runRoot 'ci.json'
$collected=& (Join-Path $runtime 'scripts/collectors/Collect-CiEvidence.ps1') -RunId test-github -EventPath $eventPath -CiConfig $ci -OutputPath $ciPath -ProviderEnvironment @{TEST_GITHUB_TOKEN='fixture-token'}
Assert-True ($collected.summary.failedJobCount -eq 1 -and $collected.build.id -eq '123') 'Collect failed GitHub jobs from the requested run.'
Assert-True ($collected.warnings.Count -gt 0 -and $collected.failedTests.Count -eq 0) 'Do not invent assertion-level test evidence from job status.'
$null=& (Join-Path $runtime 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath $ciPath -SchemaPath (Join-Path $runtime 'schemas/runtime/ci-evidence.schema.json') -SchemaRoot (Join-Path $runtime 'schemas')
$router=@($output.changes | Where-Object path -eq '.github/workflows/foundry-router.yml')[0]
[IO.File]::WriteAllText((Join-Path $target $router.path),[string]$router.content)
$global:FoundryTestGit=(Get-Command git -CommandType Application | Select-Object -First 1).Source
$global:FoundryTestPushes=[Collections.Generic.List[object]]::new()
function git {
    if ($args -contains 'push') {$global:FoundryTestPushes.Add(@($args));$global:LASTEXITCODE=0;return}
    & $global:FoundryTestGit @args
    $global:LASTEXITCODE=$LASTEXITCODE
}
$null=& git -C $target remote add origin https://github.com/example/product.git
$global:FoundryTestExistingRemote=$false
foreach ($flag in @('create_branch','commit_changes','push_branch','create_draft_pull_request')) {$config.delivery.$flag=$true}
$delivery=& (Join-Path $runtime 'scripts/writers/Publish-RepositoryDelivery.ps1') -Config $config -RepositoryRoot $target -RunRoot $runRoot -RunId test-github -ChangeSetPath $plan.changeSetPath -ActionEnvironment @{FOUNDRY_GITHUB_TOKEN='fixture-token'}
Assert-True (@($delivery.actions | Where-Object {$_.type -eq 'pull-request.draft' -and $_.externalId -eq '43'}).Count -eq 1) 'Delivery creates a GitHub PR after a real scoped local commit.'
Assert-True ($global:FoundryTestPushes.Count -eq 1 -and $global:FoundryTestPushes[0] -notcontains '--force') 'Delivery uses one non-force push (intercepted offline).'
$prRequest=@($global:FoundryTestRequests | Where-Object {$_.method -eq 'POST' -and $_.uri -match '/pulls$'})[-1].body | ConvertFrom-Json
Assert-True ($prRequest.draft -and $prRequest.base -eq 'main' -and $prRequest.head.StartsWith('sdlc-foundry/')) 'PR targets main as a draft with an automation head.'
$committed=@(& git -C $target diff-tree --no-commit-id --name-only -r HEAD)
Assert-True ($committed.Count -eq $output.changes.Count -and -not @($committed | Where-Object {$_ -like 'foundry/*' -or $_ -like '.qa-foundry-artifacts/*'}).Count) 'Commit contains exactly approved output, not runtime or evidence.'
Remove-Item Function:git
Remove-Item Function:Invoke-RestMethod
Remove-Variable FoundryTestRequests -Scope Global
Remove-Variable FoundryTestExistingRemote,FoundryTestGit,FoundryTestPushes -Scope Global
Write-Host "PASS: $script:assertions GitHub integration assertions. Evidence: $scratch"
