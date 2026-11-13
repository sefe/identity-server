# Carries the unchanged part of an inventory forward between iterations.
#
# Build 453 spent 39 minutes on a single revision because the agent re-emitted
# all 38 planned files while stating in its own summary that "every path is
# identical to iteration 1". That cost a truncated 242 KB answer, a second full
# attempt, and a request that grew with every round until it stopped fitting in
# the time allowed.
#
# A revision therefore restates only what it changes. What it does not mention
# is carried forward from the previous iteration, byte for byte, and a file
# leaves the inventory only when the revision says so in removedFiles. The
# earlier rule was the other way round: a path not named anywhere simply
# vanished, and only a dependsOn still pointing at it would say so, which meant
# a file nothing imports could be dropped without a word. Silence now keeps a
# file rather than deleting it, so forgetting cannot cost a file, and deleting
# one is a decision the artifact records.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ArtifactPath,
    [Parameter(Mandatory)][string]$PreviousArtifactPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Common.ps1")

function ConvertTo-InventoryKey {
    param([AllowNull()][object]$Value)
    return ([string]$Value).Replace("\", "/").Trim()
}

# Git tells NuGet.Config from NuGet.config, and a hashtable literal does not:
# every ordered dictionary in PowerShell compares keys without regard to case.
# Build 973259 lost leg 2 to that. An agent asked to drop NuGet.Config and
# write NuGet.config -- the spelling the approved commands pass to --configfile
# -- was told the same path was in two lists at once, which is not what it had
# written, so it could not act on the complaint and spent all three attempts
# rewriting the same answer. Paths are therefore compared exactly, and the
# spellings that differ only in case are reported as what they are.
function New-InventoryPathSet {
    param([string[]]$Path)
    $set = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($value in @($Path)) {
        if (-not [string]::IsNullOrWhiteSpace($value)) { $null = $set.Add([string]$value) }
    }
    return ,$set
}

# Now that paths are matched exactly, a spelling that differs only in case is
# the most likely mistake, and naming the spelling on record turns "no earlier
# iteration planned this" into something the agent can act on in one attempt.
function Get-CaseHint {
    param([Parameter(Mandatory)][string]$Path, [string[]]$Known)
    $match = @($Known | Where-Object { $_ -and $_.Equals($Path, [StringComparison]::OrdinalIgnoreCase) })
    if ($match.Count -eq 0) { return "" }
    return " (the inventory spells it $($match[0]))"
}

function Get-InventoryIndex {
    param([AllowNull()][object]$Inventory)
    $index = [System.Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    if ($null -eq $Inventory) { return $index }
    if ((Get-QaFoundryPropertyNames -InputObject $Inventory) -notcontains "plannedFiles") { return $index }
    foreach ($entry in @($Inventory.plannedFiles)) {
        if ($null -eq $entry) { continue }
        $key = ConvertTo-InventoryKey -Value $entry.path
        if ([string]::IsNullOrWhiteSpace($key)) { continue }
        $index[$key] = $entry
    }
    return $index
}

# CR2-03 in build 453: a revision deleted an entry but kept the dependsOn that
# entry existed to satisfy, and it cost a full review round to notice. Only a
# reference the previous iteration could satisfy and this one no longer can is
# reported, so a dependsOn naming another agent's inventory is never mistaken
# for a broken one.
function Assert-NoDroppedDependency {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Inventory,
        [Parameter(Mandatory)][object]$PreviousIndex
    )
    $currentIndex = Get-InventoryIndex -Inventory $Inventory
    $dangling = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in @($Inventory.plannedFiles)) {
        if ($null -eq $entry) { continue }
        if ((Get-QaFoundryPropertyNames -InputObject $entry) -notcontains "dependsOn") { continue }
        foreach ($dependency in @($entry.dependsOn)) {
            $key = ConvertTo-InventoryKey -Value $dependency
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if ($currentIndex.Contains($key)) { continue }
            if (-not $PreviousIndex.Contains($key)) { continue }
            $dangling.Add("$(ConvertTo-InventoryKey -Value $entry.path) -> $key")
        }
    }
    if ($dangling.Count -gt 0) {
        throw ("This revision drops files that other entries still depend on: " +
            (($dangling | Select-Object -Unique) -join "; ") +
            ". Either keep the dropped file, list it under unchangedFiles, or remove the " +
            "dependsOn together with whatever it was supporting.")
    }
}

$artifact = Get-Content -LiteralPath $ArtifactPath -Raw | ConvertFrom-Json -Depth 100
if ($null -eq $artifact -or
    (Get-QaFoundryPropertyNames -InputObject $artifact) -notcontains "plannedFiles") {
    return [pscustomobject]@{ carriedOver = 0; revised = 0 }
}

$previous = Get-Content -LiteralPath $PreviousArtifactPath -Raw | ConvertFrom-Json -Depth 100
$previousByPath = Get-InventoryIndex -Inventory $previous

$declared = @()
if ((Get-QaFoundryPropertyNames -InputObject $artifact) -contains "unchangedFiles") {
    $declared = @(@($artifact.unchangedFiles) |
        ForEach-Object { ConvertTo-InventoryKey -Value $_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
$removed = @()
if ((Get-QaFoundryPropertyNames -InputObject $artifact) -contains "removedFiles") {
    $removed = @(@($artifact.removedFiles) |
        ForEach-Object { ConvertTo-InventoryKey -Value $_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$revisedByPath = Get-InventoryIndex -Inventory $artifact
$declaredSet = New-InventoryPathSet -Path $declared

# Two entries whose paths differ only in case are one file on Windows and macOS
# checkouts and two on Linux, so an inventory carrying both cannot be built
# anywhere consistently.
$plannedSpellings = @($revisedByPath.Keys)
$caseCollisions = @($plannedSpellings |
    Group-Object -Property { $_.ToLowerInvariant() } |
    Where-Object { @($_.Group).Count -gt 1 } |
    ForEach-Object { (@($_.Group) -join " and ") })
if ($caseCollisions.Count -gt 0) {
    throw ("These planned paths differ only in case: " + ($caseCollisions -join "; ") +
        ". A checkout that ignores case holds one file for both, so pick one spelling.")
}

# A path claimed as unchanged and also restated is a contradiction about which
# of the two versions the run should build, so it is refused rather than guessed.
$contradictions = @($declared | Where-Object { $revisedByPath.Contains($_) })
if ($contradictions.Count -gt 0) {
    throw ("These paths are listed in both plannedFiles and unchangedFiles: " +
        (($contradictions | Select-Object -Unique) -join ", ") +
        ". List a file in exactly one of them: restate it only when its contract changes.")
}

# Restating a file and removing it in the same answer says two opposite things
# about whether the run should build it, and neither is safe to pick.
$restatedAndRemoved = @($removed | Where-Object { $revisedByPath.Contains($_) })
if ($restatedAndRemoved.Count -gt 0) {
    throw ("These paths are listed in both plannedFiles and removedFiles: " +
        (($restatedAndRemoved | Select-Object -Unique) -join ", ") +
        ". A file is either specified or dropped, not both.")
}
$carriedAndRemoved = @($removed | Where-Object { $declaredSet.Contains($_) })
if ($carriedAndRemoved.Count -gt 0) {
    throw ("These paths are listed in both unchangedFiles and removedFiles: " +
        (($carriedAndRemoved | Select-Object -Unique) -join ", ") +
        ". A file is either carried forward or dropped, not both.")
}

$unknown = @($declared | Where-Object { -not $previousByPath.Contains($_) })
if ($unknown.Count -gt 0) {
    throw ("These paths are named in unchangedFiles but no earlier iteration planned them: " +
        (($unknown | Select-Object -Unique |
            ForEach-Object { $_ + (Get-CaseHint -Path $_ -Known @($previousByPath.Keys)) }) -join ", ") +
        ". Only a file the previous iteration already specified may be carried forward unchanged; " +
        "state a new file in full under plannedFiles.")
}

# Removing something the run never planned is not a removal but a mistaken
# path, and acting on it would leave the file it meant still in the inventory.
$unknownRemoved = @($removed | Where-Object { -not $previousByPath.Contains($_) })
if ($unknownRemoved.Count -gt 0) {
    throw ("These paths are named in removedFiles but no earlier iteration planned them: " +
        (($unknownRemoved | Select-Object -Unique |
            ForEach-Object { $_ + (Get-CaseHint -Path $_ -Known @($previousByPath.Keys)) }) -join ", ") +
        ". Only a file the previous iteration specified can be dropped from the inventory.")
}

# A removal that has already been applied has to stay visible in the artifact.
# The instruction lists are stripped after a merge, so a leg killed between the
# rewrite and the end of the stage would leave the next leg reading the same
# artifact with nothing left saying the file was dropped on purpose: silence
# means "keep", and the deleted file would come back from the previous
# inventory. The applied removals are therefore recorded rather than forgotten.
$alreadyRemoved = @()
if ((Get-QaFoundryPropertyNames -InputObject $artifact) -contains "mergedRemovals") {
    $alreadyRemoved = @(@($artifact.mergedRemovals) |
        ForEach-Object { ConvertTo-InventoryKey -Value $_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

# Everything the previous iteration approved and this one neither restated nor
# dropped is carried forward whether or not it was named. Naming it in
# unchangedFiles is still accepted, because older prompts and artifacts do so,
# but it is no longer what keeps the file alive.
$carried = 0
$removedSet = New-InventoryPathSet -Path (@($removed) + @($alreadyRemoved))
$merged = [System.Collections.Generic.List[object]]::new()
foreach ($entry in @($artifact.plannedFiles)) {
    if ($null -ne $entry) { $merged.Add($entry) }
}
foreach ($key in $previousByPath.Keys) {
    if ($revisedByPath.Contains($key)) { continue }
    if ($removedSet.Contains($key)) { continue }
    $merged.Add($previousByPath[$key])
    $carried++
}
if ($carried -gt 0 -or $removedSet.Count -gt 0) {
    $artifact.plannedFiles = @($merged | Sort-Object { ConvertTo-InventoryKey -Value $_.path })
}

# The consistency check runs whether or not anything was carried forward: a
# revision that simply drops an entry is the case that cost build 453 a round.
Assert-NoDroppedDependency -Inventory $artifact -PreviousIndex $previousByPath

# The lists are instructions to this merge, not part of the inventory it
# produces, and leaving them in would let a later merge act on them twice.
$rewritten = $false
foreach ($listName in @("unchangedFiles", "removedFiles")) {
    if ((Get-QaFoundryPropertyNames -InputObject $artifact) -contains $listName) {
        $artifact.PSObject.Properties.Remove($listName)
        $rewritten = $true
    }
}
$tombstone = @(@($removed) + @($alreadyRemoved) | Sort-Object -Unique -CaseSensitive)
if (($tombstone -join "`n") -ne (@($alreadyRemoved | Sort-Object -Unique -CaseSensitive) -join "`n")) {
    $rewritten = $true
}
if ($tombstone.Count -gt 0) {
    if ((Get-QaFoundryPropertyNames -InputObject $artifact) -contains "mergedRemovals") {
        $artifact.mergedRemovals = $tombstone
    }
    else {
        $artifact | Add-Member -NotePropertyName "mergedRemovals" -NotePropertyValue $tombstone
    }
}
if ($carried -gt 0) { $rewritten = $true }
if ($rewritten) {
    $json = $artifact | ConvertTo-Json -Depth 100
    Set-Content -LiteralPath $ArtifactPath -Value $json -Encoding utf8
}

return [pscustomobject]@{
    carriedOver = $carried
    revised = $revisedByPath.Count
    removed = $removedSet.Count
    rewritten = $rewritten
}
