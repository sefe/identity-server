[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BlueprintPath,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$StageId,
    # The locked toolchain itself. Written once and never rewritten: everything
    # downstream builds against this file, and a file that changes underneath a
    # decision is not a lock.
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$EvidencePath,
    # A test seam, not a configuration knob. Given a registry and a package name
    # it returns the versions that exist. Nothing in a workflow file may choose
    # it, or "we checked the package exists" would mean whatever the workflow
    # wanted it to mean.
    [AllowNull()][scriptblock]$VersionSource = $null
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../Common.ps1")
$schemaRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../schemas")).Path

$checks = [System.Collections.Generic.List[object]]::new()
$findings = [System.Collections.Generic.List[string]]::new()
$evidence = [ordered]@{
    runId = $RunId
    stageId = $StageId
    status = "blocked"
    cause = ""
    blueprintSha256 = ""
    toolchains = @()
    checks = @()
    findings = @()
}

function Add-Check {
    param([string]$Name, [string]$Outcome, [string]$Detail)
    $checks.Add([ordered]@{ name = $Name; outcome = $Outcome; detail = $Detail })
}

function Write-Evidence {
    param([string]$Status, $Toolchains = @())
    $evidence.status = $Status
    $evidence.toolchains = @($Toolchains)
    $evidence.checks = @($checks)
    $evidence.findings = @($findings)
    New-Item -ItemType Directory -Path (Split-Path $EvidencePath -Parent) -Force | Out-Null
    $evidence | ConvertTo-Json -Depth 30 |
        Set-Content -LiteralPath $EvidencePath -Encoding utf8 -NoNewline
}

# Two different failures wearing the same face would be the worst outcome here.
# A stack nobody can install is the architect's problem and the run should go
# back and choose again; a feed that did not answer is nobody's design problem
# and retrying the same choice is exactly right. They are reported apart.
function New-Refusal {
    param([string]$Reason, [string]$Status = "blocked", [string]$Cause = "")
    $findings.Add($Reason)
    # Three different failures used to arrive wearing one face. A range written
    # in another ecosystem's notation, a package that satisfies nothing
    # published, and a feed that did not answer call for three different
    # responses - correct the design, choose another version, try again later -
    # and the evidence has to say which one this was, in a word a later stage
    # can read without parsing prose.
    if (-not [string]::IsNullOrWhiteSpace($Cause)) {
        $evidence.cause = $Cause
        Add-Check -Name "toolchain.$Cause" -Outcome "failed" -Detail $Reason
    }
    Write-Evidence -Status $Status
    return [pscustomobject][ordered]@{
        runId = $RunId
        stageId = $StageId
        handler = "resolve_toolchain"
        status = $Status
        dryRun = $false
        actions = @()
        evidence = @($EvidencePath)
    }
}

function Get-ContentSha256 {
    param([string]$Value)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes([string]$Value)
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes)) -replace "-", "").ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function ConvertTo-Slug {
    param([string]$Value)
    $slug = ([string]$Value).ToLowerInvariant() -replace "[^a-z0-9]+", "-"
    return $slug.Trim("-")
}

# Enough of a version to order two of them and to decide whether one satisfies a
# range. Deliberately small: a full semantic-version implementation invites the
# belief that every range expression works, and the ones that do are listed in
# the architect's prompt.
function ConvertTo-VersionParts {
    param([string]$Version)
    $core = ([string]$Version).Trim()
    $prerelease = ""
    $plus = $core.IndexOf("+")
    if ($plus -ge 0) { $core = $core.Substring(0, $plus) }
    $dash = $core.IndexOf("-")
    if ($dash -ge 0) {
        $prerelease = $core.Substring($dash + 1)
        $core = $core.Substring(0, $dash)
    }
    $segments = @($core.Split("."))
    $numbers = @(0, 0, 0)
    for ($index = 0; $index -lt 3; $index++) {
        if ($index -lt $segments.Count) {
            $parsed = 0
            if (-not [int]::TryParse($segments[$index], [ref]$parsed)) { return $null }
            $numbers[$index] = $parsed
        }
    }
    return [pscustomobject]@{
        major = $numbers[0]
        minor = $numbers[1]
        patch = $numbers[2]
        prerelease = $prerelease
        isPrerelease = -not [string]::IsNullOrEmpty($prerelease)
    }
}

function Compare-VersionParts {
    param($Left, $Right)
    foreach ($field in @("major", "minor", "patch")) {
        if ($Left.$field -ne $Right.$field) {
            return [int]([Math]::Sign($Left.$field - $Right.$field))
        }
    }
    # A released version outranks any pre-release of the same numbers; two
    # pre-releases fall back to ordinal comparison, which is the best that can
    # be said without a full specification.
    if ($Left.isPrerelease -and -not $Right.isPrerelease) { return -1 }
    if (-not $Left.isPrerelease -and $Right.isPrerelease) { return 1 }
    return [int][Math]::Sign([string]::CompareOrdinal($Left.prerelease, $Right.prerelease))
}

function Test-VersionSatisfies {
    param([string]$Version, [string]$Range)

    $candidate = ConvertTo-VersionParts -Version $Version
    if ($null -eq $candidate) { return $false }
    $expression = ([string]$Range).Trim()
    if ($expression -in @("*", "latest", "x")) { return $true }

    if ($expression -match "^([~^]|>=)?\s*([0-9]+)(?:\.([0-9]+|x|\*))?(?:\.([0-9]+|x|\*))?(?:-([0-9A-Za-z.-]+))?$") {
        $operator = [string]$Matches[1]
        $major = [int]$Matches[2]
        $minorToken = [string]$Matches[3]
        $patchToken = [string]$Matches[4]
        $prerelease = [string]$Matches[5]
        $minorIsWildcard = ([string]::IsNullOrEmpty($minorToken) -or $minorToken -in @("x", "*"))
        $patchIsWildcard = ([string]::IsNullOrEmpty($patchToken) -or $patchToken -in @("x", "*"))
        $minor = if ($minorIsWildcard) { 0 } else { [int]$minorToken }
        $patch = if ($patchIsWildcard) { 0 } else { [int]$patchToken }
        $floor = [pscustomobject]@{
            major = $major; minor = $minor; patch = $patch
            prerelease = $prerelease
            isPrerelease = -not [string]::IsNullOrEmpty($prerelease)
        }

        switch ($operator) {
            ">=" { return ((Compare-VersionParts -Left $candidate -Right $floor) -ge 0) }
            "^" {
                if ((Compare-VersionParts -Left $candidate -Right $floor) -lt 0) { return $false }
                # Caret keeps the leftmost non-zero segment, which is what makes
                # ^0.2.1 a different promise from ^1.2.1.
                if ($major -gt 0) { return ($candidate.major -eq $major) }
                if ($minor -gt 0) { return ($candidate.major -eq 0 -and $candidate.minor -eq $minor) }
                return ($candidate.major -eq 0 -and $candidate.minor -eq 0)
            }
            "~" {
                if ((Compare-VersionParts -Left $candidate -Right $floor) -lt 0) { return $false }
                if ($minorIsWildcard) { return ($candidate.major -eq $major) }
                return ($candidate.major -eq $major -and $candidate.minor -eq $minor)
            }
            default {
                if ($minorIsWildcard) { return ($candidate.major -eq $major) }
                if ($patchIsWildcard) {
                    return ($candidate.major -eq $major -and $candidate.minor -eq $minor)
                }
                return ((Compare-VersionParts -Left $candidate -Right $floor) -eq 0)
            }
        }
    }
    return $null
}

if (-not (Test-Path -LiteralPath $BlueprintPath)) {
    return New-Refusal -Reason "The approved blueprint is missing: $BlueprintPath"
}
$blueprintJson = Get-Content -LiteralPath $BlueprintPath -Raw
# Hashed from the file rather than from the decoded text, because that is how
# every later stage hashes it and a mismatch here would look like tampering.
$evidence.blueprintSha256 = (Get-FileHash -LiteralPath $BlueprintPath -Algorithm SHA256).Hash.ToLowerInvariant()
$blueprint = $blueprintJson | ConvertFrom-Json -Depth 60

if ([string]$blueprint.runId -ne $RunId) {
    return New-Refusal -Reason ("The approved blueprint belongs to run '$([string]$blueprint.runId)', " +
        "not to this run '$RunId'.")
}
if ([string]$blueprint.status -ne "completed") {
    return New-Refusal -Reason ("The approved blueprint did not complete: its status is " +
        "'$([string]$blueprint.status)', so no technology decision in it was settled.")
}
$projects = @($blueprint.details.automationProjects)
if ($projects.Count -eq 0) {
    return New-Refusal -Reason "The approved blueprint names no automation project to resolve a toolchain for."
}

$supported = @(Resolve-QaFoundryAutomationEcosystems -Automation $Config.automation)
$policy = Resolve-QaFoundryPackagePolicy -Automation $Config.automation
if ($supported.Count -eq 0) {
    return New-Refusal -Reason "This installation declares no package ecosystem, so nothing can be resolved."
}

# Projects that made the same decision share one locked toolchain, which is what
# lets one manifest serve several projects later. Projects that decided
# differently get their own, however similar the two look.
$decisions = [ordered]@{}
foreach ($project in $projects) {
    $projectName = [string]$project.name
    $names = @(Get-QaFoundryPropertyNames -InputObject $project)
    if ($names -notcontains "toolchain" -or $null -eq $project.toolchain) {
        return New-Refusal -Reason ("Automation project '$projectName' carries no technology decision, " +
            "so there is nothing to resolve and nothing anyone could review.")
    }
    $decision = $project.toolchain
    $ecosystemId = ([string]$decision.ecosystem).Trim().ToLowerInvariant()
    $ecosystem = @($supported | Where-Object { [string]$_.id -eq $ecosystemId })
    if ($ecosystem.Count -ne 1) {
        return New-Refusal -Reason ("Automation project '$projectName' is designed on the " +
            "'$ecosystemId' ecosystem, which this installation cannot install, build or run. " +
            "Supported: $(@($supported | ForEach-Object { [string]$_.id }) -join ', ').")
    }
    $proposed = @($decision.packages)
    if ([int]$policy.maxDirectPackages -gt 0 -and $proposed.Count -gt [int]$policy.maxDirectPackages) {
        return New-Refusal -Reason ("Automation project '$projectName' proposes $($proposed.Count) " +
            "direct packages against a limit of $([int]$policy.maxDirectPackages).")
    }
    $canonicalProposal = [ordered]@{
        ecosystem = $ecosystemId
        language = [string]$decision.language
        testFramework = [string]$decision.testFramework
        runtime = [ordered]@{
            name = [string]$decision.runtime.name
            version = [string]$decision.runtime.version
        }
        packages = @(@($proposed | Sort-Object { [string]$_.name }) | ForEach-Object {
            [ordered]@{
                name = ([string]$_.name).Trim()
                version = ([string]$_.version).Trim()
                scope = [string]$_.scope
            }
        })
    }
    $decisionKey = Get-ContentSha256 -Value ($canonicalProposal | ConvertTo-Json -Depth 10 -Compress)
    if (-not $decisions.Contains($decisionKey)) {
        $slugParts = @($ecosystemId, (ConvertTo-Slug -Value ([string]$decision.testFramework))) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        $decisions[$decisionKey] = [ordered]@{
            id = (@($slugParts) -join "-")
            ecosystem = $ecosystem[0]
            proposal = $canonicalProposal
            projectPaths = [System.Collections.Generic.List[string]]::new()
            projectNames = [System.Collections.Generic.List[string]]::new()
        }
    }
    $decisions[$decisionKey].projectPaths.Add(([string]$project.path))
    $decisions[$decisionKey].projectNames.Add($projectName)
}

# Two different decisions that slug to the same name would produce two locks
# claiming one identity, and every later stage looks a toolchain up by that
# identity.
$identities = @{}
foreach ($key in @($decisions.Keys)) {
    $identity = [string]$decisions[$key].id
    if ($identities.ContainsKey($identity)) {
        $decisions[$key].id = "$identity-" + $key.Substring(0, 8)
    }
    $identities[$identity] = $true
}
Add-Check -Name "blueprint.decisions" -Outcome "passed" `
    -Detail "The approved blueprint carries $($decisions.Count) distinct technology decision(s) across $($projects.Count) project(s)."

$deniedPackageNames = @($policy.deniedPackages |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { [string]$_ })
$locked = [System.Collections.Generic.List[object]]::new()
foreach ($key in @($decisions.Keys)) {
    $decision = $decisions[$key]
    $ecosystem = $decision.ecosystem
    $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem ([string]$ecosystem.id)
    $registry = [string]$ecosystem.source.registry
    $probe = if ($null -ne $VersionSource) { $VersionSource } else { $adapter.GetPublishedVersions }
    # Whether a refused name matches is the registry's rule about identity, not
    # a lower-cased string comparison: folding case for RubyGems would refuse a
    # different gem from the one that was named.
    $deniedHere = @($deniedPackageNames |
        ForEach-Object { Get-QaFoundryNormalisedPackageName -Ecosystem ([string]$ecosystem.id) -Name $_ })

    $pinned = [System.Collections.Generic.List[object]]::new()
    foreach ($package in @($decision.proposal.packages)) {
        $packageName = [string]$package.name
        $canonicalName = Get-QaFoundryNormalisedPackageName -Ecosystem ([string]$ecosystem.id) -Name $packageName
        if (@($deniedHere | Where-Object { $_ -ceq $canonicalName }).Count -gt 0) {
            return New-Refusal -Status "revision_required" -Cause "denied_package" -Reason (
                "The design depends on '$packageName', which this programme " +
                "refuses. Meet the same need another way.")
        }
        # The notation is read before the feed is asked. A range written in
        # another ecosystem's spelling matches nothing published, and reporting
        # that as "nothing satisfies it" sends everyone to look at the registry
        # for a package that is sitting there.
        $rangeVerdict = Test-QaFoundryVersionRange -Ecosystem ([string]$ecosystem.id) `
            -Range ([string]$package.version)
        if (-not [bool]$rangeVerdict.valid) {
            return New-Refusal -Status "revision_required" -Cause "invalid_range" -Reason (
                "The version requested for '$packageName' is not written in a notation " +
                "$([string]$ecosystem.id) uses, so no published version could satisfy it. " +
                [string]$rangeVerdict.reason)
        }
        $available = $null
        try {
            $available = @(& $probe $registry $packageName)
        }
        catch {
            # The feed not answering says nothing about whether this was a good
            # choice, so the run is not sent back to redesign over it.
            return New-Refusal -Status "failed" -Cause "registry_unreachable" -Reason (
                "The package feed at $registry could not be " +
                "reached while looking up '$packageName': $($_.Exception.Message). This is the " +
                "infrastructure being unavailable, not a fault in the design.")
        }
        if ($available.Count -eq 0) {
            return New-Refusal -Status "revision_required" -Cause "package_not_found" -Reason (
                "The design depends on '$packageName', which does not exist " +
                "at $registry. Name a package that exists.")
        }
        $explicitPrerelease = $policy.allowPrerelease -and ([string]$package.version -match '-[0-9A-Za-z]')
        if (-not $explicitPrerelease) {
            $available = @($available | Where-Object {
                -not (ConvertTo-QaFoundryVersionParts -Version $_).isPrerelease
            })
        }
        $requested = [string]$package.version
        # Each ecosystem reads its own range notation. npm's caret is not NuGet's
        # bracket, and a single shared reading would silently mean the wrong
        # thing in one of them.
        $best = [string](& $adapter.SelectVersion $requested @($available | ForEach-Object { [string]$_ }) ([bool]$explicitPrerelease))
        if ([string]::IsNullOrWhiteSpace($best)) {
            return New-Refusal -Status "revision_required" -Cause "no_matching_version" -Reason (
                "Nothing published for '$packageName' satisfies '$requested'" +
                $(if (-not $policy.allowPrerelease) { " among released versions" } else { "" }) +
                ". The feed has: $(@($available | Select-Object -Last 5) -join ', ').")
        }
        $pinned.Add([ordered]@{
            key = (ConvertTo-Slug -Value $packageName)
            name = $packageName
            version = [string]$best
            scope = [string]$package.scope
            requested = $requested
        })
    }

    # The design says which runtime it is written for, and this installation says
    # which one it has. Until now only the second survived: the first was
    # overwritten here, so a design for one framework was locked, built and
    # shipped against another without anything in the evidence saying so. The
    # adapter is asked instead, because what "compatible" means differs by
    # ecosystem - an SDK builds older targets, a Node major does not run newer
    # code - and it either returns the runtime that honours the design or says
    # plainly why this machine cannot.
    $lockedRuntime = $ecosystem.canonicalRuntime
    if (@(Get-QaFoundryPropertyNames -InputObject $adapter) -contains "ResolveProposedRuntime") {
        try {
            $lockedRuntime = & $adapter.ResolveProposedRuntime $ecosystem.runtime `
                $ecosystem.canonicalRuntime ([string]$decision.proposal.runtime.name) `
                ([string]$decision.proposal.runtime.version)
        }
        catch {
            return New-Refusal -Reason ("The toolchain for " +
                "$(@($decision.projectNames) -join ', ') cannot be locked. $($_.Exception.Message)")
        }
    }

    $canonical = [ordered]@{
        id = [string]$decision.id
        revision = 1
        ecosystem = [string]$ecosystem.id
        recipe = [string]$ecosystem.recipe
        source = [ordered]@{
            id = [string]$ecosystem.source.id
            registry = $registry
            authentication = [string]$ecosystem.source.authentication
        }
        runtime = $lockedRuntime
        packages = @(@($pinned) | Sort-Object { [string]$_.key })
        decidedFor = @($decision.projectPaths)
        language = [string]$decision.proposal.language
        testFramework = [string]$decision.proposal.testFramework
    }
    $canonical.sha256 = Get-ContentSha256 -Value ($canonical | ConvertTo-Json -Depth 20 -Compress)
    $locked.Add($canonical)
    Add-Check -Name "toolchain.$([string]$decision.id)" -Outcome "passed" `
        -Detail ("Pinned $($pinned.Count) package(s) from $registry for " +
            "$(@($decision.projectNames) -join ', ').")
}

$lock = [ordered]@{
    runId = $RunId
    stageId = $StageId
    blueprintSha256 = $evidence.blueprintSha256
    resolvedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    toolchains = @($locked | Sort-Object { [string]$_.id })
}

# The lock is written once. A second stage that resolved again and quietly
# replaced it would leave every earlier check describing a file that no longer
# exists, so a differing rewrite is refused rather than merged.
if (Test-Path -LiteralPath $OutputPath) {
    $existing = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -Depth 30
    $existingIds = @(@($existing.toolchains | ForEach-Object { "$([string]$_.id)|$([string]$_.sha256)" }) | Sort-Object)
    $newIds = @(@($lock.toolchains | ForEach-Object { "$([string]$_.id)|$([string]$_.sha256)" }) | Sort-Object)
    if (($existingIds -join ",") -ne ($newIds -join ",")) {
        return New-Refusal -Reason ("A locked toolchain already exists for this run and resolving " +
            "again produced a different answer. The lock is what everything downstream was built " +
            "against, so it is not replaced.")
    }
    Add-Check -Name "lock.stable" -Outcome "passed" -Detail "Re-resolving produced the same lock."
}
New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force | Out-Null
$lock | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputPath -Encoding utf8 -NoNewline
$null = & (Join-Path $PSScriptRoot "../Validate-JsonArtifact.ps1") `
    -ArtifactPath $OutputPath `
    -SchemaPath (Join-Path $schemaRoot "runtime/toolchain-lock.schema.json") `
    -SchemaRoot $schemaRoot

Write-Evidence -Status "completed" -Toolchains @($lock.toolchains | ForEach-Object {
    [ordered]@{
        id = [string]$_.id
        ecosystem = [string]$_.ecosystem
        registry = [string]$_.source.registry
        sha256 = [string]$_.sha256
        packageCount = @($_.packages).Count
        projectPaths = @($_.decidedFor)
    }
})

return [pscustomobject][ordered]@{
    runId = $RunId
    stageId = $StageId
    handler = "resolve_toolchain"
    status = "completed"
    dryRun = $false
    actions = @()
    evidence = @($EvidencePath)
    produced = @($OutputPath)
}
