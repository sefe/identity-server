[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$RuntimeRepository,
    [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$RuntimeRef,
    [Parameter(Mandatory)][string]$Model,
    [string]$Branch='main', [switch]$Publish
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../Common.ps1')
$root=Get-QaFoundryRoot -StartPath (Split-Path $PSScriptRoot -Parent)
$repositoryRoot=(Resolve-Path -LiteralPath $RepositoryRoot).Path
if ($RuntimeRepository -ine $Repository) { throw 'Embedded Foundry must use the same repository as the product.' }
if ($Branch -notmatch '^[A-Za-z0-9][A-Za-z0-9_./-]*$' -or $Branch -match '\.\.|//|/$') { throw 'Invalid target branch.' }
if ([string]::IsNullOrWhiteSpace($Model) -or $Model -notmatch '^[A-Za-z0-9][A-Za-z0-9_.:-]*$') { throw 'Supply an explicit Copilot model permitted by the organization.' }
if ((Resolve-Path -LiteralPath (Join-Path $repositoryRoot 'foundry')).Path -ne $root) {
    throw 'Check out the pinned Foundry runtime into the target repository at foundry/ first.'
}
$directory=Join-Path $repositoryRoot '.qa-foundry-artifacts'
New-Item -ItemType Directory -Path $directory -Force | Out-Null
$config=Import-QaFoundryYaml -Path (Join-Path $root 'config/project.yaml') -Root $root
$config.project.name=$Repository.Split('/')[1];$config.project.source_branch=$Branch
$config.target.repository_path='..'
if (Test-Path -LiteralPath (Join-Path $repositoryRoot 'README.md')) {$config.target.documentation_paths=@('../README.md')}
$config.ai.profiles.copilot.model=$Model
foreach ($route in $config.routing.routes) {$route.workflow=([string]$route.workflow).Replace('../workflows/','../foundry/workflows/')}
foreach ($provider in @('ci','delivery','work_tracking')) {$config.$provider.github.repository=$Repository}
$config.delivery.dry_run=$false
$config.delivery.apply_changes=$true
foreach ($flag in @('create_branch','commit_changes','push_branch','create_draft_pull_request')) {$config.delivery.$flag=[bool]$Publish}
# Workflows use the same explicit model; changing it later is a new run contract.
$configPath=Join-Path $directory 'github-project.json'
$config | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $configPath -Encoding utf8
$bootstrap=Import-QaFoundryYaml -Path (Join-Path $root 'bootstrap/foundry.bootstrap.yaml') -Root $root
$bootstrap.target.repository_path='..';$bootstrap.target.branch=$Branch
$bootstrap.framework.project_config_path='.foundry/project.json'
$bootstrap.github.repository=$Repository;$bootstrap.github.runtime_repository=$RuntimeRepository
$bootstrap.github.runtime_ref=$RuntimeRef;$bootstrap.github.dry_run=-not $Publish
$bootstrapPath=Join-Path $directory 'github-bootstrap.json'
$bootstrap | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $bootstrapPath -Encoding utf8
$null=& (Join-Path $root 'scripts/Validate-QaFoundryConfig.ps1') -Config $config -Root $root
$null=& (Join-Path $root 'scripts/Validate-BootstrapConfig.ps1') -Config $bootstrap -Root $root
return [pscustomobject]@{configPath=$configPath;bootstrapPath=$bootstrapPath}
