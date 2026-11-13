# Everything this runtime knows about NuGet in one place.
#
# NuGet is not npm with different file names. A manifest is an MSBuild project
# rather than a JSON document, there is no separate development dependency
# section - the nearest honest equivalent is PrivateAssets - and the registry is
# a service index that has to be read before any package address is known. Each
# of those differences is a place where a runtime that assumed npm would have
# quietly produced something unbuildable.

# A manifest and a NuGet.config are XML, and everything written into them - a
# package name, a version, a feed URL, the project's own name - reaches this
# file from a model-authored decision. Written raw, a value carrying a quote or
# an angle bracket would either break the document or add an element nobody
# chose. MSBuild also reads $(...) and %(...) as expressions, so those openings
# are neutralised as well: a property that expanded at build time would make the
# manifest mean something other than what was locked.
function ConvertTo-QaFoundryMsBuildText {
    param([AllowEmptyString()][string]$Text)

    $escaped = [System.Security.SecurityElement]::Escape([string]$Text)
    if ($null -eq $escaped) { return "" }
    return $escaped.Replace("`$(", "%24(").Replace("%(", "%25(")
}

function Test-QaFoundryBuiltMtpProject {
    param([string]$ProjectPath)
    # The build has already run in a clean verification directory. MTP emits this
    # entry point after evaluating the project's imports and conditional properties.
    # Reading the build result also handles runner selection in Directory.Build.props.
    $intermediate = Join-Path $ProjectPath 'obj/Release'
    if (-not (Test-Path -LiteralPath $intermediate -PathType Container)) { return $false }
    if (@(Get-ChildItem -LiteralPath $intermediate -Recurse -File -Filter 'MicrosoftTestingPlatformEntryPoint.*').Count -gt 0) { return $true }
    # Custom MTP entry points disable the generated Main (for example to select
    # environment-free tests by default). They still register the platform's
    # extensions and produce a runnable application. Package presence alone is
    # insufficient: ordinary VSTest libraries can also reference these packages.
    $registration = @(Get-ChildItem -LiteralPath $intermediate -Recurse -File -Filter 'SelfRegisteredExtensions.*' |
        Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match 'Microsoft\.Testing\.Platform' })
    $output = Join-Path $ProjectPath 'bin/Release'
    return $registration.Count -gt 0 -and (Test-Path -LiteralPath $output) -and
        @(Get-ChildItem -LiteralPath $output -Recurse -File -Filter '*.runtimeconfig.json').Count -gt 0
}

function New-QaFoundryNugetEcosystemAdapter {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        id = "nuget"
        displayName = "NuGet"
        recipe = "nuget-packages-lock"
        # A NuGet manifest carries the project's own name, so there is no
        # constant to return: the file is named for the project it builds. The
        # name reaches here from a model-authored decision, so it is reduced to
        # characters MSBuild and the file system both accept before it is used
        # as a file name.
        GetManifestFileName = {
            param([string]$ProjectName)
            $stem = (([string]$ProjectName) -replace "[^A-Za-z0-9_.-]", "_").Trim("._-")
            if ([string]::IsNullOrWhiteSpace($stem)) { $stem = "Automation" }
            return "$stem.csproj"
        }
        manifestPattern = "(^|/)[^/]+\.csproj$"
        lockFileName = "packages.lock.json"
        lockFilePattern = "(^|/)packages\.lock\.json$"
        requiredRuntimeKeys = @("sdk_major")
        resolveScript = "Resolve-EcosystemLock.ps1"
        verifyScript = "Test-EcosystemLock.ps1"
        # MSBuild will import a file this runtime never saw, and an import can
        # add package references no lock file records. A project that reaches
        # outside its own directory is also asking to be built by the product's
        # build, which the automation is deliberately not part of.
        unverifiableManifestKeys = @("Import")
        localDependencyPrefixes = @()

        # A bare NuGet version is a lower bound rather than a demand, but it is
        # still a single version written down; a bracketed range, a comma or a
        # floating '*' is not, and none of those can be checked against a lock.
        exactVersionPattern = "^\d+\.\d+(\.\d+){0,2}(-[0-9A-Za-z.-]+)?$"

        # NuGet package ids are compared without regard to case, so
        # "Newtonsoft.Json" and "newtonsoft.json" are one package and refusing
        # the second spelling would refuse a lock file the feed itself produced.
        NormalizePackageName = { param([string]$Name) return ([string]$Name).Trim().ToLowerInvariant() }

        ReadRuntime = {
            param($Runtime)
            return [ordered]@{
                sdkMajor = [int]$Runtime["sdk_major"]
                targetFramework = ("net{0}.0" -f [int]$Runtime["sdk_major"])
            }
        }

        # The architect settles which framework the automation targets, and that
        # decision used to be discarded here in favour of the SDK this
        # installation happens to pin. The two are not the same statement: an SDK
        # of major N builds every target framework up to net N.0, so a design for
        # net8.0 is buildable by SDK 10 and a design for net10.0 is not buildable
        # by SDK 8. Replacing the design silently produced automation that
        # targeted the wrong framework from the product it was written against;
        # what belongs here instead is either the design's own target or a
        # refusal that names both numbers.
        ResolveProposedRuntime = {
            param($Runtime, $Canonical, [string]$ProposedName, [string]$ProposedVersion)

            $installedMajor = [int]$Canonical["sdkMajor"]
            $requested = Get-QaFoundryProposedRuntimeVersion -Name $ProposedName -Version $ProposedVersion
            if ([string]::IsNullOrWhiteSpace($requested)) {
                Test-QaFoundryProposedRuntimeReadable -Label ".NET target framework" `
                    -ProposedName $ProposedName -ProposedVersion $ProposedVersion
                return $Canonical
            }
            $requestedMajor = Get-QaFoundryRuntimeVersionMajor -Version $requested
            if ($requestedMajor -le 0) {
                throw ("The design targets '$requested', which is not a .NET major version this " +
                    "runtime can check against the installed SDK $installedMajor.")
            }
            if ($requestedMajor -gt $installedMajor) {
                throw ("The design targets net$requestedMajor.0, and this installation has .NET " +
                    "SDK $installedMajor, which cannot build it. Either configure the automation " +
                    "ecosystem with sdk_major $requestedMajor or design against net$installedMajor.0.")
            }
            return [ordered]@{
                sdkMajor = $installedMajor
                targetFramework = ("net{0}.0" -f $requestedMajor)
            }
        }

        # Only the SDK is needed: restore, build and test all run through it.
        # It is checked by major, which is the granularity a target framework
        # is expressed at.
        GetResolverTools = {
            param($Toolchain)
            return @(
                [pscustomobject]@{
                    key = "dotnet"; command = "dotnet"; label = ".NET SDK"
                    expectedVersion = [string]$Toolchain.runtime.sdkMajor; match = "major"
                }
            )
        }

        # NuGet merges every NuGet.config it finds from the directory upwards
        # and from the machine, and an inherited one could add a feed or a
        # credential to a restore this runtime believes is anonymous. Clearing
        # the sources first is what makes the single approved feed the only one.
        NewNeutralConfigFiles = {
            param($Toolchain, [string]$WorkRoot)
            $registry = ConvertTo-QaFoundryMsBuildText ([string]$Toolchain.source.registry)
            $lines = @(
                '<?xml version="1.0" encoding="utf-8"?>',
                '<configuration>',
                '  <packageSources>',
                '    <clear />',
                "    <add key=""approved"" value=""$registry"" />",
                '  </packageSources>',
                '  <packageRestore>',
                '    <add key="enabled" value="true" />',
                '    <add key="automatic" value="false" />',
                '  </packageRestore>',
                '</configuration>'
            )
            return @(
                [pscustomobject]@{
                    key = "nugetconfig"
                    path = "project/NuGet.config"
                    content = (($lines -join "`n") + "`n")
                }
            )
        }

        GetResolveCommand = {
            param($Toolchain, $Context)
            return [pscustomobject]@{
                toolKey = "dotnet"
                # --locked-mode is deliberately absent: this restore is the one
                # that writes the lock. It is the later restores, in build and
                # in CI, that must refuse to change it.
                arguments = @(
                    "restore",
                    "--configfile", [string]$Context.configFiles["nugetconfig"],
                    "--use-lock-file",
                    "/p:RestorePackagesPath=$([string]$Context.cacheRoot)"
                )
                environment = @{
                    DOTNET_CLI_TELEMETRY_OPTOUT = "1"
                    DOTNET_NOLOGO = "1"
                    DOTNET_SKIP_FIRST_TIME_EXPERIENCE = "1"
                    NUGET_PACKAGES = [string]$Context.cacheRoot
                }
            }
        }

        ReadLockEntries = {
            param([string]$LockContent, $Toolchain)
            try { $lock = $LockContent | ConvertFrom-Json -Depth 100 -AsHashtable }
            catch {
                return [pscustomobject]@{ parsed = $false; parseError = $_.Exception.Message }
            }

            $direct = [System.Collections.Generic.List[object]]::new()
            $entries = [System.Collections.Generic.List[object]]::new()
            # The lock is grouped by target framework. Every group is read,
            # because a package restored for a framework nobody asked about is
            # still a package this project would pull in.
            foreach ($framework in @(Get-QaFoundryPropertyNames -InputObject $lock.dependencies)) {
                $group = $lock.dependencies[$framework]
                foreach ($name in @(Get-QaFoundryPropertyNames -InputObject $group)) {
                    $entry = $group[$name]
                    $fields = @(Get-QaFoundryPropertyNames -InputObject $entry)
                    $type = $(if ($fields -contains "type") { [string]$entry.type } else { "" })
                    $version = $(if ($fields -contains "resolved") { [string]$entry.resolved } else { "" })
                    $entries.Add([pscustomobject]@{
                        key = "$framework/$name"
                        name = [string]$name
                        version = $version
                        contentHash = $(if ($fields -contains "contentHash") { [string]$entry.contentHash } else { "" })
                        integrity = $(if ($fields -contains "contentHash") { [string]$entry.contentHash } else { "" })
                        # A NuGet lock names no address for a package; the feed
                        # comes from the configuration the restore ran under.
                        resolvedUrl = ""
                        # A project reference resolves to a directory on the
                        # machine rather than to a package from the feed.
                        isLocal = ($type -eq "Project")
                    })
                    if ($type -eq "Direct") {
                        # NuGet has no development scope, so the scope recorded
                        # in the decision is the only reading available, and a
                        # package absent from it is reported as it was found
                        # rather than assumed to be a runtime dependency.
                        $approved = @($Toolchain.packages | Where-Object { [string]$_.name -eq [string]$name })
                        $scope = $(if ($approved.Count -gt 0) { [string]$approved[0].scope } else { "runtime" })
                        if (@($direct | Where-Object { [string]$_.name -eq [string]$name }).Count -eq 0) {
                            $direct.Add([pscustomobject]@{
                                name = [string]$name
                                version = $version
                                scope = $scope
                            })
                        }
                    }
                }
            }

            return [pscustomobject]@{
                parsed = $true
                parseError = ""
                formatVersion = [string]$lock.version
                identity = $null # packages.lock.json has no owning project name or version.
                direct = @($direct)
                entries = @($entries)
                # Stated rather than skipped: a NuGet lock carries no origin at
                # all. What pins the bytes here is the content hash on every
                # entry, which a hostile feed cannot satisfy.
                originRecorded = $false
                originIsPerFile = $false
                feeds = @()
            }
        }

        # An SDK-style project written from the lock. Restore is pinned to a lock
        # file and told to fail rather than silently re-resolve, because a
        # restore that quietly picks a different version has thrown away the
        # reason the lock exists.
        NewManifestContent = {
            param($Toolchain, [string]$Name, [string]$Version)
            $targetFramework = [string]$Toolchain.runtime.targetFramework
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('<Project Sdk="Microsoft.NET.Sdk">')
            $lines.Add('')
            $lines.Add('  <PropertyGroup>')
            $lines.Add("    <TargetFramework>$(ConvertTo-QaFoundryMsBuildText $targetFramework)</TargetFramework>")
            $lines.Add('    <Nullable>enable</Nullable>')
            $lines.Add('    <ImplicitUsings>enable</ImplicitUsings>')
            $lines.Add('    <IsPackable>false</IsPackable>')
            $lines.Add('    <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>')
            if (-not [string]::IsNullOrWhiteSpace($Name)) {
                $lines.Add("    <AssemblyName>$(ConvertTo-QaFoundryMsBuildText $Name)</AssemblyName>")
                $lines.Add("    <RootNamespace>$($Name -replace '[^A-Za-z0-9_.]', '_')</RootNamespace>")
            }
            if (-not [string]::IsNullOrWhiteSpace($Version)) {
                $lines.Add("    <Version>$(ConvertTo-QaFoundryMsBuildText $Version)</Version>")
            }
            $lines.Add('  </PropertyGroup>')
            $lines.Add('')
            $lines.Add('  <ItemGroup>')
            foreach ($package in @($Toolchain.packages | Sort-Object { [string]$_.name })) {
                $packageName = ConvertTo-QaFoundryMsBuildText ([string]$package.name)
                $packageVersion = ConvertTo-QaFoundryMsBuildText ([string]$package.version)
                $reference = "    <PackageReference Include=""$packageName"" Version=""$packageVersion"""
                # NuGet has no development dependency section. PrivateAssets is
                # the real equivalent: the package is used to build and test this
                # project and is not passed on to anything that references it.
                if ([string]$package.scope -eq "dev") {
                    $reference += ' PrivateAssets="all"'
                }
                $reference += " />"
                $lines.Add($reference)
            }
            $lines.Add('  </ItemGroup>')
            $lines.Add('')
            $lines.Add('</Project>')
            return ($lines -join [Environment]::NewLine)
        }

        ReadManifestDependencies = {
            param([string]$ManifestContent)
            $declared = [System.Collections.Generic.List[object]]::new()
            $document = [xml]$ManifestContent
            foreach ($reference in @($document.SelectNodes("//PackageReference"))) {
                if ($null -eq $reference) { continue }
                $name = [string]$reference.GetAttribute("Include")
                if ([string]::IsNullOrWhiteSpace($name)) {
                    $name = [string]$reference.GetAttribute("Update")
                }
                if ([string]::IsNullOrWhiteSpace($name)) { continue }
                $version = [string]$reference.GetAttribute("Version")
                if ([string]::IsNullOrWhiteSpace($version)) {
                    $versionNode = $reference.SelectSingleNode("Version")
                    if ($null -ne $versionNode) { $version = [string]$versionNode.InnerText }
                }
                $privateAssets = [string]$reference.GetAttribute("PrivateAssets")
                $declared.Add([pscustomobject]@{
                    name = $name.Trim()
                    version = $version.Trim()
                    scope = if ($privateAssets.Trim().ToLowerInvariant() -eq "all") { "dev" } else { "runtime" }
                })
            }
            return @($declared)
        }

        ReadManifestIdentity = {
            param([string]$ManifestContent)
            $document = [xml]$ManifestContent
            $assemblyName = $document.SelectSingleNode("//PropertyGroup/AssemblyName")
            $version = $document.SelectSingleNode("//PropertyGroup/Version")
            return [pscustomobject]@{
                name = if ($null -ne $assemblyName) { ([string]$assemblyName.InnerText).Trim() } else { "" }
                version = if ($null -ne $version) { ([string]$version.InnerText).Trim() } else { "" }
            }
        }

        # A v3 feed publishes a service index, not package addresses. The flat
        # container has to be looked up in it: hard-coding the nuget.org address
        # would work until the day this points at an internal feed, which is
        # exactly the day it matters.
        GetPublishedVersions = {
            param([string]$Registry, [string]$Name)
            $index = Invoke-RestMethod -Uri $Registry -Method Get -TimeoutSec 60 -ErrorAction Stop
            $base = @($index.resources |
                Where-Object { ([string]$_.'@type') -like "PackageBaseAddress/3.0.0*" } |
                ForEach-Object { [string]$_.'@id' })
            if ($base.Count -eq 0) {
                throw "The feed at $Registry publishes no PackageBaseAddress resource, so package versions cannot be read from it."
            }
            $uri = ($base[0].TrimEnd("/") + "/" + $Name.ToLowerInvariant() + "/index.json")
            $document = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 60 -ErrorAction Stop
            if ($null -eq $document -or $null -eq $document.versions) { return @() }
            return @($document.versions | ForEach-Object { [string]$_ })
        }

        GetRuntimeRequirements = {
            param($Toolchain)
            return @(".NET SDK $([int]$Toolchain.runtime.sdkMajor).x")
        }

        # An architect proposes what it needs; this turns the proposal into the
        # one version the lock will carry. NuGet writes its ranges in interval
        # notation and reads a bare version as a lower bound, so it needs its own
        # reading rather than npm's.
        SelectVersion = {
            param([string]$Requested, [string[]]$Published, [bool]$AllowPrerelease)
            return Select-QaFoundryNuGetVersion -Requested $Requested -Published $Published `
                -AllowPrerelease $AllowPrerelease
        }

        # How the lock is enforced when the framework is actually installed.
        # restore --locked-mode fails rather than re-resolving when the lock does not satisfy the project.
        lockEnforcement = "install"

        # Whether the manifest format itself says which dependencies exist
        # only to build and test the project. Where it does not, this run
        # would be comparing a decision it made against a fact the file
        # cannot carry, and refusing a manifest for disagreeing about
        # something it never stated. Here: a PackageReference has no development
        # section. PrivateAssets="all" is close but means something else - do not
        # flow this on to whatever references the project - and a hand-written
        # test project usually omits it.
        manifestExpressesDependencyScope = $false

        TestVersionRange = {
            param([string]$Requested)
            return Test-QaFoundryIntervalRange -Requested $Requested -Ecosystem "NuGet"
        }
    # A project file is one project. What groups several is a solution, and a
    # solution is not this manifest, so a csproj never claims the ones below it.
    ReadWorkspaceMembers = { param([string]$ManifestPath) return @() }

        GetInstallCommand = {
            param($Toolchain, [string]$ProjectPath)
            return [pscustomobject]@{
                executable = "dotnet"
                arguments = @("restore", "--locked-mode")
                workingDirectory = $ProjectPath
            }
        }

        GetBuildCommand = {
            param($Toolchain, [string]$ProjectPath)
            return [pscustomobject]@{
                executable = "dotnet"
                arguments = @("build", "--no-restore", "--configuration", "Release")
                workingDirectory = $ProjectPath
            }
        }

        GetTestCommand = {
            param($Toolchain, [string]$ProjectPath)
            if (Test-QaFoundryBuiltMtpProject -ProjectPath $ProjectPath) {
                # .NET 10 + MTP 2 rejects the legacy VSTest target. Run the test
                # application's own entry point; do not edit the product's global.json.
                return [pscustomobject]@{
                    executable = 'dotnet'
                    arguments = @('run', '--no-build', '--no-restore', '--configuration', 'Release')
                    workingDirectory = $ProjectPath
                }
            }
            return [pscustomobject]@{
                executable = "dotnet"
                arguments = @("test", "--no-build", "--configuration", "Release")
                workingDirectory = $ProjectPath
            }
        }

        # The negative probe is a source file added after the build step ran, so
        # it has to be compiled before it can fail. '--no-build' would run the
        # binary from before the probe existed: the suite would report the same
        # number of tests it reported a moment ago, and a framework that is
        # perfectly sound would be sent back to be written again. Restore is
        # still skipped, so the lock this project was installed under stands.
        GetNegativeProbeTestCommand = {
            param($Toolchain, [string]$ProjectPath)
            if (Test-QaFoundryBuiltMtpProject -ProjectPath $ProjectPath) {
                return [pscustomobject]@{
                    executable = 'dotnet'
                    arguments = @('run', '--no-restore', '--configuration', 'Release')
                    workingDirectory = $ProjectPath
                }
            }
            return [pscustomobject]@{
                executable = "dotnet"
                arguments = @("test", "--no-restore", "--configuration", "Release")
                workingDirectory = $ProjectPath
            }
        }

        # How many tests actually ran. A suite that reports nothing has proved
        # nothing, so the count comes out of the runner's own summary rather than
        # being inferred from an exit code that is zero for "all passed" and for
        # "there was nothing to run" alike. Skipped tests are counted separately
        # because they are in the total and did not run: a suite of nothing but
        # skipped tests exits zero and asserts nothing at all.
        ReadTestRunSummary = {
            param([string]$Output, [int]$ExitCode)
            # MTP emits terminal colors even when its output is redirected. Strip
            # CSI formatting before matching line-based counts; keep raw logs intact.
            $text = [regex]::Replace([string]$Output, '\x1b\[[0-?]*[ -/]*[@-~]', '')
            $total = 0
            $failed = 0
            $skipped = 0
            $parsed = $false
            if ($text -match "(?:Failed|Passed|Skipped)!\s*-\s*Failed:\s*(\d+),\s*Passed:\s*(\d+),\s*Skipped:\s*(\d+),\s*Total:\s*(\d+)") {
                $failed = [int]$Matches[1]
                $skipped = [int]$Matches[3]
                $total = [int]$Matches[4]
                $parsed = $true
            }
            elseif ($text -match "Total tests:\s*(\d+)") {
                $total = [int]$Matches[1]
                $parsed = $true
                if ($text -match "Failed:\s*(\d+)") { $failed = [int]$Matches[1] }
                if ($text -match "Skipped:\s*(\d+)") { $skipped = [int]$Matches[1] }
            }
            elseif ($text -match "(?im)^\s*total:\s*(\d+)\s*$") {
                # Microsoft.Testing.Platform prints its own summary, one figure
                # per line under a "Test run summary" heading. Reading it as a
                # single line found nothing and sent a sound suite back to be
                # rewritten, so each figure is read where it actually is.
                $total = [int]$Matches[1]
                $parsed = $true
                if ($text -match "(?im)^\s*failed:\s*(\d+)\s*$") { $failed = [int]$Matches[1] }
                if ($text -match "(?im)^\s*skipped:\s*(\d+)\s*$") { $skipped = [int]$Matches[1] }
            }
            elseif ($text -match "total:\s*(\d+)[^\r\n]*failed:\s*(\d+)") {
                # The same summary printed on one line by an older reporter.
                $total = [int]$Matches[1]
                $failed = [int]$Matches[2]
                $parsed = $true
                if ($text -match "skipped:\s*(\d+)") { $skipped = [int]$Matches[1] }
            }
            return [pscustomobject]@{
                parsed = $parsed; total = $total; failed = $failed; skipped = $skipped
            }
        }

        # A suite that cannot fail says nothing about the suites beside it, so
        # the framework is asked to fail on purpose exactly once. Which syntax to
        # write it in is read from the packages that were actually locked, never
        # from prose in the blueprint: a probe written for a framework that is not
        # there fails to compile, and a compile error looks exactly like the
        # failure being asked for.
        NewNegativeProbe = {
            param($Toolchain, [string]$ProjectPath)
            $names = @($Toolchain.packages | ForEach-Object { ([string]$_.name).ToLowerInvariant() })
            $body = ""
            if (@($names | Where-Object { $_ -like "xunit*" }).Count -gt 0) {
                $body = @(
                    "using Xunit;",
                    "",
                    "public sealed class FoundryNegativeProbeTests",
                    "{",
                    "    [Fact]",
                    "    public void A_deliberately_broken_expectation_fails()",
                    "    {",
                    "        Assert.Equal(2, 1);",
                    "    }",
                    "}"
                ) -join [Environment]::NewLine
            }
            elseif (@($names | Where-Object { $_ -like "nunit*" }).Count -gt 0) {
                $body = @(
                    "using NUnit.Framework;",
                    "",
                    "[TestFixture]",
                    "public sealed class FoundryNegativeProbeTests",
                    "{",
                    "    [Test]",
                    "    public void A_deliberately_broken_expectation_fails()",
                    "    {",
                    "        Assert.That(1, Is.EqualTo(2));",
                    "    }",
                    "}"
                ) -join [Environment]::NewLine
            }
            elseif (@($names | Where-Object { $_ -like "mstest*" }).Count -gt 0) {
                $body = @(
                    "using Microsoft.VisualStudio.TestTools.UnitTesting;",
                    "",
                    "[TestClass]",
                    "public sealed class FoundryNegativeProbeTests",
                    "{",
                    "    [TestMethod]",
                    "    public void A_deliberately_broken_expectation_fails()",
                    "    {",
                    '        Assert.Fail("Foundry deliberately failing probe.");',
                    "    }",
                    "}"
                ) -join [Environment]::NewLine
            }
            if ([string]::IsNullOrEmpty($body)) {
                return [pscustomobject]@{
                    supported = $false
                    relativePath = ""
                    content = ""
                    reason = ("None of the locked packages is a test framework this runtime can write " +
                        "a failing test in, so it cannot prove that a broken expectation fails.")
                }
            }
            return [pscustomobject]@{
                supported = $true
                relativePath = "FoundryNegativeProbeTests.cs"
                content = $body
                reason = ""
            }
        }
    }
}
