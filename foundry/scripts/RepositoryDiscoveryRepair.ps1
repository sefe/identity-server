# Scoped schema repair for discovery. This runs inside Invoke-Agent so provider
# calls retain the normal time budget, usage accounting and evidence records.
function Repair-RepositoryDiscoveryFields {
    param(
        [Parameter(Mandatory)][object[]]$Errors,
        [Parameter(Mandatory)][string]$ArtifactPath,
        [Parameter(Mandatory)][string]$SchemaPath,
        [Parameter(Mandatory)][string]$OriginalRequest,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][int]$Attempt
    )

    if ((Split-Path $SchemaPath -Leaf) -ne 'repository-discovery.schema.json' -or
        $TimeoutSeconds -le 0 -or $Errors.Count -eq 0 -or $Errors.Count -gt 40) { return $null }
    $document = Get-Content -LiteralPath $ArtifactPath -Raw | ConvertFrom-Json -Depth 100
    $requests = @()
    foreach ($error in $Errors) {
        $pointer = [string]$error.instancePath
        if ($error.keyword -eq 'maxLength' -and
            $pointer -match '^/details/componentStacks/\d+/(name|buildSystem|configurationApproach|loggingApproach|ciEnvironment)$') {
            $current = Get-QaFoundryPointerValue -Document $document -Pointer $pointer
            $limit = [int]$error.params.limit
            if ($current -isnot [string] -or $limit -le 0) { return $null }
            $requests += [pscustomobject]@{ pointer = $pointer; operation = 'replace'; limit = $limit; current = $current }
        }
        elseif ($error.keyword -eq 'required' -and $pointer -eq '/details' -and
            $error.params.missingProperty -eq 'excludedFromStackDetermination') {
            $requests += [pscustomobject]@{
                pointer = '/details/excludedFromStackDetermination'; operation = 'add'; limit = $null; current = $null
            }
        }
        else {
            # Paths, versions, identifiers, other missing fields and structural
            # errors still use the ordinary retry. Never repair them implicitly.
            return $null
        }
    }
    if (@($requests.pointer | Select-Object -Unique).Count -ne $requests.Count) { return $null }
    $repairRequest = @"
# Repair only the listed repository discovery fields

Keep the existing discovery document. Return only the requested field values,
not a new artifact. Each pointer below must appear exactly once. Do not alter
any other fields, component ordering, evidence, paths, versions or identifiers.

For overlong labels and descriptions, remove explanation and redundant wording
while preserving the component identity, build tools and all technical facts.
Keep embedded commands, paths, identifiers and literal values verbatim. Do not
truncate strings mechanically. If a faithful value cannot fit, return no
replacements instead of dropping facts.

For a missing excludedFromStackDetermination, derive the entries from the
original supplied repository context. Use the original schema's path and reason
shape. Do not invent entries or use an empty array just to pass validation. An
empty array is valid only if the supplied evidence supports no exclusions. If
the context is insufficient, return no replacements and leave the artifact
rejected. The runner will not synthesize a default value.

## Requested fields
$($requests | ConvertTo-Json -Depth 20)

## Existing discovery document
$($document | ConvertTo-Json -Depth 100)

## Original task, evidence and schema (context only)
$OriginalRequest

## Repair response format
The response for THIS call is only:
{"replacements":[{"pointer":"<requested pointer>","value":"<shorter text>"}]}
For excludedFromStackDetermination, value is the schema-valid array, not a string.
No extra properties, no unrequested pointers, no full document and no narration.
"@
    $requestPath = "$ArtifactPath.repair.request.md"
    Set-Content -LiteralPath $requestPath -Value $repairRequest -Encoding utf8
    Write-QaFoundryLog -Level step -Indent 2 -Scope $AgentId -Message (
        "Asking for $($requests.Count) discovery field(s) to be repaired; retaining the rest of the artifact.")
    $call = Invoke-AgentProviderCall -Provider $Provider -RequestPath $requestPath -RequestText $repairRequest `
        -MetadataPath "$ArtifactPath.attempt-$Attempt.repair.provider-metadata.json" `
        -Attempt $Attempt -Purpose field_repair -TimeoutSeconds $TimeoutSeconds
    if ($call.status -ne 'answered') {
        Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message 'Discovery field repair did not answer; retaining the rejected artifact.'
        return $null
    }
    Set-Content -LiteralPath "$ArtifactPath.repair.raw.txt" -Value $call.responseText -Encoding utf8
    try {
        $answer = ConvertFrom-QaFoundryAgentJson -RawText $call.responseText | ConvertFrom-Json -Depth 100
        $answerNames = @(Get-QaFoundryPropertyNames -InputObject $answer)
        if ($answerNames.Count -ne 1 -or $answerNames[0] -ne 'replacements' -or
            $answer.replacements -isnot [array]) { return $null }
        $replacements = @($answer.replacements)
        if ($replacements.Count -ne $requests.Count) { return $null }
        foreach ($replacement in $replacements) {
            $names = @(Get-QaFoundryPropertyNames -InputObject $replacement)
            if ($names.Count -ne 2 -or $names -notcontains 'pointer' -or $names -notcontains 'value' -or
                $replacement.pointer -isnot [string] -or $requests.pointer -cnotcontains $replacement.pointer) { return $null }
        }
        foreach ($request in $requests) {
            $matching = @($replacements | Where-Object { $_.pointer -ceq $request.pointer })
            if ($matching.Count -ne 1) { return $null }
            $value = $matching[0].value
            if ($request.operation -eq 'replace') {
                if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value.Length -gt $request.limit) { return $null }
                if (-not (Set-QaFoundryPointerValue -Document $document -Pointer $request.pointer -Value $value)) { return $null }
            }
            else {
                if ($value -isnot [array]) { return $null }
                $document.details | Add-Member -NotePropertyName excludedFromStackDetermination -NotePropertyValue $value
            }
        }
    }
    catch {
        Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message 'Discovery field repair was malformed; retaining the rejected artifact.'
        return $null
    }

    # Validate a separate candidate BEFORE publishing. Invalid repairs must not
    # erase the original answer or make partial edits visible to downstream work.
    $candidate = "$ArtifactPath.repair.candidate.tmp"
    try {
        $document | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $candidate -Encoding utf8
        $validation = & (Join-Path $PSScriptRoot 'Validate-JsonArtifact.ps1') `
            -ArtifactPath $candidate -SchemaPath $SchemaPath -NoThrow
        if (-not $validation.valid) {
            Write-QaFoundryLog -Level warn -Indent 2 -Scope $AgentId -Message 'Discovery field repair failed schema validation; retaining the rejected artifact.'
            return $null
        }
        [IO.File]::Move($candidate, $ArtifactPath, $true)
    }
    finally {
        Remove-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
    }
    [pscustomobject]@{
        artifact = [IO.Path]::GetFileName($ArtifactPath)
        repaired = @($requests | ForEach-Object { [pscustomobject]@{ pointer = $_.pointer; operation = $_.operation } })
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath "$ArtifactPath.repair.applied.json" -Encoding utf8
    return @($requests.pointer)
}
