[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Directory,
    [string]$Links = '',
    [hashtable]$ActionEnvironment = @{},
    [object]$AzureDevOpsConfig = $null,
    [switch]$Resume
)
$ErrorActionPreference = 'Stop'
$environment = @{ FOUNDRY_DOCUMENTATION_LINKS = $Links }
if ($AzureDevOpsConfig) {
    $environment.FOUNDRY_DOCUMENTATION_ADO_ORG = [string]$AzureDevOpsConfig.organization_url
    $environment.FOUNDRY_DOCUMENTATION_ADO_SCHEME = [string]$AzureDevOpsConfig.auth_scheme
    $name = [string]$AzureDevOpsConfig.auth_env
    if ($ActionEnvironment.ContainsKey($name)) { $environment.FOUNDRY_DOCUMENTATION_ADO_TOKEN = [string]$ActionEnvironment[$name] }
}
$previous = @{}
try {
    foreach ($entry in $environment.GetEnumerator()) {
        $previous[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key)
        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value)
    }
    & node (Join-Path $PSScriptRoot 'helpers/documentation-sources.mjs') $Directory $(if ($Resume) { 'resume' } else { 'new' })
    if ($LASTEXITCODE -ne 0) { throw 'Documentation snapshot could not be prepared; no AI work has started.' }
}
finally {
    foreach ($entry in $previous.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $(if ($null -eq $entry.Value) { [NullString]::Value } else { [string]$entry.Value }))
    }
}
return (Get-Content -LiteralPath (Join-Path $Directory 'sources.json') -Raw | ConvertFrom-Json -Depth 20)
