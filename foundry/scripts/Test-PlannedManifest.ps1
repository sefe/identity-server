[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Changes,
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Materializations,
    [string]$ToolchainLockPath = "",
    [switch]$RequireTestCommand
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Common.ps1")

# A resolver builds a lock from the packages that were decided on rather than
# from whatever the model wrote, so a manifest that installs anything else - a
# workspace, a child package, a local path - produces a lock that does not match
# it, and the install fails at the far end of the relay. Build 466 reached the
# materialiser for the first time and stopped exactly here: the blueprint named
# three automation projects and the generator turned them into an npm workspace.
# Several projects are directories and runner-native projects inside one
# package, not packages of their own.
#
# Which keys mean that, and which specifiers point at a local directory, differ
# per ecosystem, so both come from the adapter. This file knows only that such
# things exist.

function Get-NormalizedPlanPath {
    param([string]$Path)
    return (([string]$Path).Replace("\", "/") -replace "^\./", "").TrimStart("/")
}

$findings = [System.Collections.Generic.List[string]]::new()

$changeByPath = @{}
foreach ($change in @($Changes)) {
    if ($null -eq $change) { continue }
    $fields = @(Get-QaFoundryPropertyNames -InputObject $change)
    if ($fields -notcontains "path") { continue }
    $operation = if ($fields -contains "operation") { [string]$change.operation } else { "" }
    if ($operation -eq "delete") { continue }
    $normalized = Get-NormalizedPlanPath -Path ([string]$change.path)
    $content = if ($fields -contains "content") { [string]$change.content } else { "" }
    $changeByPath[$normalized] = $content
}

foreach ($materialization in @($Materializations)) {
    if ($null -eq $materialization) { continue }
    $fields = @(Get-QaFoundryPropertyNames -InputObject $materialization)
    if ($fields -notcontains "manifestPath") { continue }
    $manifestPath = Get-NormalizedPlanPath -Path ([string]$materialization.manifestPath)
    $manifestDirectory = [string](Split-Path $manifestPath -Parent).Replace("\", "/")

    # A manifest the plan does not carry is the materialiser's business, not this
    # check's: it can only judge what the plan actually writes.
    if (-not $changeByPath.ContainsKey($manifestPath)) { continue }

    $recipe = if ($fields -contains "recipe") { [string]$materialization.recipe } else { "" }
    try { $adapter = Get-QaFoundryEcosystemAdapterByRecipe -Recipe $recipe }
    catch {
        $findings.Add("The plan asks for $manifestPath to be materialised by a recipe this " +
            "runtime cannot perform: $($_.Exception.Message)")
        continue
    }
    $adapterKeys = @(Get-QaFoundryPropertyNames -InputObject $adapter)

    $manifestContent = [string]$changeByPath[$manifestPath]
    if ([string]::IsNullOrWhiteSpace($manifestContent)) {
        $findings.Add("The planned manifest $manifestPath is empty.")
        continue
    }

    # Reading the manifest is the adapter's job, and failing to read it is a
    # finding rather than a crash: the generator gets told what was wrong with
    # what it wrote and still has an attempt left.
    $declared = @()
    try { $declared = @(& $adapter.ReadManifestDependencies $manifestContent) }
    catch {
        $findings.Add("The planned manifest $manifestPath could not be read as " +
            "$($adapter.displayName): $($_.Exception.Message)")
        continue
    }

    $unverifiableKeys = @()
    if ($adapterKeys -contains "unverifiableManifestKeys") {
        $unverifiableKeys = @($adapter.unverifiableManifestKeys)
    }
    if ($unverifiableKeys.Count -gt 0) {
        # A JSON manifest is read as JSON, so only a real top-level declaration
        # counts and the word "overrides" inside a description is not mistaken
        # for one. A manifest in any other format has no such structure to lean
        # on here, so it falls back to a word-boundary scan of the text: an
        # occasional false refusal costs the generator one attempt, while a
        # missed workspace costs the run its lock file.
        $present = @()
        $parsedManifest = $null
        try { $parsedManifest = $manifestContent | ConvertFrom-Json -Depth 50 }
        catch { $parsedManifest = $null }
        if ($null -ne $parsedManifest) {
            $topLevelKeys = @(Get-QaFoundryPropertyNames -InputObject $parsedManifest)
            $present = @($unverifiableKeys | Where-Object { $topLevelKeys -contains [string]$_ })
        }
        else {
            $present = @($unverifiableKeys | Where-Object {
                $manifestContent -match ("(?i)(^|[^A-Za-z0-9_-])" +
                    [regex]::Escape([string]$_) + "([^A-Za-z0-9_-]|$)")
            })
        }
        if ($present.Count -gt 0) {
            $findings.Add(
                "The planned manifest $manifestPath declares $($present -join ', '). " +
                "The $($adapter.recipe) recipe cannot materialise that. Remove workspaces, child " +
                "manifests and local or linked dependencies; use one root package and " +
                "runner-native project configuration.")
        }
    }

    $localPrefixes = @()
    if ($adapterKeys -contains "localDependencyPrefixes") {
        $localPrefixes = @($adapter.localDependencyPrefixes)
    }
    foreach ($dependency in $declared) {
        $specifier = [string]$dependency.version
        $localPrefix = @($localPrefixes | Where-Object {
            $specifier.StartsWith([string]$_, [StringComparison]::OrdinalIgnoreCase)
        })
        if ($localPrefix.Count -gt 0) {
            $findings.Add(
                "The planned manifest $manifestPath depends on $([string]$dependency.name) through " +
                "'$specifier'. A local or linked dependency cannot be resolved against a package " +
                "feed. Depend only on packages the resolver can pin.")
        }
    }

    # A child manifest beside the root one turns the package into a workspace even
    # when the root manifest says nothing about it, because the resolver treats it
    # as a separate package the moment anyone installs from that directory.
    # Matched by the adapter's manifest pattern rather than by a fixed name, so
    # this holds for an ecosystem that names each manifest after its project.
    $manifestPattern = [string]$adapter.manifestPattern
    if (-not [string]::IsNullOrWhiteSpace($manifestPattern)) {
        $childManifests = @($changeByPath.Keys | Where-Object {
            $_ -cne $manifestPath -and
            $_ -match $manifestPattern -and
            ($manifestDirectory -eq "" -or $_.StartsWith("$manifestDirectory/", [StringComparison]::Ordinal))
        } | Sort-Object)
        if ($childManifests.Count -gt 0) {
            $findings.Add(
                "The plan writes $($childManifests -join ', ') beneath $manifestPath. " +
                "The $($adapter.recipe) recipe materialises a single package, so the automation " +
                "projects it serves are directories inside that package rather than packages of " +
                "their own.")
        }
    }
}

# Every manifest the plan writes, whether or not this answer also says how it is
# to be materialised. A resolver pins one version and writes it into the lock,
# so a manifest that asks for a range is asking for a lock it does not match,
# and the materialiser refuses it at a stage that has no way back to the agent.
# Build 972914 blocked there, at stage 11 of 13, on 'MSTest@[4.2.3,5.0.0)'.
#
# Which paths are manifests, and what counts as an exact version, are the
# adapters' business: asked of them rather than listed here, so an installation
# that gains an ecosystem gains this with it.
$manifestPatterns = [ordered]@{}
foreach ($id in @(Get-QaFoundryEcosystemAdapterNames)) {
    try { $candidate = Get-QaFoundryEcosystemAdapter -Ecosystem $id } catch { continue }
    $pattern = [string]$candidate.manifestPattern
    if (-not [string]::IsNullOrWhiteSpace($pattern)) { $manifestPatterns[$id] = $pattern }
}

# The version was decided once, by the resolver, and written into the lock. The
# agent that writes the manifest is not choosing it again, so where the lock
# speaks the check quotes it rather than asking for "an exact version" and
# leaving the agent to guess which. In build 972914 the lock held both numbers:
# version 4.4.0 and, beside it, the 'requested' range the resolver had been
# given. The manifest came back carrying the range.
$lockedPackages = @{}
if ($ToolchainLockPath -ne "" -and (Test-Path -LiteralPath $ToolchainLockPath -PathType Leaf)) {
    try {
        $lock = Get-Content -LiteralPath $ToolchainLockPath -Raw | ConvertFrom-Json -Depth 50
        foreach ($toolchain in @($lock.toolchains)) {
            if ($null -eq $toolchain) { continue }
            $lockEcosystem = ([string]$toolchain.ecosystem).Trim().ToLowerInvariant()
            if ($lockEcosystem -eq "") { continue }
            foreach ($package in @($toolchain.packages)) {
                if ($null -eq $package) { continue }
                $packageName = [string]$package.name
                $packageVersion = [string]$package.version
                if ($packageName -eq "" -or $packageVersion -eq "") { continue }
                $canonical = Get-QaFoundryNormalisedPackageName -Ecosystem $lockEcosystem `
                    -Name $packageName
                $lockedPackages["$lockEcosystem|$canonical"] = [pscustomobject]@{
                    name = $packageName
                    version = $packageVersion
                    toolchainId = [string]$toolchain.id
                }
            }
        }
    }
    catch {
        # An unreadable lock is the resolver's problem to answer for, and the
        # materialiser will say so. Judging the manifest against half a lock
        # would refuse a manifest that is right.
        $lockedPackages = @{}
    }
}

foreach ($path in @($changeByPath.Keys | Sort-Object)) {
    $ecosystem = ""
    foreach ($id in @($manifestPatterns.Keys)) {
        if ($path -match [string]$manifestPatterns[$id]) { $ecosystem = [string]$id; break }
    }
    if ([string]::IsNullOrWhiteSpace($ecosystem)) { continue }
    try { $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $ecosystem } catch { continue }
    if ($RequireTestCommand -and $ecosystem -eq 'npm') {
        try {
            $package = $changeByPath[$path] | ConvertFrom-Json -Depth 50
            if (-not $package.PSObject.Properties['scripts'] -or
                -not $package.scripts.PSObject.Properties['test'] -or
                [string]::IsNullOrWhiteSpace([string]$package.scripts.test)) {
                $findings.Add("The verification adapter invokes npm test, but $path has no scripts.test. " +
                    "Provide an executable local test selection with real assertions; preserve deployed tests separately. " +
                    "Typechecking, listing tests and an empty or skipped suite do not satisfy verification.")
            }
        } catch { $findings.Add("The planned npm test manifest $path is not valid JSON.") }
    }

    # A manifest that cannot be read is left to the checks above and to the
    # materialiser: this pass judges specifiers, and has nothing to say about a
    # file it could not parse.
    $declared = @()
    try { $declared = @(& $adapter.ReadManifestDependencies ([string]$changeByPath[$path])) }
    catch { continue }

    foreach ($dependency in $declared) {
        $specifier = [string]$dependency.version
        # A private package is asked for neither a name nor a version, so an
        # absent specifier is not a range and is not this check's business.
        if ([string]::IsNullOrWhiteSpace($specifier)) { continue }
        $canonical = Get-QaFoundryNormalisedPackageName -Ecosystem $adapter.id `
            -Name ([string]$dependency.name)
        $locked = $null
        if ($lockedPackages.ContainsKey("$($adapter.id)|$canonical")) {
            $locked = $lockedPackages["$($adapter.id)|$canonical"]
        }
        if ($null -ne $locked) {
            # Case-sensitively, because a feed will serve a differently-cased
            # version string as a different version where it serves one at all.
            if ($specifier -cne [string]$locked.version) {
                $findings.Add(
                    "The planned manifest $path asks for $([string]$dependency.name) at " +
                    "'$specifier'. This run already resolved that package: toolchain " +
                    "'$([string]$locked.toolchainId)' pins $([string]$locked.name) at " +
                    "$([string]$locked.version), and the lock file will name that version. " +
                    "Write the pinned version, not the range it was resolved from.")
            }
            continue
        }
        if (Test-QaFoundryExactVersion -Ecosystem $adapter.id -Version $specifier) { continue }
        $findings.Add(
            "The planned manifest $path asks for $([string]$dependency.name) at '$specifier'. " +
            "The resolver pins one version and writes that version into the lock file, so a " +
            "range, a wildcard or a floating specifier cannot be materialised. Name the single " +
            "version the locked toolchain pins for this run.")
    }
}

return @($findings)
