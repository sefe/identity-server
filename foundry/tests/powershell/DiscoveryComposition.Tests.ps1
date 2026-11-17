BeforeAll {
    $script:Framework = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Framework 'scripts/Common.ps1')
    function New-DiscoveryFixture {
        $run = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $run | Out-Null
        $paths = foreach ($agent in @('repository-discovery','requirements-discovery','delivery-environment-discovery')) {
            $path = Join-Path $run "$agent.json"
            $raw = & (Join-Path $script:Framework 'scripts/providers/Invoke-MockProvider.ps1') -AgentId $agent -StageId discovery -RunId 'run-discovery'
            $raw | Set-Content -LiteralPath $path
            $path
        }
        $decision = @{
            agentId='discovery-synthesis';stageId='discovery';runId='run-discovery';status='completed'
            summary='Usable source evidence is available; execution inputs and ambiguous expectations remain documented.'
            evidence=@();assumptions=@();unknowns=@('Deployment credentials are not provisioned.');warnings=@();deferrals=@()
            details=@{existingAutomation=@();disagreements=@('REQ-1 has contradictory expected values; preserve both source claims.');blockingContext=@()}
        }
        $decisionPath = Join-Path $run 'discovery-decision.json'
        $decision | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $decisionPath
        return @{DecisionPath=$decisionPath;SourcePaths=@($paths);RunRoot=$run;RunId='run-discovery';OutputPath=(Join-Path $run 'discovery-result.json')}
    }
    $script:Composer = Join-Path $script:Framework 'scripts/actions/New-DiscoveryResult.ps1'
}

Describe 'Discovery composition' {
    It 'preserves full source facts, identities and unresolved findings without model transcription' {
        $fixture = New-DiscoveryFixture
        $before = @($fixture.SourcePaths | ForEach-Object { (Get-FileHash $_).Hash })
        $result = & $script:Composer @fixture
        $result.status | Should -Be 'completed'
        $result.details.disagreements.Count | Should -Be 1
        $result.unknowns | Should -Contain 'Deployment credentials are not provisioned.'
        $repository = Get-Content $fixture.SourcePaths[0] -Raw | ConvertFrom-Json
        ($result.details.componentStacks | ConvertTo-Json -Depth 50 -Compress) | Should -Be ($repository.details.componentStacks | ConvertTo-Json -Depth 50 -Compress)
        @($result.details.sourceArtifacts).Count | Should -Be 3
        foreach ($reference in $result.details.sourceArtifacts) {
            (Get-FileHash (Join-Path $fixture.RunRoot $reference.relativePath)).Hash.ToLowerInvariant() | Should -Be $reference.sha256
        }
        (@($fixture.SourcePaths | ForEach-Object { (Get-FileHash $_).Hash }) -join ',') | Should -Be ($before -join ',')
    }

    It 'rejects completed synthesis declaring deferred work: <Kind>' -ForEach @(
        @{Kind='output_budget'},@{Kind='external_prerequisite'},@{Kind='product_gap'}
    ) {
        $fixture = New-DiscoveryFixture
        $decision = Get-Content $fixture.DecisionPath -Raw | ConvertFrom-Json
        $decision.deferrals = @(@{kind=$Kind;item='Environment, feature or source details';reason='Required later, or already in a source artifact.'})
        $decision | ConvertTo-Json -Depth 30 | Set-Content $fixture.DecisionPath
        { & $script:Composer @fixture } | Should -Throw '*deferrals*'
        Test-Path $fixture.OutputPath | Should -BeFalse
    }

    It 'keeps a concrete discovery blocker blocked' {
        $fixture = New-DiscoveryFixture
        $decision = Get-Content $fixture.DecisionPath -Raw | ConvertFrom-Json
        $decision.status = 'blocked'
        $decision.details.blockingContext = @('The supplied repositories identify different products and no authorized target scope can be established.')
        $decision | ConvertTo-Json -Depth 30 | Set-Content $fixture.DecisionPath
        $result = & $script:Composer @fixture
        $result.status | Should -Be 'blocked'
        $result.details.blockingContext.Count | Should -Be 1
    }

    It 'refuses a source from a different run' {
        $fixture = New-DiscoveryFixture
        $source = Get-Content $fixture.SourcePaths[0] -Raw | ConvertFrom-Json
        $source.runId = 'unrelated'
        $source | ConvertTo-Json -Depth 40 | Set-Content $fixture.SourcePaths[0]
        { & $script:Composer @fixture } | Should -Throw '*identity*'
    }

    It 'publishes the compact decision, composed result and every source through the real discovery stage' {
        $config = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'tests/fixtures/sample-project-config.yaml') -Root $script:Framework
        $profile = & (Join-Path $script:Framework 'scripts/Resolve-AiProfile.ps1') -Config $config -ProfileName mock
        foreach ($property in $profile.PSObject.Properties) {
            $config.ai | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
        }
        $policy = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'policies/default-policy.yaml') -Root $script:Framework
        $workflow = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'workflows/bootstrap-automation.yaml') -Root $script:Framework
        $workflow.stages = @($workflow.stages | Where-Object id -EQ discovery)
        $workflow.stages += [pscustomobject]@{id='test-planning';type='sequential';agents=@(
            [pscustomobject]@{id='api-test-planner';prompt='prompts/planning/api-test-planner.md';schema='schemas/planning/api-test-plan.schema.json';output='api-test-plan.json'}
        )}
        $run = Join-Path $TestDrive 'stage'
        $state = & (Join-Path $script:Framework 'scripts/Invoke-Workflow.ps1') -Workflow $workflow -Config $config -Policy $policy `
            -RunRoot $run -RepositoryRoot $script:Framework -RunId 'run-discovery'
        $state.status | Should -Be 'completed'
        $state.stages[0].iteration | Should -Be 1
        $published = @($state.stages[0].attempts[0].artifacts)
        $published.Count | Should -Be 5
        $published.name | Should -Contain 'discovery-result.json'
        $published.name | Should -Contain 'requirements-discovery.json'
        $requestPath = Join-Path $run 'test-planning/api-test-plan.json.attempt-1.request.md'
        $request = Get-Content $requestPath -Raw
        foreach ($name in @('repository-discovery','requirements-discovery','delivery-environment-discovery','discovery-result')) {
            $request | Should -Match "$name.json"
        }
        $result = & (Join-Path $script:Framework 'scripts/Test-RunArtifacts.ps1') -RunRoot $run
        $result.valid | Should -BeTrue
        $synthesisRequest = Join-Path $run 'discovery/discovery-decision.json.attempt-1.request.md'
        $written = (Get-Item $synthesisRequest).LastWriteTimeUtc
        $composed = Join-Path $run 'discovery/discovery-result.json'
        $hash = (Get-FileHash $composed).Hash
        Remove-Item -LiteralPath $composed
        $replayed = & (Join-Path $script:Framework 'scripts/Invoke-Stage.ps1') -Stage $workflow.stages[0] -Config $config -Policy $policy `
            -RunRoot $run -RepositoryRoot $script:Framework -RunId 'run-discovery' -ReuseExistingArtifacts
        $replayed.Status | Should -Be 'completed'
        (Get-Item $synthesisRequest).LastWriteTimeUtc | Should -Be $written
        (Get-FileHash $composed).Hash | Should -Be $hash
    }
}
