[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][string]$RunConfigurationPath,
    [Parameter(Mandatory)][string]$BlueprintPath,
    # What the resolver actually pinned. The blueprint says what the architect
    # decided; this says what exists. Generation and verification read this, so a
    # run can never build against a version nobody confirmed.
    [Parameter(Mandatory)][string]$ToolchainLockPath,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$StageId,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$ReviewSubjectPath,
    [Parameter(Mandatory)][string]$EvidencePath,
    [Parameter(Mandatory)][string]$WorkRoot,
    # Where a lock that has already been resolved is kept so that a leg killed
    # partway through a multi-project plan does not pay for the same npm
    # resolutions again. Empty means nothing is remembered.
    [string]$CheckpointRoot = "",
    # Saved generation plans provide hash-bound resolver recipes after a repair
    # planner reports no dependency changes. Their manifests must be unchanged.
    [string]$RunRoot = "",
    # Where the merged decision will live in the repository, as the repository
    # spells it. Empty means this run records nothing, and the next run would be
    # free to choose the technology again.
    [string]$ToolchainRecordPath = "",
    # The checkout the record will be written into. Only ever read, and only to
    # tell a first decision from a revision of one: a change set that says
    # "create" for a file that already exists is a change set the writer is
    # right to refuse.
    [string]$RepositoryRoot = "",
    [AllowNull()][object]$Deadline = $null,
    # A test seam, not a configuration knob: nothing in a workflow file may
    # choose which resolver runs, or the isolation around it would be a
    # suggestion rather than a guarantee. Keyed by the adapter's tool keys, so
    # a stub can stand in for any ecosystem's package manager rather than only
    # for npm's.
    [hashtable]$ToolCommandOverrides = @{},
    [string]$NpmCommand = "",
    [string]$NodeCommand = "",
    # A rehearsal resolves nothing. Resolution is the first stage that reaches a
    # package registry, and it can only run on an agent that has the exact
    # toolchain the decision was settled on installed. A rehearsal is expected
    # to run anywhere, so it is gated the same way every other side effect in a
    # rehearsal is, and the change set it produces says out loud that it carries
    # no lock rather than carrying one nobody resolved.
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../Common.ps1")
$schemaRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../schemas")).Path

# The npm-shaped seams predate the ecosystem adapters and are still how the
# existing tests point the resolver at a stub, so they are folded into the
# general form rather than kept as a second path through the code.
if (-not [string]::IsNullOrWhiteSpace($NpmCommand)) { $ToolCommandOverrides["npm"] = $NpmCommand }
if (-not [string]::IsNullOrWhiteSpace($NodeCommand)) { $ToolCommandOverrides["node"] = $NodeCommand }

$checks = [System.Collections.Generic.List[object]]::new()
$findings = [System.Collections.Generic.List[string]]::new()
# One plan can ask for several lock files, so the record of what was resolved is
# a list. A scalar would silently describe only the last attempt and hide the
# rest.
$resolutions = [System.Collections.Generic.List[object]]::new()
$evidence = [ordered]@{
    runId = $RunId
    stageId = $StageId
    status = "blocked"
    dryRun = [bool]$DryRun
    blueprintSha256 = ""
    materialisations = @()
    checks = @()
    findings = @()
}

function Add-Resolution {
    param([System.Collections.Specialized.OrderedDictionary]$Record)
    $resolutions.Add($Record)
}

function Add-Check {
    param([string]$Name, [string]$Outcome, [string]$Detail)
    $checks.Add([ordered]@{ name = $Name; outcome = $Outcome; detail = $Detail })
}

function Write-Evidence {
    param([string]$Status)
    $evidence.status = $Status
    $evidence.materialisations = @($resolutions)
    $evidence.checks = @($checks)
    $evidence.findings = @($findings)
    New-Item -ItemType Directory -Path (Split-Path $EvidencePath -Parent) -Force | Out-Null
    $evidence | ConvertTo-Json -Depth 30 |
        Set-Content -LiteralPath $EvidencePath -Encoding utf8 -NoNewline
    $null = & (Join-Path $PSScriptRoot "../Validate-JsonArtifact.ps1") `
        -ArtifactPath $EvidencePath `
        -SchemaPath (Join-Path $schemaRoot "runtime/resolver-evidence.schema.json") `
        -SchemaRoot $schemaRoot
}

# A refusal is a result, not a crash: the stage keeps its evidence, the run stops
# cleanly, and no final change set is published.
function New-Refusal {
    param([string]$Reason, [ValidateSet('artifact_invalid', 'external_prerequisite', 'policy_blocker')][string]$Kind = 'policy_blocker')
    $findings.Add($Reason)
    Write-Evidence -Status "blocked"
    return [pscustomobject][ordered]@{
        runId = $RunId
        stageId = $StageId
        handler = "materialize_change_set"
        status = if ($Kind -eq 'artifact_invalid') { 'revision_required' } else { 'blocked' }
        failureKind = $Kind
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
        return ([Convert]::ToHexString($algorithm.ComputeHash($bytes))).ToLowerInvariant()
    }
    finally { $algorithm.Dispose() }
}

function Get-NormalisedPath {
    param([string]$Path)
    return ([string]$Path).Replace("\", "/")
}

# Resolving one project's dependencies is minutes of a package manager, and a
# plan can name several. A leg that ran out of budget on the third of five used
# to throw the first two away, and the next leg started at the first again; on a
# long enough plan the relay can never reach the end. A resolved lock is
# therefore written down under a name derived from everything that determines
# it, and a later leg that asks the identical question gets the recorded answer
# instead of paying for the resolution twice.
function Get-MaterialisationKey {
    param(
        [Parameter(Mandatory)][string]$Recipe,
        [Parameter(Mandatory)][object]$Toolchain,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$LockPath,
        [Parameter(Mandatory)][string]$ManifestContent
    )
    $canonical = [ordered]@{
        recipe = $Recipe
        ecosystem = [string]$Toolchain.ecosystem
        toolchainId = [string]$Toolchain.id
        toolchainSha256 = [string]$Toolchain.sha256
        registry = [string]$Toolchain.source.registry
        manifestPath = $ManifestPath
        lockPath = $LockPath
        manifest = $ManifestContent
    } | ConvertTo-Json -Depth 30 -Compress
    return Get-ContentSha256 -Value $canonical
}

function Get-CheckpointedLock {
    param([Parameter(Mandatory)][string]$Key)
    if ([string]::IsNullOrWhiteSpace($CheckpointRoot)) { return $null }
    $path = Join-Path $CheckpointRoot "$Key.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try {
        $recorded = Get-Content -LiteralPath $path -Raw -Force | ConvertFrom-Json -Depth 20
    }
    catch {
        # Half a document is not a lock file. It is removed rather than left to
        # be re-read as evidence on every later leg.
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return $null
    }
    $fields = @(Get-QaFoundryPropertyNames -InputObject $recorded)
    if (($fields -notcontains "key") -or ([string]$recorded.key -cne $Key) -or
        ($fields -notcontains "lockJson") -or
        [string]::IsNullOrWhiteSpace([string]$recorded.lockJson)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return $null
    }
    return $recorded
}

function Save-CheckpointedLock {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$LockJson,
        [Parameter(Mandatory)][string]$Detail
    )
    if ([string]::IsNullOrWhiteSpace($CheckpointRoot)) { return }
    New-Item -ItemType Directory -Path $CheckpointRoot -Force | Out-Null
    $path = Join-Path $CheckpointRoot "$Key.json"
    $temporaryPath = "$path.tmp"
    [ordered]@{
        key = $Key
        runId = $RunId
        stageId = $StageId
        recordedAt = [DateTime]::UtcNow.ToString("o")
        detail = $Detail
        lockJson = $LockJson
    } | ConvertTo-Json -Depth 20 |
        Set-Content -LiteralPath $temporaryPath -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
}

function Test-UnsafePath {
    param([string]$Path)
    $normalised = Get-NormalisedPath -Path $Path
    if ([string]::IsNullOrWhiteSpace($normalised)) { return $true }
    if ($normalised.StartsWith("/")) { return $true }
    if ($normalised -match "^[a-zA-Z]:") { return $true }
    return (@($normalised -split "/") -contains "..")
}

function ConvertTo-FinalChange {
    param([object]$Change)
    return [ordered]@{
        operation = [string]$Change.operation
        path = Get-NormalisedPath -Path ([string]$Change.path)
        expectedSha256 = [string]$Change.expectedSha256
        content = [string]$Change.content
        reason = [string]$Change.reason
        sourceRefs = @($Change.sourceRefs | ForEach-Object { [string]$_ })
    }
}

$null = & (Join-Path $PSScriptRoot "../Validate-JsonArtifact.ps1") `
    -ArtifactPath $PlanPath `
    -SchemaPath (Join-Path $schemaRoot "actions/change-set-plan.schema.json") `
    -SchemaRoot $schemaRoot
$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json -Depth 100
Add-Check -Name "plan.schema" -Outcome "passed" -Detail "The plan matches the planned change set contract."

# Every artifact this stage trusts has to say it belongs to this run. A plan or a
# blueprint carried over from another run describes work nobody approved here.
if ([string]$plan.runId -ne $RunId) {
    return New-Refusal -Reason ("The plan belongs to run '$([string]$plan.runId)', not to this run " +
        "'$RunId'.")
}

if ([string]$plan.status -ne "completed") {
    return New-Refusal -Reason "The plan did not complete, so there is nothing to materialise."
}

# The approved toolchain is read from the run's own immutable configuration, not
# from the plan and not from the live config file, so nothing a model wrote can
# change which versions get resolved.
$null = & (Join-Path $PSScriptRoot "../Validate-JsonArtifact.ps1") `
    -ArtifactPath $RunConfigurationPath `
    -SchemaPath (Join-Path $schemaRoot "runtime/run-configuration.schema.json") `
    -SchemaRoot $schemaRoot
$runConfig = Get-Content -LiteralPath $RunConfigurationPath -Raw | ConvertFrom-Json -Depth 100
if ([string]$runConfig.runId -ne $RunId) {
    return New-Refusal -Reason ("The run configuration belongs to run '$([string]$runConfig.runId)', " +
        "not to this run '$RunId'.")
}
Add-Check -Name "runConfiguration.identity" -Outcome "passed" `
    -Detail "The approved toolchain belongs to this run."

# The refusals this programme makes travel with the run configuration, so the
# lock is checked against the same policy the architect was told about rather
# than against a second copy read from somewhere else.
$packagePolicy = $null
if ((Get-QaFoundryPropertyNames -InputObject $runConfig) -contains "automation" -and
    $null -ne $runConfig.automation -and
    (Get-QaFoundryPropertyNames -InputObject $runConfig.automation) -contains "packagePolicy") {
    $packagePolicy = $runConfig.automation.packagePolicy
}

# The catalogue says which profiles a person permitted; the approved blueprint
# says which one this project was actually designed on. Checking only the
# catalogue would let a later agent swap the chosen profile for any other
# permitted one, so both are checked and the blueprint is hashed into evidence.
# The hash covers the raw bytes: it identifies the artifact a person approved,
# not a canonical reading of it.
$null = & (Join-Path $PSScriptRoot "../Validate-JsonArtifact.ps1") `
    -ArtifactPath $BlueprintPath `
    -SchemaPath (Join-Path $schemaRoot "architecture/automation-blueprint.schema.json") `
    -SchemaRoot $schemaRoot
$evidence.blueprintSha256 = (Get-FileHash -LiteralPath $BlueprintPath -Algorithm SHA256).Hash.ToLowerInvariant()
$blueprint = Get-Content -LiteralPath $BlueprintPath -Raw | ConvertFrom-Json -Depth 100
if ([string]$blueprint.runId -ne $RunId) {
    return New-Refusal -Reason ("The approved blueprint belongs to run '$([string]$blueprint.runId)', " +
        "not to this run '$RunId'.")
}
# A blueprint that stopped short can still carry a well formed set of projects,
# and building on a design its own author abandoned is not building on an
# approved design.
if ([string]$blueprint.status -ne "completed") {
    return New-Refusal -Reason ("The approved blueprint did not complete: its status is " +
        "'$([string]$blueprint.status)', so nothing in it was settled.")
}
$blueprintProjects = @($blueprint.details.automationProjects)
if ($blueprintProjects.Count -eq 0) {
    return New-Refusal -Reason "The approved blueprint names no automation project to materialise for."
}
# Paths are compared with -ceq below, because a repository that treats
# "Automation" and "automation" as one directory on Windows and as two on Linux
# cannot be built the same way twice.
$projectPathIndex = @{}
foreach ($project in $blueprintProjects) {
    $projectPath = (Get-NormalisedPath -Path ([string]$project.path)).Trim("/")
    foreach ($seen in $projectPathIndex.Keys) {
        if ($seen -ieq $projectPath) {
            return New-Refusal -Reason ("The approved blueprint declares '$seen' and '$projectPath' " +
                "as separate projects, which are the same directory on a case-insensitive file system.")
        }
    }
    $projectPathIndex[$projectPath] = $null
}
if (-not (Test-Path -LiteralPath $ToolchainLockPath)) {
    return New-Refusal -Reason ("No locked toolchain exists at $ToolchainLockPath, so nothing here " +
        "knows what was actually pinned. The design alone is a proposal.")
}
$toolchainLock = Get-Content -LiteralPath $ToolchainLockPath -Raw | ConvertFrom-Json -Depth 30
if ([string]$toolchainLock.blueprintSha256 -ne [string]$evidence.blueprintSha256) {
    return New-Refusal -Reason ("The locked toolchain was resolved from a different blueprint than " +
        "the one approved for this stage, so it pins the wrong decision.")
}
$lockedToolchains = @($toolchainLock.toolchains)
# The lock says which projects each decision was made for. Turning that around
# gives, for every project, the one toolchain it may be built with - and refuses
# a project the resolver never saw.
foreach ($locked in $lockedToolchains) {
    foreach ($decidedFor in @($locked.decidedFor)) {
        $decidedPath = (Get-NormalisedPath -Path ([string]$decidedFor)).Trim("/")
        $owner = @($projectPathIndex.Keys | Where-Object { $_ -ceq $decidedPath })
        if ($owner.Count -ne 1) {
            return New-Refusal -Reason ("The locked toolchain '$([string]$locked.id)' was resolved " +
                "for '$decidedPath', which the approved blueprint does not name as an automation " +
                "project.")
        }
        if ($null -ne $projectPathIndex[$owner[0]]) {
            return New-Refusal -Reason ("Two locked toolchains claim '$decidedPath'. A project is " +
                "built one way or it is not reproducible.")
        }
        $projectPathIndex[$owner[0]] = [string]$locked.id
    }
}
$unresolvedProjects = @($projectPathIndex.Keys | Where-Object { $null -eq $projectPathIndex[$_] })
if ($unresolvedProjects.Count -gt 0) {
    return New-Refusal -Reason ("The resolver pinned no toolchain for $($unresolvedProjects -join ', '), " +
        "so there is nothing to build those projects with.")
}
Add-Check -Name "toolchain.lock" -Outcome "passed" `
    -Detail ("The locked toolchain pins $($lockedToolchains.Count) resolved toolchain(s) covering " +
        "every automation project.")
Add-Check -Name "blueprint.read" -Outcome "passed" `
    -Detail "The approved blueprint names $($blueprintProjects.Count) automation project(s)."

$planChanges = @($plan.changes)
# Set-StrictMode makes an absent property fatal, and the schema only demands
# this one from a plan that proposes something. A plan that proposes nothing
# resolves nothing, which is the same thing as an empty list.
$materializations = @(if ($plan.PSObject.Properties.Name -contains "materializations") {
    @($plan.materializations)
} else { @() })
if ($RunRoot -and $materializations.Count -eq 0) {
    . (Join-Path $PSScriptRoot '../MaterializationRepair.ps1')
    try {
        $carried = Get-QaFoundryCarriedMaterializations -Plan $plan -RunRoot $RunRoot -RunId $RunId
        $materializations = @($carried.materializations)
        if ($carried.sources.Count -gt 0) {
            Add-Check -Name 'plan.carriedMaterializations' -Outcome 'passed' -Detail (
                "Recovered $($carried.sources.Count) resolver recipe(s) from hash-verified plans with unchanged manifests: " +
                (ConvertTo-Json -InputObject @($carried.sources) -Depth 10 -Compress))
        }
    }
    catch { return New-Refusal -Kind 'artifact_invalid' -Reason $_.Exception.Message }
}
foreach ($change in $planChanges) {
    $path = Get-NormalisedPath -Path ([string]$change.path)
    if (Test-UnsafePath -Path $path) {
        return New-Refusal -Reason "The plan names a path that leaves the repository: $path"
    }
    # A lock file comes from a resolver, whatever the ecosystem calls it. Asking
    # every adapter rather than naming npm's file keeps a Gemfile.lock or a
    # packages.lock.json from being authored as literal content.
    foreach ($ecosystemId in @(Get-QaFoundryEcosystemAdapterNames)) {
        $lockPattern = [string](Get-QaFoundryEcosystemAdapter -Ecosystem $ecosystemId).lockFilePattern
        if ([string]::IsNullOrWhiteSpace($lockPattern)) { continue }
        if ($path -imatch $lockPattern) {
            return New-Refusal -Reason ("The plan authors a lock file as literal content: $path. " +
                "A lock file comes from a resolver.")
        }
    }
}
Add-Check -Name "plan.paths" -Outcome "passed" `
    -Detail "No planned path leaves the repository or authors a lock file."

$finalChanges = @($planChanges | ForEach-Object { ConvertTo-FinalChange -Change $_ })

# What the plan asks to resolve is the agent's own answer, so it cannot also be
# the definition of what needed resolving. A plan that authored a pom.xml and
# then simply returned no materialisations used to pass: the change set carried
# a manifest and no lock, and the verification stage went on to build it, at
# which point Maven resolved whatever the network offered that day. Nothing was
# pinned and nothing said so.
#
# So coverage is derived here instead, from the approved blueprint and from the
# manifests the plan itself authors, and the plan is measured against it. This
# runs whether or not the plan proposes any materialisation, which is the whole
# point: the empty case is the one that used to slip through.
$claimedProjectPaths = @{}
$claimedManifestPaths = @{}
$manifestGovernors = [System.Collections.Generic.List[object]]::new()
# Coverage is a question about a plan that is otherwise well formed. A plan that
# resolves for a project nobody approved, or from a manifest that does not sit
# above the projects it claims, is wrong in a way the materialisation loop below
# names precisely. Answering such a plan here with "something was left uncovered"
# would be true and useless, so the derived checks stand aside for it and let the
# specific refusal be the one the run reports.
$materializationsWellFormed = $true
foreach ($materialization in $materializations) {
    $claimedManifest = (Get-NormalisedPath -Path ([string]$materialization.manifestPath))
    if (-not $claimedManifestPaths.ContainsKey($claimedManifest)) {
        $claimedManifestPaths[$claimedManifest] = 0
    }
    $claimedManifestPaths[$claimedManifest]++
    $governorDirectory = (Get-NormalisedPath -Path (Split-Path $claimedManifest -Parent)).Trim("/")
    $manifestGovernors.Add([pscustomobject]@{
        manifestPath = $claimedManifest
        # A manifest governs its own directory and everything below it. One at
        # the repository root has no parent, and governs the whole tree.
        directory = $governorDirectory
        toolchainId = [string]$materialization.toolchainId
    })
    foreach ($claimed in @($materialization.projectPaths)) {
        $claimedProject = (Get-NormalisedPath -Path ([string]$claimed)).Trim("/")
        if (-not $claimedProjectPaths.ContainsKey($claimedProject)) {
            $claimedProjectPaths[$claimedProject] = 0
        }
        $claimedProjectPaths[$claimedProject]++
        if (@($projectPathIndex.Keys | Where-Object { $_ -ceq $claimedProject }).Count -ne 1) {
            $materializationsWellFormed = $false
        }
        elseif (-not ([string]::IsNullOrEmpty($governorDirectory) -or
                $governorDirectory -ceq $claimedProject -or
                $claimedProject.StartsWith("$governorDirectory/", [StringComparison]::Ordinal))) {
            $materializationsWellFormed = $false
        }
    }
}

# One manifest serves the projects nested under it, so a project need not be
# named to be covered - but it does have to be reachable from some manifest the
# plan resolves.
function Get-NearestGoverningManifest {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$ProjectPath)
    return @($manifestGovernors | Where-Object {
        [string]::IsNullOrEmpty($_.directory) -or
            $_.directory -ceq $ProjectPath -or
            $ProjectPath.StartsWith("$($_.directory)/", [StringComparison]::Ordinal)
    } | Sort-Object { ([string]$_.directory).Length } -Descending)
}

if ($materializationsWellFormed) {
    $uncoveredProjects = @($projectPathIndex.Keys |
        Where-Object { @(Get-NearestGoverningManifest -ProjectPath $_).Count -eq 0 } | Sort-Object)
    if ($uncoveredProjects.Count -gt 0) {
        return New-Refusal -Reason ("The plan resolves no dependencies for " +
            "$($uncoveredProjects -join ', '). Every automation project the blueprint approved was " +
            "designed on a toolchain the resolver pinned, and a project delivered without its lock " +
            "file is a project whose packages are chosen at build time by whatever the feed offers.")
    }
    $doublyClaimedProjects = @($claimedProjectPaths.Keys |
        Where-Object { $claimedProjectPaths[$_] -gt 1 } | Sort-Object)
    if ($doublyClaimedProjects.Count -gt 0) {
        return New-Refusal -Reason ("Two materialisations both resolve dependencies for " +
            "$($doublyClaimedProjects -join ', '). A project has one manifest, or the tree it is " +
            "built from depends on which resolver ran last.")
    }
    # A project the plan does not name is still built with the manifest above it, so
    # that manifest has to be the one its own toolchain was pinned for. The
    # materialisation loop below makes the same check for the projects a plan does
    # name, and says which of them disagreed.
    foreach ($project in @($projectPathIndex.Keys |
            Where-Object { -not $claimedProjectPaths.ContainsKey($_) } | Sort-Object)) {
        $nearest = @(Get-NearestGoverningManifest -ProjectPath $project)[0]
        if ([string]$nearest.toolchainId -cne [string]$projectPathIndex[$project]) {
            return New-Refusal -Reason ("Project '$project' is built from '$($nearest.manifestPath)', " +
                "which the plan resolves with toolchain '$([string]$nearest.toolchainId)', but the " +
                "approved blueprint designed it on '$([string]$projectPathIndex[$project])'.")
        }
    }

    # The other direction: a manifest the plan authors and no materialisation
    # claims. Which files are manifests is the adapters' answer, not a list written
    # here, so a repository that gains an ecosystem gains the check with it.
    $authoredManifests = @($planChanges | Where-Object {
        [string]$_.operation -ine "delete"
    } | ForEach-Object { Get-NormalisedPath -Path ([string]$_.path) } | Where-Object {
        $candidate = $_
        @(Get-QaFoundryEcosystemAdapterNames | Where-Object {
            $pattern = [string](Get-QaFoundryEcosystemAdapter -Ecosystem $_).manifestPattern
            (-not [string]::IsNullOrWhiteSpace($pattern)) -and $candidate -imatch $pattern
        }).Count -gt 0
    })
    $unclaimedManifests = @($authoredManifests |
        Where-Object { -not $claimedManifestPaths.ContainsKey($_) } | Sort-Object -Unique)
    if ($unclaimedManifests.Count -gt 0) {
        return New-Refusal -Reason ("The plan authors $($unclaimedManifests -join ', ') and asks for no " +
            "resolution of it. A manifest delivered without its lock file installs whatever the feed " +
            "offers on the day it is built.")
    }
    Add-Check -Name "plan.materializationCoverage" -Outcome "passed" `
        -Detail ("Every approved automation project and every authored manifest is covered by exactly " +
            "one materialisation.")
}

if ($materializations.Count -eq 0) {
    Add-Check -Name "resolver.run" -Outcome "skipped" -Detail "The plan asks for no dependency resolution."
}
else {
    $attemptIndex = 0
    $seenLockPaths = @{}
    $seenManifestPaths = @{}
    foreach ($materialization in $materializations) {
        $recipe = [string]$materialization.recipe
        $toolchainId = [string]$materialization.toolchainId
        $manifestPath = Get-NormalisedPath -Path ([string]$materialization.manifestPath)
        $lockPath = Get-NormalisedPath -Path ([string]$materialization.lockPath)
        # Recorded before anything can refuse, so a refusal still says which
        # materialisation it was refusing.
        $record = [ordered]@{
            recipe = $recipe
            toolchainId = $toolchainId
            toolchainSha256 = ""
            ecosystem = ""
            registry = ""
            manifestPath = $manifestPath
            lockPath = $lockPath
            projectPaths = @($materialization.projectPaths | ForEach-Object { [string]$_ })
            resolverExitCode = $null
            durationSeconds = $null
        }
        Add-Resolution -Record $record

        if ((Test-UnsafePath -Path $manifestPath) -or (Test-UnsafePath -Path $lockPath)) {
            return New-Refusal -Reason "A materialisation names a path that leaves the repository."
        }
        if ($seenLockPaths.ContainsKey($lockPath.ToLowerInvariant()) -or
            $seenManifestPaths.ContainsKey($manifestPath.ToLowerInvariant())) {
            return New-Refusal -Reason ("Two materialisations claim the same manifest or lock path: " +
                $lockPath)
        }
        $seenLockPaths[$lockPath.ToLowerInvariant()] = $true
        $seenManifestPaths[$manifestPath.ToLowerInvariant()] = $true
        if ((Split-Path $manifestPath -Parent) -cne (Split-Path $lockPath -Parent)) {
            return New-Refusal -Reason ("A lock file belongs beside the manifest it locks: " +
                "$manifestPath and $lockPath")
        }
        if (@($planChanges | Where-Object {
                (Get-NormalisedPath -Path ([string]$_.path)) -ieq $lockPath
            }).Count -gt 0) {
            return New-Refusal -Reason "The plan both authors and materialises the same lock file: $lockPath"
        }

        $matched = @($lockedToolchains | Where-Object { [string]$_.id -ceq $toolchainId })
        if ($matched.Count -ne 1) {
            return New-Refusal -Reason ("The plan names a toolchain the resolver never pinned: $toolchainId")
        }

        # One manifest can serve several nested projects, so the plan states
        # which approved projects it speaks for rather than the runtime guessing
        # from the directory. Every one of them has to exist in the blueprint and
        # they all have to agree on the same toolchain.
        $claimedPaths = @($materialization.projectPaths |
            ForEach-Object { (Get-NormalisedPath -Path ([string]$_)).Trim("/") })
        $chosenToolchains = [System.Collections.Generic.List[string]]::new()
        foreach ($claimed in $claimedPaths) {
            $owner = @($projectPathIndex.Keys | Where-Object { $_ -ceq $claimed })
            if ($owner.Count -ne 1) {
                return New-Refusal -Reason ("The plan materialises for '$claimed', which the approved " +
                    "blueprint does not name as an automation project, so nobody chose a toolchain " +
                    "for it.")
            }
            $chosenToolchains.Add([string]$projectPathIndex[$owner[0]])
        }
        $distinctToolchains = @($chosenToolchains | Sort-Object -Unique)
        if ($distinctToolchains.Count -ne 1) {
            return New-Refusal -Reason ("One lock file cannot serve projects designed on different " +
                "toolchains: $($distinctToolchains -join ', ').")
        }
        $chosenToolchain = $distinctToolchains[0]
        if ($chosenToolchain -cne $toolchainId) {
            return New-Refusal -Reason ("The plan materialises '$manifestPath' with toolchain " +
                "'$toolchainId', but the approved blueprint designed those projects on " +
                "'$chosenToolchain'.")
        }
        # The manifest still has to govern every project it claims to serve, or a
        # plan could resolve one project's dependencies into another's tree. A
        # shared manifest sits at or above them all; it never sits beside them.
        $manifestDirectory = (Get-NormalisedPath -Path (Split-Path $manifestPath -Parent)).Trim("/")
        # A manifest at the repository root has no parent directory, and the
        # prefix test would then compare every project path against "/" and
        # find none of them governed. The root governs everything below it.
        $notGoverned = @(if ([string]::IsNullOrEmpty($manifestDirectory)) {
            @()
        }
        else {
            @($claimedPaths | Where-Object {
                -not ($_ -ceq $manifestDirectory -or
                    $_.StartsWith("$manifestDirectory/", [StringComparison]::Ordinal))
            })
        })
        if ($notGoverned.Count -gt 0) {
            return New-Refusal -Reason ("The manifest '$manifestPath' does not govern every project it " +
                "claims to serve: $($notGoverned -join ', ').")
        }
        Add-Check -Name "blueprint.toolchainChoice" -Outcome "passed" `
            -Detail ("The approved blueprint designed $($claimedPaths.Count) project(s) served by " +
                "'$manifestPath' on toolchain '$chosenToolchain'.")

        $toolchain = $matched[0]
        $record.toolchainSha256 = [string]$toolchain.sha256
        $record.ecosystem = [string]$toolchain.ecosystem
        $record.registry = [string]$toolchain.source.registry
        if ([string]$toolchain.recipe -cne $recipe) {
            return New-Refusal -Reason ("The locked toolchain '$toolchainId' does not resolve with " +
                "recipe '$recipe'.")
        }
        # The adapter, not a table in this file, says which scripts can produce
        # and check a lock for this ecosystem. A runtime that kept its own list
        # would go stale the moment an ecosystem was added.
        try { $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem ([string]$toolchain.ecosystem) }
        catch {
            return New-Refusal -Reason ("No resolver in this runtime can produce a lock file for " +
                "$([string]$toolchain.ecosystem), and inventing one is not an option.")
        }
        Add-Check -Name "toolchain.match" -Outcome "passed" `
            -Detail "Toolchain '$toolchainId' was pinned by the resolver for this run."

        $manifestChange = @($planChanges | Where-Object {
            (Get-NormalisedPath -Path ([string]$_.path)) -ceq $manifestPath
        })
        if ($manifestChange.Count -ne 1) {
            return New-Refusal -Kind artifact_invalid -Reason ("The plan materialises a manifest it does not author exactly " +
                "once: $manifestPath")
        }
        $manifestContent = [string]$manifestChange[0].content
        # How a manifest spells its dependencies is the ecosystem's business, not
        # this file's. A .csproj is XML and a Gemfile is Ruby; only the adapter
        # knows how to read either one.
        try { $identity = & $adapter.ReadManifestIdentity $manifestContent }
        catch {
            return New-Refusal -Kind artifact_invalid -Reason ("The planned manifest is not valid for " +
                "$($adapter.displayName): $manifestPath")
        }

        # Anything that changes what a resolver installs, and that this runtime
        # cannot check against the locked toolchain, is refused rather than
        # passed through and hoped about. The same check runs when the generator
        # first answers, where a rejection still buys a retry; this one is the
        # guard for a plan that reached the stage without passing through it.
        # A private package is asked for neither a name nor a version, so a
        # manifest that carries neither is valid and must still materialise. An
        # absent field travels as an empty string, which the resolver leaves out
        # of the manifest it builds and the verifier reads as "nothing to compare".
        $manifestName = [string]$identity.name
        $manifestVersion = [string]$identity.version
        $manifestFindings = @(& (Join-Path (Split-Path $PSScriptRoot -Parent) "Test-PlannedManifest.ps1") `
            -Changes @($planChanges) -Materializations @($materialization))
        if ($manifestFindings.Count -gt 0) {
            return New-Refusal -Kind artifact_invalid -Reason ($manifestFindings -join " ")
        }
        Add-Check -Name "manifest.features" -Outcome "passed" `
            -Detail "The manifest declares no unverifiable resolution feature."

        try { $declared = @(& $adapter.ReadManifestDependencies $manifestContent) }
        catch {
            return New-Refusal -Reason ("The planned manifest does not declare its dependencies in a " +
                "form this runtime can read: $manifestPath")
        }
        foreach ($dependency in $declared) {
            if (-not (Test-QaFoundryExactVersion -Ecosystem $adapter.id -Version ([string]$dependency.version))) {
                return New-Refusal -Kind artifact_invalid -Reason ("The planned manifest asks for a specifier this runtime " +
                    "cannot pin: $($dependency.name)@$($dependency.version)")
            }
        }
        # Package identity is case-sensitive on npm, PyPI and RubyGems, and a
        # feed will happily serve a differently-cased name as a different
        # package. Comparing these keys with PowerShell's default -ne would
        # accept "Newtonsoft.JSON" for a locked "Newtonsoft.Json"; the sort has
        # to agree too, or two lists holding the same names in different cases
        # can order them differently and read as a mismatch that is not one.
        #
        # Scope joins the comparison only where the manifest format states it.
        # A .csproj has no development section, a go.mod no reason column, a
        # requirements file no groups; for those the scope in the key would be
        # this run's own decision on one side and a default on the other, and
        # the run would block on a project that is entirely correct. That is
        # what stopped the first live bootstrap: a test project's MSTest was
        # decided as 'dev' and read back from the .csproj as 'runtime', which
        # names the same package at the same version either way.
        $comparesScope = $false
        if (@(Get-QaFoundryPropertyNames -InputObject $adapter) -contains "manifestExpressesDependencyScope") {
            $comparesScope = [bool]$adapter.manifestExpressesDependencyScope
        }
        $toKey = {
            param($Package)
            $canonical = Get-QaFoundryNormalisedPackageName -Ecosystem $adapter.id `
                -Name ([string]$Package.name)
            $key = "$canonical|$([string]$Package.version)"
            if ($comparesScope) { $key += "|$([string]$Package.scope)" }
            return $key
        }
        $directDeclarations = @($declared | Where-Object {
            -not ($_.PSObject.Properties['isIndirect'] -and $_.isIndirect)
        })
        $declaredKeys = @($directDeclarations | ForEach-Object { & $toKey $_ } | Sort-Object -CaseSensitive)
        $approvedKeys = @($toolchain.packages | ForEach-Object { & $toKey $_ } | Sort-Object -CaseSensitive)
        if (($declaredKeys -join ",") -cne ($approvedKeys -join ",")) {
            return New-Refusal -Kind artifact_invalid -Reason ("The planned manifest does not match the locked toolchain. " +
                "Planned: $($declaredKeys -join '; '). Locked: $($approvedKeys -join '; ').")
        }
        Add-Check -Name "manifest.toolchainMatch" -Outcome "passed" `
            -Detail "The manifest declares exactly the locked dependencies."

        # A rehearsal stops here. Everything above reads files this run already
        # wrote; resolving reaches a package registry and demands the exact
        # toolchain the decision was settled on be installed on this agent, and
        # a rehearsal is expected to run anywhere. It says plainly that it
        # resolved nothing rather than emitting a lock nobody produced.
        if ($DryRun) {
            Add-Check -Name "resolver.run" -Outcome "skipped" -Detail (
                "This is a rehearsal: no dependency was resolved and no lock file was written, so " +
                "nothing here says whether the chosen packages exist or install.")
            continue
        }

        if ($null -ne $Deadline -and (Test-QaFoundryBudgetExhausted -Deadline $Deadline)) {
            # Running out of leg budget is a handover, not a verdict on the
            # toolchain: the relay resumes and tries again.
            Add-Check -Name "resolver.run" -Outcome "skipped" `
                -Detail "The leg budget was spent before the resolver could run."
            Write-Evidence -Status "blocked"
            Stop-QaFoundryForBudget -Reason (
                "stage '$StageId' stopped before resolving dependencies because the time budget for this leg is spent")
        }

        $attemptRoot = Join-Path $WorkRoot ("materialisation-" + $attemptIndex)
        $attemptIndex++
        $materialisationKey = Get-MaterialisationKey -Recipe $recipe -Toolchain $toolchain `
            -ManifestPath $manifestPath -LockPath $lockPath `
            -ManifestContent ([string]$manifestChange[0].content)
        $checkpointed = Get-CheckpointedLock -Key $materialisationKey
        $resolution = if ($null -ne $checkpointed) {
            Write-QaFoundryLog -Indent 2 -Message (
                "An earlier leg of this run already resolved '$lockPath' from the same manifest and " +
                "the same locked toolchain, so its lock file is reused instead of resolving again.")
            [pscustomobject]@{
                succeeded = $true
                deadlineReached = $false
                exitCode = 0
                durationSeconds = 0.0
                lockJson = [string]$checkpointed.lockJson
                detail = ("Reused the lock an earlier leg resolved: " +
                    [string]$checkpointed.detail)
            }
        }
        else {
            & (Join-Path $PSScriptRoot $adapter.resolveScript) `
                -Toolchain $toolchain `
                -WorkRoot $attemptRoot `
                -ManifestName $manifestName `
                -ManifestVersion $manifestVersion `
                -ToolCommandOverrides $ToolCommandOverrides `
                -Deadline $Deadline
        }
        $record.resolverExitCode = [int]$resolution.exitCode
        $record.durationSeconds = [double]$resolution.durationSeconds
        if ($resolution.deadlineReached) {
            # The resolver ran out of leg time, not out of options. That is a
            # handover to the next leg, not a verdict that the toolchain is
            # broken.
            Add-Check -Name "resolver.run" -Outcome "skipped" -Detail ([string]$resolution.detail)
            Write-Evidence -Status "blocked"
            Stop-QaFoundryForBudget -Reason (
                "stage '$StageId' stopped while resolving dependencies because the time budget for this leg is spent")
        }
        if (-not $resolution.succeeded) {
            Add-Check -Name "resolver.run" -Outcome "failed" -Detail ([string]$resolution.detail)
            $failureKind = if ($resolution.PSObject.Properties['infrastructureUnavailable'] -and $resolution.infrastructureUnavailable) {
                'external_prerequisite'
            } else { 'artifact_invalid' }
            return New-Refusal -Kind $failureKind -Reason "The resolver produced no lock file: $([string]$resolution.detail)"
        }
        Add-Check -Name "resolver.run" -Outcome "passed" -Detail ([string]$resolution.detail)

        $verdict = & (Join-Path $PSScriptRoot $adapter.verifyScript) `
                    -LockJson ([string]$resolution.lockJson) -Toolchain $toolchain `
                    -ManifestName $manifestName -ManifestVersion $manifestVersion `
                    -PackagePolicy $packagePolicy
        if (-not $verdict.accepted) {
            Add-Check -Name "lock.verification" -Outcome "failed" -Detail (@($verdict.findings) -join " ")
            return New-Refusal -Reason ("The resolved lock file does not match the locked toolchain: " +
                (@($verdict.findings) -join " "))
        }
        Add-Check -Name "lock.verification" -Outcome "passed" `
            -Detail "Every resolved package matches the locked toolchain and came from an approved feed."

        if ($adapter.PSObject.Properties['CompleteManifestFromLock']) {
            try {
                $completedManifest = & $adapter.CompleteManifestFromLock $manifestContent ([string]$resolution.lockJson)
            }
            catch { return New-Refusal -Kind artifact_invalid -Reason $_.Exception.Message }
            $finalManifest = @($finalChanges | Where-Object {
                (Get-NormalisedPath -Path ([string]$_.path)) -ceq $manifestPath
            })
            $finalManifest[0].content = [string]$completedManifest
            Add-Check -Name 'manifest.resolvedGraph' -Outcome 'passed' `
                -Detail 'The delivered manifest includes the resolved indirect dependencies; no build-time resolution is required.'
        }

        # Written only once the lock has been verified against the locked
        # toolchain: an unverified lock is not an answer worth remembering.
        if ($null -eq $checkpointed) {
            Save-CheckpointedLock -Key $materialisationKey `
                -LockJson ([string]$resolution.lockJson) `
                -Detail ([string]$resolution.detail)
        }

        $finalChanges += [ordered]@{
            operation = [string]$materialization.operation
            path = $lockPath
            expectedSha256 = [string]$materialization.expectedSha256
            content = [string]$resolution.lockJson
            reason = [string]$materialization.reason
            sourceRefs = @($materialization.sourceRefs | ForEach-Object { [string]$_ })
        }
    }
}

# The decision has to survive the run that made it. Once this change set is
# merged the repository itself says which technology was chosen and why it is
# not open again, so an ordinary product change cannot quietly trigger a second
# architecture. It rides in the change set rather than being written to disk
# here, because a file written outside the change set would never reach the
# pull request a human reviews.
if (-not [string]::IsNullOrWhiteSpace($ToolchainRecordPath)) {
    $recordPath = Get-NormalisedPath -Path $ToolchainRecordPath
    if (Test-UnsafePath -Path $recordPath) {
        return New-Refusal -Reason "The toolchain record path leaves the repository: $recordPath"
    }
    if (@($finalChanges | Where-Object { (Get-NormalisedPath -Path ([string]$_.path)) -ieq $recordPath }).Count -gt 0) {
        return New-Refusal -Reason ("The plan authors the toolchain record itself: $recordPath. " +
            "That record is derived from the resolver's lock, not written by an agent.")
    }
    $record = ConvertTo-QaFoundryToolchainRecord -Lock $toolchainLock
    # A first decision creates the record and a revision updates it. Claiming
    # the wrong one is not a formality: the writer checks the file it is about
    # to overwrite against expectedSha256, and that check only exists for an
    # update.
    $recordOperation = "create"
    $recordExpectedSha = ""
    if (-not [string]::IsNullOrWhiteSpace($RepositoryRoot)) {
        $recordFullPath = Join-Path $RepositoryRoot ($recordPath -replace "/", [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $recordFullPath -PathType Leaf) {
            $recordOperation = "update"
            $recordExpectedSha = (Get-FileHash -LiteralPath $recordFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            # The architecture stage is told the decision is already made, but a
            # blueprint can reach this stage from a run that never read the
            # record - a resumed leg, a re-driven artifact, a repository whose
            # record arrived while the run was in flight. Overwriting it here
            # would be the migration nobody asked for, performed by the one step
            # whose output goes straight into the pull request.
            try {
                $existingRecord = Get-Content -LiteralPath $recordFullPath -Raw | ConvertFrom-Json -Depth 100
            }
            catch {
                return New-Refusal -Reason ("The toolchain record already in the repository at " +
                    "$recordPath could not be read as JSON, so this run cannot tell whether it is " +
                    "about to overwrite a decision: $($_.Exception.Message)")
            }
            $proposedForRecord = foreach ($entry in @($record.toolchains)) {
                $entryFields = @(Get-QaFoundryPropertyNames -InputObject $entry)
                foreach ($projectPath in @($entry.projects)) {
                    $proposal = [ordered]@{
                        path = [string]$projectPath
                        ecosystem = [string]$entry.ecosystem
                    }
                    foreach ($optional in @("language", "testFramework")) {
                        if ($entryFields -contains $optional) { $proposal[$optional] = [string]$entry.$optional }
                    }
                    [pscustomobject]$proposal
                }
            }
            $recordConflicts = @(Get-QaFoundryToolchainRecordConflicts -Recorded $existingRecord `
                -Proposed @($proposedForRecord))
            if ($recordConflicts.Count -gt 0) {
                return New-Refusal -Reason (($recordConflicts -join " ") +
                    " This change set would have rewritten $recordPath on the way past.")
            }
            Add-Check -Name "toolchain.recordContinuity" -Outcome "passed" `
                -Detail ("The resolved toolchain keeps every project on the technology " +
                    "$recordPath already records for it.")
        }
    }
    $finalChanges += [ordered]@{
        operation = $recordOperation
        path = $recordPath
        expectedSha256 = $recordExpectedSha
        content = (($record | ConvertTo-Json -Depth 30) + "`n")
        reason = ("Records the toolchain this run resolved so a later run builds on the same " +
            "decision instead of choosing the technology again.")
        sourceRefs = @($ToolchainLockPath)
    }
    Add-Check -Name "toolchain.record" -Outcome "passed" `
        -Detail "The change set carries the toolchain record at $recordPath."
}

$changeSet = [ordered]@{
    agentId = "change-materializer"
    stageId = $StageId
    runId = $RunId
    status = "completed"
    summary = if ($DryRun) {
        "Rehearsed the approved toolchain against the planned change set without resolving any dependency."
    }
    else {
        "Resolved the approved toolchain and turned a planned change set into a final one."
    }
    evidence = @([ordered]@{
        source = $EvidencePath
        description = "Dependency resolution evidence."
    })
    assumptions = @()
    unknowns = @()
    warnings = @(if ($DryRun) {
        "This change set was rehearsed: no dependency was resolved and it carries no lock file, so it must not be delivered."
    })
    details = [ordered]@{
        planPath = $PlanPath
        # Carried in the change set itself, not only in the run's evidence,
        # because the thing that must never be committed is this document, and
        # a reader that has to find another file to learn that is a reader that
        # will not.
        dryRun = [bool]$DryRun
        materializationCount = $materializations.Count
        # Which locked toolchain each manifest belongs to. Verification used to
        # infer this from the ecosystem alone, which is only right while there
        # is one decision per ecosystem: two npm projects, one on Playwright and
        # one on Vitest, were both tested against whichever decision the lock
        # happened to list first, and the second was never verified at all.
        materializations = @($resolutions | ForEach-Object {
            [ordered]@{
                toolchainId = [string]$_.toolchainId
                ecosystem = [string]$_.ecosystem
                manifestPath = [string]$_.manifestPath
                lockPath = [string]$_.lockPath
                projectPaths = @($_.projectPaths | ForEach-Object { [string]$_ })
            }
        })
    }
    outcome = if (@($finalChanges).Count -gt 0) { "proposed" } else { "no_action_needed" }
    changes = @($finalChanges)
}

# Validate before publishing and publish by rename, so no reader can ever open a
# change set that has not passed its own contract.
New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force | Out-Null
$stagingPath = "$OutputPath.staging"
$changeSet | ConvertTo-Json -Depth 100 |
    Set-Content -LiteralPath $stagingPath -Encoding utf8 -NoNewline
try {
    $null = & (Join-Path $PSScriptRoot "../Validate-JsonArtifact.ps1") `
        -ArtifactPath $stagingPath `
        -SchemaPath (Join-Path $schemaRoot "actions/change-set.schema.json") `
        -SchemaRoot $schemaRoot
}
catch {
    Remove-Item -LiteralPath $stagingPath -Force -ErrorAction SilentlyContinue
    return New-Refusal -Reason "The materialised change set failed its own contract: $($_.Exception.Message)"
}
Move-Item -LiteralPath $stagingPath -Destination $OutputPath -Force
Write-Evidence -Status "completed"

# Reviewers judge the plan a person's agent wrote and the evidence that the lock
# was resolved honestly. The lock itself is carried by reference: it is machine
# output, already checked against the approved profile, and pasting it into three
# review requests would cost a great deal and inform no one. This document ties
# the three together, so an approval names exactly which bytes were approved.
$deliveredLockPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($change in $finalChanges) { $null = $deliveredLockPaths.Add([string]$change.path) }
$reviewSubject = [ordered]@{
    runId = $RunId
    stageId = $StageId
    planPath = $PlanPath
    planSha256 = (Get-FileHash -LiteralPath $PlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
    blueprintSha256 = [string]$evidence.blueprintSha256
    finalChangeSetPath = $OutputPath
    finalChangeSetSha256 = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    resolverEvidencePath = $EvidencePath
    resolverEvidenceSha256 = (Get-FileHash -LiteralPath $EvidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
    authoredChangeCount = @($planChanges).Count
    # Only materialisations that produced a lock appear here. This document
    # exists to bind an approval to exact bytes, and an entry whose lock was
    # never resolved - a rehearsal, or a lock reused from a leg that is not in
    # this change set - has no bytes to bind to.
    materialisations = @($resolutions |
        Where-Object { $deliveredLockPaths.Contains([string]$_.lockPath) } |
        ForEach-Object {
        [ordered]@{
            lockPath = [string]$_.lockPath
            manifestPath = [string]$_.manifestPath
            toolchainId = [string]$_.toolchainId
            ecosystem = [string]$_.ecosystem
            registry = [string]$_.registry
            projectPaths = @($_.projectPaths)
            lockSha256 = ""
            packageCount = 0
        }
    })
}
foreach ($summary in @($reviewSubject.materialisations)) {
    $lockChange = @($finalChanges | Where-Object { [string]$_.path -ceq [string]$summary.lockPath })
    if ($lockChange.Count -ne 1) { continue }
    $lockContent = [string]$lockChange[0].content
    $summary.lockSha256 = (Get-ContentSha256 -Value $lockContent)
    # Counting packages means reading a lock file, and only the ecosystem that
    # wrote it knows its shape. A reviewer who is told "0 packages" because the
    # runtime looked for an npm key in a Gemfile.lock has been misinformed.
    $summaryAdapter = Get-QaFoundryEcosystemAdapter -Ecosystem ([string]$summary.ecosystem)
    $summaryToolchain = @($lockedToolchains |
        Where-Object { [string]$_.id -ceq [string]$summary.toolchainId })[0]
    $summaryReading = & $summaryAdapter.ReadLockEntries $lockContent $summaryToolchain
    $summary.packageCount = @($summaryReading.entries).Count
}
New-Item -ItemType Directory -Path (Split-Path $ReviewSubjectPath -Parent) -Force | Out-Null
$reviewSubject | ConvertTo-Json -Depth 30 |
    Set-Content -LiteralPath $ReviewSubjectPath -Encoding utf8 -NoNewline
$null = & (Join-Path $PSScriptRoot "../Validate-JsonArtifact.ps1") `
    -ArtifactPath $ReviewSubjectPath `
    -SchemaPath (Join-Path $schemaRoot "actions/change-review-subject.schema.json") `
    -SchemaRoot $schemaRoot

return [pscustomobject][ordered]@{
    runId = $RunId
    stageId = $StageId
    handler = "materialize_change_set"
    status = "completed"
    dryRun = [bool]$DryRun
    actions = @([pscustomobject][ordered]@{
        sourceRef = $PlanPath
        type = "dependency.materialize"
        idempotencyKey = ""
        status = if ($DryRun) { "skipped" } else { "executed" }
        externalId = $OutputPath
        summary = if ($DryRun) {
            "Rehearsed $($materializations.Count) materialisation(s) without resolving any dependency."
        }
        else {
            "Materialised $($materializations.Count) lock file(s) into a final change set."
        }
    })
    evidence = @($EvidencePath)
    produced = @($OutputPath, $ReviewSubjectPath)
}
