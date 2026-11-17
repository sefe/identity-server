[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$EventPath,
    [Parameter(Mandatory)][object]$CiConfig,
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
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function Get-ProviderSecret {
    param(
        [Parameter(Mandatory)][hashtable]$Environment,
        [Parameter(Mandatory)][string]$Name
    )
    if ([string]::IsNullOrWhiteSpace($Name) -or
        -not $Environment.ContainsKey($Name) -or
        [string]::IsNullOrWhiteSpace([string]$Environment[$Name])) {
        return ""
    }
    return ([string]$Environment[$Name]).Trim()
}

function Convert-ToSafeText {
    param(
        [object]$Value,
        [int]$MaximumLength = 8000
    )
    $text = if ($null -eq $Value) { "" } else { [string]$Value }
    if ($text.Length -gt $MaximumLength) {
        return $text.Substring(0, $MaximumLength)
    }
    return $text
}

function New-EmptyBuild {
    return [ordered]@{
        id = ""
        pipeline = ""
        status = ""
        result = ""
        branch = ""
        commitSha = ""
        url = ""
        startedAt = ""
        finishedAt = ""
    }
}

if (-not (Test-Path $EventPath -PathType Leaf)) {
    throw "Normalised SDLC event does not exist: $EventPath"
}
$event = Get-Content -Path $EventPath -Raw |
    ConvertFrom-Json -Depth 50 -ErrorAction Stop

$configuredProvider = [string](Get-ObjectValue -Object $CiConfig -Name "provider" -Default "local")
$provider = if ($configuredProvider -eq "auto") {
    switch ([string]$event.source) {
        "azure-devops" { "azure-devops" }
        "github" { "github" }
        default { "local" }
    }
}
else {
    $configuredProvider
}
$collectRealtime = [bool](Get-ObjectValue -Object $CiConfig -Name "collect_realtime" -Default $false)
$failOnError = [bool](Get-ObjectValue -Object $CiConfig -Name "fail_on_collection_error" -Default $false)
$maximumFailedTests = [int](Get-ObjectValue -Object $CiConfig -Name "max_failed_tests" -Default 200)
$maximumJobs = [int](Get-ObjectValue -Object $CiConfig -Name "max_jobs" -Default 100)

$status = "not_applicable"
$warnings = [System.Collections.Generic.List[string]]::new()
$build = New-EmptyBuild
$jobs = [System.Collections.Generic.List[object]]::new()
$failedTests = [System.Collections.Generic.List[object]]::new()
$testRunCount = 0
$truncated = $false
$collectionFailure = $null
$requestLabel = 'configuration'

try {
    if (-not $collectRealtime -or $provider -eq "local") {
        $status = "not_applicable"
    }
    elseif ($provider -eq "github") {
        . (Join-Path $PSScriptRoot '../github/GitHub.ps1')
        $context=Get-FoundryGitHubContext -Settings $CiConfig.github -Environment $ProviderEnvironment
        $id=[string]$event.correlation.ciRunId
        if (-not $id) {$id=[string]$event.correlation.buildId}
        if ($id -notmatch '^[0-9]+$') {throw 'GitHub CI evidence requires a numeric workflow run ID.'}
        $requestLabel='GitHub workflow run'
        $run=Invoke-FoundryGitHub -Context $context -Path "actions/runs/$id"
        $build=[ordered]@{id=[string]$run.id;pipeline=[string]$run.name;status=[string]$run.status;
            result=[string]$run.conclusion;branch=[string]$run.head_branch;commitSha=[string]$run.head_sha;
            url=[string]$run.html_url;startedAt=[string]$run.created_at;finishedAt=[string]$run.updated_at}
        $requestLabel='GitHub workflow jobs'
        $page=1
        do {
            $response=Invoke-FoundryGitHub -Context $context -Path "actions/runs/$id/jobs?per_page=100&page=$page"
            foreach ($job in @($response.jobs)) {
                if ($jobs.Count -ge $maximumJobs) {$truncated=$true;break}
                $jobs.Add([pscustomobject]@{id=[string]$job.id;name=[string]$job.name;status=[string]$job.status;result=[string]$job.conclusion;url=[string]$job.html_url})
            }
            if ($jobs.Count -ge $maximumJobs -and [int]$response.total_count -gt $jobs.Count) {$truncated=$true}
            $page++
        } while (-not $truncated -and @($response.jobs).Count -eq 100 -and $jobs.Count -lt [int]$response.total_count)
        $warnings.Add('GitHub Actions job conclusions are collected. Individual test assertions are in suite artifacts; empty failedTests does not prove passing tests.')
        $status='collected'
    }
    elseif ($provider -eq "azure-devops") {
        $settings = Get-ObjectValue -Object $CiConfig -Name "azure_devops" -Default $null
        $organizationUrl = [string](Get-ObjectValue -Object $settings -Name "organization_url" -Default "")
        if ([string]::IsNullOrWhiteSpace($organizationUrl)) {
            $organizationUrl = [string](Get-ObjectValue -Object $event.metadata -Name "organizationUrl" -Default "")
        }
        $project = [string](Get-ObjectValue -Object $settings -Name "project" -Default "")
        if ([string]::IsNullOrWhiteSpace($project)) {
            $project = [string](Get-ObjectValue -Object $event.metadata -Name "project" -Default "")
        }
        $authEnvironmentName = [string](Get-ObjectValue -Object $settings -Name "auth_env" -Default "AZURE_DEVOPS_TOKEN")
        $authScheme = [string](Get-ObjectValue -Object $settings -Name "auth_scheme" -Default "bearer")
        $token = Get-ProviderSecret -Environment $ProviderEnvironment -Name $authEnvironmentName
        $buildId = [string]$event.correlation.buildId
        if ([string]::IsNullOrWhiteSpace($organizationUrl) -or
            [string]::IsNullOrWhiteSpace($project) -or
            [string]::IsNullOrWhiteSpace($buildId) -or
            [string]::IsNullOrWhiteSpace($token)) {
            throw "Azure DevOps CI collection requires organization URL, project, build ID, and mapped '$authEnvironmentName'."
        }

        $authorization = if ($authScheme -eq "basic") {
            $encoded = [Convert]::ToBase64String(
                [Text.Encoding]::ASCII.GetBytes(":$token")
            )
            "Basic $encoded"
        }
        elseif ($authScheme -eq "bearer") {
            "Bearer $token"
        }
        else {
            throw ("Azure DevOps CI collection was configured with auth_scheme '$authScheme', " +
                "which it does not know how to send. Use 'bearer' or 'basic'.")
        }
        $headers = @{ Authorization = $authorization }
        $organizationRoot = $organizationUrl.TrimEnd("/")
        $encodedProject = [uri]::EscapeDataString($project)
        $buildApi = "$organizationRoot/$encodedProject/_apis/build/builds/${buildId}?api-version=7.1"
        $requestLabel = 'build details'
        $buildResponse = Invoke-RestMethod -Method Get -Uri $buildApi -Headers $headers -TimeoutSec 30
        # Azure DevOps omits fields that have no value yet rather than sending
        # them as null, and a bootstrap run collects evidence about the build it
        # is running inside, which is by definition still in progress. Reading
        # these directly therefore throws under Set-StrictMode and loses the
        # whole collection, so every optional field is read defensively.
        $definition = Get-ObjectValue -Object $buildResponse -Name "definition" -Default $null
        $links = Get-ObjectValue -Object $buildResponse -Name "_links" -Default $null
        $webLink = Get-ObjectValue -Object $links -Name "web" -Default $null
        $build = [ordered]@{
            id = [string](Get-ObjectValue -Object $buildResponse -Name "id")
            pipeline = [string](Get-ObjectValue -Object $definition -Name "name")
            status = [string](Get-ObjectValue -Object $buildResponse -Name "status")
            result = [string](Get-ObjectValue -Object $buildResponse -Name "result")
            branch = [string](Get-ObjectValue -Object $buildResponse -Name "sourceBranch")
            commitSha = [string](Get-ObjectValue -Object $buildResponse -Name "sourceVersion")
            url = [string](Get-ObjectValue -Object $webLink -Name "href")
            startedAt = [string](Get-ObjectValue -Object $buildResponse -Name "startTime")
            finishedAt = [string](Get-ObjectValue -Object $buildResponse -Name "finishTime")
        }

        $timelineApi = "$organizationRoot/$encodedProject/_apis/build/builds/$buildId/timeline?api-version=7.1"
        $requestLabel = 'build timeline'
        $timeline = Invoke-RestMethod -Method Get -Uri $timelineApi -Headers $headers -TimeoutSec 30
        foreach ($record in @($timeline.records | Where-Object {
            $_.type -in @("Job", "Stage")
        } | Select-Object -First $maximumJobs)) {
            $jobs.Add([pscustomobject][ordered]@{
                id = [string](Get-ObjectValue -Object $record -Name "id")
                name = [string](Get-ObjectValue -Object $record -Name "name")
                status = [string](Get-ObjectValue -Object $record -Name "state")
                result = [string](Get-ObjectValue -Object $record -Name "result")
                url = ""
            })
        }
        if (@($timeline.records | Where-Object { $_.type -in @("Job", "Stage") }).Count -gt $maximumJobs) {
            $truncated = $true
            $warnings.Add("CI job evidence was truncated at $maximumJobs records.")
        }

        $buildUri = [uri]::EscapeDataString("vstfs:///Build/Build/$buildId")
        $testRunsApi = "$organizationRoot/$encodedProject/_apis/test/runs?buildUri=${buildUri}&api-version=7.1"
        $requestLabel = 'test runs'
        $testRunsResponse = Invoke-RestMethod -Method Get -Uri $testRunsApi -Headers $headers -TimeoutSec 30
        $testRuns = @($testRunsResponse.value)
        $testRunCount = $testRuns.Count
        foreach ($testRun in $testRuns) {
            if ($failedTests.Count -ge $maximumFailedTests) {
                $truncated = $true
                break
            }
            $remaining = $maximumFailedTests - $failedTests.Count
            $resultsApi = "$organizationRoot/$encodedProject/_apis/test/Runs/$($testRun.id)/results?outcomes=Failed&%24top=${remaining}&api-version=7.1"
            $requestLabel = 'failed test results'
            $resultsResponse = Invoke-RestMethod -Method Get -Uri $resultsApi -Headers $headers -TimeoutSec 30
            foreach ($testResult in @($resultsResponse.value)) {
                $durationValue = Get-ObjectValue -Object $testResult -Name "durationInMs" -Default $null
                $duration = 0.0
                if ($null -ne $durationValue) {
                    $duration = [double]$durationValue
                }
                $automatedName = [string](Get-ObjectValue -Object $testResult -Name "automatedTestName")
                $failedTests.Add([pscustomobject][ordered]@{
                    id = [string](Get-ObjectValue -Object $testResult -Name "id")
                    name = if ($automatedName) {
                        $automatedName
                    }
                    else {
                        [string](Get-ObjectValue -Object $testResult -Name "testCaseTitle")
                    }
                    outcome = [string](Get-ObjectValue -Object $testResult -Name "outcome")
                    errorMessage = Convert-ToSafeText -Value (
                        Get-ObjectValue -Object $testResult -Name "errorMessage"
                    )
                    stackTrace = Convert-ToSafeText -Value (
                        Get-ObjectValue -Object $testResult -Name "stackTrace"
                    )
                    durationMs = $duration
                    container = [string](Get-ObjectValue -Object $testRun -Name "name")
                })
            }
            if ([int](Get-ObjectValue -Object $resultsResponse -Name "count" -Default 0) -gt $remaining) {
                $truncated = $true
            }
        }
        $status = "collected"
    }
    else {
        throw "Unsupported CI evidence provider: $provider"
    }
}
catch {
    $status = "unavailable"
    $collectionFailure = "CI evidence collection failed while reading ${requestLabel}: " +
        (Convert-ToSafeText -Value $_.Exception.Message -MaximumLength 2000)
    $warnings.Add($collectionFailure)
}

$failedJobCount = @($jobs | Where-Object {
    $_.result -in @("failed", "failure", "partiallySucceeded", "cancelled")
}).Count
$evidence = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    collectedAt = [DateTime]::UtcNow.ToString("o")
    provider = $provider
    status = $status
    source = [ordered]@{
        eventId = [string]$event.eventId
        buildId = [string]$event.correlation.buildId
        ciRunId = [string]$event.correlation.ciRunId
    }
    build = $build
    jobs = @($jobs)
    failedTests = @($failedTests)
    summary = [ordered]@{
        jobCount = $jobs.Count
        failedJobCount = $failedJobCount
        testRunCount = $testRunCount
        failedTestCount = $failedTests.Count
        truncated = $truncated
    }
    warnings = @($warnings)
}

$parent = Split-Path $OutputPath -Parent
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$evidence | ConvertTo-Json -Depth 50 |
    Set-Content -Path $OutputPath -Encoding utf8
if ($failOnError -and $collectionFailure) { throw $collectionFailure }
return [pscustomobject]$evidence
