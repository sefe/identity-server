[CmdletBinding()]
param([Parameter(Mandatory)][string]$RunRoot, [Parameter(Mandatory)][object]$Workflow,
    [Parameter(Mandatory)][string]$StageId)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$statePath = Join-Path $RunRoot 'workflow-state.json'
$state = & (Join-Path $PSScriptRoot 'Load-WorkflowState.ps1') -Path $statePath
if ($state.status -notin @('blocked', 'failed', 'paused')) {
    throw 'Stage recovery requires a stopped run (blocked, failed or paused).'
}
$stages = @($Workflow.stages)
$index = [Array]::IndexOf(@($stages | ForEach-Object { [string]$_.id }), $StageId)
if ($index -lt 0) { throw "Unknown recovery stage: $StageId" }
$safeHandlers = @('materialize_change_set', 'resolve_toolchain', 'verify_framework', 'quality_suite', 'collect_observability')
$affected = @($stages | Select-Object -Skip $index)
$directories = [System.Collections.Generic.List[string]]::new()
foreach ($stage in $affected) {
    $saved = @($state.stages | Where-Object id -EQ $stage.id)
    if ($saved.Count -ne 1) { throw "Saved state does not describe stage '$($stage.id)'." }
    if ($stage.type -eq 'deterministic_action' -and $saved[0].iteration -gt 0 -and
        [string]$stage.action.handler -notin $safeHandlers) {
        throw "Stage '$($stage.id)' may have external effects; reconcile its delivery receipts before recovery."
    }
    $relative = if ($stage.PSObject.Properties['artifact_directory']) { [string]$stage.artifact_directory } else { [string]$stage.id }
    $path = [IO.Path]::GetFullPath((Join-Path $RunRoot $relative))
    if (-not (Test-PathWithinRoot -Candidate $path -Root $RunRoot) -or $path -eq [IO.Path]::GetFullPath($RunRoot)) {
        throw 'Stage directory escapes its run.'
    }
    if ($relative -in @('context', 'supervisor', 'logs', 'recovery')) { throw 'Stage directory overlaps reserved evidence.' }
    $directories.Add($path)
}
$archive = Join-Path $RunRoot ("recovery/" + [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ') + '-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $archive -Force | Out-Null
Copy-Item -LiteralPath $statePath -Destination (Join-Path $archive 'workflow-state.json')
if (Test-Path -LiteralPath (Join-Path $RunRoot 'run-inputs.json')) {
    Copy-Item -LiteralPath (Join-Path $RunRoot 'run-inputs.json') -Destination (Join-Path $archive 'run-inputs.json')
}
if ($index -eq 0 -and (Test-Path -LiteralPath (Join-Path $RunRoot 'context'))) {
    Move-Item -LiteralPath (Join-Path $RunRoot 'context') -Destination (Join-Path $archive 'context')
    New-Item -ItemType Directory -Path (Join-Path $RunRoot 'context') | Out-Null
}
elseif (@($affected | Where-Object { $_.type -eq 'deterministic_action' -and $_.action.handler -eq 'resolve_toolchain' }).Count -gt 0) {
    foreach ($name in @('toolchain-lock.json', 'toolchain-current.json')) {
        $lockPath = Join-Path $RunRoot "context/$name"
        if (Test-Path -LiteralPath $lockPath) {
            New-Item -ItemType Directory -Path (Join-Path $archive 'context') -Force | Out-Null
            Move-Item -LiteralPath $lockPath -Destination (Join-Path $archive "context/$name")
        }
    }
}
@{ stageId = $StageId; requestedAt = [DateTime]::UtcNow.ToString('o'); invalidated = @($affected | ForEach-Object id) } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $archive 'recovery-request.json')
foreach ($path in $directories) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $target = Join-Path $archive ([IO.Path]::GetRelativePath($RunRoot, $path))
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Move-Item -LiteralPath $path -Destination $target
}
foreach ($stage in $affected) {
    $saved = @($state.stages | Where-Object id -EQ $stage.id)[0]
    $saved.status = 'pending'; $saved.iteration = 0; $saved.attempts = @()
}
$state.status = 'paused'; $state.currentStage = $StageId; $state.stageIteration = 0
$state | Add-Member -NotePropertyName blockedReason -NotePropertyValue $null -Force
$state | Add-Member -NotePropertyName blockers -NotePropertyValue @() -Force
& (Join-Path $PSScriptRoot 'Save-WorkflowState.ps1') -State $state -Path $statePath
Write-QaFoundryLog -Message "Recovery starts at '$StageId'. Superseded evidence is preserved in '$archive'."
