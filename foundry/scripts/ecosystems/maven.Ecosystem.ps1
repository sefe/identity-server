# Everything this runtime knows about Java packaging with Maven in one place.
#
# Maven differs from the package managers around it in two ways that matter to a
# lock. A bare version is a soft requirement - Maven uses exactly that version
# rather than the newest thing above it - and there is no lock file in the tool
# at all, so the resolved set has to be written out and checked back explicitly.

# Maven reads a bare version as "use this one", and an interval as a range. Both
# readings live here because getting them the wrong way round would pin a version
# the build would never have chosen.
function Select-QaFoundryMavenVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Published,
        [bool]$AllowPrerelease = $false
    )

    $request = ([string]$Requested).Trim()
    # A SNAPSHOT is republished under the same coordinates whenever someone
    # builds it, so pinning one produces a lock that stops meaning anything.
    $usable = @($Published | Where-Object {
        $version = [string]$_
        if ($version -match "(?i)-SNAPSHOT$") { return $false }
        $parts = ConvertTo-QaFoundryVersionParts -Version $version
        $parts.valid -and ($AllowPrerelease -or -not $parts.isPrerelease)
    })
    if ($usable.Count -eq 0) { return "" }

    if ($request -in @("", "*", "LATEST", "RELEASE", "latest")) {
        return Get-QaFoundryHighestVersion -Versions $usable
    }
    if ($request -match "^[\[\(]") {
        return Select-QaFoundryNuGetVersion -Requested $request -Published $usable `
            -AllowPrerelease $AllowPrerelease
    }
    # The soft requirement. Maven takes the named version and nothing else, so an
    # absent version is a refusal rather than an invitation to pick a neighbour.
    $match = @($usable | Where-Object { $_ -eq $request })
    return $(if ($match.Count -gt 0) { [string]$match[0] } else { "" })
}

function Get-QaFoundryMavenTestRuntimeArtifacts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][xml]$EffectivePom, [Parameter(Mandatory)][string]$DependencyTree)

    $plugin = $EffectivePom.SelectSingleNode("/*[local-name()='project']/*[local-name()='build']/*[local-name()='plugins']/*[local-name()='plugin'][*[local-name()='artifactId']='maven-surefire-plugin']")
    if ($null -eq $plugin) { return }
    $version = [string]$plugin.version
    if ($version -notmatch '^\d+(\.\d+)+([.-][0-9A-Za-z.-]+)?$') {
        throw 'The effective POM must resolve a concrete Surefire version before its providers can be locked.'
    }
    $dependencies = @{}
    foreach ($match in [regex]::Matches($DependencyTree,
        '(?m)([\w.-]+):([\w.-]+):jar:(?:[\w.-]+:)?([^:\s]+):(compile|runtime|test|provided|system)(?:\s|$)')) {
        $name = "$($match.Groups[1].Value):$($match.Groups[2].Value)"
        $dependencies[$name] = $match.Groups[3].Value
    }
    $artifacts = [System.Collections.Generic.List[string]]::new()
    $platformVersion = $dependencies['org.junit.platform:junit-platform-engine']
    if (-not $platformVersion) { $platformVersion = $dependencies['org.junit.platform:junit-platform-commons'] }
    if ($platformVersion) {
        $artifacts.Add("org.apache.maven.surefire:surefire-junit-platform:$version")
        # Match the resolved JUnit Platform, not the launcher's version in the
        # provider's own POM. Surefire resolves this alignment at execution time.
        $artifacts.Add("org.junit.platform:junit-platform-launcher:$platformVersion")
        if ($dependencies.ContainsKey('org.junit.jupiter:junit-jupiter-api') -and
            -not $dependencies.ContainsKey('org.junit.jupiter:junit-jupiter-engine')) {
            $artifacts.Add("org.junit.jupiter:junit-jupiter-engine:$($dependencies['org.junit.jupiter:junit-jupiter-api'])")
        }
    }
    elseif ($dependencies.ContainsKey('org.testng:testng')) {
        $artifacts.Add("org.apache.maven.surefire:surefire-testng:$version")
    }
    elseif ($dependencies.ContainsKey('junit:junit') -and $dependencies['junit:junit'] -match '^4\.') {
        $artifacts.Add("org.apache.maven.surefire:surefire-junit4:$version")
        # Surefire can select junit47 when parallel execution is configured.
        $artifacts.Add("org.apache.maven.surefire:surefire-junit47:$version")
    }
    else { $artifacts.Add("org.apache.maven.surefire:surefire-junit3:$version") }
    return @($artifacts)
}

function New-QaFoundryMavenEcosystemAdapter {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        id = "maven"
        displayName = "Java (Maven)"
        recipe = "maven-dependency-lock"
        GetManifestFileName = { param([string]$ProjectName) return "pom.xml" }
        manifestPattern = "(^|/)pom\.xml$"
        # Maven has no lock file of its own. The resolved set is written out by
        # dependency:list and checked back against the manifest, which is the
        # same guarantee under a different name - and, unlike a hidden local
        # repository, it is a file a reviewer can read in the pull request.
        lockFileName = "dependency-lock.txt"
        lockFilePattern = "(^|/)dependency-lock\.txt$"
        requiredRuntimeKeys = @("java_version")
        resolveScript = "Resolve-EcosystemLock.ps1"
        verifyScript = "Test-EcosystemLock.ps1"
        # Each of these lets the build reach for something the lock does not
        # name: a repository nobody approved, a version chosen by a parent, or a
        # range re-resolved on every build.
        unverifiableManifestKeys = @("repositories", "pluginRepositories", "parent", "profiles")
        localDependencyPrefixes = @("file:", "system")

        # A bare Maven version is a soft requirement for exactly that release.
        # An interval such as '[1.0,2.0)' or a LATEST/RELEASE keyword is not a
        # single version and cannot be reconciled with a lock.
        exactVersionPattern = "^\d+(\.\d+)*(-[0-9A-Za-z.-]+)?$"

        # A Maven coordinate is a groupId and an artifactId, both compared as
        # written: the repository layout turns the group into directories, and
        # directories on the central repository are case-sensitive.
        NormalizePackageName = { param([string]$Name) return ([string]$Name).Trim() }

        ReadRuntime = {
            param($Runtime)
            return [ordered]@{
                javaVersion = [string]$Runtime["java_version"]
                mavenVersion = [string]$Runtime["maven_version"]
            }
        }
        ResolveProposedRuntime = {
            param($Runtime, $Canonical, [string]$ProposedName, [string]$ProposedVersion)
            return Resolve-QaFoundryVersionedRuntime -Canonical $Canonical -Key "javaVersion" `
                -Label "Java" -ProposedName $ProposedName -ProposedVersion $ProposedVersion
        }

        GetResolverTools = {
            param($Toolchain)
            return @(
                [pscustomobject]@{
                    key = "pwsh"; command = "pwsh"; label = "PowerShell"
                    expectedVersion = "7"; match = "major"; versionArguments = @('--version')
                },
                [pscustomobject]@{
                    key = "mvn"; command = "mvn"; label = "Maven"
                    expectedVersion = [string]$Toolchain.runtime.mavenVersion
                    match = $(if ([string]::IsNullOrWhiteSpace([string]$Toolchain.runtime.mavenVersion)) { "none" } else { "major" })
                    versionArguments = @("-v")
                },
                [pscustomobject]@{
                    key = "java"; command = "java"; label = "Java"
                    expectedVersion = [string]$Toolchain.runtime.javaVersion; match = "major"
                    # java prints its version on standard error, and to stdout
                    # only from 9 onwards; the resolver reads both.
                    versionArguments = @("-version")
                }
            )
        }

        # Maven merges settings from the user's home directory and from the
        # installation, and either can add a repository or a credential. A
        # mirror of "*" is what makes the approved feed the only one a build can
        # reach, whatever the pom or an inherited setting asks for.
        NewNeutralConfigFiles = {
            param($Toolchain, [string]$WorkRoot)
            $registry = [string]$Toolchain.source.registry
            $localRepository = (Join-Path $WorkRoot "cache")
            $lines = @(
                '<?xml version="1.0" encoding="UTF-8"?>',
                '<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">',
                "  <localRepository>$localRepository</localRepository>",
                '  <interactiveMode>false</interactiveMode>',
                '  <offline>false</offline>',
                '  <mirrors>',
                '    <mirror>',
                '      <id>approved</id>',
                "      <url>$registry</url>",
                '      <mirrorOf>*</mirrorOf>',
                '    </mirror>',
                '  </mirrors>',
                '</settings>'
            )
            return @(
                [pscustomobject]@{
                    key = "settings"
                    path = "maven-settings.xml"
                    content = (($lines -join "`n") + "`n")
                }
            )
        }

        GetResolveCommand = {
            param($Toolchain, $Context)
            $settings = [string]$Context.configFiles["settings"]
            return [pscustomobject]@{
                toolKey = "pwsh"
                arguments = @(
                    '-NoProfile', '-File', (Join-Path $PSScriptRoot '../actions/Restore-MavenDependencies.ps1'),
                    '-MavenPath', [string]$Context.toolPaths['mvn'],
                    '-RepositoryPath', [string]$Context.cacheRoot, '-SettingsPath', $settings
                )
                environment = @{ MAVEN_OPTS = "-Djava.awt.headless=true" }
            }
        }

        # Maven ships no lock file, so one is written from the local repository
        # the fetch above filled. Every artefact there arrived with the checksum
        # the feed published beside it, which is what lets this file pin bytes
        # rather than just version numbers.
        NewLockFromWorkspace = {
            param($Toolchain, $Context)
            $repository = [string]$Context.cacheRoot
            if (-not (Test-Path $repository -PathType Container)) {
                throw "The dependency fetch left no local repository at $repository."
            }
            $registry = ([string]$Toolchain.source.registry).TrimEnd("/")
            $records = [System.Collections.Generic.List[string]]::new()
            foreach ($artefact in @(Get-ChildItem -Path $repository -Filter "*.jar" -File -Recurse |
                Sort-Object FullName)) {
                $relative = $artefact.FullName.Substring($repository.Length).TrimStart("\", "/")
                $segments = @($relative -split "[\\/]")
                # group/parts/artifact/version/file.jar - anything shorter is not
                # an artefact laid out the way a repository lays them out.
                if ($segments.Count -lt 4) { continue }
                $version = $segments[$segments.Count - 2]
                $artifactId = $segments[$segments.Count - 3]
                $groupId = ($segments[0..($segments.Count - 4)] -join ".")

                $digest = ""
                $checksumPath = "$($artefact.FullName).sha1"
                if (Test-Path $checksumPath -PathType Leaf) {
                    $digest = (Get-Content -LiteralPath $checksumPath -Raw).Trim()
                    # Some repositories write the checksum followed by a file
                    # name, the way sha1sum does.
                    if ($digest -match "^([0-9a-fA-F]{40})") { $digest = [string]$Matches[1] }
                    else { $digest = "" }
                }
                if ([string]::IsNullOrWhiteSpace($digest)) {
                    # Computed rather than left blank: the artefact is on disk,
                    # so its bytes can still be pinned even when the feed
                    # published no checksum beside it.
                    $digest = (Get-FileHash -LiteralPath $artefact.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    $digest = "sha256:$digest"
                }
                else {
                    $digest = "sha1:$($digest.ToLowerInvariant())"
                }
                $address = "$registry/$(($relative -replace '\\', '/'))"
                $records.Add("$groupId`:$artifactId`:$version $digest $address")
            }
            if ($records.Count -eq 0) {
                throw "The dependency fetch downloaded no artefacts, so there is nothing to lock."
            }
            $header = @(
                "# Generated from the locked toolchain. Do not edit by hand.",
                "# <groupId>:<artifactId>:<version> <algorithm>:<digest> <address>",
                ""
            )
            return ((($header + $records) -join "`n") + "`n")
        }

        ReadLockEntries = {
            param([string]$LockContent, $Toolchain)
            $entries = [System.Collections.Generic.List[object]]::new()
            foreach ($rawLine in @(([string]$LockContent) -split "`r?`n")) {
                $line = ([string]$rawLine).Trim()
                if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
                if ($line -notmatch "^(\S+):(\S+):(\S+)\s+(\S+)\s+(\S+)$") {
                    return [pscustomobject]@{
                        parsed = $false
                        parseError = "a line is not a locked artefact: $line"
                    }
                }
                $entries.Add([pscustomobject]@{
                    key = "$($Matches[1]):$($Matches[2]):$($Matches[3])"
                    name = "$($Matches[1]):$($Matches[2])"
                    version = [string]$Matches[3]
                    integrity = [string]$Matches[4]
                    resolvedUrl = [string]$Matches[5]
                    isLocal = $false
                })
            }
            if ($entries.Count -eq 0) {
                return [pscustomobject]@{ parsed = $false; parseError = "the file locks no artefact" }
            }

            # A Maven lock records the whole resolved set without saying which
            # entries the project asked for directly, so the decision's own
            # scope is the only reading available.
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
                identity = $null # The artifact lock has no owning project identity.
                direct = @($direct)
                entries = @($entries)
                originRecorded = $true
                originIsPerFile = $false
                feeds = @()
            }
        }

        NewManifestContent = {
            param($Toolchain, [string]$Name, [string]$Version)
            $artifactId = $(if ([string]::IsNullOrWhiteSpace($Name)) { "automation" } else { ([string]$Name).ToLowerInvariant() -replace "[^a-z0-9._-]", "-" })
            $projectVersion = $(if ([string]::IsNullOrWhiteSpace($Version)) { "0.1.0" } else { [string]$Version })
            $java = [string]$Toolchain.runtime.javaVersion
            if ([string]::IsNullOrWhiteSpace($java)) { $java = "17" }

            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('<?xml version="1.0" encoding="UTF-8"?>')
            $lines.Add('<!-- Generated from the locked toolchain. Do not edit by hand. -->')
            $lines.Add('<project xmlns="http://maven.apache.org/POM/4.0.0"')
            $lines.Add('         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"')
            $lines.Add('         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">')
            $lines.Add('  <modelVersion>4.0.0</modelVersion>')
            $lines.Add("  <groupId>com.foundry.automation</groupId>")
            $lines.Add("  <artifactId>$artifactId</artifactId>")
            $lines.Add("  <version>$projectVersion</version>")
            $lines.Add("  <packaging>jar</packaging>")
            $lines.Add("  <properties>")
            $lines.Add("    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>")
            $lines.Add("    <maven.compiler.release>$java</maven.compiler.release>")
            # Test automation is never a published artifact. npm has `private`
            # and the SDK has `IsPackable`; Maven's equivalent is to switch the
            # deploy plugin off, so a stray `mvn deploy` cannot push an internal
            # suite's names, endpoints and fixtures to a shared repository.
            $lines.Add("    <maven.deploy.skip>true</maven.deploy.skip>")
            $lines.Add("  </properties>")
            $lines.Add("  <dependencies>")
            foreach ($package in @($Toolchain.packages | Sort-Object { [string]$_.name })) {
                $coordinates = @(([string]$package.name) -split ":")
                if ($coordinates.Count -lt 2) { continue }
                $lines.Add("    <dependency>")
                $lines.Add("      <groupId>$($coordinates[0])</groupId>")
                $lines.Add("      <artifactId>$($coordinates[1])</artifactId>")
                $lines.Add("      <version>$([string]$package.version)</version>")
                if ([string]$package.scope -eq "dev") { $lines.Add("      <scope>test</scope>") }
                $lines.Add("    </dependency>")
            }
            $lines.Add("  </dependencies>")
            $lines.Add("</project>")
            return (($lines -join "`n") + "`n")
        }

        ReadManifestDependencies = {
            param([string]$ManifestContent)
            $declared = [System.Collections.Generic.List[object]]::new()
            try { $document = [xml]$ManifestContent } catch { return @() }
            $namespace = [System.Xml.XmlNamespaceManager]::new($document.NameTable)
            $namespace.AddNamespace("m", "http://maven.apache.org/POM/4.0.0")
            # A pom is valid with or without the namespace declared, and a
            # manifest that reads as empty would look like a project with no
            # dependencies rather than one this adapter failed to read.
            $nodes = @($document.SelectNodes("/m:project/m:dependencies/m:dependency", $namespace))
            if ($nodes.Count -eq 0) {
                $nodes = @($document.SelectNodes("/project/dependencies/dependency"))
            }
            foreach ($node in $nodes) {
                $group = [string]$node.groupId
                $artifact = [string]$node.artifactId
                if ([string]::IsNullOrWhiteSpace($group) -or [string]::IsNullOrWhiteSpace($artifact)) { continue }
                $scope = $(if (([string]$node.scope) -in @("test", "provided")) { "dev" } else { "runtime" })
                $declared.Add([pscustomobject]@{
                    name = "$group`:$artifact"
                    version = [string]$node.version
                    scope = $scope
                })
            }
            return @($declared)
        }

        ReadManifestIdentity = {
            param([string]$ManifestContent)
            try { $document = [xml]$ManifestContent } catch {
                return [pscustomobject]@{ name = ""; version = "" }
            }
            $project = $document.project
            return [pscustomobject]@{
                name = [string]$project.artifactId
                version = [string]$project.version
            }
        }

        GetPublishedVersions = {
            param([string]$Registry, [string]$Name)
            $coordinates = @(([string]$Name) -split ":")
            if ($coordinates.Count -lt 2) {
                throw "A Maven package is named 'groupId:artifactId'; '$Name' is not."
            }
            $groupPath = ($coordinates[0] -replace "\.", "/")
            $uri = "$($Registry.TrimEnd('/'))/$groupPath/$($coordinates[1])/maven-metadata.xml"
            $response = Invoke-WebRequest -Uri $uri -Method Get -TimeoutSec 60 -UseBasicParsing -ErrorAction Stop
            $document = [xml]$response.Content
            return @($document.metadata.versioning.versions.version | ForEach-Object { [string]$_ })
        }

        SelectVersion = {
            param([string]$Requested, [string[]]$Published, [bool]$AllowPrerelease)
            return Select-QaFoundryMavenVersion -Requested $Requested -Published $Published `
                -AllowPrerelease $AllowPrerelease
        }

        GetRuntimeRequirements = {
            param($Toolchain)
            $requirements = @("Java $([string]$Toolchain.runtime.javaVersion)", 'PowerShell 7 (dependency preparation)')
            if (-not [string]::IsNullOrWhiteSpace([string]$Toolchain.runtime.mavenVersion)) {
                $requirements += "Maven $([string]$Toolchain.runtime.mavenVersion)"
            }
            return $requirements
        }

        GetInstallCommand = {
            param($Toolchain, [string]$ProjectPath)
            # Into a repository beside the project rather than into the agent's
            # shared ~/.m2. A shared repository already holds artefacts from
            # other work, so "the jar is present" would say nothing about what
            # this install fetched, and the check below would have nothing to
            # compare the lock against. -C makes Maven refuse an artefact whose
            # published checksum does not match, which is the feed's own
            # integrity guarantee and is free to ask for.
            # Carry the trusted preparation code into the child. Container
            # verification mounts only the project, not the host's Foundry
            # checkout, so an absolute host -File path would fail there.
            $restore = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../actions/Restore-MavenDependencies.ps1') -Raw
            $providerFunction = 'function Get-QaFoundryMavenTestRuntimeArtifacts {' +
                (Get-Command Get-QaFoundryMavenTestRuntimeArtifacts).Definition + '}'
            $restore = $restore.Replace(". (Join-Path `$PSScriptRoot '../ecosystems/maven.Ecosystem.ps1')", $providerFunction)
            $script = "& {`n$restore`n} -RepositoryPath '.m2-repo'"
            if ($null -ne $Toolchain -and $Toolchain.PSObject.Properties.Name -contains 'source') {
                $script += " -Registry '" + ([string]$Toolchain.source.registry).Replace("'", "''") + "'"
            }
            $arguments = @('-NoProfile', '-EncodedCommand',
                [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script)))
            return [pscustomobject]@{
                executable = "pwsh"
                arguments = $arguments
                workingDirectory = $ProjectPath
            }
        }

        # Every other ecosystem here has an install that enforces its own lock:
        # npm ci, dotnet restore --locked-mode, pip --require-hashes, bundle
        # --frozen. Maven has no lock file of its own, so the one this runtime
        # writes was delivered into the change set and then ignored - the
        # install resolved from the POM and whatever the repository offered.
        # That made the lock decorative: a reviewer would read a pinned set of
        # bytes that nothing checked. The comparison is made here instead.
        lockEnforcement = "verified-after-install"

        # Whether the manifest format itself says which dependencies exist
        # only to build and test the project. Where it does not, this run
        # would be comparing a decision it made against a fact the file
        # cannot carry, and refusing a manifest for disagreeing about
        # something it never stated. Here: a dependency carries its own <scope>,
        # and 'test' says it plainly.
        manifestExpressesDependencyScope = $true

        TestVersionRange = {
            param([string]$Requested)
            return Test-QaFoundryIntervalRange -Requested $Requested -Ecosystem "Maven" `
                -FloatingWords @("", "*", "latest", "LATEST", "RELEASE")
        }

        # A POM that lists modules is an aggregator: building it builds them, so
        # they belong to it. One that lists none claims nothing, and a project
        # below it is a project of its own rather than something a build at the
        # top would have covered.
        ReadWorkspaceMembers = {
            param([string]$ManifestPath)
            $document = $null
            try { $document = [xml](Get-Content -LiteralPath $ManifestPath -Raw) }
            catch { return @() }
            if ($null -eq $document -or $null -eq $document.project -or
                $null -eq $document.project.modules) { return @() }
            return @($document.project.modules.module |
                Where-Object { $null -ne $_ } | ForEach-Object { [string]$_ })
        }
        GetInstalledArtefactFindings = {
            param($Toolchain, [string]$ProjectPath, [string]$LockContent)

            $findings = [System.Collections.Generic.List[string]]::new()
            $repository = Join-Path $ProjectPath ".m2-repo"
            if (-not (Test-Path -LiteralPath $repository -PathType Container)) {
                $findings.Add("The install left no local repository at .m2-repo, so nothing can be " +
                    "compared against the lock file.")
                return @($findings)
            }

            # Recorded exactly as the lock was written: coordinate, algorithm and
            # digest. The address is not compared, because it is derived from the
            # decision's registry and is the same string in both files by
            # construction; the bytes are what a lock is for.
            $expected = [ordered]@{}
            foreach ($rawLine in @(([string]$LockContent) -split "`r?`n")) {
                $line = ([string]$rawLine).Trim()
                if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
                $parts = @($line -split "\s+")
                if ($parts.Count -lt 2) { continue }
                $expected[[string]$parts[0]] = [string]$parts[1]
            }
            if ($expected.Count -eq 0) {
                $findings.Add("The lock file names no artefact, so the install proved nothing.")
                return @($findings)
            }

            $installed = [ordered]@{}
            foreach ($artefact in @(Get-ChildItem -LiteralPath $repository -Filter "*.jar" -File -Recurse |
                Sort-Object FullName)) {
                $relative = $artefact.FullName.Substring($repository.Length).TrimStart("\", "/")
                $segments = @($relative -split "[\\/]")
                if ($segments.Count -lt 4) { continue }
                $version = $segments[$segments.Count - 2]
                $artifactId = $segments[$segments.Count - 3]
                $groupId = ($segments[0..($segments.Count - 4)] -join ".")
                $installed["$groupId`:$artifactId`:$version"] = $artefact.FullName
            }

            foreach ($coordinate in @($expected.Keys)) {
                if (-not $installed.Contains($coordinate)) {
                    $findings.Add("The lock file pins $coordinate and the install did not fetch it.")
                    continue
                }
                $recorded = [string]$expected[$coordinate]
                $separator = $recorded.IndexOf(":")
                if ($separator -le 0) {
                    $findings.Add("The lock file records a digest for $coordinate that names no algorithm.")
                    continue
                }
                $algorithm = $recorded.Substring(0, $separator).ToUpperInvariant()
                $digest = $recorded.Substring($separator + 1).ToLowerInvariant()
                if ($algorithm -cnotin @("SHA1", "SHA256", "SHA384", "SHA512")) {
                    $findings.Add("The lock file records $coordinate under '$algorithm', which this " +
                        "runtime cannot compute, so the artefact on disk cannot be compared to it.")
                    continue
                }
                # Computed over the bytes that arrived rather than read from the
                # checksum file beside them: a repository that served the wrong
                # jar would serve a matching .sha1 with it.
                $actual = (Get-FileHash -LiteralPath ([string]$installed[$coordinate]) `
                    -Algorithm $algorithm).Hash.ToLowerInvariant()
                if ($actual -cne $digest) {
                    $findings.Add("The install fetched $coordinate with $algorithm $actual, and the " +
                        "lock file pins $digest.")
                }
            }
            foreach ($coordinate in @($installed.Keys)) {
                if ($expected.Contains($coordinate)) { continue }
                $findings.Add("The install fetched $coordinate, which the lock file does not pin. " +
                    "A dependency that arrives without being locked is one nobody resolved.")
            }
            return @($findings)
        }

        GetBuildCommand = {
            param($Toolchain, [string]$ProjectPath)
            # test-compile rather than package: the code being built here is the
            # test code, and compiling it is what a build is being asked to prove.
            return [pscustomobject]@{
                executable = "mvn"
                arguments = @("-B", "-ntp", "-o", '--settings', 'foundry-maven-settings.xml',
                    '--global-settings', 'foundry-maven-settings.xml', "-Dmaven.repo.local=.m2-repo", "test-compile")
                workingDirectory = $ProjectPath
            }
        }

        GetTestCommand = {
            param($Toolchain, [string]$ProjectPath)
            return [pscustomobject]@{
                executable = "mvn"
                arguments = @("-B", "-ntp", "-o", '--settings', 'foundry-maven-settings.xml',
                    '--global-settings', 'foundry-maven-settings.xml', "-Dmaven.repo.local=.m2-repo", "test")
                workingDirectory = $ProjectPath
            }
        }

        ReadTestRunSummary = {
            param([string]$Output, [int]$ExitCode)
            $text = [string]$Output
            $total = 0
            $failed = 0
            $skipped = 0
            $parsed = $false
            # Surefire prints a line per module and then a total; the last line
            # is the one that covers the whole run. Its "Tests run" includes the
            # skipped ones, so they are read out separately.
            $runs = [regex]::Matches($text,
                "Tests run:\s*(\d+),\s*Failures:\s*(\d+),\s*Errors:\s*(\d+)(?:,\s*Skipped:\s*(\d+))?")
            if ($runs.Count -gt 0) {
                $last = $runs[$runs.Count - 1]
                $total = [int]$last.Groups[1].Value
                $failed = [int]$last.Groups[2].Value + [int]$last.Groups[3].Value
                if ($last.Groups[4].Success) { $skipped = [int]$last.Groups[4].Value }
                $parsed = $true
            }
            elseif ($text -match "No tests to run") {
                $parsed = $true
            }
            return [pscustomobject]@{
                parsed = $parsed; total = $total; failed = $failed; skipped = $skipped
            }
        }

        NewNegativeProbe = {
            param($Toolchain, [string]$ProjectPath)
            $names = @($Toolchain.packages | ForEach-Object { ([string]$_.name).ToLowerInvariant() })
            $isTestNg = @($names | Where-Object { $_ -like "org.testng:*" }).Count -gt 0
            $isJUnit = @($names | Where-Object { $_ -like "org.junit.jupiter:*" -or $_ -like "junit:junit" }).Count -gt 0
            if ($isTestNg) {
                return [pscustomobject]@{
                    supported = $true
                    relativePath = "src/test/java/foundry/FoundryNegativeProbeTest.java"
                    content = @(
                        "package foundry;",
                        "",
                        "import org.testng.Assert;",
                        "import org.testng.annotations.Test;",
                        "",
                        "public class FoundryNegativeProbeTest {",
                        "    @Test",
                        "    public void aDeliberatelyBrokenExpectationFails() {",
                        "        Assert.assertEquals(1, 2);",
                        "    }",
                        "}",
                        ""
                    ) -join "`n"
                }
            }
            if ($isJUnit) {
                return [pscustomobject]@{
                    supported = $true
                    relativePath = "src/test/java/foundry/FoundryNegativeProbeTest.java"
                    content = @(
                        "package foundry;",
                        "",
                        "import static org.junit.jupiter.api.Assertions.assertEquals;",
                        "",
                        "import org.junit.jupiter.api.Test;",
                        "",
                        "class FoundryNegativeProbeTest {",
                        "    @Test",
                        "    void aDeliberatelyBrokenExpectationFails() {",
                        "        assertEquals(1, 2);",
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
