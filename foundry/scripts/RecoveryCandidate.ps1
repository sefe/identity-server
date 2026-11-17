. (Join-Path $PSScriptRoot 'RecoveryReuse.ps1')

function Get-QaFoundryRecoveryCandidate {
    param([string]$RunRoot, [string]$RunId, [string]$RepositoryRoot)
    $inputPath = $env:QA_FOUNDRY_RECOVERY_CANDIDATE
    if (-not $inputPath -or $inputPath -eq 'none') { return $null }
    $path = [IO.Path]::GetFullPath($inputPath, $RepositoryRoot)
    if (-not (Test-PathWithinRoot -Candidate $path -Root $RepositoryRoot)) { throw 'Recovery candidate escapes the checkout.' }
    $candidate = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
    if ($candidate.version -ne 1 -or $candidate.runId -cne $RunId -or $candidate.authorship -ne 'operator') {
        throw 'Recovery candidate has the wrong run identity or provenance.'
    }
    $baseline = Get-QaFoundryRecoveryArtifact -RunRoot $RunRoot -RunId $RunId `
        -StageId 'bootstrap-change-materialization' -Name 'change-set.json'
    if (-not $baseline -or (Get-FileHash -LiteralPath $baseline.path).Hash -ne $candidate.baseChangeSetSha256) {
        throw 'Recovery candidate does not match the preserved materialized source.'
    }
    $seen = @{}
    foreach ($change in @($candidate.changes)) {
        if (-not $change.path -or $change.path -match '(^|[/\\])\.\.([/\\]|$)' -or
            [IO.Path]::IsPathRooted($change.path) -or $seen.ContainsKey($change.path) -or
            $change.operation -notin @('create','update') -or $change.content -isnot [string]) {
            throw 'Invalid or duplicate recovery candidate change.'
        }
        $seen[$change.path] = $true
    }
    $validation = & node (Join-Path $PSScriptRoot 'helpers/recovery-source.mjs') $baseline.path $path 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($validation -join "`n") }
    return [pscustomobject]@{ path=$path; sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant(); document=$candidate }
}

function New-QaFoundryRecoveryCandidateBatch {
    param([object]$Candidate, [object]$Assignment, [string]$AgentId, [string]$StageId, [string]$RunId)
    if ($null -eq $Candidate -or $null -eq $Assignment) { return $null }
    $changes = @()
    foreach ($file in @($Assignment.assignedFiles)) {
        $match = @($Candidate.document.changes | Where-Object path -CEQ $file.path)
        if ($match.Count -eq 0) { return $null }
        if ($match.Count -ne 1 -or $match[0].operation -ne $file.operation) { throw 'Candidate conflicts with the approved assignment.' }
        $changes += $match[0]
    }
    if ($changes.Count -eq 0) { return $null }
    return [pscustomobject]@{
        agentId=$AgentId; stageId=$StageId; runId=$RunId; status='completed'; outcome='proposed'; batchId=$Assignment.batchId
        summary='Operator-authored recovery source reused verbatim. No model generated this batch; CI verification and independent review remain required.'
        evidence=@(@{source=$Candidate.path;description="Operator candidate SHA256 $($Candidate.sha256); source is bound to the preserved materialized change set."})
        assumptions=@();unknowns=@('Local verification does not prove deployed product behavior.');warnings=@();deferrals=@()
        details=@{authorship='operator';candidateSha256=$Candidate.sha256;verification=$Candidate.document.verification}
        changes=$changes
    }
}
