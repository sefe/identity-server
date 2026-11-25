BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root 'scripts/Common.ps1')
    . (Join-Path $script:Root 'scripts/RepositoryDiscoveryRepair.ps1')
    function Invoke-DiscoveryFixture {
        param([string]$Scenario, [string]$Repair = 'valid', [string]$OutputPath, [int]$Retries = 0)
        $config = Import-QaFoundryYaml -Path (Join-Path $script:Root 'tests/fixtures/sample-project-config.yaml') -Root $script:Root
        $profile = & (Join-Path $script:Root 'scripts/Resolve-AiProfile.ps1') -Config $config -ProfileName mock
        foreach ($property in $profile.PSObject.Properties) {
            $config.ai | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
        }
        $config.ai.provider = 'command'
        $config.ai.command = "node $script:Root/tests/fixtures/discovery-field-repair-provider.mjs $Scenario $Repair"
        $config.runtime.agent_schema_retries = $Retries
        & (Join-Path $script:Root 'scripts/Invoke-Agent.ps1') -AgentId repository-discovery -StageId discovery -RunId run-example `
            -PromptPath (Join-Path $script:Root 'prompts/discovery/repository-discovery.md') `
            -ContextPaths @((Join-Path $script:Root 'tests/fixtures/mock-responses/repository-discovery.json')) `
            -OutputPath $OutputPath -SchemaPath (Join-Path $script:Root 'schemas/discovery/repository-discovery.schema.json') -Config $config
    }
    $script:Base = Get-Content (Join-Path $script:Root 'tests/fixtures/mock-responses/repository-discovery.json') -Raw | ConvertFrom-Json -Depth 100
}

Describe 'Repository discovery field repair through the real agent pipeline' {
    It 'repairs <Scenario> without regenerating the artifact or changing other discovery facts' -ForEach @(
        @{ Scenario = 'name' }, @{ Scenario = 'buildSystem' }, @{ Scenario = 'configurationApproach' },
        @{ Scenario = 'missing' }, @{ Scenario = 'mixed' }
    ) {
        $output = Join-Path $TestDrive "$Scenario/repository-discovery.json"
        $result = Invoke-DiscoveryFixture -Scenario $Scenario -OutputPath $output
        ($result.details | ConvertTo-Json -Depth 100 -Compress) | Should -Be ($script:Base.details | ConvertTo-Json -Depth 100 -Compress)
        $result.evidence[0].source | Should -Be $script:Base.evidence[0].source
        @(Get-ChildItem (Split-Path $output -Parent) -Filter 'repository-discovery.json.attempt-*.raw.txt').Count | Should -Be 1
        $metadata = Get-Content "$output.attempt-1.repair.provider-metadata.json" -Raw | ConvertFrom-Json -Depth 100
        $metadata.purpose | Should -Be 'field_repair'
        $record = Get-Content "$output.repair.applied.json" -Raw | ConvertFrom-Json
        $record.repaired.Count | Should -Be $(if ($Scenario -eq 'mixed') { 2 } else { 1 })
        $request = Get-Content "$output.repair.request.md" -Raw
        $request | Should -Match 'Original task, evidence and schema'
        $request | Should -Match 'src/Billing.Api/obj'
        # The receipt and usage metadata must also survive final run validation,
        # not just the discovery document's own schema check.
        { & (Join-Path $script:Root 'scripts/Test-RunArtifacts.ps1') -RunRoot (Split-Path $output -Parent) } | Should -Not -Throw
    }

    It 'rejects a <Repair> repair and retains raw evidence without publishing an artifact' -ForEach @(
        @{ Repair = 'stillLong' }, @{ Repair = 'wrongPointer' }, @{ Repair = 'duplicate' },
        @{ Repair = 'missing' }, @{ Repair = 'invalidArray' }, @{ Repair = 'wrongType' },
        @{ Repair = 'extraProperty' }, @{ Repair = 'extraRoot' }, @{ Repair = 'malformed' }
    ) {
        $output = Join-Path $TestDrive "rejected-$Repair/repository-discovery.json"
        { Invoke-DiscoveryFixture -Scenario mixed -Repair $Repair -OutputPath $output } | Should -Throw '*schema validation*'
        Test-Path "$output.repair.applied.json" | Should -BeFalse
        $original = Get-Content "$output.attempt-1.raw.txt" -Raw | ConvertFrom-Json -Depth 100
        Test-Path $output | Should -BeFalse
        Test-Path "$output.repair.candidate.tmp" | Should -BeFalse
        $original.details.componentStacks[0].configurationApproach.Length | Should -BeGreaterThan 400
        $original.details.PSObject.Properties.Name | Should -Not -Contain 'excludedFromStackDetermination'
        @(Get-ChildItem (Split-Path $output -Parent) -Filter 'repository-discovery.json.attempt-*.raw.txt').Count | Should -Be 1
    }

    It 'does not repair unapproved <Scenario> fields' -ForEach @(
        @{ Scenario = 'longPath' }, @{ Scenario = 'otherRequired' }
    ) {
        $output = Join-Path $TestDrive "$Scenario/repository-discovery.json"
        { Invoke-DiscoveryFixture -Scenario $Scenario -OutputPath $output } | Should -Throw '*schema validation*'
        Test-Path "$output.repair.request.md" | Should -BeFalse
        Test-Path "$output.repair.applied.json" | Should -BeFalse
    }

    It 'uses the remaining ordinary retry when the targeted repair is declined' {
        $output = Join-Path $TestDrive 'fallback/repository-discovery.json'
        $result = Invoke-DiscoveryFixture -Scenario mixed -Repair fallback -Retries 1 -OutputPath $output
        ($result.details | ConvertTo-Json -Depth 100 -Compress) | Should -Be ($script:Base.details | ConvertTo-Json -Depth 100 -Compress)
        @(Get-ChildItem (Split-Path $output -Parent) -Filter 'repository-discovery.json.attempt-*.raw.txt').Count | Should -Be 2
        Test-Path "$output.repair.applied.json" | Should -BeFalse
    }

    It 'does not read artifacts or invoke a provider outside its schema or remaining time budget' {
        $parameters = @{
            Errors = @([pscustomobject]@{keyword='required';instancePath='/details';params=@{missingProperty='excludedFromStackDetermination'}})
            ArtifactPath = (Join-Path $TestDrive 'nonexistent.json'); OriginalRequest = 'context'
            Provider = 'command'; Attempt = 1; TimeoutSeconds = 0
            SchemaPath = (Join-Path $script:Root 'schemas/discovery/repository-discovery.schema.json')
        }
        Repair-RepositoryDiscoveryFields @parameters | Should -BeNullOrEmpty
        $parameters.TimeoutSeconds = 300
        $parameters.SchemaPath = Join-Path $script:Root 'schemas/architecture/automation-blueprint.schema.json'
        Repair-RepositoryDiscoveryFields @parameters | Should -BeNullOrEmpty
    }
}

Describe 'Field repair evidence remains schema validated' {
    It 'accepts existing shortening receipts and rejects invalid discovery receipts' {
        $schema = Join-Path $script:Root 'schemas/runtime/field-repair.schema.json'
        $file = Join-Path $TestDrive 'receipt.json'
        $legacy = @{ artifact='result.json'; shortened=@(@{pointer='/summary';limit=2000;before=2100;after=1900}) }
        $legacy | ConvertTo-Json -Depth 20 | Set-Content $file -Encoding utf8
        (& (Join-Path $script:Root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath $file -SchemaPath $schema -NoThrow).valid | Should -BeTrue
        foreach ($entry in @(
            @{pointer='/details/componentStacks/0/path';operation='replace'},
            @{pointer='/details/excludedFromStackDetermination';operation='replace'},
            @{pointer='/details/componentStacks/0/name';operation='add'}
        )) {
            @{artifact='result.json';repaired=@($entry)} | ConvertTo-Json -Depth 20 | Set-Content $file -Encoding utf8
            (& (Join-Path $script:Root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath $file -SchemaPath $schema -NoThrow).valid | Should -BeFalse
        }
    }
}
