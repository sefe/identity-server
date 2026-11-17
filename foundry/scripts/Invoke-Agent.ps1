[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AgentId,
    [Parameter(Mandatory)][string]$StageId,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$PromptPath,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ContextPaths,
    [AllowEmptyCollection()][string[]]$PriorityContextPaths = @(),
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$SchemaPath,
    [Parameter(Mandatory)][object]$Config,
    [object]$Policy = $null,
    [int]$StageIteration = 1,
    [int]$MaxArtifactBytes = 0,
    [hashtable]$ProviderEnvironment = @{},
    [string]$RepositoryRoot = "",
    [string]$PreviousArtifactPath = "",
    [string]$RevisionBasePath = "",
    [string]$PlannedFileOwnerArtifactPath = "",
    [string]$PlannedFileOwnerAgentId = "",
    [string]$ToolchainLockPath = "",
    [AllowNull()][object]$Deadline = $null,
    [switch]$EnforceProjectRationale,
    [switch]$AllowExistingArtifact
)

. (Join-Path $PSScriptRoot "Common.ps1")
. (Join-Path $PSScriptRoot 'GenerationRepair.ps1')
$splitInvocationParameters = @{} + $PSBoundParameters
$batchAssignment = $null
if ((Split-Path $SchemaPath -Leaf) -eq 'change-set-batch.schema.json') {
    $assignments = @(@($PriorityContextPaths) + @($ContextPaths) | Select-Object -Unique | Where-Object {
        (Split-Path $_ -Leaf) -like 'assignment-*.json'
    })
    if ($assignments.Count -eq 1) {
        $batchAssignment = Get-Content -LiteralPath $assignments[0] -Raw | ConvertFrom-Json -Depth 100
    }
}
$root = Get-QaFoundryRoot
$maxRetries = if ($null -ne $Config.runtime.agent_schema_retries) {
    [int]$Config.runtime.agent_schema_retries
}
else {
    1
}

$artifactByteBudget = if ($MaxArtifactBytes -gt 0) {
    # A per-agent budget from the workflow wins over the profile default. It is
    # read first and kept in a differently named variable because PowerShell
    # matches variables case-insensitively: a local $maxArtifactBytes and the
    # parameter $MaxArtifactBytes are one variable, so assigning the profile
    # default to the local one silently destroys the value that was passed in.
    $MaxArtifactBytes
}
elseif ($Config.ai.PSObject.Properties.Name -contains "max_artifact_bytes") {
    [int]$Config.ai.max_artifact_bytes
}
else {
    0
}

$progressSettings = if ($Config.runtime.PSObject.Properties.Name -contains "progress") {
    $Config.runtime.progress
}
else {
    $null
}
$narrationEnabled = $true
$narrationMaxItems = 2
$narrationMaxLength = 160
if ($null -ne $progressSettings) {
    if ($progressSettings.PSObject.Properties.Name -contains "narrate_agent_output") {
        $narrationEnabled = [bool]$progressSettings.narrate_agent_output
    }
    if ($progressSettings.PSObject.Properties.Name -contains "narration_max_items") {
        $narrationMaxItems = [int]$progressSettings.narration_max_items
    }
    if ($progressSettings.PSObject.Properties.Name -contains "narration_max_length") {
        $narrationMaxLength = [int]$progressSettings.narration_max_length
    }
}


$sharedPaths = @(
    "prompts/shared/system-principles.md",
    "prompts/shared/security-principles.md",
    "prompts/shared/evidence-rules.md"
)
$sharedText = @($sharedPaths | ForEach-Object {
    Get-Content -Path (Join-Path $root $_) -Raw
}) -join "`n`n"
$sharedText += @'

# Product defects and regression tests
Keep a test and its assertion when execution confirms a product defect. Do not delete, skip, mark it expected-failure, weaken its expectation or edit product code to make the run green. Foundry files a linked Bug after independent evidence review, reuses that Bug on subsequent runs and distinguishes framework readiness from the still-failing product regression. Compilation, setup failures, wrong fixtures, unsupported validators and ambiguous requirements remain framework/test issues or unresolved findings; they are not product-defect exemptions. A known product failure must remain visible in test results and delivery reporting with its Bug reference. Use runnable real checks and let the deterministic verification and defect-reporting steps establish the outcome; planning alone cannot declare a Bug confirmed.
'@
if ($StageId -in @('architecture', 'test-planning', 'implementation', 'review')) {
    $sharedText += "`n`n" + [IO.File]::ReadAllText(
        (Join-Path $root 'prompts/shared/architecture-decision-rules.md'))
}
if ($StageId -in @(
    'architecture', 'test-planning', 'implementation', 'review',
    'bootstrap-change-generation', 'bootstrap-change-review',
    'impact-analysis', 'impact-backlog', 'impact-review',
    'implementation-analysis', 'change-generation', 'change-review', 'verification-review',
    'failure-investigation', 'remediation-planning', 'remediation-review',
    'test-case-planning', 'test-case-review')) {
    $sharedText += "`n`n" + [IO.File]::ReadAllText(
        (Join-Path $root 'prompts/shared/ui-maintenance-rules.md'))
}
$agentPrompt = Get-Content -Path $PromptPath -Raw
if (Test-QaFoundryDeferredVerification -Config $Config) {
    $sharedText += "`n`n" + [IO.File]::ReadAllText(
        (Join-Path $root 'prompts/shared/deferred-verification.md'))
}
$needsSpreadsheetFixture = $false
if ($StageId -in @('implementation', 'bootstrap-change-generation')) {
    foreach ($contextPath in $ContextPaths) {
        if ((Test-Path -LiteralPath $contextPath -PathType Leaf) -and
            [IO.File]::ReadAllText($contextPath) -match '(?i)\.xlsx\b|\bspreadsheet\b|\bexcel\b') {
            $needsSpreadsheetFixture = $true
            break
        }
    }
}
if ($needsSpreadsheetFixture) {
    $fixturePath = Join-Path $root 'prompts/shared/fixtures/single-column-prices.json'
    $agentPrompt += @"

## Available spreadsheet fixture
The following fixture contains a real XLSX workbook, not XML renamed as XLSX. Its first sheet
has numeric A1=10 and A2=20, with no header. Copy its base64 bytes unchanged into a fixture module
inside the approved Automation project and decode with Node Buffer.from(value, 'base64') or .NET
Convert.FromBase64String. Verify its SHA-256. Playwright setInputFiles accepts the decoded buffer,
filename and MIME type directly; generating ZIP files or adding a spreadsheet dependency is not
needed for this upload scenario. Assert the resulting product behavior, not merely fixture decoding.
The generated project must carry its own copy; it must not depend on Foundry files at runtime.
The test agent owns this test-data module unless the foundation already planned the same path.
Use the exact filename in expected notifications. These bytes do not establish multi-column or
oversized workbook coverage; those scenarios need their own valid inputs.
$(Get-Content -LiteralPath $fixturePath -Raw)
"@
}
$responseSchemaPath = $SchemaPath
if ($RevisionBasePath) {
    $responseSchemaPath = Join-Path $root 'schemas/architecture/blueprint-revision.schema.json'
    $revisionHash = (Get-FileHash -LiteralPath $RevisionBasePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $agentPrompt += @"

## Incremental revision response (overrides full-blueprint output instructions)
The existing blueprint is $RevisionBasePath, SHA-256 $revisionHash.
Return only an Incremental blueprint revision, using this exact baseSha256.
Read the base and revision ledger. Preserve everything outside the specific edits.
An edit replaces a value at an existing parent using a JSON Pointer, for example
/details/ciIntegration/defaultSelection or /details/automationProjects/0/toolchain/ciRequirements.
Object keys may be added, array indices must exist; replace an array to change its membership.
Escape / as ~1 and ~ as ~0 in object keys. Do not replace /details or repeat unchanged sections.
The runtime applies the edits and validates the complete blueprint with its original schema
and semantic checks before critics read it. The original schema is included as validation
reference for edited values; the response itself must match only the revision schema.
You still owe every outstanding required item.
Return all remaining deferrals. For each previous deferral now resolved, provide its exact item,
the resolution and the edited paths that implement it in resolvedDeferrals. Future execution
inputs belong in documented symbolic prerequisite contracts, not omissions of architecture.
If output is constrained, retain unapplied work in deferrals; do not remove existing content.
"@
    if ($AllowExistingArtifact -and (Test-Path -LiteralPath $OutputPath)) {
        $recordedRevision = Get-Content -LiteralPath "$OutputPath.revision.json" -Raw | ConvertFrom-Json
        if ($recordedRevision.baseSha256 -cne $revisionHash) { throw 'Recorded revision belongs to a different blueprint base.' }
    }
}
$schemaParts = @(
    $responseSchemaPath,
    $SchemaPath,
    (Join-Path $root "schemas/common/agent-result.schema.json"),
    (Join-Path $root "schemas/common/evidence.schema.json"),
    (Join-Path $root "schemas/common/review-decision.schema.json")
) | Select-Object -Unique
$schemaText = @($schemaParts | ForEach-Object {
    "## Schema file: $_`n$(Get-Content -Path $_ -Raw)"
}) -join "`n`n"

$maxRequestBytes = if ($Config.runtime.context.PSObject.Properties.Name -contains "max_request_bytes") {
    [int64]$Config.runtime.context.max_request_bytes
}
else {
    [int64]262144
}

$priorityPaths = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($priorityPath in @($PriorityContextPaths)) {
    if (Test-Path $priorityPath -PathType Leaf) {
        $null = $priorityPaths.Add((Resolve-Path $priorityPath).Path)
    }
}

$contextEntries = @()
$seenContext = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)
foreach ($candidate in (@($PriorityContextPaths) + @($ContextPaths))) {
    if ([string]::IsNullOrWhiteSpace($candidate) -or -not (Test-Path $candidate -PathType Leaf)) {
        continue
    }
    $resolvedContext = (Resolve-Path $candidate).Path
    if (-not $seenContext.Add($resolvedContext)) { continue }
    $contextFile = Get-Item -LiteralPath $resolvedContext -Force
    # Direct stage inputs outrank shared run evidence, which outranks the bulky
    # repository dump, which outranks artifacts accumulated by earlier stages.
    $rank = if ($priorityPaths.Contains($resolvedContext)) { 0 }
    elseif ($contextFile.Name -eq "repository.json") { 2 }
    elseif ($contextFile.Directory.Name -eq "context") { 1 }
    else { 3 }
    $contextEntries += [pscustomobject]@{
        Path = $resolvedContext
        Rank = $rank
        LastWriteTimeUtc = $contextFile.LastWriteTimeUtc
    }
}
$contextEntries = @($contextEntries |
    Sort-Object Rank, @{ Expression = "LastWriteTimeUtc"; Descending = $true }, Path)

# An agent request must stay bounded. Artifacts remain on disk, so anything that
# does not fit the inline budget is named, sized and hashed instead of dropped.
$maxInventoryEntries = if ($Config.runtime.context.PSObject.Properties.Name -contains "max_inventory_entries") {
    [int]$Config.runtime.context.max_inventory_entries
}
else {
    2000
}

$contextSections = [System.Collections.Generic.List[string]]::new()
$contextManifest = [System.Collections.Generic.List[string]]::new()
$inlinedBytes = [int64]0
$referencedCount = 0
foreach ($entry in $contextEntries) {
    $rawContent = Get-Content -LiteralPath $entry.Path -Raw
    if ($null -eq $rawContent) { $rawContent = "" }
    $inlineText = [string]$rawContent
    $projected = $false
    if ($entry.Rank -eq 2) {
        try {
            $fullContext = $inlineText | ConvertFrom-Json -Depth 100
            $inlineText = ConvertTo-QaFoundryRepositoryDigest `
                -Context $fullContext `
                -MaxInventoryEntries $maxInventoryEntries |
                ConvertTo-Json -Depth 30
            $projected = $true
        }
        catch {
            $inlineText = [string]$rawContent
        }
    }
    $entryBytes = [Text.Encoding]::UTF8.GetByteCount($inlineText)
    # Priority artifacts are sorted first and so get first claim on the budget,
    # but they do not get to ignore it. A producer output large enough to blow
    # the budget on its own is referenced by path like anything else, because an
    # unbounded request costs more time than the extra file read it saves.
    if (($inlinedBytes + $entryBytes) -le $maxRequestBytes) {
        $inlinedBytes += $entryBytes
        $heading = if ($projected) {
            "## Context projection of $($entry.Path)`nThe complete artifact, including every file hash, is on disk at that path. Read it directly if you need an entry that is summarised here."
        }
        else {
            "## Context: $($entry.Path)"
        }
        $contextSections.Add("$heading`n$inlineText")
        $contextManifest.Add(
            "- $(if ($projected) { 'projected' } else { 'inlined' }) ($entryBytes bytes): $($entry.Path)")
    }
    else {
        $referencedCount++
        $entryHash = Get-FileSha256Safe -Path $entry.Path
        $contextSections.Add(@"
## Context reference, not inlined: $($entry.Path)

- Bytes: $entryBytes
- SHA-256: $entryHash
- This artifact exceeded the inline request budget of $maxRequestBytes bytes.
  Read the file directly with your file-view tool if you need its content.
"@)
        $contextManifest.Add("- referenced ($entryBytes bytes): $($entry.Path)")
    }
}
$contextText = @($contextSections) -join "`n`n"
$summaryLines = [System.Collections.Generic.List[string]]::new()
$summaryLines.Add("Inline budget: $maxRequestBytes bytes.")
$summaryLines.Add(
    "Inlined or projected: $inlinedBytes bytes across " +
    "$(@($contextEntries).Count - $referencedCount) artifact(s).")
$summaryLines.Add("Referenced by path, not inlined: $referencedCount artifact(s).")
$summaryLines.Add("")
foreach ($manifestLine in $contextManifest) {
    $summaryLines.Add([string]$manifestLine)
}
$contextSummary = @($summaryLines) -join [Environment]::NewLine

$parent = Split-Path $OutputPath -Parent
New-Item -ItemType Directory -Path $parent -Force | Out-Null

$lastValidationError = ""
$allowedWriteList = @($Config.repository.allowed_write_paths | ForEach-Object {
    "- " + (([string]$_).Replace("\", "/") -replace "^\./", "").TrimStart("/")
}) -join [Environment]::NewLine
$forbiddenWriteList = @($Config.repository.forbidden_write_paths | ForEach-Object {
    "- " + (([string]$_).Replace("\", "/") -replace "^\./", "").TrimStart("/")
}) -join [Environment]::NewLine
$writeScopeSection = if ([string]::IsNullOrWhiteSpace($allowedWriteList)) {
    ""
}
else {
    @"
# Repository write scope

These are the only paths this repository lets the run write to. The applier is a whitelist: a path
that does not start with one of these prefixes is refused, and so is a path under a forbidden prefix
even when an allowed prefix also matches it. Anything not listed here is unwritable, including
directories that look like the obvious place for the work.

Writable prefixes:
$allowedWriteList

Explicitly forbidden:
$forbiddenWriteList

Any path you name — a project root, a planned file, a change-set entry — must sit under a writable
prefix. Choosing a sensible-looking path outside this list does not widen the scope; it produces an
artifact the runtime rejects and a run that writes nothing. If the work genuinely cannot be done
inside these prefixes, say so in your output rather than naming a path outside them.
"@
}
# Only the agents that author file bodies are told about the output filter. A
# reviewer or a planner never emits source, so the paragraph would be noise in
# a request that already runs to 150 KB.
$outputFilterSection = if ((Get-Content -Path $SchemaPath -Raw) -notmatch '"changes"') {
    ""
}
else {
    @"
# Output filter

A secret filter runs over your answer before this runtime receives it. It matches an authorization
scheme written next to its value — the words that normally precede a token — and replaces the run
with asterisks, taking the neighbouring quote or backtick with it. The characters it removes cannot
be recovered, so an answer it touches is refused in full and costs a whole attempt.

Never write an authorization scheme adjacent to its value in one literal, in source, in a string,
or in a comment. Build it from parts instead: ``'Bearer ' + token``, or a named constant holding the
scheme alone that is concatenated with the value. Where a test or a scanner needs a credential-shaped
sample, assemble it from fragments for the same reason.
"@
}
# Emitted only for the reviews whose rejection is acted on file by file. Every
# other review would be told about fields its schema does not offer.
$repairScopeSection = if ((Get-Content -Path $SchemaPath -Raw) -notmatch '"repairScope"') {
    ""
}
else {
    @"
# Scope of the repair you are asking for

Your rejection is acted on, not read. If you reject, say how much has to be written again.

Use ``repairScope: targeted`` when the defect is confined to files you can name, and list them in
``repairTargets``. Every other approved file is carried forward byte for byte, so a file you do not
name is a file you are stating is correct as written. Name the files that have to change, not every
file the defect touches: if a helper exports the wrong name and three specs import it correctly,
the target is the helper alone. Name both sides only when both have to be rewritten. Each target
carries the instruction the writer needs to fix it, in its own words rather than a reference to a
finding number.

Use ``repairScope: all`` when the defect is structural — the wrong architecture, the wrong toolchain,
a decision that changes most of the tree — and the whole set genuinely has to be written again.

Every path you name must be one of the approved paths you were given. A path that is not among them
is not a repair target, and naming one costs the run an entire regeneration cycle.
"@
}
$attemptArtifactBytes = $artifactByteBudget
# Every time the budget is cut, the agent is asked for less than the run asked
# it for. That is a decision to leave work undone, and it has to survive the
# attempt that made it: an answer accepted three attempts later is still an
# answer to a smaller question, and nothing downstream can tell unless this run
# says so.
$scopeReductions = [System.Collections.Generic.List[object]]::new()
# Whether the agent has already been asked to name what a reduced answer left
# out. Asking is worth one call and no more: an agent that keeps insisting it
# finished is not going to change its mind on the third attempt, and each one
# costs as much as the answer itself.
$deferralNudgeUsed = $false
# Set when a reduced answer is kept even though it named nothing left out. The
# artifact stands; what does not stand is the claim that it is finished.
$coverageUnconfirmed = $false
# One wording, used by every path that cuts the budget, because an agent that is
# told to record its omissions differently each time records them differently
# each time.
$deferralInstruction =
    " List every item you leave out in the top-level ``deferrals`` array, one object per item," +
    " with ``kind`` set to output_budget, artifact_invalid, external_prerequisite or product_gap." +
    " each with ``item`` naming the piece of work specifically enough that a later attempt can" +
    " produce it without asking what was meant, and ``reason`` saying why that one went rather" +
    " than another. Keep ``item`` at or under 400 characters and ``reason`` at or under 600," +
    " and aim for 350 and 550 so a sentence added in revision does not put the answer over:" +
    " name the work, do not describe it case by case, and split an entry that will not fit" +
    " into the several items it actually is. This is not a note: the run reads that array," +
    " treats the answer as unfinished while it has entries, and comes back for what is in it." +
    " An artifact that is smaller than the work you were given and leaves ``deferrals`` empty" +
    " is rejected."
function Add-ScopeReduction {
    param(
        [Parameter(Mandatory)][int]$Attempt,
        [Parameter(Mandatory)][string]$Cause,
        [Parameter(Mandatory)][int]$GrantedBytes
    )

    $scopeReductions.Add([ordered]@{
        attempt = $Attempt
        cause = $Cause
        grantedBytes = $GrantedBytes
    })
}
# A rejection is expensive knowledge: it cost a full model call to learn what
# was wrong with the answer. Build 480 showed the relay throwing that knowledge
# away at every leg boundary — an agent whose first attempt was rejected left no
# trace, so the next leg asked the same question again, got the same wrong
# answer, and ran out of budget in the same place. The feedback therefore
# outlives the process that earned it.
$rejectionPath = "$OutputPath.rejections.json"
$priorAttempts = 0
if ($AllowExistingArtifact -and (Test-Path -LiteralPath $rejectionPath -PathType Leaf)) {
    try {
        $priorRejection = Get-Content -LiteralPath $rejectionPath -Raw | ConvertFrom-Json -Depth 100
        if ([string]$priorRejection.runId -eq $RunId -and
            [int]$priorRejection.attempts -ge 1) {
            $priorAttempts = [int]$priorRejection.attempts
            $lastValidationError = [string]$priorRejection.lastValidationError
            if ([int]$priorRejection.attemptArtifactBytes -gt 0) {
                $attemptArtifactBytes = [int]$priorRejection.attemptArtifactBytes
            }
            # Asking once is a promise about the run, not about the process. A
            # leg that ends between the ask and the answer would otherwise let
            # the next one ask again, and the twelve-minute argument this was
            # written to stop resumes across the boundary.
            if ((Get-QaFoundryPropertyNames -InputObject $priorRejection) -contains "deferralNudgeUsed") {
                $deferralNudgeUsed = [bool]$priorRejection.deferralNudgeUsed
            }
            # A budget cut on an earlier leg is still a cut. Losing the record of
            # it here would let the next leg accept a reduced answer as if it had
            # been asked for the whole thing.
            if ((Get-QaFoundryPropertyNames -InputObject $priorRejection) -contains "scopeReductions") {
                foreach ($reduction in @($priorRejection.scopeReductions)) {
                    if ($null -eq $reduction) { continue }
                    $scopeReductions.Add([ordered]@{
                        attempt = [int]$reduction.attempt
                        cause = [string]$reduction.cause
                        grantedBytes = [int]$reduction.grantedBytes
                    })
                }
            }
            Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
                "$priorAttempts attempt(s) on an earlier leg were rejected. Resuming with what " +
                "they established rather than asking the same question again.")
        }
    }
    catch {
        # Unreadable feedback is no feedback. Better a fresh attempt than one
        # steered by a half-written file.
        $priorAttempts = 0
    }
}
function Save-AgentRejection {
    param(
        [Parameter(Mandatory)][int]$Attempts,
        [Parameter(Mandatory)][AllowEmptyString()][string]$ValidationError,
        [Parameter(Mandatory)][int]$ArtifactBytes
    )

    $temporaryPath = "$rejectionPath.tmp"
    [ordered]@{
        runId = $RunId
        agentId = $AgentId
        attempts = $Attempts
        lastValidationError = $ValidationError
        attemptArtifactBytes = $ArtifactBytes
        deferralNudgeUsed = $deferralNudgeUsed
        scopeReductions = @($scopeReductions)
    } | ConvertTo-Json -Depth 100 | Set-Content -Path $temporaryPath -Encoding utf8
    Move-Item -LiteralPath $temporaryPath -Destination $rejectionPath -Force
}
function Clear-AgentRejection {
    if (Test-Path -LiteralPath $rejectionPath -PathType Leaf) {
        Remove-Item -LiteralPath $rejectionPath -Force -ErrorAction SilentlyContinue
    }
}
$namingConvention = $null
$namingSection = ""
$namingSettings = if ($Config.PSObject.Properties.Name -contains "automation" -and
    $null -ne $Config.automation -and
    $Config.automation.PSObject.Properties.Name -contains "naming") {
    $Config.automation.naming
}
else { $null }
$namingMode = if ($null -ne $namingSettings -and
    $namingSettings.PSObject.Properties.Name -contains "mode") {
    ([string]$namingSettings.mode).ToLowerInvariant()
}
else { "auto" }
$namingEnforced = if ($null -ne $namingSettings -and
    $namingSettings.PSObject.Properties.Name -contains "enforce") {
    [bool]$namingSettings.enforce
}
else { $true }
if ($namingMode -ne "off" -and -not [string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $namingSegment = if ($null -ne $namingSettings -and
        $namingSettings.PSObject.Properties.Name -contains "segment" -and
        -not [string]::IsNullOrWhiteSpace([string]$namingSettings.segment)) {
        [string]$namingSettings.segment
    }
    else { "Automation" }
    $namingPrefix = if ($namingMode -eq "fixed" -and
        $null -ne $namingSettings -and
        $namingSettings.PSObject.Properties.Name -contains "prefix") {
        [string]$namingSettings.prefix
    }
    else { "" }
    $namingExcluded = @()
    if ($Config.runtime.PSObject.Properties.Name -contains "context" -and
        $Config.runtime.context.PSObject.Properties.Name -contains "excluded_directories") {
        $namingExcluded = @($Config.runtime.context.excluded_directories | ForEach-Object { [string]$_ })
    }
    $namingCacheKey = "$RepositoryRoot|$namingMode|$namingPrefix|$namingSegment"
    if (-not (Test-Path "variable:global:QaFoundryNamingConventionCache")) {
        $global:QaFoundryNamingConventionCache = @{}
    }
    if ($global:QaFoundryNamingConventionCache.ContainsKey($namingCacheKey)) {
        $namingConvention = $global:QaFoundryNamingConventionCache[$namingCacheKey]
    }
    else {
        try {
            $namingConvention = & (Join-Path $PSScriptRoot "Get-RepositoryNamingConvention.ps1") `
                -RepositoryRoot $RepositoryRoot `
                -Segment $namingSegment `
                -FixedPrefix $namingPrefix `
                -ExcludedDirectories $namingExcluded
        }
        catch {
            # Naming is a convention, not a safety control. A repository shape the
            # detector cannot read must not stop the run.
            $namingConvention = $null
        }
        $global:QaFoundryNamingConventionCache[$namingCacheKey] = $namingConvention
    }
}
if ($null -ne $namingConvention -and $namingConvention.detected) {
    $namingSamples = if (@($namingConvention.samples).Count -gt 0) {
        "Existing names it was derived from: " + ((@($namingConvention.samples)) -join ", ") + "."
    }
    else { "" }
    $namingRule = if ($namingEnforced) {
        "A name that does not start with ``$($namingConvention.prefix)$($namingConvention.separator)$($namingConvention.segment)$($namingConvention.separator)`` is rejected by the runtime."
    }
    else {
        "Departing from it needs a reason stated in the artifact."
    }
    $namingSection = @"
# Project naming convention

This repository already names its components to a pattern, and anything this programme adds has to
look like it belongs. The convention was derived from the repository itself, not assumed:
$($namingConvention.evidence). $namingSamples

Name every automation project:

    $($namingConvention.template)

where ``{scope}`` is what that project covers — for example ``$($namingConvention.example)``. Keep the
same separator and the same casing as the surrounding names. $namingRule

The directory a project lives in is constrained by the write scope below, so it cannot always mirror
the name. Where this repository names component directories after the components themselves, follow
that too and put each project in a directory of the same name inside a writable prefix.
"@
}

# What this installation can install, build and run, and the limits any dependency
# set has to satisfy. It is deliberately not a list of approved packages: an
# approved list decides the architecture in a configuration file months before
# anyone looks at the repository the automation is for. The architect chooses
# from product evidence and testing needs; this section only says which ecosystems
# the runtime can execute and what a choice has to stay inside.
$supportedEcosystems = @()
$packagePolicy = $null
$toolchainSection = ""
if ($Config.PSObject.Properties.Name -contains "automation" -and
    $null -ne $Config.automation) {
    $supportedEcosystems = @(Resolve-QaFoundryAutomationEcosystems -Automation $Config.automation)
    $packagePolicy = Resolve-QaFoundryPackagePolicy -Automation $Config.automation
}
# Only the stage that chooses a toolchain needs to be told what it may choose.
# A discovery agent that reports what a repository contains is not designing
# anything, and telling it to stop when no ecosystem fits invites it to stop over
# something it was never asked to decide.
if ($supportedEcosystems.Count -gt 0 -and $StageId -eq "architecture") {
    $ecosystemDescriptions = foreach ($ecosystem in $supportedEcosystems) {
        $runtimeLines = foreach ($runtimeKey in @($ecosystem.runtime.Keys)) {
            "    - $runtimeKey`: $([string]$ecosystem.runtime[$runtimeKey])"
        }
        @"
- ``$([string]$ecosystem.id)``, resolved from $([string]$ecosystem.source.registry)
  Runtime available on a build agent:
$($runtimeLines -join [Environment]::NewLine)
"@
    }
    $deniedLine = if (@($packagePolicy.deniedPackages).Count -gt 0) {
        "Refused outright, whoever proposes them: " + (@($packagePolicy.deniedPackages) -join ", ") + "."
    }
    else { "No package is refused by name." }
    $prereleaseLine = if ($packagePolicy.allowPrerelease) {
        "Pre-release versions require an explicit version request and a documented need unavailable in suitable stable releases."
    }
    else { "Pre-release versions are not allowed." }
    # The licence policy is stated to the architect because it is checked against
    # the whole resolved graph later. A refused licence found only at that point
    # costs the run a redesign it could have avoided by choosing differently
    # here.
    $licenceLine = if (@($packagePolicy.deniedLicenses).Count -gt 0) {
        "Refused licences, for a direct dependency and for anything it pulls in: " +
            (@($packagePolicy.deniedLicenses) -join ", ") +
            ". The lock file is checked against this, so a package whose own dependencies carry one " +
            "of these is refused with it."
    }
    else { "No licence is refused." }
    $toolchainSection = @"
# Choosing the technology

Nobody has pre-approved a winning stack. Compare existing automation, the product ecosystem and
credible alternatives against the actual testing needs. No candidate has automatic priority.
Ground the comparison in product risks, inspected code, project documentation and existing test seams.
Assess coverage, fault control, assertion quality, diagnosis, reproducibility, maintenance and cost.

A different language is justified by an evidenced net advantage; the product language need not be
incapable. Reuse and additional toolchains both have costs to explain. Popularity, novelty and personal
familiarity alone are not reasons. The agents decide project boundaries from product evidence;
there is no prescribed decomposition by test level, component, protocol or language. Within the
configured project bounds, compare keeping tests together with separating them. Split only when
the concrete benefit outweighs added setup, duplication and maintenance; otherwise use suites,
tags or modules inside a shared framework. The upper bound is permission, not a quota.

Record alternatives, decisive criteria, tradeoffs and change conditions in ``details.decision``.
Map material risks to test layers and assertions in ``details.testTaxonomy``. Critics must challenge
the strongest alternative independently; agreement between agents is not evidence of optimality.

Base all of this on evidence you can point at: solution and project files, ``global.json``,
``Directory.Build.props``, ``Directory.Packages.props``, ``NuGet.config``, ``package.json``, lock
files, existing test projects, pipeline definitions and retrieved project documentation. Every conclusion in ``detectedStack`` carries the
files that prove it. Ignore vendored dependencies, generated output and the foundry's own tooling when
deciding what the product is written in.

# What this installation can execute

Your choice has to run on a build agent, so it has to resolve from an ecosystem this installation
supports:

$($ecosystemDescriptions -join [Environment]::NewLine)

The runtime version you record is checked against the one above before anything is locked. Where the
ecosystem's toolchain builds for older runtimes than it runs on - a .NET SDK targets its own framework
and every earlier one - you may design for an earlier target and say so. Where it does not, and Node,
Python, Ruby, PHP, Go and Java do not, the version you name has to be the version listed above.
Naming a different one stops the run with both numbers quoted rather than being silently replaced, so
if the repository genuinely needs another runtime, say that instead of designing around it.

If none of these can express the right answer for this repository, say so and stop. Do not quietly
design in a supported ecosystem you would not otherwise have chosen and present it as the decision -
a wrong stack that installs is worse than an honest refusal.

# Dependencies

Propose the packages each project needs, with a purpose for each. You are not choosing from a list and
you do not need anything approved in advance. A version may be a range; a deterministic resolver then
checks each package exists in the source above, pins an exact version, applies the rules below and
writes the lock file. Propose a package that does not exist and resolution fails with the name you
gave, so name packages you are sure of.

- $(if ([int]$packagePolicy.maxDirectPackages -gt 0) { "At most $([int]$packagePolicy.maxDirectPackages) direct packages per automation project." } else { 'No fixed limit on the number of direct packages; justify each dependency.' })
- $prereleaseLine
- $deniedLine
- $licenceLine

Record the decision on each project under ``toolchain``: the stack you detected with its evidence, the
ecosystem, language, runtime and test framework you chose, what you reused from the repository, how
each required capability is met, the alternatives you rejected and why, what a build agent has to
provide, and - if the automation is not written in the product's own technology - the concrete reason.
An unexplained change of ecosystem is sent back by review.

Current materialization capability: the runtime resolves standalone manifests. Multi-package
workspaces, child manifests and local/link dependency graphs are not automatically resolved by that
recipe. This is a runner capability limit, not an architectural prohibition. If the best design needs
one of these graphs or a product project reference, name the exact materialization/restore capability
and execution prerequisite. Do not claim it is supported or silently substitute weaker coverage.
Within the current recipe, use independently resolved manifests or runner-native suites as appropriate.

Current verifier entry points are adapter-owned, not inferred from proposedCommands or pipeline YAML.
For npm it invokes npm test; scripts.test must run the planned environment-free assertions, while
deployed tests need their own explicit entry point and prerequisite checks. For NuGet it invokes
dotnet test, or dotnet run for a built MTP executable, without adding a category filter. Merely
tagging tests EnvironmentFree does not select them. Design an actual default selection using the
runner's supported configuration/entry point, and retain a separate explicit deployed selection.
Read the selected adapter under $root/scripts/ecosystems/ for the exact commands and negative-probe
contract. The same suite must execute one additional deliberately failing probe during verification.
If the approved file contracts cannot implement that selection, revise the contracts and required
files; never satisfy the gate with discovery-only commands, skips, disabled preflight or fake values.
"@
}

# A repository that already carries a framework has already answered this
# question, and answering it again is not a neutral act: it delivers a second
# framework beside the first, in a language nobody chose twice, and splits the
# suites a team has to keep alive. The record survives the run directory, so it
# is the only thing that can stop that from happening on the next run.
$settledToolchainSection = ""
$script:RecordedToolchainForSemantics = $null
if (-not [string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $recordedToolchain = Get-QaFoundryRecordedToolchain -RepositoryRoot $RepositoryRoot -Config $Config
    if ($null -ne $recordedToolchain) {
        $script:RecordedToolchainForSemantics = $recordedToolchain
        $recordedLines = foreach ($entry in @($recordedToolchain.toolchains)) {
            $entryFields = @(Get-QaFoundryPropertyNames -InputObject $entry)
            $described = @("ecosystem ``$([string]$entry.ecosystem)``")
            foreach ($optional in @("language", "testFramework")) {
                if ($entryFields -contains $optional) {
                    $described += "$optional ``$([string]$entry.$optional)``"
                }
            }
            "- $($described -join ', ') for: " + ((@($entry.projects)) -join ", ")
        }
        $settledToolchainSection = if ($StageId -eq "architecture") {
            @"
# The technology is already decided

This repository carries a recorded automation toolchain from run
``$([string]$recordedToolchain.runId)``:

$($recordedLines -join [Environment]::NewLine)

This run continues an existing implementation. Preserve its recorded toolchain in each project's
``toolchain`` and cite this record; do not silently migrate it while adding coverage. Compare proposed
improvements on their merits and record evidence when the current choice is no longer the best fit.

Changing it is a migration, and a migration is a piece of work in its own right - its own pull
request, its own justification, its own verification that the new stack builds and the old suites
still run. A demonstrated net improvement can justify a migration even if the current stack could
technically meet the requirement. Describe the benefit, compatibility costs and migration scope.
If this run requires a migration that is not authorized and supported here, report the affected work
as blocked with that concrete prerequisite rather than quietly replacing the recorded stack.
"@
        }
        else {
            # The blueprint is not the only way a second toolchain arrives. An
            # ordinary task to add a test can do it too, by writing a manifest of
            # another ecosystem into a suite that already has one, and that change
            # set never passes through an architect.
            @"
# The automation toolchain is already decided

This repository carries a recorded automation toolchain from run
``$([string]$recordedToolchain.runId)``:

$($recordedLines -join [Environment]::NewLine)

Any automation you write or change here belongs to that toolchain. Do not add a dependency manifest
of another ecosystem under the automation root, and do not move an existing suite onto a different
stack while doing something else: that is a migration, and a migration is work in its own right with
its own pull request, its own justification and its own verification that both stacks still build.
The runtime refuses a change set that does it, so a change written that way is a wasted attempt.

If the work genuinely cannot be done in the recorded toolchain, return blocked, name the requirement
and name what about the recorded toolchain makes it unreachable.
"@
        }
    }
}

# The reasoning behind a stack is settled by the blueprint and, unless someone
# writes it into the repository, it is thrown away with the run directory. The
# name comes from configuration rather than from this text so that the prompt and
# the check that enforces it can never disagree about which file is meant.
$rationaleDocumentName = ""
if ($Config.PSObject.Properties.Name -contains "automation" -and
    $null -ne $Config.automation -and
    (Get-QaFoundryPropertyNames -InputObject $Config.automation) -contains "rationale_document") {
    $rationaleDocumentName = ([string]$Config.automation.rationale_document).Trim()
}
$rationaleSection = ""
if ($EnforceProjectRationale -and $rationaleDocumentName -ne "") {
    $rationaleSection = @"
# Recording why the stack was chosen

Every automation project carries a file named exactly ``$rationaleDocumentName`` at its root, and the
runtime rejects an inventory that leaves a project without one. Plan it like any other file, with a
``contentContract`` that says what it must contain.

It explains, for that project, why its language, runtime, test runner and libraries were chosen: what
the project has to do, which alternatives were considered and why they were rejected, and what the
choice costs as well as what it buys.

The blueprint already answered that. Each automation project carries a ``toolchain`` decision naming
the development stack that was detected and the files it was detected from, the ecosystem, language,
runtime and test framework chosen, what was reused from this repository rather than introduced, the
alternatives that were rejected and why, and - where the automation is not written in the technology
of the component it tests - the concrete requirement behind that. The contract for this file says to
carry that reasoning across in prose, with the evidence paths intact, rather than to invent a new
justification here: two different explanations of the same decision is how a reader learns to trust
neither.

Say plainly which parts were not open. The package ecosystems this installation can run, the package
sources and the programme's package policy were fixed before any agent saw the repository, and the
exact versions were pinned afterwards by a resolver rather than chosen. Presenting a constraint as a
preference, or a machine-pinned version as a judgement, misleads exactly the reader this file exists
for.

Write it for someone who arrives in a year with no access to this run and wants to know whether the
decision still holds.
"@
}

function Assert-AgentArtifactSemantics {
    param([Parameter(Mandatory)][object]$Artifact)

    # The schema says the document is well formed. These checks say it is
    # buildable: that the manifests can be materialised, that every project
    # explains itself, that the toolchain it designs against is one the
    # runtime installs, and that it writes only where it is allowed. They
    # used to live inside the retry loop alone, so an artifact recovered
    # from a killed leg was admitted on its schema alone and the reasons it
    # would have been rejected for went unasked.
    $reportedPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($pathSource in @("filesChanged", "plannedFiles", "changes")) {
        if ((Get-QaFoundryPropertyNames -InputObject $Artifact) -notcontains $pathSource) { continue }
        foreach ($entry in @($Artifact.$pathSource)) {
            if ($null -eq $entry) { continue }
            if ($entry -is [string]) { $reportedPaths.Add([string]$entry) }
            elseif ((Get-QaFoundryPropertyNames -InputObject $entry) -contains "path") {
                $reportedPaths.Add([string]$entry.path)
            }
        }
    }
    $artifactFields = @(Get-QaFoundryPropertyNames -InputObject $Artifact)
    # A change whose body carries the provider's redaction marker is not a
    # change: the filter took characters out of the source and did not say how
    # many. Refused here rather than merged, because the merge and the applier
    # both see well formed JSON and would deliver code that does not compile.
    # Only authored bodies are checked; narration may legitimately quote the
    # marker when a review is describing this very failure.
    if ($artifactFields -contains "changes") {
        $redacted = [System.Collections.Generic.List[string]]::new()
        foreach ($change in @($Artifact.changes)) {
            if ($null -eq $change) { continue }
            $changeFields = @(Get-QaFoundryPropertyNames -InputObject $change)
            if ($changeFields -notcontains "content") { continue }
            if (-not (Test-QaFoundryRedactedText -Text ([string]$change.content))) { continue }
            $path = if ($changeFields -contains "path") { [string]$change.path } else { "(unnamed)" }
            $redacted.Add($path)
        }
        if ($redacted.Count -gt 0) {
            throw (("{0}: the body of {1} file(s) came back with the provider's redaction marker " +
                "in place of source text: {2}. {3}") -f
                $script:QaFoundryRedactionMarker,
                $redacted.Count,
                (@($redacted | Select-Object -First 10) -join ", "),
                (Get-QaFoundryRedactionAdvice))
        }
    }
    # A plan that cannot be materialised is worth rejecting here, where the agent
    # still has retries left and receives the reason as feedback, rather than an
    # hour later in the deterministic stage, where a refusal ends the run. Build
    # 466 spent 23 minutes generating a plan built on npm workspaces and stopped
    # at the materialiser with no way back to the generator.
    #
    # It used to run only for an answer carrying both halves of a plan, which was
    # true of the agent build 466 had and of nothing since: generation is now
    # split across batch agents that write changes and a planner that writes
    # materialisations, so no single answer has both and the check had quietly
    # stopped running. Build 972914 reached stage 11 of 13 and blocked there on a
    # version range in a .csproj that this would have caught while the agent that
    # wrote it still had two attempts in hand. What can be judged from the
    # changes alone is now judged for every answer that carries changes.
    if ($artifactFields -contains "changes") {
        $plannedMaterializations = @()
        if ($artifactFields -contains "materializations") {
            $plannedMaterializations = @($Artifact.materializations)
        }
        $manifestFindings = @(& (Join-Path $PSScriptRoot "Test-PlannedManifest.ps1") `
            -Changes @($Artifact.changes) `
            -Materializations $plannedMaterializations `
            -ToolchainLockPath $ToolchainLockPath `
            -RequireTestCommand:($StageId -eq 'bootstrap-change-generation'))
        if ($manifestFindings.Count -gt 0) {
            throw ($manifestFindings -join " ")
        }
    }
    # Checked here, against the merged inventory, because a revision that
    # carries files forward unchanged still has to account for every project.
    if ($EnforceProjectRationale -and $rationaleDocumentName -ne "" -and
        $artifactFields -contains "plannedFiles") {
        $rationaleFindings = @(& (Join-Path $PSScriptRoot "Test-ProjectRationale.ps1") `
            -PlannedFiles @($Artifact.plannedFiles) `
            -DocumentName $rationaleDocumentName)
        if ($rationaleFindings.Count -gt 0) {
            throw ($rationaleFindings -join " ")
        }
    }
    # Also against the merged inventory: a file this agent restated two
    # iterations ago still conflicts with the owner's contract today, whether or
    # not this answer mentions it.
    if ($PlannedFileOwnerArtifactPath -ne "" -and $artifactFields -contains "plannedFiles") {
        $ownershipFindings = @(& (Join-Path $PSScriptRoot "Test-PlannedFileOwnership.ps1") `
            -PlannedFiles @($Artifact.plannedFiles) `
            -OwnerArtifactPath $PlannedFileOwnerArtifactPath `
            -OwnerAgentId $PlannedFileOwnerAgentId)
        if ($ownershipFindings.Count -gt 0) {
            throw ($ownershipFindings -join " ")
        }
    }
    if ((Get-QaFoundryPropertyNames -InputObject $Artifact) -contains "details" -and
        $null -ne $Artifact.details -and
        (Get-QaFoundryPropertyNames -InputObject $Artifact.details) -contains "automationProjects") {
        foreach ($project in @($Artifact.details.automationProjects)) {
            if ($null -ne $project -and
                (Get-QaFoundryPropertyNames -InputObject $project) -contains "path") {
                $reportedPaths.Add([string]$project.path)
            }
        }
        if ($namingEnforced -and $null -ne $namingConvention -and $namingConvention.detected) {
            foreach ($project in @($Artifact.details.automationProjects)) {
                if ($null -eq $project -or
                    (Get-QaFoundryPropertyNames -InputObject $project) -notcontains "name") { continue }
                $null = & (Join-Path $PSScriptRoot "Test-AutomationProjectName.ps1") `
                    -Name ([string]$project.name) `
                    -Convention $namingConvention
            }
        }
        if ($supportedEcosystems.Count -gt 0) {
            $supportedEcosystemIds = @($supportedEcosystems | ForEach-Object { [string]$_.id })
            foreach ($project in @($Artifact.details.automationProjects)) {
                if ($null -eq $project -or
                    (Get-QaFoundryPropertyNames -InputObject $project) -notcontains "toolchain" -or
                    $null -eq $project.toolchain) {
                    continue
                }
                $toolchain = $project.toolchain
                $toolchainNames = @(Get-QaFoundryPropertyNames -InputObject $toolchain)
                # The one thing that is genuinely not the architect's to decide.
                # Everything else about the stack is argued for in the blueprint and
                # judged by review; an ecosystem the runtime has no adapter for is
                # simply not installable, so it fails here rather than three stages
                # later in the middle of a build.
                if ($toolchainNames -contains "ecosystem") {
                    $chosenEcosystem = ([string]$toolchain.ecosystem).Trim().ToLowerInvariant()
                    if ($chosenEcosystem -notin $supportedEcosystemIds) {
                        throw ("Automation project '$([string]$project.name)' is designed against " +
                            "the '$chosenEcosystem' package ecosystem, which this installation " +
                            "cannot install, build or run. It supports " +
                            "($($supportedEcosystemIds -join ', ')). That is a limit on what can be " +
                            "executed here, not a judgement about the technology: design within one " +
                            "of those, or report that none of them fits the repository.")
                    }
                }
                if ($toolchainNames -contains "packages" -and $null -ne $packagePolicy) {
                    $proposed = @($toolchain.packages)
                    if ([int]$packagePolicy.maxDirectPackages -gt 0 -and $proposed.Count -gt [int]$packagePolicy.maxDirectPackages) {
                        throw ("Automation project '$([string]$project.name)' proposes " +
                            "$($proposed.Count) direct packages, and this programme allows at most " +
                            "$([int]$packagePolicy.maxDirectPackages). Fold the work into fewer " +
                            "dependencies rather than assembling a framework out of parts.")
                    }
                    # A refused name is matched by the registry's own rule about
                    # identity: NuGet folds case and RubyGems does not, so one
                    # lower-cased comparison would be wrong for one of them.
                    # Without a usable ecosystem there is no rule to apply, and
                    # the ecosystem check above has already refused that case.
                    $deniedEcosystem = ""
                    if ($toolchainNames -contains "ecosystem") {
                        $deniedEcosystem = ([string]$toolchain.ecosystem).Trim().ToLowerInvariant()
                    }
                    $denied = @()
                    if ($deniedEcosystem -in $supportedEcosystemIds) {
                        $denied = @($packagePolicy.deniedPackages |
                            Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                            ForEach-Object {
                                Get-QaFoundryNormalisedPackageName -Ecosystem $deniedEcosystem -Name ([string]$_)
                            })
                    }
                    foreach ($package in $proposed) {
                        if ($null -eq $package) { continue }
                        $packageNames = @(Get-QaFoundryPropertyNames -InputObject $package)
                        $packageName = if ($packageNames -contains "name") { ([string]$package.name).Trim() } else { "" }
                        # Reject unsupported notation before paying for architecture critics.
                        # Feed availability and dependency compatibility remain resolver checks.
                        if ($deniedEcosystem -in $supportedEcosystemIds -and $packageNames -contains "version") {
                            $rangeVerdict = Test-QaFoundryVersionRange -Ecosystem $deniedEcosystem -Range ([string]$package.version)
                            if (-not $rangeVerdict.valid) {
                                throw "Automation project '$($project.name)', package '${packageName}': $($rangeVerdict.reason)"
                            }
                        }
                        if ($packageName -and $denied.Count -gt 0) {
                            $canonicalName = Get-QaFoundryNormalisedPackageName -Ecosystem $deniedEcosystem `
                                -Name $packageName
                            if (@($denied | Where-Object { $_ -ceq $canonicalName }).Count -gt 0) {
                                throw ("Automation project '$([string]$project.name)' proposes the " +
                                    "package '$packageName', which this programme refuses. Choose " +
                                    "another way to meet the same need.")
                            }
                        }
                        if (-not $packagePolicy.allowPrerelease -and $packageNames -contains "version") {
                            $version = ([string]$package.version).Trim()
                            if ($version -match "-[0-9A-Za-z]") {
                                throw ("Automation project '$([string]$project.name)' pins " +
                                    "'$packageName' to the pre-release version '$version'. This " +
                                    "programme runs released versions only.")
                            }
                        }
                    }
                }
            }
        }
        # An already-bootstrapped repository has answered this once. Answering it
        # differently in passing would deliver a second framework beside the
        # first, and the run would look like a success right up to the moment two
        # suites in two languages need maintaining. A migration is legitimate,
        # but it is work with its own pull request - not a side effect of a
        # blueprint written for something else.
        if ($null -ne $script:RecordedToolchainForSemantics) {
            $proposedToolchains = foreach ($project in @($Artifact.details.automationProjects)) {
                if ($null -eq $project) { continue }
                $projectFields = @(Get-QaFoundryPropertyNames -InputObject $project)
                if ($projectFields -notcontains "toolchain" -or $null -eq $project.toolchain) { continue }
                $toolchainFields = @(Get-QaFoundryPropertyNames -InputObject $project.toolchain)
                if ($toolchainFields -notcontains "ecosystem") { continue }
                $proposal = [ordered]@{
                    name = [string]$project.name
                    path = [string]$project.path
                    ecosystem = [string]$project.toolchain.ecosystem
                }
                foreach ($optional in @("language", "testFramework")) {
                    if ($toolchainFields -contains $optional) {
                        $proposal[$optional] = [string]$project.toolchain.$optional
                    }
                }
                [pscustomobject]$proposal
            }
            $recordConflicts = @(Get-QaFoundryToolchainRecordConflicts `
                -Recorded $script:RecordedToolchainForSemantics -Proposed @($proposedToolchains))
            if ($recordConflicts.Count -gt 0) {
                throw ($recordConflicts -join " ")
            }
        }
    }
    if ($reportedPaths.Count -gt 0) {
        # The blueprint check reads what a design says about itself. This one
        # reads what the change actually writes, which is the only thing that
        # reaches the repository - and the only check an ordinary implementation
        # run, which has no blueprint at all, ever meets.
        $manifestConflicts = @(Get-QaFoundryToolchainManifestConflicts `
            -Recorded $script:RecordedToolchainForSemantics -Paths @($reportedPaths) `
            -AutomationRoot (Get-QaFoundryAutomationRoot -Config $Config))
        if ($manifestConflicts.Count -gt 0) {
            throw ($manifestConflicts -join " ")
        }
        $allowedPaths = @($Config.repository.allowed_write_paths | ForEach-Object {
            (([string]$_).Replace("\", "/") -replace "^\./", "").TrimStart("/").TrimEnd("/") + "/"
        })
        $forbiddenPaths = @($Config.repository.forbidden_write_paths | ForEach-Object {
            (([string]$_).Replace("\", "/") -replace "^\./", "").TrimStart("/").TrimEnd("/") + "/"
        })
        foreach ($changedFile in $reportedPaths) {
            $normalized = (([string]$changedFile).Replace("\", "/") -replace "^\./", "").TrimStart("/")
            if ($normalized -match "(^|/)\.\.(/|$)") {
                throw "Agent reported an unsafe write path: $changedFile"
            }
            if (@($forbiddenPaths | Where-Object {
                "$normalized/" -like "$_*"
            }).Count -gt 0) {
                throw "Agent reported a forbidden write path: $changedFile"
            }
            if (@($allowedPaths | Where-Object {
                "$normalized/" -like "$_*"
            }).Count -eq 0) {
                throw ("Agent reported a path outside allowed_write_paths: $changedFile. " +
                    "Writable prefixes are: " + (@($allowedPaths) -join ", ") +
                    ". Re-place the work under one of those prefixes.")
            }
        }
    }
}

# The whole acceptance path a fresh answer walks, in the order it walks it:
# schema, then the merge that carries unchanged file contracts forward from the
# previous iteration, then the schema again over the larger merged document, and
# only then the checks that say whether it is buildable. A leg can be killed
# between any two of these, so a recovered artifact walks the same path rather
# than a shortened one.
function Complete-AgentArtifact {
    param([Parameter(Mandatory)][object]$Artifact)

    $completed = $Artifact
    if ($PreviousArtifactPath -and (Test-Path -LiteralPath $PreviousArtifactPath) -and
        (Get-QaFoundryPropertyNames -InputObject $completed) -contains "plannedFiles") {
        # Merging an already-merged inventory carries nothing forward, so this is
        # safe to repeat on an artifact that reached disk after its merge.
        $mergeSummary = & (Join-Path $PSScriptRoot "Merge-IncrementalInventory.ps1") `
            -ArtifactPath $OutputPath `
            -PreviousArtifactPath $PreviousArtifactPath
        # Anything the merge rewrote has to be re-read and re-checked, not only
        # a merge that grew the inventory: a revision that drops a file changes
        # the document on disk while leaving the one in memory the answer the
        # agent gave, and the checks below would then run on what was replaced.
        if ([bool]$mergeSummary.rewritten) {
            if ([int]$mergeSummary.carriedOver -gt 0 -or [int]$mergeSummary.removed -gt 0) {
                Write-QaFoundryLog -Indent 2 -Scope $AgentId -Message (
                    "Revised $([int]$mergeSummary.revised) file contract(s), carried " +
                    "$([int]$mergeSummary.carriedOver) forward unchanged from the previous " +
                    "iteration and dropped $([int]$mergeSummary.removed) at the revision's " +
                    "request.")
            }
            # Validate every carried contract too. The inventory schema has no
            # total file-count cap: response budgets bound individual calls,
            # and unchanged contracts accumulate without being emitted again.
            $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
                -ArtifactPath $OutputPath `
                -SchemaPath $SchemaPath `
                -SchemaRoot (Join-Path $root "schemas")
            $completed = Get-Content -Path $OutputPath -Raw |
                ConvertFrom-Json -Depth 100
        }
    }
    Assert-AgentArtifactSemantics -Artifact $completed
    return $completed
}

function Invoke-ProviderRequest {
    param(
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$RequestPath,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [int]$Attempt = 1
    )

    if ($Provider -eq "mock") {
        return & (Join-Path $PSScriptRoot "providers/Invoke-MockProvider.ps1") `
            -AgentId $AgentId `
            -StageId $StageId `
            -RunId $RunId `
            -StageIteration $StageIteration `
            -Attempt $Attempt `
            -RequestPath $RequestPath
    }
    if ($Provider -eq "command") {
        return & (Join-Path $PSScriptRoot "providers/Invoke-CommandProvider.ps1") `
            -Command ([string]$Config.ai.command) `
            -RequestPath $RequestPath `
            -TimeoutSeconds $TimeoutSeconds `
            -Model ([string]$Config.ai.model) `
            -ReasoningEffort ([string]$Config.ai.reasoning_effort) `
            -ProviderEnvironment $ProviderEnvironment
    }
    if ($Provider -eq "copilot-cli") {
        if (-not $RepositoryRoot) {
            throw "The copilot-cli provider requires RepositoryRoot."
        }
        return & (Join-Path $PSScriptRoot "providers/Invoke-CopilotCliProvider.ps1") `
            -RequestPath $RequestPath `
            -RepositoryRoot $RepositoryRoot `
            -Model ([string]$Config.ai.model) `
            -ReasoningEffort ([string]$Config.ai.reasoning_effort) `
            -Command ([string]$Config.ai.command) `
            -TimeoutSeconds $TimeoutSeconds `
            -ProviderOptions $Config.ai.provider_options `
            -ProviderEnvironment $ProviderEnvironment `
            -MaxAiCredits $script:ReservedAiCredits `
            -ProgressScope $AgentId
    }
    throw "Unsupported AI provider: $Provider"
}

# Every call is written down, whether or not it produced anything. The record
# sits beside the artifact the call was meant to produce, so a run carries its
# own cost with it and the ledger cannot drift away from the work it describes.
# A provider that can report token counts leaves them in a sidecar beside the
# request; one that cannot leaves nothing, and the record then holds measured
# sizes only rather than an invented number.
function Write-AgentProviderMetadata {
    param(
        [Parameter(Mandatory)][string]$RequestPath,
        [Parameter(Mandatory)][string]$MetadataPath,
        [Parameter(Mandatory)][int]$Attempt,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Purpose,
        [Parameter(Mandatory)][DateTime]$StartedAt,
        [Parameter(Mandatory)][double]$DurationMs,
        [AllowEmptyString()][string]$RequestText = "",
        [AllowEmptyString()][string]$ResponseText = "",
        [AllowEmptyString()][string]$ErrorMessage = ""
    )

    $reported = $null
    $usageSidecar = "$RequestPath.usage.json"
    if (Test-Path -LiteralPath $usageSidecar -PathType Leaf) {
        # A provider that miscounts must not be able to stop a run that already
        # has its answer. The sidecar is advisory, so an unreadable one leaves
        # the record without token counts instead of throwing.
        try { $reported = Get-Content -LiteralPath $usageSidecar -Raw | ConvertFrom-Json -Depth 20 }
        catch {
            Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
                "The provider left usage figures that could not be read, so this call is " +
                "recorded with measured sizes only: $($_.Exception.Message)")
            $reported = $null
        }
    }

    try {
        $null = Write-QaFoundryProviderMetadata `
            -Path $MetadataPath `
            -RunId $RunId -StageId $StageId -AgentId $AgentId `
            -StageIteration $StageIteration -Attempt $Attempt `
            -Provider $Provider `
            -Model ([string]$Config.ai.model) `
            -ReasoningEffort ([string]$Config.ai.reasoning_effort) `
            -Status $Status -Purpose $Purpose `
            -StartedAt $StartedAt -DurationMs $DurationMs `
            -RequestText $RequestText -ResponseText $ResponseText `
            -ProviderUsage $reported -ErrorMessage $ErrorMessage
    }
    catch {
        # Accounting is not the work. Losing a cost record is worth a warning;
        # failing a run that has a valid answer because its receipt could not be
        # filed is not.
        Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
            "This call could not be recorded in the run's cost ledger: $($_.Exception.Message)")
    }
}

# Every call to a provider goes through here, and two things that have to be true
# of all of them were not true of some.
#
# The ledger has to hold one record per call. It held one per schema attempt, so
# the shortening call that follows an otherwise-good answer was invisible - an
# artifact that needed one repair cost two calls and reported one - and a
# provider failure that was neither a timeout nor transient was rethrown before
# anything was written, so the calls that ended a run were the ones missing from
# the account of it.
#
# And the usage sidecar a provider leaves beside its request has to be consumed
# once and then removed. Left in place it is swept into the next agent's context
# as an ordinary JSON artifact, and on a resumed run - which reuses attempt paths
# - the figures from the interrupted call are read back as the cost of the one
# that replaced it.
function Invoke-AgentProviderCall {
    param(
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][string]$RequestPath,
        [Parameter(Mandatory)][AllowEmptyString()][string]$RequestText,
        [Parameter(Mandatory)][string]$MetadataPath,
        [Parameter(Mandatory)][int]$Attempt,
        [ValidateSet("artifact", "field_repair")][string]$Purpose = "artifact",
        [int]$TimeoutSeconds = 0
    )

    $script:ReservedAiCredits = 0
    $reservation = $null
    $budgetRoot = ''
    $budgetHelper = Join-Path $PSScriptRoot 'helpers/call-budget.mjs'
    if ($Provider -ne 'mock' -and $env:QA_FOUNDRY_ADDITIONAL_USD_LIMIT) {
        if ($Provider -ne 'copilot-cli') { throw 'USD budgeting requires the Copilot provider with session credit limits.' }
        $budgetRoot = Split-Path $OutputPath -Parent
        while ($budgetRoot -and -not ((Test-Path (Join-Path $budgetRoot 'workflow-state.json')) -and
            (Test-Path (Join-Path $budgetRoot 'context') -PathType Container))) {
            $parent = Split-Path $budgetRoot -Parent
            if ($parent -eq $budgetRoot) { $budgetRoot = ''; break }
            $budgetRoot = $parent
        }
        if (-not $budgetRoot) { throw 'Cannot locate the run budget; refusing an unaccounted call.' }
        $creditLimit = if ($env:QA_FOUNDRY_CALL_CREDIT_LIMIT) { $env:QA_FOUNDRY_CALL_CREDIT_LIMIT } else { '250' }
        $owner = if ($env:SYSTEM_JOBID) { $env:SYSTEM_JOBID } else { "local-$PID" }
        $reservationText = & node $budgetHelper reserve $budgetRoot $env:QA_FOUNDRY_ADDITIONAL_USD_LIMIT `
            $creditLimit ([string]$Config.ai.model) $owner $MetadataPath 2>&1
        if ($LASTEXITCODE -ne 0) { Stop-QaFoundryForRunBudget -Reason ($reservationText -join "`n") }
        $reservation = ($reservationText -join "`n") | ConvertFrom-Json
        $script:ReservedAiCredits = [int]$reservation.credits
    }
    $usageSidecar = "$RequestPath.usage.json"
    Remove-Item -LiteralPath $usageSidecar -Force -ErrorAction SilentlyContinue

    $startedAt = [DateTime]::UtcNow
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $status = "failed"
    $responseText = ""
    $failure = ""
    $errorRecord = $null
    try {
        $raw = Invoke-ProviderRequest -Provider $Provider -RequestPath $RequestPath `
            -TimeoutSeconds $TimeoutSeconds -Attempt $Attempt
        $stopwatch.Stop()
        $status = "answered"
        $responseText = ($raw -join [Environment]::NewLine).Trim()
    }
    catch {
        $stopwatch.Stop()
        $errorRecord = $_
        $failure = [string]$_.Exception.Message
        $status = if (Test-QaFoundryProviderTimeout -Message $failure) { "timed_out" }
            elseif (Test-QaFoundryProviderTransientFailure -Message $failure) { "faltered" }
            else { "failed" }
    }
    finally {
        # Written whatever happened, and before the sidecar is removed, because
        # the counts are the only part of the record the run cannot measure for
        # itself.
        Write-AgentProviderMetadata -RequestPath $RequestPath -MetadataPath $MetadataPath `
            -Attempt $Attempt -Provider $Provider -Status $status -Purpose $Purpose `
            -StartedAt $startedAt -DurationMs $stopwatch.Elapsed.TotalMilliseconds `
            -RequestText $RequestText -ResponseText $responseText -ErrorMessage $failure
        Remove-Item -LiteralPath $usageSidecar -Force -ErrorAction SilentlyContinue
        if ($null -ne $reservation) {
            $settlement = & node $budgetHelper settle $budgetRoot ([string]$reservation.id) 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Could not settle AI spending; the reservation remains charged: $($settlement -join ' ')" }
            Write-QaFoundryLog -Indent 2 -Scope $AgentId -Message ("AI spending receipt: " + ($settlement -join ' '))
        }
    }

    return [pscustomobject]@{
        status = $status
        responseText = $responseText
        errorMessage = $failure
        errorRecord = $errorRecord
        elapsed = $stopwatch.Elapsed
        durationMs = $stopwatch.Elapsed.TotalMilliseconds
    }
}

# Shortening is only ever safe for prose. The same maxLength keyword also
# guards paths, identifiers, command lines and free-form map values, and a
# shorter path is not a shorter way of saying the same thing: it is a different
# path. Only fields whose whole content is wording appear here, and everything
# else is left to an ordinary retry.
$script:QaFoundryRepairableFields = @(
    "contentContract",
    "instruction",
    "note",
    "purpose",
    "summary"
)

# Some wording is only wording in one place. 'item' and 'reason' are prose
# inside a deferral - what was left out and why it was that one - but nothing
# says another schema cannot use either name for a key, an identifier or a
# command, so they are allowed by where they sit rather than by what they are
# called. Build 972660 lost a leg because a deferral's 'item' came back at 410
# characters against a limit of 400: the repair that exists for exactly that
# stood aside, and a 60 KB answer was written three times over ten characters.
$script:QaFoundryRepairablePointers = @(
    '^/deferrals/\d+/item$',
    '^/deferrals/\d+/reason$'
)
# These are architecture explanations, not arbitrary configuration values or
# commands. Keep the exception tied to this schema and these exact locations.
if ((Split-Path $SchemaPath -Leaf) -eq 'automation-blueprint.schema.json') {
    $script:QaFoundryRepairablePointers += @(
        '^/details/automationProjects/\d+/toolchain/coverageFit/\d+/howItIsMet$',
        '^/details/ciIntegration/(artifactGate|pipelines-api|pipelines-ui)$',
        '^/details/configuration/(apiPreflight|uiPreflight|topicNaming|authorityPolicy)$',
        '^/details/authentication/(api|ui)$',
        '^/details/diagnostics/artifactControls$'
    )
}

# The repair call answers with a few hundred bytes, so it is given a fraction of
# an ordinary attempt. It must never be able to spend a budget that belongs to
# the answer it is correcting.
$script:QaFoundryRepairTimeoutSeconds = 300

# Build 499 lost the run on the fourth of eleven stages because one description
# was 3035 characters against a limit of 3000. The agent shortened it on every
# attempt — 3678, then 3270, then 3035 — regenerating a 65 KB answer each time,
# and ran out of attempts one percent short after twenty minutes. Rewriting an
# entire document to shorten one field is the wrong unit of work: the field is
# what is wrong, so the field is what is asked for again. The answer is a few
# hundred bytes and arrives in seconds, and the patched document is validated
# in full before it is accepted, so nothing is taken on trust.
function Repair-OverlongFields {
    param(
        [Parameter(Mandatory)][object[]]$Errors,
        [Parameter(Mandatory)][string]$ArtifactPath,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][int]$Attempt
    )

    $overlong = @($Errors | Where-Object { [string]$_.keyword -eq "maxLength" })
    if ($overlong.Count -eq 0 -or $overlong.Count -ne @($Errors).Count) { return $null }
    if ($TimeoutSeconds -le 0) { return $null }

    $document = Get-Content -LiteralPath $ArtifactPath -Raw | ConvertFrom-Json -Depth 100
    $requests = @()
    foreach ($error in $overlong) {
        $pointer = [string]$error.instancePath
        # An array element is named by its index, so the field it belongs to is
        # the last segment that is not one.
        $fieldName = @(@($pointer -split "/") |
            Where-Object { $_ -ne "" -and $_ -notmatch '^\d+$' } |
            Select-Object -Last 1)
        $repairable = $fieldName.Count -eq 1 -and
            $script:QaFoundryRepairableFields -contains $fieldName[0]
        if (-not $repairable) {
            $repairable = @($script:QaFoundryRepairablePointers |
                Where-Object { $pointer -match $_ }).Count -gt 0
        }
        if (-not $repairable) { return $null }
        $limit = 0
        if ($null -ne $error.params -and
            (Get-QaFoundryPropertyNames -InputObject $error.params) -contains "limit") {
            $limit = [int]$error.params.limit
        }
        if ($limit -le 0) { return $null }
        $current = Get-QaFoundryPointerValue -Document $document -Pointer $pointer
        if ($current -isnot [string] -or [string]$current -eq "") { return $null }
        if (@($requests | Where-Object { $_.pointer -eq $pointer }).Count -gt 0) { continue }
        $requests += [pscustomobject]@{
            pointer = $pointer
            limit = $limit
            current = [string]$current
        }
    }
    # A field that has to lose more than a third of its text is not overlong by
    # accident, and shortening it that far is a rewrite rather than an edit.
    foreach ($request in $requests) {
        if ($request.current.Length -gt ($request.limit * 1.5)) { return $null }
    }
    # An answer with this many overlong fields is not one that overran: it is one
    # written to a different measure, and the whole of it is worth asking for
    # again. The bound is the one the repair record itself is held to.
    if ($requests.Count -gt 40) { return $null }

    $fieldsText = @(
        foreach ($request in $requests) {
            @"
## $($request.pointer)
Limit: $($request.limit) characters. Yours is $($request.current.Length).

$($request.current)
"@
        }
    ) -join [Environment]::NewLine
    $repairRequest = @"
# Shorten the fields that are over their limit

Your answer was accepted in every respect but one: the fields below are longer
than the schema allows. Nothing else about it is in question, and you are not
being asked to write it again.

Return only the shortened text for each field. Keep every requirement, name and
constraint that is in the current text: shorten by tightening the wording, not
by dropping content. Do not add anything new.
Preserve embedded commands, paths, identifiers and literal values verbatim.
If all requirements cannot fit, return no replacements rather than omit them.

$fieldsText

# Required answer

Emit this JSON object on its own, with no narration around it:

{"replacements":[{"pointer":"<the pointer above>","text":"<the shortened text>"}]}

Every pointer above must appear exactly once, and every text must be at or
under its limit.
"@
    $repairRequestPath = "$ArtifactPath.repair.request.md"
    Set-Content -Path $repairRequestPath -Value $repairRequest -Encoding utf8
    Write-QaFoundryLog -Level step -Indent 2 -Scope $AgentId -Message (
        "Asking for $($requests.Count) overlong field(s) to be shortened, rather than for the " +
        "whole artifact again.")

    $repairCall = Invoke-AgentProviderCall -Provider $Provider -RequestPath $repairRequestPath `
        -RequestText $repairRequest `
        -MetadataPath "$ArtifactPath.attempt-$Attempt.repair.provider-metadata.json" `
        -Attempt $Attempt -Purpose "field_repair" -TimeoutSeconds $TimeoutSeconds
    if ($repairCall.status -ne "answered") {
        # A shortening call is an optimisation over asking for the whole artifact
        # again, so its failure is not the run's failure: the caller falls back
        # to a full retry. The record of the call is written either way, because
        # a call that failed still spent the budget.
        Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
            "The shortening call did not answer: " + $repairCall.errorMessage)
        return $null
    }
    $repairRaw = [string]$repairCall.responseText
    Set-Content -Path "$ArtifactPath.repair.raw.txt" -Value $repairRaw -Encoding utf8

    $replacements = $null
    try {
        $replacements = (ConvertFrom-QaFoundryAgentJson -RawText $repairRaw |
            ConvertFrom-Json -Depth 20).replacements
    }
    catch {
        Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
            "The shortening call did not return usable JSON: " + $_.Exception.Message)
        return $null
    }

    $applied = @()
    # The answer has to be exactly the set of fields that was asked about. An
    # extra pointer means the call went further than it was asked to, and a
    # missing one means it did not go far enough; either way the artifact is not
    # touched and the ordinary retry stands.
    if (@($replacements).Count -ne $requests.Count) {
        Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
            "The shortening call answered about " + @($replacements).Count +
            " field(s) when $($requests.Count) were asked about, so it was discarded.")
        return $null
    }
    foreach ($replacement in @($replacements)) {
        if ($requests.pointer -notcontains [string]$replacement.pointer) {
            Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
                "The shortening call answered about a field that was not in question: " +
                [string]$replacement.pointer)
            return $null
        }
    }
    foreach ($request in $requests) {
        $replacement = @(@($replacements) |
            Where-Object { [string]$_.pointer -eq [string]$request.pointer })
        if ($replacement.Count -ne 1) { return $null }
        $text = $replacement[0].text
        if ($text -isnot [string] -or [string]$text -eq "" -or
            ([string]$text).Length -gt $request.limit) {
            return $null
        }
        if (-not (Set-QaFoundryPointerValue -Document $document -Pointer $request.pointer -Value ([string]$text))) {
            return $null
        }
        $applied += "$($request.pointer) ($($request.current.Length) to $(([string]$text).Length) characters)"
    }

    $document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $ArtifactPath -Encoding utf8
    # What was changed and by how much is kept beside the artifact, so a reader
    # of the evidence can see that the document is not verbatim what the agent
    # first returned without having to read the log.
    [pscustomobject]@{
        artifact = [System.IO.Path]::GetFileName($ArtifactPath)
        shortened = @(
            foreach ($request in $requests) {
                $text = [string](@($replacements) |
                    Where-Object { [string]$_.pointer -eq [string]$request.pointer })[0].text
                [pscustomobject]@{
                    pointer = $request.pointer
                    limit = $request.limit
                    before = $request.current.Length
                    after = $text.Length
                }
            }
        )
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$ArtifactPath.repair.applied.json" -Encoding utf8
    return $applied
}

if ($null -ne $batchAssignment -and $StageIteration -eq 1 -and
    $env:QA_FOUNDRY_RECOVERY_CANDIDATE -and $env:QA_FOUNDRY_RECOVERY_CANDIDATE -ne 'none' -and
    -not (Test-Path -LiteralPath $OutputPath)) {
    . (Join-Path $PSScriptRoot 'RecoveryCandidate.ps1')
    $candidateRoot = Split-Path $OutputPath -Parent
    while ($candidateRoot -and -not ((Test-Path (Join-Path $candidateRoot 'workflow-state.json')) -and
        (Test-Path (Join-Path $candidateRoot 'context') -PathType Container))) {
        $parent = Split-Path $candidateRoot -Parent
        if ($parent -eq $candidateRoot) { $candidateRoot=''; break }
        $candidateRoot=$parent
    }
    if (-not $candidateRoot) { throw 'Cannot locate the run for the operator candidate.' }
    $candidate = Get-QaFoundryRecoveryCandidate -RunRoot $candidateRoot -RunId $RunId -RepositoryRoot $RepositoryRoot
    $candidateBatch = New-QaFoundryRecoveryCandidateBatch -Candidate $candidate -Assignment $batchAssignment `
        -AgentId $AgentId -StageId $StageId -RunId $RunId
    if ($null -ne $candidateBatch) {
        $candidateBatch | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $OutputPath -Encoding utf8
        $null = & (Join-Path $PSScriptRoot 'Validate-JsonArtifact.ps1') -ArtifactPath $OutputPath `
            -SchemaPath $SchemaPath -SchemaRoot (Join-Path $root 'schemas')
        $candidateBatch = Complete-AgentArtifact -Artifact $candidateBatch
        # One source acceptance attempt, zero provider calls. Provenance is in
        # the batch; no fabricated provider receipt or model usage is written.
        @{runId=$RunId;agentId=$AgentId;stageId=$StageId;status='covered';requestedBytes=0;grantedBytes=0;
          attempts=1;reductions=@();deferrals=@()} | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath "$OutputPath.coverage.json" -Encoding utf8
        Write-QaFoundryLog -Indent 2 -Scope $AgentId -Message 'Reused operator recovery source; no provider call. Verification and final review still apply.'
        return $candidateBatch
    }
}

if (Test-Path $OutputPath) {
    if (-not $AllowExistingArtifact) {
        throw "Immutable agent artifact already exists: $OutputPath"
    }

    $reusable = $null
    try {
        $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
            -ArtifactPath $OutputPath `
            -SchemaPath $SchemaPath `
            -SchemaRoot (Join-Path $root "schemas")
        $reusable = Get-Content -Path $OutputPath -Raw | ConvertFrom-Json -Depth 100
        # The artifact reaches disk before the merge and the semantic checks run,
        # so a leg killed in that window leaves a document that passed its schema
        # and nothing else. Walking the rest of the path again here is all that
        # stands between such a file and being carried forward as approved work.
        $reusable = Complete-AgentArtifact -Artifact $reusable
    }
    catch {
        Write-QaFoundryLog -Level "warn" -Indent 2 -Scope $AgentId -Message (
            "Discarding an unusable artifact left by an earlier leg: " + $_.Exception.Message)
        Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
        # The record of a shortening belongs to the document it was applied to.
        # Left behind it would claim a repair for an artifact that no longer
        # exists, which is worse than no record at all.
        Remove-Item -Path "$OutputPath.repair.applied.json" -Force -ErrorAction SilentlyContinue
        $reusable = $null
    }

    if ($null -ne $reusable) {
        # An artifact reaches disk before the record of how complete it is. A leg
        # killed in that window leaves a document that passes its schema and
        # nothing beside it, and a missing coverage record reads everywhere else
        # as "nothing was left out" - which is exactly the claim it was never
        # around to make. The run cannot tell such an artifact from one written
        # under a halved budget, so it does not try: it asks again.
        if (-not (Test-Path -LiteralPath "$OutputPath.coverage.json" -PathType Leaf)) {
            Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
                "Discarding an artifact an earlier leg left without its record of what was left " +
                "out: how complete it is was never written down, so it is being asked again.")
            Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
            Remove-Item -Path "$OutputPath.repair.applied.json" -Force -ErrorAction SilentlyContinue
            $reusable = $null
        }
    }

    if ($null -ne $reusable) {
        # One artifact must not be reused: the one this run kept although it was
        # written under a cut budget and named nothing it had left out. The
        # stage sends the run back here precisely to ask the question again at
        # full scope, and handing back the same document would turn that into a
        # loop that changes nothing and ends in a blocked run.
        $reusedCoveragePath = "$OutputPath.coverage.json"
        if (Test-Path -LiteralPath $reusedCoveragePath -PathType Leaf) {
            $reusedCoverage = $null
            try {
                $reusedCoverage = Get-Content -LiteralPath $reusedCoveragePath -Raw |
                    ConvertFrom-Json -Depth 40
            }
            catch { $reusedCoverage = $null }
            if ($null -ne $reusedCoverage -and
                (Get-QaFoundryPropertyNames -InputObject $reusedCoverage) -contains "deferralsSource" -and
                [string]$reusedCoverage.deferralsSource -eq "run" -and
                (Test-QaFoundryAssignedBatchCoverage -Artifact $reusable -Assignment $batchAssignment)) {
                # An output-size retry does not imply missing files. Delivery is checked
                # against the explicit assignment; source correctness is checked downstream.
                $reusedCoverage.status = 'covered'
                $reusedCoverage.deferrals = @()
                $reusedCoverage.deferralsSource = 'agent'
                $reusedCoverage | ConvertTo-Json -Depth 100 |
                    Set-Content -LiteralPath $reusedCoveragePath -Encoding utf8
                Write-QaFoundryLog -Indent 2 -Scope $AgentId -Message 'Reusing all assigned file bodies; compilation, tests and review remain mandatory.'
            }
            elseif ($null -ne $reusedCoverage -and
                (Get-QaFoundryPropertyNames -InputObject $reusedCoverage) -contains 'deferralsSource' -and
                [string]$reusedCoverage.deferralsSource -eq 'run') {
                Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
                    "Discarding the answer an earlier attempt gave under a reduced budget: it " +
                    "named nothing it had left out, so it is being asked again at full scope.")
                Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $reusedCoveragePath -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$OutputPath.repair.applied.json" -Force -ErrorAction SilentlyContinue
                Remove-Item -Path "$OutputPath.rejections.json" -Force -ErrorAction SilentlyContinue
                # The budget this process starts with is the full one; the only
                # thing that ever lowered it was the rejection record just
                # removed, and the reductions it carried came from the same file.
                $priorAttempts = 0
                $lastValidationError = ""
                $attemptArtifactBytes = $artifactByteBudget
                $scopeReductions.Clear()
                $reusable = $null
            }
        }
    }

    if ($null -ne $reusable) {
        # A usable artifact settles the question that any recorded rejection was
        # about, so the feedback must not outlive it into a later iteration.
        Remove-Item -Path "$OutputPath.rejections.json" -Force -ErrorAction SilentlyContinue
        Write-QaFoundryLog -Indent 2 -Scope $AgentId -Message (
            "Reused the artifact an earlier leg of this run already produced (" +
            (Format-QaFoundryBytes -Bytes ((Get-Item $OutputPath).Length)) + ").")
        return $reusable
    }
}

$executionPolicySection = ""
if ($null -ne $Policy -and
    $Policy.PSObject.Properties.Name -contains "commands" -and
    $null -ne $Policy.commands) {
    $policyExecutables = @($Policy.commands.allowed_executables | ForEach-Object { [string]$_ })
    $policyEnvironment = @($Policy.commands.allowed_environment_variables | ForEach-Object { [string]$_ })
    $policyTimeout = if ($Policy.commands.PSObject.Properties.Name -contains "timeout_seconds") {
        [int]$Policy.commands.timeout_seconds
    }
    else { 0 }
    if ($policyExecutables.Count -gt 0) {
        # Being allowed is not the same as being installed. An agent that cannot
        # tell the difference plans commands that can never run, and spends the
        # stage's one chance at real evidence on them.
        $availableExecutables = [System.Collections.Generic.List[string]]::new()
        $missingExecutables = [System.Collections.Generic.List[string]]::new()
        foreach ($candidate in $policyExecutables) {
            if (Test-QaFoundryExecutableAvailable -Name $candidate) {
                $availableExecutables.Add($candidate)
            }
            else { $missingExecutables.Add($candidate) }
        }
        $availabilityLine = if ($missingExecutables.Count -eq 0) {
            "Every executable above is installed on the machine that will run your commands."
        }
        elseif ($availableExecutables.Count -eq 0) {
            "None of these are installed on the machine that will run your commands, so no command " +
            "in this plan can produce evidence. Say so in your output rather than proposing commands " +
            "that cannot run."
        }
        else {
            "Installed on the machine that will run your commands: " +
            (@($availableExecutables) -join ", ") + ". Allowed but not installed: " +
            (@($missingExecutables) -join ", ") + ". A command naming one of the missing ones fails " +
            "on the machine rather than proving anything, so do not propose it."
        }
        $timeoutLine = if ($policyTimeout -gt 0) {
            "Each command is killed after $policyTimeout seconds, so nothing long-running belongs here."
        }
        else { "" }
        $environmentLine = if ($policyEnvironment.Count -gt 0) {
            "The only environment variables a command may set are: " +
            (@($policyEnvironment) -join ", ") + "."
        }
        else {
            "A command may not set any environment variable."
        }
        $executionPolicySection = @"
# Command execution policy

A deterministic runner executes what you propose, and it refuses anything outside this policy. A
refused command does not run and proves nothing, so proposing one wastes the only chance this stage
has to produce real evidence.

This policy governs the commands you propose in this run, and nothing else. It is not a description
of the product's runtime, of the pipelines the product will own, or of what the delivered system is
permitted to do. A value the product needs at runtime, or a test that can only run against a
deployed service, is outside this list because it is outside this run — not because the design is
wrong. Say what such a step requires and where it belongs; do not treat this list as a constraint on
the architecture.

Only these executables may be named, and the executable is the program itself, never a shell:
$((@($policyExecutables | ForEach-Object { "- $_" })) -join [Environment]::NewLine)

$availabilityLine

$environmentLine Anything else — including harmless-looking telemetry or logging switches — is
refused. Pass such settings as command arguments instead, or leave them out. This restricts what a
command of yours may set here; the environment a deployed service or a separate test pipeline reads
is a matter for the design, not for this list.

$timeoutLine Commands are run without a shell, so pipes, redirection, chaining and globbing do not
work: give the executable and its arguments as separate values.
"@
    }
}

function Invoke-TruncatedBatchRecovery {
    $recovered = & (Join-Path $PSScriptRoot 'Invoke-SplitChangeSetBatch.ps1') `
        -AgentParameters $splitInvocationParameters -AssignmentPath $assignments[0]
    $null = & (Join-Path $PSScriptRoot 'Validate-JsonArtifact.ps1') -ArtifactPath $OutputPath `
        -SchemaPath $SchemaPath -SchemaRoot (Join-Path $root 'schemas')
    $recovered = Complete-AgentArtifact -Artifact $recovered
    Clear-AgentRejection
    return $recovered
}

# A relay handover during a split must resume its completed parts, not repeat the
# oversized parent call. The existing rejection checkpoint records that decision.
if ($null -ne $batchAssignment -and @($batchAssignment.assignedPaths).Count -gt 1 -and
    (Test-QaFoundryTruncationFailure -Message $lastValidationError)) {
    return Invoke-TruncatedBatchRecovery
}

if ($priorAttempts -gt $maxRetries) {
    # Every attempt this stage is allowed has already been spent, across
    # however many legs. Repeating them would burn the rest of the relay on a
    # question that has been answered wrongly as often as the budget permits.
    Clear-AgentRejection
    throw ("Agent $AgentId failed schema validation after $priorAttempts attempt(s) on earlier " +
        "legs of this run: $lastValidationError")
}

# The fields the artifact must carry, so that a fragment of the answer is never
# mistaken for the artifact itself when the agent leaves a partial copy behind.
$artifactRequiredFields = @(Get-QaFoundryArtifactRequiredProperty -SchemaPath $responseSchemaPath)

for ($attempt = $priorAttempts + 1; $attempt -le ($maxRetries + 1); $attempt++) {
    $requestPath = "$OutputPath.attempt-$attempt.request.md"
    $sizeBudgetSection = if ($null -ne $batchAssignment) {
        @"
# Source file output

Return every assigned file with its complete executable body. The $attemptArtifactBytes byte
estimate is a sizing hint, not permission to omit code, assertions, scenarios or file contracts.
Keep explanatory prose short. Do not substitute stubs or ellipses for code. If the assignment
cannot be completed, declare the precise remaining work in deferrals. For repair assignments,
use the supplied existing bodies and change only what the diagnostics require.
"@
    }
    elseif ($attemptArtifactBytes -gt 0) {
        @"
# Output size budget

Your entire answer must not exceed $attemptArtifactBytes bytes, because a longer one is cut off
mid-sentence by the model output limit and is then unusable. Depth of thought is not the same as
length of prose: decide everything the schema asks for, then write it densely. Prefer fewer, larger
decisions over exhaustive enumeration, keep prose fields to a couple of sentences, and drop any
detail a competent implementer can infer. A short, complete, schema-valid object always beats a long
one that never closes.
"@
    }
    else {
        ""
    }
    $request = @"
# Invocation metadata

- Agent ID: $AgentId
- Stage ID: $StageId
- Run ID: $RunId
- Stage iteration: $StageIteration
- Schema retry attempt: $attempt
- Provider: $($Config.ai.provider)
- Model: $($Config.ai.model)
- Reasoning effort: $($Config.ai.reasoning_effort)

$sharedText

$agentPrompt

$sizeBudgetSection

$namingSection

$toolchainSection

$settledToolchainSection

$rationaleSection

$executionPolicySection

$writeScopeSection

$outputFilterSection

$repairScopeSection

# Context manifest

$contextSummary

# Supplied context

$contextText

# Required JSON Schema

$schemaText

# Validation feedback from the previous attempt

$lastValidationError
"@
    Set-Content -Path $requestPath -Value $request -Encoding utf8

    $provider = if ($Config.ai.provider) { [string]$Config.ai.provider } else { "mock" }
    $attemptLabel = if ($maxRetries -gt 0) { " (attempt $attempt of $($maxRetries + 1))" } else { "" }
    # A call that cannot finish before this leg hands over is worse than no call:
    # it spends the rest of the budget and returns nothing. An attempt is
    # therefore bounded by the time that is actually left, and a leg holding too
    # little time for a worthwhile attempt stops on this agent boundary so the
    # next leg repeats the agent with a full budget.
    $configuredTimeout = [int]$Config.ai.timeout_seconds
    $attemptTimeout = $configuredTimeout
    $timeoutLabel = ""
    if ($null -ne $Deadline -and $provider -ne "mock") {
        $usableSeconds = (Get-QaFoundryBudgetSecondsRemaining -Deadline $Deadline) -
            $script:QaFoundryHandoverReserveSeconds
        $minimumAttempt = Get-QaFoundryMinimumAttemptSeconds -ConfiguredTimeout $configuredTimeout `
            -Directory $parent -RunId $RunId -StageId $StageId -Provider $provider `
            -Model ([string]$Config.ai.model) -RequestBytes ([Text.Encoding]::UTF8.GetByteCount($request))
        if ($usableSeconds -lt $minimumAttempt) {
            Stop-QaFoundryForBudget -Reason (
                "stage '$StageId' stopped before attempt $attempt of agent '$AgentId' because " +
                (Format-QaFoundryRemainingBudget -Deadline $Deadline) +
                " is not enough for a worthwhile attempt")
        }
        if ($usableSeconds -lt $attemptTimeout) {
            $attemptTimeout = [int]$usableSeconds
            $timeoutLabel = ", allowed " +
                (Format-QaFoundryDuration ([TimeSpan]::FromSeconds($attemptTimeout))) +
                " by the remaining leg budget"
        }
    }
    Write-QaFoundryLog -Level step -Indent 2 -Scope $AgentId -Message (
        "Calling $provider$attemptLabel, request " +
        (Format-QaFoundryBytes ([long]$request.Length)) +
        ", $referencedCount artifact(s) referenced by path$timeoutLabel.")
    $providerCall = Invoke-AgentProviderCall -Provider $provider -RequestPath $requestPath `
        -RequestText $request `
        -MetadataPath "$OutputPath.attempt-$attempt.provider-metadata.json" `
        -Attempt $attempt -Purpose "artifact" -TimeoutSeconds $attemptTimeout
    if ($providerCall.status -ne "answered") {
        $providerFailure = [string]$providerCall.errorMessage
        # A failure that is neither a timeout nor a passing fault says something
        # is wrong that repeating the call will not put right, so the run stops
        # on it. The record of the call has already been written, which is the
        # part that used to be lost: the calls that ended a run were the ones
        # missing from the account of what it cost.
        if ($providerCall.status -eq "failed") { throw $providerCall.errorRecord }
        if ($providerCall.status -eq "faltered") {
            # No usable answer came back, and nothing is known about how far the
            # request got. There is therefore no feedback to give and nothing in
            # an answer to correct: the same call is simply made again. The wait
            # is jittered so that agents which failed together do not return
            # together and repeat the burst that may have caused it.
            if ($attempt -gt $maxRetries) {
                Write-QaFoundryLog -Level error -Indent 2 -Scope $AgentId -Message (
                    "The provider returned no usable answer $attempt time(s): $providerFailure")
                throw ("Agent $AgentId got no usable answer from its provider after " +
                    "$attempt attempt(s): $providerFailure")
            }
            $backoffSeconds = [Math]::Min(30, 5 * $attempt) + (Get-Random -Minimum 0 -Maximum 4)
            Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
                "The provider returned no usable answer after " +
                (Format-QaFoundryDuration $providerCall.elapsed) +
                "; retrying in $backoffSeconds" + "s. Reported: $providerFailure")
            Start-Sleep -Seconds $backoffSeconds
            continue
        }
        if ($null -ne $batchAssignment) {
            $lastValidationError = "$providerFailure The call timed out. Preserve the entire assigned file scope; use existing source and diagnostics, avoid repeated exploration, and return the complete JSON artifact."
            if ($attempt -gt $maxRetries) {
                Clear-AgentRejection
                throw "Agent $AgentId produced no answer within the time allowed after $attempt attempt(s)."
            }
            Save-AgentRejection -Attempts $attempt -ValidationError $lastValidationError -ArtifactBytes $attemptArtifactBytes
            continue
        }
        # A shorter answer is produced sooner, so the retry asks for less instead
        # of repeating a request that has already proved too slow to finish.
        $attemptArtifactBytes = if ($attemptArtifactBytes -gt 0) {
            [int][Math]::Max(4096, [Math]::Floor($attemptArtifactBytes / 2))
        }
        else { 32768 }
        # Asking for the same scope in fewer words produces a thinner version of
        # everything: every entry vaguer, every description shorter, and no sign
        # of which part was weakened. Asking for fewer entries instead keeps the
        # ones that are delivered complete. What is left out is then named item
        # by item in a field the run reads, not described in prose it does not,
        # so the omission is work the run can still go and do rather than a
        # sentence somebody has to notice.
        Add-ScopeReduction -Attempt $attempt -Cause "no_answer_in_time" `
            -GrantedBytes $attemptArtifactBytes
        $lastValidationError = $providerFailure +
            " Your previous attempt was stopped because it had not produced an answer in the time allowed." +
            " Produce a smaller artifact this time: at most $attemptArtifactBytes bytes in total." +
            " Do not do it by writing less about each item. Decide which items matter most," +
            " cover those to the same depth and detail you would have used anyway, and leave the rest out." +
            " Keep every property the schema requires." +
            $deferralInstruction +
            " Emit the JSON object on its own with no narration around it."
        if ($attempt -gt $maxRetries) {
            Clear-AgentRejection
            Write-QaFoundryLog -Level error -Indent 2 -Scope $AgentId -Message (
                "No answer within the time allowed after $attempt attempt(s).")
            throw "Agent $AgentId produced no answer within the time allowed after $attempt attempt(s)."
        }
        Save-AgentRejection -Attempts $attempt -ValidationError $lastValidationError `
            -ArtifactBytes $attemptArtifactBytes
        Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
            "No answer within " + (Format-QaFoundryDuration $providerCall.elapsed) +
            "; retrying with a smaller budget of $attemptArtifactBytes bytes.")
        continue
    }

    $rawText = [string]$providerCall.responseText
    $rawPath = "$OutputPath.attempt-$attempt.raw.txt"
    Set-Content -Path $rawPath -Value $rawText -Encoding utf8
    Write-QaFoundryLog -Indent 2 -Scope $AgentId -Message (
        "Responded in $(Format-QaFoundryDuration $providerCall.elapsed) with " +
        (Format-QaFoundryBytes ([long]$rawText.Length)) + " of output.")

    try {
        $jsonText = ConvertFrom-QaFoundryAgentJson -RawText $rawText `
            -RequiredProperty $artifactRequiredFields
        $null = $jsonText | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        if ($jsonText.Length -lt $rawText.Length) {
            Write-QaFoundryLog -Indent 2 -Scope $AgentId -Message (
                "Recovered a JSON artifact of " +
                (Format-QaFoundryBytes ([long]$jsonText.Length)) +
                " from surrounding prose.")
        }
        if ($RevisionBasePath) {
            # Validate and repair the small revision before merging it. Otherwise
            # an overlong summary fails inside Apply-BlueprintRevision, before
            # the field repair below can ever see the error.
            $revisionInputPath = "$OutputPath.revision-input.json"
            Set-Content -LiteralPath $revisionInputPath -Value $jsonText -Encoding utf8
            $revisionValidation = & (Join-Path $PSScriptRoot 'Validate-JsonArtifact.ps1') `
                -ArtifactPath $revisionInputPath -SchemaPath $responseSchemaPath `
                -SchemaRoot (Join-Path $root 'schemas') -NoThrow
            if (-not $revisionValidation.valid) {
                $revisionRepairTimeout = $script:QaFoundryRepairTimeoutSeconds
                if ($null -ne $Deadline -and $provider -ne 'mock') {
                    $revisionRepairTimeout = [int][Math]::Min($revisionRepairTimeout,
                        (Get-QaFoundryBudgetSecondsRemaining -Deadline $Deadline) - $script:QaFoundryHandoverReserveSeconds)
                }
                $null = Repair-OverlongFields -Errors @($revisionValidation.errors) `
                    -ArtifactPath $revisionInputPath -Provider $provider -TimeoutSeconds $revisionRepairTimeout -Attempt $attempt
                $null = & (Join-Path $PSScriptRoot 'Validate-JsonArtifact.ps1') `
                    -ArtifactPath $revisionInputPath -SchemaPath $responseSchemaPath -SchemaRoot (Join-Path $root 'schemas')
                $jsonText = Get-Content -LiteralPath $revisionInputPath -Raw
            }
            $revisionJson = $jsonText
            $jsonText = & (Join-Path $PSScriptRoot 'Apply-BlueprintRevision.ps1') -BasePath $RevisionBasePath `
                -RevisionJson $revisionJson -RunId $RunId -StageId $StageId -AgentId $AgentId
            $revisionJson | Set-Content -LiteralPath "$OutputPath.revision.json" -Encoding utf8
        }
        Set-Content -Path $OutputPath -Value $jsonText -Encoding utf8
        $validation = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
            -ArtifactPath $OutputPath `
            -SchemaPath $SchemaPath `
            -SchemaRoot (Join-Path $root "schemas") `
            -NoThrow
        if (-not $validation.valid) {
            # The main call has already spent from the leg, so the repair is
            # bounded by what is left after it, not by what was left before it.
            $repairTimeout = $script:QaFoundryRepairTimeoutSeconds
            if ($null -ne $Deadline -and $provider -ne "mock") {
                $repairTimeout = [int][Math]::Min($repairTimeout,
                    (Get-QaFoundryBudgetSecondsRemaining -Deadline $Deadline) -
                        $script:QaFoundryHandoverReserveSeconds)
            }
            $shortened = Repair-OverlongFields -Errors @($validation.errors) `
                -ArtifactPath $OutputPath -Provider $provider -TimeoutSeconds $repairTimeout `
                -Attempt $attempt
            if ($null -ne $shortened) {
                $validation = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
                    -ArtifactPath $OutputPath `
                    -SchemaPath $SchemaPath `
                    -SchemaRoot (Join-Path $root "schemas") `
                    -NoThrow
                if ($validation.valid) {
                    Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
                        "Accepted after shortening " + (@($shortened) -join "; ") +
                        ". The rest of the answer is the one the agent gave.")
                }
            }
            if (-not $validation.valid) { throw [string]$validation.message }
        }
        $validatedArtifact = Get-Content -Path $OutputPath -Raw |
            ConvertFrom-Json -Depth 100
        $validatedArtifact = Complete-AgentArtifact -Artifact $validatedArtifact
        # Assigned as a statement rather than as the value of an `if`: an empty
        # array returned from a block unrolls to $null on its way out, and every
        # .Count on it then throws under StrictMode.
        $declaredDeferrals = @()
        if ((Get-QaFoundryPropertyNames -InputObject $validatedArtifact) -contains "deferrals") {
            $declaredDeferrals = @($validatedArtifact.deferrals | Where-Object { $null -ne $_ })
        }
        if (-not $RevisionBasePath -and
            -not (Test-QaFoundryAssignedBatchCoverage -Artifact $validatedArtifact -Assignment $batchAssignment) -and
            $scopeReductions.Count -gt 0 -and $declaredDeferrals.Count -eq 0 -and
            [string]$validatedArtifact.status -eq "completed") {
            # The agent was asked for less than the run asked it for, and it has
            # come back saying it finished. Both cannot be true, or at least
            # cannot be shown to be true from here.
            #
            # Asking again is worth one call: an agent that did leave something
            # out will usually say so when told how. Asking repeatedly is not.
            # The first live run spent three attempts of twelve minutes each on
            # this and then failed the whole bootstrap, which is the opposite of
            # what the check is for - and the demand it made, produce it at full
            # scope, is one the agent cannot meet, because the budget it is
            # answering under is the reduced one.
            #
            # So it is asked once, and after that the answer is kept and the
            # coverage recorded as unconfirmed. The stage then reads that as
            # work still open and comes back to it with a full budget, which is
            # the one condition under which a bare 'completed' means anything.
            #
            # "After that" has to exist for any of this to hold. Build 972808
            # resumed a leg on the third attempt of three - two had been
            # rejected before the relay handed over - and the ask landed on the
            # last one there was. There was no attempt left to keep the answer
            # on, so a question the run was willing to take either answer to
            # became the thing that failed the run, after a model call of
            # fourteen minutes. An ask that cannot be answered is not worth
            # spending a good artifact on: with no attempt in hand the answer is
            # kept now, on exactly the terms it would have been kept on later.
            $attemptsLeft = ($maxRetries + 1) - $attempt
            if (-not $deferralNudgeUsed -and $attemptsLeft -gt 0) {
                $deferralNudgeUsed = $true
                throw ("This artifact was produced under a reduced output budget after " +
                    "$($scopeReductions.Count) reduction(s), and reports status 'completed' with an " +
                    "empty 'deferrals' array. If the answer really does cover everything you were " +
                    "asked for, say so again and it will be kept. If it does not, every item you " +
                    "left out belongs in 'deferrals'." + $deferralInstruction)
            }
            if (-not $deferralNudgeUsed) {
                Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
                    "Answered under a reduced budget on the last attempt available, so what it " +
                    "left out was never asked for. The answer is kept and the stage will come " +
                    "back for the work at full scope.")
            }
            $coverageUnconfirmed = $true
            $declaredDeferrals = @([pscustomobject]@{
                kind = "output_budget"
                item = "Everything this stage was asked for, produced again at full scope"
                reason = ("The answer was written under a budget reduced $($scopeReductions.Count) " +
                    "time(s) and named nothing it had left out, so what it covers is not known.")
            })
            Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
                "Answered under a reduced budget and named nothing left out. The answer is kept, " +
                "but the stage will ask for it again at full scope rather than take it as finished.")
        }
        Write-QaFoundryLog -Indent 2 -Scope $AgentId -Message "Artifact accepted against its schema."
        if (-not $RevisionBasePath -and $attemptArtifactBytes -gt 0 -and $jsonText.Length -gt $attemptArtifactBytes) {
            Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
                "Artifact of " + (Format-QaFoundryBytes ([long]$jsonText.Length)) +
                " exceeds the size budget of " + (Format-QaFoundryBytes ([long]$attemptArtifactBytes)) +
                "; it is close to the output limit and may be cut off when revised.")
        }
        if ($narrationEnabled) {
            Write-QaFoundryArtifactNarration -Artifact $validatedArtifact -Scope $AgentId `
                -Indent 3 -MaxItems $narrationMaxItems -MaxLength $narrationMaxLength
        }
        # What the run gave up, written next to what it got. Always written, even
        # when nothing was given up, because a missing file is then a defect in
        # this script rather than an agent that happened to lose nothing.
        [ordered]@{
            runId = $RunId
            agentId = $AgentId
            stageId = $StageId
            status = if ($declaredDeferrals.Count -gt 0) { "deferred" } else { "covered" }
            requestedBytes = [int]$artifactByteBudget
            grantedBytes = [int]$attemptArtifactBytes
            attempts = $attempt
            reductions = @($scopeReductions)
            deferrals = @($declaredDeferrals | ForEach-Object {
                [ordered]@{
                    item = [string]$_.item; reason = [string]$_.reason
                    kind = if ($_.PSObject.Properties['kind']) { [string]$_.kind } else { 'unclassified' }
                }
            })
            deferralsSource = if ($coverageUnconfirmed) { "run" } else { "agent" }
        } | ConvertTo-Json -Depth 100 | Set-Content -Path "$OutputPath.coverage.json" -Encoding utf8
        $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
            -ArtifactPath "$OutputPath.coverage.json" `
            -SchemaPath (Join-Path $root "schemas/runtime/agent-coverage.schema.json") `
            -SchemaRoot (Join-Path $root "schemas")
        if ($declaredDeferrals.Count -gt 0 -and -not $coverageUnconfirmed) {
            Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
                "Declared $($declaredDeferrals.Count) required item(s) " +
                "undone: " + ((@($declaredDeferrals | Select-Object -First 5 |
                    ForEach-Object { [string]$_.item }) -join "; ")) +
                ". The stage is not finished while they stand.")
        }
        Clear-AgentRejection
        return $validatedArtifact
    }
    catch {
        $lastValidationError = $_.Exception.Message
        if ($null -ne $batchAssignment -and (Test-QaFoundryTruncationFailure -Message $lastValidationError)) {
            if (@($batchAssignment.assignedPaths).Count -gt 1) {
                Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
                Save-AgentRejection -Attempts $attempt -ValidationError $lastValidationError `
                    -ArtifactBytes $attemptArtifactBytes
                return Invoke-TruncatedBatchRecovery
            }
            $lastValidationError += ' The JSON was cut off. Return every assigned file in full with concise explanatory fields and compact JSON. Do not remove executable code or weaken tests to fit a size hint. Declare any unfinished work explicitly.'
        }
        elseif (Test-QaFoundryTruncationFailure -Message $lastValidationError) {
            # Repeating the schema errors here would send the agent back to write
            # the same oversized document again, which is what it just failed at.
            $attemptArtifactBytes = if ($attemptArtifactBytes -gt 0) {
                [int][Math]::Max(4096, [Math]::Floor($attemptArtifactBytes / 2))
            }
            else {
                [int][Math]::Max(4096, [Math]::Floor($rawText.Length / 4))
            }
            $lastValidationError = $lastValidationError +
                " Your previous answer was cut off by the model output limit before the JSON object closed." +
                " Produce a smaller artifact this time: at most $attemptArtifactBytes bytes in total." +
                " Do not do it by writing less about each item. Decide which items matter most," +
                " cover those to the same depth and detail you would have used anyway, and leave the rest out," +
                " so the complete object fits well inside that budget." +
                " Keep every property the schema requires." +
                $deferralInstruction +
                " Emit the JSON object on its own, with no narration around it."
            Add-ScopeReduction -Attempt $attempt -Cause "answer_cut_off" `
                -GrantedBytes $attemptArtifactBytes
        }
        Remove-Item -Path $OutputPath -Force -ErrorAction SilentlyContinue
        # A shortening that was applied and then rejected did not happen as far
        # as the evidence is concerned, so its record goes with the document.
        Remove-Item -Path "$OutputPath.repair.applied.json" -Force -ErrorAction SilentlyContinue
        if ($attempt -gt $maxRetries) {
            Clear-AgentRejection
            Write-QaFoundryLog -Level error -Indent 2 -Scope $AgentId -Message (
                "Rejected after $attempt attempt(s): $lastValidationError")
            throw "Agent $AgentId failed schema validation after $attempt attempt(s): $lastValidationError"
        }
        # Recorded before the next attempt, not after it, because the leg may not
        # live long enough to make one.
        Save-AgentRejection -Attempts $attempt -ValidationError $lastValidationError `
            -ArtifactBytes $attemptArtifactBytes
        Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message (
            "Rejected, retrying with feedback: $lastValidationError")
    }
}
