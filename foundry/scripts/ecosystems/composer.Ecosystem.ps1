# Everything this runtime knows about PHP packaging with Composer in one place.
#
# Composer's constraints look like npm's and mean something slightly different:
# its tilde widens by one segment less than npm's does, and its "||" makes a
# constraint a set of alternatives rather than a single range. Reading a
# Composer constraint with npm's rules would pin versions Composer would refuse.

function Select-QaFoundryComposerVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Published,
        [bool]$AllowPrerelease = $false
    )

    $usable = @($Published | Where-Object {
        $parts = ConvertTo-QaFoundryVersionParts -Version $_
        $parts.valid -and ($AllowPrerelease -or -not $parts.isPrerelease)
    })
    if ($usable.Count -eq 0) { return "" }

    $request = ([string]$Requested).Trim()
    if ($request -in @("", "*", "latest")) {
        $highest = Get-QaFoundryHighestVersion -Versions $usable
        $match = @($usable | Where-Object {
            (Compare-QaFoundryVersion -Left $_ -Right $highest) -eq 0
        })
        return $(if ($match.Count -gt 0) { [string]$match[0] } else { "" })
    }

    $satisfiesClause = {
        param([string]$Candidate, [string]$Clause)
        $clause = ([string]$Clause).Trim()
        if ([string]::IsNullOrWhiteSpace($clause)) { return $true }
        if ($clause -notmatch "^(\^|~|>=|<=|!=|==|=|<|>)?\s*v?(.+)$") { return $false }
        $operator = [string]$Matches[1]
        $target = ([string]$Matches[2]).Trim()
        $wildcard = $target.EndsWith(".*")
        if ($wildcard) { $target = $target.Substring(0, $target.Length - 2) }
        $named = @($target -split "[.\-+]" | Where-Object { $_ -match "^\d+$" }).Count
        $order = Compare-QaFoundryVersion -Left $Candidate -Right $target
        $candidateParts = ConvertTo-QaFoundryVersionParts -Version $Candidate
        $targetParts = ConvertTo-QaFoundryVersionParts -Version $target

        switch ($operator) {
            ">=" { return $order -ge 0 }
            ">" { return $order -gt 0 }
            "<=" { return $order -le 0 }
            "<" { return $order -lt 0 }
            "!=" { return $order -ne 0 }
            "^" {
                # The caret keeps the leftmost non-zero segment. Composer treats
                # a leading zero the same way npm does, so ^0.4 stops at 0.5.
                if ($order -lt 0) { return $false }
                if ($targetParts.major -ne 0) { return $candidateParts.major -eq $targetParts.major }
                if ($targetParts.minor -ne 0 -or $named -ge 2) {
                    return $candidateParts.major -eq 0 -and $candidateParts.minor -eq $targetParts.minor
                }
                return $candidateParts.major -eq 0
            }
            "~" {
                # Composer's tilde allows the last named segment to move: ~1.2
                # reaches 1.9 where npm's would stop at 1.2.x, and ~1.2.3 stops
                # at 1.2.x in both.
                if ($order -lt 0) { return $false }
                if ($named -ge 3) {
                    return $candidateParts.major -eq $targetParts.major -and
                        $candidateParts.minor -eq $targetParts.minor
                }
                return $candidateParts.major -eq $targetParts.major
            }
            default {
                if ($wildcard) {
                    if ($named -ge 1 -and $candidateParts.major -ne $targetParts.major) { return $false }
                    if ($named -ge 2 -and $candidateParts.minor -ne $targetParts.minor) { return $false }
                    return $true
                }
                return $order -eq 0
            }
        }
    }

    # "||" separates alternatives and a space or comma joins requirements, so an
    # alternative is satisfied when every one of its parts holds.
    $alternatives = @($request -split "\|\|" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $best = ""
    foreach ($candidate in $usable) {
        $satisfied = $false
        foreach ($alternative in $alternatives) {
            $clauses = @($alternative -split "[,\s]+" | Where-Object { $_ })
            $all = $true
            foreach ($clause in $clauses) {
                if (-not (& $satisfiesClause $candidate $clause)) { $all = $false; break }
            }
            if ($all) { $satisfied = $true; break }
        }
        if (-not $satisfied) { continue }
        if ([string]::IsNullOrWhiteSpace($best) -or
            (Compare-QaFoundryVersion -Left $candidate -Right $best) -gt 0) {
            $best = [string]$candidate
        }
    }
    return $best
}

function New-QaFoundryComposerEcosystemAdapter {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        id = "composer"
        displayName = "PHP (Composer)"
        recipe = "composer-package-lock"
        GetManifestFileName = { param([string]$ProjectName) return "composer.json" }
        manifestPattern = "(^|/)composer\.json$"
        lockFileName = "composer.lock"
        lockFilePattern = "(^|/)composer\.lock$"
        requiredRuntimeKeys = @("php_version")
        resolveScript = "Resolve-EcosystemLock.ps1"
        verifyScript = "Test-EcosystemLock.ps1"
        # Each of these lets an install take something the lock does not name:
        # another repository, a package nobody published, or a rule that relaxes
        # the constraints the lock was resolved against.
        unverifiableManifestKeys = @("repositories", "minimum-stability", "prefer-stable", "provide", "replace")
        localDependencyPrefixes = @("path", "vcs", "file:", "../", "./")

        # Composer tolerates a leading 'v' on a released version. A constraint
        # built from '^', '~', '||', '*' or a space-separated pair is a range.
        exactVersionPattern = "^v?\d+\.\d+(\.\d+){0,2}(-[0-9A-Za-z.-]+)?$"

        # Packagist canonicalises vendor/package to lower case and resolves a
        # differently-cased request to the same package, so folding case here
        # matches what composer would actually install.
        NormalizePackageName = { param([string]$Name) return ([string]$Name).Trim().ToLowerInvariant() }

        ReadRuntime = {
            param($Runtime)
            return [ordered]@{
                phpVersion = [string]$Runtime["php_version"]
                composerVersion = [string]$Runtime["composer_version"]
            }
        }
        ResolveProposedRuntime = {
            param($Runtime, $Canonical, [string]$ProposedName, [string]$ProposedVersion)
            return Resolve-QaFoundryVersionedRuntime -Canonical $Canonical -Key "phpVersion" `
                -Label "PHP" -ProposedName $ProposedName -ProposedVersion $ProposedVersion
        }

        GetResolverTools = {
            param($Toolchain)
            return @(
                [pscustomobject]@{
                    key = "composer"; command = "composer"; label = "Composer"
                    expectedVersion = [string]$Toolchain.runtime.composerVersion
                    match = $(if ([string]::IsNullOrWhiteSpace([string]$Toolchain.runtime.composerVersion)) { "none" } else { "major" })
                },
                [pscustomobject]@{
                    key = "php"; command = "php"; label = "PHP"
                    expectedVersion = [string]$Toolchain.runtime.phpVersion; match = "minor"
                    versionArguments = @("-r", "echo PHP_VERSION;")
                }
            )
        }

        # Composer reads a global config and an auth file from its home
        # directory, and either can add a repository or a credential. The home
        # is redirected into the work root and the files are written empty.
        NewNeutralConfigFiles = {
            param($Toolchain, [string]$WorkRoot)
            return @(
                [pscustomobject]@{ key = "composerconfig"; path = "composer-home/config.json"; content = "{}`n" },
                [pscustomobject]@{ key = "composerauth"; path = "composer-home/auth.json"; content = "{}`n" }
            )
        }

        GetResolveCommand = {
            param($Toolchain, $Context)
            $home = Split-Path ([string]$Context.configFiles["composerconfig"]) -Parent
            return [pscustomobject]@{
                toolKey = "composer"
                # --no-install writes the lock without unpacking anything, which
                # is the whole act being asked for here.
                arguments = @(
                    "update", "--no-install", "--no-interaction", "--no-progress",
                    "--no-audit", "--no-ansi", "--prefer-stable"
                )
                environment = @{
                    COMPOSER_HOME = $home
                    COMPOSER_CACHE_DIR = [string]$Context.cacheRoot
                    # The one place a Composer resolution can be pointed at an
                    # approved mirror without writing a repository into the
                    # manifest, where it would be an unverifiable key.
                    COMPOSER_REPO_PACKAGIST = [string]$Toolchain.source.registry
                    COMPOSER_NO_INTERACTION = "1"
                    COMPOSER_DISABLE_XDEBUG_WARN = "1"
                }
            }
        }

        ReadLockEntries = {
            param([string]$LockContent, $Toolchain)
            try { $lock = $LockContent | ConvertFrom-Json -Depth 100 }
            catch {
                return [pscustomobject]@{ parsed = $false; parseError = $_.Exception.Message }
            }

            $lockKeys = @(Get-QaFoundryPropertyNames -InputObject $lock)
            $entries = [System.Collections.Generic.List[object]]::new()
            $direct = [System.Collections.Generic.List[object]]::new()

            foreach ($section in @(
                @{ property = "packages"; scope = "runtime" },
                @{ property = "packages-dev"; scope = "dev" }
            )) {
                if ($lockKeys -notcontains $section.property) { continue }
                foreach ($package in @($lock.($section.property))) {
                    $fields = @(Get-QaFoundryPropertyNames -InputObject $package)
                    $name = [string]$package.name
                    # Composer keeps the tag as it was pushed, so a leading "v"
                    # is part of the tag rather than of the version.
                    $version = ([string]$package.version) -replace "^v", ""
                    $distUrl = ""
                    $digest = ""
                    if ($fields -contains "dist" -and $null -ne $package.dist) {
                        $distFields = @(Get-QaFoundryPropertyNames -InputObject $package.dist)
                        if ($distFields -contains "url") { $distUrl = [string]$package.dist.url }
                        if ($distFields -contains "shasum") { $digest = [string]$package.dist.shasum }
                    }
                    # A package taken from source rather than from a published
                    # archive is built from a working copy of a repository, which
                    # is not something a lock can pin.
                    $isLocal = [string]::IsNullOrWhiteSpace($distUrl)
                    $entries.Add([pscustomobject]@{
                        key = $name
                        name = $name
                        version = $version
                        integrity = $digest
                        resolvedUrl = $distUrl
                        # Composer copies each package's declared licence into
                        # the lock as an array, because a package may be offered
                        # under more than one.
                        license = $(if ($fields -contains "license") {
                            (@(@($package.license) | ForEach-Object { [string]$_ } |
                                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join " OR ")
                        } else { "" })
                        isLocal = $isLocal
                    })
                    $approved = @($Toolchain.packages | Where-Object { [string]$_.name -eq $name })
                    if ($approved.Count -gt 0) {
                        $direct.Add([pscustomobject]@{
                            name = $name
                            version = $version
                            scope = [string]$section.scope
                        })
                    }
                }
            }

            if ($entries.Count -eq 0) {
                return [pscustomobject]@{ parsed = $false; parseError = "the lock names no package" }
            }

            return [pscustomobject]@{
                parsed = $true
                parseError = ""
                formatVersion = ""
                identity = [pscustomobject]@{ name = ""; version = "" }
                direct = @($direct)
                entries = @($entries)
                # A Composer lock records the archive address per package, so
                # every one of them is checked against the approved feed. The
                # dist host is a content delivery domain rather than the API
                # host, which is why the decision's registry has to name it.
                originRecorded = $true
                originIsPerFile = $false
                feeds = @()
                # Composer records a licence per package, so a licence policy can
                # be decided from the lock alone.
                licensesRecorded = $true
            }
        }

        NewManifestContent = {
            param($Toolchain, [string]$Name, [string]$Version)
            $packageName = $(if ([string]::IsNullOrWhiteSpace($Name)) { "foundry/automation" } else { ([string]$Name).ToLowerInvariant() -replace "[^a-z0-9._-]", "-" })
            if ($packageName -notmatch "/") { $packageName = "foundry/$packageName" }

            $require = [ordered]@{}
            if (-not [string]::IsNullOrWhiteSpace([string]$Toolchain.runtime.phpVersion)) {
                $require["php"] = ">=$([string]$Toolchain.runtime.phpVersion)"
            }
            $requireDev = [ordered]@{}
            foreach ($package in @($Toolchain.packages | Sort-Object { [string]$_.name })) {
                $target = $(if ([string]$package.scope -eq "dev") { $requireDev } else { $require })
                $target[[string]$package.name] = [string]$package.version
            }

            $manifest = [ordered]@{
                name = $packageName
                description = "Generated from the locked toolchain. Do not edit by hand."
                type = "project"
            }
            if (-not [string]::IsNullOrWhiteSpace($Version)) { $manifest["version"] = [string]$Version }
            $manifest["require"] = $require
            if ($requireDev.Count -gt 0) { $manifest["require-dev"] = $requireDev }
            # An install that may choose a pre-release is an install the lock did
            # not describe, so the manifest says so rather than leaving it to the
            # machine's Composer defaults.
            $manifest["minimum-stability"] = "stable"
            $manifest["prefer-stable"] = $true
            $manifest["config"] = [ordered]@{ "sort-packages" = $true }

            return (($manifest | ConvertTo-Json -Depth 8) + "`n")
        }

        ReadManifestDependencies = {
            param([string]$ManifestContent)
            $declared = [System.Collections.Generic.List[object]]::new()
            try { $manifest = $ManifestContent | ConvertFrom-Json } catch { return @() }
            foreach ($section in @(
                @{ property = "require"; scope = "runtime" },
                @{ property = "require-dev"; scope = "dev" }
            )) {
                $node = $manifest.PSObject.Properties[$section.property]
                if ($null -eq $node -or $null -eq $node.Value) { continue }
                foreach ($entry in $node.Value.PSObject.Properties) {
                    # The platform requirements are constraints on the machine,
                    # not packages to resolve, and treating them as packages
                    # would send the resolver looking for a "php" release.
                    if ($entry.Name -eq "php" -or $entry.Name -like "ext-*" -or $entry.Name -like "lib-*") { continue }
                    $declared.Add([pscustomobject]@{
                        name = [string]$entry.Name
                        version = [string]$entry.Value
                        scope = $section.scope
                    })
                }
            }
            return @($declared)
        }

        ReadManifestIdentity = {
            param([string]$ManifestContent)
            try { $manifest = $ManifestContent | ConvertFrom-Json } catch {
                return [pscustomobject]@{ name = ""; version = "" }
            }
            return [pscustomobject]@{
                name = [string]$manifest.name
                version = [string]$manifest.version
            }
        }

        GetPublishedVersions = {
            param([string]$Registry, [string]$Name)
            $uri = "$($Registry.TrimEnd('/'))/p2/$([string]$Name).json"
            $document = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 60 -ErrorAction Stop
            $node = $document.packages.PSObject.Properties[[string]$Name]
            if ($null -eq $node) { return @() }
            # Packagist reports tags as they were pushed, so a leading "v" is
            # part of the tag rather than the version and is dropped here.
            return @($node.Value | ForEach-Object { ([string]$_.version) -replace "^v", "" })
        }

        SelectVersion = {
            param([string]$Requested, [string[]]$Published, [bool]$AllowPrerelease)
            return Select-QaFoundryComposerVersion -Requested $Requested -Published $Published `
                -AllowPrerelease $AllowPrerelease
        }

        GetRuntimeRequirements = {
            param($Toolchain)
            $requirements = @("PHP $([string]$Toolchain.runtime.phpVersion)")
            if (-not [string]::IsNullOrWhiteSpace([string]$Toolchain.runtime.composerVersion)) {
                $requirements += "Composer $([string]$Toolchain.runtime.composerVersion)"
            }
            return $requirements
        }

        # How the lock is enforced when the framework is actually installed.
        # composer install reads composer.lock and installs exactly what it names.
        lockEnforcement = "install"

        # Whether the manifest format itself says which dependencies exist
        # only to build and test the project. Where it does not, this run
        # would be comparing a decision it made against a fact the file
        # cannot carry, and refusing a manifest for disagreeing about
        # something it never stated. Here: require and require-dev are two
        # different objects in the manifest.
        manifestExpressesDependencyScope = $true

        # Composer reads the same comparators as npm and, unlike this
        # installation's npm reader, honours '||' alternatives and
        # space-separated pairs, so those are accepted here.
        TestVersionRange = {
            param([string]$Requested)
            $request = ([string]$Requested).Trim()
            if ($request -in @("", "*", "latest")) {
                return New-QaFoundryRangeVerdict -Valid $true
            }
            if ($request -match "[\[\]\(\)]") {
                return New-QaFoundryRangeVerdict -Valid $false -Reason (
                    "'$Requested' is interval notation, which belongs to NuGet and Maven. Composer " +
                    "writes the same intent as '^1.49.0'.")
            }
            if ($request -match "~>") {
                return New-QaFoundryRangeVerdict -Valid $false -Reason (
                    "'$Requested' uses RubyGems' pessimistic operator. Composer writes the same " +
                    "intent as '~1.49' or '^1.49.0'.")
            }
            foreach ($alternative in @($request -split "\|\|")) {
                $clauses = @($alternative -split "[,\s]+" | Where-Object { $_ })
                if ($clauses.Count -eq 0) {
                    return New-QaFoundryRangeVerdict -Valid $false -Reason (
                        "'$Requested' leaves an alternative empty, so there is nothing to resolve " +
                        "against. Expected something like '^1.49.0 || ^2.0.0'.")
                }
                foreach ($clause in $clauses) {
                    if ($clause -notmatch "^(\^|~|>=|<=|!=|==|=|<|>)?v?(\d+|\*)(\.(\d+|\*)){0,3}([-+][0-9A-Za-z.\-]+)?$") {
                        return New-QaFoundryRangeVerdict -Valid $false -Reason (
                            "'$clause' in '$Requested' is not a Composer constraint. Expected " +
                            "something like '^1.49.0', '~1.49' or '>=1.49.0 <2.0.0'.")
                    }
                }
            }
            return New-QaFoundryRangeVerdict -Valid $true
        }
    # Composer has no workspace concept: a composer.json describes one package
    # and never claims the ones beside or below it.
    ReadWorkspaceMembers = { param([string]$ManifestPath) return @() }

        GetInstallCommand = {
            param($Toolchain, [string]$ProjectPath)
            return [pscustomobject]@{
                executable = "composer"
                arguments = @("install", "--no-interaction", "--no-progress", "--no-ansi")
                workingDirectory = $ProjectPath
            }
        }

        GetBuildCommand = {
            param($Toolchain, [string]$ProjectPath)
            # PHP has no build step. Validating the manifest against the lock is
            # the equivalent check: it fails when the two have drifted apart.
            return [pscustomobject]@{
                executable = "composer"
                arguments = @("validate", "--no-interaction", "--no-check-publish", "--strict")
                workingDirectory = $ProjectPath
            }
        }

        GetTestCommand = {
            param($Toolchain, [string]$ProjectPath)
            $names = @($Toolchain.packages | ForEach-Object { ([string]$_.name).ToLowerInvariant() })
            if (@($names | Where-Object { $_ -like "behat/*" }).Count -gt 0 -and
                @($names | Where-Object { $_ -like "phpunit/*" }).Count -eq 0) {
                return [pscustomobject]@{
                    executable = "php"
                    arguments = @("vendor/bin/behat", "--no-colors")
                    workingDirectory = $ProjectPath
                }
            }
            return [pscustomobject]@{
                executable = "php"
                arguments = @("vendor/bin/phpunit", "--colors=never")
                workingDirectory = $ProjectPath
            }
        }

        ReadTestRunSummary = {
            param([string]$Output, [int]$ExitCode)
            $text = [string]$Output
            if ($text -match "Tests:\s*(\d+)") {
                $total = [int]$Matches[1]
                $failed = 0
                $skipped = 0
                if ($text -match "Failures:\s*(\d+)") { $failed += [int]$Matches[1] }
                if ($text -match "Errors:\s*(\d+)") { $failed += [int]$Matches[1] }
                if ($text -match "Skipped:\s*(\d+)") { $skipped += [int]$Matches[1] }
                if ($text -match "Incomplete:\s*(\d+)") { $skipped += [int]$Matches[1] }
                return [pscustomobject]@{
                    parsed = $true; total = $total; failed = $failed; skipped = $skipped
                }
            }
            if ($text -match "OK\s*\((\d+)\s+tests?") {
                return [pscustomobject]@{
                    parsed = $true; total = [int]$Matches[1]; failed = 0; skipped = 0
                }
            }
            if ($text -match "No tests executed") {
                return [pscustomobject]@{ parsed = $true; total = 0; failed = 0; skipped = 0 }
            }
            return [pscustomobject]@{ parsed = $false; total = 0; failed = 0; skipped = 0 }
        }

        NewNegativeProbe = {
            param($Toolchain, [string]$ProjectPath)
            $names = @($Toolchain.packages | ForEach-Object { ([string]$_.name).ToLowerInvariant() })
            if (@($names | Where-Object { $_ -like "phpunit/*" }).Count -gt 0) {
                return [pscustomobject]@{
                    supported = $true
                    relativePath = "tests/FoundryNegativeProbeTest.php"
                    content = @(
                        "<?php",
                        "",
                        "declare(strict_types=1);",
                        "",
                        "namespace Tests;",
                        "",
                        "use PHPUnit\Framework\TestCase;",
                        "",
                        "final class FoundryNegativeProbeTest extends TestCase",
                        "{",
                        "    public function testADeliberatelyBrokenExpectationFails(): void",
                        "    {",
                        "        self::assertSame(2, 1);",
                        "    }",
                        "}",
                        ""
                    ) -join "`n"
                }
            }
            return [pscustomobject]@{ supported = $false; relativePath = ""; content = "" }
        }
    }
}
