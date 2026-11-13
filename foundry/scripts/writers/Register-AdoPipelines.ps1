[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$AzureDevOpsConfig,
    [Parameter(Mandatory)][object[]]$Pipelines,
    [Parameter(Mandatory)][string]$TargetBranch,
    [hashtable]$ActionEnvironment = @{}
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../Common.ps1")
$dryRun = [bool]$AzureDevOpsConfig.dry_run
$organization = ([string]$AzureDevOpsConfig.organization_url).TrimEnd("/")
$projectName = [string]$AzureDevOpsConfig.project
$repositoryId = [string]$AzureDevOpsConfig.repository_id
$secretName = [string]$AzureDevOpsConfig.auth_env

if (-not $dryRun) {
    foreach ($required in @(
        @{ Name = "azure_devops.organization_url"; Value = $organization },
        @{ Name = "azure_devops.project"; Value = $projectName },
        @{ Name = "azure_devops.repository_id"; Value = $repositoryId }
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$required.Value)) {
            throw "Live Azure DevOps bootstrap requires $($required.Name)."
        }
    }
    if (-not $ActionEnvironment.ContainsKey($secretName) -or
        [string]::IsNullOrWhiteSpace([string]$ActionEnvironment[$secretName])) {
        throw "Live Azure DevOps bootstrap requires mapped token '$secretName'."
    }
}

$credential = if ($dryRun) {
    $null
}
else {
    Get-QaFoundryAzureDevOpsUserContext `
        -AzureDevOpsConfig $AzureDevOpsConfig `
        -ActionEnvironment $ActionEnvironment
}
$headers = if ($credential) {
    @{ Authorization = [string]$credential.authorization }
}
else { @{} }
$encodedProject = [Uri]::EscapeDataString($projectName)
$apiRoot = "$organization/$encodedProject/_apis/pipelines"
$definitionRoot = "$organization/$encodedProject/_apis/build/definitions"
function Invoke-RegistrationRequest {
    param([string]$Method, [string]$Uri, [hashtable]$Headers, [string]$ContentType, [string]$Body)
    try { Invoke-RestMethod @PSBoundParameters }
    catch {
        $detail = if ($_.ErrorDetails -and $_.ErrorDetails.Message) { [string]$_.ErrorDetails.Message } else { $_.Exception.Message }
        try {
            $errorBody = $detail | ConvertFrom-Json -ErrorAction Stop
            if ($errorBody.PSObject.Properties['message']) { $detail = [string]$errorBody.message }
        } catch { }
        $detail = (Protect-QaFoundrySecretText -Text $detail).text
        if ($detail.Length -gt 2000) { $detail = $detail.Substring(0,2000) }
        throw "Azure DevOps pipeline registration failed ($Method $Uri): $detail"
    }
}
$existingPipelines = @()
if (-not $dryRun) {
    if ([string]$AzureDevOpsConfig.repository_type -eq 'azureReposGit') {
        $repositoryGuid = [guid]::Empty
        if (-not [guid]::TryParse($repositoryId, [ref]$repositoryGuid)) {
            # Git repository lookup accepts a name; Pipelines Create requires
            # its GUID. Keep names valid in configuration and resolve once.
            $encodedRepository = [Uri]::EscapeDataString($repositoryId)
            $repository = Invoke-RegistrationRequest -Method Get -Headers $headers `
                -Uri "$organization/$encodedProject/_apis/git/repositories/${encodedRepository}?api-version=7.1"
            if (-not $repository.PSObject.Properties['id'] -or
                -not [guid]::TryParse([string]$repository.id, [ref]$repositoryGuid)) {
                throw "Azure DevOps returned no repository GUID for '$repositoryId'."
            }
        }
        if ($repositoryGuid -eq [guid]::Empty) { throw 'Azure DevOps repository GUID must not be empty.' }
        $repositoryId = $repositoryGuid.ToString('D')
    }
    $listResponse = Invoke-RegistrationRequest -Method Get `
        -Uri "${apiRoot}?`$top=10000&api-version=7.1" -Headers $headers
    $existingPipelines = @($listResponse.value)
}

$results = [System.Collections.Generic.List[object]]::new()
foreach ($pipeline in @($Pipelines)) {
    $key = [string]$pipeline.key
    $name = [string]$pipeline.name
    $folder = [string]$pipeline.folder
    $yamlPath = "/" + ([string]$pipeline.yamlPath).Replace("\", "/").TrimStart("/")
    if (-not [bool]$pipeline.enabled) {
        $results.Add([pscustomobject][ordered]@{
            key = $key; name = $name; status = "disabled"; pipelineId = ""; runId = ""
            defaultBranch = ""
        })
        continue
    }
    if ($dryRun) {
        $results.Add([pscustomobject][ordered]@{
            key = $key; name = $name; status = "dry_run"; pipelineId = ""; runId = ""
            defaultBranch = ""
        })
        continue
    }

    $matches = @($existingPipelines | Where-Object {
        [string]$_.name -eq $name -and [string]$_.folder -eq $folder
    })
    if ($matches.Count -gt 1) {
        throw "Azure DevOps contains more than one pipeline named '$name' in '$folder'."
    }
    $status = "reused"
    $registered = if ($matches.Count -eq 1) {
        # A pipeline with the right name in the right folder is not necessarily
        # the right pipeline. It may have been pointed at another repository or
        # another YAML file, and reusing it would report success while the file
        # this installation just wrote is never run by anything.
        $existingId = [string]$matches[0].id
        $definition = Invoke-RegistrationRequest -Method Get `
            -Uri "$apiRoot/${existingId}?api-version=7.1" -Headers $headers
        $existingYamlPath = "/" + (
            [string]$definition.configuration.path).Replace("\", "/").TrimStart("/")
        $existingRepositoryId = [string]$definition.configuration.repository.id
        if ($existingYamlPath -ne $yamlPath) {
            throw ("Azure DevOps already has a pipeline named '$name' in '$folder', but it runs " +
                "'$existingYamlPath' rather than '$yamlPath'. Reusing it would leave the file this " +
                "installation wrote unregistered while reporting success. Rename the pipeline or " +
                "repoint the existing one.")
        }
        if (-not [string]::IsNullOrWhiteSpace($existingRepositoryId) -and
            $existingRepositoryId -ne $repositoryId) {
            throw ("Azure DevOps already has a pipeline named '$name' in '$folder', but it is bound " +
                "to repository '$existingRepositoryId' rather than '$repositoryId'. Reusing it " +
                "would run somebody else's code under this installation's name.")
        }
        $matches[0]
    }
    else {
        $status = "created"
        $body = [ordered]@{
            name = $name
            folder = $folder
            configuration = [ordered]@{
                type = "yaml"
                path = $yamlPath
                repository = [ordered]@{
                    id = $repositoryId
                    type = [string]$AzureDevOpsConfig.repository_type
                }
            }
        }
        $created = Invoke-RegistrationRequest -Method Post -Uri "${apiRoot}?api-version=7.1" `
            -Headers $headers -ContentType "application/json" `
            -Body ($body | ConvertTo-Json -Depth 30)
        $existingPipelines += $created
        $created
    }

    $pipelineId = [string]$registered.id
    if ([string]::IsNullOrWhiteSpace($pipelineId)) {
        throw "Azure DevOps did not return an ID for pipeline '$name'."
    }
    # Azure DevOps points a new pipeline at the repository default branch, which
    # here is main while the whole relay runs on develop. Left alone, every
    # scheduled trigger in these files would fire against a branch that does not
    # contain them, and nothing would announce it - the pipeline exists, its name
    # is right, and it simply never runs the installed code.
    $desiredDefaultRef = "refs/heads/$TargetBranch"
    $definition = Invoke-RegistrationRequest -Method Get `
        -Uri "$definitionRoot/${pipelineId}?api-version=7.1" -Headers $headers
    $definitionNames = @(Get-QaFoundryPropertyNames -InputObject $definition)
    $repositoryBlock = if ($definitionNames -contains "repository") { $definition.repository } else { $null }
    $currentDefaultRef = if (
        $repositoryBlock -and
        (@(Get-QaFoundryPropertyNames -InputObject $repositoryBlock) -contains "defaultBranch")
    ) { [string]$repositoryBlock.defaultBranch } else { "" }
    if ($currentDefaultRef -ne $desiredDefaultRef) {
        if ($null -eq $repositoryBlock) {
            throw ("Azure DevOps returned no repository block for pipeline '$name', so its default " +
                "branch cannot be set to '$desiredDefaultRef'.")
        }
        $repositoryBlock | Add-Member -NotePropertyName defaultBranch `
            -NotePropertyValue $desiredDefaultRef -Force
        $null = Invoke-RegistrationRequest -Method Put `
            -Uri "$definitionRoot/${pipelineId}?api-version=7.1" `
            -Headers $headers -ContentType "application/json" `
            -Body ($definition | ConvertTo-Json -Depth 40)
    }
    $runId = ""
    if ([bool]$AzureDevOpsConfig.queue_smoke_run -and [bool]$pipeline.smoke) {
        $runBody = [ordered]@{
            resources = [ordered]@{
                repositories = [ordered]@{
                    self = [ordered]@{ refName = "refs/heads/$TargetBranch" }
                }
            }
            templateParameters = [ordered]@{ eventType = "manual" }
        }
        $run = Invoke-RegistrationRequest -Method Post `
            -Uri "$apiRoot/$pipelineId/runs?api-version=7.1" `
            -Headers $headers -ContentType "application/json" `
            -Body ($runBody | ConvertTo-Json -Depth 30)
        $runId = [string]$run.id
    }
    $results.Add([pscustomobject][ordered]@{
        key = $key; name = $name; status = $status
        pipelineId = $pipelineId; runId = $runId
        defaultBranch = $desiredDefaultRef
    })
}

return @($results)
