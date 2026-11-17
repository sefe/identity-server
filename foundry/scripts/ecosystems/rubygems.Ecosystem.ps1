# Everything this runtime knows about Ruby packaging in one place.
#
# RubyGems spells a pre-release with a dot rather than a hyphen - 5.0.0.rc1, not
# 5.0.0-rc1 - and its pessimistic operator means something no other ecosystem
# spells the same way, so both readings are given here rather than borrowed.

# A gem version is a dot-separated list in which any non-numeric segment starts
# the pre-release part. Rewriting it into the hyphenated shape lets the shared
# comparison order it correctly instead of reading "rc1" as a patch number.
function ConvertTo-QaFoundryGemComparableVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Version)

    $segments = @(([string]$Version).Trim() -split "\.")
    $release = [System.Collections.Generic.List[string]]::new()
    $prerelease = [System.Collections.Generic.List[string]]::new()
    foreach ($segment in $segments) {
        if ($prerelease.Count -eq 0 -and $segment -match "^\d+$") { $release.Add($segment) }
        else { $prerelease.Add($segment) }
    }
    if ($prerelease.Count -eq 0) { return ($release -join ".") }
    return (($release -join ".") + "-" + ($prerelease -join "."))
}

function Select-QaFoundryGemVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Published,
        [bool]$AllowPrerelease = $false
    )

    $usable = @($Published | Where-Object {
        $parts = ConvertTo-QaFoundryVersionParts -Version (ConvertTo-QaFoundryGemComparableVersion -Version $_)
        $parts.valid -and ($AllowPrerelease -or -not $parts.isPrerelease)
    })
    if ($usable.Count -eq 0) { return "" }

    $request = ([string]$Requested).Trim()
    $clauses = @()
    if ($request -notin @("", "*", "latest")) {
        $clauses = @($request -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    $satisfies = {
        param([string]$Candidate)
        $comparable = ConvertTo-QaFoundryGemComparableVersion -Version $Candidate
        foreach ($clause in $clauses) {
            if ($clause -notmatch "^(~>|>=|<=|!=|=|<|>)?\s*(.+)$") { return $false }
            $operator = [string]$Matches[1]
            $target = ([string]$Matches[2]).Trim()
            $targetComparable = ConvertTo-QaFoundryGemComparableVersion -Version $target
            $order = Compare-QaFoundryVersion -Left $comparable -Right $targetComparable
            switch ($operator) {
                ">=" { if ($order -lt 0) { return $false } }
                ">" { if ($order -le 0) { return $false } }
                "<=" { if ($order -gt 0) { return $false } }
                "<" { if ($order -ge 0) { return $false } }
                "!=" { if ($order -eq 0) { return $false } }
                "~>" {
                    # The pessimistic operator allows the last named segment to
                    # move and nothing above it: "~> 1.4.2" permits 1.4.9 and
                    # refuses 1.5.0, while "~> 1.4" permits 1.9 and refuses 2.0.
                    if ($order -lt 0) { return $false }
                    $named = @($target -split "\." | Where-Object { $_ -match "^\d+$" }).Count
                    $candidateParts = ConvertTo-QaFoundryVersionParts -Version $comparable
                    $targetParts = ConvertTo-QaFoundryVersionParts -Version $targetComparable
                    if ($named -ge 3) {
                        if ($candidateParts.major -ne $targetParts.major -or
                            $candidateParts.minor -ne $targetParts.minor) { return $false }
                    }
                    elseif ($named -eq 2) {
                        if ($candidateParts.major -ne $targetParts.major) { return $false }
                    }
                }
                default { if ($order -ne 0) { return $false } }
            }
        }
        return $true
    }

    $best = ""
    foreach ($candidate in $usable) {
        if (-not (& $satisfies $candidate)) { continue }
        if ([string]::IsNullOrWhiteSpace($best) -or
            (Compare-QaFoundryVersion `
                -Left (ConvertTo-QaFoundryGemComparableVersion -Version $candidate) `
                -Right (ConvertTo-QaFoundryGemComparableVersion -Version $best)) -gt 0) {
            $best = [string]$candidate
        }
    }
    return $best
}

function New-QaFoundryRubygemsEcosystemAdapter {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        id = "rubygems"
        displayName = "Ruby (Bundler)"
        recipe = "bundler-gemfile-lock"
        GetManifestFileName = { param([string]$ProjectName) return "Gemfile" }
        manifestPattern = "(^|/)Gemfile$"
        lockFileName = "Gemfile.lock"
        lockFilePattern = "(^|/)Gemfile\.lock$"
        requiredRuntimeKeys = @("ruby_version")
        resolveScript = "Resolve-EcosystemLock.ps1"
        verifyScript = "Test-EcosystemLock.ps1"
        # A Gemfile is executable Ruby, so these are the constructs that let it
        # decide at install time what the lock was supposed to have settled.
        unverifiableManifestKeys = @("path:", "git:", "github:", "branch:", "eval_gemfile", "require ")
        localDependencyPrefixes = @("path:", "git:", "github:", "file:")

        # RubyGems separates a pre-release with a dot rather than a hyphen. A
        # requirement written with '~>', '>=' or a comma is a range, whatever
        # else it resolves to today.
        exactVersionPattern = "^\d+(\.\d+)*(\.[A-Za-z][0-9A-Za-z]*)?$"

        # RubyGems keeps the name it was published under, and "Ascii85" is not
        # "ascii85". Both exist, which is the whole reason not to fold case.
        NormalizePackageName = { param([string]$Name) return ([string]$Name).Trim() }

        ReadRuntime = {
            param($Runtime)
            return [ordered]@{
                rubyVersion = [string]$Runtime["ruby_version"]
                bundlerVersion = [string]$Runtime["bundler_version"]
            }
        }
        ResolveProposedRuntime = {
            param($Runtime, $Canonical, [string]$ProposedName, [string]$ProposedVersion)
            return Resolve-QaFoundryVersionedRuntime -Canonical $Canonical -Key "rubyVersion" `
                -Label "Ruby" -ProposedName $ProposedName -ProposedVersion $ProposedVersion
        }

        GetResolverTools = {
            param($Toolchain)
            return @(
                [pscustomobject]@{
                    key = "bundle"; command = "bundle"; label = "Bundler"
                    expectedVersion = [string]$Toolchain.runtime.bundlerVersion
                    match = $(if ([string]::IsNullOrWhiteSpace([string]$Toolchain.runtime.bundlerVersion)) { "none" } else { "minor" })
                },
                [pscustomobject]@{
                    key = "ruby"; command = "ruby"; label = "Ruby"
                    expectedVersion = [string]$Toolchain.runtime.rubyVersion; match = "minor"
                }
            )
        }

        # Bundler reads its configuration from the home directory and from
        # .bundle/config beside the Gemfile, and either can redirect a source or
        # carry a credential. The local file is written empty and the home one
        # is already redirected into the work root.
        NewNeutralConfigFiles = {
            param($Toolchain, [string]$WorkRoot)
            return @(
                [pscustomobject]@{ key = "bundleconfig"; path = "project/.bundle/config"; content = "---`n" }
            )
        }

        GetResolveCommand = {
            param($Toolchain, $Context)
            return [pscustomobject]@{
                toolKey = "bundle"
                # --add-checksums is the difference between a lock that names
                # versions and one that pins bytes. Without it a Gemfile.lock
                # says which gem to fetch but nothing about what it contains.
                arguments = @("lock", "--add-checksums")
                environment = @{
                    BUNDLE_PATH = [string]$Context.cacheRoot
                    BUNDLE_APP_CONFIG = (Join-Path ([string]$Context.projectRoot) ".bundle")
                    BUNDLE_DISABLE_SHARED_GEMS = "true"
                    BUNDLE_FROZEN = "false"
                    GEM_HOME = [string]$Context.cacheRoot
                }
            }
        }

        ReadLockEntries = {
            param([string]$LockContent, $Toolchain)
            $entries = [System.Collections.Generic.List[object]]::new()
            $feeds = [System.Collections.Generic.List[string]]::new()
            $checksums = @{}
            $dependencies = [System.Collections.Generic.List[object]]::new()

            $section = ""
            $inSpecs = $false
            foreach ($rawLine in @(([string]$LockContent) -split "`r?`n")) {
                if ([string]::IsNullOrWhiteSpace($rawLine)) { continue }
                if ($rawLine -match "^\S") {
                    $section = $rawLine.Trim()
                    $inSpecs = $false
                    continue
                }
                $line = $rawLine.Trim()
                if ($section -in @("GEM", "PATH", "GIT")) {
                    if ($line -match "^remote:\s*(\S+)") { $feeds.Add([string]$Matches[1]); continue }
                    if ($line -eq "specs:") { $inSpecs = $true; continue }
                    if (-not $inSpecs) { continue }
                    # A gem is indented four spaces and its own dependencies six,
                    # which is the only thing separating a spec from a
                    # requirement of that spec.
                    if ($rawLine -match "^\s{4}(\S+)\s+\(([^)]+)\)\s*$" -and $rawLine -notmatch "^\s{6}") {
                        $entries.Add([pscustomobject]@{
                            key = [string]$Matches[1]
                            name = [string]$Matches[1]
                            version = [string]$Matches[2]
                            integrity = ""
                            resolvedUrl = ""
                            # A gem resolved from a path or a git remote is not a
                            # published package, whatever the lock calls it.
                            isLocal = ($section -ne "GEM")
                        })
                    }
                    continue
                }
                if ($section -eq "CHECKSUMS") {
                    if ($line -match "^(\S+)\s+\(([^)]+)\)\s+(\S+)$") {
                        $checksums["$($Matches[1])|$($Matches[2])"] = [string]$Matches[3]
                    }
                    continue
                }
                if ($section -eq "DEPENDENCIES") {
                    if ($line -match "^(\S+)(?:\s+\(([^)]*)\))?") {
                        $dependencies.Add([pscustomobject]@{
                            name = ([string]$Matches[1]).TrimEnd("!")
                            version = ((([string]$Matches[2]) -replace "^=\s*", ""))
                        })
                    }
                    continue
                }
            }

            if ($entries.Count -eq 0) {
                return [pscustomobject]@{ parsed = $false; parseError = "the lock names no gem" }
            }
            foreach ($entry in $entries) {
                $key = "$([string]$entry.name)|$([string]$entry.version)"
                if ($checksums.ContainsKey($key)) { $entry.integrity = [string]$checksums[$key] }
            }

            # Bundler records the direct set in DEPENDENCIES without saying which
            # group each came from, so the decision's own scope is used and the
            # version is taken from the resolved spec.
            $direct = [System.Collections.Generic.List[object]]::new()
            foreach ($dependency in $dependencies) {
                $approved = @($Toolchain.packages | Where-Object { [string]$_.name -ceq [string]$dependency.name })
                $resolved = @($entries | Where-Object { [string]$_.name -ceq [string]$dependency.name })
                $direct.Add([pscustomobject]@{
                    name = [string]$dependency.name
                    version = $(if ($resolved.Count -gt 0) { [string]$resolved[0].version } else { [string]$dependency.version })
                    scope = $(if ($approved.Count -gt 0) { [string]$approved[0].scope } else { "runtime" })
                })
            }

            return [pscustomobject]@{
                parsed = $true
                parseError = ""
                formatVersion = ""
                identity = [pscustomobject]@{ name = ""; version = "" }
                direct = @($direct)
                entries = @($entries)
                originRecorded = $true
                # A Gemfile.lock names its source once per section rather than
                # per gem, so the origin is checked there.
                originIsPerFile = $true
                feeds = @($feeds)
            }
        }

        NewManifestContent = {
            param($Toolchain, [string]$Name, [string]$Version)
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("# frozen_string_literal: true")
            $lines.Add("# Generated from the locked toolchain. Do not edit by hand.")
            if (-not [string]::IsNullOrWhiteSpace($Name)) { $lines.Add("# Project: $Name") }
            if (-not [string]::IsNullOrWhiteSpace($Version)) { $lines.Add("# Version: $Version") }
            $lines.Add("")
            $source = [string]$Toolchain.source.registry
            if ([string]::IsNullOrWhiteSpace($source)) { $source = "https://rubygems.org" }
            $lines.Add("source `"$source`"")
            $lines.Add("")
            if (-not [string]::IsNullOrWhiteSpace([string]$Toolchain.runtime.rubyVersion)) {
                $lines.Add("ruby `"$([string]$Toolchain.runtime.rubyVersion)`"")
                $lines.Add("")
            }
            # Bundler's development group is the closest thing to a development
            # scope, and keeping the two apart means a deployment install can
            # leave the linting tools out.
            $runtime = @($Toolchain.packages | Where-Object { [string]$_.scope -ne "dev" } | Sort-Object { [string]$_.name })
            $development = @($Toolchain.packages | Where-Object { [string]$_.scope -eq "dev" } | Sort-Object { [string]$_.name })
            foreach ($package in $runtime) {
                $lines.Add("gem `"$([string]$package.name)`", `"$([string]$package.version)`"")
            }
            if ($development.Count -gt 0) {
                $lines.Add("")
                $lines.Add("group :development, :test do")
                foreach ($package in $development) {
                    $lines.Add("  gem `"$([string]$package.name)`", `"$([string]$package.version)`"")
                }
                $lines.Add("end")
            }
            return (($lines -join "`n") + "`n")
        }

        ReadManifestDependencies = {
            param([string]$ManifestContent)
            $declared = [System.Collections.Generic.List[object]]::new()
            $scope = "runtime"
            foreach ($rawLine in @(([string]$ManifestContent) -split "`r?`n")) {
                $line = ([string]$rawLine).Trim()
                if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
                if ($line -match "^group\s+.*\bdo\b") {
                    $scope = $(if ($line -match ":development|:test") { "dev" } else { "runtime" })
                    continue
                }
                if ($line -eq "end") { $scope = "runtime"; continue }
                if ($line -match "^gem\s+[`"']([^`"']+)[`"']\s*(?:,\s*[`"']([^`"']+)[`"'])?") {
                    $declared.Add([pscustomobject]@{
                        name = [string]$Matches[1]
                        version = [string]$Matches[2]
                        scope = $scope
                    })
                }
            }
            return @($declared)
        }

        ReadManifestIdentity = {
            param([string]$ManifestContent)
            $name = ""
            $version = ""
            foreach ($rawLine in @(([string]$ManifestContent) -split "`r?`n")) {
                if ($rawLine -match "^#\s*Project:\s*(.+)$") { $name = ([string]$Matches[1]).Trim() }
                if ($rawLine -match "^#\s*Version:\s*(.+)$") { $version = ([string]$Matches[1]).Trim() }
            }
            return [pscustomobject]@{ name = $name; version = $version }
        }

        GetPublishedVersions = {
            param([string]$Registry, [string]$Name)
            $uri = "$($Registry.TrimEnd('/'))/api/v1/versions/$([Uri]::EscapeDataString($Name)).json"
            $document = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 60 -ErrorAction Stop
            # A yanked version still appears in the index but cannot be
            # installed, so pinning one would produce a lock that never restores.
            return @($document |
                Where-Object { -not [bool]$_.yanked } |
                ForEach-Object { [string]$_.number })
        }

        SelectVersion = {
            param([string]$Requested, [string[]]$Published, [bool]$AllowPrerelease)
            return Select-QaFoundryGemVersion -Requested $Requested -Published $Published `
                -AllowPrerelease $AllowPrerelease
        }

        GetRuntimeRequirements = {
            param($Toolchain)
            $requirements = @("Ruby $([string]$Toolchain.runtime.rubyVersion)")
            if (-not [string]::IsNullOrWhiteSpace([string]$Toolchain.runtime.bundlerVersion)) {
                $requirements += "Bundler $([string]$Toolchain.runtime.bundlerVersion)"
            }
            return $requirements
        }

        # How the lock is enforced when the framework is actually installed.
        # bundle install --frozen refuses to update the lock, so an install that would change the resolved set fails.
        lockEnforcement = "install"

        # Whether the manifest format itself says which dependencies exist
        # only to build and test the project. Where it does not, this run
        # would be comparing a decision it made against a fact the file
        # cannot carry, and refusing a manifest for disagreeing about
        # something it never stated. Here: a gem declared inside a :development
        # or :test group says so in the Gemfile.
        manifestExpressesDependencyScope = $true

        TestVersionRange = {
            param([string]$Requested)
            return Test-QaFoundryClauseRange -Requested $Requested -Ecosystem "RubyGems" `
                -OperatorPattern "~>|>=|<=|!=|=|<|>" -Example "~> 1.49"
        }
    # A Gemfile resolves one bundle. It can point at a path, but it does not
    # declare member projects that install as one.
    ReadWorkspaceMembers = { param([string]$ManifestPath) return @() }

        GetInstallCommand = {
            param($Toolchain, [string]$ProjectPath)
            # A frozen install refuses to update the lock, so an install that
            # would have changed the resolved set fails here instead of quietly
            # rewriting the file the review approved.
            return [pscustomobject]@{
                executable = "bundle"
                arguments = @("install", "--frozen", "--jobs", "4", "--retry", "2")
                workingDirectory = $ProjectPath
            }
        }

        GetBuildCommand = {
            param($Toolchain, [string]$ProjectPath)
            # Ruby has no build step, so the equivalent check is that every file
            # actually compiles - which is what a build would have told us.
            return [pscustomobject]@{
                executable = "bundle"
                arguments = @("exec", "ruby", "-e",
                    "Dir.glob('**/*.rb').sort.each { |f| RubyVM::InstructionSequence.compile_file(f) }")
                workingDirectory = $ProjectPath
            }
        }

        GetTestCommand = {
            param($Toolchain, [string]$ProjectPath)
            $names = @($Toolchain.packages | ForEach-Object { ([string]$_.name).ToLowerInvariant() })
            if ($names -contains "cucumber" -and $names -notcontains "rspec") {
                return [pscustomobject]@{
                    executable = "bundle"
                    arguments = @("exec", "cucumber", "--publish-quiet")
                    workingDirectory = $ProjectPath
                }
            }
            return [pscustomobject]@{
                executable = "bundle"
                arguments = @("exec", "rspec", "--format", "progress")
                workingDirectory = $ProjectPath
            }
        }

        ReadTestRunSummary = {
            param([string]$Output, [int]$ExitCode)
            $text = [string]$Output
            if ($text -match "(\d+)\s+examples?,\s*(\d+)\s+failures?") {
                # Captured before anything else matches: PowerShell replaces
                # $Matches wholesale on the next -match, and reading the totals
                # afterwards read the pending count as the number of tests.
                $total = [int]$Matches[1]
                $failed = [int]$Matches[2]
                $skipped = 0
                # RSpec calls them pending, and prints them in the same line.
                if ($text -match "(\d+)\s+pending") { $skipped = [int]$Matches[1] }
                return [pscustomobject]@{
                    parsed = $true
                    total = $total
                    failed = $failed
                    skipped = $skipped
                }
            }
            if ($text -match "(\d+)\s+scenarios?\s*\(([^)]*)\)") {
                $total = [int]$Matches[1]
                $breakdown = [string]$Matches[2]
                $failed = 0
                $skipped = 0
                if ($breakdown -match "(\d+)\s+failed") { $failed = [int]$Matches[1] }
                if ($breakdown -match "(\d+)\s+skipped") { $skipped += [int]$Matches[1] }
                if ($breakdown -match "(\d+)\s+undefined") { $skipped += [int]$Matches[1] }
                if ($breakdown -match "(\d+)\s+pending") { $skipped += [int]$Matches[1] }
                return [pscustomobject]@{
                    parsed = $true; total = $total; failed = $failed; skipped = $skipped
                }
            }
            return [pscustomobject]@{ parsed = $false; total = 0; failed = 0; skipped = 0 }
        }

        NewNegativeProbe = {
            param($Toolchain, [string]$ProjectPath)
            $names = @($Toolchain.packages | ForEach-Object { ([string]$_.name).ToLowerInvariant() })
            if ($names -contains "rspec" -or $names -contains "rspec-core") {
                return [pscustomobject]@{
                    supported = $true
                    relativePath = "spec/foundry_negative_probe_spec.rb"
                    content = @(
                        "# frozen_string_literal: true",
                        "",
                        "RSpec.describe 'the foundry negative probe' do",
                        "  it 'fails on a deliberately broken expectation' do",
                        "    expect(1).to eq(2)",
                        "  end",
                        "end",
                        ""
                    ) -join "`n"
                }
            }
            return [pscustomobject]@{ supported = $false; relativePath = ""; content = "" }
        }
    }
}
