BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
    . (Join-Path $script:Root 'scripts/Common.ps1')
    . (Join-Path $script:Root 'scripts/RecoveryReuse.ps1')
    function Save-Record($Base, $Relative, $Document) {
        $path = Join-Path $Base $Relative
        New-Item -ItemType Directory (Split-Path $path) -Force | Out-Null
        $Document | ConvertTo-Json -Depth 100 | Set-Content $path
        return @{ name = Split-Path $path -Leaf; relativePath = $Relative; sha256 = (Get-FileHash $path).Hash }
    }
    function Get-Seed {
        param($Split = $script:Split)
        Get-QaFoundryRecoveryGenerationSeed -RunRoot $script:Run -RunId run -StageId generation -PlanName change-set-plan.json -CurrentSplit $Split
    }
}

Describe 'Controlled recovery reuses verified artifact identities' {
    BeforeEach {
        $script:Run = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:Archive = Join-Path $script:Run 'recovery/20260914'
        New-Item -ItemType Directory $script:Archive -Force | Out-Null
        $inputs = @{ version = 1; hashes = @{ source = 'same-source'; contracts = 'same-contracts' } }
        $null = Save-Record $script:Run run-inputs.json $inputs
        $null = Save-Record $script:Archive run-inputs.json $inputs
        $null = Save-Record $script:Archive recovery-request.json @{ stageId = 'implementation'; invalidated = @('implementation','generation','verification') }
        $script:Inventory = @{ plannedFiles = @('a.ts','b.ts','removed.ts' | ForEach-Object {
            @{ path = "automation/$_"; operation = 'create'; purpose = 'Assertions'; contentContract = 'Keep actual checks'; dependsOn = @() }
        }) }
        $inv = Save-Record $script:Archive implementation/framework-implementation.json $script:Inventory
        $basis = Save-Record $script:Archive generation/batch-basis.json @{ inventories = @(@{ path = $inv.relativePath; sha256 = $inv.sha256 }) }
        $script:Plan = @{ runId = 'run'; status = 'completed'; changes = @($script:Inventory.plannedFiles | ForEach-Object {
            @{ path = $_.path; operation = 'create'; content = "assertions in $($_.path)"; expectedSha256 = '' }
        }); materializations = @() }
        $planRecord = Save-Record $script:Archive generation/change-set-plan.json $script:Plan
        $blocked = Save-Record $script:Archive generation/iteration-2/change-set-plan.json @{ runId = 'run'; status = 'blocked'; changes = @() }
        $verification = Save-Record $script:Archive verification/framework-verification.json @{ projects = @(@{
            projectPath = 'automation/ui'; outcome = 'toolchain_defect'; steps = @(@{ name = 'test'; status = 'failed'; detail = 'Exactly one deployed project must be selected' })
        }) }
        $script:State = @{ runId = 'run'; stages = @(
            @{ id = 'implementation'; attempts = @(@{ iteration = 4; status = 'completed'; artifacts = @($inv) }) },
            @{ id = 'generation'; attempts = @(@{ iteration = 1; status = 'completed'; artifacts = @($planRecord,$basis) }, @{ iteration = 2; status = 'blocked'; artifacts = @($blocked) }) },
            @{ id = 'verification'; attempts = @(@{ iteration = 1; status = 'revision_required'; artifacts = @($verification) }) }
        ) }
        $null = Save-Record $script:Archive workflow-state.json $script:State
        $script:Split = & (Join-Path $script:Root scripts/New-ChangeSetBatches.ps1) -InventoryPaths (Join-Path $script:Archive $inv.relativePath)
    }

    It 'recovers the completed plan instead of the later blocked partial output' {
        $seed = Get-Seed
        $seed.planPath | Should -Be (Join-Path $script:Archive generation/change-set-plan.json)
        @($seed.paths).Count | Should -Be 0
        $prior = Get-QaFoundryRecoveryArtifact -RunRoot $script:Run -RunId run -StageId implementation -Name framework-implementation.json
        $prior.attempt.iteration | Should -Be 4
    }

    It 'retains accepted source through a second recovery that produced no artifacts' {
        $latest=Join-Path $script:Run recovery/20260925
        $null=Save-Record $latest run-inputs.json @{version=1;hashes=@{source='same-source';contracts='same-contracts'}}
        $null=Save-Record $latest recovery-request.json @{stageId='implementation';invalidated=@('implementation','generation','verification')}
        $null=Save-Record $latest workflow-state.json @{runId='run';stages=@(
            @{id='implementation';attempts=@(@{iteration=1;status='failed';error='merged inventory exceeds 40'})},
            @{id='generation';attempts=@()},@{id='verification';attempts=@()})}
        (Get-Seed).planPath | Should -Be (Join-Path $script:Archive generation/change-set-plan.json)
        (Get-QaFoundryRecoveryArtifact -RunRoot $script:Run -RunId run -StageId implementation -Name framework-implementation.json).attempt.iteration | Should -Be 4
        $path=New-QaFoundryRecoveryContext -RunRoot $script:Run -RunId run -StageId implementation -OutputPath (Join-Path $script:Run recovery-context.md)
        Get-Content $path -Raw | Should -Match 'Exactly one deployed project'
        $null=Save-Record $latest run-inputs.json @{version=1;hashes=@{source='different-source';contracts='same-contracts'}}
        Get-Seed | Should -BeNullOrEmpty
    }

    It 'generates changed and new contracts only, dropping removed files at merge' {
        $script:Inventory.plannedFiles = @($script:Inventory.plannedFiles | Where-Object path -ne automation/removed.ts)
        $script:Inventory.plannedFiles[0].contentContract = 'Add a real local selection'
        $script:Inventory.plannedFiles += @{ path = 'automation/local.spec.ts'; operation = 'create'; purpose = 'Local'; contentContract = 'Real assertions'; dependsOn = @() }
        $current = Save-Record $script:Run current.json $script:Inventory
        $split = & (Join-Path $script:Root scripts/New-ChangeSetBatches.ps1) -InventoryPaths (Join-Path $script:Run $current.relativePath)
        $seed = Get-Seed $split
        @($seed.paths).Count | Should -Be 2
        $seed.paths | Should -Contain automation/a.ts
        $seed.paths | Should -Contain automation/local.spec.ts
        $batch = Save-Record $script:Run batch.json @{ status = 'completed'; batchId = 'batch-01'; changes = @($seed.paths | ForEach-Object {
            @{ path = $_; operation = 'create'; content = 'new assertions' }
        }) }
        $output = Join-Path $script:Run merged.json
        $null = & (Join-Path $script:Root scripts/Merge-ChangeSetBatches.ps1) -BatchPaths (Join-Path $script:Run $batch.relativePath) `
            -ExpectedPaths @($split.approvedFiles.path) -CarriedPlanPath $seed.planPath -RegeneratedPaths $seed.paths `
            -OutputPath $output -AgentId generator -StageId generation -RunId run
        $merged = Get-Content $output -Raw | ConvertFrom-Json
        @($merged.changes).Count | Should -Be 3
        ($merged.changes | Where-Object path -eq automation/b.ts).content | Should -Be 'assertions in automation/b.ts'
        $merged.changes.path | Should -Not -Contain automation/removed.ts
    }

    It 'carries unchanged source without any generated batch and still enforces coverage' {
        $seed = Get-Seed
        $mergeArgs = @{ BatchPaths = @(); ExpectedPaths = @($script:Split.approvedFiles.path); CarriedPlanPath = $seed.planPath
            CarryAll = $true; OutputPath = (Join-Path $script:Run merged.json); AgentId = 'generator'; StageId = 'generation'; RunId = 'run' }
        $result = & (Join-Path $script:Root scripts/Merge-ChangeSetBatches.ps1) @mergeArgs
        $result.changeCount | Should -Be 3
        $mergeArgs.ExpectedPaths += 'automation/missing.ts'
        { & (Join-Path $script:Root scripts/Merge-ChangeSetBatches.ps1) @mergeArgs } | Should -Throw '*missing*'
        $mergeArgs.RegeneratedPaths = @('automation/a.ts')
        { & (Join-Path $script:Root scripts/Merge-ChangeSetBatches.ps1) @mergeArgs } | Should -Throw '*CarryAll*'
    }

    It 'does not reuse artifacts when source or contracts changed' -ForEach @('source','contracts') {
        $inputs = Get-Content (Join-Path $script:Run run-inputs.json) -Raw | ConvertFrom-Json
        $inputs.hashes.$_ = 'changed'
        $null = Save-Record $script:Run run-inputs.json $inputs
        Get-Seed | Should -BeNullOrEmpty
    }

    It 'rejects modified archived evidence' -ForEach @('generation/change-set-plan.json','implementation/framework-implementation.json','generation/batch-basis.json') {
        Add-Content (Join-Path $script:Archive $_) ' '
        Get-Seed | Should -BeNullOrEmpty
    }

    It 'does not follow artifact paths outside the recovery archive' {
        $script:State.stages[1].attempts[0].artifacts[0].relativePath = '../../../outside.json'
        $null = Save-Record $script:Archive workflow-state.json $script:State
        Get-Seed | Should -BeNullOrEmpty
    }

    It 'supplies verification evidence and requires real local checks on a planning restart' {
        $path = New-QaFoundryRecoveryContext -RunRoot $script:Run -RunId run -StageId implementation -OutputPath (Join-Path $script:Run recovery-context.md)
        $text = Get-Content $path -Raw
        $text | Should -Match 'Exactly one deployed project'
        $text | Should -Match 'Listing tests, empty suites, skipped tests and weakened assertions do not satisfy'
        $text | Should -Match 'unchanged contracts are merged'
        New-QaFoundryRecoveryContext -RunRoot $script:Run -RunId run -StageId generation -OutputPath (Join-Path $script:Run unused.md) | Should -BeNullOrEmpty
    }
    It 'retains the completed verification diagnostics after a supervisor crash and checks original log integrity' {
        $log = Join-Path $script:Archive 'verification/commands/command-001.log'
        New-Item -ItemType Directory (Split-Path $log) -Force | Out-Null
        'Error: CPS_TARGET_ENVIRONMENT is required.' | Set-Content $log
        $hash = (Get-FileHash $log).Hash.ToLowerInvariant()
        $record = Save-Record $script:Archive verification/framework-verification.json @{ projects = @(@{
            projectPath='automation/ui';outcome='toolchain_defect';steps=@(@{
                name='test';status='failed';detail="Original verification failure. Full output: commands/command-001.log [sha256: $hash]"
            })
        }) }
        $script:State.stages[2].attempts[0].artifacts = @($record)
        $script:State.stages[2].attempts += @{iteration=1;status='failed';error='supervisor could not write preflight'}
        $null = Save-Record $script:Archive workflow-state.json $script:State
        $output = Join-Path $script:Run recovery-context.md
        $null = New-QaFoundryRecoveryContext -RunRoot $script:Run -RunId run -StageId implementation -OutputPath $output
        Get-Content $output -Raw | Should -Match 'Original verification failure'
        Get-Content $output -Raw | Should -Match ([regex]::Escape($log))
        'Changed evidence' | Add-Content $log
        { New-QaFoundryRecoveryContext -RunRoot $script:Run -RunId run -StageId implementation -OutputPath $output } | Should -Throw '*integrity check*'
    }
}
