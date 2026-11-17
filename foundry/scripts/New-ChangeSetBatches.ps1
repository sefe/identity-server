# Cuts the approved file inventory into batches a model can actually answer.
#
# Build 475 spent five relay legs and 170 minutes on one stage. The generator was
# asked for the bodies of 47 approved files in a single JSON object; every call
# was cut off by the model output limit before the object closed, so nine calls
# in a row produced nothing at all. Asking the model to "be shorter" does not
# help, because the work is not compressible: the files are the deliverable.
#
# So the runtime decides the split rather than the model. The inventory is
# already approved by the implementation stages, which means the set of paths is
# not a judgement call and does not need a model to restate it. Each batch is a
# named, bounded assignment, and a batch that is answered stays answered: its
# artifact survives the relay handover like any other.

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$InventoryPaths,
    [int]$TargetBatchBytes = 36864,
    [int]$MaxFilesPerBatch = 6,
    # A revision that only has to repair named files batches only those files.
    # Everything else in the approved inventory is carried forward from the plan
    # the review rejected, so the split covers the repair rather than the tree.
    [string[]]$RegeneratePaths = @()
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common.ps1")

# A lock file records the exact version, origin URL and content hash of every
# package in the tree, so it can only come from a resolver. Both change-item.schema.json
# and the apply action refuse one written as literal content. The inventory
# stages still list it, because the file does belong in the delivered tree, and
# in build 478 the slicer duly assigned it to a batch. The generator was then
# holding an assignment it could not satisfy without breaking the schema, and
# correctly refused the whole batch, which stopped the run at stage 9. So the
# split leaves lock files out and lets the materialisation planner name the
# manifest to resolve instead. The names come from the ecosystem adapters, so
# an installation that gains an adapter gains its lock file here without anyone
# remembering to add it; a test asserts the change contract still refuses the
# same set.
$script:ResolverOwnedPathPattern = Get-QaFoundryResolverOwnedPathPattern

if ($TargetBatchBytes -lt 4096) {
    throw "A batch budget of $TargetBatchBytes bytes is too small to hold a single authored file."
}
if ($MaxFilesPerBatch -lt 1) {
    throw "A batch must be allowed at least one file."
}

# The contract is the only description of the file that exists before it is
# written, so it is the only honest basis for an estimate. It is a summary
# rather than the text, so the multiplier is deliberately generous: a batch that
# comes back smaller than planned costs nothing, and one that comes back larger
# costs the whole call.
function Get-EstimatedBytes {
    param([Parameter(Mandatory)][object]$PlannedFile)
    $contract = ""
    foreach ($name in @("contentContract", "purpose")) {
        if ($PlannedFile.PSObject.Properties.Name -contains $name) {
            $contract += [string]$PlannedFile.$name
        }
    }
    $estimate = 1024 + ($contract.Length * 4)
    return [int][Math]::Min($estimate, 24576)
}

# Tarjan's algorithm, written iteratively because a recursive version would
# blow the PowerShell call stack on a deep import chain. Returned in reverse
# topological order, and each component's members sorted by path, so the split
# is the same on every leg that recomputes it.
function Get-StronglyConnectedComponents {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Nodes,
        [Parameter(Mandatory)][hashtable]$Edges
    )

    $index = @{}
    $lowLink = @{}
    $onStack = @{}
    $stack = [System.Collections.Generic.List[string]]::new()
    $components = [System.Collections.Generic.List[object]]::new()
    $nextIndex = 0

    foreach ($start in $Nodes) {
        if ($index.ContainsKey($start)) { continue }
        $work = [System.Collections.Generic.List[object]]::new()
        $work.Add([pscustomobject]@{ node = $start; edge = 0 })
        while ($work.Count -gt 0) {
            $frame = $work[$work.Count - 1]
            $node = [string]$frame.node
            if ($frame.edge -eq 0) {
                $index[$node] = $nextIndex
                $lowLink[$node] = $nextIndex
                $nextIndex++
                $stack.Add($node)
                $onStack[$node] = $true
            }
            $neighbours = @($Edges[$node])
            $descended = $false
            while ($frame.edge -lt $neighbours.Count) {
                $neighbour = [string]$neighbours[$frame.edge]
                $frame.edge = $frame.edge + 1
                if (-not $index.ContainsKey($neighbour)) {
                    $work.Add([pscustomobject]@{ node = $neighbour; edge = 0 })
                    $descended = $true
                    break
                }
                if ($onStack.ContainsKey($neighbour)) {
                    $lowLink[$node] = [Math]::Min([int]$lowLink[$node], [int]$index[$neighbour])
                }
            }
            if ($descended) { continue }
            if ([int]$lowLink[$node] -eq [int]$index[$node]) {
                $member = [System.Collections.Generic.List[string]]::new()
                while ($true) {
                    $popped = [string]$stack[$stack.Count - 1]
                    $stack.RemoveAt($stack.Count - 1)
                    $onStack.Remove($popped)
                    $member.Add($popped)
                    if ($popped -eq $node) { break }
                }
                $components.Add(@($member | Sort-Object))
            }
            $work.RemoveAt($work.Count - 1)
            if ($work.Count -gt 0) {
                $parent = [string]$work[$work.Count - 1].node
                $lowLink[$parent] = [Math]::Min([int]$lowLink[$parent], [int]$lowLink[$node])
            }
        }
    }
    return @($components)
}

$planned = [System.Collections.Generic.List[object]]::new()
$seen = @{}
foreach ($inventoryPath in @($InventoryPaths)) {
    if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) {
        throw "Inventory artifact does not exist: $inventoryPath"
    }
    $inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json -Depth 100
    if ($inventory.PSObject.Properties.Name -notcontains "plannedFiles") {
        continue
    }
    foreach ($file in @($inventory.plannedFiles)) {
        $path = if ($file.PSObject.Properties.Name -contains "path") { [string]$file.path } else { "" }
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        $normalised = $path.Replace("\", "/").Trim()
        # Two inventories may legitimately name the same file; the later one
        # wins, because the run carried it forward on purpose. Silently emitting
        # it twice would make the merge refuse a plan that is in fact correct.
        # What is not acceptable is doing it quietly when the two disagree: the
        # file is then delivered to one inventory's contract while the other
        # inventory, and the review that approved it, expect the other.
        if ($seen.ContainsKey($normalised)) {
            $existing = $planned[$seen[$normalised]]
            $existingContract = if (@(Get-QaFoundryPropertyNames -InputObject $existing.file) -contains
                "contentContract") {
                [string]$existing.file.contentContract
            }
            else { "" }
            $incomingContract = if (@(Get-QaFoundryPropertyNames -InputObject $file) -contains
                "contentContract") {
                [string]$file.contentContract
            }
            else { "" }
            if ($existingContract -ne $incomingContract) {
                # A warning would reach the operator and nobody else: the
                # generator and the reviewers would still be handed one contract
                # while the other inventory, and the review that approved it,
                # expect the other. The inventories of build 499 named
                # thirty-seven files and no path twice, so this is a defect in
                # the inventory rather than a case the run has to carry.
                throw ("$normalised is specified in both " +
                    "$(Split-Path $existing.source -Leaf) and " +
                    "$(Split-Path $inventoryPath -Leaf), and the two contracts do not agree. " +
                    "One file cannot be written to two specifications, and choosing between " +
                    "them is not the runtime's to make.")
            }
            $planned[$seen[$normalised]] = [pscustomobject]@{
                path = $normalised
                file = $file
                source = $inventoryPath
            }
            continue
        }
        $seen[$normalised] = $planned.Count
        $planned.Add([pscustomobject]@{
            path = $normalised
            file = $file
            source = $inventoryPath
        })
    }
}

if ($planned.Count -eq 0) {
    throw "The approved inventory names no files, so there is nothing to generate."
}

# A dependency on a file the inventory does not name has no owner, no layer and
# no final text to be shown to the batch that imports it. Skipping it quietly
# does not merely reorder the work: the edge disappears, the consumer is
# generated without ever being shown the provider it builds on, and it invents
# the interface instead. Nothing downstream reads imports, so that invention
# survives the merge and the review of file lists. The inventories of build 499
# named thirty-seven files and carried no unknown dependency, so this is a
# defect in the inventory rather than a case the run has to carry.
$plannedPathSet = @{}
foreach ($entry in $planned) { $plannedPathSet[$entry.path.ToLowerInvariant()] = $true }
$danglingDependencies = @(
    foreach ($entry in $planned) {
        $entryNames = @(Get-QaFoundryPropertyNames -InputObject $entry.file)
        if ($entryNames -notcontains "dependsOn") { continue }
        foreach ($dependency in @($entry.file.dependsOn)) {
            $dependencyPath = ([string]$dependency).Replace("\", "/").Trim()
            if (-not $dependencyPath) { continue }
            if ($plannedPathSet.ContainsKey($dependencyPath.ToLowerInvariant())) { continue }
            "$($entry.path) depends on $dependencyPath"
        }
    }
)
if ($danglingDependencies.Count -gt 0) {
    throw ("The approved inventory names dependencies on files it does not plan: " +
        (($danglingDependencies | Sort-Object -Unique) -join "; ") +
        ". Nothing writes those files, so whatever builds on them would be written " +
        "without ever seeing them.")
}

$resolverOwned = @($planned | Where-Object { $_.path -imatch $script:ResolverOwnedPathPattern })
$authored = @($planned | Where-Object { $_.path -inotmatch $script:ResolverOwnedPathPattern })

if ($authored.Count -eq 0) {
    throw ("The approved inventory names only files a resolver owns (" +
        (@($resolverOwned | ForEach-Object { $_.path }) -join ", ") +
        "), so there is no file content to generate.")
}

# Sorted by path, so files that live together are assigned together. A shared
# helper and the specs that import it then tend to land in one call, which is
# the cheapest way to keep them consistent without paying to resend the bodies.
$approved = @($authored | Sort-Object -Property path)
$approvedPaths = @($approved | ForEach-Object { $_.path })

$requested = @($RegeneratePaths | ForEach-Object { ([string]$_).Replace("\", "/").Trim() } |
    Where-Object { $_ } | Sort-Object -Unique)
if ($requested.Count -gt 0) {
    $unknown = @($requested | Where-Object { $approvedPaths -notcontains $_ })
    if ($unknown.Count -gt 0) {
        throw ("The repair names $($unknown.Count) path(s) that are not in the approved inventory: " +
            (@($unknown) -join ", ") +
            ". A file the run never approved cannot be regenerated, and treating the request as " +
            "the whole tree would hide the mistake behind an hour of work.")
    }
    $ordered = @($approved | Where-Object { $requested -contains $_.path })
}
else {
    $ordered = @($approved)
}

# Alphabetical order is not dependency order, and build 496 paid for the
# difference: the specs sorted into batches 01-04 and the helpers they import
# into 05-07, so every spec was written against a helper that did not exist
# yet and the reviewers correctly called the mismatched imports critical.
#
# The inventory already states the relation. Each planned file may name the
# files it dependsOn, so the split follows that graph instead: a file sits one
# layer below the deepest file it depends on, batches never mix layers, and a
# batch is told which earlier batches wrote the files it builds on. Layer zero
# is therefore the foundation, and everything above it is written with the
# real text of what it imports rather than a guess at it.
#
# Only edges inside the approved set count. A dependency on a file no stage
# planned is either an external package or a mistake, and neither can be
# ordered against.
$pathIndex = @{}
foreach ($entry in $ordered) { $pathIndex[$entry.path] = $true }

$dependencies = @{}
foreach ($entry in $ordered) {
    $edges = [System.Collections.Generic.List[string]]::new()
    if ((Get-QaFoundryPropertyNames -InputObject $entry.file) -contains "dependsOn") {
        foreach ($dependency in @($entry.file.dependsOn)) {
            $normalised = ([string]$dependency).Replace("\", "/").Trim()
            if ([string]::IsNullOrWhiteSpace($normalised)) { continue }
            if ($normalised -eq $entry.path) { continue }
            if (-not $pathIndex.ContainsKey($normalised)) { continue }
            if ($edges.Contains($normalised)) { continue }
            $edges.Add($normalised)
        }
    }
    $dependencies[$entry.path] = @($edges)
}

# Kahn's algorithm over strongly connected components rather than over files.
# Two files that import each other cannot be ordered against one another, and
# putting them in separate batches of the same layer would let them be written
# in parallel against a guess at each other, which is the failure the layering
# exists to prevent. So a cycle collapses into one component and one batch.
$components = @(Get-StronglyConnectedComponents -Nodes @($ordered | ForEach-Object { $_.path }) `
    -Edges $dependencies)
$componentOf = @{}
for ($componentIndex = 0; $componentIndex -lt $components.Count; $componentIndex++) {
    foreach ($path in $components[$componentIndex]) { $componentOf[$path] = $componentIndex }
}
$componentEdges = @{}
for ($componentIndex = 0; $componentIndex -lt $components.Count; $componentIndex++) {
    $componentEdges[$componentIndex] = [System.Collections.Generic.List[int]]::new()
}
foreach ($entry in $ordered) {
    $from = [int]$componentOf[$entry.path]
    foreach ($dependency in $dependencies[$entry.path]) {
        $to = [int]$componentOf[$dependency]
        if ($to -eq $from) { continue }
        if ($componentEdges[$from].Contains($to)) { continue }
        $componentEdges[$from].Add($to)
    }
}

$componentLayer = @{}
$remaining = @{}
for ($componentIndex = 0; $componentIndex -lt $components.Count; $componentIndex++) {
    $remaining[$componentIndex] = $true
}
$layerNumber = 0
while ($remaining.Count -gt 0) {
    $ready = @(
        foreach ($componentIndex in @($remaining.Keys | Sort-Object)) {
            $blocked = $false
            foreach ($dependency in $componentEdges[$componentIndex]) {
                if ($remaining.ContainsKey($dependency)) { $blocked = $true; break }
            }
            if (-not $blocked) { $componentIndex }
        }
    )
    # The condensation of a graph is acyclic by construction, so this cannot
    # happen; it is guarded anyway, because an empty ready set here would spin
    # the loop forever and take the run with it.
    if ($ready.Count -eq 0) { $ready = @($remaining.Keys | Sort-Object) }
    foreach ($componentIndex in $ready) {
        $componentLayer[$componentIndex] = $layerNumber
        $remaining.Remove($componentIndex)
    }
    $layerNumber++
}

$batches = [System.Collections.Generic.List[object]]::new()
$current = [System.Collections.Generic.List[object]]::new()
$currentBytes = 0

function Add-Batch {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Files,
        [Parameter(Mandatory)][int]$Layer
    )
    if ($Files.Count -eq 0) { return }
    $ordinal = $batches.Count + 1
    $batches.Add([pscustomobject]@{
        batchId = "batch-{0:d2}" -f $ordinal
        ordinal = $ordinal
        layer = $Layer
        estimatedBytes = [int](@($Files | ForEach-Object { $_.estimatedBytes }) | Measure-Object -Sum).Sum
        files = @($Files)
    })
}

# Packed layer by layer, and inside a layer component by component. A batch
# never spans two layers, because the whole point of the layer is that
# everything in it can be written at the same time against text that is
# already final. A component is never split, because its members can only be
# written against each other.
foreach ($layer in @(0..($layerNumber - 1))) {
    $layerComponents = @(
        foreach ($componentIndex in @(0..($components.Count - 1))) {
            if ([int]$componentLayer[$componentIndex] -ne $layer) { continue }
            [pscustomobject]@{
                index = $componentIndex
                paths = @($components[$componentIndex])
                sortKey = [string](@($components[$componentIndex])[0])
            }
        }
    )
    if ($layerComponents.Count -eq 0) { continue }
    $current = [System.Collections.Generic.List[object]]::new()
    $currentBytes = 0
    foreach ($component in @($layerComponents | Sort-Object -Property sortKey)) {
        $records = @(
            foreach ($path in $component.paths) {
                $entry = @($ordered | Where-Object { $_.path -eq $path })[0]
                [pscustomobject]@{
                    path = $entry.path
                    estimatedBytes = (Get-EstimatedBytes -PlannedFile $entry.file)
                    plannedFile = $entry.file
                }
            }
        )
        $componentBytes = [int](@($records | ForEach-Object { $_.estimatedBytes }) | Measure-Object -Sum).Sum
        $wouldExceedBytes = ($current.Count -gt 0) -and (($currentBytes + $componentBytes) -gt $TargetBatchBytes)
        $wouldExceedCount = ($current.Count -gt 0) -and (($current.Count + $records.Count) -gt $MaxFilesPerBatch)
        if ($wouldExceedBytes -or $wouldExceedCount) {
            Add-Batch -Files @($current) -Layer $layer
            $current = [System.Collections.Generic.List[object]]::new()
            $currentBytes = 0
        }
        # A single component larger than a whole batch is a cycle across more
        # files than one call should answer for. It is still emitted whole and
        # only warned about: splitting it would reintroduce the guessing this
        # layering removes, and refusing it would end a run that has already
        # paid for the inventory over an ordering detail the generator can
        # still resolve.
        if ($records.Count -gt $MaxFilesPerBatch -or $componentBytes -gt $TargetBatchBytes) {
            Write-QaFoundryLog -Level warn -Indent 2 -Message (
                "$($records.Count) file(s) depend on each other in a cycle and are assigned to one " +
                "oversized batch, because splitting them would make each half guess at the other: " +
                (@($component.paths) -join ", ") + ".")
        }
        foreach ($record in $records) { $current.Add($record) }
        $currentBytes += $componentBytes
    }
    Add-Batch -Files @($current) -Layer $layer
}

# Which earlier batches a batch has to read before it can be written. Sending
# every earlier batch would put the whole framework back into one request and
# undo the split, so only the batches that actually wrote a dependency are
# named. A batch in layer zero names none.
$batchOfPath = @{}
foreach ($batch in $batches) {
    foreach ($file in @($batch.files)) { $batchOfPath[[string]$file.path] = [string]$batch.batchId }
}
foreach ($batch in $batches) {
    $sources = [System.Collections.Generic.List[string]]::new()
    foreach ($file in @($batch.files)) {
        foreach ($dependency in $dependencies[[string]$file.path]) {
            $sourceBatch = [string]$batchOfPath[$dependency]
            if ([string]::IsNullOrWhiteSpace($sourceBatch)) { continue }
            if ($sourceBatch -eq [string]$batch.batchId) { continue }
            if ($sources.Contains($sourceBatch)) { continue }
            $sources.Add($sourceBatch)
        }
    }
    $batch | Add-Member -NotePropertyName dependsOnBatchIds -NotePropertyValue @($sources | Sort-Object)
}

# Who imports what, over the whole approved set rather than the regenerated
# subset. A repaired helper has to keep compiling against the callers nobody
# asked to change, and those callers are carried forward as final text: the
# stage supplies them to the batch read-only, so the repair is written against
# the exports they actually use instead of a second review round discovering
# it broke them.
$dependents = @{}
foreach ($entry in $approved) { $dependents[$entry.path] = [System.Collections.Generic.List[string]]::new() }
foreach ($entry in $approved) {
    if ((Get-QaFoundryPropertyNames -InputObject $entry.file) -notcontains "dependsOn") { continue }
    foreach ($dependency in @($entry.file.dependsOn)) {
        $normalised = ([string]$dependency).Replace("\", "/").Trim()
        if ([string]::IsNullOrWhiteSpace($normalised)) { continue }
        if ($normalised -eq $entry.path) { continue }
        if (-not $dependents.ContainsKey($normalised)) { continue }
        if ($dependents[$normalised].Contains($entry.path)) { continue }
        $dependents[$normalised].Add($entry.path)
    }
}

$dependentsByPath = [ordered]@{}
foreach ($key in @($dependents.Keys | Sort-Object)) {
    $dependentsByPath[$key] = @($dependents[$key] | Sort-Object)
}

return [pscustomobject]@{
    totalFiles = $approved.Count
    paths = @($approvedPaths)
    approvedFiles = @($approved | ForEach-Object {
        [pscustomobject]@{ path = $_.path; plannedFile = $_.file; estimatedBytes = (Get-EstimatedBytes $_.file) }
    })
    dependentsByPath = [pscustomobject]$dependentsByPath
    regeneratedPaths = @($ordered | ForEach-Object { $_.path })
    resolverOwnedPaths = @($resolverOwned | Sort-Object -Property path | ForEach-Object { $_.path })
    layerCount = $layerNumber
    batches = @($batches)
}
