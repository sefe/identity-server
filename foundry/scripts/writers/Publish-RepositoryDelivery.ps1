[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RunId,
    [string]$StageId = "deliver-changes",
    [string]$ChangeSetPath = "",
    [hashtable]$ActionEnvironment = @{}
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../Common.ps1")
$dryRun = [bool]$Config.delivery.dry_run
$azureCredential = $null
$committerName = ""
$committerEmail = ""
$liveDeliveryRequested = -not $dryRun -and (
    [bool]$Config.delivery.create_branch -or
    [bool]$Config.delivery.commit_changes -or
    [bool]$Config.delivery.push_branch -or
    [bool]$Config.delivery.create_draft_pull_request
)
if ($liveDeliveryRequested -and -not [bool]$Config.idempotency.enabled) {
    throw (
        "Live repository delivery requires idempotency.enabled=true so partial Git or " +
        "Azure DevOps writes cannot be reported as no_action_needed on a retry."
    )
}
Assert-QaFoundryRehearsalNotDelivered -ChangeSetPath $ChangeSetPath `
    -DeliveryIsLive (Test-QaFoundryDeliveryLeavesMachine -DeliveryConfig $Config.delivery) `
    -Context "Stage '$StageId'"
# What that registry actually guarantees is narrower than it looks. It lives in
# the target working tree, is not committed, and is not carried between relay
# legs or between builds, so it settles repeated writes within one checkout and
# nothing wider. Across builds, the stable delivery branch and its pull request
# are discovered from Azure DevOps before publication.

# A pull request that nobody is required to review is validated before a branch
# or commit exists, so correcting the configuration leaves no repository state.
if ([bool]$Config.delivery.create_draft_pull_request -and
    ($Config.delivery.PSObject.Properties.Name -contains "require_reviewer_group") -and
    [bool]$Config.delivery.require_reviewer_group) {
    $configuredReviewers = @(@($Config.delivery.reviewers) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($configuredReviewers.Count -eq 0) {
        throw "delivery.require_reviewer_group is true but delivery.reviewers is empty."
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$FailureMessage
    )
    $output = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        # Without git's own message the failure is undiagnosable from a build log.
        $detail = (@($output) -join "`n").Trim()
        if ([string]::IsNullOrWhiteSpace($detail)) { throw $FailureMessage }
        throw ($FailureMessage + " git reported: " + $detail)
    }
    # git writes warnings, hints and progress to stderr even when it succeeds,
    # and the redirection above merges them into this stream so that a failure
    # can be explained. Handing them back as though they were output is how a
    # commit id becomes "warning: ... <sha>": the caller casts an array to a
    # string and gets the notice glued to the value it asked for.
    return @($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] })
}

function Invoke-GitAsUser {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$FailureMessage,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Email
    )
    $values = [ordered]@{
        GIT_AUTHOR_NAME = $Name
        GIT_AUTHOR_EMAIL = $Email
        GIT_COMMITTER_NAME = $Name
        GIT_COMMITTER_EMAIL = $Email
    }
    $previous = @{}
    try {
        foreach ($item in $values.GetEnumerator()) {
            $previousValue = [Environment]::GetEnvironmentVariable($item.Key, "Process")
            $previous[$item.Key] = [pscustomobject]@{
                exists = $null -ne $previousValue
                value = $previousValue
            }
            [Environment]::SetEnvironmentVariable($item.Key, [string]$item.Value, "Process")
        }
        return @(Invoke-Git -Arguments $Arguments -FailureMessage $FailureMessage)
    }
    finally {
        foreach ($item in $values.GetEnumerator()) {
            if (-not [bool]$previous[$item.Key].exists) {
                [Environment]::SetEnvironmentVariable(
                    $item.Key,
                    [NullString]::Value,
                    "Process"
                )
            }
            else {
                [Environment]::SetEnvironmentVariable(
                    $item.Key,
                    [string]$previous[$item.Key].value,
                    "Process"
                )
            }
        }
    }
}

function Invoke-GitWithAuthorization {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$FailureMessage,
        [Parameter(Mandatory)][string]$Authorization
    )

    $countValue = [Environment]::GetEnvironmentVariable("GIT_CONFIG_COUNT", "Process")
    $baseCount = 0
    if (-not [string]::IsNullOrWhiteSpace($countValue) -and
        -not [int]::TryParse($countValue, [ref]$baseCount)) {
        throw "GIT_CONFIG_COUNT is not a valid integer."
    }
    if ($baseCount -lt 0) { throw "GIT_CONFIG_COUNT may not be negative." }

    $names = @(
        "GIT_CONFIG_COUNT",
        "GIT_CONFIG_KEY_$baseCount",
        "GIT_CONFIG_VALUE_$baseCount",
        "GIT_CONFIG_KEY_$($baseCount + 1)",
        "GIT_CONFIG_VALUE_$($baseCount + 1)",
        "GIT_TERMINAL_PROMPT"
    )
    $previous = @{}
    foreach ($name in $names) {
        $previousValue = [Environment]::GetEnvironmentVariable($name, "Process")
        $previous[$name] = [pscustomobject]@{
            exists = $null -ne $previousValue
            value = $previousValue
        }
    }
    try {
        [Environment]::SetEnvironmentVariable(
            "GIT_CONFIG_COUNT",
            [string]($baseCount + 2),
            "Process"
        )
        [Environment]::SetEnvironmentVariable(
            "GIT_CONFIG_KEY_$baseCount",
            "http.extraHeader",
            "Process"
        )
        [Environment]::SetEnvironmentVariable(
            "GIT_CONFIG_VALUE_$baseCount",
            "",
            "Process"
        )
        [Environment]::SetEnvironmentVariable(
            "GIT_CONFIG_KEY_$($baseCount + 1)",
            "http.extraHeader",
            "Process"
        )
        [Environment]::SetEnvironmentVariable(
            "GIT_CONFIG_VALUE_$($baseCount + 1)",
            "Authorization: $Authorization",
            "Process"
        )
        [Environment]::SetEnvironmentVariable("GIT_TERMINAL_PROMPT", "0", "Process")
        return @(Invoke-Git -Arguments $Arguments -FailureMessage $FailureMessage)
    }
    finally {
        foreach ($name in $names) {
            if (-not [bool]$previous[$name].exists) {
                [Environment]::SetEnvironmentVariable(
                    $name,
                    [NullString]::Value,
                    "Process"
                )
            }
            else {
                [Environment]::SetEnvironmentVariable(
                    $name,
                    [string]$previous[$name].value,
                    "Process"
                )
            }
        }
    }
}

$actions = [System.Collections.Generic.List[object]]::new()
# What gets published is the change set the reviewers approved, named by the
# caller. Searching the run directory for the newest file of that name finds
# every superseded draft a critic loop left behind, and on a run that carries
# more than one change set it finds whichever was written last, which is not a
# statement about what was approved. The search survives only as a fallback for
# callers that have nothing to name, and it says so.
$changeSetPathToRead = ""
if (-not [string]::IsNullOrWhiteSpace($ChangeSetPath)) {
    if (-not (Test-Path -LiteralPath $ChangeSetPath -PathType Leaf)) {
        throw "The change set to deliver was named as '$ChangeSetPath', which does not exist."
    }
    $changeSetPathToRead = $ChangeSetPath
}
else {
    $changeSetFiles = @(Get-ChildItem -Path $RunRoot -File -Recurse -Filter "change-set.json" |
        Sort-Object LastWriteTimeUtc, FullName -Descending)
    if ($changeSetFiles.Count -gt 1) {
        Write-QaFoundryLog -Level warn -Message (
            "This run holds $($changeSetFiles.Count) change sets and the caller named none, so " +
            "delivery falls back to the most recently written one: " +
            "$($changeSetFiles[0].FullName).")
    }
    if ($changeSetFiles.Count -gt 0) { $changeSetPathToRead = $changeSetFiles[0].FullName }
}
$approvedChanges = @()
$proposedPaths = if ($changeSetPathToRead -ne "") {
    $changeSet = Get-Content -LiteralPath $changeSetPathToRead -Raw |
        ConvertFrom-Json -Depth 100 -ErrorAction Stop
    $approvedChanges = @($changeSet.changes | Where-Object { $null -ne $_ })
    @($changeSet.changes | ForEach-Object { ([string]$_.path).Replace("\", "/") } | Select-Object -Unique)
} else { @() }
$proposedPaths = @($proposedPaths)
if ($proposedPaths.Count -eq 0) {
    return [pscustomobject][ordered]@{
        runId = $RunId; stageId = $StageId; handler = "deliver_changes"
        status = "no_action_needed"; dryRun = $dryRun; actions = @(); evidence = @()
    }
}
$gitChangedPaths = @(& (Join-Path $PSScriptRoot "../Get-GitChangedPaths.ps1") -RepositoryRoot $RepositoryRoot)
# Git path identity is case-sensitive, and the Linux agents these pipelines run on
# will happily hold both 'automation/foo.yml' and 'Automation/foo.yml'. PowerShell's
# -in folds case on every platform, so an unproposed file whose path differs only by
# case would be treated as approved, staged, and committed. The comparison below is
# ordinal, which is the only comparison git itself makes.
$proposedPathSet = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@($proposedPaths), [System.StringComparer]::Ordinal)
$changedPaths = @($gitChangedPaths | Where-Object { $proposedPathSet.Contains([string]$_) })
# Dropping a case-only near-miss silently would trade one wrong outcome for another:
# on a case-folding file system a proposed 'automation/foo.yml' can land inside an
# existing 'Automation/' and be reported by git under that spelling, and quietly
# delivering nothing reads exactly like having nothing to deliver. Either way the
# working tree does not hold what was approved, and that is worth stopping for.
$proposedPathsFolded = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@($proposedPaths), [System.StringComparer]::OrdinalIgnoreCase)
$caseMismatches = @($gitChangedPaths | Where-Object {
    -not $proposedPathSet.Contains([string]$_) -and $proposedPathsFolded.Contains([string]$_)
})
if ($caseMismatches.Count -gt 0) {
    throw ("The working tree holds $($caseMismatches.Count) change(s) whose path differs from an " +
        "approved path only by letter case, and git tells those apart: " +
        (@($caseMismatches | Select-Object -First 10) -join ", ") +
        ". Delivering them would commit a file nobody approved, and skipping them would deliver " +
        "less than was approved. Correct the casing in the repository and run again.")
}
foreach ($path in $changedPaths) {
    $null = & (Join-Path $PSScriptRoot "../Test-RepositoryPathScope.ps1") `
        -Path $path -Config $Config -RepositoryRoot $RepositoryRoot
}
# Paths were compared. Bytes were not, and bytes are what a pull request carries.
#
# Between the change set being applied and this point the run installs packages,
# builds the framework and runs the tests, and any of those can rewrite a file
# that was approved: a formatter run by a build, a lock file an install
# regenerates, a project file an SDK touches. Comparing paths alone hands
# whatever they left behind the approval that was given to something else. The
# opposite miss is quieter still - a step that puts an approved file back the
# way it was takes it out of git's list of changes, and the pull request goes
# out missing work nobody agreed to drop.
#
# So every approved change is checked against what is on disk now: the same
# bytes for a create or an update, and gone for a delete. The content is
# compared as it was written - UTF-8 with no byte order mark and no newline
# added - because that is what applying the change set puts there.
$repositoryPrefix = (Resolve-Path -LiteralPath $RepositoryRoot).Path.TrimEnd([char]"\", [char]"/") +
    [System.IO.Path]::DirectorySeparatorChar
$drift = [System.Collections.Generic.List[string]]::new()
foreach ($change in $approvedChanges) {
    $relative = ([string]$change.path).Replace("\", "/")
    $absolute = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot $relative))
    if (-not $absolute.StartsWith($repositoryPrefix, [StringComparison]::Ordinal)) {
        $drift.Add("$relative resolves outside the repository")
        continue
    }
    $onDisk = Test-Path -LiteralPath $absolute -PathType Leaf
    if ([string]$change.operation -eq "delete") {
        if ($onDisk) { $drift.Add("$relative was approved for deletion and is still there") }
        continue
    }
    if (-not $onDisk) {
        $drift.Add("$relative was approved but is no longer there")
        continue
    }
    if ((Get-QaFoundryPropertyNames -InputObject $change) -notcontains "content") {
        $drift.Add("$relative was approved without a record of what it should contain")
        continue
    }
    $approvedHash = [BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData(
        [System.Text.Encoding]::UTF8.GetBytes([string]$change.content))).Replace("-", "").ToLowerInvariant()
    $actualHash = (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $approvedHash) {
        $drift.Add("$relative holds different bytes from the ones that were approved")
    }
}
if ($drift.Count -gt 0) {
    throw ("The working tree no longer matches the change set that was approved, so a pull request " +
        "raised from it would not be the one anybody reviewed. $($drift.Count) difference(s): " +
        (@($drift | Select-Object -First 10) -join "; ") +
        ". Something rewrote these after they were applied - a build, an install or a test run is " +
        "the usual cause - and the run stops rather than deliver bytes nobody approved.")
}
if ($changedPaths.Count -eq 0) {
    $nothingToStage = $true
}
else {
    $nothingToStage = $false
}

function Get-RunWorkItemIds {
    # A pull request that does not name the work it implements is untraceable,
    # so the identifiers created earlier in this run are collected here rather
    # than being configured by hand.
    $ids = [System.Collections.Generic.List[string]]::new()
    foreach ($configured in @($Config.delivery.work_items)) {
        $value = [string]$configured
        if (-not [string]::IsNullOrWhiteSpace($value) -and -not $ids.Contains($value)) {
            $ids.Add($value)
        }
    }
    # A run started to implement one work item creates none, so the item it was handed is the only
    # thing that connects the pull request to the reason it exists.
    $eventPath = Join-Path $RunRoot "context/sdlc-event.json"
    if (Test-Path -LiteralPath $eventPath -PathType Leaf) {
        $event = try {
            Get-Content -LiteralPath $eventPath -Raw | ConvertFrom-Json -Depth 50
        }
        catch { $null }
        if ($null -ne $event -and $event.PSObject.Properties.Name -contains "correlation" -and
            $event.correlation.PSObject.Properties.Name -contains "workItemId") {
            $value = [string]$event.correlation.workItemId
            if (-not [string]::IsNullOrWhiteSpace($value) -and -not $ids.Contains($value)) {
                $ids.Add($value)
            }
        }
    }
    foreach ($resultFile in @(Get-ChildItem -Path $RunRoot -File -Recurse -Filter "action-result.json")) {
        $result = try {
            Get-Content -LiteralPath $resultFile.FullName -Raw | ConvertFrom-Json -Depth 100
        }
        catch { continue }
        if ($result.PSObject.Properties.Name -notcontains "handler" -or
            [string]$result.handler -ne "create_work_items") {
            continue
        }
        foreach ($action in @($result.actions)) {
            if ([string]$action.status -notin @("executed", "duplicate")) { continue }
            $value = [string]$action.externalId
            if (-not [string]::IsNullOrWhiteSpace($value) -and -not $ids.Contains($value)) {
                $ids.Add($value)
            }
        }
    }
    return @($ids)
}

function Get-ConfiguredReviewers {
    # Azure DevOps accepts the identity of a person or of a group in the same
    # field, so a required reviewer group needs no separate handling. An empty
    # configuration leaves the pull request without reviewers.
    if ($Config.delivery.PSObject.Properties.Name -notcontains "reviewers") { return @() }
    return @(@($Config.delivery.reviewers) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { [string]$_ } |
        Select-Object -Unique)
}

function Get-DeliveryIdentity {
    # The branch used to be named after the run, and a run is not the work. A
    # build that created the branch, the commit and the pull request and then
    # lost the answer leaves a delivery nobody can find again: the next run has
    # a different id, so it opens a second branch and a second pull request for
    # the same work item, and a reviewer is asked to merge the same change
    # twice.
    #
    # What is durable is the work item the run was handed. Anything a run
    # creates for itself is not: on a fresh checkout those identifiers may come
    # out different, and an identity that changes is the defect being fixed.
    # Bootstrap uses a stable installation identity; other changes use their
    # approved content, so a different run id does not duplicate delivery.
    $eventPath = Join-Path $RunRoot "context/sdlc-event.json"
    if (Test-Path -LiteralPath $eventPath -PathType Leaf) {
        $event = try { Get-Content -LiteralPath $eventPath -Raw | ConvertFrom-Json -Depth 50 }
                 catch { $null }
        if ($null -ne $event -and
            (Get-QaFoundryPropertyNames -InputObject $event) -contains "correlation" -and
            (Get-QaFoundryPropertyNames -InputObject $event.correlation) -contains "workItemId") {
            $workItemId = ([string]$event.correlation.workItemId).Trim()
            if ($workItemId -match "^[0-9]+$") {
                return [pscustomobject]@{ slug = "wi-$workItemId"; durable = $true }
            }
        }
    }
    . (Join-Path $PSScriptRoot '../DeliveryIdentity.ps1')
    return Get-QaFoundryChangeDeliveryIdentity -Changes @($approvedChanges) -TargetBranch ([string]$Config.project.source_branch)
}

$deliveryIdentity = Get-DeliveryIdentity
$branch = "$([string]$Config.delivery.branch_prefix)$([string]$deliveryIdentity.slug)"

$sourceBranch = [string]$Config.project.source_branch
if ($branch -eq $sourceBranch -or $branch -in @("main", "master", "develop", "development")) {
    throw "Automation branch may not be a protected/source branch: $branch"
}
$registryPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot ([string]$Config.idempotency.registry_path)))

function Add-DeliveryAction {
    param([string]$Type, [string]$SourceRef, [string]$Status, [string]$ExternalId, [string]$Summary)
    $key = & (Join-Path $PSScriptRoot "../New-IdempotencyKey.ps1") -ActionType $Type -SourceRef $SourceRef
    if ([bool]$Config.idempotency.enabled) {
        $null = & (Join-Path $PSScriptRoot "../Use-IdempotencyRegistry.ps1") -Operation register `
            -RegistryPath $registryPath -Key $key -ActionType $Type -SourceRef $SourceRef `
            -Status $(if ($Status -eq "executed") { "executed" } else { "dry_run" }) `
            -RunId $RunId -ExternalId $ExternalId
    }
    $actions.Add([pscustomobject][ordered]@{
        sourceRef = $SourceRef; type = $Type; idempotencyKey = $key; status = $Status
        externalId = $ExternalId; summary = $Summary
    })
}

function Assert-NotExecuted {
    param([string]$Type, [string]$SourceRef)
    if (-not [bool]$Config.idempotency.enabled) { return $true }
    $key = & (Join-Path $PSScriptRoot "../New-IdempotencyKey.ps1") -ActionType $Type -SourceRef $SourceRef
    $check = & (Join-Path $PSScriptRoot "../Use-IdempotencyRegistry.ps1") -Operation check `
        -RegistryPath $registryPath -Key $key
    if ($check.exists -and [string]$check.record.status -eq "executed") {
        $actions.Add([pscustomobject][ordered]@{
            sourceRef = $SourceRef; type = $Type; idempotencyKey = $key; status = "duplicate"
            externalId = [string]$check.record.externalId; summary = "Existing delivery action reused."
        })
        return $false
    }
    return $true
}

# A completed retry in the same workspace is idempotent, but a partially
# recorded delivery cannot be reconstructed by the hosted relay: the next job
# has a fresh checkout and restores only evidence artifacts, not the local
# branch or commit. Never turn that state into a false successful result.
$requiredDeliveryTypes = [System.Collections.Generic.List[string]]::new()
if ([bool]$Config.delivery.create_branch) { $requiredDeliveryTypes.Add("git.branch") }
if ([bool]$Config.delivery.commit_changes) { $requiredDeliveryTypes.Add("git.commit") }
if ([bool]$Config.delivery.push_branch) { $requiredDeliveryTypes.Add("git.push") }
if ([bool]$Config.delivery.create_draft_pull_request) {
    $requiredDeliveryTypes.Add("pull-request.draft")
}
$recordedDeliveryTypes = [System.Collections.Generic.List[string]]::new()
if ([bool]$Config.idempotency.enabled) {
    foreach ($recordedType in $requiredDeliveryTypes) {
        $recordedKey = & (Join-Path $PSScriptRoot "../New-IdempotencyKey.ps1") `
            -ActionType $recordedType -SourceRef $RunId
        $recorded = & (Join-Path $PSScriptRoot "../Use-IdempotencyRegistry.ps1") -Operation check `
            -RegistryPath $registryPath -Key $recordedKey
        if ($recorded.exists -and [string]$recorded.record.status -eq "executed") {
            $recordedDeliveryTypes.Add($recordedType)
        }
    }
}

if ($nothingToStage) {
    if ($recordedDeliveryTypes.Count -eq 0) {
        return [pscustomobject][ordered]@{
            runId = $RunId; stageId = $StageId; handler = "deliver_changes"
            status = "no_action_needed"; dryRun = $dryRun; actions = @(); evidence = @()
        }
    }
    $missingDeliveryTypes = @($requiredDeliveryTypes | Where-Object {
        $_ -notin $recordedDeliveryTypes
    })
    if ($missingDeliveryTypes.Count -gt 0) {
        throw (
            "Partial delivery state cannot be resumed safely across fresh hosted-agent " +
            "checkouts. Completed actions: $($recordedDeliveryTypes -join ', '); missing " +
            "actions: $($missingDeliveryTypes -join ', '). Start a fresh run rather than " +
            "claiming that this delivery completed."
        )
    }
}

$deliveryProvider = [string]$Config.delivery.provider
$createsLiveCommit = -not $dryRun -and [bool]$Config.delivery.commit_changes
if ($createsLiveCommit -and $deliveryProvider -notin @("azure-devops", "github")) {
    throw (
        "Live commit creation requires delivery.provider='azure-devops' so the " +
        "authenticated PAT owner supplies the Git author and committer identity."
    )
}
$needsUserCredential = -not $dryRun -and
    $deliveryProvider -in @("azure-devops", "github") -and
    (
        [bool]$Config.delivery.commit_changes -or
        [bool]$Config.delivery.push_branch -or
        [bool]$Config.delivery.create_draft_pull_request
    )
if ($needsUserCredential -and $deliveryProvider -eq 'github') {
    . (Join-Path $PSScriptRoot '../github/GitHub.ps1')
    $ghContext = Get-FoundryGitHubContext -Settings $Config.delivery.github -Environment $ActionEnvironment
    $azureCredential = [pscustomobject]@{authorization=$ghContext.gitAuthorization}
    $committerName = [string]$Config.delivery.committer_name
    $committerEmail = [string]$Config.delivery.committer_email
    $remoteUrl = [string](& git -C $RepositoryRoot remote get-url origin)
    if ($LASTEXITCODE -ne 0 -or $remoteUrl.TrimEnd('/') -notin @("https://github.com/$($ghContext.repository)","https://github.com/$($ghContext.repository).git")) {
        throw 'Git origin must be the configured HTTPS GitHub repository before authenticated delivery.'
    }
}
elseif ($needsUserCredential) {
    $azureCredential = Get-QaFoundryAzureDevOpsUserContext `
        -AzureDevOpsConfig $Config.delivery.azure_devops `
        -ActionEnvironment $ActionEnvironment
    $committerName = [string]$azureCredential.displayName
    $committerEmail = [string]$azureCredential.email
}

function Get-RemoteDeliveryState {
    # The local registry settles repeats inside one checkout and nothing wider.
    # It is not committed and not carried between relay legs, so the run that
    # has to be recognised - a fresh build after a lost answer - starts with an
    # empty one and would deliver everything a second time. The only record
    # that survives that is the server's, so it is read before anything is
    # created.
    param([Parameter(Mandatory)][string]$BranchName)

    if ($deliveryProvider -eq 'github') {
        return Get-FoundryGitHubDeliveryState -Context $ghContext -Branch $BranchName -Base $sourceBranch
    }
    $settings = $Config.delivery.azure_devops
    $organization = ([string]$settings.organization_url).TrimEnd("/")
    $project = [Uri]::EscapeDataString([string]$settings.project)
    $repo = [Uri]::EscapeDataString([string]$settings.repository_id)
    $headers = @{ Authorization = [string]$azureCredential.authorization }
    $base = "$organization/$project/_apis/git/repositories/$repo"

    $refFilter = [Uri]::EscapeDataString("heads/$BranchName")
    $refs = Invoke-RestMethod -Method Get -Headers $headers `
        -Uri "$base/refs?filter=$refFilter&api-version=7.1"
    $exact = @(@($refs.value) | Where-Object { [string]$_.name -eq "refs/heads/$BranchName" })
    $tip = if ($exact.Count -gt 0) { [string]$exact[0].objectId } else { "" }

    # Every status, not just the active ones: an abandoned or already completed
    # pull request for this branch means the delivery was made and answered, and
    # raising another would ask for the same decision twice.
    $source = [Uri]::EscapeDataString("refs/heads/$BranchName")
    $pullRequests = Invoke-RestMethod -Method Get -Headers $headers -Uri (
        "$base/pullrequests?searchCriteria.sourceRefName=$source" +
        "&searchCriteria.status=all&api-version=7.1")
    $existing = @(@($pullRequests.value) |
        Where-Object { [string]$_.sourceRefName -eq "refs/heads/$BranchName" } |
        Sort-Object { [int]$_.pullRequestId })

    return [pscustomobject]@{
        branchExists = ($tip -ne "")
        tip = $tip
        pullRequestId = if ($existing.Count -gt 0) { [string]$existing[-1].pullRequestId } else { "" }
        pullRequestStatus = if ($existing.Count -gt 0) { [string]$existing[-1].status } else { "" }
    }
}

# Anything the server already holds for this branch has to be read before the
# first write, because after it there is no way to tell a delivery this run made
# from one it repeated.
$remoteDelivery = [pscustomobject]@{
    branchExists = $false; tip = ""; pullRequestId = ""; pullRequestStatus = ""
}
if ($needsUserCredential -and [bool]$Config.delivery.push_branch) {
    $remoteDelivery = Get-RemoteDeliveryState -BranchName $branch
    if ($remoteDelivery.branchExists) {
        Write-QaFoundryLog -Level warn -Message (
            "Branch '$branch' already exists on the server at $($remoteDelivery.tip)" +
            $(if ($remoteDelivery.pullRequestId -ne "") {
                ", with pull request $($remoteDelivery.pullRequestId) ($($remoteDelivery.pullRequestStatus))"
            } else { " with no pull request" }) +
            ". This delivery is being continued rather than made a second time.")
    }
}
$resumedRemoteDelivery = $false
$alreadyDelivered = $false

if ([bool]$Config.delivery.create_branch -and (Assert-NotExecuted -Type "git.branch" -SourceRef $RunId)) {
    if (-not $dryRun) {
        if ($remoteDelivery.branchExists) {
            # Creating the branch afresh from the source branch would put this
            # run's commit beside the earlier one rather than after it, and the
            # push would be refused as a non-fast-forward - or, with a different
            # branch name, would succeed and open a second pull request. The
            # branch is continued from the tip the server already has.
            $resumedRemoteDelivery = $true
            $null = Invoke-GitWithAuthorization -Arguments @(
                    "-C", $RepositoryRoot, "fetch", "origin", "refs/heads/$branch"
                ) -FailureMessage "Failed to fetch the existing automation branch '$branch'." `
                -Authorization ([string]$azureCredential.authorization)
            # Use the fetched tip, including a concurrent server update after
            # the REST lookup. Do not check out this older tree: that would
            # replace the running Foundry scripts before subsequent steps.
            $remoteDelivery.tip = [string]@(Invoke-Git -Arguments @(
                    '-C', $RepositoryRoot, 'rev-parse', 'FETCH_HEAD'
                ) -FailureMessage 'Failed to read the fetched delivery commit.')[-1]
            if ($remoteDelivery.tip -notmatch '^[0-9a-f]{40}$') {
                throw 'The fetched delivery commit is not a valid Git object ID.'
            }
        }
        else {
            $null = Invoke-Git -Arguments @("-C", $RepositoryRoot, "switch", "-c", $branch) `
                -FailureMessage "Failed to create automation branch '$branch'."
        }
    }
    Add-DeliveryAction -Type "git.branch" -SourceRef $RunId `
        -Status $(if ($dryRun) { "dry_run" } else { "executed" }) -ExternalId $branch `
        -Summary $(if ($resumedRemoteDelivery) { "Continue branch $branch" } else { "Create branch $branch" })
}

function New-ContinuedDeliveryCommit {
    # A separate index builds on the remote commit without touching HEAD, local
    # branches, the caller's index, or the runtime files used by later stages.
    $indexPath = Join-Path ([IO.Path]::GetTempPath()) ("foundry-delivery-" + [guid]::NewGuid().ToString('N') + '.index')
    $previousIndex = [Environment]::GetEnvironmentVariable('GIT_INDEX_FILE', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE', $indexPath, 'Process')
        $null = Invoke-Git -Arguments @('-C', $RepositoryRoot, 'read-tree', [string]$remoteDelivery.tip) `
            -FailureMessage 'Failed to prepare the remote delivery tree.'
        foreach ($change in $approvedChanges) {
            $relative = ([string]$change.path).Replace('\', '/')
            $arguments = if ([string]$change.operation -eq 'delete') {
                @('-C', $RepositoryRoot, 'update-index', '--force-remove', '--', $relative)
            } else {
                @('-C', $RepositoryRoot, 'add', '--', $relative)
            }
            $null = Invoke-Git -Arguments $arguments -FailureMessage "Failed to stage approved delivery path '$relative'."
        }
        $staged = @(Invoke-Git -Arguments @(
                '-C', $RepositoryRoot, 'diff', '--cached', '--name-only', [string]$remoteDelivery.tip
            ) -FailureMessage 'Failed to inspect the continued delivery tree.')
        $unexpected = @($staged | Where-Object { -not $proposedPathSet.Contains([string]$_) })
        if ($unexpected.Count -gt 0) { throw "Continued delivery contains unapproved paths: $($unexpected -join ', ')" }
        if ($staged.Count -eq 0) { return [string]$remoteDelivery.tip }
        $tree = [string]@(Invoke-Git -Arguments @('-C', $RepositoryRoot, 'write-tree') `
            -FailureMessage 'Failed to write the continued delivery tree.')[-1]
        return [string]@(Invoke-GitAsUser -Arguments @(
                '-C', $RepositoryRoot, 'commit-tree', $tree, '-p', [string]$remoteDelivery.tip,
                '-m', [string]$Config.delivery.commit_message
            ) -FailureMessage 'Failed to commit the continued delivery tree.' `
            -Name $committerName -Email $committerEmail)[-1]
    }
    finally {
        if ($null -eq $previousIndex) {
            [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE', [NullString]::Value, 'Process')
        } else {
            [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE', $previousIndex, 'Process')
        }
        if (Test-Path -LiteralPath $indexPath -PathType Leaf) { Remove-Item -LiteralPath $indexPath -Force }
    }
}

$commitId = ""
if ([bool]$Config.delivery.commit_changes -and (Assert-NotExecuted -Type "git.commit" -SourceRef $RunId)) {
    if (-not [bool]$Config.delivery.create_branch) { throw "Committing changes requires delivery.create_branch=true." }
    # Reaching here with nothing to stage means the run has recorded delivery
    # work but no commit of its own to make. Recording a commit that was never
    # created would put a fabricated id in the pull request.
    if (-not $nothingToStage) {
        # The relay rewrites the checkout's NuGet.Config when no configured
        # package feed answers from the build agent, so that restores fail
        # honestly instead of hanging. That rewrite describes the agent, not
        # the product, and committing it would push a CI workaround into the
        # repository and silently cut everyone else off from the internal feed.
        foreach ($candidate in @($changedPaths)) {
            $absolute = Join-Path $RepositoryRoot $candidate
            if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { continue }
            $head = Get-Content -LiteralPath $absolute -Raw -ErrorAction SilentlyContinue
            if ([string]$head -match "ci-package-source-override") {
                throw (
                    "Refusing to commit '$candidate': it carries the package-source override this " +
                    "leg wrote because no configured feed was reachable from the build agent. That " +
                    "file belongs to the agent, not to the repository.")
            }
        }
        if (-not $dryRun) {
        if ($resumedRemoteDelivery) {
            $commitId = New-ContinuedDeliveryCommit
            if ($commitId -notmatch '^[0-9a-f]{40}$') { throw "Invalid continued delivery commit ID '$commitId'." }
            $alreadyDelivered = $commitId -eq [string]$remoteDelivery.tip
        }
        else {
        $stageTargets = @($changedPaths)
        $null = Invoke-Git -Arguments (@("-C", $RepositoryRoot, "add", "--") + @($stageTargets)) `
            -FailureMessage "Failed to stage scoped changes."
        # git commits the whole index, not the paths that were just added. Anything a person had
        # already staged would be swept into this commit and pushed under the automation's name,
        # including files the write rules would never have allowed it to touch.
        $stagedPaths = @(Invoke-Git -Arguments @(
                "-C", $RepositoryRoot, "diff", "--cached", "--name-only"
            ) -FailureMessage "Failed to read the staged changes." |
            ForEach-Object { ([string]$_).Trim().Replace("\", "/") } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        # The same ordinal rule as the membership test above: a staged
        # 'Automation/foo.yml' is not the 'automation/foo.yml' this run proposed.
        $stagedExpected = [System.Collections.Generic.HashSet[string]]::new(
            [string[]]@($stageTargets), [System.StringComparer]::Ordinal)
        $unexpected = @($stagedPaths | Where-Object { -not $stagedExpected.Contains([string]$_) })
        if ($unexpected.Count -gt 0) {
            throw ("The index holds $($unexpected.Count) change(s) this run did not propose, so a " +
                "commit here would publish them too: " +
                (@($unexpected | Select-Object -First 10) -join ", ") +
                ". Unstage them and run again.")
        }
        $null = Invoke-GitAsUser -Arguments @(
            "-C", $RepositoryRoot, "commit", "-m", [string]$Config.delivery.commit_message
        ) -FailureMessage "Failed to commit scoped changes." `
            -Name $committerName -Email $committerEmail
        $revision = @(Invoke-Git -Arguments @("-C", $RepositoryRoot, "rev-parse", "HEAD") `
                -FailureMessage "Failed to read the commit that was just created." |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $commitId = if ($revision.Count -gt 0) { $revision[-1] } else { "" }
        # The commit id travels into the action result and into the pull request
        # description, where a wrong value is both unnoticeable and useless.
            if ($commitId -notmatch "^[0-9a-f]{40}$") {
                throw "Expected a commit id from git rev-parse HEAD but read '$commitId'."
            }
        }
        }
        Add-DeliveryAction -Type "git.commit" -SourceRef $RunId `
            -Status $(if ($dryRun) { "dry_run" } else { "executed" }) -ExternalId $commitId `
            -Summary $(if ($alreadyDelivered) { "Reuse commit already on branch $branch" } else { "Commit scoped changes" })
    }
}

if ([bool]$Config.delivery.push_branch -and (Assert-NotExecuted -Type "git.push" -SourceRef $RunId)) {
    if (-not [bool]$Config.delivery.commit_changes) { throw "Pushing requires delivery.commit_changes=true." }
    if (-not $dryRun -and -not $alreadyDelivered) {
        # A resumed delivery may deliberately leave the cached local branch
        # untouched. Publish the commit just validated, never that cached ref.
        $pushRef = if ($resumedRemoteDelivery) { "${commitId}:refs/heads/$branch" } else { $branch }
        $null = Invoke-GitWithAuthorization `
            -Arguments @("-C", $RepositoryRoot, "push", "-u", "origin", $pushRef) `
            -FailureMessage "Failed to push automation branch '$branch'." `
            -Authorization ([string]$azureCredential.authorization)
    }
    Add-DeliveryAction -Type "git.push" -SourceRef $RunId `
        -Status $(if ($dryRun) { "dry_run" } else { "executed" }) -ExternalId $branch `
        -Summary $(if ($alreadyDelivered) { "Branch $branch already carries these changes" } else { "Push branch $branch without force" })
}

if ([bool]$Config.delivery.create_draft_pull_request -and
    (Assert-NotExecuted -Type "pull-request.draft" -SourceRef $RunId)) {
    if (-not [bool]$Config.delivery.push_branch) { throw "Draft pull request creation requires delivery.push_branch=true." }
    if ([string]$remoteDelivery.pullRequestId -ne "") {
        # The earlier delivery got all the way. Posting again would give the one
        # human in the loop the same change to decide on twice, from two pull
        # requests, with no way to tell which is the real one.
        Add-DeliveryAction -Type "pull-request.draft" -SourceRef $RunId `
            -Status "executed" -ExternalId ([string]$remoteDelivery.pullRequestId) `
            -Summary ("Reuse pull request $($remoteDelivery.pullRequestId) " +
                "($($remoteDelivery.pullRequestStatus)) already raised from branch $branch")
        return [pscustomobject][ordered]@{
            runId = $RunId; stageId = $StageId; handler = "deliver_changes"
            status = "completed"; dryRun = $dryRun; actions = @($actions); evidence = @($changedPaths)
        }
    }
    $provider = [string]$Config.delivery.provider
    $isDraft = if ($Config.delivery.PSObject.Properties.Name -contains "pull_request_draft") {
        [bool]$Config.delivery.pull_request_draft
    }
    else { $true }
    # Unanimity is the target, so a run that failed to reach it has a defect
    # somewhere upstream. The work is still delivered rather than destroyed, but
    # it must not arrive looking ready to merge.
    $dissent = @(Get-QaFoundryDeliveryDissent -RunRoot $RunRoot)
    if ($dissent.Count -gt 0) { $isDraft = $true }
    $workItemIds = @(Get-RunWorkItemIds)
    $reviewers = @(Get-ConfiguredReviewers)
    $externalId = ""
    if (-not $dryRun) {
        if ($provider -eq "azure-devops") {
            $settings = $Config.delivery.azure_devops
            $organization = ([string]$settings.organization_url).TrimEnd("/")
            $project = [Uri]::EscapeDataString([string]$settings.project)
            $repo = [Uri]::EscapeDataString([string]$settings.repository_id)
            $uri = "$organization/$project/_apis/git/repositories/$repo/pullrequests?api-version=7.1"
            $description = if ($dissent.Count -gt 0) {
                "Generated by SDLC Foundry run $RunId. Review did **not** reach unanimity, " +
                "which means a stage upstream of this pull request is wrong: the run hit its " +
                "review iteration limit with findings still open. It is delivered as a draft " +
                "so the work and the objections can be judged together rather than discarded. " +
                "Fix the cause, do not merge around it. Unresolved objections:`n`n" +
                ($dissent -join "`n")
            }
            elseif ($isDraft) {
                "Generated by SDLC Foundry run $RunId. Automatic merge is prohibited."
            }
            else {
                "Generated by SDLC Foundry run $RunId after unanimous review. Merging remains a human decision."
            }
            # The one human in the loop reads this pull request, so the reasoning
            # behind the technology choice has to be in it. A rationale that
            # lives only in a run artifact is a rationale nobody reviews.
            $narrative = @(Get-QaFoundryToolchainNarrative -RunRoot $RunRoot)
            if ($narrative.Count -gt 0) {
                $description = $description + "`n`n" + ($narrative -join "`n")
            }
            $requestBody = [ordered]@{
                sourceRefName = "refs/heads/$branch"
                targetRefName = "refs/heads/$sourceBranch"
                title = [string]$Config.delivery.commit_message
                description = $description
                isDraft = $isDraft
                workItemRefs = @($workItemIds | ForEach-Object { @{ id = [string]$_ } })
            }
            if ($reviewers.Count -gt 0) {
                $requestBody["reviewers"] = @($reviewers | ForEach-Object { @{ id = [string]$_ } })
            }
            $response = Invoke-RestMethod -Method Post -Uri $uri -Headers @{
                Authorization = [string]$azureCredential.authorization
            } `
                -ContentType "application/json" -Body ($requestBody | ConvertTo-Json -Depth 20)
            $externalId = [string]$response.pullRequestId
        }
        elseif ($provider -eq 'github') {
            $body = "Generated by SDLC Foundry run $RunId. Automatic merge is prohibited."
            if (Test-QaFoundryDeferredVerification -Config $Config) {
                $body += "`n`nBootstrap prepared and reviewed the frameworks and tests without executing them. Add application credentials and environment configuration, then run the delivered manual test workflows. No passing tests or measured coverage are claimed. See foundry-report.html for work performed, model usage and estimated cost."
            }
            $body += "

" + (@(Get-QaFoundryToolchainNarrative -RunRoot $RunRoot) -join "
")
            if ($workItemIds.Count) { $body += "

" + (($workItemIds | ForEach-Object { "Refs #$_" }) -join ', ') }
            if ($dissent.Count) { $body += "

Unresolved review findings:
" + ($dissent -join "
") }
            $created = Invoke-FoundryGitHub -Context $ghContext -Method POST -Path 'pulls' -Body @{
                title=[string]$Config.delivery.commit_message; head=$branch; base=$sourceBranch; body=$body; draft=$true
            }
            $externalId = [string]$created.number
            if ($reviewers.Count) {
                $null = Invoke-FoundryGitHub -Context $ghContext -Method POST -Path "pulls/$externalId/requested_reviewers" -Body @{reviewers=$reviewers}
            }
        }
        else { throw "Unsupported draft pull request provider." }
    }
    $pullRequestSummary = if ($isDraft) { "Create draft pull request" } else { "Create pull request" }
    if ($workItemIds.Count -gt 0) {
        $pullRequestSummary += " linked to work item(s) " + (@($workItemIds) -join ", ")
    }
    if ($reviewers.Count -gt 0) {
        $pullRequestSummary += " for $($reviewers.Count) reviewer(s)"
    }
    Add-DeliveryAction -Type "pull-request.draft" -SourceRef $RunId `
        -Status $(if ($dryRun) { "dry_run" } else { "executed" }) -ExternalId $externalId -Summary $pullRequestSummary
}

return [pscustomobject][ordered]@{
    runId = $RunId; stageId = $StageId; handler = "deliver_changes"
    status = if ($actions.Count -eq 0) { "no_action_needed" } else { "completed" }
    dryRun = $dryRun; actions = @($actions); evidence = @($changedPaths)
}
