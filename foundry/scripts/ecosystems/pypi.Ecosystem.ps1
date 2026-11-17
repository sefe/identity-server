# Everything this runtime knows about Python packaging in one place.
#
# Python is the single most common language in test automation, and it is also
# the one where a runtime built around npm's assumptions goes wrong quietly: a
# version like 2.0b1 is a pre-release with no hyphen in it, dependencies carry no
# development scope, and there is no build step to speak of. Each of those is
# handled here rather than approximated somewhere shared.

# PEP 440 is not semantic versioning with different spelling. It has an epoch, a
# release segment of any length, a pre-release, a post-release and a development
# release, and they do not all order the way a hyphenated pre-release does:
# 1.2.3.post1 is *newer* than 1.2.3, and 1.2.3.dev1 is older than 1.2.3a1.
# Rewriting a Python version into the shared shape lost exactly those facts -
# a post-release collapsed onto the release it follows, so ==1.2.3.post1 was
# answered with 1.2.3, which is a different distribution. So the ordering is
# implemented here, in the terms the specification is written in.
function ConvertTo-QaFoundryPythonVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Version)

    $invalid = [pscustomobject]@{ valid = $false }
    $text = ([string]$Version).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $invalid }
    # Normalised the way PEP 440 asks: a leading v is decoration, and case is
    # not significant anywhere in the version.
    $text = $text.TrimStart("v", "V").Trim()

    $pattern = "^(?:(?<epoch>\d+)!)?(?<release>\d+(?:\.\d+)*)" +
        "(?:[-_.]?(?<preLabel>a|b|c|rc|alpha|beta|pre|preview)[-_.]?(?<preNumber>\d+)?)?" +
        "(?:(?:-(?<implicitPost>\d+))|(?:[-_.]?(?<postLabel>post|rev|r)[-_.]?(?<postNumber>\d+)?))?" +
        "(?<dev>[-_.]?dev[-_.]?(?<devNumber>\d+)?)?" +
        "(?:\+(?<local>[a-z0-9]+(?:[-_.][a-z0-9]+)*))?$"
    if ($text -notmatch $pattern) { return $invalid }
    $groups = $Matches

    $release = @(([string]$groups["release"]) -split "\." | ForEach-Object { [int]$_ })
    # Trailing zeros carry no meaning: 1.0 and 1.0.0 are the same version, and
    # comparing them by length would order one above the other.
    $trimmed = [System.Collections.Generic.List[int]]::new()
    foreach ($segment in $release) { $trimmed.Add([int]$segment) }
    while ($trimmed.Count -gt 1 -and $trimmed[$trimmed.Count - 1] -eq 0) {
        $trimmed.RemoveAt($trimmed.Count - 1)
    }

    $hasPre = -not [string]::IsNullOrEmpty([string]$groups["preLabel"])
    $preRank = 0
    $preNumber = 0
    if ($hasPre) {
        $label = ([string]$groups["preLabel"]).ToLowerInvariant()
        $preRank = switch ($label) {
            "alpha" { 1 }
            "a" { 1 }
            "beta" { 2 }
            "b" { 2 }
            default { 3 }
        }
        if (-not [string]::IsNullOrEmpty([string]$groups["preNumber"])) {
            $preNumber = [int]$groups["preNumber"]
        }
    }

    $hasPost = (-not [string]::IsNullOrEmpty([string]$groups["postLabel"])) -or
        (-not [string]::IsNullOrEmpty([string]$groups["implicitPost"]))
    $postNumber = 0
    if ($hasPost) {
        if (-not [string]::IsNullOrEmpty([string]$groups["implicitPost"])) {
            $postNumber = [int]$groups["implicitPost"]
        }
        elseif (-not [string]::IsNullOrEmpty([string]$groups["postNumber"])) {
            $postNumber = [int]$groups["postNumber"]
        }
    }

    $hasDev = -not [string]::IsNullOrEmpty([string]$groups["dev"])
    $devNumber = 0
    if ($hasDev -and -not [string]::IsNullOrEmpty([string]$groups["devNumber"])) {
        $devNumber = [int]$groups["devNumber"]
    }

    return [pscustomobject]@{
        valid = $true
        epoch = $(if ([string]::IsNullOrEmpty([string]$groups["epoch"])) { 0 } else { [int]$groups["epoch"] })
        release = @($trimmed)
        hasPre = $hasPre
        preRank = $preRank
        preNumber = $preNumber
        hasPost = $hasPost
        postNumber = $postNumber
        hasDev = $hasDev
        devNumber = $devNumber
        local = ([string]$groups["local"]).ToLowerInvariant()
        # A post-release of a final version is a release, not a pre-release. A
        # development release is one whatever else it carries.
        isPrerelease = ($hasPre -or $hasDev)
        text = $text
    }
}

function Compare-QaFoundryPythonVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Left, [Parameter(Mandatory)]$Right)

    if ($Left.epoch -ne $Right.epoch) { return $(if ($Left.epoch -gt $Right.epoch) { 1 } else { -1 }) }

    $leftRelease = @($Left.release)
    $rightRelease = @($Right.release)
    $length = [Math]::Max($leftRelease.Count, $rightRelease.Count)
    for ($i = 0; $i -lt $length; $i++) {
        $l = $(if ($i -lt $leftRelease.Count) { [int]$leftRelease[$i] } else { 0 })
        $r = $(if ($i -lt $rightRelease.Count) { [int]$rightRelease[$i] } else { 0 })
        if ($l -ne $r) { return $(if ($l -gt $r) { 1 } else { -1 }) }
    }

    # The order the specification gives for the same release segment:
    # .devN, then aN/bN/rcN, then the release itself, then .postN. A version
    # that carries only a development release sorts below every pre-release of
    # the same version, which is why it is ranked separately rather than
    # treated as a missing pre-release.
    $rank = {
        param($Version)
        if (-not $Version.hasPre -and -not $Version.hasPost -and $Version.hasDev) { return 0 }
        if ($Version.hasPre) { return $Version.preRank }
        return 4
    }
    $leftRank = [int](& $rank $Left)
    $rightRank = [int](& $rank $Right)
    if ($leftRank -ne $rightRank) { return $(if ($leftRank -gt $rightRank) { 1 } else { -1 }) }
    if ($Left.hasPre -and $Right.hasPre -and $Left.preNumber -ne $Right.preNumber) {
        return $(if ($Left.preNumber -gt $Right.preNumber) { 1 } else { -1 })
    }

    $leftPost = $(if ($Left.hasPost) { [int]$Left.postNumber } else { -1 })
    $rightPost = $(if ($Right.hasPost) { [int]$Right.postNumber } else { -1 })
    if ($leftPost -ne $rightPost) { return $(if ($leftPost -gt $rightPost) { 1 } else { -1 }) }

    # A development release precedes the thing it develops towards, so its
    # absence orders above any development number.
    $leftDev = $(if ($Left.hasDev) { [int]$Left.devNumber } else { [int]::MaxValue })
    $rightDev = $(if ($Right.hasDev) { [int]$Right.devNumber } else { [int]::MaxValue })
    if ($leftDev -ne $rightDev) { return $(if ($leftDev -gt $rightDev) { 1 } else { -1 }) }

    return 0
}

# A prefix match in PEP 440 is made on the release segment as written, not on
# major and minor: "1.5.*" excludes 1.5.9 and "1.5.0.*" does not. The trailing
# zeros this comparison must not trim are exactly the ones the ordering does.
function Test-QaFoundryPythonVersionPrefix {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Candidate, [Parameter(Mandatory)][string]$Prefix)

    $prefixText = ([string]$Prefix).Trim()
    $epoch = 0
    if ($prefixText -match "^(\d+)!(.+)$") {
        $epoch = [int]$Matches[1]
        $prefixText = [string]$Matches[2]
    }
    if ($Candidate.epoch -ne $epoch) { return $false }
    $segments = @($prefixText -split "\.")
    if (@($segments | Where-Object { $_ -notmatch "^\d+$" }).Count -gt 0) { return $false }
    $candidateRelease = @($Candidate.release)
    for ($i = 0; $i -lt $segments.Count; $i++) {
        $actual = $(if ($i -lt $candidateRelease.Count) { [int]$candidateRelease[$i] } else { 0 })
        if ($actual -ne [int]$segments[$i]) { return $false }
    }
    return $true
}

# Two versions that name the same release and the same pre-release, differing
# only in what follows it. PEP 440's exclusive bounds are written in these
# terms: >1.5 must not admit 1.5.post1, and <1.5 must not admit 1.5a1, even
# though the ordering places each of those on the permitted side.
function Test-QaFoundrySamePythonRelease {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Left, [Parameter(Mandatory)]$Right)

    if ($Left.epoch -ne $Right.epoch) { return $false }
    $leftRelease = @($Left.release)
    $rightRelease = @($Right.release)
    $length = [Math]::Max($leftRelease.Count, $rightRelease.Count)
    for ($i = 0; $i -lt $length; $i++) {
        $l = $(if ($i -lt $leftRelease.Count) { [int]$leftRelease[$i] } else { 0 })
        $r = $(if ($i -lt $rightRelease.Count) { [int]$rightRelease[$i] } else { 0 })
        if ($l -ne $r) { return $false }
    }
    if ($Left.hasPre -ne $Right.hasPre) { return $false }
    if ($Left.hasPre -and ($Left.preRank -ne $Right.preRank -or $Left.preNumber -ne $Right.preNumber)) {
        return $false
    }
    return $true
}

function Select-QaFoundryPythonVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Published,
        [bool]$AllowPrerelease = $false
    )

    $parsed = [System.Collections.Generic.List[object]]::new()
    # Not $published: PowerShell variable names are case-insensitive, so a loop
    # variable spelled that way rebinds the [string[]] parameter and each
    # element is silently re-wrapped into a one-element array.
    foreach ($candidate in @($Published)) {
        $version = ConvertTo-QaFoundryPythonVersion -Version $candidate
        if (-not $version.valid) { continue }
        if (-not $AllowPrerelease -and $version.isPrerelease) { continue }
        $parsed.Add([pscustomobject]@{ original = [string]$candidate; parsed = $version })
    }
    if ($parsed.Count -eq 0) { return "" }

    $request = ([string]$Requested).Trim()
    # A PEP 440 specifier is a comma-separated conjunction: every clause has to
    # hold. Splitting first means ">=1.0,<2.0" is read as the two limits it
    # actually is rather than as one expression nothing can satisfy. An unbounded
    # request leaves no clauses, and the selection below then simply takes the
    # newest usable version.
    $clauses = @()
    if ($request -notin @("", "*", "latest")) {
        $clauses = @($request -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    $satisfies = {
        param([string]$Original, $Candidate)
        foreach ($clause in $clauses) {
            if ($clause -notmatch "^(===|==|!=|<=|>=|~=|<|>)?\s*(.+)$") { return $false }
            $operator = [string]$Matches[1]
            $written = ([string]$Matches[2]).Trim()

            # Arbitrary equality compares the strings as published and nothing
            # else, which is the whole point of it.
            if ($operator -eq "===") {
                if ($Original -cne $written) { return $false }
                continue
            }

            $wildcard = $written.EndsWith(".*")
            $target = $(if ($wildcard) { $written.Substring(0, $written.Length - 2) } else { $written })
            if ($wildcard) {
                # Prefix matching is defined for == and != only; any other
                # operator with a wildcard is not a specifier this can honour,
                # and guessing at one would pin a version nobody asked for.
                if ($operator -eq "==") {
                    if (-not (Test-QaFoundryPythonVersionPrefix -Candidate $Candidate -Prefix $target)) {
                        return $false
                    }
                    continue
                }
                if ($operator -eq "!=") {
                    if (Test-QaFoundryPythonVersionPrefix -Candidate $Candidate -Prefix $target) { return $false }
                    continue
                }
                return $false
            }

            $targetVersion = ConvertTo-QaFoundryPythonVersion -Version $target
            if (-not $targetVersion.valid) { return $false }
            $order = Compare-QaFoundryPythonVersion -Left $Candidate -Right $targetVersion
            switch ($operator) {
                ">=" { if ($order -lt 0) { return $false } }
                ">" {
                    if ($order -le 0) { return $false }
                    # A post-release of the excluded version is newer than it and
                    # still not what ">" asked for, unless the bound was itself a
                    # post-release.
                    if (-not $targetVersion.hasPost -and
                        (Test-QaFoundrySamePythonRelease -Left $Candidate -Right $targetVersion)) {
                        return $false
                    }
                }
                "<=" { if ($order -gt 0) { return $false } }
                "<" {
                    if ($order -ge 0) { return $false }
                    # Symmetrically: a pre-release of the excluded version is
                    # older than it and still not what "<" asked for.
                    if (-not $targetVersion.hasPre -and $Candidate.hasPre) {
                        $release = @($Candidate.release)
                        $bound = @($targetVersion.release)
                        $length = [Math]::Max($release.Count, $bound.Count)
                        $sameRelease = ($Candidate.epoch -eq $targetVersion.epoch)
                        for ($i = 0; $sameRelease -and $i -lt $length; $i++) {
                            $l = $(if ($i -lt $release.Count) { [int]$release[$i] } else { 0 })
                            $r = $(if ($i -lt $bound.Count) { [int]$bound[$i] } else { 0 })
                            if ($l -ne $r) { $sameRelease = $false }
                        }
                        if ($sameRelease) { return $false }
                    }
                }
                "!=" { if ($order -eq 0) { return $false } }
                "~=" {
                    # Compatible release: at least this version, and not past the
                    # last segment the request named. "~=1.4.2" allows 1.4.9 and
                    # refuses 1.5.0; "~=1.4" allows 1.9 and refuses 2.0.
                    if ($order -lt 0) { return $false }
                    $segments = @($target -split "[-_.+!]" | Where-Object { $_ -match "^\d+$" })
                    if ($segments.Count -lt 2) { return $false }
                    $prefix = (@($segments[0..($segments.Count - 2)]) -join ".")
                    if (-not (Test-QaFoundryPythonVersionPrefix -Candidate $Candidate -Prefix $prefix)) {
                        return $false
                    }
                }
                default { if ($order -ne 0) { return $false } }
            }
        }
        return $true
    }

    $best = $null
    $bestOriginal = ""
    foreach ($entry in $parsed) {
        if (-not (& $satisfies $entry.original $entry.parsed)) { continue }
        if ($null -eq $best -or
            (Compare-QaFoundryPythonVersion -Left $entry.parsed -Right $best) -gt 0) {
            $best = $entry.parsed
            $bestOriginal = [string]$entry.original
        }
    }
    return $bestOriginal
}

function New-QaFoundryPypiEcosystemAdapter {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        id = "pypi"
        displayName = "Python (pip)"
        recipe = "pip-requirements-lock"
        # A requirements file rather than pyproject.toml, and deliberately so.
        # The manifest here is written by the runtime from a resolved lock and
        # read back to check it, and TOML would put a hand-written parser
        # between those two acts for no gain: the dependency list is the whole
        # content either way. A project that later wants pyproject.toml can have
        # one; nothing about it needs to be the file the lock is checked against.
        GetManifestFileName = { param([string]$ProjectName) return "requirements.txt" }
        manifestPattern = "(^|/)requirements\.txt$"
        lockFileName = "requirements.lock"
        lockFilePattern = "(^|/)requirements\.lock$"
        requiredRuntimeKeys = @("python_version")
        resolveScript = "Resolve-EcosystemLock.ps1"
        verifyScript = "Test-EcosystemLock.ps1"
        # Each of these makes the installed set depend on something outside the
        # file, which is the one thing a lock exists to prevent.
        unverifiableManifestKeys = @("--index-url", "--extra-index-url", "--find-links", "-r", "--requirement", "-e", "--editable")
        localDependencyPrefixes = @("file:", "-e ", "./", "../", "git+")

        # PEP 440 spells a pre-release without a hyphen and allows a post or dev
        # suffix, so an exact version here looks unlike an npm one. A specifier
        # carrying '==', '>=', '~=' or a '*' is a range and is refused.
        exactVersionPattern = "^\d+(\.\d+)*((a|b|rc)\d+)?(\.post\d+)?(\.dev\d+)?$"

        # PEP 503: a project name is compared after runs of hyphen, underscore
        # and dot collapse to a single hyphen and the whole is lowercased, so
        # "Foo.Bar_baz" and "foo-bar-baz" are one project on the index.
        NormalizePackageName = {
            param([string]$Name)
            return (([string]$Name).Trim().ToLowerInvariant() -replace "[-_.]+", "-")
        }

        ReadRuntime = {
            param($Runtime)
            $version = [string]$Runtime["python_version"]
            $parts = @($version -split "\.")
            return [ordered]@{
                pythonVersion = $version
                pythonMajor = [int]$parts[0]
                pythonMinor = $(if ($parts.Count -gt 1) { [int]$parts[1] } else { 0 })
            }
        }
        ResolveProposedRuntime = {
            param($Runtime, $Canonical, [string]$ProposedName, [string]$ProposedVersion)
            return Resolve-QaFoundryVersionedRuntime -Canonical $Canonical -Key "pythonVersion" `
                -Label "Python" -ProposedName $ProposedName -ProposedVersion $ProposedVersion
        }

        # pip on its own cannot write a lock: "pip install" resolves and installs
        # in one act and leaves nothing behind that a later install can be held
        # to. pip-compile is what produces the pinned, hashed file, so it is
        # named as a requirement rather than assumed - an agent without it gets
        # an infrastructure refusal instead of an unpinned install.
        GetResolverTools = {
            param($Toolchain)
            return @(
                [pscustomobject]@{
                    key = "python"; command = "python"; label = "Python"
                    # Minor, not major: 3.11 and 3.12 are different runtimes with
                    # different bytecode and different wheels, and a lock
                    # resolved against one says nothing about the other. Matching
                    # on the major alone accepted any Python 3 for a decision
                    # settled on a named one.
                    expectedVersion = [string]$Toolchain.runtime.pythonVersion; match = "minor"
                },
                [pscustomobject]@{
                    key = "pip-compile"; command = "pip-compile"; label = "pip-tools"
                    expectedVersion = ""; match = "none"
                }
            )
        }

        # pip reads pip.conf and PIP_* variables from the machine, and an
        # inherited index URL would resolve against a feed nobody approved. The
        # file is written empty and pointed at explicitly.
        NewNeutralConfigFiles = {
            param($Toolchain, [string]$WorkRoot)
            return @(
                [pscustomobject]@{ key = "pipconfig"; path = "empty-pip.conf"; content = "" }
            )
        }

        GetResolveCommand = {
            param($Toolchain, $Context)
            $compile = [pscustomobject]@{
                toolKey = "pip-compile"
                arguments = @(
                    "--quiet",
                    "--no-header",
                    # Without hashes the lock names versions but not bytes, and
                    # "--require-hashes" at install time then has nothing to
                    # check the download against.
                    "--generate-hashes",
                    "--emit-index-url",
                    "--index-url", [string]$Toolchain.source.registry,
                    "--output-file", ([string]$Context.projectRoot + [IO.Path]::DirectorySeparatorChar + "requirements.lock"),
                    "requirements.txt"
                )
                environment = @{
                    PIP_CONFIG_FILE = [string]$Context.configFiles["pipconfig"]
                    PIP_DISABLE_PIP_VERSION_CHECK = "1"
                    PIP_NO_INPUT = "1"
                    PIP_CACHE_DIR = [string]$Context.cacheRoot
                }
            }
            # pip-tools omits the default PyPI URL even with --emit-index-url.
            # Preserve the explicitly approved source in the delivered lock so
            # verification and installation do not depend on pip's defaults.
            $recordSource = @'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
content = path.read_text(encoding="utf-8")
if not re.search(r"(?m)^--(?:extra-)?index-url(?:=|\s)", content):
    path.write_text("--index-url " + sys.argv[2] + "\n\n" + content, encoding="utf-8")
'@
            return [pscustomobject]@{ commands = @(
                $compile,
                [pscustomobject]@{
                    toolKey = 'python'
                    arguments = @('-c', $recordSource, (Join-Path $Context.projectRoot 'requirements.lock'), [string]$Toolchain.source.registry)
                    environment = @{}
                }
            ) }
        }

        ReadLockEntries = {
            param([string]$LockContent, $Toolchain)
            $entries = [System.Collections.Generic.List[object]]::new()
            $feeds = [System.Collections.Generic.List[string]]::new()
            $current = $null
            $sawRequirement = $false

            foreach ($rawLine in @(([string]$LockContent) -split "`r?`n")) {
                $line = ([string]$rawLine).Trim()
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line -match "^--(?:extra-)?index-url[=\s]+(\S+)") {
                    $feeds.Add([string]$Matches[1])
                    continue
                }
                # A hash continues the requirement above it, and the backslash
                # that joins them is stripped before the line is read.
                $line = ($line -replace "\\\s*$", "").Trim()
                if ($line -match "^--hash[=\s]+(\S+)") {
                    if ($null -ne $current) {
                        # A package can carry a hash per artefact; the first one
                        # is enough to establish that the bytes are pinned, and
                        # the rest are alternatives for the same version.
                        if ([string]::IsNullOrWhiteSpace([string]$current.integrity)) {
                            $current.integrity = [string]$Matches[1]
                        }
                    }
                    continue
                }
                if ($line.StartsWith("#")) { continue }
                $comment = $line.IndexOf("#")
                if ($comment -ge 0) { $line = $line.Substring(0, $comment).Trim() }
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                # pip-compile writes every requirement pinned with "==". A line
                # that is not pinned is a requirement this file does not settle.
                if ($line -match "^([A-Za-z0-9._-]+)\s*(?:\[[^\]]*\])?\s*==\s*(\S+)$") {
                    $sawRequirement = $true
                    $current = [pscustomobject]@{
                        key = [string]$Matches[1]
                        # Distribution names compare case-insensitively and treat
                        # runs of . _ - as one separator, so they are normalised
                        # before anything is matched against the decision.
                        name = (([string]$Matches[1]).ToLowerInvariant() -replace "[-_.]+", "-")
                        version = [string]$Matches[2]
                        integrity = ""
                        resolvedUrl = ""
                        isLocal = $false
                    }
                    $entries.Add($current)
                    continue
                }
                if ($line -match "^(-e\s|--editable|\./|\.\./|file:|git\+)") {
                    $sawRequirement = $true
                    $current = [pscustomobject]@{
                        key = $line; name = $line; version = ""
                        integrity = ""; resolvedUrl = ""; isLocal = $true
                    }
                    $entries.Add($current)
                    continue
                }
                $sawRequirement = $true
                $current = [pscustomobject]@{
                    key = $line
                    name = $line
                    version = ""
                    integrity = ""
                    resolvedUrl = ""
                    isLocal = $false
                }
                $entries.Add($current)
            }

            if (-not $sawRequirement) {
                return [pscustomobject]@{
                    parsed = $false
                    parseError = "the file names no pinned requirement"
                }
            }

            # The decision's own scope is the only reading available, because a
            # requirements file has no development section of its own.
            $direct = [System.Collections.Generic.List[object]]::new()
            foreach ($approved in @($Toolchain.packages)) {
                $normalised = (([string]$approved.name).ToLowerInvariant() -replace "[-_.]+", "-")
                $match = @($entries | Where-Object { [string]$_.name -eq $normalised })
                if ($match.Count -eq 0) { continue }
                $direct.Add([pscustomobject]@{
                    name = [string]$approved.name
                    version = [string]$match[0].version
                    scope = [string]$approved.scope
                })
            }
            # Matched on the normalised name, so the approved spelling is the one
            # reported back and the caller compares like with like.
            foreach ($entry in $entries) {
                $approved = @($Toolchain.packages | Where-Object {
                    (([string]$_.name).ToLowerInvariant() -replace "[-_.]+", "-") -eq [string]$entry.name
                })
                if ($approved.Count -gt 0) { $entry.name = [string]$approved[0].name }
            }

            return [pscustomobject]@{
                parsed = $true
                parseError = ""
                formatVersion = ""
                identity = $null # Requirements locks identify distributions, not their consumer.
                direct = @($direct)
                entries = @($entries)
                originRecorded = $true
                # pip-compile writes the index once at the top of the file rather
                # than an address per package, so the origin is checked there.
                originIsPerFile = $true
                feeds = @($feeds)
            }
        }

        NewManifestContent = {
            param($Toolchain, [string]$Name, [string]$Version)
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("# Generated from the locked toolchain. Do not edit by hand.")
            if (-not [string]::IsNullOrWhiteSpace($Name)) { $lines.Add("# Project: $Name") }
            if (-not [string]::IsNullOrWhiteSpace($Version)) { $lines.Add("# Version: $Version") }
            $lines.Add("")
            foreach ($package in @($Toolchain.packages | Sort-Object { [string]$_.name })) {
                # A requirements file has no development section. The scope is
                # still real - a linter is not a runtime dependency - so it is
                # recorded in a trailing marker that this adapter reads back,
                # rather than being dropped and then guessed at later.
                $line = "$([string]$package.name)==$([string]$package.version)"
                if ([string]$package.scope -eq "dev") { $line += "  # scope: dev" }
                $lines.Add($line)
            }
            return (($lines -join "`n") + "`n")
        }

        ReadManifestDependencies = {
            param([string]$ManifestContent)
            $declared = [System.Collections.Generic.List[object]]::new()
            foreach ($rawLine in @(([string]$ManifestContent) -split "`r?`n")) {
                $line = ([string]$rawLine).Trim()
                if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { continue }
                $scope = "runtime"
                $comment = $line.IndexOf("#")
                if ($comment -ge 0) {
                    if ($line.Substring($comment) -match "scope:\s*dev") { $scope = "dev" }
                    $line = $line.Substring(0, $comment).Trim()
                }
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                if ($line -match "^([A-Za-z0-9._-]+)\s*(?:\[[^\]]*\])?\s*(.*)$") {
                    $declared.Add([pscustomobject]@{
                        name = [string]$Matches[1]
                        version = ([string]$Matches[2]).Trim()
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
            # PyPI's JSON API lives beside the simple index, and a feed given as
            # a simple index still answers here once the path is corrected.
            $base = $Registry.TrimEnd("/")
            if ($base -match "/simple$") { $base = $base.Substring(0, $base.Length - 7).TrimEnd("/") }
            $uri = "$base/pypi/$([Uri]::EscapeDataString($Name))/json"
            $document = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec 60 -ErrorAction Stop
            if ($null -eq $document -or $null -eq $document.releases) { return @() }
            # A release with no files was yanked or never uploaded; pip cannot
            # install it, so neither can this.
            return @($document.releases.PSObject.Properties |
                Where-Object { @($_.Value).Count -gt 0 } |
                ForEach-Object { [string]$_.Name })
        }

        SelectVersion = {
            param([string]$Requested, [string[]]$Published, [bool]$AllowPrerelease)
            return Select-QaFoundryPythonVersion -Requested $Requested -Published $Published `
                -AllowPrerelease $AllowPrerelease
        }

        GetRuntimeRequirements = {
            param($Toolchain)
            return @("Python $([string]$Toolchain.runtime.pythonVersion)")
        }

        # How the lock is enforced when the framework is actually installed.
        # pip --require-hashes installs only what the lock names and refuses anything whose bytes differ.
        lockEnforcement = "install"

        # Whether the manifest format itself says which dependencies exist
        # only to build and test the project. Where it does not, this run
        # would be comparing a decision it made against a fact the file
        # cannot carry, and refusing a manifest for disagreeing about
        # something it never stated. Here: a requirements file is a flat list;
        # where a project states this at all, it does so somewhere this runtime
        # does not read.
        manifestExpressesDependencyScope = $false

        TestVersionRange = {
            param([string]$Requested)
            return Test-QaFoundryClauseRange -Requested $Requested -Ecosystem "PyPI" `
                -OperatorPattern "===|==|!=|<=|>=|~=|<|>" -Example ">=1.49.0,<2.0.0"
        }
    # A pyproject describes one distribution. Nothing in it names another
    # project directory as part of the same install.
    ReadWorkspaceMembers = { param([string]$ManifestPath) return @() }

        GetInstallCommand = {
            param($Toolchain, [string]$ProjectPath)
            return [pscustomobject]@{
                executable = "python"
                # Keep generated dependencies out of the shared interpreter and
                # pip-tools environment; each framework owns its package tree.
                arguments = @("-m", "pip", "install", "--target", ".foundry-python-packages", "--no-deps", "--require-hashes", "-r", "requirements.lock")
                workingDirectory = $ProjectPath
            }
        }

        # Python has no build step, and pretending otherwise would make the build
        # check meaningless. Byte-compiling everything is the honest equivalent:
        # it fails on a file that does not parse, which is what a build catches.
        GetBuildCommand = {
            param($Toolchain, [string]$ProjectPath)
            return [pscustomobject]@{
                executable = "python"
                arguments = @("-m", "compileall", "-q", "-x", "[\\/]\.foundry-python-packages[\\/]", ".")
                workingDirectory = $ProjectPath
            }
        }

        GetTestCommand = {
            param($Toolchain, [string]$ProjectPath)
            $names = @($Toolchain.packages | ForEach-Object { ([string]$_.name).ToLowerInvariant() })
            $runner = if ('robotframework' -in $names -and 'pytest' -notin $names) {
                "import sys; sys.path.insert(0, '.foundry-python-packages'); import robot; sys.exit(robot.run('tests', outputdir='test-results'))"
            } else {
                "import sys; sys.path.insert(0, '.foundry-python-packages'); import pytest; sys.exit(pytest.main(['-q', '--ignore=.foundry-python-packages']))"
            }
            return [pscustomobject]@{
                executable = "python"
                arguments = @("-c", $runner)
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
            # Robot prints a summary for each child suite and the aggregate
            # last. Mixing the first passed/failed matches counts different
            # suites and can mistake a setup failure for an executed probe.
            $robot = [regex]::Matches($text, '(?m)^\s*(\d+) tests?,\s*(\d+) passed,\s*(\d+) failed(?:,\s*(\d+) skipped)?\s*$')
            if ($robot.Count -gt 0) {
                $last = $robot[$robot.Count - 1]
                return [pscustomobject]@{
                    parsed = $true; total = [int]$last.Groups[1].Value
                    failed = [int]$last.Groups[3].Value
                    skipped = $(if ($last.Groups[4].Success) { [int]$last.Groups[4].Value } else { 0 })
                }
            }
            if ($text -match "(\d+)\s+passed") { $total += [int]$Matches[1]; $parsed = $true }
            if ($text -match "(\d+)\s+failed") { $failed += [int]$Matches[1]; $total += [int]$Matches[1]; $parsed = $true }
            if ($text -match "(\d+)\s+error") { $failed += [int]$Matches[1]; $parsed = $true }
            # Counted into the total as well, so that the total means "tests the
            # runner reported" everywhere and the caller can subtract to learn
            # how many actually ran.
            if ($text -match "(\d+)\s+skipped") { $skipped += [int]$Matches[1]; $total += [int]$Matches[1]; $parsed = $true }
            if ($text -match "(\d+)\s+deselected") { $skipped += [int]$Matches[1]; $total += [int]$Matches[1]; $parsed = $true }
            # "no tests ran" is a real pytest outcome and is emphatically not a
            # pass, so it is reported as a parsed run of zero rather than left
            # unparsed and treated as unknown.
            if (-not $parsed -and $text -match "no tests ran") { $parsed = $true }
            if (-not $parsed -and $text -match "collected\s+(\d+)\s+item") {
                $total = [int]$Matches[1]
                $parsed = $true
            }
            return [pscustomobject]@{
                parsed = $parsed; total = $total; failed = $failed; skipped = $skipped
            }
        }

        NewNegativeProbe = {
            param($Toolchain, [string]$ProjectPath)
            $names = @($Toolchain.packages | ForEach-Object { ([string]$_.name).ToLowerInvariant() })
            if ($names -contains "pytest" -or $names -contains "pytest-playwright" -or $names -contains "robotframework") {
                if ($names -contains "robotframework" -and $names -notcontains "pytest") {
                    return [pscustomobject]@{
                        supported = $true
                        relativePath = "tests/foundry_negative_probe.robot"
                        content = @(
                            "*** Test Cases ***",
                            "A deliberately broken expectation fails",
                            "    Should Be Equal As Integers    1    2",
                            ""
                        ) -join "`n"
                    }
                }
                return [pscustomobject]@{
                    supported = $true
                    relativePath = "tests/test_foundry_negative_probe.py"
                    content = @(
                        "def test_a_deliberately_broken_expectation_fails():",
                        "    assert 1 == 2",
                        ""
                    ) -join "`n"
                }
            }
            return [pscustomobject]@{ supported = $false; relativePath = ""; content = "" }
        }
    }
}
