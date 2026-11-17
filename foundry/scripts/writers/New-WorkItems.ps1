[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PlanPath,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$RunId,
    [string]$StageId = "create-work-items",
    [hashtable]$ActionEnvironment = @{}
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../Common.ps1")
. (Join-Path $PSScriptRoot '../WorkItemDefaults.ps1')
$plan = Get-Content -LiteralPath $PlanPath -Raw | ConvertFrom-Json -Depth 100 -ErrorAction Stop
# An agent that reports it could not plan the work still emits a schema-valid
# document, and its items array is whatever it managed before giving up. Filing
# those as real work items in a real project is not a recoverable mistake, so a
# plan that does not say it is proposing work does not get acted on.
$planFields = @(Get-QaFoundryPropertyNames -InputObject $plan)
$planOutcome = if ($planFields -contains "outcome") { [string]$plan.outcome } else { "" }
$planStatus = if ($planFields -contains "status") { [string]$plan.status } else { "" }
if ($planStatus -ne "" -and $planStatus -ne "completed") {
    throw ("The work item plan at '$PlanPath' reports status '$planStatus'. Work items are created " +
        "in a real project and cannot be taken back, so a plan that does not report success is " +
        "not acted on.")
}
if ($planOutcome -eq "blocked") {
    throw ("The work item plan at '$PlanPath' reports outcome 'blocked': the agent could not plan " +
        "the work. Whatever items it listed are not a plan, and creating them would file " +
        "half-considered work into a real project.")
}
if ($planOutcome -eq "no_action_needed" -and @($plan.items).Count -gt 0) {
    throw ("The work item plan at '$PlanPath' reports that no action is needed and then lists " +
        "$(@($plan.items).Count) item(s). The document contradicts itself, so neither reading of " +
        "it is acted on.")
}
$provider = [string]$Config.work_tracking.provider
$dryRun = -not [bool]$Config.work_tracking.enabled -or
    [bool]$Config.work_tracking.dry_run -or $provider -eq "none"
if ($provider -eq 'github') {
    if (-not $dryRun -and @($plan.items).Count) {
        throw 'GitHub Issues writing is not enabled in this bootstrap release. Keep work_tracking.enabled=false; the reviewed plan is retained in evidence.'
    }
    return [pscustomobject]@{runId=$RunId;stageId=$StageId;handler='create_work_items';status='no_action_needed';dryRun=$true;actions=@();evidence=@($PlanPath)}
}
$registryPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot ([string]$Config.idempotency.registry_path)))
$repositoryPrefix = (Resolve-Path $RepositoryRoot).Path.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $registryPath.StartsWith($repositoryPrefix, [StringComparison]::Ordinal)) {
    throw "Idempotency registry must stay inside the target repository."
}

$azureCredential = $null

# Which repository this plan came out of. Two repositories delivering into one
# Azure DevOps project name their findings the same way - 'task-1', 'finding:3' -
# so without this the marker for one repository's item matches the other's, and
# the second run adopts work it did not plan instead of filing its own. Read from
# the delivery settings because that is where the repository this run publishes
# to is already named.
$deliverySettings = $null
if (@(Get-QaFoundryPropertyNames -InputObject $Config) -contains "delivery" -and
    @(Get-QaFoundryPropertyNames -InputObject $Config.delivery) -contains "azure_devops") {
    $deliverySettings = $Config.delivery.azure_devops
}
$identityScope = ""
if ($null -ne $deliverySettings) {
    $identityScope = (@(
        ([string]$deliverySettings.organization_url).TrimEnd("/"),
        [string]$deliverySettings.project,
        [string]$deliverySettings.repository_id
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "|"
}
$configuredRepositoryId = ""
if ($null -ne $deliverySettings -and
    @(Get-QaFoundryPropertyNames -InputObject $deliverySettings) -contains "repository_id") {
    $configuredRepositoryId = [string]$deliverySettings.repository_id
}
# Work tracking can be live while delivery is not configured at all, and the
# schema lets repository_id be present but empty. Either way the scope collapses
# to an organisation and a project that every repository in it shares, which is
# exactly the collision this scope exists to prevent. The repository is asked for
# its own remote instead, and where even that is unknown the run refuses rather
# than filing under a name that is not its own.
if ([string]::IsNullOrWhiteSpace($configuredRepositoryId)) {
    $remote = ""
    try {
        $remote = (& git -C $RepositoryRoot remote get-url origin 2>$null | Select-Object -First 1)
    }
    catch { $remote = "" }
    # A cast of $null to string is still $null under StrictMode, and calling
    # .Trim() on it throws; interpolation is what makes it a string.
    $remote = "$remote".Trim()
    if (-not [string]::IsNullOrWhiteSpace($remote)) {
        $identityScope = (@($identityScope, $remote) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "|"
    }
    elseif (-not $dryRun -and [bool]$Config.work_tracking.enabled) {
        throw ("Work items cannot be created without something that identifies this repository. " +
            "The delivery settings name no repository_id and the checkout has no 'origin' remote, " +
            "so the marker written on every item would be the one another repository in the same " +
            "Azure DevOps project writes, and the two runs would adopt each other's work. " +
            "Configure delivery.azure_devops.repository_id.")
    }
}

# The idempotency registry is a file inside the repository, and a pipeline run
# starts from a fresh checkout. Nothing that only the last run wrote survives to
# be read by the next one, so a re-planned or re-queued run reads an empty
# registry, concludes nothing was ever created, and files a second copy of every
# item into a real project. The marker therefore has to live where the items do.
# A tag carrying the idempotency key is that marker: it is written by the same
# call that creates the item, so it cannot be lost between the two, and it can be
# asked for from any machine.
$markerPrefix = "sdlc-foundry-ref-"
function New-WorkItemMarkerTag {
    param([Parameter(Mandatory)][string]$Key)
    # Enough of the digest to make a collision across one project's lifetime not
    # worth reasoning about, and short enough that a person reading the item's
    # tags is not looking at a wall of hex.
    return "$markerPrefix$($Key.Substring(0, 20))"
}

# Returns the ids already carrying this marker. Throws rather than returning
# nothing when the question cannot be answered: "the query failed" and "no such
# item exists" lead to opposite actions, and guessing the second creates
# duplicates in a project people are working out of.
function Get-ExistingWorkItemIds {
    param([Parameter(Mandatory)][object]$Settings, [Parameter(Mandatory)][string]$MarkerTag)

    $organization = ([string]$Settings.organization_url).TrimEnd("/")
    $project = [Uri]::EscapeDataString([string]$Settings.project)
    $uri = "$organization/$project/_apis/wit/wiql?api-version=7.1"
    # The tag is generated here from a hex digest, so it carries no quote to
    # escape. The assertion says so rather than trusting it silently.
    if ($MarkerTag -notmatch "^$markerPrefix[0-9a-f]{20}$") {
        throw "Refusing to query with a malformed work item marker: '$MarkerTag'."
    }
    $query = "SELECT [System.Id] FROM WorkItems WHERE [System.TeamProject] = @project " +
        "AND [System.Tags] CONTAINS '$MarkerTag' ORDER BY [System.Id] ASC"
    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers @{
            Authorization = [string]$azureCredential.authorization
        } -ContentType "application/json" -Body (@{ query = $query } | ConvertTo-Json)
    }
    catch {
        throw ("Could not ask $organization whether work item '$MarkerTag' already exists: " +
            "$($_.Exception.Message). Creating it now could file a second copy of work that is " +
            "already in the project, so nothing is created until the question can be answered.")
    }
    # A WIQL answer always carries a workItems array, empty when nothing matched.
    # A response without one is not an empty result, it is a reply this runtime
    # does not understand, and reading it as "nothing exists" creates duplicates.
    if (@(Get-QaFoundryPropertyNames -InputObject $response) -notcontains "workItems") {
        throw ("$organization answered the query for '$MarkerTag' with a document carrying no " +
            "workItems, so whether the item already exists is unknown and nothing is created.")
    }
    return @(@($response.workItems | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_.id }) |
        Sort-Object)
}

# The plan says work goes into the current sprint. An empty iteration_path does
# not do that: Azure DevOps falls back to the project's default iteration, which
# is the backlog, and the item is created successfully in the one place nobody is
# looking. Pinning a literal path in configuration is worse - it is correct until
# the sprint rolls over, and then it is silently wrong. So the current iteration
# is asked for at the moment of writing.
$script:ResolvedIterationPath = $null
function Get-CurrentIterationPath {
    param([Parameter(Mandatory)][object]$Settings)
    if ($null -ne $script:ResolvedIterationPath) { return $script:ResolvedIterationPath }
    $organization = ([string]$Settings.organization_url).TrimEnd("/")
    $project = [Uri]::EscapeDataString([string]$Settings.project)
    $uri = "$organization/$project/_apis/work/teamsettings/iterations" +
        "?`$timeframe=current&api-version=7.1"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{
        Authorization = [string]$azureCredential.authorization
    }
    $current = @($response.value) | Where-Object { $null -ne $_ } | Select-Object -First 1
    if ($null -eq $current) {
        throw (
            "Work tracking is configured to use the current iteration, but the team has no " +
            "iteration in the current timeframe. Either set an explicit iteration_path or give " +
            "the team a sprint that covers today.")
    }
    $script:ResolvedIterationPath = [string]$current.path
    return $script:ResolvedIterationPath
}

function Get-ConfiguredIterationPath {
    param([Parameter(Mandatory)][object]$Settings)
    $fields = @(Get-QaFoundryPropertyNames -InputObject $Settings)
    if (-not [string]::IsNullOrWhiteSpace([string]$Settings.iteration_path)) {
        return [string]$Settings.iteration_path
    }
    if ($fields -contains "use_current_iteration" -and [bool]$Settings.use_current_iteration) {
        return Get-CurrentIterationPath -Settings $Settings
    }
    return ""
}

# Not every work item type carries every field. Under the Scrum process
# Microsoft.VSTS.Common.AcceptanceCriteria exists on Product Backlog Item and Bug
# but not on Task or Test Case, and a JSON Patch that sets a field the type does
# not have is rejected outright - the item is simply never created. Which fields
# a type has is a property of the project's process template, so it is asked for
# rather than assumed. If the question cannot be answered the field is still
# sent, so a lookup failure cannot silently strip content from an item.
$script:WorkItemTypeFields = @{}
function Test-WorkItemFieldSupported {
    param(
        [Parameter(Mandatory)][object]$Settings,
        [Parameter(Mandatory)][string]$Type,
        [Parameter(Mandatory)][string]$Field
    )
    if (-not $script:WorkItemTypeFields.ContainsKey($Type)) {
        $organization = ([string]$Settings.organization_url).TrimEnd("/")
        $project = [Uri]::EscapeDataString([string]$Settings.project)
        $encoded = [Uri]::EscapeDataString($Type)
        $uri = "$organization/$project/_apis/wit/workitemtypes/$encoded/fields?api-version=7.1"
        try {
            $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{
                Authorization = [string]$azureCredential.authorization
            }
            $names = @($response.value | Where-Object { $null -ne $_ } | ForEach-Object {
                [string]$_.referenceName
            } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            # An answer that lists no fields is not an answer. Treating it as one
            # would strip every field off the item and create it empty.
            $script:WorkItemTypeFields[$Type] = if ($names.Count -gt 0) { $names } else { $null }
        }
        catch {
            $script:WorkItemTypeFields[$Type] = $null
        }
    }
    $known = $script:WorkItemTypeFields[$Type]
    if ($null -eq $known) {
        return $true
    }
    return $known -contains $Field
}

# "Product Backlog Item" exists only under the Scrum process. An Agile project
# calls the same thing a User Story, CMMI calls it a Requirement and Basic calls
# it an Issue, and posting to a type the project does not have fails the create
# outright. Which process a project runs is not something this runtime gets to
# assume, so it is either configured or asked for.
$script:StoryWorkItemType = ""
function Resolve-StoryWorkItemType {
    param([Parameter(Mandatory)][object]$Settings)

    if ($script:StoryWorkItemType -ne "") { return $script:StoryWorkItemType }
    $configured = ""
    if ((Get-QaFoundryPropertyNames -InputObject $Settings) -contains "story_work_item_type") {
        $configured = ([string]$Settings.story_work_item_type).Trim()
    }
    if ($configured -ne "") {
        $script:StoryWorkItemType = $configured
        return $script:StoryWorkItemType
    }
    $organization = ([string]$Settings.organization_url).TrimEnd("/")
    $project = [Uri]::EscapeDataString([string]$Settings.project)
    # Categories, not the type list. Every process names its requirement type
    # differently but they all file it under Microsoft.RequirementCategory, so
    # the category's default type is the answer rather than a guess from a list
    # of names. The type list also carries every form layout in the project and
    # runs to hundreds of kilobytes, which is a payload no answer needs.
    $uri = "$organization/$project/_apis/wit/workitemtypecategories?api-version=7.1"
    $categories = @()
    try {
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers @{
            Authorization = [string]$azureCredential.authorization
        }
        # Under StrictMode a missing property is fatal, and this answer comes
        # from outside. A malformed one has to become a stated refusal rather
        # than a crash with a stack trace where the reason should be.
        if ((Get-QaFoundryPropertyNames -InputObject $response) -contains "value") {
            $categories = @($response.value | Where-Object { $null -ne $_ })
        }
    }
    catch {
        throw ("The work item type to file requirements as is not configured, and Azure DevOps " +
            "would not say which types project '$([string]$Settings.project)' has: " +
            "$($_.Exception.Message). Set work_tracking.azure_devops.story_work_item_type.")
    }
    $offered = [System.Collections.Generic.List[string]]::new()
    foreach ($category in $categories) {
        $categoryNames = Get-QaFoundryPropertyNames -InputObject $category
        if ($categoryNames -notcontains "referenceName") { continue }
        $referenceName = [string]$category.referenceName
        if (-not [string]::IsNullOrWhiteSpace($referenceName)) { $offered.Add($referenceName) }
        if ($referenceName -ne "Microsoft.RequirementCategory") { continue }
        if ($categoryNames -notcontains "defaultWorkItemType") { continue }
        $defaultType = $category.defaultWorkItemType
        if ($null -eq $defaultType) { continue }
        if ((Get-QaFoundryPropertyNames -InputObject $defaultType) -notcontains "name") { continue }
        $resolved = ([string]$defaultType.name).Trim()
        if ($resolved -ne "") {
            $script:StoryWorkItemType = $resolved
            return $script:StoryWorkItemType
        }
    }
    throw ("Project '$([string]$Settings.project)' does not offer a requirement category to file " +
        "backlog items under. It offers: " + (@($offered) -join ", ") +
        ". Set work_tracking.azure_devops.story_work_item_type to the type that fits.")
}

# The Azure Boards type a planned item is filed as. Named once because creating
# an item as one type and later reading its fields as another would ask the
# project whether the wrong type supports a field, and answer confidently.
function Resolve-WorkItemTypeName {
    param([Parameter(Mandatory)][object]$Item, [Parameter(Mandatory)][object]$Settings)

    switch ([string]$Item.type) {
        "bug" { return "Bug" }
        "task" { return "Task" }
        "test_case" { return "Test Case" }
        default { return (Resolve-StoryWorkItemType -Settings $Settings) }
    }
}

function Invoke-WorkItemCreate {
    param([object]$Item, [string]$ParentId = "", [string]$MarkerTag = "")
    if ($provider -eq "azure-devops") {
        $settings = $Config.work_tracking.azure_devops
        $type = Resolve-WorkItemTypeName -Item $Item -Settings $settings
        $encodedType = [Uri]::EscapeDataString($type)
        $organization = ([string]$settings.organization_url).TrimEnd("/")
        $project = [Uri]::EscapeDataString([string]$settings.project)
        $uri = "$organization/$project/_apis/wit/workitems/`$$($encodedType)?api-version=7.1"
        $criteria = @($Item.acceptanceCriteria | ForEach-Object { "<li>$([Net.WebUtility]::HtmlEncode([string]$_))</li>" }) -join ""
        $patch = [System.Collections.Generic.List[object]]::new()
        $patch.Add([ordered]@{ op = "add"; path = "/fields/System.Title"; value = [string]$Item.title })
        $patch.Add([ordered]@{ op = "add"; path = "/fields/System.Description"; value = [string]$Item.description })
        # Bug forms commonly display Repro Steps rather than System.Description.
        # Keep the diagnostic evidence visible on both supported fields.
        if ($type -eq 'Bug' -and (Test-WorkItemFieldSupported -Settings $settings -Type $type `
            -Field 'Microsoft.VSTS.TCM.ReproSteps')) {
            $patch.Add([ordered]@{ op = 'add'; path = '/fields/Microsoft.VSTS.TCM.ReproSteps'; value = [string]$Item.description })
        }
        if (Test-WorkItemFieldSupported -Settings $settings -Type $type `
            -Field "Microsoft.VSTS.Common.Priority") {
            $patch.Add([ordered]@{ op = "add"; path = "/fields/Microsoft.VSTS.Common.Priority"; value = [int]$Item.priority })
        }
        if (@($Item.acceptanceCriteria).Count -gt 0 -and
            (Test-WorkItemFieldSupported -Settings $settings -Type $type `
                -Field "Microsoft.VSTS.Common.AcceptanceCriteria")) {
            $patch.Add([ordered]@{ op = "add"; path = "/fields/Microsoft.VSTS.Common.AcceptanceCriteria"; value = "<ul>$criteria</ul>" })
        }
        # The marker travels in the same request that creates the item. Written
        # afterwards it could be lost to a dropped response, and an item without
        # it is an item the next run cannot recognise as its own work.
        $allTags = @(@($Item.tags) | ForEach-Object { [string]$_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if (-not [string]::IsNullOrWhiteSpace($MarkerTag)) { $allTags += $MarkerTag }
        if ($allTags.Count -gt 0) {
            $patch.Add([ordered]@{ op = "add"; path = "/fields/System.Tags"; value = ($allTags -join "; ") })
        }        if (-not [string]::IsNullOrWhiteSpace([string]$settings.area_path)) {
            $patch.Add([ordered]@{ op = "add"; path = "/fields/System.AreaPath"; value = [string]$settings.area_path })
        }
        $iterationPath = Get-ConfiguredIterationPath -Settings $settings
        if (-not [string]::IsNullOrWhiteSpace($iterationPath)) {
            $patch.Add([ordered]@{ op = "add"; path = "/fields/System.IterationPath"; value = $iterationPath })
        }
        if (-not [string]::IsNullOrWhiteSpace($ParentId)) {
            # Hierarchy-Reverse points from the child to its parent, so the task
            # is created already hanging off the backlog item it implements.
            $patch.Add([ordered]@{
                op = "add"
                path = "/relations/-"
                value = [ordered]@{
                    rel = "System.LinkTypes.Hierarchy-Reverse"
                    url = "$organization/_apis/wit/workItems/$ParentId"
                }
            })
        }
        $defaults = Get-QaFoundryWorkItemDefaults -Settings $settings -Type $type -UserEmail $azureCredential.email
        foreach ($field in $defaults.Keys) {
            $fieldPath = '/fields/' + $field
            if ($fieldPath -in @($patch | ForEach-Object path)) { continue }
            if (-not (Test-WorkItemFieldSupported -Settings $settings -Type $type -Field $field)) {
                throw "Configured work-item field '$field' is not supported by '$type' in '$($settings.project)'."
            }
            $patch.Add([ordered]@{ op = 'add'; path = $fieldPath; value = $defaults[$field] })
        }
        return Invoke-RestMethod -Method Post -Uri $uri -Headers @{
            Authorization = [string]$azureCredential.authorization
        } -ContentType "application/json-patch+json" -Body ($patch | ConvertTo-Json -Depth 30)
    }
    throw "Unsupported work tracking provider: $provider"
}

# Marks an item this run created as the loser of a race it could not have seen
# coming. The lookup and the create are two calls, so two runs on two agents can
# both find nothing and both create; nothing in Azure DevOps makes a tag unique.
# The duplicate is therefore not prevented here, it is made obvious: the item
# carries a tag naming the one that was kept, so a person reading the backlog
# sees which of the two is the live one instead of two identical items with no
# way to tell them apart.
function Add-WorkItemDuplicateTag {
    param(
        [Parameter(Mandatory)][object]$Settings,
        [Parameter(Mandatory)][int]$WorkItemId,
        [Parameter(Mandatory)][int]$KeptId,
        [string[]]$Tags = @()
    )

    $organization = ([string]$Settings.organization_url).TrimEnd("/")
    $project = [Uri]::EscapeDataString([string]$Settings.project)
    $uri = "$organization/$project/_apis/wit/workitems/$WorkItemId" + "?api-version=7.1"
    $merged = @(@($Tags) + @("sdlc-foundry-duplicate-of-$KeptId") |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $patch = @([ordered]@{
        op = "add"; path = "/fields/System.Tags"; value = ($merged -join "; ")
    })
    Invoke-RestMethod -Method Patch -Uri $uri -Headers @{
        Authorization = [string]$azureCredential.authorization
    } -ContentType "application/json-patch+json" -Body ($patch | ConvertTo-Json -Depth 10)
}

# Azure DevOps stores these fields as HTML and adds markup of its own to what it
# was given: a plain sentence comes back wrapped in a div. Comparing the stored
# value with the planned one literally would therefore find a difference every
# time and rewrite the item on every run, which is indistinguishable in the
# history from the test actually changing. The comparison is on the text.
function ConvertTo-ComparableFieldText {
    param([AllowEmptyString()][AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return "" }
    $withoutMarkup = [regex]::Replace($Text, "<[^>]+>", " ")
    $decoded = [Net.WebUtility]::HtmlDecode($withoutMarkup)
    return ([regex]::Replace($decoded, "\s+", " ")).Trim()
}

function Get-WorkItemDocument {
    param([Parameter(Mandatory)][object]$Settings, [Parameter(Mandatory)][string]$WorkItemId)

    $organization = ([string]$Settings.organization_url).TrimEnd("/")
    $project = [Uri]::EscapeDataString([string]$Settings.project)
    $uri = "$organization/$project/_apis/wit/workitems/$WorkItemId" + "?api-version=7.1"
    try {
        return Invoke-RestMethod -Method Get -Uri $uri -Headers @{
            Authorization = [string]$azureCredential.authorization
        }
    }
    catch {
        throw ("Work item $WorkItemId is the card for a test this run is syncing, and it could not " +
            "be read from $organization, so whether it still describes that test is unknown: " +
            $_.Exception.Message)
    }
}

# Brings an item this run already filed back into agreement with the plan.
#
# Reuse alone is not synchronisation. A test case's sourceRef is derived from the
# project, file and test name so that a second run recognises the card rather
# than filing a duplicate - which means a test whose assertions changed keeps the
# same card, and that card goes on describing behaviour the suite no longer has.
# A test management surface that states the wrong expectation is worse than one
# that states nothing, because someone will execute it by hand and report the
# difference as a defect.
#
# Only the fields the plan is the author of are touched. State, assignment, area
# and iteration belong to whoever is working the item, and tags are added to
# rather than replaced: the marker tag is what lets the next run find this card
# at all, and a tag a person put on is a note this run has no business erasing.
function Update-WorkItemToPlan {
    param(
        [Parameter(Mandatory)][object]$Settings,
        [Parameter(Mandatory)][string]$WorkItemId,
        [Parameter(Mandatory)][object]$Item
    )

    $type = Resolve-WorkItemTypeName -Item $Item -Settings $Settings
    $organization = ([string]$Settings.organization_url).TrimEnd("/")
    $project = [Uri]::EscapeDataString([string]$Settings.project)
    $uri = "$organization/$project/_apis/wit/workitems/$WorkItemId" + "?api-version=7.1"
    $attempts = 3
    for ($attempt = 1; $attempt -le $attempts; $attempt++) {
        $document = Get-WorkItemDocument -Settings $Settings -WorkItemId $WorkItemId
        $documentNames = @(Get-QaFoundryPropertyNames -InputObject $document)
        $fields = if ($documentNames -contains "fields") { $document.fields } else { $null }
        $fieldNames = @(Get-QaFoundryPropertyNames -InputObject $fields)
        function Get-CurrentField {
            param([string]$Name)
            if ($fieldNames -notcontains $Name) { return "" }
            return [string]$fields.$Name
        }

        $patch = [System.Collections.Generic.List[object]]::new()
        $changed = [System.Collections.Generic.List[string]]::new()

        $plannedTitle = ([string]$Item.title).Trim()
        if ((Get-CurrentField -Name "System.Title").Trim() -cne $plannedTitle) {
            $patch.Add([ordered]@{ op = "add"; path = "/fields/System.Title"; value = $plannedTitle })
            $changed.Add("title")
        }

        $plannedDescription = [string]$Item.description
        if ((ConvertTo-ComparableFieldText -Text (Get-CurrentField -Name "System.Description")) -cne
            (ConvertTo-ComparableFieldText -Text $plannedDescription)) {
            $patch.Add([ordered]@{
                op = "add"; path = "/fields/System.Description"; value = $plannedDescription
            })
            $changed.Add("description")
        }

        if (Test-WorkItemFieldSupported -Settings $Settings -Type $type `
            -Field "Microsoft.VSTS.Common.Priority") {
            $currentPriority = Get-CurrentField -Name "Microsoft.VSTS.Common.Priority"
            if ("$currentPriority".Trim() -ne "$([int]$Item.priority)") {
                $patch.Add([ordered]@{
                    op = "add"; path = "/fields/Microsoft.VSTS.Common.Priority"
                    value = [int]$Item.priority
                })
                $changed.Add("priority")
            }
        }

        if (@($Item.acceptanceCriteria).Count -gt 0 -and
            (Test-WorkItemFieldSupported -Settings $Settings -Type $type `
                -Field "Microsoft.VSTS.Common.AcceptanceCriteria")) {
            $criteria = @($Item.acceptanceCriteria | ForEach-Object {
                "<li>$([Net.WebUtility]::HtmlEncode([string]$_))</li>"
            }) -join ""
            $plannedCriteria = "<ul>$criteria</ul>"
            if ((ConvertTo-ComparableFieldText -Text (Get-CurrentField -Name "Microsoft.VSTS.Common.AcceptanceCriteria")) -cne
                (ConvertTo-ComparableFieldText -Text $plannedCriteria)) {
                $patch.Add([ordered]@{
                    op = "add"; path = "/fields/Microsoft.VSTS.Common.AcceptanceCriteria"
                    value = $plannedCriteria
                })
                $changed.Add("acceptance criteria")
            }
        }

        $currentTags = @((Get-CurrentField -Name "System.Tags").Split(";") |
            ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $plannedTags = @(@($Item.tags) | ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ })
        $missingTags = @($plannedTags | Where-Object { $_ -cnotin $currentTags })
        if ($missingTags.Count -gt 0) {
            $patch.Add([ordered]@{
                op = "add"; path = "/fields/System.Tags"
                value = ((@($currentTags) + @($missingTags)) -join "; ")
            })
            $changed.Add("tags")
        }

        if ($patch.Count -eq 0) { return @() }

        # The read and the write are two calls. Without this the refresh would
        # overwrite whatever someone saved in between and leave no trace of it.
        $revision = if ($documentNames -contains "rev") { [int]$document.rev } else { 0 }
        $patch.Insert(0, [ordered]@{ op = "test"; path = "/rev"; value = $revision })
        try {
            $null = Invoke-RestMethod -Method Patch -Uri $uri -Headers @{
                Authorization = [string]$azureCredential.authorization
            } -ContentType "application/json-patch+json" -Body ($patch | ConvertTo-Json -Depth 30)
            return @($changed)
        }
        catch {
            if ($attempt -eq $attempts) {
                throw ("Work item $WorkItemId describes a test that has changed, and it could not be " +
                    "brought up to date after $attempts attempt(s), so the test management surface " +
                    "would state something the suite no longer does: $($_.Exception.Message)")
            }
            Start-Sleep -Seconds $attempt
        }
    }
    return @()
}

function Get-OrderedPlanItems {
    param([object[]]$Items)

    $byRef = @{}
    foreach ($item in $Items) {
        $ref = [string]$item.sourceRef
        if ($byRef.ContainsKey($ref)) {
            throw "Work item plan repeats sourceRef '$ref'."
        }
        $byRef[$ref] = $item
    }
    foreach ($item in $Items) {
        $parentRef = Get-ItemParentRef -Item $item
        if ([string]::IsNullOrWhiteSpace($parentRef)) { continue }
        if (-not $byRef.ContainsKey($parentRef)) {
            throw "Work item '$([string]$item.sourceRef)' names parent '$parentRef', which the plan does not contain."
        }
        if ([string]$byRef[$parentRef].type -eq "task") {
            throw "Work item '$([string]$item.sourceRef)' cannot hang off task '$parentRef'."
        }
        if ($parentRef -eq [string]$item.sourceRef) {
            throw "Work item '$parentRef' cannot be its own parent."
        }
    }

    # Parents must exist before their children so the link can be made on
    # creation rather than in a second pass that a failed run could skip.
    $ordered = [System.Collections.Generic.List[object]]::new()
    $state = @{}
    function Add-ItemAndParents {
        param([object]$Item)
        $ref = [string]$Item.sourceRef
        if ([string]$state[$ref] -eq "done") { return }
        if ([string]$state[$ref] -eq "visiting") {
            throw "Work item plan contains a parent cycle through '$ref'."
        }
        $state[$ref] = "visiting"
        $parentRef = Get-ItemParentRef -Item $Item
        if (-not [string]::IsNullOrWhiteSpace($parentRef)) {
            Add-ItemAndParents -Item $byRef[$parentRef]
        }
        $state[$ref] = "done"
        $ordered.Add($Item)
    }
    foreach ($item in $Items) { Add-ItemAndParents -Item $item }
    return @($ordered)
}

function Get-ItemParentRef {
    param([object]$Item)
    if ($Item.PSObject.Properties.Name -notcontains "parentRef") { return "" }
    return [string]$Item.parentRef
}

# Which reused items are brought back into agreement with the plan, and which are
# left as they are.
#
# A test case is a statement about a test that exists in the repository, so the
# plan is its only author and a stale card is simply wrong. Everything else -
# a backlog item, a bug, a task - is a description of work to be done, and once
# it is filed people work out of it: they add what they found, they refine the
# acceptance criteria with whoever asked for the feature. Rewriting those from a
# later analysis would erase that silently, so a reused one is left alone.
function Sync-ReusedWorkItem {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$WorkItemId, [Parameter(Mandatory)][object]$Item)

    if ($dryRun -or $provider -ne "azure-devops") { return @() }
    if ([string]$Item.type -ne "test_case") { return @() }
    if ([string]::IsNullOrWhiteSpace($WorkItemId)) { return @() }
    if ($null -eq $azureCredential) {
        $script:azureCredential = Get-QaFoundryAzureDevOpsUserContext `
            -AzureDevOpsConfig $Config.work_tracking.azure_devops `
            -ActionEnvironment $ActionEnvironment
    }
    return @(Update-WorkItemToPlan -Settings $Config.work_tracking.azure_devops `
        -WorkItemId $WorkItemId -Item $Item)
}

function Get-ReuseSummary {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$WorkItemId,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Refreshed,
        [Parameter(Mandatory)][string]$Unchanged
    )

    if (@($Refreshed).Count -eq 0) { return $Unchanged }
    return ("Work item $WorkItemId already existed and the test it describes has changed, so its " +
        (@($Refreshed) -join ", ") + " were brought up to date.")
}

$actions = [System.Collections.Generic.List[object]]::new()
$externalIdByRef = @{}
foreach ($item in (Get-OrderedPlanItems -Items @($plan.items))) {
    $sourceRef = [string]$item.sourceRef
    $parentRef = Get-ItemParentRef -Item $item
    $parentId = if ([string]::IsNullOrWhiteSpace($parentRef)) { "" }
        else { [string]$externalIdByRef[$parentRef] }
    $key = & (Join-Path $PSScriptRoot "../New-IdempotencyKey.ps1") -ActionType "work-item.$provider" `
        -SourceRef $sourceRef -Scope $identityScope
    $existing = if ([bool]$Config.idempotency.enabled) {
        & (Join-Path $PSScriptRoot "../Use-IdempotencyRegistry.ps1") -Operation check `
            -RegistryPath $registryPath -Key $key
    }
    else { [pscustomobject]@{ exists = $false; record = $null } }
    if ($existing.exists -and [string]$existing.record.status -eq "executed") {
        $reusedId = [string]$existing.record.externalId
        $externalIdByRef[$sourceRef] = $reusedId
        $refreshed = @(Sync-ReusedWorkItem -WorkItemId $reusedId -Item $item)
        $actions.Add([pscustomobject][ordered]@{
            sourceRef = $sourceRef; type = "work-item.$provider"; parentRef = $parentRef
            idempotencyKey = $key
            status = if ($refreshed.Count -gt 0) { "executed" } else { "duplicate" }
            externalId = $reusedId
            summary = Get-ReuseSummary -WorkItemId $reusedId -Refreshed $refreshed `
                -Unchanged "Existing work item reused."
        })
        continue
    }
    if (-not [string]::IsNullOrWhiteSpace($parentRef) -and
        [string]::IsNullOrWhiteSpace($parentId) -and -not $dryRun) {
        throw "Work item '$sourceRef' cannot be linked because parent '$parentRef' has no identifier."
    }
    $externalId = ""
    $status = "dry_run"
    $registryStatus = "dry_run"
    $raceNote = ""
    if (-not $dryRun) {
        if ($null -eq $azureCredential -and $provider -eq "azure-devops") {
            $azureCredential = Get-QaFoundryAzureDevOpsUserContext `
                -AzureDevOpsConfig $Config.work_tracking.azure_devops `
                -ActionEnvironment $ActionEnvironment
        }
        # The local registry said nothing, which on a fresh checkout is what it
        # would say whether or not the item exists. The project itself is asked
        # before anything is created.
        $markerTag = New-WorkItemMarkerTag -Key $key
        $alreadyThere = @()
        if ($provider -eq "azure-devops") {
            $alreadyThere = @(Get-ExistingWorkItemIds `
                -Settings $Config.work_tracking.azure_devops -MarkerTag $markerTag)
        }
        if ($alreadyThere.Count -gt 0) {
            # More than one means an earlier run already duplicated this item.
            # Adding a third would not help anyone; the oldest is adopted and the
            # duplication is stated in the evidence where it can be dealt with.
            $externalId = [string]$alreadyThere[0]
            $status = "duplicate"
            $duplicateNote = if ($alreadyThere.Count -gt 1) {
                " Ids $(@($alreadyThere) -join ', ') all carry this marker; the oldest was adopted."
            }
            else { "" }
            $externalIdByRef[$sourceRef] = $externalId
            $refreshed = @(Sync-ReusedWorkItem -WorkItemId $externalId -Item $item)
            if ([bool]$Config.idempotency.enabled) {
                $null = & (Join-Path $PSScriptRoot "../Use-IdempotencyRegistry.ps1") -Operation register `
                    -RegistryPath $registryPath -Key $key -ActionType "work-item.$provider" `
                    -SourceRef $sourceRef -Status "executed" -RunId $RunId -ExternalId $externalId
            }
            $actions.Add([pscustomobject][ordered]@{
                sourceRef = $sourceRef; type = "work-item.$provider"; parentRef = $parentRef
                idempotencyKey = $key
                status = if ($refreshed.Count -gt 0) { "executed" } else { "duplicate" }
                externalId = $externalId
                summary = (Get-ReuseSummary -WorkItemId $externalId -Refreshed $refreshed `
                    -Unchanged ("Work item $externalId already carries this run's marker in the " +
                        "project, so it was reused rather than created again.")) + $duplicateNote
            })
            continue
        }
        $response = Invoke-WorkItemCreate -Item $item -ParentId $parentId -MarkerTag $markerTag
        $externalId = [string]$response.id
        $status = "executed"
        $registryStatus = "executed"
        if ($provider -eq "azure-devops") {
            # The lookup above and this create are two calls, and nothing between
            # them stops another agent doing the same. Asking again is not
            # instant truth either - a work item takes a moment to become
            # visible to a query - so the question is asked a few times over a
            # few seconds rather than once, which is long enough to catch the
            # ordinary case of two runs starting together.
            #
            # It is still a window, and it is not claimed to be closed. The
            # durable guarantee is the one the next run gives: the oldest item
            # carrying this marker is the one adopted, every time. What this adds
            # is that the two runs usually converge on the same id straight away,
            # and the hand-off to implementation is claimed on that one item with
            # a conditional write, so only one of them can start work on it.
            $createdId = [int]$response.id
            $afterwards = @($createdId)
            for ($attempt = 1; $attempt -le 3; $attempt++) {
                Start-Sleep -Milliseconds ($attempt * 700)
                try {
                    $seen = @(Get-ExistingWorkItemIds `
                        -Settings $Config.work_tracking.azure_devops -MarkerTag $markerTag)
                }
                catch {
                    Write-QaFoundryLog -Level warn -Indent 1 -Message (
                        "Could not check whether '$sourceRef' was created twice: " +
                        "$($_.Exception.Message)")
                    break
                }
                if (@($seen) -notcontains $createdId) {
                    # Our own item is not visible yet, so neither would anybody
                    # else's be. The answer is not yet worth acting on.
                    continue
                }
                # The query has caught up to this run's own write, which is the
                # best signal available that it would also show another run's.
                $afterwards = @($seen)
                break
            }
            if ($afterwards.Count -gt 1 -and [int]$afterwards[0] -ne $createdId) {
                $keptId = [int]$afterwards[0]
                try {
                    $null = Add-WorkItemDuplicateTag `
                        -Settings $Config.work_tracking.azure_devops `
                        -WorkItemId $createdId -KeptId $keptId `
                        -Tags @(@($item.tags) | ForEach-Object { [string]$_ })
                }
                catch {
                    Write-QaFoundryLog -Level warn -Indent 1 -Message (
                        "Work item $createdId duplicates $keptId and could not be marked as such: " +
                        "$($_.Exception.Message)")
                }
                $externalId = [string]$keptId
                $status = "duplicate"
                # The registry records what the project now holds, and it holds
                # an item for this reference. Recording the race instead would
                # make the next run create a third.
                $registryStatus = "executed"
                $raceNote = (" Another run created $keptId for the same work at the same moment; " +
                    "$keptId is the one used and $createdId is tagged as its duplicate.")
            }
        }
    }
    $externalIdByRef[$sourceRef] = $externalId
    if ([bool]$Config.idempotency.enabled) {
        $null = & (Join-Path $PSScriptRoot "../Use-IdempotencyRegistry.ps1") -Operation register `
            -RegistryPath $registryPath -Key $key -ActionType "work-item.$provider" `
            -SourceRef $sourceRef -Status $registryStatus -RunId $RunId -ExternalId $externalId
    }
    $parentSuffix = if ([string]::IsNullOrWhiteSpace($parentRef)) { "" } else { " under $parentRef" }
    $actions.Add([pscustomobject][ordered]@{
        sourceRef = $sourceRef; type = "work-item.$provider"; parentRef = $parentRef
        idempotencyKey = $key; status = $status
        externalId = $externalId
        summary = "$([string]$item.type): $([string]$item.title)$parentSuffix$raceNote"
    })
}

return [pscustomobject][ordered]@{
    runId = $RunId
    stageId = $StageId
    handler = "create_work_items"
    status = if (@($plan.items).Count -eq 0) { "no_action_needed" } else { "completed" }
    dryRun = $dryRun
    actions = @($actions)
    evidence = @($PlanPath)
}
