BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
    . (Join-Path $script:Root "scripts/Common.ps1")
    $script:ConfigPath = Join-Path $script:Root "tests/fixtures/sample-project-config.yaml"
    $script:PolicyPath = Join-Path $script:Root "policies/default-policy.yaml"

    function New-MockExecutionConfig {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $mockProfile = & (Join-Path $script:Root "scripts/Resolve-AiProfile.ps1") `
            -Config $config -ProfileName "mock"
        foreach ($property in @(
            $mockProfile.PSObject.Properties |
                Where-Object { $_.Name -notin @("name", "required_secret_env", "secret_env") }
        )) {
            $config.ai | Add-Member -NotePropertyName $property.Name `
                -NotePropertyValue $property.Value -Force
        }
        return $config
    }

    function New-ExecutionStage {
        return [pscustomobject]@{
            id = "execution"
            type = "sequential"
            agents = @([pscustomobject]@{
                id = "execution"
                prompt = "prompts/execution/execution.md"
                schema = "schemas/execution/execution-plan.schema.json"
                output = "execution-plan.json"
            })
        }
    }

    # Mark the result the run actually recorded, leaving the run id and the
    # commands themselves untouched. Only a reused file can carry the mark:
    # running the commands again regenerates their output from scratch.
    function Set-SentinelExecutionResult {
        param([Parameter(Mandatory)][string]$Path)
        $recorded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
        $recorded.commands[0].standardOutput = "SENTINEL-NOT-RERUN"
        $recorded | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
    }

    function Test-SentinelSurvived {
        param([Parameter(Mandatory)][string]$Path)
        $recorded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
        return @($recorded.commands | Where-Object {
            [string]$_.standardOutput -eq "SENTINEL-NOT-RERUN"
        }).Count -eq 1
    }

    function Invoke-ExecutionStageTwice {
        param(
            [Parameter(Mandatory)][string]$RunRoot,
            [Parameter(Mandatory)][scriptblock]$BetweenCalls,
            [switch]$ReuseOnSecondCall
        )
        $config = New-MockExecutionConfig
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $stage = New-ExecutionStage
        $repositoryRoot = Join-Path $script:Root "tests/fixtures/sample-target"
        $invoke = {
            param([bool]$Reuse)
            & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
                -Stage $stage `
                -Config $config `
                -Policy $policy `
                -RunRoot $RunRoot `
                -RepositoryRoot $repositoryRoot `
                -RunId "run-execution-replay" `
                -ReuseExistingArtifacts:$Reuse
        }
        $null = & $invoke $false
        $resultPath = Join-Path $RunRoot "execution/execution-result.json"
        & $BetweenCalls $resultPath
        $second = & $invoke ([bool]$ReuseOnSecondCall)
        return [pscustomobject]@{
            ResultPath = $resultPath
            Second = $second
        }
    }
}

Describe "Execution evidence status" {
    It "marks aggregate evidence failed when policy rejects a command" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $profile = & (Join-Path $script:Root "scripts/Resolve-AiProfile.ps1") `
            -Config $config -ProfileName "mock"
        foreach ($property in @(
            $profile.PSObject.Properties |
                Where-Object { $_.Name -notin @("name", "required_secret_env", "secret_env") }
        )) {
            $config.ai | Add-Member -NotePropertyName $property.Name `
                -NotePropertyValue $property.Value -Force
        }

        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $policy.commands.allowed_executables = @(
            $policy.commands.allowed_executables | Where-Object { $_ -ne "node" }
        )
        $stage = [pscustomobject]@{
            id = "execution"
            type = "sequential"
            agents = @([pscustomobject]@{
                id = "execution"
                prompt = "prompts/execution/execution.md"
                schema = "schemas/execution/execution-plan.schema.json"
                output = "execution-plan.json"
            })
        }
        $runRoot = Join-Path $TestDrive "run"
        $repositoryRoot = Join-Path $script:Root "tests/fixtures/sample-target"

        $stageResult = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage $stage `
            -Config $config `
            -Policy $policy `
            -RunRoot $runRoot `
            -RepositoryRoot $repositoryRoot `
            -RunId "run-rejected-command"

        $evidencePath = Join-Path $runRoot "execution/execution-result.json"
        $evidence = Get-Content -LiteralPath $evidencePath -Raw |
            ConvertFrom-Json -Depth 100
        $stageResult.Status | Should -Be "completed"
        @($evidence.commands).Count | Should -BeGreaterThan 0
        @($evidence.commands | Where-Object { $_.status -eq "rejected" }).Count |
            Should -Be @($evidence.commands).Count
        $evidence.status | Should -Be "failed"
    }
}

Describe "Execution commands across relay legs" {
    # Build 480 spent legs three, four and five running the same commands and
    # reported success on each of them. The plan was reused in seconds, the
    # commands it named took thirty minutes, and the leg ran out of budget
    # before the failure-analysis agent that was supposed to read the results.
    # Nothing moved forward, and nothing said so.
    It "reuses a recorded result instead of running the commands again" {
        $runRoot = Join-Path $TestDrive "reuse-run"
        $replay = Invoke-ExecutionStageTwice `
            -RunRoot $runRoot `
            -ReuseOnSecondCall `
            -BetweenCalls { param($Path) Set-SentinelExecutionResult -Path $Path }

        Test-SentinelSurvived -Path $replay.ResultPath | Should -BeTrue
        # Reused evidence is still this stage's evidence, so the next stage has
        # to be able to declare it as an input.
        @($replay.Second.Artifacts | Where-Object {
            [string]$_.name -eq "execution-result.json"
        }).Count | Should -Be 1
        $replay.Second.Status | Should -Be "completed"
    }

    It "runs the commands when it was not told to reuse anything" {
        # The agent artifact is immutable, so a leg that is not resuming starts
        # from a clean stage directory. What matters is that a leftover result
        # sitting there does not stop the commands from running.
        $runRoot = Join-Path $TestDrive "fresh-run"
        $replay = Invoke-ExecutionStageTwice `
            -RunRoot $runRoot `
            -BetweenCalls {
                param($Path)
                Remove-Item -LiteralPath (
                    Join-Path (Split-Path $Path -Parent) "execution-plan.json") -Force
                Set-SentinelExecutionResult -Path $Path
            }

        Test-SentinelSurvived -Path $replay.ResultPath | Should -BeFalse
    }

    It "runs the commands again when the recorded result is unusable" {
        # A leg killed mid-write leaves half a document behind. Half a document
        # is not evidence that anything ran.
        $runRoot = Join-Path $TestDrive "truncated-run"
        $replay = Invoke-ExecutionStageTwice `
            -RunRoot $runRoot `
            -ReuseOnSecondCall `
            -BetweenCalls {
                param($Path)
                Set-Content -LiteralPath $Path -Encoding utf8 -Value '{"runId":"run-exec'
            }

        $recovered = Get-Content -LiteralPath $replay.ResultPath -Raw |
            ConvertFrom-Json -Depth 100
        $recovered.stageId | Should -Be "execution"
        @($recovered.commands).Count | Should -BeGreaterThan 0
    }

    It "refuses to reuse a result that does not match the schema" {
        # Valid JSON that is not a valid result is the dangerous case: it parses,
        # so only the schema check stands between it and being taken as evidence.
        $runRoot = Join-Path $TestDrive "offschema-run"
        $replay = Invoke-ExecutionStageTwice `
            -RunRoot $runRoot `
            -ReuseOnSecondCall `
            -BetweenCalls {
                param($Path)
                [ordered]@{
                    runId = "run-off-schema"
                    stageId = "execution"
                    status = "completed"
                    commands = @([ordered]@{ id = "sentinel-not-rerun" })
                } | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
            }

        $recovered = Get-Content -LiteralPath $replay.ResultPath -Raw |
            ConvertFrom-Json -Depth 100
        $recovered.runId | Should -Be "run-execution-replay"
        @($recovered.commands | Where-Object {
            $_.PSObject.Properties.Name -contains "exitCode"
        }).Count | Should -Be @($recovered.commands).Count
    }

    It "refuses to reuse a result recorded by a different run" {
        # Passing the schema only proves the file is a result. A result from
        # somewhere else, reused here, would be a lie told with a straight face.
        $runRoot = Join-Path $TestDrive "foreign-run"
        $replay = Invoke-ExecutionStageTwice `
            -RunRoot $runRoot `
            -ReuseOnSecondCall `
            -BetweenCalls {
                param($Path)
                $recorded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
                $recorded.runId = "run-somebody-else"
                $recorded | ConvertTo-Json -Depth 100 |
                    Set-Content -LiteralPath $Path -Encoding utf8
            }

        $recovered = Get-Content -LiteralPath $replay.ResultPath -Raw |
            ConvertFrom-Json -Depth 100
        $recovered.runId | Should -Be "run-execution-replay"
    }

    It "carries on from the command the previous leg stopped at" {
        # A leg that dies partway through the plan leaves the commands it did
        # finish recorded. Those cost real minutes — build 480 paid for the same
        # thirty of them three times over. Only what is left is run again.
        $runRoot = Join-Path $TestDrive "partial-run"
        $replay = Invoke-ExecutionStageTwice `
            -RunRoot $runRoot `
            -ReuseOnSecondCall `
            -BetweenCalls {
                param($Path)
                $recorded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
                $recorded.commands = @(@($recorded.commands)[0])
                $recorded.commands[0].standardOutput = "SENTINEL-NOT-RERUN"
                $recorded.status = "failed"
                $recorded | ConvertTo-Json -Depth 100 |
                    Set-Content -LiteralPath $Path -Encoding utf8
            }

        $recovered = Get-Content -LiteralPath $replay.ResultPath -Raw |
            ConvertFrom-Json -Depth 100
        $planned = Get-Content -LiteralPath (
            Join-Path (Split-Path $replay.ResultPath -Parent) "execution-plan.json") -Raw |
            ConvertFrom-Json -Depth 100

        # The finished command keeps the result it was recorded with.
        $recovered.commands[0].standardOutput | Should -Be "SENTINEL-NOT-RERUN"
        # And the plan is answered in full, not left half-open.
        @($recovered.commands).Count | Should -Be @($planned.commands).Count
        @($recovered.commands | ForEach-Object { $_.id }) |
            Should -Be @($planned.commands | ForEach-Object { $_.id })
        # The command that never ran is not carrying the sentinel.
        $recovered.commands[1].standardOutput | Should -Not -Be "SENTINEL-NOT-RERUN"
    }

    It "refuses to reuse a result whose finished commands answer a different plan" {
        # Resuming trusts the recorded prefix. That trust only holds while the
        # prefix is the same commands the plan opens with; a result that starts
        # somewhere else is evidence about somewhere else.
        $runRoot = Join-Path $TestDrive "misaligned-run"
        $replay = Invoke-ExecutionStageTwice `
            -RunRoot $runRoot `
            -ReuseOnSecondCall `
            -BetweenCalls {
                param($Path)
                $recorded = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
                $recorded.commands = @(@($recorded.commands)[-1])
                $recorded.commands[0].standardOutput = "SENTINEL-NOT-RERUN"
                $recorded.status = "failed"
                $recorded | ConvertTo-Json -Depth 100 |
                    Set-Content -LiteralPath $Path -Encoding utf8
            }

        Test-SentinelSurvived -Path $replay.ResultPath | Should -BeFalse
    }

    It "refuses to reuse a result when the plan moved the commands elsewhere" {
        # Same ids, same executables, same arguments — and a different working
        # directory, which is a different command in every way that matters.
        # The recorded result says nothing about what happens over there.
        $runRoot = Join-Path $TestDrive "moved-run"
        $config = New-MockExecutionConfig
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $stage = New-ExecutionStage
        $repositoryRoot = Join-Path $script:Root "tests/fixtures/sample-target"
        $null = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage $stage -Config $config -Policy $policy `
            -RunRoot $runRoot -RepositoryRoot $repositoryRoot -RunId "run-execution-moved"

        $resultPath = Join-Path $runRoot "execution/execution-result.json"
        Set-SentinelExecutionResult -Path $resultPath

        $planPath = Join-Path $runRoot "execution/execution-plan.json"
        $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 100
        foreach ($command in @($plan.commands)) { $command.workingDirectory = "automation" }
        $plan | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $planPath -Encoding utf8

        $null = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage $stage -Config $config -Policy $policy `
            -RunRoot $runRoot -RepositoryRoot $repositoryRoot -RunId "run-execution-moved" `
            -ReuseExistingArtifacts

        Test-SentinelSurvived -Path $resultPath | Should -BeFalse
    }

    It "leaves no partial result behind when it writes one" {
        $runRoot = Join-Path $TestDrive "atomic-run"
        $config = New-MockExecutionConfig
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $null = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage (New-ExecutionStage) `
            -Config $config `
            -Policy $policy `
            -RunRoot $runRoot `
            -RepositoryRoot (Join-Path $script:Root "tests/fixtures/sample-target") `
            -RunId "run-execution-atomic"

        @(Get-ChildItem -Path (Join-Path $runRoot "execution") -Filter "*.tmp" -File).Count |
            Should -Be 0
    }
}
