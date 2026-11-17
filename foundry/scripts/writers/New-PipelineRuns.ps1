[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][string]$WorkItemResultPath,
    [Parameter(Mandatory)][string]$PipelineName,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$RunId,
    [string]$StageId = "queue-pipeline",
    [string]$Branch = "",
    [hashtable]$ActionEnvironment = @{}
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../Common.ps1")
if ($Config.ci.provider -eq 'github') {
    $workResult=Get-Content -LiteralPath $WorkItemResultPath -Raw | ConvertFrom-Json -Depth 100
    if (@($workResult.actions | Where-Object {$_.status -eq 'executed'}).Count) {
        throw 'GitHub issue-to-implementation dispatch is not enabled in this bootstrap release.'
    }
    return [pscustomobject]@{runId=$RunId;stageId=$StageId;handler='queue_pipeline';status='no_action_needed';dryRun=$true;actions=@();evidence=@($WorkItemResultPath)}
}

$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json -Depth 100 -ErrorAction Stop
$result = Get-Content -LiteralPath $WorkItemResultPath -Raw | ConvertFrom-Json -Depth 100 -ErrorAction Stop

$resultFields = @(Get-QaFoundryPropertyNames -InputObject $result)
if ($resultFields -notcontains "handler" -or [string]$result.handler -ne "create_work_items") {
    throw ("Queueing implementation reads the result of work item creation, but " +
        "'$WorkItemResultPath' was written by handler '$([string]$result.handler)'.")
}

# Only a task is implementable: a backlog item states the outcome its tasks deliver, so queueing one
# would implement the same work twice - once for the parent and once for each of its children. The
# type is not in the creation record, so it is read from the plan the creation acted on.
$typeBySourceRef = @{}
foreach ($item in @($plan.items)) {
    $typeBySourceRef[[string]$item.sourceRef] = [string]$item.type
}

# A run that only rehearsed work item creation has no work items to implement, so it must not start
# anything either.
$dryRun = [bool]$result.dryRun -or (
    (@(Get-QaFoundryPropertyNames -InputObject $Config.ci) -contains "dry_run") -and
    [bool]$Config.ci.dry_run
)

$organization = ([string]$Config.ci.azure_devops.organization_url).TrimEnd("/")
$project = [string]$Config.ci.azure_devops.project
$tokenName = [string]$Config.ci.azure_devops.auth_env
$ciAuthScheme = "basic"
if (@(Get-QaFoundryPropertyNames -InputObject $Config.ci.azure_devops) -contains "auth_scheme") {
    $configuredCiScheme = ([string]$Config.ci.azure_devops.auth_scheme).Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($configuredCiScheme)) { $ciAuthScheme = $configuredCiScheme }
}

# The marker lives on a work item, and work items belong to the work-tracking
# project, which is not always the project the pipelines live in. Reading and
# writing it through the CI settings worked only while the two happened to be
# the same: elsewhere the GET returns 404, the marker reads as absent, and every
# run queues the same implementation again.
$workTrackingSettings = $null
if ((@(Get-QaFoundryPropertyNames -InputObject $Config) -contains "work_tracking") -and
    (@(Get-QaFoundryPropertyNames -InputObject $Config.work_tracking) -contains "azure_devops")) {
    $workTrackingSettings = $Config.work_tracking.azure_devops
}
# An installation that tracks work nowhere else still has to read the marker, and
# the CI settings are the only Azure DevOps it has. Falling back to them keeps
# that case working; naming work_tracking is what makes the split case correct.
if ($null -eq $workTrackingSettings) { $workTrackingSettings = $Config.ci.azure_devops }
$markerOrganization = $organization
$markerProject = $project
if ($null -ne $workTrackingSettings) {
    $configuredOrganization = ([string]$workTrackingSettings.organization_url).TrimEnd("/")
    $configuredProject = [string]$workTrackingSettings.project
    if (-not [string]::IsNullOrWhiteSpace($configuredOrganization)) {
        $markerOrganization = $configuredOrganization
    }
    if (-not [string]::IsNullOrWhiteSpace($configuredProject)) { $markerProject = $configuredProject }
}

# The record that says "this task is already being implemented" has to survive the checkout it was
# written in. The local idempotency registry does not: CI starts every run from a fresh clone, so a
# second run would read an empty registry and open a second pull request for the same task. The work
# item itself is the one place both runs can see, so the marker lives there.
$implementationMarker = "sdlc-foundry-implementation-queued"

# The tag the implementation pipeline writes on the work item to elect itself as
# the one build implementing it. It is recognised here so that a marker cleared
# after a failed run does not leave the election tag behind: the next run would
# queue a build the template then refuses, which is the same deadlock one step
# further along.
$implementingTagPattern = '^sdlc-foundry-implementing-[0-9]+$'

# A claim is not the marker. The marker means "a run exists for this task"; a
# claim means "a run is trying to start one right now", and the two have to be
# distinguishable because they fail differently. A claim that outlives the run
# that wrote it would strand the task forever, so it carries who made it and
# when, and any later run may settle it by asking Azure DevOps what actually
# happened. Nothing here needs a person to remove a tag.
$claimPrefix = "sdlc-foundry-implementation-claim"
# Long enough that a run still queueing is never treated as dead, short enough
# that a crashed one does not hold a task for a working day.
$claimLifetimeSeconds = 1800

function New-ClaimTag {
    param([Parameter(Mandatory)][string]$RunIdentifier)

    # Azure DevOps tags are compared as whole strings and cannot contain ';', so
    # the parts are joined with a character that survives a round trip through
    # the tag field.
    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $safeRun = ($RunIdentifier -replace "[^A-Za-z0-9\-_]", "-")
    return "$claimPrefix.$safeRun.$stamp"
}

function Read-ClaimTag {
    param([Parameter(Mandatory)][string]$Tag)

    $parts = $Tag.Split(".")
    if ($parts.Count -lt 3 -or $parts[0] -ne $claimPrefix) { return $null }
    $stamp = 0L
    if (-not [long]::TryParse($parts[$parts.Count - 1], [ref]$stamp)) { return $null }
    return [pscustomobject]@{
        tag = $Tag
        runId = ($parts[1..($parts.Count - 2)] -join ".")
        claimedAt = [DateTimeOffset]::FromUnixTimeSeconds($stamp)
        ageSeconds = [int]([DateTimeOffset]::UtcNow - [DateTimeOffset]::FromUnixTimeSeconds($stamp)).TotalSeconds
    }
}

function Get-ClaimFromTags {
    param([string[]]$Tags = @())

    foreach ($tag in @($Tags)) {
        $claim = Read-ClaimTag -Tag ([string]$tag)
        if ($null -ne $claim) { return $claim }
    }
    return $null
}

function Get-AdoHeaders {
    return (Get-QaFoundryAzureDevOpsHeaders -AzureDevOpsConfig $workTrackingSettings `
        -Environment $ActionEnvironment -AllowProcessEnvironment `
        -Purpose "Reading the implementation marker").headers
}

function Get-CiHeaders {
    return (Get-QaFoundryAzureDevOpsHeaders -AzureDevOpsConfig $Config.ci.azure_devops `
        -Environment $ActionEnvironment -AllowProcessEnvironment `
        -Purpose "Settling an implementation claim against the runs that exist").headers
}

function Test-ImplementationRunExists {
    param(
        [Parameter(Mandatory)][string]$WorkItemId,
        [Parameter(Mandatory)][DateTimeOffset]$Since
    )

    # The one question that settles a stale claim: did a run actually start? The
    # implementation pipeline tags its own build with the work item it is
    # implementing, so Azure DevOps can answer it directly - and answering it
    # from the builds themselves is what makes a lost response recoverable
    # instead of permanent.
    $uri = "$organization/$([Uri]::EscapeDataString($project))/_apis/build/builds" +
        "?tagFilters=$([Uri]::EscapeDataString("work-item-$WorkItemId"))&api-version=7.1"
    try {
        $builds = @((Invoke-RestMethod -Method Get -Uri $uri -Headers (Get-CiHeaders)).value)
    } catch {
        # Unable to ask is not the same as "no run exists". Taking a claim over
        # on an unanswered question is how the duplicate this whole mechanism
        # exists to prevent would be created, so an unreadable answer keeps the
        # claim where it is.
        throw ("Work item $WorkItemId holds an expired implementation claim, and whether a run " +
            "already exists for it could not be read from Azure DevOps, so nothing was queued: " +
            $_.Exception.Message)
    }
    foreach ($build in $builds) {
        $queued = [DateTimeOffset]::MinValue
        if ((@(Get-QaFoundryPropertyNames -InputObject $build) -contains "queueTime") -and
            [DateTimeOffset]::TryParse([string]$build.queueTime, [ref]$queued)) {
            # A build from before the claim belongs to an earlier hand-off that
            # has already been accounted for.
            if ($queued -lt $Since.AddMinutes(-5)) { continue }
        }
        return $true
    }
    return $false
}

function Get-BuildOutcome {
    param([Parameter(Mandatory)][string]$BuildId)

    $uri = "$organization/$([Uri]::EscapeDataString($project))/_apis/build/builds/" +
        "$([Uri]::EscapeDataString($BuildId))?api-version=7.1"
    try {
        $build = Invoke-RestMethod -Method Get -Uri $uri -Headers (Get-CiHeaders)
    } catch {
        # A build Azure DevOps no longer has is a build that is not running. Any
        # other failure is a question that went unanswered, and an unanswered
        # question never authorises a takeover.
        $statusCode = 0
        if ($_.Exception.PSObject.Properties['Response'] -and $null -ne $_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($statusCode -eq 404) {
            return [pscustomobject][ordered]@{
                known = $true; state = "failed"; buildId = $BuildId; detail = "no longer exists"
            }
        }
        return [pscustomobject][ordered]@{
            known = $false; state = "unreadable"; buildId = $BuildId
            detail = $_.Exception.Message
        }
    }
    return (ConvertTo-BuildOutcome -Build $build)
}

function ConvertTo-BuildOutcome {
    param([Parameter(Mandatory)][object]$Build)

    $buildFields = @(Get-QaFoundryPropertyNames -InputObject $Build)
    $buildId = if ($buildFields -contains "id") { [string]$Build.id } else { "" }
    $status = if ($buildFields -contains "status") { "$($Build.status)".Trim().ToLowerInvariant() } else { "" }
    $result = if ($buildFields -contains "result") { "$($Build.result)".Trim().ToLowerInvariant() } else { "" }

    # Anything that is not finished is still someone else's to finish. Only a run
    # Azure DevOps reports as completed can be judged by its result.
    if ($status -ne "completed") {
        return [pscustomobject][ordered]@{
            known = $true; state = "active"; buildId = $buildId; detail = $status
        }
    }
    # A partial success produced a pull request as surely as a full one did.
    # Re-implementing on top of it would open a second.
    if ($result -in @("succeeded", "partiallysucceeded")) {
        return [pscustomobject][ordered]@{
            known = $true; state = "succeeded"; buildId = $buildId; detail = $result
        }
    }
    # A completed run with no result at all is not a run that did the work, but
    # it is not one this can prove died either, so it is treated as unfinished
    # rather than as an invitation to queue a second.
    if ([string]::IsNullOrWhiteSpace($result) -or $result -eq "none") {
        return [pscustomobject][ordered]@{
            known = $true; state = "active"; buildId = $buildId; detail = "completed without a result"
        }
    }
    return [pscustomobject][ordered]@{
        known = $true; state = "failed"; buildId = $buildId; detail = $result
    }
}

function Merge-BuildOutcomes {
    param([object[]]$Outcomes)

    # One live run is enough to leave the task alone, and one unanswered question
    # is enough to refuse. Only when every run that could be holding this task is
    # provably finished, and none of them finished by doing the work, is the task
    # free again.
    $unreadable = @($Outcomes | Where-Object { -not $_.known })
    if ($unreadable.Count -gt 0) {
        return [pscustomobject][ordered]@{
            known = $false; state = "unreadable"; buildId = [string]$unreadable[0].buildId
            detail = [string]$unreadable[0].detail; deadBuildIds = @()
        }
    }
    $active = @($Outcomes | Where-Object { $_.state -eq "active" })
    if ($active.Count -gt 0) {
        return [pscustomobject][ordered]@{
            known = $true; state = "active"; buildId = [string]$active[0].buildId
            detail = [string]$active[0].detail; deadBuildIds = @()
        }
    }
    $succeeded = @($Outcomes | Where-Object { $_.state -eq "succeeded" })
    if ($succeeded.Count -gt 0) {
        return [pscustomobject][ordered]@{
            known = $true; state = "succeeded"; buildId = [string]$succeeded[0].buildId
            detail = [string]$succeeded[0].detail; deadBuildIds = @()
        }
    }
    return [pscustomobject][ordered]@{
        known = $true; state = "failed"; buildId = [string]@($Outcomes)[0].buildId
        detail = [string]@($Outcomes)[0].detail
        deadBuildIds = @(@($Outcomes) | ForEach-Object { [string]$_.buildId } |
            Where-Object { $_ })
    }
}

function Get-ImplementationRunOutcome {
    param(
        [Parameter(Mandatory)][string]$WorkItemId,
        [string[]]$OwnerBuildIds = @()
    )

    # The marker says a run exists. It does not say the run finished, and a run
    # that failed or was cancelled leaves the marker behind - so a marker read on
    # its own turned every failed implementation into a task nothing would ever
    # pick up again. What settles it is the build the marker stands for.
    #
    # Which build that is, is not a question of recency. A duplicate run that the
    # election turned away fails seconds later and is the newest build carrying
    # the task's tag, while the run that actually holds the task carries on for
    # an hour. Judging by the newest would then clear a live owner's tags and let
    # a second implementation start alongside it. So the owners are the builds
    # the election tags name, and each of them is asked about by id.
    $owners = @(@($OwnerBuildIds) | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
    if ($owners.Count -gt 0) {
        return (Merge-BuildOutcomes -Outcomes @($owners | ForEach-Object {
            Get-BuildOutcome -BuildId $_
        }))
    }

    # No election tag: either the run never got as far as electing itself, or the
    # tag was lost. Then every build carrying the task's tag is a possible owner,
    # and the same rule applies to all of them at once.
    $uri = "$organization/$([Uri]::EscapeDataString($project))/_apis/build/builds" +
        "?tagFilters=$([Uri]::EscapeDataString("work-item-$WorkItemId"))&api-version=7.1"
    try {
        $builds = @((Invoke-RestMethod -Method Get -Uri $uri -Headers (Get-CiHeaders)).value)
    } catch {
        return [pscustomobject][ordered]@{
            known = $false; state = "unreadable"; buildId = ""
            detail = $_.Exception.Message; deadBuildIds = @()
        }
    }
    if ($builds.Count -eq 0) {
        return [pscustomobject][ordered]@{
            known = $true; state = "none"; buildId = ""; detail = ""; deadBuildIds = @()
        }
    }
    return (Merge-BuildOutcomes -Outcomes @($builds | ForEach-Object { ConvertTo-BuildOutcome -Build $_ }))
}

function Get-WorkItemState {
    param([Parameter(Mandatory)][string]$WorkItemId)

    # The revision comes back with the tags because the tags are written back as a
    # whole field: without the revision the write cannot say which version of the
    # field it edited, and a concurrent edit is overwritten instead of detected.
    $uri = "$markerOrganization/$([Uri]::EscapeDataString($markerProject))/_apis/wit/workitems/" +
        "$([Uri]::EscapeDataString($WorkItemId))?`$fields=System.Tags,System.Rev&api-version=7.1"
    $item = Invoke-RestMethod -Method Get -Uri $uri -Headers (Get-AdoHeaders)
    $itemFields = @(Get-QaFoundryPropertyNames -InputObject $item)
    $fields = if ($itemFields -contains "fields") { $item.fields } else { $null }
    $fieldNames = @(Get-QaFoundryPropertyNames -InputObject $fields)

    $tags = @()
    if ($null -ne $fields -and $fieldNames -contains "System.Tags") {
        $tags = @([string]$fields."System.Tags" -split ";" |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $revision = 0
    if ($itemFields -contains "rev") {
        $revision = [int]$item.rev
    } elseif ($null -ne $fields -and $fieldNames -contains "System.Rev") {
        $revision = [int]$fields."System.Rev"
    }

    return [pscustomobject][ordered]@{ tags = @($tags); revision = $revision }
}

function Set-WorkItemTags {
    param(
        [Parameter(Mandatory)][string]$WorkItemId,
        [string[]]$Tags = @(),
        [int]$Revision = 0
    )

    $uri = "$markerOrganization/$([Uri]::EscapeDataString($markerProject))/_apis/wit/workitems/" +
        "$([Uri]::EscapeDataString($WorkItemId))?api-version=7.1"
    $patch = [System.Collections.Generic.List[object]]::new()
    if ($Revision -gt 0) {
        # A JSON Patch 'test' makes the whole document conditional: Azure DevOps
        # applies it only while the item is still at the revision that was read.
        # Without it two runs that read the same tags both write, and the second
        # write silently discards the first - which is how the same task was
        # handed on twice, and how a person's tags disappeared.
        $patch.Add([ordered]@{ op = "test"; path = "/rev"; value = $Revision })
    }
    # Azure DevOps replaces the whole tag field, so the tags already on the item are sent back with
    # the marker. Writing the marker alone would silently strip whatever a person had put there.
    $patch.Add([ordered]@{
        op = "add"; path = "/fields/System.Tags"
        value = (@($Tags) | Select-Object -Unique) -join "; "
    })
    $null = Invoke-RestMethod -Method Patch -Uri $uri -Headers (Get-AdoHeaders) `
        -ContentType "application/json-patch+json" `
        -Body (@($patch) | ConvertTo-Json -Depth 10 -AsArray)
}

function Request-ImplementationReservation {
    param([Parameter(Mandatory)][string]$WorkItemId)

    # Reading the marker and then queueing leaves a window in which a second run
    # reads the same absence and queues the same implementation. Claiming it
    # first closes the window: the claim is the same conditional write both runs
    # attempt, and exactly one of them can win.
    #
    # The tag is built once rather than per attempt. Azure DevOps can commit a
    # write whose answer never arrives, and a retry then reads a claim that is
    # this run's own. With a fresh tag each time that claim is unrecognisable and
    # the run stands down from itself, reporting a duplicate for a task nothing
    # is implementing - the same silent loss the claim exists to prevent.
    $claimTag = New-ClaimTag -RunIdentifier $RunId
    $attempts = 3
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $state = Get-WorkItemState -WorkItemId $WorkItemId
        $carriedTags = @($state.tags)
        if (@($state.tags) -contains $implementationMarker) {
            # The marker is a statement about a run, so it is read against that
            # run rather than on its own. A run still going, or one that reached
            # a pull request, is the end of it for this run. A run that failed or
            # was cancelled leaves work nobody is doing, and refusing to touch it
            # is how a task stays stuck until a person notices - which on an
            # unattended pipeline is never.
            $ownerBuildIds = @(@($state.tags) |
                Where-Object { $_ -match $implementingTagPattern } |
                ForEach-Object { ($_ -replace '^sdlc-foundry-implementing-', '') })
            $outcome = Get-ImplementationRunOutcome -WorkItemId $WorkItemId `
                -OwnerBuildIds $ownerBuildIds
            if (-not $outcome.known) {
                return [pscustomobject][ordered]@{
                    reserved = $false; tags = @($state.tags); claimTag = ""
                    reason = ("Work item $WorkItemId is marked as being implemented and what " +
                        "became of that run could not be read from Azure DevOps, so nothing was " +
                        "queued: $([string]$outcome.detail)")
                }
            }
            if ($outcome.state -ne "failed") {
                $reason = switch ([string]$outcome.state) {
                    "active" { "and build $([string]$outcome.buildId) is still $([string]$outcome.detail)" }
                    "succeeded" { "and build $([string]$outcome.buildId) $([string]$outcome.detail)" }
                    default { "and no build carrying its tag remains to be re-run" }
                }
                return [pscustomobject][ordered]@{
                    reserved = $false; tags = @($state.tags); claimTag = ""
                    reason = "Work item $WorkItemId is already being implemented by an earlier run, $reason."
                }
            }
            # The run that held this task died. Its marker goes, and with it the
            # election tags of the builds that were proven dead - and only those.
            # Leaving a dead build's election tag would let this run queue a
            # build the template then refuses, which is the same deadlock one
            # step further along; removing a live build's tag would let a second
            # implementation start beside the first, which is worse.
            $deadTags = @(@($outcome.deadBuildIds) |
                ForEach-Object { "sdlc-foundry-implementing-$_" })
            $carriedTags = @(@($carriedTags) |
                Where-Object { $_ -ne $implementationMarker -and $deadTags -notcontains $_ })
        }

        $existingClaim = Get-ClaimFromTags -Tags @($state.tags)
        if ($null -ne $existingClaim) {
            # This run's own claim, from a write that landed without saying so.
            if ($existingClaim.tag -eq $claimTag -or $existingClaim.runId -eq $RunId) {
                return [pscustomobject][ordered]@{
                    reserved = $true
                    tags = @(@($state.tags) | Where-Object { $_ -ne $existingClaim.tag })
                    claimTag = $existingClaim.tag; reason = ""
                }
            }
            if ($existingClaim.ageSeconds -lt $claimLifetimeSeconds) {
                return [pscustomobject][ordered]@{
                    reserved = $false; tags = @($state.tags); claimTag = ""
                    reason = ("Run $($existingClaim.runId) claimed work item $WorkItemId " +
                        "$($existingClaim.ageSeconds)s ago and may still be starting it.")
                }
            }
            # The claiming run is gone. Whether it managed to start anything
            # before it went is a question about builds, and Azure DevOps still
            # has the answer, so the claim is settled from the runs that exist
            # rather than left for a person to clear.
            if (Test-ImplementationRunExists -WorkItemId $WorkItemId -Since $existingClaim.claimedAt) {
                try {
                    Set-WorkItemTags -WorkItemId $WorkItemId -Revision $state.revision `
                        -Tags (@(@($state.tags) | Where-Object { $_ -ne $existingClaim.tag }) +
                            @($implementationMarker))
                } catch { }
                return [pscustomobject][ordered]@{
                    reserved = $false; tags = @($state.tags); claimTag = ""
                    reason = ("Run $($existingClaim.runId) left an expired claim on work item " +
                        "$WorkItemId, and the run it started does exist, so the hand-off is " +
                        "recorded rather than repeated.")
                }
            }
            # Nothing was ever started under that claim, so it is this run's to take.
            # A run that was queued but has not begun executing is not visible in
            # the builds this asks about, so this could in principle queue a
            # second one. That case is settled where it can be settled atomically:
            # both runs elect a single implementer through a revision-guarded
            # write on the work item itself, and the one that loses stops.
            $carriedTags = @(@($carriedTags) | Where-Object { $_ -ne $existingClaim.tag })
        }

        try {
            Set-WorkItemTags -WorkItemId $WorkItemId `
                -Tags (@($carriedTags) + @($claimTag)) -Revision $state.revision
            return [pscustomobject][ordered]@{
                reserved = $true; tags = @($carriedTags); claimTag = $claimTag; reason = ""
            }
        } catch {
            # The claim was refused. Either someone else claimed it or the item
            # moved on for an unrelated reason, and the next read tells which -
            # so this retries rather than deciding from the error text, which
            # Azure DevOps words differently across versions.
            if ($attempt -eq $attempts) {
                throw ("Work item $WorkItemId changed under every attempt to claim it for " +
                    "implementation, so nothing was queued: $($_.Exception.Message)")
            }
        }
    }
}

function Complete-ImplementationReservation {
    param(
        [Parameter(Mandatory)][string]$WorkItemId,
        [Parameter(Mandatory)][string]$ClaimTag
    )

    # The claim becomes the marker only once a run exists. Until then the tag on
    # the item says exactly what is true: a run is trying to start one.
    $state = Get-WorkItemState -WorkItemId $WorkItemId
    $tags = @(@($state.tags) | Where-Object { $_ -ne $ClaimTag }) + @($implementationMarker)
    Set-WorkItemTags -WorkItemId $WorkItemId -Tags $tags -Revision $state.revision
}

function Remove-ImplementationReservation {
    param(
        [Parameter(Mandatory)][string]$WorkItemId,
        [Parameter(Mandatory)][string]$ClaimTag
    )

    # Releasing re-reads rather than reusing the tags the claim was built on: the
    # item may have been edited since, and a release must not undo that edit.
    $state = Get-WorkItemState -WorkItemId $WorkItemId
    $remaining = @(@($state.tags) | Where-Object { $_ -ne $ClaimTag })
    Set-WorkItemTags -WorkItemId $WorkItemId -Tags $remaining -Revision $state.revision
}

function Test-QueueRejectedRequest {
    param($ErrorRecord)

    # Whether the run was queued decides whether the claim may be released now or
    # left to expire. A refusal is an answer: Azure DevOps saw the request and
    # declined it, so no run exists. A timeout or a dropped connection is not an
    # answer - the run may well have started - and releasing on those is what
    # turns one lost response into two implementations of the same task.
    #
    # The order of these checks matters. On PowerShell 7 a non-2xx response
    # throws HttpResponseException, which derives from HttpRequestException, so
    # a type test alone reads every plain refusal as a lost connection and
    # strands the task. The response is therefore looked for first.
    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        $response = $exception.psobject.Properties["Response"]
        if ($null -ne $response -and $null -ne $response.Value) {
            $status = 0
            try { $status = [int]$response.Value.StatusCode } catch { $status = 0 }
            # A server error may have been applied before it was reported, so
            # only a client-side refusal counts as "certainly nothing happened".
            return ($status -ge 400 -and $status -lt 500)
        }
        $exception = $exception.InnerException
    }
    $exception = $ErrorRecord.Exception
    while ($null -ne $exception) {
        if ($exception -is [System.Net.Http.HttpRequestException] -or
            $exception -is [System.Net.WebException] -or
            $exception -is [System.TimeoutException] -or
            $exception -is [System.OperationCanceledException]) {
            return $false
        }
        $exception = $exception.InnerException
    }
    # Nothing reached Azure DevOps at all: the failure happened while this run was
    # still preparing the request, so there is certainly nothing to wait for.
    return $true
}

$ref = $Branch.Trim()
if ([string]::IsNullOrWhiteSpace($ref)) {
    $ref = [string][Environment]::GetEnvironmentVariable("BUILD_SOURCEBRANCH")
}
if ([string]::IsNullOrWhiteSpace($ref)) {
    # The queued run needs a ref to read its YAML from, and the honest answer is the branch this run
    # is analysing: the pipeline it starts is the one that exists beside the code that caused it.
    Push-Location $RepositoryRoot
    try { $ref = (& git rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1) }
    finally { Pop-Location }
}
if ([string]::IsNullOrWhiteSpace($ref) -or $ref -eq "HEAD") {
    throw "Queueing '$PipelineName' requires the branch its definition should run from."
}

$registryPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot ([string]$Config.idempotency.registry_path)))
$repositoryPrefix = (Resolve-Path $RepositoryRoot).Path.TrimEnd([IO.Path]::DirectorySeparatorChar) +
    [IO.Path]::DirectorySeparatorChar
if (-not $registryPath.StartsWith($repositoryPrefix, [StringComparison]::Ordinal)) {
    throw "Idempotency registry must stay inside the target repository."
}

$actions = [System.Collections.Generic.List[object]]::new()
foreach ($action in @($result.actions)) {
    $sourceRef = [string]$action.sourceRef
    $workItemId = [string]$action.externalId
    if (-not $typeBySourceRef.ContainsKey($sourceRef)) { continue }
    if ([string]$typeBySourceRef[$sourceRef] -ne "task") { continue }
    # 'duplicate' means an earlier run filed this task, not that an earlier run handed it on: a run
    # that created the task and then failed to queue it would report 'duplicate' forever and the
    # task would never be implemented. Both are candidates, and the marker on the work item - not
    # the creation status - decides whether the hand-off already happened.
    if ([string]$action.status -notin @("executed", "duplicate")) { continue }
    if ([string]::IsNullOrWhiteSpace($workItemId)) { continue }

    $key = & (Join-Path $PSScriptRoot "../New-IdempotencyKey.ps1") `
        -ActionType "pipeline-run.$PipelineName" -SourceRef $workItemId

    if (-not $dryRun) {
        $reservation = Request-ImplementationReservation -WorkItemId $workItemId
        if (-not $reservation.reserved) {
            $actions.Add([pscustomobject][ordered]@{
                sourceRef = $sourceRef; type = "pipeline-run.azure-devops"; parentRef = ""
                idempotencyKey = $key; status = "duplicate"
                externalId = ""
                summary = [string]$reservation.reason
            })
            continue
        }
    }

    try {
        $run = & (Join-Path $PSScriptRoot "Start-AdoPipelineRun.ps1") `
            -PipelineName $PipelineName -Organization $organization -Project $project `
            -Branch $ref -TemplateParameters @{ workItemId = $workItemId; handoffKey = $key } `
            -TokenEnvironmentName $tokenName -AuthScheme $ciAuthScheme `
            -ActionEnvironment $ActionEnvironment -DryRun:$dryRun
    } catch {
        if ($dryRun) { throw }
        if (Test-QueueRejectedRequest -ErrorRecord $_) {
            # Azure DevOps refused the request, so no run exists and the task must
            # stay implementable. Holding the claim here is what would strand it.
            Remove-ImplementationReservation -WorkItemId $workItemId -ClaimTag $reservation.claimTag
            throw
        }
        throw ("Queueing '$PipelineName' for work item $workItemId did not complete, and Azure " +
            "DevOps may still have started it. The implementation claim on the work item was " +
            "left in place so a retry cannot implement it twice. The claim expires after " +
            "$claimLifetimeSeconds seconds, after which the next run settles it against the " +
            "builds Azure DevOps actually holds - no manual step is required. " +
            $_.Exception.Message)
    }
    if (-not $dryRun) {
        # The run exists now, so the claim becomes the durable marker. A failure
        # here is recoverable on its own: the claim is still in place, and the
        # build it names is what a later run finds when it settles it.
        Complete-ImplementationReservation -WorkItemId $workItemId -ClaimTag $reservation.claimTag
    }
    $status = if ($dryRun) { "dry_run" } else { "executed" }
    if ([bool]$Config.idempotency.enabled) {
        $null = & (Join-Path $PSScriptRoot "../Use-IdempotencyRegistry.ps1") -Operation register `
            -RegistryPath $registryPath -Key $key -ActionType "pipeline-run.azure-devops" `
            -SourceRef $workItemId -Status $status -RunId $RunId -ExternalId ([string]$run.runId)
    }
    $actions.Add([pscustomobject][ordered]@{
        sourceRef = $sourceRef; type = "pipeline-run.azure-devops"; parentRef = ""
        idempotencyKey = $key; status = $status
        externalId = [string]$run.runId
        summary = "$PipelineName queued on $ref for work item $workItemId."
    })
}

return [pscustomobject][ordered]@{
    runId = $RunId
    stageId = $StageId
    handler = "queue_pipeline"
    status = if ($actions.Count -eq 0) { "no_action_needed" } else { "completed" }
    dryRun = $dryRun
    actions = @($actions)
    evidence = @($PlanPath, $WorkItemResultPath)
}
