BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root 'scripts/Common.ps1')
}
Describe 'Architecture field repair' {
    It 'repairs revision summary before merge and only invalid prose fields after merge' {
        $directory=Join-Path $TestDrive 'architecture'
        New-Item -ItemType Directory $directory | Out-Null
        $basePath=Join-Path $directory 'base.json'
        $base=Get-Content (Join-Path $script:Root 'tests/fixtures/blueprints/bounded-blueprint.json') -Raw | ConvertFrom-Json -Depth 100
        $base.runId='run-field-repair'
        $base | Add-Member -NotePropertyName deferrals -NotePropertyValue @() -Force
        $base | ConvertTo-Json -Depth 100 | Set-Content $basePath -Encoding utf8
        $before=(Get-FileHash $basePath).Hash
        $config=Import-QaFoundryYaml -Path (Join-Path $script:Root 'tests/fixtures/sample-project-config.yaml') -Root $script:Root
        $profile=& (Join-Path $script:Root 'scripts/Resolve-AiProfile.ps1') -Config $config -ProfileName mock
        foreach($property in $profile.PSObject.Properties){$config.ai | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force}
        $config.ai.provider='command'
        $config.ai.command="node $script:Root/tests/fixtures/architecture-field-repair-provider.mjs $basePath"
        $config.runtime.agent_schema_retries=0
        $output=Join-Path $directory 'blueprint.json'
        $result=& (Join-Path $script:Root 'scripts/Invoke-Agent.ps1') -AgentId automation-architect -StageId architecture -RunId run-field-repair `
            -PromptPath (Join-Path $script:Root 'prompts/architecture/automation-architect.md') -ContextPaths @() `
            -OutputPath $output -SchemaPath (Join-Path $script:Root 'schemas/architecture/automation-blueprint.schema.json') `
            -RevisionBasePath $basePath -Config $config
        $result.summary.Length | Should -BeLessOrEqual 2000
        $result.details.ciIntegration.artifactGate.Length | Should -BeLessOrEqual 800
        $result.details.configuration.topicNaming.Length | Should -BeLessOrEqual 800
        $result.details.configuration.authorityPolicy.Length | Should -BeLessOrEqual 800
        $result.details.automationProjects[0].toolchain.packages[0].purpose.Length | Should -BeLessOrEqual 400
        $result.details.automationProjects[0].toolchain.coverageFit[0].howItIsMet.Length | Should -BeLessOrEqual 400
        ($result.details.proposedCommands | ConvertTo-Json -Depth 50 -Compress) | Should -Be ($base.details.proposedCommands | ConvertTo-Json -Depth 50 -Compress)
        (Get-FileHash $basePath).Hash | Should -Be $before
        @(Get-ChildItem $directory -Filter 'blueprint.json.attempt-*.raw.txt').Count | Should -Be 1
        Test-Path "$output.revision-input.json.repair.applied.json" | Should -BeTrue
        Test-Path "$output.repair.applied.json" | Should -BeTrue
    }
}
