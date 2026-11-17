BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
    . (Join-Path $script:Root "scripts/Common.ps1")
    function New-TestBootstrapAdoConnectionData {
        return [pscustomobject]@{
            authenticatedUser = [pscustomobject]@{
                id = "11111111-2222-3333-4444-555555555555"
                providerDisplayName = "Foundry User"
                properties = [pscustomobject]@{
                    Account = [pscustomobject]@{ '$value' = "foundry.user@example.invalid" }
                }
            }
        }
    }
}

Describe "Azure DevOps bootstrap planning" {
    It "creates a schema-valid deterministic managed change set" {
        $repository = Join-Path $TestDrive "plan-repository"
        $runRoot = Join-Path $TestDrive "plan-artifacts"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $bootstrap = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/bootstrap-config.yaml") `
            -Root $script:Root
        $project = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/sample-project-config.yaml") `
            -Root $script:Root
        $project.project.source_branch = "dev"
        $bootstrap.azure_devops.auth_env = "ADO_USER_PAT"
        $project.ci.azure_devops.auth_env = "ADO_USER_PAT"
        $project.work_tracking.azure_devops.auth_env = "ADO_USER_PAT"
        $project.delivery.azure_devops.auth_env = "ADO_USER_PAT"
        $result = & (Join-Path $script:Root "scripts/New-BootstrapChangeSet.ps1") `
            -BootstrapConfig $bootstrap -ProjectConfig $project `
            -RepositoryRoot $repository -FrameworkRoot $script:Root `
            -RunRoot $runRoot -RunId "bootstrap-test" `
            -ConfigurationHash ("a" * 64)

        $result.changeCount | Should -Be 4
        $changeSet = Get-Content -LiteralPath $result.changeSetPath -Raw |
            ConvertFrom-Json -Depth 100
        @($changeSet.changes.path) | Should -Contain ".foundry/pipelines/sdlc-router.yml"
        @($changeSet.changes.path) | Should -Contain ".foundry/installation-plan.json"
        ($changeSet.changes | Where-Object path -eq ".foundry/pipelines/sdlc-router.yml").content |
            Should -Match "foundry/scripts/ci/AzureDevOps.ps1"
        ($changeSet.changes | Where-Object path -eq ".foundry/pipelines/sdlc-router.yml").content |
            Should -Match "setup-copilot-cli.yml"
        ($changeSet.changes | Where-Object path -eq ".foundry/pipelines/sdlc-router.yml").content |
            Should -Match 'ADO_USER_PAT:\s*\$\(ADO_USER_PAT\)'
        ($changeSet | ConvertTo-Json -Depth 100) | Should -Not -Match "System\.AccessToken"
        ($changeSet | ConvertTo-Json -Depth 100) | Should -Not -Match "test-token"
    }

    It "aims the router at the target branch and keeps it off its own delivery branches" {
        $repository = Join-Path $TestDrive "router-trigger-repository"
        $runRoot = Join-Path $TestDrive "router-trigger-artifacts"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $bootstrap = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/bootstrap-config.yaml") `
            -Root $script:Root
        $project = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/sample-project-config.yaml") `
            -Root $script:Root
        $project.project.source_branch = "dev"
        $result = & (Join-Path $script:Root "scripts/New-BootstrapChangeSet.ps1") `
            -BootstrapConfig $bootstrap -ProjectConfig $project `
            -RepositoryRoot $repository -FrameworkRoot $script:Root `
            -RunRoot $runRoot -RunId "bootstrap-router-trigger" `
            -ConfigurationHash ("d" * 64)

        $changeSet = Get-Content -LiteralPath $result.changeSetPath -Raw |
            ConvertFrom-Json -Depth 100
        $router = ($changeSet.changes | Where-Object path -eq ".foundry/pipelines/sdlc-router.yml").content
        # A router that triggers on every branch reacts to the branches Foundry
        # itself pushes, so each delivery starts another run.
        $router | Should -Not -Match "include: \['\*'\]"
        $router | Should -Match "include:\s*\r?\n\s*- dev"
        $router | Should -Match "exclude:\s*\r?\n\s*- sdlc-foundry/\*"
    }

    It "registers a pipeline the agents authored without taking ownership of it" {
        $repository = Join-Path $TestDrive "agent-pipeline-repository"
        $runRoot = Join-Path $TestDrive "agent-pipeline-artifacts"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $bootstrap = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/bootstrap-config.yaml") `
            -Root $script:Root
        $project = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/sample-project-config.yaml") `
            -Root $script:Root
        $project.project.source_branch = "dev"
        $bootstrap | Add-Member -NotePropertyName "agent_pipelines" -NotePropertyValue ([pscustomobject]@{
            register_from_change_set = $true
            path_prefix = "pipelines"
            name_prefix = "Automation - "
        })
        $agentPlan = Join-Path $TestDrive "agent-pipeline-change-set.json"
        [ordered]@{
            agentId = "bootstrap-change-generator"
            stageId = "bootstrap-change-generation"
            runId = "bootstrap-agent-pipeline"
            status = "completed"
            summary = "Automation pipeline proposal."
            evidence = @([ordered]@{ source = "test"; description = "test" })
            assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"
            changes = @(@{
                operation = "create"; path = "pipelines/automation.yml"
                expectedSha256 = ""
                content = "trigger:`n  branches:`n    include:`n      - dev`nsteps:`n  - script: npm test`n"
                reason = "test"
                sourceRefs = @("test:automation")
            })
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $agentPlan

        $result = & (Join-Path $script:Root "scripts/New-BootstrapChangeSet.ps1") `
            -BootstrapConfig $bootstrap -ProjectConfig $project `
            -RepositoryRoot $repository -FrameworkRoot $script:Root `
            -RunRoot $runRoot -RunId "bootstrap-agent-pipeline" `
            -ConfigurationHash ("e" * 64) -AnalysisChangeSetPath $agentPlan

        $changeSet = Get-Content -LiteralPath $result.changeSetPath -Raw |
            ConvertFrom-Json -Depth 100
        $plan = ($changeSet.changes | Where-Object path -eq ".foundry/installation-plan.json").content |
            ConvertFrom-Json -Depth 100
        $registered = @($plan.pipelines | Where-Object yamlPath -eq "pipelines/automation.yml")
        $registered.Count | Should -Be 1
        $registered[0].name | Should -Be "Automation - automation"
        # Installation is not the moment to run tests against a real environment.
        $registered[0].smoke | Should -BeFalse
        # Registered, not owned: the installer must never rewrite it later.
        @($plan.managedFiles.path) | Should -Not -Contain "pipelines/automation.yml"
    }

    It "refuses an installation whose pull requests would land where no pipeline is watching" {
        $repository = Join-Path $TestDrive "branch-drift-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $bootstrap = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/bootstrap-config.yaml") `
            -Root $script:Root
        $project = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/sample-project-config.yaml") `
            -Root $script:Root
        # The installation is delivered to and watched on 'dev'; delivery would propose into 'main'.
        $project.project.source_branch = "main"

        {
            & (Join-Path $script:Root "scripts/New-BootstrapChangeSet.ps1") `
                -BootstrapConfig $bootstrap -ProjectConfig $project `
                -RepositoryRoot $repository -FrameworkRoot $script:Root `
                -RunRoot (Join-Path $TestDrive "branch-drift-run") -RunId "bootstrap-branch-drift" `
                -ConfigurationHash ("c" * 64)
        } | Should -Throw "*project.source_branch is 'main'*"
    }

    Context "when the agents author the pipelines that run the suites" {        BeforeAll {
            function New-ExecutorChangeSet {
                param([object[]]$Changes)

                $path = Join-Path $TestDrive "executor-change-set-$([guid]::NewGuid().ToString('N')).json"
                [ordered]@{
                    agentId = "bootstrap-change-generator"
                    stageId = "bootstrap-change-generation"
                    runId = "bootstrap-executor"
                    status = "completed"
                    summary = "Executor proposal."
                    evidence = @([ordered]@{ source = "test"; description = "test" })
                    assumptions = @(); unknowns = @(); warnings = @(); details = @{}
                    outcome = "proposed"
                    changes = @($Changes)
                } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path
                return $path
            }

            function Invoke-ExecutorPlan {
                param([string]$ChangeSetPath)

                return & (Join-Path $script:Root "scripts/New-BootstrapChangeSet.ps1") `
                    -BootstrapConfig $script:ExecutorBootstrap -ProjectConfig $script:ExecutorProject `
                    -RepositoryRoot $script:ExecutorRepository -FrameworkRoot $script:Root `
                    -RunRoot $script:ExecutorRunRoot -RunId "bootstrap-executor" `
                    -ConfigurationHash ("f" * 64) -AnalysisChangeSetPath $ChangeSetPath
            }
        }

        BeforeEach {
            $script:ExecutorRepository = Join-Path $TestDrive "executor-repository-$([guid]::NewGuid().ToString('N'))"
            New-Item -ItemType Directory -Path $script:ExecutorRepository -Force | Out-Null
            $script:ExecutorRunRoot = Join-Path $TestDrive "executor-artifacts-$([guid]::NewGuid().ToString('N'))"
            $script:ExecutorBootstrap = Import-QaFoundryYaml `
                -Path (Join-Path $script:Root "tests/fixtures/bootstrap-config.yaml") `
                -Root $script:Root
            $script:ExecutorProject = Import-QaFoundryYaml `
                -Path (Join-Path $script:Root "tests/fixtures/sample-project-config.yaml") `
                -Root $script:Root
            $script:ExecutorProject.project.source_branch = "dev"
            $script:ExecutorBootstrap | Add-Member -NotePropertyName "agent_pipelines" -NotePropertyValue ([pscustomobject]@{
                register_from_change_set = $true
                path_prefix = "pipelines"
                name_prefix = "Automation - "
                require_at_least = 1
            })
            $script:ExecutorBootstrap | Add-Member -NotePropertyName "shared_templates" -NotePropertyValue @(
                [pscustomobject]@{
                    yaml_path = ".foundry/pipelines/steps/report-suite-failure.yml"
                    template_path = "bootstrap/templates/report-suite-failure.yml.template"
                    required_in_agent_pipelines = $true
                }
            )
            $script:WorkingExecutor = @(
                "trigger:"
                "  branches:"
                "    include:"
                "      - dev"
                "steps:"
                "  - template: /.foundry/pipelines/steps/report-suite-failure.yml"
            ) -join "`n"
        }


        It "installs the failure hand-off it expects the executors to include" {
            $result = Invoke-ExecutorPlan -ChangeSetPath (New-ExecutorChangeSet -Changes @(@{
                operation = "create"; path = "pipelines/api.yml"; expectedSha256 = ""
                content = $script:WorkingExecutor; reason = "test"; sourceRefs = @("test:api")
            }))
            $changeSet = Get-Content -LiteralPath $result.changeSetPath -Raw | ConvertFrom-Json -Depth 100
            $step = @($changeSet.changes | Where-Object path -eq ".foundry/pipelines/steps/report-suite-failure.yml")
            $step.Count | Should -Be 1
            # The hand-off names the triage pipeline this installation registers, not one an agent
            # remembered, and it is owned by the installer so it stays in step with the framework.
            $step[0].content | Should -BeLike "*SDLC Foundry - Failed Build Triage*"
            # Exporting the credential is not enough: the writer has to be told which
            # variable holds it and how to send it. Left to its default it looked for
            # AZURE_DEVOPS_TOKEN and always built a Basic header, so an installation
            # that named anything else, or configured a bearer token, handed its
            # failures to nobody - and a failing suite failing silently a second
            # time is the one failure nothing else reports.
            $step[0].content | Should -BeLike "*-TokenEnvironmentName 'AZURE_DEVOPS_TOKEN'*"
            $step[0].content | Should -BeLike "*-AuthScheme 'basic'*"
            $plan = ($changeSet.changes | Where-Object path -eq ".foundry/installation-plan.json").content |
                ConvertFrom-Json -Depth 100
            @($plan.managedFiles.path) | Should -Contain ".foundry/pipelines/steps/report-suite-failure.yml"
            # A step template is included by a pipeline. Registering it would create a pipeline that
            # runs a fragment of one.
            @($plan.pipelines.yamlPath) | Should -Not -Contain ".foundry/pipelines/steps/report-suite-failure.yml"
        }

        It "refuses an installation whose suites nothing would ever run" {
            {
                Invoke-ExecutorPlan -ChangeSetPath (New-ExecutorChangeSet -Changes @(@{
                    operation = "create"; path = "automation/playwright.config.ts"
                    expectedSha256 = ""; content = "export default {};"; reason = "test"
                    sourceRefs = @("test:config")
                }))
            } | Should -Throw "*requires at least 1*"
        }

        It "refuses an executor that watches a branch this installation never delivers to" {
            # The failure this catches is silence: a trigger on the wrong branch never fires, and a
            # suite that never runs is indistinguishable from a suite that always passes.
            $wrongBranch = $script:WorkingExecutor.Replace("      - dev", "      - main")
            {
                Invoke-ExecutorPlan -ChangeSetPath (New-ExecutorChangeSet -Changes @(@{
                    operation = "create"; path = "pipelines/api.yml"; expectedSha256 = ""
                    content = $wrongBranch; reason = "test"; sourceRefs = @("test:api")
                }))
            } | Should -Throw "*but not on 'dev'*"
        }

        # Each of these files passes every substring search the check used to make:
        # the word 'trigger' is there, the target branch is there, and the required
        # template path is there. None of them is automation.
        It "refuses an executor whose continuous integration is switched off" {
            $disabled = @(
                "trigger: none"
                "# This pipeline delivers to dev."
                "steps:"
                "  - template: /.foundry/pipelines/steps/report-suite-failure.yml"
            ) -join "`n"
            {
                Invoke-ExecutorPlan -ChangeSetPath (New-ExecutorChangeSet -Changes @(@{
                    operation = "create"; path = "pipelines/api.yml"; expectedSha256 = ""
                    content = $disabled; reason = "test"; sourceRefs = @("test:api")
                }))
            } | Should -Throw "*trigger: none*"
        }

        It "refuses an executor that names the delivery branch only in a comment" {
            $commentOnly = @(
                "trigger:"
                "  branches:"
                "    include:"
                "      - main # the dev branch is handled elsewhere"
                "steps:"
                "  - template: /.foundry/pipelines/steps/report-suite-failure.yml"
            ) -join "`n"
            {
                Invoke-ExecutorPlan -ChangeSetPath (New-ExecutorChangeSet -Changes @(@{
                    operation = "create"; path = "pipelines/api.yml"; expectedSha256 = ""
                    content = $commentOnly; reason = "test"; sourceRefs = @("test:api")
                }))
            } | Should -Throw "*but not on 'dev'*"
        }

        It "refuses an executor that excludes the delivery branch it triggers on" {
            $excluded = @(
                "trigger:"
                "  branches:"
                "    include:"
                "      - '*'"
                "    exclude:"
                "      - dev"
                "steps:"
                "  - template: /.foundry/pipelines/steps/report-suite-failure.yml"
            ) -join "`n"
            {
                Invoke-ExecutorPlan -ChangeSetPath (New-ExecutorChangeSet -Changes @(@{
                    operation = "create"; path = "pipelines/api.yml"; expectedSha256 = ""
                    content = $excluded; reason = "test"; sourceRefs = @("test:api")
                }))
            } | Should -Throw "*excludes 'dev' from its trigger*"
        }

        It "refuses an executor that names the failure hand-off only in a comment" {
            $mentioned = @(
                "trigger:"
                "  branches:"
                "    include:"
                "      - dev"
                "steps:"
                "  # TODO: add /.foundry/pipelines/steps/report-suite-failure.yml"
                "  - script: npm test"
                "    displayName: Run /.foundry/pipelines/steps/report-suite-failure.yml suite"
            ) -join "`n"
            {
                Invoke-ExecutorPlan -ChangeSetPath (New-ExecutorChangeSet -Changes @(@{
                    operation = "create"; path = "pipelines/api.yml"; expectedSha256 = ""
                    content = $mentioned; reason = "test"; sourceRefs = @("test:api")
                }))
            } | Should -Throw "*as a template*"
        }

        It "refuses an executor that triggers on the delivery branch and then runs nothing" {
            $empty = @(
                "trigger:"
                "  branches:"
                "    include:"
                "      - dev"
                "variables:"
                "  handoff: /.foundry/pipelines/steps/report-suite-failure.yml"
            ) -join "`n"
            {
                Invoke-ExecutorPlan -ChangeSetPath (New-ExecutorChangeSet -Changes @(@{
                    operation = "create"; path = "pipelines/api.yml"; expectedSha256 = ""
                    content = $empty; reason = "test"; sourceRefs = @("test:api")
                }))
            } | Should -Throw "*declares no stages, jobs, steps or extends*"
        }

        It "refuses an executor that is not valid YAML at all" {
            {
                Invoke-ExecutorPlan -ChangeSetPath (New-ExecutorChangeSet -Changes @(@{
                    operation = "create"; path = "pipelines/api.yml"; expectedSha256 = ""
                    content = "trigger: [dev`nsteps: - template: /.foundry/x.yml"
                    reason = "test"; sourceRefs = @("test:api")
                }))
            } | Should -Throw "*not valid YAML*"
        }

        # The ordinary shapes an executor can legitimately take, so that the check
        # refuses broken pipelines rather than unfamiliar ones.
        It "accepts a wildcard trigger, a sequence trigger and a template in a job" {
            $wildcard = @("trigger:", "  branches:", "    include:", "      - 'de*'", "steps:",
                "  - template: .foundry/pipelines/steps/report-suite-failure.yml") -join "`n"
            $sequence = @("trigger:", "  - dev", "steps:",
                "  - template: /.foundry/pipelines/steps/report-suite-failure.yml") -join "`n"
            $inJob = @("trigger:", "  branches:", "    include:", "      - refs/heads/dev", "jobs:",
                "  - job: run", "    steps:",
                "      - template: /.foundry/pipelines/steps/report-suite-failure.yml") -join "`n"
            foreach ($body in @($wildcard, $sequence, $inJob)) {
                $result = Invoke-ExecutorPlan -ChangeSetPath (New-ExecutorChangeSet -Changes @(@{
                    operation = "create"; path = "pipelines/api.yml"; expectedSha256 = ""
                    content = $body; reason = "test"; sourceRefs = @("test:api")
                }))
                $plan = (Get-Content -LiteralPath $result.changeSetPath -Raw |
                    ConvertFrom-Json -Depth 100).changes |
                    Where-Object path -eq ".foundry/installation-plan.json"
                @(($plan.content | ConvertFrom-Json -Depth 100).pipelines.yamlPath) |
                    Should -Contain "pipelines/api.yml"
            }
        }

        It "refuses an executor whose failures would reach nobody" {
            $noHandoff = ($script:WorkingExecutor -split "`n" |
                Where-Object { $_ -notlike "*report-suite-failure*" }) -join "`n"
            {
                Invoke-ExecutorPlan -ChangeSetPath (New-ExecutorChangeSet -Changes @(@{
                    operation = "create"; path = "pipelines/api.yml"; expectedSha256 = ""
                    content = $noHandoff; reason = "test"; sourceRefs = @("test:api")
                }))
            } | Should -Throw "*report-suite-failure*"
        }
    }

    It "rejects project providers that do not use the bootstrap credential setting" {        $repository = Join-Path $TestDrive "credential-plan-repository"
        $runRoot = Join-Path $TestDrive "credential-plan-artifacts"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $bootstrap = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/bootstrap-config.yaml") `
            -Root $script:Root
        $project = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/sample-project-config.yaml") `
            -Root $script:Root
        $project.project.source_branch = "dev"
        $project.delivery.azure_devops.auth_env = "DIFFERENT_ADO_PAT"

        {
            & (Join-Path $script:Root "scripts/New-BootstrapChangeSet.ps1") `
                -BootstrapConfig $bootstrap -ProjectConfig $project `
                -RepositoryRoot $repository -FrameworkRoot $script:Root `
                -RunRoot $runRoot -RunId "bootstrap-credential-mismatch" `
                -ConfigurationHash ("c" * 64)
        } | Should -Throw "*must use the same configured credential environment variable*"
    }

    It "renders an implementation pipeline that treats its parameters as data" {
        # Azure DevOps expands ${{ parameters.x }} into a script body before
        # PowerShell parses it. A value carrying a quote and a statement would
        # therefore run as source, under the identity holding this pipeline's
        # credential - and anyone who may queue the pipeline chooses that value.
        $repository = Join-Path $TestDrive "implement-template-repository"
        $runRoot = Join-Path $TestDrive "implement-template-artifacts"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $bootstrap = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/bootstrap-config.yaml") `
            -Root $script:Root
        $project = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/sample-project-config.yaml") `
            -Root $script:Root
        $project.project.source_branch = "dev"
        $project.work_tracking.azure_devops.organization_url = "https://dev.azure.com/tracking"
        $project.work_tracking.azure_devops.project = "delivery"
        $bootstrap.pipelines = @($bootstrap.pipelines) + @([pscustomobject]@{
            key = "implement-work-item"
            name = "SDLC Foundry - Implement Work Item"
            yaml_path = ".foundry/pipelines/implement-work-item.yml"
            template_path = "bootstrap/templates/implement-work-item.yml.template"
            enabled = $true
            smoke = $false
        })

        $result = & (Join-Path $script:Root "scripts/New-BootstrapChangeSet.ps1") `
            -BootstrapConfig $bootstrap -ProjectConfig $project `
            -RepositoryRoot $repository -FrameworkRoot $script:Root `
            -RunRoot $runRoot -RunId "bootstrap-implement-template" `
            -ConfigurationHash ("d" * 64)
        $changeSet = Get-Content -LiteralPath $result.changeSetPath -Raw |
            ConvertFrom-Json -Depth 100
        $content = ($changeSet.changes |
            Where-Object path -eq ".foundry/pipelines/implement-work-item.yml").content
        $content | Should -Not -BeNullOrEmpty

        $yamlPath = Join-Path $TestDrive "implement-work-item-rendered.yml"
        Set-Content -LiteralPath $yamlPath -Value $content -Encoding utf8
        $pipeline = Import-QaFoundryYaml -Path $yamlPath -Root $script:Root
        @($pipeline.parameters.name) | Should -Contain "workItemId"
        @($pipeline.parameters.name) | Should -Contain "handoffKey"

        foreach ($step in @($pipeline.steps)) {
            if (@(Get-QaFoundryPropertyNames -InputObject $step) -notcontains "pwsh") { continue }
            $body = [string]$step.pwsh
            if (-not $body) { continue }
            # Every parameter reaches the script as an environment variable. One
            # inside a script body is the injection this invariant exists to stop.
            $body | Should -Not -Match '\$\{\{\s*parameters\.'
        }
        # Both values are generated and each has exactly one legal form, so the
        # shape is checked rather than assumed.
        $content | Should -Match "\^\[0-9\]\+\`$"
        $content | Should -Match "\^\[0-9a-f\]\{64\}\`$"

        # Two runs can reach implementation for one item, and which one continues
        # has to be decided by a write Azure DevOps serialises, not by each run
        # comparing build ids it can only see after it has already started.
        $content | Should -Match "sdlc-foundry-implementing-"
        $content | Should -Match '"test"; path = "/rev"'
        # A holder tag names a build, and a build that failed or was cancelled is
        # not implementing anything. Reading the tag alone left the task stranded
        # for good, so the generated pipeline asks Azure DevOps what became of
        # the build before it stands down for it.
        $content | Should -Match "_apis/build/builds/\`$HolderBuildId"
        $content | Should -Match "partiallysucceeded"
        # Work items live in the project that tracks work, not the one that builds.
        $content | Should -Match "https://dev\.azure\.com/tracking"
        $content | Should -Match "'delivery'"
    }

    It "rejects providers that would send one shared credential two different ways" {
        # The generated pipelines are rendered from the bootstrap scheme and the
        # runtime writers read their own. A disagreement does not fail: one side
        # encodes a pipeline access token as a password, Azure DevOps answers a
        # sign-in page with a 200 on it, and the run reads that as a work item
        # that does not exist.
        $repository = Join-Path $TestDrive "scheme-plan-repository"
        $runRoot = Join-Path $TestDrive "scheme-plan-artifacts"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $bootstrap = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/bootstrap-config.yaml") `
            -Root $script:Root
        $project = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/sample-project-config.yaml") `
            -Root $script:Root
        $project.project.source_branch = "dev"
        $project.ci.azure_devops | Add-Member -NotePropertyName auth_scheme `
            -NotePropertyValue "bearer" -Force

        {
            & (Join-Path $script:Root "scripts/New-BootstrapChangeSet.ps1") `
                -BootstrapConfig $bootstrap -ProjectConfig $project `
                -RepositoryRoot $repository -FrameworkRoot $script:Root `
                -RunRoot $runRoot -RunId "bootstrap-scheme-mismatch" `
                -ConfigurationHash ("c" * 64)
        } | Should -Throw "*ci.azure_devops.auth_scheme*"
    }

    It "rejects an agent attempt to overwrite an installer-owned path" {        $repository = Join-Path $TestDrive "reserved-repository"
        $runRoot = Join-Path $TestDrive "reserved-artifacts"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $bootstrap = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/bootstrap-config.yaml") `
            -Root $script:Root
        $project = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/sample-project-config.yaml") `
            -Root $script:Root
        $project.project.source_branch = "dev"
        $agentPlan = Join-Path $TestDrive "agent-change-set.json"
        [ordered]@{
            agentId = "bootstrap-change-generator"
            stageId = "bootstrap-change-generation"
            runId = "bootstrap-reserved"
            status = "completed"
            summary = "Malicious reserved-path proposal."
            evidence = @([ordered]@{ source = "test"; description = "test" })
            assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"
            changes = @(@{
                operation = "create"; path = ".foundry/pipelines/evil.yml"
                expectedSha256 = ""; content = "evil"; reason = "test"
                sourceRefs = @("test:evil")
            })
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $agentPlan
        {
            & (Join-Path $script:Root "scripts/New-BootstrapChangeSet.ps1") `
                -BootstrapConfig $bootstrap -ProjectConfig $project `
                -RepositoryRoot $repository -FrameworkRoot $script:Root `
                -RunRoot $runRoot -RunId "bootstrap-reserved" `
                -ConfigurationHash ("b" * 64) -AnalysisChangeSetPath $agentPlan
        } | Should -Throw "*reserved bootstrap path*"
    }
}

Describe "Reading a pipeline the agents wrote" {
    # The check that decides whether an authored pipeline will ever start walks
    # the parsed document looking for template references. Every .NET object
    # answers a PSObject, arrays included, and an array's properties are Length,
    # Rank and SyncRoot - SyncRoot being the array itself. Walking those as if
    # they were YAML keys costs both things this check exists for.
    function script:Test-AuthoredPipeline {
        param(
            [Parameter(Mandatory)][string]$Yaml,
            [string[]]$RequiredIncludes = @()
        )
        return @(& (Join-Path $script:Root "scripts/Test-AgentPipelineDefinition.ps1") `
            -Path "pipelines/agent/suite.yml" `
            -Content $Yaml `
            -TargetBranch "develop" `
            -RequiredIncludes $RequiredIncludes `
            -FrameworkRoot $script:Root)
    }

    It "reads a pipeline whose jobs carry more than one step" {
        # One step per job survived by accident: the parser hands a single-item
        # sequence back as the item itself, so no array was ever walked.
        $yaml = @"
trigger:
  branches:
    include:
      - develop
stages:
  - stage: Api
    jobs:
      - job: RunApi
        steps:
          - script: dotnet test ./Api
            displayName: Api suite
          - script: dotnet test ./Api --collect coverage
            displayName: Api coverage
  - stage: Ui
    jobs:
      - job: RunUi
        steps:
          - script: npx playwright test
            displayName: Ui suite
          - script: npx playwright show-report
            displayName: Ui report
"@
        $problems = Test-AuthoredPipeline -Yaml $yaml
        # Not a stack overflow, not a hang, and nothing wrong with the pipeline.
        @($problems).Count | Should -Be 0
    }

    It "finds a required template that a step reaches for" {
        # The reference lives inside a sequence. A walk that never enters one
        # reports the include as missing, which is the same silence as a walk
        # that never happens.
        $yaml = @"
trigger:
  branches:
    include:
      - develop
stages:
  - stage: Api
    jobs:
      - job: RunApi
        steps:
          - script: echo preparing
          - template: pipelines/agent/report-suite-failure.yml
            parameters:
              suite: Api
"@
        $problems = Test-AuthoredPipeline -Yaml $yaml `
            -RequiredIncludes @("pipelines/agent/report-suite-failure.yml")
        @($problems).Count | Should -Be 0
    }

    It "still says so when the template a suite needs is only mentioned" {
        $yaml = @"
trigger:
  branches:
    include:
      - develop
stages:
  - stage: Api
    jobs:
      - job: RunApi
        steps:
          - script: echo pipelines/agent/report-suite-failure.yml
          - script: dotnet test ./Api
"@
        $problems = Test-AuthoredPipeline -Yaml $yaml `
            -RequiredIncludes @("pipelines/agent/report-suite-failure.yml")
        @($problems).Count | Should -BeGreaterThan 0
        (@($problems) -join " ") | Should -Match "report-suite-failure"
    }
}

Describe "What Azure DevOps is told about a run" {
    # The one human step in the whole design is approving the pull request. A
    # run that stops without making one has to reach the build as a failure, or
    # the queue reads the green build as work delivered and the approval is
    # skipped over something that does not exist.
    function script:Invoke-CiWrapper {
        param([Parameter(Mandatory)][string]$Status)
        $tree = Join-Path $TestDrive "ci-$Status"
        New-Item -ItemType Directory -Path (Join-Path $tree "scripts/ci") -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:Root "scripts/ci/AzureDevOps.ps1") `
            -Destination (Join-Path $tree "scripts/ci/AzureDevOps.ps1")
        # Stands in for the entry point so the wrapper's own reading of the
        # outcome is what the test exercises, rather than a whole workflow.
        @"
[CmdletBinding()]
param(
    [string]`$ConfigPath = "",
    [string]`$PolicyPath = "",
    [string]`$WorkflowPath = "",
    [string]`$EventType = "",
    [string]`$EventPath = "",
    [string]`$CiBuildId = "",
    [string]`$CiRunId = ""
)
[pscustomobject]@{
    runId = "run-ci-wrapper"
    status = "$Status"
    runRoot = "$($tree -replace '\\', '/')/artifacts"
    resumable = `$false
}
"@ | Set-Content -LiteralPath (Join-Path $tree "scripts/Invoke-Foundry.ps1") -Encoding utf8

        return & (Join-Path $tree "scripts/ci/AzureDevOps.ps1") `
            -ConfigPath (Join-Path $script:Root "config/project.yaml")
    }

    It "fails the build when a stage blocked the run" {
        { Invoke-CiWrapper -Status "blocked" } | Should -Throw "*did not finish*"
    }

    It "says a blocked run made no delivery rather than naming a defect" {
        # The distinction matters to whoever opens the build: this is a judgement
        # the run made, not a crash to debug.
        $message = ""
        try { Invoke-CiWrapper -Status "blocked" } catch { $message = $_.Exception.Message }
        $message | Should -Match "no delivery was made"
        $message | Should -Match "artifacts"
    }

    It "fails the build when the run ran out of time partway through" {
        { Invoke-CiWrapper -Status "paused" } | Should -Throw "*did not finish*"
    }

    It "fails the build when the run left no outcome at all" {
        $tree = Join-Path $TestDrive "ci-silent"
        New-Item -ItemType Directory -Path (Join-Path $tree "scripts/ci") -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:Root "scripts/ci/AzureDevOps.ps1") `
            -Destination (Join-Path $tree "scripts/ci/AzureDevOps.ps1")
        "param([string]`$ConfigPath = '', [string]`$PolicyPath = '', [string]`$WorkflowPath = ''," +
            " [string]`$EventType = '', [string]`$EventPath = '', [string]`$CiBuildId = ''," +
            " [string]`$CiRunId = '')" |
            Set-Content -LiteralPath (Join-Path $tree "scripts/Invoke-Foundry.ps1") -Encoding utf8

        {
            & (Join-Path $tree "scripts/ci/AzureDevOps.ps1") `
                -ConfigPath (Join-Path $script:Root "config/project.yaml")
        } | Should -Throw "*nothing to say whether the work was done*"
    }

    It "passes the build when the run finished" {
        $outcome = Invoke-CiWrapper -Status "completed"
        [string]$outcome.status | Should -Be "completed"
    }
}

Describe "Idempotent Azure DevOps pipeline registration" {
    BeforeEach {
        $script:AdoConfig = [pscustomobject]@{
            organization_url = "https://dev.azure.com/example"
            project = "Product Project"
            repository_id = "11111111-2222-3333-4444-555555555555"
            repository_type = "azureReposGit"
            auth_env = "AZURE_DEVOPS_TOKEN"
            auth_scheme = "basic"
            expected_user_id = ""
            match_build_requester = $true
            pipeline_folder = "\SDLC Foundry"
            dry_run = $false
            queue_smoke_run = $true
        }
        $script:Pipelines = @(
            [pscustomobject]@{
                key = "router"; name = "Foundry Router"; folder = "\SDLC Foundry"
                yamlPath = ".foundry/pipelines/router.yml"; enabled = $true; smoke = $true
            },
            [pscustomobject]@{
                key = "triage"; name = "Foundry Triage"; folder = "\SDLC Foundry"
                yamlPath = ".foundry/pipelines/triage.yml"; enabled = $true; smoke = $false
            }
        )
    }

    It "supports a credential-free dry run" {
        $script:AdoConfig.dry_run = $true
        $result = @(& (Join-Path $script:Root "scripts/writers/Register-AdoPipelines.ps1") `
            -AzureDevOpsConfig $script:AdoConfig -Pipelines $script:Pipelines `
            -TargetBranch dev -ActionEnvironment @{})
        @($result.status | Select-Object -Unique) | Should -Be @("dry_run")
    }

    It "resolves a repository name before <ExpectedStatus> registration" -ForEach @(
        @{ Existing = $false; ExpectedStatus = 'created' },
        @{ Existing = $true; ExpectedStatus = 'reused' }
    ) {
        $script:AdoConfig.repository_id = 'Product & API'
        $script:AdoConfig.queue_smoke_run = $false
        Mock Invoke-RestMethod {
            param($Method, $Uri, $Body)
            if ($Uri -like '*/_apis/connectionData?*') { return New-TestBootstrapAdoConnectionData }
            if ($Uri -like '*/_apis/git/repositories/*') {
                return [pscustomobject]@{ id = '11111111-2222-3333-4444-555555555555' }
            }
            if ($Uri -match '/_apis/build/definitions/101\?') {
                return [pscustomobject]@{ repository = [pscustomobject]@{
                    id = '11111111-2222-3333-4444-555555555555'; defaultBranch = 'refs/heads/dev'
                } }
            }
            if ($Uri -match '/_apis/pipelines/101\?') {
                return [pscustomobject]@{ configuration = [pscustomobject]@{
                    path = '/.foundry/pipelines/router.yml'
                    repository = [pscustomobject]@{ id = '11111111-2222-3333-4444-555555555555' }
                } }
            }
            if ($Method -eq 'Post') { return [pscustomobject]@{ id = 101 } }
            return [pscustomobject]@{ value = @(
                if ($Existing) {
                    [pscustomobject]@{ id = 101; name = 'Foundry Router'; folder = '\SDLC Foundry' }
                }
            ) }
        }
        $result = @(& (Join-Path $script:Root 'scripts/writers/Register-AdoPipelines.ps1') `
            -AzureDevOpsConfig $script:AdoConfig -Pipelines @($script:Pipelines[0]) `
            -TargetBranch dev -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = 'test-token' })
        $result[0].status | Should -Be $ExpectedStatus
        $script:AdoConfig.repository_id | Should -Be 'Product & API'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'Get' -and $Uri -eq 'https://dev.azure.com/example/Product%20Project/_apis/git/repositories/Product%20%26%20API?api-version=7.1'
        }
        $postCount = if ($Existing) { 0 } else { 1 }
        Should -Invoke Invoke-RestMethod -Times $postCount -Exactly -ParameterFilter { $Method -eq 'Post' }
        if (-not $Existing) {
            Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'Post' -and
                ($Body | ConvertFrom-Json).configuration.repository.id -eq '11111111-2222-3333-4444-555555555555'
            }
        }
    }

    It "rejects invalid repository lookup results before writing definitions" -ForEach @(
        @{ Repository = [pscustomobject]@{} },
        @{ Repository = [pscustomobject]@{ id = 'invalid' } },
        @{ Repository = [pscustomobject]@{ id = '00000000-0000-0000-0000-000000000000' } }
    ) {
        $script:AdoConfig.repository_id = 'Product API'
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like '*/_apis/connectionData?*') { return New-TestBootstrapAdoConnectionData }
            return $Repository
        }
        {
            & (Join-Path $script:Root 'scripts/writers/Register-AdoPipelines.ps1') `
                -AzureDevOpsConfig $script:AdoConfig -Pipelines $script:Pipelines `
                -TargetBranch dev -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = 'test-token' }
        } | Should -Throw '*repository GUID*'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly -ParameterFilter { $Method -in @('Post', 'Put') }
    }

    It "retains the server error message when pipeline creation fails" {
        Mock Invoke-RestMethod {
            param($Method, $Uri)
            if ($Uri -like '*/_apis/connectionData?*') { return New-TestBootstrapAdoConnectionData }
            if ($Method -eq 'Get') { return [pscustomobject]@{ value = @() } }
            $failure = [System.Management.Automation.ErrorRecord]::new(
                [System.Exception]::new('400 Bad Request'), 'HttpFailure',
                [System.Management.Automation.ErrorCategory]::InvalidOperation, $null)
            $failure.ErrorDetails = [System.Management.Automation.ErrorDetails]::new(
                '{"message":"The guid specified for parameter repositoryId must not be Guid.Empty."}')
            throw $failure
        }
        {
            & (Join-Path $script:Root 'scripts/writers/Register-AdoPipelines.ps1') `
                -AzureDevOpsConfig $script:AdoConfig -Pipelines $script:Pipelines `
                -TargetBranch dev -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = 'test-token' }
        } | Should -Throw '*pipeline registration failed*repositoryId must not be Guid.Empty*'
    }

    It "creates missing definitions and queues only the configured smoke pipeline" {
        Mock Invoke-RestMethod {
            param($Method, $Uri, $Body)
            if ($Uri -like "*/_apis/connectionData?*") {
                return New-TestBootstrapAdoConnectionData
            }
            if ($Uri -match "/_apis/build/definitions/(\d+)\?") {
                if ($Method -eq "Get") {
                    return [pscustomobject]@{
                        id = [int]$Matches[1]
                        repository = [pscustomobject]@{
                            id = "11111111-2222-3333-4444-555555555555"; defaultBranch = "refs/heads/main"
                        }
                    }
                }
                return ($Body | ConvertFrom-Json)
            }
            if ($Method -eq "Get") { return [pscustomobject]@{ value = @() } }
            if ($Uri -like "*/runs?*") { return [pscustomobject]@{ id = 700 } }
            $request = $Body | ConvertFrom-Json
            return [pscustomobject]@{
                id = if ($request.name -eq "Foundry Router") { 101 } else { 102 }
                name = [string]$request.name
                folder = "\SDLC Foundry"
            }
        }
        $result = @(& (Join-Path $script:Root "scripts/writers/Register-AdoPipelines.ps1") `
            -AzureDevOpsConfig $script:AdoConfig -Pipelines $script:Pipelines `
            -TargetBranch dev -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" })
        @($result.status | Select-Object -Unique) | Should -Be @("created")
        $result[0].runId | Should -Be "700"
        $result[1].runId | Should -Be ""
        # Azure DevOps hands a new pipeline the repository default branch. Left
        # at that, every trigger in the file would watch a branch that does not
        # contain it.
        @($result.defaultBranch | Select-Object -Unique) | Should -Be @("refs/heads/dev")
        Should -Invoke -CommandName Invoke-RestMethod -Times 2 -Exactly -ParameterFilter {
            $Method -eq "Put" -and
            ($Body | ConvertFrom-Json).repository.defaultBranch -eq "refs/heads/dev"
        }
        Should -Invoke -CommandName Invoke-RestMethod -Times 9 -Exactly
    }

    It "reuses existing definitions instead of creating duplicates" {
        $script:AdoConfig.queue_smoke_run = $false
        Mock Invoke-RestMethod {
            param($Method, $Uri)
            if ($Uri -like "*/_apis/connectionData?*") {
                return New-TestBootstrapAdoConnectionData
            }
            if ($Uri -match "/_apis/build/definitions/(\d+)\?") {
                return [pscustomobject]@{
                    id = [int]$Matches[1]
                    repository = [pscustomobject]@{
                        id = "11111111-2222-3333-4444-555555555555"; defaultBranch = "refs/heads/dev"
                    }
                }
            }
            if ($Uri -match "/_apis/pipelines/(\d+)\?") {
                $definitionId = [int]$Matches[1]
                $yaml = if ($definitionId -eq 21) {
                    ".foundry/pipelines/router.yml"
                } else { ".foundry/pipelines/triage.yml" }
                return [pscustomobject]@{
                    id = $definitionId
                    configuration = [pscustomobject]@{
                        type = "yaml"; path = $yaml
                        repository = [pscustomobject]@{ id = "11111111-2222-3333-4444-555555555555" }
                    }
                }
            }
            return [pscustomobject]@{ value = @(
                [pscustomobject]@{ id = 21; name = "Foundry Router"; folder = "\SDLC Foundry" },
                [pscustomobject]@{ id = 22; name = "Foundry Triage"; folder = "\SDLC Foundry" }
            ) }
        }
        $result = @(& (Join-Path $script:Root "scripts/writers/Register-AdoPipelines.ps1") `
            -AzureDevOpsConfig $script:AdoConfig -Pipelines $script:Pipelines `
            -TargetBranch dev -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" })
        @($result.status | Select-Object -Unique) | Should -Be @("reused")
        @($result.pipelineId) | Should -Be @("21", "22")
        # Already pointed at the right branch, so nothing is written back.
        Should -Invoke -CommandName Invoke-RestMethod -Times 6 -Exactly
    }

    It "repoints an existing pipeline that watches the wrong branch" {
        # A pipeline registered by an earlier run, or by hand, can carry the
        # repository default branch while the installation lives on another. It
        # would look registered and correct in every listing and still never run
        # the files this installation wrote.
        $script:AdoConfig.queue_smoke_run = $false
        Mock Invoke-RestMethod {
            param($Method, $Uri, $Body)
            if ($Uri -like "*/_apis/connectionData?*") {
                return New-TestBootstrapAdoConnectionData
            }
            if ($Uri -match "/_apis/build/definitions/(\d+)\?") {
                if ($Method -eq "Get") {
                    return [pscustomobject]@{
                        id = [int]$Matches[1]
                        repository = [pscustomobject]@{
                            id = "11111111-2222-3333-4444-555555555555"; defaultBranch = "refs/heads/main"
                        }
                    }
                }
                return ($Body | ConvertFrom-Json)
            }
            if ($Uri -match "/_apis/pipelines/(\d+)\?") {
                $definitionId = [int]$Matches[1]
                $yaml = if ($definitionId -eq 21) {
                    ".foundry/pipelines/router.yml"
                } else { ".foundry/pipelines/triage.yml" }
                return [pscustomobject]@{
                    id = $definitionId
                    configuration = [pscustomobject]@{
                        type = "yaml"; path = $yaml
                        repository = [pscustomobject]@{ id = "11111111-2222-3333-4444-555555555555" }
                    }
                }
            }
            return [pscustomobject]@{ value = @(
                [pscustomobject]@{ id = 21; name = "Foundry Router"; folder = "\SDLC Foundry" },
                [pscustomobject]@{ id = 22; name = "Foundry Triage"; folder = "\SDLC Foundry" }
            ) }
        }
        $result = @(& (Join-Path $script:Root "scripts/writers/Register-AdoPipelines.ps1") `
            -AzureDevOpsConfig $script:AdoConfig -Pipelines $script:Pipelines `
            -TargetBranch dev -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" })
        @($result.status | Select-Object -Unique) | Should -Be @("reused")
        Should -Invoke -CommandName Invoke-RestMethod -Times 2 -Exactly -ParameterFilter {
            $Method -eq "Put" -and
            ($Body | ConvertFrom-Json).repository.defaultBranch -eq "refs/heads/dev"
        }
    }

    It "refuses a same-named pipeline that runs somebody else's YAML file" {
        $script:AdoConfig.queue_smoke_run = $false
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like "*/_apis/connectionData?*") {
                return New-TestBootstrapAdoConnectionData
            }
            if ($Uri -match "/_apis/pipelines/(\d+)\?") {
                return [pscustomobject]@{
                    id = [int]$Matches[1]
                    configuration = [pscustomobject]@{
                        type = "yaml"; path = "legacy/router.yml"
                        repository = [pscustomobject]@{ id = "11111111-2222-3333-4444-555555555555" }
                    }
                }
            }
            return [pscustomobject]@{ value = @(
                [pscustomobject]@{ id = 21; name = "Foundry Router"; folder = "\SDLC Foundry" }
            ) }
        }
        {
            & (Join-Path $script:Root "scripts/writers/Register-AdoPipelines.ps1") `
                -AzureDevOpsConfig $script:AdoConfig -Pipelines $script:Pipelines `
                -TargetBranch dev -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        } | Should -Throw "*rather than '/.foundry/pipelines/router.yml'*"
    }

    It "refuses a same-named pipeline bound to another repository" {
        $script:AdoConfig.queue_smoke_run = $false
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like "*/_apis/connectionData?*") {
                return New-TestBootstrapAdoConnectionData
            }
            if ($Uri -match "/_apis/pipelines/(\d+)\?") {
                return [pscustomobject]@{
                    id = [int]$Matches[1]
                    configuration = [pscustomobject]@{
                        type = "yaml"; path = ".foundry/pipelines/router.yml"
                        repository = [pscustomobject]@{ id = "another-repository-id" }
                    }
                }
            }
            return [pscustomobject]@{ value = @(
                [pscustomobject]@{ id = 21; name = "Foundry Router"; folder = "\SDLC Foundry" }
            ) }
        }
        {
            & (Join-Path $script:Root "scripts/writers/Register-AdoPipelines.ps1") `
                -AzureDevOpsConfig $script:AdoConfig -Pipelines $script:Pipelines `
                -TargetBranch dev -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        } | Should -Throw "*bound to repository 'another-repository-id'*"
    }

    It "fails before calling Azure DevOps when a live token is absent" {
        Mock Invoke-RestMethod { throw "must not be called" }
        {
            & (Join-Path $script:Root "scripts/writers/Register-AdoPipelines.ps1") `
                -AzureDevOpsConfig $script:AdoConfig -Pipelines $script:Pipelines `
                -TargetBranch dev -ActionEnvironment @{}
        } | Should -Throw "*requires mapped token*"
        Should -Invoke -CommandName Invoke-RestMethod -Times 0 -Exactly
    }

    It "refuses a build-service bearer token for live registration" {
        $script:AdoConfig.auth_scheme = "bearer"
        Mock Invoke-RestMethod { throw "must not be called" }
        {
            & (Join-Path $script:Root "scripts/writers/Register-AdoPipelines.ps1") `
                -AzureDevOpsConfig $script:AdoConfig -Pipelines $script:Pipelines `
                -TargetBranch dev -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "service-token" }
        } | Should -Throw "*Bearer/System.AccessToken credentials act as a build service*"
        Should -Invoke -CommandName Invoke-RestMethod -Times 0 -Exactly
    }
}

Describe "Two-phase first start" {
    It "plans locally, waits off-target, and finalizes as an ADO dry run on target" {
        $repository = Join-Path $TestDrive "two-phase-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $frameworkLink = Join-Path $repository "foundry"
        try {
            New-Item -ItemType SymbolicLink -Path $frameworkLink `
                -Target $script:Root -ErrorAction Stop | Out-Null
        }
        catch {
            New-Item -ItemType Junction -Path $frameworkLink `
                -Target $script:Root -ErrorAction Stop | Out-Null
        }
        & git -C $repository init | Out-Null
        & git -C $repository config user.email "foundry-tests@example.invalid"
        & git -C $repository config user.name "Foundry Tests"
        Set-Content -LiteralPath (Join-Path $repository "README.md") -Value "target"
        & git -C $repository add README.md
        & git -C $repository commit -m baseline | Out-Null
        & git -C $repository branch -M dev

        $project = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/sample-project-config.yaml") `
            -Root $script:Root
        $project.project.source_branch = "dev"
        $project.target.repository_path = "."
        $project.target.documentation_paths = @("README.md")
        $project.target.requirements_paths = @()
        $project.target.architecture_paths = @()
        $project.target.additional_context_paths = @()
        $project.runtime.artifacts_root = ".analysis-artifacts"
        $project.quality.auto_detect = $false
        $project.quality.security.secret_scan = $false
        $project.quality.security.dependency_audit = $false
        $project.secrets.source = "none"
        $project.delivery.dry_run = $false
        $project.delivery.apply_changes = $true
        $project | ConvertTo-Json -Depth 100 |
            Set-Content -LiteralPath (Join-Path $repository "project.json")

        $policy = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "policies/default-policy.yaml") `
            -Root $script:Root
        $policy.delivery.allow_repository_changes = $true
        $policy | ConvertTo-Json -Depth 30 |
            Set-Content -LiteralPath (Join-Path $repository "policy.json")

        $bootstrap = Import-QaFoundryYaml `
            -Path (Join-Path $script:Root "tests/fixtures/bootstrap-config.yaml") `
            -Root $script:Root
        $bootstrap.target.repository_path = "."
        $bootstrap.framework.path = "foundry"
        $bootstrap.framework.project_config_path = "project.json"
        $bootstrap.framework.policy_path = "policy.json"
        $bootstrap.framework.bootstrap_workflow_path = "foundry/workflows/bootstrap-automation.yaml"
        $bootstrap.installation.artifacts_root = ".bootstrap-artifacts"
        $bootstrap.installation.run_analysis = $true
        $bootstrap | ConvertTo-Json -Depth 100 |
            Set-Content -LiteralPath (Join-Path $repository "bootstrap.json")

        $plan = & (Join-Path $script:Root "scripts/Start-FoundryBootstrap.ps1") `
            -ConfigPath (Join-Path $repository "bootstrap.json") `
            -Phase Plan -CurrentRef "refs/heads/dev" -Demo
        $plan.status | Should -Be "plan_applied"
        $plan.analysisRunId | Should -Match "^run-"
        Test-Path (Join-Path $repository ".foundry/installation-plan.json") |
            Should -BeTrue

        $waiting = & (Join-Path $script:Root "scripts/Start-FoundryBootstrap.ps1") `
            -ConfigPath (Join-Path $repository "bootstrap.json") `
            -Phase Auto -CurrentRef "refs/heads/foundry/install"
        $waiting.status | Should -Be "awaiting_merge"

        $final = & (Join-Path $script:Root "scripts/Start-FoundryBootstrap.ps1") `
            -ConfigPath (Join-Path $repository "bootstrap.json") `
            -Phase Auto -CurrentRef "refs/heads/dev"
        $final.phase | Should -Be "finalize"
        $final.status | Should -Be "dry_run"
        @($final.pipelines.status | Select-Object -Unique) | Should -Be @("dry_run")
        @(@($plan.runId, $waiting.runId, $final.runId) | Select-Object -Unique).Count |
            Should -Be 3
        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $final.statePath `
                -SchemaPath (Join-Path $script:Root "schemas/bootstrap/installation-state.schema.json") `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Not -Throw
    }
}
