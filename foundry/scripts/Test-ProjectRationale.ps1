[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PlannedFiles,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$DocumentName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "Common.ps1")

# Why a stack was chosen is decided in the blueprint and, until this check
# existed, died there: run artifacts are thrown away and the repository is the
# only thing that survives the run. Whoever inherits the automation then reads a
# lockfile and guesses. The reasoning costs one file per project to keep, and the
# agent is not being asked to invent it - it is being asked to write down what
# the approved blueprint already settled, next to the code it produced.

function Get-RationalePathLeaf {
    param([string]$Path)
    $normalized = (([string]$Path).Replace("\", "/")).TrimEnd("/")
    $separator = $normalized.LastIndexOf("/")
    if ($separator -lt 0) { return $normalized }
    return $normalized.Substring($separator + 1)
}

$findings = [System.Collections.Generic.List[string]]::new()
$expected = $DocumentName.Trim()

# Ordered so the message names projects in the order the inventory introduced
# them, which is the order the agent is reading its own output in.
$carriesDocument = [ordered]@{}
foreach ($plannedFile in @($PlannedFiles)) {
    if ($null -eq $plannedFile) { continue }
    $fields = @(Get-QaFoundryPropertyNames -InputObject $plannedFile)
    if ($fields -notcontains "project") { continue }
    $project = ([string]$plannedFile.project).Trim()
    if ($project -eq "") { continue }
    if (-not $carriesDocument.Contains($project)) { $carriesDocument[$project] = $false }
    if ($fields -notcontains "path") { continue }
    # Compared exactly rather than case-insensitively: the agent runs on Linux,
    # where TECHNOLOGY-CHOICES.md and technology-choices.md are two files, and
    # only one of them is the one everyone was told to look for.
    if ((Get-RationalePathLeaf -Path ([string]$plannedFile.path)) -ceq $expected) {
        $carriesDocument[$project] = $true
    }
}

if ($carriesDocument.Count -eq 0) {
    $findings.Add(
        "No planned file says which automation project it belongs to, so there is no way to " +
        "tell whether every project carries $expected. Set 'project' on each entry in " +
        "plannedFiles to the name of the automation project the blueprint approved for it.")
}
else {
    $missing = @($carriesDocument.Keys | Where-Object { -not $carriesDocument[$_] })
    if ($missing.Count -gt 0) {
        $findings.Add(
            "These automation projects plan no $expected file: $($missing -join ', '). " +
            "Every automation project must carry one at its root, named exactly $expected, " +
            "recording why its language, runtime, test runner and libraries were chosen, " +
            "which alternatives were rejected and why, and which of those choices were fixed " +
            "by the approved blueprint's toolchain decision rather than decided during this run. Plan that " +
            "file for each project listed above.")
    }
}

return @($findings)
