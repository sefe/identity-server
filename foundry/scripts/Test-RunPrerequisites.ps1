[CmdletBinding()]
param([Parameter(Mandatory)][object]$Config, [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$OutputPath, [hashtable]$ActionEnvironment = @{}, [switch]$Demo)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$checks = [System.Collections.Generic.List[object]]::new()
$status = 'completed'
$checkName = 'local tools'
try {
    if (-not $Demo) {
        $tools = @('git', 'node')
        if (@(Get-ChildItem -LiteralPath $RepositoryRoot -File -Filter '*.sln*').Count -gt 0) { $tools += 'dotnet' }
        foreach ($tool in $tools) {
            if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Required tool '$tool' is absent on this agent." }
            $version = @(& $tool --version 2>&1)
            if ($LASTEXITCODE -ne 0) { throw "Required tool '$tool' cannot report its version." }
            $checks.Add([pscustomobject]@{ name = $tool; detail = ($version -join ' ').Trim() })
        }
        if ($Config.delivery.provider -eq 'github' -and -not $Config.delivery.dry_run -and
            ($Config.delivery.push_branch -or $Config.delivery.create_draft_pull_request)) {
            . (Join-Path $PSScriptRoot 'github/GitHub.ps1')
            $checkName='GitHub target repository access'
            $githubContext=Get-FoundryGitHubContext -Settings $Config.delivery.github -Environment $ActionEnvironment
            $repository=Invoke-FoundryGitHub -Context $githubContext -Path ''
            if ($repository.archived) {throw 'The target GitHub repository is archived.'}
            $checks.Add([pscustomobject]@{name='github.repository';detail='Repository read access verified. Workflow/contents/PR write permissions are enforced when publishing.'})
        }
        if ($Config.delivery.provider -eq 'azure-devops' -and -not $Config.delivery.dry_run -and
            ($Config.delivery.push_branch -or $Config.delivery.create_draft_pull_request)) {
            $settings = $Config.delivery.azure_devops
            $checkName = 'Azure DevOps secret mapping'
            $secretName = [string]$settings.auth_env
            $token = if ($ActionEnvironment.ContainsKey($secretName)) { ([string]$ActionEnvironment[$secretName]).Trim() } else { '' }
            if (-not $token) { throw "Mapped secret '$secretName' is absent from this process." }
            if ($token -match '^\$\([^)]+\)$') { throw "Mapped secret '$secretName' contains an unexpanded pipeline variable reference." }
            if ($token -match '^(Basic|Bearer)\s' -or $token.StartsWith('"') -or $token.StartsWith("'")) {
                throw "Mapped secret '$secretName' must contain the raw PAT without an authorization prefix or surrounding quotes."
            }
            $checks.Add([pscustomobject]@{name='azure-devops.mapping';detail="Mapped secret '$secretName' is present and contains neither a variable placeholder nor a header prefix. Its value is not recorded."})
            $checkName = 'Azure DevOps PAT identity (connectionData)'
            Write-QaFoundryLog -Message "Checking $checkName using '$secretName'."
            $credential = Get-QaFoundryAzureDevOpsUserContext -AzureDevOpsConfig $settings -ActionEnvironment $ActionEnvironment
            $checks.Add([pscustomobject]@{name='azure-devops.identity';detail='The PAT resolved to the configured user identity.'})
            $checkName = 'Azure DevOps target repository read access'
            $organization = ([string]$settings.organization_url).TrimEnd('/')
            $project = [Uri]::EscapeDataString([string]$settings.project)
            $repository = [Uri]::EscapeDataString([string]$settings.repository_id)
            $null = Invoke-RestMethod -Method Get -TimeoutSec 30 -Headers @{ Authorization = $credential.authorization } `
                -Uri "$organization/$project/_apis/git/repositories/${repository}?api-version=7.1"
            $checks.Add([pscustomobject]@{ name = 'azure-devops'; detail = 'User identity and target repository read access verified. Write authorization remains enforced at delivery.' })
        }
    }
    else { $checks.Add([pscustomobject]@{ name = 'rehearsal'; detail = 'External prerequisites were not contacted.' }) }
}
catch {
    $status = 'blocked'
    # Do not record request headers, credentials or exception response bodies.
    $response = $_.Exception.PSObject.Properties['Response']
    $detail = if ($response -and $null -ne $response.Value) {
        "HTTP $([int]$response.Value.StatusCode). No conclusion about token expiry is inferred from this response."
    } else { [string]$_.Exception.Message }
    $message = "Prerequisite failed at ${checkName}: $detail"
    $checks.Add([pscustomobject]@{ name = 'prerequisite'; detail = $message })
    throw $message
}
finally {
    New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force | Out-Null
    @{ status = $status; checkedAt = [DateTime]::UtcNow.ToString('o'); checks = @($checks) } |
        ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8
}
