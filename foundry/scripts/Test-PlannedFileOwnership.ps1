[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PlannedFiles,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OwnerArtifactPath,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$OwnerAgentId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Common.ps1")

# Two agents in one stage may plan the same file, and only one of them can be
# right about what goes in it. The change generator refuses a path whose two
# contracts disagree, which is correct - choosing between two specifications is
# not the runtime's decision - but it refuses at stage 10 of 13, where a refusal
# ends the run and every review that approved the conflict has already been paid
# for. Build 972596 died there after three and a half hours on two .csproj files
# that the test agent restated while answering a review.
#
# So the same disagreement is found here instead, in the agent that does not own
# the file, while it still has retries and the owner's inventory in front of it.
# Ownership is declared by the workflow rather than inferred: the agent that
# lays a foundation runs first and is the one a later agent defers to.

function Get-PlannedFileContract {
    param([object]$PlannedFile)
    if ($null -eq $PlannedFile) { return "" }
    if (@(Get-QaFoundryPropertyNames -InputObject $PlannedFile) -notcontains "contentContract") {
        return ""
    }
    return ([string]$PlannedFile.contentContract).Trim()
}

$findings = [System.Collections.Generic.List[string]]::new()

if (-not (Test-Path -LiteralPath $OwnerArtifactPath -PathType Leaf)) {
    # The owner has not answered in this run yet, so there is nothing to defer
    # to. That is not a defect in this artifact.
    return @($findings)
}

$ownerArtifact = Get-Content -LiteralPath $OwnerArtifactPath -Raw | ConvertFrom-Json -Depth 100
if (@(Get-QaFoundryPropertyNames -InputObject $ownerArtifact) -notcontains "plannedFiles") {
    return @($findings)
}

$ownerContracts = @{}
foreach ($ownerFile in @($ownerArtifact.plannedFiles)) {
    if ($null -eq $ownerFile) { continue }
    if (@(Get-QaFoundryPropertyNames -InputObject $ownerFile) -notcontains "path") { continue }
    $ownerPath = ([string]$ownerFile.path).Replace("\", "/").Trim()
    if ($ownerPath -eq "") { continue }
    $ownerContracts[$ownerPath] = Get-PlannedFileContract -PlannedFile $ownerFile
}

if ($ownerContracts.Count -eq 0) { return @($findings) }

# Ordered so the message names files in the order this inventory introduced
# them, which is the order the agent is reading its own output in.
$conflicting = [System.Collections.Generic.List[string]]::new()
foreach ($plannedFile in @($PlannedFiles)) {
    if ($null -eq $plannedFile) { continue }
    if (@(Get-QaFoundryPropertyNames -InputObject $plannedFile) -notcontains "path") { continue }
    $path = ([string]$plannedFile.path).Replace("\", "/").Trim()
    if ($path -eq "" -or -not $ownerContracts.ContainsKey($path)) { continue }
    # An identical restatement is harmless: the merge keeps one of two entries
    # that say the same thing. Only a disagreement has to be settled, and it
    # cannot be settled by whichever inventory happens to be read last.
    if ((Get-PlannedFileContract -PlannedFile $plannedFile) -ceq $ownerContracts[$path]) { continue }
    if (-not $conflicting.Contains($path)) { $conflicting.Add($path) }
}

if ($conflicting.Count -gt 0) {
    $findings.Add(
        "These files are already specified by '$OwnerAgentId', which owns them, and this " +
        "inventory specifies them differently: $($conflicting -join ', '). One file cannot be " +
        "written to two contracts, and the deterministic generator refuses the pair rather than " +
        "guessing which one the reviews approved. Remove each of these paths from 'plannedFiles' " +
        "and name it in 'dependsOn' on the entries that consume it. Where you need the owner's " +
        "contract to change - a package, a linked file, a build target - do not restate the file " +
        "here: record the change you need in 'unknowns', naming the path and the exact addition, " +
        "so the review raises it against '$OwnerAgentId' and the owner makes it in the next " +
        "iteration. Restating the file is the one thing that cannot work, because both contracts " +
        "then reach the generator and neither of them wins.")
}

return @($findings)
