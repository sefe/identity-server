BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root 'scripts/Common.ps1')
    function New-AssessmentCase {
        $run = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $run 'implementation') -Force | Out-Null
        $workflow = Import-QaFoundryYaml -Path (Join-Path $script:Root 'workflows/bootstrap-automation.yaml') -Root $script:Root
        $records = @()
        foreach ($agent in @('framework-implementation','test-implementation')) {
            $path = Join-Path $run "implementation/$agent.json"
            @{agentId=$agent;stageId='implementation';runId='run-assessment';status='completed';summary='File contracts';
                evidence=@();assumptions=@();unknowns=@();warnings=@();details=@{};
                plannedFiles=@(@{path="automation/$agent.ts";operation='create';purpose='Fixture';contentContract='Implement the required assertions.'});
                commandsProposed=@('npm test');deferrals=@()} | ConvertTo-Json -Depth 30 | Set-Content $path
            $records += @{name="$agent.json";relativePath="implementation/$agent.json";sha256=(Get-FileHash $path).Hash.ToLowerInvariant()}
        }
        @{runId='run-assessment';workflowName='bootstrap-automation';stages=@(@{id='implementation';status='completed';attempts=@(@{status='completed';artifacts=$records})})} |
            ConvertTo-Json -Depth 30 | Set-Content (Join-Path $run 'workflow-state.json')
        return @{Run=$run;Workflow=$workflow}
    }
    function Assess($Case) {
        & (Join-Path $script:Root 'scripts/actions/New-BootstrapExecutionAssessment.ps1') -Workflow $Case.Workflow `
            -RunRoot $Case.Run -RunId run-assessment -OutputDirectory (Join-Path $Case.Run 'execution')
    }
    function StageSettings {
        $config = Import-QaFoundryYaml -Path (Join-Path $script:Root 'tests/fixtures/sample-project-config.yaml') -Root $script:Root
        $profile = & (Join-Path $script:Root 'scripts/Resolve-AiProfile.ps1') -Config $config -ProfileName mock
        foreach ($p in $profile.PSObject.Properties) { $config.ai | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
        $policy = Import-QaFoundryYaml -Path (Join-Path $script:Root 'policies/default-policy.yaml') -Root $script:Root
        return @{Config=$config;Policy=$policy}
    }
}
Describe 'Bootstrap execution phase boundaries' {
    It 'records an honest assessment without calling a model or touching the product' {
        $case=New-AssessmentCase
        $settings=StageSettings
        $settings.Config.ai.provider='command'
        $settings.Config.ai.command='a-provider-that-must-never-be-started'
        $stage=@($case.Workflow.stages | Where-Object id -EQ execution)[0]
        $result=& (Join-Path $script:Root 'scripts/Invoke-Stage.ps1') -Stage $stage -Workflow $case.Workflow `
            -RunRoot $case.Run -RepositoryRoot $case.Run -RunId run-assessment @settings
        $result.Status | Should -Be completed
        $result.CoverageIncomplete | Should -BeFalse
        @($result.Artifacts).Count | Should -Be 3
        @($result.Inputs).Count | Should -Be 2
        $analysis=Get-Content (Join-Path $case.Run 'execution/failure-analysis.json') -Raw | ConvertFrom-Json
        $analysis.details.executionPerformed | Should -BeFalse
        @($analysis.failures).Count | Should -Be 0
        @($analysis.details.plannedFiles).Count | Should -Be 2
        ($analysis.warnings -join ' ') | Should -Match 'not passing test'
        Test-Path (Join-Path $case.Run 'automation') | Should -BeFalse
        @(Get-ChildItem $case.Run -Recurse -Filter '*.request.md').Count | Should -Be 0
        (& (Join-Path $script:Root 'scripts/Test-RunArtifacts.ps1') -RunRoot (Join-Path $case.Run 'execution')).valid | Should -BeTrue
    }
    It 'refuses to replace execution when the real gate is weakened: <Change>' -ForEach @(
        @{Change='missing'},@{Change='proceed'},@{Change='different input'},@{Change='wrong order'}
    ) {
        $case=New-AssessmentCase
        $gate=@($case.Workflow.stages | Where-Object id -EQ framework-verification)[0]
        switch($Change) {
            missing {$case.Workflow.stages=@($case.Workflow.stages | Where-Object id -NE framework-verification)}
            proceed {$gate.approval.on_exhaustion='proceed'}
            'different input' {$gate.action.inputs.changeSet.stage='implementation'}
            'wrong order' {$case.Workflow.stages=@($gate)+@($case.Workflow.stages | Where-Object id -NE framework-verification)}
        }
        {Assess $case} | Should -Throw
    }
    It 'refuses a changed approved inventory' {
        $case=New-AssessmentCase
        Add-Content (Join-Path $case.Run 'implementation/framework-implementation.json') ' '
        {Assess $case} | Should -Throw '*changed since*'
    }
    It 'writes fresh evidence for an empty plan in an ordinary execution stage' {
        $case=New-AssessmentCase
        $settings=StageSettings
        $settings.Config.ai.provider='command'
        $settings.Config.ai.command="node $script:Root/tests/fixtures/empty-execution-provider.mjs"
        $stage=@($case.Workflow.stages | Where-Object id -EQ execution)[0]
        $result=& (Join-Path $script:Root 'scripts/Invoke-Stage.ps1') -Stage $stage -Iteration 2 `
            -RunRoot $case.Run -RepositoryRoot $case.Run -RunId run-assessment @settings
        $result.Status | Should -Be completed
        @($result.Artifacts | Where-Object name -EQ 'execution-result.json').Count | Should -Be 1
        $analysis=Get-Content (Join-Path $case.Run 'execution/iteration-2/failure-analysis.json') -Raw | ConvertFrom-Json
        $analysis.details.currentEvidence.runId | Should -Be run-assessment
        @($analysis.details.currentEvidence.commands).Count | Should -Be 0
    }
}
