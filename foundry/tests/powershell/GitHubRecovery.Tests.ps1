BeforeAll {
    $script:Root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root 'scripts/Common.ps1')
    . (Join-Path $script:Root 'scripts/RunInputs.ps1')
    function Invoke-FixtureGit {
        param([string[]]$Arguments)
        $output=& git -C $script:Target @Arguments 2>&1
        if ($LASTEXITCODE) { throw "Fixture git failed: $output" }
        return $output
    }
}

Describe 'GitHub recovery preserves product identity across a runtime repair' {
    It 'checks out the saved product and overlays only the runtime without bypassing fingerprint gates' {
        $script:Target=Join-Path $TestDrive product
        $runtime=Join-Path $script:Target foundry
        foreach ($relative in @('foundry/prompts','foundry/schemas','.github/workflows','src','.qa-foundry-artifacts')) {
            New-Item -ItemType Directory (Join-Path $script:Target $relative) -Force | Out-Null
        }
        '/.qa-foundry-artifacts/' | Set-Content (Join-Path $script:Target .gitignore)
        'original source' | Set-Content (Join-Path $script:Target src/product.cs)
        'original dispatcher' | Set-Content (Join-Path $script:Target .github/workflows/foundry-bootstrap.yml)
        'original runtime' | Set-Content (Join-Path $runtime engine.ps1)
        'approved prompt' | Set-Content (Join-Path $runtime prompts/agent.md)
        '{}' | Set-Content (Join-Path $runtime schemas/artifact.json)
        $null=Invoke-FixtureGit @('init','-b','main')
        $null=Invoke-FixtureGit @('config','core.autocrlf','false')
        $null=Invoke-FixtureGit @('add','.')
        $null=Invoke-FixtureGit @('-c','user.name=Test','-c','user.email=test@example.invalid','commit','-m','Original')
        $sourceSha=[string](Invoke-FixtureGit @('rev-parse','HEAD'))
        $fingerprintArgs=@{RepositoryRoot=$script:Target;FrameworkRoot=$runtime;Config=[pscustomobject]@{
            runtime=[pscustomobject]@{artifacts_root='.qa-foundry-artifacts'}
        };Workflow=[pscustomobject]@{stages=@()};Policy=[pscustomobject]@{}}
        $saved=Get-QaFoundryRunInputs @fingerprintArgs
        'changed product on main' | Set-Content (Join-Path $script:Target src/product.cs)
        'new recovery dispatcher' | Set-Content (Join-Path $script:Target .github/workflows/foundry-bootstrap.yml)
        'fixed runtime' | Set-Content (Join-Path $runtime engine.ps1)
        $null=Invoke-FixtureGit @('add','.')
        $null=Invoke-FixtureGit @('-c','user.name=Test','-c','user.email=test@example.invalid','commit','-m','Repair')
        $runtimeSha=[string](Invoke-FixtureGit @('rev-parse','HEAD'))
        {Assert-QaFoundryRunInputs -Recorded $saved -Current (Get-QaFoundryRunInputs @fingerprintArgs)} | Should -Throw '*source*'
        # These are the workflow's exact checkout operations. Saved evidence is untracked.
        'saved evidence' | Set-Content (Join-Path $script:Target .qa-foundry-artifacts/evidence.json)
        $null=Invoke-FixtureGit @('checkout','--detach',$sourceSha)
        $null=Invoke-FixtureGit @('restore','--source',$runtimeSha,'--worktree','--','foundry')
        $current=Get-QaFoundryRunInputs @fingerprintArgs
        {Assert-QaFoundryRunInputs -Recorded $saved -Current $current} | Should -Not -Throw
        $current.sourceCommit | Should -BeExactly $sourceSha
        Get-Content (Join-Path $runtime engine.ps1) | Should -Be 'fixed runtime'
        Get-Content (Join-Path $script:Target src/product.cs) | Should -Be 'original source'
        Get-Content (Join-Path $script:Target .qa-foundry-artifacts/evidence.json) | Should -Be 'saved evidence'
        'changed prompt' | Set-Content (Join-Path $runtime prompts/agent.md)
        {Assert-QaFoundryRunInputs -Recorded $saved -Current (Get-QaFoundryRunInputs @fingerprintArgs)} | Should -Throw '*contracts*'
    }
}

Describe 'GitHub entry point forwards an explicit restart only with saved evidence' {
    BeforeEach {
        $script:Target=Join-Path $TestDrive ('target-'+[guid]::NewGuid().ToString('N'))
        $scripts=Join-Path $script:Target foundry/scripts
        $script:Wrapper=Join-Path $scripts github/Invoke-GitHubBootstrap.ps1
        New-Item -ItemType Directory (Split-Path $script:Wrapper) -Force | Out-Null
        Copy-Item (Join-Path $script:Root scripts/github/Invoke-GitHubBootstrap.ps1) $script:Wrapper
        $run=Join-Path $script:Target .qa-foundry-artifacts/run-saved
        New-Item -ItemType Directory $run -Force | Out-Null
        '{}' | Set-Content (Join-Path $run workflow-state.json)
        '<html>fixture</html>' | Set-Content (Join-Path $run report.html)
        @'
param($ConfigPath,$PreparedProjectConfigPath,$Phase,$CurrentRef,$BudgetMinutes,$ResumeRunRoot,$RestartStage)
$PSBoundParameters | ConvertTo-Json | Set-Content (Join-Path $PSScriptRoot invocation.json)
[pscustomobject]@{status='paused';reportPath=(Join-Path $ResumeRunRoot report.html)}
'@ | Set-Content (Join-Path $scripts Start-FoundryBootstrap.ps1)
        $script:Invocation=Join-Path $scripts invocation.json
        $script:Environment=@{}
        foreach ($name in @('GITHUB_OUTPUT','GITHUB_STEP_SUMMARY','QA_FOUNDRY_ADDITIONAL_USD_LIMIT')) {
            $script:Environment[$name]=[Environment]::GetEnvironmentVariable($name)
            [Environment]::SetEnvironmentVariable($name,'')
        }
    }
    AfterEach {
        foreach ($name in $script:Environment.Keys) { [Environment]::SetEnvironmentVariable($name,$script:Environment[$name]) }
    }
    It 'passes the saved run and implementation restart to the core without invoking a model' {
        $result=& $script:Wrapper -RepositoryRoot $script:Target -Resume -RestartStage implementation
        $result.status | Should -Be paused
        $call=Get-Content $script:Invocation -Raw | ConvertFrom-Json
        $call.RestartStage | Should -Be implementation
        $call.ResumeRunRoot | Should -Be (Join-Path $script:Target .qa-foundry-artifacts/run-saved)
        $call.Phase | Should -Be Plan
    }
    It 'refuses restart without resume and does not call the core' {
        {& $script:Wrapper -RepositoryRoot $script:Target -RestartStage implementation} | Should -Throw '*requires -Resume*'
        Test-Path $script:Invocation | Should -BeFalse
    }
}
