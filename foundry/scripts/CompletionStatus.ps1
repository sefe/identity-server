function Get-QaFoundryDeferralKind {
    param([Parameter(Mandatory)][object]$Deferral, [switch]$RuntimeBudgetDeferral)
    if ($RuntimeBudgetDeferral) { return 'output_budget' }
    $property = $Deferral.PSObject.Properties['kind']
    if ($null -eq $property) { return 'unclassified' }
    $kind = [string]$property.Value
    if ($kind -notin @('output_budget', 'artifact_invalid', 'external_prerequisite', 'product_gap', 'unclassified')) {
        return 'unclassified'
    }
    return $kind
}

function Get-QaFoundryCompletionDisposition {
    param([AllowEmptyCollection()][object[]]$Deferrals = @())
    if ($Deferrals.Count -eq 0) { return 'completed' }
    foreach ($deferral in $Deferrals) {
        if ((Get-QaFoundryDeferralKind -Deferral $deferral) -notin @('output_budget', 'artifact_invalid')) {
            return 'blocked'
        }
    }
    return 'revision_required'
}

function Get-QaFoundryArtifactDeferrals {
    param([Parameter(Mandatory)][string]$PublishedPath)
    $openDeferrals = [System.Collections.Generic.List[object]]::new()
    # The artifact's own declaration is the authoritative one: an agent that
    # left work out says so in the document it signed, and that document is
    # what every later stage reads. Anything that is not a readable agent
    # artifact simply has nothing to declare.
    $document = $null
    try {
        $raw = Get-Content -LiteralPath $publishedPath -Raw
        # Change sets run to tens of megabytes, and rebuilding one as an object
        # to look for a field it cannot have costs the stage real time. The name
        # has to appear in the text before the document is worth parsing.
        if ("$raw".Contains('"deferrals"')) {
            $document = $raw | ConvertFrom-Json -Depth 60
        }
    }
    catch { $document = $null }
    if ($null -ne $document -and
        (Get-QaFoundryPropertyNames -InputObject $document) -contains "deferrals") {
        foreach ($deferral in @($document.deferrals)) {
            if ($null -eq $deferral) { continue }
            $openDeferrals.Add([pscustomobject]@{
                agentId = [string]$document.agentId
                item = [string]$deferral.item
                reason = [string]$deferral.reason
                kind = Get-QaFoundryDeferralKind -Deferral $deferral
            })
        }
    }
    # The sidecar carries what the artifact cannot: how much budget was cut,
    # after how many attempts, and — when the artifact was written under a cut
    # budget and still named nothing left out — the assignment the run entered
    # in its place. Those entries count exactly like the artifact's own, and a
    # sidecar that exists and cannot be read must not pass for "nothing was
    # left out".
    $coveragePath = "$publishedPath.coverage.json"
    if (-not (Test-Path -LiteralPath $coveragePath -PathType Leaf)) { return @($openDeferrals) }
    try {
        $coverage = Get-Content -LiteralPath $coveragePath -Raw | ConvertFrom-Json -Depth 40
        if ((Get-QaFoundryPropertyNames -InputObject $coverage) -contains "deferralsSource" -and
            [string]$coverage.deferralsSource -eq "run") {
            foreach ($deferral in @($coverage.deferrals)) {
                if ($null -eq $deferral) { continue }
                $openDeferrals.Add([pscustomobject]@{
                    agentId = [string]$coverage.agentId
                    item = [string]$deferral.item
                    reason = [string]$deferral.reason
                    kind = Get-QaFoundryDeferralKind -Deferral $deferral -RuntimeBudgetDeferral
                })
            }
        }
    }
    catch {
        $openDeferrals.Add([pscustomobject]@{
            agentId = (Split-Path $publishedPath -Leaf)
            item = "its record of what was left out could not be read"
            reason = $_.Exception.Message
            kind = 'unclassified'
        })
    }

    return @($openDeferrals)
}
