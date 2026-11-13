[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyString()][string]$LockJson,
    [Parameter(Mandatory)][object]$Toolchain,
    [string]$ManifestName = "",
    [string]$ManifestVersion = "",
    # What this programme refuses whoever proposes it. Applied here rather than
    # only where an agent names a package, because a lock file is the first
    # place the whole graph exists: a refused package pulled in as somebody
    # else's dependency is installed just the same.
    [AllowNull()][object]$PackagePolicy = $null
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../Common.ps1")

# What a lock has to prove is the same in every ecosystem: it parses, it was
# produced by the approved tooling, it pins exactly the packages that were
# approved and nothing else, every artefact it names carries a hash, and every
# artefact it names comes from the approved feed. Only the reading of the file
# differs, and that is the adapter's job. Keeping the questions here means a new
# ecosystem inherits all of them instead of re-implementing the ones its author
# happened to remember.

$findings = [System.Collections.Generic.List[string]]::new()

function New-Verdict {
    return [pscustomobject][ordered]@{
        accepted = ($findings.Count -eq 0)
        findings = @($findings)
    }
}

$ecosystem = [string]$Toolchain.ecosystem
try { $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $ecosystem }
catch {
    $findings.Add("No adapter can read a $ecosystem lock file: $($_.Exception.Message)")
    return New-Verdict
}

try { $reading = & $adapter.ReadLockEntries ([string]$LockJson) $Toolchain }
catch {
    $findings.Add("The $($adapter.displayName) lock could not be read: $($_.Exception.Message)")
    return New-Verdict
}

if (-not [bool]$reading.parsed) {
    $detail = [string]$reading.parseError
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = "the file is not in the expected format" }
    $findings.Add("The resolver produced a lock file that could not be read: $detail")
    return New-Verdict
}

# A lock written by a different tool version can have a different shape, and a
# shape this runtime does not expect is one whose guarantees it cannot check.
# Read defensively: an ecosystem with no notion of a lock format states neither
# key, and reaching for an absent one would fail the check rather than skip it.
$runtimeKeys = @(Get-QaFoundryPropertyNames -InputObject $Toolchain.runtime)
$expectedFormat = ""
foreach ($key in @("lockFormatVersion", "lockfileVersion")) {
    if ($runtimeKeys -contains $key) {
        $expectedFormat = [string]$Toolchain.runtime.$key
        if (-not [string]::IsNullOrWhiteSpace($expectedFormat)) { break }
    }
}
if (-not [string]::IsNullOrWhiteSpace($expectedFormat)) {
    $actualFormat = [string]$reading.formatVersion
    if ($actualFormat -ne $expectedFormat) {
        $findings.Add("The lock file is format version $actualFormat, not the approved $expectedFormat.")
        return New-Verdict
    }
}

$entries = @($reading.entries)
if ($entries.Count -eq 0) {
    $findings.Add("The lock file records no packages at all.")
    return New-Verdict
}

# Read the optional parts of the adapter's reading defensively, so an adapter
# that has no opinion on them gets the strict default rather than an error.
$readingKeys = @(Get-QaFoundryPropertyNames -InputObject $reading)
$originRecorded = $true
if ($readingKeys -contains "originRecorded") { $originRecorded = [bool]$reading.originRecorded }
$originIsPerFile = $false
if ($readingKeys -contains "originIsPerFile") { $originIsPerFile = [bool]$reading.originIsPerFile }
$declaredFeeds = @()
if ($readingKeys -contains "feeds") {
    $declaredFeeds = @($reading.feeds | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
}

# The identity check is not about what the installer would refuse. A lock that
# names another project is a lock resolved for something other than what was
# asked for, and one of unknown provenance is not one to hand on. An adapter
# that returns an identity at all is claiming its ecosystem records one, so a
# blank where the manifest states a value is a lock that dropped it rather than
# a lock that never had it - and it is compared exactly, because two packages
# whose names differ only in case are two packages.
if ($readingKeys -contains "identity" -and $null -ne $reading.identity) {
    $lockName = [string]$reading.identity.name
    $lockVersion = [string]$reading.identity.version
    if ($ManifestName) {
        if ([string]::IsNullOrWhiteSpace($lockName)) {
            $findings.Add("The lock file names no project, so it cannot be shown to be the lock for '$ManifestName'.")
        }
        elseif ($lockName -cne $ManifestName) {
            $findings.Add("The lock file is for project '$lockName', not for '$ManifestName'.")
        }
    }
    if ($ManifestVersion) {
        if ([string]::IsNullOrWhiteSpace($lockVersion)) {
            $findings.Add("The lock file records no project version, so it cannot be shown to be the lock for version '$ManifestVersion'.")
        }
        elseif ($lockVersion -cne $ManifestVersion) {
            $findings.Add("The lock file is for version '$lockVersion', not for '$ManifestVersion'.")
        }
    }
}

$approvedPackages = @($Toolchain.packages)
# Names are compared through the ecosystem's own canonical form, so NuGet's
# case-folding is honoured and RubyGems' case-sensitivity is not quietly
# discarded by PowerShell's -eq, which folds case for every ecosystem alike.
function script:Get-Canonical {
    param([AllowEmptyString()][string]$Name)
    return (Get-QaFoundryNormalisedPackageName -Ecosystem $ecosystem -Name $Name)
}
foreach ($approved in $approvedPackages) {
    $name = [string]$approved.name
    $canonical = Get-Canonical -Name $name
    $match = @($entries | Where-Object { (Get-Canonical -Name ([string]$_.name)) -ceq $canonical })
    if ($match.Count -eq 0) {
        $findings.Add("The lock file does not contain the approved package $name.")
        continue
    }
    if ([string]$match[0].version -cne [string]$approved.version) {
        $findings.Add("The lock file pins $name at $([string]$match[0].version), not the approved $([string]$approved.version).")
    }
}

# Compared per scope, because moving an approved package out of the development
# scope changes what a production install pulls in.
$direct = @()
if ($readingKeys -contains "direct") { $direct = @($reading.direct) }
if ($direct.Count -gt 0) {
    foreach ($scope in @("runtime", "dev")) {
        $declaredHere = @($direct | Where-Object { [string]$_.scope -eq $scope })
        $approvedHere = @($approvedPackages | Where-Object { [string]$_.scope -eq $scope })
        $approvedNames = @($approvedHere | ForEach-Object { Get-Canonical -Name ([string]$_.name) })
        foreach ($declared in $declaredHere) {
            $name = [string]$declared.name
            $canonical = Get-Canonical -Name $name
            if (@($approvedNames | Where-Object { $_ -ceq $canonical }).Count -eq 0) {
                $findings.Add("The lock file lists $name in the $scope scope, which nobody approved there.")
                continue
            }
            $approvedVersion = [string](@($approvedHere | Where-Object {
                (Get-Canonical -Name ([string]$_.name)) -ceq $canonical
            })[0].version)
            if (-not [string]::IsNullOrWhiteSpace([string]$declared.version) -and
                [string]$declared.version -cne $approvedVersion) {
                $findings.Add("The lock file asks for $name $([string]$declared.version) in the $scope scope, not the approved $approvedVersion.")
            }
        }
        $declaredNames = @($declaredHere | ForEach-Object { Get-Canonical -Name ([string]$_.name) })
        foreach ($approved in $approvedHere) {
            $canonical = Get-Canonical -Name ([string]$approved.name)
            if (@($declaredNames | Where-Object { $_ -ceq $canonical }).Count -eq 0) {
                $findings.Add("The lock file drops the approved $scope entry $([string]$approved.name).")
            }
        }
    }
}

$registryUri = $null
$registryPrefix = ""
$registryKnown = [Uri]::TryCreate([string]$Toolchain.source.registry, [UriKind]::Absolute, [ref]$registryUri)
if (-not $registryKnown) {
    $findings.Add("The locked toolchain has a registry that is not an absolute URL.")
    return New-Verdict
}
# A registry can be hosted under a path, and a feed one directory over is a
# different feed, so the approved prefix travels with the host comparison.
$registryPrefix = $registryUri.AbsolutePath.TrimEnd("/")

# Everything in the file gets installed, so transitive entries are held to the
# same origin and integrity rules as the ones a person named.
foreach ($entry in $entries) {
    $key = [string]$entry.key
    if ([string]::IsNullOrWhiteSpace($key)) { $key = [string]$entry.name }

    if ([bool]$entry.isLocal) {
        $findings.Add("The lock file points $key at a local path, which this manifest cannot produce.")
        continue
    }

    $integrity = [string]$entry.integrity
    if ([string]::IsNullOrWhiteSpace($integrity)) {
        $findings.Add("The lock file records no integrity hash for $key.")
    }
    elseif (-not (Test-QaFoundryPackageDigest -Value $integrity)) {
        # An unreadable hash is not a hash: there would be nothing to compare a
        # download against. "sha512-a" looks like one and carries a single byte.
        $findings.Add("The lock file records a hash for $key that is not a readable digest.")
    }

    $resolved = [string]$entry.resolvedUrl
    if ([string]::IsNullOrWhiteSpace($resolved)) {
        # Some lock formats record no origin at all - NuGet's is one - because
        # the feed is fixed by the configuration the restore runs under rather
        # than written into the file. Skipping the origin check silently would
        # be a hole, so the adapter has to say so, and it is only defensible
        # because every entry still carries a content hash: a hostile feed can
        # serve the request but cannot change the bytes without being caught.
        if (-not $originRecorded) {
            if ([string]::IsNullOrWhiteSpace($integrity)) {
                $findings.Add("The lock file records neither an origin nor a hash for $key, so nothing pins what would be installed.")
            }
            continue
        }
        # Others record the feed once for the whole file rather than per entry.
        # The adapter says so by reporting the feeds it read, and the origin is
        # then checked once instead of being skipped.
        if ($originIsPerFile) { continue }
        $findings.Add("The lock file records no resolved URL for $key.")
        continue
    }
    $entryUri = $null
    if (-not [Uri]::TryCreate($resolved, [UriKind]::Absolute, [ref]$entryUri)) {
        $findings.Add("The lock file resolves $key from something that is not an absolute URL.")
        continue
    }
    # Compared as a URL rather than as a string, because a host such as
    # "registry.npmjs.org.attacker.example" starts with the approved registry
    # and is a different machine.
    if ($entryUri.Scheme -ne "https" -or
        $entryUri.Host -ne $registryUri.Host -or
        $entryUri.Port -ne $registryUri.Port) {
        $findings.Add("The lock file resolves $key from $($entryUri.Host), not from the approved $($registryUri.Host).")
        continue
    }
    if ($registryPrefix -and
        -not ($entryUri.AbsolutePath.StartsWith("$registryPrefix/", [StringComparison]::Ordinal))) {
        $findings.Add("The lock file resolves $key from outside the approved feed $($registryUri.AbsoluteUri).")
    }
}

if ($originIsPerFile) {
    if ($declaredFeeds.Count -eq 0) {
        $findings.Add("The lock file names no feed, so nothing states where its packages would come from.")
    }
    foreach ($feed in $declaredFeeds) {
        $feedUri = $null
        if (-not [Uri]::TryCreate([string]$feed, [UriKind]::Absolute, [ref]$feedUri)) {
            $findings.Add("The lock file names a feed that is not an absolute URL: $feed")
            continue
        }
        if ($feedUri.Scheme -ne "https" -or
            $feedUri.Host -ne $registryUri.Host -or
            $feedUri.Port -ne $registryUri.Port) {
            $findings.Add("The lock file names the feed $($feedUri.Host), not the approved $($registryUri.Host).")
            continue
        }
        # A host is not a feed. One organisation's feed and another's sit on the
        # same host and differ only in the path, so the approved path travels
        # with the host here exactly as it does for a per-entry origin.
        $feedPath = $feedUri.AbsolutePath.TrimEnd("/")
        if (-not ($feedPath -ceq $registryPrefix -or
                $feedPath.StartsWith("$registryPrefix/", [StringComparison]::Ordinal))) {
            $findings.Add("The lock file names the feed $($feedUri.AbsoluteUri), which is not the approved $($registryUri.AbsoluteUri).")
        }
    }
}

# A programme's refusals are about what gets installed, not about who asked for
# it. Checking only the packages an agent named let a refused package in as
# somebody else's dependency, which is how most of them arrive. The lock is the
# first artefact in which the whole graph exists, so it is the place to ask.
if ($null -ne $PackagePolicy) {
    $policyFields = @(Get-QaFoundryPropertyNames -InputObject $PackagePolicy)

    $deniedPackages = @()
    if ($policyFields -contains "deniedPackages") {
        $deniedPackages = @(@($PackagePolicy.deniedPackages) |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { Get-Canonical -Name ([string]$_) })
    }
    if ($deniedPackages.Count -gt 0) {
        $refusedHere = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $entries) {
            $canonical = Get-Canonical -Name ([string]$entry.name)
            if (@($deniedPackages | Where-Object { $_ -ceq $canonical }).Count -eq 0) { continue }
            $refused = [string]$entry.name
            if (-not [string]::IsNullOrWhiteSpace([string]$entry.version)) {
                $refused = "$refused $([string]$entry.version)"
            }
            if ($refusedHere -notcontains $refused) { $refusedHere.Add($refused) }
        }
        if ($refusedHere.Count -gt 0) {
            $findings.Add("The resolved dependencies include $($refusedHere -join ', '), which this " +
                "programme refuses. A refused package counts whether it was chosen directly or " +
                "pulled in by something else, because either way it is installed.")
        }
    }

    $deniedLicenses = @()
    if ($policyFields -contains "deniedLicenses") {
        $deniedLicenses = @(@($PackagePolicy.deniedLicenses) |
            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
            ForEach-Object { ([string]$_).Trim().ToUpperInvariant() })
    }
    if ($deniedLicenses.Count -gt 0) {
        # Not every lock format records a licence. npm and Composer copy each
        # package's declared licence into the file; NuGet, Go and Bundler do
        # not, and there is nowhere else in this run to learn it from. A policy
        # that cannot be applied is not quietly skipped, because "no finding"
        # would read as "nothing is refused" - the one reading that is certainly
        # wrong. It fails closed and names what would have to change.
        $licensesRecorded = $false
        if ($readingKeys -contains "licensesRecorded") { $licensesRecorded = [bool]$reading.licensesRecorded }
        if (-not $licensesRecorded) {
            $findings.Add("This programme refuses $($deniedLicenses.Count) licence(s), but a " +
                "$($adapter.displayName) lock file records no licence for the packages it pins, so " +
                "this run cannot establish that the refused ones are absent. Either the licence " +
                "policy is dropped for $ecosystem or the dependencies are approved by something " +
                "that can read licences; guessing is not one of the options.")
        }
        else {
            $refusedLicenses = [System.Collections.Generic.List[string]]::new()
            $unstated = [System.Collections.Generic.List[string]]::new()
            foreach ($entry in $entries) {
                $name = [string]$entry.name
                $entryFields = @(Get-QaFoundryPropertyNames -InputObject $entry)
                $license = ""
                if ($entryFields -contains "license") { $license = ([string]$entry.license).Trim() }
                if ([string]::IsNullOrWhiteSpace($license)) {
                    if ($unstated -notcontains $name) { $unstated.Add($name) }
                    continue
                }
                # An SPDX expression can offer a choice or combine terms, and the
                # refused identifier is one token inside it. Splitting on the
                # operators and the brackets compares identifiers rather than
                # searching for a substring, so "GPL-3.0" does not match
                # "LGPL-3.0" and "AGPL-3.0-or-later" is still caught by
                # "AGPL-3.0-or-later".
                $tokens = @(($license.ToUpperInvariant() -split "\s+(?:OR|AND|WITH)\s+|[()]") |
                    ForEach-Object { ([string]$_).Trim() } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                foreach ($token in $tokens) {
                    if (@($deniedLicenses | Where-Object { $_ -ceq $token }).Count -eq 0) { continue }
                    $refused = "$name ($license)"
                    if ($refusedLicenses -notcontains $refused) { $refusedLicenses.Add($refused) }
                }
            }
            if ($refusedLicenses.Count -gt 0) {
                $findings.Add("The resolved dependencies include $($refusedLicenses -join ', '), " +
                    "under a licence this programme refuses.")
            }
            if ($unstated.Count -gt 0) {
                # A package whose licence the lock does not state is one whose
                # terms nobody has read. With a licence policy in force that is
                # a gap, not a pass.
                $findings.Add("The lock file states no licence for " +
                    "$(@($unstated | Sort-Object) -join ', '), so this run cannot establish that " +
                    "they are not under a refused one.")
            }
        }
    }
}

return New-Verdict
