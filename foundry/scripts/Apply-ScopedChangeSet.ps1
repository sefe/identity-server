[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunId,
    [string]$StageId = "apply-changes"
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common.ps1")
# The applier is the last thing standing between a model's output and the
# repository, so it checks what it was handed rather than trusting whoever
# handed it over. An unresolved plan, a refusal that still carries changes, or
# anything short of a finished change set stops here.
$null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
    -ArtifactPath $PlanPath `
    -SchemaPath (Join-Path $PSScriptRoot "../schemas/actions/change-set.schema.json")
$plan = Get-Content -Path $PlanPath -Raw |
    ConvertFrom-Json -Depth 100 -ErrorAction Stop
if ((Get-QaFoundryPropertyNames -InputObject $plan) -contains "materializations") {
    throw "Change set still names work for a resolver; it is a plan, not a change set: $PlanPath"
}
$planStatus = [string]$plan.status
$planOutcome = [string]$plan.outcome
Assert-QaFoundryRehearsalNotDelivered -ChangeSet $plan -ChangeSetPath $PlanPath `
    -DeliveryIsLive (Test-QaFoundryDeliveryLeavesMachine -DeliveryConfig $Config.delivery) `
    -Context "Stage '$StageId'"
if ($planStatus -ne "completed") {
    throw "Change set did not complete, so there is nothing to apply. Status: $planStatus"
}
if ($planOutcome -notin @("proposed", "no_action_needed")) {
    throw "Change set completed with an outcome that proposes nothing to apply: $planOutcome"
}
$changes = @($plan.changes)
if ($planOutcome -eq "no_action_needed" -and $changes.Count -gt 0) {
    throw "Change set says no action is needed yet carries $($changes.Count) change(s)."
}
$dryRun = [bool]$Config.delivery.dry_run -or -not [bool]$Config.delivery.apply_changes
if ($changes.Count -eq 0) {
    return [pscustomobject][ordered]@{
        runId = $RunId
        stageId = $StageId
        handler = "apply_change_set"
        status = "no_action_needed"
        dryRun = $dryRun
        actions = @()
        evidence = @($PlanPath)
    }
}
$actions = [System.Collections.Generic.List[object]]::new()
$registryPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot ([string]$Config.idempotency.registry_path)))
$repositoryPrefix = (Resolve-Path $RepositoryRoot).Path.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $registryPath.StartsWith($repositoryPrefix, [StringComparison]::Ordinal)) {
    throw "Idempotency registry must stay inside the target repository."
}
$baseline = @(& (Join-Path $PSScriptRoot "Get-GitChangedPaths.ps1") `
    -RepositoryRoot $RepositoryRoot)
$prepared = [System.Collections.Generic.List[object]]::new()
$seen = @{}
foreach ($change in $changes) {
    $scope = & (Join-Path $PSScriptRoot "Test-RepositoryPathScope.ps1") `
        -Path ([string]$change.path) `
        -Config $Config `
        -RepositoryRoot $RepositoryRoot
    $relative = [string]$scope.relativePath
    if ($seen.ContainsKey($relative)) {
        throw "Change set contains the same path more than once: $relative"
    }
    $seen[$relative] = $true
    $sourceRef = if (@($change.sourceRefs).Count -gt 0) {
        [string]$change.sourceRefs[0]
    } else { $relative }
    # What a change is, for the purpose of not doing it twice, is the file it
    # writes and the bytes it writes there. The agent's own sourceRef is
    # neither. One reference - "blueprint:automationProjects" - is cited by
    # every file a blueprint asks for, so a key built from it made the second
    # file indistinguishable from the first: a resumed run read the record left
    # by the first and skipped the second, which was then never written at all.
    # And a key blind to content cannot tell a revision from the draft it
    # revises, so the repair round of a rejected change could not be applied
    # over its own first attempt.
    $contentVersion = if ([string]$change.operation -eq "delete") {
        "removes:" + ([string]$change.expectedSha256).Trim().ToLowerInvariant()
    }
    else {
        "writes:" + (Get-QaFoundryTextSha256 -Text ([string]$change.content))
    }
    $key = & (Join-Path $PSScriptRoot "New-IdempotencyKey.ps1") `
        -ActionType "repository.$([string]$change.operation)" `
        -Scope $relative -SourceRef $contentVersion
    $existing = if ([bool]$Config.idempotency.enabled) {
        & (Join-Path $PSScriptRoot "Use-IdempotencyRegistry.ps1") -Operation check `
            -RegistryPath $registryPath -Key $key
    } else { [pscustomobject]@{ exists = $false; record = $null } }
    # A record says this change was made. Whether it is still made is a question
    # about the repository, and the registry is not the repository: a checkout
    # that never carried the change, or carried it and lost it, leaves a record
    # that would skip the only thing standing between the plan and an empty
    # delivery. So the record is believed only where the file agrees with it.
    if ($existing.exists -and [string]$existing.record.status -eq "executed" -and
        (Test-QaFoundryChangeAlreadyApplied -Operation ([string]$change.operation) `
            -Path ([string]$scope.absolutePath) -Content ([string]$change.content))) {
        $actions.Add([pscustomobject][ordered]@{
            sourceRef = $sourceRef
            type = "repository.$([string]$change.operation)"
            idempotencyKey = $key
            status = "duplicate"
            externalId = $relative
            summary = "Previously applied $([string]$change.operation) $relative"
        })
        continue
    }
    if ($relative -in $baseline) {
        throw "Change set refuses to touch a pre-existing dirty path: $relative"
    }
    $operation = [string]$change.operation
    $exists = Test-Path $scope.absolutePath -PathType Leaf
    if ($operation -eq "create" -and $exists) {
        throw "Create target already exists: $relative"
    }
    if ($operation -in @("update", "delete") -and -not $exists) {
        throw "$operation target does not exist: $relative"
    }
    if ($operation -eq "delete" -and -not [bool]$Config.delivery.allow_file_deletions) {
        throw "File deletion is disabled: $relative"
    }
    if ($operation -in @("update", "delete")) {
        if ([string]::IsNullOrWhiteSpace([string]$change.expectedSha256)) {
            throw "$operation requires expectedSha256: $relative"
        }
        $actualHash = (Get-FileHash -LiteralPath $scope.absolutePath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne [string]$change.expectedSha256) {
            throw "File changed after planning; SHA-256 mismatch: $relative"
        }
    }
    $prepared.Add([pscustomobject]@{
        operation = $operation
        relativePath = $relative
        absolutePath = [string]$scope.absolutePath
        content = [string]$change.content
        sourceRef = $sourceRef
        key = $key
    })
}
if ($dryRun) {
    foreach ($change in $prepared) {
        $key = [string]$change.key
        $actions.Add([pscustomobject][ordered]@{
            sourceRef = $change.sourceRef
            type = "repository.$($change.operation)"
            idempotencyKey = $key
            status = "dry_run"
            externalId = $change.relativePath
            summary = "$($change.operation) $($change.relativePath)"
        })
        if ([bool]$Config.idempotency.enabled) {
            $null = & (Join-Path $PSScriptRoot "Use-IdempotencyRegistry.ps1") `
                -Operation register -RegistryPath $registryPath -Key $key `
                -ActionType "repository.$($change.operation)" -SourceRef $change.sourceRef `
                -Status dry_run -RunId $RunId -ExternalId $change.relativePath
        }
    }
    return [pscustomobject][ordered]@{
        runId = $RunId
        stageId = $StageId
        handler = "apply_change_set"
        status = if ($prepared.Count -eq 0) { "no_action_needed" } else { "completed" }
        dryRun = $true
        actions = @($actions)
        evidence = @($PlanPath)
    }
}

$backupRoot = Join-Path $RunRoot "actions/backups/$StageId"
$createdPaths = [System.Collections.Generic.List[string]]::new()
$backedUp = [System.Collections.Generic.List[object]]::new()
try {
    foreach ($change in $prepared) {
        if ($change.operation -in @("update", "delete")) {
            $backupPath = Join-Path $backupRoot $change.relativePath
            New-Item -ItemType Directory -Path (Split-Path $backupPath -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $change.absolutePath -Destination $backupPath -Force
            $backedUp.Add([pscustomobject]@{
                original = $change.absolutePath
                backup = $backupPath
            })
        }
        if ($change.operation -eq "delete") {
            Remove-Item -LiteralPath $change.absolutePath -Force
        }
        else {
            New-Item -ItemType Directory -Path (Split-Path $change.absolutePath -Parent) -Force | Out-Null
            Set-Content -LiteralPath $change.absolutePath `
                -Value $change.content -Encoding utf8 -NoNewline
            if ($change.operation -eq "create") {
                $createdPaths.Add($change.absolutePath)
            }
        }
    }
    $after = @(& (Join-Path $PSScriptRoot "Get-GitChangedPaths.ps1") `
        -RepositoryRoot $RepositoryRoot)
    $newChangedPaths = @($after | Where-Object { $_ -notin $baseline })
    $registryRelative = [IO.Path]::GetRelativePath($RepositoryRoot, $registryPath).Replace("\", "/")
    $internalPaths = @($registryRelative, "$registryRelative.lock")
    $unexpected = @($newChangedPaths | Where-Object {
        $_ -notin @($prepared.relativePath) -and $_ -notin $internalPaths
    })
    if ($unexpected.Count -gt 0) {
        throw "Change application produced unexpected Git paths: $($unexpected -join ', ')"
    }
    foreach ($change in $prepared) {
        $key = [string]$change.key
        $actions.Add([pscustomobject][ordered]@{
            sourceRef = $change.sourceRef
            type = "repository.$($change.operation)"
            idempotencyKey = $key
            status = if ($change.relativePath -in $newChangedPaths) { "executed" } else { "skipped" }
            externalId = $change.relativePath
            summary = "$($change.operation) $($change.relativePath)"
        })
        if ([bool]$Config.idempotency.enabled) {
            $null = & (Join-Path $PSScriptRoot "Use-IdempotencyRegistry.ps1") `
                -Operation register -RegistryPath $registryPath -Key $key `
                -ActionType "repository.$($change.operation)" -SourceRef $change.sourceRef `
                -Status executed -RunId $RunId -ExternalId $change.relativePath
        }
    }
}
catch {
    foreach ($path in $createdPaths) {
        if (Test-Path $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
    foreach ($backup in $backedUp) {
        Copy-Item -LiteralPath $backup.backup -Destination $backup.original -Force
    }
    throw
}

return [pscustomobject][ordered]@{
    runId = $RunId
    stageId = $StageId
    handler = "apply_change_set"
    status = if ($prepared.Count -eq 0) { "no_action_needed" } else { "completed" }
    dryRun = $false
    actions = @($actions)
    evidence = @($PlanPath, $backupRoot)
}
