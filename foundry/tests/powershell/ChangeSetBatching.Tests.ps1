Describe "Change set batching" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        $script:Splitter = Join-Path $script:Root "scripts/New-ChangeSetBatches.ps1"
        $script:Merger = Join-Path $script:Root "scripts/Merge-ChangeSetBatches.ps1"

        function New-Inventory {
            param(
                [Parameter(Mandatory)][string]$Path,
                [AllowEmptyCollection()][object[]]$Files = @()
            )
            $inventory = [ordered]@{
                agentId = "framework-implementation"
                stageId = "implementation"
                runId = "run-test"
                status = "completed"
                summary = "Inventory for tests."
                evidence = @()
                assumptions = @()
                unknowns = @()
                warnings = @()
                details = @{}
                plannedFiles = @($Files)
            }
            $inventory | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding utf8
            return $Path
        }

        function New-PlannedFile {
            param(
                [Parameter(Mandatory)][string]$FilePath,
                [string]$Contract = "A short contract.",
                [string]$Operation = "create"
            )
            return [ordered]@{
                path = $FilePath
                operation = $Operation
                purpose = "Test file."
                contentContract = $Contract
                dependsOn = @()
            }
        }

        function New-Batch {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][string]$BatchId,
                [AllowEmptyCollection()][string[]]$Paths = @(),
                [string]$Status = "completed",
                [string]$Outcome = "proposed"
            )
            $batch = [ordered]@{
                agentId = "bootstrap-change-generator"
                stageId = "bootstrap-change-generation"
                runId = "run-test"
                status = $Status
                summary = "Batch $BatchId."
                evidence = @()
                assumptions = @()
                unknowns = @()
                warnings = @()
                details = @{}
                outcome = $Outcome
                batchId = $BatchId
                changes = @($Paths | ForEach-Object {
                    [ordered]@{
                        operation = "create"
                        path = $_
                        expectedSha256 = ""
                        content = "content of $_"
                        reason = "Because the inventory says so."
                        sourceRefs = @("framework-implementation.json")
                    }
                })
            }
            $batch | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $Path -Encoding utf8
            return $Path
        }

        function Invoke-Merge {
            param(
                [Parameter(Mandatory)][string[]]$BatchPaths,
                [Parameter(Mandatory)][string[]]$ExpectedPaths,
                [Parameter(Mandatory)][string]$OutputPath,
                [string]$MaterializationPath = ""
            )
            return & $script:Merger `
                -BatchPaths $BatchPaths `
                -ExpectedPaths $ExpectedPaths `
                -OutputPath $OutputPath `
                -AgentId "bootstrap-change-generator" `
                -StageId "bootstrap-change-generation" `
                -RunId "run-test" `
                -MaterializationPath $MaterializationPath
        }
    }

    Context "when the approved inventory is cut into assignments" {
        It "gives every approved file to exactly one batch" {
            # The whole design rests on this: a file assigned twice is written
            # twice and a file assigned to nobody is silently missing from the
            # delivered framework.
            $paths = 1..17 | ForEach-Object { "automation/lib/file-$_.ts" }
            $inventory = New-Inventory -Path (Join-Path $TestDrive "inventory.json") `
                -Files @($paths | ForEach-Object { New-PlannedFile -FilePath $_ })
            $split = & $script:Splitter -InventoryPaths @($inventory)
            $assigned = @($split.batches | ForEach-Object { $_.files } | ForEach-Object { $_.path })
            $assigned.Count | Should -Be 17
            @($assigned | Sort-Object -Unique).Count | Should -Be 17
            foreach ($path in $paths) { $assigned | Should -Contain $path }
        }

        It "keeps a batch inside the file count it was given" {
            $inventory = New-Inventory -Path (Join-Path $TestDrive "count.json") `
                -Files @(1..13 | ForEach-Object { New-PlannedFile -FilePath "automation/f$_.ts" })
            $split = & $script:Splitter -InventoryPaths @($inventory) -MaxFilesPerBatch 4
            @($split.batches).Count | Should -Be 4
            foreach ($batch in $split.batches) {
                @($batch.files).Count | Should -BeLessOrEqual 4
            }
        }

        It "splits on the size estimate as well as the count" {
            # A handful of very large files is the case that produced 170 wasted
            # minutes, so the count limit alone is not enough.
            $long = "x" * 6000
            $inventory = New-Inventory -Path (Join-Path $TestDrive "size.json") `
                -Files @(1..6 | ForEach-Object {
                    New-PlannedFile -FilePath "automation/big-$_.ts" -Contract $long
                })
            $split = & $script:Splitter -InventoryPaths @($inventory) `
                -TargetBatchBytes 36864 -MaxFilesPerBatch 6
            @($split.batches).Count | Should -BeGreaterThan 1
        }

        It "never leaves a file unassigned just because it is bigger than the budget" {
            $huge = "x" * 40000
            $inventory = New-Inventory -Path (Join-Path $TestDrive "huge.json") `
                -Files @(
                    (New-PlannedFile -FilePath "automation/huge.ts" -Contract $huge),
                    (New-PlannedFile -FilePath "automation/small.ts")
                )
            $split = & $script:Splitter -InventoryPaths @($inventory) -TargetBatchBytes 8192
            $assigned = @($split.batches | ForEach-Object { $_.files } | ForEach-Object { $_.path })
            $assigned | Should -Contain "automation/huge.ts"
            $assigned | Should -Contain "automation/small.ts"
        }

        It "carries one entry per file when two inventories name the same path identically" {
            # The framework and test inventories are separate documents and may
            # legitimately overlap. Emitting the path twice would make the merge
            # reject a plan that is in fact correct.
            $first = New-Inventory -Path (Join-Path $TestDrive "first.json") `
                -Files @(New-PlannedFile -FilePath "automation/shared.ts" -Contract "The same.")
            $second = New-Inventory -Path (Join-Path $TestDrive "second.json") `
                -Files @(New-PlannedFile -FilePath "automation/shared.ts" -Contract "The same.")
            $split = & $script:Splitter -InventoryPaths @($first, $second)
            $split.totalFiles | Should -Be 1
            $assigned = @($split.batches | ForEach-Object { $_.files })
            @($assigned).Count | Should -Be 1
            [string]$assigned[0].plannedFile.contentContract | Should -Be "The same."
        }

        It "refuses one path that two inventories specify differently" {
            # The later inventory used to win in silence. The file was then
            # written to one contract while the other inventory, and the review
            # that approved it, expected the other, and nothing downstream ever
            # compared the two.
            $first = New-Inventory -Path (Join-Path $TestDrive "clash-first.json") `
                -Files @(New-PlannedFile -FilePath "automation/shared.ts" -Contract "First.")
            $second = New-Inventory -Path (Join-Path $TestDrive "clash-second.json") `
                -Files @(New-PlannedFile -FilePath "automation/shared.ts" -Contract "Second, and different.")
            { & $script:Splitter -InventoryPaths @($first, $second) } |
                Should -Throw "*automation/shared.ts*do not agree*"
        }

        It "keeps files that live together in the same assignment where it can" {
            $inventory = New-Inventory -Path (Join-Path $TestDrive "grouped.json") -Files @(
                (New-PlannedFile -FilePath "automation/tests/b.spec.ts"),
                (New-PlannedFile -FilePath "automation/lib/a.ts"),
                (New-PlannedFile -FilePath "automation/tests/a.spec.ts"),
                (New-PlannedFile -FilePath "automation/lib/b.ts")
            )
            $split = & $script:Splitter -InventoryPaths @($inventory) -MaxFilesPerBatch 2
            $firstBatch = @($split.batches)[0]
            @($firstBatch.files | ForEach-Object { $_.path }) |
                Should -Be @("automation/lib/a.ts", "automation/lib/b.ts")
        }

        It "refuses an inventory that names nothing rather than producing no batches" {
            $inventory = New-Inventory -Path (Join-Path $TestDrive "empty.json") -Files @()
            { & $script:Splitter -InventoryPaths @($inventory) } |
                Should -Throw "*names no files*"
        }

        It "leaves a lock file to the resolver instead of assigning it to a batch" {
            # Build 478 reached this stage and then stopped on it. The inventory
            # named automation/package-lock.json, the splitter handed it to a
            # batch, and the generator could not author it without breaking the
            # change-item contract, so it refused the batch and the run ended
            # blocked at stage 9 of 11.
            $inventory = New-Inventory -Path (Join-Path $TestDrive "lock.json") -Files @(
                (New-PlannedFile -FilePath "automation/package.json"),
                (New-PlannedFile -FilePath "automation/package-lock.json"),
                (New-PlannedFile -FilePath "automation/tests/a.spec.ts")
            )
            $split = & $script:Splitter -InventoryPaths @($inventory)
            $assigned = @($split.batches | ForEach-Object { $_.files } | ForEach-Object { $_.path })
            $assigned | Should -Not -Contain "automation/package-lock.json"
            $assigned | Should -Contain "automation/package.json"
            $split.paths | Should -Not -Contain "automation/package-lock.json"
            $split.totalFiles | Should -Be 2
        }

        It "names the withheld lock file rather than dropping it silently" {
            $inventory = New-Inventory -Path (Join-Path $TestDrive "lock-named.json") -Files @(
                (New-PlannedFile -FilePath "automation/package.json"),
                (New-PlannedFile -FilePath "automation/package-lock.json")
            )
            $split = & $script:Splitter -InventoryPaths @($inventory)
            @($split.resolverOwnedPaths) | Should -Be @("automation/package-lock.json")
        }

        It "withholds a lock file the inventory wrote with a backslash" {
            # Path scoping normalises separators later, so a lock file spelled
            # the other way would otherwise slip past the filter and reach a
            # batch exactly as the unescaped one did.
            $inventory = New-Inventory -Path (Join-Path $TestDrive "lock-backslash.json") -Files @(
                (New-PlannedFile -FilePath "automation\package.json"),
                (New-PlannedFile -FilePath "automation\package-lock.json")
            )
            $split = & $script:Splitter -InventoryPaths @($inventory)
            @($split.resolverOwnedPaths) | Should -Be @("automation/package-lock.json")
            $split.paths | Should -Be @("automation/package.json")
        }

        It "refuses an inventory of nothing but resolver-owned files" {
            $inventory = New-Inventory -Path (Join-Path $TestDrive "lock-only.json") `
                -Files @(New-PlannedFile -FilePath "automation/package-lock.json")
            { & $script:Splitter -InventoryPaths @($inventory) } |
                Should -Throw "*only files a resolver owns*"
        }

        It "withholds exactly the paths the change contract refuses" {
            # Three places decide what a lock file is: the ecosystem adapters,
            # this splitter and the schema every change is validated against. If
            # they drift apart the run either assigns work no batch can deliver,
            # as build 478 did, or silently omits a file that was meant to be
            # authored. The adapters are the source; the other two are checked
            # against them rather than against each other, so an installation
            # that gains an adapter cannot leave either behind.
            . (Join-Path $script:Root "scripts/Common.ps1")
            $expected = Get-QaFoundryResolverOwnedPathPattern
            $schema = Get-Content -LiteralPath (Join-Path $script:Root "schemas/actions/change-item.schema.json") `
                -Raw | ConvertFrom-Json -Depth 40
            [string]$schema.properties.path.not.pattern | Should -Be $expected

            # And the splitter has to act on it, not merely declare it. Every
            # adapter's lock file is offered to the slicer and none of them may
            # reach a batch, while the manifest beside it must.
            $lockNames = @(Get-QaFoundryResolverOwnedLockFileNames)
            $lockNames.Count | Should -BeGreaterThan 1
            $files = @(New-PlannedFile -FilePath "automation/keep.ts") +
                @($lockNames | ForEach-Object { New-PlannedFile -FilePath "automation/$_" })
            $inventory = New-Inventory -Path (Join-Path $TestDrive "every-lock.json") -Files $files
            $split = & $script:Splitter -InventoryPaths @($inventory)
            @($split.paths) | Should -Be @("automation/keep.ts")
            foreach ($name in $lockNames) {
                @($split.resolverOwnedPaths) | Should -Contain "automation/$name" `
                    -Because "$name is a lock file the change contract refuses as literal content"
            }
        }
    }

    Context "when the answered batches are added back together" {
        BeforeEach {
            $script:Expected = @("automation/a.ts", "automation/b.ts", "automation/c.ts")
            $script:PlanPath = Join-Path $TestDrive ("plan-" + [Guid]::NewGuid().ToString("N") + ".json")
        }

        It "produces one plan carrying every approved file" {
            $one = New-Batch -Path (Join-Path $TestDrive "b1.json") -BatchId "batch-01" `
                -Paths @("automation/a.ts", "automation/b.ts")
            $two = New-Batch -Path (Join-Path $TestDrive "b2.json") -BatchId "batch-02" `
                -Paths @("automation/c.ts")
            $result = Invoke-Merge -BatchPaths @($one, $two) -ExpectedPaths $script:Expected `
                -OutputPath $script:PlanPath
            $result.status | Should -Be "completed"
            $result.changeCount | Should -Be 3
            $plan = Get-Content -LiteralPath $script:PlanPath -Raw | ConvertFrom-Json -Depth 40
            @($plan.changes | ForEach-Object { $_.path } | Sort-Object) |
                Should -Be @("automation/a.ts", "automation/b.ts", "automation/c.ts")
            $plan.outcome | Should -Be "proposed"
        }

        It "refuses a plan that is missing an approved file" {
            # This is the failure the single-call design could not have. A batch
            # that quietly drops a file would deliver a framework with a hole in
            # it and report success.
            $one = New-Batch -Path (Join-Path $TestDrive "m1.json") -BatchId "batch-01" `
                -Paths @("automation/a.ts", "automation/b.ts")
            { Invoke-Merge -BatchPaths @($one) -ExpectedPaths $script:Expected `
                -OutputPath $script:PlanPath } |
                Should -Throw "*automation/c.ts*"
            Test-Path -LiteralPath $script:PlanPath | Should -BeFalse
        }

        It "refuses a file nobody approved" {
            $one = New-Batch -Path (Join-Path $TestDrive "u1.json") -BatchId "batch-01" `
                -Paths @("automation/a.ts", "automation/b.ts", "automation/c.ts", "automation/rogue.ts")
            { Invoke-Merge -BatchPaths @($one) -ExpectedPaths $script:Expected `
                -OutputPath $script:PlanPath } |
                Should -Throw "*automation/rogue.ts*"
        }

        It "refuses a file two batches both claim to have written" {
            $one = New-Batch -Path (Join-Path $TestDrive "d1.json") -BatchId "batch-01" `
                -Paths @("automation/a.ts", "automation/b.ts")
            $two = New-Batch -Path (Join-Path $TestDrive "d2.json") -BatchId "batch-02" `
                -Paths @("automation/b.ts", "automation/c.ts")
            { Invoke-Merge -BatchPaths @($one, $two) -ExpectedPaths $script:Expected `
                -OutputPath $script:PlanPath } |
                Should -Throw "*more than one batch*"
        }

        It "reports a refusing batch as a blocked plan rather than a partial one" {
            $one = New-Batch -Path (Join-Path $TestDrive "r1.json") -BatchId "batch-01" `
                -Paths @("automation/a.ts", "automation/b.ts")
            $two = New-Batch -Path (Join-Path $TestDrive "r2.json") -BatchId "batch-02" `
                -Paths @() -Status "blocked" -Outcome "blocked"
            $result = Invoke-Merge -BatchPaths @($one, $two) -ExpectedPaths $script:Expected `
                -OutputPath $script:PlanPath
            $result.status | Should -Be "blocked"
            $plan = Get-Content -LiteralPath $script:PlanPath -Raw | ConvertFrom-Json -Depth 40
            $plan.status | Should -Be "blocked"
            @($plan.changes).Count | Should -Be 0
            @($plan.details.filesWithoutContent) | Should -Contain "automation/c.ts"
        }

        It "refuses to lock a manifest the change set never wrote" {
            $one = New-Batch -Path (Join-Path $TestDrive "mat1.json") -BatchId "batch-01" `
                -Paths $script:Expected
            $materializationPath = Join-Path $TestDrive "materializations.json"
            [ordered]@{
                agentId = "bootstrap-materialization-planner"
                stageId = "bootstrap-change-generation"
                runId = "run-test"
                status = "completed"
                summary = "One manifest."
                evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
                outcome = "proposed"
                materializations = @(
                    [ordered]@{
                        recipe = "npm-package-lock"
                        toolchainId = "typescript-playwright"
                        projectPaths = @("automation")
                        manifestPath = "automation/package.json"
                        lockPath = "automation/package-lock.json"
                        operation = "create"
                        expectedSha256 = ""
                        reason = "Lock the resolved toolchain."
                        sourceRefs = @("automation-blueprint.json")
                    }
                )
            } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $materializationPath -Encoding utf8
            { Invoke-Merge -BatchPaths @($one) -ExpectedPaths $script:Expected `
                -OutputPath $script:PlanPath -MaterializationPath $materializationPath } |
                Should -Throw "*automation/package.json*"
        }

        It "normalises separators so a Windows-style path is not reported as missing" {
            $one = New-Batch -Path (Join-Path $TestDrive "sep.json") -BatchId "batch-01" `
                -Paths @("automation\a.ts", "automation/b.ts", "automation/c.ts")
            $result = Invoke-Merge -BatchPaths @($one) -ExpectedPaths $script:Expected `
                -OutputPath $script:PlanPath
            $result.changeCount | Should -Be 3
        }
    }
}
