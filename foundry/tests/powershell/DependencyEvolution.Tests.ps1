BeforeAll {
    $script:Framework = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Framework 'scripts/Common.ps1')
    . (Join-Path $script:Framework 'scripts/DependencyEvolution.ps1')
    function New-DependencyFixture {
        $run = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $run 'context') -Force | Out-Null
        $config = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'tests/fixtures/sample-project-config.yaml') -Root $script:Framework
        $config.automation.package_policy.max_direct_packages = 0
        $config.automation.package_policy.allow_prerelease = $true
        $lock = [ordered]@{
            runId='run-deps';stageId='toolchain';blueprintSha256=('a' * 64);resolvedAt='2026-09-12T00:00:00Z'
            toolchains=@([ordered]@{
                id='npm-tests';revision=1;ecosystem='npm';recipe='custom';source=@{id='npm-public';registry='https://registry.npmjs.org/';authentication='none'}
                runtime=@{nodeMajor=22;npmVersion='10.9.4';lockfileVersion=3};decidedFor=@('api','ui');sha256=('b' * 64)
                packages=@(@{key='typescript';name='typescript';version='5.9.3';requested='5.9.3';scope='dev'})
            })
        }
        $baseline = Join-Path $run 'context/toolchain-lock.json'
        $lock | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $baseline
        return @{RunRoot=$run;Config=$config;RunId='run-deps';StageId='implementation';OutputPath=(Join-Path $run 'resolution.json')}
    }
    function New-DependencyRequest {
        param([string]$Version='^1.0.0')
        return [pscustomobject]@{toolchainId='npm-tests';name='fixture-reader';version=$Version;scope='dev';reason='Decode uploaded fixtures';versionReason='Compatible API and Node runtime';evidence=@('Inspected package release notes and target upload component')}
    }
    $script:Resolver = Join-Path $script:Framework 'scripts/actions/Resolve-DependencyRequests.ps1'
    $script:Versions = { param($registry,$name) @('1.0.0','1.2.0','2.0.0-beta.1') }
    $script:PassingProbe = { param($path,$output) [pscustomobject]@{status='completed';checks=@()} }
}

Describe 'Verified dependency evolution' {
    It 'revisits the framework owner after a test agent request and validates all run artifacts' {
        $fixture = New-DependencyFixture
        $config = $fixture.Config
        $profile = & (Join-Path $script:Framework 'scripts/Resolve-AiProfile.ps1') -Config $config -ProfileName mock
        foreach ($property in $profile.PSObject.Properties) {
            $config.ai | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
        }
        $config.ai.provider = 'command'
        $config.ai.command = "node $script:Framework/tests/fixtures/dependency-request-provider.mjs"
        $policy = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'policies/default-policy.yaml') -Root $script:Framework
        Mock Invoke-RestMethod { [pscustomobject]@{versions=[pscustomobject]@{'1.0.0'=@{};'1.2.0'=@{}}} }
        $workflow = [pscustomobject]@{name='dependencies';version=1;stages=@([pscustomobject]@{
            id='implementation';type='sequential';agents=@(
                [pscustomobject]@{id='foundation';prompt='prompts/implementation/framework-implementation.md';schema='schemas/implementation/implementation-result.schema.json';output='framework-implementation.json'},
                [pscustomobject]@{id='dependent';prompt='prompts/implementation/test-implementation.md';schema='schemas/implementation/implementation-result.schema.json';output='test-implementation.json'}
            )
        })}
        $state = & (Join-Path $script:Framework 'scripts/Invoke-Workflow.ps1') -Workflow $workflow -Config $config -Policy $policy `
            -RepositoryRoot $script:Framework -RunRoot $fixture.RunRoot -RunId $fixture.RunId
        $state.status | Should -Be 'completed'
        $state.stages[0].iteration | Should -Be 2
        $state.stages[0].attempts[0].status | Should -Be 'revision_required'
        foreach ($name in @('framework-implementation','test-implementation')) {
            $artifact = Get-Content (Join-Path $fixture.RunRoot "implementation/iteration-2/$name.json") -Raw | ConvertFrom-Json
            $artifact.details.receivedActiveLock | Should -BeTrue
            $artifact.details.receivedRationale | Should -BeTrue
        }
        $owner = Get-Content (Join-Path $fixture.RunRoot 'implementation/iteration-2/framework-implementation.json') -Raw | ConvertFrom-Json
        $owner.plannedFiles[0].contentContract | Should -Match 'fixture-reader 1.2.0'
        $validated = & (Join-Path $script:Framework 'scripts/Test-RunArtifacts.ps1') -RunRoot $fixture.RunRoot
        $validated.valid | Should -BeTrue
    }

    It 'adds a stable dependency, preserves old pins and keeps the original lock immutable' {
        $fixture = New-DependencyFixture
        $baseline = Get-QaFoundryActiveToolchainPath -RunRoot $fixture.RunRoot
        $hash = (Get-FileHash $baseline).Hash
        $result = & $script:Resolver @fixture -Requests @(New-DependencyRequest) -VersionSource $script:Versions -Probe $script:PassingProbe
        $result.status | Should -Be 'completed' -Because $result.detail
        $result.changed | Should -BeTrue
        (Get-FileHash $baseline).Hash | Should -Be $hash
        $active = Get-Content (Get-QaFoundryActiveToolchainPath -RunRoot $fixture.RunRoot) -Raw | ConvertFrom-Json
        $active.toolchains[0].revision | Should -Be 2
        ($active.toolchains[0].packages | Where-Object name -EQ fixture-reader).version | Should -Be '1.2.0'
        ($active.toolchains[0].packages | Where-Object name -EQ typescript).version | Should -Be '5.9.3'
        & (Join-Path $script:Framework 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath $fixture.OutputPath -SchemaPath (Join-Path $script:Framework 'schemas/common/agent-result.schema.json') -SchemaRoot (Join-Path $script:Framework 'schemas') | Out-Null
    }

    It 'accepts an explicitly justified prerelease but does not choose one for a stable request' {
        $fixture = New-DependencyFixture
        $result = & $script:Resolver @fixture -Requests @(New-DependencyRequest '2.0.0-beta.1') -VersionSource $script:Versions -Probe $script:PassingProbe
        $result.status | Should -Be 'completed' -Because $result.detail
        $active = Get-Content (Get-QaFoundryActiveToolchainPath -RunRoot $fixture.RunRoot) -Raw | ConvertFrom-Json
        ($active.toolchains[0].packages | Where-Object name -EQ fixture-reader).version | Should -Be '2.0.0-beta.1'
    }

    It 'updates an existing package without disturbing unrelated pins' {
        $fixture = New-DependencyFixture
        $request = New-DependencyRequest '5.9.4'
        $request.name = 'typescript'
        $result = & $script:Resolver @fixture -Requests @($request) -VersionSource { @('5.9.3','5.9.4') } -Probe $script:PassingProbe
        $result.status | Should -Be 'completed' -Because $result.detail
        $active = Get-Content (Get-QaFoundryActiveToolchainPath -RunRoot $fixture.RunRoot) -Raw | ConvertFrom-Json
        @($active.toolchains[0].packages).Count | Should -Be 1
        $active.toolchains[0].packages[0].version | Should -Be '5.9.4'
    }

    It 'leaves the active lock unchanged after a failed compatibility probe' {
        $fixture = New-DependencyFixture
        $baseline = Get-QaFoundryActiveToolchainPath -RunRoot $fixture.RunRoot
        $result = & $script:Resolver @fixture -Requests @(New-DependencyRequest) -VersionSource $script:Versions -Probe {
            [pscustomobject]@{status='blocked';failureKind='artifact_invalid';checks=@('peer dependency conflict')}
        }
        $result.status | Should -Be 'revision_required'
        $result.changed | Should -BeFalse
        (Get-QaFoundryActiveToolchainPath -RunRoot $fixture.RunRoot) | Should -Be $baseline
    }

    It 'requires inventory revision on relay replay and resolves repeated requests only once' {
        $fixture = New-DependencyFixture
        $request = New-DependencyRequest
        $null = & $script:Resolver @fixture -Requests @($request) -VersionSource $script:Versions -Probe $script:PassingProbe
        $result = & $script:Resolver @fixture -Requests @($request) -VersionSource { throw 'Must not query again' } -Probe { throw 'Must not probe again' }
        $result.status | Should -Be 'completed' -Because $result.detail
        $result.changed | Should -BeTrue
        $fixture.OutputPath = Join-Path $fixture.RunRoot 'next-iteration.json'
        $result = & $script:Resolver @fixture -Requests @($request) -VersionSource { throw 'Must not query again' } -Probe { throw 'Must not probe again' }
        $result.status | Should -Be 'completed' -Because $result.detail
        $result.changed | Should -BeFalse
    }

    It 'rejects an unjustified or unresolvable request: <Case>' -ForEach @(
        @{Case='latest'},@{Case='no rationale'},@{Case='missing package'},@{Case='unknown toolchain'},@{Case='feed unavailable'}
    ) {
        $fixture = New-DependencyFixture
        $request = New-DependencyRequest
        $source = $script:Versions
        switch ($Case) {
            'latest' { $request.version = 'latest' }
            'no rationale' { $request.versionReason = '' }
            'missing package' { $source = { @() } }
            'unknown toolchain' { $request.toolchainId = 'unknown' }
            'feed unavailable' { $source = { throw 'service unavailable' } }
        }
        $result = & $script:Resolver @fixture -Requests @($request) -VersionSource $source -Probe { throw 'Must not probe' }
        $result.status | Should -Be $(if ($Case -eq 'feed unavailable') { 'blocked' } else { 'revision_required' })
        $result.changed | Should -BeFalse
        Test-Path (Join-Path $fixture.RunRoot 'context/toolchain-current.json') | Should -BeFalse
    }

    It 'detects tampering with an accepted lock' {
        $fixture = New-DependencyFixture
        $null = & $script:Resolver @fixture -Requests @(New-DependencyRequest) -VersionSource $script:Versions -Probe $script:PassingProbe
        $active = Get-QaFoundryActiveToolchainPath -RunRoot $fixture.RunRoot
        'tampered' | Add-Content -LiteralPath $active
        { Get-QaFoundryActiveToolchainPath -RunRoot $fixture.RunRoot } | Should -Throw '*hash*'
    }

    It 'preserves an explicit prerelease lower bound in npm ranges' {
        Select-QaFoundryNodeStyleVersion -Requested '^2.0.0-beta.1' -Published @('2.0.0-beta.0','2.0.0-beta.1','2.0.0-beta.2') -AllowPrerelease $true | Should -Be '2.0.0-beta.2'
        Select-QaFoundryNodeStyleVersion -Requested '2.0.0-beta.1' -Published @('2.0.0','2.0.0-beta.1') -AllowPrerelease $true | Should -Be '2.0.0-beta.1'
        Select-QaFoundryNodeStyleVersion -Requested '2.0.0-beta.1' -Published @('2.0.0-beta.1') -AllowPrerelease $false | Should -Be ''
    }
}
