[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Requests,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$StageId,
    [Parameter(Mandatory)][string]$OutputPath,
    [AllowNull()][object]$Deadline = $null,
    [AllowNull()][scriptblock]$VersionSource = $null,
    [AllowNull()][scriptblock]$Probe = $null
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../Common.ps1')
. (Join-Path $PSScriptRoot '../DependencyEvolution.ps1')
$root = Get-QaFoundryRoot
$revisionRoot = Join-Path $RunRoot ('dependency-updates/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $revisionRoot -Force | Out-Null
$outcome = 'revision_required'
$changed = $false
$detail = ''
$active = ''
$candidatePath = Join-Path $revisionRoot 'toolchain-lock.json'
$requestSignature = ConvertTo-Json -InputObject @($Requests) -Depth 20 -Compress
function Write-ResolutionRecord {
    $deferrals = if ($changed -or $outcome -ne 'completed') { @([ordered]@{
        kind=$(if ($outcome -eq 'blocked') { 'external_prerequisite' } else { 'artifact_invalid' })
        item='Update the dependency request or implementation inventory against dependency resolution evidence.'
        reason=$detail.Substring(0, [Math]::Min(600, $detail.Length))
    }) } else { @() }
    $record = [ordered]@{
        agentId='dependency-resolution';stageId=$StageId;runId=$RunId
        status=$(if ($outcome -eq 'blocked') { 'blocked' } else { 'completed' })
        summary=$detail;evidence=@();assumptions=@();unknowns=@();warnings=@();deferrals=@($deferrals)
        details=@{outcome=$outcome;changed=$changed;requests=@($Requests);previousLock=$active;candidateLock=$candidatePath;candidateSha256=$candidateHash}
    }
    $record | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath "$OutputPath.tmp" -Encoding utf8
    Move-Item -LiteralPath "$OutputPath.tmp" -Destination $OutputPath -Force
}
$candidateHash = ''
# A resumed stage must still revise its old inventory after a successful promotion.
# The result is written before the pointer, so even interruption at that boundary
# cannot turn an accepted update into a no-op that lets stale manifests pass.
if (Test-Path -LiteralPath $OutputPath) {
    $previous = Get-Content -LiteralPath $OutputPath -Raw | ConvertFrom-Json -Depth 100
    if ($previous.runId -ceq $RunId -and $previous.stageId -ceq $StageId -and
        $previous.details.changed -and $previous.details.outcome -eq 'completed' -and
        (ConvertTo-Json -InputObject @($previous.details.requests) -Depth 20 -Compress) -ceq $requestSignature) {
        $current = Get-QaFoundryActiveToolchainPath -RunRoot $RunRoot
        if ((Get-FileHash -LiteralPath $current -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $previous.details.candidateSha256) {
            return [pscustomobject]@{status='completed';changed=$true;detail=$previous.summary;path=$OutputPath}
        }
    }
}
try {
    $requestPath = Join-Path $revisionRoot 'requests.json'
    ConvertTo-Json -InputObject @($Requests) -Depth 20 | Set-Content -LiteralPath "$requestPath.txt" -Encoding utf8
    $null = & (Join-Path $root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath "$requestPath.txt" `
        -SchemaPath (Join-Path $root 'schemas/runtime/dependency-requests.schema.json') -SchemaRoot (Join-Path $root 'schemas')
    Move-Item -LiteralPath "$requestPath.txt" -Destination $requestPath -Force
    $active = Get-QaFoundryActiveToolchainPath -RunRoot $RunRoot
    $beforeHash = (Get-FileHash -LiteralPath $active -Algorithm SHA256).Hash.ToLowerInvariant()
    $candidate = Get-Content -LiteralPath $active -Raw | ConvertFrom-Json -AsHashtable -Depth 100
    if ([string]$candidate.runId -ne $RunId) { throw 'Dependency lock belongs to another run.' }
    $policy = Resolve-QaFoundryPackagePolicy -Automation $Config.automation
    $touched = [System.Collections.Generic.HashSet[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($request in $Requests) {
        $matches = @($candidate.toolchains | Where-Object { $_.id -ceq [string]$request.toolchainId })
        if ($matches.Count -ne 1) { throw "Unknown toolchain '$($request.toolchainId)'. Use an ID from the active lock." }
        $toolchain = $matches[0]
        $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem ([string]$toolchain.ecosystem)
        $name = ([string]$request.name).Trim()
        $canonicalName = Get-QaFoundryNormalisedPackageName -Ecosystem $toolchain.ecosystem -Name $name
        if (-not $seen.Add("$($toolchain.id)/$canonicalName")) { throw "Duplicate dependency request for '$name'." }
        $requested = ([string]$request.version).Trim()
        if ($requested -in @('', '*', 'latest')) { throw "Choose a justified version or bounded range for '$name'; latest alone is not a compatibility decision." }
        $range = Test-QaFoundryVersionRange -Ecosystem $toolchain.ecosystem -Range $requested
        if (-not $range.valid) { throw $range.reason }
        foreach ($denied in $policy.deniedPackages) {
            if ((Get-QaFoundryNormalisedPackageName -Ecosystem $toolchain.ecosystem -Name $denied) -ceq $canonicalName) {
                throw "The configured package policy refuses '$name'."
            }
        }
        $existing = @($toolchain.packages | Where-Object {
            (Get-QaFoundryNormalisedPackageName -Ecosystem $toolchain.ecosystem -Name $_.name) -ceq $canonicalName
        })
        $allowPrerelease = [bool]$policy.allowPrerelease -and $requested -match '-[0-9A-Za-z]'
        # A repeated accepted request is already satisfied: do not upgrade on every retry.
        if ($existing.Count -eq 1 -and $existing[0].scope -ceq [string]$request.scope -and
            -not [string]::IsNullOrEmpty([string](& $adapter.SelectVersion $requested @([string]$existing[0].version) $allowPrerelease))) { continue }
        try {
            $versions = if ($null -ne $VersionSource) { @(& $VersionSource $toolchain.source.registry $name) }
                else { @(& $adapter.GetPublishedVersions $toolchain.source.registry $name) }
        } catch { $outcome = 'blocked'; throw "Package feed lookup failed for '${name}': $($_.Exception.Message)" }
        if ($versions.Count -eq 0) { throw "Package '$name' was not found at $($toolchain.source.registry)." }
        $version = [string](& $adapter.SelectVersion $requested @($versions | ForEach-Object { [string]$_ }) $allowPrerelease)
        if (-not $version) { throw "No published version of '$name' satisfies '$requested' under the selected prerelease policy." }
        $key = if ($existing.Count -eq 1) { [string]$existing[0].key } else { ($name.ToLowerInvariant() -replace '[^a-z0-9]+','-').Trim('-') }
        $retained = @($toolchain.packages | Where-Object {
            (Get-QaFoundryNormalisedPackageName -Ecosystem $toolchain.ecosystem -Name $_.name) -cne $canonicalName
        })
        if (@($retained | Where-Object key -CEQ $key).Count) { throw "Package key '$key' collides with another dependency." }
        $toolchain.packages = @($retained + @([ordered]@{key=$key;name=$name;version=$version;scope=[string]$request.scope;requested=$requested}) | Sort-Object { $_.key })
        if ($policy.maxDirectPackages -gt 0 -and $toolchain.packages.Count -gt $policy.maxDirectPackages) { throw 'Dependency update exceeds the configured package count limit.' }
        $null = $touched.Add([string]$toolchain.id)
    }
    if ($touched.Count -gt 0) {
        foreach ($toolchain in $candidate.toolchains) {
            if (-not $touched.Contains([string]$toolchain.id)) { continue }
            $toolchain.revision = [int]$toolchain.revision + 1
            $null = $toolchain.Remove('sha256')
            $canonical = $toolchain | ConvertTo-Json -Depth 30 -Compress
            $toolchain.sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical))).ToLowerInvariant()
        }
        $candidate.resolvedAt = [DateTime]::UtcNow.ToString('o')
        $candidate | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath "$candidatePath.txt" -Encoding utf8
        $null = & (Join-Path $root 'scripts/Validate-JsonArtifact.ps1') -ArtifactPath "$candidatePath.txt" `
            -SchemaPath (Join-Path $root 'schemas/runtime/toolchain-lock.schema.json') -SchemaRoot (Join-Path $root 'schemas')
        Move-Item -LiteralPath "$candidatePath.txt" -Destination $candidatePath -Force
        $probePath = Join-Path $revisionRoot 'readiness.json'
        if ($null -ne $Probe) { $probeResult = & $Probe $candidatePath $probePath }
        else {
            $dryRun = $Config.automation.PSObject.Properties['verification'] -and
                $Config.automation.verification.PSObject.Properties['dry_run'] -and [bool]$Config.automation.verification.dry_run
            $scratchParent = Join-Path (Split-Path $RunRoot -Parent) '.scratch'
            $scratch = Join-Path $scratchParent ([guid]::NewGuid().ToString('N'))
            try {
                $probeResult = & (Join-Path $PSScriptRoot 'Test-ToolchainReadiness.ps1') -ToolchainLockPath $candidatePath `
                    -OutputPath $probePath -WorkRoot $scratch -DryRun:$dryRun -Deadline $Deadline
            } finally {
                if ((Test-PathWithinRoot -Candidate $scratch -Root $scratchParent) -and (Test-Path -LiteralPath $scratch)) {
                    Remove-Item -LiteralPath $scratch -Recurse -Force
                }
            }
        }
        if ($probeResult.status -ne 'completed') {
            $outcome = if ($probeResult.failureKind -eq 'external_prerequisite') { 'blocked' } else { 'revision_required' }
            throw "Dependency compatibility probe failed: $($probeResult.checks | ConvertTo-Json -Depth 10 -Compress)"
        }
        $now = Get-QaFoundryActiveToolchainPath -RunRoot $RunRoot
        if ((Get-FileHash -LiteralPath $now -Algorithm SHA256).Hash.ToLowerInvariant() -cne $beforeHash) { throw 'Active dependencies changed during resolution; retry against the current lock.' }
        $pointer = [ordered]@{
            relativePath=[IO.Path]::GetRelativePath($RunRoot,$candidatePath).Replace('\','/')
            sha256=(Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash.ToLowerInvariant()
            previousPath=[IO.Path]::GetRelativePath($RunRoot,$active).Replace('\','/')
            previousSha256=$beforeHash
            requestsPath=[IO.Path]::GetRelativePath($RunRoot,$requestPath).Replace('\','/')
        }
        $pointerPath = Join-Path $RunRoot 'context/toolchain-current.json'
        $candidateHash = $pointer.sha256
        $changed = $true
        $outcome = 'completed'
        $detail = 'Dependencies resolved and probed. Revise the owner manifests, configuration, rationale and dependent test contracts against the active lock.'
        Write-ResolutionRecord
        $pointer | ConvertTo-Json | Set-Content -LiteralPath "$pointerPath.tmp" -Encoding utf8
        Move-Item -LiteralPath "$pointerPath.tmp" -Destination $pointerPath -Force
    } else { $detail = 'All requested dependencies are already satisfied by the active lock.' }
    $outcome = 'completed'
} catch {
    if (Test-QaFoundryBudgetStop -Message $_) { throw }
    if ($outcome -eq 'completed') { $outcome = 'revision_required'; $changed = $false }
    $detail = $_.Exception.Message
}
Write-ResolutionRecord
return [pscustomobject]@{status=$outcome;changed=$changed;detail=$detail;path=$OutputPath}
