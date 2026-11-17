BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root scripts/Common.ps1)
    . (Join-Path $script:Root scripts/ProductDefects.ps1)
}

Describe 'Product regressions remain red and become tracked Bugs' {
    BeforeEach {
        $script:Repo = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $script:Repo | Out-Null
        Set-Content (Join-Path $script:Repo requirements.md) 'An empty product name is rejected with HTTP 400.'
        $script:Text = "failed RejectsEmptyName (14ms)`n  expected: 400`n  actual: 200`n at Tests in /work/automation/api/ProductTests.cs:line 17`n"
        $script:Cases = @(Get-QaFoundryFailedTestCases $script:Text automation/api)
        $script:ChangeSet = [pscustomobject]@{ runId = 'run'; changes = @([pscustomobject]@{
            path = 'automation/api/ProductTests.cs'; content = 'Assert.AreEqual(400, response.StatusCode);'; operation = 'create'
        }) }
        $script:Finding = [pscustomobject]@{
            sourceRef = $script:Cases[0].sourceRef; classification = 'product_defect'; signature = 'Empty name accepted'
            example = '400 expected; 200 observed'; affectedCount = 1; hypothesis = 'The response violates requirements.md.'
            evidence = @('test-path:automation/api/ProductTests.cs','requirement-path:requirements.md')
            confidence = 0.95; recommendedAction = 'File a Bug and retain the regression.'
        }
        $script:Analysis = [pscustomobject]@{ agentId = 'failure-root-cause-analyst'; status = 'completed'; findings = @($script:Finding) }
        $script:Review = $script:Analysis | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $script:Review.agentId = 'failure-evidence-auditor'
        function Get-Confirmed {
            @(Get-QaFoundryConfirmedProductDefects -Cases $script:Cases -Analysis $script:Analysis -Review @($script:Review) `
                -ChangeSet $script:ChangeSet -RepositoryRoot $script:Repo)
        }
        $script:Verification = [pscustomobject]@{
            runId = 'run'; outcome = 'toolchain_defect'; projects = @([pscustomobject]@{
                projectPath = 'automation/api'; testsFailed = 1; testsDiscovered = 10; outcome = 'toolchain_defect'
                steps = @([pscustomobject]@{ name = 'test'; status = 'failed'; exitCode = 1 })
                negativeProbe = [pscustomobject]@{ attempted = $true; failedAsExpected = $true }
            }); findings = @([pscustomobject]@{ severity = 'error'; projectPath = 'automation/api'; message = 'One test failed.' })
        }
        $script:Report = [pscustomobject]@{
            cases = @($script:Cases); confirmed = @(Get-Confirmed)
            bugActions = @([pscustomobject]@{ sourceRef = 'product-defect:' + $script:Cases[0].sourceRef; status = 'executed'; externalId = '12345' })
        }
    }

    It 'reads stable test identities from MTP, Playwright and pytest output' {
        $script:Cases.Count | Should -Be 1
        $script:Cases[0].testName | Should -Be RejectsEmptyName
        (Get-QaFoundryFailedTestCases ($script:Text.Replace('(14ms)','(300ms)')) automation/api).sourceRef | Should -Be $script:Cases[0].sourceRef
        @(Get-QaFoundryFailedTestCases '  1) [local] › tests/cart.spec.ts:12:3 › rejects empty cart ─────' automation/ui).Count | Should -Be 1
        @(Get-QaFoundryFailedTestCases 'FAILED tests/test_cart.py::test_empty - AssertionError' automation/api).Count | Should -Be 1
        @(Get-QaFoundryFailedTestCases '1 failed, 20 passed' automation/api).Count | Should -Be 0
    }

    It 'requires agreement on observed execution, the retained test and a product requirement' {
        @(Get-Confirmed).Count | Should -Be 1
        $script:Review.findings[0].classification = 'requirement_mismatch'
        @(Get-Confirmed).Count | Should -Be 0
    }

    It 'accepts independent evidence from multiple different requirement documents for the same failed test' {
        Set-Content (Join-Path $script:Repo model.md) 'The product rejects an empty name.'
        Set-Content (Join-Path $script:Repo validation.md) 'An empty name is invalid.'
        $script:Finding.evidence += 'requirement-path:model.md'
        $script:Review.findings[0].evidence = @('test-path:automation/api/ProductTests.cs','requirement-path:validation.md')
        $confirmed = @(Get-Confirmed)
        $confirmed.Count | Should -Be 1
        $confirmed[0].requirementSources.Count | Should -Be 3
        $bug = New-QaFoundryProductBugPlan -Defects $confirmed -RunId run
        $bug.items[0].description | Should -Match 'model.md'
        $bug.items[0].description | Should -Match 'validation.md'
        $script:Review.findings[0].evidence = @('test-path:automation/api/ProductTests.cs')
        @(Get-Confirmed).Count | Should -Be 0
    }

    It 'does not file a speculative, unobserved or out-of-repository finding' -ForEach @('unobserved','path','test','incomplete') {
        switch ($_) {
            unobserved { $script:Finding.sourceRef = 'invented' }
            path { $script:Finding.evidence[1] = 'requirement-path:../outside.md'; $script:Review.findings[0].evidence[1] = $script:Finding.evidence[1] }
            test { $script:Cases[0].output = 'No trace points at this test file.' }
            incomplete { $script:Review.status = 'blocked' }
        }
        @(Get-Confirmed).Count | Should -Be 0
    }

    It 'obeys the required number of independent confirmations' {
        @(Get-QaFoundryConfirmedProductDefects -Cases $script:Cases -Analysis $script:Analysis -Review @($script:Review) `
            -ChangeSet $script:ChangeSet -RepositoryRoot $script:Repo -MinimumConfirmations 3).Count | Should -Be 0
        $script:Review.agentId = $script:Analysis.agentId
        @(Get-Confirmed).Count | Should -Be 0
    }

    It 'creates stable Bug references with reproduction evidence and no product implementation tasks' {
        $first = New-QaFoundryProductBugPlan -Defects @(Get-Confirmed) -RunId first -BuildUrl 'https://example.invalid/build/1'
        $second = New-QaFoundryProductBugPlan -Defects @(Get-Confirmed) -RunId second
        $first.items[0].sourceRef | Should -Be $second.items[0].sourceRef
        $first.items[0].type | Should -Be bug
        $first.items.Count | Should -Be 1
        $first.items[0].description | Should -Match 'expected: 400|400 expected'
        $first.items[0].description | Should -Match 'requirements.md'
        $first.items[0].description | Should -Match 'do not weaken or skip'
        $path = Join-Path $script:Repo product-defect-plan.json
        $first | ConvertTo-Json -Depth 100 | Set-Content $path
        & (Join-Path $script:Root scripts/Validate-JsonArtifact.ps1) -ArtifactPath $path `
            -SchemaPath (Join-Path $script:Root schemas/actions/work-item-plan.schema.json) -SchemaRoot (Join-Path $script:Root schemas) | Out-Null
    }

    It 'allows framework readiness while preserving failed counts, exit codes and assertions' {
        Complete-QaFoundryProductDefectVerification $script:Verification $script:Report | Should -BeTrue
        $script:Verification.outcome | Should -Be verified
        $script:Verification.projects[0].testsFailed | Should -Be 1
        $script:Verification.projects[0].steps[0].status | Should -Be failed
        $script:Verification.projects[0].steps[0].exitCode | Should -Be 1
        $script:Verification.findings[0].message | Should -Match '12345'
        $script:ChangeSet.changes[0].content | Should -BeExactly 'Assert.AreEqual(400, response.StatusCode);'
    }

    It 'keeps incomplete or unproved verification blocked from readiness' -ForEach @('missing_bug','dry_run','unconfirmed','extra_failure','build','probe') {
        switch ($_) {
            missing_bug { $script:Report.bugActions = @() }
            dry_run { $script:Report.bugActions[0].status = 'dry_run' }
            unconfirmed { $script:Report.confirmed = @() }
            extra_failure { $script:Verification.projects[0].testsFailed = 2 }
            build { $script:Verification.projects[0].steps += [pscustomobject]@{ name = 'build'; status = 'failed' } }
            probe { $script:Verification.projects[0].negativeProbe.failedAsExpected = $false }
        }
        Complete-QaFoundryProductDefectVerification $script:Verification $script:Report | Should -BeFalse
        $script:Verification.outcome | Should -Be toolchain_defect
    }

    It 'connects execution evidence, independent analysis and the existing Bug writer' {
        $run = Join-Path $script:Repo run
        $directory = Join-Path $run framework-verification
        New-Item -ItemType Directory (Join-Path $directory commands) -Force | Out-Null
        Set-Content (Join-Path $run run-inputs.json) '{"version":1,"hashes":{"source":"fixture"}}'
        $log = Join-Path $directory commands/command-001.log
        Set-Content $log $script:Text
        $script:Verification.projects[0] | Add-Member ecosystem nuget
        $script:Verification.projects[0].steps[0] | Add-Member detail "Full output: commands/command-001.log [sha256: $((Get-FileHash $log).Hash.ToLowerInvariant())]"
        $verificationPath = Join-Path $directory framework-verification.json
        $script:Verification | ConvertTo-Json -Depth 50 | Set-Content $verificationPath
        $changeSetPath = Join-Path $run change-set.json
        $script:ChangeSet | ConvertTo-Json -Depth 50 | Set-Content $changeSetPath
        $seenAgents = [System.Collections.Generic.List[string]]::new()
        $analysisFixture = $script:Analysis
        $bugActionsFixture = $script:Report.bugActions
        $bugActionsFixture[0] | Add-Member type bug
        $bugActionsFixture[0] | Add-Member idempotencyKey ('a' * 64)
        $bugActionsFixture[0] | Add-Member summary 'Created a product Bug.'
        $analyzer = {
            param($AgentId,$InputPath,$OutputPath)
            $seenAgents.Add($AgentId)
            (Get-Content $InputPath -Raw) | Should -Match '400'
            $result = $analysisFixture | ConvertTo-Json -Depth 30 | ConvertFrom-Json
            $result.agentId = $AgentId
            $result | ConvertTo-Json -Depth 30 | Set-Content $OutputPath
            return $result
        }.GetNewClosure()
        $writer = {
            param($Path)
            $plan = Get-Content $Path -Raw | ConvertFrom-Json -Depth 100
            $plan.items.Count | Should -Be 1
            [pscustomobject]@{ runId = 'run'; stageId = 'framework-verification'; handler = 'create_work_items';
                status = 'completed'; dryRun = $false; actions = @($bugActionsFixture); evidence = @() }
        }.GetNewClosure()
        $config = [pscustomobject]@{ assurance = [pscustomobject]@{ high_risk_minimum_reviewers = 3 }; work_tracking = [pscustomobject]@{ enabled = $true; dry_run = $false } }
        $result = & (Join-Path $script:Root scripts/actions/Report-ProductDefects.ps1) -VerificationPath $verificationPath `
            -ChangeSetPath $changeSetPath -RunRoot $run -RepositoryRoot $script:Repo -RunId run `
            -Config $config -Policy ([pscustomobject]@{ work_tracking = [pscustomobject]@{ allow_create = $true } }) -Analyzer $analyzer -Writer $writer
        $seenAgents.Count | Should -Be 3
        $result.confirmed.Count | Should -Be 1
        $result.bugActions[0].externalId | Should -Be 12345
        (Get-Content $changeSetPath -Raw | ConvertFrom-Json).changes[0].content | Should -BeExactly $script:ChangeSet.changes[0].content

        # Changed execution must not reuse a conclusion about the same test
        # identity. Exercise the real agent envelope with a local mock provider.
        Set-Content $log ($script:Text.Replace('actual: 200','actual: 503'))
        $script:Verification.projects[0].steps[0].detail = "Full output: commands/command-001.log [sha256: $((Get-FileHash $log).Hash.ToLowerInvariant())]"
        $script:Verification | ConvertTo-Json -Depth 50 | Set-Content $verificationPath
        $stageConfig = Import-QaFoundryYaml -Path (Join-Path $script:Root tests/fixtures/sample-project-config.yaml) -Root $script:Root
        $profile = & (Join-Path $script:Root scripts/Resolve-AiProfile.ps1) -Config $stageConfig -ProfileName mock
        $stageConfig = Set-QaFoundryResolvedAiProfile -Config $stageConfig -Profile $profile
        $policy = Import-QaFoundryYaml -Path (Join-Path $script:Root policies/bootstrap-policy.yaml) -Root $script:Root
        $agentRoot = $script:Root
        $analyzer = {
            param($AgentId,$InputPath,$OutputPath)
            & (Join-Path $agentRoot scripts/Invoke-Agent.ps1) -AgentId $AgentId -StageId failure-investigation -RunId run `
                -PromptPath (Join-Path $agentRoot "prompts/operations/$AgentId.md") `
                -SchemaPath (Join-Path $agentRoot schemas/operations/failure-investigation.schema.json) `
                -ContextPaths @() -PriorityContextPaths @($InputPath) -OutputPath $OutputPath -Config $stageConfig `
                -Policy $policy -AllowExistingArtifact
        }.GetNewClosure()
        $rechecked = & (Join-Path $script:Root scripts/actions/Report-ProductDefects.ps1) -VerificationPath $verificationPath `
            -ChangeSetPath $changeSetPath -RunRoot $run -RepositoryRoot $script:Repo -RunId run `
            -Config $stageConfig -Policy $policy -Analyzer $analyzer -Writer { throw 'No confirmed product defect: writer must not run.' }
        $rechecked.confirmed.Count | Should -Be 0
        $rechecked.bugActions.Count | Should -Be 0
        $rechecked.artifacts[0] | Should -Not -Be $result.artifacts[0]
    }
}
