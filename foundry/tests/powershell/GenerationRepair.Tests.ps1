BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root 'scripts/Common.ps1')
    . (Join-Path $script:Root 'scripts/GenerationRepair.ps1')
}

Describe 'Repairing verified source without recreating the project' {
    BeforeEach {
        $script:Run = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory $script:Run | Out-Null
        $script:Plan = [pscustomobject]@{ changes = @(
            [pscustomobject]@{ path = 'automation/api/Client.cs'; operation = 'create'; content = 'existing client' },
            [pscustomobject]@{ path = 'automation/api/Other.cs'; operation = 'create'; content = 'keep this' },
            [pscustomobject]@{ path = 'automation/ui/package.json'; operation = 'create'; content = '{"scripts":{"test:deployed":"playwright test"}}' },
            [pscustomobject]@{ path = 'automation/ui/test.spec.ts'; operation = 'create'; content = 'existing assertions' }
        ) }
        $script:Verification = [pscustomobject]@{ runId = 'run'; outcome = 'toolchain_defect'; projects = @(
            [pscustomobject]@{ projectPath = 'automation/api'; manifestPath = 'automation/api/api.csproj'; ecosystem = 'nuget'; outcome = 'toolchain_defect'; steps = @(
                [pscustomobject]@{ name = 'build'; status = 'failed'; detail = '/scratch/automation/api/Client.cs(24,5): error CS1002: ; expected [/scratch/automation/api/api.csproj]' }
            ) },
            [pscustomobject]@{ projectPath = 'automation/ui'; manifestPath = 'automation/ui/package.json'; ecosystem = 'npm'; outcome = 'toolchain_defect'; steps = @(
                [pscustomobject]@{ name = 'test'; status = 'failed'; detail = 'no readable summary' }
            ) }
        ) }
        function Save-Evidence {
            $materialized = [pscustomobject]@{ runId = 'run'; changes = $script:Plan.changes }
            $state = @{ stages = @() }
            foreach ($spec in @(
                @{ id = 'bootstrap-change-materialization'; name = 'change-set.json'; document = $materialized; status = 'completed' },
                @{ id = 'framework-verification'; name = 'framework-verification.json'; document = $script:Verification; status = 'revision_required' }
            )) {
                $path = Join-Path $script:Run $spec.name
                $spec.document | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $path
                $state.stages += @{ id = $spec.id; attempts = @(@{ iteration = 1; status = $spec.status; artifacts = @(@{
                    name = $spec.name; relativePath = $spec.name; sha256 = (Get-FileHash $path).Hash
                }) }) }
            }
            $state | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $script:Run 'workflow-state.json')
        }
        function Get-Repair {
            Get-QaFoundryVerificationRepair -RunRoot $script:Run -RunId 'run' -Iteration 1 `
                -Plan $script:Plan -ApprovedPaths @($script:Plan.changes.path)
        }
        Save-Evidence
    }
    It 'targets the compiler source and missing npm script and preserves unrelated files' {
        $repair = Get-Repair
        @($repair.repairTargets.paths).Count | Should -Be 2
        $repair.repairTargets.paths | Should -Contain 'automation/api/Client.cs'
        $repair.repairTargets.paths | Should -Contain 'automation/ui/package.json'
        $repair.repairTargets[1].instruction | Should -Match 'no scripts.test'
    }
    It 'limits ambiguous diagnostics to the failed project' {
        $script:Verification.projects = @($script:Verification.projects[0])
        $script:Verification.projects[0].steps[0].detail = 'compiler failed without a source location'
        Save-Evidence
        $paths = @((Get-Repair).repairTargets.paths)
        $paths.Count | Should -Be 2
        $paths | Should -Not -Contain 'automation/ui/package.json'
    }
    It 'includes npm selection controls when a deployed preflight correctly refuses missing configuration' {
        ($script:Plan.changes | Where-Object path -eq 'automation/ui/package.json').content = '{"scripts":{"test":"playwright test","test:deployed":"playwright test"}}'
        $script:Plan.changes += [pscustomobject]@{path='automation/ui/playwright.config.ts';operation='create';content='existing runner config'}
        $script:Verification.projects[1].steps[0].detail = "Error: CPS_TARGET_ENVIRONMENT is required.`n at /scratch/automation/ui/test.spec.ts:10:2"
        Save-Evidence
        $repair = Get-Repair
        $repair.repairTargets[1].paths | Should -Contain 'automation/ui/package.json'
        $repair.repairTargets[1].paths | Should -Contain 'automation/ui/playwright.config.ts'
        $repair.repairTargets[1].paths | Should -Contain 'automation/ui/test.spec.ts'
        $repair.repairTargets[1].paths | Should -Not -Contain 'automation/api/Client.cs'
        $repair.repairTargets[1].instruction | Should -Match 'Keep deployed tests and their fail-closed preflight intact'
    }
    It 'does not treat a trailing project reference as a source error location' {
        $script:Plan.changes += [pscustomobject]@{ path = 'automation/api/api.csproj'; operation = 'create'; content = '<Project />' }
        Save-Evidence
        @((Get-Repair).repairTargets.paths) | Should -Not -Contain 'automation/api/api.csproj'
    }
    It 'refuses modified verification evidence' {
        Add-Content (Join-Path $script:Run 'framework-verification.json') ' '
        Get-Repair | Should -BeNullOrEmpty
    }
    It 'refuses diagnostics for other source bodies' {
        $script:Plan.changes[0].content = 'different source'
        Get-Repair | Should -BeNullOrEmpty
    }
    It 'refuses infrastructure errors as a reason to rewrite code' {
        $script:Verification.outcome = 'infrastructure_unavailable'
        Save-Evidence
        Get-Repair | Should -BeNullOrEmpty
    }
    It 'refuses evidence from another iteration' {
        Get-QaFoundryVerificationRepair -RunRoot $script:Run -RunId 'run' -Iteration 2 `
            -Plan $script:Plan -ApprovedPaths @($script:Plan.changes.path) | Should -BeNullOrEmpty
    }
    It 'keeps targeted repair after only the verification stage was explicitly restarted' {
        $path = Join-Path $script:Run 'workflow-state.json'
        $state = Get-Content $path -Raw | ConvertFrom-Json -Depth 50
        $state.stages[0].attempts[0].iteration = 3
        $state.stages[0].attempts[0] | Add-Member completedAt '2026-09-13T18:00:00Z'
        $state.stages[1].attempts[0] | Add-Member startedAt '2026-09-13T19:00:00Z'
        $state | ConvertTo-Json -Depth 50 | Set-Content $path
        $repair = Get-QaFoundryVerificationRepair -RunRoot $script:Run -RunId 'run' -Iteration 3 `
            -Plan $script:Plan -ApprovedPaths @($script:Plan.changes.path)
        @($repair.repairTargets.paths).Count | Should -Be 2
    }
    It 'refuses a verification that predates its materialized source even if counters agree' {
        $path = Join-Path $script:Run workflow-state.json
        $state = Get-Content $path -Raw | ConvertFrom-Json -Depth 50
        $state.stages[0].attempts[0] | Add-Member completedAt '2026-09-14T10:00:00Z'
        $state.stages[1].attempts[0] | Add-Member startedAt '2026-09-14T09:00:00Z'
        $state | ConvertTo-Json -Depth 50 | Set-Content $path
        Get-Repair | Should -BeNullOrEmpty
    }
    It 'binds repair to materialized bodies and execution instead of equal stage counters' {
        $path = Join-Path $script:Run workflow-state.json
        $state = Get-Content $path -Raw | ConvertFrom-Json -Depth 50
        $state.stages[0].attempts[0].iteration = 2
        $state.stages[0].attempts[0] | Add-Member completedAt '2026-09-14T10:00:00Z'
        $state.stages[1].attempts[0].iteration = 3
        $state.stages[1].attempts[0] | Add-Member startedAt '2026-09-14T11:00:00Z'
        $state | ConvertTo-Json -Depth 50 | Set-Content $path
        $repair = Get-QaFoundryVerificationRepair -RunRoot $script:Run -RunId run -Iteration 4 `
            -Plan $script:Plan -ApprovedPaths @($script:Plan.changes.path)
        @($repair.repairTargets.paths).Count | Should -Be 2
        $script:Plan.changes[0].content = 'unverified new source'
        Get-QaFoundryVerificationRepair -RunRoot $script:Run -RunId run -Iteration 4 `
            -Plan $script:Plan -ApprovedPaths @($script:Plan.changes.path) | Should -BeNullOrEmpty
    }
    It 'uses all compiler locations from the hash-bound command log' {
        $directory = Join-Path $script:Run 'commands'
        New-Item -ItemType Directory $directory | Out-Null
        $path = Join-Path $directory 'command-001.log'
        Set-Content $path '/scratch/automation/api/Other.cs(11,2): error CS1002: ; expected'
        $hash = (Get-FileHash $path).Hash.ToLowerInvariant()
        $script:Verification.projects[0].steps[0].detail += "`nFull output: commands/command-001.log [sha256: $hash]"
        Save-Evidence
        $repair = Get-Repair
        $repair.repairTargets.paths | Should -Contain 'automation/api/Other.cs'
        $repair.repairTargets[0].instruction | Should -Match 'Read all failures before editing'
        Add-Content $path 'modified'
        Get-Repair | Should -BeNullOrEmpty
    }
    It 'collects runtime failures across the full log and includes missing-resource wiring' {
        $script:Plan.changes += [pscustomobject]@{ path = 'automation/api/api.csproj'; operation = 'create'; content = '<Project />' }
        $script:Verification.projects = @($script:Verification.projects[0])
        $script:Verification.projects[0].steps[0].name = 'test'
        $directory = Join-Path $script:Run 'commands'
        New-Item -ItemType Directory $directory | Out-Null
        $path = Join-Path $directory 'command-003.log'
        Set-Content $path "Could not find file schema.json`nat TestOne in C:\work\automation\api\Other.cs:line 12`nat TestTwo in /scratch/automation/api/Client.cs:line 24"
        $hash = (Get-FileHash $path).Hash.ToLowerInvariant()
        $script:Verification.projects[0].steps[0].detail = "Failed tests. Full output: commands/command-003.log [sha256: $hash]"
        Save-Evidence
        $paths = @((Get-Repair).repairTargets.paths)
        $paths.Count | Should -Be 3
        $paths | Should -Contain 'automation/api/Other.cs'
        $paths | Should -Contain 'automation/api/Client.cs'
        $paths | Should -Contain 'automation/api/api.csproj'
    }
}

Describe 'Checking explicit batch delivery' {
    It 'surfaces repeated root causes once instead of just the final stack trace' {
        $exception = "System.InvalidOperationException: The schema reference path '#/definitions/Item' has not been resolved."
        $text = "$exception`n at A`n$exception`n at B`nAssertion failed. Expected condition to be false.`n  expected: 0`n  actual: 5"
        $digest = Get-QaFoundryVerificationFailureDigest $text
        ([regex]::Matches($digest, 'has not been resolved')).Count | Should -Be 1
        $digest | Should -Match 'expected: 0'
        $digest | Should -Not -Match ' at A'
        $digest.Length | Should -BeLessThan 1000
    }
    BeforeEach {
        $script:Assignment = [pscustomobject]@{ batchId = 'batch-01'; assignedPaths = @('automation/a.cs', 'automation/b.cs') }
        $script:Batch = [pscustomobject]@{ batchId = 'batch-01'; status = 'completed'; outcome = 'proposed'; deferrals = @(); changes = @(
            [pscustomobject]@{ path = 'automation/a.cs'; operation = 'create'; content = 'class A {}' },
            [pscustomobject]@{ path = 'automation/b.cs'; operation = 'create'; content = 'class B {}' }
        ) }
    }
    It 'recognizes delivery of the complete assignment' {
        Test-QaFoundryAssignedBatchCoverage $script:Batch $script:Assignment | Should -BeTrue
    }
    It 'does not accept missing, duplicated or foreign files' {
        $script:Batch.changes[1].path = 'automation/a.cs'
        Test-QaFoundryAssignedBatchCoverage $script:Batch $script:Assignment | Should -BeFalse
        $script:Batch.changes[1].path = 'automation/foreign.cs'
        Test-QaFoundryAssignedBatchCoverage $script:Batch $script:Assignment | Should -BeFalse
        $script:Batch.changes = @($script:Batch.changes[0])
        Test-QaFoundryAssignedBatchCoverage $script:Batch $script:Assignment | Should -BeFalse
    }
    It 'preserves explicitly declared unfinished work' {
        $script:Batch.deferrals = @(@{ item = 'missing assertion'; reason = 'unfinished' })
        Test-QaFoundryAssignedBatchCoverage $script:Batch $script:Assignment | Should -BeFalse
    }
    It 'refuses empty bodies and another batch identity' {
        $script:Batch.batchId = 'batch-02'
        Test-QaFoundryAssignedBatchCoverage $script:Batch $script:Assignment | Should -BeFalse
        $script:Batch.batchId = 'batch-01'
        $script:Batch.changes[0].content = ''
        Test-QaFoundryAssignedBatchCoverage $script:Batch $script:Assignment | Should -BeFalse
    }
}
