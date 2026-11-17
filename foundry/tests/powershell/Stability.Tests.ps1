BeforeAll {
    $script:Framework = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Framework 'scripts/RelayEvidence.ps1')
    . (Join-Path $script:Framework 'scripts/CompletionStatus.ps1')
    . (Join-Path $script:Framework 'scripts/RunInputs.ps1')
    . (Join-Path $script:Framework 'scripts/DeliveryIdentity.ps1')
    function New-Evidence {
        param([string]$Name = 'evidence')
        $root = Join-Path $TestDrive ("$Name-$([guid]::NewGuid().ToString('N'))")
        New-Item -ItemType Directory -Path (Join-Path $root 'run-selected') -Force | Out-Null
        '{"runId":"run-selected","status":"paused"}' |
            Set-Content -LiteralPath (Join-Path $root 'run-selected/workflow-state.json')
        & (Join-Path $script:Framework 'scripts/Transfer-RelayEvidence.ps1') -Mode Seal `
            -SourceRoot $root -BuildId '100' -Leg 'leg1'
        return $root
    }
}

Describe 'Run input compatibility and controlled stage recovery' {
    It 'allows budget changes but rejects a changed product file or prompt' {
        $repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $repo | Out-Null
        $null = & git -C $repo init -q
        'first' | Set-Content (Join-Path $repo 'product.txt')
        $framework = Join-Path $repo 'framework'
        New-Item -ItemType Directory -Path (Join-Path $framework 'prompts'),(Join-Path $framework 'schemas') -Force | Out-Null
        'prompt' | Set-Content (Join-Path $framework 'prompts/shared.md')
        $config = [pscustomobject]@{ runtime = @{relay=@{budget_minutes=5}}; ai=@{run_budget=@{max_total_tokens=100}} }
        $args = @{RepositoryRoot=$repo;FrameworkRoot=$framework;Config=$config;Workflow=@{name='sample'};Policy=@{allow=$false}}
        # An unborn branch is a supported local fixture: the content fingerprint is authoritative.
        $null = & git -C $repo -c user.name=Test -c user.email=test@example.invalid commit --allow-empty -qm initial
        $before = Get-QaFoundryRunInputs @args
        $config.ai.run_budget.max_total_tokens = 200
        $same = Get-QaFoundryRunInputs @args
        { Assert-QaFoundryRunInputs -Recorded $before -Current $same } | Should -Not -Throw
        'changed' | Set-Content (Join-Path $repo 'product.txt')
        $changed = Get-QaFoundryRunInputs @args
        { Assert-QaFoundryRunInputs -Recorded $before -Current $changed } | Should -Throw '*source*'
        'first' | Set-Content (Join-Path $repo 'product.txt')
        'changed' | Set-Content (Join-Path $framework 'prompts/shared.md')
        $changed = Get-QaFoundryRunInputs @args
        { Assert-QaFoundryRunInputs -Recorded $before -Current $changed } | Should -Throw '*contracts*'
    }

    It 'archives the rejected stage and its downstream results while retaining upstream evidence' {
        $run = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $workflow = [pscustomobject]@{ stages = @(
            [pscustomobject]@{id='design';type='agent';artifact_directory='planning'},
            [pscustomobject]@{id='materialize';type='deterministic_action';action=@{handler='materialize_change_set'}},
            [pscustomobject]@{id='review';type='agent'}
        ) }
        foreach ($directory in @('planning','materialize','review')) {
            New-Item -ItemType Directory -Path (Join-Path $run $directory) -Force | Out-Null
            'old evidence' | Set-Content (Join-Path $run "$directory/artifact.json")
        }
        $state = @{ status='blocked';currentStage='materialize';stageIteration=3;updatedAt=''; stages=@(
            @{id='design';status='completed';iteration=1;attempts=@(@{status='completed'})},
            @{id='materialize';status='blocked';iteration=3;attempts=@(@{status='blocked'})},
            @{id='review';status='pending';iteration=0;attempts=@()}
        ) }
        $state | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $run 'workflow-state.json')
        & (Join-Path $script:Framework 'scripts/Reset-WorkflowStage.ps1') -RunRoot $run -Workflow $workflow -StageId materialize
        $resumed = Get-Content (Join-Path $run 'workflow-state.json') -Raw | ConvertFrom-Json -Depth 20
        $resumed.status | Should -Be 'paused'
        $resumed.stages[0].iteration | Should -Be 1
        $resumed.stages[1].iteration | Should -Be 0
        Test-Path (Join-Path $run 'planning/artifact.json') | Should -BeTrue
        Test-Path (Join-Path $run 'materialize/artifact.json') | Should -BeFalse
        @(Get-ChildItem (Join-Path $run 'recovery') -Recurse -Filter artifact.json).Count | Should -Be 2
    }

    It 'refuses to replay a stage that may already have pushed or published' {
        $run = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $run | Out-Null
        @{status='failed';stages=@(@{id='delivery';iteration=1;status='failed'})} |
            ConvertTo-Json -Depth 10 | Set-Content (Join-Path $run 'workflow-state.json')
        $workflow = [pscustomobject]@{stages=@([pscustomobject]@{id='delivery';type='deterministic_action';action=@{handler='deliver_changes'}})}
        { & (Join-Path $script:Framework 'scripts/Reset-WorkflowStage.ps1') -RunRoot $run -Workflow $workflow -StageId delivery } |
            Should -Throw '*external effects*'
        Test-Path (Join-Path $run 'recovery') | Should -BeFalse
    }
}

Describe 'Durable delivery identity' {
    It 'keeps one bootstrap transaction when a new run writes a new timestamp into its plan' {
        $first = Get-QaFoundryChangeDeliveryIdentity -TargetBranch develop -Changes @([pscustomobject]@{path='.foundry/installation-plan.json';operation='create';content='run-one'})
        $second = Get-QaFoundryChangeDeliveryIdentity -TargetBranch develop -Changes @([pscustomobject]@{path='.foundry/installation-plan.json';operation='create';content='run-two'})
        $first.slug | Should -Be $second.slug
        $first.durable | Should -BeTrue
    }
    It 'distinguishes different approved content for ordinary deliveries' {
        $first = Get-QaFoundryChangeDeliveryIdentity -TargetBranch develop -Changes @([pscustomobject]@{path='automation/a.ts';operation='create';content='one'})
        $second = Get-QaFoundryChangeDeliveryIdentity -TargetBranch develop -Changes @([pscustomobject]@{path='automation/a.ts';operation='create';content='two'})
        $first.slug | Should -Not -Be $second.slug
    }
}

Describe 'Relay evidence ownership and integrity' {
    It 'seals a failure before workflow initialization as diagnostic evidence without allowing resume' {
        $root = Join-Path $TestDrive ('early-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root 'run-early/context') -Force | Out-Null
        '{"status":"unavailable","warnings":["401 Unauthorized"]}' | Set-Content (Join-Path $root 'run-early/context/ci-evidence.json')
        Set-QaFoundryRelayRun -ArtifactRoot $root -RunId run-early
        & (Join-Path $script:Framework 'scripts/Transfer-RelayEvidence.ps1') -Mode Seal -SourceRoot $root -BuildId 100 -Leg leg1
        $manifest = Test-QaFoundryRelayEvidence -Root $root -BuildId 100 -Leg leg1
        $manifest.resumable | Should -BeFalse
        $manifest.runId | Should -Be 'run-early'
        { Get-QaFoundryRelayRun -ArtifactRoot $root } | Should -Throw '*no workflow state*'
        { & (Join-Path $script:Framework 'scripts/Transfer-RelayEvidence.ps1') -Mode Restore -SourceRoot $root -BuildId 100 -Leg leg1 } |
            Should -Throw '*diagnostic evidence only*'
    }

    It 'seals bootstrap-only evidence when no analysis was started' {
        $root = Join-Path $TestDrive ('bootstrap-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $root 'bootstrap') -Force | Out-Null
        '{"status":"failed"}' | Set-Content (Join-Path $root 'bootstrap/result.json')
        & (Join-Path $script:Framework 'scripts/Transfer-RelayEvidence.ps1') -Mode Seal -SourceRoot $root -BuildId 100 -Leg leg1
        $manifest = Test-QaFoundryRelayEvidence -Root $root -BuildId 100 -Leg leg1
        $manifest.resumable | Should -BeFalse
        $manifest.runId | Should -Be ''
    }

    It 'selects the recorded run even when another run has a later name' {
        $root = New-Evidence
        New-Item -ItemType Directory -Path (Join-Path $root 'run-zzzz') | Out-Null
        '{"status":"completed"}' | Set-Content (Join-Path $root 'run-zzzz/workflow-state.json')
        (Get-QaFoundryRelayRun -ArtifactRoot $root).Name | Should -Be 'run-selected'
    }
    It 'refuses ambiguous legacy evidence' {
        $root = New-Evidence
        Remove-Item -LiteralPath (Join-Path $root 'active-run.json')
        New-Item -ItemType Directory -Path (Join-Path $root 'run-another') | Out-Null
        '{}' | Set-Content (Join-Path $root 'run-another/workflow-state.json')
        { Get-QaFoundryRelayRun -ArtifactRoot $root } | Should -Throw '*Ambiguous*'
    }
    It 'rejects a complete artifact from another build' {
        $root = New-Evidence
        { Test-QaFoundryRelayEvidence -Root $root -BuildId '101' -Leg 'leg1' } | Should -Throw '*belong*'
    }
    It 'rejects partial downloads and changed state' {
        $root = New-Evidence
        '{"status":"completed"}' | Set-Content (Join-Path $root 'run-selected/workflow-state.json')
        { Test-QaFoundryRelayEvidence -Root $root -BuildId '100' -Leg 'leg1' } | Should -Throw '*changed*'
        Remove-Item -LiteralPath (Join-Path $root 'run-selected/workflow-state.json')
        { Test-QaFoundryRelayEvidence -Root $root -BuildId '100' -Leg 'leg1' } | Should -Throw '*changed*'
    }
    It 'restores the whole verified artifact and refuses an overlay' {
        $root = New-Evidence
        Push-Location $TestDrive
        try {
            $restore = Join-Path $script:Framework 'scripts/Transfer-RelayEvidence.ps1'
            & $restore -Mode Restore -SourceRoot $root -BuildId '100' -Leg 'leg1' -ArtifactRoot 'restored'
            (Test-QaFoundryRelayEvidence -Root (Join-Path $TestDrive 'restored') -BuildId '100' -Leg 'leg1').runId |
                Should -Be 'run-selected'
            { & $restore -Mode Restore -SourceRoot $root -BuildId '100' -Leg 'leg1' -ArtifactRoot 'restored' } |
                Should -Throw '*absent*'
        } finally { Pop-Location }
    }
}

Describe 'Early toolchain execution and diagnostic replay' {
    It 'persists the CI authentication failure before throwing and trims the mapped PAT' {
        $ci = [pscustomobject]@{
            provider='azure-devops';collect_realtime=$true;fail_on_collection_error=$true
            azure_devops=@{organization_url='https://dev.azure.com/example';project='product';auth_env='AZURE_DEVOPS_TOKEN';auth_scheme='basic'}
        }
        # Use a PSCustomObject for settings, as configuration import produces.
        $ci.azure_devops = [pscustomobject]$ci.azure_devops
        $expected = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(':test-pat'))
        Mock Invoke-RestMethod {
            param($Headers)
            $Headers.Authorization | Should -Be $expected
            throw '401 Unauthorized'
        }
        $output = Join-Path $TestDrive 'failed-ci.json'
        { & (Join-Path $script:Framework 'scripts/collectors/Collect-CiEvidence.ps1') `
            -RunId run-early -EventPath (Join-Path $script:Framework 'tests/fixtures/events/azure-devops-build-failed.json') `
            -CiConfig $ci -OutputPath $output -ProviderEnvironment @{AZURE_DEVOPS_TOKEN=" test-pat`r`n"} } |
            Should -Throw '*build details*401*'
        $raw = Get-Content -LiteralPath $output -Raw
        ($raw | ConvertFrom-Json).status | Should -Be 'unavailable'
        $raw | Should -Not -Match 'test-pat'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }

    It 'selects the highest matching npm release with a linear number of comparisons' {
        . (Join-Path $script:Framework 'scripts/Common.ps1')
        $script:versionComparator = (Get-Command Compare-QaFoundryVersion).ScriptBlock
        $script:versionComparisons = 0
        Mock Compare-QaFoundryVersion {
            param($Left, $Right)
            $script:versionComparisons++
            & $script:versionComparator -Left $Left -Right $Right
        }
        $versions = @(100..0 | ForEach-Object { "1.$_.0" }) + @('2.0.0', '1.101.0-beta.1')
        Select-QaFoundryNodeStyleVersion -Requested '^1.0.0' -Published $versions | Should -Be '1.100.0'
        $script:versionComparisons | Should -BeLessThan (3 * $versions.Count)
    }

    It 'retains the last equivalent version and filters excluded releases' {
        . (Join-Path $script:Framework 'scripts/Common.ps1')
        Select-QaFoundryNodeStyleVersion -Requested '*' -Published @('1.0.0+first', '2.0.0-beta', '1.0.0+last') |
            Should -Be '1.0.0+last'
        Select-QaFoundryNodeStyleVersion -Requested '<1.0.0' -Published @('1.0.0', '2.0.0') |
            Should -Be ''
    }

    It 'restores and compiles an isolated minimal dotnet project without product configuration' -Skip:(-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        $sdk = [string](& dotnet --version)
        $major = [int]($sdk.Trim().Split('.')[0])
        $toolchain = [pscustomobject]@{
            id='probe';ecosystem='nuget';source=@{registry='https://api.nuget.org/v3/index.json'}
            runtime=@{sdkMajor=$major;targetFramework="net$major.0"};packages=@()
        }
        $scratch = Join-Path $TestDrive ('probe-' + [guid]::NewGuid().ToString('N'))
        $result = & (Join-Path $script:Framework 'scripts/actions/Resolve-EcosystemLock.ps1') `
            -Toolchain $toolchain -WorkRoot $scratch -ManifestName FoundryProbe -BuildProbe
        $result.succeeded | Should -BeTrue -Because $result.detail
        Test-Path (Join-Path $scratch "project/bin/Release/net$major.0/FoundryProbe.dll") | Should -BeTrue
    }

    It 'refuses replay of delivery before creating a workspace or reading run artifacts' {
        { & (Join-Path $script:Framework 'scripts/Replay-FoundryStage.ps1') `
            -RunRoot (Join-Path $TestDrive 'does-not-exist') -StageId delivery-preparation } |
            Should -Throw '*Replay supports only*'
    }

    It 'records a rehearsal without contacting credentials or the target repository' {
        $output = Join-Path $TestDrive 'prerequisites.json'
        & (Join-Path $script:Framework 'scripts/Test-RunPrerequisites.ps1') `
            -Config ([pscustomobject]@{}) -RepositoryRoot $TestDrive -OutputPath $output -Demo
        $result = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
        $result.status | Should -Be 'completed'
        $result.checks[0].name | Should -Be 'rehearsal'
        $result.checks[0].detail | Should -Match 'not contacted'
    }
}

Describe 'Startup authentication diagnostics' {
    BeforeEach {
        $script:prerequisiteConfig = [pscustomobject]@{delivery=[pscustomobject]@{
            provider='azure-devops';dry_run=$false;push_branch=$true;create_draft_pull_request=$false
            azure_devops=[pscustomobject]@{organization_url='https://dev.azure.com/example';project='project';repository_id='repo';auth_env='ADO_TEST';auth_scheme='basic'}
        }}
        $script:prerequisiteOutput = Join-Path $TestDrive 'startup.json'
    }
    It 'rejects an unexpanded secret before any HTTP request' {
        Mock Invoke-RestMethod { throw 'Unexpected network call' }
        { & (Join-Path $script:Framework 'scripts/Test-RunPrerequisites.ps1') -Config $script:prerequisiteConfig `
            -RepositoryRoot $TestDrive -OutputPath $script:prerequisiteOutput -ActionEnvironment @{ADO_TEST='$(MISSING_PAT)'} } |
            Should -Throw '*secret mapping*unexpanded*'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        (Get-Content $script:prerequisiteOutput -Raw | ConvertFrom-Json).status | Should -Be 'blocked'
    }
    It 'records the failed identity check without response body or credential' {
        Mock Invoke-RestMethod {
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Unauthorized)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('private-response-body', $response)
        }
        { & (Join-Path $script:Framework 'scripts/Test-RunPrerequisites.ps1') -Config $script:prerequisiteConfig `
            -RepositoryRoot $TestDrive -OutputPath $script:prerequisiteOutput -ActionEnvironment @{ADO_TEST='private-test-token'} } |
            Should -Throw '*PAT identity*HTTP 401*'
        $text = Get-Content $script:prerequisiteOutput -Raw
        $text | Should -Not -Match 'private-test-token|private-response-body'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly
    }
    It 'distinguishes repository access failure from successful authentication' {
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -match 'connectionData') {
                return [pscustomobject]@{authenticatedUser=[pscustomobject]@{
                    id='test-user';providerDisplayName='Test User';customDisplayName='Test User'
                    properties=[pscustomobject]@{Account=[pscustomobject]@{'$value'='user@example.invalid'}}
                }}
            }
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('private-response-body', $response)
        }
        { & (Join-Path $script:Framework 'scripts/Test-RunPrerequisites.ps1') -Config $script:prerequisiteConfig `
            -RepositoryRoot $TestDrive -OutputPath $script:prerequisiteOutput -ActionEnvironment @{ADO_TEST='private-test-token'} } |
            Should -Throw '*repository read access*HTTP 403*'
        $artifact = Get-Content $script:prerequisiteOutput -Raw | ConvertFrom-Json
        $artifact.checks.name | Should -Contain 'azure-devops.identity'
        $artifact.status | Should -Be 'blocked'
        Should -Invoke Invoke-RestMethod -Times 2 -Exactly
    }
}

Describe 'Spreadsheet upload fixtures' {
    It 'regenerates the checked workbook and carries the specified numeric cells' {
        $output = Join-Path $TestDrive 'fixture.json'
        & (Join-Path $script:Framework 'scripts/New-SpreadsheetFixture.ps1') -OutputPath $output
        $generated = Get-Content $output -Raw | ConvertFrom-Json
        $checked = Get-Content (Join-Path $script:Framework 'prompts/shared/fixtures/single-column-prices.json') -Raw | ConvertFrom-Json
        # ZIP platform metadata may differ across Windows and Linux; verify both workbooks.
        foreach ($fixture in @($generated, $checked)) {
        $bytes = [Convert]::FromBase64String($fixture.base64)
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant() | Should -Be $fixture.sha256
        $stream = [IO.MemoryStream]::new($bytes)
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
        try {
            $reader = [IO.StreamReader]::new($zip.GetEntry('xl/worksheets/sheet1.xml').Open())
            try { $sheet = [xml]$reader.ReadToEnd() } finally { $reader.Dispose() }
            $cells = @($sheet.worksheet.sheetData.row.c)
            $cells.Count | Should -Be 2
            $cells[0].r | Should -Be 'A1'
            $cells[0].v | Should -Be '10'
            $cells[1].r | Should -Be 'A2'
            $cells[1].v | Should -Be '20'
            $zip.GetEntry('[Content_Types].xml') | Should -Not -BeNullOrEmpty
            $zip.GetEntry('xl/_rels/workbook.xml.rels') | Should -Not -BeNullOrEmpty
        } finally { $zip.Dispose(); $stream.Dispose() }
        }
    }

    It 'supplies fixture bytes only for relevant implementation context: <Relevant>' -ForEach @(
        @{Relevant=$true;Source='The approved UI plan requires uploading a valid .xlsx spreadsheet.'},
        @{Relevant=$false;Source='The approved API plan requires a health endpoint check.'}
    ) {
        . (Join-Path $script:Framework 'scripts/Common.ps1')
        $config = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'tests/fixtures/sample-project-config.yaml') -Root $script:Framework
        $profile = & (Join-Path $script:Framework 'scripts/Resolve-AiProfile.ps1') -Config $config -ProfileName mock
        foreach ($property in $profile.PSObject.Properties) {
            $config.ai | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
        }
        $config.ai.provider = 'command'
        $config.ai.command = "node $script:Framework/tests/fixtures/deferral-provider.mjs executionPrerequisite"
        $context = Join-Path $TestDrive 'context.md'
        Set-Content $context $Source
        $output = Join-Path $TestDrive "fixture-$Relevant-output.json"
        $null = & (Join-Path $script:Framework 'scripts/Invoke-Agent.ps1') -AgentId fixture-test -StageId implementation `
            -RunId run-fixture -PromptPath (Join-Path $script:Framework 'prompts/implementation/test-implementation.md') `
            -ContextPaths @($context) -OutputPath $output -SchemaPath (Join-Path $script:Framework 'schemas/common/agent-result.schema.json') `
            -Config $config -RepositoryRoot $script:Framework
        $request = Get-Content "$output.attempt-1.request.md" -Raw
        $fixture = Get-Content (Join-Path $script:Framework 'prompts/shared/fixtures/single-column-prices.json') -Raw | ConvertFrom-Json
        $request.Contains($fixture.base64) | Should -Be $Relevant
        $request.Contains($fixture.sha256) | Should -Be $Relevant
    }
}

Describe 'Completion reasons' {
    It 'completes an owner inventory before invoking a dependent agent' {
        . (Join-Path $script:Framework 'scripts/Common.ps1')
        $config = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'tests/fixtures/sample-project-config.yaml') -Root $script:Framework
        $profile = & (Join-Path $script:Framework 'scripts/Resolve-AiProfile.ps1') -Config $config -ProfileName mock
        foreach ($property in $profile.PSObject.Properties) {
            $config.ai | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
        }
        $config.ai.provider = 'command'
        $config.ai.command = "node $script:Framework/tests/fixtures/deferral-provider.mjs ownerDependency"
        $policy = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'policies/default-policy.yaml') -Root $script:Framework
        $workflow = [pscustomobject]@{name='dependencies';version=1;stages=@([pscustomobject]@{
            id='implementation';type='sequential';agents=@(
                [pscustomobject]@{id='foundation';prompt='prompts/implementation/framework-implementation.md';schema='schemas/common/agent-result.schema.json';output='foundation.json'},
                [pscustomobject]@{id='dependent';prompt='prompts/implementation/test-implementation.md';schema='schemas/common/agent-result.schema.json';output='dependent.json'}
            )
        })}
        $run = Join-Path $TestDrive 'owner-dependency'
        $state = & (Join-Path $script:Framework 'scripts/Invoke-Workflow.ps1') -Workflow $workflow -Config $config -Policy $policy `
            -RepositoryRoot $script:Framework -RunRoot $run -RunId 'run-dependencies'
        $state.status | Should -Be 'completed'
        $state.stages[0].iteration | Should -Be 2
        $state.stages[0].attempts[0].status | Should -Be 'revision_required'
        Test-Path (Join-Path $run 'implementation/dependent.json.attempt-1.request.md') | Should -BeFalse
        $owner = Get-Content (Join-Path $run 'implementation/iteration-2/foundation.json') -Raw | ConvertFrom-Json
        $owner.details.completedFiles | Should -Contain 'QueryClient.cs'
        $dependent = Get-Content (Join-Path $run 'implementation/iteration-2/dependent.json') -Raw | ConvertFrom-Json
        $dependent.details.completedFiles | Should -Contain 'QueryTests.cs'
    }

    It 'distinguishes planned execution dependencies from omitted deliverables: <Behaviour>' -ForEach @(
        @{Behaviour='executionPrerequisite';Expected='completed'},
        @{Behaviour='planningPrerequisite';Expected='blocked'}
    ) {
        . (Join-Path $script:Framework 'scripts/Common.ps1')
        $config = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'tests/fixtures/sample-project-config.yaml') -Root $script:Framework
        $profile = & (Join-Path $script:Framework 'scripts/Resolve-AiProfile.ps1') -Config $config -ProfileName mock
        foreach ($property in $profile.PSObject.Properties) {
            $config.ai | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
        }
        $config.ai.provider = 'command'
        $config.ai.command = "node $script:Framework/tests/fixtures/deferral-provider.mjs $Behaviour"
        $policy = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'policies/default-policy.yaml') -Root $script:Framework
        $workflow = [pscustomobject]@{name='prerequisites';version=1;stages=@([pscustomobject]@{
            id='test-planning';type='sequential';agents=@([pscustomobject]@{
                id='risk-test-planner';prompt='prompts/planning/risk-test-planner.md';schema='schemas/planning/risk-test-plan.schema.json';output='risk-test-plan.json'
            })
        })}
        $run = Join-Path $TestDrive $Behaviour
        $state = & (Join-Path $script:Framework 'scripts/Invoke-Workflow.ps1') -Workflow $workflow -Config $config -Policy $policy `
            -RepositoryRoot $script:Framework -RunRoot $run -RunId 'run-prerequisites'
        $state.status | Should -Be $Expected
        $state.stages[0].iteration | Should -Be 1
        if ($Expected -eq 'completed') {
            $artifact = Get-Content (Join-Path $run 'test-planning/risk-test-plan.json') -Raw | ConvertFrom-Json -Depth 20
            $artifact.riskScenarios[0].id | Should -Be 'RISK-1'
            $artifact.details.executionPrerequisites[0].input | Should -Be 'ADMIN_TOKEN'
            $artifact.details.assertions[0].scenarioId | Should -Be 'RISK-1'
            $artifact.unknowns.Count | Should -Be 1
        } else { $state.blockers[0].kind | Should -Be 'external_prerequisite' }
    }

    It 'persists a product gap after one workflow attempt without retrying or declaring success' {
        . (Join-Path $script:Framework 'scripts/Common.ps1')
        $config = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'tests/fixtures/sample-project-config.yaml') -Root $script:Framework
        $profile = & (Join-Path $script:Framework 'scripts/Resolve-AiProfile.ps1') -Config $config -ProfileName mock
        foreach ($property in $profile.PSObject.Properties) {
            $config.ai | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value -Force
        }
        $config.ai.provider = 'command'
        $config.ai.command = "node $script:Framework/tests/fixtures/deferral-provider.mjs productGap"
        $policy = Import-QaFoundryYaml -Path (Join-Path $script:Framework 'policies/default-policy.yaml') -Root $script:Framework
        $workflow = [pscustomobject]@{name='gap';version=1;stages=@([pscustomobject]@{
            id='test-planning';type='sequential';agents=@([pscustomobject]@{
                id='risk-test-planner';prompt='prompts/planning/risk-test-planner.md';schema='schemas/planning/risk-test-plan.schema.json';output='risk-test-plan.json'
            })
        })}
        $run = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $state = & (Join-Path $script:Framework 'scripts/Invoke-Workflow.ps1') -Workflow $workflow -Config $config -Policy $policy `
            -RepositoryRoot $script:Framework -RunRoot $run -RunId 'run-gap'
        $state.status | Should -Be 'blocked'
        $state.stages[0].iteration | Should -Be 1
        $state.blockers[0].kind | Should -Be 'product_gap'
        $state.blockedReason | Should -Be 'unresolved_prerequisites'
        $null = & (Join-Path $script:Framework 'scripts/Test-RunArtifacts.ps1') -RunRoot $run
    }
    It 'does not spend more generation attempts on a missing product feature' {
        Get-QaFoundryCompletionDisposition -Deferrals @([pscustomobject]@{kind='product_gap'}) | Should -Be 'blocked'
    }
    It 'does not retry missing access or an unclassified legacy omission' {
        Get-QaFoundryCompletionDisposition -Deferrals @([pscustomobject]@{kind='external_prerequisite'}) | Should -Be 'blocked'
        Get-QaFoundryCompletionDisposition -Deferrals @([pscustomobject]@{item='unknown omission'}) | Should -Be 'blocked'
    }
    It 'can revise budget omissions and artifact defects without declaring completion' {
        Get-QaFoundryCompletionDisposition -Deferrals @([pscustomobject]@{kind='output_budget'}, [pscustomobject]@{kind='artifact_invalid'}) |
            Should -Be 'revision_required'
        Get-QaFoundryCompletionDisposition -Deferrals @() | Should -Be 'completed'
    }
    It 'retains the runtime evidence for an old budget sidecar' {
        Get-QaFoundryDeferralKind -Deferral ([pscustomobject]@{item='full assignment'}) -RuntimeBudgetDeferral | Should -Be 'output_budget'
    }
}
