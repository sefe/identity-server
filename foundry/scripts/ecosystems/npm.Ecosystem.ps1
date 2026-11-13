# Everything this runtime knows about npm in one place.
#
# The materialiser used to know it too, in the form of assumptions spread through
# it: that a manifest is called package.json, that dependencies live under two
# named sections, that a lock file is npm's. Those assumptions were invisible
# until someone chose a different ecosystem, and then they were not assumptions
# any more, they were a silent redirection of the architecture back to npm. An
# adapter makes them a property of npm rather than a property of the runtime.

function New-QaFoundryNpmEcosystemAdapter {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        id = "npm"
        displayName = "npm"
        # The pair of deterministic scripts that produce a lock file and prove it
        # matches what was locked. Named here rather than in the materialiser so
        # that adding an ecosystem is a file rather than an edit to a table
        # buried in a stage.
        recipe = "npm-package-lock"
        # What the manifest is called is asked of the adapter rather than read
        # as a constant, because not every ecosystem has one: a NuGet project's
        # manifest is named after the project. A path is checked against the
        # pattern below rather than against a literal name for the same reason.
        GetManifestFileName = { param([string]$ProjectName) return "package.json" }
        manifestPattern = "(^|/)package\.json$"
        lockFileName = "package-lock.json"
        lockFilePattern = "(^|/)package-lock\.json$"
        # The keys an ecosystem entry under automation.ecosystems must carry for
        # this adapter to know what it is running on.
        requiredRuntimeKeys = @("node_major", "npm_version", "lockfile_version")
        resolveScript = "Resolve-EcosystemLock.ps1"
        verifyScript = "Test-EcosystemLock.ps1"
        # Declaring one of these turns resolution into something this runtime
        # cannot check against what was locked, and an unverifiable install is
        # the one thing a lock file exists to prevent.
        unverifiableManifestKeys = @(
            "workspaces", "overrides", "resolutions", "peerDependencies",
            "optionalDependencies", "bundleDependencies", "bundledDependencies"
        )
        localDependencyPrefixes = @("file:", "link:", "portal:", "workspace:")

        # What a single released version looks like when it is written down.
        # Anything a range, a caret, a tilde or a wildcard could also match is
        # not exact, and a manifest that asks for one cannot be checked against
        # a locked toolchain.
        exactVersionPattern = "^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$"

        # Whether two spellings name the same package is the registry's rule, not
        # PowerShell's. npm treats a name as the bytes it was published under, so
        # a locked "JSON5" and a declared "json5" are two different packages and
        # accepting one for the other would install something nobody approved.
        NormalizePackageName = { param([string]$Name) return ([string]$Name).Trim() }

        # The canonical runtime block, named the way every downstream consumer
        # reads it. Config keys are snake_case, artifacts are camelCase, and the
        # translation belongs here rather than in each reader.
        ReadRuntime = {
            param($Runtime)
            return [ordered]@{
                nodeMajor = [int]$Runtime["node_major"]
                npmVersion = [string]$Runtime["npm_version"]
                lockfileVersion = [int]$Runtime["lockfile_version"]
            }
        }

        # Node is not backward-compatible the way an SDK is: code written for one
        # major uses APIs an older major does not have, and an older major is
        # what would actually run. So the design's choice is honoured by being
        # checked rather than by being adopted - a mismatch is stated, not
        # silently resolved in favour of whichever number this file happens to
        # carry.
        ResolveProposedRuntime = {
            param($Runtime, $Canonical, [string]$ProposedName, [string]$ProposedVersion)

            $installedMajor = [int]$Canonical["nodeMajor"]
            $requested = Get-QaFoundryProposedRuntimeVersion -Name $ProposedName -Version $ProposedVersion
            if ([string]::IsNullOrWhiteSpace($requested)) {
                Test-QaFoundryProposedRuntimeReadable -Label "Node runtime" `
                    -ProposedName $ProposedName -ProposedVersion $ProposedVersion
                return $Canonical
            }
            $requestedMajor = Get-QaFoundryRuntimeVersionMajor -Version $requested
            if ($requestedMajor -le 0) {
                throw ("The design is written for Node '$requested', which is not a major version " +
                    "this runtime can check against the installed Node $installedMajor.")
            }
            if ($requestedMajor -eq $installedMajor) { return $Canonical }
            throw ("The design is written for Node $requestedMajor, and this installation runs " +
                "Node $installedMajor. Either configure the automation ecosystem with node_major " +
                "$requestedMajor or design against Node $installedMajor.")
        }

        # What has to be on the agent before a lock can be produced here, and
        # which versions the decision was settled on. npm is checked exactly
        # because a different npm emits a different lock shape from the same
        # manifest; Node is checked by major, which is the granularity npm's own
        # engine constraints work at.
        GetResolverTools = {
            param($Toolchain)
            return @(
                [pscustomobject]@{
                    key = "npm"; command = "npm"; label = "npm"
                    expectedVersion = [string]$Toolchain.runtime.npmVersion; match = "exact"
                },
                [pscustomobject]@{
                    key = "node"; command = "node"; label = "Node"
                    expectedVersion = [string]$Toolchain.runtime.nodeMajor; match = "major"
                }
            )
        }

        # npm reads user and global configuration unless it is pointed at empty
        # files, and an inherited .npmrc could redirect the registry or add a
        # credential to a request this runtime believes is anonymous.
        NewNeutralConfigFiles = {
            param($Toolchain, [string]$WorkRoot)
            return @(
                [pscustomobject]@{ key = "userconfig"; path = "empty-user.npmrc"; content = "" },
                [pscustomobject]@{ key = "globalconfig"; path = "empty-global.npmrc"; content = "" }
            )
        }

        GetResolveCommand = {
            param($Toolchain, $Context)
            return [pscustomobject]@{
                toolKey = "npm"
                arguments = @(
                    "install", "--package-lock-only", "--ignore-scripts", "--no-audit", "--no-fund",
                    "--registry", [string]$Toolchain.source.registry,
                    "--userconfig", [string]$Context.configFiles["userconfig"],
                    "--globalconfig", [string]$Context.configFiles["globalconfig"],
                    "--cache", [string]$Context.cacheRoot
                )
            }
        }

        ReadLockEntries = {
            param([string]$LockContent, $Toolchain)
            try {
                # A v3 lock always keys its root entry with the empty string, and
                # ConvertFrom-Json refuses that property name unless it builds a
                # hashtable.
                $lock = $LockContent | ConvertFrom-Json -Depth 100 -AsHashtable
            }
            catch {
                return [pscustomobject]@{ parsed = $false; parseError = $_.Exception.Message }
            }

            $direct = [System.Collections.Generic.List[object]]::new()
            $entries = [System.Collections.Generic.List[object]]::new()
            $identity = [pscustomobject]@{ name = ""; version = "" }

            $root = $null
            if ($null -ne $lock.packages) { $root = $lock.packages[""] }
            if ($null -ne $root) {
                # npm omits a name or a version from the root entry when the
                # manifest omits it, so the absent case is read rather than
                # reached for.
                $rootFields = @(Get-QaFoundryPropertyNames -InputObject $root)
                $identity = [pscustomobject]@{
                    name = $(if ($rootFields -contains "name") { [string]$root.name } else { "" })
                    version = $(if ($rootFields -contains "version") { [string]$root.version } else { "" })
                }
                foreach ($section in @("dependencies", "devDependencies")) {
                    $scope = $(if ($section -eq "devDependencies") { "dev" } else { "runtime" })
                    foreach ($name in @(Get-QaFoundryPropertyNames -InputObject $root[$section])) {
                        $direct.Add([pscustomobject]@{
                            name = [string]$name
                            version = [string]$root[$section][$name]
                            scope = $scope
                        })
                    }
                }
            }

            foreach ($key in @(Get-QaFoundryPropertyNames -InputObject $lock.packages)) {
                if ($key -eq "") { continue }
                $entry = $lock.packages[$key]
                $fields = @(Get-QaFoundryPropertyNames -InputObject $entry)
                # A nested entry is keyed by its whole path, and the package it
                # installs is the segment after the last node_modules.
                $name = [string]$key
                $marker = $name.LastIndexOf("node_modules/")
                if ($marker -ge 0) { $name = $name.Substring($marker + 13) }
                $entries.Add([pscustomobject]@{
                    key = [string]$key
                    name = $name
                    version = $(if ($fields -contains "version") { [string]$entry.version } else { "" })
                    integrity = $(if ($fields -contains "integrity") { [string]$entry.integrity } else { "" })
                    resolvedUrl = $(if ($fields -contains "resolved") { [string]$entry.resolved } else { "" })
                    # npm copies each package's declared licence into the lock, so
                    # the licence a policy is applied to is the one the resolver
                    # actually saw rather than one looked up later from a registry
                    # that may have changed its mind since.
                    license = $(if ($fields -contains "license") {
                        $declaredLicense = $entry.license
                        if ($declaredLicense -is [System.Collections.IEnumerable] -and
                            $declaredLicense -isnot [string]) {
                            (@($declaredLicense | ForEach-Object { [string]$_ }) -join " OR ")
                        }
                        else { [string]$declaredLicense }
                    } else { "" })
                    # A link entry points at a directory on the machine that
                    # resolved it. The manifest this runtime writes has no
                    # workspaces and no file: dependencies, so a link here means
                    # the lock came from somewhere else entirely.
                    isLocal = ($fields -contains "link" -and [bool]$entry.link)
                })
            }

            return [pscustomobject]@{
                parsed = $true
                parseError = ""
                formatVersion = [string]$lock.lockfileVersion
                identity = $identity
                direct = @($direct)
                entries = @($entries)
                originIsPerFile = $false
                feeds = @()
                # npm records a licence per package, so a licence policy can be
                # decided from the lock alone.
                licensesRecorded = $true
            }
        }

        # The manifest a locked toolchain implies. Written from the lock rather
        # than by an agent, so the file and the resolution can never disagree.
        NewManifestContent = {
            param($Toolchain, [string]$Name, [string]$Version)
            $manifest = [ordered]@{}
            if (-not [string]::IsNullOrWhiteSpace($Name)) { $manifest.name = $Name }
            if (-not [string]::IsNullOrWhiteSpace($Version)) { $manifest.version = $Version }
            # Test automation is never a published package. Without this npm is
            # willing to publish it to the public registry on a stray `npm
            # publish`, and an internal suite's names, endpoints and fixtures are
            # exactly the sort of thing that must not leave the organisation by
            # accident. It costs one key and removes the possibility.
            $manifest.private = $true
            $runtimeScoped = @()
            $devScoped = @()
            foreach ($package in @($Toolchain.packages)) {
                if ([string]$package.scope -eq "dev") { $devScoped += $package } else { $runtimeScoped += $package }
            }
            if ($runtimeScoped.Count -gt 0) {
                $section = [ordered]@{}
                foreach ($package in @($runtimeScoped | Sort-Object { [string]$_.name })) {
                    $section[[string]$package.name] = [string]$package.version
                }
                $manifest.dependencies = $section
            }
            if ($devScoped.Count -gt 0) {
                $section = [ordered]@{}
                foreach ($package in @($devScoped | Sort-Object { [string]$_.name })) {
                    $section[[string]$package.name] = [string]$package.version
                }
                $manifest.devDependencies = $section
            }
            return ($manifest | ConvertTo-Json -Depth 20)
        }

        # What a planned manifest actually asks for, flattened to one shape so the
        # materialiser can compare it against the lock without knowing which
        # ecosystem produced it.
        ReadManifestDependencies = {
            param([string]$ManifestContent)
            $manifest = $ManifestContent | ConvertFrom-Json -Depth 50
            $names = @(Get-QaFoundryPropertyNames -InputObject $manifest)
            $declared = [System.Collections.Generic.List[object]]::new()
            foreach ($section in @("dependencies", "devDependencies")) {
                if ($names -notcontains $section -or $null -eq $manifest.$section) { continue }
                # Asked for through the shared reader rather than by reaching for
                # .PSObject.Properties.Name, which is a member enumeration and
                # throws under the strict mode this runtime sets when the
                # collection is empty. A manifest that declares '"dependencies":
                # {}' - which npm writes, and which an author writes to say that
                # nothing runs in production - blocked the materialisation of
                # build 973307 with "the property 'Name' cannot be found".
                foreach ($name in @(Get-QaFoundryPropertyNames -InputObject $manifest.$section)) {
                    $declared.Add([pscustomobject]@{
                        name = [string]$name
                        version = [string]$manifest.$section.$name
                        scope = if ($section -eq "devDependencies") { "dev" } else { "runtime" }
                    })
                }
            }
            return @($declared)
        }

        # The identity npm asks a package for. Optional, because npm asks a
        # private package for neither a name nor a version, and a field this
        # runtime invented would appear in a lock the manifest never claimed.
        ReadManifestIdentity = {
            param([string]$ManifestContent)
            $manifest = $ManifestContent | ConvertFrom-Json -Depth 50
            $names = @(Get-QaFoundryPropertyNames -InputObject $manifest)
            return [pscustomobject]@{
                name = if ($names -contains "name") { [string]$manifest.name } else { "" }
                version = if ($names -contains "version") { [string]$manifest.version } else { "" }
            }
        }

        # Every released version the registry has for a package. Nothing here
        # trusts the agent's arithmetic: the registry is the only thing that
        # knows what actually exists.
        GetPublishedVersions = {
            param([string]$Registry, [string]$Name)
            $encoded = [Uri]::EscapeDataString($Name).Replace("%40", "@").Replace("%2F", "/")
            $uri = ($Registry.TrimEnd("/") + "/" + $encoded)
            $document = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 60 -ErrorAction Stop
            if ($null -eq $document -or $null -eq $document.versions) { return @() }
            return @(Get-QaFoundryPropertyNames -InputObject $document.versions |
                ForEach-Object { [string]$_ })
        }

        # An architect proposes what it needs; this turns that into the one
        # version the lock will carry. The highest published release that
        # satisfies the request wins, so two runs of the same blueprint against
        # the same registry state resolve to the same bytes.
        SelectVersion = {
            param([string]$Requested, [string[]]$Published, [bool]$AllowPrerelease)
            return Select-QaFoundryNodeStyleVersion -Requested $Requested -Published $Published `
                -AllowPrerelease $AllowPrerelease
        }

        # What a build agent has to provide before any of this can run.
        GetRuntimeRequirements = {
            param($Toolchain)
            return @(
                "Node.js $([int]$Toolchain.runtime.nodeMajor).x",
                "npm $([string]$Toolchain.runtime.npmVersion)"
            )
        }

        # How the lock is enforced when the framework is actually installed.
        # npm ci refuses to run at all when the manifest and the lock disagree, and installs the lock rather than resolving.
        lockEnforcement = "install"

        # Whether the manifest format itself says which dependencies exist
        # only to build and test the project. Where it does not, this run
        # would be comparing a decision it made against a fact the file
        # cannot carry, and refusing a manifest for disagreeing about
        # something it never stated. Here: dependencies and devDependencies are
        # two different objects in the manifest.
        manifestExpressesDependencyScope = $true

        TestVersionRange = {
            param([string]$Requested)
            return Test-QaFoundryNodeStyleRange -Requested $Requested -Ecosystem "npm"
        }

        # A package.json can claim the projects below it, and npm is one of the
        # few formats where it says so outright. Only what 'workspaces' names is
        # installed by an install at the root, so only what it names belongs to
        # the root project - anything else down there installs nothing and would
        # go untested behind a gate that passed.
        ReadWorkspaceMembers = {
            param([string]$ManifestPath)
            $document = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 40
            if (@(Get-QaFoundryPropertyNames -InputObject $document) -notcontains "workspaces") {
                return @()
            }
            $workspaces = $document.workspaces
            if ($null -eq $workspaces) { return @() }
            if ($workspaces -is [string]) { return @([string]$workspaces) }
            # The object form, 'workspaces: { packages: [...] }', is what Yarn
            # writes and npm still reads.
            if ($workspaces -isnot [System.Collections.IEnumerable] -and
                @(Get-QaFoundryPropertyNames -InputObject $workspaces) -contains "packages") {
                return @($workspaces.packages | ForEach-Object { [string]$_ })
            }
            return @($workspaces | ForEach-Object { [string]$_ })
        }

        GetInstallCommand = {
            param($Toolchain, [string]$ProjectPath)
            return [pscustomobject]@{
                executable = "npm"
                arguments = @("ci", "--no-audit", "--no-fund")
                workingDirectory = $ProjectPath
            }
        }

        GetBuildCommand = {
            param($Toolchain, [string]$ProjectPath)
            $arguments = @("run", "build", "--if-present")
            $manifestPath = Join-Path $ProjectPath 'package.json'
            if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
                $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                if ($manifest.PSObject.Properties['scripts'] -and $manifest.scripts -and
                    -not $manifest.scripts.PSObject.Properties['build'] -and
                    $manifest.scripts.PSObject.Properties['typecheck']) {
                    $arguments = @('run', 'typecheck')
                }
            }
            return [pscustomobject]@{
                executable = "npm"
                arguments = $arguments
                workingDirectory = $ProjectPath
            }
        }

        GetTestCommand = {
            param($Toolchain, [string]$ProjectPath)
            return [pscustomobject]@{
                executable = "npm"
                arguments = @("test")
                workingDirectory = $ProjectPath
            }
        }

        # How many tests actually ran. A run that reports nothing is not a
        # passing run, it is a run that proved nothing, so the count is read out
        # of the runner's own summary rather than inferred from the exit code.
        ReadTestRunSummary = {
            param([string]$Output, [int]$ExitCode)
            $text = [regex]::Replace([string]$Output, '\x1b\[[0-?]*[ -/]*[@-~]', '')
            $total = 0
            $failed = 0
            $skipped = 0
            $parsed = $false
            # node:test and most TAP-shaped reporters.
            if ($text -match "(?m)^#\s*pass\s+(\d+)\s*$") { $total += [int]$Matches[1]; $parsed = $true }
            if ($text -match "(?m)^#\s*fail\s+(\d+)\s*$") { $failed += [int]$Matches[1]; $total += [int]$Matches[1]; $parsed = $true }
            if ($parsed) {
                # A skipped or todo test is in the file and did not run. Left out
                # of the count, a suite of nothing but skips reads as a suite
                # that found nothing; counted as a pass, it reads as proof.
                if ($text -match "(?m)^#\s*skipped\s+(\d+)\s*$") { $skipped += [int]$Matches[1]; $total += [int]$Matches[1] }
                if ($text -match "(?m)^#\s*todo\s+(\d+)\s*$") { $skipped += [int]$Matches[1]; $total += [int]$Matches[1] }
            }
            # Jest/Vitest print file/suite counts before test counts. Only the
            # Tests line describes executed assertions; a failed import can
            # fail a file while zero tests in that file execute.
            $testLines = [regex]::Matches($text, '(?m)^\s*Tests:?\s+([^\r\n]+)$')
            if (-not $parsed -and $testLines.Count -gt 0) {
                $counts = $testLines[$testLines.Count - 1].Groups[1].Value
                foreach ($match in [regex]::Matches($counts, '(\d+)\s+(passed|failed|skipped|todo)')) {
                    $count = [int]$match.Groups[1].Value
                    $total += $count
                    if ($match.Groups[2].Value -eq 'failed') { $failed += $count }
                    if ($match.Groups[2].Value -in @('skipped', 'todo')) { $skipped += $count }
                    $parsed = $true
                }
                if ($counts -match '(\d+)\s+total') { $total = [int]$Matches[1]; $parsed = $true }
            }
            # Playwright and Mocha report counts without a separate Tests line.
            if (-not $parsed) {
                if ($text -match "(\d+)\s+(?:passed|passing)") { $total += [int]$Matches[1]; $parsed = $true }
                if ($text -match "(\d+)\s+(?:failed|failing)") { $failed += [int]$Matches[1]; $total += [int]$Matches[1]; $parsed = $true }
                if ($text -match "(\d+)\s+(?:skipped|pending)") { $skipped += [int]$Matches[1]; $total += [int]$Matches[1]; $parsed = $true }
                if ($text -match "Tests:\s+(\d+)\s+total") { $total = [int]$Matches[1]; $parsed = $true }
            }
            return [pscustomobject]@{
                parsed = $parsed
                total = $total
                failed = $failed
                skipped = $skipped
            }
        }

        # A suite that cannot fail proves nothing about the suites beside it, so
        # the framework is asked to fail on purpose once. The probe is written in
        # whichever runner the resolved packages actually contain: guessing the
        # syntax from prose in the blueprint would produce a file that fails to
        # parse, and a parse error looks exactly like the failure being asked for.
        NewNegativeProbe = {
            param($Toolchain, [string]$ProjectPath)
            $names = @($Toolchain.packages | ForEach-Object { ([string]$_.name).ToLowerInvariant() })
            if ($names -contains "@playwright/test") {
                return [pscustomobject]@{
                    supported = $true
                    relativePath = "tests/foundry-negative-probe.spec.ts"
                    content = @(
                        "import { expect, test } from '@playwright/test';",
                        "",
                        "test('a deliberately broken expectation fails', async () => {",
                        "  expect(1).toBe(2);",
                        "});",
                        ""
                    ) -join "`n"
                }
            }
            foreach ($runner in @("vitest", "jest")) {
                if ($names -contains $runner) {
                    return [pscustomobject]@{
                        supported = $true
                        relativePath = "tests/foundry-negative-probe.test.js"
                        content = @(
                            $(if ($runner -eq 'vitest') { "import { test, expect } from 'vitest';" } else { '' }),
                            "test('a deliberately broken expectation fails', () => {",
                            "  expect(1).toBe(2);",
                            "});",
                            ""
                        ) -join "`n"
                    }
                }
            }
            if ($names -contains "mocha") {
                return [pscustomobject]@{
                    supported = $true
                    relativePath = "tests/foundry-negative-probe.test.js"
                    content = @(
                        "const assert = require('node:assert/strict');",
                        "",
                        "it('a deliberately broken expectation fails', () => {",
                        "  assert.equal(1, 2);",
                        "});",
                        ""
                    ) -join "`n"
                }
            }
            # node:test needs no package, so it is the answer when nothing else
            # in the lock is a runner rather than a reason to give up.
            return [pscustomobject]@{
                supported = $true
                relativePath = "tests/foundry-negative-probe.test.mjs"
                content = @(
                    "import assert from 'node:assert/strict';",
                    "import { test } from 'node:test';",
                    "",
                    "test('a deliberately broken expectation fails', () => {",
                    "  assert.equal(1, 2);",
                    "});",
                    ""
                ) -join "`n"
            }
        }
    }
}
