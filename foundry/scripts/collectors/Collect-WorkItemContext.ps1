<#
.SYNOPSIS
    Reads the work item a run was started to implement.

.DESCRIPTION
    The pipeline that implements a task is started with nothing but the task's id, because that is
    all the analyser that filed it knows at the moment it hands over. An id is not a specification:
    without the title, the description, the acceptance criteria and the outcome the parent backlog
    item states, the agents would be inventing the requirement they are supposed to satisfy.

    The revision is recorded with the content so the evidence says which version of the item was
    implemented. Work items are edited by people, and "implemented item 4002" is not a claim anyone
    can check later unless it says which reading of 4002 it means.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$EventPath,
    [Parameter(Mandatory)][object]$WorkTrackingConfig,
    [Parameter(Mandatory)][string]$OutputPath,
    [hashtable]$ProviderEnvironment = @{}
)

$ErrorActionPreference = "Stop"

function Get-ObjectValue {
    param(
        [object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [object]$Default = ""
    )
    if ($null -ne $Object -and $null -ne $Object.PSObject -and
        $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function Convert-FromWorkItemHtml {
    param([object]$Value, [int]$MaximumLength = 20000)

    $text = if ($null -eq $Value) { "" } else { [string]$Value }
    if ([string]::IsNullOrWhiteSpace($text)) { return "" }
    # Azure DevOps stores these fields as HTML. An agent reads the requirement, not the markup, and
    # list items carry meaning that collapsing the tags away would lose, so they become lines.
    $text = [regex]::Replace($text, "(?i)<br\s*/?>", "`n")
    $text = [regex]::Replace($text, "(?i)</(p|div|li|tr|h[1-6])>", "`n")
    $text = [regex]::Replace($text, "(?i)<li[^>]*>", "- ")
    $text = [regex]::Replace($text, "<[^>]+>", "")
    $text = [Net.WebUtility]::HtmlDecode($text)
    $text = [regex]::Replace($text, "[ `t]+", " ")
    $text = [regex]::Replace($text, "(`r?`n\s*){3,}", "`n`n").Trim()
    if ($text.Length -gt $MaximumLength) {
        return $text.Substring(0, $MaximumLength)
    }
    return $text
}

function ConvertTo-WorkItemRecord {
    param([Parameter(Mandatory)][object]$Response)

    $fields = Get-ObjectValue -Object $Response -Name "fields" -Default $null
    $tags = [string](Get-ObjectValue -Object $fields -Name "System.Tags" -Default "")
    return [ordered]@{
        id = [string](Get-ObjectValue -Object $Response -Name "id")
        revision = [int](Get-ObjectValue -Object $Response -Name "rev" -Default 0)
        type = [string](Get-ObjectValue -Object $fields -Name "System.WorkItemType" -Default "")
        title = [string](Get-ObjectValue -Object $fields -Name "System.Title" -Default "")
        state = [string](Get-ObjectValue -Object $fields -Name "System.State" -Default "")
        description = Convert-FromWorkItemHtml -Value (
            Get-ObjectValue -Object $fields -Name "System.Description" -Default "")
        acceptanceCriteria = Convert-FromWorkItemHtml -Value (
            Get-ObjectValue -Object $fields -Name "Microsoft.VSTS.Common.AcceptanceCriteria" -Default "")
        tags = @($tags -split ";" | ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        areaPath = [string](Get-ObjectValue -Object $fields -Name "System.AreaPath" -Default "")
        iterationPath = [string](Get-ObjectValue -Object $fields -Name "System.IterationPath" -Default "")
        url = [string](Get-ObjectValue -Object (
            Get-ObjectValue -Object (
                Get-ObjectValue -Object $Response -Name "_links" -Default $null
            ) -Name "html" -Default $null
        ) -Name "href" -Default "")
    }
}

if (-not (Test-Path $EventPath -PathType Leaf)) {
    throw "Normalised SDLC event does not exist: $EventPath"
}
$event = Get-Content -Path $EventPath -Raw | ConvertFrom-Json -Depth 50 -ErrorAction Stop

$provider = [string](Get-ObjectValue -Object $WorkTrackingConfig -Name "provider" -Default "local")
$workItemId = [string](Get-ObjectValue -Object (
    Get-ObjectValue -Object $event -Name "correlation" -Default $null
) -Name "workItemId" -Default "")

$warnings = [System.Collections.Generic.List[string]]::new()
$status = "not_applicable"
$item = $null
$parent = $null

# Most lanes are not started by a work item, and for them there is nothing to read. Only a run that
# was handed an id has a requirement to fetch.
if (-not [string]::IsNullOrWhiteSpace($workItemId) -and $provider -eq "azure-devops") {
    $settings = Get-ObjectValue -Object $WorkTrackingConfig -Name "azure_devops" -Default $null
    $organizationUrl = [string](Get-ObjectValue -Object $settings -Name "organization_url" -Default "")
    if ([string]::IsNullOrWhiteSpace($organizationUrl)) {
        $organizationUrl = [string](Get-ObjectValue -Object (
            Get-ObjectValue -Object $event -Name "metadata" -Default $null
        ) -Name "organizationUrl" -Default "")
    }
    $project = [string](Get-ObjectValue -Object $settings -Name "project" -Default "")
    if ([string]::IsNullOrWhiteSpace($project)) {
        $project = [string](Get-ObjectValue -Object (
            Get-ObjectValue -Object $event -Name "metadata" -Default $null
        ) -Name "project" -Default "")
    }
    $authEnvironmentName = [string](Get-ObjectValue -Object $settings -Name "auth_env" -Default "AZURE_DEVOPS_TOKEN")
    if ([string]::IsNullOrWhiteSpace($organizationUrl) -or [string]::IsNullOrWhiteSpace($project)) {
        # Not a warning. A run started to implement work item N that cannot read N would otherwise
        # go on to invent one, and the pull request would look exactly like a real implementation.
        throw ("Implementing work item $workItemId requires the work tracking organization URL, " +
            "project, and mapped '$authEnvironmentName'.")
    }
    # The scheme comes from the same settings block as the variable name. Reading
    # one from configuration and hard-coding the other is how a bearer-configured
    # installation sends a Basic header and is told the work item does not exist.
    $authorization = Get-QaFoundryAzureDevOpsHeaders -AzureDevOpsConfig $settings `
        -Environment $ProviderEnvironment `
        -Purpose "Implementing work item $workItemId"
    $headers = $authorization.headers
    $apiRoot = "$($organizationUrl.TrimEnd('/'))/$([uri]::EscapeDataString($project))/_apis/wit/workitems"

    $response = Invoke-RestMethod -Method Get -Headers $headers `
        -Uri "$apiRoot/$([uri]::EscapeDataString($workItemId))?`$expand=relations&api-version=7.1"
    $item = ConvertTo-WorkItemRecord -Response $response
    $status = "collected"

    # The task says what to do; the backlog item above it says what it is for. Implementing the
    # task without that context is how a correct change ends up satisfying the wrong outcome.
    $parentLink = @(@(Get-ObjectValue -Object $response -Name "relations" -Default @()) |
        Where-Object { [string](Get-ObjectValue -Object $_ -Name "rel") -eq "System.LinkTypes.Hierarchy-Reverse" } |
        Select-Object -First 1)
    if ($parentLink.Count -eq 1) {
        $parentUrl = [string](Get-ObjectValue -Object $parentLink[0] -Name "url")
        $parentId = ($parentUrl -split "/" | Select-Object -Last 1)
        if (-not [string]::IsNullOrWhiteSpace($parentId)) {
            try {
                $parentResponse = Invoke-RestMethod -Method Get -Headers $headers `
                    -Uri "$apiRoot/$([uri]::EscapeDataString($parentId))?api-version=7.1"
                $parent = ConvertTo-WorkItemRecord -Response $parentResponse
            }
            catch {
                # The task is still implementable without its parent, so this is reported rather
                # than thrown: losing the surrounding intent is a degraded run, not a wrong one.
                $warnings.Add("Parent work item $parentId could not be read: $($_.Exception.Message)")
            }
        }
    }
    else {
        $warnings.Add("Work item $workItemId has no parent backlog item.")
    }
}
elseif (-not [string]::IsNullOrWhiteSpace($workItemId)) {
    $status = "unavailable"
    $warnings.Add("Work item $workItemId cannot be read: work tracking provider is '$provider'.")
}

$context = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    collectedAt = [DateTime]::UtcNow.ToString("o")
    provider = $(if ($provider -eq "azure-devops") { "azure-devops" } else { "local" })
    status = $status
    item = $item
    parent = $parent
    warnings = @($warnings)
}

New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force | Out-Null
$context | ConvertTo-Json -Depth 30 | Set-Content -Path $OutputPath -Encoding utf8
return [pscustomobject]$context
