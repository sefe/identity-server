[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AgentId,
    [Parameter(Mandatory)][string]$StageId,
    [Parameter(Mandatory)][string]$RunId,
    [int]$StageIteration = 1,
    [int]$Attempt = 1,
    [string]$RequestPath
)

# The mock answers for ecosystems it must not have hard-coded knowledge of, so
# it asks the same adapters the runtime asks. Dot-sourced rather than inherited
# from the caller, because a script invoked with the call operator must not
# depend on what its caller happened to load.
. (Join-Path (Split-Path $PSScriptRoot -Parent) "Common.ps1")

$evidence = @(
    [ordered]@{
        source = if ($RequestPath) { $RequestPath } else { "mock-provider" }
        description = "Deterministic mock input envelope used for this result."
    }
)

# An artifact reaches the agent either inlined or referenced by path, and both
# forms carry the path in their heading. Matching the heading avoids guessing at
# a path that may contain characters a bare token match breaks on.
function Get-MockContextJson {
    param([Parameter(Mandatory)][string]$PathPattern)

    if ([string]::IsNullOrWhiteSpace($RequestPath) -or -not (Test-Path -LiteralPath $RequestPath)) {
        return $null
    }
    $requestText = Get-Content -LiteralPath $RequestPath -Raw
    $match = [regex]::Match($requestText,
        '(?m)^## Context(?: reference, not inlined)?: (?<path>.+' + $PathPattern + ')\s*$')
    if (-not $match.Success) {
        $match = [regex]::Match($requestText, '(?<path>[^\s"]*' + $PathPattern + ')')
    }
    if (-not $match.Success) { return $null }
    $artifactPath = $match.Groups["path"].Value.Trim()
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $artifactPath -Raw | ConvertFrom-Json -Depth 100
}

function Get-MockProjectName {
    param([Parameter(Mandatory)][string]$Scope, [Parameter(Mandatory)][string]$Fallback)

    if ([string]::IsNullOrWhiteSpace($RequestPath) -or -not (Test-Path -LiteralPath $RequestPath)) {
        return $Fallback
    }
    $requestText = Get-Content -LiteralPath $RequestPath -Raw
    if ($requestText -notmatch "(?m)^ {4}(\S+)\{scope\}\s*$") { return $Fallback }
    $prefix = [string]$Matches[1]
    $scopeWord = if ($prefix -cmatch "[A-Z]") {
        $Scope.Substring(0, 1).ToUpperInvariant() + $Scope.Substring(1)
    }
    else {
        $Scope.ToLowerInvariant()
    }
    return "$prefix$scopeWord"
}
function Get-MockConfiguredRuntime {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Fallback)

    # The request tells the architect which runtime a build agent here has. An
    # architect that ignored it would design something this installation cannot
    # run, and the resolver would refuse the blueprint - which is exactly what a
    # mock producing a hard-coded version was doing.
    if ([string]::IsNullOrWhiteSpace($RequestPath) -or -not (Test-Path -LiteralPath $RequestPath)) {
        return $Fallback
    }
    $requestText = Get-Content -LiteralPath $RequestPath -Raw
    if ($requestText -match "(?m)^\s*-\s+$([regex]::Escape($Key))\s*:\s*(\S+)\s*$") {
        return ([string]$Matches[1]).Trim('"')
    }
    return $Fallback
}

function New-MockToolchainDecision {
    # The blueprint now has to say why the automation is in the technology it is
    # in, so the mock answers like an architect that read discovery rather than
    # like one that picked a profile off a list.
    $nodeMajor = Get-MockConfiguredRuntime -Key "node_major" -Fallback "22"
    return [ordered]@{
        detectedStack = [ordered]@{
            language = "TypeScript"
            runtime = "node 20"
            buildSystem = "npm scripts"
            packageManager = "npm"
            existingTestFrameworks = @()
            evidence = @("src/service/package.json", "package-lock.json")
        }
        ecosystem = "npm"
        language = "typescript"
        runtime = [ordered]@{ name = "node"; version = $nodeMajor }
        testFramework = "playwright-test"
        packages = @(
            [ordered]@{
                name = "@playwright/test"
                version = "^1.47.0"
                scope = "dev"
                purpose = "Runs the suite and drives the browser."
            },
            [ordered]@{
                name = "typescript"
                version = "^5.5.0"
                scope = "dev"
                purpose = "Compiles the specifications the product is already written in."
            }
        )
        reusedConventions = @(
            "The Node major the pipeline already installs.",
            "The public npm registry the service already restores from."
        )
        coverageFit = @(
            [ordered]@{
                capability = "HTTP and transport contracts"
                howItIsMet = "Playwright's request fixture calls the service without a browser."
            },
            [ordered]@{
                capability = "Browser journeys"
                howItIsMet = "Playwright drives the same journeys the product's users take."
            }
        )
        alternativesRejected = @(
            [ordered]@{
                option = "A second suite in another language for the browser tests"
                reason = "One runner already covers both surfaces, and a second toolchain is a second thing to maintain."
            }
        )
        ciRequirements = @(
            "Node.js 20 on the agent.",
            "Playwright browser download permitted on first install."
        )
        deviatesFromDetectedStack = $false
    }
}

function Get-MockAssignment {
    return Get-MockContextJson -PathPattern 'assignment-batch-\d+(?:-escalated)?\.json'
}

function Get-MockApprovedPaths {
    return Get-MockContextJson -PathPattern 'approved-paths\.json'
}

# The plan has to name the toolchain the resolver actually locked, so the mock
# reads it rather than asserting one. A mock that named a toolchain of its own
# would pass the schema and then be refused downstream for a reason no real run
# would ever hit.
function Get-MockToolchainLock {
    return Get-MockContextJson -PathPattern 'toolchain-lock\.json'
}

$result = [ordered]@{
    agentId = $AgentId
    stageId = $StageId
    runId = $RunId
    status = "completed"
    summary = "Deterministic mock result produced by $AgentId."
    evidence = $evidence
    assumptions = @("Demo mode uses deterministic project evidence.")
    unknowns = @("Live target behavior was not exercised in mock mode.")
    warnings = @()
    details = [ordered]@{
        provider = "mock"
        stageIteration = $StageIteration
        attempt = $Attempt
    }
}

switch ($AgentId) {
    "repository-discovery" {
        $result.details.findings = @(
            "The target is the SDLC Foundry prototype repository.",
            "PowerShell orchestrates YAML-defined stages."
        )
        $result.details.technologies = @("PowerShell", "Node.js", "YAML", "JSON Schema")
        # The mock answers with the same stack facts a live discovery would, so a
        # demo run exercises the architect's "start from the product's own
        # ecosystem" rule rather than skipping past it on an empty details block.
        $result.details.componentStacks = @(
            [ordered]@{
                name = "Demo service"
                path = "src/service"
                role = "product"
                primaryLanguage = "TypeScript"
                runtime = "node 20"
                buildSystem = "npm scripts"
                packageManager = "npm"
                dependencies = @([ordered]@{ name = "express"; version = "4.19.2"; scope = "runtime" })
                testFrameworks = @()
                configurationApproach = "Environment variables read at startup."
                loggingApproach = "Structured JSON written to stdout."
                ciEnvironment = "The pipeline installs Node.js 20 before any script runs."
                packageFeeds = @("https://registry.npmjs.org")
                evidence = @("src/service/package.json", "package-lock.json", "azure-pipelines.yml")
            }
        )
        $result.details.primaryStack = [ordered]@{
            language = "TypeScript"
            runtime = "node 20"
            buildSystem = "npm scripts"
            packageManager = "npm"
            ecosystem = "npm"
            polyglot = $false
            rationale = "The only component the repository ships is a Node service; the PowerShell belongs to the automation installation."
            evidence = @("src/service/package.json", "package-lock.json")
        }
        $result.details.excludedFromStackDetermination = @(
            [ordered]@{ path = "foundry"; reason = "foundry_installation" },
            [ordered]@{ path = "node_modules"; reason = "vendored" }
        )
    }
    "requirements-discovery" {
        $result.details.requirements = @(
            "Use deterministic orchestration.",
            "Preserve schema-valid evidence artifacts.",
            "Never merge automatically."
        )
        $result.details.contradictions = @()
    }
    "delivery-environment-discovery" {
        $result.details.providers = @("local")
        $result.details.constraints = @(
            "Remote writes and production delivery are disabled in demo mode."
        )
    }
    "discovery-synthesis" {
        $result.details.mayContinue = $true
        $result.details.knownContext = @(
            "A local deterministic demo is required.",
            "TypeScript and Playwright are one isolated generation strategy."
        )
        $result.details.disagreements = @()
        # Legacy discovery workflows ask the model for stack fields. The compact
        # workflow below leaves them to deterministic composition from its source.
        $result.details.componentStacks = @(
            [ordered]@{
                name = "Demo service"
                path = "src/service"
                role = "product"
                primaryLanguage = "TypeScript"
                runtime = "node 20"
                buildSystem = "npm scripts"
                packageManager = "npm"
                testFrameworks = @()
                ciEnvironment = "The pipeline installs Node.js 20 before any script runs."
                packageFeeds = @("https://registry.npmjs.org")
                evidence = @("src/service/package.json", "package-lock.json")
            }
        )
        $result.details.primaryStack = [ordered]@{
            language = "TypeScript"
            runtime = "node 20"
            buildSystem = "npm scripts"
            packageManager = "npm"
            ecosystem = "npm"
            polyglot = $false
            rationale = "The only component the repository ships is a Node service; the PowerShell belongs to the automation installation."
            evidence = @("src/service/package.json", "package-lock.json")
        }
        $result.details.existingAutomation = @()
        if ($RequestPath -and (Get-Content -LiteralPath $RequestPath -Raw) -match 'Compact discovery reconciliation') {
            $null = $result.details.Remove('componentStacks')
            $null = $result.details.Remove('primaryStack')
            $result.details.blockingContext = @()
        }
    }
    "automation-architect" {
        # The blueprint's details are a closed contract, so the mock's own run metadata
        # does not belong in it.
        foreach ($metadata in @("provider", "stageIteration", "attempt")) {
            $result.details.Remove($metadata)
        }
        $result.details.decision = [ordered]@{
            outcome = "proceed"
            scope = "An isolated black-box automation suite for the discovered target."
            rationale = "Deterministic mock decision used to exercise the architecture loop."
        }
        $result.details.stack = [ordered]@{
            language = "typescript"
            runner = "playwright-test"
            runtime = "node"
            dependencies = @("@playwright/test", "typescript")
        }
        $result.details.structure = [ordered]@{
            root = "automation"
            tree = @("automation/api", "automation/ui", "automation/support")
            namingConvention = "kebab-case directories, *.spec.ts for tests"
        }
        $result.details.automationProjects = @(
            [ordered]@{
                name = Get-MockProjectName -Scope "api" -Fallback "automation-api"
                path = "automation/api"
                purpose = "Cover HTTP and transport contracts, which run headless without a browser."
                runsWith = "automation-install"
                toolchain = (New-MockToolchainDecision)
            },
            [ordered]@{
                name = Get-MockProjectName -Scope "ui" -Fallback "automation-ui"
                path = "automation/ui"
                purpose = "Cover browser journeys, which need a different runtime from the API project."
                runsWith = "automation-install"
                toolchain = (New-MockToolchainDecision)
            }
        )
        $result.details.proposedCommands = @(
            [ordered]@{
                id = "automation-install"
                command = "npm ci"
                workingDirectory = "automation"
                purpose = "Install the declared dependencies."
                verified = $false
            }
        )
        $result.details.milestones = @(
            [ordered]@{
                id = "M1"
                name = "Runnable skeleton"
                deliverables = @("Playwright configuration", "One health-check specification")
                exit = "The suite runs and reports."
            }
        )
        $result.details.guardrails = @(
            "The suite writes nothing outside its own root."
        )
    }
    "api-test-planner" {
        $result.details.tests = @(
            [ordered]@{
                id = "API-001"
                priority = "smoke"
                level = "api"
                rationale = "Validate one evidence-supported health contract."
            }
        )
    }
    "ui-test-planner" {
        $result.details.tests = @(
            [ordered]@{
                id = "UI-001"
                priority = "critical"
                level = "ui"
                rationale = "Validate one evidence-supported primary journey."
            }
        )
    }
    "risk-test-planner" {
        $result.riskScenarios = @(
            [ordered]@{
                id = "RISK-001"
                category = "resilience"
                priority = "high"
                rationale = "Verify deterministic failure evidence and bounded correction loops."
            }
        )
    }
    "coverage-synthesis" {
        $result.details.orderedTests = @("API-001", "UI-001")
        $result.details.duplicatesRemoved = @()
    }
    "framework-implementation" {
        $result.plannedFiles = @(
            [ordered]@{
                path = "automation/package.json"
                operation = "create"
                project = "automation-api"
                purpose = "Declare the automation workspace and its runnable scripts."
                contentContract = "Private npm package named automation with a playwright devDependency and test scripts for each project."
            },
            # The lock belongs in the inventory even though no agent may write it:
            # the slicer withholds it for the resolver, and a plan that never names
            # it leaves the materialisation stage with nothing to resolve and every
            # automation project delivered without a lock.
            [ordered]@{
                path = "automation/package-lock.json"
                operation = "create"
                project = "automation-api"
                purpose = "Pin every package the manifest declares to an exact resolved version."
                contentContract = "Resolved by the package manager from automation/package.json; never authored by hand."
                dependsOn = @("automation/package.json")
            },
            [ordered]@{
                path = "automation/playwright.config.ts"
                operation = "create"
                project = "automation-api"
                purpose = "Define the Playwright projects the blueprint approved."
                contentContract = "Export a config declaring one project per approved automation project, a reporter and a base URL read from support/config.ts."
                dependsOn = @("automation/support/config.ts")
            },
            [ordered]@{
                path = "automation/support/config.ts"
                operation = "create"
                project = "automation-api"
                purpose = "Read environment configuration without embedding secrets."
                contentContract = "Export a typed config object built from named environment variables, failing fast when a required variable is missing."
            },
            [ordered]@{
                path = "automation/technology-choices.md"
                operation = "create"
                project = "automation-api"
                purpose = "Record why this project's language and technologies were chosen."
                contentContract = "State the language, runtime, test runner and libraries, the development stack of the component under test and the evidence for it, which alternatives were rejected and why, and what the choice costs."
            }
        )
        $result.commandsProposed = @("npm ci", "npx playwright test")
        $result.details.correctionApplied = $StageIteration -gt 1
    }
    "test-implementation" {
        $result.plannedFiles = @(
            [ordered]@{
                path = "automation/api/health.spec.ts"
                operation = "create"
                project = "automation-api"
                purpose = "Cover API-001."
                contentContract = "Request the health endpoint and assert the status code and the reported state field."
                dependsOn = @("automation/support/config.ts")
            }
        )
        $result.commandsProposed = @("npx playwright test")
        $result.details.traceability = @("API-001")
        $result.details.correctionApplied = $StageIteration -gt 1
    }
    "execution" {
        $result.commands = @(
            [ordered]@{
                id = "runtime-proof"
                executable = "node"
                arguments = @("--version")
                workingDirectory = "."
                environment = [ordered]@{}
            },
            # A bootstrap plan always contains commands that fail, because the
            # automation they exercise is written at the end of the run. The mock
            # carries one so that "a failure is evidence, not a crash" is exercised
            # by every workflow test rather than asserted in one place.
            [ordered]@{
                id = "automation-not-built-yet"
                executable = "node"
                arguments = @("--qa-foundry-not-a-real-flag")
                workingDirectory = "."
                environment = [ordered]@{}
            }
        )
        $result.details.reportLocations = @(".qa-foundry-artifacts")
    }
    "failure-analysis" {
        $result.failures = @()
        $result.details.conclusion = "The failed command exercises automation that this run has not written yet."
    }
    { $_ -in @(
        "failure-root-cause-analyst",
        "failure-change-analyst",
        "failure-evidence-auditor"
    ) } {
        $result.findings = @()
        $result.details.conclusion = "No failed realtime CI evidence was supplied in local demo mode."
    }
    "failure-analysis-synthesis" {
        $result.outcome = "no_action_needed"
        $result.verifiedFindings = @()
        $result.details.conclusion = "The demo event contains no failed build evidence."
    }
    "remediation-planner" {
        $result.outcome = "no_action_needed"
        $result.proposals = @()
        $result.details.conclusion = "No verified actionable finding requires remediation."
    }
    "architecture-critic" {
        $result.decision = "approved"
        $result.findings = @()
        $result.requiredChanges = @()
        $result.confidence = 0.96
    }
    { $_ -in @("architecture-security-critic", "architecture-delivery-critic") } {
        # Reject the opening draft once so the revision path is exercised, then approve
        # as soon as the producer has been handed the revision ledger. Anything else
        # would leave the loop's briefing step untested.
        $briefed = $RequestPath -and (Test-Path -LiteralPath $RequestPath) -and
            ((Get-Content -Path $RequestPath -Raw) -match "revision-ledger\.json")
        if ($AgentId -eq "architecture-security-critic" -and -not $briefed) {
            $result.decision = "revision_required"
            $result.findings = @(
                [ordered]@{
                    severity = "error"
                    message = "SEC-MOCK-01 secret handling is not described."
                    evidence = "Deterministic mock finding for the first architecture draft."
                    resolutionScope = "blueprint_revision"
                }
            )
            $result.requiredChanges = @("Describe how secrets are supplied and redacted.")
            $result.confidence = 0.93
        }
        else {
            $result.decision = "approved"
            $result.findings = @()
            $result.requiredChanges = @()
            $result.confidence = 0.96
        }
    }
    "code-review" {
        if ($StageIteration -eq 1) {
            $result.decision = "revision_required"
            $result.findings = @(
                [ordered]@{
                    severity = "error"
                    message = "The first demo pass lacks explicit correction evidence."
                    evidence = "implementation/framework-implementation.json"
                }
            )
            $result.requiredChanges = @(
                "Re-run implementation with the structured review finding."
            )
            $result.confidence = 0.95
        }
        else {
            $result.decision = "approved"
            $result.findings = @()
            $result.requiredChanges = @()
            $result.confidence = 0.98
        }
    }
    "test-quality-review" {
        $result.decision = "approved"
        $result.findings = @()
        $result.requiredChanges = @()
        $result.confidence = 0.94
    }
    { $_ -in @(
        "remediation-safety-review",
        "remediation-value-review",
        "remediation-operations-review",
        "security-resilience-review",
        "delivery-security-review",
        "release-risk-review"
    ) } {
        $result.decision = "approved"
        $result.findings = @()
        $result.requiredChanges = @()
        $result.confidence = 0.97
    }
    "change-summary" {
        $result.details.architecture = "YAML process, prompt intelligence, JSON artifacts, PowerShell control."
        $result.details.reviewIterations = $StageIteration
        $result.details.knownLimitations = @(
            "Mock mode does not generate or execute a real target test suite."
        )
    }
    "pull-request-compliance" {
        $result.decision = "approved"
        $result.findings = @()
        $result.requiredChanges = @()
        $result.confidence = 0.97
        $result.draftPullRequestAllowed = $false
        $result.checks = @(
            "Allowed paths checked.",
            "Execution evidence present.",
            "Unanimous review approval present.",
            "Draft PR creation is disabled by demo configuration.",
            "Automatic merge is prohibited."
        )
    }
    "supervisor" {
        $result.reason = "iteration_limit_reached"
        $result.recommendation = "block"
        $result.details.allowedDecisionObserved = $true
    }
    { $_ -like "*-analyst" } {
        $result.findings = @()
        $result.details.conclusion = "No evidence-supported actionable finding was produced in deterministic demo mode."
    }
    { $_ -like "*-synthesis" } {
        $result.outcome = "no_action_needed"
        $result.findings = @()
        $result.details.conclusion = "Independent demo analyses found no actionable item."
    }
    { $_ -like "*-work-item-planner" } {
        $result.outcome = "no_action_needed"
        $result.items = @()
        $result.details.conclusion = "No work item is justified by demo evidence."
    }
    { $_ -like "*-change-generator-batch-*" } {
        # A batch answers for exactly the paths it was assigned. The mock reads
        # the assignment rather than inventing paths, because the merge that
        # follows is the thing worth exercising: it refuses a set that does not
        # add up to the approved inventory, and a mock that guessed would either
        # never trip that check or trip it always.
        $assignment = Get-MockAssignment
        if ($null -eq $assignment) {
            throw "Mock provider found no batch assignment in the request for agent: $AgentId"
        }
        $result.outcome = "proposed"
        $result.batchId = [string]$assignment.batchId
        # A manifest is not free text. The materialisation stage reads it with the
        # ecosystem's own parser and compares what it declares against the locked
        # toolchain, so a mock that wrote a comment where a manifest belongs would
        # stop the demo at the resolver with an error about the mock rather than
        # about the thing under test. The adapter writes it, exactly as it would
        # for a real run.
        $manifestAdapters = @(@(Get-QaFoundryEcosystemAdapterNames) |
            ForEach-Object { Get-QaFoundryEcosystemAdapter -Ecosystem $_ })
        $mockLock = Get-MockToolchainLock
        $result.changes = @(@($assignment.assignedFiles) | ForEach-Object {
            $path = [string]$_.path
            $content = "// Deterministic mock content for $path.`n"
            if ($null -ne $mockLock) {
                $adapter = @($manifestAdapters | Where-Object { $path -match [string]$_.manifestPattern }) |
                    Select-Object -First 1
                if ($null -ne $adapter) {
                    $toolchain = @($mockLock.toolchains | Where-Object {
                            [string]$_.recipe -ceq [string]$adapter.recipe
                        }) | Select-Object -First 1
                    if ($null -ne $toolchain) {
                        $directory = (Split-Path $path -Parent) -replace "\\", "/"
                        $projectName = if ($directory) { ($directory -replace "[\\/]+", "-") } else { "automation" }
                        $content = [string](& $adapter.NewManifestContent $toolchain $projectName "0.0.0")
                    }
                }
            }
            [ordered]@{
                operation = if ($_.PSObject.Properties.Name -contains "operation") {
                    [string]$_.operation
                } else { "create" }
                path = $path
                expectedSha256 = ""
                content = $content
                reason = "Mock implementation of the approved planned file."
                sourceRefs = @("implementation/framework-implementation.json")
            }
        })
        $result.details.conclusion = "Mock batch $($assignment.batchId) wrote its assigned files."
    }
    { $_ -like "*-materialization-planner" } {
        # A planner that ignored the paths withheld for a resolver would let the
        # merge pass with a change set that has no lock in it, which is the one
        # failure this stage exists to prevent. The mock reads the same coverage
        # document the real planner is given and answers for it.
        #
        # Which lock belongs to which ecosystem is asked of the adapters rather
        # than assumed, because the runtime this mock stands in for supports
        # every ecosystem that ships an adapter. A mock that only ever emitted
        # npm entries would leave every other ecosystem's planning path untried.
        $approved = Get-MockApprovedPaths
        $generated = @()
        $resolverOwned = @()
        if ($null -ne $approved) {
            $generated = @($approved.generatedPaths | ForEach-Object { [string]$_ })
            $resolverOwned = @($approved.resolverOwnedPaths | ForEach-Object { [string]$_ })
        }
        $planned = @()
        if ($resolverOwned.Count -gt 0) {
            $lock = Get-MockToolchainLock
            if ($null -eq $lock) {
                throw ("Mock provider found no resolved toolchain in the request for agent: " +
                    "$AgentId, so it cannot say which toolchain a lock belongs to.")
            }
            $adapters = @(@(Get-QaFoundryEcosystemAdapterNames) |
                ForEach-Object { Get-QaFoundryEcosystemAdapter -Ecosystem $_ })
            foreach ($lockPath in $resolverOwned) {
                $adapter = @($adapters | Where-Object { $lockPath -match [string]$_.lockFilePattern }) |
                    Select-Object -First 1
                if ($null -eq $adapter) { continue }
                $directory = (Split-Path $lockPath -Parent) -replace "\\", "/"
                $manifestPath = @($generated | Where-Object {
                        ((Split-Path $_ -Parent) -replace "\\", "/") -ceq $directory -and
                        $_ -match [string]$adapter.manifestPattern
                    }) | Select-Object -First 1
                if (-not $manifestPath) { continue }
                $toolchain = @($lock.toolchains | Where-Object {
                        [string]$_.recipe -ceq [string]$adapter.recipe
                    }) | Select-Object -First 1
                if ($null -eq $toolchain) { continue }
                # The projects a manifest serves are the ones the toolchain was
                # decided for, not the directory the manifest happens to sit in:
                # one manifest at 'automation' governs 'automation/api' and
                # 'automation/ui', and naming the directory names a project the
                # blueprint never approved.
                $governed = @(@($toolchain.decidedFor | ForEach-Object { ([string]$_).Replace("\", "/") }) |
                    Where-Object {
                        $directory -eq "" -or $_ -ceq $directory -or
                        $_.StartsWith("$directory/", [StringComparison]::Ordinal)
                    })
                if ($governed.Count -eq 0) { $governed = @(if ($directory) { $directory } else { "." }) }
                $planned += [ordered]@{
                    recipe = [string]$adapter.recipe
                    toolchainId = [string]$toolchain.id
                    projectPaths = @($governed)
                    manifestPath = [string]$manifestPath
                    lockPath = $lockPath
                    operation = "create"
                    expectedSha256 = ""
                    reason = "Lock the dependencies the approved manifest declares."
                    sourceRefs = @([string]$manifestPath)
                }
            }
        }
        $result.outcome = if ($planned.Count -gt 0) { "proposed" } else { "no_action_needed" }
        $result.materializations = @($planned)
        $result.details.conclusion = if ($planned.Count -gt 0) {
            "Mock mode hands $($planned.Count) manifest(s) to the resolver."
        } else { "Mock mode locks no dependencies." }
    }
    { $_ -like "*-change-generator" } {
        $result.outcome = "no_action_needed"
        $result.changes = @()
        $result.details.conclusion = "No repository mutation is justified by demo evidence."
    }
    { $_ -like "*-reviewer" } {
        $result.decision = "approved"
        $result.findings = @()
        $result.requiredChanges = @()
        $result.confidence = 0.97
    }
    default {
        throw "Mock provider does not support agent: $AgentId"
    }
}

if ($AgentId -eq 'automation-architect' -and $RequestPath) {
    $requestText = Get-Content -LiteralPath $RequestPath -Raw
    if ($requestText.Contains('## Incremental revision response')) {
        $result = [ordered]@{
            baseSha256 = [regex]::Match($requestText, 'SHA-256 ([a-f0-9]{64})').Groups[1].Value
            summary = 'Deterministic mock revision retains the existing blueprint.'
            status = 'completed'
            edits = @()
            deferrals = @()
            resolvedDeferrals = @()
        }
    }
}
$result | ConvertTo-Json -Depth 100 -Compress
