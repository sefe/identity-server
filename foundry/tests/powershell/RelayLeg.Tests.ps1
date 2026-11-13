Describe "Relay leg" {
    BeforeAll {
        $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
        . (Join-Path $script:Root 'scripts/Common.ps1')
        $script:LegScript = Join-Path $script:Root "scripts/Invoke-RelayLeg.ps1"
        $script:RelayTemplate = Get-Content -LiteralPath (
            Join-Path $script:Root "pipelines/azure-devops/templates/relay-leg.yml"
        ) -Raw
        $script:FirstStartPipeline = Get-Content -LiteralPath (
            Join-Path $script:Root "pipelines/azure-devops/first-start-bootstrap.yml"
        ) -Raw

        function Invoke-Leg {
            param(
                [string]$Stub = "",
                [string]$RunStatus = "",
                [switch]$IsFinalLeg,
                [int]$RunBudgetMinutes = 720,
                [switch]$NoResult,
                [switch]$MissingStatus,
                [string]$SyntheticStatus = "",
                [string]$CurrentStage = "",
                [string]$StageType = "",
                [string]$StageHandler = "",
                [string]$RunName = "run-test",
                [string]$StaleRunName = "",
                [string]$StaleRunStatus = "blocked",
                [object[]]$ExistingIncidents = @()
            )
            $work = Join-Path ([IO.Path]::GetTempPath()) ("relay-leg-" + [Guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path (Join-Path $work ".qa-foundry-artifacts") -Force | Out-Null
            if ($ExistingIncidents.Count -gt 0) {
                Set-Content -LiteralPath (Join-Path $work ".qa-foundry-artifacts/relay-incidents.json") `
                    -Value (ConvertTo-Json -InputObject @($ExistingIncidents) -Depth 20)
            }
            if ($RunStatus) {
                $runDir = Join-Path $work ".qa-foundry-artifacts/$RunName"
                New-Item -ItemType Directory -Path $runDir -Force | Out-Null
                if ($CurrentStage) {
                    $stage = [ordered]@{
                        id = $CurrentStage
                        type = $StageType
                        status = "failed"
                        iteration = 1
                        attempts = @()
                    }
                    if ($StageHandler) { $stage["handler"] = $StageHandler }
                    $state = [ordered]@{
                        runId = $RunName
                        status = $RunStatus
                        currentStage = $CurrentStage
                        stages = @($stage)
                    }
                    Set-Content -LiteralPath (Join-Path $runDir "workflow-state.json") `
                        -Value ($state | ConvertTo-Json -Depth 20)
                }
                else {
                    Set-Content -LiteralPath (Join-Path $runDir "workflow-state.json") `
                        -Value ('{"status":"' + $RunStatus + '"}') -NoNewline
                }
            }
            # Written after the run above, so its file time is the newer one.
            # That is what a downloaded artifact looks like: the order the files
            # were unpacked in, which has nothing to do with the order the runs
            # happened in.
            if ($StaleRunName) {
                # Ownership is explicit; neither directory timestamp nor its name chooses a run.
                @{ runId = $RunName } | ConvertTo-Json |
                    Set-Content -LiteralPath (Join-Path $work '.qa-foundry-artifacts/active-run.json')
                $staleDir = Join-Path $work ".qa-foundry-artifacts/$StaleRunName"
                New-Item -ItemType Directory -Path $staleDir -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $staleDir "workflow-state.json") `
                    -Value ('{"status":"' + $StaleRunStatus + '"}') -NoNewline
            }
            $bootstrapScript = if ($NoResult -or $MissingStatus -or $SyntheticStatus) {
                $body = if ($NoResult) {
                    'return $null'
                }
                elseif ($MissingStatus) {
                    'return [pscustomobject]@{ message = "finished without a status" }'
                }
                else {
                    $escapedStatus = $SyntheticStatus.Replace("'", "''")
                    "return [pscustomobject]@{ status = '$escapedStatus' }"
                }
                $generatedStub = Join-Path $work "generated-bootstrap.ps1"
                $stubSource = @'
param(
    [string]$ConfigPath,
    [string]$Phase,
    [string]$ResumeRunRoot,
    [int]$BudgetMinutes
)
'@ + [Environment]::NewLine + $body
                Set-Content -LiteralPath $generatedStub -Value $stubSource -NoNewline
                $generatedStub
            }
            else {
                if ([string]::IsNullOrWhiteSpace($Stub)) {
                    throw "A fixture stub or synthetic result is required."
                }
                Join-Path $script:Root "tests/fixtures/$Stub"
            }
            $incidents = @()
            Push-Location $work
            try {
                $output = & pwsh -NoProfile -ExecutionPolicy Bypass -File $script:LegScript `
                    -LegIndex 3 `
                    -BootstrapConfigPath "config.json" `
                    -Phase "bootstrap" `
                    -BudgetMinutes 5 `
                    -RunBudgetMinutes $RunBudgetMinutes `
                    -IsFinalLeg:$IsFinalLeg.IsPresent `
                    -BootstrapScript $bootstrapScript 2>&1
                $code = $LASTEXITCODE
                $incidentPath = Join-Path $work ".qa-foundry-artifacts/relay-incidents.json"
                if (Test-Path -LiteralPath $incidentPath) {
                    $incidents = @(Get-Content -LiteralPath $incidentPath -Raw | ConvertFrom-Json -Depth 20)
                }
                $continuationPath = Join-Path $work '.qa-foundry-artifacts/relay-continuation.json'
                $continuation = if (Test-Path -LiteralPath $continuationPath) { Get-Content $continuationPath -Raw | ConvertFrom-Json -Depth 10 } else { $null }
            }
            finally {
                Pop-Location
                Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
            }
            $text = ($output | Out-String)
            $relay = ""
            $match = [regex]::Match($text, 'relayStatus;isOutput=true\]([^\r\n]*)')
            if ($match.Success) { $relay = $match.Groups[1].Value.Trim() }
            return [pscustomobject]@{
                ExitCode    = $code
                RelayStatus = $relay
                Output      = $text
                Continuation = $continuation
                Incidents   = $incidents
            }
        }
    }

    Context "when the leg spends its budget cleanly" {
        It "reports paused so the next leg continues the same run" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-paused.ps1" -RunStatus "in_progress"
            $leg.RelayStatus | Should -Be "paused"
        }

        It "continues its own run rather than the newest file on the agent" {
            # A self-hosted agent keeps its working directory, and a pipeline
            # artifact carries no modification times, so an older run from an
            # earlier build can be the newest thing on disk. Build 973304's leg
            # 4 continued one and crashed on an artifact that run had already
            # written. A run id starts with its own timestamp, so the name says
            # which run is the later one wherever it is read.
            $leg = Invoke-Leg -Stub "relay-bootstrap-paused.ps1" -RunStatus "in_progress" `
                -RunName "run-20260912T031434027Z-10f1387e" `
                -StaleRunName "run-20260911T234513345Z-3e08be0d" -StaleRunStatus "blocked"

            $leg.RelayStatus | Should -Be "paused"
            $leg.Output | Should -Match "run-20260912T031434027Z-10f1387e"
            $leg.Output | Should -Not -Match "had already blocked"
        }

        It "stays green even though a rejected agent artifact left a non-zero exit code behind" {
            # Leg 2 of build 455 paused successfully and was still failed by the
            # exit code node left behind when it rejected an agent artifact.
            $leg = Invoke-Leg -Stub "relay-bootstrap-paused.ps1" -RunStatus "in_progress"
            $leg.ExitCode | Should -Be 0
            $leg.Incidents.Count | Should -Be 0
        }
    }

    Context "when bootstrap reports its outcome" {
        It "accepts every documented successful terminal status" {
            foreach ($status in @(
                "awaiting_merge",
                "dry_run",
                "plan_applied",
                "pull_request_created",
                "installed"
            )) {
                $leg = Invoke-Leg -SyntheticStatus $status
                $leg.ExitCode | Should -Be 0
                $leg.RelayStatus | Should -Be $status
                $leg.Incidents.Count | Should -Be 0
            }
        }

        It "fails and records an incident when bootstrap returns no result" {
            $leg = Invoke-Leg -NoResult
            $leg.ExitCode | Should -Be 1
            $leg.RelayStatus | Should -Be "failed"
            $leg.Incidents.Count | Should -Be 1
            $leg.Incidents[0].message | Should -Match "returned no result"
        }

        It "fails and records an incident when the result has no status" {
            $leg = Invoke-Leg -MissingStatus
            $leg.ExitCode | Should -Be 1
            $leg.RelayStatus | Should -Be "failed"
            $leg.Incidents.Count | Should -Be 1
            $leg.Incidents[0].message | Should -Match "does not contain a status"
        }

        It "fails and records an incident for an unknown status" {
            $leg = Invoke-Leg -SyntheticStatus "future_success"
            $leg.ExitCode | Should -Be 1
            $leg.RelayStatus | Should -Be "failed"
            $leg.Incidents.Count | Should -Be 1
            $leg.Incidents[0].message | Should -Match "unknown status 'future_success'"
        }
    }

    Context "when the leg crashes" {
        It "stops the relay rather than carrying the run around the defect" {
            # Build 453 threw on leg 4 and the relay ended with no decision
            # recorded at all, because relayStatus was never set. Stopping is the
            # intended outcome; stopping silently is not.
            $leg = Invoke-Leg -Stub "relay-bootstrap-throws.ps1" -RunStatus "in_progress"
            $leg.RelayStatus | Should -Be "failed"
            $leg.ExitCode | Should -Be 1
        }

        It "records the crash as a defect in the published evidence" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-throws.ps1" -RunStatus "in_progress"
            $leg.Incidents.Count | Should -Be 1
            $leg.Incidents[0].leg | Should -Be 3
            $leg.Incidents[0].message | Should -Match "provider call failed"
            $leg.Incidents[0].recordedAt | Should -Not -BeNullOrEmpty
        }

        It "keeps the crash readable in the log" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-throws.ps1" -RunStatus "in_progress"
            $leg.Output | Should -Match "provider call failed"
        }

        It "says where the run was left so the next fix needs no further run" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-throws.ps1" -RunStatus "in_progress"
            $leg.Output | Should -Match "in_progress"
        }
    }

    Context "when the leg is interrupted by a fault that clears by itself" {
        # Build 474 reached the eleventh stage of eleven and discarded four
        # finished legs because one review call came back 400 while the same
        # profile answered eight other calls in the same run.
        It "hands the run to the next leg instead of discarding the finished ones" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-falters.ps1" -RunStatus "failed" `
                -CurrentStage "bootstrap-change-review" -StageType "parallel_review"
            $leg.RelayStatus | Should -Be "paused"
            $leg.ExitCode | Should -Be 0
            $leg.Output | Should -Match "bootstrap-change-review"
        }

        It "records the interruption as carried rather than hiding it" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-falters.ps1" -RunStatus "failed" `
                -CurrentStage "bootstrap-change-review" -StageType "parallel_review"
            $leg.Incidents.Count | Should -Be 1
            $leg.Incidents[0].recovered | Should -BeTrue
            $leg.Incidents[0].stage | Should -Be "bootstrap-change-review"
            $leg.Incidents[0].runId | Should -Be "run-test"
        }

        It "carries a handler that only reads and can be run again" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-falters.ps1" -RunStatus "failed" `
                -CurrentStage "bootstrap-change-materialization" -StageType "deterministic_action" `
                -StageHandler "materialize_change_set"
            $leg.RelayStatus | Should -Be "paused"
            $leg.ExitCode | Should -Be 0
        }

        It "refuses to replay a handler that has already changed the world" {
            # A POST that filed work items may have succeeded with its answer
            # lost. Running the stage again would file them a second time.
            foreach ($handler in @("create_work_items", "deliver_changes", "apply_change_set")) {
                $leg = Invoke-Leg -Stub "relay-bootstrap-falters.ps1" -RunStatus "failed" `
                    -CurrentStage "delivery" -StageType "deterministic_action" -StageHandler $handler
                $leg.RelayStatus | Should -Be "failed"
                $leg.ExitCode | Should -Be 1
                $leg.Output | Should -Match "outside this repository"
            }
        }

        It "refuses an action that does not say what it does" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-falters.ps1" -RunStatus "failed" `
                -CurrentStage "delivery" -StageType "deterministic_action"
            $leg.RelayStatus | Should -Be "failed"
            $leg.ExitCode | Should -Be 1
        }

        It "still stops for a fault that will not clear on its own" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-throws.ps1" -RunStatus "failed" `
                -CurrentStage "bootstrap-change-review" -StageType "parallel_review"
            $leg.RelayStatus | Should -Be "failed"
            $leg.ExitCode | Should -Be 1
            $leg.Output | Should -Match "not one that clears by itself"
        }

        It "treats a stage carried twice as the defect it evidently is" {
            $prior = @(
                [pscustomobject]@{ leg = 1; recordedAt = "2026-09-01T00:00:00Z"; message = "x"
                    runId = "run-test"; stage = "bootstrap-change-review"; recovered = $true },
                [pscustomobject]@{ leg = 2; recordedAt = "2026-09-01T00:10:00Z"; message = "x"
                    runId = "run-test"; stage = "bootstrap-change-review"; recovered = $true }
            )
            $leg = Invoke-Leg -Stub "relay-bootstrap-falters.ps1" -RunStatus "failed" `
                -CurrentStage "bootstrap-change-review" -StageType "parallel_review" `
                -ExistingIncidents $prior
            $leg.RelayStatus | Should -Be "failed"
            $leg.ExitCode | Should -Be 1
            $leg.Output | Should -Match "already been carried"
        }

        It "counts only the stage that keeps failing, not every incident in the relay" {
            $prior = @(
                [pscustomobject]@{ leg = 1; recordedAt = "2026-09-01T00:00:00Z"; message = "x"
                    runId = "run-test"; stage = "architecture"; recovered = $true },
                [pscustomobject]@{ leg = 2; recordedAt = "2026-09-01T00:10:00Z"; message = "x"
                    runId = "run-test"; stage = "implementation"; recovered = $true }
            )
            $leg = Invoke-Leg -Stub "relay-bootstrap-falters.ps1" -RunStatus "failed" `
                -CurrentStage "bootstrap-change-review" -StageType "parallel_review" `
                -ExistingIncidents $prior
            $leg.RelayStatus | Should -Be "paused"
            $leg.ExitCode | Should -Be 0
        }

        It "carries a recoverable last-leg interruption into the continuation manifest" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-falters.ps1" -RunStatus "failed" `
                -CurrentStage "bootstrap-change-review" -StageType "parallel_review" -IsFinalLeg
            $leg.RelayStatus | Should -Be 'continuation_required'
            $leg.ExitCode | Should -Be 0
            $leg.Output | Should -Match 'Saved recoverable interruption'
        }

        It "refuses to continue a run that had already settled" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-falters.ps1" -RunStatus "completed" `
                -CurrentStage "bootstrap-change-review" -StageType "parallel_review"
            $leg.RelayStatus | Should -Be "failed"
            $leg.ExitCode | Should -Be 1
        }

        It "refuses when the crash happened outside the analysis" {
            # No stage means the wrapper or the delivery failed, and there is
            # nothing on disk that describes what to resume.
            $leg = Invoke-Leg -Stub "relay-bootstrap-falters.ps1" -RunStatus "failed"
            $leg.RelayStatus | Should -Be "failed"
            $leg.ExitCode | Should -Be 1
        }
    }

    Context "when the run cannot be resumed" {
        It "reports a stage's refusal as a stopped run rather than a crash" {
            # A stage that returns 'blocked' has judged the work. Calling that a
            # crash sends whoever reads the log looking for a defect in the runtime
            # instead of reading the blocker the stage recorded.
            $leg = Invoke-Leg -SyntheticStatus "blocked" -RunStatus "running"
            $leg.RelayStatus | Should -Be "blocked"
            $leg.ExitCode | Should -Be 1
            $leg.Output | Should -Not -Match "crashed"
            $leg.Output | Should -Match "ended as 'blocked'"
        }

        It "records no crash incident when a run is deliberately blocked" {
            $leg = Invoke-Leg -SyntheticStatus "blocked" -RunStatus "running"
            @($leg.Incidents).Count | Should -Be 0
        }

        It "carries an already blocked run forward instead of restarting it" {
            # Resuming a run that has already blocked would reopen a decision that
            # was already made, and the resumed run would find its stage finished
            # and crash instead.
            $leg = Invoke-Leg -Stub "relay-bootstrap-throws.ps1" -RunStatus "blocked"
            $leg.RelayStatus | Should -Be "blocked"
            $leg.ExitCode | Should -Be 1
            $leg.Output | Should -Not -Match "crashed"
            @($leg.Incidents).Count | Should -Be 0
        }

        It "stops the relay when the crash left no run on disk" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-throws.ps1"
            $leg.RelayStatus | Should -Be "failed"
            $leg.ExitCode | Should -Be 1
        }
    }

    Context "when the relay runs out of legs" {
        It "marks the final leg as requiring continuation rather than delivery success" {
            $leg = Invoke-Leg -Stub "relay-bootstrap-paused.ps1" -RunStatus "in_progress" -IsFinalLeg
            $leg.ExitCode | Should -Be 0
            $leg.RelayStatus | Should -Be 'continuation_required'
            $leg.Output | Should -Match 'SucceededWithIssues'
            $leg.Output | Should -Match 'relay-continuation.json'
            $leg.Continuation.parameters.resumeRunId | Should -Be 'run-test'
            $leg.Continuation.parameters.restartStage | Should -Be 'none'
            $leg.Continuation.reason | Should -Be 'relay_segment_exhausted'
        }

        It 'refuses bootstrap when the run allowance cannot cover even the handover reserve' {
            $leg = Invoke-Leg -Stub 'relay-bootstrap-throws.ps1' -RunStatus 'paused' -RunBudgetMinutes 1
            $leg.RelayStatus | Should -Be 'blocked'
            $leg.ExitCode | Should -Be 1
            $leg.Output | Should -Not -Match 'crashed'
            $leg.Continuation.reason | Should -Be 'run_time_budget_exhausted'
        }
    }

    Context "pipeline relay boundary" {
        It "starts a new run on an evidence root that holds no other build's work" {
            # The evidence root is not tracked by Git and a self-hosted agent
            # keeps its working directory, so without this a build publishes
            # every run an earlier build left behind - five of them by build
            # 973304 - and a later leg can continue one of those instead of its
            # own.
            $script:RelayTemplate | Should -Match "Prepare isolated relay directories"
            $script:RelayTemplate | Should -Match 'Remove-Item -LiteralPath \$entry.path -Recurse -Force'
            # Only the leg that starts the run clears anything, and it clears
            # before the evidence of a build genuinely being continued arrives.
            $clear = $script:RelayTemplate.IndexOf("Prepare isolated relay directories")
            $restore = $script:RelayTemplate.IndexOf("Restore the evidence of the run being continued")
            $clear | Should -BeGreaterThan 0
            $restore | Should -BeGreaterThan $clear
            $script:RelayTemplate | Should -Match 'Transfer-RelayEvidence.ps1'
        }

        It "passes queue-time paths through environment variables, not inline PowerShell" {
            $script:RelayTemplate | Should -Match `
                'FOUNDRY_FRAMEWORK_PATH_INPUT:\s*\$\{\{\s*parameters\.frameworkPath\s*\}\}'
            $script:RelayTemplate | Should -Match `
                'FOUNDRY_BOOTSTRAP_CONFIG_PATH_INPUT:\s*\$\{\{\s*parameters\.bootstrapConfigPath\s*\}\}'
            $script:RelayTemplate | Should -Match '& \$env:FOUNDRY_RELAY_SCRIPT_PATH'
            $script:RelayTemplate | Should -Match `
                '-BootstrapConfigPath \$env:FOUNDRY_BOOTSTRAP_CONFIG_PATH'
            $script:RelayTemplate | Should -Not -Match `
                '(?m)^\s*&\s*"\$\{\{\s*parameters\.frameworkPath'
            $script:RelayTemplate | Should -Not -Match `
                '-BootstrapConfigPath\s+"\$\{\{\s*parameters\.bootstrapConfigPath'
        }

        It "maps the configured user PAT instead of persisted build-service credentials" {
            $script:RelayTemplate | Should -Match 'persistCredentials:\s*false'
            $script:RelayTemplate | Should -Match (`
                '\$\{\{\s*parameters\.azureDevOpsAuthEnvironment\s*\}\}:\s*' +
                '\$\(\$\{\{\s*parameters\.azureDevOpsAuthEnvironment\s*\}\}\)'
            )
            $script:FirstStartPipeline | Should -Match `
                '(?s)name:\s*azureDevOpsAuthEnvironment.*?default:\s*AZURE_DEVOPS_TOKEN'
            [regex]::Matches(
                $script:FirstStartPipeline,
                'azureDevOpsAuthEnvironment:\s*\$\{\{\s*parameters\.azureDevOpsAuthEnvironment\s*\}\}'
            ).Count | Should -Be 1
            Get-Content (Join-Path $script:Root 'pipelines/azure-devops/templates/relay-chain.yml') -Raw |
                Should -Match 'azureDevOpsAuthEnvironment: \$\{\{ parameters.azureDevOpsAuthEnvironment \}\}'
            $script:RelayTemplate | Should -Not -Match 'System\.AccessToken'
        }

        It "continues only a budget-paused analysis, never a failed delivery" {
            $script:RelayTemplate | Should -Match (`
                "eq\(dependencies\.\$\{\{\s*parameters\.previousLeg\s*\}\}" +
                "\.outputs\['bootstrap\.relayStatus'\],\s*'paused'\)"
            )
            $script:RelayTemplate | Should -Not -Match `
                "relayStatus'.*?(failed|blocked)"
        }

        It "rejects resolved framework and configuration paths outside the checkout" {
            $script:RelayTemplate | Should -Match 'Build\.SourcesDirectory'
            $script:RelayTemplate | Should -Match `
                '\[IO\.Path\]::GetRelativePath\(\$sourceRoot, \$resolved\)'
            $script:RelayTemplate | Should -Match 'must stay inside Build\.SourcesDirectory'
            $script:RelayTemplate | Should -Match 'may not traverse a symbolic link or junction'
        }

        It "makes the last leg the only final relay leg" {
            $chain = Import-QaFoundryYaml -Path (Join-Path $script:Root 'pipelines/azure-devops/templates/relay-chain.yml') -Root $script:Root
            $slots = @($chain.parameters | Where-Object name -EQ slots)[0].default
            foreach ($count in @(1, 12, 24)) {
                $selected = @($slots | Where-Object index -LE $count)
                $selected.Count | Should -Be $count
                $selected[-1].index | Should -Be $count
                for ($i = 1; $i -lt $selected.Count; $i++) {
                    $selected[$i].previous | Should -Be "leg$i"
                }
            }
            Get-Content (Join-Path $script:Root 'pipelines/azure-devops/templates/relay-chain.yml') -Raw |
                Should -Match 'isFinalLeg: \$\{\{ eq\(slot.index, parameters.maxLegCount\) \}\}'
        }

        It "brings the agent to the approved npm before the run resolves anything" {
            # Build 469 reached the resolver for the first time and stopped: the
            # hosted image had moved to npm 10.9.8 while the configured npm
            # ecosystem pins 10.9.4. Reading the pin needs the YAML helper that the
            # Foundry install provides, so the order of these steps is the fix.
            $npmCiIndex = [regex]::Match($script:RelayTemplate, '(?m)^\s*- script: npm ci').Index
            $readIndex = [regex]::Match($script:RelayTemplate, 'Get-EcosystemRuntimeVersion\.ps1').Index
            $installIndex = [regex]::Match(
                $script:RelayTemplate, 'npm install --global "npm@\$APPROVED_NPM_VERSION"').Index
            $runIndex = [regex]::Match($script:RelayTemplate, 'displayName: Run bootstrap leg').Index
            foreach ($index in @($npmCiIndex, $readIndex, $installIndex, $runIndex)) {
                $index | Should -BeGreaterThan 0
            }
            $readIndex | Should -BeGreaterThan $npmCiIndex
            $installIndex | Should -BeGreaterThan $readIndex
            $runIndex | Should -BeGreaterThan $installIndex
            # One script now serves every ecosystem, so the leg has to say which
            # pin it is asking for. Asking for the wrong one would install a
            # version nobody configured and report it as the approved one.
            $script:RelayTemplate | Should -Match '-Ecosystem "npm" -RuntimeKey "npm_version"'
        }

        It "keeps the approved npm version out of the pipeline itself" {
            # A pin kept in two places is a pin that eventually disagrees.
            $script:RelayTemplate | Should -Not -Match 'npm@[0-9]'
            $script:RelayTemplate | Should -Match `
                'ACTUAL_NPM_VERSION" != "\$APPROVED_NPM_VERSION'
        }
    }
}
