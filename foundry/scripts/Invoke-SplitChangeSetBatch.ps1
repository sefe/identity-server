[CmdletBinding()]
param(
    [Parameter(Mandatory)][hashtable]$AgentParameters,
    [Parameter(Mandatory)][string]$AssignmentPath
)

. (Join-Path $PSScriptRoot 'Common.ps1')
. (Join-Path $PSScriptRoot 'GenerationRepair.ps1')
$assignment = Get-Content -LiteralPath $AssignmentPath -Raw | ConvertFrom-Json -Depth 100
$paths = @($assignment.assignedPaths)
if ($paths.Count -lt 2) { throw 'Only multi-file assignments can be split.' }
if (@($paths | Select-Object -Unique).Count -ne $paths.Count) { throw 'Duplicate split assignment paths.' }
$output = [string]$AgentParameters.OutputPath
$assignmentHash = (Get-FileHash -LiteralPath $AssignmentPath -Algorithm SHA256).Hash.ToLowerInvariant()
$contextHashes = @(@($AgentParameters.ContextPaths) + @($AgentParameters.PriorityContextPaths) |
    Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | ForEach-Object {
        # Hash content, not machine-specific checkout paths: the next leg can
        # run on a different agent. Changed dependency bodies invalidate parts.
        (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash.ToLowerInvariant()
    } | Sort-Object -Unique)
$signature = [ordered]@{ runId = $AgentParameters.RunId; assignment = $assignmentHash; context = $contextHashes } |
    ConvertTo-Json -Compress -Depth 20
$hasher = [Security.Cryptography.SHA256]::Create()
try { $basis = [Convert]::ToHexString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($signature))).ToLowerInvariant() }
finally { $hasher.Dispose() }
# A different contract or dependency cannot reuse a part with the same ordinal.
$directory = Join-Path "$output.parts" $basis
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$contractsPath = Join-Path $directory 'sibling-contracts.md'
@{ instruction = 'Read-only contracts for the whole original batch, including cyclic dependencies. Generate only your assigned path. Use completed sibling bodies as the source of truth; report contract conflicts explicitly.'
   files = @($assignment.assignedFiles) } |
    ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $contractsPath -Encoding utf8

Write-QaFoundryLog -Level step -Indent 2 -Scope $AgentParameters.AgentId -Message (
    "The response exceeded the output limit. Continuing as $($paths.Count) single-file assignments; completed parts are reused across relay legs.")
$parts = [System.Collections.Generic.List[object]]::new()
$completedPaths = [System.Collections.Generic.List[string]]::new()
for ($index = 0; $index -lt $paths.Count; $index++) {
    $partDirectory = Join-Path $directory ("part-{0:d3}" -f ($index + 1))
    New-Item -ItemType Directory -Path $partDirectory -Force | Out-Null
    # Keep the original leaf name so context readers recognize an assignment.
    $partAssignmentPath = Join-Path $partDirectory (Split-Path $AssignmentPath -Leaf)
    $partAssignment = $assignment | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    $partAssignment.batchId = "$($assignment.batchId)-part-$($index + 1)"
    $partAssignment.assignedPaths = @($paths[$index])
    $partAssignment.assignedFiles = @($assignment.assignedFiles | Where-Object path -CEQ $paths[$index])
    if ($partAssignment.assignedFiles.Count -ne 1) { throw "Missing unique contract for '$($paths[$index])'." }
    $partAssignment | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $partAssignmentPath -Encoding utf8
    $parameters = @{} + $AgentParameters
    $parameters.AgentId = "$($AgentParameters.AgentId)-part-$($index + 1)"
    $parameters.OutputPath = Join-Path $partDirectory 'change-set-batch-split.json'
    $parameters.AllowExistingArtifact = $true
    $parameters.ContextPaths = @($AgentParameters.ContextPaths | Where-Object { $_ -ne $AssignmentPath })
    $parameters.PriorityContextPaths = @($AgentParameters.PriorityContextPaths | Where-Object { $_ -and $_ -ne $AssignmentPath }) +
        @($partAssignmentPath, $contractsPath) + @($completedPaths)
    $part = & (Join-Path $PSScriptRoot 'Invoke-Agent.ps1') @parameters
    if ($part.status -ne 'completed' -or $part.outcome -ne 'proposed') {
        # Preserve the refusal and its repair paths. Never merge a blocked part
        # into a successful parent or publish the other files on its behalf.
        $part.agentId = [string]$AgentParameters.AgentId
        $part.batchId = [string]$assignment.batchId
        $part.changes = @()
        $part | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $output -Encoding utf8
        $coverage = Get-Content "$($parameters.OutputPath).coverage.json" -Raw | ConvertFrom-Json -Depth 100
        $coverage.agentId = [string]$AgentParameters.AgentId
        $coverage | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath "$output.coverage.json" -Encoding utf8
        return $part
    }
    if (-not (Test-QaFoundryAssignedBatchCoverage -Artifact $part -Assignment $partAssignment)) {
        throw "Split assignment '$($partAssignment.batchId)' did not deliver its full file contract."
    }
    $parts.Add($part)
    $completedPaths.Add([string]$parameters.OutputPath)
}
$merged = [pscustomobject]@{
    agentId = [string]$AgentParameters.AgentId; stageId = [string]$AgentParameters.StageId
    runId = [string]$AgentParameters.RunId; status = 'completed'; outcome = 'proposed'
    batchId = [string]$assignment.batchId; summary = "Completed all $($paths.Count) assigned files in separately validated responses."
    evidence = @($parts | ForEach-Object { $_.evidence })
    assumptions = @($parts | ForEach-Object { $_.assumptions } | Select-Object -Unique)
    unknowns = @($parts | ForEach-Object { $_.unknowns } | Select-Object -Unique)
    warnings = @($parts | ForEach-Object { $_.warnings } | Select-Object -Unique)
    deferrals = @(); changes = @($parts | ForEach-Object { $_.changes })
    details = @{ splitAfterTruncation = $true; assignmentSha256 = $assignmentHash; inputsSha256 = $basis; parts = @($parts | ForEach-Object { $_.batchId }) }
}
if (-not (Test-QaFoundryAssignedBatchCoverage -Artifact $merged -Assignment $assignment)) {
    throw 'Split batch aggregation does not exactly cover the original assignment.'
}
$temporary = "$output.split.tmp"
$merged | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $temporary -Encoding utf8
$null = & (Join-Path $PSScriptRoot 'Validate-JsonArtifact.ps1') -ArtifactPath $temporary `
    -SchemaPath $AgentParameters.SchemaPath -SchemaRoot (Join-Path (Get-QaFoundryRoot) 'schemas')
Move-Item -LiteralPath $temporary -Destination $output -Force
$requestedBytes = if ($AgentParameters.ContainsKey('MaxArtifactBytes') -and $AgentParameters.MaxArtifactBytes -gt 0) {
    [int]$AgentParameters.MaxArtifactBytes
} elseif ($AgentParameters.Config.ai.PSObject.Properties['max_artifact_bytes']) {
    [int]$AgentParameters.Config.ai.max_artifact_bytes
} else { 0 }
@{ runId = $AgentParameters.RunId; agentId = $AgentParameters.AgentId; stageId = $AgentParameters.StageId
   status = 'covered'; requestedBytes = $requestedBytes; grantedBytes = $requestedBytes; attempts = 1
   reductions = @(); deferrals = @(); deferralsSource = 'run' } |
    ConvertTo-Json -Depth 100 | Set-Content -LiteralPath "$output.coverage.json" -Encoding utf8
return $merged
