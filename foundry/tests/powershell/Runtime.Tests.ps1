BeforeAll {
    $script:Root = (Resolve-Path (Join-Path $PSScriptRoot "../..")).Path
    . (Join-Path $script:Root "scripts/Common.ps1")
    $script:WorkflowPath = Join-Path $script:Root "workflows/bootstrap-automation.yaml"
    $script:ConfigPath = Join-Path $script:Root "tests/fixtures/sample-project-config.yaml"
    $script:PolicyPath = Join-Path $script:Root "policies/default-policy.yaml"
    $script:AdoUserId = "11111111-2222-3333-4444-555555555555"
    $script:AdoUserName = "Foundry User"
    $script:AdoUserEmail = "foundry.user@example.invalid"

    function New-TestAdoConnectionData {
        param(
            [string]$UserId = "11111111-2222-3333-4444-555555555555",
            [string]$DisplayName = "Foundry User",
            [string]$Email = "foundry.user@example.invalid"
        )
        return [pscustomobject]@{
            authenticatedUser = [pscustomobject]@{
                id = $UserId
                providerDisplayName = $DisplayName
                customDisplayName = $DisplayName
                properties = [pscustomobject]@{
                    Account = [pscustomobject]@{ '$value' = $Email }
                }
            }
        }
    }

    function Set-ResolvedTestAiProfile {
        param(
            [Parameter(Mandatory)][object]$Config,
            [string]$ProfileName = "mock"
        )
        $profile = & (Join-Path $script:Root "scripts/Resolve-AiProfile.ps1") `
            -Config $Config `
            -ProfileName $ProfileName
        foreach ($property in @(
            $profile.PSObject.Properties |
                Where-Object { $_.Name -notin @("name", "required_secret_env", "secret_env") } |
                ForEach-Object { $_.Name }
        )) {
            $Config.ai | Add-Member -NotePropertyName $property `
                -NotePropertyValue $profile.$property -Force
        }
        return $Config
    }

    function New-TestRunConfiguration {
        param(
            [Parameter(Mandatory)][string]$RunRoot,
            [Parameter(Mandatory)][string]$RunId,
            [Parameter(Mandatory)][object]$Config,
            [Parameter(Mandatory)][object]$Workflow,
            [string]$RepositoryRoot = ""
        )
        # Deterministic stages check their work against the run configuration,
        # so a test that drives the workflow directly has to produce the real
        # one. Writing a plausible document here instead is how a test comes to
        # agree with a mistake rather than catch it.
        if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = $script:Root }
        return & (Join-Path $script:Root "scripts/New-RunConfiguration.ps1") `
            -RunRoot $RunRoot -RunId $RunId -Config $Config -Workflow $Workflow `
            -RepositoryRoot $RepositoryRoot
    }
    function script:Get-RawConfig {
        return Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
    }

    # Set-ResolvedTestAiProfile flattens the ai section for the agent tests, which
    # is not what the config schema describes, so config-level checks read the file
    # as a person wrote it.
    function script:Get-TestConfig {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        return Set-ResolvedTestAiProfile -Config $config
    }

    function script:New-BatchingRun {
        param(
            [Parameter(Mandatory)][string]$RunRoot,
            [Parameter(Mandatory)][string]$RunId,
            [int]$FrameworkFileCount = 8,
            [int]$TestFileCount = 5,
            # A test case that imports the module it exercises is the shape the
            # real inventories have, and the only shape that exercises both
            # directions of the dependency graph.
            [switch]$LinkTestsToModules,
            [switch]$IncludeLockFile
        )
        # The batched generation stage takes its work from the inventories the
        # implementation stage approved, named rather than searched for. A test
        # that drives the stage has to leave those inventories and the state
        # record that points at them, or it is testing a different stage.
        New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
        $implementation = Join-Path $RunRoot "implementation"
        New-Item -ItemType Directory -Path $implementation -Force | Out-Null

        $written = @()
        foreach ($entry in @(
            @{ name = "framework-implementation.json"; agent = "framework-implementation"
               prefix = "automation/lib/module"; count = $FrameworkFileCount },
            @{ name = "test-implementation.json"; agent = "test-implementation"
               prefix = "automation/tests/case"; count = $TestFileCount }
        )) {
            $path = Join-Path $implementation ([string]$entry.name)
            $plannedFiles = @(1..([int]$entry.count) | ForEach-Object {
                $index = $_
                [ordered]@{
                    path = "$([string]$entry.prefix)-$('{0:d2}' -f $index).ts"
                    operation = "create"
                    purpose = "Approved by the implementation stage."
                    contentContract = "Export the behaviour the blueprint named."
                    dependsOn = @(
                        if ($LinkTestsToModules -and [string]$entry.agent -eq "test-implementation") {
                            "automation/lib/module-$('{0:d2}' -f $index).ts"
                        }
                    )
                }
            })
            # The real inventories name the lock file, because it does belong in
            # the delivered tree even though a resolver rather than a model
            # produces it.
            if ($IncludeLockFile -and [string]$entry.agent -eq "framework-implementation") {
                $plannedFiles += [ordered]@{
                    path = "automation/package.json"
                    operation = "create"
                    purpose = "Declare the approved dependencies."
                    contentContract = "Name the packages the blueprint approved."
                    dependsOn = @()
                }
                $plannedFiles += [ordered]@{
                    path = "automation/package-lock.json"
                    operation = "create"
                    purpose = "Lock the approved dependency versions."
                    contentContract = "Resolved by the package manager."
                    dependsOn = @()
                }
            }            [ordered]@{
                agentId = [string]$entry.agent
                stageId = "implementation"
                runId = $RunId
                status = "completed"
                summary = "Approved inventory for the batching test."
                evidence = @()
                assumptions = @()
                unknowns = @()
                warnings = @()
                details = @{}
                plannedFiles = @($plannedFiles)
                commandsProposed = @()
            } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $path -Encoding utf8
            $written += [pscustomobject]@{
                name = [string]$entry.name
                relativePath = "implementation/" + [string]$entry.name
                sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }
        # A run that has a lock file to produce has necessarily settled which
        # toolchain produces it, and the materialization planner is given that
        # decision rather than asked to invent one. Leaving it out would test a
        # stage in a state no real run reaches.
        if ($IncludeLockFile) {
            $context = Join-Path $RunRoot "context"
            New-Item -ItemType Directory -Path $context -Force | Out-Null
            [ordered]@{
                runId = $RunId
                stageId = "bootstrap-toolchain-resolution"
                blueprintSha256 = ("b" * 64)
                resolvedAt = [DateTime]::UtcNow.ToString("o")
                toolchains = @(
                    [ordered]@{
                        id = "npm-playwright-test"
                        revision = 1
                        ecosystem = "npm"
                        recipe = "npm-package-lock"
                        language = "typescript"
                        testFramework = "playwright-test"
                        source = [ordered]@{
                            id = "npm-public"
                            registry = "https://registry.npmjs.org/"
                            authentication = "anonymous"
                        }
                        runtime = [ordered]@{ nodeMajor = 22; npmVersion = "10.9.4" }
                        packages = @(
                            [ordered]@{
                                key = "playwright-test"
                                name = "@playwright/test"
                                version = "1.47.0"
                                scope = "dev"
                                requested = "^1.47.0"
                            }
                        )
                        decidedFor = @("automation")
                        sha256 = ("c" * 64)
                    }
                )
            } | ConvertTo-Json -Depth 40 |
                Set-Content -LiteralPath (Join-Path $context "toolchain-lock.json") -Encoding utf8
        }
        return $written
    }

    function script:New-BatchingWorkflowState {
        param(
            [Parameter(Mandatory)][string]$RunRoot,
            [Parameter(Mandatory)][string]$RunId,
            [Parameter(Mandatory)][object]$Workflow,
            [switch]$LinkTestsToModules,
            [switch]$IncludeLockFile
        )
        $artifacts = New-BatchingRun -RunRoot $RunRoot -RunId $RunId `
            -LinkTestsToModules:$LinkTestsToModules -IncludeLockFile:$IncludeLockFile
        $now = [DateTime]::UtcNow.ToString("o")
        [ordered]@{
            workflowName = [string]$Workflow.name
            workflowVersion = [int]$Workflow.version
            runId = $RunId
            status = "running"
            currentStage = "bootstrap-change-generation"
            stageIteration = 1
            startedAt = $now
            updatedAt = $now
            stages = @(
                [ordered]@{
                    id = "implementation"
                    type = "parallel_with_synthesis"
                    status = "completed"
                    iteration = 1
                    attempts = @([ordered]@{
                        iteration = 1
                        status = "completed"
                        artifacts = @($artifacts)
                    })
                },
                [ordered]@{
                    id = "bootstrap-change-generation"
                    type = "batched_agent"
                    status = "pending"
                    iteration = 0
                    attempts = @()
                }
            )
        } | ConvertTo-Json -Depth 40 |
            Set-Content -LiteralPath (Join-Path $RunRoot "workflow-state.json") -Encoding utf8
    }

    function script:New-BatchingResumeWorkflow {
        param([Parameter(Mandatory)][object]$Workflow)

        $stages = @("implementation", "bootstrap-change-generation" | ForEach-Object {
            $stageId = $_
            $stage = @($Workflow.stages | Where-Object id -eq $stageId)[0]
            if ($stage.PSObject.Properties.Name -contains "depends_on") {
                $stage.PSObject.Properties.Remove("depends_on")
            }
            $stage
        })
        $Workflow.stages = $stages
        return $Workflow
    }

    function script:New-NpmStub {
        param(
            [Parameter(Mandatory)][string]$Directory,
            [string]$LockFixturePath = "",
            [int]$ExitCode = 0,
            [string]$EnvDumpPath = "",
            [string]$ArgsDumpPath = "",
            [string]$ManifestDumpPath = "",
            [string]$NpmVersion = "10.9.4",
            [string]$NodeVersion = "v22.11.0",
            # The build agents are Linux, so the POSIX form has to be
            # writable and runnable from a Windows workstation too, or it
            # only ever gets exercised where nobody can see it fail.
            [switch]$ForcePosix
        )
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
        if ($IsWindows -and -not $ForcePosix) {
            $stub = Join-Path $Directory "npm-stub.cmd"
            $body = @(
                "@echo off",
                "if `"%1`"==`"--version`" (",
                "  if `"%QAFOUNDRY_STUB_AS_NODE%`"==`"1`" (echo $NodeVersion) else (echo $NpmVersion)",
                "  exit /b 0",
                ")"
            )
            if ($ArgsDumpPath) { $body += "echo %* > `"$ArgsDumpPath`"" }
            if ($EnvDumpPath) { $body += "set > `"$EnvDumpPath`"" }
            if ($ManifestDumpPath) { $body += "copy /y package.json `"$ManifestDumpPath`" >nul" }
            if ($LockFixturePath) { $body += "copy /y `"$LockFixturePath`" package-lock.json >nul" }
            $body += "exit /b $ExitCode"
            Set-Content -LiteralPath $stub -Value ($body -join "`r`n") -Encoding ascii
        }
        else {
            $stub = Join-Path $Directory "npm-stub"
            $body = @(
                "#!/bin/sh",
                "if [ `"`$1`" = `"--version`" ]; then",
                "  if [ `"`$QAFOUNDRY_STUB_AS_NODE`" = `"1`" ]; then echo '$NodeVersion'; else echo '$NpmVersion'; fi",
                "  exit 0",
                "fi"
            )
            if ($ArgsDumpPath) { $body += "echo `"`$@`" > '$ArgsDumpPath'" }
            if ($EnvDumpPath) { $body += "env > '$EnvDumpPath'" }
            if ($ManifestDumpPath) { $body += "cp package.json '$ManifestDumpPath'" }
            if ($LockFixturePath) { $body += "cp '$LockFixturePath' package-lock.json" }
            $body += "exit $ExitCode"
            Set-Content -LiteralPath $stub -Value ($body -join "`n") -Encoding ascii
            if (-not $IsWindows) { & chmod +x $stub }
        }
        return $stub
    }

    function script:New-NodeStub {
        param(
            [Parameter(Mandatory)][string]$Directory,
            [string]$NodeVersion = "v22.11.0",
            [switch]$ForcePosix
        )
        $stub = New-NpmStub -Directory $Directory -NodeVersion $NodeVersion -ForcePosix:$ForcePosix
        $renamed = Join-Path $Directory ((Split-Path $stub -Leaf) -replace "^npm-", "node-")
        Move-Item -LiteralPath $stub -Destination $renamed -Force
        $content = Get-Content -LiteralPath $renamed -Raw
        $content = $content -replace [regex]::Escape('%QAFOUNDRY_STUB_AS_NODE%'), "1" `
            -replace [regex]::Escape('$QAFOUNDRY_STUB_AS_NODE'), "1"
        Set-Content -LiteralPath $renamed -Value $content -Encoding ascii -NoNewline
        if (-not $IsWindows) { & chmod +x $renamed }
        return $renamed
    }

    # What the resolver is allowed to find published. Asking the real registry
    # would make the suite fail on a network nobody here controls, and it would
    # make "the resolver pinned 1.62.1" an assertion nobody could write.
    function script:New-VersionSource {
        param([hashtable]$Versions = @{})
        $published = @{
            "@playwright/test" = @("1.47.0", "1.61.0", "1.62.0", "1.62.1")
            "typescript"       = @("5.8.3", "5.9.2", "5.9.3")
            "vitest"           = @("2.1.8", "3.0.5")
            "ajv"              = @("8.17.1")
        }
        foreach ($key in @($Versions.Keys)) { $published[[string]$key] = @($Versions[$key]) }
        return {
            param($Registry, $Name)
            if ($published.ContainsKey([string]$Name)) { return @($published[[string]$Name]) }
            return @()
        }.GetNewClosure()
    }

    # The technology argument an architect now has to make for each automation
    # project. Nothing is picked from a list the runtime holds, so a test that
    # wants a second toolchain asks for a different framework or different
    # packages rather than a different profile name.
    function script:New-ToolchainDecision {
        param(
            [string]$Ecosystem = "npm",
            [string]$TestFramework = "@playwright/test",
            [string]$Language = "TypeScript 5.9 (strict, ES2023 target)",
            [string]$RuntimeName = "node",
            [string]$RuntimeVersion = "22",
            [object[]]$Packages = @()
        )
        if ($Packages.Count -eq 0) {
            $Packages = @(
                [ordered]@{
                    name = "@playwright/test"; version = "^1.62.0"; scope = "dev"
                    purpose = "One runner covering the HTTP surface and the browser journeys."
                },
                [ordered]@{
                    name = "typescript"; version = "~5.9.2"; scope = "dev"
                    purpose = "Compile-time contracts over the fixtures the specs share."
                }
            )
        }
        return [ordered]@{
            detectedStack = [ordered]@{
                language = "C#"
                runtime = "net8.0"
                buildSystem = "dotnet"
                packageManager = "nuget"
                existingTestFrameworks = @("MSTest")
                evidence = @("src/Service/Service.csproj", "NuGet.config")
            }
            ecosystem = $Ecosystem
            language = $Language
            runtime = [ordered]@{ name = $RuntimeName; version = $RuntimeVersion }
            testFramework = $TestFramework
            packages = @($Packages)
            coverageFit = @([ordered]@{
                capability = "HTTP and contract coverage of the service under test"
                howItIsMet = "The runner calls the public surface with no browser started."
            })
            alternativesRejected = @([ordered]@{
                option = "A second integration-test project in the product's own ecosystem"
                reason = "It cannot drive the browser half of the documented flows, so it would mean two suites and two toolchains for one set of journeys."
            })
            ciRequirements = @("Node.js 22 LTS on the agent.")
            deviatesFromDetectedStack = $true
            deviationReason = "The flows under test end in the browser, and the product's own ecosystem has no runner that reaches it."
        }
    }

    # Resolved by the real resolver from the real blueprint rather than written
    # out here, because the materialiser refuses a lock whose blueprintSha256
    # does not match the blueprint beside it - and a lock a test wrote by hand
    # would be a shape the pipeline never produces.
    function script:New-ToolchainLock {
        param(
            [Parameter(Mandatory)][string]$BlueprintPath,
            [Parameter(Mandatory)][string]$Path,
            [AllowNull()][scriptblock]$VersionSource = $null
        )
        $blueprint = Get-Content -LiteralPath $BlueprintPath -Raw | ConvertFrom-Json -Depth 100
        if ($null -eq $VersionSource) { $VersionSource = New-VersionSource }
        $result = & (Join-Path $script:Root "scripts/actions/Resolve-ToolchainLock.ps1") `
            -BlueprintPath $BlueprintPath `
            -Config (Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root) `
            -RunId ([string]$blueprint.runId) -StageId "toolchain-resolution" `
            -OutputPath $Path `
            -EvidencePath (Join-Path (Split-Path $Path -Parent) "toolchain-resolution-evidence.json") `
            -VersionSource $VersionSource
        # Several tests below hand the materialiser a blueprint the resolver was
        # always going to refuse, and what those tests are about is what the
        # materialiser does when no lock exists.
        if ([string]$result.status -ne "completed") { return $null }
        return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 30)
    }

    function script:New-ApprovedRunConfiguration {
        param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$RunId)
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $scratch = Join-Path $TestDrive ("approved-run-" + [Guid]::NewGuid().ToString("N"))
        # Written by the runtime's own builder rather than by a literal here, so
        # a test cannot pass against a shape the runtime never produces.
        $produced = & (Join-Path $script:Root "scripts/New-RunConfiguration.ps1") `
            -RunRoot $scratch -RunId $RunId -Config $config `
            -Workflow ([pscustomobject]@{ name = "bootstrap-automation"; version = 2 }) `
            -RepositoryRoot $script:Root `
            -EventContext ([pscustomobject]@{ eventId = "evt-test"; type = "manual"; source = "test" }) `
            -AiProfile ([pscustomobject]@{
                name = "test"; provider = "openai"; model = "test-model"; reasoning_effort = "medium"
            })
        New-Item -ItemType Directory -Path (Split-Path $Path -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $produced -Destination $Path -Force
        # Configuration no longer names a toolchain, so the one a plan is written
        # against is whatever the resolver pinned from the same default blueprint
        # the materialisation helper below builds.
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $scratch "blueprint.json") -RunId $RunId
        $lock = New-ToolchainLock -BlueprintPath $blueprintPath `
            -Path (Join-Path $scratch "toolchain-lock.json")
        return $lock.toolchains[0]
    }

    function script:New-ApprovedLock {
        param(
            [Parameter(Mandatory)][object]$Toolchain,
            [hashtable]$Override = @{}
        )
        $packages = [ordered]@{}
        $rootDependencies = [ordered]@{}
        $rootDevDependencies = [ordered]@{}
        foreach ($package in @($Toolchain.packages)) {
            $name = [string]$package.name
            $version = if ($Override.ContainsKey("version")) { [string]$Override.version } else { [string]$package.version }
            $registry = if ($Override.ContainsKey("registry")) {
                [string]$Override.registry
            } else { [string]$Toolchain.source.registry }
            $entry = [ordered]@{
                version = $version
                resolved = "$($registry.TrimEnd('/'))/$name/-/$($name -replace '^@[^/]+/', '')-$version.tgz"
            }
            if (-not $Override.ContainsKey("dropIntegrity")) {
                $entry.integrity = "sha512-" + ("a" * 86) + "=="
            }
            $packages["node_modules/$name"] = $entry
            if ([string]$package.scope -eq "dev") {
                $rootDevDependencies[$name] = [string]$package.version
            }
            else {
                $rootDependencies[$name] = [string]$package.version
            }
        }
        $root = [ordered]@{}
        if (-not $Override.ContainsKey("dropRootName")) { $root.name = "automation" }
        if (-not $Override.ContainsKey("dropRootVersion")) { $root.version = "0.0.0" }
        if ($rootDependencies.Count -gt 0) { $root.dependencies = $rootDependencies }
        if ($rootDevDependencies.Count -gt 0) { $root.devDependencies = $rootDevDependencies }
        $allPackages = [ordered]@{ "" = $root }
        foreach ($key in $packages.Keys) { $allPackages[$key] = $packages[$key] }
        return ([ordered]@{
            name = "automation"
            version = "0.0.0"
            lockfileVersion = if ($Override.ContainsKey("lockfileVersion")) { $Override.lockfileVersion } else { 3 }
            requires = $true
            packages = $allPackages
        } | ConvertTo-Json -Depth 30)
    }

    function script:New-Plan {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$RunId,
            [Parameter(Mandatory)][object]$Toolchain,
            [hashtable]$ManifestOverride = @{},
            [string[]]$ManifestRemove = @(),
            [string[]]$ProjectPaths = @("automation"),
            [string]$ManifestPath = "automation/package.json",
            [string]$LockPath = "automation/package-lock.json",
            [object[]]$ExtraMaterializations = @(),
            [object[]]$ExtraChanges = @(),
            [switch]$NoMaterializations
        )
        $dependencies = [ordered]@{}
        $devDependencies = [ordered]@{}
        foreach ($package in @($Toolchain.packages)) {
            if ([string]$package.scope -eq "dev") {
                $devDependencies[[string]$package.name] = [string]$package.version
            }
            else {
                $dependencies[[string]$package.name] = [string]$package.version
            }
        }
        $manifest = [ordered]@{ name = "automation"; version = "0.0.0"; private = $true }
        if ($dependencies.Count -gt 0) { $manifest.dependencies = $dependencies }
        if ($devDependencies.Count -gt 0) { $manifest.devDependencies = $devDependencies }
        foreach ($key in $ManifestOverride.Keys) { $manifest[$key] = $ManifestOverride[$key] }
        foreach ($key in @($ManifestRemove)) { $manifest.Remove($key) }
        $materializations = @([ordered]@{
            recipe = "npm-package-lock"
            toolchainId = [string]$Toolchain.id
            projectPaths = @($ProjectPaths)
            manifestPath = $ManifestPath
            lockPath = $LockPath
            operation = "create"
            expectedSha256 = ""
            reason = "Lock the approved toolchain."
            sourceRefs = @("work-item:42")
        }) + $ExtraMaterializations
        if ($NoMaterializations) { $materializations = @() }
        [ordered]@{
            agentId = "bootstrap-change-generator"
            stageId = "bootstrap-change-generation"
            runId = $RunId
            status = "completed"
            summary = "Propose the automation workspace."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"
            changes = @([ordered]@{
                operation = "create"
                path = $ManifestPath
                expectedSha256 = ""
                content = ($manifest | ConvertTo-Json -Depth 20)
                reason = "Declare the approved toolchain."
                sourceRefs = @("work-item:42")
            }) + $ExtraChanges
            materializations = @($materializations)
        } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $Path -Encoding utf8
    }

    # Built from the fixture a real architecture stage produces, so the shape
    # the materialiser reads is the shape the pipeline actually writes.
    function script:New-ApprovedBlueprint {
        param(
            [Parameter(Mandatory)][string]$Path,
            [Parameter(Mandatory)][string]$RunId,
            [object[]]$Projects = @()
        )
        if ($Projects.Count -eq 0) {
            # One argument shared by both projects, which is the ordinary case:
            # the resolver pins it once and both projects are built with it.
            $decision = New-ToolchainDecision
            $Projects = @(
                @{ path = "automation"; decision = $decision },
                @{ path = "automation/tests/ui"; decision = $decision }
            )
        }
        $fixture = Join-Path $script:Root "tests/fixtures/blueprints/bounded-blueprint.json"
        $blueprint = Get-Content -LiteralPath $fixture -Raw | ConvertFrom-Json -Depth 100
        $blueprint.runId = $RunId
        $blueprint.details.automationProjects = @($Projects | ForEach-Object {
            $projectPath = [string]$_.path
            [ordered]@{
                name = "project-" + ($projectPath -replace "[^a-zA-Z0-9]", "-")
                path = $projectPath
                purpose = "Prove the pipeline works end to end."
                toolchain = $_.decision
            }
        })
        $blueprint | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
        return $Path
    }

    function script:Invoke-Materialisation {
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$PlanPath,
            [Parameter(Mandatory)][string]$RunConfigurationPath,
            [Parameter(Mandatory)][string]$RunId,
            [string]$BlueprintPath = "",
            [string]$RunRoot = "",
            [string]$NpmCommand = "npm",
            [string]$NodeCommand = "",
            [AllowNull()][object]$Deadline = $null,
            [switch]$DryRun
        )
        $stageRoot = Join-Path $TestDrive "materialisation-$Name"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        if (-not $NodeCommand) {
            $NodeCommand = New-NodeStub -Directory (Join-Path $stageRoot "node-stub")
        }
        if (-not $BlueprintPath) {
            $BlueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
                -RunId $RunId
        }
        # Resolved from this blueprint and no other. The materialiser compares
        # the lock's blueprintSha256 against the bytes it was handed, so a lock
        # left over from a different blueprint is refused rather than believed.
        $toolchainLockPath = Join-Path $stageRoot "toolchain-lock.json"
        $null = New-ToolchainLock -BlueprintPath $BlueprintPath -Path $toolchainLockPath
        $outputPath = Join-Path $stageRoot "change-set.json"
        $evidencePath = Join-Path $stageRoot "resolver-evidence.json"
        $reviewSubjectPath = Join-Path $stageRoot "change-review-subject.json"
        $result = & (Join-Path $script:Root "scripts/actions/New-MaterializedChangeSet.ps1") `
            -PlanPath $PlanPath -RunConfigurationPath $RunConfigurationPath `
            -BlueprintPath $BlueprintPath -ToolchainLockPath $toolchainLockPath `
            -RunId $RunId -StageId "bootstrap-change-materialization" `
            -OutputPath $outputPath -EvidencePath $evidencePath `
            -ReviewSubjectPath $reviewSubjectPath `
            -RunRoot $RunRoot `
            -WorkRoot (Join-Path $stageRoot "work") -NpmCommand $NpmCommand `
            -NodeCommand $NodeCommand -Deadline $Deadline -DryRun:$DryRun
        return [pscustomobject]@{
            Result = $result
            OutputPath = $outputPath
            EvidencePath = $evidencePath
            ReviewSubjectPath = $reviewSubjectPath
            StageRoot = $stageRoot
            ToolchainLockPath = $toolchainLockPath
            BlueprintPath = $BlueprintPath
        }
    }
}

Describe "Configuration and workflow loading" {
    It "loads the safe demo configuration" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.ai.active_profile | Should -Be "copilot"
        $config.ai.profiles.mock.provider | Should -Be "mock"
        $config.ai.profiles.copilot.model | Should -Be "claude-opus-5"
        $config.ai.profiles.alternate.model | Should -Be "gpt-5.6-sol"
        $config.ai.collaboration.enabled | Should -BeFalse
        $config.delivery.create_branch | Should -BeFalse
        $config.delivery.create_draft_pull_request | Should -BeFalse
    }

    It "accepts configurations created before collaboration pools were introduced" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.ai.PSObject.Properties.Remove("collaboration")
        $path = Join-Path $TestDrive "config-without-collaboration.json"
        $config | ConvertTo-Json -Depth 100 |
            Set-Content -LiteralPath $path -Encoding utf8

        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $path `
                -SchemaPath (Join-Path $script:Root "schemas/config/qa-foundry-config.schema.json") `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Not -Throw
        @(Get-QaFoundryCollaborationProfileNames -Config $config).Count | Should -Be 0
    }

    It "loads stages in deterministic dependency order" {
        $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
        $resolved = & (Join-Path $script:Root "scripts/Resolve-WorkflowStages.ps1") `
            -Workflow $workflow
        @($resolved.id) | Should -Be @(
            "discovery",
            "architecture",
            "toolchain-resolution",
            "test-planning",
            "implementation",
            "execution",
            "review",
            "delivery-preparation",
            "delivery-review",
            "bootstrap-change-generation",
            "bootstrap-change-materialization",
            "framework-verification",
            "bootstrap-change-review"
        )
    }

    It "enforces maximum-assurance independent perspectives" {
        $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
        $workflow.stages = @(
            & (Join-Path $script:Root "scripts/Resolve-WorkflowStages.ps1") `
                -Workflow $workflow
        )
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        {
            & (Join-Path $script:Root "scripts/Test-WorkflowAssurance.ps1") `
                -Workflow $workflow `
                -Config $config
        } | Should -Not -Throw

        $review = @($workflow.stages | Where-Object id -eq "review")[0]
        $review.agents = @($review.agents | Select-Object -First 2)
        {
            & (Join-Path $script:Root "scripts/Test-WorkflowAssurance.ps1") `
                -Workflow $workflow `
                -Config $config
        } | Should -Throw "*at least 3 independent reviewers*"
    }

    It "rejects cyclic stage dependencies" {
        $workflow = [pscustomobject]@{
            stages = @(
                [pscustomobject]@{ id = "one"; depends_on = @("two") },
                [pscustomobject]@{ id = "two"; depends_on = @("one") }
            )
        }
        {
            & (Join-Path $script:Root "scripts/Resolve-WorkflowStages.ps1") `
                -Workflow $workflow
        } | Should -Throw "*dependency cycle*"
    }

    It "validates configuration without starting a run" {
        Push-Location $script:Root
        try {
            $result = & (Join-Path $script:Root "scripts/Invoke-QaFoundry.ps1") `
                -ConfigPath $script:ConfigPath `
                -WorkflowPath $script:WorkflowPath `
                -PolicyPath $script:PolicyPath `
                -ValidateOnly
            $result.valid | Should -BeTrue
            $result.stages | Should -Be 13
            $result.assuranceMode | Should -Be "maximum"
            $result.targetRepository | Should -Be (
                Join-Path $script:Root "tests/fixtures/sample-target"
            )
            $result.aiProfile | Should -Be "copilot"
            $result.analysisInputCount | Should -Be 5
        }
        finally {
            Pop-Location
        }
    }

    It "allows a one-run model override without changing orchestration" {
        Push-Location $script:Root
        try {
            $result = & (Join-Path $script:Root "scripts/Invoke-QaFoundry.ps1") `
                -ConfigPath $script:ConfigPath `
                -Model "provider-specific-model" `
                -ReasoningEffort "provider-specific-high" `
                -ValidateOnly
            $result.model | Should -Be "provider-specific-model"
            $result.reasoningEffort | Should -Be "provider-specific-high"
        }
        finally {
            Pop-Location
        }
    }

    It "routes every supported SDLC event to a maximum-assurance workflow" {
        $expected = @{
            "repository.push" = "change-impact"
            "work_item.ready" = "implement-work-item"
            "schedule.tick" = "requirements-backlog"
            "release.candidate" = "release-readiness"
            "incident.opened" = "incident-response"
            "documentation.changed" = "documentation-update"
            "ci.build.failed" = "failed-build-triage"
        }
        foreach ($entry in $expected.GetEnumerator()) {
            $result = & (Join-Path $script:Root "scripts/Invoke-QaFoundry.ps1") `
                -ConfigPath $script:ConfigPath -PolicyPath $script:PolicyPath `
                -EventType $entry.Key -ValidateOnly
            $result.workflowName | Should -Be $entry.Value
            $result.assuranceMode | Should -Be "maximum"
        }
    }
}

Describe "Multi-model collaboration" {
    BeforeEach {
        $script:CollaborationConfig = Import-QaFoundryYaml `
            -Path $script:ConfigPath `
            -Root $script:Root
        foreach ($entry in @(
            @{ name = "claude"; model = "claude-opus-5" },
            @{ name = "codex"; model = "gpt-5.3-codex" },
            @{ name = "sol"; model = "gpt-5.6-sol" }
        )) {
            $profile = Copy-QaFoundryConfig -Config $script:CollaborationConfig.ai.profiles.mock
            $profile.model = [string]$entry.model
            $script:CollaborationConfig.ai.profiles | Add-Member `
                -NotePropertyName ([string]$entry.name) `
                -NotePropertyValue $profile `
                -Force
        }
        $script:CollaborationConfig.ai.collaboration.enabled = $true
        $script:CollaborationConfig.ai.collaboration.profiles = @("claude", "codex", "sol")
    }

    It "assigns distinct configured models to adjacent agents deterministically" {
        $first = @(0..2 | ForEach-Object {
            Select-QaFoundryAgentProfileName `
                -Config $script:CollaborationConfig `
                -RunId "run-model-pool" `
                -StageId "architecture" `
                -StageIteration 1 `
                -AgentOrdinal $_
        })
        $second = @(0..2 | ForEach-Object {
            Select-QaFoundryAgentProfileName `
                -Config $script:CollaborationConfig `
                -RunId "run-model-pool" `
                -StageId "architecture" `
                -StageIteration 1 `
                -AgentOrdinal $_
        })

        $first | Should -Be $second
        @($first | Select-Object -Unique).Count | Should -Be 3
        @($first | Sort-Object) | Should -Be @("claude", "codex", "sol")
    }

    It "passes each assigned model through a private agent configuration" {
        $config = Set-ResolvedTestAiProfile `
            -Config $script:CollaborationConfig `
            -ProfileName "mock"
        $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $stage = @($workflow.stages | Where-Object id -eq "discovery")[0]
        $repository = Join-Path $TestDrive "collaboration-repository"
        $runRoot = Join-Path $TestDrive "collaboration-run"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

        $result = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage $stage `
            -Config $config `
            -Policy $policy `
            -RunRoot $runRoot `
            -RepositoryRoot $repository `
            -RunId "run-private-model-config" `
            -Iteration 1

        $result.Status | Should -Be "completed"
        $agents = @($stage.agents) + @([pscustomobject]@{
            id = [string]$stage.synthesis.agent
            output = [string]$stage.synthesis.output
        })
        for ($index = 0; $index -lt $agents.Count; $index++) {
            $profileName = Select-QaFoundryAgentProfileName `
                -Config $config `
                -RunId "run-private-model-config" `
                -StageId "discovery" `
                -StageIteration 1 `
                -AgentOrdinal $index
            $expectedModel = [string]$config.ai.profiles.PSObject.Properties[$profileName].Value.model
            $requestPath = Join-Path $runRoot (
                "discovery/" + [string]$agents[$index].output + ".attempt-1.request.md"
            )
            $request = Get-Content -LiteralPath $requestPath -Raw
            # The assertion is that the line names this model and nothing after
            # it, not which characters end the line. A CRLF checkout puts a
            # carriage return before the newline, and anchoring on $ alone would
            # then fail on a request that is entirely correct.
            $request | Should -Match ("(?m)^- Model: " + [regex]::Escape($expectedModel) + "\r?$")
        }
        $config.ai.model | Should -Be "claude-opus-5"
        $config.ai.PSObject.Properties.Name | Should -Not -Contain "resolved_profile"
    }

    It "rejects a collaboration pool that names an unknown profile" {
        $script:CollaborationConfig.ai.collaboration.profiles = @("claude", "missing")
        {
            Get-QaFoundryCollaborationProfileNames -Config $script:CollaborationConfig
        } | Should -Throw "*profile does not exist: missing*"
    }

    It "rejects profile aliases that all resolve to one model" {
        $script:CollaborationConfig.ai.profiles.codex.model = "claude-opus-5"
        $script:CollaborationConfig.ai.profiles.sol.model = "claude-opus-5"
        {
            Get-QaFoundryCollaborationProfileNames -Config $script:CollaborationConfig
        } | Should -Throw "*at least two distinct configured models*"
    }
}

Describe "Azure DevOps user credentials" {
    BeforeEach {
        $script:CredentialConfig = [pscustomobject]@{
            organization_url = "https://dev.azure.com/example"
            auth_env = "AZURE_DEVOPS_TOKEN"
            auth_scheme = "basic"
            expected_user_id = ""
            match_build_requester = $true
        }
    }

    It "resolves the configured PAT owner and returns Basic authorization" {
        Mock Invoke-RestMethod {
            param($Method, $Uri, $Headers)
            $Method | Should -Be "Get"
            $Uri | Should -Match "/_apis/connectionData"
            [string]$Headers.Authorization | Should -Match "^Basic "
            return New-TestAdoConnectionData
        }

        $context = Get-QaFoundryAzureDevOpsUserContext `
            -AzureDevOpsConfig $script:CredentialConfig `
            -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }

        $context.userId | Should -Be $script:AdoUserId
        $context.displayName | Should -Be $script:AdoUserName
        $context.email | Should -Be $script:AdoUserEmail
    }

    It "rejects bearer credentials before contacting Azure DevOps" {
        $script:CredentialConfig.auth_scheme = "bearer"
        Mock Invoke-RestMethod { throw "must not be called" }

        {
            Get-QaFoundryAzureDevOpsUserContext `
                -AzureDevOpsConfig $script:CredentialConfig `
                -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "service-token" }
        } | Should -Throw "*Bearer/System.AccessToken credentials act as a build service*"
        Should -Invoke -CommandName Invoke-RestMethod -Times 0 -Exactly
    }

    It "rejects a manual build whose requester does not own the PAT" {
        $previousReason = $env:BUILD_REASON
        $previousRequester = $env:BUILD_REQUESTEDFORID
        $env:BUILD_REASON = "Manual"
        $env:BUILD_REQUESTEDFORID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        Mock Invoke-RestMethod { return New-TestAdoConnectionData }
        try {
            {
                Get-QaFoundryAzureDevOpsUserContext `
                    -AzureDevOpsConfig $script:CredentialConfig `
                    -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
            } | Should -Throw "*does not belong to the user who requested this build*"
        }
        finally {
            if ($null -eq $previousReason) {
                Remove-Item Env:BUILD_REASON -ErrorAction SilentlyContinue
            }
            else { $env:BUILD_REASON = $previousReason }
            if ($null -eq $previousRequester) {
                Remove-Item Env:BUILD_REQUESTEDFORID -ErrorAction SilentlyContinue
            }
            else { $env:BUILD_REQUESTEDFORID = $previousRequester }
        }
    }
}

Describe "Permissioned deterministic actions" {
    It "applies only scoped paths and applies the same change once" {
        $repository = Join-Path $TestDrive "scoped-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        & git -C $repository init | Out-Null
        & git -C $repository config user.email "foundry-tests@example.invalid"
        & git -C $repository config user.name "Foundry Tests"
        Set-Content -Path (Join-Path $repository "README.md") -Value "baseline"
        & git -C $repository add README.md
        & git -C $repository commit -m "baseline" | Out-Null

        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.delivery.dry_run = $false
        $config.delivery.apply_changes = $true
        $planPath = Join-Path $TestDrive "change-set.json"
        [ordered]@{
            agentId = "test-generator"; stageId = "change-generation"; runId = "run-action"
            status = "completed"; summary = "Create one scoped file."; evidence = @()
            assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"
            changes = @([ordered]@{
                operation = "create"; path = "automation/proof.txt"; expectedSha256 = ""
                content = "proof"; reason = "test"; sourceRefs = @("work-item:42")
            })
        } | ConvertTo-Json -Depth 20 | Set-Content -Path $planPath

        $first = & (Join-Path $script:Root "scripts/Apply-ScopedChangeSet.ps1") `
            -PlanPath $planPath -Config $config -RepositoryRoot $repository `
            -RunRoot $TestDrive -RunId "run-action"
        $first.actions[0].status | Should -Be "executed"
        (Get-Content -Path (Join-Path $repository "automation/proof.txt") -Raw) |
            Should -Be "proof"

        $second = & (Join-Path $script:Root "scripts/Apply-ScopedChangeSet.ps1") `
            -PlanPath $planPath -Config $config -RepositoryRoot $repository `
            -RunRoot $TestDrive -RunId "run-action-retry"
        $second.actions[0].status | Should -Be "duplicate"
    }

    # What a change is, for the purpose of not doing it twice, is the file it
    # writes and the bytes it writes there. Keying it by the agent's own source
    # reference made these three cases indistinguishable from work already done.
    Context "Telling one change from another" {
        BeforeAll {
            function script:New-AppliedRepository {
                $repository = Join-Path $TestDrive ("apply-" + [Guid]::NewGuid().ToString("N"))
                New-Item -ItemType Directory -Path $repository -Force | Out-Null
                & git -C $repository init | Out-Null
                & git -C $repository config user.email "foundry-tests@example.invalid"
                & git -C $repository config user.name "Foundry Tests"
                Set-Content -Path (Join-Path $repository "README.md") -Value "baseline"
                & git -C $repository add README.md
                & git -C $repository commit -m "baseline" | Out-Null
                return $repository
            }

            function script:New-ChangePlan {
                param([Parameter(Mandatory)][object[]]$Changes)
                $planPath = Join-Path $TestDrive ("plan-" + [Guid]::NewGuid().ToString("N") + ".json")
                [ordered]@{
                    agentId = "test-generator"; stageId = "change-generation"; runId = "run-keyed"
                    status = "completed"; summary = "Write the files this change describes."
                    evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
                    outcome = "proposed"
                    changes = @($Changes)
                } | ConvertTo-Json -Depth 20 | Set-Content -Path $planPath
                return $planPath
            }

            function script:Get-ApplyConfig {
                $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
                $config.delivery.dry_run = $false
                $config.delivery.apply_changes = $true
                return $config
            }
        }

        It "writes every file a plan names even when they cite one reason" {
            # A blueprint's files all cite the blueprint. Keyed by that reference,
            # the second file read as work already done and was never written -
            # and the run reported success with half a framework on disk.
            $repository = New-AppliedRepository
            $planPath = New-ChangePlan -Changes @(
                [ordered]@{
                    operation = "create"; path = "automation/first.txt"; expectedSha256 = ""
                    content = "first"; reason = "test"; sourceRefs = @("blueprint:automationProjects")
                },
                [ordered]@{
                    operation = "create"; path = "automation/second.txt"; expectedSha256 = ""
                    content = "second"; reason = "test"; sourceRefs = @("blueprint:automationProjects")
                }
            )

            # Applied twice: the second run is where a shared key would have
            # skipped the second file, because the first run registers both.
            $null = & (Join-Path $script:Root "scripts/Apply-ScopedChangeSet.ps1") `
                -PlanPath $planPath -Config (Get-ApplyConfig) -RepositoryRoot $repository `
                -RunRoot $TestDrive -RunId "run-shared-ref"
            Remove-Item -LiteralPath (Join-Path $repository "automation/second.txt") -Force
            $again = & (Join-Path $script:Root "scripts/Apply-ScopedChangeSet.ps1") `
                -PlanPath $planPath -Config (Get-ApplyConfig) -RepositoryRoot $repository `
                -RunRoot $TestDrive -RunId "run-shared-ref-again"

            (Get-Content -LiteralPath (Join-Path $repository "automation/first.txt") -Raw) |
                Should -Be "first"
            (Get-Content -LiteralPath (Join-Path $repository "automation/second.txt") -Raw) |
                Should -Be "second"
            @($again.actions | Where-Object { $_.externalId -eq "automation/second.txt" })[0].status |
                Should -Be "executed"
        }

        It "applies a second correction to a file it already corrected once" {
            # Both corrections are updates to one file for one work item, so under
            # a key built from operation and reference they are the same action:
            # the second read as work already done and the file kept the first
            # correction. Only the bytes tell them apart.
            $repository = New-AppliedRepository
            $tracked = Join-Path $repository "automation/suite.txt"
            New-Item -ItemType Directory -Path (Split-Path $tracked -Parent) -Force | Out-Null
            Set-Content -LiteralPath $tracked -Value "original" -Encoding utf8 -NoNewline
            & git -C $repository add automation/suite.txt
            & git -C $repository commit -m "suite" | Out-Null

            $first = New-ChangePlan -Changes @([ordered]@{
                operation = "update"; path = "automation/suite.txt"
                expectedSha256 = (Get-FileHash -LiteralPath $tracked -Algorithm SHA256).Hash.ToLowerInvariant()
                content = "first correction"; reason = "test"; sourceRefs = @("work-item:42")
            })
            $null = & (Join-Path $script:Root "scripts/Apply-ScopedChangeSet.ps1") `
                -PlanPath $first -Config (Get-ApplyConfig) -RepositoryRoot $repository `
                -RunRoot $TestDrive -RunId "run-correction-one"
            & git -C $repository add -A
            & git -C $repository commit -m "first correction" | Out-Null

            $second = New-ChangePlan -Changes @([ordered]@{
                operation = "update"; path = "automation/suite.txt"
                expectedSha256 = (Get-FileHash -LiteralPath $tracked -Algorithm SHA256).Hash.ToLowerInvariant()
                content = "second correction"; reason = "test"; sourceRefs = @("work-item:42")
            })
            $result = & (Join-Path $script:Root "scripts/Apply-ScopedChangeSet.ps1") `
                -PlanPath $second -Config (Get-ApplyConfig) -RepositoryRoot $repository `
                -RunRoot $TestDrive -RunId "run-correction-two"

            $result.actions[0].status | Should -Be "executed"
            (Get-Content -LiteralPath $tracked -Raw) | Should -Be "second correction"
        }

        It "does not treat its own record as evidence that the file is there" {
            # The registry lives in the repository and travels with it. A checkout
            # that carries the record without the file - or a working tree someone
            # cleaned - would otherwise skip the only write in the run and deliver
            # nothing, reporting a duplicate.
            $repository = New-AppliedRepository
            $planPath = New-ChangePlan -Changes @([ordered]@{
                operation = "create"; path = "automation/proof.txt"; expectedSha256 = ""
                content = "proof"; reason = "test"; sourceRefs = @("work-item:42")
            })
            $null = & (Join-Path $script:Root "scripts/Apply-ScopedChangeSet.ps1") `
                -PlanPath $planPath -Config (Get-ApplyConfig) -RepositoryRoot $repository `
                -RunRoot $TestDrive -RunId "run-record-first"
            Remove-Item -LiteralPath (Join-Path $repository "automation/proof.txt") -Force

            $result = & (Join-Path $script:Root "scripts/Apply-ScopedChangeSet.ps1") `
                -PlanPath $planPath -Config (Get-ApplyConfig) -RepositoryRoot $repository `
                -RunRoot $TestDrive -RunId "run-record-again"

            $result.actions[0].status | Should -Be "executed"
            (Get-Content -LiteralPath (Join-Path $repository "automation/proof.txt") -Raw) |
                Should -Be "proof"
        }
    }

    It "rejects out-of-scope repository changes before writing" {
        $repository = Join-Path $TestDrive "rejected-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        & git -C $repository init | Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.delivery.dry_run = $false
        $config.delivery.apply_changes = $true
        $planPath = Join-Path $TestDrive "rejected-change-set.json"
        # Schema-valid on purpose: this test is about the scope guard, and a
        # fixture that fails validation first would stop proving the guard works.
        [ordered]@{
            agentId = "test-generator"; stageId = "change-generation"; runId = "run-rejected"
            status = "completed"; summary = "Attempt a change outside the allowed scope."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"
            changes = @([ordered]@{
                operation = "create"; path = "src/unsafe.txt"; expectedSha256 = ""
                content = "unsafe"; reason = "test"; sourceRefs = @("unsafe:1")
            })
        } | ConvertTo-Json -Depth 20 | Set-Content -Path $planPath
        {
            & (Join-Path $script:Root "scripts/Apply-ScopedChangeSet.ps1") `
                -PlanPath $planPath -Config $config -RepositoryRoot $repository `
                -RunRoot $TestDrive -RunId "run-rejected"
        } | Should -Throw "*forbidden path*"
        Test-Path (Join-Path $repository "src/unsafe.txt") | Should -BeFalse
    }

    It "refuses a plan that still names work for a resolver" {
        # A lock file's integrity hashes come from a resolver, so a plan that still
        # asks for one has not produced the bytes it claims to deliver. Applying it
        # would either write nothing or write an invented lock.
        $repository = Join-Path $TestDrive "unresolved-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        & git -C $repository init | Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.delivery.dry_run = $false
        $config.delivery.apply_changes = $true
        $planPath = Join-Path $TestDrive "unresolved-change-set.json"
        [ordered]@{
            agentId = "test-generator"; stageId = "change-generation"; runId = "run-unresolved"
            status = "completed"; summary = "Propose a manifest and ask for its lock."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"
            changes = @([ordered]@{
                operation = "create"; path = "automation/package.json"; expectedSha256 = ""
                content = "{}"; reason = "test"; sourceRefs = @("work-item:42")
            })
            materializations = @([ordered]@{
                recipe = "npm-package-lock"; toolchainId = "npm-playwright-test"
                manifestPath = "automation/package.json"
                lockPath = "automation/package-lock.json"
                projectPaths = @("automation")
                operation = "create"; expectedSha256 = ""; reason = "test"
                sourceRefs = @("work-item:42")
            })
        } | ConvertTo-Json -Depth 20 | Set-Content -Path $planPath
        {
            & (Join-Path $script:Root "scripts/Apply-ScopedChangeSet.ps1") `
                -PlanPath $planPath -Config $config -RepositoryRoot $repository `
                -RunRoot $TestDrive -RunId "run-unresolved"
        } | Should -Throw
        Test-Path (Join-Path $repository "automation/package.json") | Should -BeFalse
    }

    It "refuses a blocked change set that still carries changes" {
        # A refusal that writes to the repository is not a refusal.
        $repository = Join-Path $TestDrive "blocked-carrying-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        & git -C $repository init | Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.delivery.dry_run = $false
        $config.delivery.apply_changes = $true
        $planPath = Join-Path $TestDrive "blocked-carrying-change-set.json"
        [ordered]@{
            agentId = "test-generator"; stageId = "change-generation"; runId = "run-blocked-carrying"
            status = "blocked"; summary = "Could not finish, but wrote something anyway."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"
            changes = @([ordered]@{
                operation = "create"; path = "automation/sneaked.txt"; expectedSha256 = ""
                content = "sneaked"; reason = "test"; sourceRefs = @("work-item:42")
            })
        } | ConvertTo-Json -Depth 20 | Set-Content -Path $planPath
        {
            & (Join-Path $script:Root "scripts/Apply-ScopedChangeSet.ps1") `
                -PlanPath $planPath -Config $config -RepositoryRoot $repository `
                -RunRoot $TestDrive -RunId "run-blocked-carrying"
        } | Should -Throw
        Test-Path (Join-Path $repository "automation/sneaked.txt") | Should -BeFalse
    }

    It "keeps a lock file out of literal plan content whichever separator it uses" {
        # The plan contract has to make the dishonest option unrepresentable, not
        # merely discouraged in a prompt. A backslash is not a different file:
        # path scoping normalises it to a forward slash before anything is written.
        foreach ($lockPath in @("automation/package-lock.json", "automation\package-lock.json")) {
            $planPath = Join-Path $TestDrive "invented-lock-plan.json"
            [ordered]@{
                agentId = "test-generator"; stageId = "change-generation"; runId = "run-invented-lock"
                status = "completed"; summary = "Write a lock file from memory."
                evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
                outcome = "proposed"
                changes = @([ordered]@{
                    operation = "create"; path = $lockPath; expectedSha256 = ""
                    content = "{}"; reason = "test"; sourceRefs = @("work-item:42")
                })
                materializations = @()
            } | ConvertTo-Json -Depth 20 | Set-Content -Path $planPath
            {
                & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                    -ArtifactPath $planPath `
                    -SchemaPath (Join-Path $script:Root "schemas/actions/change-set-plan.schema.json")
            } | Should -Throw
        }
    }

    It "accepts a plan that asks for a lock instead of inventing one" {
        $planPath = Join-Path $TestDrive "honest-plan.json"
        [ordered]@{
            agentId = "test-generator"; stageId = "change-generation"; runId = "run-honest"
            status = "completed"; summary = "Propose a manifest and name the lock to resolve."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"
            changes = @([ordered]@{
                operation = "create"; path = "automation/package.json"; expectedSha256 = ""
                content = "{}"; reason = "test"; sourceRefs = @("work-item:42")
            })
            materializations = @([ordered]@{
                recipe = "npm-package-lock"; toolchainId = "npm-playwright-test"
                manifestPath = "automation/package.json"
                lockPath = "automation/package-lock.json"
                projectPaths = @("automation")
                operation = "create"; expectedSha256 = ""; reason = "test"
                sourceRefs = @("work-item:42")
            })
        } | ConvertTo-Json -Depth 20 | Set-Content -Path $planPath
        & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $planPath `
            -SchemaPath (Join-Path $script:Root "schemas/actions/change-set-plan.schema.json")
    }

    It "creates Azure DevOps work items as dry-run without any credential" {
        $repository = Join-Path $TestDrive "work-items"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.work_tracking.enabled = $true
        $config.work_tracking.provider = "azure-devops"
        $config.work_tracking.dry_run = $true
        $planPath = Join-Path $TestDrive "work-item-plan.json"
        @{ items = @(@{
            sourceRef = "finding:1"; type = "bug"; title = "Fix evidence-backed defect"
            description = "A bounded dry-run item."; priority = 2; tags = @("foundry")
            acceptanceCriteria = @("The deterministic check passes.")
        }) } | ConvertTo-Json -Depth 10 | Set-Content -Path $planPath
        $result = & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
            -PlanPath $planPath -Config $config -RepositoryRoot $repository `
            -RunId "run-items" -ActionEnvironment @{}
        $result.dryRun | Should -BeTrue
        $result.actions[0].status | Should -Be "dry_run"
    }

    It "refuses a live commit when no authenticated user provider is configured" {
        $repository = Join-Path $TestDrive "unattributed-commit-repository"
        $runRoot = Join-Path $TestDrive "unattributed-commit-run"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $runRoot "planning") -Force | Out-Null
        & git -C $repository init | Out-Null
        Set-Content -LiteralPath (Join-Path $repository "README.md") -Value "baseline"
        & git -c user.name="Baseline" -c user.email="baseline@example.invalid" `
            -C $repository add README.md
        & git -c user.name="Baseline" -c user.email="baseline@example.invalid" `
            -C $repository commit -m "baseline" | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $repository "automation") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repository "automation/proof.txt") -Value "approved" -NoNewline
        @{ changes = @(@{ path = "automation/proof.txt"; operation = "create"; content = "approved" }) } |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $runRoot "planning/change-set.json")
        $originalBranch = [string](& git -C $repository branch --show-current)
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.delivery.provider = "none"
        $config.delivery.dry_run = $false
        $config.delivery.create_branch = $true
        $config.delivery.commit_changes = $true

        {
            & (Join-Path $script:Root "scripts/writers/Publish-RepositoryDelivery.ps1") `
                -Config $config `
                -RepositoryRoot $repository `
                -RunRoot $runRoot `
                -RunId "run-unattributed-commit"
        } | Should -Throw "*authenticated PAT owner*"
        [string](& git -C $repository branch --show-current) | Should -Be $originalBranch
        [string](& git -C $repository rev-list --count HEAD) | Should -Be "1"
    }

    # Git tells 'automation/proof.txt' and 'Automation/proof.txt' apart, and the
    # pipelines commit from Linux agents where both can exist side by side. Treating
    # them as one path is how a file nobody approved reaches a pull request.
    It "refuses a working-tree path that differs from an approved one only by case" {
        $repository = Join-Path $TestDrive "cased-delivery-repository"
        $runRoot = Join-Path $TestDrive "cased-delivery-run"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $runRoot "planning") -Force | Out-Null
        & git -C $repository init | Out-Null
        Set-Content -LiteralPath (Join-Path $repository "README.md") -Value "baseline"
        & git -c user.name="Baseline" -c user.email="baseline@example.invalid" `
            -C $repository add README.md
        & git -c user.name="Baseline" -c user.email="baseline@example.invalid" `
            -C $repository commit -m "baseline" | Out-Null
        # Only the differently-cased path exists; nothing approved it.
        New-Item -ItemType Directory -Path (Join-Path $repository "Automation") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repository "Automation/proof.txt") -Value "unapproved"
        @{ changes = @(@{ path = "automation/proof.txt"; operation = "create"; content = "approved" }) } |
            ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath (Join-Path $runRoot "planning/change-set.json")
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.delivery.provider = "none"
        $config.delivery.dry_run = $false
        $config.delivery.create_branch = $true
        $config.delivery.commit_changes = $true

        {
            & (Join-Path $script:Root "scripts/writers/Publish-RepositoryDelivery.ps1") `
                -Config $config `
                -RepositoryRoot $repository `
                -RunRoot $runRoot `
                -RunId "run-cased-delivery"
        } | Should -Throw "*differs from an approved path only by letter case*"
        [string](& git -C $repository rev-list --count HEAD) | Should -Be "1"
    }

    It "creates one Azure DevOps work item and de-duplicates an executed retry" {        $repository = Join-Path $TestDrive "work-items-live"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.work_tracking.enabled = $true
        $config.work_tracking.provider = "azure-devops"
        $config.work_tracking.dry_run = $false
        $config.work_tracking.azure_devops.organization_url = "https://dev.azure.com/example"
        $config.work_tracking.azure_devops.project = "product"
        $config.delivery.azure_devops.repository_id = "repo-under-test"
        $planPath = Join-Path $TestDrive "work-item-live-plan.json"
        @{ items = @(@{
            sourceRef = "finding:live"; type = "task"; title = "Create one item"
            description = "Mocked provider request."; priority = 2; tags = @("foundry")
            acceptanceCriteria = @("One issue exists.")
        }) } | ConvertTo-Json -Depth 10 | Set-Content -Path $planPath
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like "*/_apis/connectionData?*") {
                return New-TestAdoConnectionData
            }
            if ($Uri -like "*/_apis/wit/wiql*") {
                return [pscustomobject]@{ workItems = @() }
            }
            return [pscustomobject]@{ id = 91 }
        }
        $first = & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
            -PlanPath $planPath -Config $config -RepositoryRoot $repository `
            -RunId "run-items-live" -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        $first.actions[0].status | Should -Be "executed"
        $first.actions[0].externalId | Should -Be "91"
        $second = & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
            -PlanPath $planPath -Config $config -RepositoryRoot $repository `
            -RunId "run-items-live-retry" -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        $second.actions[0].status | Should -Be "duplicate"
        Should -Invoke -CommandName Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq "Post" -and $Uri -like "*/_apis/wit/workitems/*"
        }
    }

    It "recognises work it already filed when the registry did not survive the checkout" {
        # The registry is a file in the repository and every pipeline run starts
        # from a fresh clone, so on the second run it says nothing - not "no item
        # exists" but "I have never seen anything". Acting on that reading files
        # a second copy of every item into a project people are working out of.
        # The marker that answers the question therefore lives on the item.
        $repository = Join-Path $TestDrive "work-items-fresh-checkout"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.work_tracking.enabled = $true
        $config.work_tracking.provider = "azure-devops"
        $config.work_tracking.dry_run = $false
        $config.work_tracking.azure_devops.organization_url = "https://dev.azure.com/example"
        $config.work_tracking.azure_devops.project = "product"
        $config.delivery.azure_devops.repository_id = "repo-under-test"
        $planPath = Join-Path $TestDrive "work-item-fresh-plan.json"
        @{ items = @(@{
            sourceRef = "finding:survives"; type = "task"; title = "File this once"
            description = "Mocked provider request."; priority = 2; tags = @("foundry")
            acceptanceCriteria = @("Exactly one item exists.")
        }) } | ConvertTo-Json -Depth 10 | Set-Content -Path $planPath

        $global:WorkItemMarkerProbe = @{ marker = ""; exists = $false }
        Mock Invoke-RestMethod {
            param($Uri, $Method, $Body)
            if ($Uri -like "*/_apis/connectionData?*") { return New-TestAdoConnectionData }
            if ($Uri -like "*/_apis/wit/wiql*") {
                if (-not $global:WorkItemMarkerProbe.exists) { return [pscustomobject]@{ workItems = @() } }
                return [pscustomobject]@{ workItems = @([pscustomobject]@{ id = 502 }) }
            }
            if ($Uri -like "*/_apis/wit/workitems/*") {
                $patch = @($Body | ConvertFrom-Json -Depth 20)
                $tags = @($patch | Where-Object { [string]$_.path -eq "/fields/System.Tags" })
                if ($tags.Count -gt 0) { $global:WorkItemMarkerProbe.marker = [string]$tags[0].value }
                $global:WorkItemMarkerProbe.exists = $true
                return [pscustomobject]@{ id = 502 }
            }
            return [pscustomobject]@{ value = @() }
        }

        $first = & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
            -PlanPath $planPath -Config $config -RepositoryRoot $repository `
            -RunId "run-fresh-first" -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        $first.actions[0].status | Should -Be "executed"
        # The marker travels in the creating request itself, beside whatever tags
        # the plan asked for.
        $global:WorkItemMarkerProbe.marker | Should -Match "sdlc-foundry-ref-[0-9a-f]{20}"
        $global:WorkItemMarkerProbe.marker | Should -Match "foundry"

        # What a fresh checkout looks like: everything the last run wrote inside
        # the repository is gone.
        $registryPath = Join-Path $repository ([string]$config.idempotency.registry_path)
        Remove-Item -LiteralPath $registryPath -Force -ErrorAction SilentlyContinue
        Test-Path -LiteralPath $registryPath | Should -BeFalse

        $second = & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
            -PlanPath $planPath -Config $config -RepositoryRoot $repository `
            -RunId "run-fresh-second" -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        $second.actions[0].status | Should -Be "duplicate"
        $second.actions[0].externalId | Should -Be "502"
        Should -Invoke -CommandName Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq "Post" -and $Uri -like "*/_apis/wit/workitems/*"
        }
        Remove-Variable -Name "WorkItemMarkerProbe" -Scope Global -ErrorAction SilentlyContinue
    }

    # A test case's sourceRef is derived from the project, file and test name so
    # that a second run recognises the card instead of filing a duplicate. The
    # consequence is that a test whose assertions changed keeps its old card, and
    # a card that states an expectation the suite no longer has is worse than no
    # card at all: someone executes it by hand and reports the difference.
    Context "Keeping a test case in step with the test" {
        BeforeAll {
            function script:New-SyncConfig {
                param([Parameter(Mandatory)][string]$Repository)
                New-Item -ItemType Directory -Path $Repository -Force | Out-Null
                $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
                $config.work_tracking.enabled = $true
                $config.work_tracking.provider = "azure-devops"
                $config.work_tracking.dry_run = $false
                $config.work_tracking.azure_devops.organization_url = "https://dev.azure.com/example"
                $config.work_tracking.azure_devops.project = "product"
                $config.delivery.azure_devops.repository_id = "repo-under-test"
                return $config
            }

            function script:New-TestCasePlan {
                param(
                    [Parameter(Mandatory)][string]$Path,
                    [Parameter(Mandatory)][string]$Title,
                    [Parameter(Mandatory)][string]$Description,
                    [string[]]$Criteria = @("The quote is returned."),
                    [string[]]$Tags = @("automation-api"),
                    [int]$Priority = 2,
                    [string]$Type = "test_case"
                )
                @{ items = @(@{
                    sourceRef = "automation/Api/QuoteTests.cs::returns_a_quote"
                    type = $Type; title = $Title; description = $Description
                    priority = $Priority; tags = @($Tags); acceptanceCriteria = @($Criteria)
                }) } | ConvertTo-Json -Depth 10 | Set-Content -Path $Path
                return $Path
            }

            # One card in a project, as Azure DevOps would answer for it. The
            # store is what makes the second run a genuine second run: it reads
            # back what the first one wrote rather than a fixture written by hand.
            function script:Register-WorkItemCardMock {
                $global:WorkItemCard = @{
                    exists = $false
                    rev = 1
                    fields = @{}
                    patches = [System.Collections.Generic.List[object]]::new()
                }
                Mock Invoke-RestMethod {
                    param($Uri, $Method, $Body)
                    if ($Uri -like "*/_apis/connectionData?*") { return New-TestAdoConnectionData }
                    if ($Uri -like "*/_apis/wit/wiql*") {
                        if (-not $global:WorkItemCard.exists) {
                            return [pscustomobject]@{ workItems = @() }
                        }
                        return [pscustomobject]@{ workItems = @([pscustomobject]@{ id = 771 }) }
                    }
                    if ($Uri -like "*/_apis/wit/workitems/*") {
                        if ($Method -eq "Get") {
                            return [pscustomobject]@{
                                id = 771; rev = $global:WorkItemCard.rev
                                fields = $global:WorkItemCard.fields
                            }
                        }
                        $operations = @($Body | ConvertFrom-Json -Depth 20)
                        foreach ($operation in $operations) {
                            $path = [string]$operation.path
                            if ($path -eq "/rev") {
                                if ([int]$operation.value -ne [int]$global:WorkItemCard.rev) {
                                    throw "TF401326: the work item has been updated by someone else."
                                }
                                continue
                            }
                            if ($path -notlike "/fields/*") { continue }
                            $global:WorkItemCard.patches.Add($path)
                            $global:WorkItemCard.fields[$path.Substring(8)] = $operation.value
                        }
                        $global:WorkItemCard.exists = $true
                        $global:WorkItemCard.rev = [int]$global:WorkItemCard.rev + 1
                        return [pscustomobject]@{ id = 771 }
                    }
                    return [pscustomobject]@{ value = @() }
                }
            }

            function script:Invoke-WorkItemSync {
                param([Parameter(Mandatory)][string]$PlanPath, [Parameter(Mandatory)][object]$Config,
                    [Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][string]$RunId)
                return & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
                    -PlanPath $PlanPath -Config $Config -RepositoryRoot $Repository `
                    -RunId $RunId -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
            }
        }

        AfterEach {
            Remove-Variable -Name "WorkItemCard" -Scope Global -ErrorAction SilentlyContinue
        }

        It "brings the card up to date when the test it describes has changed" {
            $repository = Join-Path $TestDrive "test-case-changed"
            $config = New-SyncConfig -Repository $repository
            Register-WorkItemCardMock
            $planPath = Join-Path $TestDrive "test-case-plan.json"

            $null = Invoke-WorkItemSync -RunId "run-sync-first" -Config $config -Repository $repository `
                -PlanPath (New-TestCasePlan -Path $planPath -Title "Returns a quote" `
                    -Description "automation/Api, QuoteTests.cs" -Criteria @("A quote is returned."))
            $global:WorkItemCard.fields["System.Title"] | Should -Be "Returns a quote"

            $global:WorkItemCard.patches.Clear()
            $result = Invoke-WorkItemSync -RunId "run-sync-second" -Config $config -Repository $repository `
                -PlanPath (New-TestCasePlan -Path $planPath -Title "Returns a quote with tax" `
                    -Description "automation/Api, QuoteTests.cs" `
                    -Criteria @("A quote is returned.", "The quote includes tax."))

            $result.actions[0].externalId | Should -Be "771"
            # A write happened, so the action says one happened.
            $result.actions[0].status | Should -Be "executed"
            $result.actions[0].summary | Should -Match "brought up to date"
            $global:WorkItemCard.fields["System.Title"] | Should -Be "Returns a quote with tax"
            $global:WorkItemCard.fields["Microsoft.VSTS.Common.AcceptanceCriteria"] |
                Should -Match "The quote includes tax"
            # The description did not change, so it was not rewritten.
            @($global:WorkItemCard.patches) | Should -Not -Contain "/fields/System.Description"
        }

        It "writes nothing when the card already says what the test says" {
            # Azure DevOps returns these fields wrapped in markup it added itself,
            # so a literal comparison would rewrite every card on every run and
            # the history would stop showing which tests actually changed.
            $repository = Join-Path $TestDrive "test-case-unchanged"
            $config = New-SyncConfig -Repository $repository
            Register-WorkItemCardMock
            $planPath = Join-Path $TestDrive "test-case-unchanged-plan.json"
            $plan = New-TestCasePlan -Path $planPath -Title "Returns a quote" `
                -Description "automation/Api, QuoteTests.cs"

            $null = Invoke-WorkItemSync -RunId "run-same-first" -Config $config `
                -Repository $repository -PlanPath $plan
            # What the project gives back is not what was sent to it.
            $global:WorkItemCard.fields["System.Description"] =
                "<div>automation/Api,&nbsp;QuoteTests.cs</div>"
            $global:WorkItemCard.patches.Clear()

            $result = Invoke-WorkItemSync -RunId "run-same-second" -Config $config `
                -Repository $repository -PlanPath $plan

            $result.actions[0].status | Should -Be "duplicate"
            @($global:WorkItemCard.patches).Count | Should -Be 0
        }

        It "adds the tags the plan asks for without removing the ones already there" {
            $repository = Join-Path $TestDrive "test-case-tags"
            $config = New-SyncConfig -Repository $repository
            Register-WorkItemCardMock
            $planPath = Join-Path $TestDrive "test-case-tags-plan.json"

            $null = Invoke-WorkItemSync -RunId "run-tags-first" -Config $config -Repository $repository `
                -PlanPath (New-TestCasePlan -Path $planPath -Title "Returns a quote" `
                    -Description "automation/Api, QuoteTests.cs" -Tags @("automation-api"))
            # A person filed this card under a suite of their own.
            $global:WorkItemCard.fields["System.Tags"] =
                [string]$global:WorkItemCard.fields["System.Tags"] + "; regression-pack"

            $null = Invoke-WorkItemSync -RunId "run-tags-second" -Config $config -Repository $repository `
                -PlanPath (New-TestCasePlan -Path $planPath -Title "Returns a quote" `
                    -Description "automation/Api, QuoteTests.cs" -Tags @("automation-api", "smoke"))

            $tags = @([string]$global:WorkItemCard.fields["System.Tags"] -split ";" |
                ForEach-Object { $_.Trim() })
            $tags | Should -Contain "regression-pack"
            $tags | Should -Contain "smoke"
            # The marker is what lets the next run find this card at all.
            @($tags | Where-Object { $_ -match "^sdlc-foundry-ref-" }).Count | Should -Be 1
        }

        It "writes visible reproduction evidence for <Type> when the field is supported=<Supported>" -ForEach @(
            @{ Type = 'bug'; Supported = $true; Expected = $true },
            @{ Type = 'bug'; Supported = $false; Expected = $false },
            @{ Type = 'task'; Supported = $true; Expected = $false }
        ) {
            $repository = Join-Path $TestDrive "visible-description-$Type-$Supported"
            $config = New-SyncConfig -Repository $repository
            Register-WorkItemCardMock
            Mock Invoke-RestMethod {
                [pscustomobject]@{ value = @(
                    [pscustomobject]@{ referenceName = 'System.Description' }
                    if ($Supported) { [pscustomobject]@{ referenceName = 'Microsoft.VSTS.TCM.ReproSteps' } }
                ) }
            } -ParameterFilter { $Uri -like '*/workitemtypes/*/fields?*' }
            $plan = New-TestCasePlan -Path (Join-Path $repository 'plan.json') -Title 'Schema rejects TOTAL' `
                -Description '<p>Expected TOTAL to validate; actual NotInEnumeration.</p>' -Type $Type
            $null = Invoke-WorkItemSync -RunId run-visible-bug -Config $config -Repository $repository -PlanPath $plan
            $global:WorkItemCard.fields['System.Description'] | Should -Match 'NotInEnumeration'
            $global:WorkItemCard.fields.ContainsKey('Microsoft.VSTS.TCM.ReproSteps') | Should -Be $Expected
            if ($Expected) {
                $global:WorkItemCard.fields['Microsoft.VSTS.TCM.ReproSteps'] |
                    Should -Be $global:WorkItemCard.fields['System.Description']
            }
        }

        It "leaves a reused task alone, because people work out of one" {
            # A test case is a statement about code and the plan is its only
            # author. A task is a description of work, and once it is filed the
            # people doing it add what they found. Rewriting that from a later
            # analysis would erase it with nothing to show for it.
            $repository = Join-Path $TestDrive "reused-task"
            $config = New-SyncConfig -Repository $repository
            Register-WorkItemCardMock
            $planPath = Join-Path $TestDrive "reused-task-plan.json"

            $null = Invoke-WorkItemSync -RunId "run-task-first" -Config $config -Repository $repository `
                -PlanPath (New-TestCasePlan -Path $planPath -Title "Fix the rounding" `
                    -Description "The total is rounded twice." -Type "bug")
            $global:WorkItemCard.fields["System.Description"] =
                "Reproduced on build 900 with a two-leg trade."
            $global:WorkItemCard.patches.Clear()

            $result = Invoke-WorkItemSync -RunId "run-task-second" -Config $config -Repository $repository `
                -PlanPath (New-TestCasePlan -Path $planPath -Title "Fix the rounding twice over" `
                    -Description "The total is rounded twice." -Type "bug")

            $result.actions[0].status | Should -Be "duplicate"
            @($global:WorkItemCard.patches).Count | Should -Be 0
            $global:WorkItemCard.fields["System.Description"] |
                Should -Be "Reproduced on build 900 with a two-leg trade."
        }
    }

    It "creates nothing when the project cannot say whether the work is already there" {
        # "The query failed" and "no such item exists" lead to opposite actions.
        # Reading the first as the second is how a run files duplicates during an
        # outage, and a duplicate in a real backlog cannot be taken back.
        $repository = Join-Path $TestDrive "work-items-unanswerable"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.work_tracking.enabled = $true
        $config.work_tracking.provider = "azure-devops"
        $config.work_tracking.dry_run = $false
        $config.work_tracking.azure_devops.organization_url = "https://dev.azure.com/example"
        $config.work_tracking.azure_devops.project = "product"
        $config.delivery.azure_devops.repository_id = "repo-under-test"
        $planPath = Join-Path $TestDrive "work-item-unanswerable-plan.json"
        @{ items = @(@{
            sourceRef = "finding:outage"; type = "task"; title = "Do not file twice"
            description = "Mocked provider request."; priority = 2; tags = @()
            acceptanceCriteria = @("Nothing is created.")
        }) } | ConvertTo-Json -Depth 10 | Set-Content -Path $planPath
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like "*/_apis/connectionData?*") { return New-TestAdoConnectionData }
            if ($Uri -like "*/_apis/wit/wiql*") { throw "503 Service Unavailable" }
            return [pscustomobject]@{ id = 777 }
        }

        {
            & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
                -PlanPath $planPath -Config $config -RepositoryRoot $repository `
                -RunId "run-unanswerable" -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        } | Should -Throw "*could file a second copy of work that is already in the project*"
        Should -Not -Invoke -CommandName Invoke-RestMethod -ParameterFilter {
            $Method -eq "Post" -and $Uri -like "*/_apis/wit/workitems/*"
        }
    }

    It "adopts the oldest of several items already carrying one marker" {
        # An earlier run without this protection could have filed the same item
        # twice. Adding a third helps nobody; the oldest is adopted and the
        # duplication is said out loud where someone can act on it.
        $repository = Join-Path $TestDrive "work-items-already-duplicated"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.work_tracking.enabled = $true
        $config.work_tracking.provider = "azure-devops"
        $config.work_tracking.dry_run = $false
        $config.work_tracking.azure_devops.organization_url = "https://dev.azure.com/example"
        $config.work_tracking.azure_devops.project = "product"
        $config.delivery.azure_devops.repository_id = "repo-under-test"
        $planPath = Join-Path $TestDrive "work-item-already-duplicated-plan.json"
        @{ items = @(@{
            sourceRef = "finding:twice"; type = "task"; title = "Already filed twice"
            description = "Mocked provider request."; priority = 2; tags = @()
            acceptanceCriteria = @("No third copy appears.")
        }) } | ConvertTo-Json -Depth 10 | Set-Content -Path $planPath
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like "*/_apis/connectionData?*") { return New-TestAdoConnectionData }
            if ($Uri -like "*/_apis/wit/wiql*") {
                return [pscustomobject]@{ workItems = @(
                    [pscustomobject]@{ id = 640 }, [pscustomobject]@{ id = 611 })
                }
            }
            return [pscustomobject]@{ id = 999 }
        }

        $result = & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
            -PlanPath $planPath -Config $config -RepositoryRoot $repository `
            -RunId "run-already-duplicated" -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }

        $result.actions[0].status | Should -Be "duplicate"
        $result.actions[0].externalId | Should -Be "611"
        [string]$result.actions[0].summary | Should -Match "611, 640 all carry this marker"
        Should -Not -Invoke -CommandName Invoke-RestMethod -ParameterFilter {
            $Method -eq "Post" -and $Uri -like "*/_apis/wit/workitems/*"
        }
    }

    It "creates, commits, pushes, and opens a pull request without reviewers" {
        $repository = Join-Path $TestDrive "delivery-repository"
        $remote = Join-Path $TestDrive "delivery-remote.git"
        $runRoot = Join-Path $TestDrive "delivery-run"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $runRoot "planning") -Force | Out-Null
        & git init --bare $remote | Out-Null
        & git -C $repository init | Out-Null
        & git -C $repository config user.email "foundry-tests@example.invalid"
        & git -C $repository config user.name "Foundry Tests"
        Set-Content -Path (Join-Path $repository "README.md") -Value "baseline"
        & git -C $repository add README.md
        & git -C $repository commit -m "baseline" | Out-Null
        & git -C $repository branch -M main
        & git -C $repository remote add origin $remote
        New-Item -ItemType Directory -Path (Join-Path $repository "automation") -Force | Out-Null
        Set-Content -Path (Join-Path $repository "automation/proof.txt") -Value "approved" -NoNewline
        @{ changes = @(@{ path = "automation/proof.txt"; operation = "create"; content = "approved" }) } |
            ConvertTo-Json -Depth 10 |
            Set-Content -Path (Join-Path $runRoot "planning/change-set.json")

        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.delivery.provider = "azure-devops"
        $config.delivery.dry_run = $false
        $config.delivery.create_branch = $true
        $config.delivery.commit_changes = $true
        $config.delivery.push_branch = $true
        $config.delivery.create_draft_pull_request = $true
        $config.delivery | Add-Member -NotePropertyName pull_request_draft `
            -NotePropertyValue $false -Force
        $config.delivery.azure_devops.organization_url = "https://dev.azure.com/example"
        $config.delivery.azure_devops.project = "product"
        $config.delivery.azure_devops.repository_id = "repo-id"
        Mock Invoke-RestMethod {
            param($Uri, $Method, $Body)
            if ($Uri -like "*/_apis/connectionData?*") {
                return New-TestAdoConnectionData
            }
            # Nothing has been delivered for this branch yet.
            if ($Uri -like "*/refs?*") { return [pscustomobject]@{ count = 0; value = @() } }
            if ($Uri -like "*/pullrequests?*" -and "$Method" -eq "Get") {
                return [pscustomobject]@{ count = 0; value = @() }
            }
            $global:DeliveryRequestBody = $Body
            return [pscustomobject]@{ pullRequestId = 73 }
        }
        $result = & (Join-Path $script:Root "scripts/writers/Publish-RepositoryDelivery.ps1") `
            -Config $config -RepositoryRoot $repository -RunRoot $runRoot `
            -RunId "run-delivery" -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        @($result.actions.status | Select-Object -Unique) | Should -Be @("executed")
        @($result.actions.summary) | Should -Contain "Create pull request"
        $sent = $global:DeliveryRequestBody | ConvertFrom-Json -Depth 20
        $sent.isDraft | Should -BeFalse
        $sent.PSObject.Properties.Name | Should -Not -Contain "reviewers"
        $sent.sourceRefName | Should -Match '^refs/heads/sdlc-foundry/changes-[a-f0-9]{24}$'
        $expectedBranch = $sent.sourceRefName -replace '^refs/heads/', ''
        [string](& git -C $repository branch --show-current) |
            Should -Be $expectedBranch
        [string](& git --git-dir $remote branch --list $expectedBranch) |
            Should -Match ([regex]::Escape($expectedBranch))
        [string](& git -C $repository log -1 --format=%an) |
            Should -Be $script:AdoUserName
        [string](& git -C $repository log -1 --format=%ae) |
            Should -Be $script:AdoUserEmail
        Should -Invoke -CommandName Invoke-RestMethod -Times 4 -Exactly
    }

    It "uses the authenticated PAT owner when the agent has no git identity of its own" {
        $repository = Join-Path $TestDrive "identity-repository"
        $remote = Join-Path $TestDrive "identity-remote.git"
        $runRoot = Join-Path $TestDrive "identity-run"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $runRoot "planning") -Force | Out-Null
        & git init --bare $remote | Out-Null
        & git -C $repository init | Out-Null
        Set-Content -Path (Join-Path $repository "README.md") -Value "baseline"
        & git -C $repository add README.md
        # The baseline carries an identity inline so the repository itself never
        # gains one, which is the condition a hosted build agent runs under.
        & git -c user.name="Baseline" -c user.email="baseline@example.invalid" `
            -C $repository commit -m "baseline" | Out-Null
        & git -C $repository branch -M main
        & git -C $repository remote add origin $remote
        New-Item -ItemType Directory -Path (Join-Path $repository "automation") -Force | Out-Null
        Set-Content -Path (Join-Path $repository "automation/proof.txt") -Value "approved" -NoNewline
        @{ changes = @(@{ path = "automation/proof.txt"; operation = "create"; content = "approved" }) } |
            ConvertTo-Json -Depth 10 |
            Set-Content -Path (Join-Path $runRoot "planning/change-set.json")

        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.delivery.dry_run = $false
        $config.delivery.create_branch = $true
        $config.delivery.commit_changes = $true
        $config.delivery.push_branch = $false
        $config.delivery.create_draft_pull_request = $false
        $config.delivery.azure_devops.organization_url = "https://dev.azure.com/example"
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like "*/_apis/connectionData?*") {
                return New-TestAdoConnectionData
            }
            throw "Unexpected Azure DevOps request: $Uri"
        }

        # Deny every identity git could otherwise fall back to.
        $previousGlobal = $env:GIT_CONFIG_GLOBAL
        $previousNoSystem = $env:GIT_CONFIG_NOSYSTEM
        $env:GIT_CONFIG_GLOBAL = Join-Path $TestDrive "absent-global-gitconfig"
        $env:GIT_CONFIG_NOSYSTEM = "1"
        try {
            $result = & (Join-Path $script:Root "scripts/writers/Publish-RepositoryDelivery.ps1") `
                -Config $config -RepositoryRoot $repository -RunRoot $runRoot `
                -RunId "run-identity" `
                -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
            @($result.actions.status | Select-Object -Unique) | Should -Be @("executed")
            [string](& git -C $repository log -1 --format=%an) |
                Should -Be $script:AdoUserName
            [string](& git -C $repository log -1 --format=%ae) |
                Should -Be $script:AdoUserEmail
        }
        finally {
            $env:GIT_CONFIG_GLOBAL = $previousGlobal
            $env:GIT_CONFIG_NOSYSTEM = $previousNoSystem
        }
    }

    It "collects command quality evidence and redacts observability secrets" {
        $repository = Join-Path $TestDrive "evidence-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        & git -C $repository init | Out-Null
        Set-Content -Path (Join-Path $repository "runtime.log") `
            -Value "Authorization: Bearer very-sensitive-value"
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.quality.auto_detect = $false
        $config.quality.security.secret_scan = $false
        $config.quality.security.dependency_audit = $false
        $config.quality.commands = @([pscustomobject]@{
            id = "node-version"; category = "build"; executable = "node"
            arguments = @("--version"); working_directory = "."; required = $true
        })
        $config.observability.input_paths = @("runtime.log")
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $qualityPath = Join-Path $TestDrive "quality-evidence.json"
        $quality = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
            -RunId "run-evidence" -Config $config -Policy $policy `
            -RepositoryRoot $repository -OutputPath $qualityPath
        $quality.status | Should -Be "completed"
        $quality.commands[0].exitCode | Should -Be 0

        $observabilityPath = Join-Path $TestDrive "observability-evidence.json"
        $observability = & (Join-Path $script:Root "scripts/collectors/Collect-ObservabilityEvidence.ps1") `
            -RunId "run-evidence" -Config $config -RepositoryRoot $repository `
            -OutputPath $observabilityPath
        $observability.files[0].content | Should -Match "\[REDACTED\]"
        $observability.files[0].content | Should -Not -Match "very-sensitive-value"
    }

    It "says in the evidence that detection was disabled" {
        # A narrowed gate and a gate that found nothing produce the same green
        # result. Only the evidence can tell them apart, and a comment in the
        # configuration never travels as far as the pull request.
        $repository = Join-Path $TestDrive "narrowed-gate-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        & git -C $repository init | Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.quality.auto_detect = $false
        $config.quality.security.secret_scan = $false
        $config.quality.security.dependency_audit = $false
        $config.quality.commands = @()
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $qualityPath = Join-Path $TestDrive "narrowed-gate-quality-evidence.json"
        $quality = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
            -RunId "run-narrowed-gate" -Config $config -Policy $policy `
            -RepositoryRoot $repository -OutputPath $qualityPath
        @($quality.warnings).Count | Should -BeGreaterThan 0
        (@($quality.warnings) -join " ") | Should -Match "detection is disabled"

        $config.quality.auto_detect = $true
        $enabledPath = Join-Path $TestDrive "detected-gate-quality-evidence.json"
        $detected = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
            -RunId "run-detected-gate" -Config $config -Policy $policy `
            -RepositoryRoot $repository -OutputPath $enabledPath
        (@($detected.warnings) -join " ") | Should -Not -Match "detection is disabled"
    }

    It "runs a quality command where the manifest actually is" {
        # Leg 6 of build 970346 applied a valid change set, then reported
        # "npm ci can only install with an existing package-lock.json". The lock
        # was present and valid; the gate was aimed one directory too high,
        # because the configured path is written by hand while the layout is
        # chosen by the architecture stage. Five legs of work were spent before
        # the mismatch surfaced.
        $repository = Join-Path $TestDrive "manifest-aim-repository"
        $project = Join-Path $repository "automation/CommodityPricingService.Automation"
        New-Item -ItemType Directory -Path $project -Force | Out-Null
        & git -C $repository init | Out-Null
        Set-Content -Path (Join-Path $project "package.json") -Value '{ "name": "automation" }'
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.quality.auto_detect = $false
        $config.quality.security.secret_scan = $false
        $config.quality.security.dependency_audit = $false
        $config.quality.commands = @([pscustomobject]@{
            id = "automation-install"; category = "dependency"; executable = "node"
            arguments = @("--version"); working_directory = "automation"; required = $true
        })
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root

        $quality = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
            -RunId "run-manifest-aim" -Config $config -Policy $policy `
            -RepositoryRoot $repository -OutputPath (Join-Path $TestDrive "aim-quality.json")
        $quality.commands[0].workingDirectory |
            Should -Be "automation/CommodityPricingService.Automation"
        (@($quality.warnings) -join " ") | Should -Match "ran there instead"

        # The near miss the next run is most likely to produce: the configured
        # directory names a project the blueprint decided to call something else.
        $config.quality.commands[0].working_directory = "automation/Some.Other.Name"
        $missed = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
            -RunId "run-manifest-missed" -Config $config -Policy $policy `
            -RepositoryRoot $repository -OutputPath (Join-Path $TestDrive "missed-quality.json")
        $missed.commands[0].workingDirectory |
            Should -Be "automation/CommodityPricingService.Automation"

        # Two candidates mean the gate cannot know which one it was meant to
        # check. Guessing would be worse than failing where it was told to run.
        New-Item -ItemType Directory -Path (Join-Path $repository "automation/Second.Project") -Force |
            Out-Null
        Set-Content -Path (Join-Path $repository "automation/Second.Project/package.json") `
            -Value '{ "name": "second" }'
        $config.quality.commands[0].working_directory = "automation"
        $ambiguous = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
            -RunId "run-manifest-ambiguous" -Config $config -Policy $policy `
            -RepositoryRoot $repository -OutputPath (Join-Path $TestDrive "ambiguous-quality.json")
        $ambiguous.commands[0].workingDirectory | Should -Be "automation"
        (@($ambiguous.warnings) -join " ") | Should -Not -Match "ran there instead"
    }

    It "derives the automation gate from the ecosystem that is actually installed" {
        # The gate used to be a hand-written npm install pointed at a directory,
        # in a file edited long before any architect chose an ecosystem. The
        # first blueprint that chose .NET would have run 'npm ci' against a
        # csproj and failed the run for a reason that had nothing to do with the
        # work under review.
        . (Join-Path $script:Root "scripts/Common.ps1")
        $repository = Join-Path $TestDrive "derived-gate-dotnet"
        $project = Join-Path $repository "automation/CommodityPricingService.Automation"
        New-Item -ItemType Directory -Path $project -Force | Out-Null
        Set-Content -Path (Join-Path $project "CommodityPricingService.Automation.csproj") -Value @"
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup><PackageReference Include="MSTest" Version="3.6.4" /></ItemGroup>
</Project>
"@

        $gate = Resolve-QaFoundryAutomationGate -RepositoryRoot $repository -Path "automation" `
            -EcosystemIds @("npm", "nuget")

        $gate.resolved | Should -BeTrue
        $gate.ecosystem | Should -Be "nuget"
        $gate.projectPath | Should -Be "automation/CommodityPricingService.Automation"
        @($gate.commands).Count | Should -Be 3
        foreach ($command in @($gate.commands)) {
            [string]$command.executable | Should -Be "dotnet"
            [string]$command.workingDirectory |
                Should -Be "automation/CommodityPricingService.Automation"
        }
        (@($gate.commands | Where-Object id -like "automation-install-*").arguments -join " ") |
            Should -Be "restore --locked-mode"
    }

    It "derives an npm gate from the same configuration, without the configuration changing" {
        # The point of the previous test is only half made until the same
        # untouched configuration produces a different gate for a different
        # design. Nothing here is ecosystem-specific; the manifest decides.
        . (Join-Path $script:Root "scripts/Common.ps1")
        $repository = Join-Path $TestDrive "derived-gate-npm"
        $project = Join-Path $repository "automation/ui-journeys"
        New-Item -ItemType Directory -Path $project -Force | Out-Null
        Set-Content -Path (Join-Path $project "package.json") -Value '{ "name": "ui-journeys" }'

        $gate = Resolve-QaFoundryAutomationGate -RepositoryRoot $repository -Path "automation" `
            -EcosystemIds @("npm", "nuget")

        $gate.resolved | Should -BeTrue
        $gate.ecosystem | Should -Be "npm"
        (@($gate.commands | Where-Object id -like "automation-install-*").arguments -join " ") |
            Should -Be "ci --no-audit --no-fund"
        (@($gate.commands | Where-Object id -like "automation-test-*").executable) | Should -Be "npm"
    }

    It "covers every automation project under one gate instead of refusing them" {
        # This installation asks the architecture stage for at least two
        # automation projects - an API suite and a UI suite is the ordinary
        # answer - and configures one gate over the directory that holds them.
        # The resolver used to refuse the moment it found more than one project
        # there, which made the standard shape of the programme's own output
        # unrunnable and, because the gate is required, blocked every SDLC stage
        # after it.
        . (Join-Path $script:Root "scripts/Common.ps1")
        $repository = Join-Path $TestDrive "derived-gate-two-projects"
        New-Item -ItemType Directory -Path (Join-Path $repository "automation/a") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $repository "automation/b") -Force | Out-Null
        Set-Content -Path (Join-Path $repository "automation/a/package.json") -Value '{ "name": "a" }'
        Set-Content -Path (Join-Path $repository "automation/b/package.json") -Value '{ "name": "b" }'

        $gate = Resolve-QaFoundryAutomationGate -RepositoryRoot $repository -Path "automation" `
            -EcosystemIds @("npm", "nuget")

        $gate.resolved | Should -BeTrue
        @($gate.projects).Count | Should -Be 2
        @($gate.commands).Count | Should -Be 6
        @(@($gate.commands | ForEach-Object { [string]$_.id }) | Sort-Object -Unique).Count |
            Should -Be 6
        @(@($gate.commands | ForEach-Object { [string]$_.workingDirectory }) | Sort-Object -Unique) |
            Should -Be @("automation/a", "automation/b")
        @($gate.problems).Count | Should -Be 0
    }

    It "lets a workspace at the gate's own root stand for everything beneath it" {
        # A manifest lying directly in the gate directory is a workspace or
        # solution root. Installing separately in each of its members would run
        # the tool in a directory that has no lock of its own, so the root claims
        # the whole tree.
        . (Join-Path $script:Root "scripts/Common.ps1")
        $repository = Join-Path $TestDrive "derived-gate-workspace"
        New-Item -ItemType Directory -Path (Join-Path $repository "automation/packages/api") `
            -Force | Out-Null
        Set-Content -Path (Join-Path $repository "automation/package.json") `
            -Value '{ "name": "suite", "workspaces": ["packages/*"] }'
        Set-Content -Path (Join-Path $repository "automation/packages/api/package.json") `
            -Value '{ "name": "api" }'

        $gate = Resolve-QaFoundryAutomationGate -RepositoryRoot $repository -Path "automation" `
            -EcosystemIds @("npm", "nuget")

        $gate.resolved | Should -BeTrue
        @($gate.projects).Count | Should -Be 1
        [string]$gate.projectPath | Should -Be "automation"
    }

    It "keeps two suites apart when they share a folder above them" {
        # The grouping used to be by the first path segment under the gate, and
        # that segment is not a project. Both suites of the ordinary answer -
        # automation/Suites/Api and automation/Suites/Ui - keyed on 'Suites', and
        # only the shallowest manifest of the group was ever used: the UI suite
        # was never installed, never built, never run, and the gate said the
        # automation was good.
        . (Join-Path $script:Root "scripts/Common.ps1")
        $repository = Join-Path $TestDrive "derived-gate-nested-suites"
        foreach ($suite in @("Api", "Ui")) {
            $directory = Join-Path $repository "automation/Suites/$suite"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Set-Content -Path (Join-Path $directory "$suite.csproj") -Value @"
<Project Sdk="Microsoft.NET.Sdk"></Project>
"@
        }

        $gate = Resolve-QaFoundryAutomationGate -RepositoryRoot $repository -Path "automation" `
            -EcosystemIds @("npm", "nuget")

        $gate.resolved | Should -BeTrue
        @($gate.projects).Count | Should -Be 2
        @(@($gate.projects | ForEach-Object { [string]$_.projectPath }) | Sort-Object) |
            Should -Be @("automation/Suites/Api", "automation/Suites/Ui")
        @($gate.commands).Count | Should -Be 6
        @($gate.problems).Count | Should -Be 0
    }

    It "does not let a suite in another ecosystem cancel the one beside it" {
        # The same grouping put an API suite and a UI suite written in different
        # ecosystems into one key, and then refused the pair for holding more
        # than one ecosystem. Two suites in two ecosystems is a design this
        # programme is expected to produce, not a defect in the automation.
        . (Join-Path $script:Root "scripts/Common.ps1")
        $repository = Join-Path $TestDrive "derived-gate-nested-mixed-suites"
        New-Item -ItemType Directory -Path (Join-Path $repository "automation/Suites/Api") `
            -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $repository "automation/Suites/Ui") `
            -Force | Out-Null
        Set-Content -Path (Join-Path $repository "automation/Suites/Api/Api.csproj") -Value @"
<Project Sdk="Microsoft.NET.Sdk"></Project>
"@
        Set-Content -Path (Join-Path $repository "automation/Suites/Ui/package.json") `
            -Value '{ "name": "ui" }'

        $gate = Resolve-QaFoundryAutomationGate -RepositoryRoot $repository -Path "automation" `
            -EcosystemIds @("npm", "nuget")

        $gate.resolved | Should -BeTrue
        @($gate.projects).Count | Should -Be 2
        @(@($gate.projects | ForEach-Object { [string]$_.ecosystem }) | Sort-Object) |
            Should -Be @("npm", "nuget")
        @($gate.problems).Count | Should -Be 0
    }

    It "does not let a root manifest swallow a project it never declared" {
        # A manifest in the gate's own directory used to claim the whole tree on
        # the strength of where it sits. An npm root that lists no workspaces
        # installs nothing for the suite below it, so treating it as covered
        # means that suite is never installed and never run - and the gate still
        # passes. What the root claims is now read out of the root.
        . (Join-Path $script:Root "scripts/Common.ps1")
        $repository = Join-Path $TestDrive "derived-gate-undeclared"
        New-Item -ItemType Directory -Path (Join-Path $repository "automation/packages/api") `
            -Force | Out-Null
        Set-Content -Path (Join-Path $repository "automation/package.json") `
            -Value '{ "name": "suite" }'
        Set-Content -Path (Join-Path $repository "automation/packages/api/package.json") `
            -Value '{ "name": "api" }'

        $gate = Resolve-QaFoundryAutomationGate -RepositoryRoot $repository -Path "automation" `
            -EcosystemIds @("npm", "nuget")

        $gate.resolved | Should -BeTrue
        @($gate.projects).Count | Should -Be 2
        @(@($gate.projects | ForEach-Object { [string]$_.projectPath }) | Sort-Object) |
            Should -Be @("automation", "automation/packages/api")
    }

    It "reads a Yarn-shaped workspace list the same way as npm's own" {
        # 'workspaces: { packages: [...] }' is the other spelling npm accepts. A
        # reader that only understands the array would treat a declared member as
        # its own project, expect a lock beside it, and fail a workspace that is
        # correct.
        . (Join-Path $script:Root "scripts/Common.ps1")
        $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem "npm"
        $manifest = Join-Path $TestDrive "yarn-shaped-package.json"
        Set-Content -Path $manifest -Value '{ "workspaces": { "packages": ["suites/*"] } }'
        @(Get-QaFoundryWorkspaceMembers -Adapter $adapter -ManifestPath $manifest) |
            Should -Be @("suites/*")

        $plain = Join-Path $TestDrive "plain-package.json"
        Set-Content -Path $plain -Value '{ "name": "solo" }'
        @(Get-QaFoundryWorkspaceMembers -Adapter $adapter -ManifestPath $plain).Count |
            Should -Be 0
    }

    It "reads the modules an aggregator POM builds" {
        # Maven's aggregator does build what it lists, so those modules are
        # covered by a build at the root. A POM listing nothing covers nothing.
        . (Join-Path $script:Root "scripts/Common.ps1")
        $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem "maven"
        $aggregator = Join-Path $TestDrive "aggregator-pom.xml"
        Set-Content -Path $aggregator -Value @"
<project><modules><module>api</module><module>ui</module></modules></project>
"@
        @(Get-QaFoundryWorkspaceMembers -Adapter $adapter -ManifestPath $aggregator) |
            Should -Be @("api", "ui")

        $leaf = Join-Path $TestDrive "leaf-pom.xml"
        Set-Content -Path $leaf -Value "<project></project>"
        @(Get-QaFoundryWorkspaceMembers -Adapter $adapter -ManifestPath $leaf).Count | Should -Be 0
    }

    It "refuses one project written in two ecosystems without losing the others" {
        # Two manifests from different ecosystems inside a single project is the
        # one case that stays a refusal: nothing on disk says which one the suite
        # is written in. It must not take the projects beside it down with it,
        # and it must still be reported, because a required gate that produced no
        # result at all is a required gate that passed by not being there.
        . (Join-Path $script:Root "scripts/Common.ps1")
        $repository = Join-Path $TestDrive "derived-gate-mixed"
        New-Item -ItemType Directory -Path (Join-Path $repository "automation/mixed") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $repository "automation/clean") -Force | Out-Null
        Set-Content -Path (Join-Path $repository "automation/mixed/package.json") -Value '{ "name": "m" }'
        Set-Content -Path (Join-Path $repository "automation/mixed/Mixed.csproj") -Value @"
<Project Sdk="Microsoft.NET.Sdk"></Project>
"@
        Set-Content -Path (Join-Path $repository "automation/clean/package.json") -Value '{ "name": "c" }'

        $gate = Resolve-QaFoundryAutomationGate -RepositoryRoot $repository -Path "automation" `
            -EcosystemIds @("npm", "nuget")

        $gate.resolved | Should -BeTrue
        @($gate.projects).Count | Should -Be 1
        [string]$gate.projects[0].projectPath | Should -Be "automation/clean"
        @($gate.problems).Count | Should -Be 1
        [string]$gate.problems[0].path | Should -Be "automation/mixed"
        [string]$gate.problems[0].reason | Should -Match "more than one ecosystem"
    }

    It "says in the evidence when an automation gate found nothing to run" {        # On the run that generates the automation there is nothing at the path
        # when this is first read, and a gate that is absent is not a gate that
        # passed. What must never happen is for it to be absent in silence.
        $repository = Join-Path $TestDrive "gate-nothing-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        & git -C $repository init | Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.quality.auto_detect = $false
        $config.quality.security.secret_scan = $false
        $config.quality.security.dependency_audit = $false
        $config.quality.commands = @()
        $config.quality | Add-Member -NotePropertyName "automation_gates" -NotePropertyValue @(
            [pscustomobject]@{ path = "automation"; required = $false }
        )
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root

        $quality = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
            -RunId "run-gate-nothing" -Config $config -Policy $policy `
            -RepositoryRoot $repository -OutputPath (Join-Path $TestDrive "gate-nothing-quality.json")

        # Not required, so it does not stop the run - but it is still written
        # down as a gate that produced nothing rather than left out.
        @($quality.commands).Count | Should -Be 1
        [string]@($quality.commands)[0].status | Should -Be "blocked"
        (@($quality.warnings) -join " ") | Should -Match "No quality gate ran for 'automation'"
    }

    Context "when a test command comes back green having run nothing" {
        # The failure this is about: the quality gate accepted a test command by
        # its exit code alone. A runner exits zero when every test passed and
        # when it found nothing to run, so deleting the tests, or skipping all of
        # them, produced a green gate. The rule that catches this existed - in
        # the bootstrap stage only, which is to say it stopped applying at
        # exactly the point the code started changing.
        BeforeAll {
            function script:New-EmptySuiteConfig {
                param([string[]]$SummaryLines)

                $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
                $config.quality.auto_detect = $false
                $config.quality.security.secret_scan = $false
                $config.quality.security.dependency_audit = $false
                $config.quality.fail_on_required_failure = $false
                $script = (@($SummaryLines) | ForEach-Object { "console.log('$_');" }) -join ""
                $config.quality.commands = @([pscustomobject]@{
                    id = "suite"; category = "test"; executable = "node"
                    arguments = @("-e", $script); working_directory = "."; required = $true
                    ecosystem = "npm"
                })
                return $config
            }
        }

        It "fails a suite that reported no tests at all" {
            $repository = Join-Path $TestDrive "empty-suite-none"
            New-Item -ItemType Directory -Path $repository -Force | Out-Null
            & git -C $repository init | Out-Null
            $config = script:New-EmptySuiteConfig -SummaryLines @("# pass 0", "# fail 0")
            $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root

            $quality = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
                -RunId "run-empty-suite" -Config $config -Policy $policy `
                -RepositoryRoot $repository -OutputPath (Join-Path $TestDrive "empty-suite.json")

            $result = @($quality.commands | Where-Object id -eq "suite")[0]
            [int]$result.exitCode | Should -Be 0
            [string]$result.status | Should -Be "failed"
            [string]$result.standardError | Should -Match "discovered no tests"
            (@($quality.warnings) -join " ") | Should -Match "discovered no tests"
        }

        It "fails a suite whose every test was skipped" {
            $repository = Join-Path $TestDrive "empty-suite-skipped"
            New-Item -ItemType Directory -Path $repository -Force | Out-Null
            & git -C $repository init | Out-Null
            $config = script:New-EmptySuiteConfig -SummaryLines @(
                "# pass 0", "# fail 0", "# skipped 4")
            $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root

            $quality = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
                -RunId "run-skipped-suite" -Config $config -Policy $policy `
                -RepositoryRoot $repository -OutputPath (Join-Path $TestDrive "skipped-suite.json")

            $result = @($quality.commands | Where-Object id -eq "suite")[0]
            [int]$result.exitCode | Should -Be 0
            [string]$result.status | Should -Be "failed"
            [string]$result.standardError | Should -Match "were skipped"
        }

        It "leaves a suite that actually ran exactly as it found it" {
            $repository = Join-Path $TestDrive "empty-suite-real"
            New-Item -ItemType Directory -Path $repository -Force | Out-Null
            & git -C $repository init | Out-Null
            $config = script:New-EmptySuiteConfig -SummaryLines @("# pass 7", "# fail 0")
            $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root

            $quality = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
                -RunId "run-real-suite" -Config $config -Policy $policy `
                -RepositoryRoot $repository -OutputPath (Join-Path $TestDrive "real-suite.json")

            $result = @($quality.commands | Where-Object id -eq "suite")[0]
            [string]$result.status | Should -Be "completed"
            (@($quality.warnings) -join " ") | Should -Not -Match "proves nothing"
        }

        It "judges a command by its exit code when nothing says which runner it is" {
            # A hand-written command that names no ecosystem cannot be read this
            # way, and inventing a parser for it would fail honest suites. It is
            # left alone on purpose - which is why every command this runtime
            # derives itself carries its ecosystem.
            $repository = Join-Path $TestDrive "empty-suite-unknown"
            New-Item -ItemType Directory -Path $repository -Force | Out-Null
            & git -C $repository init | Out-Null
            $config = script:New-EmptySuiteConfig -SummaryLines @("# pass 0", "# fail 0")
            $config.quality.commands[0].PSObject.Properties.Remove("ecosystem")
            $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root

            $quality = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
                -RunId "run-unknown-suite" -Config $config -Policy $policy `
                -RepositoryRoot $repository -OutputPath (Join-Path $TestDrive "unknown-suite.json")

            $result = @($quality.commands | Where-Object id -eq "suite")[0]
            [string]$result.status | Should -Be "completed"
        }
    }

    It "runs the derived gate rather than a stale command carrying the same name" {
        # The collector is what has to change, not only the helper: a derived
        # command that never reached the runner would leave the pinned one in
        # charge and nothing about the evidence would say so.
        $repository = Join-Path $TestDrive "gate-derived-run"
        $project = Join-Path $repository "automation/ui-journeys"
        New-Item -ItemType Directory -Path $project -Force | Out-Null
        & git -C $repository init | Out-Null
        Set-Content -Path (Join-Path $project "package.json") -Value '{ "name": "ui-journeys" }'
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.quality.auto_detect = $false
        $config.quality.security.secret_scan = $false
        $config.quality.security.dependency_audit = $false
        # The stale pin the finding was about, kept here deliberately: a wrong
        # ecosystem aimed at the wrong directory, under the id the gate uses.
        $config.quality.commands = @([pscustomobject]@{
            id = "automation-install"; category = "dependency"; executable = "dotnet"
            arguments = @("restore"); working_directory = "automation/Wrong.Name"; required = $false
        })
        $config.quality | Add-Member -NotePropertyName "automation_gates" -NotePropertyValue @(
            [pscustomobject]@{ path = "automation"; required = $false }
        )
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root

        $quality = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
            -RunId "run-gate-derived" -Config $config -Policy $policy `
            -RepositoryRoot $repository -OutputPath (Join-Path $TestDrive "gate-derived-quality.json")

        $install = @($quality.commands | Where-Object id -like "automation-install-*")[0]
        [string]$install.command | Should -Match "^npm ci"
        [string]$install.workingDirectory | Should -Be "automation/ui-journeys"
        # The stale pin carried the id this gate used to answer to, so it is
        # superseded rather than run in addition to the derived one.
        @($quality.commands | Where-Object id -eq "automation-install") | Should -BeNullOrEmpty
        @($quality.commands).Count | Should -Be 3
    }

    It "gives each automation gate its own commands instead of running only the first" {
        # Two gates produced the same three ids, and the collector ignores an id
        # it has already seen. The second project was never installed, built or
        # tested, and the evidence looked like agreement rather than absence.
        $repository = Join-Path $TestDrive "gate-two-projects"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        & git -C $repository init | Out-Null
        foreach ($name in @("ui-journeys", "api-journeys")) {
            $project = Join-Path $repository "automation/$name"
            New-Item -ItemType Directory -Path $project -Force | Out-Null
            Set-Content -Path (Join-Path $project "package.json") -Value "{ `"name`": `"$name`" }"
        }
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.quality.auto_detect = $false
        $config.quality.security.secret_scan = $false
        $config.quality.security.dependency_audit = $false
        $config.quality.commands = @()
        $config.quality | Add-Member -NotePropertyName "automation_gates" -NotePropertyValue @(
            [pscustomobject]@{ path = "automation/ui-journeys"; required = $false },
            [pscustomobject]@{ path = "automation/api-journeys"; required = $false }
        )
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root

        $quality = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
            -RunId "run-gate-two" -Config $config -Policy $policy `
            -RepositoryRoot $repository -OutputPath (Join-Path $TestDrive "gate-two-quality.json")

        @($quality.commands).Count | Should -Be 6
        @(@($quality.commands | ForEach-Object { [string]$_.id }) | Sort-Object -Unique).Count |
            Should -Be 6
        @(@($quality.commands | ForEach-Object { [string]$_.workingDirectory }) |
            Sort-Object -Unique) | Should -Be @("automation/api-journeys", "automation/ui-journeys")

        # Every command result carries the directory it ran in, and the schema
        # forbade exactly that field - so any run with a quality command wrote an
        # artifact that failed its own contract.
        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath (Join-Path $TestDrive "gate-two-quality.json") `
                -SchemaPath (Join-Path $script:Root "schemas/runtime/quality-evidence.schema.json") `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Not -Throw
    }

    It "tells two gates apart whose paths read the same once punctuation is dropped" {
        # The readable half of a gate's id replaces every run of punctuation with
        # a dash, so 'automation/a-b' and 'automation/a/b' read the same. Two
        # projects sharing one id means the collector runs only the first, and
        # the second is never installed, built or tested.
        . (Join-Path $script:Root "scripts/Common.ps1")
        $repository = Join-Path $TestDrive "gate-slug-collision"
        foreach ($relative in @("automation/a-b", "automation/a/b")) {
            $project = Join-Path $repository $relative
            New-Item -ItemType Directory -Path $project -Force | Out-Null
            Set-Content -Path (Join-Path $project "package.json") -Value '{ "name": "p" }'
        }

        $first = Resolve-QaFoundryAutomationGate -RepositoryRoot $repository `
            -Path "automation/a-b" -EcosystemIds @("npm", "nuget")
        $second = Resolve-QaFoundryAutomationGate -RepositoryRoot $repository `
            -Path "automation/a/b" -EcosystemIds @("npm", "nuget")

        $first.resolved | Should -BeTrue
        $second.resolved | Should -BeTrue
        $firstIds = @($first.commands | ForEach-Object { [string]$_.id })
        $secondIds = @($second.commands | ForEach-Object { [string]$_.id })
        foreach ($id in $firstIds) { $secondIds | Should -Not -Contain $id }
        # The path is still readable in the id; only the tail tells them apart.
        $firstIds[0] | Should -BeLike "automation-install-automation-a-b-*"
    }

    It "refuses two gates that would run under one id rather than dropping one" {
        # If two gates ever do resolve to the same commands, the collector's
        # habit of ignoring an id it has already seen would silently drop one.
        # A configured gate that does not run is not a gate that passed.
        $repository = Join-Path $TestDrive "gate-duplicate-path"
        $project = Join-Path $repository "automation/ui-journeys"
        New-Item -ItemType Directory -Path $project -Force | Out-Null
        & git -C $repository init | Out-Null
        Set-Content -Path (Join-Path $project "package.json") -Value '{ "name": "ui" }'
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.quality.auto_detect = $false
        $config.quality.security.secret_scan = $false
        $config.quality.security.dependency_audit = $false
        $config.quality.commands = @()
        $config.quality | Add-Member -NotePropertyName "automation_gates" -NotePropertyValue @(
            [pscustomobject]@{ path = "automation/ui-journeys"; required = $false },
            [pscustomobject]@{ path = "automation/ui-journeys"; required = $true }
        )
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root

        {
            & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
                -RunId "run-gate-duplicate" -Config $config -Policy $policy `
                -RepositoryRoot $repository `
                -OutputPath (Join-Path $TestDrive "gate-duplicate-quality.json")
        } | Should -Throw "*produced the same command id*"
    }

    It "fails a required gate that could not be derived instead of passing it in silence" {
        # A required gate that resolved to nothing produced no command result at
        # all, and the run's required-failure count is computed from results. The
        # gate that was supposed to stop the run was the one thing that could not.
        $repository = Join-Path $TestDrive "gate-required-unresolved"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        & git -C $repository init | Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.quality.auto_detect = $false
        $config.quality.security.secret_scan = $false
        $config.quality.security.dependency_audit = $false
        $config.quality.commands = @()
        $config.quality | Add-Member -NotePropertyName "automation_gates" -NotePropertyValue @(
            [pscustomobject]@{ path = "automation"; required = $true }
        )
        $config.quality.fail_on_required_failure = $false
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root

        $quality = & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
            -RunId "run-gate-required" -Config $config -Policy $policy `
            -RepositoryRoot $repository -OutputPath (Join-Path $TestDrive "gate-required-quality.json")

        $blocked = @($quality.commands | Where-Object { [string]$_.status -eq "blocked" })
        $blocked.Count | Should -Be 1
        [string]$blocked[0].id | Should -Match "^automation-gate-"
        [bool]$blocked[0].required | Should -BeTrue
        $quality.summary.requiredFailureCount | Should -Be 1
        [string]$quality.status | Should -Be "failed"

        # And with the ordinary setting the run stops there, which is the whole
        # point of calling the gate required.
        $config.quality.fail_on_required_failure = $true
        {
            & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
                -RunId "run-gate-required-stop" -Config $config -Policy $policy `
                -RepositoryRoot $repository `
                -OutputPath (Join-Path $TestDrive "gate-required-stop-quality.json")
        } | Should -Throw "*automation-gate-automation*"
    }

    It "scans a repository dot file instead of dying on it" {        # Build 470 finished all eleven stages, applied its change set and then
        # crashed on the repository's own .dockerignore. PowerShell marks a
        # dot-prefixed file hidden on Linux and the provider withholds a hidden
        # item unless it is forced, while Test-Path still reports it present.
        $repository = Join-Path $TestDrive "hidden-file-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        & git -C $repository init | Out-Null
        $dotFile = Join-Path $repository ".dockerignore"
        Set-Content -LiteralPath $dotFile -Value @(
            "node_modules",
            'api_key = "0123456789abcdef"'
        ) -Encoding utf8
        # Linux hides a dot file by its name alone; Windows needs the attribute
        # set for the same provider path to be exercised here.
        if ($IsWindows) {
            (Get-Item -LiteralPath $dotFile -Force).Attributes = "Hidden"
        }
        & git -C $repository add --all | Out-Null

        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.quality.auto_detect = $false
        $config.quality.commands = @()
        $config.quality.security.secret_scan = $true
        $config.quality.security.dependency_audit = $false
        $config.observability.input_paths = @()
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $qualityPath = Join-Path $TestDrive "hidden-file-quality-evidence.json"

        # Finding the planted secret is what proves the file was read: a scan
        # that silently skips every dot file never sees the files secrets are
        # usually left in. Reaching this refusal at all proves it was not the
        # crash that stopped the collector.
        {
            & (Join-Path $script:Root "scripts/collectors/Collect-QualityEvidence.ps1") `
                -RunId "run-hidden-file" -Config $config -Policy $policy `
                -RepositoryRoot $repository -OutputPath $qualityPath
        } | Should -Throw "*Secret scan found 1 potential secret(s)*"

        $evidence = Get-Content -LiteralPath $qualityPath -Raw | ConvertFrom-Json -Depth 100
        @($evidence.secretFindings | Where-Object { $_.path -eq ".dockerignore" }).Count |
            Should -Be 1
    }

    It "emits schema-valid action entries for evidence collectors" {
        $repository = Join-Path $TestDrive "collector-action-repository"
        $runRoot = Join-Path $TestDrive "collector-action-run"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.quality.auto_detect = $false
        $config.quality.commands = @()
        $config.quality.security.secret_scan = $false
        $config.quality.security.dependency_audit = $false
        $config.observability.input_paths = @()
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $cases = @(
            [pscustomobject]@{
                Handler = "quality_suite"
                Type = "evidence.quality"
            },
            [pscustomobject]@{
                Handler = "collect_observability"
                Type = "evidence.observability"
            }
        )

        foreach ($case in $cases) {
            $stage = [pscustomobject]@{
                id = "$($case.Handler)-stage"
                action = [pscustomobject]@{
                    handler = $case.Handler
                    output = "action-result.json"
                }
            }
            $outputPath = Join-Path $runRoot "$($case.Handler)/action-result.json"
            $result = & (Join-Path $script:Root "scripts/Invoke-DeterministicAction.ps1") `
                -Stage $stage `
                -Config $config `
                -Policy $policy `
                -RunRoot $runRoot `
                -RepositoryRoot $repository `
                -RunId "run-collector-actions" `
                -OutputPath $outputPath

            $result.actions[0].type | Should -Be $case.Type
            $result.status | Should -Be "no_action_needed"
        }
    }
}

Describe "State and schema primitives" {
    It "persists and reloads workflow state" {
        $path = Join-Path $TestDrive "workflow-state.json"
        $state = [pscustomobject]@{
            updatedAt = ""
            status = "running"
            stages = @()
        }
        & (Join-Path $script:Root "scripts/Save-WorkflowState.ps1") `
            -State $state `
            -Path $path
        $loaded = & (Join-Path $script:Root "scripts/Load-WorkflowState.ps1") -Path $path
        $loaded.status | Should -Be "running"
        $loaded.updatedAt | Should -Not -BeNullOrEmpty
    }

    It "accepts a valid schema artifact and rejects invalid status values" {
        $schema = Join-Path $script:Root "schemas/discovery/repository-discovery.schema.json"
        $valid = Join-Path $script:Root "tests/fixtures/mock-responses/repository-discovery.json"
        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $valid `
                -SchemaPath $schema `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Not -Throw

        $invalid = Join-Path $script:Root "tests/fixtures/invalid-agent-result.json"
        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $invalid `
                -SchemaPath $schema `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Throw
    }

    It "extracts bounded text from an explicitly supplied DOCX document" {
        $repository = Join-Path $TestDrive "document-repository"
        $source = Join-Path $TestDrive "docx-source"
        New-Item -ItemType Directory -Path (Join-Path $source "word") -Force | Out-Null
        Set-Content -Path (Join-Path $source "word/document.xml") -Value @"
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body><w:p><w:r><w:t>Evidence from DOCX</w:t></w:r></w:p></w:body>
</w:document>
"@
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $documentPath = Join-Path $repository "requirements.docx"
        [IO.Compression.ZipFile]::CreateFromDirectory($source, $documentPath)
        $outputPath = Join-Path $TestDrive "document-context.json"
        $context = & (Join-Path $script:Root "scripts/Collect-RepositoryContext.ps1") `
            -RepositoryRoot $repository -OutputPath $outputPath -RunId "run-docx" `
            -DocumentationPaths @($documentPath) -AllowedReadPaths @(".") `
            -MaxFileBytes 131072 -MaxTotalBytes 1048576
        $document = @($context.analysisInputs | Where-Object path -eq "requirements.docx")[0]
        $document.included | Should -BeTrue
        $document.content | Should -Match "Evidence from DOCX"
    }

    It "sends the shape of a configuration file to a model, not the values in it" {
        # Excluding files whose names look like secrets was never the whole job.
        # An ordinary appsettings.json is not named like a secret, is exactly
        # what an agent needs in order to understand a service, and carries a
        # connection string with a password in it. The secret scan that fails a
        # build runs long after this content has been sent to a provider.
        $repository = Join-Path $TestDrive "redaction-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $password = "P" + ("a" * 14) + "9"
        $apiKey = "sk-live-" + ("0123456789" * 2)
        Set-Content -LiteralPath (Join-Path $repository "appsettings.json") -Value @"
{
  "ConnectionStrings": {
    "Sql": "Server=tcp:app.database.windows.net;Database=app;User ID=svc;Password=$password;Encrypt=true"
  },
  "Integrations": { "ApiKey": "$apiKey" },
  "Logging": { "LogLevel": { "Default": "Information" } },
  "Timeout": 30
}
"@
        $outputPath = Join-Path $TestDrive "redaction-context.json"
        $context = & (Join-Path $script:Root "scripts/Collect-RepositoryContext.ps1") `
            -RepositoryRoot $repository -OutputPath $outputPath -RunId "run-redaction" `
            -AllowedReadPaths @(".") -MaxFileBytes 131072 -MaxTotalBytes 1048576

        $input = @($context.analysisInputs | Where-Object path -eq "appsettings.json")[0]
        $input.included | Should -BeTrue
        # Nothing of the value survives, in the artifact or on disk.
        $input.content | Should -Not -Match ([regex]::Escape($password))
        $input.content | Should -Not -Match ([regex]::Escape($apiKey))
        (Get-Content -LiteralPath $outputPath -Raw) | Should -Not -Match ([regex]::Escape($password))
        (Get-Content -LiteralPath $outputPath -Raw) | Should -Not -Match ([regex]::Escape($apiKey))
        # The shape does survive, because an agent that cannot see which
        # settings exist cannot reason about the service at all.
        $input.content | Should -Match "ConnectionStrings"
        $input.content | Should -Match "Server=tcp:app\.database\.windows\.net"
        $input.content | Should -Match '"Timeout": 30'
        $input.content | Should -Match "redacted"
        # And the run can tell a file that was cleaned from one that never held
        # anything.
        @($input.redactions) | Should -Contain "connection-string-secret"
        @($input.redactions) | Should -Contain "generic-secret-assignment"
    }

    It "leaves a file alone when there is nothing in it to hide" {
        $repository = Join-Path $TestDrive "clean-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        $original = @(
            "# Service",
            "",
            "Set the API_KEY environment variable before running.",
            'const port = process.env.PORT ?? 8080;'
        ) -join "`n"
        Set-Content -LiteralPath (Join-Path $repository "README.md") -Value $original
        $context = & (Join-Path $script:Root "scripts/Collect-RepositoryContext.ps1") `
            -RepositoryRoot $repository `
            -OutputPath (Join-Path $TestDrive "clean-context.json") -RunId "run-clean" `
            -AllowedReadPaths @(".") -MaxFileBytes 131072 -MaxTotalBytes 1048576

        $input = @($context.analysisInputs | Where-Object path -eq "README.md")[0]
        # Naming an environment variable is how documentation is supposed to
        # talk about a secret. A redactor that eats that teaches everyone to
        # turn it off.
        @($input.redactions).Count | Should -Be 0
        $input.content | Should -Match "API_KEY environment variable"
        $input.content | Should -Not -Match "redacted"
    }

    It "spends the content budget across components instead of on whichever sorts first" {
        # A backend whose projects sort before the user interface once took the
        # whole budget, and the agent asked to write interface tests was handed
        # 137 paths with no content behind any of them. It reported the control
        # names as unknowable and stopped the run, correctly: nothing it had
        # been given named them.
        $repository = Join-Path $TestDrive "two-component-repository"
        $backend = Join-Path $repository "CommodityPricingService.Api"
        $frontend = Join-Path $repository "pricing-service-ui"
        New-Item -ItemType Directory -Path $backend -Force | Out-Null
        New-Item -ItemType Directory -Path $frontend -Force | Out-Null
        $filler = "x" * 900
        foreach ($index in 1..10) {
            Set-Content -LiteralPath (Join-Path $backend "Controller$index.cs") `
                -Value "// backend $index`n$filler"
            Set-Content -LiteralPath (Join-Path $frontend "Panel$index.tsx") `
                -Value "// aria-label=`"quote-panel-$index`"`n$filler"
        }
        # Room for roughly half of them, so ordering decides who is left out.
        $context = & (Join-Path $script:Root "scripts/Collect-RepositoryContext.ps1") `
            -RepositoryRoot $repository `
            -OutputPath (Join-Path $TestDrive "two-component-context.json") `
            -RunId "run-two-component" -AllowedReadPaths @(".") `
            -MaxFileBytes 131072 -MaxTotalBytes 9000

        $included = @($context.analysisInputs | Where-Object { $_.included })
        $frontendIncluded = @($included | Where-Object { $_.path -like "pricing-service-ui/*" })
        $backendIncluded = @($included | Where-Object { $_.path -like "CommodityPricingService.Api/*" })
        $frontendIncluded.Count | Should -BeGreaterThan 0
        $backendIncluded.Count | Should -BeGreaterThan 0
        # Neither component is starved while the other is fully served.
        [math]::Abs($frontendIncluded.Count - $backendIncluded.Count) | Should -BeLessOrEqual 1
        # The content is really there, not just the path.
        $frontendIncluded[0].content | Should -Match "aria-label"
        # Every file still appears in the index, budget or no budget.
        @($context.files | Where-Object { $_.path -like "pricing-service-ui/*" }).Count |
            Should -Be 10
    }

    It "tells an agent that the file index points at files it can open" {
        $repository = Join-Path $TestDrive "index-note-repository"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $repository "README.md") -Value "# Service"
        $context = & (Join-Path $script:Root "scripts/Collect-RepositoryContext.ps1") `
            -RepositoryRoot $repository `
            -OutputPath (Join-Path $TestDrive "index-note-context.json") `
            -RunId "run-index-note" -AllowedReadPaths @(".") `
            -MaxFileBytes 131072 -MaxTotalBytes 1048576

        # An agent that believes the index is all it was given records an
        # unknown instead of opening the file that answers the question.
        (@($context.notes) -join " ") | Should -Match "index"
        (@($context.notes) -join " ") | Should -Match "repositoryRoot"
        $context.repositoryRoot | Should -Not -BeNullOrEmpty
    }
}

Describe "Bounded provider retries" {
    It "stops after the configured retry bound" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/invalid-provider.mjs"
        $config.runtime.agent_schema_retries = 1
        $output = Join-Path $TestDrive "retry/result.json"
        {
            & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
                -AgentId "repository-discovery" `
                -StageId "discovery" `
                -RunId "run-retry-test" `
                -PromptPath (Join-Path $script:Root "prompts/discovery/repository-discovery.md") `
                -ContextPaths @() `
                -OutputPath $output `
                -SchemaPath (Join-Path $script:Root "schemas/discovery/repository-discovery.schema.json") `
                -Config $config
        } | Should -Throw "*after 2 attempt(s)*"
        (Get-ChildItem -Path (Split-Path $output -Parent) -Filter "*.raw.txt").Count |
            Should -Be 2
    }

    It "accepts a review whose details object is empty" {
        # Build 460: architecture-critic approved the blueprint and returned
        # "details": {}. Reading the property names of that object threw under
        # Set-StrictMode, the catch deleted the approval as though the schema had
        # rejected it, and three rounds of unusable feedback crashed the leg.
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/empty-details-review-provider.mjs"
        $output = Join-Path $TestDrive "empty-details/architecture-review.json"
        $result = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "architecture-critic" `
            -StageId "architecture" `
            -RunId "run-empty-details-test" `
            -PromptPath (Join-Path $script:Root "prompts/architecture/architecture-critic.md") `
            -ContextPaths @() `
            -OutputPath $output `
            -SchemaPath (Join-Path $script:Root "schemas/architecture/architecture-review.schema.json") `
            -Config $config

        $result.decision | Should -Be "approved"
        Test-Path -LiteralPath $output | Should -BeTrue
        @(Get-ChildItem -Path (Split-Path $output -Parent) -Filter "*.raw.txt").Count |
            Should -Be 1
    }
}

Describe "Provider faults that clear on their own" {
    It "tells a fault that will pass from one that will not" {
        Test-QaFoundryProviderTransientFailure -Message (
            "Copilot CLI exited with 1: Execution failed: 400 The resource you requested " +
            "was not found. (Request ID: 9083:3F6DE9)") | Should -BeTrue
        Test-QaFoundryProviderTransientFailure -Message "socket hang up" | Should -BeTrue
        Test-QaFoundryProviderTransientFailure -Message "Execution failed: 503 upstream" |
            Should -BeTrue
        Test-QaFoundryProviderTransientFailure -Message "the model returned invalid JSON" |
            Should -BeFalse
        Test-QaFoundryProviderTransientFailure -Message "Unsupported AI provider: nonsense" |
            Should -BeFalse
        # A verdict, not weather: asking again gets the same answer.
        Test-QaFoundryProviderTransientFailure -Message "Execution failed: 401 Unauthorized" |
            Should -BeFalse
        Test-QaFoundryProviderTransientFailure -Message "Execution failed: 403 Forbidden" |
            Should -BeFalse
        Test-QaFoundryProviderTransientFailure -Message "Execution failed: 422 Unprocessable" |
            Should -BeFalse
        Test-QaFoundryProviderTransientFailure -Message "Execution failed: 429 Too Many Requests" |
            Should -BeTrue
        Test-QaFoundryProviderTransientFailure -Message "" | Should -BeFalse
        Test-QaFoundryProviderTransientFailure -Message $null | Should -BeFalse
    }

    It "asks again when the provider refused the call, and keeps the answer" {
        # Build 474 reached the eleventh stage of eleven and then lost two hours
        # of completed work because one review call came back 400 while the same
        # profile answered eight other calls in the same run.
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/faltering-provider.mjs"
        $config.runtime.agent_schema_retries = 1
        $output = Join-Path $TestDrive "faltering/discovery.json"

        $result = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "repository-discovery" `
            -StageId "discovery" `
            -RunId "run-faltering-provider-test" `
            -PromptPath (Join-Path $script:Root "prompts/discovery/repository-discovery.md") `
            -ContextPaths @() `
            -OutputPath $output `
            -SchemaPath (Join-Path $script:Root "schemas/discovery/repository-discovery.schema.json") `
            -Config $config

        $result.status | Should -Be "completed"
        Test-Path -LiteralPath $output | Should -BeTrue
    }

    It "still stops when the provider is broken rather than unlucky" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/missing-provider-fixture.mjs"
        $config.runtime.agent_schema_retries = 1
        $output = Join-Path $TestDrive "broken/discovery.json"

        {
            & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
                -AgentId "repository-discovery" `
                -StageId "discovery" `
                -RunId "run-broken-provider-test" `
                -PromptPath (Join-Path $script:Root "prompts/discovery/repository-discovery.md") `
                -ContextPaths @() `
                -OutputPath $output `
                -SchemaPath (Join-Path $script:Root "schemas/discovery/repository-discovery.schema.json") `
                -Config $config
        } | Should -Throw
        @(Get-ChildItem -Path (Split-Path $output -Parent) -Filter "*.raw.txt" -ErrorAction SilentlyContinue).Count |
            Should -Be 0
    }
}

Describe "A blocked stage stops the run without faking a crash" {
    It "returns the blocked run instead of throwing" {
        # Build 462: bootstrap-change-generator refused to author lock files it
        # could not honestly produce and returned 'blocked'. The runtime turned
        # that judgement into an exception, so the leg reported a crash and sent
        # whoever read the log looking for a defect that was not there.
        $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/blocked-change-set-provider.mjs"
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $workflow = New-BatchingResumeWorkflow -Workflow $workflow
        $runRoot = Join-Path $TestDrive "blocked-run"
        New-BatchingWorkflowState -RunRoot $runRoot -RunId "run-blocked-change-set-test" `
            -Workflow $workflow

        $state = & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
            -Workflow $workflow `
            -Config $config `
            -Policy $policy `
            -RepositoryRoot $script:Root `
            -RunRoot $runRoot `
            -RunId "run-blocked-change-set-test" `
            -Resume

        $state.status | Should -Be "blocked"
        $persisted = Get-Content -Path (Join-Path $runRoot "workflow-state.json") -Raw |
            ConvertFrom-Json -Depth 100
        $persisted.status | Should -Be "blocked"
        $persisted.currentStage | Should -Be "bootstrap-change-generation"
    }

    It "keeps a failed stage an exception so a defect still stops the relay" {
        $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/invalid-provider.mjs"
        $config.runtime.agent_schema_retries = 0
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $workflow = New-BatchingResumeWorkflow -Workflow $workflow
        $runRoot = Join-Path $TestDrive "failed-run"
        New-BatchingWorkflowState -RunRoot $runRoot -RunId "run-failed-change-set-test" `
            -Workflow $workflow

        {
            & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                -Workflow $workflow `
                -Config $config `
                -Policy $policy `
                -RepositoryRoot $script:Root `
                -RunRoot $runRoot `
                -RunId "run-failed-change-set-test" `
                -Resume
        } | Should -Throw
        $persisted = Get-Content -Path (Join-Path $runRoot "workflow-state.json") -Raw |
            ConvertFrom-Json -Depth 100
        $persisted.status | Should -Be "failed"
    }
}

Describe "Secret isolation" {
    It "loads only explicitly mapped secret keys" {
        $secretPath = Join-Path $TestDrive "provider.secrets.env"
        Set-Content -Path $secretPath -Value @(
            "SOURCE_API_KEY=real-test-value",
            "UNMAPPED_VALUE=must-not-be-exported"
        )
        $secretConfig = [pscustomobject]@{
            source = "file"
            path = $secretPath
            format = "env"
            allow_inside_target = $false
            required_keys = @("SOURCE_API_KEY")
            mappings = [pscustomobject]@{
                COPILOT_GITHUB_TOKEN = "SOURCE_API_KEY"
            }
        }
        $environment = & (Join-Path $script:Root "scripts/Import-QaFoundrySecrets.ps1") `
            -SecretsConfig $secretConfig `
            -ConfigDirectory $TestDrive `
            -TargetRoot (Join-Path $script:Root "tests/fixtures/sample-target")
        $environment["COPILOT_GITHUB_TOKEN"] | Should -Be "real-test-value"
        $environment.ContainsKey("UNMAPPED_VALUE") | Should -BeFalse
    }

    It "rejects a secrets file inside the target repository" {
        $target = Join-Path $TestDrive "target"
        New-Item -ItemType Directory -Path $target | Out-Null
        $secretPath = Join-Path $target ".env"
        Set-Content -Path $secretPath -Value "SOURCE_API_KEY=value"
        $secretConfig = [pscustomobject]@{
            source = "file"
            path = $secretPath
            format = "env"
            allow_inside_target = $false
            required_keys = @("SOURCE_API_KEY")
            mappings = [pscustomobject]@{
                COPILOT_GITHUB_TOKEN = "SOURCE_API_KEY"
            }
        }
        {
            & (Join-Path $script:Root "scripts/Import-QaFoundrySecrets.ps1") `
                -SecretsConfig $secretConfig `
                -ConfigDirectory $TestDrive `
                -TargetRoot $target
        } | Should -Throw "*outside the target repository*"
    }

    It "masks provider secrets from captured output" {
        $output = & (Join-Path $script:Root "scripts/providers/Invoke-CommandProvider.ps1") `
            -Command "node $script:Root/tests/fixtures/leaky-provider.mjs" `
            -RequestPath (Join-Path $script:Root "README.md") `
            -TimeoutSeconds 30 `
            -Model "any-model" `
            -ReasoningEffort "high" `
            -ProviderEnvironment @{ TEST_TOKEN = "do-not-persist-this-value" }
        $output | Should -Be "***"
    }

    It "passes configurable model and reasoning to command wrappers" {
        $output = & (Join-Path $script:Root "scripts/providers/Invoke-CommandProvider.ps1") `
            -Command "node $script:Root/tests/fixtures/profile-env-provider.mjs" `
            -RequestPath (Join-Path $script:Root "README.md") `
            -TimeoutSeconds 30 `
            -Model "customer-model" `
            -ReasoningEffort "customer-effort" `
            -ProviderEnvironment @{ PROVIDER_TOKEN = "hidden-value" }
        $output | Should -Be "customer-model|customer-effort|***"
    }

    It "refuses direct Copilot CLI execution outside the target repository" {
        {
            & (Join-Path $script:Root "scripts/providers/Invoke-CopilotCliProvider.ps1") `
                -RequestPath (Join-Path $script:Root "README.md") `
                -RepositoryRoot (Join-Path $script:Root "tests/fixtures/sample-target") `
                -Model "claude-opus-5" `
                -ReasoningEffort "high" `
                -Command "copilot" `
                -TimeoutSeconds 30 `
                -ProviderEnvironment @{}
        } | Should -Throw "*must be inside the target repository*"
    }
}

Describe "Copilot CLI realtime provider" {
    It 'uses the real preflight context when a nested supervisor directory contains a legacy state snapshot' {
        $target = Join-Path $TestDrive 'supervisor-copilot-target'
        $runRoot = Join-Path $target '.qa-foundry-artifacts/run-test'
        $requestDirectory = Join-Path $runRoot 'supervisor/decision-hash'
        New-Item -ItemType Directory (Join-Path $runRoot 'context') -Force | Out-Null
        New-Item -ItemType Directory $requestDirectory -Force | Out-Null
        '{}' | Set-Content (Join-Path $runRoot 'workflow-state.json')
        '{}' | Set-Content (Join-Path $requestDirectory 'workflow-state.json')
        $requestPath = Join-Path $requestDirectory 'supervisor.request.md'
        'Return the allowed decision.' | Set-Content $requestPath
        $raw = & (Join-Path $script:Root 'scripts/providers/Invoke-CopilotCliProvider.ps1') `
            -RequestPath $requestPath -RepositoryRoot $target -Model 'fixture-model' -TimeoutSeconds 30 -MaxAiCredits 250 `
            -Command "node $script:Root/tests/fixtures/fake-copilot.mjs" `
            -ProviderOptions ([pscustomobject]@{install_mode='required'}) `
            -ProviderEnvironment @{COPILOT_GITHUB_TOKEN='fixture-token'}
        ($raw | ConvertFrom-Json).model | Should -Be 'fixture-model'
        ($raw | ConvertFrom-Json).maxAiCredits | Should -Be 250
        Test-Path (Join-Path $runRoot 'context/copilot-preflight.json') | Should -BeTrue
        Test-Path (Join-Path $requestDirectory 'context') | Should -BeFalse
    }
    It "invokes a CLI non-interactively with the configured model and read-only permissions" {
        $target = Join-Path $TestDrive "copilot-target"
        $runRoot = Join-Path $target ".qa-foundry-artifacts/run-test"
        $requestDirectory = Join-Path $runRoot "discovery"
        New-Item -ItemType Directory -Path (
            Join-Path $runRoot "context"
        ) -Force | Out-Null
        New-Item -ItemType Directory -Path $requestDirectory -Force | Out-Null
        Set-Content -Path (Join-Path $runRoot "workflow-state.json") -Value "{}"
        $requestPath = Join-Path $requestDirectory "agent.request.md"
        Set-Content -Path $requestPath -Value "Return a JSON object."
        $options = [pscustomobject]@{
            install_mode = "required"
            package = "@github/copilot"
            package_version = "latest"
        }
        $raw = & (Join-Path $script:Root "scripts/providers/Invoke-CopilotCliProvider.ps1") `
            -RequestPath $requestPath `
            -RepositoryRoot $target `
            -Model "account-available-model" `
            -ReasoningEffort "high" `
            -Command "node $script:Root/tests/fixtures/fake-copilot.mjs" `
            -TimeoutSeconds 30 `
            -ProviderOptions $options `
            -ProviderEnvironment @{
                COPILOT_GITHUB_TOKEN = "test-token-that-must-be-masked"
            }
        $result = $raw | ConvertFrom-Json
        $result.model | Should -Be "account-available-model"
        $result.reasoningEffort | Should -Be "high"
        $result.viewOnly | Should -BeTrue
        $result.noAskUser | Should -BeTrue
        $result.shellAllowed | Should -BeFalse
        $result.token | Should -Be "***"
        $result.noAutoUpdate | Should -BeTrue
        $result.taskTimeout | Should -Be "30"
        $result.prompt | Should -Match "Read the complete SDLC Foundry agent request"
        $preflightPath = Join-Path $runRoot "context/copilot-preflight.json"
        Test-Path $preflightPath | Should -BeTrue
        $preflight = Get-Content -LiteralPath $preflightPath -Raw |
            ConvertFrom-Json -Depth 20
        $preflight.model | Should -Be "account-available-model"
        $preflight.authenticationSource | Should -Be "COPILOT_GITHUB_TOKEN"
        $preflight.authenticationMode | Should -Be "auto"
        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $preflightPath `
                -SchemaPath (Join-Path $script:Root "schemas/runtime/copilot-preflight.schema.json") `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Not -Throw
    }

    It "uses official token precedence and ignores undefined ADO macros" {
        $target = Join-Path $TestDrive "copilot-token-target"
        $runRoot = Join-Path $target ".qa-foundry-artifacts/run-test"
        $requestDirectory = Join-Path $runRoot "discovery"
        New-Item -ItemType Directory -Path (Join-Path $runRoot "context") `
            -Force | Out-Null
        New-Item -ItemType Directory -Path $requestDirectory -Force | Out-Null
        Set-Content -Path (Join-Path $runRoot "workflow-state.json") -Value "{}"
        $requestPath = Join-Path $requestDirectory "agent.request.md"
        Set-Content -Path $requestPath -Value "Return a JSON object."
        $options = [pscustomobject]@{
            install_mode = "required"
            auth_mode = "auto"
        }
        $raw = & (Join-Path $script:Root "scripts/providers/Invoke-CopilotCliProvider.ps1") `
            -RequestPath $requestPath -RepositoryRoot $target `
            -Model "claude-opus-5" -ReasoningEffort "high" `
            -Command "node $script:Root/tests/fixtures/fake-copilot.mjs" `
            -TimeoutSeconds 30 -ProviderOptions $options `
            -ProviderEnvironment @{
                COPILOT_GITHUB_TOKEN = '$(COPILOT_GITHUB_TOKEN)'
                GH_TOKEN = "usable-token"
                GITHUB_TOKEN = "lower-precedence-token"
            }
        ($raw | ConvertFrom-Json).token | Should -Be "***"
        $preflight = Get-Content -LiteralPath (
            Join-Path $runRoot "context/copilot-preflight.json"
        ) -Raw | ConvertFrom-Json -Depth 20
        $preflight.authenticationSource | Should -Be "GH_TOKEN"
    }

    It "fails fast in CI when no Copilot credential is mapped" {
        $previousTfBuild = [Environment]::GetEnvironmentVariable("TF_BUILD")
        try {
            [Environment]::SetEnvironmentVariable("TF_BUILD", "True")
            {
                & (Join-Path $script:Root "scripts/providers/Invoke-CopilotCliProvider.ps1") `
                    -RequestPath (Join-Path $script:Root "README.md") `
                    -RepositoryRoot $script:Root -Model "claude-opus-5" `
                    -Command "missing-copilot" -TimeoutSeconds 30 `
                    -ProviderEnvironment @{}
            } | Should -Throw "*no mapped CI credential*"
        }
        finally {
            [Environment]::SetEnvironmentVariable("TF_BUILD", $previousTfBuild)
        }
    }

    Context "Reporting what a call actually cost" {
        BeforeAll {
            function script:Invoke-FakeCopilot {
                param([Parameter(Mandatory)][string]$Model)

                $target = Join-Path $TestDrive ("copilot-usage-" + $Model)
                $runRoot = Join-Path $target ".qa-foundry-artifacts/run-test"
                $requestDirectory = Join-Path $runRoot "discovery"
                New-Item -ItemType Directory -Path (Join-Path $runRoot "context") -Force |
                    Out-Null
                New-Item -ItemType Directory -Path $requestDirectory -Force | Out-Null
                Set-Content -Path (Join-Path $runRoot "workflow-state.json") -Value "{}"
                $requestPath = Join-Path $requestDirectory "agent.request.md"
                Set-Content -Path $requestPath -Value "Return a JSON object."
                $null = & (Join-Path $script:Root "scripts/providers/Invoke-CopilotCliProvider.ps1") `
                    -RequestPath $requestPath -RepositoryRoot $target `
                    -Model $Model -ReasoningEffort "high" `
                    -Command "node $script:Root/tests/fixtures/fake-copilot.mjs" `
                    -TimeoutSeconds 30 `
                    -ProviderEnvironment @{ COPILOT_GITHUB_TOKEN = "test-token" }
                return $requestPath
            }
        }

        It "leaves the counts the CLI reported beside the request it was asked for" {
            $requestPath = Invoke-FakeCopilot -Model "usage-single"

            $sidecar = "$requestPath.usage.json"
            Test-Path -LiteralPath $sidecar | Should -BeTrue
            $usage = Get-Content -LiteralPath $sidecar -Raw | ConvertFrom-Json -Depth 20
            $usage.inputTokens | Should -Be 1234
            $usage.outputTokens | Should -Be 56
            $usage.cacheReadTokens | Should -Be 7
            $usage.totalTokens | Should -Be 1290
            $usage.model | Should -Be "usage-single"

            # The CLI's own document is a means, not evidence: it is removed so
            # that the next agent in the stage does not read it back as context.
            Test-Path -LiteralPath "$requestPath.copilot.usage.json" | Should -BeFalse
        }

        It "sums a session that more than one model answered and names none of them" {
            $requestPath = Invoke-FakeCopilot -Model "usage-multi"

            $usage = Get-Content -LiteralPath "$requestPath.usage.json" -Raw |
                ConvertFrom-Json -Depth 20
            $usage.inputTokens | Should -Be 1234
            $usage.outputTokens | Should -Be 56
            # Naming one of two would charge the whole session to it.
            @($usage.PSObject.Properties.Name) | Should -Not -Contain "model"
        }

        It "records measured sizes only when the CLI reports nothing usable" {
            foreach ($mode in @("usage-none", "usage-empty", "usage-garbage", "usage-invalid",
                    "usage-partial")) {
                $requestPath = Invoke-FakeCopilot -Model $mode
                # Silence and unreadable noise both mean the same thing: no
                # measurement exists. Writing a zero here would be indistinguishable
                # from a call that genuinely cost nothing. 'usage-invalid' is the
                # sharpest case: a well-formed document whose every counter is
                # negative, not a number, or absent - a block that was looked at
                # and measured nothing. 'usage-partial' is sharper still: one
                # counter reads and one does not, and carrying the readable half
                # would report the call as cheaper than it was.
                Test-Path -LiteralPath "$requestPath.usage.json" | Should -BeFalse
                Test-Path -LiteralPath "$requestPath.copilot.usage.json" | Should -BeFalse
            }
        }

        # A call that times out or exits non-zero still leaves the CLI's document
        # beside the request. Left there it becomes context the next agent in the
        # stage reads back as if this runtime had written it.
        It "clears the CLI's own document even when the call fails" {
            $target = Join-Path $TestDrive "copilot-usage-failure"
            $runRoot = Join-Path $target ".qa-foundry-artifacts/run-test"
            $requestDirectory = Join-Path $runRoot "discovery"
            New-Item -ItemType Directory -Path (Join-Path $runRoot "context") -Force | Out-Null
            New-Item -ItemType Directory -Path $requestDirectory -Force | Out-Null
            Set-Content -Path (Join-Path $runRoot "workflow-state.json") -Value "{}"
            $requestPath = Join-Path $requestDirectory "agent.request.md"
            Set-Content -Path $requestPath -Value "Return a JSON object."

            {
                & (Join-Path $script:Root "scripts/providers/Invoke-CopilotCliProvider.ps1") `
                    -RequestPath $requestPath -RepositoryRoot $target `
                    -Model "usage-single" -ReasoningEffort "high" `
                    -Command "node $script:Root/tests/fixtures/fake-copilot.mjs --fail" `
                    -TimeoutSeconds 30 `
                    -ProviderEnvironment @{ COPILOT_GITHUB_TOKEN = "test-token" }
            } | Should -Throw
            Test-Path -LiteralPath "$requestPath.copilot.usage.json" | Should -BeFalse
        }
    }
}

Describe "Realtime CI evidence collection" {
    It "normalises Azure DevOps build, timeline, and failed-test evidence" {
        $eventPath = Join-Path $TestDrive "azure-event.json"
        Copy-Item -Path (
            Join-Path $script:Root "tests/fixtures/events/azure-devops-build-failed.json"
        ) -Destination $eventPath
        $outputPath = Join-Path $TestDrive "azure-ci-evidence.json"
        $ci = [pscustomobject]@{
            provider = "azure-devops"
            collect_realtime = $true
            fail_on_collection_error = $true
            max_failed_tests = 50
            max_jobs = 50
            azure_devops = [pscustomobject]@{
                organization_url = "https://dev.azure.com/example"
                project = "product"
                auth_env = "AZURE_DEVOPS_TOKEN"
                auth_scheme = "bearer"
            }
        }
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like "*timeline*") {
                return [pscustomobject]@{
                    records = @(
                        [pscustomobject]@{
                            id = "job-1"; name = "Test"; type = "Job"
                            state = "completed"; result = "failed"
                        }
                    )
                }
            }
            if ($Uri -like "*/results?*") {
                return [pscustomobject]@{
                    count = 1
                    value = @(
                        [pscustomobject]@{
                            id = 9
                            automatedTestName = "Example.Tests.Fails"
                            testCaseTitle = "Fails"
                            outcome = "Failed"
                            errorMessage = "Expected true but was false"
                            stackTrace = "at Example.Tests.Fails()"
                            durationInMs = 12.5
                        }
                    )
                }
            }
            if ($Uri -like "*/_apis/test/runs?*") {
                return [pscustomobject]@{
                    value = @([pscustomobject]@{ id = 7; name = "unit-tests" })
                }
            }
            return [pscustomobject]@{
                id = 12345
                definition = [pscustomobject]@{ name = "product-ci" }
                status = "completed"
                result = "failed"
                sourceBranch = "refs/heads/main"
                sourceVersion = "0123456789abcdef0123456789abcdef01234567"
                startTime = "2026-08-03T09:59:00Z"
                finishTime = "2026-08-03T10:00:00Z"
                _links = [pscustomobject]@{
                    web = [pscustomobject]@{ href = "https://dev.azure.com/example/build/12345" }
                }
            }
        }

        $result = & (Join-Path $script:Root "scripts/collectors/Collect-CiEvidence.ps1") `
            -RunId "run-ci-test" `
            -EventPath $eventPath `
            -CiConfig $ci `
            -OutputPath $outputPath `
            -ProviderEnvironment @{ AZURE_DEVOPS_TOKEN = "must-not-persist" }
        $result.status | Should -Be "collected"
        $result.summary.failedJobCount | Should -Be 1
        $result.summary.failedTestCount | Should -Be 1
        $result.failedTests[0].name | Should -Be "Example.Tests.Fails"
        (Get-Content -Path $outputPath -Raw) | Should -Not -Match "must-not-persist"
        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $outputPath `
                -SchemaPath (Join-Path $script:Root "schemas/runtime/ci-evidence.schema.json") `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Not -Throw
    }

    It "collects evidence for a build that is still running" {
        # A bootstrap run collects evidence about the build it is running
        # inside, so the build is always in progress. Azure DevOps omits
        # 'result', 'finishTime' and '_links' entirely until the build ends
        # rather than sending them as null, which used to abort the whole
        # collection under Set-StrictMode and leave every agent without CI
        # evidence.
        $eventPath = Join-Path $TestDrive "running-event.json"
        Copy-Item -Path (
            Join-Path $script:Root "tests/fixtures/events/azure-devops-build-failed.json"
        ) -Destination $eventPath
        $outputPath = Join-Path $TestDrive "running-ci-evidence.json"
        $ci = [pscustomobject]@{
            provider = "azure-devops"
            collect_realtime = $true
            fail_on_collection_error = $true
            max_failed_tests = 50
            max_jobs = 50
            azure_devops = [pscustomobject]@{
                organization_url = "https://dev.azure.com/example"
                project = "product"
                auth_env = "AZURE_DEVOPS_TOKEN"
                auth_scheme = "basic"
            }
        }
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like "*timeline*") {
                return [pscustomobject]@{
                    records = @(
                        [pscustomobject]@{
                            id = "job-1"; name = "Bootstrap relay leg 1"; type = "Job"
                            state = "inProgress"
                        }
                    )
                }
            }
            if ($Uri -like "*/_apis/test/runs?*") {
                return [pscustomobject]@{ value = @() }
            }
            return [pscustomobject]@{
                id = 970346
                definition = [pscustomobject]@{ name = "SDLC Foundry - First Start Bootstrap" }
                status = "inProgress"
                sourceBranch = "refs/heads/develop"
                sourceVersion = "0123456789abcdef0123456789abcdef01234567"
                startTime = "2026-09-08T11:55:54Z"
            }
        }

        $result = & (Join-Path $script:Root "scripts/collectors/Collect-CiEvidence.ps1") `
            -RunId "run-ci-running" `
            -EventPath $eventPath `
            -CiConfig $ci `
            -OutputPath $outputPath `
            -ProviderEnvironment @{ AZURE_DEVOPS_TOKEN = "token" }
        $result.status | Should -Be "collected"
        $result.warnings.Count | Should -Be 0
        $result.build.status | Should -Be "inProgress"
        $result.build.result | Should -Be ""
        $result.build.finishedAt | Should -Be ""
        $result.build.url | Should -Be ""
        $result.build.pipeline | Should -Be "SDLC Foundry - First Start Bootstrap"
        $result.jobs[0].result | Should -Be ""
        $result.summary.failedJobCount | Should -Be 0
        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $outputPath `
                -SchemaPath (Join-Path $script:Root "schemas/runtime/ci-evidence.schema.json") `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Not -Throw
    }

}

Describe "Command execution policy" {
    BeforeAll {
        $script:Policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
    }

    It "executes an allowed structured command" {
        $command = [pscustomobject]@{
            id = "node-version"
            executable = "node"
            arguments = @("--version")
            workingDirectory = "."
            environment = [pscustomobject]@{}
        }
        $result = & (Join-Path $script:Root "scripts/Invoke-CommandSafely.ps1") `
            -CommandSpec $command `
            -Policy $script:Policy `
            -RepositoryRoot $script:Root
        $result.status | Should -Be "completed"
        $result.exitCode | Should -Be 0
        $result.standardOutput | Should -Match "^v\d+"
    }

    It "records an allowed but uninstalled executable as a failed command" {
        # Run 452 died five stages in because osv-scanner is allowed by policy but
        # absent from the build agent, and starting it threw instead of failing.
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $absent = "qa-foundry-executable-that-does-not-exist"
        $policy.commands.allowed_executables = @($policy.commands.allowed_executables) + $absent
        $command = [pscustomobject]@{
            id = "absent-tool"
            executable = $absent
            arguments = @("--version")
            workingDirectory = "."
            environment = [pscustomobject]@{}
        }
        $result = & (Join-Path $script:Root "scripts/Invoke-CommandSafely.ps1") `
            -CommandSpec $command `
            -Policy $policy `
            -RepositoryRoot $script:Root
        $result.status | Should -Be "failed"
        $result.exitCode | Should -Be 127
        $result.standardError | Should -Match "not found on this machine"
    }

    It "records a command with no directory to run in instead of killing the run" {
        # An hour of completed stages must not be destroyed because one proposed
        # command points at a directory the change set has not created yet.
        $command = [pscustomobject]@{
            id = "future-automation"
            executable = "node"
            arguments = @("--version")
            workingDirectory = "automation/api-e2e"
            environment = [pscustomobject]@{}
        }
        $result = & (Join-Path $script:Root "scripts/Invoke-CommandSafely.ps1") `
            -CommandSpec $command `
            -Policy $script:Policy `
            -RepositoryRoot $script:Root
        $result.status | Should -Be "skipped"
        $result.standardError | Should -Match "does not exist in the repository yet"
        $result.standardOutput | Should -Be ""
    }

    It "still refuses a working directory that escapes the repository" {
        $command = [pscustomobject]@{
            id = "escape"
            executable = "node"
            arguments = @("--version")
            workingDirectory = "../.."
            environment = [pscustomobject]@{}
        }
        {
            & (Join-Path $script:Root "scripts/Invoke-CommandSafely.ps1") `
                -CommandSpec $command `
                -Policy $script:Policy `
                -RepositoryRoot $script:Root
        } | Should -Throw "*outside the repository*"
    }

    It "rejects destructive Git history rewriting" {
        $command = [pscustomobject]@{
            id = "forbidden"
            executable = "git"
            arguments = @("reset", "--hard")
            workingDirectory = "."
            environment = [pscustomobject]@{}
        }
        $result = & (Join-Path $script:Root "scripts/Invoke-CommandSafely.ps1") `
            -CommandSpec $command `
            -Policy $script:Policy `
            -RepositoryRoot $script:Root
        $result.status | Should -Be "rejected"
        $result.standardError | Should -Match "forbidden pattern"
        $result.standardOutput | Should -Be ""
    }

    It "refuses an executable outside the policy without ending the run" {
        $command = [pscustomobject]@{
            id = "unlisted"
            executable = "bash"
            arguments = @("-c", "echo hello")
            workingDirectory = "."
            environment = [pscustomobject]@{}
        }
        $result = & (Join-Path $script:Root "scripts/Invoke-CommandSafely.ps1") `
            -CommandSpec $command `
            -Policy $script:Policy `
            -RepositoryRoot $script:Root
        $result.status | Should -Be "rejected"
        $result.standardError | Should -Match "not on the policy's allowed list"
    }

    It "refuses an unlisted environment variable instead of destroying the run" {
        # Run 451 died here: an agent asked for a harmless telemetry opt-out and the
        # refusal was thrown, discarding four completed stages.
        $command = [pscustomobject]@{
            id = "env-not-allowed"
            executable = "node"
            arguments = @("--version")
            workingDirectory = "."
            environment = [pscustomobject]@{ SOME_UNLISTED_VARIABLE = "1" }
        }
        $result = & (Join-Path $script:Root "scripts/Invoke-CommandSafely.ps1") `
            -CommandSpec $command `
            -Policy $script:Policy `
            -RepositoryRoot $script:Root
        $result.status | Should -Be "rejected"
        $result.standardError | Should -Match "SOME_UNLISTED_VARIABLE"
        $result.standardError | Should -Match "Allowed variables are"
    }

    It "allows the build-tool switches agents actually ask for" {
        $command = [pscustomobject]@{
            id = "telemetry-opt-out"
            executable = "node"
            arguments = @("--version")
            workingDirectory = "."
            environment = [pscustomobject]@{ DOTNET_CLI_TELEMETRY_OPTOUT = "1"; DOTNET_NOLOGO = "1" }
        }
        $result = & (Join-Path $script:Root "scripts/Invoke-CommandSafely.ps1") `
            -CommandSpec $command `
            -Policy $script:Policy `
            -RepositoryRoot $script:Root
        $result.status | Should -Be "completed"
    }

    It "reads one isolation setting, and still honours where it used to live" {
        # The setting was written when only bootstrap verification ran untrusted
        # code. Execution plans and the quality suite run it too, so the key moved
        # up a level - and an installation that already configured the old place
        # must keep the boundary it asked for rather than silently lose it.
        $current = Get-QaFoundryIsolationSetting -Config ([pscustomobject]@{
            automation = [pscustomobject]@{ isolation = [pscustomobject]@{ mode = "container" } }
        })
        [string]$current.mode | Should -Be "container"

        $legacy = Get-QaFoundryIsolationSetting -Config ([pscustomobject]@{
            automation = [pscustomobject]@{
                verification = [pscustomobject]@{ isolation = [pscustomobject]@{ mode = "container" } }
            }
        })
        [string]$legacy.mode | Should -Be "container"

        Get-QaFoundryIsolationSetting -Config ([pscustomobject]@{}) | Should -BeNullOrEmpty

        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        [string](Get-QaFoundryIsolationSetting -Config $config).mode | Should -Not -BeNullOrEmpty
    }

    It "gives a generated command a home of its own rather than the agent's" {
        # Every command that reaches this script was written by an agent minutes
        # earlier. Inheriting this process's environment would hand it the Azure
        # DevOps token the run holds, and inheriting the agent's home would hand it
        # the .npmrc and NuGet.config that hold the feed credentials.
        $probe = Join-Path $TestDrive "probe.mjs"
        $report = Join-Path $TestDrive "observed.json"
        @'
import fs from "node:fs";
const seen = process["e" + "nv"];
fs.writeFileSync(process.argv[2], JSON.stringify({
    home: seen.HOME ?? "",
    npmCache: seen.npm_config_cache ?? "",
    nugetPackages: seen.NUGET_PACKAGES ?? "",
    gitConfig: seen.GIT_CONFIG_GLOBAL ?? "",
    orchestratorToken: seen.AZURE_DEVOPS_TOKEN ?? ""
}));
'@ | Set-Content -LiteralPath $probe -Encoding utf8

        $previousToken = [Environment]::GetEnvironmentVariable("AZURE_DEVOPS_TOKEN")
        $env:AZURE_DEVOPS_TOKEN = "orchestrator-credential"
        try {
            $command = [pscustomobject]@{
                id = "isolated-probe"
                executable = "node"
                arguments = @($probe, $report)
                workingDirectory = "."
                environment = [pscustomobject]@{}
            }
            $result = & (Join-Path $script:Root "scripts/Invoke-CommandSafely.ps1") `
                -CommandSpec $command `
                -Policy $script:Policy `
                -RepositoryRoot $script:Root `
                -Isolation ([pscustomobject]@{ mode = "process" })
        }
        finally {
            $env:AZURE_DEVOPS_TOKEN = $previousToken
        }

        $result.status | Should -Be "completed"
        $observed = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
        # Asserted as a boolean rather than by printing the value: the token is the
        # thing this test exists to keep out of anything a person reads.
        [string]::IsNullOrEmpty([string]$observed.orchestratorToken) | Should -BeTrue
        [string]$observed.home | Should -Match "command-home"
        [string]$observed.home | Should -Not -Be ([Environment]::GetEnvironmentVariable("USERPROFILE"))
        # The caches have to live under the repository, not under the command's own
        # home, or in container mode what an install step downloaded is gone by the
        # time the build step runs.
        [string]$observed.npmCache | Should -Match "command-home"
        [string]$observed.nugetPackages | Should -Match "command-home"
        (Test-Path -LiteralPath ([string]$observed.gitConfig)) | Should -BeFalse
    }

    It "runs the same command inside a container when the installation asks for one" {
        # The boundary bootstrap verification has had all along, now applied to the
        # commands an execution plan and the quality suite run.
        $runtimeDirectory = Join-Path $TestDrive "runtime"
        New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $runtimeDirectory "docker.cmd") `
            -Value "@echo off`r`necho %*" -Encoding ascii

        $previousPath = $env:PATH
        $env:PATH = "$runtimeDirectory$([System.IO.Path]::PathSeparator)$previousPath"
        try {
            $command = [pscustomobject]@{
                id = "containerised"
                executable = "node"
                arguments = @("--version")
                workingDirectory = "."
                environment = [pscustomobject]@{}
            }
            $result = & (Join-Path $script:Root "scripts/Invoke-CommandSafely.ps1") `
                -CommandSpec $command `
                -Policy $script:Policy `
                -RepositoryRoot $script:Root `
                -Isolation ([pscustomobject]@{
                    mode = "container"
                    container = [pscustomobject]@{ executable = "docker"; image = "node:22" }
                })
        }
        finally {
            $env:PATH = $previousPath
        }

        $result.status | Should -Be "completed"
        # Recorded as the command the agent asked for, not as the container line
        # that carried it: the evidence is about the command, not about the runtime.
        $result.command | Should -Be "node --version"
        $result.standardOutput | Should -Match "run --rm --name qa-foundry-command-"
        $result.standardOutput | Should -Match ([regex]::Escape("--volume $script:Root`:/qa-foundry/work"))
        $result.standardOutput | Should -Match ([regex]::Escape("--workdir /qa-foundry/work"))
        $result.standardOutput | Should -Match ([regex]::Escape("node:22 node --version"))
        # Named in the container's own terms. Left as an agent path it would name
        # nothing inside the image, and a restore would be thrown away with the
        # container that performed it.
        $result.standardOutput | Should -Match ([regex]::Escape(
            "NUGET_PACKAGES=/qa-foundry/work/.qa-foundry-artifacts/command-home/nuget/packages"))
    }

    It "refuses to run untrusted code at all when the runtime it was promised is absent" {
        # No falling back to a child process. A run that believes it is isolated
        # and is not is worse than one that stops.
        $command = [pscustomobject]@{
            id = "no-runtime"
            executable = "node"
            arguments = @("--version")
            workingDirectory = "."
            environment = [pscustomobject]@{}
        }
        {
            & (Join-Path $script:Root "scripts/Invoke-CommandSafely.ps1") `
                -CommandSpec $command `
                -Policy $script:Policy `
                -RepositoryRoot $script:Root `
                -Isolation ([pscustomobject]@{
                    mode = "container"
                    container = [pscustomobject]@{
                        executable = "qa-foundry-container-runtime-that-does-not-exist"
                        image = "node:22"
                    }
                })
        } | Should -Throw "*is not installed on this agent*"
    }

    It "gives an agent the budget its workflow entry asks for" {
        # PowerShell matches variable names case-insensitively, so a local
        # $maxArtifactBytes and the $MaxArtifactBytes parameter were one variable
        # and the profile default silently overwrote every per-agent budget. The
        # change generator carries whole file bodies and was capped at a quarter
        # of what its workflow entry asks for.
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $profileBudget = [int]$config.ai.max_artifact_bytes
        $profileBudget | Should -BeGreaterThan 0
        $agentBudget = $profileBudget * 3

        $outputPath = Join-Path $TestDrive "budget-run/generation/change-set.json"
        New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null
        $null = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "bootstrap-change-generator" `
            -StageId "bootstrap-change-generation" `
            -RunId "run-budget" `
            -PromptPath (Join-Path $script:Root "prompts/sdlc/change-generator.md") `
            -ContextPaths @() `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/actions/change-set.schema.json") `
            -Config $config `
            -MaxArtifactBytes $agentBudget
        $request = Get-Content -Path "$outputPath.attempt-1.request.md" -Raw
        $request | Should -Match "must not exceed $agentBudget bytes"
        $request | Should -Not -Match "must not exceed $profileBudget bytes"
    }

    It "falls back to the profile budget when the workflow entry sets none" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $profileBudget = [int]$config.ai.max_artifact_bytes

        $outputPath = Join-Path $TestDrive "budget-default-run/generation/change-set.json"
        New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null
        $null = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "bootstrap-change-generator" `
            -StageId "bootstrap-change-generation" `
            -RunId "run-budget-default" `
            -PromptPath (Join-Path $script:Root "prompts/sdlc/change-generator.md") `
            -ContextPaths @() `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/actions/change-set.schema.json") `
            -Config $config
        $request = Get-Content -Path "$outputPath.attempt-1.request.md" -Raw
        $request | Should -Match "must not exceed $profileBudget bytes"
    }

    It "tells the agents which executables and variables the runner accepts" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $outputPath = Join-Path $TestDrive "policy-run/execution/execution-plan.json"
        New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null
        $null = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "execution" `
            -StageId "execution" `
            -RunId "run-policy" `
            -PromptPath (Join-Path $script:Root "prompts/execution/execution.md") `
            -ContextPaths @() `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/execution/execution-plan.schema.json") `
            -Config $config `
            -Policy $script:Policy

        $request = Get-Content -Path "$outputPath.attempt-1.request.md" -Raw
        $request | Should -Match "# Command execution policy"
        $request | Should -Match "- dotnet"
        $request | Should -Match "DOTNET_CLI_TELEMETRY_OPTOUT"
    }
}

Describe "The difference an event is about" {
    BeforeAll {
        function New-TestRepository {
            param([Parameter(Mandatory)][string]$Path)

            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            $git = {
                param([string[]]$Arguments)
                $info = [System.Diagnostics.ProcessStartInfo]::new()
                $info.FileName = "git"
                foreach ($argument in $Arguments) { $info.ArgumentList.Add([string]$argument) }
                $info.WorkingDirectory = $Path
                $info.UseShellExecute = $false
                $info.RedirectStandardOutput = $true
                $info.RedirectStandardError = $true
                $process = [System.Diagnostics.Process]::new()
                $process.StartInfo = $info
                $null = $process.Start()
                $null = $process.StandardOutput.ReadToEnd()
                $null = $process.StandardError.ReadToEnd()
                $process.WaitForExit()
                $code = $process.ExitCode
                $process.Dispose()
                if ($code -ne 0) { throw "git $($Arguments -join ' ') exited $code" }
            }
            & $git @("init", "--initial-branch=main")
            & $git @("config", "user.email", "runtime-test@example.invalid")
            & $git @("config", "user.name", "Runtime Test")
            Set-Content -LiteralPath (Join-Path $Path "kept.txt") -Value "one" -Encoding utf8
            Set-Content -LiteralPath (Join-Path $Path "removed.txt") -Value "gone" -Encoding utf8
            & $git @("add", "-A")
            & $git @("commit", "-m", "first")
            return $git.GetNewClosure()
        }
    }

    It "records which files the event changed rather than which files exist" {
        # Handed only a snapshot and a commit sha, every analyst saw the whole
        # repository as equally new: three touched files were indistinguishable
        # from three thousand untouched ones, which costs both the analysis and
        # the tokens spent describing work nobody asked about.
        $repository = Join-Path $TestDrive "diff-repo"
        $git = New-TestRepository -Path $repository
        Set-Content -LiteralPath (Join-Path $repository "kept.txt") -Value "one`ntwo" -Encoding utf8
        Set-Content -LiteralPath (Join-Path $repository "added.txt") -Value "new" -Encoding utf8
        Remove-Item -LiteralPath (Join-Path $repository "removed.txt") -Force
        & $git @("add", "-A")
        & $git @("commit", "-m", "second")

        $outputPath = Join-Path $TestDrive "event-with-change.json"
        $event = & (Join-Path $script:Root "scripts/Collect-SdlcEvent.ps1") `
            -RunId "run-change" -OutputPath $outputPath -RepositoryRoot $repository

        $event.change.available | Should -BeTrue
        $event.change.basis | Should -Be "parent"
        $event.change.baseCommitSha | Should -Not -BeNullOrEmpty
        $event.change.headCommitSha | Should -Not -Be $event.change.baseCommitSha
        $event.change.fileCount | Should -Be 3
        $event.change.truncated | Should -BeFalse
        ($event.change.files | Where-Object { $_.path -eq "added.txt" }).status | Should -Be "added"
        ($event.change.files | Where-Object { $_.path -eq "removed.txt" }).status | Should -Be "deleted"
        $changedKept = @($event.change.files | Where-Object { $_.path -eq "kept.txt" })[0]
        $changedKept.status | Should -Be "modified"
        $changedKept.insertions | Should -BeGreaterThan 0

        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $outputPath `
                -SchemaPath (Join-Path $script:Root "schemas/runtime/sdlc-event.schema.json") `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Not -Throw
    }

    It "measures against the base the caller named when there is one" {
        $repository = Join-Path $TestDrive "declared-repo"
        $git = New-TestRepository -Path $repository
        Set-Content -LiteralPath (Join-Path $repository "kept.txt") -Value "one`ntwo" -Encoding utf8
        & $git @("add", "-A")
        & $git @("commit", "-m", "second")
        Set-Content -LiteralPath (Join-Path $repository "third.txt") -Value "three" -Encoding utf8
        & $git @("add", "-A")
        & $git @("commit", "-m", "third")

        $event = & (Join-Path $script:Root "scripts/Collect-SdlcEvent.ps1") `
            -RunId "run-declared" `
            -OutputPath (Join-Path $TestDrive "event-declared.json") `
            -RepositoryRoot $repository `
            -BaseRef "HEAD~2"

        $event.change.basis | Should -Be "declared"
        # Two commits of work, not one: a base that was named is the base that
        # is used, and the parent is not quietly substituted for it.
        $event.change.fileCount | Should -Be 2
        @($event.change.files.path | Sort-Object) | Should -Be @("kept.txt", "third.txt")
    }

    It "says plainly when there is nothing to compare against" {
        # A shallow checkout has no parent commit. Reporting an empty change would
        # read as 'nothing changed', which is a claim the repository does not
        # support and the opposite of what is true.
        $repository = Join-Path $TestDrive "single-commit-repo"
        $null = New-TestRepository -Path $repository

        $event = & (Join-Path $script:Root "scripts/Collect-SdlcEvent.ps1") `
            -RunId "run-no-base" `
            -OutputPath (Join-Path $TestDrive "event-no-base.json") `
            -RepositoryRoot $repository

        $event.change.available | Should -BeFalse
        $event.change.basis | Should -Be "none"
        $event.change.baseCommitSha | Should -BeNullOrEmpty
        $event.change.headCommitSha | Should -Not -BeNullOrEmpty
        $event.change.fileCount | Should -Be 0
        $event.change.reason | Should -Match "cannot be separated from what was already there"
    }

    It "does not claim a change when there is no working copy to read" {
        $event = & (Join-Path $script:Root "scripts/Collect-SdlcEvent.ps1") `
            -RunId "run-no-repository" `
            -OutputPath (Join-Path $TestDrive "event-no-repository.json")

        $event.change.available | Should -BeFalse
        $event.change.reason | Should -Match "treated as equally new"
    }
}

Describe 'Supervisor decisions follow their evidence across restarted stage counters' {
    It 'reuses the same decision but preserves a separate decision when state changes at the same iteration' {
        $runRoot = Join-Path $TestDrive supervisor-recovery
        New-Item -ItemType Directory (Join-Path $runRoot supervisor) -Force | Out-Null
        $legacyPath = Join-Path $runRoot supervisor/supervisor-decision-3.json
        Set-Content $legacyPath '{"legacy":"preserve this previous decision"}'
        $legacyHash = (Get-FileHash $legacyPath).Hash
        $state = [pscustomobject]@{ currentStage = 'review'; stages = @(@{id='review';iteration=3;status='revision_required';attempts=@()}) }
        $state | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $runRoot workflow-state.json)
        $config = Set-ResolvedTestAiProfile -Config (Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root)
        $parameters = @{ Reason='The review did not approve'; AllowedDecisions=@('block','fail'); Config=$config;
            RunRoot=$runRoot; RunId='run-supervisor-recovery'; Iteration=3; RepositoryRoot=$script:Root }
        $first = & (Join-Path $script:Root scripts/Invoke-Supervisor.ps1) @parameters
        $first.recommendation | Should -BeIn @('block','fail')
        $requestCount = @(Get-ChildItem (Join-Path $runRoot supervisor) -Recurse -Filter '*.attempt-*.request.md').Count
        $requestCount | Should -Be 1
        $null = & (Join-Path $script:Root scripts/Invoke-Supervisor.ps1) @parameters
        @(Get-ChildItem (Join-Path $runRoot supervisor) -Recurse -Filter '*.attempt-*.request.md').Count | Should -Be $requestCount
        $state.currentStage = 'framework-verification'
        $state | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $runRoot workflow-state.json)
        $null = & (Join-Path $script:Root scripts/Invoke-Supervisor.ps1) @parameters
        @(Get-ChildItem (Join-Path $runRoot supervisor) -Recurse -Filter '*.attempt-*.request.md').Count | Should -Be 2
        (Get-FileHash $legacyPath).Hash | Should -Be $legacyHash
    }
}

Describe "Complete mock workflow" {
    It "runs the failed-build triage lane with a normal no-action outcome" {
        Push-Location $script:Root
        try {
            $run = & (Join-Path $script:Root "scripts/Invoke-QaFoundry.ps1") `
                -ConfigPath $script:ConfigPath `
                -WorkflowPath (Join-Path $script:Root "workflows/failed-build-triage.yaml") `
                -PolicyPath $script:PolicyPath `
                -EventType "ci.build.failed" `
                -CiBuildId "demo-build" `
                -Demo
            $run.status | Should -Be "completed"
            $state = Get-Content -Path $run.statePath -Raw |
                ConvertFrom-Json -Depth 100
            $state.workflowName | Should -Be "failed-build-triage"
            $verified = Get-Content -Path (
                Join-Path $run.runRoot "failure-investigation/verified-failure-analysis.json"
            ) -Raw | ConvertFrom-Json -Depth 100
            $verified.outcome | Should -Be "no_action_needed"
            $validation = & (Join-Path $script:Root "scripts/Test-RunArtifacts.ps1") `
                -RunRoot $run.runRoot
            $validation.valid | Should -BeTrue
        }
        finally {
            Pop-Location
        }
    }

    It "assesses file contracts before generation and retains the later verification gate" {
        Push-Location $script:Root
        try {
            $run = & (Join-Path $script:Root "scripts/Invoke-QaFoundry.ps1") `
                -ConfigPath $script:ConfigPath `
                -WorkflowPath $script:WorkflowPath `
                -PolicyPath $script:PolicyPath `
                -Demo
            $run.status | Should -Be "completed"
            $executionResults = @(Get-ChildItem -Path $run.runRoot -Recurse `
                -Filter "execution-result.json" -File)
            $executionResults.Count | Should -BeGreaterThan 0
            $executed = Get-Content -Path $executionResults[0].FullName -Raw |
                ConvertFrom-Json -Depth 100
            $executed.status | Should -Be "completed"
            @($executed.commands).Count | Should -Be 0
            $analysis = Get-Content (Join-Path $run.runRoot 'execution/failure-analysis.json') -Raw | ConvertFrom-Json
            $analysis.details.executionPerformed | Should -BeFalse
            @($analysis.failures).Count | Should -Be 0
            $verification = Get-Content (Join-Path $run.runRoot 'framework-verification/framework-verification.json') -Raw | ConvertFrom-Json
            # Demo reaches the gate but must not claim to have run generated code.
            # Executed builds, test counts and negative probes have their own
            # verifier tests; this scenario checks bootstrap orchestration.
            $verification.outcome | Should -Be 'not_attempted'
        }
        finally {
            Pop-Location
        }
    }

    It "routes one unanimous-review rejection back to implementation and completes" {
        Push-Location $script:Root
        try {
            $run = & (Join-Path $script:Root "scripts/Invoke-QaFoundry.ps1") `
                -ConfigPath $script:ConfigPath `
                -WorkflowPath $script:WorkflowPath `
                -PolicyPath $script:PolicyPath `
                -Demo
            $run.status | Should -Be "completed"
            $run.targetRepository | Should -Be (
                Join-Path $script:Root "tests/fixtures/sample-target"
            )
            $run.model | Should -Be "claude-opus-5"
            # The profile budget has to survive profile resolution and the merge
            # into the run config, and a per-agent budget from the workflow has to
            # override it rather than being silently replaced by it.
            $requests = @(Get-ChildItem -Path $run.runRoot -Recurse -Filter "*.request.md" -File)
            $requests.Count | Should -BeGreaterThan 0
            $expectedBudgets = @{
                "framework-implementation" = 131072
                "test-implementation"      = 131072
                "change-set"               = 196608
                "materialization-plan"     = 16384
            }
            foreach ($request in $requests) {
                $text = Get-Content -Path $request.FullName -Raw
                $agent = ($request.Name -split "\.json")[0]
                $expected = if ($expectedBudgets.ContainsKey($agent)) {
                    $expectedBudgets[$agent]
                }
                else { 65536 }
                if ($agent -like 'change-set-batch-*') {
                    # Source batches carry a sizing hint: a hard prose ceiling
                    # must not tell a generator to omit executable file bodies.
                    $text | Should -Match "The $expected byte\s+estimate is a sizing hint"
                    $text | Should -Match 'Return every assigned file with its complete executable body'
                }
                else {
                    $text | Should -Match "must not exceed $expected bytes" -Because (
                        "$($request.Name) must carry the budget its workflow entry asks for")
                }
            }
            # The agents that carry whole file bodies must actually have been reached.
            @($requests | Where-Object { $_.Name -like "change-set*" }).Count |
                Should -BeGreaterThan 0
            $state = Get-Content -Path $run.statePath -Raw | ConvertFrom-Json -Depth 100
            $review = @($state.stages | Where-Object id -eq "review")[0]
            @($review.attempts).Count | Should -Be 2
            $review.attempts[0].decision | Should -Be "revision_required"
            $review.attempts[1].decision | Should -Be "approved"
            (@($state.stages | Where-Object id -eq "implementation")[0]).iteration |
                Should -Be 2
            $state.status | Should -Be "completed"

            $validation = & (Join-Path $script:Root "scripts/Test-RunArtifacts.ps1") `
                -RunRoot $run.runRoot
            $validation.valid | Should -BeTrue
            $validation.artifactCount | Should -BeGreaterThan 20
            $resolvedRunConfig = Get-Content -Path (
                Join-Path $run.runRoot "context/run-configuration.json"
            ) -Raw | ConvertFrom-Json -Depth 100
            $resolvedRunConfig.ai.profile | Should -Be "mock"
            $resolvedRunConfig.workflow.name | Should -Be "bootstrap-automation"
            $resolvedRunConfig.event.type | Should -Be "manual"
            $resolvedRunConfig.assurance.mode | Should -Be "maximum"
            $resolvedRunConfig.assurance.highRiskMinimumReviewers | Should -Be 3
            $resolvedRunConfig.secrets.mappedEnvironmentNames.Count | Should -Be 0
            $resolvedRunConfig.secrets.modelEnvironmentNames.Count | Should -Be 0
            # What a person approved has to reach the run itself, not just the
            # config file nobody downstream reads. The packages moved out to the
            # architect's decision, but where they may be installed from and what
            # has to be on the agent to install them did not.
            $approvedEcosystem = @($resolvedRunConfig.automation.ecosystems |
                Where-Object id -eq "npm")[0]
            $approvedEcosystem.recipe | Should -Be "npm-package-lock"
            $approvedEcosystem.source.registry | Should -Be "https://registry.npmjs.org/"
            $approvedEcosystem.source.authentication | Should -Be "none"
            # A materialiser has to check the lock file it reuses came from this
            # ecosystem, so the run has to carry enough of it to check against.
            $approvedEcosystem.runtime.node_major | Should -Be 22
            $approvedEcosystem.runtime.lockfile_version | Should -Be 3
            $approvedEcosystem.sha256 | Should -Match "^[0-9a-f]{64}$"
            # A design is only bounded if the bound travels with the run.
            $resolvedRunConfig.automation.packagePolicy.maxDirectPackages | Should -Be 12
            $resolvedRunConfig.automation.packagePolicy.allowPrerelease | Should -BeFalse
            $sdlcEvent = Get-Content -Path (
                Join-Path $run.runRoot "context/sdlc-event.json"
            ) -Raw | ConvertFrom-Json -Depth 100
            $sdlcEvent.source | Should -Be "local"
            $ciEvidence = Get-Content -Path (
                Join-Path $run.runRoot "context/ci-evidence.json"
            ) -Raw | ConvertFrom-Json -Depth 100
            $ciEvidence.status | Should -Be "not_applicable"
            $context = Get-Content -Path (
                Join-Path $run.runRoot "context/repository.json"
            ) -Raw | ConvertFrom-Json -Depth 100
            @($context.analysisInputs.category) | Should -Contain "requirements"
            @($context.analysisInputs.category) | Should -Contain "architecture"
            (@($context.analysisInputs | Where-Object {
                $_.path -eq "docs/requirements.md"
            })[0]).content | Should -Match "REQ-003"
        }
        finally {
            Pop-Location
        }
    }

    It "blocks at a bounded unanimous-review iteration limit when exhaustion is not permitted" {
        $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $limitedApproval = (@($workflow.stages | Where-Object id -eq "review")[0]).approval
        $limitedApproval.max_iterations = 1
        $limitedApproval.PSObject.Properties.Remove("on_exhaustion")
        $runRoot = Join-Path $TestDrive "limited-run"
        New-Item -ItemType Directory -Path (Join-Path $runRoot "context") -Force | Out-Null
        [ordered]@{
            runId = "run-limited"
            collectedAt = [DateTime]::UtcNow.ToString("o")
            repositoryRoot = $script:Root
            fileCount = 0
            files = @()
            extensionSummary = @()
            analysisInputs = @()
            contextBytes = 0
            limits = [ordered]@{
                maxFileBytes = 1024
                maxTotalBytes = 1024
            }
            notes = @("test")
        } | ConvertTo-Json -Depth 10 |
            Set-Content -Path (Join-Path $runRoot "context/repository.json")
        New-TestRunConfiguration -RunRoot $runRoot -RunId "run-limited" -Config $config -Workflow $workflow | Out-Null

        $result = & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
            -Workflow $workflow `
            -Config $config `
            -Policy $policy `
            -RepositoryRoot $script:Root `
            -RunRoot $runRoot `
            -RunId "run-limited"

        $result.status | Should -Be "blocked"
        $state = Get-Content -Path (Join-Path $runRoot "workflow-state.json") -Raw |
            ConvertFrom-Json -Depth 100
        $state.status | Should -Be "blocked"
        @(Get-ChildItem (Join-Path $runRoot supervisor) -Recurse -Filter supervisor-decision-1.json).Count |
            Should -Be 1
    }
    It "proceeds with recorded dissent when the review stage permits exhaustion" {
        # Reviewers that never reach unanimity used to destroy the whole run at the
        # iteration limit, including every stage that had already succeeded. A stage
        # declaring on_exhaustion: proceed now delivers what it has and carries the
        # dissent forward instead.
        $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $reviewStage = @($workflow.stages | Where-Object id -eq "review")[0]
        $reviewStage.approval.max_iterations = 1
        $reviewStage.approval.on_exhaustion | Should -Be "proceed"
        $runRoot = Join-Path $TestDrive "dissent-run"
        New-Item -ItemType Directory -Path (Join-Path $runRoot "context") -Force | Out-Null
        [ordered]@{
            runId = "run-dissent"
            collectedAt = [DateTime]::UtcNow.ToString("o")
            repositoryRoot = $script:Root
            fileCount = 0
            files = @()
            extensionSummary = @()
            analysisInputs = @()
            contextBytes = 0
            limits = [ordered]@{
                maxFileBytes = 1024
                maxTotalBytes = 1024
            }
            notes = @("test")
        } | ConvertTo-Json -Depth 10 |
            Set-Content -Path (Join-Path $runRoot "context/repository.json")
        New-TestRunConfiguration -RunRoot $runRoot -RunId "run-dissent" -Config $config -Workflow $workflow | Out-Null

        {
            & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                -Workflow $workflow `
                -Config $config `
                -Policy $policy `
                -RepositoryRoot $script:Root `
                -RunRoot $runRoot `
                -RunId "run-dissent"
        } | Should -Not -Throw
        $state = Get-Content -Path (Join-Path $runRoot "workflow-state.json") -Raw |
            ConvertFrom-Json -Depth 100
        $state.status | Should -Not -Be "blocked"
        $reviewRecord = @($state.stages | Where-Object { $_.id -eq "review" })[-1]
        $reviewRecord.status | Should -Be "approved_with_dissent"
        @($state.stages | Where-Object { $_.id -eq "review" }).Count |
            Should -BeGreaterThan 0
    }
    It "blocks when a review stage dissents and has nowhere to send the work" {
        # A parallel_review revises nothing itself, so with no on_reject target
        # there is no improved artifact to carry forward and permission to
        # proceed does not apply. Reading a return target anyway used to crash
        # the run instead of reporting the outcome.
        $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $reviewApproval = (@($workflow.stages | Where-Object id -eq "review")[0]).approval
        $reviewApproval.PSObject.Properties.Remove("on_reject")
        $runRoot = Join-Path $TestDrive "no-return-run"
        New-Item -ItemType Directory -Path (Join-Path $runRoot "context") -Force | Out-Null
        [ordered]@{
            runId = "run-no-return"
            collectedAt = [DateTime]::UtcNow.ToString("o")
            repositoryRoot = $script:Root
            fileCount = 0
            files = @()
            extensionSummary = @()
            analysisInputs = @()
            contextBytes = 0
            limits = [ordered]@{
                maxFileBytes = 1024
                maxTotalBytes = 1024
            }
            notes = @("test")
        } | ConvertTo-Json -Depth 10 |
            Set-Content -Path (Join-Path $runRoot "context/repository.json")
        New-TestRunConfiguration -RunRoot $runRoot -RunId "run-no-return" -Config $config -Workflow $workflow | Out-Null

        $result = & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
            -Workflow $workflow `
            -Config $config `
            -Policy $policy `
            -RepositoryRoot $script:Root `
            -RunRoot $runRoot `
            -RunId "run-no-return"

        $result.status | Should -Be "blocked"
        $state = Get-Content -Path (Join-Path $runRoot "workflow-state.json") -Raw |
            ConvertFrom-Json -Depth 100
        $state.status | Should -Be "blocked"
        $state.currentStage | Should -Be "review"
        @($state.stages | Where-Object id -eq "review")[0].status | Should -Be "blocked"
    }
}

Describe "Agent response JSON recovery" {
    It "accepts a bare JSON object" {
        $recovered = ConvertFrom-QaFoundryAgentJson -RawText '{"status":"completed"}'
        ($recovered | ConvertFrom-Json).status | Should -Be "completed"
    }

    It "recovers the artifact when a conversational CLI narrates before the JSON" {
        $raw = @"
I'll read the request file first.

Large file (781 KB) - reading in sections.

{
  "agentId": "repository-discovery",
  "status": "completed"
}
"@
        $recovered = ConvertFrom-QaFoundryAgentJson -RawText $raw
        ($recovered | ConvertFrom-Json).agentId | Should -Be "repository-discovery"
    }

    It "recovers the artifact from a fenced code block with trailing commentary" {
        $raw = "Here is the result:`n``````json`n{`"status`": `"completed`", `"summary`": `"ok`"}`n```````n`nLet me know if you need more."
        $recovered = ConvertFrom-QaFoundryAgentJson -RawText $raw
        ($recovered | ConvertFrom-Json).summary | Should -Be "ok"
    }

    It "prefers the complete artifact over a smaller example object" {
        $raw = 'Schema example: {"status":"x"}. Final answer: {"agentId":"a","status":"completed","evidence":["e"]}'
        $recovered = ConvertFrom-QaFoundryAgentJson -RawText $raw
        ($recovered | ConvertFrom-Json).agentId | Should -Be "a"
    }

    It "recovers the artifact despite unbalanced narration braces" {
        $raw = 'The template uses {placeholder syntax and returns {"agentId":"a","status":"completed"}'
        $recovered = ConvertFrom-QaFoundryAgentJson -RawText $raw
        ($recovered | ConvertFrom-Json).status | Should -Be "completed"
    }

    It "does not mistake a brace inside a JSON string for structure" {
        $recovered = ConvertFrom-QaFoundryAgentJson -RawText 'note: {"summary":"a } brace \" quoted","status":"completed"}'
        ($recovered | ConvertFrom-Json).summary | Should -Be 'a } brace " quoted'
    }

    It "rejects a response that contains no JSON object" {
        { ConvertFrom-QaFoundryAgentJson -RawText "I cannot complete this task." } |
            Should -Throw "*did not contain a parsable JSON object*"
    }

    It "rejects an empty response" {
        { ConvertFrom-QaFoundryAgentJson -RawText "   " } | Should -Throw "*empty response*"
    }
}

Describe "An artifact the agent started twice" {
    BeforeAll {
        # The shape build 972985 failed on: narration, an artifact abandoned
        # inside a string value that carries an opening brace, and the whole
        # artifact written again after it. The abandoned copy leaves the string
        # open, so a brace scan closes the object in the wrong place and every
        # entry after that looks like a top-level object of its own.
        $script:RestartedArtifact = @'
I'll read the request file first.

{
  "agentId": "framework-implementation",
  "stageId": "implementation",
  "runId": "run-1",
  "status": "completed",
  "summary": "First copy, abandoned part-way through.",
  "commandsProposed": [
    "npx playwright test --{
  "agentId": "framework-implementation",
  "stageId": "implementation",
  "runId": "run-1",
  "status": "completed",
  "summary": "The copy the agent finished.",
  "evidence": [],
  "assumptions": [],
  "unknowns": [],
  "warnings": [],
  "details": { "note": "second copy" },
  "plannedFiles": [
    {
      "path": "automation/Api/Api.csproj",
      "operation": "create",
      "purpose": "The project file, written out at a length that beats the artifact on size alone so that size cannot decide which object is the artifact.",
      "contentContract": "Target net10.0, pin the test packages to the versions the resolver chose, and enable the lock file so the restore is reproducible on a clean checkout."
    },
    {
      "path": "automation/Api/HostAllowlist.cs",
      "operation": "create",
      "purpose": "The allowlist matcher, written out at a length that beats the artifact on size alone so that size cannot decide which object is the artifact.",
      "contentContract": "Match a host against the configured allowlist, fail closed on anything unlisted, and carry no default that reaches the public internet."
    }
  ],
  "commandsProposed": ["dotnet build automation/Api/Api.csproj"]
}
'@
        $script:ArtifactFields = @(
            "agentId", "stageId", "runId", "status", "summary",
            "evidence", "assumptions", "unknowns", "warnings", "details",
            "plannedFiles", "commandsProposed")
    }

    It "keeps the copy the agent finished rather than a fragment of the one it abandoned" {
        $recovered = ConvertFrom-QaFoundryAgentJson -RawText $script:RestartedArtifact `
            -RequiredProperty $script:ArtifactFields
        $artifact = $recovered | ConvertFrom-Json -Depth 100
        $artifact.agentId | Should -Be "framework-implementation"
        $artifact.summary | Should -Be "The copy the agent finished."
        @($artifact.plannedFiles).Count | Should -Be 2
        @($artifact.commandsProposed).Count | Should -Be 1
    }

    It "says what went wrong when no object carries the fields the artifact must have" {
        $withoutRestart = $script:RestartedArtifact.Substring(
            0, $script:RestartedArtifact.IndexOf('"npx playwright test --{')) +
            '"npx playwright test --{ "path": "a.cs", "operation": "create" }'
        { ConvertFrom-QaFoundryAgentJson -RawText $withoutRestart `
            -RequiredProperty $script:ArtifactFields } |
            Should -Throw "*names the required fields*started again*"
    }

    It "still takes the largest parsable object when the caller names no fields" {
        $raw = 'Example: {"a":1}. Answer: {"agentId":"a","status":"completed"}'
        $recovered = ConvertFrom-QaFoundryAgentJson -RawText $raw
        ($recovered | ConvertFrom-Json).agentId | Should -Be "a"
    }

    It "reads the fields an artifact must carry from the schema it is validated against" {
        $fields = @(Get-QaFoundryArtifactRequiredProperty -SchemaPath (Join-Path $script:Root `
            "schemas/implementation/implementation-result.schema.json"))
        # agentId and status are named once, in the shared agent result the
        # implementation schema pulls in through allOf.
        $fields | Should -Contain "agentId"
        $fields | Should -Contain "status"
        $fields | Should -Contain "plannedFiles"
    }

    It "names no fields for a schema that is missing" {
        @(Get-QaFoundryArtifactRequiredProperty -SchemaPath (Join-Path $script:Root `
            "schemas/nothing-here.schema.json")).Count | Should -Be 0
    }
}

Describe "Interrupted run accounting" {
    It "records the abandoned stage instead of resuming a permanently running state" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $workflow = [pscustomobject]@{
            name = "interrupted-demo"
            version = 1
            stages = @([pscustomobject]@{ id = "discovery"; type = "unsupported_stage_type" })
        }
        $runRoot = Join-Path $TestDrive "interrupted-run"
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
        [ordered]@{
            workflowName = "interrupted-demo"
            workflowVersion = 1
            runId = "run-interrupted"
            status = "running"
            currentStage = "discovery"
            stageIteration = 1
            startedAt = [DateTime]::UtcNow.ToString("o")
            updatedAt = [DateTime]::UtcNow.ToString("o")
            stages = @([ordered]@{
                id = "discovery"
                type = "unsupported_stage_type"
                status = "running"
                iteration = 1
                attempts = @()
            })
        } | ConvertTo-Json -Depth 10 |
            Set-Content -Path (Join-Path $runRoot "workflow-state.json") -Encoding utf8

        {
            & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                -Workflow $workflow `
                -Config $config `
                -Policy $policy `
                -RepositoryRoot $script:Root `
                -RunRoot $runRoot `
                -RunId "run-interrupted" `
                -Resume
        } | Should -Throw

        $state = Get-Content -Path (Join-Path $runRoot "workflow-state.json") -Raw |
            ConvertFrom-Json -Depth 100
        $state.status | Should -Be "failed"
        $abandoned = @($state.stages[0].attempts | Where-Object {
            $_.PSObject.Properties.Name -contains "interrupted"
        })
        $abandoned.Count | Should -Be 1
        $abandoned[0].error | Should -Match "stopped before this stage reported a result"
    }
}

Describe "Bounded agent request context" {
    BeforeAll {
        $script:SampleContext = [pscustomobject]@{
            runId = "run-digest"
            collectedAt = [DateTime]::UtcNow.ToString("o")
            repositoryRoot = "C:/repo"
            fileCount = 4
            files = @(
                [pscustomobject]@{ path = "a.cs"; extension = ".cs"; sizeBytes = 10 },
                [pscustomobject]@{ path = "b.cs"; extension = ".cs"; sizeBytes = 20 },
                [pscustomobject]@{ path = "c.png"; extension = ".png"; sizeBytes = 30 },
                [pscustomobject]@{ path = "d.md"; extension = ".md"; sizeBytes = 40 }
            )
            extensionSummary = @([pscustomobject]@{ extension = ".cs"; count = 2 })
            analysisInputs = @(
                [pscustomobject]@{
                    category = "repository"; path = "a.cs"; sizeBytes = 10
                    sha256 = "aa"; included = $true; skipReason = ""; content = "class A {}"
                },
                [pscustomobject]@{
                    category = "repository"; path = "b.cs"; sizeBytes = 20
                    sha256 = "bb"; included = $false; skipReason = "total_context_limit"; content = ""
                },
                [pscustomobject]@{
                    category = "repository"; path = "c.png"; sizeBytes = 30
                    sha256 = "cc"; included = $false; skipReason = "unsupported_text_format"; content = ""
                },
                [pscustomobject]@{
                    category = "repository"; path = "d.md"; sizeBytes = 40
                    sha256 = "dd"; included = $false; skipReason = "total_context_limit"; content = ""
                }
            )
            contextBytes = 10
            limits = [pscustomobject]@{ maxFileBytes = 1024; maxTotalBytes = 2048 }
            notes = @("note")
        }
    }

    It "keeps every collected content entry in the repository projection" {
        $digest = ConvertTo-QaFoundryRepositoryDigest -Context $script:SampleContext
        @($digest.analysisInputs).Count | Should -Be 1
        $digest.analysisInputs[0].path | Should -Be "a.cs"
        $digest.analysisInputs[0].content | Should -Be "class A {}"
    }

    It "collapses content-free entries into skip-reason counts" {
        $digest = ConvertTo-QaFoundryRepositoryDigest -Context $script:SampleContext
        $digest.omittedInputs.count | Should -Be 3
        $reasons = @{}
        foreach ($row in $digest.omittedInputs.byReason) { $reasons[$row.skipReason] = $row.count }
        $reasons["total_context_limit"] | Should -Be 2
        $reasons["unsupported_text_format"] | Should -Be 1
    }

    It "still lists every omitted path in the bounded inventory" {
        $digest = ConvertTo-QaFoundryRepositoryDigest -Context $script:SampleContext
        $digest.inventory.totalFiles | Should -Be 4
        $digest.inventory.truncated | Should -BeFalse
        @($digest.inventory.files.path) | Should -Contain "b.cs"
        @($digest.inventory.files.path) | Should -Contain "d.md"
    }

    It "bounds the inventory and records the truncation" {
        $digest = ConvertTo-QaFoundryRepositoryDigest -Context $script:SampleContext -MaxInventoryEntries 2
        $digest.inventory.listedHere | Should -Be 2
        $digest.inventory.totalFiles | Should -Be 4
        $digest.inventory.truncated | Should -BeTrue
    }

    It "is smaller than the complete artifact it projects" {
        $full = $script:SampleContext | ConvertTo-Json -Depth 30
        $digest = ConvertTo-QaFoundryRepositoryDigest -Context $script:SampleContext |
            ConvertTo-Json -Depth 30
        $digest.Length | Should -BeLessThan $full.Length
    }

    It "references oversized artifacts by path instead of inlining them" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.runtime.context |
            Add-Member -NotePropertyName max_request_bytes -NotePropertyValue 512 -Force

        $runRoot = Join-Path $TestDrive "bounded-run"
        New-Item -ItemType Directory -Path (Join-Path $runRoot "context") -Force | Out-Null
        $bulkPath = Join-Path $runRoot "context/bulk-evidence.json"
        [ordered]@{ payload = ("x" * 4096) } | ConvertTo-Json |
            Set-Content -Path $bulkPath -Encoding utf8
        $smallPath = Join-Path $runRoot "context/sdlc-event.json"
        [ordered]@{ id = "e1" } | ConvertTo-Json | Set-Content -Path $smallPath -Encoding utf8

        $outputPath = Join-Path $runRoot "discovery/repository-discovery.json"
        $null = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "repository-discovery" `
            -StageId "discovery" `
            -RunId "run-bounded" `
            -PromptPath (Join-Path $script:Root "prompts/discovery/repository-discovery.md") `
            -ContextPaths @($bulkPath, $smallPath) `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/discovery/repository-discovery.schema.json") `
            -Config $config

        $request = Get-Content -Path "$outputPath.attempt-1.request.md" -Raw
        $request | Should -Match "Context reference, not inlined:.*bulk-evidence\.json"
        $request | Should -Not -Match "xxxxxxxxxxxxxxxx"
        $request | Should -Match "referenced \(\d+ bytes\)"
        $request | Should -Match "inlined \(\d+ bytes\).*sdlc-event\.json"
    }

    It "states an output size budget when the profile sets one" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai | Add-Member -NotePropertyName max_artifact_bytes `
            -NotePropertyValue 4096 -Force

        $runRoot = Join-Path $TestDrive "budgeted-run"
        $outputPath = Join-Path $runRoot "discovery/repository-discovery.json"
        $null = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "repository-discovery" `
            -StageId "discovery" `
            -RunId "run-budgeted" `
            -PromptPath (Join-Path $script:Root "prompts/discovery/repository-discovery.md") `
            -ContextPaths @() `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/discovery/repository-discovery.schema.json") `
            -Config $config

        $request = Get-Content -Path "$outputPath.attempt-1.request.md" -Raw
        $request | Should -Match "# Output size budget"
        $request | Should -Match "must not exceed 4096 bytes"
    }

    It "omits the output size budget when the profile does not set one" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai | Add-Member -NotePropertyName max_artifact_bytes `
            -NotePropertyValue 0 -Force

        $runRoot = Join-Path $TestDrive "unbudgeted-run"
        $outputPath = Join-Path $runRoot "discovery/repository-discovery.json"
        $null = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "repository-discovery" `
            -StageId "discovery" `
            -RunId "run-unbudgeted" `
            -PromptPath (Join-Path $script:Root "prompts/discovery/repository-discovery.md") `
            -ContextPaths @() `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/discovery/repository-discovery.schema.json") `
            -Config $config

        $request = Get-Content -Path "$outputPath.attempt-1.request.md" -Raw
        $request | Should -Not -Match "# Output size budget"
    }

    It "gives an explicit stage input first claim on the request budget" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.runtime.context |
            Add-Member -NotePropertyName max_request_bytes -NotePropertyValue 3072 -Force

        $runRoot = Join-Path $TestDrive "priority-run"
        New-Item -ItemType Directory -Path (Join-Path $runRoot "context") -Force | Out-Null
        $producerPath = Join-Path $runRoot "context/producer-output.json"
        [ordered]@{ marker = ("p" * 2048) } | ConvertTo-Json |
            Set-Content -Path $producerPath -Encoding utf8
        $rivalPath = Join-Path $runRoot "context/sdlc-event.json"
        [ordered]@{ marker = ("r" * 2048) } | ConvertTo-Json |
            Set-Content -Path $rivalPath -Encoding utf8

        $outputPath = Join-Path $runRoot "discovery/repository-discovery.json"
        $null = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "repository-discovery" `
            -StageId "discovery" `
            -RunId "run-priority" `
            -PromptPath (Join-Path $script:Root "prompts/discovery/repository-discovery.md") `
            -ContextPaths @($rivalPath) `
            -PriorityContextPaths @($producerPath) `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/discovery/repository-discovery.schema.json") `
            -Config $config

        $request = Get-Content -Path "$outputPath.attempt-1.request.md" -Raw
        $request | Should -Match "pppppppppppppppp"
        $request | Should -Not -Match "rrrrrrrrrrrrrrrr"
        $request | Should -Match "Context reference, not inlined:.*sdlc-event\.json"
    }

    It "references an explicit stage input that cannot fit the budget at all" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.runtime.context |
            Add-Member -NotePropertyName max_request_bytes -NotePropertyValue 16 -Force

        $runRoot = Join-Path $TestDrive "priority-overflow-run"
        New-Item -ItemType Directory -Path (Join-Path $runRoot "context") -Force | Out-Null
        $producerPath = Join-Path $runRoot "context/producer-output.json"
        [ordered]@{ marker = ("p" * 2048) } | ConvertTo-Json |
            Set-Content -Path $producerPath -Encoding utf8

        $outputPath = Join-Path $runRoot "discovery/repository-discovery.json"
        $null = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "repository-discovery" `
            -StageId "discovery" `
            -RunId "run-priority-overflow" `
            -PromptPath (Join-Path $script:Root "prompts/discovery/repository-discovery.md") `
            -ContextPaths @() `
            -PriorityContextPaths @($producerPath) `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/discovery/repository-discovery.schema.json") `
            -Config $config

        $request = Get-Content -Path "$outputPath.attempt-1.request.md" -Raw
        $request | Should -Not -Match "pppppppppppppppp"
        $request | Should -Match "Context reference, not inlined:.*producer-output\.json"
    }
}

Describe "Progress reporting helpers" {
    It "Formats sub-minute durations with one decimal second" {
        Format-QaFoundryDuration -Duration ([TimeSpan]::FromSeconds(4.25)) |
            Should -Be "4.3s"
    }

    It "Formats longer durations as whole minutes and seconds" {
        Format-QaFoundryDuration -Duration ([TimeSpan]::FromSeconds(185)) |
            Should -Be "3m 05s"
    }

    It "Formats byte counts across every unit boundary" {
        Format-QaFoundryBytes -Bytes 512 | Should -Be "512 B"
        Format-QaFoundryBytes -Bytes 2048 | Should -Be "2.0 KB"
        Format-QaFoundryBytes -Bytes 3145728 | Should -Be "3.0 MB"
    }

    It "Writes progress to the information stream, never to the success stream" {
        $captured = Write-QaFoundryLog -Message "stage started" -Level step 6>$null
        $captured | Should -BeNullOrEmpty
    }

    It "Indents nested progress and labels the reporting scope" {
        $record = @(Write-QaFoundryLog -Message "calling provider" -Indent 2 `
            -Scope "code-review" -InformationVariable emitted 6>$null)
        $null = $record
        $line = [string]$emitted[0].MessageData
        $line | Should -Be "      -  [code-review] calling provider"
    }

    It "Marks warnings and errors distinctly from routine progress" {
        $null = Write-QaFoundryLog -Message "retrying" -Level warn `
            -InformationVariable warnEmitted 6>$null
        $null = Write-QaFoundryLog -Message "rejected" -Level error `
            -InformationVariable errorEmitted 6>$null
        ([string]$warnEmitted[0].MessageData) | Should -Be "[!]  retrying"
        ([string]$errorEmitted[0].MessageData) | Should -Be "[x]  rejected"
    }
}

Describe "JSON control character repair" {
    It "Escapes a raw newline inside a string literal" {
        $repaired = Repair-QaFoundryJsonControlCharacters -JsonText "{`"a`":`"one`ntwo`"}"
        $repaired | Should -Be '{"a":"one\ntwo"}'
    }

    It "Escapes tabs, carriage returns and exotic control characters" {
        $raw = "{`"a`":`"t`tr`rb`u{0008}f`u{000C}x`u{0001}`"}"
        $repaired = Repair-QaFoundryJsonControlCharacters -JsonText $raw
        $repaired | Should -Be '{"a":"t\tr\rb\bf\fx\u0001"}'
    }

    It "Leaves already escaped sequences untouched" {
        $raw = '{"a":"already\nescaped","b":"trailing backslash pair \\"}'
        Repair-QaFoundryJsonControlCharacters -JsonText $raw | Should -Be $raw
    }

    It "Does not touch formatting whitespace outside string literals" {
        $raw = "{`n  `"a`": 1`n}"
        Repair-QaFoundryJsonControlCharacters -JsonText $raw | Should -Be $raw
    }

    It "Recovers an agent artifact whose strings contain raw newlines" {
        $raw = "Here is the artifact:`n{`"summary`":`"line one`nline two`",`"count`":2}`nHope that helps."
        $recovered = ConvertFrom-QaFoundryAgentJson -RawText $raw
        $recovered | Should -Be '{"summary":"line one\nline two","count":2}'
        ($recovered | ConvertFrom-Json).summary | Should -Be "line one`nline two"
    }

    It "Produces text that a strict JSON.parse implementation accepts" {
        $raw = "{`"summary`":`"line one`nline two`"}"
        $repaired = ConvertFrom-QaFoundryAgentJson -RawText $raw
        $repaired | Should -Not -Match "[`u{0000}-`u{001F}]"
    }
}

Describe "Agent output narration" {
    BeforeAll {
        $script:CriticArtifact = [pscustomobject]@{
            agentId = "architecture-critic"
            status = "completed"
            summary = "The blueprint routes every stage through one shared runspace pool."
            decision = "revision_required"
            confidence = 0.72
            findings = @(
                [pscustomobject]@{ severity = "warning"; message = "Retry budget is shared."; evidence = "e1" },
                [pscustomobject]@{ severity = "critical"; message = "Apply writes outside allowed paths."; evidence = "e2" },
                [pscustomobject]@{ severity = "info"; message = "Naming is consistent."; evidence = "e3" }
            )
            requiredChanges = @("Scope the retry budget per stage.", "Add an idempotency key.")
            warnings = @("CI evidence came from a stale build.")
            unknowns = @("Whether self-hosted agents are allowed.")
        }
    }

    It "Leads with what the agent concluded" {
        $lines = @(Get-QaFoundryArtifactNarration -Artifact $script:CriticArtifact)
        $lines[0].text | Should -Be "Thinks: The blueprint routes every stage through one shared runspace pool."
    }

    It "Reports the verdict with its confidence and marks it for attention" {
        $verdict = @(Get-QaFoundryArtifactNarration -Artifact $script:CriticArtifact) |
            Where-Object { $_.text -like "Verdict:*" }
        $verdict.text | Should -Be "Verdict: revision_required (confidence 0.72)."
        $verdict.level | Should -Be "warn"
    }

    It "Promotes the most severe findings and counts the remainder" {
        $lines = @(Get-QaFoundryArtifactNarration -Artifact $script:CriticArtifact -MaxItems 2)
        $findings = @($lines | Where-Object { $_.text -like "Finds*" })
        $findings.Count | Should -Be 2
        $findings[0].text | Should -Be "Finds (critical): Apply writes outside allowed paths."
        $findings[0].level | Should -Be "error"
        $findings[1].text | Should -Be "Finds (warning): Retry budget is shared."
        @($lines | Where-Object { $_.text -eq "...and 1 further finding(s)." }).Count | Should -Be 1
    }

    It "Repeats the changes the reviewer asked for" {
        $asks = @(Get-QaFoundryArtifactNarration -Artifact $script:CriticArtifact) |
            Where-Object { $_.text -like "Asks for:*" }
        @($asks).Count | Should -Be 2
        @($asks)[0].level | Should -Be "warn"
    }

    It "Narrates a plan as its proposals" {
        $plan = [pscustomobject]@{
            summary = "Two remediations restore the pipeline."
            outcome = "remediation_proposed"
            proposals = @(
                [pscustomobject]@{ title = "Pin the Copilot CLI version"; priority = "high" },
                [pscustomobject]@{ title = "Retry the flaky contract test"; priority = "low" }
            )
        }
        $texts = @(Get-QaFoundryArtifactNarration -Artifact $plan | ForEach-Object { $_.text })
        $texts | Should -Contain "Outcome: remediation_proposed."
        $texts | Should -Contain "Proposes: Pin the Copilot CLI version [high]"
    }

    It "Narrates a change set as a file count with examples" {
        $changeSet = [pscustomobject]@{
            summary = "Adds the bootstrap pipeline."
            changes = @(
                [pscustomobject]@{ operation = "create"; path = "foundry/pipelines/a.yml" },
                [pscustomobject]@{ operation = "update"; path = "foundry/config/project.yaml" }
            )
        }
        $texts = @(Get-QaFoundryArtifactNarration -Artifact $changeSet | ForEach-Object { $_.text })
        $texts | Should -Contain "Plans 2 file change(s)."
        $texts | Should -Contain "Change: create foundry/pipelines/a.yml"
    }

    It "Shortens long prose on a word boundary" {
        $long = [pscustomobject]@{ summary = ("word " * 80).Trim() }
        $text = @(Get-QaFoundryArtifactNarration -Artifact $long -MaxLength 60)[0].text
        $text.Length | Should -BeLessOrEqual 63
        $text | Should -BeLike "Thinks: word word*..."
    }

    It "Collapses embedded newlines so one finding stays one log line" {
        $noisy = [pscustomobject]@{ summary = "first line`nsecond line" }
        @(Get-QaFoundryArtifactNarration -Artifact $noisy)[0].text |
            Should -Be "Thinks: first line second line"
    }

    It "Says nothing about an artifact that carries no narratable field" {
        @(Get-QaFoundryArtifactNarration -Artifact ([pscustomobject]@{ id = "x" })).Count |
            Should -Be 0
    }

    It "Writes narration to the information stream, never to the success stream" {
        $output = Write-QaFoundryArtifactNarration -Artifact $script:CriticArtifact -Scope "critic" 6>$null
        $output | Should -BeNullOrEmpty
        $written = Write-QaFoundryArtifactNarration -Artifact $script:CriticArtifact -Scope "critic" 6>&1
        @($written | Where-Object { "$_" -like "*[critic]*" }).Count | Should -BeGreaterThan 0
    }
}

Describe "Parallel agent configuration isolation" {
    It "hands a runspace an independent copy of the configuration" {
        $config = [pscustomobject]@{
            runtime = [pscustomobject]@{
                progress = [pscustomobject]@{ narrate_agent_output = $true; narration_max_items = 2 }
            }
        }
        $copy = Copy-QaFoundryConfig -Config $config

        $copy.runtime.progress.narrate_agent_output | Should -BeTrue
        $copy.runtime.progress.narration_max_items | Should -Be 2
        [object]::ReferenceEquals($copy, $config) | Should -BeFalse
        [object]::ReferenceEquals($copy.runtime, $config.runtime) | Should -BeFalse

        $copy.runtime.progress.narrate_agent_output = $false
        $config.runtime.progress.narrate_agent_output | Should -BeTrue
    }
}

Describe "Property name reading under StrictMode" {
    It "returns nothing for an object a model emitted without properties" {
        # Build 460 crashed leg 1 here: architecture-critic returned a schema-valid
        # review that approved the blueprint but carried "details": {}. Reading its
        # property names threw, the catch that treats every failure as a rejected
        # artifact deleted the approval, and the model was handed the PowerShell
        # fault as schema feedback three times over.
        { (ConvertFrom-Json '{}').PSObject.Properties.Name } | Should -Throw
        @(Get-QaFoundryPropertyNames -InputObject (ConvertFrom-Json '{}')).Count |
            Should -Be 0
    }

    It "lists the properties an object does carry" {
        @(Get-QaFoundryPropertyNames -InputObject (ConvertFrom-Json '{"a":1,"b":2}')) |
            Should -Be @("a", "b")
    }

    It "treats a missing object as carrying no properties" {
        @(Get-QaFoundryPropertyNames -InputObject $null).Count | Should -Be 0
    }

    It "reads the keys of a dictionary" {
        @(Get-QaFoundryPropertyNames -InputObject @{ only = 1 }) | Should -Be @("only")
    }

    It "keeps an artifact field lookup working on an empty artifact" {
        Get-QaFoundryArtifactField -Artifact (ConvertFrom-Json '{}') -Name "decision" |
            Should -BeNullOrEmpty
        Get-QaFoundryArtifactField -Artifact (ConvertFrom-Json '{"decision":"approved"}') `
            -Name "decision" | Should -Be "approved"
    }
}

Describe "Time budget helpers" {
    It "treats a missing deadline as unlimited" {
        Test-QaFoundryBudgetExhausted -Deadline $null | Should -BeFalse
    }

    It "reports a future deadline as available and a past one as spent" {
        Test-QaFoundryBudgetExhausted -Deadline ([DateTime]::UtcNow.AddMinutes(5)) |
            Should -BeFalse
        Test-QaFoundryBudgetExhausted -Deadline ([DateTime]::UtcNow.AddMinutes(-1)) |
            Should -BeTrue
    }

    It "recognises only its own budget stop signal" {
        { Stop-QaFoundryForBudget -Reason "no time" } | Should -Throw "*no time*"
        try { Stop-QaFoundryForBudget -Reason "no time" }
        catch { Test-QaFoundryBudgetStop -Message $_.Exception.Message | Should -BeTrue }
        Test-QaFoundryBudgetStop -Message "Stage 'review' ended with status 'failed'." |
            Should -BeFalse
        Test-QaFoundryBudgetStop -Message "" | Should -BeFalse
    }

    It "recognises a budget stop that a parallel runspace wrapped on its way out" {
        # Build 459 crashed leg 1 and skipped the seven legs behind it because the
        # marker a critic raised inside a runspace arrived wrapped in the exception
        # EndInvoke throws, so the handover signal read as an ordinary failure.
        $pool = [RunspaceFactory]::CreateRunspacePool(1, 1)
        $pool.Open()
        try {
            $shell = [PowerShell]::Create()
            $shell.RunspacePool = $pool
            $null = $shell.AddScript('throw "QAFOUNDRY_BUDGET_EXHAUSTED: no time for a worthwhile attempt"')
            $async = $shell.BeginInvoke()
            $caught = $null
            try { $null = $shell.EndInvoke($async) } catch { $caught = $_ }
            $shell.Dispose()

            $caught | Should -Not -BeNullOrEmpty
            $caught.Exception.Message.StartsWith("QAFOUNDRY_BUDGET_EXHAUSTED") | Should -BeFalse
            Test-QaFoundryBudgetStop -Message $caught | Should -BeTrue
            Get-QaFoundryBudgetStopMessage -Message $caught |
                Should -Be "QAFOUNDRY_BUDGET_EXHAUSTED: no time for a worthwhile attempt"
        }
        finally { $pool.Dispose() }
    }

    It "keeps an unrelated wrapped failure out of the budget stop path" {
        $inner = [System.InvalidOperationException]::new("the model returned invalid JSON")
        $outer = [System.InvalidOperationException]::new("Parallel agent 'critic' failed", $inner)
        Test-QaFoundryBudgetStop -Message $outer | Should -BeFalse
        Get-QaFoundryBudgetStopMessage -Message $outer | Should -Be ""
    }

    It "describes the remaining budget in words" {
        Format-QaFoundryRemainingBudget -Deadline $null | Should -Be "no deadline"
        Format-QaFoundryRemainingBudget -Deadline ([DateTime]::UtcNow.AddMinutes(-1)) |
            Should -Be "no time left"
        Format-QaFoundryRemainingBudget -Deadline ([DateTime]::UtcNow.AddMinutes(10)) |
            Should -Match "left$"
    }
}

Describe "Run spending budget" {
    BeforeAll {
        function script:New-CallLedgerEntry {
            param(
                [Parameter(Mandatory)][string]$RunRoot,
                [Parameter(Mandatory)][string]$Name,
                [object]$Usage = $null,
                [int]$RequestBytes = 0,
                [int]$ResponseBytes = 0
            )
            $directory = Join-Path $RunRoot "discovery"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $record = [ordered]@{
                id = "run/stage/agent/0/1/artifact"
                request = [ordered]@{ bytes = $RequestBytes; characters = $RequestBytes }
                response = [ordered]@{ bytes = $ResponseBytes; characters = $ResponseBytes }
                usage = $Usage
            }
            $path = Join-Path $directory "$Name.provider-metadata.json"
            $record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $path -Encoding utf8
            return $path
        }

        function script:New-BudgetConfig {
            param([AllowNull()][object]$MaxTotalTokens)
            $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
            if ($null -ne $MaxTotalTokens) {
                Add-Member -InputObject $config.ai -MemberType NoteProperty -Name "run_budget" `
                    -Value ([pscustomobject]@{ max_total_tokens = $MaxTotalTokens }) -Force
            }
            return $config
        }
    }

    It "treats an unstated budget as no budget at all" {
        # The ceiling is opt-in. A configuration that never mentions it must run
        # exactly as it did before this existed, or every repository already
        # using Foundry would stop at a limit nobody chose.
        Get-QaFoundryRunTokenBudget -Config (New-BudgetConfig -MaxTotalTokens $null) | Should -Be 0
        Get-QaFoundryRunTokenBudget -Config (New-BudgetConfig -MaxTotalTokens 0) | Should -Be 0
        Get-QaFoundryRunTokenBudget -Config (New-BudgetConfig -MaxTotalTokens 250000) |
            Should -Be 250000
    }

    It "charges a call what the provider said it cost" {
        $exact = Get-QaFoundryCallTokenCost -Record ([pscustomobject]@{
            request = [pscustomobject]@{ bytes = 40000 }
            response = [pscustomobject]@{ bytes = 8000 }
            usage = [pscustomobject]@{ source = "provider"; totalTokens = 1234 }
        })
        [int]$exact.tokens | Should -Be 1234
        [bool]$exact.estimated | Should -BeFalse

        # A provider that states the two halves but not the sum has still stated
        # what the call cost.
        $halves = Get-QaFoundryCallTokenCost -Record ([pscustomobject]@{
            request = [pscustomobject]@{ bytes = 40000 }
            response = [pscustomobject]@{ bytes = 8000 }
            usage = [pscustomobject]@{ source = "provider"; inputTokens = 900; outputTokens = 100 }
        })
        [int]$halves.tokens | Should -Be 1000
        [bool]$halves.estimated | Should -BeFalse
    }

    It "still charges a call whose provider reported nothing" {
        # Otherwise a provider that declines to report its usage is a way to
        # spend without being counted, and the ceiling would never be reached
        # no matter how long the run went on.
        $estimated = Get-QaFoundryCallTokenCost -Record ([pscustomobject]@{
            request = [pscustomobject]@{ bytes = 4000 }
            response = [pscustomobject]@{ bytes = 800 }
            usage = $null
        })
        [int]$estimated.tokens | Should -Be 1200
        [bool]$estimated.estimated | Should -BeTrue
    }

    It "sums what the whole run has spent and says how much of it was guessed" {
        $runRoot = Join-Path $TestDrive ("spend-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
        $null = New-CallLedgerEntry -RunRoot $runRoot -Name "one" `
            -Usage ([pscustomobject]@{ source = "provider"; totalTokens = 500 })
        $null = New-CallLedgerEntry -RunRoot $runRoot -Name "two" `
            -Usage ([pscustomobject]@{ source = "provider"; totalTokens = 300 })
        $null = New-CallLedgerEntry -RunRoot $runRoot -Name "three" -RequestBytes 400 -ResponseBytes 400

        $spent = Get-QaFoundryRunTokensSpent -RunRoot $runRoot
        [int]$spent.tokens | Should -Be 1000
        [int]$spent.calls | Should -Be 3
        [int]$spent.estimatedCalls | Should -Be 1
    }

    It "keeps counting when an interrupted call left an unreadable record" {
        # A half-written ledger entry is not a reason to abandon the accounting:
        # the calls that did record cleanly still have to be paid for.
        $runRoot = Join-Path $TestDrive ("spend-torn-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
        $null = New-CallLedgerEntry -RunRoot $runRoot -Name "good" `
            -Usage ([pscustomobject]@{ source = "provider"; totalTokens = 700 })
        Set-Content -LiteralPath (Join-Path $runRoot "discovery/torn.provider-metadata.json") `
            -Encoding utf8 -Value '{ "id": "run/stage/agent/0/1/artif'

        $spent = Get-QaFoundryRunTokensSpent -RunRoot $runRoot
        [int]$spent.tokens | Should -Be 700
        [int]$spent.calls | Should -Be 1
    }

    It "reports the run as overspent only once it has reached its ceiling" {
        $runRoot = Join-Path $TestDrive ("ceiling-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
        $null = New-CallLedgerEntry -RunRoot $runRoot -Name "one" `
            -Usage ([pscustomobject]@{ source = "provider"; totalTokens = 900 })

        Test-QaFoundryRunBudgetExhausted -RunRoot $runRoot `
            -Config (New-BudgetConfig -MaxTotalTokens 1000) | Should -BeNullOrEmpty
        Test-QaFoundryRunBudgetExhausted -RunRoot $runRoot `
            -Config (New-BudgetConfig -MaxTotalTokens $null) | Should -BeNullOrEmpty

        $detail = Test-QaFoundryRunBudgetExhausted -RunRoot $runRoot `
            -Config (New-BudgetConfig -MaxTotalTokens 900)
        $detail | Should -Match "900 token"
        $detail | Should -Match "run budget of 900"
    }

    It "tells a run that must stop apart from a leg that should be resumed" {
        # The two signals travel the same route and mean opposite things. If
        # either were read as the other, a run out of budget would be resumed by
        # the next leg and keep spending, or a leg out of time would be treated
        # as a terminal failure and lose the work behind it.
        try { Stop-QaFoundryForRunBudget -Reason "the run has spent 10 tokens" }
        catch {
            Test-QaFoundryRunBudgetStop -Message $_ | Should -BeTrue
            Test-QaFoundryBudgetStop -Message $_ | Should -BeFalse
            Get-QaFoundryRunBudgetStopMessage -Message $_ |
                Should -Be "QAFOUNDRY_RUN_BUDGET_EXHAUSTED: the run has spent 10 tokens"
        }
        try { Stop-QaFoundryForBudget -Reason "no time" }
        catch {
            Test-QaFoundryBudgetStop -Message $_ | Should -BeTrue
            Test-QaFoundryRunBudgetStop -Message $_ | Should -BeFalse
        }
        Test-QaFoundryRunBudgetStop -Message "Stage 'review' ended with status 'failed'." |
            Should -BeFalse
        Test-QaFoundryRunBudgetStop -Message "" | Should -BeFalse
    }

    It "blocks a run that has spent its budget instead of pausing it" {
        # A pause invites the next leg to carry on, which is the one thing an
        # overspent run must not do. The ledger planted here stands for the
        # calls a previous leg of the same run already made.
        Push-Location $script:Root
        try {
            $config = Set-ResolvedTestAiProfile -Config (New-BudgetConfig -MaxTotalTokens 1000)
            $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
            $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
            $runRoot = Join-Path $TestDrive "overspent-run"
            New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
            $null = New-CallLedgerEntry -RunRoot $runRoot -Name "earlier-leg" `
                -Usage ([pscustomobject]@{ source = "provider"; totalTokens = 4000 })

            New-TestRunConfiguration -RunRoot $runRoot -RunId "run-overspent-test" `
                -Config $config -Workflow $workflow | Out-Null
            $blocked = & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                -Workflow $workflow `
                -Config $config `
                -Policy $policy `
                -RepositoryRoot $script:Root `
                -RunRoot $runRoot `
                -RunId "run-overspent-test"

            $blocked.status | Should -Be "blocked"
            $blocked.status | Should -Not -Be "paused"
            $blocked.currentStage | Should -Be ([string]$workflow.stages[0].id)

            $onDisk = Get-Content -Path (Join-Path $runRoot "workflow-state.json") -Raw |
                ConvertFrom-Json -Depth 100
            $onDisk.status | Should -Be "blocked"

            # Nothing was bought with money the run did not have.
            @(Get-ChildItem -Path $runRoot -Recurse -Filter "*.json" |
                Where-Object {
                    $_.Name -ne "workflow-state.json" -and
                    $_.Name -notlike "*.provider-metadata.json" -and
                    $_.Directory.Name -ne "context"
                }).Count | Should -Be 0
        }
        finally {
            Pop-Location
        }
    }

    It "lets a raised allowance continue the run it stopped rather than pay twice" {
        # Build 972449 stopped at stage 10 of 13 with 25.1M tokens of finished
        # work behind it. Refusing to resume would have thrown all of it away
        # over a number chosen too low - so a block for spending is undone by
        # raising the allowance, unlike a block for judgement.
        Push-Location $script:Root
        try {
            $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
            $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
            $runRoot = Join-Path $TestDrive "raised-allowance-run"
            New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
            $null = New-CallLedgerEntry -RunRoot $runRoot -Name "earlier-leg" `
                -Usage ([pscustomobject]@{ source = "provider"; totalTokens = 4000 })

            $tight = Set-ResolvedTestAiProfile -Config (New-BudgetConfig -MaxTotalTokens 1000)
            New-TestRunConfiguration -RunRoot $runRoot -RunId "run-raised-test" `
                -Config $tight -Workflow $workflow | Out-Null
            $blocked = & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                -Workflow $workflow -Config $tight -Policy $policy `
                -RepositoryRoot $script:Root -RunRoot $runRoot -RunId "run-raised-test"
            $blocked.status | Should -Be "blocked"
            $blocked.blockedReason | Should -Be "run_budget_exhausted"

            # Still short: the reason for stopping has not gone away, so neither
            # has the refusal.
            $stillTight = Set-ResolvedTestAiProfile -Config (New-BudgetConfig -MaxTotalTokens 2000)
            { & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                -Workflow $workflow -Config $stillTight -Policy $policy `
                -RepositoryRoot $script:Root -RunRoot $runRoot -RunId "run-raised-test" -Resume } |
                Should -Throw "*explicit new run*"

            $raised = Set-ResolvedTestAiProfile -Config (New-BudgetConfig -MaxTotalTokens 5000000)
            $finished = & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                -Workflow $workflow -Config $raised -Policy $policy `
                -RepositoryRoot $script:Root -RunRoot $runRoot -RunId "run-raised-test" -Resume

            $finished.status | Should -Be "completed"
            $finished.blockedReason | Should -BeNullOrEmpty
            # The stage that never ran must not come back with an attempt
            # already charged against its iteration limit.
            $firstStage = @($finished.stages |
                Where-Object { $_.id -eq [string]$workflow.stages[0].id })[0]
            [int]$firstStage.iteration | Should -Be 1
        }
        finally {
            Pop-Location
        }
    }

    It "still refuses to resume a run a decision blocked" {
        # The distinction is the whole point: a critic that said no, or coverage
        # a stage could not finish, is a judgement that raising an allowance
        # does not answer.
        $runRoot = Join-Path $TestDrive "judged-block-run"
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
        $config = Set-ResolvedTestAiProfile -Config (New-BudgetConfig -MaxTotalTokens 5000000)
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
        New-TestRunConfiguration -RunRoot $runRoot -RunId "run-judged-test" `
            -Config $config -Workflow $workflow | Out-Null

        $state = [pscustomobject][ordered]@{
            workflowName = [string]$workflow.name
            workflowVersion = [int]$workflow.version
            runId = "run-judged-test"
            status = "blocked"
            currentStage = [string]$workflow.stages[0].id
            stageIteration = 1
            blockedReason = $null
            startedAt = [DateTime]::UtcNow.ToString("o")
            updatedAt = [DateTime]::UtcNow.ToString("o")
            stages = @($workflow.stages | ForEach-Object {
                [pscustomobject][ordered]@{
                    id = [string]$_.id
                    type = [string]$_.type
                    status = "pending"
                    iteration = 0
                    attempts = @()
                }
            })
        }
        & (Join-Path $script:Root "scripts/Save-WorkflowState.ps1") -State $state `
            -Path (Join-Path $runRoot "workflow-state.json")

        { & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
            -Workflow $workflow -Config $config -Policy $policy `
            -RepositoryRoot $script:Root -RunRoot $runRoot -RunId "run-judged-test" -Resume } |
            Should -Throw "*blocked by a decision rather than by its budget*"
    }
}

Describe "Artifact reuse across legs" {
    BeforeAll {
        $script:ReuseConfig = Set-ResolvedTestAiProfile -Config (
            Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root)
        $script:ReuseSchemaPath = Join-Path $script:Root `
            "schemas/discovery/repository-discovery.schema.json"

        function script:Invoke-ReuseAgent {
            param([string]$OutputPath, [switch]$AllowExisting)
            return & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
                -AgentId "repository-discovery" `
                -StageId "discovery" `
                -RunId "run-reuse-test" `
                -PromptPath (Join-Path $script:Root "prompts/discovery/repository-discovery.md") `
                -ContextPaths @() `
                -OutputPath $OutputPath `
                -SchemaPath $script:ReuseSchemaPath `
                -Config $script:ReuseConfig `
                -AllowExistingArtifact:$AllowExisting
        }
    }

    It "still refuses to overwrite an artifact when reuse was not requested" {
        $output = Join-Path $TestDrive "reuse-immutable/result.json"
        $null = Invoke-ReuseAgent -OutputPath $output
        { Invoke-ReuseAgent -OutputPath $output } |
            Should -Throw "*Immutable agent artifact already exists*"
    }

    It "reuses a valid artifact instead of calling the model again" {
        $output = Join-Path $TestDrive "reuse-valid/result.json"
        $null = Invoke-ReuseAgent -OutputPath $output
        $firstWrite = (Get-Item $output).LastWriteTimeUtc
        $rawBefore = @(Get-ChildItem -Path (Split-Path $output -Parent) -Filter "*.raw.txt").Count

        $reused = Invoke-ReuseAgent -OutputPath $output -AllowExisting

        $reused | Should -Not -BeNullOrEmpty
        (Get-Item $output).LastWriteTimeUtc | Should -Be $firstWrite
        @(Get-ChildItem -Path (Split-Path $output -Parent) -Filter "*.raw.txt").Count |
            Should -Be $rawBefore
    }

    It "discards an artifact that no longer satisfies its schema and produces it again" {
        $output = Join-Path $TestDrive "reuse-invalid/result.json"
        $null = Invoke-ReuseAgent -OutputPath $output
        Set-Content -Path $output -Value '{ "summary": "truncated by a killed job" }' -Encoding utf8

        $repaired = Invoke-ReuseAgent -OutputPath $output -AllowExisting

        $repaired | Should -Not -BeNullOrEmpty
        $onDisk = Get-Content -Path $output -Raw | ConvertFrom-Json -Depth 100
        $onDisk.summary | Should -Not -Be "truncated by a killed job"
        $null = & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $output `
            -SchemaPath $script:ReuseSchemaPath `
            -SchemaRoot (Join-Path $script:Root "schemas")
    }
}

Describe "Relay across job legs" {
    It "pauses instead of starting work it cannot finish, then completes on the next leg" {
        Push-Location $script:Root
        try {
            $config = Set-ResolvedTestAiProfile -Config (
                Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root)
            $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
            $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
            $runRoot = Join-Path $TestDrive "relay-run"
            New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

            New-TestRunConfiguration -RunRoot $runRoot -RunId "run-relay-test" -Config $config -Workflow $workflow | Out-Null
            $paused = & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                -Workflow $workflow `
                -Config $config `
                -Policy $policy `
                -RepositoryRoot $script:Root `
                -RunRoot $runRoot `
                -RunId "run-relay-test" `
                -Deadline ([DateTime]::UtcNow.AddMinutes(-1))

            $paused.status | Should -Be "paused"
            $paused.currentStage | Should -Be ([string]$workflow.stages[0].id)
            @(Get-ChildItem -Path $runRoot -Recurse -Filter "*.json" |
                Where-Object { $_.Name -ne "workflow-state.json" -and $_.Directory.Name -ne "context" }).Count |
                Should -Be 0

            $onDisk = Get-Content -Path (Join-Path $runRoot "workflow-state.json") -Raw |
                ConvertFrom-Json -Depth 100
            $onDisk.status | Should -Be "paused"

            $finished = & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                -Workflow $workflow `
                -Config $config `
                -Policy $policy `
                -RepositoryRoot $script:Root `
                -RunRoot $runRoot `
                -RunId "run-relay-test" `
                -Resume

            $finished.status | Should -Be "completed"

            # Nothing a mock provider wrote was chosen by anyone, so resolving
            # its dependencies would install whatever answers to those invented
            # names and write a lock as though a decision stood behind it. A
            # mocked run rehearses materialisation whatever else it is told.
            $materialised = Get-ChildItem -LiteralPath $runRoot -Recurse -Filter "change-set.json" |
                Select-Object -First 1
            $materialised | Should -Not -BeNullOrEmpty
            $changeSet = Get-Content -LiteralPath $materialised.FullName -Raw |
                ConvertFrom-Json -Depth 100
            [bool]$changeSet.details.dryRun | Should -BeTrue
        }
        finally {
            Pop-Location
        }
    }

    It "keeps the artifacts an interrupted stage already produced" {
        Push-Location $script:Root
        try {
            $config = Set-ResolvedTestAiProfile -Config (
                Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root)
            $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
            $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
            $runRoot = Join-Path $TestDrive "relay-partial"
            New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

            New-TestRunConfiguration -RunRoot $runRoot -RunId "run-relay-partial" -Config $config -Workflow $workflow | Out-Null
            $first = & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                -Workflow $workflow `
                -Config $config `
                -Policy $policy `
                -RepositoryRoot $script:Root `
                -RunRoot $runRoot `
                -RunId "run-relay-partial" `
                -Deadline ([DateTime]::UtcNow.AddSeconds(3))

            $first.status | Should -BeIn @("paused", "completed")
            if ($first.status -eq "paused") {
                $produced = @(Get-ChildItem -Path $runRoot -Recurse -Filter "*.json" |
                    Where-Object { $_.Name -ne "workflow-state.json" -and $_.Directory.Name -ne "context" })
                $fingerprints = @{}
                foreach ($artifact in $produced) {
                    $fingerprints[$artifact.FullName] = $artifact.LastWriteTimeUtc
                }

                $second = & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                    -Workflow $workflow `
                    -Config $config `
                    -Policy $policy `
                    -RepositoryRoot $script:Root `
                    -RunRoot $runRoot `
                    -RunId "run-relay-partial" `
                    -Resume

                $second.status | Should -Be "completed"
                foreach ($path in $fingerprints.Keys) {
                    (Get-Item $path).LastWriteTimeUtc | Should -Be $fingerprints[$path]
                }
            }
        }
        finally {
            Pop-Location
        }
    }
}

Describe "Pull request traceability" {
    BeforeAll {
        $script:PrRepository = Join-Path $TestDrive "pr-repository"
        $script:PrRemote = Join-Path $TestDrive "pr-remote.git"
        $script:PrRunRoot = Join-Path $TestDrive "pr-run"
        New-Item -ItemType Directory -Path $script:PrRepository -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:PrRunRoot "planning") -Force | Out-Null
        & git init --bare $script:PrRemote | Out-Null
        & git -C $script:PrRepository init | Out-Null
        & git -C $script:PrRepository config user.email "foundry-tests@example.invalid"
        & git -C $script:PrRepository config user.name "Foundry Tests"
        Set-Content -Path (Join-Path $script:PrRepository "README.md") -Value "baseline"
        & git -C $script:PrRepository add README.md
        & git -C $script:PrRepository commit -m "baseline" | Out-Null
        & git -C $script:PrRepository branch -M main
        & git -C $script:PrRepository remote add origin $script:PrRemote
        New-Item -ItemType Directory -Path (Join-Path $script:PrRepository "automation") -Force | Out-Null
        Set-Content -Path (Join-Path $script:PrRepository "automation/proof.txt") -Value "approved" -NoNewline
        @{ changes = @(@{ path = "automation/proof.txt"; operation = "create"; content = "approved" }) } | ConvertTo-Json -Depth 10 |
            Set-Content -Path (Join-Path $script:PrRunRoot "planning/change-set.json")

        # A work item creation result from earlier in the same run.
        [ordered]@{
            runId = "run-pr"
            stageId = "create-work-items"
            handler = "create_work_items"
            status = "completed"
            dryRun = $false
            actions = @(
                [ordered]@{ sourceRef = "pbi-1"; status = "executed"; externalId = "4001" },
                [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" },
                [ordered]@{ sourceRef = "task-2"; status = "dry_run"; externalId = "" }
            )
        } | ConvertTo-Json -Depth 10 |
            Set-Content -Path (Join-Path $script:PrRunRoot "planning/action-result.json") -Encoding utf8
    }

    It "links the work items the run created and honours a configured reviewer group" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.delivery.provider = "azure-devops"
        $config.delivery.dry_run = $false
        $config.delivery.create_branch = $true
        $config.delivery.commit_changes = $true
        $config.delivery.push_branch = $true
        $config.delivery.create_draft_pull_request = $true
        $config.delivery.reviewers = @("qa-reviewers-group-id")
        $config.delivery | Add-Member -NotePropertyName pull_request_draft `
            -NotePropertyValue $false -Force
        $config.delivery.azure_devops.organization_url = "https://dev.azure.com/example"
        $config.delivery.azure_devops.project = "product"
        $config.delivery.azure_devops.repository_id = "repo-id"
        Mock Invoke-RestMethod {
            param($Uri, $Method, $Body)
            if ($Uri -like "*/_apis/connectionData?*") {
                return New-TestAdoConnectionData
            }
            if ($Uri -like "*/refs?*") { return [pscustomobject]@{ count = 0; value = @() } }
            if ($Uri -like "*/pullrequests?*" -and "$Method" -eq "Get") {
                return [pscustomobject]@{ count = 0; value = @() }
            }
            $global:PrRequestBody = $Body
            return [pscustomobject]@{ pullRequestId = 91 }
        }

        $result = & (Join-Path $script:Root "scripts/writers/Publish-RepositoryDelivery.ps1") `
            -Config $config -RepositoryRoot $script:PrRepository -RunRoot $script:PrRunRoot `
            -RunId "run-pr" -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }

        $sent = $global:PrRequestBody | ConvertFrom-Json -Depth 20
        $sent.isDraft | Should -BeFalse
        @($sent.workItemRefs.id) | Should -Be @("4001", "4002")
        @($sent.reviewers.id) | Should -Be @("qa-reviewers-group-id")
        @($result.actions | Where-Object { $_.type -eq "pull-request.draft" }).summary |
            Should -Match "^Create pull request linked to work item\(s\) 4001, 4002 for 1 reviewer\(s\)$"
    }

    It "refuses to open a pull request when a required reviewer is not configured" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.delivery.provider = "azure-devops"
        $config.delivery.dry_run = $false
        $config.delivery.create_branch = $true
        $config.delivery.commit_changes = $true
        $config.delivery.push_branch = $true
        $config.delivery.create_draft_pull_request = $true
        $config.delivery.reviewers = @()
        $config.delivery | Add-Member -NotePropertyName require_reviewer_group `
            -NotePropertyValue $true -Force
        $config.delivery.azure_devops.organization_url = "https://dev.azure.com/example"
        $config.delivery.azure_devops.project = "product"
        $config.delivery.azure_devops.repository_id = "repo-id"

        { & (Join-Path $script:Root "scripts/writers/Publish-RepositoryDelivery.ps1") `
            -Config $config -RepositoryRoot $script:PrRepository -RunRoot $script:PrRunRoot `
            -RunId "run-pr-reviewer" -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" } } |
            Should -Throw "*require_reviewer_group is true but delivery.reviewers is empty*"
    }
}

Describe "Work item hierarchy" {
    BeforeAll {
        $script:HierarchyConfig = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $script:HierarchyConfig.work_tracking.provider = "azure-devops"
        $script:HierarchyConfig.work_tracking.enabled = $true
        $script:HierarchyConfig.work_tracking.dry_run = $false
        $script:HierarchyConfig.work_tracking.azure_devops.organization_url = "https://dev.azure.com/example"
        $script:HierarchyConfig.work_tracking.azure_devops.project = "product"
        # Two repositories delivering into one Azure DevOps project name their
        # items the same way, so the marker has to carry which repository this
        # is. The writer refuses to create anything without it.
        $script:HierarchyConfig.delivery.azure_devops.organization_url =
            "https://dev.azure.com/example"
        $script:HierarchyConfig.delivery.azure_devops.project = "product"
        $script:HierarchyConfig.delivery.azure_devops.repository_id = "repo-under-test"
        $script:HierarchyConfig.idempotency.enabled = $false

        function script:New-HierarchyPlan {
            param([object[]]$Items)
            $repository = Join-Path $TestDrive ("hierarchy-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
            New-Item -ItemType Directory -Path $repository -Force | Out-Null
            $planPath = Join-Path $repository "work-item-plan.json"
            [ordered]@{ outcome = "proposed"; items = $Items } | ConvertTo-Json -Depth 20 |
                Set-Content -Path $planPath -Encoding utf8
            return [pscustomobject]@{ Repository = $repository; PlanPath = $planPath }
        }

        function script:New-PlanItem {
            param([string]$Ref, [string]$Type, [string]$ParentRef = "")
            $item = [ordered]@{
                sourceRef = $Ref; type = $Type; title = "Item $Ref"; description = "Description $Ref"
                priority = 2; tags = @(); acceptanceCriteria = @("Works")
            }
            if (-not [string]::IsNullOrWhiteSpace($ParentRef)) { $item["parentRef"] = $ParentRef }
            return $item
        }
    }

    It "creates the backlog item first and hangs its tasks off it" {
        $plan = New-HierarchyPlan -Items @(
            (New-PlanItem -Ref "task-1" -Type "task" -ParentRef "pbi-1"),
            (New-PlanItem -Ref "pbi-1" -Type "backlog_item")
        )
        $global:CreatedBodies = [System.Collections.Generic.List[string]]::new()
        $global:NextId = 5000
        Mock Invoke-RestMethod {
            param($Uri, $Body)
            if ($Uri -like "*/_apis/connectionData?*") {
                return New-TestAdoConnectionData
            }
            if ($Uri -like "*/_apis/wit/workitemtypecategories?*") {
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{
                        referenceName = "Microsoft.RequirementCategory"
                        defaultWorkItemType = [pscustomobject]@{ name = "Product Backlog Item" }
                    }
                ) }
            }
            if ($Uri -like "*/_apis/wit/wiql*") {
                # The durable marker lookup. A document without workItems means
                # the query failed, so the writer must not read a plain value
                # collection as "nothing exists yet".
                return [pscustomobject]@{ workItems = @() }
            }
            if ($Uri -notlike "*/_apis/wit/workitems/*") {
                return [pscustomobject]@{ value = @() }
            }
            $global:CreatedBodies.Add([string]$Body)
            $global:NextId = $global:NextId + 1
            return [pscustomobject]@{ id = $global:NextId }
        }

        $result = & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
            -PlanPath $plan.PlanPath -Config $script:HierarchyConfig `
            -RepositoryRoot $plan.Repository -RunId "run-hierarchy" `
            -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }

        @($result.actions.sourceRef) | Should -Be @("pbi-1", "task-1")
        $global:CreatedBodies.Count | Should -Be 2
        ($global:CreatedBodies[0] | ConvertFrom-Json -Depth 20).path |
            Should -Not -Contain "/relations/-"
        $childPatch = $global:CreatedBodies[1] | ConvertFrom-Json -Depth 20
        $relation = @($childPatch | Where-Object { $_.path -eq "/relations/-" })
        $relation.Count | Should -Be 1
        $relation[0].value.rel | Should -Be "System.LinkTypes.Hierarchy-Reverse"
        $relation[0].value.url | Should -Match "/workItems/5001$"
    }

    It "hands the older item back when another run created one at the same moment" {
        $plan = New-HierarchyPlan -Items @((New-PlanItem -Ref "pbi-1" -Type "backlog_item"))
        $global:CreatedId = 0
        $global:Patched = [System.Collections.Generic.List[object]]::new()
        $global:WiqlCalls = 0
        Mock Invoke-RestMethod {
            param($Uri, $Method, $Body)
            if ($Uri -like "*/_apis/connectionData?*") { return New-TestAdoConnectionData }
            if ($Uri -like "*/_apis/wit/workitemtypecategories?*") {
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{
                        referenceName = "Microsoft.RequirementCategory"
                        defaultWorkItemType = [pscustomobject]@{ name = "Product Backlog Item" }
                    }
                ) }
            }
            if ($Uri -like "*/_apis/wit/wiql*") {
                $global:WiqlCalls = $global:WiqlCalls + 1
                # Nothing exists when asked the first time, so this run creates.
                # By the time it asks again the other run's item has landed, and
                # it is the older of the two.
                if ($global:WiqlCalls -eq 1) { return [pscustomobject]@{ workItems = @() } }
                return [pscustomobject]@{ workItems = @(
                    [pscustomobject]@{ id = 6001 }, [pscustomobject]@{ id = 4000 }
                ) }
            }
            if ($Uri -notlike "*/_apis/wit/workitems/*") { return [pscustomobject]@{ value = @() } }
            if ([string]$Method -eq "Patch") {
                $global:Patched.Add([pscustomobject]@{ uri = [string]$Uri; body = [string]$Body })
                return [pscustomobject]@{ id = 6001 }
            }
            $global:CreatedId = 6001
            return [pscustomobject]@{ id = $global:CreatedId }
        }

        $result = & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
            -PlanPath $plan.PlanPath -Config $script:HierarchyConfig `
            -RepositoryRoot $plan.Repository -RunId "run-hierarchy-race" `
            -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }

        $action = @($result.actions)[0]
        $action.status | Should -Be "duplicate"
        $action.externalId | Should -Be "4000"
        $action.summary | Should -Match "4000 is the one used"
        $global:Patched.Count | Should -Be 1
        $global:Patched[0].uri | Should -Match "/workitems/6001\?"
        ($global:Patched[0].body | ConvertFrom-Json -Depth 10).value |
            Should -Match "sdlc-foundry-duplicate-of-4000"
    }

    It "remembers the item the race left standing so the next run adds no third" {
        $plan = New-HierarchyPlan -Items @((New-PlanItem -Ref "pbi-1" -Type "backlog_item"))
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.work_tracking.provider = "azure-devops"
        $config.work_tracking.enabled = $true
        $config.work_tracking.dry_run = $false
        $config.work_tracking.azure_devops.organization_url = "https://dev.azure.com/example"
        $config.work_tracking.azure_devops.project = "product"
        $config.delivery.azure_devops.repository_id = "repo-under-test"
        $config.idempotency.enabled = $true
        $global:WiqlCalls = 0
        Mock Invoke-RestMethod {
            param($Uri, $Method)
            if ($Uri -like "*/_apis/connectionData?*") { return New-TestAdoConnectionData }
            if ($Uri -like "*/_apis/wit/workitemtypecategories?*") {
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{
                        referenceName = "Microsoft.RequirementCategory"
                        defaultWorkItemType = [pscustomobject]@{ name = "Product Backlog Item" }
                    }
                ) }
            }
            if ($Uri -like "*/_apis/wit/wiql*") {
                $global:WiqlCalls = $global:WiqlCalls + 1
                if ($global:WiqlCalls -eq 1) { return [pscustomobject]@{ workItems = @() } }
                return [pscustomobject]@{ workItems = @(
                    [pscustomobject]@{ id = 6001 }, [pscustomobject]@{ id = 4000 }
                ) }
            }
            if ($Uri -notlike "*/_apis/wit/workitems/*") { return [pscustomobject]@{ value = @() } }
            return [pscustomobject]@{ id = 6001 }
        }

        $null = & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
            -PlanPath $plan.PlanPath -Config $config `
            -RepositoryRoot $plan.Repository -RunId "run-hierarchy-race-registry" `
            -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }

        $registryPath = Join-Path $plan.Repository ([string]$config.idempotency.registry_path)
        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json -Depth 50
        $record = @($registry.records)[0]
        # The project holds an item for this reference, so the next run must
        # reuse it. Recording the race itself would make that run create a third,
        # and 'duplicate' is not a status this registry's schema even allows.
        $record.status | Should -Be "executed"
        $record.externalId | Should -Be "4000"
        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $registryPath `
                -SchemaPath (Join-Path $script:Root "schemas/runtime/idempotency-registry.schema.json") `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Not -Throw
    }

    It "refuses to file work items when nothing identifies this repository" {
        # The schema lets repository_id be an empty string, and work tracking can
        # be live while delivery is not configured at all. Either way the marker
        # collapses to an organisation and a project every repository shares, and
        # the next repository's run adopts this one's items.
        $plan = New-HierarchyPlan -Items @((New-PlanItem -Ref "pbi-1" -Type "backlog_item"))
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.work_tracking.provider = "azure-devops"
        $config.work_tracking.enabled = $true
        $config.work_tracking.dry_run = $false
        $config.work_tracking.azure_devops.organization_url = "https://dev.azure.com/example"
        $config.work_tracking.azure_devops.project = "product"
        $config.delivery.azure_devops.repository_id = ""
        Mock Invoke-RestMethod { throw "Nothing may be created without a repository identity." }

        {
            & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
                -PlanPath $plan.PlanPath -Config $config `
                -RepositoryRoot $plan.Repository -RunId "run-hierarchy-no-identity" `
                -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        } | Should -Throw "*identifies this repository*"
    }

    It "identifies the repository by its own remote when the configuration names none" {
        # A checkout knows where it came from. That is a weaker identity than a
        # configured repository id - a fork carries the same remote - but it is
        # this repository's own name rather than every repository's.
        $plan = New-HierarchyPlan -Items @((New-PlanItem -Ref "pbi-1" -Type "backlog_item"))
        & git -C $plan.Repository init | Out-Null
        & git -C $plan.Repository remote add origin "https://dev.azure.com/example/_git/repo-b" |
            Out-Null
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.work_tracking.provider = "azure-devops"
        $config.work_tracking.enabled = $true
        $config.work_tracking.dry_run = $false
        $config.work_tracking.azure_devops.organization_url = "https://dev.azure.com/example"
        $config.work_tracking.azure_devops.project = "product"
        $config.delivery.azure_devops.repository_id = ""
        $config.idempotency.enabled = $false
        $global:MarkerTags = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-RestMethod {
            param($Uri, $Body)
            if ($Uri -like "*/_apis/connectionData?*") { return New-TestAdoConnectionData }
            if ($Uri -like "*/_apis/wit/workitemtypecategories?*") {
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{
                        referenceName = "Microsoft.RequirementCategory"
                        defaultWorkItemType = [pscustomobject]@{ name = "Product Backlog Item" }
                    }
                ) }
            }
            if ($Uri -like "*/_apis/wit/wiql*") {
                $global:MarkerTags.Add([string]$Body)
                return [pscustomobject]@{ workItems = @() }
            }
            if ($Uri -notlike "*/_apis/wit/workitems/*") { return [pscustomobject]@{ value = @() } }
            return [pscustomobject]@{ id = 7001 }
        }

        $result = & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
            -PlanPath $plan.PlanPath -Config $config `
            -RepositoryRoot $plan.Repository -RunId "run-hierarchy-remote-identity" `
            -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }

        @($result.actions)[0].status | Should -Be "executed"
        # The marker this repository queried is not the one the same plan would
        # produce anywhere else.
        $queried = ($global:MarkerTags -join " ")
        $queried | Should -Match "sdlc-foundry-ref-[0-9a-f]{20}"
        $elsewhere = & (Join-Path $script:Root "scripts/New-IdempotencyKey.ps1") `
            -ActionType "work-item.azure-devops" -SourceRef "pbi-1" `
            -Scope "https://dev.azure.com/example|product|https://dev.azure.com/example/_git/repo-a"
        $queried | Should -Not -Match $elsewhere.Substring(0, 20)
    }

    It "refuses a task whose parent is not in the plan" {        $plan = New-HierarchyPlan -Items @(
            (New-PlanItem -Ref "task-1" -Type "task" -ParentRef "missing-pbi")
        )
        {
            & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
                -PlanPath $plan.PlanPath -Config $script:HierarchyConfig `
                -RepositoryRoot $plan.Repository -RunId "run-hierarchy-missing" `
                -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        } | Should -Throw "*which the plan does not contain*"
    }

    It "refuses a parent cycle" {
        $plan = New-HierarchyPlan -Items @(
            (New-PlanItem -Ref "a" -Type "backlog_item" -ParentRef "b"),
            (New-PlanItem -Ref "b" -Type "backlog_item" -ParentRef "a")
        )
        {
            & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
                -PlanPath $plan.PlanPath -Config $script:HierarchyConfig `
                -RepositoryRoot $plan.Repository -RunId "run-hierarchy-cycle" `
                -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        } | Should -Throw "*parent cycle*"
    }

    It "refuses a task hanging off another task" {
        $plan = New-HierarchyPlan -Items @(
            (New-PlanItem -Ref "parent-task" -Type "task" -ParentRef "pbi-1"),
            (New-PlanItem -Ref "child-task" -Type "task" -ParentRef "parent-task"),
            (New-PlanItem -Ref "pbi-1" -Type "backlog_item")
        )
        {
            & (Join-Path $script:Root "scripts/writers/New-WorkItems.ps1") `
                -PlanPath $plan.PlanPath -Config $script:HierarchyConfig `
                -RepositoryRoot $plan.Repository -RunId "run-hierarchy-task-parent" `
                -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        } | Should -Throw "*cannot hang off task*"
    }

    It "requires every task to name its backlog item" {
        $planPath = Join-Path $TestDrive "task-without-parent.json"
        [ordered]@{
            stageId = "backlog"; runId = "run-schema"; summary = "Plan"; status = "completed"
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @()
            details = [ordered]@{}
            outcome = "proposed"
            items = @((New-PlanItem -Ref "task-1" -Type "task"))
        } | ConvertTo-Json -Depth 20 | Set-Content -Path $planPath -Encoding utf8

        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $planPath `
                -SchemaPath (Join-Path $script:Root "schemas/actions/work-item-plan.schema.json") `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Throw "*parentRef*"
    }
}

Describe "Truncated agent responses" {
    It "reports a cut-off answer instead of the fragment it carried" {
        $prose = "Here is a small example: " + ('{"note":"example"}') + " and now the artifact: "
        $padding = "x" * 60000
        $truncated = $prose + '{"agentId":"automation-architect","details":{"blueprint":"' + $padding
        { ConvertFrom-QaFoundryAgentJson -RawText $truncated } |
            Should -Throw "*QAFOUNDRY_TRUNCATED_RESPONSE*"
    }

    It "reports a cut-off answer that recovered nothing at all" {
        $truncated = '{"agentId":"a","summary":"' + ("y" * 40000)
        { ConvertFrom-QaFoundryAgentJson -RawText $truncated } |
            Should -Throw "*ends inside an unterminated JSON value*"
    }

    It "does not mistake narration around a complete artifact for truncation" {
        $artifact = [ordered]@{ agentId = "a"; details = @{ body = ("z" * 40000) } } |
            ConvertTo-Json -Depth 10 -Compress
        $wrapped = "Some narration first. $artifact Some narration after."
        $recovered = ConvertFrom-QaFoundryAgentJson -RawText $wrapped
        ($recovered | ConvertFrom-Json -Depth 10).agentId | Should -Be "a"
    }

    It "does not treat a small unterminated response as a truncated artifact" {
        { ConvertFrom-QaFoundryAgentJson -RawText 'The value is {"a": 1' } |
            Should -Throw "*did not contain a parsable JSON object*"
    }

    It "recognises an open string and an open object as unterminated" {
        Test-QaFoundryJsonTruncated -Text '{"a":"b"}' | Should -BeFalse
        Test-QaFoundryJsonTruncated -Text '{"a":"b"' | Should -BeTrue
        Test-QaFoundryJsonTruncated -Text '{"a":"unclosed' | Should -BeTrue
        Test-QaFoundryJsonTruncated -Text 'no json here' | Should -BeFalse
    }

    It "recognises only its own truncation signal" {
        Test-QaFoundryTruncationFailure -Message "QAFOUNDRY_TRUNCATED_RESPONSE: cut off" |
            Should -BeTrue
        Test-QaFoundryTruncationFailure -Message "must have required property 'agentId'" |
            Should -BeFalse
    }
}

Describe "Answers the provider's secret filter has edited" {
    BeforeAll {
        # Built rather than written, so this file does not carry the literal the
        # filter looks for and get edited on its way through a review.
        $script:RedactionMark = [string]::new([char]42, 6)
    }

    It "recognises the filter's mark and not an ordinary run of asterisks" {
        Test-QaFoundryRedactedText -Text ("head " + $script:RedactionMark + " tail") | Should -BeTrue
        Test-QaFoundryRedactedText -Text "a *** b" | Should -BeFalse
        Test-QaFoundryRedactedText -Text "const scheme = 'Bearer';" | Should -BeFalse
        Test-QaFoundryRedactedText -Text "" | Should -BeFalse
    }

    It "blames the filter rather than the model when the edited answer will not parse" {
        # The filter takes the delimiter next to what it removes, so the answer
        # arrives as unparsable JSON. Reported as generic bad JSON it would send
        # the agent back to write the same thing again.
        $edited = '{"summary":"s","changes":[{"path":"a.ts","content":"h: `' +
            $script:RedactionMark + ' };"'
        { ConvertFrom-QaFoundryAgentJson -RawText $edited } |
            Should -Throw "*QAFOUNDRY_REDACTED_RESPONSE*"
    }

    It "tells the agent how to write the value so the filter leaves it alone" {
        $edited = '{"changes":[{"content":"' + $script:RedactionMark
        $message = ""
        try { $null = ConvertFrom-QaFoundryAgentJson -RawText $edited }
        catch { $message = $_.Exception.Message }
        $message | Should -BeLike "*build*from parts*"
    }

    It "still reports an ordinary unparsable answer as unparsable" {
        { ConvertFrom-QaFoundryAgentJson -RawText 'The value is {"a": 1' } |
            Should -Throw "*did not contain a parsable JSON object*"
    }

    It "recognises only its own redaction signal" {
        Test-QaFoundryRedactionFailure -Message "QAFOUNDRY_REDACTED_RESPONSE: edited" |
            Should -BeTrue
        Test-QaFoundryRedactionFailure -Message "QAFOUNDRY_TRUNCATED_RESPONSE: cut off" |
            Should -BeFalse
    }

    It "will not admit an edited file body even when the JSON around it is valid" {
        # The filter only breaks the JSON when it eats a delimiter. When it eats
        # the inside of a string the answer parses, passes its schema, merges,
        # and is applied as source that does not compile. Build 496 shipped
        # exactly that and spent a review cycle being told so.
        $directory = Join-Path $TestDrive ("redacted-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $assignmentPath = Join-Path $directory "assignment-batch-01.json"
        [ordered]@{
            batchId = "batch-01"; ordinal = 1; batchCount = 1; estimatedBytes = 1024
            assignedFiles = @([ordered]@{
                path = "automation/lib/auth.ts"; operation = "create"
                purpose = "Build the authorization header."; contentContract = "c"
            })
            assignedPaths = @("automation/lib/auth.ts")
            allApprovedPaths = @("automation/lib/auth.ts")
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $assignmentPath -Encoding utf8

        $output = Join-Path $directory "change-set-batch.json"
        [ordered]@{
            agentId = "bootstrap-change-generator-batch-01"
            stageId = "bootstrap-change-generation"
            runId = "run-redacted"; status = "completed"; summary = "One file."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"; batchId = "batch-01"
            changes = @([ordered]@{
                operation = "create"; path = "automation/lib/auth.ts"; expectedSha256 = ""
                content = "export const h = { Authorization: " + $script:RedactionMark + " };"
                reason = "Build the authorization header."; sourceRefs = @()
            })
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $output -Encoding utf8

        $agentArguments = @{
            AgentId = "bootstrap-change-generator-batch-01"
            StageId = "bootstrap-change-generation"
            RunId = "run-redacted"
            PromptPath = (Join-Path $script:Root "prompts/sdlc/bootstrap-plan-generator.md")
            ContextPaths = @($assignmentPath)
            OutputPath = $output
            SchemaPath = (Join-Path $script:Root "schemas/actions/change-set-batch.schema.json")
            Config = (Set-ResolvedTestAiProfile -Config (
                Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root))
            AllowExistingArtifact = $true
        }
        $null = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") @agentArguments

        # The artifact was schema-valid, so only the semantic check could have
        # rejected it. Whatever is on disk now, it is not the edited body.
        $onDisk = Get-Content -LiteralPath $output -Raw
        Test-QaFoundryRedactedText -Text $onDisk | Should -BeFalse
        (Get-Content -LiteralPath $output -Raw | ConvertFrom-Json -Depth 100).changes[0].content |
            Should -Not -BeLike "*Authorization*"
    }
}

Describe "AI profile resolution" {
    It "carries the artifact size budget from the profile into the resolved config" {
        # The budget only works if it survives profile resolution; a whitelist that
        # forgets it leaves every request silently unbounded.
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $resolved = & (Join-Path $script:Root "scripts/Resolve-AiProfile.ps1") `
            -Config $config -ProfileName "copilot"
        $resolved.PSObject.Properties.Name | Should -Contain "max_artifact_bytes"
        $resolved.max_artifact_bytes | Should -Be ([int]$config.ai.profiles.copilot.max_artifact_bytes)
        $resolved.max_artifact_bytes | Should -BeGreaterThan 0
    }

    It "reports no budget when the profile does not declare one" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config.ai.profiles.mock.PSObject.Properties.Remove("max_artifact_bytes")
        $resolved = & (Join-Path $script:Root "scripts/Resolve-AiProfile.ps1") `
            -Config $config -ProfileName "mock"
        $resolved.max_artifact_bytes | Should -Be 0
    }
}

Describe "Producer revision ledger" {
    BeforeAll {
        function script:New-TestCriticHistory {
            return @(
                [pscustomobject]@{
                    revision = 1
                    criticId = "architecture-critic"
                    decision = "revision_required"
                    findings = @([pscustomobject]@{
                        severity = "error"
                        message = "ARC-01 no rollback path"
                        evidence = "blueprint section 4"
                    })
                    requiredChanges = @("Describe a rollback path.")
                },
                [pscustomobject]@{
                    revision = 1
                    criticId = "architecture-security-critic"
                    decision = "revision_required"
                    findings = @([pscustomobject]@{
                        severity = "critical"
                        message = "SEC-01 secrets in logs"
                        evidence = "blueprint section 7"
                    })
                    requiredChanges = @("Redact secrets from logs.")
                },
                [pscustomobject]@{
                    revision = 2
                    criticId = "architecture-critic"
                    decision = "approved"
                    findings = @()
                    requiredChanges = @()
                },
                [pscustomobject]@{
                    revision = 2
                    criticId = "architecture-security-critic"
                    decision = "revision_required"
                    findings = @([pscustomobject]@{
                        severity = "error"
                        message = "SEC-02 redaction is too narrow"
                        evidence = "revision 2 section 7"
                    })
                    requiredChanges = @("Redact secrets from every sink.")
                }
            )
        }
    }

    It "names the critics that already approved so their concerns are not reopened" {
        $ledger = New-QaFoundryRevisionLedger -RunId "run-1" -StageId "architecture" `
            -Revision 3 -History (New-TestCriticHistory)
        $ledger.revision | Should -Be 3
        $ledger.previousRevision | Should -Be 2
        @($ledger.settledCritics).Count | Should -Be 1
        $ledger.settledCritics[0].criticId | Should -Be "architecture-critic"
        $ledger.settledCritics[0].approvedAtRevision | Should -Be 2
    }

    It "carries an earlier demand forward only once its critic approved a later revision" {
        $ledger = New-QaFoundryRevisionLedger -RunId "run-1" -StageId "architecture" `
            -Revision 3 -History (New-TestCriticHistory)
        @($ledger.honouredCommitments | ForEach-Object { $_.change }) |
            Should -Contain "Describe a rollback path."
        # The security critic answered revision 2 with "redaction is too narrow", so the
        # redaction it demanded in revision 1 was never met. Reporting it as honoured told
        # the producer to hold a commitment the critic had already refused.
        @($ledger.honouredCommitments | Where-Object {
            $_.change -eq "Redact secrets from logs."
        }).Count | Should -Be 0
        @($ledger.honouredCommitments | Where-Object {
            $_.change -eq "Redact secrets from every sink."
        }).Count | Should -Be 0
    }

    It "drops a critic from settled once it rejects a later revision" {
        $history = @(
            [pscustomobject]@{
                revision = 1
                criticId = "architecture-critic"
                decision = "approved"
                findings = @()
                requiredChanges = @()
            },
            [pscustomobject]@{
                revision = 2
                criticId = "architecture-critic"
                decision = "revision_required"
                findings = @([pscustomobject]@{
                    severity = "error"
                    message = "ARC-09 the rollback path regressed"
                    evidence = "revision 2 section 4"
                })
                requiredChanges = @("Restore the rollback path.")
            }
        )
        $ledger = New-QaFoundryRevisionLedger -RunId "run-1" -StageId "architecture" `
            -Revision 3 -History $history
        @($ledger.settledCritics).Count | Should -Be 0
        @($ledger.outstandingChanges | ForEach-Object { $_.change }) |
            Should -Contain "Restore the rollback path."
    }

    It "settles a returning critic from the revision it approved again" {
        $history = @(
            [pscustomobject]@{
                revision = 1
                criticId = "architecture-critic"
                decision = "approved"
                findings = @()
                requiredChanges = @()
            },
            [pscustomobject]@{
                revision = 2
                criticId = "architecture-critic"
                decision = "revision_required"
                findings = @([pscustomobject]@{
                    severity = "error"
                    message = "ARC-09 the rollback path regressed"
                    evidence = "revision 2 section 4"
                })
                requiredChanges = @("Restore the rollback path.")
            },
            [pscustomobject]@{
                revision = 3
                criticId = "architecture-critic"
                decision = "approved"
                findings = @()
                requiredChanges = @()
            }
        )
        $ledger = New-QaFoundryRevisionLedger -RunId "run-1" -StageId "architecture" `
            -Revision 4 -History $history
        @($ledger.settledCritics).Count | Should -Be 1
        $ledger.settledCritics[0].approvedAtRevision | Should -Be 3
        @($ledger.honouredCommitments | ForEach-Object { $_.change }) |
            Should -Contain "Restore the rollback path."
    }

    It "asks only for what the latest round still rejects" {
        $ledger = New-QaFoundryRevisionLedger -RunId "run-1" -StageId "architecture" `
            -Revision 3 -History (New-TestCriticHistory)
        @($ledger.outstandingFindings).Count | Should -Be 1
        $ledger.outstandingFindings[0].message | Should -Be "SEC-02 redaction is too narrow"
        $ledger.outstandingFindings[0].criticId | Should -Be "architecture-security-critic"
        @($ledger.outstandingChanges).Count | Should -Be 1
        $ledger.outstandingChanges[0].change | Should -Be "Redact secrets from every sink."
    }

    It "produces a ledger the schema accepts" {
        $ledger = New-QaFoundryRevisionLedger -RunId "run-1" -StageId "architecture" `
            -Revision 3 -History (New-TestCriticHistory)
        $path = Join-Path $TestDrive "revision-ledger.json"
        $ledger | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding utf8
        { & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $path `
            -SchemaPath (Join-Path $script:Root "schemas/architecture/revision-ledger.schema.json") `
            -SchemaRoot (Join-Path $script:Root "schemas") } | Should -Not -Throw
    }

    It "reaches the producer on every revision of a producer-critic loop" {
        Push-Location $script:Root
        try {
            $run = & (Join-Path $script:Root "scripts/Invoke-QaFoundry.ps1") `
                -ConfigPath $script:ConfigPath `
                -WorkflowPath $script:WorkflowPath `
                -PolicyPath $script:PolicyPath `
                -Demo
            $ledgers = @(Get-ChildItem -Path (Join-Path $run.runRoot "architecture") `
                -Recurse -Filter "revision-ledger.json" -File)
            $architectRequests = @(Get-ChildItem -Path (Join-Path $run.runRoot "architecture") `
                -Recurse -Filter "automation-blueprint.json.attempt-*.request.md" -File |
                Where-Object { $_.Directory.Name -like "critic-iteration-*" })
            @($ledgers).Count | Should -BeGreaterThan 0
            $architectRequests.Count | Should -BeGreaterThan 0
            @($architectRequests | Where-Object {
                (Get-Content -Path $_.FullName -Raw) -notmatch "revision-ledger\.json"
            }).Count | Should -Be 0
            $ledger = Get-Content -Path $ledgers[0].FullName -Raw | ConvertFrom-Json -Depth 100
            @($ledger.outstandingChanges | ForEach-Object { $_.change }) |
                Should -Contain "Describe how secrets are supplied and redacted."
            @($ledger.settledCritics | ForEach-Object { $_.criticId }) |
                Should -Contain "architecture-critic"
        }
        finally {
            Pop-Location
        }
    }
}

Describe "Automation blueprint bounds" {
    BeforeAll {
        $script:BlueprintSchema = Join-Path $script:Root `
            "schemas/architecture/automation-blueprint.schema.json"
        $script:BlueprintFixture = Join-Path $script:Root `
            "tests/fixtures/blueprints/bounded-blueprint.json"
        function script:Test-Blueprint {
            param([Parameter(Mandatory)][object]$Blueprint)
            $path = Join-Path $TestDrive ("blueprint-" + [Guid]::NewGuid().ToString("N") + ".json")
            $Blueprint | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding utf8
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $path `
                -SchemaPath $script:BlueprintSchema `
                -SchemaRoot (Join-Path $script:Root "schemas")
        }
        function script:Get-Blueprint {
            return (Get-Content -Path $script:BlueprintFixture -Raw |
                ConvertFrom-Json -Depth 100)
        }
    }

    It "accepts a real blueprint an architect actually produced" {
        # The fixture is the first-round artifact from a live run: the schema has to fit
        # what the agent genuinely writes, not an idealised shape.
        { Test-Blueprint -Blueprint (Get-Blueprint) } | Should -Not -Throw
    }

    It "refuses a section the architect invented to answer a critic" {
        $blueprint = Get-Blueprint
        $blueprint.details | Add-Member -NotePropertyName revisionResponse `
            -NotePropertyValue @("Finding 1 is resolved by the new sanitiser.") -Force
        { Test-Blueprint -Blueprint $blueprint } |
            Should -Throw "*revisionResponse*"
    }

    It "names the offending section so the retry can act on the feedback" {
        $blueprint = Get-Blueprint
        $blueprint.details | Add-Member -NotePropertyName secretScanning `
            -NotePropertyValue ([pscustomobject]@{ gate = "npm run secretscan" }) -Force
        { Test-Blueprint -Blueprint $blueprint } |
            Should -Throw "*must NOT have additional properties ('secretScanning')*"
    }

    It "caps a list that grows instead of a decision that changes" {
        $blueprint = Get-Blueprint
        $blueprint.details.proposedCommands = @(1..21 | ForEach-Object {
            [pscustomobject]@{ id = "cmd-$_"; command = "npm run task-$_" }
        })
        { Test-Blueprint -Blueprint $blueprint } | Should -Throw "*more than 20 items*"
    }

    It "caps prose so a revision cannot answer findings by writing more" {
        $blueprint = Get-Blueprint
        $blueprint.details.decision.rationale = "x" * 801
        { Test-Blueprint -Blueprint $blueprint } | Should -Throw "*more than 800 characters*"
    }

    It "still requires the sections a blueprint is worthless without" {
        $blueprint = Get-Blueprint
        $blueprint.details.PSObject.Properties.Remove("stack")
        { Test-Blueprint -Blueprint $blueprint } | Should -Throw "*'stack'*"
    }

    It "insists the architect names the automation projects it decided on" {
        $blueprint = Get-Blueprint
        $blueprint.details.PSObject.Properties.Remove("automationProjects")
        { Test-Blueprint -Blueprint $blueprint } | Should -Throw "*'automationProjects'*"
    }

    It "requires at least two projects for the API and UI deliverables" {
        $blueprint = Get-Blueprint
        $blueprint.details.automationProjects = @($blueprint.details.automationProjects[0])
        { Test-Blueprint -Blueprint $blueprint } | Should -Throw "*fewer than 2 items*"
    }

    It "refuses the pile of projects the sprint cannot maintain" {
        $blueprint = Get-Blueprint
        $template = $blueprint.details.automationProjects[0]
        $blueprint.details.automationProjects = @(1..5 | ForEach-Object {
            [pscustomobject]@{
                name = "project-$_"
                path = "automation/project-$_"
                purpose = $template.purpose
            }
        })
        { Test-Blueprint -Blueprint $blueprint } | Should -Throw "*more than 4 items*"
    }

    It "refuses a project that says where but never why" {
        $blueprint = Get-Blueprint
        $blueprint.details.automationProjects[0].PSObject.Properties.Remove("purpose")
        { Test-Blueprint -Blueprint $blueprint } | Should -Throw "*'purpose'*"
    }
}

Describe "Recorded technology choices" {
    BeforeAll {
        $script:RationaleCheck = Join-Path $script:Root "scripts/Test-ProjectRationale.ps1"
    }

    It "accepts an inventory where every project records why its stack was chosen" {
        $findings = @(& $script:RationaleCheck -DocumentName "technology-choices.md" -PlannedFiles @(
            [pscustomobject]@{ path = "automation/api/fixtures.ts"; project = "automation-api" }
            [pscustomobject]@{ path = "automation/api/technology-choices.md"; project = "automation-api" }
            [pscustomobject]@{ path = "automation/ui/fixtures.ts"; project = "automation-ui" }
            [pscustomobject]@{ path = "automation/ui/technology-choices.md"; project = "automation-ui" }
            [pscustomobject]@{ path = "docs/automation.md" }
        ))
        $findings.Count | Should -Be 0
    }

    It "names the projects that would arrive without an explanation" {
        # The reasoning is settled in the blueprint and thrown away with the run
        # directory. A project whose stack is undocumented is one nobody can
        # question a year later.
        $findings = @(& $script:RationaleCheck -DocumentName "technology-choices.md" -PlannedFiles @(
            [pscustomobject]@{ path = "automation/api/technology-choices.md"; project = "automation-api" }
            [pscustomobject]@{ path = "automation/ui/fixtures.ts"; project = "automation-ui" }
        ))
        $findings.Count | Should -Be 1
        $findings[0] | Should -Match "automation-ui"
        $findings[0] | Should -Not -Match "automation-api"
    }

    It "refuses to be satisfied by a differently cased file name" {
        # The agent runs on Linux, where TECHNOLOGY-CHOICES.md and
        # technology-choices.md are two different files and only one of them is
        # the one everybody was told to look for.
        $findings = @(& $script:RationaleCheck -DocumentName "technology-choices.md" -PlannedFiles @(
            [pscustomobject]@{ path = "automation/api/TECHNOLOGY-CHOICES.md"; project = "automation-api" }
        ))
        $findings.Count | Should -Be 1
    }

    It "reports an inventory that never says which project a file belongs to" {
        $findings = @(& $script:RationaleCheck -DocumentName "technology-choices.md" -PlannedFiles @(
            [pscustomobject]@{ path = "automation/package.json" }
        ))
        $findings.Count | Should -Be 1
        $findings[0] | Should -Match "which automation project"
    }
}

Describe "Implementation stage output" {
    BeforeAll {
        $script:ImplementationSchema = Join-Path $script:Root `
            "schemas/implementation/implementation-result.schema.json"
        function script:New-ImplementationResult {
            return [pscustomobject]@{
                agentId = "framework-implementation"
                stageId = "implementation"
                runId = "run-1"
                status = "completed"
                summary = "Specified the automation foundation."
                confidence = 0.9
                evidence = @()
                assumptions = @()
                unknowns = @()
                warnings = @()
                details = [pscustomobject]@{}
                plannedFiles = @(
                    [pscustomobject]@{
                        path = "automation/package.json"
                        operation = "create"
                        purpose = "Declare the automation workspace."
                        contentContract = "Private npm package with a playwright devDependency and one script per approved project."
                    }
                )
                commandsProposed = @("npm ci")
            }
        }
        function script:Test-Implementation {
            param([Parameter(Mandatory)][object]$Result)
            $path = Join-Path $TestDrive ("implementation-" + [Guid]::NewGuid().ToString("N") + ".json")
            $Result | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding utf8
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $path `
                -SchemaPath $script:ImplementationSchema `
                -SchemaRoot (Join-Path $script:Root "schemas")
        }
    }

    It "accepts an inventory of files the change generator can write" {
        { Test-Implementation -Result (New-ImplementationResult) } | Should -Not -Throw
    }

    It "no longer asks for files the agent has no way to change" {
        $schema = Get-Content -Path $script:ImplementationSchema -Raw
        $schema | Should -Not -Match "filesChanged"
    }

    It "refuses a planned file with no contract to write against" {
        $result = New-ImplementationResult
        $result.plannedFiles[0].PSObject.Properties.Remove("contentContract")
        { Test-Implementation -Result $result } | Should -Throw "*'contentContract'*"
    }

    It "refuses an operation the deterministic applier would not accept here" {
        $result = New-ImplementationResult
        $result.plannedFiles[0].operation = "execute"
        { Test-Implementation -Result $result } | Should -Throw "*operation*"
    }

    It "tells the implementation agents that they do not write the files themselves" {
        foreach ($name in @("framework-implementation", "test-implementation")) {
            $prompt = Get-Content -Path (Join-Path $script:Root "prompts/implementation/$name.md") -Raw
            $prompt | Should -Match "no write tool"
            $prompt | Should -Match "not a stop condition"
        }
    }
}

Describe "Reported write paths" {
    BeforeAll {
        $script:PathConfig = [pscustomobject]@{
            repository = [pscustomobject]@{
                allowed_write_paths = @("automation/", "docs/")
                forbidden_write_paths = @("automation/secrets/", "src/")
            }
        }
    }

    It "refuses a planned file outside the configured write scope" {
        {
            & (Join-Path $script:Root "scripts/Test-RepositoryPathScope.ps1") `
                -Path "CommodityPricingService.Api/Program.cs" `
                -Config $script:PathConfig `
                -RepositoryRoot $TestDrive
        } | Should -Throw "*outside allowed_write_paths*"
    }

    It "refuses a forbidden path even when it sits under an allowed one" {
        {
            & (Join-Path $script:Root "scripts/Test-RepositoryPathScope.ps1") `
                -Path "automation/secrets/token.txt" `
                -Config $script:PathConfig `
                -RepositoryRoot $TestDrive
        } | Should -Throw "*forbidden path*"
    }

    It "accepts a path the blueprint is allowed to claim" {
        $scoped = & (Join-Path $script:Root "scripts/Test-RepositoryPathScope.ps1") `
            -Path "automation/playwright.config.ts" `
            -Config $script:PathConfig `
            -RepositoryRoot $TestDrive
        $scoped.relativePath | Should -Be "automation/playwright.config.ts"
    }

    It "tells every agent which prefixes it may actually write to" {
        # An agent that is only told to respect "configured write paths" has to guess,
        # and a sensible guess outside the whitelist costs the whole run.
        Push-Location $script:Root
        try {
            $run = & (Join-Path $script:Root "scripts/Invoke-QaFoundry.ps1") `
                -ConfigPath $script:ConfigPath `
                -WorkflowPath $script:WorkflowPath `
                -PolicyPath $script:PolicyPath `
                -Demo
            $requests = @(Get-ChildItem -Path $run.runRoot -Recurse -File `
                -Filter "*.request.md")
            $requests.Count | Should -BeGreaterThan 0
            $withoutScope = @($requests | Where-Object {
                (Get-Content -Path $_.FullName -Raw) -notmatch "# Repository write scope"
            })
            $withoutScope.Count | Should -Be 0
            $sample = Get-Content -Path $requests[0].FullName -Raw
            $sample | Should -Match "Writable prefixes:"
            $sample | Should -Match "automation/"
            $sample | Should -Match "Explicitly forbidden:"
        }
        finally {
            Pop-Location
        }
    }
}

Describe "Automation project naming convention" {
    BeforeAll {
        function script:New-NamedRepository {
            param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string[]]$Projects)

            $repository = Join-Path $TestDrive $Name
            foreach ($project in $Projects) {
                $directory = Join-Path $repository $project
                New-Item -ItemType Directory -Path $directory -Force | Out-Null
                Set-Content -Path (Join-Path $directory "$project.csproj") -Value "<Project />" -Encoding utf8
            }
            return $repository
        }

        function script:Get-NamingConvention {
            param([Parameter(Mandatory)][string]$RepositoryRoot, [string]$FixedPrefix = "")

            return & (Join-Path $script:Root "scripts/Get-RepositoryNamingConvention.ps1") `
                -RepositoryRoot $RepositoryRoot `
                -FixedPrefix $FixedPrefix
        }
    }

    It "derives the prefix from the repository's own project names" {
        $repository = New-NamedRepository -Name "dotted" -Projects @(
            "Contoso.Billing.Api", "Contoso.Billing.Api.Tests", "Contoso.Billing.Worker"
        )
        $convention = Get-NamingConvention -RepositoryRoot $repository
        $convention.detected | Should -BeTrue
        $convention.prefix | Should -Be "Contoso.Billing"
        $convention.separator | Should -Be "."
        $convention.template | Should -Be "Contoso.Billing.Automation.{scope}"
    }

    It "follows the repository's separator and casing rather than a house style" {
        $repository = Join-Path $TestDrive "kebab"
        foreach ($component in @("acme-shop-api", "acme-shop-web", "acme-shop-worker")) {
            New-Item -ItemType Directory -Path (Join-Path $repository $component) -Force | Out-Null
        }
        $convention = Get-NamingConvention -RepositoryRoot $repository
        $convention.detected | Should -BeTrue
        $convention.template | Should -Be "acme-shop-automation-{scope}"
        $convention.example | Should -Be "acme-shop-automation-api"
    }

    It "claims no convention when the repository has none to copy" {
        $repository = Join-Path $TestDrive "flat"
        foreach ($component in @("api", "web", "worker")) {
            New-Item -ItemType Directory -Path (Join-Path $repository $component) -Force | Out-Null
        }
        $convention = Get-NamingConvention -RepositoryRoot $repository
        $convention.detected | Should -BeFalse
        $convention.template | Should -BeNullOrEmpty
    }

    It "prefers a configured prefix over the detected one" {
        $repository = New-NamedRepository -Name "overridden" -Projects @(
            "Contoso.Billing.Api", "Contoso.Billing.Worker"
        )
        $convention = Get-NamingConvention -RepositoryRoot $repository -FixedPrefix "Northwind.Sales"
        $convention.prefix | Should -Be "Northwind.Sales"
        $convention.evidence | Should -Be "configured prefix"
    }

    It "shows the architect the convention it is expected to follow" {
        $repository = New-NamedRepository -Name "requested" -Projects @(
            "Fabrikam.Pricing.Api", "Fabrikam.Pricing.Worker"
        )
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config

        $outputPath = Join-Path $TestDrive "naming-run/architecture/automation-blueprint.json"
        New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null
        $artifact = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "automation-architect" `
            -StageId "architecture" `
            -RunId "run-naming" `
            -PromptPath (Join-Path $script:Root "prompts/architecture/automation-architect.md") `
            -ContextPaths @() `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/architecture/automation-blueprint.schema.json") `
            -Config $config `
            -RepositoryRoot $repository

        $request = Get-Content -Path "$outputPath.attempt-1.request.md" -Raw
        $request | Should -Match "# Project naming convention"
        $request | Should -Match "Fabrikam\.Pricing\.Automation\.\{scope\}"
        foreach ($project in @($artifact.details.automationProjects)) {
            $project.name | Should -BeLike "Fabrikam.Pricing.Automation.*"
        }
    }

    It "refuses a blueprint that names its projects off-convention" {
        $repository = New-NamedRepository -Name "refused" -Projects @(
            "Fabrikam.Pricing.Api", "Fabrikam.Pricing.Worker"
        )
        $convention = Get-NamingConvention -RepositoryRoot $repository
        {
            & (Join-Path $script:Root "scripts/Test-AutomationProjectName.ps1") `
                -Name "automation-api" `
                -Convention $convention
        } | Should -Throw "*Fabrikam.Pricing.Automation.{scope}*"
    }

    It "refuses a name that is the bare prefix with no scope of its own" {
        $repository = New-NamedRepository -Name "bare" -Projects @(
            "Fabrikam.Pricing.Api", "Fabrikam.Pricing.Worker"
        )
        $convention = Get-NamingConvention -RepositoryRoot $repository
        {
            & (Join-Path $script:Root "scripts/Test-AutomationProjectName.ps1") `
                -Name "Fabrikam.Pricing.Automation." `
                -Convention $convention
        } | Should -Throw "*does not follow this repository's convention*"
    }

    It "accepts a name that carries the convention forward" {
        $repository = New-NamedRepository -Name "accepted" -Projects @(
            "Fabrikam.Pricing.Api", "Fabrikam.Pricing.Worker"
        )
        $convention = Get-NamingConvention -RepositoryRoot $repository
        $accepted = & (Join-Path $script:Root "scripts/Test-AutomationProjectName.ps1") `
            -Name "Fabrikam.Pricing.Automation.Integration" `
            -Convention $convention
        $accepted | Should -BeTrue
    }

    It "leaves naming alone when the repository has no convention to enforce" {
        $repository = Join-Path $TestDrive "unconstrained"
        foreach ($component in @("api", "web")) {
            New-Item -ItemType Directory -Path (Join-Path $repository $component) -Force | Out-Null
        }
        $convention = Get-NamingConvention -RepositoryRoot $repository
        $accepted = & (Join-Path $script:Root "scripts/Test-AutomationProjectName.ps1") `
            -Name "whatever-the-architect-likes" `
            -Convention $convention
        $accepted | Should -BeTrue
    }
}

Describe "Dependency materialisation" {

    It "recovers missing resolver recipes after <Case>" -ForEach @(
        @{ Case = 'a source-only repair'; Intermediate = $false; OmitProperty = $false },
        @{ Case = 'two source-only repairs'; Intermediate = $true; OmitProperty = $false },
        @{ Case = 'a repair omitting the optional recipes property'; Intermediate = $false; OmitProperty = $true }
    ) {
        $runId = 'run-carried-locks'
        $name = "carried-locks-$Intermediate-$OmitProperty"
        $root = Join-Path $TestDrive $name
        New-Item -ItemType Directory $root | Out-Null
        $configPath = Join-Path $root 'configuration.json'
        $toolchain = New-ApprovedRunConfiguration -Path $configPath -RunId $runId
        $basePath = Join-Path $root 'base-plan.json'
        New-Plan -Path $basePath -RunId $runId -Toolchain $toolchain
        $plan = Get-Content $basePath -Raw | ConvertFrom-Json -Depth 100
        $plan.materializations = @()
        $plan.details | Add-Member carriedForward @{
            plan = 'base-plan.json'; sha256 = (Get-FileHash $basePath).Hash
        }
        if ($Intermediate) {
            $intermediatePath = Join-Path $root 'intermediate-plan.json'
            $plan | ConvertTo-Json -Depth 100 | Set-Content $intermediatePath
            $plan.details.carriedForward = @{
                plan = 'intermediate-plan.json'; sha256 = (Get-FileHash $intermediatePath).Hash
            }
        }
        if ($OmitProperty) {
            # The contract permits its absence only for no_action_needed.
            $plan.PSObject.Properties.Remove('materializations')
            $plan.outcome = 'no_action_needed'
        }
        $planPath = Join-Path $root 'repair-plan.json'
        $plan | ConvertTo-Json -Depth 100 | Set-Content $planPath
        $lockFixture = Join-Path $root 'lock.json'
        New-ApprovedLock -Toolchain $toolchain | Set-Content $lockFixture
        $stub = New-NpmStub -Directory (Join-Path $root 'stub') -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name $name -PlanPath $planPath `
            -RunConfigurationPath $configPath -RunId $runId -RunRoot $root -NpmCommand $stub

        $run.Result.status | Should -Be 'completed'
        $changeSet = Get-Content $run.OutputPath -Raw | ConvertFrom-Json -Depth 100
        @($changeSet.changes | Where-Object path -eq 'automation/package-lock.json').Count | Should -Be 1
        $evidence = Get-Content $run.EvidencePath -Raw | ConvertFrom-Json -Depth 100
        ($evidence.checks | Where-Object name -eq 'plan.carriedMaterializations').detail |
            Should -Match (Get-FileHash $basePath).Hash
        $saved = Get-Content $planPath -Raw | ConvertFrom-Json
        if ($OmitProperty) { $saved.PSObject.Properties.Name | Should -Not -Contain 'materializations' }
        else { @($saved.materializations).Count | Should -Be 0 }
    }

    It "refuses carried resolver recipes when <Case>" -ForEach @(
        @{ Case = 'the manifest changed'; Mutation = 'manifest'; Expected = 'no dependencies' },
        @{ Case = 'the previous plan was altered'; Mutation = 'hash'; Expected = 'missing or changed' },
        @{ Case = 'the previous plan belongs to another run'; Mutation = 'run'; Expected = 'this run' },
        @{ Case = 'the current toolchain disagrees'; Mutation = 'toolchain'; Expected = 'approved blueprint designed it on' }
    ) {
        $runId = 'run-carried-refusal'
        $root = Join-Path $TestDrive ('carried-' + $Mutation)
        New-Item -ItemType Directory $root | Out-Null
        $configPath = Join-Path $root 'configuration.json'
        $toolchain = New-ApprovedRunConfiguration -Path $configPath -RunId $runId
        $basePath = Join-Path $root 'base-plan.json'
        New-Plan -Path $basePath -RunId $runId -Toolchain $toolchain
        $base = Get-Content $basePath -Raw | ConvertFrom-Json -Depth 100
        if ($Mutation -eq 'run') { $base.runId = 'different-run' }
        if ($Mutation -eq 'toolchain') { $base.materializations[0].toolchainId = 'unapproved-toolchain' }
        $base | ConvertTo-Json -Depth 100 | Set-Content $basePath
        $plan = Get-Content $basePath -Raw | ConvertFrom-Json -Depth 100
        $plan.runId = $runId
        $plan.materializations = @()
        $plan.details | Add-Member carriedForward @{
            plan = 'base-plan.json'; sha256 = (Get-FileHash $basePath).Hash
        }
        if ($Mutation -eq 'manifest') { $plan.changes[0].content += ' ' }
        if ($Mutation -eq 'hash') { Add-Content $basePath ' ' }
        $planPath = Join-Path $root 'repair-plan.json'
        $plan | ConvertTo-Json -Depth 100 | Set-Content $planPath

        $run = Invoke-Materialisation -Name ('refused-' + $Mutation) -PlanPath $planPath `
            -RunConfigurationPath $configPath -RunId $runId -RunRoot $root -DryRun

        $run.Result.status | Should -BeIn @('blocked', 'revision_required')
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content $run.EvidencePath -Raw) | Should -Match $Expected
    }

    It "turns a planned change set into a final one carrying a resolved lock" {
        $runId = "run-materialise-happy"
        $runConfigPath = Join-Path $TestDrive "happy-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "happy-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $lockFixture = Join-Path $TestDrive "happy-lock.json"
        New-ApprovedLock -Toolchain $toolchain | Set-Content -LiteralPath $lockFixture -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "happy-stub") -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name "happy" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "completed"
        Test-Path $run.OutputPath | Should -BeTrue
        $changeSet = Get-Content -LiteralPath $run.OutputPath -Raw | ConvertFrom-Json -Depth 100
        $changeSet.outcome | Should -Be "proposed"
        $lockChange = @($changeSet.changes | Where-Object path -eq "automation/package-lock.json")
        $lockChange.Count | Should -Be 1
        $resolvedLock = $lockChange[0].content | ConvertFrom-Json -Depth 100 -AsHashtable
        $resolvedLock.lockfileVersion | Should -Be 3
        $resolvedLock.packages[""] | Should -Not -BeNullOrEmpty
        $evidence = Get-Content -LiteralPath $run.EvidencePath -Raw | ConvertFrom-Json -Depth 100
        $evidence.status | Should -Be "completed"
        $evidence.blueprintSha256 | Should -Match "^[0-9a-f]{64}$"
        @($evidence.materialisations).Count | Should -Be 1
        $evidence.materialisations[0].toolchainSha256 | Should -Match "^[0-9a-f]{64}$"
        @($evidence.materialisations[0].projectPaths) | Should -Contain "automation"
    }

    It "rehearses without resolving anything, and marks what it produced as undeliverable" {
        # A rehearsal has to be runnable on any machine. Resolution reaches a
        # registry and additionally insists the exact npm the decision was
        # settled on is installed here, so a rehearsal that resolved would
        # refuse on every agent carrying a different one.
        $runId = "run-materialise-rehearsal"
        $runConfigPath = Join-Path $TestDrive "rehearsal-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "rehearsal-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        # A resolver that cannot exist. Reaching it at all is the failure this
        # test is looking for.
        $absentResolver = Join-Path $TestDrive "no-such-resolver.cmd"

        $run = Invoke-Materialisation -Name "rehearsal" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId `
            -NpmCommand $absentResolver -DryRun

        $run.Result.status | Should -Be "completed"
        $run.Result.dryRun | Should -BeTrue
        @($run.Result.actions)[0].status | Should -Be "skipped"

        $changeSet = Get-Content -LiteralPath $run.OutputPath -Raw | ConvertFrom-Json -Depth 100
        $changeSet.details.dryRun | Should -BeTrue
        @($changeSet.changes | Where-Object path -eq "automation/package-lock.json").Count |
            Should -Be 0
        @($changeSet.changes | Where-Object path -eq "automation/package.json").Count |
            Should -Be 1
        (@($changeSet.warnings) -join " ") | Should -Match "must not be delivered"

        $evidence = Get-Content -LiteralPath $run.EvidencePath -Raw | ConvertFrom-Json -Depth 100
        $evidence.status | Should -Be "completed"
        $evidence.dryRun | Should -BeTrue
        # Every check that reads this run's own files was still made: a
        # rehearsal that skipped them would report nothing wrong with a plan
        # that a real run refuses.
        @($evidence.checks | Where-Object { $_.name -eq "manifest.toolchainMatch" })[0].outcome |
            Should -Be "passed"
        @($evidence.checks | Where-Object { $_.name -eq "resolver.run" })[0].outcome |
            Should -Be "skipped"
        $evidence.materialisations[0].resolverExitCode | Should -BeNullOrEmpty

        # Nothing was resolved, so there are no bytes for an approval to name.
        $reviewSubject = Get-Content -LiteralPath $run.ReviewSubjectPath -Raw |
            ConvertFrom-Json -Depth 100
        @($reviewSubject.materialisations).Count | Should -Be 0
    }

    It "still refuses a plan a real run would refuse, even in a rehearsal" {
        # The rehearsal skips the resolver, not the reading. A manifest that
        # disagrees with the locked toolchain is wrong before a single package
        # is fetched, and a rehearsal that passed it would be a rehearsal
        # nobody could learn anything from.
        $runId = "run-materialise-rehearsal-refusal"
        $runConfigPath = Join-Path $TestDrive "rehearsal-refusal-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "rehearsal-refusal-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain `
            -ManifestOverride @{ devDependencies = [ordered]@{ "@playwright/test" = "9.9.9" } }

        $run = Invoke-Materialisation -Name "rehearsal-refusal" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -DryRun

        $run.Result.status | Should -Be "revision_required"
        $run.Result.failureKind | Should -Be "artifact_invalid"
        $evidence = Get-Content -LiteralPath $run.EvidencePath -Raw | ConvertFrom-Json -Depth 100
        (@($evidence.findings) -join " ") | Should -Match "does not match the locked toolchain"
    }

    It "runs the resolver without inheriting the agent's environment" {
        # An inherited proxy, CA override or npm_config_* variable would quietly
        # change where packages come from, so the resolver starts from nothing.
        $runId = "run-materialise-isolation"
        $runConfigPath = Join-Path $TestDrive "isolation-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "isolation-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $lockFixture = Join-Path $TestDrive "isolation-lock.json"
        New-ApprovedLock -Toolchain $toolchain | Set-Content -LiteralPath $lockFixture -Encoding utf8
        $envDump = Join-Path $TestDrive "resolver-env.txt"
        $argsDump = Join-Path $TestDrive "resolver-args.txt"
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "isolation-stub") `
            -LockFixturePath $lockFixture -EnvDumpPath $envDump -ArgsDumpPath $argsDump

        $env:NPM_CONFIG_REGISTRY = "https://leaked.example/"
        $env:HTTPS_PROXY = "https://proxy.example/"
        try {
            $run = Invoke-Materialisation -Name "isolation" -PlanPath $planPath `
                -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub
        }
        finally {
            Remove-Item Env:NPM_CONFIG_REGISTRY -ErrorAction SilentlyContinue
            Remove-Item Env:HTTPS_PROXY -ErrorAction SilentlyContinue
        }

        $run.Result.status | Should -Be "completed"
        $observed = Get-Content -LiteralPath $envDump -Raw
        $observed | Should -Not -Match "(?i)npm_config"
        $observed | Should -Not -Match "(?i)https_proxy"
        $observed | Should -Not -Match "(?i)node_extra_ca_certs"
        $arguments = Get-Content -LiteralPath $argsDump -Raw
        $arguments | Should -Match "--package-lock-only"
        $arguments | Should -Match "--ignore-scripts"
        $arguments | Should -Match "--userconfig"
        $arguments | Should -Match "--globalconfig"
        $arguments | Should -Match "registry.npmjs.org"
    }

    It "refuses a lock whose packages came from somewhere else" {
        # "registry.npmjs.org.attacker.example" starts with the approved registry
        # and is a different host, so the check compares URLs, not prefixes.
        $runId = "run-materialise-registry"
        $runConfigPath = Join-Path $TestDrive "registry-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "registry-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $lockFixture = Join-Path $TestDrive "registry-lock.json"
        New-ApprovedLock -Toolchain $toolchain -Override @{
            registry = "https://registry.npmjs.org.attacker.example/"
        } | Set-Content -LiteralPath $lockFixture -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "registry-stub") -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name "registry" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        $evidence = Get-Content -LiteralPath $run.EvidencePath -Raw | ConvertFrom-Json -Depth 100
        $evidence.status | Should -Be "blocked"
        ($evidence.findings -join " ") | Should -Match "attacker.example"
    }

    It "refuses a lock that pins a version nobody approved" {
        $runId = "run-materialise-version"
        $runConfigPath = Join-Path $TestDrive "version-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "version-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $lockFixture = Join-Path $TestDrive "version-lock.json"
        New-ApprovedLock -Toolchain $toolchain -Override @{ version = "9.9.9" } |
            Set-Content -LiteralPath $lockFixture -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "version-stub") -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name "version" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "9.9.9"
    }

    It "refuses a lock with no integrity hash to verify later" {
        $runId = "run-materialise-integrity"
        $runConfigPath = Join-Path $TestDrive "integrity-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "integrity-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $lockFixture = Join-Path $TestDrive "integrity-lock.json"
        New-ApprovedLock -Toolchain $toolchain -Override @{ dropIntegrity = $true } |
            Set-Content -LiteralPath $lockFixture -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "integrity-stub") -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name "integrity" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "integrity"
    }

    It "refuses a manifest using resolution features it cannot verify" {
        $runId = "run-materialise-overrides"
        $runConfigPath = Join-Path $TestDrive "overrides-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "overrides-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain `
            -ManifestOverride @{ overrides = @{ semver = "1.0.0" } }
        $argsDump = Join-Path $TestDrive "overrides-args.txt"
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "overrides-stub") -ArgsDumpPath $argsDump

        $run = Invoke-Materialisation -Name "overrides" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "revision_required"
        $run.Result.failureKind | Should -Be "artifact_invalid"
        Test-Path $run.OutputPath | Should -BeFalse
        # Refused before anything was executed, not after.
        Test-Path $argsDump | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "overrides"
    }

    It "refuses a manifest that does not declare exactly the approved dependencies" {
        $runId = "run-materialise-extra"
        $runConfigPath = Join-Path $TestDrive "extra-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "extra-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain `
            -ManifestOverride @{ dependencies = [ordered]@{ "left-pad" = "1.3.0" } }
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "extra-stub")

        $run = Invoke-Materialisation -Name "extra" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "revision_required"
        $run.Result.failureKind | Should -Be "artifact_invalid"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "left-pad"
    }

    It "refuses to materialise when no resolver is installed" {
        $runId = "run-materialise-no-npm"
        $runConfigPath = Join-Path $TestDrive "no-npm-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "no-npm-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain

        $run = Invoke-Materialisation -Name "no-npm" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId `
            -NpmCommand "qa-foundry-absent-resolver"

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "qa-foundry-absent-resolver"
    }

    It "refuses two materialisations that claim the same lock file" {
        $runId = "run-materialise-collision"
        $runConfigPath = Join-Path $TestDrive "collision-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "collision-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain -ExtraMaterializations @(
            [ordered]@{
                recipe = "npm-package-lock"
                toolchainId = [string]$toolchain.id
                projectPaths = @("automation")
                manifestPath = "automation/package.json"
                lockPath = "automation/package-lock.json"
                operation = "create"; expectedSha256 = ""; reason = "Duplicate."
                sourceRefs = @("work-item:42")
            }
        )
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "collision-stub")

        $run = Invoke-Materialisation -Name "collision" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
    }

    It "refuses a run configuration belonging to a different run" {
        $runConfigPath = Join-Path $TestDrive "foreign-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId "run-somebody-else"
        $planPath = Join-Path $TestDrive "foreign-plan.json"
        New-Plan -Path $planPath -RunId "run-materialise-foreign" -Toolchain $toolchain

        $run = Invoke-Materialisation -Name "foreign" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId "run-materialise-foreign" `
            -NpmCommand "npm"

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "run-somebody-else"
    }

    It "refuses a toolchain the approved blueprint did not choose for that project" {
        # Everything the resolver pinned is legitimate somewhere in this run, so
        # checking the lock alone would let a later agent quietly build one
        # project with another project's toolchain. The blueprint is what a
        # person approved, and it is what decides which project gets which.
        $runId = "run-materialise-swap"
        $runConfigPath = Join-Path $TestDrive "swap-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "swap-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $stageRoot = Join-Path $TestDrive "materialisation-swap"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId -Projects @(
                @{ path = "automation"; decision = (New-ToolchainDecision -TestFramework "vitest" `
                    -Packages @([ordered]@{
                        name = "vitest"; version = "^3.0.0"; scope = "dev"
                        purpose = "The unit surface this project was actually designed on."
                    })) },
                @{ path = "automation/tests/ui"; decision = (New-ToolchainDecision) }
            )

        $run = Invoke-Materialisation -Name "swap" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId `
            -BlueprintPath $blueprintPath -NpmCommand "npm"

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        $evidence = Get-Content -LiteralPath $run.EvidencePath -Raw | ConvertFrom-Json -Depth 100
        $evidence.blueprintSha256 | Should -Match "^[0-9a-f]{64}$"
        (@($evidence.findings) -join " ") | Should -Match "designed those projects on 'npm-vitest'"
    }

    It "refuses to materialise for a project the blueprint does not name" {
        $runId = "run-materialise-orphan"
        $runConfigPath = Join-Path $TestDrive "orphan-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "orphan-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $stageRoot = Join-Path $TestDrive "materialisation-orphan"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $decision = New-ToolchainDecision
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId -Projects @(
                @{ path = "somewhere-else"; decision = $decision },
                @{ path = "somewhere-else/ui"; decision = $decision }
            )

        $run = Invoke-Materialisation -Name "orphan" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId `
            -BlueprintPath $blueprintPath -NpmCommand "npm"

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "does not name as an automation project"
    }

    It "refuses one lock file serving projects designed on different toolchains" {
        # A single lock cannot honour two different approved choices, and picking
        # one silently would override a decision a person signed off.
        $runId = "run-materialise-mixed"
        $runConfigPath = Join-Path $TestDrive "mixed-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "mixed-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain `
            -ProjectPaths @("automation", "automation/tests/ui")
        $stageRoot = Join-Path $TestDrive "materialisation-mixed"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId -Projects @(
                @{ path = "automation"; decision = (New-ToolchainDecision) },
                @{ path = "automation/tests/ui"; decision = (New-ToolchainDecision -TestFramework "vitest" `
                    -Packages @([ordered]@{
                        name = "vitest"; version = "^3.0.0"; scope = "dev"
                        purpose = "A second runner, argued for separately and pinned separately."
                    })) }
            )

        $run = Invoke-Materialisation -Name "mixed" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId `
            -BlueprintPath $blueprintPath -NpmCommand "npm"

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "different"
    }

    It "refuses to resolve on a runtime the profile was not approved on" {
        # The same manifest can produce a differently shaped lock on a different
        # npm, so the version a person approved is checked rather than assumed.
        $runId = "run-materialise-npmversion"
        $runConfigPath = Join-Path $TestDrive "npmversion-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "npmversion-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "npmversion-stub") -NpmVersion "9.0.0"

        $run = Invoke-Materialisation -Name "npmversion" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "npm 9\.0\.0"
    }

    It "refuses to resolve on a Node major the profile was not approved on" {
        $runId = "run-materialise-nodeversion"
        $runConfigPath = Join-Path $TestDrive "nodeversion-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "nodeversion-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "nodeversion-stub")
        $nodeStub = New-NodeStub -Directory (Join-Path $TestDrive "nodeversion-node") -NodeVersion "v18.20.4"

        $run = Invoke-Materialisation -Name "nodeversion" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId `
            -NpmCommand $stub -NodeCommand $nodeStub

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "Node 18\.20\.4"
    }

    It "refuses a lock whose transitive package came from somewhere else" {
        # A dependency of a dependency is installed on every machine just the
        # same, so it cannot come from a registry nobody approved.
        $runId = "run-materialise-transitive"
        $runConfigPath = Join-Path $TestDrive "transitive-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "transitive-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $lockFixture = Join-Path $TestDrive "transitive-lock.json"
        $lock = New-ApprovedLock -Toolchain $toolchain | ConvertFrom-Json -Depth 100 -AsHashtable
        $lock.packages["node_modules/some-transitive"] = [ordered]@{
            version = "1.0.0"
            resolved = "https://packages.attacker.example/some-transitive/-/some-transitive-1.0.0.tgz"
            integrity = "sha512-" + ("b" * 86) + "=="
        }
        $lock | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $lockFixture -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "transitive-stub") -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name "transitive" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "attacker\.example"
    }

    It "refuses a plan carried over from another run" {
        # A plan from another run describes work nobody approved here, however
        # well formed it is.
        $runId = "run-materialise-planrun"
        $runConfigPath = Join-Path $TestDrive "planrun-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "planrun-plan.json"
        New-Plan -Path $planPath -RunId "run-somewhere-else" -Toolchain $toolchain
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "planrun-stub")

        $run = Invoke-Materialisation -Name "planrun" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "run-somewhere-else"
    }

    It "refuses a blueprint carried over from another run" {
        $runId = "run-materialise-bprun"
        $runConfigPath = Join-Path $TestDrive "bprun-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "bprun-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $stageRoot = Join-Path $TestDrive "materialisation-bprun"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId "run-a-different-design"
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "bprun-stub")

        $run = Invoke-Materialisation -Name "bprun" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -BlueprintPath $blueprintPath `
            -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "run-a-different-design"
    }

    It "lets one manifest above a project serve the projects nested under it" {
        # A single manifest at the root of an automation tree is the normal
        # shape, so requiring it to sit in each project would refuse a valid plan.
        $runId = "run-materialise-shared"
        $runConfigPath = Join-Path $TestDrive "shared-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "shared-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain `
            -ProjectPaths @("automation", "automation/tests/ui")
        $lockFixture = Join-Path $TestDrive "shared-lock.json"
        New-ApprovedLock -Toolchain $toolchain | Set-Content -LiteralPath $lockFixture -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "shared-stub") -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name "shared" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "completed"
        $evidence = Get-Content -LiteralPath $run.EvidencePath -Raw | ConvertFrom-Json -Depth 100
        @($evidence.materialisations[0].projectPaths).Count | Should -Be 2
    }

    It "refuses a manifest that does not govern every project it claims to serve" {
        $runId = "run-materialise-ungoverned"
        $runConfigPath = Join-Path $TestDrive "ungoverned-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "ungoverned-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain `
            -ManifestPath "automation/tests/ui/package.json" `
            -LockPath "automation/tests/ui/package-lock.json" `
            -ProjectPaths @("automation", "automation/tests/ui")
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "ungoverned-stub")

        $run = Invoke-Materialisation -Name "ungoverned" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "does not govern"
    }

    It "refuses a lock that links a package to a directory on the resolving machine" {
        $runId = "run-materialise-link"
        $runConfigPath = Join-Path $TestDrive "link-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "link-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $lockFixture = Join-Path $TestDrive "link-lock.json"
        $lock = New-ApprovedLock -Toolchain $toolchain | ConvertFrom-Json -Depth 100 -AsHashtable
        $lock.packages["node_modules/local-thing"] = [ordered]@{ resolved = "../local-thing"; link = $true }
        $lock | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $lockFixture -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "link-stub") -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name "link" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        (Get-Content -LiteralPath $run.EvidencePath -Raw) |
            Should -Match "points node_modules/local-thing at a local path"
    }

    It "refuses a lock whose integrity value is not a hash at all" {
        # An unreadable hash is not a hash: there would be nothing to compare a
        # later download against.
        $runId = "run-materialise-sri"
        $runConfigPath = Join-Path $TestDrive "sri-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "sri-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $lockFixture = Join-Path $TestDrive "sri-lock.json"
        $lock = New-ApprovedLock -Toolchain $toolchain | ConvertFrom-Json -Depth 100 -AsHashtable
        foreach ($key in @($lock.packages.Keys | Where-Object { $_ -ne "" })) {
            $lock.packages[$key].integrity = "trust-me"
        }
        $lock | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $lockFixture -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "sri-stub") -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name "sri" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "records a hash for node_modules/typescript that is not a readable digest"
    }

    It "writes a POSIX resolver stub a Linux agent could actually run" {
        # The relay runs on Linux. Generating the POSIX form here and running it
        # through a real sh proves the quoting and the node-stub rewrite hold,
        # rather than leaving both to be discovered by a red build.
        $sh = @(
            "C:\Program Files\Git\bin\sh.exe",
            "C:\Program Files\Git\usr\bin\sh.exe"
        ) | Where-Object { Test-Path $_ -PathType Leaf } | Select-Object -First 1
        if (-not $sh) { Set-ItResult -Skipped -Because "no POSIX shell is installed on this machine"; return }

        $npmStub = New-NpmStub -Directory (Join-Path $TestDrive "posix-npm") -ForcePosix
        $nodeStub = New-NodeStub -Directory (Join-Path $TestDrive "posix-node") -ForcePosix `
            -NodeVersion "v22.11.0"

        (& $sh $npmStub "--version" | Select-Object -First 1).Trim() | Should -Be "10.9.4"
        (& $sh $nodeStub "--version" | Select-Object -First 1).Trim() | Should -Be "v22.11.0"
        (Get-Content -LiteralPath $nodeStub -Raw) | Should -Not -Match "QAFOUNDRY_STUB_AS_NODE"
    }

    It "refuses a blueprint whose own author did not finish it" {
        $runId = "run-materialise-bpstatus"
        $runConfigPath = Join-Path $TestDrive "bpstatus-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "bpstatus-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $stageRoot = Join-Path $TestDrive "materialisation-bpstatus"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId
        $blueprint = Get-Content -LiteralPath $blueprintPath -Raw | ConvertFrom-Json -Depth 100
        $blueprint.status = "blocked"
        $blueprint | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $blueprintPath -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "bpstatus-stub")

        $run = Invoke-Materialisation -Name "bpstatus" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -BlueprintPath $blueprintPath `
            -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "did not complete"
    }

    It "refuses a lock whose integrity value decodes to the wrong length" {
        # "sha512-YQ==" is well formed base64 behind a real algorithm name and
        # carries one byte, so a shape check alone would let it through.
        $runId = "run-materialise-shortsri"
        $runConfigPath = Join-Path $TestDrive "shortsri-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "shortsri-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $lockFixture = Join-Path $TestDrive "shortsri-lock.json"
        $lock = New-ApprovedLock -Toolchain $toolchain | ConvertFrom-Json -Depth 100 -AsHashtable
        foreach ($key in @($lock.packages.Keys | Where-Object { $_ -ne "" })) {
            $lock.packages[$key].integrity = "sha512-YQ=="
        }
        $lock | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $lockFixture -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "shortsri-stub") -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name "shortsri" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "records a hash for node_modules/typescript that is not a readable digest"
    }

    It "hands the leg over instead of blaming the toolchain when the budget is spent" {
        # A spent leg budget means resume later, not "this toolchain does not work".
        $runId = "run-materialise-deadline"
        $runConfigPath = Join-Path $TestDrive "deadline-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "deadline-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "deadline-stub")

        {
            Invoke-Materialisation -Name "deadline" -PlanPath $planPath `
                -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub `
                -Deadline ([DateTime]::UtcNow.AddMinutes(-1))
        } | Should -Throw "*QAFOUNDRY_BUDGET_EXHAUSTED*"
        Test-Path (Join-Path $TestDrive "materialisation-deadline/change-set.json") | Should -BeFalse
    }

    It "materialises a private manifest that claims no version" {
        # npm asks a private package for no version, so a manifest without one is
        # valid npm and has to materialise. Build 468 reached this stage for the
        # first time and crashed reading the field the generator never wrote.
        $runId = "run-materialise-noversion"
        $runConfigPath = Join-Path $TestDrive "noversion-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "noversion-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain -ManifestRemove @("version")
        $lockFixture = Join-Path $TestDrive "noversion-lock.json"
        New-ApprovedLock -Toolchain $toolchain -Override @{ dropRootVersion = $true } |
            Set-Content -LiteralPath $lockFixture -Encoding utf8
        $manifestDump = Join-Path $TestDrive "noversion-resolver-manifest.json"
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "noversion-stub") `
            -LockFixturePath $lockFixture -ManifestDumpPath $manifestDump

        $run = Invoke-Materialisation -Name "noversion" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "completed"
        $changeSet = Get-Content -LiteralPath $run.OutputPath -Raw | ConvertFrom-Json -Depth 100
        $changeSet.outcome | Should -Be "proposed"
        @($changeSet.changes | Where-Object path -eq "automation/package-lock.json").Count | Should -Be 1

        # An invented version would put an identity in the lock that the manifest
        # beside it never claimed.
        $resolverManifest = Get-Content -LiteralPath $manifestDump -Raw | ConvertFrom-Json -Depth 20
        @(Get-QaFoundryPropertyNames -InputObject $resolverManifest) | Should -Not -Contain "version"
        $resolverManifest.name | Should -Be "automation"
    }

    It "materialises a private manifest that claims neither name nor version" {
        $runId = "run-materialise-anonymous"
        $runConfigPath = Join-Path $TestDrive "anonymous-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "anonymous-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain -ManifestRemove @("name", "version")
        $lockFixture = Join-Path $TestDrive "anonymous-lock.json"
        New-ApprovedLock -Toolchain $toolchain -Override @{ dropRootName = $true; dropRootVersion = $true } |
            Set-Content -LiteralPath $lockFixture -Encoding utf8
        $manifestDump = Join-Path $TestDrive "anonymous-resolver-manifest.json"
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "anonymous-stub") `
            -LockFixturePath $lockFixture -ManifestDumpPath $manifestDump

        $run = Invoke-Materialisation -Name "anonymous" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "completed"
        $resolverManifest = Get-Content -LiteralPath $manifestDump -Raw | ConvertFrom-Json -Depth 20
        $manifestFields = @(Get-QaFoundryPropertyNames -InputObject $resolverManifest)
        $manifestFields | Should -Not -Contain "name"
        $manifestFields | Should -Not -Contain "version"
        # An anonymous manifest still has to be the manifest the lock implies,
        # or "it materialised" would only mean the resolver was handed an empty
        # file and wrote whatever it liked.
        @($resolverManifest.devDependencies.PSObject.Properties.Name | Sort-Object) |
            Should -Be @($toolchain.packages | Where-Object scope -eq "dev" |
                ForEach-Object { [string]$_.name } | Sort-Object)
    }

    It "still refuses a lock whose root names a project the manifest does not" {
        # Dropping the identity check for an absent field must not drop it for a
        # field the manifest does state.
        $runId = "run-materialise-identity"
        $runConfigPath = Join-Path $TestDrive "identity-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "identity-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $lockFixture = Join-Path $TestDrive "identity-lock.json"
        $lock = New-ApprovedLock -Toolchain $toolchain | ConvertFrom-Json -Depth 30 -AsHashtable
        $lock.packages[""].name = "somebody-elses-project"
        $lock | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $lockFixture -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "identity-stub") -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name "identity" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "somebody-elses-project"
    }

    It "refuses rather than crashes when the resolver drops an identity the manifest states" {
        $runId = "run-materialise-rootgap"
        $runConfigPath = Join-Path $TestDrive "rootgap-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "rootgap-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $lockFixture = Join-Path $TestDrive "rootgap-lock.json"
        New-ApprovedLock -Toolchain $toolchain -Override @{ dropRootVersion = $true } |
            Set-Content -LiteralPath $lockFixture -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "rootgap-stub") -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name "rootgap" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        # The refusal has to say the lock states no version of its own, which is
        # a different fault from a lock that states the wrong one.
        $evidence = Get-Content -LiteralPath $run.EvidencePath -Raw
        $evidence | Should -Match "records no project version"
        $evidence | Should -Match "'0\.0\.0'"
    }
}

Describe "Approved toolchain" {

    It "refuses an ecosystem that installs from a source nobody configured" {
        # Build 462 stopped because nothing said where packages come from. A source
        # that does not exist is the same gap, and finding it an hour into a relay
        # costs the whole run, so it is settled before the first model call.
        $config = Get-RawConfig
        $config.automation.ecosystems.npm.source = "npm-internal"
        {
            & (Join-Path $script:Root "scripts/Validate-QaFoundryConfig.ps1") `
                -Config $config -Root $script:Root
        } | Should -Throw "*not one of the configured dependency sources*"
    }

    It "refuses an ecosystem this installation has nothing to install with" {
        # Declaring support is a promise the architect is allowed to design
        # against: the request lists the ecosystem, a blueprint chooses it, and
        # only then does the resolver discover there is no adapter to produce a
        # lock with. The promise is checked where it is made instead.
        $config = Get-RawConfig
        $config.automation.dependency_sources | Add-Member -NotePropertyName "cargo-public" `
            -NotePropertyValue ([pscustomobject]@{
                ecosystem = "cargo"; registry = "https://crates.io/"; authentication = "none"
            })
        $config.automation.ecosystems | Add-Member -NotePropertyName "cargo" `
            -NotePropertyValue ([pscustomobject]@{
                source = "cargo-public"
                runtime = [pscustomobject]@{ cargo_major = 1 }
            })
        {
            & (Join-Path $script:Root "scripts/Validate-QaFoundryConfig.ps1") `
                -Config $config -Root $script:Root
        } | Should -Throw "*has no adapter at scripts/ecosystems/cargo.Ecosystem.ps1*"
    }

    It "turns the range an architect proposed into the exact version it locked" {
        # A range is a decision deferred to whoever runs the resolver next, which
        # is the opposite of what a lock file is for. The architect may now write
        # one, so the guarantee moved rather than went away: nothing downstream
        # ever sees it.
        $runId = "run-toolchain-range"
        $stageRoot = Join-Path $TestDrive "toolchain-range"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId
        $lock = New-ToolchainLock -BlueprintPath $blueprintPath `
            -Path (Join-Path $stageRoot "toolchain-lock.json")

        $playwright = @($lock.toolchains[0].packages | Where-Object name -eq "@playwright/test")[0]
        $playwright.requested | Should -Be "^1.62.0"
        $playwright.version | Should -Be "1.62.1"
        foreach ($package in @($lock.toolchains[0].packages)) {
            [string]$package.version | Should -Match "^\d+\.\d+\.\d+$"
        }
    }

    It "refuses a range nothing published satisfies rather than pinning near it" {
        # Pinning the closest published version would quietly deliver something
        # the design did not ask for, and a lock file is the last place anyone
        # thinks to look for a substitution.
        $runId = "run-toolchain-unsatisfiable"
        $stageRoot = Join-Path $TestDrive "toolchain-unsatisfiable"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $decision = New-ToolchainDecision -Packages @([ordered]@{
            name = "@playwright/test"; version = "^9.0.0"; scope = "dev"
            purpose = "A major nobody has published."
        })
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId -Projects @(
                @{ path = "automation"; decision = $decision },
                @{ path = "automation/tests/ui"; decision = $decision }
            )
        $evidencePath = Join-Path $stageRoot "toolchain-resolution-evidence.json"

        $result = & (Join-Path $script:Root "scripts/actions/Resolve-ToolchainLock.ps1") `
            -BlueprintPath $blueprintPath `
            -Config (Get-RawConfig) -RunId $runId -StageId "toolchain-resolution" `
            -OutputPath (Join-Path $stageRoot "toolchain-lock.json") `
            -EvidencePath $evidencePath -VersionSource (New-VersionSource)

        $result.status | Should -Be "revision_required"
        Test-Path -LiteralPath (Join-Path $stageRoot "toolchain-lock.json") | Should -BeFalse
        $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json -Depth 30
        $evidence.cause | Should -Be "no_matching_version"
        (@($evidence.findings) -join " ") |
            Should -Match "Nothing published for '@playwright/test' satisfies '\^9\.0\.0'"
    }

    It "sends a range written in another ecosystem's notation back to be rewritten" {
        # Build 972137. The architect designed a .NET half and an npm half and
        # wrote NuGet's interval notation for both. '[1.49.0,2.0.0)' matches
        # nothing npm publishes, so the run stopped with "nothing satisfies it"
        # against a package sitting on the feed with a version in range. The
        # notation is read before the feed is asked, the refusal says what to
        # write instead, and the architect gets it back rather than the run
        # ending.
        $runId = "run-toolchain-notation"
        $stageRoot = Join-Path $TestDrive "toolchain-notation"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $decision = New-ToolchainDecision -Packages @([ordered]@{
            name = "@playwright/test"; version = "[1.49.0,2.0.0)"; scope = "dev"
            purpose = "A real package asked for in the wrong ecosystem's spelling."
        })
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId -Projects @(
                @{ path = "automation"; decision = $decision },
                @{ path = "automation/tests/ui"; decision = $decision }
            )
        $evidencePath = Join-Path $stageRoot "toolchain-resolution-evidence.json"

        $result = & (Join-Path $script:Root "scripts/actions/Resolve-ToolchainLock.ps1") `
            -BlueprintPath $blueprintPath `
            -Config (Get-RawConfig) -RunId $runId -StageId "toolchain-resolution" `
            -OutputPath (Join-Path $stageRoot "toolchain-lock.json") `
            -EvidencePath $evidencePath -VersionSource (New-VersionSource)

        $result.status | Should -Be "revision_required"
        Test-Path -LiteralPath (Join-Path $stageRoot "toolchain-lock.json") | Should -BeFalse
        $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json -Depth 30
        # Told apart from a version nothing satisfies, because they call for
        # different corrections and used to read identically.
        $evidence.cause | Should -Be "invalid_range"
        $findings = @($evidence.findings) -join " "
        $findings | Should -Match "not written in a notation npm uses"
        $findings | Should -Match "\^1\.49\.0" -Because "the architect needs the spelling that works"
        $findings | Should -Not -Match "Nothing published"
    }

    It "refuses a package the feed has never heard of" {
        # A package name produced from memory is what this stage exists to catch.
        # Build 447 spent a relay leg proving the registry was reachable at all;
        # a name that is not on it fails just as late and looks exactly like an
        # outage unless somebody says which name it was.
        $runId = "run-toolchain-phantom"
        $stageRoot = Join-Path $TestDrive "toolchain-phantom"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $decision = New-ToolchainDecision -Packages @([ordered]@{
            name = "@playwright/tets"; version = "^1.62.0"; scope = "dev"
            purpose = "A plausible misremembering of a real package."
        })
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId -Projects @(
                @{ path = "automation"; decision = $decision },
                @{ path = "automation/tests/ui"; decision = $decision }
            )
        $evidencePath = Join-Path $stageRoot "toolchain-resolution-evidence.json"

        $result = & (Join-Path $script:Root "scripts/actions/Resolve-ToolchainLock.ps1") `
            -BlueprintPath $blueprintPath `
            -Config (Get-RawConfig) -RunId $runId -StageId "toolchain-resolution" `
            -OutputPath (Join-Path $stageRoot "toolchain-lock.json") `
            -EvidencePath $evidencePath -VersionSource (New-VersionSource)

        $result.status | Should -Be "revision_required"
        $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json -Depth 30
        $evidence.cause | Should -Be "package_not_found"
        (@($evidence.findings) -join " ") |
            Should -Match "'@playwright/tets', which does not exist at https://registry\.npmjs\.org/"
    }

    It "locks the framework the design chose, not the SDK the agent happens to have" {
        # The architect settles the target framework from the product's own
        # solution. The resolver used to write this installation's SDK number
        # into the lock instead, so a design for net8.0 beside a net8.0 product
        # was locked as net10.0 and the mismatch surfaced later as a build error
        # nobody could trace back to a decision.
        $runId = "run-toolchain-target"
        $stageRoot = Join-Path $TestDrive "toolchain-target"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $decision = New-ToolchainDecision -Ecosystem "nuget" -TestFramework "MSTest" `
            -Language "C# 12" -RuntimeName "dotnet" -RuntimeVersion "net8.0" `
            -Packages @([ordered]@{
                name = "Microsoft.Playwright.MSTest"; version = "1.62.0"; scope = "runtime"
                purpose = "The runner the product's own solution can reference."
            })
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId -Projects @(
                @{ path = "automation"; decision = $decision },
                @{ path = "automation/tests/ui"; decision = $decision }
            )
        $config = Get-RawConfig
        $config.automation.ecosystems.nuget.runtime.sdk_major = 10
        $lockPath = Join-Path $stageRoot "toolchain-lock.json"

        $result = & (Join-Path $script:Root "scripts/actions/Resolve-ToolchainLock.ps1") `
            -BlueprintPath $blueprintPath `
            -Config $config -RunId $runId -StageId "toolchain-resolution" `
            -OutputPath $lockPath `
            -EvidencePath (Join-Path $stageRoot "toolchain-resolution-evidence.json") `
            -VersionSource (New-VersionSource -Versions @{
                "Microsoft.Playwright.MSTest" = @("1.62.0")
            })

        $result.status | Should -Be "completed"
        $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -Depth 30
        # The framework is the design's. The SDK is the machine's, because that
        # is the thing that will actually run dotnet build.
        [string]$lock.toolchains[0].runtime.targetFramework | Should -Be "net8.0"
        [int]$lock.toolchains[0].runtime.sdkMajor | Should -Be 10
    }

    It "refuses a design this installation's SDK cannot build, naming both numbers" {
        # The opposite direction is not a preference, it is impossible: SDK 8
        # does not build net10.0. Silently locking net8.0 would produce
        # automation written against a product surface that is not there.
        $runId = "run-toolchain-too-new"
        $stageRoot = Join-Path $TestDrive "toolchain-too-new"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $decision = New-ToolchainDecision -Ecosystem "nuget" -TestFramework "MSTest" `
            -Language "C# 13" -RuntimeName "dotnet" -RuntimeVersion "net10.0" `
            -Packages @([ordered]@{
                name = "Microsoft.Playwright.MSTest"; version = "1.62.0"; scope = "runtime"
                purpose = "The runner the product's own solution can reference."
            })
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId -Projects @(
                @{ path = "automation"; decision = $decision },
                @{ path = "automation/tests/ui"; decision = $decision }
            )
        $evidencePath = Join-Path $stageRoot "toolchain-resolution-evidence.json"

        $result = & (Join-Path $script:Root "scripts/actions/Resolve-ToolchainLock.ps1") `
            -BlueprintPath $blueprintPath `
            -Config (Get-RawConfig) -RunId $runId -StageId "toolchain-resolution" `
            -OutputPath (Join-Path $stageRoot "toolchain-lock.json") `
            -EvidencePath $evidencePath `
            -VersionSource (New-VersionSource -Versions @{
                "Microsoft.Playwright.MSTest" = @("1.62.0")
            })

        $result.status | Should -Be "blocked"
        Test-Path -LiteralPath (Join-Path $stageRoot "toolchain-lock.json") | Should -BeFalse
        $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json -Depth 30
        (@($evidence.findings) -join " ") |
            Should -Match "targets net10\.0, and this installation has \.NET SDK 8"
    }

    It "refuses a design written for a Node major this installation does not run" {
        # Node is not backward-compatible the way an SDK is, so there is no
        # version of this the resolver may decide on its own. It says which two
        # numbers disagree and stops.
        $runId = "run-toolchain-node-major"
        $stageRoot = Join-Path $TestDrive "toolchain-node-major"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $decision = New-ToolchainDecision -RuntimeVersion "24"
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId -Projects @(
                @{ path = "automation"; decision = $decision },
                @{ path = "automation/tests/ui"; decision = $decision }
            )
        $evidencePath = Join-Path $stageRoot "toolchain-resolution-evidence.json"

        $result = & (Join-Path $script:Root "scripts/actions/Resolve-ToolchainLock.ps1") `
            -BlueprintPath $blueprintPath `
            -Config (Get-RawConfig) -RunId $runId -StageId "toolchain-resolution" `
            -OutputPath (Join-Path $stageRoot "toolchain-lock.json") `
            -EvidencePath $evidencePath -VersionSource (New-VersionSource)

        $result.status | Should -Be "blocked"
        $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json -Depth 30
        (@($evidence.findings) -join " ") |
            Should -Match "written for Node 24, and this installation runs Node 22"
    }

    It "reports an unreachable feed as infrastructure rather than a bad design" {
        # Sending the run back to redesign over a feed that did not answer spends
        # the repair budget on a decision that was never wrong, and the second
        # attempt fails identically.
        $runId = "run-toolchain-outage"
        $stageRoot = Join-Path $TestDrive "toolchain-outage"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId
        $evidencePath = Join-Path $stageRoot "toolchain-resolution-evidence.json"

        $result = & (Join-Path $script:Root "scripts/actions/Resolve-ToolchainLock.ps1") `
            -BlueprintPath $blueprintPath `
            -Config (Get-RawConfig) -RunId $runId -StageId "toolchain-resolution" `
            -OutputPath (Join-Path $stageRoot "toolchain-lock.json") `
            -EvidencePath $evidencePath `
            -VersionSource { param($Registry, $Name) throw "getaddrinfo ENOTFOUND registry.npmjs.org" }

        $result.status | Should -Be "failed"
        $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json -Depth 30
        # Named apart from the design faults on purpose: this one is not the
        # architect's to fix, so it must never come back as revision_required.
        $evidence.cause | Should -Be "registry_unreachable"
        (@($evidence.findings) -join " ") |
            Should -Match "infrastructure being unavailable, not a fault in the design"
    }

    It "rejects unsupported proposal notation before accepting an architecture artifact" {
        $stageRoot = Join-Path $TestDrive 'early-range'
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $decision = New-ToolchainDecision -Packages @([ordered]@{
            name='@playwright/test';version='[1.49.0,2.0.0)';scope='dev';purpose='Exercise invalid npm notation.'
        })
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot 'blueprint.json') -RunId 'run-early-range' -Projects @(
            @{path='automation/api';decision=$decision}, @{path='automation/ui';decision=$decision}
        )
        $payload = Get-Content $blueprintPath -Raw
        $provider = Join-Path $stageRoot 'provider.mjs'
        Set-Content $provider -Value ('process.stdout.write(' + ($payload | ConvertTo-Json -Compress) + ');')
        $config = Get-TestConfig
        $config.ai.provider = 'command'
        $config.ai.command = "node $provider"
        $config.runtime.agent_schema_retries = 0
        $output = Join-Path $stageRoot 'accepted.json'
        { & (Join-Path $script:Root 'scripts/Invoke-Agent.ps1') -AgentId automation-architect -StageId architecture `
            -RunId 'run-early-range' -PromptPath (Join-Path $script:Root 'prompts/architecture/automation-architect.md') `
            -ContextPaths @() -OutputPath $output -SchemaPath (Join-Path $script:Root 'schemas/architecture/automation-blueprint.schema.json') `
            -Config $config -RepositoryRoot $script:Root } | Should -Throw '*npm*'
        Test-Path $output | Should -BeFalse
        (Get-Content "$output.attempt-1.request.md" -Raw).Length | Should -BeGreaterThan 0
    }

    It "tells the architect what this installation can execute, not what to design" {
        $config = Get-TestConfig
        $outputPath = Join-Path $TestDrive "toolchain-run/architecture/automation-blueprint.json"
        New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null
        $artifact = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "automation-architect" `
            -StageId "architecture" `
            -RunId "run-toolchain" `
            -PromptPath (Join-Path $script:Root "prompts/architecture/automation-architect.md") `
            -ContextPaths @() `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/architecture/automation-blueprint.schema.json") `
            -Config $config `
            -RepositoryRoot $script:Root

        $request = Get-Content -Path "$outputPath.attempt-1.request.md" -Raw
        $request | Should -Match "# What this installation can execute"
        $request | Should -Match "``npm``, resolved from https://registry\.npmjs\.org/"
        $request | Should -Match "``nuget``, resolved from https://api\.nuget\.org/v3/index\.json"
        $request | Should -Match "npm_version: 10\.9\.4"
        $request | Should -Match "node_major: 22"
        # What a choice has to stay inside, rather than what the choice is.
        $request | Should -Match "At most 12 direct packages per automation project"
        $request | Should -Match "Pre-release versions are not allowed"
        # A request that still shipped a catalogue would put the architecture
        # back in a configuration file written months before anyone read the
        # repository the automation is for.
        $request | Should -Not -Match "(?m)^# Approved toolchain"
        $request | Should -Not -Match "toolchainProfile"

        # Check the composed request, not only the prompt files: the runtime
        # previously appended a conflicting mandatory same-language rule.
        $request | Should -Match "# Evidence-based architecture deliberation"
        $request | Should -Match "No candidate has automatic priority"
        $request | Should -Match "product language need not be"
        $request | Should -Match "details\.testTaxonomy"
        $request | Should -Match "project documentation"
        $request | Should -Match "Product code remains read-only"
        $request | Should -Match "The agents decide the decomposition"
        $request | Should -Match "The upper bound is permission, not a quota"
        $request | Should -Match "compare keeping tests together with separating them"
        $request | Should -Match "# Evidence-based UI automation maintenance"
        $request | Should -Match "Compare BDD with runner-native tests"
        $request | Should -Not -Match "Only then consider another ecosystem"
        $request | Should -Not -Match "demonstrably cannot meet"
        $request | Should -Not -Match "A C#/.NET solution gets C#/.NET automation"

        $supported = @(Resolve-QaFoundryAutomationEcosystems -Automation (Get-RawConfig).automation |
            ForEach-Object { [string]$_.id })
        @($artifact.details.automationProjects).Count | Should -BeGreaterThan 0
        foreach ($project in @($artifact.details.automationProjects)) {
            @(Get-QaFoundryPropertyNames -InputObject $project) | Should -Contain "toolchain"
            $supported | Should -Contain ([string]$project.toolchain.ecosystem)
            @($project.toolchain.alternativesRejected).Count | Should -BeGreaterThan 0
        }
    }

    It "refuses a blueprint built on an ecosystem this installation cannot run" {
        # Which technology the automation is written in is argued for in the
        # blueprint and judged by review. Whether the runtime can install, build
        # and run the result is not an opinion, so a design nothing here could
        # ever execute is refused where it is cheap.
        $config = Get-TestConfig
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/unknown-ecosystem-blueprint-provider.mjs"
        $config.runtime.agent_schema_retries = 0
        $outputPath = Join-Path $TestDrive "unknown-ecosystem/architecture/automation-blueprint.json"
        New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null
        {
            & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
                -AgentId "automation-architect" `
                -StageId "architecture" `
                -RunId "run-unknown-ecosystem" `
                -PromptPath (Join-Path $script:Root "prompts/architecture/automation-architect.md") `
                -ContextPaths @() `
                -OutputPath $outputPath `
                -SchemaPath (Join-Path $script:Root "schemas/architecture/automation-blueprint.schema.json") `
                -Config $config `
                -RepositoryRoot $script:Root
        } | Should -Throw "*cannot install, build or run*"
    }

    It "accepts an architect that reports no toolchain fits rather than inventing one" {
        # A blueprint is a design. An architect that has none has nothing to put in
        # the required sections, and demanding them anyway is how a refusal becomes
        # an invented design that cannot be built.
        $config = Get-TestConfig
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/blocked-blueprint-provider.mjs"
        $outputPath = Join-Path $TestDrive "blocked-blueprint/architecture/automation-blueprint.json"
        New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null
        $artifact = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "automation-architect" `
            -StageId "architecture" `
            -RunId "run-blocked-blueprint" `
            -PromptPath (Join-Path $script:Root "prompts/architecture/automation-architect.md") `
            -ContextPaths @() `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/architecture/automation-blueprint.schema.json") `
            -Config $config `
            -RepositoryRoot $script:Root

        $artifact.status | Should -Be "blocked"
        @(Get-QaFoundryPropertyNames -InputObject $artifact.details).Count | Should -Be 0
    }

    It "still refuses a completed blueprint that designed nothing" {
        # Relaxing the required sections for a refusal must not relax them for a
        # design. An architect that says it finished owes the sections it finished.
        $artifactPath = Join-Path $TestDrive "empty-completed-blueprint.json"
        [ordered]@{
            agentId = "automation-architect"
            stageId = "architecture"
            runId = "run-empty-completed"
            status = "completed"
            summary = "Designed the automation solution."
            evidence = @()
            assumptions = @()
            unknowns = @()
            warnings = @()
            outcome = "completed"
            details = @{}
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $artifactPath -Encoding UTF8
        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $artifactPath `
                -SchemaPath (Join-Path $script:Root "schemas/architecture/automation-blueprint.schema.json")
        } | Should -Throw
    }

    It "refuses a registry URL that could carry a credential" {
        # That URL reaches every prompt and every evidence file, so a token in it is
        # a token published everywhere.
        $config = Get-RawConfig
        $config.automation.dependency_sources.'npm-public'.registry =
            "https://token:secret@registry.npmjs.org/"
        {
            & (Join-Path $script:Root "scripts/Validate-QaFoundryConfig.ps1") `
                -Config $config -Root $script:Root
        } | Should -Throw "*carries credentials in its registry URL*"
    }

    It "identifies an ecosystem by what a resolver would install, not by its name" {
        # The hash is what lets a materialiser refuse a lock file built somewhere
        # else, so it has to move when the ecosystem moves and stay still when
        # only the file's shape does.
        $config = Get-RawConfig
        $original = @(Resolve-QaFoundryAutomationEcosystems -Automation $config.automation)[0]
        $original.sha256 | Should -Match "^[0-9a-f]{64}$"

        $again = @(Resolve-QaFoundryAutomationEcosystems -Automation $config.automation)[0]
        $again.sha256 | Should -Be $original.sha256

        $repinned = Get-RawConfig
        $repinned.automation.ecosystems.npm.runtime.npm_version = "10.9.8"
        @(Resolve-QaFoundryAutomationEcosystems -Automation $repinned.automation)[0].sha256 |
            Should -Not -Be $original.sha256

        $rehomed = Get-RawConfig
        $rehomed.automation.dependency_sources.'npm-public'.registry = "https://registry.example.com/"
        @(Resolve-QaFoundryAutomationEcosystems -Automation $rehomed.automation)[0].sha256 |
            Should -Not -Be $original.sha256
    }

    It "identifies a locked toolchain by the versions it pinned, not by its id" {
        # Packages moved out of configuration and into the decision, so the hash
        # that covers them is the lock's rather than the ecosystem's. A
        # materialiser that reused a lock across a version change would install
        # something nobody approved.
        $runId = "run-toolchain-identity"
        $stageRoot = Join-Path $TestDrive "toolchain-identity"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId
        $original = (New-ToolchainLock -BlueprintPath $blueprintPath `
            -Path (Join-Path $stageRoot "toolchain-lock.json")).toolchains[0]
        $original.sha256 | Should -Match "^[0-9a-f]{64}$"

        $again = (New-ToolchainLock -BlueprintPath $blueprintPath `
            -Path (Join-Path $stageRoot "again/toolchain-lock.json")).toolchains[0]
        $again.sha256 | Should -Be $original.sha256

        # The same decision and the same id: only the version the feed offered
        # for it has moved.
        $moved = (New-ToolchainLock -BlueprintPath $blueprintPath `
            -Path (Join-Path $stageRoot "moved/toolchain-lock.json") `
            -VersionSource (New-VersionSource -Versions @{
                "@playwright/test" = @("1.62.0", "1.62.1", "1.63.0")
            })).toolchains[0]
        $moved.id | Should -Be $original.id
        $moved.sha256 | Should -Not -Be $original.sha256
    }

    Context "the runtime the pipeline has to install" {
        BeforeAll {
            $script:RuntimeVersionScript = Join-Path $script:Root "scripts/Get-EcosystemRuntimeVersion.ps1"

            # A bootstrap configuration resolves its repository from its own
            # directory, so the synthetic one sits where the real one does.
            function script:New-RuntimeVersionFixture {
                param([Parameter(Mandatory)][string]$Name)
                $repository = Join-Path $TestDrive "runtimepin-$Name"
                $configDirectory = Join-Path $repository "foundry/config"
                $bootstrapDirectory = Join-Path $repository "foundry/bootstrap"
                New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
                New-Item -ItemType Directory -Path $bootstrapDirectory -Force | Out-Null

                Copy-Item -LiteralPath $script:ConfigPath `
                    -Destination (Join-Path $configDirectory "project.yaml") -Force
                $bootstrapPath = Join-Path $bootstrapDirectory "foundry.bootstrap.yaml"
                Copy-Item -LiteralPath (
                    Join-Path $script:Root "tests/fixtures/bootstrap-config.yaml") `
                    -Destination $bootstrapPath -Force
                return $bootstrapPath
            }
        }

        It "reads the pin from the configuration the run itself reads" {
            # Build 469 stopped at the resolver because the hosted image had moved
            # to npm 10.9.8 while the configuration pins 10.9.4. The pipeline
            # installs what the configuration asks for, and asking the
            # configuration is what keeps that pin in one place. Two pins can no
            # longer disagree the way two profiles could: an ecosystem is keyed
            # by its own name, so there is only ever one npm entry to read.
            $version = & $script:RuntimeVersionScript `
                -BootstrapConfigPath (New-RuntimeVersionFixture -Name "npm") `
                -Ecosystem "npm" -RuntimeKey "npm_version"
            $version | Should -Be "10.9.4"
        }

        It "reads another ecosystem's pin through the same script" {
            # A second copy of this logic for the next ecosystem is how a pin ends
            # up living in two places and eventually disagreeing with itself.
            $version = & $script:RuntimeVersionScript `
                -BootstrapConfigPath (New-RuntimeVersionFixture -Name "nuget") `
                -Ecosystem "nuget" -RuntimeKey "sdk_major"
            $version | Should -Be "8"
        }

        It "refuses to pin a runtime key the ecosystem does not configure" {
            # Returning nothing would install nothing and leave the agent on
            # whatever version its image happens to bundle, which is exactly the
            # failure this script exists to prevent.
            {
                & $script:RuntimeVersionScript `
                    -BootstrapConfigPath (New-RuntimeVersionFixture -Name "wrongkey") `
                    -Ecosystem "npm" -RuntimeKey "sdk_major"
            } | Should -Throw "*configured without sdk_major*"
        }

        It "refuses to pin an ecosystem this installation does not support" {
            {
                & $script:RuntimeVersionScript `
                    -BootstrapConfigPath (New-RuntimeVersionFixture -Name "unsupported") `
                    -Ecosystem "cargo" -RuntimeKey "cargo_major"
            } | Should -Throw "*does not support the cargo ecosystem*"
        }
    }

    # The recorded toolchain used to be read only for the architect. Every other
    # stage - every ordinary "add a test for this fix" - ran without it, and the
    # change set an ordinary stage produces reaches the repository by exactly the
    # same road. This is that road being watched.
    Context "An ordinary stage held to the recorded toolchain" {
        BeforeAll {
            function script:New-RecordedRepository {
                $repo = Join-Path $TestDrive ("recorded-" + [Guid]::NewGuid().ToString("N"))
                New-Item -ItemType Directory -Path (Join-Path $repo "automation") -Force | Out-Null
                @{
                    recordedBy = "run-first"
                    recordedAt = "2026-01-01T00:00:00Z"
                    runId = "run-first"
                    toolchains = @(
                        @{
                            id = "nuget-api"; ecosystem = "nuget"; language = "C#"
                            testFramework = "xunit"; projects = @("automation/Api")
                        }
                    )
                } | ConvertTo-Json -Depth 20 |
                    Set-Content -LiteralPath (Join-Path $repo "automation/automation-toolchain.json") `
                        -Encoding utf8
                return $repo
            }

            function script:Invoke-PlanningAgent {
                param(
                    [Parameter(Mandatory)][string]$RepositoryRoot,
                    [Parameter(Mandatory)][string]$PlannedPath
                )
                $providerPath = Join-Path $TestDrive ("planner-" + [Guid]::NewGuid().ToString("N") + ".mjs")
                $payload = [ordered]@{
                    agentId = "framework-implementation"
                    stageId = "implementation"
                    runId = "run-recorded-stage"
                    status = "completed"
                    summary = "Planned the file the task asked for."
                    confidence = 0.9
                    evidence = @(); assumptions = @(); unknowns = @(); warnings = @()
                    details = @{}
                    plannedFiles = @(@{
                        path = $PlannedPath
                        operation = "create"
                        purpose = "Cover the reported defect."
                        contentContract = "One suite exercising the reported defect."
                    })
                    commandsProposed = @()
                } | ConvertTo-Json -Depth 20 -Compress
                Set-Content -LiteralPath $providerPath -Encoding utf8 `
                    -Value ("process.stdout.write(" + ($payload | ConvertTo-Json -Depth 20) + ");")

                $config = Get-TestConfig
                $config.ai.provider = "command"
                $config.ai.command = "node $providerPath"
                $config.runtime.agent_schema_retries = 0
                $config.automation | Add-Member -NotePropertyName toolchain_record `
                    -NotePropertyValue "automation-toolchain.json" -Force
                $outputPath = Join-Path $TestDrive `
                    ("recorded-stage-" + [Guid]::NewGuid().ToString("N") + "/implementation.json")
                New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null
                return & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
                    -AgentId "framework-implementation" `
                    -StageId "implementation" `
                    -RunId "run-recorded-stage" `
                    -PromptPath (Join-Path $script:Root "prompts/implementation/framework-implementation.md") `
                    -ContextPaths @() `
                    -OutputPath $outputPath `
                    -SchemaPath (Join-Path $script:Root "schemas/implementation/implementation-result.schema.json") `
                    -Config $config `
                    -RepositoryRoot $RepositoryRoot
            }
        }

        It "refuses a change that quietly moves a recorded suite onto another stack" {
            {
                Invoke-PlanningAgent -RepositoryRoot (New-RecordedRepository) `
                    -PlannedPath "automation/Api/package.json"
            } | Should -Throw "*records on 'nuget'*"
        }

        It "accepts the same change written in the technology the suite is recorded on" {
            $artifact = Invoke-PlanningAgent -RepositoryRoot (New-RecordedRepository) `
                -PlannedPath "automation/Api/DefectTests.csproj"
            $artifact.status | Should -Be "completed"
        }

        It "tells an ordinary stage what the repository already decided" {
            $repo = New-RecordedRepository
            $null = Invoke-PlanningAgent -RepositoryRoot $repo `
                -PlannedPath "automation/Api/DefectTests.csproj"
            $request = @(Get-ChildItem -Path $TestDrive -Recurse -File -Filter "*.request.md" |
                Sort-Object LastWriteTime | Select-Object -Last 1)
            $text = Get-Content -LiteralPath $request[0].FullName -Raw
            # Not the architect's wording: this stage is not being asked to design
            # anything, only told which stack the automation it touches is on.
            $text | Should -Match "# The automation toolchain is already decided"
            $text | Should -Match "ecosystem ``nuget``"
            $text | Should -Not -Match "Design on it"
        }
    }
}

Describe "Incremental inventory merge" {
    BeforeAll {
        $script:MergeScript = Join-Path $script:Root "scripts/Merge-IncrementalInventory.ps1"
        function New-TestInventory {
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][object[]]$PlannedFiles,
                [object[]]$UnchangedFiles,
                [object[]]$RemovedFiles
            )
            $artifact = [ordered]@{
                summary = "test inventory"
                plannedFiles = $PlannedFiles
            }
            if ($PSBoundParameters.ContainsKey("UnchangedFiles")) {
                $artifact.unchangedFiles = $UnchangedFiles
            }
            if ($PSBoundParameters.ContainsKey("RemovedFiles")) {
                $artifact.removedFiles = $RemovedFiles
            }
            $artifact | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path -Encoding utf8
            return $Path
        }
    }

    It "carries an unchanged contract forward exactly as the previous iteration stated it" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev.json") -PlannedFiles @(
            [ordered]@{ path = "tests/A.cs"; contentContract = "ORIGINAL A" }
            [ordered]@{ path = "tests/B.cs"; contentContract = "ORIGINAL B" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur.json") `
            -PlannedFiles @([ordered]@{ path = "tests/B.cs"; contentContract = "REVISED B" }) `
            -UnchangedFiles @("tests/A.cs")

        $result = & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous

        $result.carriedOver | Should -Be 1
        $result.revised | Should -Be 1
        $merged = Get-Content -LiteralPath $current -Raw | ConvertFrom-Json -Depth 100
        @($merged.plannedFiles).Count | Should -Be 2
        (@($merged.plannedFiles | Where-Object path -eq "tests/A.cs")[0]).contentContract |
            Should -Be "ORIGINAL A"
        (@($merged.plannedFiles | Where-Object path -eq "tests/B.cs")[0]).contentContract |
            Should -Be "REVISED B"
        $merged.PSObject.Properties.Name | Should -Not -Contain "unchangedFiles"
    }

    It "refuses a path that is both restated and claimed unchanged" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev2.json") -PlannedFiles @(
            [ordered]@{ path = "tests/A.cs"; contentContract = "ORIGINAL A" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur2.json") `
            -PlannedFiles @([ordered]@{ path = "tests/A.cs"; contentContract = "REVISED A" }) `
            -UnchangedFiles @("tests/A.cs")

        { & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous } |
            Should -Throw "*listed in both*"
    }

    It "refuses to carry forward a path no earlier iteration planned" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev3.json") -PlannedFiles @(
            [ordered]@{ path = "tests/A.cs"; contentContract = "ORIGINAL A" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur3.json") `
            -PlannedFiles @([ordered]@{ path = "tests/B.cs"; contentContract = "NEW B" }) `
            -UnchangedFiles @("tests/Ghost.cs")

        { & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous } |
            Should -Throw "*no earlier iteration planned them*"
    }

    It "leaves an inventory that claims nothing unchanged untouched" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev4.json") -PlannedFiles @(
            [ordered]@{ path = "tests/A.cs"; contentContract = "ORIGINAL A" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur4.json") -PlannedFiles @(
            [ordered]@{ path = "tests/A.cs"; contentContract = "REVISED A" }
            [ordered]@{ path = "tests/B.cs"; contentContract = "NEW B" }
        )
        $before = Get-Content -LiteralPath $current -Raw

        $result = & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous

        $result.carriedOver | Should -Be 0
        $result.revised | Should -Be 2
        Get-Content -LiteralPath $current -Raw | Should -Be $before
    }

    It "refuses a revision that drops a file another entry still depends on" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev5.json") -PlannedFiles @(
            [ordered]@{ path = "tests/Base.cs"; contentContract = "ORIGINAL BASE" }
            [ordered]@{
                path = "tests/Uses.cs"; contentContract = "ORIGINAL USES"
                dependsOn = @("tests/Base.cs")
            }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur5.json") -PlannedFiles @(
            [ordered]@{
                path = "tests/Uses.cs"; contentContract = "REVISED USES, base deleted"
                dependsOn = @("tests/Base.cs")
            }
        ) -RemovedFiles @("tests/Base.cs")

        { & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous } |
            Should -Throw "*still depend on*"
    }

    It "keeps a file nothing depends on when the revision simply does not mention it" {
        # The rule used to be that a path named nowhere was dropped. A file that
        # nothing imports could therefore leave the inventory without a word:
        # the dependency check had no edge to notice, the stage reported success,
        # and the generation wrote fewer files than the review had approved.
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev7.json") -PlannedFiles @(
            [ordered]@{ path = "tests/Leaf.cs"; contentContract = "ORIGINAL LEAF" }
            [ordered]@{ path = "tests/B.cs"; contentContract = "ORIGINAL B" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur7.json") -PlannedFiles @(
            [ordered]@{ path = "tests/B.cs"; contentContract = "REVISED B" }
        )

        $result = & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous

        $result.carriedOver | Should -Be 1
        $merged = Get-Content -LiteralPath $current -Raw | ConvertFrom-Json -Depth 100
        @($merged.plannedFiles | ForEach-Object { [string]$_.path }) |
            Should -Contain "tests/Leaf.cs"
        (@($merged.plannedFiles | Where-Object path -eq "tests/Leaf.cs")[0]).contentContract |
            Should -Be "ORIGINAL LEAF"
    }

    It "drops a file only when the revision says so" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev8.json") -PlannedFiles @(
            [ordered]@{ path = "tests/Leaf.cs"; contentContract = "ORIGINAL LEAF" }
            [ordered]@{ path = "tests/B.cs"; contentContract = "ORIGINAL B" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur8.json") -PlannedFiles @(
            [ordered]@{ path = "tests/B.cs"; contentContract = "REVISED B" }
        ) -RemovedFiles @("tests/Leaf.cs")

        $result = & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous

        $result.carriedOver | Should -Be 0
        [int]$result.removed | Should -Be 1
        $merged = Get-Content -LiteralPath $current -Raw | ConvertFrom-Json -Depth 100
        @($merged.plannedFiles | ForEach-Object { [string]$_.path }) | Should -Be @("tests/B.cs")
        $merged.PSObject.Properties.Name | Should -Not -Contain "removedFiles"
    }

    It "does not bring a removed file back when the merge runs a second time" {
        # A leg killed between the rewrite and the end of the stage leaves the
        # next leg merging the same artifact again. The instruction list is gone
        # by then, and silence means "keep", so without a record of what was
        # already dropped the deleted file would reappear from the previous
        # inventory.
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev8b.json") -PlannedFiles @(
            [ordered]@{ path = "tests/Leaf.cs"; contentContract = "ORIGINAL LEAF" }
            [ordered]@{ path = "tests/B.cs"; contentContract = "ORIGINAL B" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur8b.json") -PlannedFiles @(
            [ordered]@{ path = "tests/B.cs"; contentContract = "REVISED B" }
        ) -RemovedFiles @("tests/Leaf.cs")

        $first = & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous
        [int]$first.removed | Should -Be 1
        $afterFirst = Get-Content -LiteralPath $current -Raw | ConvertFrom-Json -Depth 100
        @($afterFirst.mergedRemovals) | Should -Contain "tests/Leaf.cs"

        $second = & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous

        [int]$second.carriedOver | Should -Be 0
        $afterSecond = Get-Content -LiteralPath $current -Raw | ConvertFrom-Json -Depth 100
        @($afterSecond.plannedFiles | ForEach-Object { [string]$_.path }) | Should -Be @("tests/B.cs")
        @($afterSecond.mergedRemovals) | Should -Be @("tests/Leaf.cs")
    }

    It "reports nothing rewritten when a repeated merge changes nothing" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev8c.json") -PlannedFiles @(
            [ordered]@{ path = "tests/B.cs"; contentContract = "ORIGINAL B" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur8c.json") -PlannedFiles @(
            [ordered]@{ path = "tests/B.cs"; contentContract = "REVISED B" }
        ) -RemovedFiles @()

        $null = & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous
        $second = & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous

        [bool]$second.rewritten | Should -BeFalse
    }

    It "refuses a path that is both restated and removed" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev9.json") -PlannedFiles @(
            [ordered]@{ path = "tests/A.cs"; contentContract = "ORIGINAL A" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur9.json") `
            -PlannedFiles @([ordered]@{ path = "tests/A.cs"; contentContract = "REVISED A" }) `
            -RemovedFiles @("tests/A.cs")

        { & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous } |
            Should -Throw "*plannedFiles and removedFiles*"
    }

    It "refuses a path that is both carried forward and removed" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev10.json") -PlannedFiles @(
            [ordered]@{ path = "tests/A.cs"; contentContract = "ORIGINAL A" }
            [ordered]@{ path = "tests/B.cs"; contentContract = "ORIGINAL B" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur10.json") `
            -PlannedFiles @([ordered]@{ path = "tests/B.cs"; contentContract = "REVISED B" }) `
            -UnchangedFiles @("tests/A.cs") -RemovedFiles @("tests/A.cs")

        { & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous } |
            Should -Throw "*unchangedFiles and removedFiles*"
    }

    It "refuses to remove a path no earlier iteration planned" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev11.json") -PlannedFiles @(
            [ordered]@{ path = "tests/A.cs"; contentContract = "ORIGINAL A" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur11.json") `
            -PlannedFiles @([ordered]@{ path = "tests/A.cs"; contentContract = "REVISED A" }) `
            -RemovedFiles @("tests/Ghost.cs")

        { & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous } |
            Should -Throw "*named in removedFiles but no earlier iteration planned them*"
    }

    It "carries the same inventory forward twice without changing it" {
        # A leg can be killed after the merge has reached disk, and the recovered
        # artifact walks the acceptance path again. The second pass must find
        # nothing left to carry rather than duplicating what the first one did.
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev12.json") -PlannedFiles @(
            [ordered]@{ path = "tests/Leaf.cs"; contentContract = "ORIGINAL LEAF" }
            [ordered]@{ path = "tests/B.cs"; contentContract = "ORIGINAL B" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur12.json") -PlannedFiles @(
            [ordered]@{ path = "tests/B.cs"; contentContract = "REVISED B" }
        ) -RemovedFiles @()

        $null = & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous
        $afterFirst = Get-Content -LiteralPath $current -Raw
        $second = & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous

        [int]$second.carriedOver | Should -Be 0
        Get-Content -LiteralPath $current -Raw | Should -Be $afterFirst
    }

    It "accepts a dependency on a file this inventory never owned" {
        # A test inventory names foundation files from the framework agent's
        # inventory. Those were never in this artifact, so they are not dangling.
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prev6.json") -PlannedFiles @(
            [ordered]@{ path = "tests/A.cs"; contentContract = "ORIGINAL A" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "cur6.json") -PlannedFiles @(
            [ordered]@{
                path = "tests/B.cs"; contentContract = "NEW B"
                dependsOn = @("framework/HttpFixture.cs")
            }
        ) -UnchangedFiles @("tests/A.cs")

        $result = & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous

        $result.carriedOver | Should -Be 1
    }

    It "lets an agent correct the case of a path it already planned" {
        # Build 973259, leg 2: the approved commands pass NuGet.config to
        # --configfile while the inventory held NuGet.Config, so the agent
        # dropped one spelling and planned the other. Case-blind matching read
        # that as one path in two lists and burned all three attempts on it.
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prevCase.json") -PlannedFiles @(
            [ordered]@{ path = "automation/Auto/NuGet.Config"; contentContract = "ORIGINAL" }
            [ordered]@{ path = "automation/Auto/Program.cs"; contentContract = "KEEP" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "curCase.json") `
            -PlannedFiles @([ordered]@{ path = "automation/Auto/NuGet.config"; contentContract = "PINNED" }) `
            -RemovedFiles @("automation/Auto/NuGet.Config")

        $result = & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous

        $merged = Get-Content -LiteralPath $current -Raw | ConvertFrom-Json -Depth 100
        $paths = @($merged.plannedFiles | ForEach-Object { [string]$_.path })
        # Should -Contain matches without regard to case, which is the very
        # thing under test, so the spellings are compared exactly here.
        @($paths | Where-Object { $_.Equals("automation/Auto/NuGet.config", [StringComparison]::Ordinal) }).Count |
            Should -Be 1
        @($paths | Where-Object { $_.Equals("automation/Auto/NuGet.Config", [StringComparison]::Ordinal) }).Count |
            Should -Be 0
        $paths | Should -Contain "automation/Auto/Program.cs"
        $merged.mergedRemovals | Should -Contain "automation/Auto/NuGet.Config"
        [int]$result.carriedOver | Should -Be 1
    }

    It "still refuses a path restated and removed under one spelling" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prevSame.json") -PlannedFiles @(
            [ordered]@{ path = "tests/A.cs"; contentContract = "ORIGINAL A" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "curSame.json") `
            -PlannedFiles @([ordered]@{ path = "tests/A.cs"; contentContract = "REVISED A" }) `
            -RemovedFiles @("tests/A.cs")

        { & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous } |
            Should -Throw "*plannedFiles and removedFiles*"
    }

    It "refuses an inventory holding two spellings of one path at once" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prevBoth.json") -PlannedFiles @(
            [ordered]@{ path = "automation/Auto/NuGet.Config"; contentContract = "ORIGINAL" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "curBoth.json") -PlannedFiles @(
            [ordered]@{ path = "automation/Auto/NuGet.Config"; contentContract = "ONE" }
            [ordered]@{ path = "automation/Auto/NuGet.config"; contentContract = "TWO" }
        )

        { & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous } |
            Should -Throw "*differ only in case*"
    }

    It "names the spelling on record when a removal misses it by case only" {
        $previous = New-TestInventory -Path (Join-Path $TestDrive "prevHint.json") -PlannedFiles @(
            [ordered]@{ path = "automation/Auto/NuGet.Config"; contentContract = "ORIGINAL" }
        )
        $current = New-TestInventory -Path (Join-Path $TestDrive "curHint.json") `
            -PlannedFiles @([ordered]@{ path = "tests/B.cs"; contentContract = "NEW B" }) `
            -RemovedFiles @("automation/auto/nuget.config")

        { & $script:MergeScript -ArtifactPath $current -PreviousArtifactPath $previous } |
            Should -Throw "*spells it automation/Auto/NuGet.Config*"
    }
}

Describe "Provider timeout handling" {
    It "recognises a timeout by its marker rather than by message wording" {
        Test-QaFoundryProviderTimeout -Message "boom QAFOUNDRY_PROVIDER_TIMEOUT after 1500s" |
            Should -BeTrue
        Test-QaFoundryProviderTimeout -Message "the model returned invalid JSON" | Should -BeFalse
        Test-QaFoundryProviderTimeout -Message "" | Should -BeFalse
        Test-QaFoundryProviderTimeout -Message $null | Should -BeFalse
    }

    It "throws a timeout the caller can recognise, from the provider's own scope" {
        # The marker is defined in Common.ps1 but referenced as $script: inside the
        # provider, which is a different script scope. Asserting the real throw is the
        # only way to know the two halves actually meet.
        $requestPath = Join-Path $TestDrive "request.json"
        "{}" | Set-Content -LiteralPath $requestPath -Encoding utf8
        $sleeper = Join-Path $script:Root "tests/fixtures/sleep-forever.ps1"
        $sleeper | Should -Exist

        $thrown = $null
        try {
            & (Join-Path $script:Root "scripts/providers/Invoke-CommandProvider.ps1") `
                -Command "pwsh -NoProfile -ExecutionPolicy Bypass -File $sleeper" `
                -RequestPath $requestPath `
                -TimeoutSeconds 2
        }
        catch {
            $thrown = $_.Exception.Message
        }

        $thrown | Should -Not -BeNullOrEmpty
        Test-QaFoundryProviderTimeout -Message $thrown | Should -BeTrue
    }

    It "reports the budget a deadline leaves and never reports a negative one" {
        Get-QaFoundryBudgetSecondsRemaining -Deadline $null | Should -Be ([int]::MaxValue)
        Get-QaFoundryBudgetSecondsRemaining -Deadline ([DateTime]::UtcNow.AddSeconds(-30)) |
            Should -Be 0
        $remaining = Get-QaFoundryBudgetSecondsRemaining `
            -Deadline ([DateTime]::UtcNow.AddSeconds(600))
        $remaining | Should -BeGreaterThan 590
        $remaining | Should -BeLessOrEqual 600
    }
}

Describe "Delivery dissent notice" {
    BeforeAll {
        function New-DissentRun {
            param(
                [Parameter(Mandatory)][string]$RunRoot,
                [Parameter(Mandatory)][string]$ReviewStatus
            )
            New-Item -ItemType Directory -Path (Join-Path $RunRoot "review") -Force | Out-Null
            [ordered]@{
                workflowName = "bootstrap-automation"
                workflowVersion = 1
                runId = "run-dissent-notice"
                status = "completed"
                currentStage = $null
                stageIteration = 2
                startedAt = [DateTime]::UtcNow.ToString("o")
                updatedAt = [DateTime]::UtcNow.ToString("o")
                stages = @(
                    [ordered]@{
                        id = "review"; type = "parallel_review"; status = $ReviewStatus
                        iteration = 2; attempts = @()
                    }
                )
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $RunRoot "workflow-state.json") -Encoding utf8
            return $RunRoot
        }
        function New-ReviewArtifact {
            param(
                [Parameter(Mandatory)][string]$RunRoot,
                [Parameter(Mandatory)][string]$AgentId,
                [Parameter(Mandatory)][string]$Decision,
                [object[]]$Findings = @(),
                [string[]]$RequiredChanges = @()
            )
            [ordered]@{
                agentId = $AgentId
                stageId = "review"
                decision = $Decision
                findings = $Findings
                requiredChanges = $RequiredChanges
                confidence = 0.8
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $RunRoot "review/$AgentId.json") -Encoding utf8
        }
    }

    It "reports nothing when the review stage reached unanimity" {
        $runRoot = New-DissentRun -RunRoot (Join-Path $TestDrive "unanimous") -ReviewStatus "approved"
        New-ReviewArtifact -RunRoot $runRoot -AgentId "code-review" -Decision "approved"

        @(Get-QaFoundryDeliveryDissent -RunRoot $runRoot).Count | Should -Be 0
    }

    It "names the dissenting reviewer and its unresolved errors" {
        $runRoot = New-DissentRun -RunRoot (Join-Path $TestDrive "dissent") `
            -ReviewStatus "approved_with_dissent"
        New-ReviewArtifact -RunRoot $runRoot -AgentId "test-quality-review" -Decision "approved"
        New-ReviewArtifact -RunRoot $runRoot -AgentId "code-review" -Decision "revision_required" `
            -Findings @(
                [ordered]@{
                    severity = "error"
                    message = "CR2-02 the seam was applied to RequestThrottle but not to RunScope"
                    evidence = "plannedFiles[12]"
                }
                [ordered]@{ severity = "info"; message = "naming could be clearer"; evidence = "n/a" }
            ) `
            -RequiredChanges @("Apply the seam to RunScope as well.")

        $notice = @(Get-QaFoundryDeliveryDissent -RunRoot $runRoot)

        ($notice -join "`n") | Should -Match "code-review"
        ($notice -join "`n") | Should -Match "CR2-02"
        ($notice -join "`n") | Should -Match "Apply the seam to RunScope"
        # An approving reviewer is not an objection, and info is not an objection.
        ($notice -join "`n") | Should -Not -Match "test-quality-review"
        ($notice -join "`n") | Should -Not -Match "naming could be clearer"
    }

    It "reports nothing when the run produced no state at all" {
        $empty = Join-Path $TestDrive "empty-run"
        New-Item -ItemType Directory -Path $empty -Force | Out-Null

        @(Get-QaFoundryDeliveryDissent -RunRoot $empty).Count | Should -Be 0
    }
}

Describe "Artifact validation exit codes" {
    It "leaves no failing exit code behind when it rejects an artifact" {
        # Build 455 lost relay leg 2 forty-nine minutes in. The run had paused
        # cleanly, but node had exited 1 while rejecting an agent artifact and
        # that code was still sitting in $LASTEXITCODE when the leg script ended,
        # so Azure DevOps failed a job that had actually succeeded. Rejecting an
        # artifact is the normal retry path and must not look like a crash.
        $artifact = Join-Path $TestDrive "invalid.json"
        '{"agentId":"x"}' | Set-Content -LiteralPath $artifact -Encoding utf8
        $schema = Join-Path $script:Root "schemas/implementation/implementation-result.schema.json"
        $global:LASTEXITCODE = 0

        { & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $artifact `
            -SchemaPath $schema `
            -SchemaRoot (Join-Path $script:Root "schemas") } |
            Should -Throw "*Schema validation failed*"

        $global:LASTEXITCODE | Should -Be 0
    }

    It "still reports a valid artifact as valid" {
        $artifact = Join-Path $TestDrive "valid.json"
        [ordered]@{
            agentId = "framework-implementation"
            stageId = "implementation"
            runId = "run-validation-test"
            status = "completed"
            summary = "A minimal but schema-complete inventory."
            evidence = @()
            assumptions = @()
            unknowns = @()
            warnings = @()
            details = [ordered]@{}
            plannedFiles = @(
                [ordered]@{
                    path = "automation/tests/Smoke.cs"
                    operation = "create"
                    purpose = "Proves the harness starts."
                    contentContract = "A single test asserting the API returns 200 for /health."
                }
            )
            commandsProposed = @("dotnet test automation/Automation.sln")
        } | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $artifact -Encoding utf8
        $schema = Join-Path $script:Root "schemas/implementation/implementation-result.schema.json"
        $global:LASTEXITCODE = 0

        { & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $artifact `
            -SchemaPath $schema `
            -SchemaRoot (Join-Path $script:Root "schemas") } | Should -Not -Throw

        $global:LASTEXITCODE | Should -Be 0
    }

    It "reports a rejection whose validator params carry no entries" {
        # Ajv leaves params empty for some keywords, and formatting that error
        # used to read the property names of an empty object, which throws under
        # Set-StrictMode. The agent would then be told about the PowerShell fault
        # rather than about the schema rule it broke.
        $schema = Join-Path $TestDrive "no-params.schema.json"
        '{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"value":{"not":{"type":"string"}}}}' |
            Set-Content -LiteralPath $schema -Encoding utf8
        $artifact = Join-Path $TestDrive "no-params.json"
        '{"value":"rejected because the schema forbids a string here"}' |
            Set-Content -LiteralPath $artifact -Encoding utf8
        $global:LASTEXITCODE = 0

        { & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $artifact `
            -SchemaPath $schema `
            -SchemaRoot $TestDrive } |
            Should -Throw "*Schema validation failed*"

        $global:LASTEXITCODE | Should -Be 0
    }
}

Describe "Live repository delivery" {
    BeforeAll {
        # Delivery is the last thing a three-hour run does and the one thing no
        # live build has ever reached, so it is exercised here against a real
        # local repository: a bare repository standing in for the remote, and a
        # clone with an origin pointing at it. Nothing leaves the machine and no
        # global Git configuration is touched.
        $script:DeliveryRoot = Join-Path $TestDrive "live-delivery"
        $script:DeliveryCommitterName = $script:AdoUserName
        $script:DeliveryCommitterEmail = $script:AdoUserEmail
        $script:DeliveryWorkstationName = "Local Developer"
        $script:DeliveryWorkstationEmail = "local-developer@workstation.invalid"

        function Invoke-FixtureGit {
            param([Parameter(Mandatory)][string[]]$Arguments)
            $previous = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $output = & git @Arguments 2>&1
                if ($LASTEXITCODE -ne 0) {
                    throw ("git " + ($Arguments -join " ") + " failed: " +
                        (@($output) -join "`n").Trim())
                }
                return @($output | ForEach-Object { [string]$_ })
            }
            finally {
                $ErrorActionPreference = $previous
            }
        }

        function New-DeliveryFixture {
            param(
                [Parameter(Mandatory)][string]$Name,
                [string]$RemoteUrl = "",
                [string]$WorkItemId = ""
            )
            $base = Join-Path $script:DeliveryRoot $Name
            $repository = Join-Path $base "workspace"
            $remote = Join-Path $base "origin.git"
            $runRoot = Join-Path $base "run"
            $newFiles = @("automation/tests/smoke.spec.ts", "automation/playwright.config.ts")
            New-Item -ItemType Directory -Path $repository -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $runRoot "planning") -Force | Out-Null

            $null = Invoke-FixtureGit -Arguments @("init", "--bare", "--initial-branch=main", $remote)
            $null = Invoke-FixtureGit -Arguments @("init", "--initial-branch=main", $repository)
            # Local identity only: -C keeps this inside the throwaway repository.
            $null = Invoke-FixtureGit -Arguments @(
                "-C", $repository, "config", "user.name", $script:DeliveryWorkstationName)
            $null = Invoke-FixtureGit -Arguments @(
                "-C", $repository, "config", "user.email", $script:DeliveryWorkstationEmail)
            $null = Invoke-FixtureGit -Arguments @("-C", $repository, "config", "commit.gpgsign", "false")
            Set-Content -LiteralPath (Join-Path $repository "README.md") -Value "baseline" -NoNewline
            $null = Invoke-FixtureGit -Arguments @("-C", $repository, "add", "README.md")
            $null = Invoke-FixtureGit -Arguments @("-C", $repository, "commit", "-m", "baseline")
            $originUrl = if ([string]::IsNullOrWhiteSpace($RemoteUrl)) { $remote } else { $RemoteUrl }
            $null = Invoke-FixtureGit -Arguments @("-C", $repository, "remote", "add", "origin", $originUrl)
            if ([string]::IsNullOrWhiteSpace($RemoteUrl)) {
                $null = Invoke-FixtureGit -Arguments @("-C", $repository, "push", "--quiet", "-u", "origin", "main")
            }

            # Files Git has never seen. Delivery has to stage them itself, which
            # is the step a plain "git commit -a" would silently miss.
            foreach ($file in $newFiles) {
                $absolute = Join-Path $repository $file
                New-Item -ItemType Directory -Path (Split-Path $absolute -Parent) -Force | Out-Null
                Set-Content -LiteralPath $absolute -Value "generated by the foundry" -NoNewline
            }
            @{
                changes = @($newFiles | ForEach-Object {
                    [ordered]@{ path = $_; operation = "create"; content = "generated by the foundry" }
                })
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $runRoot "planning/change-set.json") -Encoding utf8

            if (-not [string]::IsNullOrWhiteSpace($WorkItemId)) {
                # What the run was handed, rather than anything it made for
                # itself: this is the identity a repeat has to recognise.
                New-Item -ItemType Directory -Path (Join-Path $runRoot "context") -Force | Out-Null
                @{ correlation = @{ workItemId = $WorkItemId } } | ConvertTo-Json -Depth 10 |
                    Set-Content -LiteralPath (Join-Path $runRoot "context/sdlc-event.json") -Encoding utf8
            }

            return [pscustomobject]@{
                Repository = $repository
                Remote = $remote
                RunRoot = $runRoot
                NewFiles = @($newFiles)
            }
        }

        function New-FreshCheckout {
            # A repeat after a lost answer does not get the workspace back: the
            # next build clones again and applies the change set to a clean
            # tree. Nothing of the first run's local state survives, which is
            # exactly why the server has to be asked what it already holds.
            param(
                [Parameter(Mandatory)][object]$Fixture,
                [Parameter(Mandatory)][string]$Name
            )
            $checkout = Join-Path (Split-Path -Parent $Fixture.Repository) $Name
            $null = Invoke-FixtureGit -Arguments @("clone", "--quiet", $Fixture.Remote, $checkout)
            $null = Invoke-FixtureGit -Arguments @(
                "-C", $checkout, "config", "user.name", $script:DeliveryWorkstationName)
            $null = Invoke-FixtureGit -Arguments @(
                "-C", $checkout, "config", "user.email", $script:DeliveryWorkstationEmail)
            $null = Invoke-FixtureGit -Arguments @("-C", $checkout, "config", "commit.gpgsign", "false")
            foreach ($file in @($Fixture.NewFiles)) {
                $absolute = Join-Path $checkout $file
                New-Item -ItemType Directory -Path (Split-Path $absolute -Parent) -Force | Out-Null
                Set-Content -LiteralPath $absolute -Value "generated by the foundry" -NoNewline
            }
            return [pscustomobject]@{
                Repository = $checkout
                Remote = $Fixture.Remote
                RunRoot = $Fixture.RunRoot
                NewFiles = @($Fixture.NewFiles)
            }
        }

        function New-DeliveryConfig {
            param([string]$BranchPrefix = "")
            $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
            $config.delivery.dry_run = $false
            $config.delivery.create_branch = $true
            $config.delivery.commit_changes = $true
            $config.delivery.push_branch = $true
            $config.delivery.create_draft_pull_request = $false
            $config.delivery.azure_devops.organization_url = "https://dev.azure.com/example"
            if (-not [string]::IsNullOrWhiteSpace($BranchPrefix)) {
                $config.delivery.branch_prefix = $BranchPrefix
            }
            return $config
        }

        function Invoke-Delivery {
            param(
                [Parameter(Mandatory)][object]$Fixture,
                [Parameter(Mandatory)][object]$Config,
                [Parameter(Mandatory)][string]$RunId
            )
            return & (Join-Path $script:Root "scripts/writers/Publish-RepositoryDelivery.ps1") `
                -Config $Config `
                -RepositoryRoot $Fixture.Repository `
                -RunRoot $Fixture.RunRoot `
                -RunId $RunId `
                -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        }

        function Get-LocalBranches {
            param([Parameter(Mandatory)][string]$Repository)
            return @(Invoke-FixtureGit -Arguments @(
                "-C", $Repository, "for-each-ref", "--format=%(refname:short)", "refs/heads"))
        }

        function Get-RemoteBranches {
            param([Parameter(Mandatory)][string]$Remote)
            return @(Invoke-FixtureGit -Arguments @(
                "--git-dir", $Remote, "for-each-ref", "--format=%(refname:short)", "refs/heads"))
        }
    }

    BeforeEach {
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -like "*/_apis/connectionData?*") {
                return New-TestAdoConnectionData
            }
            # Nothing has been delivered for this branch yet, which is what the
            # server says on every run but the one that is repeating itself.
            if ($Uri -like "*/_apis/git/repositories/*/refs?*") {
                return [pscustomobject]@{ count = 0; value = @() }
            }
            if ($Uri -like "*/_apis/git/repositories/*/pullrequests?*") {
                return [pscustomobject]@{ count = 0; value = @() }
            }
            throw "Unexpected Azure DevOps request: $Uri"
        }
    }

    It "creates the prefixed branch, commits files Git has never seen, and pushes them to the remote" {
        $fixture = New-DeliveryFixture -Name "happy-path"
        $config = New-DeliveryConfig
        $runId = "run-DELIVERY-2026"
        $expectedBranch = "$([string]$config.delivery.branch_prefix)changes-876282eeaaad15b97afb2418"

        $result = Invoke-Delivery -Fixture $fixture -Config $config -RunId $runId

        $result.status | Should -Be "completed"
        $result.dryRun | Should -BeFalse
        @($result.actions | Where-Object { $_.status -eq "executed" }).Count | Should -Be 3

        # The branch exists, carries the configured prefix, and is checked out.
        Get-LocalBranches -Repository $fixture.Repository | Should -Contain $expectedBranch
        @(Invoke-FixtureGit -Arguments @(
            "-C", $fixture.Repository, "rev-parse", "--abbrev-ref", "HEAD"))[0] |
            Should -Be $expectedBranch

        # Exactly one new commit, and it contains the previously untracked files.
        @(Invoke-FixtureGit -Arguments @("-C", $fixture.Repository, "rev-list", "--count", "HEAD"))[0] |
            Should -Be "2"
        $committed = @(Invoke-FixtureGit -Arguments @(
            "-C", $fixture.Repository, "diff-tree", "--no-commit-id", "--name-only", "-r", "HEAD"))
        foreach ($file in $fixture.NewFiles) {
            $committed | Should -Contain $file
        }
        @(Invoke-FixtureGit -Arguments @(
            "-C", $fixture.Repository, "log", "-1", "--format=%s"))[0] |
            Should -Be ([string]$config.delivery.commit_message)

        # The identity comes from the PAT owner, not from local Git configuration.
        $identity = @(Invoke-FixtureGit -Arguments @(
            "-C", $fixture.Repository, "log", "-1", "--format=%an%n%ae%n%cn%n%ce"))
        $identity[0] | Should -Be $script:DeliveryCommitterName
        $identity[1] | Should -Be $script:DeliveryCommitterEmail
        $identity[2] | Should -Be $script:DeliveryCommitterName
        $identity[3] | Should -Be $script:DeliveryCommitterEmail
        $identity | Should -Not -Contain $script:DeliveryWorkstationName

        # The push is proved from the receiving side, not from the pushing side.
        $localHead = @(Invoke-FixtureGit -Arguments @("-C", $fixture.Repository, "rev-parse", "HEAD"))[0]
        $remoteHead = @(Invoke-FixtureGit -Arguments @(
            "--git-dir", $fixture.Remote, "rev-parse", "refs/heads/$expectedBranch"))[0]
        $remoteHead | Should -Be $localHead
        Get-RemoteBranches -Remote $fixture.Remote | Should -Contain $expectedBranch
    }

    It "refuses to deliver a file a later step rewrote" {
        # The gap this closes is between applying the change set and publishing
        # it: the run installs packages, builds and runs the tests in that
        # window, and a formatter or a regenerated lock file rewrites an
        # approved file without touching its path. Comparing paths alone would
        # hand those bytes the approval given to something else.
        $fixture = New-DeliveryFixture -Name "rewritten-after-approval"
        $config = New-DeliveryConfig
        $rewritten = Join-Path $fixture.Repository $fixture.NewFiles[0]
        Set-Content -LiteralPath $rewritten -Value "reformatted by a build step" -NoNewline

        { Invoke-Delivery -Fixture $fixture -Config $config -RunId "run-rewritten" } |
            Should -Throw "*different bytes from the ones that were approved*"

        # Nothing was delivered: no branch, no commit, no push.
        Get-LocalBranches -Repository $fixture.Repository | Should -Not -Contain "run-rewritten"
        @(Invoke-FixtureGit -Arguments @(
            "-C", $fixture.Repository, "rev-list", "--count", "HEAD"))[0] | Should -Be "1"
    }

    It "refuses to deliver when a later step put an approved file back" {
        # The quieter half of the same failure. A file restored to what it was
        # drops out of git's list of changes, and a publisher that only reads
        # that list raises a pull request missing work nobody agreed to drop.
        $fixture = New-DeliveryFixture -Name "reverted-after-approval"
        $config = New-DeliveryConfig
        Remove-Item -LiteralPath (Join-Path $fixture.Repository $fixture.NewFiles[0]) -Force

        { Invoke-Delivery -Fixture $fixture -Config $config -RunId "run-reverted" } |
            Should -Throw "*no longer there*"
    }

    It "requires idempotency before any live delivery mutation" {
        $fixture = New-DeliveryFixture -Name "idempotency-required"
        $config = New-DeliveryConfig
        $config.idempotency.enabled = $false
        $runId = "run-idempotency-required"
        $expectedBranch = "$([string]$config.delivery.branch_prefix)changes-876282eeaaad15b97afb2418"
        $headBefore = @(Invoke-FixtureGit -Arguments @(
            "-C", $fixture.Repository, "rev-parse", "HEAD"))[0]

        { Invoke-Delivery -Fixture $fixture -Config $config -RunId $runId } |
            Should -Throw "*requires idempotency.enabled=true*"

        @(Invoke-FixtureGit -Arguments @("-C", $fixture.Repository, "rev-parse", "HEAD"))[0] |
            Should -Be $headBefore
        Get-LocalBranches -Repository $fixture.Repository | Should -Not -Contain $expectedBranch
        Get-RemoteBranches -Remote $fixture.Remote | Should -Not -Contain $expectedBranch
    }

    It "repeats completed delivery in the same worktree and run without side effects" {
        $fixture = New-DeliveryFixture -Name "resumed-leg"
        $config = New-DeliveryConfig
        $runId = "run-resumed-leg"
        $expectedBranch = "$([string]$config.delivery.branch_prefix)changes-876282eeaaad15b97afb2418"

        $first = Invoke-Delivery -Fixture $fixture -Config $config -RunId $runId
        $first.status | Should -Be "completed"
        $headAfterFirst = @(Invoke-FixtureGit -Arguments @("-C", $fixture.Repository, "rev-parse", "HEAD"))[0]
        $commitsAfterFirst = @(Invoke-FixtureGit -Arguments @(
            "-C", $fixture.Repository, "rev-list", "--count", "HEAD"))[0]
        $branchesAfterFirst = @(Get-LocalBranches -Repository $fixture.Repository)

        # The second invocation is what a relay leg does when the job that ran
        # delivery was lost after it finished: same run identifier, same run
        # root, same repository.
        # A throw here fails the test, which is the "does not fail" assertion.
        $secondResult = Invoke-Delivery -Fixture $fixture -Config $config -RunId $runId

        @($secondResult.actions | Where-Object { $_.status -eq "executed" }).Count | Should -Be 0
        @(Get-LocalBranches -Repository $fixture.Repository) | Should -Be $branchesAfterFirst
        @(Get-LocalBranches -Repository $fixture.Repository |
            Where-Object { $_ -eq $expectedBranch }).Count | Should -Be 1
        @(Invoke-FixtureGit -Arguments @("-C", $fixture.Repository, "rev-list", "--count", "HEAD"))[0] |
            Should -Be $commitsAfterFirst
        @(Invoke-FixtureGit -Arguments @("-C", $fixture.Repository, "rev-parse", "HEAD"))[0] |
            Should -Be $headAfterFirst
        @(Invoke-FixtureGit -Arguments @(
            "--git-dir", $fixture.Remote, "rev-parse", "refs/heads/$expectedBranch"))[0] |
            Should -Be $headAfterFirst
    }

    It "rejects a partial delivery instead of claiming that a later hosted leg recovered it" {
        # Hosted relay legs use separate checkouts and transfer only the evidence
        # root. A local commit from a failed push therefore cannot be assumed to
        # exist in the next leg.
        $fixture = New-DeliveryFixture -Name "interrupted-push" `
            -RemoteUrl (Join-Path $script:DeliveryRoot "interrupted-push/absent-origin.git")
        $config = New-DeliveryConfig
        $runId = "run-interrupted-push"
        $expectedBranch = "$([string]$config.delivery.branch_prefix)changes-876282eeaaad15b97afb2418"

        { Invoke-Delivery -Fixture $fixture -Config $config -RunId $runId } |
            Should -Throw "*Failed to push automation branch*"

        $committedHead = @(Invoke-FixtureGit -Arguments @("-C", $fixture.Repository, "rev-parse", "HEAD"))[0]
        $registry = Get-Content -LiteralPath (
            Join-Path $fixture.Repository ([string]$config.idempotency.registry_path)) -Raw |
            ConvertFrom-Json -Depth 50
        @($registry.records | Where-Object { $_.actionType -eq "git.commit" }).status |
            Should -Be "executed"
        @($registry.records | Where-Object { $_.actionType -eq "git.push" }).Count | Should -Be 0

        # The remote is reachable again, exactly as it would be on a retry.
        $null = Invoke-FixtureGit -Arguments @(
            "-C", $fixture.Repository, "remote", "set-url", "origin", $fixture.Remote)

        { Invoke-Delivery -Fixture $fixture -Config $config -RunId $runId } |
            Should -Throw "*Partial delivery state cannot be resumed safely*"
        Get-RemoteBranches -Remote $fixture.Remote | Should -Not -Contain $expectedBranch
        @(Invoke-FixtureGit -Arguments @("-C", $fixture.Repository, "rev-parse", "HEAD"))[0] |
            Should -Be $committedHead
    }

    It "names the delivery after the work it implements, not after the run carrying it" {
        # The branch used to be named after the run. A run is not the work: the
        # next build has a different id, so it opened a second branch for the
        # same work item and asked for the same change to be merged twice.
        $fixture = New-DeliveryFixture -Name "stable-identity" -WorkItemId "4242"
        $config = New-DeliveryConfig
        $expectedBranch = "$([string]$config.delivery.branch_prefix)wi-4242"

        $result = Invoke-Delivery -Fixture $fixture -Config $config -RunId "run-first-attempt"

        $result.status | Should -Be "completed"
        @($result.actions | Where-Object { $_.type -eq "git.branch" }).externalId |
            Should -Be $expectedBranch
        Get-RemoteBranches -Remote $fixture.Remote | Should -Contain $expectedBranch
        @(Get-RemoteBranches -Remote $fixture.Remote |
            Where-Object { $_ -like "$([string]$config.delivery.branch_prefix)*" }).Count |
            Should -Be 1
    }

    It "continues delivery without duplicate pull requests with a <LocalBranch> local branch and update=<Update>" -ForEach @(
        @{ LocalBranch = 'absent'; Update = $false },
        @{ LocalBranch = 'retained'; Update = $false },
        @{ LocalBranch = 'behind'; Update = $false },
        @{ LocalBranch = 'diverged'; Update = $false },
        @{ LocalBranch = 'retained'; Update = $true },
        @{ LocalBranch = 'retained'; Update = 'delete' }
    ) {
        # The scenario: the pull request was created and the answer was lost, or
        # the job died just after it. The next build starts from a clean
        # checkout with an empty local registry, so nothing it owns remembers
        # any of this. Without asking the server it delivers everything again
        # and a reviewer is handed the same change twice, with no way to tell
        # which one is real.
        $fixture = New-DeliveryFixture -Name "no-duplicate-pull-request-$LocalBranch-$Update" -WorkItemId "5150"
        $config = New-DeliveryConfig
        $config.delivery.create_draft_pull_request = $true
        $expectedBranch = "$([string]$config.delivery.branch_prefix)wi-5150"

        Mock Invoke-RestMethod {
            param($Uri, $Method)
            if ($Uri -like "*/_apis/connectionData?*") { return New-TestAdoConnectionData }
            if ($Uri -like "*/refs?*") { return [pscustomobject]@{ count = 0; value = @() } }
            if ($Uri -like "*/pullrequests?*" -and "$Method" -eq "Get") {
                return [pscustomobject]@{ count = 0; value = @() }
            }
            if ($Uri -like "*/pullrequests?*") { return [pscustomobject]@{ pullRequestId = 77 } }
            throw "Unexpected Azure DevOps request: $Uri"
        }

        $first = Invoke-Delivery -Fixture $fixture -Config $config -RunId "run-lost-answer"
        $first.status | Should -Be "completed"
        @($first.actions | Where-Object { $_.type -eq "pull-request.draft" }).externalId |
            Should -Be "77"
        $deliveredHead = @(Invoke-FixtureGit -Arguments @(
            "--git-dir", $fixture.Remote, "rev-parse", "refs/heads/$expectedBranch"))[0]

        # A different build, a clean clone, and a local registry that knows
        # nothing - everything the first run recorded for itself is gone.
        $retry = New-FreshCheckout -Fixture $fixture -Name "retry-workspace"
        # A self-hosted checkout retains refs/heads even after cleaning files
        # and checking out the source commit in detached HEAD state.
        $localTip = ''
        if ($LocalBranch -ne 'absent') {
            $localTip = switch ($LocalBranch) {
                'retained' { $deliveredHead }
                'behind' { @(Invoke-FixtureGit -Arguments @('-C', $retry.Repository, 'rev-parse', 'main'))[0] }
                'diverged' { @(Invoke-FixtureGit -Arguments @('-C', $retry.Repository, 'commit-tree', 'main^{tree}', '-p', 'main', '-m', 'Unpublished local work'))[0] }
            }
            $null = Invoke-FixtureGit -Arguments @('-C', $retry.Repository, 'branch', $expectedBranch, $localTip)
        }
        $null = Invoke-FixtureGit -Arguments @('-C', $retry.Repository, 'switch', '--detach', 'main')
        # A runtime update arrived on the source branch after the first PR.
        # Publication must not roll it back by checking out the old PR tree.
        $runtimePath = Join-Path $retry.Repository 'foundry/runtime.ps1'
        New-Item -ItemType Directory -Path (Split-Path $runtimePath -Parent) -Force | Out-Null
        Set-Content -LiteralPath $runtimePath -Value 'current runtime' -NoNewline
        $null = Invoke-FixtureGit -Arguments @('-C', $retry.Repository, 'add', '--', 'foundry/runtime.ps1')
        $null = Invoke-FixtureGit -Arguments @('-C', $retry.Repository, 'commit', '-m', 'Runtime fix on source')
        $sourceTip = @(Invoke-FixtureGit -Arguments @('-C', $retry.Repository, 'rev-parse', 'HEAD'))[0]
        $indexPath = Join-Path $retry.Repository '.git/index'
        $indexHash = (Get-FileHash -LiteralPath $indexPath).Hash
        if ($Update) {
            foreach ($file in $retry.NewFiles) {
                Set-Content -LiteralPath (Join-Path $retry.Repository $file) -Value 'approved follow-up' -NoNewline
            }
            $followUpChanges = @($retry.NewFiles | ForEach-Object {
                @{ path = $_; operation = 'create'; content = 'approved follow-up' }
            })
            if ($Update -eq 'delete') {
                $config.delivery.allow_file_deletions = $true
                Remove-Item -LiteralPath (Join-Path $retry.Repository $retry.NewFiles[-1]) -Force
                $followUpChanges[-1] = @{ path = $retry.NewFiles[-1]; operation = 'delete' }
            }
            @{ changes = $followUpChanges } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $retry.RunRoot 'planning/change-set.json')
        }
        # The values are baked into the mock rather than read from a variable:
        # a mock body runs in Pester's own scope, not the test's.
        Mock Invoke-RestMethod ([scriptblock]::Create(@"
            param(`$Uri, `$Method)
            if (`$Uri -like "*/_apis/connectionData?*") { return New-TestAdoConnectionData }
            if (`$Uri -like "*/refs?*") {
                return [pscustomobject]@{
                    count = 1
                    value = @([pscustomobject]@{
                        name = "refs/heads/$expectedBranch"; objectId = "$deliveredHead"
                    })
                }
            }
            if (`$Uri -like "*/pullrequests?*" -and "`$Method" -eq "Get") {
                return [pscustomobject]@{
                    count = 1
                    value = @([pscustomobject]@{
                        pullRequestId = 77
                        sourceRefName = "refs/heads/$expectedBranch"
                        status = "active"
                    })
                }
            }
            throw "A second pull request was requested for a delivery that already has one: `$Uri"
"@))

        $second = Invoke-Delivery -Fixture $retry -Config $config -RunId "run-after-the-loss"

        $second.status | Should -Be "completed"
        $pullRequestAction = @($second.actions | Where-Object { $_.type -eq "pull-request.draft" })
        @($pullRequestAction).Count | Should -Be 1
        [string]$pullRequestAction[0].externalId | Should -Be "77"
        [string]$pullRequestAction[0].summary | Should -Match "Reuse pull request 77"

        # One branch on the server, still at the commit the first run pushed.
        @(Get-RemoteBranches -Remote $fixture.Remote |
            Where-Object { $_ -like "$([string]$config.delivery.branch_prefix)*" }) |
            Should -Be @($expectedBranch)
        $remoteTip = @(Invoke-FixtureGit -Arguments @(
            "--git-dir", $fixture.Remote, "rev-parse", "refs/heads/$expectedBranch"))[0]
        if ($Update) {
            $remoteTip | Should -Not -Be $deliveredHead
            @(Invoke-FixtureGit -Arguments @('--git-dir', $fixture.Remote, 'rev-parse', "${remoteTip}^"))[0] |
                Should -Be $deliveredHead
            foreach ($file in $retry.NewFiles) {
                if ($Update -eq 'delete' -and $file -eq $retry.NewFiles[-1]) {
                    @(Invoke-FixtureGit -Arguments @('--git-dir', $fixture.Remote, 'ls-tree', '--name-only', $remoteTip, '--', $file)).Count |
                        Should -Be 0
                    continue
                }
                @(Invoke-FixtureGit -Arguments @('--git-dir', $fixture.Remote, 'show', "${remoteTip}:$file"))[0] |
                    Should -Be 'approved follow-up'
            }
        } else { $remoteTip | Should -Be $deliveredHead }
        if ($LocalBranch -ne 'absent') {
            @(Invoke-FixtureGit -Arguments @('-C', $retry.Repository, 'rev-parse', "refs/heads/$expectedBranch"))[0] |
                Should -Be $localTip
        }
        # The current runtime, checkout and caller's index survive publication.
        @(Invoke-FixtureGit -Arguments @("-C", $retry.Repository, "rev-parse", "HEAD"))[0] |
            Should -Be $sourceTip
        (Get-FileHash -LiteralPath $indexPath).Hash | Should -Be $indexHash
        Get-Content -LiteralPath $runtimePath -Raw | Should -Be 'current runtime'
        @($second.actions | Where-Object type -eq 'git.commit').externalId | Should -Be $remoteTip
    }

    It "continues a branch an earlier run pushed rather than forking beside it" {
        # The other half of the same loss: the branch and its commit reached the
        # server, the pull request did not. Creating the branch again from the
        # source branch would put this run's commit beside the earlier one, and
        # the push would be refused as a non-fast-forward.
        $fixture = New-DeliveryFixture -Name "continue-pushed-branch" -WorkItemId "6060"
        $config = New-DeliveryConfig
        $expectedBranch = "$([string]$config.delivery.branch_prefix)wi-6060"

        $first = Invoke-Delivery -Fixture $fixture -Config $config -RunId "run-pushed-only"
        $first.status | Should -Be "completed"
        $deliveredHead = @(Invoke-FixtureGit -Arguments @(
            "--git-dir", $fixture.Remote, "rev-parse", "refs/heads/$expectedBranch"))[0]

        $retry = New-FreshCheckout -Fixture $fixture -Name "continue-workspace"
        Mock Invoke-RestMethod ([scriptblock]::Create(@"
            param(`$Uri, `$Method)
            if (`$Uri -like "*/_apis/connectionData?*") { return New-TestAdoConnectionData }
            if (`$Uri -like "*/refs?*") {
                return [pscustomobject]@{
                    count = 1
                    value = @([pscustomobject]@{
                        name = "refs/heads/$expectedBranch"; objectId = "$deliveredHead"
                    })
                }
            }
            if (`$Uri -like "*/pullrequests?*") { return [pscustomobject]@{ count = 0; value = @() } }
            throw "Unexpected Azure DevOps request: `$Uri"
"@))

        $second = Invoke-Delivery -Fixture $retry -Config $config -RunId "run-continuing"

        $second.status | Should -Be "completed"
        @(Invoke-FixtureGit -Arguments @(
            "-C", $retry.Repository, "rev-parse", "--abbrev-ref", "HEAD"))[0] |
            Should -Be 'main'
        # Publication reuses the remote commit and leaves this checkout alone.
        @($second.actions | Where-Object type -eq 'git.commit').externalId |
            Should -Be $deliveredHead
        @($second.actions | Where-Object { $_.type -eq "git.commit" }).summary |
            Should -Match "Reuse commit already on branch"
        @(Get-RemoteBranches -Remote $fixture.Remote |
            Where-Object { $_ -like "$([string]$config.delivery.branch_prefix)*" }) |
            Should -Be @($expectedBranch)
    }

    It "refuses to deliver onto a protected branch and leaves the repository exactly as it found it" {
        $fixture = New-DeliveryFixture -Name "protected-branch" -WorkItemId '123'
        # An empty prefix makes the automation branch collide with the source
        # branch, which is the misconfiguration the guard exists for.
        $config = New-DeliveryConfig
        $config.delivery.branch_prefix = ""
        $config.project.source_branch = 'wi-123'
        $branchesBefore = @(Get-LocalBranches -Repository $fixture.Repository)
        $headBefore = @(Invoke-FixtureGit -Arguments @("-C", $fixture.Repository, "rev-parse", "HEAD"))[0]

        { Invoke-Delivery -Fixture $fixture -Config $config -RunId "MAIN" } |
            Should -Throw "*may not be a protected/source branch*"

        @(Get-LocalBranches -Repository $fixture.Repository) | Should -Be $branchesBefore
        @(Invoke-FixtureGit -Arguments @("-C", $fixture.Repository, "rev-parse", "HEAD"))[0] |
            Should -Be $headBefore
        @(Invoke-FixtureGit -Arguments @("-C", $fixture.Repository, "rev-list", "--count", "HEAD"))[0] |
            Should -Be "1"
        # The proposed files are still untracked, so nothing was staged either.
        $status = @(Invoke-FixtureGit -Arguments @(
            "-C", $fixture.Repository, "status", "--porcelain=v1", "--untracked-files=all"))
        foreach ($file in $fixture.NewFiles) {
            @($status | Where-Object { $_ -eq "?? $file" }).Count | Should -Be 1
        }
        Test-Path (Join-Path $fixture.Repository ([string]$config.idempotency.registry_path)) |
            Should -BeFalse
    }

    It "records every delivery action in the idempotency registry in the shape the registry schema requires" {
        $fixture = New-DeliveryFixture -Name "registry-shape"
        $config = New-DeliveryConfig
        $runId = "run-registry-shape"

        $null = Invoke-Delivery -Fixture $fixture -Config $config -RunId $runId

        $registryPath = Join-Path $fixture.Repository ([string]$config.idempotency.registry_path)
        Test-Path $registryPath -PathType Leaf | Should -BeTrue
        { & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $registryPath `
            -SchemaPath (Join-Path $script:Root "schemas/runtime/idempotency-registry.schema.json") `
            -SchemaRoot (Join-Path $script:Root "schemas") } | Should -Not -Throw

        $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json -Depth 50
        @($registry.records).Count | Should -Be 3
        @($registry.records.actionType | Sort-Object) |
            Should -Be @("git.branch", "git.commit", "git.push")
        foreach ($record in @($registry.records)) {
            $record.status | Should -Be "executed"
            $record.runId | Should -Be $runId
            $record.key | Should -Match "^[a-f0-9]{64}$"
        }

        # A check of a key that was never registered must not invent a record.
        $unknownKey = & (Join-Path $script:Root "scripts/New-IdempotencyKey.ps1") `
            -ActionType "git.tag" -SourceRef $runId
        $check = & (Join-Path $script:Root "scripts/Use-IdempotencyRegistry.ps1") `
            -Operation check -RegistryPath $registryPath -Key $unknownKey
        $check.exists | Should -BeFalse
        $check.record | Should -BeNullOrEmpty
    }

    It "keeps one project's marker from adopting another project's work item" {
        # The marker is a hash of the plan's own reference, and two projects
        # running the same generated plan produce the same reference. Without the
        # delivery target in the key, the second project's run finds the first
        # project's item, adopts it, and files nothing - the work exists only in
        # somebody else's backlog.
        $key = Join-Path $script:Root "scripts/New-IdempotencyKey.ps1"
        $here = & $key -ActionType "work-item.azure-devops" -SourceRef "pbi-1" `
            -Scope "https://dev.azure.com/sefe|X AI Mission|repo-a"
        $elsewhere = & $key -ActionType "work-item.azure-devops" -SourceRef "pbi-1" `
            -Scope "https://dev.azure.com/sefe|Other Project|repo-b"
        $unscoped = & $key -ActionType "work-item.azure-devops" -SourceRef "pbi-1"

        $here | Should -Match "^[a-f0-9]{64}$"
        $here | Should -Not -Be $elsewhere
        $here | Should -Not -Be $unscoped
        # The same project asking twice still gets the same key, or nothing
        # would ever be recognised as already created.
        $here | Should -Be (& $key -ActionType "work-item.azure-devops" -SourceRef "pbi-1" `
            -Scope "https://dev.azure.com/sefe|X AI Mission|repo-a")
    }

    It "emits an action result that the deterministic action schema accepts" {
        # Invoke-DeterministicAction.ps1 writes this object to action-result.json
        # and validates it against schemas/actions/action-result.schema.json
        # before the stage is allowed to succeed, so an object the schema rejects
        # fails the run after the branch has already been pushed.
        $fixture = New-DeliveryFixture -Name "action-result-shape"
        $config = New-DeliveryConfig
        $result = Invoke-Delivery -Fixture $fixture -Config $config -RunId "run-action-result-shape"

        $artifact = Join-Path $fixture.RunRoot "deliver/action-result.json"
        New-Item -ItemType Directory -Path (Split-Path $artifact -Parent) -Force | Out-Null
        $result | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $artifact -Encoding utf8

        { & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $artifact `
            -SchemaPath (Join-Path $script:Root "schemas/actions/action-result.schema.json") `
            -SchemaRoot (Join-Path $script:Root "schemas") } | Should -Not -Throw
    }
}

Describe "Artifacts carried between stages by identity" {
    BeforeAll {
        . (Join-Path $script:Root "scripts/Common.ps1")

        function New-IdentityRun {
            param([Parameter(Mandatory)][string]$Name)
            $runRoot = Join-Path $TestDrive "identity-$Name"
            New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
            return $runRoot
        }

        function Add-RunFile {
            param(
                [Parameter(Mandatory)][string]$RunRoot,
                [Parameter(Mandatory)][string]$RelativePath,
                [Parameter(Mandatory)][string]$Content
            )
            $full = Join-Path $RunRoot $RelativePath
            New-Item -ItemType Directory -Path (Split-Path $full -Parent) -Force | Out-Null
            Set-Content -LiteralPath $full -Value $Content -Encoding utf8 -NoNewline
            return $full
        }

        function New-ArtifactRecord {
            param(
                [Parameter(Mandatory)][string]$RunRoot,
                [Parameter(Mandatory)][string]$RelativePath
            )
            $full = Join-Path $RunRoot $RelativePath
            return [pscustomobject][ordered]@{
                name = (Split-Path $RelativePath -Leaf)
                relativePath = $RelativePath.Replace("\", "/")
                sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        }

        function Save-RunState {
            param(
                [Parameter(Mandatory)][string]$RunRoot,
                [Parameter(Mandatory)][object[]]$Stages
            )
            $state = [pscustomobject]@{ stages = $Stages }
            $state | ConvertTo-Json -Depth 100 |
                Set-Content -LiteralPath (Join-Path $RunRoot "workflow-state.json") -Encoding utf8
        }
    }

    It "resolves the artifact the run carried forward, not the newest file of that name" {
        $runRoot = New-IdentityRun -Name "carried"
        $approved = Add-RunFile -RunRoot $runRoot `
            -RelativePath "architecture/critic-iteration-2/automation-blueprint.json" `
            -Content '{"runId":"run-identity","status":"completed"}'
        # A later, newer file of the same name is exactly what a directory search
        # would find, and it is not what the critics approved.
        Start-Sleep -Milliseconds 20
        Add-RunFile -RunRoot $runRoot `
            -RelativePath "architecture/critic-iteration-3/automation-blueprint.json" `
            -Content '{"runId":"run-identity","status":"draft"}' | Out-Null
        Save-RunState -RunRoot $runRoot -Stages @(
            [pscustomobject]@{
                id = "architecture"
                attempts = @(
                    [pscustomobject]@{
                        status = "revision_required"
                        artifacts = @(New-ArtifactRecord -RunRoot $runRoot `
                            -RelativePath "architecture/critic-iteration-3/automation-blueprint.json")
                    },
                    [pscustomobject]@{
                        status = "approved"
                        artifacts = @(New-ArtifactRecord -RunRoot $runRoot `
                            -RelativePath "architecture/critic-iteration-2/automation-blueprint.json")
                    }
                )
            }
        )

        $resolved = Resolve-QaFoundryDeclaredInputs -RunRoot $runRoot -StageId "consumer" -Inputs (
            [pscustomobject]@{
                blueprint = [pscustomobject]@{
                    stage = "architecture"; artifact = "automation-blueprint.json"
                }
            })

        $resolved["blueprint"].path | Should -Be $approved
        (Get-Content -LiteralPath $resolved["blueprint"].path -Raw) | Should -Match "completed"
    }

    It "refuses an artifact that changed after the stage recorded it" {
        $runRoot = New-IdentityRun -Name "changed"
        $path = Add-RunFile -RunRoot $runRoot -RelativePath "producer/plan.json" -Content '{"a":1}'
        $record = New-ArtifactRecord -RunRoot $runRoot -RelativePath "producer/plan.json"
        Save-RunState -RunRoot $runRoot -Stages @(
            [pscustomobject]@{
                id = "producer"
                attempts = @([pscustomobject]@{ status = "completed"; artifacts = @($record) })
            }
        )
        Set-Content -LiteralPath $path -Value '{"a":2}' -Encoding utf8 -NoNewline

        {
            Resolve-QaFoundryDeclaredInputs -RunRoot $runRoot -StageId "consumer" -Inputs (
                [pscustomobject]@{
                    plan = [pscustomobject]@{ stage = "producer"; artifact = "plan.json" }
                })
        } | Should -Throw "*changed since stage 'producer' produced it*"
    }

    It "refuses an artifact recorded as belonging to another run" {
        $runRoot = New-IdentityRun -Name "foreign"
        Add-RunFile -RunRoot $runRoot -RelativePath "producer/plan.json" `
            -Content '{"runId":"some-other-run"}' | Out-Null
        Save-RunState -RunRoot $runRoot -Stages @(
            [pscustomobject]@{
                id = "producer"
                attempts = @([pscustomobject]@{
                    status = "completed"
                    artifacts = @(New-ArtifactRecord -RunRoot $runRoot -RelativePath "producer/plan.json")
                })
            }
        )

        {
            Resolve-QaFoundryDeclaredInputs -RunRoot $runRoot -StageId "consumer" -RunId "run-identity" -Inputs (
                [pscustomobject]@{
                    plan = [pscustomobject]@{ stage = "producer"; artifact = "plan.json" }
                })
        } | Should -Throw "*not from this run*"
    }

    It "refuses a stage that recorded two artifacts under one name" {
        $runRoot = New-IdentityRun -Name "ambiguous"
        Add-RunFile -RunRoot $runRoot -RelativePath "producer/a/plan.json" -Content '{"a":1}' | Out-Null
        Add-RunFile -RunRoot $runRoot -RelativePath "producer/b/plan.json" -Content '{"a":2}' | Out-Null
        Save-RunState -RunRoot $runRoot -Stages @(
            [pscustomobject]@{
                id = "producer"
                attempts = @([pscustomobject]@{
                    status = "completed"
                    artifacts = @(
                        (New-ArtifactRecord -RunRoot $runRoot -RelativePath "producer/a/plan.json"),
                        (New-ArtifactRecord -RunRoot $runRoot -RelativePath "producer/b/plan.json")
                    )
                })
            }
        )

        {
            Resolve-QaFoundryDeclaredInputs -RunRoot $runRoot -StageId "consumer" -Inputs (
                [pscustomobject]@{
                    plan = [pscustomobject]@{ stage = "producer"; artifact = "plan.json" }
                })
        } | Should -Throw "*recorded 2 artifact(s) by that name*"
    }

    It "refuses a recorded path that climbs out of the run" {
        $runRoot = New-IdentityRun -Name "traversal"
        New-Item -ItemType Directory -Path (Join-Path $TestDrive "outside") -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $TestDrive "outside/secret.json") -Value '{}' -Encoding utf8

        {
            Resolve-QaFoundryRunArtifactPath -RunRoot $runRoot -RelativePath "../outside/secret.json"
        } | Should -Throw "*escapes the run directory*"
    }

    It "refuses a recorded path that is absolute" {
        $runRoot = New-IdentityRun -Name "rooted"
        $outside = Join-Path $TestDrive "rooted-outside.json"
        Set-Content -LiteralPath $outside -Value '{}' -Encoding utf8

        { Resolve-QaFoundryRunArtifactPath -RunRoot $runRoot -RelativePath $outside } |
            Should -Throw "*is absolute*"
    }

    It "refuses a recorded path that reaches its file through a link" {
        $runRoot = New-IdentityRun -Name "link"
        $outside = Join-Path $TestDrive "link-target"
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $outside "plan.json") -Value '{}' -Encoding utf8
        $junction = Join-Path $runRoot "elsewhere"
        try {
            New-Item -ItemType Junction -Path $junction -Target $outside -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because "this machine does not allow creating a junction"
            return
        }

        { Resolve-QaFoundryRunArtifactPath -RunRoot $runRoot -RelativePath "elsewhere/plan.json" } |
            Should -Throw "*passes through a link*"
    }

    It "validates a declared input against the schema the workflow named for it" {
        $runRoot = New-IdentityRun -Name "schema"
        Add-RunFile -RunRoot $runRoot -RelativePath "producer/change-review-subject.json" `
            -Content '{"runId":"run-identity"}' | Out-Null
        Save-RunState -RunRoot $runRoot -Stages @(
            [pscustomobject]@{
                id = "producer"
                attempts = @([pscustomobject]@{
                    status = "completed"
                    artifacts = @(New-ArtifactRecord -RunRoot $runRoot `
                        -RelativePath "producer/change-review-subject.json")
                })
            }
        )

        {
            Resolve-QaFoundryDeclaredInputs -RunRoot $runRoot -StageId "consumer" -Inputs (
                [pscustomobject]@{
                    reviewSubject = [pscustomobject]@{
                        stage = "producer"
                        artifact = "change-review-subject.json"
                        schema = "schemas/actions/change-review-subject.schema.json"
                    }
                })
        } | Should -Throw "*Schema validation failed*"
    }
}

Describe "Declared inputs under maximum assurance" {
    BeforeAll {
        $script:AssuranceConfig = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root

        function New-InputWorkflow {
            param([Parameter(Mandatory)][object]$Inputs, [string[]]$ConsumerDependsOn = @("producer"))
            return [pscustomobject]@{
                stages = @(
                    [pscustomobject]@{
                        id = "producer"
                        risk = "low"
                        type = "deterministic_action"
                        depends_on = @()
                        action = [pscustomobject]@{ handler = "quality_suite"; output = "action-result.json" }
                    },
                    [pscustomobject]@{
                        id = "unrelated"
                        risk = "low"
                        type = "deterministic_action"
                        depends_on = @()
                        action = [pscustomobject]@{ handler = "quality_suite"; output = "action-result.json" }
                    },
                    [pscustomobject]@{
                        id = "consumer"
                        risk = "low"
                        type = "deterministic_action"
                        depends_on = $ConsumerDependsOn
                        inputs = $Inputs
                        action = [pscustomobject]@{ handler = "quality_suite"; output = "action-result.json" }
                    }
                )
            }
        }
    }

    It "accepts an input taken from a stage the consumer depends on" {
        $workflow = New-InputWorkflow -Inputs ([pscustomobject]@{
            plan = [pscustomobject]@{ stage = "producer"; artifact = "plan.json" }
        })
        {
            & (Join-Path $script:Root "scripts/Test-WorkflowAssurance.ps1") `
                -Workflow $workflow -Config $script:AssuranceConfig
        } | Should -Not -Throw
    }

    It "rejects an input taken from a stage the consumer does not depend on" {
        $workflow = New-InputWorkflow -Inputs ([pscustomobject]@{
            plan = [pscustomobject]@{ stage = "unrelated"; artifact = "plan.json" }
        })
        {
            & (Join-Path $script:Root "scripts/Test-WorkflowAssurance.ps1") `
                -Workflow $workflow -Config $script:AssuranceConfig
        } | Should -Throw "*does not transitively depend on*"
    }

    It "rejects an input naming a stage this workflow does not run" {
        $workflow = New-InputWorkflow -Inputs ([pscustomobject]@{
            plan = [pscustomobject]@{ stage = "imaginary"; artifact = "plan.json" }
        })
        {
            & (Join-Path $script:Root "scripts/Test-WorkflowAssurance.ps1") `
                -Workflow $workflow -Config $script:AssuranceConfig
        } | Should -Throw "*which this workflow does not run*"
    }
}

Describe "Review context after a revision" {
    It "hands the reviewers the one subject the run carried forward" {
        $config = Set-ResolvedTestAiProfile -Config (
            Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root) -ProfileName "mock"
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $repository = Join-Path $TestDrive "revision-repository"
        $runRoot = Join-Path $TestDrive "revision-run"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

        $supersededDirectory = Join-Path $runRoot "materialization"
        $currentDirectory = Join-Path $runRoot "materialization/iteration-2"
        New-Item -ItemType Directory -Path $supersededDirectory -Force | Out-Null
        New-Item -ItemType Directory -Path $currentDirectory -Force | Out-Null
        $superseded = Join-Path $supersededDirectory "change-review-subject.json"
        $current = Join-Path $currentDirectory "change-review-subject.json"
        Set-Content -LiteralPath $superseded -Value '{"note":"superseded"}' -Encoding utf8 -NoNewline
        Set-Content -LiteralPath $current -Value '{"note":"current"}' -Encoding utf8 -NoNewline

        $state = [pscustomobject]@{
            stages = @([pscustomobject]@{
                id = "materialization"
                attempts = @(
                    [pscustomobject]@{
                        status = "completed"
                        artifacts = @([pscustomobject]@{
                            name = "change-review-subject.json"
                            relativePath = "materialization/change-review-subject.json"
                            sha256 = (Get-FileHash -LiteralPath $superseded -Algorithm SHA256).Hash.ToLowerInvariant()
                        })
                    },
                    [pscustomobject]@{
                        status = "completed"
                        artifacts = @([pscustomobject]@{
                            name = "change-review-subject.json"
                            relativePath = "materialization/iteration-2/change-review-subject.json"
                            sha256 = (Get-FileHash -LiteralPath $current -Algorithm SHA256).Hash.ToLowerInvariant()
                        })
                    }
                )
            })
        }
        $state | ConvertTo-Json -Depth 100 |
            Set-Content -LiteralPath (Join-Path $runRoot "workflow-state.json") -Encoding utf8

        $stage = [pscustomobject]@{
            id = "revision-review"
            type = "parallel_review"
            inputs = [pscustomobject]@{
                reviewSubject = [pscustomobject]@{
                    stage = "materialization"
                    artifact = "change-review-subject.json"
                }
            }
            agents = @(
                [pscustomobject]@{
                    id = "first-reviewer"
                    prompt = "prompts/sdlc/review-correctness.md"
                    schema = "schemas/sdlc/review.schema.json"
                    output = "first-review.json"
                }
            )
            approval = [pscustomobject]@{
                strategy = "unanimous"
                max_iterations = 1
                on_exhaustion = "proceed"
            }
        }

        $result = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage $stage -Config $config -Policy $policy -RunRoot $runRoot `
            -RepositoryRoot $repository -RunId "run-revision-review" -Iteration 1

        $result.Status | Should -Be "approved"
        @($result.Inputs).Count | Should -Be 1
        [string]$result.Inputs[0].relativePath |
            Should -Be "materialization/iteration-2/change-review-subject.json"
        $request = Get-Content -LiteralPath (
            Join-Path $runRoot "revision-review/first-review.json.attempt-1.request.md") -Raw
        $request | Should -Match "current"
        $request | Should -Not -Match "superseded"
    }
}

# Build 464 exhausted all four architecture iterations without consensus. The dissenting
# critic demanded canonical endpoints, credentials and topic names that no input to the run
# contained and nobody could supply, so the producer could never satisfy it. A critic must
# now say whether the producer can settle a finding inside the blueprint, and only such a
# finding can justify asking for another revision.
Describe "Blueprint review finding scope" {
    BeforeAll {
        $script:ReviewSchemas = @(
            (Join-Path $script:Root "schemas/architecture/architecture-review.schema.json"),
            (Join-Path $script:Root "schemas/architecture/architecture-specialist-review.schema.json")
        )

        function New-ScopedFinding {
            param([string]$Severity, [string]$Scope)
            $finding = [ordered]@{ severity = $Severity; message = "m"; evidence = "e" }
            if ($Scope) { $finding.resolutionScope = $Scope }
            return $finding
        }

        function Test-BlueprintReview {
            param(
                [string]$Decision,
                [object[]]$Findings,
                [string]$AgentId = "architecture-critic",
                [string]$SchemaName = "architecture-review.schema.json"
            )
            $review = [ordered]@{
                agentId = $AgentId
                stageId = "architecture"
                runId = "run-scope"
                status = "completed"
                summary = "A blueprint review used to exercise the scope rules."
                evidence = @()
                assumptions = @()
                unknowns = @()
                warnings = @()
                details = @{}
                decision = $Decision
                findings = @($Findings)
                requiredChanges = @()
                confidence = 0.9
            }
            $path = Join-Path $TestDrive "scoped-review.json"
            $review | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding utf8
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $path `
                -SchemaPath (Join-Path $script:Root "schemas/architecture/$SchemaName") `
                -SchemaRoot (Join-Path $script:Root "schemas") | Out-Null
        }
    }

    It "requires every finding to declare where it can be resolved" {
        { Test-BlueprintReview -Decision "approved" `
            -Findings @((New-ScopedFinding -Severity "info" -Scope $null)) } |
            Should -Throw -ExpectedMessage "*resolutionScope*"
    }

    It "accepts a revision demanded by a defect the producer can fix" {
        { Test-BlueprintReview -Decision "revision_required" `
            -Findings @((New-ScopedFinding -Severity "error" -Scope "blueprint_revision")) } |
            Should -Not -Throw
    }

    It "refuses a revision demanded only by facts nobody in the run can supply" {
        { Test-BlueprintReview -Decision "revision_required" `
            -Findings @(
                (New-ScopedFinding -Severity "critical" -Scope "external_prerequisite"),
                (New-ScopedFinding -Severity "warning" -Scope "blueprint_revision")) } |
            Should -Throw
    }

    It "refuses an approval that still carries a blocking finding" {
        { Test-BlueprintReview -Decision "approved" `
            -Findings @((New-ScopedFinding -Severity "error" -Scope "blueprint_revision")) } |
            Should -Throw
    }

    It "lets an approval carry an unresolved external prerequisite" {
        { Test-BlueprintReview -Decision "approved" `
            -Findings @((New-ScopedFinding -Severity "warning" -Scope "external_prerequisite")) } |
            Should -Not -Throw
    }

    It "applies the same rules to the specialist critics" {
        { Test-BlueprintReview -Decision "revision_required" `
            -Findings @((New-ScopedFinding -Severity "error" -Scope "external_prerequisite")) `
            -AgentId "architecture-security-critic" `
            -SchemaName "architecture-specialist-review.schema.json" } |
            Should -Throw

        { Test-BlueprintReview -Decision "revision_required" `
            -Findings @((New-ScopedFinding -Severity "error" -Scope "blueprint_revision")) `
            -AgentId "architecture-delivery-critic" `
            -SchemaName "architecture-specialist-review.schema.json" } |
            Should -Not -Throw
    }

    It "carries the scope into the ledger the producer is briefed with" {
        $history = @(
            [pscustomobject]@{
                criticId = "architecture-critic"
                revision = 1
                decision = "revision_required"
                findings = @(
                    [pscustomobject]@{
                        severity = "error"; message = "Contract is inconsistent."
                        evidence = "e"; resolutionScope = "blueprint_revision"
                    },
                    [pscustomobject]@{
                        severity = "warning"; message = "Endpoint is unknown."
                        evidence = "e"; resolutionScope = "external_prerequisite"
                    }
                )
                requiredChanges = @("Make the contract self-consistent.")
            }
        )
        $ledger = New-QaFoundryRevisionLedger -RunId "run-1" -StageId "architecture" `
            -Revision 2 -History $history
        @($ledger.outstandingFindings).Count | Should -Be 2
        $ledger.outstandingFindings[0].resolutionScope | Should -Be "blueprint_revision"
        $ledger.outstandingFindings[1].resolutionScope | Should -Be "external_prerequisite"

        $path = Join-Path $TestDrive "scoped-ledger.json"
        $ledger | ConvertTo-Json -Depth 100 | Set-Content -Path $path -Encoding utf8
        { & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $path `
            -SchemaPath (Join-Path $script:Root "schemas/architecture/revision-ledger.schema.json") `
            -SchemaRoot (Join-Path $script:Root "schemas") } | Should -Not -Throw
    }

    It "leaves the scope out of the ledger when a critic does not classify" {
        $history = @(
            [pscustomobject]@{
                criticId = "code-review"
                revision = 1
                decision = "revision_required"
                findings = @(
                    [pscustomobject]@{ severity = "error"; message = "m"; evidence = "e" }
                )
                requiredChanges = @("Fix it.")
            }
        )
        $ledger = New-QaFoundryRevisionLedger -RunId "run-1" -StageId "review" `
            -Revision 2 -History $history
        @($ledger.outstandingFindings).Count | Should -Be 1
        $ledger.outstandingFindings[0].Keys | Should -Not -Contain "resolutionScope"
    }
}

# Build 465 lost leg 1 after the work had succeeded. architecture-critic returned an
# empty first answer, the retry produced a schema-valid approval, and the stage was
# then killed by the runspace's HadErrors flag, which the recovered attempt had left
# set. The crash message was "Parallel agent 'architecture-critic' failed: " with
# nothing after the colon, because the error stream held only blank noise.
Describe "Recoverable diagnostics from a parallel agent" {
    It "keeps a validated result that arrived after noise on the error stream" {
        $config = Set-ResolvedTestAiProfile -Config (
            Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root)
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/stderr-noise-review-provider.mjs"
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $repository = Join-Path $TestDrive "noise-repository"
        $runRoot = Join-Path $TestDrive "noise-run"
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

        $stage = [pscustomobject]@{
            id = "revision-review"
            type = "parallel_review"
            agents = @(
                [pscustomobject]@{
                    id = "first-reviewer"
                    prompt = "prompts/sdlc/review-correctness.md"
                    schema = "schemas/sdlc/review.schema.json"
                    output = "first-review.json"
                }
            )
            approval = [pscustomobject]@{
                strategy = "unanimous"
                max_iterations = 1
                on_exhaustion = "proceed"
            }
        }

        $result = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage $stage -Config $config -Policy $policy -RunRoot $runRoot `
            -RepositoryRoot $repository -RunId "run-stderr-noise" -Iteration 1

        $result.Status | Should -Be "approved"
        Test-Path -LiteralPath (Join-Path $runRoot "revision-review/first-review.json") |
            Should -BeTrue
    }

    It "explains itself when a parallel agent returns nothing at all" {
        $pool = [RunspaceFactory]::CreateRunspacePool(1, 1)
        $pool.Open()
        try {
            $shell = [PowerShell]::Create()
            $shell.RunspacePool = $pool
            # A runspace that writes to the error stream and returns nothing is the
            # shape the collector must still treat as a failure.
            $null = $shell.AddScript('Write-Error "the model returned invalid JSON" -ErrorAction Continue')
            $async = $shell.BeginInvoke()
            $output = @($shell.EndInvoke($async))
            $records = @($shell.Streams.Error)
            $shell.Dispose()

            $output.Count | Should -Be 0
            $records.Count | Should -BeGreaterThan 0
            @($records | ForEach-Object { ([string]$_).Trim() } |
                Where-Object { $_ }) | Should -Contain "the model returned invalid JSON"
        }
        finally { $pool.Dispose() }
    }

    It "records that a caught failure leaves the runspace marked as having errored" {
        # This is the PowerShell behaviour the collector must not trust: the script
        # below handles its own failure and returns a result, yet HadErrors stays set.
        $pool = [RunspaceFactory]::CreateRunspacePool(1, 1)
        $pool.Open()
        try {
            $shell = [PowerShell]::Create()
            $shell.RunspacePool = $pool
            $null = $shell.AddScript(
                'try { Write-Error "first attempt failed" -ErrorAction Continue } catch { }; "recovered"')
            $async = $shell.BeginInvoke()
            $output = @($shell.EndInvoke($async))
            $hadErrors = $shell.HadErrors
            $shell.Dispose()

            $output[-1] | Should -Be "recovered"
            $hadErrors | Should -BeTrue
        }
        finally { $pool.Dispose() }
    }
}

Describe "A manifest is held to the version the resolver already pinned" {
    # Reads and compares JSON and XML and nothing else: no provider, no network,
    # no restore. Build 972914 is the case, and it costs milliseconds to hold.
    function script:New-CsprojChange {
        param([Parameter(Mandatory)][string]$Version, [string]$Package = "MSTest")
        return [pscustomobject]@{
            path = "automation/Widget.Automation.Api/Widget.Automation.Api.csproj"
            operation = "create"
            content = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="$Package" Version="$Version" />
  </ItemGroup>
</Project>
"@
        }
    }

    function script:New-PinnedToolchainLock {
        param([Parameter(Mandatory)][string]$Path)
        # The lock as the resolver writes it: the version it chose, and beside it
        # the range it was asked to choose from. Build 972914's generator copied
        # the second field into the manifest.
        [ordered]@{
            runId = "run-pinned"
            stageId = "toolchain-resolution"
            toolchains = @([ordered]@{
                id = "nuget-mstest-4"
                ecosystem = "nuget"
                recipe = "nuget-packages-lock"
                packages = @([ordered]@{
                    key = "mstest"
                    name = "MSTest"
                    version = "4.4.0"
                    scope = "runtime"
                    requested = "[4.2.3,5.0.0)"
                })
            })
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
        return $Path
    }

    function script:Get-ManifestFindings {
        param([Parameter(Mandatory)][object]$Change, [string]$LockPath = "")
        return @(& (Join-Path $script:Root "scripts/Test-PlannedManifest.ps1") `
            -Changes @($Change) -Materializations @() -ToolchainLockPath $LockPath)
    }

    It "names the pinned version when the manifest carries the range it was resolved from" {
        $lock = New-PinnedToolchainLock -Path (Join-Path $TestDrive "pinned-lock.json")
        $findings = @(Get-ManifestFindings -Change (New-CsprojChange -Version "[4.2.3,5.0.0)") -LockPath $lock)

        @($findings).Count | Should -Be 1
        # The agent is told the number, not asked to find it: the choice was
        # made once, by the resolver, and repeating it is how they diverge.
        $findings[0] | Should -Match "asks for MSTest at '\[4\.2\.3,5\.0\.0\)'"
        $findings[0] | Should -Match "pins MSTest at 4\.4\.0"
        $findings[0] | Should -Match "nuget-mstest-4"
    }

    It "accepts the manifest once it names the pinned version" {
        $lock = New-PinnedToolchainLock -Path (Join-Path $TestDrive "accepted-lock.json")
        @(Get-ManifestFindings -Change (New-CsprojChange -Version "4.4.0") -LockPath $lock).Count |
            Should -Be 0
    }

    It "refuses an exact version that is not the pinned one" {
        # 4.2.3 is exact, is inside the requested range, and is not what the
        # resolver chose. The lock will name 4.4.0 and the restore would fail on
        # a manifest the lock does not match.
        $lock = New-PinnedToolchainLock -Path (Join-Path $TestDrive "wrong-lock.json")
        $findings = @(Get-ManifestFindings -Change (New-CsprojChange -Version "4.2.3") -LockPath $lock)

        @($findings).Count | Should -Be 1
        $findings[0] | Should -Match "asks for MSTest at '4\.2\.3'"
        $findings[0] | Should -Match "pins MSTest at 4\.4\.0"
    }

    It "still refuses a range when there is no lock to quote" {
        # The materialiser refuses any specifier it cannot pin, lock or no lock,
        # so the generator hears about it here either way.
        $findings = @(Get-ManifestFindings -Change (New-CsprojChange -Version "[4.2.3,5.0.0)"))

        @($findings).Count | Should -Be 1
        $findings[0] | Should -Match "cannot be materialised"
    }

    It "leaves a package the lock does not mention to its own exact version" {
        $lock = New-PinnedToolchainLock -Path (Join-Path $TestDrive "other-lock.json")
        @(Get-ManifestFindings -Change (New-CsprojChange -Version "3.1.0" -Package "Widget.Testing") `
            -LockPath $lock).Count | Should -Be 0
    }

    It "reads an unreadable lock as no lock rather than refusing a manifest that is right" {
        $lockPath = Join-Path $TestDrive "broken-lock.json"
        Set-Content -LiteralPath $lockPath -Value "{ this is not json" -Encoding utf8
        @(Get-ManifestFindings -Change (New-CsprojChange -Version "4.4.0") -LockPath $lockPath).Count |
            Should -Be 0
    }
}

Describe "Plans the materialiser cannot resolve" {
    It "sends a version range back to the batch that wrote it, not to stage 11" {
        # Build 972914 got further than any run before it and blocked at stage 11
        # of 13 on 'MSTest@[4.2.3,5.0.0)'. The check that would have caught it ran
        # only for an answer carrying both changes and materialisations, which was
        # true of the single generator build 466 had and of nothing since:
        # generation is split across batches that write changes and a planner that
        # writes materialisations, so the check had quietly stopped running.
        $config = Get-TestConfig
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/version-range-batch-provider.mjs"
        $config.runtime.agent_schema_retries = 1
        $outputPath = Join-Path $TestDrive "version-range/bootstrap-change-generation/change-set-batch-01.json"
        New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null

        $artifact = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "bootstrap-change-generator-batch-01" `
            -StageId "bootstrap-change-generation" `
            -RunId "run-version-range" `
            -PromptPath (Join-Path $script:Root "prompts/sdlc/bootstrap-plan-generator.md") `
            -ContextPaths @() `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/actions/change-set-batch.schema.json") `
            -Config $config `
            -RepositoryRoot $script:Root

        # The batch answers with changes and no materialisations, which is the
        # shape that used to skip the check entirely.
        (Get-QaFoundryPropertyNames -InputObject $artifact) -contains "materializations" |
            Should -BeFalse
        [string]$artifact.changes[0].content | Should -Match 'Version="4\.2\.3"'
        [string]$artifact.changes[0].content | Should -Not -Match '\[4\.2\.3,5\.0\.0\)'
        $feedback = Get-Content -Path "$outputPath.attempt-2.request.md" -Raw
        $feedback | Should -Match "asks for MSTest at '\[4\.2\.3,5\.0\.0\)'"
        $feedback | Should -Match "The resolver pins one version"
    }

    It "sends a workspace plan back to the generator while it still has an attempt left" {
        # The materialiser is the far end of the relay: by the time it refuses, the
        # generator that could fix the plan has been gone for twenty minutes and the
        # run ends. Rejecting the same plan at the moment it arrives costs one retry.
        $config = Get-TestConfig
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/workspace-plan-provider.mjs"
        $config.runtime.agent_schema_retries = 1
        $outputPath = Join-Path $TestDrive "workspace-plan/bootstrap-change-generation/change-set-plan.json"
        New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null

        $artifact = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "bootstrap-change-generator" `
            -StageId "bootstrap-change-generation" `
            -RunId "run-workspace-plan" `
            -PromptPath (Join-Path $script:Root "prompts/sdlc/bootstrap-plan-generator.md") `
            -ContextPaths @() `
            -OutputPath $outputPath `
            -SchemaPath (Join-Path $script:Root "schemas/actions/change-set-plan.schema.json") `
            -Config $config `
            -RepositoryRoot $script:Root

        $manifestChange = @($artifact.changes | Where-Object path -eq "automation/package.json")[0]
        ($manifestChange.content | ConvertFrom-Json -Depth 20).PSObject.Properties.Name |
            Should -Not -Contain "workspaces"
        @($artifact.changes).Count | Should -Be 1
        $feedback = Get-Content -Path "$outputPath.attempt-2.request.md" -Raw
        $feedback | Should -Match "declares workspaces"
        $feedback | Should -Match "The npm-package-lock recipe cannot materialise that"
    }

    It "gives up on the plan when the generator keeps returning a workspace" {
        $config = Get-TestConfig
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/workspace-plan-provider.mjs"
        $config.runtime.agent_schema_retries = 0
        $outputPath = Join-Path $TestDrive "workspace-final/bootstrap-change-generation/change-set-plan.json"
        New-Item -ItemType Directory -Path (Split-Path $outputPath -Parent) -Force | Out-Null

        {
            & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
                -AgentId "bootstrap-change-generator" `
                -StageId "bootstrap-change-generation" `
                -RunId "run-workspace-final" `
                -PromptPath (Join-Path $script:Root "prompts/sdlc/bootstrap-plan-generator.md") `
                -ContextPaths @() `
                -OutputPath $outputPath `
                -SchemaPath (Join-Path $script:Root "schemas/actions/change-set-plan.schema.json") `
                -Config $config `
                -RepositoryRoot $script:Root
        } | Should -Throw "*The npm-package-lock recipe cannot materialise that*"
    }

    It "refuses a workspace manifest that reached the materialiser anyway" {
        $runId = "run-materialise-workspaces"
        $runConfigPath = Join-Path $TestDrive "workspaces-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "workspaces-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain `
            -ManifestOverride @{ workspaces = @("projects/*") }
        $argsDump = Join-Path $TestDrive "workspaces-args.txt"
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "workspaces-stub") -ArgsDumpPath $argsDump

        $run = Invoke-Materialisation -Name "workspaces" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "revision_required"
        $run.Result.failureKind | Should -Be 'artifact_invalid'
        Test-Path $run.OutputPath | Should -BeFalse
        Test-Path $argsDump | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) |
            Should -Match "declares workspaces"
        (Get-Content -LiteralPath $run.EvidencePath -Raw) |
            Should -Match "The npm-package-lock recipe cannot materialise that"
    }

    It "refuses a plan that authors a manifest and asks for nothing to be resolved" {
        # The empty case is the one that used to pass. The plan carries a manifest
        # and no lock, the materialiser had nothing to refuse because it only ever
        # judged the materialisations it was given, and the build downstream
        # installed whatever the feed offered that day. Coverage is derived from
        # the approved blueprint instead, so an absent materialisation is now
        # missing rather than merely unrequested.
        $runId = "run-materialise-nothing"
        $runConfigPath = Join-Path $TestDrive "nothing-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "nothing-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain -NoMaterializations
        $argsDump = Join-Path $TestDrive "nothing-args.txt"
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "nothing-stub") -ArgsDumpPath $argsDump

        $run = Invoke-Materialisation -Name "nothing" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        Test-Path $argsDump | Should -BeFalse
        $evidence = Get-Content -LiteralPath $run.EvidencePath -Raw
        $evidence | Should -Match "resolves no dependencies for automation"
        $evidence | Should -Match "chosen at build time by whatever the feed offers"
    }

    It "refuses a plan whose only manifest sits outside an approved project" {
        # One manifest serves the projects nested under it, which is why a plan
        # need not name every project. A project in another part of the tree is
        # nested under nothing the plan resolves, so nothing pins it.
        $runId = "run-materialise-elsewhere"
        $runConfigPath = Join-Path $TestDrive "elsewhere-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $stageRoot = Join-Path $TestDrive "elsewhere-blueprint"
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        $decision = New-ToolchainDecision
        $blueprintPath = New-ApprovedBlueprint -Path (Join-Path $stageRoot "blueprint.json") `
            -RunId $runId -Projects @(
                @{ path = "automation"; decision = $decision },
                @{ path = "services/api/tests"; decision = $decision }
            )
        $planPath = Join-Path $TestDrive "elsewhere-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $argsDump = Join-Path $TestDrive "elsewhere-args.txt"
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "elsewhere-stub") -ArgsDumpPath $argsDump

        $run = Invoke-Materialisation -Name "elsewhere" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub `
            -BlueprintPath $blueprintPath

        $run.Result.status | Should -Be "blocked"
        Test-Path $run.OutputPath | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) |
            Should -Match "resolves no dependencies for services/api/tests"
    }

    It "refuses a manifest that asks for the locked package under another spelling" {
        # npm serves the name as it was published, so "TypeScript" and
        # "typescript" are two packages and only one of them was resolved. The
        # comparison used to be PowerShell's -eq, which folds case for every
        # ecosystem alike and would have installed a package nobody locked.
        $runId = "run-materialise-case"
        $runConfigPath = Join-Path $TestDrive "case-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $devDependencies = [ordered]@{}
        foreach ($package in @($toolchain.packages)) {
            $name = [string]$package.name
            if ($name -ceq "typescript") { $name = "TypeScript" }
            $devDependencies[$name] = [string]$package.version
        }
        @($devDependencies.Keys) | Should -Contain "TypeScript"
        $planPath = Join-Path $TestDrive "case-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain `
            -ManifestOverride @{ devDependencies = $devDependencies }
        $argsDump = Join-Path $TestDrive "case-args.txt"
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "case-stub") -ArgsDumpPath $argsDump

        $run = Invoke-Materialisation -Name "case" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "revision_required"
        $run.Result.failureKind | Should -Be 'artifact_invalid'
        Test-Path $argsDump | Should -BeFalse
        (Get-Content -LiteralPath $run.EvidencePath -Raw) |
            Should -Match "does not match the locked toolchain"
    }

    It "refuses a child package manifest beneath the manifest it materialises" {
        # A second manifest under the same tree is a workspace whether or not the
        # root manifest admits it, because npm resolves it as its own package.
        $runId = "run-materialise-child"
        $runConfigPath = Join-Path $TestDrive "child-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "child-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain -ExtraChanges @([ordered]@{
            operation = "create"
            path = "automation/projects/ui/package.json"
            expectedSha256 = ""
            content = '{"name":"ui","version":"0.0.0"}'
            reason = "Give the UI project its own package."
            sourceRefs = @("work-item:42")
        })
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "child-stub")

        $run = Invoke-Materialisation -Name "child" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "blocked"
        (Get-Content -LiteralPath $run.EvidencePath -Raw) |
            Should -Match "automation/projects/ui/package.json"
    }

    It "refuses a manifest that depends on a package by local path" {
        $runId = "run-materialise-filedep"
        $runConfigPath = Join-Path $TestDrive "filedep-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "filedep-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain `
            -ManifestOverride @{ dependencies = [ordered]@{ "shared-fixtures" = "file:../shared" } }
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "filedep-stub")

        $run = Invoke-Materialisation -Name "filedep" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "revision_required"
        $run.Result.failureKind | Should -Be 'artifact_invalid'
        (Get-Content -LiteralPath $run.EvidencePath -Raw) | Should -Match "file:\.\./shared"
    }

    It "accepts the single-package manifest the rule asks for" {
        $runId = "run-materialise-single"
        $runConfigPath = Join-Path $TestDrive "single-run-configuration.json"
        $toolchain = New-ApprovedRunConfiguration -Path $runConfigPath -RunId $runId
        $planPath = Join-Path $TestDrive "single-plan.json"
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain
        $lockFixture = Join-Path $TestDrive "single-lock.json"
        New-ApprovedLock -Toolchain $toolchain | Set-Content -LiteralPath $lockFixture -Encoding utf8
        $stub = New-NpmStub -Directory (Join-Path $TestDrive "single-stub") -LockFixturePath $lockFixture

        $run = Invoke-Materialisation -Name "single" -PlanPath $planPath `
            -RunConfigurationPath $runConfigPath -RunId $runId -NpmCommand $stub

        $run.Result.status | Should -Be "completed"
    }
}

Describe "A refused materialisation is a result, not a crash" {
    It "requests correction of the manifest instead of reading files it never produced" {
        # Build 466 reached this stage for the first time. The materialiser declined
        # the plan for a stated reason, and the stage crashed reading the produced
        # files a refusal does not have, so the log said "The property 'produced'
        # cannot be found on this object" and the reason was lost.
        $runId = "run-refused-materialisation"
        $runRoot = Join-Path $TestDrive "refusal-run"
        $repository = Join-Path $TestDrive "refusal-repository"
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $runRoot "context") -Force | Out-Null
        $toolchain = New-ApprovedRunConfiguration `
            -Path (Join-Path $runRoot "context/run-configuration.json") -RunId $runId
        $planPath = Join-Path $runRoot "bootstrap-change-generation/change-set-plan.json"
        New-Item -ItemType Directory -Path (Split-Path $planPath -Parent) -Force | Out-Null
        New-Plan -Path $planPath -RunId $runId -Toolchain $toolchain `
            -ManifestOverride @{ workspaces = @("projects/*") }
        $blueprintPath = Join-Path $runRoot "architecture/automation-blueprint.json"
        New-Item -ItemType Directory -Path (Split-Path $blueprintPath -Parent) -Force | Out-Null
        New-ApprovedBlueprint -Path $blueprintPath -RunId $runId | Out-Null
        # The refusal this test is about happens while reading the manifest, which
        # is well past the checks the materialiser runs first. Without the lock the
        # resolver stage pins, the run would stop on the missing lock instead and
        # prove nothing about how a refusal is reported.
        New-ToolchainLock -BlueprintPath $blueprintPath `
            -Path (Join-Path $runRoot "context/toolchain-lock.json") | Out-Null

        $state = [pscustomobject]@{
            stages = @(
                [pscustomobject]@{
                    id = "bootstrap-change-generation"
                    attempts = @([pscustomobject]@{
                        status = "completed"
                        artifacts = @([pscustomobject]@{
                            name = "change-set-plan.json"
                            relativePath = "bootstrap-change-generation/change-set-plan.json"
                            sha256 = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant()
                        })
                    })
                },
                [pscustomobject]@{
                    id = "architecture"
                    attempts = @([pscustomobject]@{
                        status = "completed"
                        artifacts = @([pscustomobject]@{
                            name = "automation-blueprint.json"
                            relativePath = "architecture/automation-blueprint.json"
                            sha256 = (Get-FileHash -LiteralPath $blueprintPath -Algorithm SHA256).Hash.ToLowerInvariant()
                        })
                    })
                }
            )
        }
        $state | ConvertTo-Json -Depth 100 |
            Set-Content -LiteralPath (Join-Path $runRoot "workflow-state.json") -Encoding utf8

        $config = Get-TestConfig
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
        $stage = @($workflow.stages | Where-Object id -eq "bootstrap-change-materialization")[0]

        $result = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage $stage -Config $config -Policy $policy `
            -RunRoot $runRoot -RepositoryRoot $repository -RunId $runId -Iteration 1

        $result.Status | Should -Be "revision_required"
        @($result.Artifacts | ForEach-Object { [string]$_.name }) |
            Should -Contain "resolver-evidence.json"
        $evidence = Get-Content -LiteralPath (
            Join-Path $result.ArtifactDirectory "resolver-evidence.json") -Raw
        $evidence | Should -Match "declares workspaces"
        $evidence | Should -Match "The npm-package-lock recipe cannot materialise that"
    }

    It "lets a rehearsal that refused before reading the blueprint record the refusal" {
        # A refusal can happen before the blueprint is opened, so the record it
        # writes has no digest to carry. Holding a rehearsed refusal to the shape
        # of a rehearsal that finished turns the controlled refusal - the thing
        # the stage is supposed to produce - into a validation failure instead,
        # and the run reports a crash where it should report a reason.
        $document = [ordered]@{
            runId = "run-blocked-rehearsal"
            stageId = "bootstrap-change-materialization"
            status = "blocked"
            dryRun = $true
            blueprintSha256 = ""
            materialisations = @()
            checks = @()
            findings = @("The blueprint names an ecosystem this installation cannot resolve.")
        }
        $path = Join-Path $TestDrive "blocked-rehearsal-evidence.json"
        $document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding utf8

        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $path `
                -SchemaPath (Join-Path $script:Root "schemas/runtime/resolver-evidence.schema.json") `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Not -Throw
    }

    It "still requires a rehearsal that completed to say what it read" {
        # The relaxation above is for refusals only. A rehearsal that reports it
        # completed did read the blueprint, and a record that completed without
        # naming one describes nothing a later reader could check.
        $document = [ordered]@{
            runId = "run-completed-rehearsal"
            stageId = "bootstrap-change-materialization"
            status = "completed"
            dryRun = $true
            blueprintSha256 = ""
            materialisations = @()
            checks = @()
            findings = @()
        }
        $path = Join-Path $TestDrive "completed-rehearsal-evidence.json"
        $document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $path -Encoding utf8

        {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath $path `
                -SchemaPath (Join-Path $script:Root "schemas/runtime/resolver-evidence.schema.json") `
                -SchemaRoot (Join-Path $script:Root "schemas")
        } | Should -Throw
    }
}

Describe "The change set is generated in assignments the model can actually finish" {
    BeforeAll {

        function script:Invoke-BatchingStage {
            param(
                [Parameter(Mandatory)][string]$RunRoot,
                [Parameter(Mandatory)][string]$Repository,
                [Parameter(Mandatory)][string]$RunId,
                [int]$Iteration = 1,
                [switch]$Reuse
            )
            $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
            $stage = @($workflow.stages | Where-Object id -eq "bootstrap-change-generation")[0]
            return & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
                -Stage $stage `
                -Config (Get-TestConfig) `
                -Policy (Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root) `
                -RunRoot $RunRoot `
                -RepositoryRoot $Repository `
                -RunId $RunId `
                -Iteration $Iteration `
                -ReuseExistingArtifacts:$Reuse
        }

        function script:New-BatchReview {
            param(
                [Parameter(Mandatory)][string]$RunRoot,
                [Parameter(Mandatory)][string]$AgentId,
                [Parameter(Mandatory)][string]$Scope,
                [AllowEmptyCollection()][string[]]$Paths = @()
            )
            $directory = Join-Path $RunRoot "bootstrap-change-review"
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            $review = [ordered]@{
                agentId = $AgentId; stageId = "bootstrap-change-review"; runId = "run-batched-generation"
                status = "completed"; summary = "The imports do not match the helper."
                evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
                decision = "revision_required"
                findings = @(); requiredChanges = @("Align the helper with its callers.")
                confidence = 0.9
                repairScope = $Scope
            }
            if ($Scope -eq "targeted") {
                $review["repairTargets"] = @([ordered]@{
                    paths = @($Paths)
                    instruction = "Export the name the specs already import."
                })
            }
            $review | ConvertTo-Json -Depth 40 |
                Set-Content -LiteralPath (Join-Path $directory "$AgentId.json") -Encoding utf8
        }
    }

    BeforeEach {
        $script:BatchRunId = "run-batched-generation"
        $script:BatchRunRoot = Join-Path $TestDrive ("batch-run-" + [Guid]::NewGuid().ToString("N"))
        $script:BatchRepository = Join-Path $TestDrive ("batch-repo-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $script:BatchRepository -Force | Out-Null
        New-BatchingWorkflowState -RunRoot $script:BatchRunRoot -RunId $script:BatchRunId `
            -Workflow (Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root)
    }

    It "delivers one plan holding every approved file, written by several calls" {
        # Build 475 spent five relay legs and 170 minutes on a single call that
        # could never close its JSON, because the bodies of 47 files do not fit
        # in one answer. The stage now asks several times for bounded subsets.
        $result = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId

        $result.Status | Should -Be "completed"
        $planPath = Join-Path $result.ArtifactDirectory "change-set-plan.json"
        Test-Path -LiteralPath $planPath | Should -BeTrue
        $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json -Depth 100
        @($plan.changes).Count | Should -Be 13
        @($plan.changes | ForEach-Object { $_.path } | Sort-Object -Unique).Count | Should -Be 13
        $plan.changes | ForEach-Object { [string]$_.content | Should -Not -BeNullOrEmpty }

        $batchArtifacts = @($result.Artifacts |
            Where-Object { [string]$_.name -match "^change-set-batch-\d+\.json$" })
        @($batchArtifacts).Count | Should -BeGreaterThan 1
    }

    It 'keeps unrelated review narratives and the full previous change set out of batch repair requests' {
        $statePath = Join-Path $script:BatchRunRoot workflow-state.json
        $state = Get-Content $statePath -Raw | ConvertFrom-Json -Depth 100
        $narrativePath = Join-Path $script:BatchRunRoot previous-delivery.json
        Set-Content $narrativePath '{"summary":"UNRELATED_PREVIOUS_DELIVERY_SENTINEL"}'
        $state.stages += [pscustomobject]@{ id = 'old-delivery'; attempts = @(@{ status = 'completed'; artifacts = @(@{
            name = 'previous-delivery.json'; relativePath = 'previous-delivery.json'; sha256 = (Get-FileHash $narrativePath).Hash.ToLowerInvariant()
        }) }) }
        $state | ConvertTo-Json -Depth 100 | Set-Content $statePath
        $result = Invoke-BatchingStage -RunRoot $script:BatchRunRoot -Repository $script:BatchRepository -RunId $script:BatchRunId
        $result.Status | Should -Be completed
        $request = Get-Content (Join-Path $result.ArtifactDirectory change-set-batch-01.json.attempt-1.request.md) -Raw
        $request | Should -Not -Match 'UNRELATED_PREVIOUS_DELIVERY_SENTINEL|previous-delivery.json'
        $request | Should -Match 'assignment-batch-01.json'
        $request | Should -Match 'Export the behaviour the blueprint named'
    }

    It 'passes archived inventories into the restarted implementation agents and merges their revisions' {
        $statePath = Join-Path $script:BatchRunRoot workflow-state.json
        $state = Get-Content $statePath -Raw | ConvertFrom-Json -Depth 100
        $state.status = 'blocked'
        $state | ConvertTo-Json -Depth 100 | Set-Content $statePath
        @{ version = 1; hashes = @{ source = 'same'; contracts = 'same' } } | ConvertTo-Json |
            Set-Content (Join-Path $script:BatchRunRoot run-inputs.json)
        $workflow = New-BatchingResumeWorkflow (Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root)
        $null = & (Join-Path $script:Root scripts/Reset-WorkflowStage.ps1) -RunRoot $script:BatchRunRoot -Workflow $workflow -StageId implementation
        $result = & (Join-Path $script:Root scripts/Invoke-Stage.ps1) -Stage $workflow.stages[0] `
            -Config (Get-TestConfig) -Policy (Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root) `
            -RunRoot $script:BatchRunRoot -RepositoryRoot $script:BatchRepository -RunId $script:BatchRunId -Iteration 1
        $result.Status | Should -Be completed
        foreach ($name in @('framework-implementation','test-implementation')) {
            $path = Join-Path $result.ArtifactDirectory "$name.json"
            $inventory = Get-Content $path -Raw | ConvertFrom-Json -Depth 100
            $oldPrefix = if ($name -eq 'framework-implementation') { 'automation/lib/module-*' } else { 'automation/tests/case-*' }
            $expectedCount = if ($name -eq 'framework-implementation') { 8 } else { 5 }
            @($inventory.plannedFiles | Where-Object path -Like $oldPrefix).Count | Should -Be $expectedCount
            $request = Get-Content "$path.attempt-1.request.md" -Raw
            $request | Should -Match 'Recovery after downstream verification'
            $request | Should -Match 'unchanged contracts are merged'
            $request | Should -Match 'automation/lib/module-01.ts'
        }
    }

    It 'reuses source after controlled planning recovery with <ChangedCount> changed contracts' -ForEach @(
        @{ ChangedCount = 0 }, @{ ChangedCount = 1 }
    ) {
        $first = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId
        $first.Status | Should -Be 'completed'
        $oldPlan = Get-Content (Join-Path $first.ArtifactDirectory 'change-set-plan.json') -Raw | ConvertFrom-Json -Depth 100
        $statePath = Join-Path $script:BatchRunRoot 'workflow-state.json'
        $state = Get-Content $statePath -Raw | ConvertFrom-Json -Depth 100
        $state.status = 'blocked'
        $generation = $state.stages | Where-Object id -eq bootstrap-change-generation
        $generation.status = 'completed'; $generation.iteration = 1
        $generation.attempts = @(@{ iteration = 1; status = 'completed'; artifacts = @($first.Artifacts) })
        $state | ConvertTo-Json -Depth 100 | Set-Content $statePath
        @{ version = 1; hashes = @{ source = 'same'; contracts = 'same' } } | ConvertTo-Json |
            Set-Content (Join-Path $script:BatchRunRoot run-inputs.json)
        $workflow = New-BatchingResumeWorkflow (Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root)
        $null = & (Join-Path $script:Root scripts/Reset-WorkflowStage.ps1) -RunRoot $script:BatchRunRoot -Workflow $workflow -StageId implementation
        . (Join-Path $script:Root scripts/RecoveryReuse.ps1)
        $archive = Get-QaFoundryRecoveryArchive -RunRoot $script:BatchRunRoot -RunId $script:BatchRunId -StageId implementation
        Copy-Item (Join-Path $archive.path implementation) (Join-Path $script:BatchRunRoot implementation) -Recurse
        $state = Get-Content $statePath -Raw | ConvertFrom-Json -Depth 100
        $implementation = $state.stages | Where-Object id -eq implementation
        $implementation.status = 'completed'; $implementation.iteration = 1
        $implementation.attempts = @($archive.state.stages | Where-Object id -eq implementation)[0].attempts
        $inventoryRecord = @($implementation.attempts[0].artifacts | Where-Object name -eq framework-implementation.json)[0]
        $inventoryPath = Join-Path $script:BatchRunRoot $inventoryRecord.relativePath
        $inventory = Get-Content $inventoryPath -Raw | ConvertFrom-Json -Depth 100
        $changedPath = $inventory.plannedFiles[0].path
        if ($ChangedCount -gt 0) {
            $inventory.plannedFiles[0].contentContract += ' Add meaningful local checks.'
            $inventory | ConvertTo-Json -Depth 100 | Set-Content $inventoryPath
            $inventoryRecord.sha256 = (Get-FileHash $inventoryPath).Hash.ToLowerInvariant()
        }
        $state | ConvertTo-Json -Depth 100 | Set-Content $statePath
        $second = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId
        $second.Status | Should -Be 'completed'
        $plan = Get-Content (Join-Path $second.ArtifactDirectory change-set-plan.json) -Raw | ConvertFrom-Json -Depth 100
        $plan.changes.Count | Should -Be 13
        $plan.details.carriedForward.fileCount | Should -Be (13 - $ChangedCount)
        @($second.Artifacts | Where-Object name -Match '^change-set-batch-\d+\.json$').Count | Should -Be $ChangedCount
        foreach ($change in @($plan.changes | Where-Object { $ChangedCount -eq 0 -or $_.path -ne $changedPath })) {
            $change.content | Should -BeExactly ($oldPlan.changes | Where-Object path -eq $change.path).content
        }
    }

    It 'reuses complete batch bodies after a legacy output-budget deferral without another provider call' {
        $first = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId
        $output = Join-Path $first.ArtifactDirectory 'change-set-batch-01.json'
        $artifact = Get-Content $output -Raw | ConvertFrom-Json -Depth 100
        $artifact | Add-Member -NotePropertyName deferrals -NotePropertyValue @() -Force
        $artifact | ConvertTo-Json -Depth 100 | Set-Content $output
        $originalHash = (Get-FileHash $output).Hash
        $request = "$output.attempt-1.request.md"
        $originalRequestTime = (Get-Item $request).LastWriteTimeUtc
        $coverage = Get-Content "$output.coverage.json" -Raw | ConvertFrom-Json -Depth 40
        $coverage.status = 'deferred'
        $coverage.deferralsSource = 'run'
        $coverage.deferrals = @(@{ item = 'Everything again'; reason = 'Reduced output budget'; kind = 'output_budget' })
        $coverage | ConvertTo-Json -Depth 40 | Set-Content "$output.coverage.json"

        $second = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId -Reuse
        $second.Status | Should -Be 'completed'
        (Get-FileHash $output).Hash | Should -Be $originalHash
        (Get-Item $request).LastWriteTimeUtc | Should -Be $originalRequestTime
        (Get-Content "$output.coverage.json" -Raw | ConvertFrom-Json).status | Should -Be 'covered'
    }

    It "keeps the answered batches out of the requests that follow them" {
        # The point of splitting is a smaller call. If each batch carried the
        # previous batches as context, the requests would grow exactly as fast
        # as the answers shrank and nothing would have been gained.
        #
        # Provider accounting is kept out for the same reason and one more: what
        # a call cost is a fact about the run, not evidence about the product,
        # and the ledger that exists to measure prompt growth would otherwise
        # become a cause of it. The usage sidecar is planted here because an
        # interrupted run can leave one behind after the call that wrote it.
        #
        # A coverage record is the third of the same kind: it states whether one
        # call answered everything it was asked for, so a resumed run can refuse
        # a half-finished artifact. Carried forward it would put the record of
        # what every earlier stage deferred into every later request.
        $strayUsage = Join-Path $script:BatchRunRoot `
            "bootstrap-change-generation/change-set-batch-01.json.attempt-1.request.md.usage.json"
        New-Item -ItemType Directory -Path (Split-Path $strayUsage -Parent) -Force | Out-Null
        Set-Content -LiteralPath $strayUsage -Encoding utf8 `
            -Value '{"input_tokens":1234,"output_tokens":56}'
        $strayCoverage = Join-Path $script:BatchRunRoot `
            "bootstrap-change-generation/change-set-batch-01.json.coverage.json"
        Set-Content -LiteralPath $strayCoverage -Encoding utf8 `
            -Value '{"complete":true,"requested":4,"answered":4,"deferred":[]}'

        $result = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId
        $result.Status | Should -Be "completed"

        $lastRequest = Join-Path $result.ArtifactDirectory `
            "change-set-batch-03.json.attempt-1.request.md"
        Test-Path -LiteralPath $lastRequest | Should -BeTrue
        $request = Get-Content -LiteralPath $lastRequest -Raw
        $request | Should -Not -Match "change-set-batch-01\.json"
        $request | Should -Not -Match "assignment-batch-01\.json"
        $request | Should -Match "assignment-batch-03\.json"
        $request | Should -Not -Match "provider-metadata\.json"
        $request | Should -Not -Match "usage\.json"
        $request | Should -Not -Match "coverage\.json"
    }

    It "tells each call exactly which files are its own and which belong to others" {
        $result = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId
        $result.Status | Should -Be "completed"

        $assignment = Get-Content -LiteralPath (
            Join-Path $result.ArtifactDirectory "assignment-batch-01.json") -Raw |
            ConvertFrom-Json -Depth 100
        @($assignment.assignedPaths).Count | Should -Be 1
        @($assignment.allApprovedPaths).Count | Should -Be 13
        $assignment.batchCount | Should -Be 13
        foreach ($path in @($assignment.assignedPaths)) {
            @($assignment.allApprovedPaths) | Should -Contain $path
        }
    }

    It "leaves the lock file to the resolver instead of asking a batch to invent it" {
        # Build 478 reached this stage, the eighth of eleven, and stopped on it.
        # The approved inventory named automation/package-lock.json, the split
        # handed it to batch five, and the generator could not author a lock
        # file without breaking the change contract, so it refused the batch and
        # the run ended blocked after ninety minutes.
        $runRoot = Join-Path $TestDrive ("batch-lock-" + [Guid]::NewGuid().ToString("N"))
        $repository = Join-Path $TestDrive ("batch-lock-repo-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        New-BatchingWorkflowState -RunRoot $runRoot -RunId $script:BatchRunId `
            -Workflow (Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root) `
            -IncludeLockFile

        $result = Invoke-BatchingStage -RunRoot $runRoot -Repository $repository `
            -RunId $script:BatchRunId
        $result.Status | Should -Be "completed"

        foreach ($assignmentPath in @(Get-ChildItem -LiteralPath $result.ArtifactDirectory `
                -Filter "assignment-batch-*.json")) {
            $assignment = Get-Content -LiteralPath $assignmentPath.FullName -Raw |
                ConvertFrom-Json -Depth 100
            @($assignment.assignedPaths) | Should -Not -Contain "automation/package-lock.json"
            @($assignment.allApprovedPaths) | Should -Not -Contain "automation/package-lock.json"
            @($assignment.resolverOwnedPaths) | Should -Contain "automation/package-lock.json"
        }

        $coverage = Get-Content -LiteralPath (
            Join-Path $result.ArtifactDirectory "approved-paths.json") -Raw |
            ConvertFrom-Json -Depth 100
        @($coverage.resolverOwnedPaths) | Should -Be @("automation/package-lock.json")
        @($coverage.generatedPaths) | Should -Not -Contain "automation/package-lock.json"

        $plan = Get-Content -LiteralPath (
            Join-Path $result.ArtifactDirectory "change-set-plan.json") -Raw |
            ConvertFrom-Json -Depth 100
        @($plan.changes | ForEach-Object { [string]$_.path }) |
            Should -Not -Contain "automation/package-lock.json"
        @($plan.changes | ForEach-Object { [string]$_.path }) |
            Should -Contain "automation/package.json"
        @($plan.changes).Count | Should -Be 14
        @($plan.materializations | ForEach-Object { [string]$_.lockPath }) |
            Should -Be @("automation/package-lock.json")
    }

    It "writes a file before the files that import it, not before the files that follow it alphabetically" {
        # Build 496 sorted by path, so the specs landed in batches 01-04 and the
        # helpers they import in 05-07. Every spec was therefore written against
        # a helper that did not exist yet, and all three reviewers called the
        # mismatched imports critical.
        $directory = Join-Path $TestDrive ("slice-layers-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $inventoryPath = Join-Path $directory "inventory.json"
        [ordered]@{
            agentId = "impl"; stageId = "implementation"; runId = "run-slice"
            status = "completed"; summary = "Four files."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            commandsProposed = @()
            plannedFiles = @(
                [ordered]@{ path = "automation/aaa.spec.ts"; operation = "create"
                    purpose = "p"; contentContract = "c"
                    dependsOn = @("automation/zzz-helper.ts") },
                [ordered]@{ path = "automation/bbb.spec.ts"; operation = "create"
                    purpose = "p"; contentContract = "c"
                    dependsOn = @("automation/zzz-helper.ts") },
                [ordered]@{ path = "automation/zzz-helper.ts"; operation = "create"
                    purpose = "p"; contentContract = "c" }
            )
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $inventoryPath -Encoding utf8

        $split = & (Join-Path $script:Root "scripts/New-ChangeSetBatches.ps1") `
            -InventoryPaths @($inventoryPath) -MaxFilesPerBatch 2
        [int]$split.layerCount | Should -Be 2

        $helperBatch = @($split.batches | Where-Object {
            @($_.files | ForEach-Object { [string]$_.path }) -contains "automation/zzz-helper.ts"
        })[0]
        $specBatch = @($split.batches | Where-Object {
            @($_.files | ForEach-Object { [string]$_.path }) -contains "automation/aaa.spec.ts"
        })[0]
        [int]$helperBatch.layer | Should -Be 0
        [int]$specBatch.layer | Should -Be 1
        @($specBatch.dependsOnBatchIds) | Should -Contain ([string]$helperBatch.batchId)
        @($helperBatch.dependsOnBatchIds).Count | Should -Be 0
    }

    It "keeps two files that import each other in one call" {
        # Split across two calls of the same layer they would run at the same
        # time, each writing against a guess at the other, which is the failure
        # the layering exists to prevent.
        $directory = Join-Path $TestDrive ("slice-cycle-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $inventoryPath = Join-Path $directory "inventory.json"
        [ordered]@{
            agentId = "impl"; stageId = "implementation"; runId = "run-cycle"
            status = "completed"; summary = "A cycle."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            commandsProposed = @()
            plannedFiles = @(
                [ordered]@{ path = "automation/x.ts"; operation = "create"; purpose = "p"
                    contentContract = "c"; dependsOn = @("automation/y.ts") },
                [ordered]@{ path = "automation/y.ts"; operation = "create"; purpose = "p"
                    contentContract = "c"; dependsOn = @("automation/x.ts") }
            )
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $inventoryPath -Encoding utf8

        $split = & (Join-Path $script:Root "scripts/New-ChangeSetBatches.ps1") `
            -InventoryPaths @($inventoryPath) -MaxFilesPerBatch 1
        @($split.batches).Count | Should -Be 1
        @($split.batches[0].files | ForEach-Object { [string]$_.path }) |
            Should -Be @("automation/x.ts", "automation/y.ts")
    }

    It "refuses one file that two inventories specify differently" {
        # The last inventory used to win in silence. The file was then written
        # to one contract while the other inventory, and the review that
        # approved it, expected the other, and nothing downstream compared them.
        $directory = Join-Path $TestDrive ("slice-clash-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $frameworkPath = Join-Path $directory "framework.json"
        $testPath = Join-Path $directory "test.json"
        [ordered]@{
            agentId = "impl"; stageId = "implementation"; runId = "run-clash"
            status = "completed"; summary = "One file."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            commandsProposed = @()
            plannedFiles = @(
                [ordered]@{ path = "automation/shared.ts"; operation = "create"; purpose = "p"
                    contentContract = "Export a page object." }
            )
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $frameworkPath -Encoding utf8
        [ordered]@{
            agentId = "impl"; stageId = "implementation"; runId = "run-clash"
            status = "completed"; summary = "The same file, said otherwise."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            commandsProposed = @()
            plannedFiles = @(
                [ordered]@{ path = "automation/shared.ts"; operation = "create"; purpose = "p"
                    contentContract = "Export a fixture factory." }
            )
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $testPath -Encoding utf8

        { & (Join-Path $script:Root "scripts/New-ChangeSetBatches.ps1") `
            -InventoryPaths @($frameworkPath, $testPath) -MaxFilesPerBatch 4 } |
            Should -Throw -ExpectedMessage "*automation/shared.ts*do not agree*"
    }

    It "carries one file that two inventories specify identically" {
        # Naming a file twice is legitimate when the run carried it forward on
        # purpose, so the refusal above must not fire on agreement.
        $directory = Join-Path $TestDrive ("slice-agree-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $frameworkPath = Join-Path $directory "framework.json"
        $testPath = Join-Path $directory "test.json"
        foreach ($target in @($frameworkPath, $testPath)) {
            [ordered]@{
                agentId = "impl"; stageId = "implementation"; runId = "run-agree"
                status = "completed"; summary = "One file."
                evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
                commandsProposed = @()
                plannedFiles = @(
                    [ordered]@{ path = "automation/shared.ts"; operation = "create"; purpose = "p"
                        contentContract = "Export a page object." }
                )
            } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $target -Encoding utf8
        }

        $split = & (Join-Path $script:Root "scripts/New-ChangeSetBatches.ps1") `
            -InventoryPaths @($frameworkPath, $testPath) -MaxFilesPerBatch 4
        @($split.batches).Count | Should -Be 1
        @($split.batches[0].files | ForEach-Object { [string]$_.path }) |
            Should -Be @("automation/shared.ts")
    }

    It "refuses a dependency on a file the inventory never plans" {
        # A mistyped dependency does not merely reorder the work. The edge
        # disappears, so the file that imports it is written without ever being
        # shown the provider it builds on and invents the interface instead, and
        # nothing downstream reads imports.
        $directory = Join-Path $TestDrive ("slice-dangling-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $inventoryPath = Join-Path $directory "inventory.json"
        [ordered]@{
            agentId = "impl"; stageId = "implementation"; runId = "run-dangling"
            status = "completed"; summary = "Two files, one typo."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            commandsProposed = @()
            plannedFiles = @(
                [ordered]@{ path = "automation/persona-provider.ts"; operation = "create"
                    purpose = "p"; contentContract = "c" },
                [ordered]@{ path = "automation/case.spec.ts"; operation = "create"
                    purpose = "p"; contentContract = "c"
                    dependsOn = @("automation/persona-provider.tsx") }
            )
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $inventoryPath -Encoding utf8

        { & (Join-Path $script:Root "scripts/New-ChangeSetBatches.ps1") `
            -InventoryPaths @($inventoryPath) -MaxFilesPerBatch 4 } |
            Should -Throw -ExpectedMessage "*automation/case.spec.ts depends on automation/persona-provider.tsx*"
    }

    It "batches only the files a repair names and refuses a name nobody approved" {
        $directory = Join-Path $TestDrive ("slice-repair-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $inventoryPath = Join-Path $directory "inventory.json"
        [ordered]@{
            agentId = "impl"; stageId = "implementation"; runId = "run-repair"
            status = "completed"; summary = "Three files."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            commandsProposed = @()
            plannedFiles = @(
                [ordered]@{ path = "automation/a.ts"; operation = "create"; purpose = "p"; contentContract = "c" },
                [ordered]@{ path = "automation/b.ts"; operation = "create"; purpose = "p"; contentContract = "c" },
                [ordered]@{ path = "automation/c.ts"; operation = "create"; purpose = "p"; contentContract = "c" }
            )
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $inventoryPath -Encoding utf8

        $split = & (Join-Path $script:Root "scripts/New-ChangeSetBatches.ps1") `
            -InventoryPaths @($inventoryPath) -RegeneratePaths @("automation/b.ts")
        @($split.paths).Count | Should -Be 3
        @($split.regeneratedPaths) | Should -Be @("automation/b.ts")
        @($split.batches).Count | Should -Be 1

        {
            & (Join-Path $script:Root "scripts/New-ChangeSetBatches.ps1") `
                -InventoryPaths @($inventoryPath) -RegeneratePaths @("automation/never-approved.ts")
        } | Should -Throw "*not in the approved inventory*"
    }

    It "carries the files a review left alone forward instead of paying to write them again" {
        # Build 496 regenerated all eight batches, 49 minutes of model time,
        # because three of the forty-seven files were wrong.
        $directory = Join-Path $TestDrive ("merge-carry-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $carriedPlanPath = Join-Path $directory "change-set-plan-previous.json"
        [ordered]@{
            agentId = "generator"; stageId = "generation"; runId = "run-carry"
            status = "completed"; summary = "Two files."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"; materializations = @()
            changes = @(
                [ordered]@{ operation = "create"; path = "automation/a.ts"; expectedSha256 = ""
                    content = "original a"; reason = "r"; sourceRefs = @() },
                [ordered]@{ operation = "create"; path = "automation/b.ts"; expectedSha256 = ""
                    content = "original b"; reason = "r"; sourceRefs = @() }
            )
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $carriedPlanPath -Encoding utf8

        $batchPath = Join-Path $directory "change-set-batch-01.json"
        [ordered]@{
            agentId = "generator"; stageId = "generation"; runId = "run-carry"
            status = "completed"; summary = "The repaired file."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"; batchId = "batch-01"
            changes = @([ordered]@{
                operation = "create"; path = "automation/b.ts"; expectedSha256 = ""
                content = "repaired b"; reason = "r"; sourceRefs = @()
            })
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $batchPath -Encoding utf8

        $outputPath = Join-Path $directory "change-set-plan.json"
        $merged = & (Join-Path $script:Root "scripts/Merge-ChangeSetBatches.ps1") `
            -BatchPaths @($batchPath) `
            -ExpectedPaths @("automation/a.ts", "automation/b.ts") `
            -OutputPath $outputPath `
            -AgentId "generator" -StageId "generation" -RunId "run-carry" `
            -CarriedPlanPath $carriedPlanPath `
            -RegeneratedPaths @("automation/b.ts")

        [string]$merged.status | Should -Be "completed"
        $plan = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 100
        @($plan.changes).Count | Should -Be 2
        [string](@($plan.changes | Where-Object path -eq "automation/a.ts")[0].content) |
            Should -Be "original a"
        [string](@($plan.changes | Where-Object path -eq "automation/b.ts")[0].content) |
            Should -Be "repaired b"
        [string]$plan.details.carriedForward.sha256 | Should -Not -BeNullOrEmpty
        [int]$plan.details.carriedForward.fileCount | Should -Be 1
    }

    It "refuses a repair batch that rewrites a file the review called correct" {
        # A file carried forward is a file a reviewer approved. A batch that
        # rewrites it anyway is discarding a judgement the run paid a review
        # cycle to obtain, and nothing downstream would notice.
        $directory = Join-Path $TestDrive ("merge-overreach-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $carriedPlanPath = Join-Path $directory "change-set-plan-previous.json"
        [ordered]@{
            agentId = "generator"; stageId = "generation"; runId = "run-overreach"
            status = "completed"; summary = "Two files."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"; materializations = @()
            changes = @(
                [ordered]@{ operation = "create"; path = "automation/a.ts"; expectedSha256 = ""
                    content = "original a"; reason = "r"; sourceRefs = @() },
                [ordered]@{ operation = "create"; path = "automation/b.ts"; expectedSha256 = ""
                    content = "original b"; reason = "r"; sourceRefs = @() }
            )
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $carriedPlanPath -Encoding utf8

        $batchPath = Join-Path $directory "change-set-batch-01.json"
        [ordered]@{
            agentId = "generator"; stageId = "generation"; runId = "run-overreach"
            status = "completed"; summary = "Both files, one of them uninvited."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"; batchId = "batch-01"
            changes = @(
                [ordered]@{ operation = "create"; path = "automation/b.ts"; expectedSha256 = ""
                    content = "repaired b"; reason = "r"; sourceRefs = @() },
                [ordered]@{ operation = "create"; path = "automation/a.ts"; expectedSha256 = ""
                    content = "rewritten a"; reason = "r"; sourceRefs = @() }
            )
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $batchPath -Encoding utf8

        {
            & (Join-Path $script:Root "scripts/Merge-ChangeSetBatches.ps1") `
                -BatchPaths @($batchPath) `
                -ExpectedPaths @("automation/a.ts", "automation/b.ts") `
                -OutputPath (Join-Path $directory "change-set-plan.json") `
                -AgentId "generator" -StageId "generation" -RunId "run-overreach" `
                -CarriedPlanPath $carriedPlanPath `
                -RegeneratedPaths @("automation/b.ts")
        } | Should -Throw "*was not asked to repair it*"
    }

    It 'keeps a targeted repair across a failed generation with no merged plan' {
        $first = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId
        $first.Status | Should -Be completed
        $original = Get-Content (Join-Path $first.ArtifactDirectory change-set-plan.json) -Raw | ConvertFrom-Json -Depth 100
        $target = [string]$original.changes[0].path
        New-BatchReview -RunRoot $script:BatchRunRoot -AgentId bootstrap-correctness-reviewer -Scope targeted -Paths @($target)
        $statePath = Join-Path $script:BatchRunRoot workflow-state.json
        $state = Get-Content $statePath -Raw | ConvertFrom-Json -Depth 100
        $generation = @($state.stages | Where-Object id -EQ bootstrap-change-generation)[0]
        $generation.attempts = @(
            [pscustomobject]@{ iteration = 1; status = 'completed'; artifacts = @($first.Artifacts) },
            [pscustomobject]@{ iteration = 2; status = 'failed'; artifacts = @() }
        )
        $state | ConvertTo-Json -Depth 100 | Set-Content $statePath
        $third = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId -Iteration 3
        $third.Status | Should -Be completed
        $assignments = @(Get-ChildItem $third.ArtifactDirectory -Filter 'assignment-batch-*.json')
        $assignments.Count | Should -Be 1
        $assignment = Get-Content $assignments[0].FullName -Raw | ConvertFrom-Json -Depth 50
        @($assignment.assignedPaths) | Should -Be @($target)
        $repaired = Get-Content (Join-Path $third.ArtifactDirectory change-set-plan.json) -Raw | ConvertFrom-Json -Depth 100
        $repaired.changes.Count | Should -Be $original.changes.Count
        foreach ($change in @($original.changes | Where-Object path -NE $target)) {
            @($repaired.changes | Where-Object path -EQ $change.path)[0].content | Should -BeExactly $change.content
        }
        # Corrupted provenance must stop, not silently trigger paid regeneration.
        Add-Content (Join-Path $first.ArtifactDirectory batch-basis.json) ' '
        { Invoke-BatchingStage -RunRoot $script:BatchRunRoot -Repository $script:BatchRepository `
            -RunId $script:BatchRunId -Iteration 5 } | Should -Throw '*changed; refusing full regeneration*'
    }

    It "repairs only the files a review named and reuses the rest of the plan it rejected" {
        # Build 496 reached the last stage, was sent back over a handful of
        # files, and spent 49 minutes regenerating all eight batches before it
        # ran out of relay legs.
        $first = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId
        $first.Status | Should -Be "completed"
        $firstPlan = Get-Content -LiteralPath (
            Join-Path $first.ArtifactDirectory "change-set-plan.json") -Raw |
            ConvertFrom-Json -Depth 100
        $target = [string]@($firstPlan.changes)[0].path
        $untouched = [string]@($firstPlan.changes)[1].path

        foreach ($reviewer in @("bootstrap-correctness-reviewer", "bootstrap-quality-reviewer")) {
            New-BatchReview -RunRoot $script:BatchRunRoot -AgentId $reviewer `
                -Scope "targeted" -Paths @($target)
        }

        $second = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId -Iteration 2
        $second.Status | Should -Be "completed"

        $assignments = @(Get-ChildItem -LiteralPath $second.ArtifactDirectory `
            -Filter "assignment-batch-*.json")
        @($assignments).Count | Should -Be 1
        $assignment = Get-Content -LiteralPath $assignments[0].FullName -Raw |
            ConvertFrom-Json -Depth 100
        @($assignment.assignedPaths) | Should -Be @($target)
        @($assignment.repairInstructions).Count | Should -BeGreaterThan 0

        $repairSource = Join-Path $second.ArtifactDirectory 'repair-source-batch-01.json'
        $source = Get-Content -LiteralPath $repairSource -Raw | ConvertFrom-Json -Depth 100
        @($source.files).Count | Should -Be 1
        $source.files[0].path | Should -Be $target
        $source.files[0].content | Should -Be ([string]@($firstPlan.changes | Where-Object path -eq $target)[0].content)
        Get-Content (Join-Path $second.ArtifactDirectory 'change-set-batch-01.json.attempt-1.request.md') -Raw |
            Should -Match 'repair-source-batch-01.json'
        & (Join-Path $script:Root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath $repairSource `
            -SchemaPath (Join-Path $script:Root 'schemas/runtime/carried-batch-context.schema.json') `
            -SchemaRoot (Join-Path $script:Root 'schemas') | Out-Null

        $secondPlan = Get-Content -LiteralPath (
            Join-Path $second.ArtifactDirectory "change-set-plan.json") -Raw |
            ConvertFrom-Json -Depth 100
        @($secondPlan.changes).Count | Should -Be @($firstPlan.changes).Count
        [int]$secondPlan.details.carriedForward.fileCount |
            Should -Be (@($firstPlan.changes).Count - 1)
        [string](@($secondPlan.changes | Where-Object path -eq $untouched)[0].content) |
            Should -Be ([string](@($firstPlan.changes | Where-Object path -eq $untouched)[0].content))

        # An artifact the run writes but the validator cannot map ends the
        # stage after every batch has been paid for, which is how the first
        # green build of this feature was lost.
        foreach ($mapped in @(
            @{ name = "batch-basis.json"; schema = "schemas/runtime/batch-basis.schema.json" },
            @{ name = "repair-instructions.json"
               schema = "schemas/runtime/repair-instructions.schema.json" }
        )) {
            & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
                -ArtifactPath (Join-Path $second.ArtifactDirectory ([string]$mapped.name)) `
                -SchemaPath (Join-Path $script:Root ([string]$mapped.schema)) `
                -SchemaRoot (Join-Path $script:Root "schemas") | Out-Null
        }
    }

    It "lets the repaired file read the callers the review left alone" {
        # A helper repaired without its callers in view is a helper renamed out
        # from under them, and the run learns that from the next review rather
        # than from the request it already paid for.
        $runRoot = Join-Path $TestDrive ("linked-run-" + [Guid]::NewGuid().ToString("N"))
        $repository = Join-Path $TestDrive ("linked-repo-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $repository -Force | Out-Null
        New-BatchingWorkflowState -RunRoot $runRoot -RunId $script:BatchRunId `
            -Workflow (Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root) `
            -LinkTestsToModules

        $first = Invoke-BatchingStage -RunRoot $runRoot `
            -Repository $repository -RunId $script:BatchRunId
        $first.Status | Should -Be "completed"
        $firstPlan = Get-Content -LiteralPath (
            Join-Path $first.ArtifactDirectory "change-set-plan.json") -Raw |
            ConvertFrom-Json -Depth 100

        $target = "automation/lib/module-01.ts"
        $caller = "automation/tests/case-01.ts"
        foreach ($reviewer in @("bootstrap-correctness-reviewer", "bootstrap-quality-reviewer")) {
            New-BatchReview -RunRoot $runRoot -AgentId $reviewer -Scope "targeted" -Paths @($target)
        }

        $second = Invoke-BatchingStage -RunRoot $runRoot `
            -Repository $repository -RunId $script:BatchRunId -Iteration 2
        $second.Status | Should -Be "completed"

        $assignments = @(Get-ChildItem -LiteralPath $second.ArtifactDirectory `
            -Filter "assignment-batch-*.json")
        @($assignments).Count | Should -Be 1
        $assignment = Get-Content -LiteralPath $assignments[0].FullName -Raw |
            ConvertFrom-Json -Depth 100
        @($assignment.carriedDependencies) | Should -Contain $caller
        [string]$assignment.carriedDependencyArtifact | Should -Not -BeNullOrEmpty

        $carriedPath = Join-Path $second.ArtifactDirectory ([string]$assignment.carriedDependencyArtifact)
        Test-Path -LiteralPath $carriedPath -PathType Leaf | Should -BeTrue
        $carried = Get-Content -LiteralPath $carriedPath -Raw | ConvertFrom-Json -Depth 100
        [string](@($carried.files | Where-Object path -eq $caller)[0].content) |
            Should -Be ([string](@($firstPlan.changes | Where-Object path -eq $caller)[0].content))

        & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $carriedPath `
            -SchemaPath (Join-Path $script:Root "schemas/runtime/carried-batch-context.schema.json") `
            -SchemaRoot (Join-Path $script:Root "schemas") | Out-Null
        & (Join-Path $script:Root "scripts/Validate-JsonArtifact.ps1") `
            -ArtifactPath $assignments[0].FullName `
            -SchemaPath (Join-Path $script:Root "schemas/runtime/batch-assignment.schema.json") `
            -SchemaRoot (Join-Path $script:Root "schemas") | Out-Null
    }

    It "regenerates everything when a reviewer asks for everything" {
        $first = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId
        $first.Status | Should -Be "completed"
        $firstPlan = Get-Content -LiteralPath (
            Join-Path $first.ArtifactDirectory "change-set-plan.json") -Raw |
            ConvertFrom-Json -Depth 100

        New-BatchReview -RunRoot $script:BatchRunRoot `
            -AgentId "bootstrap-correctness-reviewer" -Scope "targeted" `
            -Paths @([string]@($firstPlan.changes)[0].path)
        # One reviewer asking for the whole tree is enough: the files another
        # reviewer called correct were not read by this one.
        New-BatchReview -RunRoot $script:BatchRunRoot `
            -AgentId "bootstrap-security-reviewer" -Scope "all"

        $second = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId -Iteration 2
        $second.Status | Should -Be "completed"
        $secondPlan = Get-Content -LiteralPath (
            Join-Path $second.ArtifactDirectory "change-set-plan.json") -Raw |
            ConvertFrom-Json -Depth 100
        (Get-QaFoundryPropertyNames -InputObject $secondPlan.details) |
            Should -Not -Contain "carriedForward"
        @($secondPlan.changes).Count | Should -Be @($firstPlan.changes).Count
    }

    It "regenerates everything when a reviewer names a file the run never approved" {
        # A reviewer that points at the wrong path has made a mistake, and
        # carrying every other file forward on the strength of it would deliver
        # a tree nobody checked.
        $first = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId
        $first.Status | Should -Be "completed"

        New-BatchReview -RunRoot $script:BatchRunRoot `
            -AgentId "bootstrap-correctness-reviewer" -Scope "targeted" `
            -Paths @("automation/this-was-never-approved.ts")

        $second = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId -Iteration 2
        $second.Status | Should -Be "completed"
        $secondPlan = Get-Content -LiteralPath (
            Join-Path $second.ArtifactDirectory "change-set-plan.json") -Raw |
            ConvertFrom-Json -Depth 100
        (Get-QaFoundryPropertyNames -InputObject $secondPlan.details) |
            Should -Not -Contain "carriedForward"
    }

    It "refuses a merge whose plan leaves a withheld lock file unproduced" {
        # Called directly rather than through the stage, so that the mock
        # planner cannot answer for the coverage check and hide a regression
        # in it. The merge is the only thing that ties the two halves together.
        $directory = Join-Path $TestDrive ("merge-coverage-" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $batchPath = Join-Path $directory "change-set-batch-01.json"
        [ordered]@{
            agentId = "generator"; stageId = "generation"; runId = "run-merge-coverage"
            status = "completed"; summary = "One manifest."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"; batchId = "batch-01"
            changes = @([ordered]@{
                operation = "create"; path = "automation/package.json"; expectedSha256 = ""
                content = "{}"; reason = "Declare the approved dependencies."; sourceRefs = @()
            })
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $batchPath -Encoding utf8

        $emptyPlanPath = Join-Path $directory "materialization-plan.json"
        [ordered]@{
            agentId = "planner"; stageId = "generation"; runId = "run-merge-coverage"
            status = "completed"; summary = "Nothing to resolve."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "no_action_needed"; materializations = @()
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $emptyPlanPath -Encoding utf8

        $mergeArguments = @{
            BatchPaths = @($batchPath)
            ExpectedPaths = @("automation/package.json")
            OutputPath = (Join-Path $directory "change-set-plan.json")
            AgentId = "generator"; StageId = "generation"; RunId = "run-merge-coverage"
            ResolverOwnedPaths = @("automation/package-lock.json")
            MaterializationPath = $emptyPlanPath
        }
        {
            & (Join-Path $script:Root "scripts/Merge-ChangeSetBatches.ps1") @mergeArguments
        } | Should -Throw "*automation/package-lock.json*"
        Test-Path -LiteralPath $mergeArguments.OutputPath | Should -BeFalse

        $fullPlanPath = Join-Path $directory "materialization-plan-full.json"
        [ordered]@{
            agentId = "planner"; stageId = "generation"; runId = "run-merge-coverage"
            status = "completed"; summary = "One manifest handed to the resolver."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            outcome = "proposed"
            materializations = @([ordered]@{
                recipe = "npm-package-lock"; toolchainId = "npm-playwright-test"
                projectPaths = @("automation"); manifestPath = "automation/package.json"
                lockPath = "automation/package-lock.json"; operation = "create"
                expectedSha256 = ""; reason = "Lock the approved dependencies."
                sourceRefs = @("automation/package.json")
            })
        } | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $fullPlanPath -Encoding utf8

        $mergeArguments.MaterializationPath = $fullPlanPath
        $merged = & (Join-Path $script:Root "scripts/Merge-ChangeSetBatches.ps1") @mergeArguments
        [string]$merged.status | Should -Be "completed"
        [int]$merged.materializationCount | Should -Be 1
    }

    It "keeps the batches a lost relay leg already paid for" {
        # A batch costs a model call. Regenerating batches the previous leg
        # finished is how a 40-minute leg spends itself on work already done.
        $first = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId
        $first.Status | Should -Be "completed"

        $firstBatchPath = Join-Path $first.ArtifactDirectory "change-set-batch-01.json"
        $document = Get-Content -LiteralPath $firstBatchPath -Raw | ConvertFrom-Json -Depth 100
        $document.summary = "Written by the leg that was lost."
        $document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $firstBatchPath -Encoding utf8
        Remove-Item -LiteralPath (Join-Path $first.ArtifactDirectory "change-set-plan.json") -Force

        $second = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId -Reuse
        $second.Status | Should -Be "completed"
        (Get-Content -LiteralPath $firstBatchPath -Raw | ConvertFrom-Json -Depth 100).summary |
            Should -Be "Written by the leg that was lost."
        $plan = Get-Content -LiteralPath (
            Join-Path $second.ArtifactDirectory "change-set-plan.json") -Raw |
            ConvertFrom-Json -Depth 100
        @($plan.changes).Count | Should -Be 13
    }

    It "refuses to hand on a plan when a batch answered for the wrong files" {
        # Losing a file quietly is worse than failing loudly: the review stage
        # that follows reads the plan, not the inventory, and would approve a
        # framework with a hole in it.
        $first = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId
        $first.Status | Should -Be "completed"

        $tamperedPath = Join-Path $first.ArtifactDirectory "change-set-batch-02.json"
        $document = Get-Content -LiteralPath $tamperedPath -Raw | ConvertFrom-Json -Depth 100
        # Keep a schema-valid nonempty batch: an empty single-file response is
        # correctly discarded and regenerated before the merge is reached.
        $document.changes[0].path = 'automation/lib/not-assigned.ts'
        $document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $tamperedPath -Encoding utf8
        Remove-Item -LiteralPath (Join-Path $first.ArtifactDirectory "change-set-plan.json") -Force

        { Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId -Reuse } |
            Should -Throw "*came back from no batch*"
    }

    It "resolves the inventory the run approved rather than the newest file on disk" {
        # The implementation stages run as a critic loop and leave one inventory
        # per iteration. Searching the run directory would find the draft.
        $supersededDirectory = Join-Path $script:BatchRunRoot "implementation/iteration-2"
        New-Item -ItemType Directory -Path $supersededDirectory -Force | Out-Null
        [ordered]@{
            agentId = "framework-implementation"
            stageId = "implementation"
            runId = $script:BatchRunId
            status = "completed"
            summary = "A superseded draft that names a file nobody approved."
            evidence = @(); assumptions = @(); unknowns = @(); warnings = @(); details = @{}
            plannedFiles = @([ordered]@{
                path = "automation/lib/never-approved.ts"
                operation = "create"
                purpose = "Draft only."
                contentContract = "Should not reach the change set."
                dependsOn = @()
            })
        } | ConvertTo-Json -Depth 40 |
            Set-Content -LiteralPath (Join-Path $supersededDirectory "framework-implementation.json") `
                -Encoding utf8

        $result = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
            -Repository $script:BatchRepository -RunId $script:BatchRunId
        $result.Status | Should -Be "completed"
        $plan = Get-Content -LiteralPath (
            Join-Path $result.ArtifactDirectory "change-set-plan.json") -Raw |
            ConvertFrom-Json -Depth 100
        @($plan.changes | ForEach-Object { $_.path }) |
            Should -Not -Contain "automation/lib/never-approved.ts"
        @($plan.changes).Count | Should -Be 13
    }

    Context "A batch refuses because the file it needs belongs to another batch" {
        function script:Invoke-EscalatingStage {
            param(
                [string]$RequiredPaths = "automation/lib/module-01.ts",
                [string]$Escalation = "escalation:accept",
                [string]$RefusingBatch = "batch-04",
                [string]$RunRoot = "",
                [int]$MaxFilesPerBatch = 0,
                [int]$Iteration = 1
            )
            if (-not $RunRoot) { $RunRoot = $script:BatchRunRoot }
            $config = Get-TestConfig
            $config.ai.provider = "command"
            $config.ai.command = (
                "node $script:Root/tests/fixtures/escalating-batch-provider.mjs " +
                "$RefusingBatch $RequiredPaths $Escalation")
            $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
            $stage = @($workflow.stages | Where-Object id -eq "bootstrap-change-generation")[0]
            if ($MaxFilesPerBatch -gt 0) {
                $stage.batching.max_files_per_batch = $MaxFilesPerBatch
            }
            return & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
                -Stage $stage `
                -Config $config `
                -Policy (Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root) `
                -RunRoot $RunRoot `
                -RepositoryRoot $script:BatchRepository `
                -RunId $script:BatchRunId `
                -Iteration $Iteration
        }

        It 'repairs an approved carried file requested by a targeted batch and preserves unrelated code' {
            $first = Invoke-BatchingStage -RunRoot $script:BatchRunRoot `
                -Repository $script:BatchRepository -RunId $script:BatchRunId
            $first.Status | Should -Be 'completed'
            $before = Get-Content (Join-Path $first.ArtifactDirectory 'change-set-plan.json') -Raw |
                ConvertFrom-Json -Depth 100
            $target = 'automation/tests/case-05.ts'
            $dependency = 'automation/lib/module-01.ts'
            foreach ($reviewer in @('bootstrap-correctness-reviewer', 'bootstrap-quality-reviewer')) {
                New-BatchReview -RunRoot $script:BatchRunRoot -AgentId $reviewer -Scope targeted -Paths @($target)
            }
            $second = Invoke-EscalatingStage -Iteration 2 -RefusingBatch batch-01 -RequiredPaths $dependency
            $second.Status | Should -Be 'completed'
            $assignment = Get-Content (Join-Path $second.ArtifactDirectory 'assignment-batch-01-escalated.json') -Raw |
                ConvertFrom-Json -Depth 100
            @($assignment.assignedPaths).Count | Should -Be 2
            $assignment.assignedPaths | Should -Contain $target
            $assignment.assignedPaths | Should -Contain $dependency
            $assignment.repairInstructions[0].instruction | Should -Match 'do not substitute --list'
            $after = Get-Content (Join-Path $second.ArtifactDirectory 'change-set-plan.json') -Raw |
                ConvertFrom-Json -Depth 100
            @($after.changes).Count | Should -Be @($before.changes).Count
            @($after.changes | Where-Object path -eq $dependency)[0].content | Should -Match 'reconciled'
            foreach ($original in @($before.changes | Where-Object path -NotIn @($target, $dependency))) {
                @($after.changes | Where-Object path -eq $original.path)[0].content | Should -BeExactly $original.content
            }
        }

        It "asks once more for the refused files together with the ones it named" {
            # Build 498 ran the whole pipeline for ninety-five minutes and died
            # on the last batch of twelve. The refusal was correct and specific,
            # and the run had no way to act on it, so four hours of approved
            # work was thrown away over one contract that did not meet.
            # Exercise a multi-file batch independently of the production
            # default, which now assigns independent files one at a time.
            $result = Invoke-EscalatingStage -MaxFilesPerBatch 4

            $result.Status | Should -Be "completed"
            $plan = Get-Content -LiteralPath (
                Join-Path $result.ArtifactDirectory "change-set-plan.json") -Raw |
                ConvertFrom-Json -Depth 100
            @($plan.changes).Count | Should -Be 13
            @($plan.changes | ForEach-Object { $_.path } | Sort-Object -Unique).Count |
                Should -Be 13

            $assignment = Get-Content -LiteralPath (
                Join-Path $result.ArtifactDirectory "assignment-batch-04-escalated.json") -Raw |
                ConvertFrom-Json -Depth 100
            @($assignment.assignedPaths) | Should -Contain "automation/tests/case-05.ts"
            @($assignment.assignedPaths) | Should -Contain "automation/lib/module-01.ts"
            [string]$assignment.repairInstructions[0].instruction |
                Should -Match "do not offer"

            $sourcePath = Join-Path $result.ArtifactDirectory 'repair-source-batch-04-escalated.json'
            $source = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json -Depth 100
            @($source.files | Where-Object path -eq 'automation/lib/module-01.ts')[0].content |
                Should -Match 'written by batch-01'
            & (Join-Path $script:Root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath $sourcePath `
                -SchemaPath (Join-Path $script:Root 'schemas/runtime/carried-batch-context.schema.json') `
                -SchemaRoot (Join-Path $script:Root 'schemas') | Out-Null

            # The reconciled text wins over the version the earlier batch wrote,
            # which is the whole point of asking again.
            $reconciled = @($plan.changes |
                Where-Object { [string]$_.path -eq "automation/lib/module-01.ts" })[0]
            [string]$reconciled.content | Should -Match "reconciled by batch-04-escalated"
            $untouched = @($plan.changes |
                Where-Object { [string]$_.path -eq "automation/lib/module-02.ts" })[0]
            [string]$untouched.content | Should -Match "written by batch-01"
        }

        It "writes a merged set larger than one answer in parts that agree" {
            # Build 973271 spent two hours and lost leg 5 here: one of three
            # refusing batches had a merged assignment of 74 KB, more than a
            # single answer can close, and the run abandoned the whole stage
            # rather than write it in more than one call.
            $runRoot = Join-Path $TestDrive ("batch-escalation-parts-" +
                [Guid]::NewGuid().ToString("N"))
            New-BatchingWorkflowState -RunRoot $runRoot -RunId $script:BatchRunId `
                -Workflow (Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root)
            $result = Invoke-EscalatingStage -RunRoot $runRoot -MaxFilesPerBatch 1 `
                -RefusingBatch "batch-13" `
                -RequiredPaths "automation/lib/module-01.ts,automation/lib/module-02.ts"

            $result.Status | Should -Be "completed"

            $partOne = Join-Path $result.ArtifactDirectory "assignment-batch-13-escalated-part-1.json"
            $partTwo = Join-Path $result.ArtifactDirectory "assignment-batch-13-escalated-part-2.json"
            Test-Path -LiteralPath $partOne | Should -BeTrue
            Test-Path -LiteralPath $partTwo | Should -BeTrue

            # The files the refusal was waiting on are written first, and the
            # part that follows is given their finished text rather than the
            # contract they came from.
            $first = Get-Content -LiteralPath $partOne -Raw | ConvertFrom-Json -Depth 100
            @($first.assignedPaths) | Should -Contain "automation/lib/module-01.ts"
            $second = Get-Content -LiteralPath $partTwo -Raw | ConvertFrom-Json -Depth 100
            @($second.carriedDependencies) | Should -Contain "automation/lib/module-01.ts"
            $carried = Get-Content -LiteralPath (
                Join-Path $result.ArtifactDirectory "carried-batch-13-escalated-part-2.json") -Raw |
                ConvertFrom-Json -Depth 100
            [string](@($carried.files |
                Where-Object { $_.path -eq "automation/lib/module-01.ts" })[0].content) |
                Should -Match "reconciled by batch-13-escalated-part-1"

            # Downstream sees one change set for the escalation, and the plan
            # still carries every approved file exactly once.
            $combined = Get-Content -LiteralPath (
                Join-Path $result.ArtifactDirectory "change-set-batch-13-escalated.json") -Raw |
                ConvertFrom-Json -Depth 100
            @($combined.changes | ForEach-Object { $_.path }) |
                Should -Contain "automation/lib/module-02.ts"
            $plan = Get-Content -LiteralPath (
                Join-Path $result.ArtifactDirectory "change-set-plan.json") -Raw |
                ConvertFrom-Json -Depth 100
            @($plan.changes).Count | Should -Be 13
            @($plan.changes | ForEach-Object { $_.path } | Sort-Object -Unique).Count |
                Should -Be 13
        }

        It "ends the run when the refusal names no file that would help" {
            $result = Invoke-EscalatingStage -RequiredPaths "none"
            $result.Status | Should -Be "blocked"
            Test-Path -LiteralPath (
                Join-Path $result.ArtifactDirectory "assignment-batch-04-escalated.json") |
                Should -BeFalse
        }

        It "ends the run when the refusal names a file this stage is not writing" {
            $result = Invoke-EscalatingStage -RequiredPaths "automation/lib/not-approved.ts"
            $result.Status | Should -Be "blocked"
            Test-Path -LiteralPath (
                Join-Path $result.ArtifactDirectory "assignment-batch-04-escalated.json") |
                Should -BeFalse
        }

        It "ends the run when the merged assignment is refused as well" {
            # One retry, not a loop. A second refusal is an answer about the
            # plan, and spending another call on it would be spending the
            # budget of the leg to hear it again.
            $result = Invoke-EscalatingStage -Escalation "escalation:refuse"
            $result.Status | Should -Be "blocked"
            Test-Path -LiteralPath (
                Join-Path $result.ArtifactDirectory "change-set-batch-04-escalated.json") |
                Should -BeTrue
        }

        It "leaves a run whose every artifact still answers to a schema" {
            # The escalation writes files under names the run had never produced
            # before. Test-RunArtifacts refuses any generated JSON it has no
            # schema for, so a name the registry does not know would pass the
            # stage and then fail the run at the very end.
            $runRoot = Join-Path $TestDrive ("batch-escalation-registry-" +
                [Guid]::NewGuid().ToString("N"))
            New-BatchingWorkflowState -RunRoot $runRoot -RunId $script:BatchRunId `
                -Workflow (Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root)
            $result = Invoke-EscalatingStage -RunRoot $runRoot
            $result.Status | Should -Be "completed"

            Test-Path -LiteralPath (
                Join-Path $result.ArtifactDirectory "assignment-batch-04-escalated.json") |
                Should -BeTrue
            $validation = & (Join-Path $script:Root "scripts/Test-RunArtifacts.ps1") `
                -RunRoot $runRoot
            $validation.valid | Should -BeTrue
        }

        It "refuses an escalation that answered without the files it was given" {
            # The escalation exists to rewrite files another batch already
            # wrote. An answer that leaves one out merges cleanly: the earlier
            # version is still there, nothing is missing, and the plan ships the
            # exact mismatch the refusal was about with no record of it. This is
            # the one failure in the batching that is silent, which makes it
            # worse than the crash it replaces.
            $runRoot = Join-Path $TestDrive ("batch-escalation-partial-" +
                [Guid]::NewGuid().ToString("N"))
            New-BatchingWorkflowState -RunRoot $runRoot -RunId $script:BatchRunId `
                -Workflow (Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root)
            $result = Invoke-EscalatingStage -RunRoot $runRoot `
                -Escalation "escalation:partial"

            $result.Status | Should -Not -Be "completed"
            $plan = Join-Path $result.ArtifactDirectory "change-set-plan.json"
            if (Test-Path -LiteralPath $plan) {
                $document = Get-Content -LiteralPath $plan -Raw | ConvertFrom-Json -Depth 100
                @($document.changes | Where-Object {
                    [string]$_.path -eq "automation/lib/module-01.ts" -and
                    [string]$_.content -match "written by batch-01"
                }).Count | Should -Be 0
            }
        }

        It "shows the escalation the files its merged assignment imports" {
            # The blocked batch owns a test that imports a module another batch
            # has already written. If the second call cannot read that module it
            # writes against the contract again, which is the reason it refused.
            $runRoot = Join-Path $TestDrive ("batch-escalation-deps-" + [Guid]::NewGuid().ToString("N"))
            New-BatchingWorkflowState -RunRoot $runRoot -RunId $script:BatchRunId `
                -Workflow (Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root) `
                -LinkTestsToModules

            $result = Invoke-EscalatingStage -RunRoot $runRoot -RefusingBatch "batch-04" `
                -RequiredPaths "automation/tests/case-01.ts" -MaxFilesPerBatch 4
            $result.Status | Should -Be "completed"

            $request = Get-Content -LiteralPath (Join-Path $result.ArtifactDirectory `
                "change-set-batch-04-escalated.json.attempt-1.request.md") -Raw
            $request | Should -Match "written by batch-02"
        }

        It "shows the layers that follow the text the escalation wrote, not the text it replaced" {
            # The escalation rewrites a file a lower layer had already written.
            # A batch above it that imports that file would otherwise be shown
            # the version that is no longer in the plan, and would agree with
            # text nobody is going to deliver.
            $runRoot = Join-Path $TestDrive ("batch-escalation-layers-" + [Guid]::NewGuid().ToString("N"))
            New-BatchingWorkflowState -RunRoot $runRoot -RunId $script:BatchRunId `
                -Workflow (Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root) `
                -LinkTestsToModules

            $result = Invoke-EscalatingStage -RunRoot $runRoot -RefusingBatch "batch-02" `
                -RequiredPaths "automation/lib/module-01.ts" -MaxFilesPerBatch 4
            $result.Status | Should -Be "completed"

            $superseded = Get-Content -LiteralPath (
                Join-Path $result.ArtifactDirectory "change-set-batch-01-superseded.json") -Raw |
                ConvertFrom-Json -Depth 100
            @($superseded.changes | ForEach-Object { [string]$_.path }) |
                Should -Not -Contain "automation/lib/module-01.ts"

            $carried = Get-Content -LiteralPath (
                Join-Path $result.ArtifactDirectory "carried-batch-03.json") -Raw |
                ConvertFrom-Json -Depth 100
            $moduleOne = @($carried.files |
                Where-Object { [string]$_.path -eq "automation/lib/module-01.ts" })[0]
            [string]$moduleOne.content | Should -Match "reconciled by batch-02-escalated"

            $plan = Get-Content -LiteralPath (
                Join-Path $result.ArtifactDirectory "change-set-plan.json") -Raw |
                ConvertFrom-Json -Depth 100
            @($plan.changes).Count | Should -Be 13
        }
    }
}


Describe "A self-revising stage carries its last revision forward" {
    BeforeAll {
        function script:New-LoopWorkflow {
            param(
                [Parameter(Mandatory)][string[]]$CriticIds,
                [string]$OnExhaustion = "proceed",
                [int]$MaxIterations = 2
            )
            $approval = [ordered]@{
                strategy = "unanimous"
                max_iterations = $MaxIterations
            }
            if (-not [string]::IsNullOrWhiteSpace($OnExhaustion)) {
                $approval["on_exhaustion"] = $OnExhaustion
            }
            $outputs = @("correctness-review.json", "quality-review.json", "security-review.json")
            $critics = @()
            for ($index = 0; $index -lt $CriticIds.Count; $index++) {
                $critics += [pscustomobject][ordered]@{
                    agent = [string]$CriticIds[$index]
                    prompt = "prompts/architecture/architecture-critic.md"
                    schema = "schemas/sdlc/review.schema.json"
                    input = "product-analysis.json"
                    output = $outputs[$index]
                }
            }
            return [pscustomobject][ordered]@{
                name = "loop-exhaustion-probe"
                version = 1
                stages = @([pscustomobject][ordered]@{
                    id = "loop"
                    risk = "high"
                    type = "producer_critic_loop"
                    producer = [pscustomobject][ordered]@{
                        agent = "loop-producer"
                        prompt = "prompts/architecture/automation-architect.md"
                        schema = "schemas/sdlc/analysis.schema.json"
                        output = "product-analysis.json"
                    }
                    critics = $critics
                    approval = [pscustomobject]$approval
                })
            }
        }

        function script:Invoke-LoopWorkflow {
            param(
                [Parameter(Mandatory)][object]$Workflow,
                [Parameter(Mandatory)][string]$RunRoot,
                [Parameter(Mandatory)][string]$RunId
            )
            $config = Get-TestConfig
            $config.ai.provider = "command"
            $config.ai.command = "node $script:Root/tests/fixtures/producer-critic-loop-provider.mjs"
            New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
            return & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                -Workflow $Workflow `
                -Config $config `
                -Policy (Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root) `
                -RepositoryRoot $script:Root `
                -RunRoot $RunRoot `
                -RunId $RunId
        }
    }

    It "continues with recorded dissent instead of discarding four rounds of work" {
        # Build 476 died on stage 2 of 11. The security critic approved, the other
        # two kept asking for endpoint values and credentials the environment
        # cannot supply, and the run threw away a blueprint four rounds of
        # critique had already improved. A stage that revises inside itself does
        # carry revised work, even though it declares no stage to return to.
        $workflow = New-LoopWorkflow -CriticIds @("loop-critic-dissents", "loop-critic-approves")
        $runRoot = Join-Path $TestDrive "loop-proceed"
        $state = Invoke-LoopWorkflow -Workflow $workflow -RunRoot $runRoot -RunId "run-loop-proceed"

        $state.status | Should -Be "completed"
        $record = @($state.stages | Where-Object { $_.id -eq "loop" })[-1]
        $record.status | Should -Be "approved_with_dissent"
        @($record.attempts[-1].artifacts | ForEach-Object { [string]$_.name }) |
            Should -Contain "product-analysis.json"
    }

    It "still stops when the stage is not told it may proceed" {
        $workflow = New-LoopWorkflow -CriticIds @("loop-critic-dissents") -OnExhaustion ""
        $runRoot = Join-Path $TestDrive "loop-default"
        $state = Invoke-LoopWorkflow -Workflow $workflow -RunRoot $runRoot -RunId "run-loop-default"

        $state.status | Should -Be "blocked"
        @($state.stages | Where-Object { $_.id -eq "loop" })[-1].status | Should -Be "blocked"
    }

    It "still stops when a critic refuses, whatever exhaustion permits" {
        # Permission to proceed past an iteration limit is not permission to
        # proceed past a refusal. A critic that answers 'blocked' has judged the
        # work unsafe rather than unfinished.
        $workflow = New-LoopWorkflow -CriticIds @("loop-critic-blocks", "loop-critic-approves")
        $runRoot = Join-Path $TestDrive "loop-blocked"
        $state = Invoke-LoopWorkflow -Workflow $workflow -RunRoot $runRoot -RunId "run-loop-blocked"

        $state.status | Should -Be "blocked"
        @($state.stages | Where-Object { $_.id -eq "loop" })[-1].status | Should -Be "blocked"
    }

    It "records the dissent on the attempt a later stage will read, not only on the stage" {
        # Build 479 reached stage 10 of 11 after two hours and crashed there:
        # the architecture stage had proceeded with dissent, but every attempt
        # it recorded still read 'revision_required', and a declared input is
        # resolved from an attempt. The run had been building on a blueprint it
        # then refused to admit existed.
        $workflow = New-LoopWorkflow -CriticIds @("loop-critic-dissents", "loop-critic-approves")
        $runRoot = Join-Path $TestDrive "loop-attempt-status"
        $state = Invoke-LoopWorkflow -Workflow $workflow -RunRoot $runRoot `
            -RunId "run-loop-attempt-status"

        $state.status | Should -Be "completed"
        $record = @($state.stages | Where-Object { $_.id -eq "loop" })[-1]
        [string]$record.attempts[-1].status | Should -Be "approved_with_dissent"
        # The status says what the run did with the work; the decision says what
        # the critics thought of it. Overwriting the second to fix the first
        # would erase the dissent the draft delivery is supposed to publish.
        [string]$record.attempts[-1].decision | Should -Be "revision_required"
    }

    It "lets a later stage take the blueprint the dissenting stage carried forward" {
        $workflow = New-LoopWorkflow -CriticIds @("loop-critic-dissents", "loop-critic-approves")
        $runRoot = Join-Path $TestDrive "loop-declared-input"
        $null = Invoke-LoopWorkflow -Workflow $workflow -RunRoot $runRoot `
            -RunId "run-loop-declared-input"

        $resolved = Resolve-QaFoundryDeclaredInputs -RunRoot $runRoot -StageId "consumer" -Inputs (
            [pscustomobject]@{
                blueprint = [pscustomobject]@{
                    stage = "loop"; artifact = "product-analysis.json"
                }
            })

        Test-Path -LiteralPath $resolved["blueprint"].path | Should -BeTrue
        $resolved["blueprint"].stage | Should -Be "loop"
    }

    It "keeps the architecture stage allowed to proceed with its dissent recorded" {
        $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
        $architecture = @($workflow.stages | Where-Object id -eq "architecture")[0]
        $architecture.type | Should -Be "producer_critic_loop"
        $architecture.approval.on_exhaustion | Should -Be "proceed"
        $architecture.approval.PSObject.Properties.Name | Should -Not -Contain "on_reject"
    }

    It "gives the toolchain resolver somewhere to send a design it cannot lock" {
        # Build 972137 approved an architecture unanimously, pinned nine of ten
        # packages, and ended the run because the tenth range was written in the
        # wrong ecosystem's notation. The resolver was the only stage in the
        # workflow that could refuse without a way back, so a fault one revision
        # would have fixed cost the whole bootstrap.
        $workflow = Import-QaFoundryYaml -Path $script:WorkflowPath -Root $script:Root
        $ids = @($workflow.stages | ForEach-Object { [string]$_.id })
        $stage = @($workflow.stages | Where-Object id -eq "toolchain-resolution")[0]
        $stage.type | Should -Be "deterministic_action"
        $stage.approval.on_reject.return_to | Should -Be "architecture"
        # The target has to come earlier, or the rewind would skip work instead
        # of repeating it.
        $ids.IndexOf("architecture") | Should -BeLessThan $ids.IndexOf("toolchain-resolution")
        # Bounded, because the same wrong notation twice is a signal about the
        # design rather than something more rounds improve.
        [int]$stage.approval.max_iterations | Should -BeGreaterThan 1
        [int]$stage.approval.max_iterations | Should -BeLessOrEqual 3
        # Every later stage builds against the lock, so there is nothing to
        # proceed with when there is no lock.
        $stage.approval.on_exhaustion | Should -Be "block"
    }
}

Describe "A field that is over its limit is asked for again, not the whole answer" {
    # Build 499 lost the run on the fourth of eleven stages because one
    # contentContract was 3035 characters against a limit of 3000. The agent
    # shortened it on every attempt -- 3678, then 3270, then 3035 -- regenerating
    # sixty-five kilobytes each time, and ran out of attempts one percent short.
    function script:Invoke-OverlongAgent {
        param(
            [string]$Overage = "slight",
            [string]$Repair = "honours",
            [Parameter(Mandatory)][string]$OutputPath,
            [int]$Retries = 0
        )
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/overlong-field-provider.mjs " +
            "$Overage $Repair"
        $config.runtime.agent_schema_retries = $Retries
        return & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "framework-implementation" `
            -StageId "implementation" `
            -RunId "run-overlong-test" `
            -PromptPath (Join-Path $script:Root "prompts/sdlc/implementation-engineering.md") `
            -ContextPaths @() `
            -OutputPath $OutputPath `
            -SchemaPath (Join-Path $script:Root "schemas/implementation/implementation-result.schema.json") `
            -Config $config
    }

    It "accepts the answer once the agent has shortened the field it was asked about" {
        $output = Join-Path $TestDrive "repair-honoured/implementation-result.json"
        $result = Invoke-OverlongAgent -OutputPath $output

        $result.plannedFiles[0].contentContract.Length | Should -BeLessOrEqual 4500
        # Nothing but the field in question is touched.
        $result.plannedFiles[1].contentContract |
            Should -Be "The gadget contract, which is within its limit."
        $result.plannedFiles[0].path | Should -Be "automation/widget.mjs"
        $result.commandsProposed | Should -Be @("dotnet build")
        # One full answer and one short correction, not two full answers.
        @(Get-ChildItem -Path (Split-Path $output -Parent) -Filter "*.attempt-*.raw.txt").Count |
            Should -Be 1
        Test-Path -LiteralPath "$output.repair.raw.txt" | Should -BeTrue
        Test-Path -LiteralPath "$output.repair.request.md" | Should -BeTrue
        $record = Get-Content -LiteralPath "$output.repair.applied.json" -Raw |
            ConvertFrom-Json -Depth 10
        $record.shortened[0].pointer | Should -Be "/plannedFiles/0/contentContract"
        $record.shortened[0].before | Should -Be 4535
        $record.shortened[0].after | Should -BeLessOrEqual 4500
    }

    It "asks about every overlong field at once" {
        $output = Join-Path $TestDrive "repair-two-fields/implementation-result.json"
        $result = Invoke-OverlongAgent -Overage "badPurpose" -OutputPath $output

        $result.plannedFiles[0].purpose.Length | Should -BeLessOrEqual 400
        $result.plannedFiles[0].contentContract.Length | Should -BeLessOrEqual 4500
        $request = Get-Content -LiteralPath "$output.repair.request.md" -Raw
        $request | Should -Match "/plannedFiles/0/purpose"
        $request | Should -Match "/plannedFiles/0/contentContract"
    }

    It "refuses a shortening that is still over the limit" {
        $output = Join-Path $TestDrive "repair-still-long/implementation-result.json"
        { Invoke-OverlongAgent -Repair "stillLong" -OutputPath $output } |
            Should -Throw "*must NOT have more than 4500 characters*"
        Test-Path -LiteralPath "$output.repair.applied.json" | Should -BeFalse
    }

    It "refuses a shortening that answers about a field nobody asked about" {
        $output = Join-Path $TestDrive "repair-wrong-pointer/implementation-result.json"
        { Invoke-OverlongAgent -Repair "wrongPointer" -OutputPath $output } |
            Should -Throw "*must NOT have more than 4500 characters*"
        Test-Path -LiteralPath "$output.repair.applied.json" | Should -BeFalse
    }

    It "refuses a shortening that is not JSON at all" {
        $output = Join-Path $TestDrive "repair-prose/implementation-result.json"
        { Invoke-OverlongAgent -Repair "prose" -OutputPath $output } |
            Should -Throw "*must NOT have more than 4500 characters*"
        Test-Path -LiteralPath "$output.repair.applied.json" | Should -BeFalse
    }

    It "does not shorten a field that is a path rather than prose" {
        # The same keyword guards paths, identifiers and command lines. A shorter
        # path is not a shorter way of saying the same thing: it is a different
        # path, and the run would carry a file name nobody wrote.
        $output = Join-Path $TestDrive "repair-path/implementation-result.json"
        { Invoke-OverlongAgent -Overage "longPath" -OutputPath $output } |
            Should -Throw "*must NOT have more than 200 characters*"
        Test-Path -LiteralPath "$output.repair.request.md" | Should -BeFalse
    }

    It "does not ask for an edit when the field needs rewriting" {
        # Half as long again is not a wording problem, and asking for it to be
        # tightened invites the content to be dropped instead.
        $output = Join-Path $TestDrive "repair-gross/implementation-result.json"
        { Invoke-OverlongAgent -Overage "gross" -OutputPath $output } |
            Should -Throw "*must NOT have more than 4500 characters*"
        Test-Path -LiteralPath "$output.repair.request.md" | Should -BeFalse
    }

    It "shortens a deferral that is ten characters over and keeps the rest of the list" {
        # Build 972660 lost a leg on a deferral's item of 410 characters against
        # a limit of 400. What is left undone is prose in the same sense as a
        # summary, and the run had every reason to settle it in one short call
        # rather than write sixty kilobytes again three times over.
        $output = Join-Path $TestDrive "repair-deferral/implementation-result.json"
        $result = Invoke-OverlongAgent -Overage "deferralItem" -OutputPath $output

        $result.deferrals[1].item.Length | Should -BeLessOrEqual 400
        # The work the agent named is still named: an item that is shortened is
        # still the item, and the entries either side of it are untouched.
        $result.deferrals.Count | Should -Be 3
        $result.deferrals[0].item | Should -Be "The gadget suite"
        $result.deferrals[1].reason | Should -Be "Ran out of room."
        $result.deferrals[2].item | Should -Be "The harness README"
        # One full answer and one short correction, not two full answers.
        @(Get-ChildItem -Path (Split-Path $output -Parent) -Filter "*.attempt-*.raw.txt").Count |
            Should -Be 1
        $record = Get-Content -LiteralPath "$output.repair.applied.json" -Raw |
            ConvertFrom-Json -Depth 10
        $record.shortened[0].pointer | Should -Be "/deferrals/1/item"
        $record.shortened[0].before | Should -Be 410
        # The run still knows there is work outstanding, and how much.
        $coverage = Get-Content -LiteralPath "$output.coverage.json" -Raw | ConvertFrom-Json -Depth 10
        $coverage.status | Should -Be "deferred"
        $coverage.deferrals.Count | Should -Be 3
    }
}

Describe "Work a smaller answer left undone" {
    # Cutting the output budget is the runtime deciding to leave work out. Until
    # now the agent was asked to mention the omission in prose, which nothing
    # read, so a stage could hand on a plan smaller than the one it was asked
    # for and every check downstream would pass on the smaller one.
    function script:Invoke-DeferringAgent {
        param(
            [string]$Behaviour = "declares",
            [Parameter(Mandatory)][string]$OutputPath,
            [int]$Retries = 2,
            [int]$StageIteration = 1,
            [switch]$AllowExistingArtifact
        )
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/deferral-provider.mjs $Behaviour"
        $config.runtime.agent_schema_retries = $Retries
        return & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "risk-test-planner" `
            -StageId "test-planning" `
            -RunId "run-deferral-test" `
            -StageIteration $StageIteration `
            -PromptPath (Join-Path $script:Root "prompts/planning/risk-test-planner.md") `
            -ContextPaths @() `
            -OutputPath $OutputPath `
            -SchemaPath (Join-Path $script:Root "schemas/planning/risk-test-plan.schema.json") `
            -Config $config `
            -AllowExistingArtifact:$AllowExistingArtifact
    }

    It "asks for the omissions as items rather than as a note" {
        $output = Join-Path $TestDrive "deferral-asked/risk-test-plan.json"
        $null = Invoke-DeferringAgent -OutputPath $output
        $secondRequest = Get-Content -LiteralPath "$output.attempt-2.request.md" -Raw
        $secondRequest | Should -Match "deferrals"
        $secondRequest | Should -Match "one object per item"
        # The old wording sent the omission to whichever prose field happened to
        # exist, which is how it stopped being work and became a sentence.
        $secondRequest | Should -Not -Match "whichever field the schema provides"
    }

    It "keeps what the agent left out as items the run can act on" {
        $output = Join-Path $TestDrive "deferral-declared/risk-test-plan.json"
        $result = Invoke-DeferringAgent -OutputPath $output

        @($result.deferrals).Count | Should -Be 2
        [string]$result.deferrals[0].item | Should -Match "payment gateway"
        [string]$result.deferrals[0].reason | Should -Not -BeNullOrEmpty

        $coverage = Get-Content -LiteralPath "$output.coverage.json" -Raw | ConvertFrom-Json -Depth 20
        [string]$coverage.status | Should -Be "deferred"
        [string]$coverage.agentId | Should -Be "risk-test-planner"
        @($coverage.reductions).Count | Should -Be 1
        [string]$coverage.reductions[0].cause | Should -Be "answer_cut_off"
        [int]$coverage.grantedBytes | Should -BeLessThan ([int]$coverage.requestedBytes)
        @($coverage.deferrals).Count | Should -Be 2
    }

    It "asks once for what a smaller answer left out, and no more" {
        # The first live bootstrap spent three model calls of twelve minutes
        # each arguing with an agent that insisted it had finished, and then
        # failed the whole run. An agent that has already been told how to name
        # its omissions and still names none is not going to name any on the
        # third ask, and the demand the old wording made — produce it at full
        # scope — is one it cannot meet under the budget it is answering with.
        $output = Join-Path $TestDrive "deferral-dropped/risk-test-plan.json"
        $result = Invoke-DeferringAgent -Behaviour "drops" -OutputPath $output -Retries 3

        # Asked on attempt 2, kept on attempt 3, never asked a fourth time.
        Get-Content -LiteralPath "$output.attempt-3.request.md" -Raw |
            Should -Match "reduced output budget"
        Test-Path -LiteralPath "$output.attempt-4.request.md" | Should -BeFalse
        @($result.riskScenarios).Count | Should -Be 1
    }

    It "books the whole job as still owed rather than take that answer as finished" {
        # The answer is kept: it cost twelve minutes and it is not worthless.
        # What is not kept is the claim that it finished, so the stage reads one
        # item still owed and comes back for it with a full budget.
        $output = Join-Path $TestDrive "deferral-unconfirmed/risk-test-plan.json"
        $null = Invoke-DeferringAgent -Behaviour "drops" -OutputPath $output -Retries 3

        $coverage = Get-Content -LiteralPath "$output.coverage.json" -Raw | ConvertFrom-Json -Depth 20
        [string]$coverage.status | Should -Be "deferred"
        [string]$coverage.deferralsSource | Should -Be "run"
        @($coverage.deferrals).Count | Should -Be 1
        [string]$coverage.deferrals[0].item | Should -Match "full scope"
        [string]$coverage.deferrals[0].reason | Should -Not -BeNullOrEmpty
        # The artifact itself is left exactly as the agent signed it. Writing
        # the run's own item into the agent's document would put words in its
        # mouth that every later stage would read as its own.
        $artifact = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json -Depth 20
        (Get-QaFoundryPropertyNames -InputObject $artifact) -contains "deferrals" | Should -BeFalse
    }

    It "asks that answer again at full scope instead of handing back the same one" {
        # Without this the repeat is a no-op: the artifact is on disk and passes
        # its schema, so the next iteration reuses it, records the same unmet
        # item, and the run walks its iterations out and blocks having asked
        # nothing twice.
        $output = Join-Path $TestDrive "deferral-reasked/risk-test-plan.json"
        $null = Invoke-DeferringAgent -Behaviour "drops" -OutputPath $output -Retries 3

        $second = Invoke-DeferringAgent -Behaviour "declaresThenCovers" -OutputPath $output `
            -Retries 3 -StageIteration 2 -AllowExistingArtifact

        @($second.riskScenarios).Count | Should -Be 3
        $coverage = Get-Content -LiteralPath "$output.coverage.json" -Raw | ConvertFrom-Json -Depth 20
        [string]$coverage.status | Should -Be "covered"
        # The cut that the discarded answer was written under went with it. A
        # repeat that inherited the halved budget would end where the first one
        # did, whatever the agent had to say.
        @($coverage.reductions).Count | Should -Be 0
        [int]$coverage.grantedBytes | Should -Be ([int]$coverage.requestedBytes)
    }

    It "keeps the answer rather than spend the last attempt asking a question it cannot answer" {
        # Build 972808 resumed a leg on the third attempt of three, because two
        # had been rejected before the relay handed over. The ask landed on the
        # last attempt there was, so the throw that is meant to cost one call
        # cost the run instead - fourteen minutes of model time thrown away over
        # a question the runtime was willing to take either answer to.
        $output = Join-Path $TestDrive "deferral-lastattempt/risk-test-plan.json"
        $result = Invoke-DeferringAgent -Behaviour "drops" -OutputPath $output -Retries 1

        # Cut off on the first attempt, answered on the second, and the second
        # was the last: it is kept rather than argued with.
        @($result.riskScenarios).Count | Should -Be 1
        Test-Path -LiteralPath "$output.attempt-2.request.md" | Should -BeTrue
        Get-Content -LiteralPath "$output.attempt-2.request.md" -Raw |
            Should -Not -Match "say so again and it will be kept"
        # Kept on the same terms it would have been kept on after the ask: the
        # claim to have finished is not believed, and the stage comes back.
        $coverage = Get-Content -LiteralPath "$output.coverage.json" -Raw | ConvertFrom-Json -Depth 20
        [string]$coverage.status | Should -Be "deferred"
        [string]$coverage.deferralsSource | Should -Be "run"
        [string]$coverage.deferrals[0].item | Should -Match "full scope"
    }

    It "records that nothing was left out when nothing was" {
        # The file is written either way, so a run whose coverage record is
        # missing is a defect in the runtime rather than an agent that lost
        # nothing.
        $output = Join-Path $TestDrive "deferral-none/implementation-result.json"
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $null = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "framework-implementation" `
            -StageId "implementation" `
            -RunId "run-deferral-none" `
            -PromptPath (Join-Path $script:Root "prompts/sdlc/implementation-engineering.md") `
            -ContextPaths @() `
            -OutputPath $output `
            -SchemaPath (Join-Path $script:Root "schemas/implementation/implementation-result.schema.json") `
            -Config $config

        $coverage = Get-Content -LiteralPath "$output.coverage.json" -Raw | ConvertFrom-Json -Depth 20
        [string]$coverage.status | Should -Be "covered"
        @($coverage.reductions).Count | Should -Be 0
        @($coverage.deferrals).Count | Should -Be 0
    }

    It "does not ask a second time because the leg it asked on ended" {
        # 'Asked once' is a promise about the run. The record of having asked
        # lives beside the feedback that earned it, or the argument this was
        # written to stop simply resumes on the next leg.
        $output = Join-Path $TestDrive "deferral-nudge-relay/risk-test-plan.json"
        New-Item -ItemType Directory -Path (Split-Path $output -Parent) -Force | Out-Null
        [ordered]@{
            runId = "run-deferral-test"
            agentId = "risk-test-planner"
            attempts = 1
            lastValidationError = "This artifact was produced under a reduced output budget"
            attemptArtifactBytes = 16384
            deferralNudgeUsed = $true
            scopeReductions = @(
                [ordered]@{ attempt = 1; cause = "answer_cut_off"; grantedBytes = 16384 })
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$output.rejections.json" -Encoding utf8

        $result = Invoke-DeferringAgent -Behaviour "drops" -OutputPath $output -Retries 1 `
            -AllowExistingArtifact

        # The same setup without that flag throws, one test below.
        @($result.riskScenarios).Count | Should -Be 1
        $coverage = Get-Content -LiteralPath "$output.coverage.json" -Raw | ConvertFrom-Json -Depth 20
        [string]$coverage.deferralsSource | Should -Be "run"
    }

    It "does not reuse an artifact whose completeness was never written down" {
        # The artifact reaches disk before the coverage record beside it. A leg
        # killed in that window leaves a document that passes its schema and
        # nothing to say what it cost, and a missing record reads everywhere
        # else as 'nothing was left out'.
        $output = Join-Path $TestDrive "deferral-half-written/risk-test-plan.json"
        $first = Invoke-DeferringAgent -Behaviour "declaresThenCovers" -OutputPath $output `
            -StageIteration 2
        @($first.riskScenarios).Count | Should -Be 3
        Remove-Item -LiteralPath "$output.coverage.json" -Force

        $second = Invoke-DeferringAgent -Behaviour "declaresThenCovers" -OutputPath $output `
            -StageIteration 1 -AllowExistingArtifact

        # Reuse would have handed back the three-scenario answer untouched.
        @($second.riskScenarios).Count | Should -Be 1
        @($second.deferrals).Count | Should -Be 2
        Test-Path -LiteralPath "$output.coverage.json" | Should -BeTrue
    }

    It "carries a budget cut from an earlier leg into the leg that answers" {
        # The reduction and the answer can fall on opposite sides of a job
        # boundary. A leg that has forgotten the cut accepts the smaller answer
        # as the whole one, which is the loss this check exists to prevent.
        $output = Join-Path $TestDrive "deferral-relay/risk-test-plan.json"
        New-Item -ItemType Directory -Path (Split-Path $output -Parent) -Force | Out-Null
        [ordered]@{
            runId = "run-deferral-test"
            agentId = "risk-test-planner"
            attempts = 1
            lastValidationError = "QAFOUNDRY_TRUNCATED_RESPONSE: cut off"
            attemptArtifactBytes = 16384
            scopeReductions = @(
                [ordered]@{ attempt = 1; cause = "answer_cut_off"; grantedBytes = 16384 })
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$output.rejections.json" -Encoding utf8

        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/deferral-provider.mjs drops"
        $config.runtime.agent_schema_retries = 1
        $result = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "risk-test-planner" `
            -StageId "test-planning" `
            -RunId "run-deferral-test" `
            -PromptPath (Join-Path $script:Root "prompts/planning/risk-test-planner.md") `
            -ContextPaths @() `
            -OutputPath $output `
            -SchemaPath (Join-Path $script:Root "schemas/planning/risk-test-plan.schema.json") `
            -Config $config `
            -AllowExistingArtifact

        # The cut came over the boundary, so the short answer is not taken for
        # the whole one: the run books the job as still owed. Had the reduction
        # been forgotten, this would read 'covered' from the agent itself.
        @($result.riskScenarios).Count | Should -Be 1
        $coverage = Get-Content -LiteralPath "$output.coverage.json" -Raw | ConvertFrom-Json -Depth 20
        [string]$coverage.status | Should -Be "deferred"
        [string]$coverage.deferralsSource | Should -Be "run"
        @($coverage.reductions).Count | Should -Be 1
        [string]$coverage.reductions[0].cause | Should -Be "answer_cut_off"
    }

    It "keeps the third answer when two legs have already spent the other two attempts" {
        # Build 972808 as it happened. The first answer was cut off, which cost
        # an attempt and the budget; the second was rejected for a missing
        # document; the relay handed over; and the third came back valid in
        # every respect but its claim to have finished. That claim is worth one
        # question and never the run, so with the last attempt in use it is the
        # answer that is kept and the claim that is dropped.
        $output = Join-Path $TestDrive "deferral-lastleg/risk-test-plan.json"
        New-Item -ItemType Directory -Path (Split-Path $output -Parent) -Force | Out-Null
        [ordered]@{
            runId = "run-deferral-test"
            agentId = "risk-test-planner"
            attempts = 2
            lastValidationError = "technology-choices.md was not written"
            attemptArtifactBytes = 16384
            scopeReductions = @(
                [ordered]@{ attempt = 1; cause = "answer_cut_off"; grantedBytes = 16384 })
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$output.rejections.json" -Encoding utf8

        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/deferral-provider.mjs drops"
        $config.runtime.agent_schema_retries = 2
        $result = & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "risk-test-planner" `
            -StageId "test-planning" `
            -RunId "run-deferral-test" `
            -PromptPath (Join-Path $script:Root "prompts/planning/risk-test-planner.md") `
            -ContextPaths @() `
            -OutputPath $output `
            -SchemaPath (Join-Path $script:Root "schemas/planning/risk-test-plan.schema.json") `
            -Config $config `
            -AllowExistingArtifact

        @($result.riskScenarios).Count | Should -Be 1
        # The one attempt this leg had went on the answer, not on arguing about
        # it, and no fourth was invented to hold the argument.
        Test-Path -LiteralPath "$output.attempt-3.request.md" | Should -BeTrue
        Test-Path -LiteralPath "$output.attempt-4.request.md" | Should -BeFalse
        Get-Content -LiteralPath "$output.attempt-3.request.md" -Raw |
            Should -Not -Match "say so again and it will be kept"
        # The stage is not finished: it comes back for the whole job at full
        # scope, which is the only condition under which 'completed' means
        # anything here.
        $coverage = Get-Content -LiteralPath "$output.coverage.json" -Raw | ConvertFrom-Json -Depth 20
        [string]$coverage.status | Should -Be "deferred"
        [string]$coverage.deferralsSource | Should -Be "run"
        [int]$coverage.attempts | Should -Be 3
        [string]$coverage.deferrals[0].item | Should -Match "full scope"
        # The rejection ledger is cleared, so a later leg does not read two
        # spent attempts against an answer that was accepted.
        Test-Path -LiteralPath "$output.rejections.json" | Should -BeFalse
    }
}

Describe "A stage does not finish over work it wrote down as undone" {
    It "sends the stage back rather than passing on a plan with a hole in it" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/deferral-provider.mjs declares"
        $config.runtime.agent_schema_retries = 2
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $runRoot = Join-Path $TestDrive "stage-with-deferrals"
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
        $stage = [pscustomobject]@{
            id = "test-planning"
            type = "sequential"
            agents = @([pscustomobject]@{
                id = "risk-test-planner"
                prompt = "prompts/planning/risk-test-planner.md"
                schema = "schemas/planning/risk-test-plan.schema.json"
                output = "risk-test-plan.json"
            })
        }

        $stageResult = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage $stage `
            -Config $config `
            -Policy $policy `
            -RunRoot $runRoot `
            -RepositoryRoot $script:Root `
            -RunId "run-stage-deferral"

        # The agent's own answer said 'completed' and the stage would otherwise
        # have agreed with it.
        $artifact = Get-Content -LiteralPath (
            Join-Path $runRoot "test-planning/risk-test-plan.json") -Raw |
            ConvertFrom-Json -Depth 40
        [string]$artifact.status | Should -Be "completed"
        @($artifact.deferrals).Count | Should -Be 2

        $stageResult.Status | Should -Be "revision_required"
        $stageResult.Decision | Should -Be "revision_required"
    }

    It "sends the stage back when the agent named nothing but was cut short" {
        # The artifact says 'completed' and declares no deferrals, so nothing in
        # the document itself asks for a second look. The run's own record of
        # the cut budget is the only thing that does, and the stage has to read
        # it exactly as it reads the agent's own list.
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/deferral-provider.mjs drops"
        $config.runtime.agent_schema_retries = 3
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $runRoot = Join-Path $TestDrive "stage-unconfirmed-coverage"
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
        $stage = [pscustomobject]@{
            id = "test-planning"
            type = "sequential"
            agents = @([pscustomobject]@{
                id = "risk-test-planner"
                prompt = "prompts/planning/risk-test-planner.md"
                schema = "schemas/planning/risk-test-plan.schema.json"
                output = "risk-test-plan.json"
            })
        }

        $stageResult = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage $stage `
            -Config $config `
            -Policy $policy `
            -RunRoot $runRoot `
            -RepositoryRoot $script:Root `
            -RunId "run-stage-unconfirmed"

        $artifact = Get-Content -LiteralPath (
            Join-Path $runRoot "test-planning/risk-test-plan.json") -Raw |
            ConvertFrom-Json -Depth 40
        [string]$artifact.status | Should -Be "completed"

        $stageResult.Status | Should -Be "revision_required"
        $stageResult.CoverageIncomplete | Should -BeTrue
        @($stageResult.Deferrals).Count | Should -Be 1
    }

    It "lets a stage finish when the agent left nothing undone" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $runRoot = Join-Path $TestDrive "stage-without-deferrals"
        New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
        $stage = [pscustomobject]@{
            id = "test-planning"
            type = "sequential"
            agents = @([pscustomobject]@{
                id = "risk-test-planner"
                prompt = "prompts/planning/risk-test-planner.md"
                schema = "schemas/planning/risk-test-plan.schema.json"
                output = "risk-test-plan.json"
            })
        }

        $stageResult = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage $stage `
            -Config $config `
            -Policy $policy `
            -RunRoot $runRoot `
            -RepositoryRoot $script:Root `
            -RunId "run-stage-no-deferral"

        $stageResult.Status | Should -Be "completed"
    }

    It "does not read an unreadable coverage record as nothing having been left out" {
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        $runRoot = Join-Path $TestDrive "stage-unreadable-coverage"
        $stageDirectory = Join-Path $runRoot "test-planning"
        New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
        $stage = [pscustomobject]@{
            id = "test-planning"
            type = "sequential"
            agents = @([pscustomobject]@{
                id = "risk-test-planner"
                prompt = "prompts/planning/risk-test-planner.md"
                schema = "schemas/planning/risk-test-plan.schema.json"
                output = "risk-test-plan.json"
            })
        }
        # The artifact is produced by the run; only its record of what was left
        # out is damaged, which must not read as "nothing was left out".
        $null = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage $stage `
            -Config $config `
            -Policy $policy `
            -RunRoot $runRoot `
            -RepositoryRoot $script:Root `
            -RunId "run-stage-broken-coverage"
        Set-Content -LiteralPath (Join-Path $stageDirectory "risk-test-plan.json.coverage.json") `
            -Value "{ this is not json" -Encoding utf8

        $stageResult = & (Join-Path $script:Root "scripts/Invoke-Stage.ps1") `
            -Stage $stage `
            -Config $config `
            -Policy $policy `
            -RunRoot $runRoot `
            -RepositoryRoot $script:Root `
            -RunId "run-stage-broken-coverage" `
            -ReuseExistingArtifacts

        $stageResult.Status | Should -Be "blocked"
        $stageResult.BlockedReason | Should -Be "unresolved_prerequisites"
    }
}

Describe "A run does not walk past work it wrote down as undone" {
    BeforeAll {
        function script:New-DeferralWorkflow {
            param([hashtable]$Approval = $null)
            $stage = [ordered]@{
                id = "test-planning"
                type = "sequential"
                agents = @([pscustomobject]@{
                    id = "risk-test-planner"
                    prompt = "prompts/planning/risk-test-planner.md"
                    schema = "schemas/planning/risk-test-plan.schema.json"
                    output = "risk-test-plan.json"
                })
            }
            if ($null -ne $Approval) { $stage["approval"] = [pscustomobject]$Approval }
            return [pscustomobject]@{
                name = "deferral-workflow"
                version = 1
                stages = @([pscustomobject]$stage)
            }
        }

        function script:Invoke-DeferralWorkflow {
            param(
                [Parameter(Mandatory)][string]$Behaviour,
                [Parameter(Mandatory)][string]$RunRoot,
                [hashtable]$Approval = $null,
                [int]$MaxStageIterations = 2
            )
            $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
            $config = Set-ResolvedTestAiProfile -Config $config
            $config.ai.provider = "command"
            $config.ai.command = "node $script:Root/tests/fixtures/deferral-provider.mjs $Behaviour"
            $config.runtime.agent_schema_retries = 2
            $config.runtime.max_stage_iterations = $MaxStageIterations
            $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
            New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
            return & (Join-Path $script:Root "scripts/Invoke-Workflow.ps1") `
                -Workflow (New-DeferralWorkflow -Approval $Approval) `
                -Config $config `
                -Policy $policy `
                -RepositoryRoot $script:Root `
                -RunRoot $RunRoot `
                -RunId "run-deferral-workflow"
        }
    }

    It "repeats the stage with a full budget instead of stopping for want of a return target" {
        # A stage with nothing to hand the work back to used to stop the run the
        # moment it asked for a revision. The work that was left out belongs to
        # this stage, so this stage is the one that does it.
        $runRoot = Join-Path $TestDrive "workflow-repeats"
        $state = Invoke-DeferralWorkflow -Behaviour "declaresThenCovers" -RunRoot $runRoot

        [string]$state.status | Should -Be "completed"
        $stageState = @($state.stages | Where-Object { $_.id -eq "test-planning" })[0]
        [int]$stageState.iteration | Should -Be 2
        [string]$stageState.status | Should -Be "completed"
        # The second attempt is the whole answer.
        $final = Get-Content -LiteralPath (
            Join-Path $runRoot "test-planning/iteration-2/risk-test-plan.json") -Raw |
            ConvertFrom-Json -Depth 40
        @($final.riskScenarios).Count | Should -Be 3
        (Get-QaFoundryPropertyNames -InputObject $final) -contains "deferrals" | Should -BeFalse
    }

    It "stops the run rather than deliver work it never did" {
        $runRoot = Join-Path $TestDrive "workflow-blocks"
        $state = Invoke-DeferralWorkflow -Behaviour "declares" -RunRoot $runRoot `
            -MaxStageIterations 2

        [string]$state.status | Should -Be "blocked"
        $stageState = @($state.stages | Where-Object { $_.id -eq "test-planning" })[0]
        [int]$stageState.iteration | Should -Be 2
        [string]$stageState.status | Should -Be "blocked"
    }

    It "does not let 'proceed on exhaustion' publish work that was never done" {
        # The setting exists so a run is not thrown away over reviewers who never
        # agreed about work that exists. Missing work is not a disagreement, and
        # there is nothing to publish, so the setting must not reach it.
        $runRoot = Join-Path $TestDrive "workflow-no-proceed"
        $state = Invoke-DeferralWorkflow -Behaviour "declares" -RunRoot $runRoot `
            -Approval @{ max_iterations = 1; on_exhaustion = "proceed" }

        [string]$state.status | Should -Be "blocked"
        $stageState = @($state.stages | Where-Object { $_.id -eq "test-planning" })[0]
        [string]$stageState.status | Should -Not -Be "approved_with_dissent"
        [string]$stageState.status | Should -Be "blocked"
    }
}

Describe "What every call to a provider cost" {    # The ledger is the only account the run keeps of its own cost, and two kinds
    # of call were missing from it. A shortening call is a second call against
    # the same attempt, so an artifact that needed one repair cost two calls and
    # reported one; and a provider failure that is neither a timeout nor a
    # passing fault was rethrown before anything was written, so the calls that
    # ended a run were exactly the ones absent from the account of it.
    function script:Invoke-AccountedAgent {
        param(
            [string]$Mode = "reports",
            [Parameter(Mandatory)][string]$OutputPath
        )
        $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
        $config = Set-ResolvedTestAiProfile -Config $config
        $config.ai.provider = "command"
        $config.ai.command = "node $script:Root/tests/fixtures/accounting-provider.mjs $Mode"
        $config.runtime.agent_schema_retries = 0
        return & (Join-Path $script:Root "scripts/Invoke-Agent.ps1") `
            -AgentId "framework-implementation" `
            -StageId "implementation" `
            -RunId "run-accounting-test" `
            -PromptPath (Join-Path $script:Root "prompts/sdlc/implementation-engineering.md") `
            -ContextPaths @() `
            -OutputPath $OutputPath `
            -SchemaPath (Join-Path $script:Root "schemas/implementation/implementation-result.schema.json") `
            -Config $config
    }

    function script:Get-CallRecords {
        param([Parameter(Mandatory)][string]$OutputPath)
        return @(Get-ChildItem -Path (Split-Path $OutputPath -Parent) `
                -Filter "*.provider-metadata.json" |
            Sort-Object Name |
            ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json -Depth 20 })
    }

    It "records the token counts the provider reported and then removes them" {
        $output = Join-Path $TestDrive "accounted/implementation-result.json"
        $null = Invoke-AccountedAgent -OutputPath $output

        $records = @(Get-CallRecords -OutputPath $output)
        $records.Count | Should -Be 1
        $records[0].status | Should -Be "answered"
        $records[0].purpose | Should -Be "artifact"
        $records[0].usage.source | Should -Be "provider"
        $records[0].usage.inputTokens | Should -Be 1234
        $records[0].usage.outputTokens | Should -Be 56
        # Measured sizes are always there; the counts are what only the provider
        # can supply.
        $records[0].request.bytes | Should -BeGreaterThan 0

        # The sidecar is consumed once. Left behind it would be read back as
        # context by every later agent in the stage, and a resumed run reusing
        # the same attempt path would credit these counts to a different call.
        @(Get-ChildItem -Path (Split-Path $output -Parent) -Filter "*.usage.json").Count |
            Should -Be 0
    }

    It "records a call whose provider left no counts as measured sizes only" {
        $output = Join-Path $TestDrive "accounted-silent/implementation-result.json"
        $null = Invoke-AccountedAgent -Mode "silent" -OutputPath $output

        $records = @(Get-CallRecords -OutputPath $output)
        $records.Count | Should -Be 1
        # Null, not zero and not an estimate: a guess written where a measurement
        # goes cannot afterwards be told apart from one.
        $records[0].usage | Should -BeNullOrEmpty
        $records[0].request.bytes | Should -BeGreaterThan 0
    }

    It "records the shortening call as well as the answer it corrected" {
        $output = Join-Path $TestDrive "accounted-repair/implementation-result.json"
        $null = Invoke-AccountedAgent -Mode "repair" -OutputPath $output

        $records = @(Get-CallRecords -OutputPath $output)
        $records.Count | Should -Be 2
        @($records | ForEach-Object { [string]$_.purpose }) |
            Should -Be @("artifact", "field_repair")
        @($records | ForEach-Object { [string]$_.status }) |
            Should -Be @("answered", "answered")
        # Two calls, two records, and one identity each: summing the ledger must
        # not double-count the repair as another attempt at the artifact.
        @($records | ForEach-Object { [string]$_.id } | Sort-Object -Unique).Count |
            Should -Be 2
        @(Get-ChildItem -Path (Split-Path $output -Parent) -Filter "*.usage.json").Count |
            Should -Be 0
    }

    It "records the call that ended the run" {
        $output = Join-Path $TestDrive "accounted-failed/implementation-result.json"
        { Invoke-AccountedAgent -Mode "permanent" -OutputPath $output } |
            Should -Throw "*401*"

        $records = @(Get-CallRecords -OutputPath $output)
        $records.Count | Should -Be 1
        $records[0].status | Should -Be "failed"
        $records[0].error.message | Should -Match "401"
        # A failed call still spent whatever the provider charged for it.
        $records[0].usage.inputTokens | Should -Be 1234
        @(Get-ChildItem -Path (Split-Path $output -Parent) -Filter "*.usage.json").Count |
            Should -Be 0
    }
}

Describe "Queueing the implementation of created work" {    BeforeAll {
        function script:New-QueueFixture {
            param([object[]]$PlanItems, [object[]]$ResultActions, [bool]$ResultDryRun = $false)

            $repository = Join-Path $TestDrive ("queue-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
            New-Item -ItemType Directory -Path $repository -Force | Out-Null
            $planPath = Join-Path $repository "work-item-plan.json"
            [ordered]@{ outcome = "proposed"; items = $PlanItems } | ConvertTo-Json -Depth 20 |
                Set-Content -Path $planPath -Encoding utf8
            $resultPath = Join-Path $repository "action-result.json"
            [ordered]@{
                runId = "run-queue"; stageId = "create-work-items"; handler = "create_work_items"
                status = "completed"; dryRun = $ResultDryRun; actions = $ResultActions
            } | ConvertTo-Json -Depth 20 | Set-Content -Path $resultPath -Encoding utf8
            return [pscustomobject]@{
                Repository = $repository; PlanPath = $planPath; ResultPath = $resultPath
            }
        }

        function script:New-QueueConfig {
            $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
            $config.ci.azure_devops.organization_url = "https://dev.azure.com/example"
            $config.ci.azure_devops.project = "product"
            $config.idempotency.enabled = $false
            return $config
        }

        function script:Invoke-QueueRun {
            param([object]$Fixture, [string]$RunId, [AllowNull()][object]$Config = $null)

            if ($null -eq $Config) { $Config = New-QueueConfig }
            return & (Join-Path $script:Root "scripts/writers/New-PipelineRuns.ps1") `
                -PlanPath $Fixture.PlanPath -WorkItemResultPath $Fixture.ResultPath `
                -PipelineName "SDLC Foundry - Implement Work Item" -Config $Config `
                -RepositoryRoot $Fixture.Repository -RunId $RunId -Branch "develop" `
                -ActionEnvironment @{ AZURE_DEVOPS_TOKEN = "test-token" }
        }

        # One Azure DevOps stand-in for every test: it answers the pipeline lookup, the work item
        # read that decides whether the hand-off already happened, the tag write that records it,
        # and the run creation itself.
        function script:Set-QueueAdoMock {
            param(
                [string[]]$ExistingTags = @(),
                # Simulates another run claiming the same work item between this
                # run's read and its write: the conditional write is refused, and
                # by the time this run looks again the marker is there.
                [switch]$ClaimedByAnother,
                # How queueing fails, when the test is about what happens to the
                # claim afterwards. 'refused' is an answer from Azure DevOps;
                # 'lost' is no answer at all; 'http-refused' is the answer shape
                # PowerShell 7 actually throws for a 4xx.
                [ValidateSet("", "refused", "http-refused", "lost")][string]$QueueFailure = "",
                # The builds Azure DevOps reports for the work item, used when a
                # test is about settling a claim whose run has gone.
                [object[]]$ExistingBuilds = @(),
                # Makes the builds question unanswerable, so a claim must be left
                # alone rather than taken over on a guess.
                [switch]$BuildLookupFails
            )

            $global:QueuedBodies = [System.Collections.Generic.List[string]]::new()
            $global:TagPatches = [System.Collections.Generic.List[string]]::new()
            $global:RequestUris = [System.Collections.Generic.List[string]]::new()
            $global:RequestOrder = [System.Collections.Generic.List[string]]::new()
            $global:RequestAuthorizations = [System.Collections.Generic.List[string]]::new()
            $global:MarkerTags = ($ExistingTags -join "; ")
            $global:MarkerRevision = 7
            $global:ClaimedByAnother = [bool]$ClaimedByAnother
            $global:QueueFailure = $QueueFailure
            $global:ExistingBuilds = @($ExistingBuilds)
            $global:BuildLookupFails = [bool]$BuildLookupFails
            Mock Invoke-RestMethod {
                param($Uri, $Method, $Body, $Headers)
                $global:RequestUris.Add([string]$Uri)
                $global:RequestOrder.Add("$Method|$Uri")
                if ($null -ne $Headers -and $Headers.ContainsKey("Authorization")) {
                    $global:RequestAuthorizations.Add([string]$Headers["Authorization"])
                }
                # Matched as regex, not -like: '?' is a single-character wildcard there, so a
                # pattern meant for the pipeline list also swallows '/pipelines/77/runs'.
                if ($Uri -match "/_apis/build/builds") {
                    if ($global:BuildLookupFails) {
                        throw "TF400813: The build list could not be read."
                    }
                    # A question about one build by id, which is how an election
                    # tag's owner is checked, answers with that build alone.
                    if ($Uri -match "/_apis/build/builds/(\d+)") {
                        $wanted = [string]$Matches[1]
                        $found = @($global:ExistingBuilds |
                            Where-Object { [string]$_.id -eq $wanted })
                        if ($found.Count -eq 0) {
                            throw [Microsoft.PowerShell.Commands.HttpResponseException]::new(
                                "404 (Not Found)",
                                [System.Net.Http.HttpResponseMessage]::new(
                                    [System.Net.HttpStatusCode]::NotFound))
                        }
                        return $found[0]
                    }
                    return [pscustomobject]@{ value = @($global:ExistingBuilds) }
                }
                if ($Uri -match "/_apis/wit/workitems/") {
                    if ($Method -eq "Patch") {
                        $global:TagPatches.Add([string]$Body)
                        $operations = @([string]$Body | ConvertFrom-Json -Depth 20)
                        $test = @($operations | Where-Object { $_.op -eq "test" }) |
                            Select-Object -First 1
                        if ($global:ClaimedByAnother) {
                            # The competitor's write landed first, so this item is
                            # no longer at the revision this write was built on.
                            $global:ClaimedByAnother = $false
                            $global:MarkerTags = (@($global:MarkerTags,
                                "sdlc-foundry-implementation-queued") |
                                Where-Object { $_ } ) -join "; "
                            $global:MarkerRevision++
                            throw "VS402625: The work item has been changed by someone else."
                        }
                        if ($null -ne $test -and [int]$test.value -ne $global:MarkerRevision) {
                            throw "VS402625: The work item has been changed by someone else."
                        }
                        $written = @($operations |
                            Where-Object { $_.path -eq "/fields/System.Tags" }) |
                            Select-Object -First 1
                        $global:MarkerTags = [string]$written.value
                        $global:MarkerRevision++
                        return [pscustomobject]@{ id = 4002 }
                    }
                    return [pscustomobject]@{
                        id = 4002
                        rev = $global:MarkerRevision
                        fields = [pscustomobject]@{ "System.Tags" = $global:MarkerTags }
                    }
                }
                if ($Uri -match "/_apis/pipelines/\d+/runs") {
                    if ($global:QueueFailure -eq "refused") {
                        throw "The pipeline was refused: 403 Forbidden."
                    }
                    if ($global:QueueFailure -eq "http-refused") {
                        # The shape PowerShell 7 raises for a non-2xx response.
                        # It derives from HttpRequestException, which is exactly
                        # why the refusal has to be read off the response.
                        $message = [System.Net.Http.HttpResponseMessage]::new(
                            [System.Net.HttpStatusCode]::Forbidden)
                        throw [Microsoft.PowerShell.Commands.HttpResponseException]::new(
                            "Response status code does not indicate success: 403 (Forbidden).",
                            $message)
                    }
                    if ($global:QueueFailure -eq "lost") {
                        throw [System.Net.Http.HttpRequestException]::new(
                            "The connection was closed before an answer arrived.")
                    }
                    $global:QueuedBodies.Add([string]$Body)
                    return [pscustomobject]@{ id = 909 }
                }
                return [pscustomobject]@{ value = @(
                    [pscustomobject]@{ id = 77; name = "SDLC Foundry - Implement Work Item" }
                ) }
            }
        }

        # Claims carry the run that made them and the moment it did, so a test can
        # place one at any age without waiting for it.
        function script:New-AgedClaimTag {
            param([string]$RunIdentifier = "run-earlier", [int]$AgeSeconds = 0)

            $stamp = [DateTimeOffset]::UtcNow.AddSeconds(-$AgeSeconds).ToUnixTimeSeconds()
            return "sdlc-foundry-implementation-claim.$RunIdentifier.$stamp"
        }
    }

    It "starts one implementation run per task and leaves the backlog item alone" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "pbi-1"; type = "backlog_item"; title = "Parent" },
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "pbi-1"; status = "executed"; externalId = "4001" },
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue"

        # A backlog item states the outcome its tasks deliver. Implementing it as well as its tasks
        # would open two pull requests for one piece of work.
        @($result.actions.sourceRef) | Should -Be @("task-1")
        $result.actions[0].status | Should -Be "executed"
        $result.actions[0].externalId | Should -Be "909"
        $global:QueuedBodies.Count | Should -Be 1
        $sent = $global:QueuedBodies[0] | ConvertFrom-Json -Depth 20
        $sent.templateParameters.workItemId | Should -Be "4002"
        $sent.resources.repositories.self.refName | Should -Be "refs/heads/develop"
    }

    It "records the hand-off on the work item so a later checkout can see it" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @("triage")

        $null = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-marker"

        # Two writes, and the order of them is the point. The first says "a run is
        # trying to start this", which is all that is true before the run exists;
        # the second says "a run exists", which is the record a later checkout acts on.
        $global:TagPatches.Count | Should -Be 2
        $claim = @($global:TagPatches[0] | ConvertFrom-Json -Depth 20)
        # The write is conditional on the revision that was read. Without that, a
        # tag a person added in between is overwritten rather than noticed.
        $claim[0].op | Should -Be "test"
        $claim[0].path | Should -Be "/rev"
        $claim[0].value | Should -Be 7
        $claim[1].path | Should -Be "/fields/System.Tags"
        # The tags already on the item survive: the claim is added, not written over them.
        $claim[1].value | Should -Match "^triage; sdlc-foundry-implementation-claim\."
        # The claim names the run that made it, so a later run can tell whose it is.
        $claim[1].value | Should -Match "run-queue-marker"

        $marker = @($global:TagPatches[1] | ConvertFrom-Json -Depth 20)
        $marker[0].value | Should -Be 8
        $marker[1].value | Should -Be "triage; sdlc-foundry-implementation-queued"
        # The claim is not left behind next to the marker: it has served its purpose.
        $global:MarkerTags | Should -Not -Match "sdlc-foundry-implementation-claim"
    }

    It "claims the work item before queueing, so a second run finds it taken" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock

        $null = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-claim"

        # Reading the marker, queueing, and only then writing it leaves a window
        # in which two runs both read no marker and both queue the same task.
        # The claim has to be written before the run exists to close it.
        $claimedAt = @($global:RequestOrder).IndexOf(
            @($global:RequestOrder | Where-Object { $_ -match "^Patch\|.*/_apis/wit/workitems/" })[0])
        $queuedAt = @($global:RequestOrder).IndexOf(
            @($global:RequestOrder | Where-Object { $_ -match "/_apis/pipelines/\d+/runs" })[0])
        $claimedAt | Should -BeGreaterThan -1
        $claimedAt | Should -BeLessThan $queuedAt
        $global:QueuedBodies.Count | Should -Be 1
    }

    It "stands down when another run claims the same work item first" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ClaimedByAnother

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-lost-race"

        # Losing the race is not an error: the task is being implemented, just by
        # someone else. Queueing anyway would open the second pull request the
        # claim exists to prevent.
        $result.actions[0].status | Should -Be "duplicate"
        $global:QueuedBodies.Count | Should -Be 0
    }

    It "releases its claim when Azure DevOps refuses to queue the run" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -QueueFailure "refused"

        { Invoke-QueueRun -Fixture $fixture -RunId "run-queue-refused" } | Should -Throw

        # A refusal is an answer: no run exists, so the task must stay
        # implementable. A claim held after a refusal strands it forever.
        $global:MarkerTags | Should -Not -Match "sdlc-foundry-implementation"
    }

    It "reads a refusal off the response rather than off the exception type" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -QueueFailure "http-refused"

        { Invoke-QueueRun -Fixture $fixture -RunId "run-queue-http-refused" } | Should -Throw

        # PowerShell raises a 403 as HttpResponseException, which derives from
        # HttpRequestException - the same type a dropped connection raises. A
        # check that looked at the type alone would read every plain refusal as a
        # lost answer and hold the claim on a task nothing is implementing.
        $global:MarkerTags | Should -Not -Match "sdlc-foundry-implementation"
    }

    It "keeps its claim when queueing gets no answer at all" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -QueueFailure "lost"

        { Invoke-QueueRun -Fixture $fixture -RunId "run-queue-lost" } |
            Should -Throw "*may still have started it*"

        # A dropped connection is not a refusal. The run may exist, so releasing
        # the claim here is what turns one lost response into two implementations
        # of the same task. What is left behind is a claim, not the marker: it
        # expires, and the next run settles it without anyone being asked to.
        $global:MarkerTags | Should -Match "sdlc-foundry-implementation-claim"
        $global:MarkerTags | Should -Not -Match "sdlc-foundry-implementation-queued"
    }

    It "waits for a claim that is younger than a run takes to start" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @((New-AgedClaimTag -RunIdentifier "run-a" -AgeSeconds 60))

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-fresh-claim"

        # The run holding the claim is still alive as far as anything here can
        # tell. Taking the task from it would queue the second implementation.
        $result.actions[0].status | Should -Be "duplicate"
        $result.actions[0].summary | Should -Match "run-a"
        $global:QueuedBodies.Count | Should -Be 0
        @($global:RequestUris | Where-Object { $_ -match "/_apis/build/builds" }).Count |
            Should -Be 0
    }

    It "settles an expired claim against the run Azure DevOps actually holds" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @(
            (New-AgedClaimTag -RunIdentifier "run-gone" -AgeSeconds 4000)
        ) -ExistingBuilds @(
            [pscustomobject]@{ id = 555; queueTime = [DateTimeOffset]::UtcNow.ToString("o") }
        )

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-settle"

        # The claiming run died after queueing but before recording it. The run it
        # started is still there, so the honest reading is that the hand-off
        # happened - and the claim becomes the marker that says so.
        $result.actions[0].status | Should -Be "duplicate"
        $global:QueuedBodies.Count | Should -Be 0
        $global:MarkerTags | Should -Match "sdlc-foundry-implementation-queued"
        $global:MarkerTags | Should -Not -Match "sdlc-foundry-implementation-claim"
    }

    It "takes over an expired claim whose run never started anything" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @(
            "triage", (New-AgedClaimTag -RunIdentifier "run-gone" -AgeSeconds 4000)
        )

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-takeover"

        # Nothing was ever queued under that claim, so the task is unimplemented
        # and no one is coming back for it. Leaving it would mean a crash costs a
        # task permanently, and clearing it by hand is the manual step this whole
        # system exists to remove.
        $result.actions[0].status | Should -Be "executed"
        $global:QueuedBodies.Count | Should -Be 1
        $global:MarkerTags | Should -Be "triage; sdlc-foundry-implementation-queued"
    }

    It "leaves an expired claim alone when it cannot tell whether a run exists" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @(
            (New-AgedClaimTag -RunIdentifier "run-gone" -AgeSeconds 4000)
        ) -BuildLookupFails

        { Invoke-QueueRun -Fixture $fixture -RunId "run-queue-unknown" } |
            Should -Throw "*could not be read*"

        # Taking a claim over is only safe because the question behind it was
        # answered. Guessing at an unanswered one is how the duplicate this
        # mechanism exists to prevent gets created.
        $global:QueuedBodies.Count | Should -Be 0
        $global:MarkerTags | Should -Match "sdlc-foundry-implementation-claim"
    }

    It "names the hand-off it made so the started run can recognise a duplicate" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-handoff"

        $sent = $global:QueuedBodies[0] | ConvertFrom-Json -Depth 20
        # The started run is told which hand-off it is, not merely which work item
        # it concerns: two runs about one item are indistinguishable without it.
        $sent.templateParameters.handoffKey | Should -Be $result.actions[0].idempotencyKey
        $sent.templateParameters.handoffKey | Should -Not -BeNullOrEmpty
    }

    It "does not queue a second run for a task an earlier run already handed on" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @("sdlc-foundry-implementation-queued")

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-duplicate"

        @($result.actions.status) | Should -Be @("duplicate")
        $global:QueuedBodies.Count | Should -Be 0
        $global:TagPatches.Count | Should -Be 0
    }

    It "leaves a task alone while the run implementing it is still going" {
        # The marker is a statement about a build, so it is read against that
        # build. One that has not finished is nobody else's to take.
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @("sdlc-foundry-implementation-queued") -ExistingBuilds @(
            [pscustomobject]@{
                id = 555; queueTime = [DateTimeOffset]::UtcNow.ToString("o")
                status = "inProgress"; result = $null
            }
        )

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-running"

        @($result.actions.status) | Should -Be @("duplicate")
        [string]$result.actions[0].summary | Should -Match "still inprogress"
        $global:QueuedBodies.Count | Should -Be 0
    }

    It "picks up a task again after the run implementing it failed" {
        # The failure this catches: the child pipeline died, and both the marker
        # and the tag its build wrote to elect itself stayed on the work item. No
        # later run would touch it, so the task was stranded for good - on an
        # unattended pipeline, until a person happened to look.
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @(
            "triage", "sdlc-foundry-implementation-queued", "sdlc-foundry-implementing-555"
        ) -ExistingBuilds @(
            [pscustomobject]@{
                id = 555; queueTime = [DateTimeOffset]::UtcNow.AddHours(-2).ToString("o")
                status = "completed"; result = "failed"
            }
        )

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-takeover"

        @($result.actions.status) | Should -Be @("executed")
        $global:QueuedBodies.Count | Should -Be 1
        # The dead build's election tag goes with the marker. Leaving it would
        # let this run queue a build the pipeline template then refuses, which is
        # the same deadlock one step further along.
        $global:MarkerTags | Should -Not -Match "sdlc-foundry-implementing-555"
        $global:MarkerTags | Should -Match "sdlc-foundry-implementation-queued"
        # Whatever a person put on the item is still there.
        $global:MarkerTags | Should -Match "triage"
    }

    It "leaves a task alone while any run carrying its tag is still going" {
        # A task re-tried after a failure has both builds under its tag, and no
        # election tag says which one holds it. Judging by any single one of them
        # would take the task away from the run currently doing it.
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @("sdlc-foundry-implementation-queued") -ExistingBuilds @(
            [pscustomobject]@{
                id = 555; queueTime = [DateTimeOffset]::UtcNow.AddHours(-2).ToString("o")
                status = "completed"; result = "failed"
            },
            [pscustomobject]@{
                id = 556; queueTime = [DateTimeOffset]::UtcNow.ToString("o")
                status = "inProgress"; result = $null
            }
        )

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-newest"

        @($result.actions.status) | Should -Be @("duplicate")
        $global:QueuedBodies.Count | Should -Be 0
    }

    It "does not free a task because a duplicate the election turned away has failed" {
        # The build that holds the task is the one its election tag names, not
        # the newest one carrying its tag. A duplicate that lost the election
        # fails within seconds, so it is always the newer of the two, while the
        # run actually implementing the task carries on for an hour. Reading the
        # newest would clear a live owner's tags and let a second implementation
        # start beside the first.
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @(
            "sdlc-foundry-implementation-queued", "sdlc-foundry-implementing-555"
        ) -ExistingBuilds @(
            [pscustomobject]@{
                id = 555; queueTime = [DateTimeOffset]::UtcNow.AddMinutes(-40).ToString("o")
                status = "inProgress"; result = $null
            },
            [pscustomobject]@{
                id = 556; queueTime = [DateTimeOffset]::UtcNow.ToString("o")
                status = "completed"; result = "failed"
            }
        )

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-owner-alive"

        @($result.actions.status) | Should -Be @("duplicate")
        [string]$result.actions[0].summary | Should -Match "555"
        $global:QueuedBodies.Count | Should -Be 0
        # The live owner keeps its claim on the task.
        $global:MarkerTags | Should -Match "sdlc-foundry-implementing-555"
    }

    It "frees a task whose owning build Azure DevOps no longer has" {
        # A build deleted by retention is not a build that is running. The task
        # would otherwise be held by a tag naming something that no longer
        # exists, which nothing could ever clear.
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @(
            "sdlc-foundry-implementation-queued", "sdlc-foundry-implementing-777"
        ) -ExistingBuilds @()

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-gone-owner"

        @($result.actions.status) | Should -Be @("executed")
        $global:MarkerTags | Should -Not -Match "sdlc-foundry-implementing-777"
    }

    It "does not take a marked task over on a question Azure DevOps could not answer" {
        # An unreadable answer is not the same as a dead run. Taking the task
        # over on one is how the duplicate pull request this all exists to
        # prevent would be created.
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @("sdlc-foundry-implementation-queued") -BuildLookupFails

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-unreadable"

        @($result.actions.status) | Should -Be @("duplicate")
        [string]$result.actions[0].summary | Should -Match "could not be read"
        $global:QueuedBodies.Count | Should -Be 0
        $global:TagPatches.Count | Should -Be 0
    }

    It "implements a task that was filed by an earlier run but never handed on" {        # The failure this catches: creation succeeded, queueing did not. Re-running reports the
        # task as a duplicate, and treating that as "already handed on" would strand it forever.
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "duplicate"; externalId = "4002" }
        )
        Set-QueueAdoMock

        $result = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-recovered"

        @($result.actions.status) | Should -Be @("executed")
        $global:QueuedBodies.Count | Should -Be 1
        ($global:QueuedBodies[0] | ConvertFrom-Json -Depth 20).templateParameters.workItemId |
            Should -Be "4002"
    }

    It "rehearses instead of starting anything when the work items were only rehearsed" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        ) -ResultDryRun $true
        Mock Invoke-RestMethod { throw "A rehearsal must not reach Azure DevOps." }

        $result = & (Join-Path $script:Root "scripts/writers/New-PipelineRuns.ps1") `
            -PlanPath $fixture.PlanPath -WorkItemResultPath $fixture.ResultPath `
            -PipelineName "SDLC Foundry - Implement Work Item" -Config (New-QueueConfig) `
            -RepositoryRoot $fixture.Repository -RunId "run-queue-dry" -Branch "develop"

        $result.dryRun | Should -BeTrue
        @($result.actions.status) | Should -Be @("dry_run")
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It "reads and writes the marker in the project that tracks the work, not the one that builds it" {
        # The marker lives on a work item. Work items belong to the work-tracking
        # project, which is not always the project the pipelines live in, and
        # reading it through the CI settings returns 404 there - so the marker
        # reads as absent and every run queues the same implementation again.
        $config = New-QueueConfig
        $config.work_tracking.azure_devops.organization_url = "https://dev.azure.com/tracking"
        $config.work_tracking.azure_devops.project = "delivery"
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock

        $null = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-marker-project" -Config $config

        $workItemUris = @($global:RequestUris | Where-Object { $_ -match "/_apis/wit/workitems/" })
        $workItemUris.Count | Should -BeGreaterThan 0
        foreach ($uri in $workItemUris) {
            $uri | Should -BeLike "https://dev.azure.com/tracking/delivery/*"
        }
        # The pipeline itself is still started where the pipelines are.
        @($global:RequestUris | Where-Object { $_ -match "/_apis/pipelines/" }) |
            ForEach-Object { $_ | Should -BeLike "https://dev.azure.com/example/product/*" }
    }

    It "asks for the runs where the pipelines live, not where the work is tracked" {
        # Settling a claim is a question about builds, and builds belong to the CI
        # project. Asking the work-tracking project returns nothing, which reads
        # as "no run exists" and re-queues an implementation that already started.
        $config = New-QueueConfig
        $config.work_tracking.azure_devops.organization_url = "https://dev.azure.com/tracking"
        $config.work_tracking.azure_devops.project = "delivery"
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock -ExistingTags @(
            (New-AgedClaimTag -RunIdentifier "run-gone" -AgeSeconds 4000)
        )

        $null = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-settle-project" -Config $config

        $buildUris = @($global:RequestUris | Where-Object { $_ -match "/_apis/build/builds" })
        $buildUris.Count | Should -Be 1
        $buildUris[0] | Should -BeLike "https://dev.azure.com/example/product/*"
        # The question asked is the one the started run answers about itself.
        $buildUris[0] | Should -BeLike "*tagFilters=work-item-4002*"
    }

    It "sends a pipeline access token as a bearer token rather than encoding it as a password" {
        # Basic-encoding a bearer token does not fail loudly: Azure DevOps answers
        # a sign-in page with a 200 on it, and the run reads that as a work item
        # that does not exist.
        $config = New-QueueConfig
        $config.work_tracking.azure_devops.auth_scheme = "bearer"
        $config.ci.azure_devops.auth_scheme = "bearer"
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Set-QueueAdoMock

        $null = Invoke-QueueRun -Fixture $fixture -RunId "run-queue-bearer" -Config $config

        @($global:RequestAuthorizations).Count | Should -BeGreaterThan 0
        foreach ($authorization in @($global:RequestAuthorizations)) {
            $authorization | Should -Be "Bearer test-token"
        }
    }

    It "refuses to queue from a record that was not the work item creation" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @()
        $foreign = Get-Content -LiteralPath $fixture.ResultPath -Raw | ConvertFrom-Json -Depth 20
        $foreign.handler = "quality_suite"
        $foreign | ConvertTo-Json -Depth 20 | Set-Content -Path $fixture.ResultPath -Encoding utf8

        { Invoke-QueueRun -Fixture $fixture -RunId "run-queue-foreign" } |
            Should -Throw "*was written by handler 'quality_suite'*"
    }

    It "refuses to queue a pipeline that was never registered" {
        $fixture = New-QueueFixture -PlanItems @(
            [ordered]@{ sourceRef = "task-1"; type = "task"; title = "Child"; parentRef = "pbi-1" }
        ) -ResultActions @(
            [ordered]@{ sourceRef = "task-1"; status = "executed"; externalId = "4002" }
        )
        Mock Invoke-RestMethod {
            param($Uri)
            if ($Uri -match "/_apis/wit/workitems/") {
                return [pscustomobject]@{ id = 4002; fields = [pscustomobject]@{ "System.Tags" = "" } }
            }
            return [pscustomobject]@{ value = @() }
        }

        { Invoke-QueueRun -Fixture $fixture -RunId "run-queue-missing" } |
            Should -Throw "*was never registered*"
    }

    It "stops the hand-off when policy does not allow this run to start pipelines" {
        $runRoot = Join-Path $TestDrive ("queue-policy-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
        New-Item -ItemType Directory -Path (Join-Path $runRoot "queue") -Force | Out-Null
        [ordered]@{
            updatedAt = ""; status = "running"
            stages = @([ordered]@{ id = "plan-review"; status = "approved" })
        } | ConvertTo-Json -Depth 20 | Set-Content -Path (Join-Path $runRoot "workflow-state.json") -Encoding utf8

        $policy = Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root
        if (@(Get-QaFoundryPropertyNames -InputObject $policy) -contains "ci") {
            $policy.ci.allow_pipeline_queue = $false
        }
        $stage = [pscustomobject]@{
            id = "queue"
            assurance = [pscustomobject]@{ approved_by = "plan-review" }
            action = [pscustomobject]@{
                handler = "queue_pipeline"
                pipeline = "SDLC Foundry - Implement Work Item"
                output = "action-result.json"
            }
        }

        {
            & (Join-Path $script:Root "scripts/Invoke-DeterministicAction.ps1") `
                -Stage $stage -Config (New-QueueConfig) -Policy $policy -RunRoot $runRoot `
                -RepositoryRoot $script:Root -RunId "run-queue-policy" `
                -OutputPath (Join-Path $runRoot "queue/action-result.json")
        } | Should -Throw "*Policy denies starting other pipelines*"
    }
}

Describe "A rehearsed change set never reaches a repository" {
    # A rehearsed materialisation resolves nothing and carries no lock file, so
    # the framework it describes has never been shown to install. Reading one in
    # a rehearsal is the point of a rehearsal; committing one would put an
    # unresolvable framework into a repository with an approval attached to it.
    BeforeAll {
        function script:New-RehearsedApplyFixture {
            param([bool]$DeliveryDryRun)

            $runRoot = Join-Path $TestDrive ("rehearsed-apply-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
            New-Item -ItemType Directory -Path (Join-Path $runRoot "materialise") -Force | Out-Null
            [ordered]@{
                updatedAt = ""; status = "running"
                stages = @([ordered]@{ id = "change-review"; status = "approved" })
            } | ConvertTo-Json -Depth 20 |
                Set-Content -Path (Join-Path $runRoot "workflow-state.json") -Encoding utf8

            [ordered]@{
                agentId = "change-materializer"; stageId = "materialise"; runId = "run-rehearsed"
                status = "completed"; summary = "Rehearsed."
                evidence = @(); assumptions = @(); unknowns = @()
                warnings = @("This change set was rehearsed.")
                details = [ordered]@{ dryRun = $true }
                outcome = "proposed"
                changes = @([ordered]@{
                    operation = "create"; path = "automation/package.json"
                    expectedSha256 = ""; content = "{}"
                    reason = "Rehearsal."; sourceRefs = @()
                })
            } | ConvertTo-Json -Depth 30 |
                Set-Content -Path (Join-Path $runRoot "materialise/change-set.json") -Encoding utf8

            $config = Import-QaFoundryYaml -Path $script:ConfigPath -Root $script:Root
            $config.delivery.dry_run = $DeliveryDryRun
            # Left off so the policy gates above this check cannot be what
            # refuses: this test is about the change set, not about permission.
            $config.delivery.apply_changes = $false
            return [pscustomobject]@{
                RunRoot = $runRoot
                Config = $config
                Policy = (Import-QaFoundryYaml -Path $script:PolicyPath -Root $script:Root)
                Stage = [pscustomobject]@{
                    id = "apply"
                    assurance = [pscustomobject]@{ approved_by = "change-review" }
                    action = [pscustomobject]@{
                        handler = "apply_change_set"
                        input = "change-set.json"
                        output = "action-result.json"
                    }
                }
            }
        }
    }

    It "refuses to apply a rehearsed change set in a run that is not a rehearsal" {
        # What makes this wrong is not the writing but where the writing ends up:
        # a run that pushes puts a framework nothing ever resolved in front of a
        # reviewer with an approval attached to it.
        $fixture = New-RehearsedApplyFixture -DeliveryDryRun $false
        $fixture.Config.delivery.push_branch = $true

        {
            & (Join-Path $script:Root "scripts/Invoke-DeterministicAction.ps1") `
                -Stage $fixture.Stage -Config $fixture.Config -Policy $fixture.Policy `
                -RunRoot $fixture.RunRoot -RepositoryRoot $script:Root -RunId "run-rehearsed" `
                -OutputPath (Join-Path $fixture.RunRoot "apply/action-result.json")
        } | Should -Throw "*rehearsed change set*"
    }

    It "refuses to apply a rehearsed change set to a run that opens a pull request" {
        # Pushing is not the only way content reaches a reviewer.
        $fixture = New-RehearsedApplyFixture -DeliveryDryRun $false
        $fixture.Config.delivery.push_branch = $false
        $fixture.Config.delivery.create_draft_pull_request = $true

        {
            & (Join-Path $script:Root "scripts/Invoke-DeterministicAction.ps1") `
                -Stage $fixture.Stage -Config $fixture.Config -Policy $fixture.Policy `
                -RunRoot $fixture.RunRoot -RepositoryRoot $script:Root -RunId "run-rehearsed" `
                -OutputPath (Join-Path $fixture.RunRoot "apply/action-result.json")
        } | Should -Throw "*rehearsed change set*"
    }

    It "lets a rehearsal read the change set its own rehearsal produced" {
        $fixture = New-RehearsedApplyFixture -DeliveryDryRun $true

        {
            & (Join-Path $script:Root "scripts/Invoke-DeterministicAction.ps1") `
                -Stage $fixture.Stage -Config $fixture.Config -Policy $fixture.Policy `
                -RunRoot $fixture.RunRoot -RepositoryRoot $script:Root -RunId "run-rehearsed" `
                -OutputPath (Join-Path $fixture.RunRoot "apply/action-result.json")
        } | Should -Not -Throw
    }

    It "refuses to publish a rehearsed change set even when nothing checked it first" {
        # The guard used to live only in the action dispatcher, which is not
        # where the writing happens. The bootstrap wrapper calls the writers
        # directly and so passed straight by it, which is what turns a guard into
        # a convention. The writer refuses on its own.
        $fixture = New-RehearsedApplyFixture -DeliveryDryRun $false
        $fixture.Config.delivery.apply_changes = $true
        $fixture.Config.delivery.push_branch = $true
        $fixture.Config.idempotency.enabled = $true

        {
            & (Join-Path $script:Root "scripts/writers/Publish-RepositoryDelivery.ps1") `
                -Config $fixture.Config -RepositoryRoot $script:Root -RunRoot $fixture.RunRoot `
                -RunId "run-rehearsed" -StageId "deliver" `
                -ChangeSetPath (Join-Path $fixture.RunRoot "materialise/change-set.json")
        } | Should -Throw "*rehearsed change set*"
    }

    It "lets a rehearsal deliver into a checkout nothing is published from" {
        # A rehearsal still writes the installation to the working tree - that is
        # the thing being rehearsed, and the installer's own demo depends on it.
        # Refusing here would make the rehearsal impossible to run at all.
        $fixture = New-RehearsedApplyFixture -DeliveryDryRun $false
        $fixture.Config.delivery.push_branch = $false
        $fixture.Config.delivery.create_draft_pull_request = $false

        $leaves = Test-QaFoundryDeliveryLeavesMachine -DeliveryConfig $fixture.Config.delivery
        $leaves | Should -BeFalse
        {
            & (Join-Path $script:Root "scripts/Invoke-DeterministicAction.ps1") `
                -Stage $fixture.Stage -Config $fixture.Config -Policy $fixture.Policy `
                -RunRoot $fixture.RunRoot -RepositoryRoot $script:Root -RunId "run-rehearsed" `
                -OutputPath (Join-Path $fixture.RunRoot "apply/action-result.json")
        } | Should -Not -Throw
    }
}

Describe 'UI maintenance instructions across the lifecycle' {
    It 'carries the same traceability and repair constraints to <Agent>' -ForEach @(
        @{ Agent='ui-test-planner'; Stage='test-planning'; Prompt='prompts/planning/ui-test-planner.md'; Schema='schemas/planning/ui-test-plan.schema.json' },
        @{ Agent='impact-quality-analyst'; Stage='impact-analysis'; Prompt='prompts/sdlc/impact-quality.md'; Schema='schemas/sdlc/analysis.schema.json' },
        @{ Agent='implementation-change-generator'; Stage='change-generation'; Prompt='prompts/sdlc/change-generator.md'; Schema='schemas/actions/change-set.schema.json' }
    ) {
        $config = Get-TestConfig
        $output = Join-Path $TestDrive "$Agent/result.json"
        New-Item -ItemType Directory -Path (Split-Path $output -Parent) -Force | Out-Null
        $null = & (Join-Path $script:Root 'scripts/Invoke-Agent.ps1') -AgentId $Agent -StageId $Stage `
            -RunId 'run-ui-maintenance' -PromptPath (Join-Path $script:Root $Prompt) -ContextPaths @() `
            -OutputPath $output -SchemaPath (Join-Path $script:Root $Schema) -Config $config -RepositoryRoot $script:Root
        $request = Get-Content "$output.attempt-1.request.md" -Raw
        $request | Should -Match '# Evidence-based UI automation maintenance'
        $request | Should -Match 'Compare BDD with runner-native tests'
        $request | Should -Match 'stable logical ID'
        $request | Should -Match 'Preserve the journey ID and\s+business assertions'
        $request | Should -Match 'Automation-only path trigger does not observe product changes'
        $request | Should -Match 'Missing credentials or a browser environment leave execution unverified'
        $request | Should -Match 'Do not claim that describing them implemented'
    }
}
