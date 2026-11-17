[CmdletBinding()]
param([Parameter(Mandatory)][string]$ToolchainLockPath, [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$WorkRoot, [switch]$DryRun, [switch]$DeferExecution,
    [AllowNull()][object]$Deadline = $null)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../Common.ps1')
New-Item -ItemType Directory -Path (Split-Path ([IO.Path]::GetFullPath($OutputPath, (Get-Location).ProviderPath)) -Parent) -Force | Out-Null
$lock = Get-Content -LiteralPath $ToolchainLockPath -Raw | ConvertFrom-Json -Depth 50
$checks = [System.Collections.Generic.List[object]]::new()
$status = 'completed'
$failureKind = ''
try {
    foreach ($toolchain in @($lock.toolchains)) {
        if ($DeferExecution) {
            $checks.Add(@{name=[string]$toolchain.id;detail='Bootstrap generation only: build and execution probes deferred until after delivery.'})
            continue
        }
        if ($DryRun -or $toolchain.ecosystem -notin @('nuget', 'npm')) {
            $checks.Add(@{name=[string]$toolchain.id;detail='Minimal build probe not executed: rehearsal or unsupported ecosystem. Final framework verification is still required.'})
            continue
        }
        # The caller already owns a unique workspace. Short child names avoid
        # Windows package paths exceeding build-tool path limits.
        $scratch = Join-Path $WorkRoot ("project-" + $checks.Count)
        $manifestName = if ($toolchain.ecosystem -eq 'npm') { 'foundry-probe' } else { 'FoundryProbe' }
        $result = & (Join-Path $PSScriptRoot 'Resolve-EcosystemLock.ps1') -Toolchain $toolchain `
            -WorkRoot $scratch -ManifestName $manifestName -ManifestVersion '1.0.0' -BuildProbe -Deadline $Deadline
        if ($result.deadlineReached) { Stop-QaFoundryForBudget -Reason 'Minimal toolchain probe reached the relay deadline.' }
        if (-not $result.succeeded) {
            $status = 'blocked'
            $failureKind = if ($result.infrastructureUnavailable) { 'external_prerequisite' } else { 'artifact_invalid' }
            $checks.Add(@{name=[string]$toolchain.id;detail=[string]$result.detail})
            break
        }
        $checks.Add(@{name=[string]$toolchain.id;detail='Dependencies installed and deterministic minimal project executed or compiled successfully. Product scenarios have not been verified.'})
    }
}
catch { $status = 'blocked'; throw }
finally {
    @{status=$status;checkedAt=[DateTime]::UtcNow.ToString('o');checks=@($checks)} |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8
}
return [pscustomobject]@{status=$status;checks=@($checks);failureKind=$failureKind}
