<#
.SYNOPSIS
    Queues another Azure DevOps pipeline, passing it template parameters.

.DESCRIPTION
    Azure DevOps has no trigger for the two events this installation turns on most: a build that
    failed, and a work item that became ready. Its pipeline-completion trigger fires only when the
    upstream run SUCCEEDED, which is precisely the case where triage has nothing to do. So a stage
    that wants the next pipeline to run says so, here, and passes the run id that carries its
    evidence.

    Queueing is deliberately not treated as a user-attributed write: nothing is authored, and the
    queued run authenticates for itself. What matters is that the run is attributable, and it is -
    Azure DevOps records the identity behind this token as its requester, so the same identity
    checks apply downstream exactly as if a person had pressed the button.
#>
[CmdletBinding(DefaultParameterSetName = "ByName")]
param(
    [Parameter(Mandatory, ParameterSetName = "ByName")][string]$PipelineName,
    [Parameter(Mandatory, ParameterSetName = "ById")][int]$PipelineId,
    [Parameter(Mandatory)][string]$Organization,
    [Parameter(Mandatory)][string]$Project,
    [Parameter(Mandatory)][string]$Branch,
    [hashtable]$TemplateParameters = @{},
    [string]$TokenEnvironmentName = "AZURE_DEVOPS_TOKEN",
    # How the credential above is sent. A personal access token goes as Basic with
    # an empty user name; a pipeline's own access token is a bearer token. Sending
    # one as the other does not fail loudly - Azure DevOps answers a sign-in page -
    # so the caller states which it holds rather than letting this guess.
    [ValidateSet("basic", "bearer")][string]$AuthScheme = "basic",
    [hashtable]$ActionEnvironment = @{},
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../Common.ps1")

$organization = $Organization.TrimEnd("/")
if ([string]::IsNullOrWhiteSpace($organization)) {
    throw "Queueing a pipeline requires an Azure DevOps organization URL."
}
if ([string]::IsNullOrWhiteSpace($Project)) {
    throw "Queueing a pipeline requires an Azure DevOps project."
}
# A run is queued against a ref, and the ref decides which version of the YAML runs. Defaulting it
# would silently queue the wrong branch's pipeline, so the caller names it.
$ref = $Branch.Trim()
if ([string]::IsNullOrWhiteSpace($ref)) {
    throw "Queueing a pipeline requires the branch whose pipeline definition should run."
}
if (-not $ref.StartsWith("refs/", [StringComparison]::Ordinal)) {
    $ref = "refs/heads/$($ref.TrimStart('/'))"
}

$parameters = [ordered]@{}
foreach ($name in @($TemplateParameters.Keys | Sort-Object)) {
    $parameters[[string]$name] = [string]$TemplateParameters[$name]
}

$targetDescription = if ($PSCmdlet.ParameterSetName -eq "ByName") { $PipelineName } else { "id $PipelineId" }

if ($DryRun) {
    Write-QaFoundryLog -Level "info" -Message "Dry run: would queue '$targetDescription' on $ref."
    return [pscustomobject][ordered]@{
        status = "dry_run"
        pipelineId = if ($PSCmdlet.ParameterSetName -eq "ById") { $PipelineId } else { 0 }
        pipelineName = if ($PSCmdlet.ParameterSetName -eq "ByName") { $PipelineName } else { "" }
        runId = ""
        branch = $ref
        templateParameters = [pscustomobject]$parameters
    }
}

$authorization = Get-QaFoundryAzureDevOpsHeaders -AzureDevOpsConfig ([pscustomobject]@{
        auth_env = $TokenEnvironmentName
        auth_scheme = $AuthScheme
    }) -Environment $ActionEnvironment -AllowProcessEnvironment `
    -Purpose "Queueing a pipeline"
$headers = $authorization.headers
$apiRoot = "$organization/$([Uri]::EscapeDataString($Project))/_apis/pipelines"

$resolvedName = ""
if ($PSCmdlet.ParameterSetName -eq "ByName") {
    $listResponse = Invoke-RestMethod -Method Get `
        -Uri "${apiRoot}?`$top=10000&api-version=7.1" -Headers $headers
    $candidates = @(@($listResponse.value) | Where-Object { [string]$_.name -eq $PipelineName })
    if ($candidates.Count -eq 0) {
        throw (
            "No pipeline named '$PipelineName' exists in project '$Project'. Queueing a pipeline " +
            "that was never registered cannot work, so nothing was queued."
        )
    }
    # Two pipelines may share a name in different folders. Picking one would be a coin toss over
    # which automation runs, so the caller is told to name the id instead.
    if ($candidates.Count -gt 1) {
        throw (
            "Project '$Project' has $($candidates.Count) pipelines named '$PipelineName'. Pass " +
            "-PipelineId to say which one should run."
        )
    }
    $PipelineId = [int]$candidates[0].id
    $resolvedName = [string]$candidates[0].name
}

$body = [ordered]@{
    resources = [ordered]@{
        repositories = [ordered]@{
            self = [ordered]@{ refName = $ref }
        }
    }
    templateParameters = $parameters
}
$run = Invoke-RestMethod -Method Post `
    -Uri "$apiRoot/$PipelineId/runs?api-version=7.1" `
    -Headers $headers -ContentType "application/json" `
    -Body ($body | ConvertTo-Json -Depth 30)

$description = ($parameters.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", "
Write-QaFoundryLog -Level "info" -Message (
    "Queued '$targetDescription' (id $PipelineId) run $($run.id) on $ref" +
    $(if ($description) { " with $description." } else { "." })
)

return [pscustomobject][ordered]@{
    status = "queued"
    pipelineId = $PipelineId
    pipelineName = if ($resolvedName) { $resolvedName } else { $PipelineName }
    runId = [string]$run.id
    branch = $ref
    templateParameters = [pscustomobject]$parameters
}
