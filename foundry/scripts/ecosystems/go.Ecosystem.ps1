# Everything this runtime knows about Go modules in one place.
#
# Go is the outlier among package managers: a module requirement is always an
# exact version, never a range, and the resolver's job is therefore to confirm a
# version exists rather than to choose between candidates. Saying so explicitly
# here keeps a range from being silently accepted and then ignored by the build.

function Select-QaFoundryGoVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Published,
        [bool]$AllowPrerelease = $false
    )

    $normalise = {
        param([string]$Value)
        $text = ([string]$Value).Trim()
        # Build metadata orders as equal in semver, and "+incompatible" is Go's
        # marker for a module that predates modules rather than part of the
        # version, so it is dropped before comparing.
        $plus = $text.IndexOf("+")
        if ($plus -ge 0) { $text = $text.Substring(0, $plus) }
        return $text
    }

    $usable = @($Published | Where-Object {
        $version = & $normalise $_
        # A pseudo-version names an untagged commit. It is a valid requirement
        # when asked for by name, but it is never the answer to "the newest
        # release", so it is left out of the candidates.
        if ($version -match "-\d{14}-[0-9a-f]{12}$") { return $false }
        $parts = ConvertTo-QaFoundryVersionParts -Version $version
        $parts.valid -and ($AllowPrerelease -or -not $parts.isPrerelease)
    })

    $request = ([string]$Requested).Trim()
    if ($request -in @("", "*", "latest")) {
        if ($usable.Count -eq 0) { return "" }
        $highest = Get-QaFoundryHighestVersion -Versions @($usable | ForEach-Object { & $normalise $_ })
        $match = @($usable | Where-Object { (& $normalise $_) -eq $highest })
        return $(if ($match.Count -gt 0) { [string]$match[0] } else { "" })
    }
    if ($request -match "^[\^~<>=]") {
        throw ("Go modules take an exact version, not a range. '$Requested' cannot be locked; " +
            "name the version to use, for example 'v1.9.0'.")
    }
    # An exact requirement, including a pseudo-version that was asked for by
    # name, so the whole published list is searched rather than the candidates.
    $wanted = & $normalise $request
    $exact = @($Published | Where-Object { (& $normalise $_) -eq $wanted -or $_ -eq $request })
    return $(if ($exact.Count -gt 0) { [string]$exact[0] } else { "" })
}

function Complete-QaFoundryGoManifestFromLock {
    param([string]$ManifestContent, [string]$LockContent)
    # Modern Go needs explicit indirect requirements for graph pruning. The
    # resolver already fetched this graph; record its versions in go.mod rather
    # than asking a build to run tidy and choose more dependencies later.
    $locked = [System.Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    foreach ($line in ($LockContent -split '\r?\n')) {
        if ($line -notmatch '^(\S+)\s+(v\S+)\s+h1:\S+\s*$') { continue }
        $name = $Matches[1]; $version = $Matches[2]
        if ($version.EndsWith('/go.mod')) { continue }
        if ($locked.ContainsKey($name) -and $locked[$name] -cne $version) {
            throw "The resolved Go graph contains multiple artifact versions of $name; resolve an unambiguous graph."
        }
        $locked[$name] = $version
    }
    $adapter = New-QaFoundryGoEcosystemAdapter
    $declared = @(& $adapter.ReadManifestDependencies $ManifestContent)
    $present = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($dependency in $declared) {
        $name = [string]$dependency.name
        if (-not $locked.ContainsKey($name) -or $locked[$name] -cne [string]$dependency.version) {
            throw "The Go manifest requirement $name@$($dependency.version) is absent from the resolved graph."
        }
        $null = $present.Add($name)
    }
    $missing = @($locked.Keys | Where-Object { -not $present.Contains($_) } | Sort-Object -CaseSensitive)
    if ($missing.Count -eq 0) { return $ManifestContent }
    $lines = @($ManifestContent.TrimEnd(), '', '// Transitive modules from the resolved dependency graph.', 'require (')
    foreach ($name in $missing) { $lines += "`t$name $($locked[$name]) // indirect" }
    return (($lines + ')' + '') -join "`n")
}

function New-QaFoundryGoEcosystemAdapter {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        id = "go"
        displayName = "Go (modules)"
        recipe = "go-module-sum"
        GetManifestFileName = { param([string]$ProjectName) return "go.mod" }
        manifestPattern = "(^|/)go\.mod$"
        lockFileName = "go.sum"
        lockFilePattern = "(^|/)go\.sum$"
        requiredRuntimeKeys = @("go_version")
        resolveScript = "Resolve-EcosystemLock.ps1"
        verifyScript = "Test-EcosystemLock.ps1"
        # A replace or exclude directive changes what is actually built without
        # changing the version beside it, which is exactly what a lock cannot see.
        unverifiableManifestKeys = @("replace", "exclude", "retract")
        localDependencyPrefixes = @("./", "../", "file:")

        # Go writes the 'v' as part of the version, and takes nothing but an
        # exact one; a pseudo-version names a commit and is still exact.
        exactVersionPattern = "^v?\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?(\+incompatible)?$"

        # A module path is a URL path, and the proxy encodes an upper-case letter
        # as "!" plus its lower-case form precisely because the two spellings are
        # different modules. Comparing them as written keeps that distinction.
        NormalizePackageName = { param([string]$Name) return ([string]$Name).Trim() }

        ReadRuntime = {
            param($Runtime)
            return [ordered]@{
                goVersion = [string]$Runtime["go_version"]
                modulePath = [string]$Runtime["module_path"]
            }
        }
        ResolveProposedRuntime = {
            param($Runtime, $Canonical, [string]$ProposedName, [string]$ProposedVersion)
            return Resolve-QaFoundryVersionedRuntime -Canonical $Canonical -Key "goVersion" `
                -Label "Go" -ProposedName $ProposedName -ProposedVersion $ProposedVersion
        }

        GetResolverTools = {
            param($Toolchain)
            return @(
                [pscustomobject]@{
                    key = 'pwsh'; command = 'pwsh'; label = 'PowerShell'
                    expectedVersion = '7'; match = 'major'; versionArguments = @('--version')
                },
                [pscustomobject]@{
                    key = "go"; command = "go"; label = "Go"
                    # A Go toolchain is named to two segments and ships a third
                    # nobody pinned, so 1.22.5 is exactly what "1.22" asked for.
                    expectedVersion = [string]$Toolchain.runtime.goVersion; match = "minor"
                    versionArguments = @("version")
                }
            )
        }

        # Go takes its configuration from the environment rather than from files,
        # so there is nothing on disk to neutralise; the variables are set on the
        # resolve command instead, where they can be seen next to what they affect.
        NewNeutralConfigFiles = {
            param($Toolchain, [string]$WorkRoot)
            return @()
        }

        GetResolveCommand = {
            param($Toolchain, $Context)
            $environment = @{
                GOPATH = [string]$Context.cacheRoot
                GOMODCACHE = (Join-Path ([string]$Context.cacheRoot) "mod")
                GOCACHE = (Join-Path ([string]$Context.cacheRoot) "build")
                # The single approved proxy, and no direct fetch behind it: a
                # fallback to "direct" would reach the origin repository for a
                # module the approved feed refused to serve.
                GOPROXY = [string]$Toolchain.source.registry
                GOFLAGS = "-mod=mod"
                GONOSUMCHECK = "0"
                GOTOOLCHAIN = "local"
            }
            return [pscustomobject]@{
                toolKey = 'pwsh'
                arguments = @('-NoProfile', '-File', (Join-Path $PSScriptRoot '../actions/Resolve-GoDependencyGraph.ps1'),
                    '-GoPath', [string]$Context.toolPaths['go'])
                environment = $environment
            }
        }

        ReadLockEntries = {
            param([string]$LockContent, $Toolchain)
            $byKey = [ordered]@{}
            $sawLine = $false
            foreach ($rawLine in @(([string]$LockContent) -split "`r?`n")) {
                $line = ([string]$rawLine).Trim()
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line -notmatch "^(\S+)\s+(\S+)\s+(\S+)$") {
                    return [pscustomobject]@{
                        parsed = $false
                        parseError = "a line is not a go.sum record: $line"
                    }
                }
                $sawLine = $true
                $module = [string]$Matches[1]
                $version = [string]$Matches[2]
                $digest = [string]$Matches[3]
                # go.sum records two hashes per module: one for the module zip
                # and one for its go.mod. They are the same entry, and the zip's
                # hash is the one that pins the code.
                $isGoMod = $version.EndsWith("/go.mod")
                if ($isGoMod) { $version = $version.Substring(0, $version.Length - 7) }
                $key = "$module@$version"
                if (-not $byKey.Contains($key)) {
                    $byKey[$key] = [pscustomobject]@{
                        key = $key
                        name = $module
                        version = $version
                        integrity = ""
                        goModIntegrity = ""
                        # The module proxy serves every module from the same
                        # host, and go.sum records no address of its own.
                        resolvedUrl = ""
                        isLocal = $false
                    }
                }
                if ($isGoMod) { $byKey[$key].goModIntegrity = $digest }
                else { $byKey[$key].integrity = $digest }
            }

            if (-not $sawLine) {
                return [pscustomobject]@{ parsed = $false; parseError = "the file records no module" }
            }
            $entries = @($byKey.Values)
            # A module whose zip was never hashed is one nothing pins, even
            # though its go.mod was recorded.
            foreach ($entry in $entries) {
                if ([string]::IsNullOrWhiteSpace([string]$entry.integrity)) {
                    $entry.integrity = ""
                }
            }

            $direct = [System.Collections.Generic.List[object]]::new()
            foreach ($approved in @($Toolchain.packages)) {
                $match = @($entries | Where-Object { [string]$_.name -ceq [string]$approved.name })
                if ($match.Count -eq 0) { continue }
                $direct.Add([pscustomobject]@{
                    name = [string]$approved.name
                    version = [string]$match[0].version
                    scope = [string]$approved.scope
                })
            }

            return [pscustomobject]@{
                parsed = $true
                parseError = ""
                formatVersion = ""
                identity = $null # go.sum records modules, not the owning project's identity.
                direct = @($direct)
                entries = @($entries)
                # Stated rather than skipped: go.sum carries no address at all.
                # What pins the bytes is the dirhash on every module, which the
                # toolchain checks on every build.
                originRecorded = $false
                originIsPerFile = $false
                feeds = @()
            }
        }

        NewManifestContent = {
            param($Toolchain, [string]$Name, [string]$Version)
            $modulePath = [string]$Toolchain.runtime.modulePath
            if ([string]::IsNullOrWhiteSpace($modulePath)) {
                $slug = $(if ([string]::IsNullOrWhiteSpace($Name)) { "automation" } else { ([string]$Name).ToLowerInvariant() -replace "[^a-z0-9._-]", "-" })
                $modulePath = "foundry.local/$slug"
            }
            $goVersion = [string]$Toolchain.runtime.goVersion
            if ([string]::IsNullOrWhiteSpace($goVersion)) { $goVersion = "1.22" }

            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("// Generated from the locked toolchain. Do not edit by hand.")
            $lines.Add("module $modulePath")
            $lines.Add("")
            $lines.Add("go $goVersion")
            $packages = @($Toolchain.packages | Sort-Object { [string]$_.name })
            if ($packages.Count -gt 0) {
                $lines.Add("")
                $lines.Add("require (")
                foreach ($package in $packages) {
                    # Go has no development scope, so a package that only the
                    # tests need is recorded in a comment this adapter reads back
                    # rather than being flattened away and guessed at later.
                    $suffix = $(if ([string]$package.scope -eq "dev") { " // scope: dev" } else { "" })
                    $lines.Add("`t$([string]$package.name) $([string]$package.version)$suffix")
                }
                $lines.Add(")")
            }
            return (($lines -join "`n") + "`n")
        }

        ReadManifestDependencies = {
            param([string]$ManifestContent)
            $declared = [System.Collections.Generic.List[object]]::new()
            $inBlock = $false
            foreach ($rawLine in @(([string]$ManifestContent) -split "`r?`n")) {
                $line = ([string]$rawLine).Trim()
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line -match "^require\s*\($") { $inBlock = $true; continue }
                if ($inBlock -and $line -eq ")") { $inBlock = $false; continue }

                $requirement = ""
                if ($inBlock -and -not $line.StartsWith("//")) { $requirement = $line }
                elseif ($line -match "^require\s+(.+)$") { $requirement = [string]$Matches[1] }
                if ([string]::IsNullOrWhiteSpace($requirement)) { continue }

                $scope = "runtime"
                $isIndirect = $false
                $comment = $requirement.IndexOf("//")
                if ($comment -ge 0) {
                    $isIndirect = $requirement.Substring($comment) -match '^//\s*indirect(?:\s|$)'
                    if ($requirement.Substring($comment) -match "scope:\s*dev") { $scope = "dev" }
                    $requirement = $requirement.Substring(0, $comment).Trim()
                }
                if ($requirement -match "^(\S+)\s+(\S+)$") {
                    $declared.Add([pscustomobject]@{
                        name = [string]$Matches[1]
                        version = [string]$Matches[2]
                        scope = $scope
                        isIndirect = $isIndirect
                    })
                }
            }
            return @($declared)
        }

        CompleteManifestFromLock = {
            param([string]$ManifestContent, [string]$LockContent)
            return Complete-QaFoundryGoManifestFromLock $ManifestContent $LockContent
        }

        ReadManifestIdentity = {
            param([string]$ManifestContent)
            $name = ""
            foreach ($rawLine in @(([string]$ManifestContent) -split "`r?`n")) {
                if ($rawLine -match "^module\s+(\S+)") { $name = [string]$Matches[1]; break }
            }
            # A Go module carries no version of its own; the repository tag is
            # the version, and inventing one here would put a number in the
            # manifest that nothing else agrees with.
            return [pscustomobject]@{ name = $name; version = "" }
        }

        GetPublishedVersions = {
            param([string]$Registry, [string]$Name)
            # The module proxy lower-cases capitals in a path with a "!" escape,
            # so github.com/Foo/Bar is requested as github.com/!foo/!bar.
            $escaped = [regex]::Replace([string]$Name, "[A-Z]", { param($match) "!" + $match.Value.ToLowerInvariant() })
            $uri = "$($Registry.TrimEnd('/'))/$escaped/@v/list"
            $response = Invoke-WebRequest -Uri $uri -Method Get -TimeoutSec 60 -UseBasicParsing -ErrorAction Stop
            return @(([string]$response.Content) -split "`r?`n" |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ })
        }

        SelectVersion = {
            param([string]$Requested, [string[]]$Published, [bool]$AllowPrerelease)
            return Select-QaFoundryGoVersion -Requested $Requested -Published $Published `
                -AllowPrerelease $AllowPrerelease
        }

        GetRuntimeRequirements = {
            param($Toolchain)
            return @("Go $([string]$Toolchain.runtime.goVersion)")
        }

        # How the lock is enforced when the framework is actually installed.
        # go mod download checks every module against go.sum and fails on a mismatch.
        lockEnforcement = "install"

        # Whether the manifest format itself says which dependencies exist
        # only to build and test the project. Where it does not, this run
        # would be comparing a decision it made against a fact the file
        # cannot carry, and refusing a manifest for disagreeing about
        # something it never stated. Here: go.mod requires everything the module
        # needs and says nothing about why.
        manifestExpressesDependencyScope = $false

        # Go modules take one version, not a range: the toolchain picks the
        # highest version any module in the build requires, so a range here has
        # nothing to resolve against.
        TestVersionRange = {
            param([string]$Requested)
            $request = ([string]$Requested).Trim()
            if ($request -in @("", "*", "latest")) {
                return New-QaFoundryRangeVerdict -Valid $true
            }
            if ($request -match "^[\^~<>=]" -or $request -match "[\[\]\(\)]" -or $request -match ",") {
                return New-QaFoundryRangeVerdict -Valid $false -Reason (
                    "'$Requested' is a range, and Go modules take an exact version. Name the " +
                    "version to use, for example 'v1.9.0'.")
            }
            if ($request -notmatch "^v?\d+(\.\d+)*([-+][0-9A-Za-z.\-]+)?$") {
                return New-QaFoundryRangeVerdict -Valid $false -Reason (
                    "'$Requested' is not a Go module version. Expected something like 'v1.9.0'.")
            }
            return New-QaFoundryRangeVerdict -Valid $true
        }
    # A go.mod is one module. Multi-module workspaces are declared in a go.work,
    # which is not this manifest, so a go.mod claims nothing below it.
    ReadWorkspaceMembers = { param([string]$ManifestPath) return @() }

        GetInstallCommand = {
            param($Toolchain, [string]$ProjectPath)
            return [pscustomobject]@{
                executable = "go"
                arguments = @("mod", "download")
                workingDirectory = $ProjectPath
            }
        }

        GetBuildCommand = {
            param($Toolchain, [string]$ProjectPath)
            # Test files are not compiled by "go build", and in an automation
            # project they are the code that matters, so the build vets them too.
            return [pscustomobject]@{
                executable = "go"
                arguments = @("vet", "-mod=readonly", "./...")
                workingDirectory = $ProjectPath
            }
        }

        GetTestCommand = {
            param($Toolchain, [string]$ProjectPath)
            # -count=1 defeats the test cache; a cached pass from an earlier
            # revision would otherwise look like this revision passing.
            return [pscustomobject]@{
                executable = "go"
                arguments = @("test", "-mod=readonly", "./...", "-v", "-count=1")
                workingDirectory = $ProjectPath
            }
        }

        ReadTestRunSummary = {
            param([string]$Output, [int]$ExitCode)
            $text = [string]$Output
            $passed = [regex]::Matches($text, "(?m)^\s*--- PASS:").Count
            $failed = [regex]::Matches($text, "(?m)^\s*--- FAIL:").Count
            $skipped = [regex]::Matches($text, "(?m)^\s*--- SKIP:").Count
            if (($passed + $failed + $skipped) -gt 0) {
                return [pscustomobject]@{
                    parsed = $true
                    total = $passed + $failed + $skipped
                    failed = $failed
                    skipped = $skipped
                }
            }
            # "no test files" is a real outcome of a run that found nothing, and
            # reporting it as a parsed zero is what lets the caller refuse it.
            if ($text -match "no test files" -or $text -match "no Go files") {
                return [pscustomobject]@{ parsed = $true; total = 0; failed = 0; skipped = 0 }
            }
            return [pscustomobject]@{ parsed = $false; total = 0; failed = 0; skipped = 0 }
        }

        NewNegativeProbe = {
            param($Toolchain, [string]$ProjectPath)
            # A Go file in the wrong package stops the package compiling, and a
            # compile error is not a failing test - it would prove the probe
            # broke the build rather than that a broken expectation turns the
            # run red. So the package clause is taken from the code already there.
            $package = "automation"
            $existing = @(Get-ChildItem -Path $ProjectPath -Filter "*.go" -File -ErrorAction SilentlyContinue |
                Sort-Object Name)
            foreach ($file in $existing) {
                $clause = @(Get-Content -Path $file.FullName -ErrorAction SilentlyContinue |
                    Where-Object { $_ -match "^package\s+(\S+)" } |
                    Select-Object -First 1)
                if ($clause.Count -gt 0 -and $clause[0] -match "^package\s+(\S+)") {
                    $package = [string]$Matches[1]
                    break
                }
            }
            return [pscustomobject]@{
                supported = $true
                relativePath = "foundry_negative_probe_test.go"
                content = @(
                    "package $package",
                    "",
                    "import `"testing`"",
                    "",
                    "func TestADeliberatelyBrokenExpectationFails(t *testing.T) {",
                    "`tif 1 != 2 {",
                    "`t`tt.Fatalf(`"expected 1 to equal 2`")",
                    "`t}",
                    "}",
                    ""
                ) -join "`n"
            }
        }
    }
}
