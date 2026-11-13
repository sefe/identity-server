[CmdletBinding()]
param(
    [string]$BootstrapConfigPath,
    [string]$ProjectConfigPath = '',
    # Which ecosystem's runtime to read, and which of its runtime keys. The
    # pipeline pins npm today because the Foundry's own resolver and schema
    # validation need it; a repository whose automation is built on another
    # ecosystem pins that one's runtime through the same script rather than
    # through a second copy of this logic.
    [string]$Ecosystem = "npm",
    [Parameter(Mandatory)][string]$RuntimeKey,
    [switch]$Optional
)

# The resolver refuses to build a lock with a runtime the configured ecosystem
# did not name, and a hosted agent brings whichever version its image happens to
# bundle. Build 469 reached the resolver for the first time and stopped there:
# the image had moved to npm 10.9.8 while the configuration pins 10.9.4. The
# pipeline therefore installs the version the configuration asks for, and it
# reads that version from the same configuration the run itself reads rather
# than repeating the pin in YAML, because a pin kept in two places is a pin that
# eventually disagrees.

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Common.ps1")

$frameworkRoot = Get-QaFoundryRoot
$launcherRoot = (Get-Location).Path
if ($ProjectConfigPath) {
    $projectConfigPath = Resolve-QaFoundryPath -Root $launcherRoot -Path $ProjectConfigPath
}
else {
    if (-not $BootstrapConfigPath) { throw 'Supply ProjectConfigPath or BootstrapConfigPath.' }
    $resolvedConfigPath = Resolve-QaFoundryPath -Root $launcherRoot -Path $BootstrapConfigPath
    if (-not (Test-Path -LiteralPath $resolvedConfigPath -PathType Leaf)) {
        throw "Bootstrap configuration does not exist: $resolvedConfigPath"
    }
    $bootstrapConfig = Import-QaFoundryYaml -Path $resolvedConfigPath -Root $frameworkRoot
    $null = & (Join-Path $PSScriptRoot "Validate-BootstrapConfig.ps1") `
        -Config $bootstrapConfig -Root $frameworkRoot

    $configDirectory = Split-Path $resolvedConfigPath -Parent
    $repositoryRoot = Resolve-QaFoundryPath -Root $configDirectory `
        -Path ([string]$bootstrapConfig.target.repository_path)
    if (-not (Test-Path -LiteralPath $repositoryRoot -PathType Container)) {
        throw "Bootstrap target repository does not exist: $repositoryRoot"
    }
    $repositoryRoot = (Resolve-Path -LiteralPath $repositoryRoot).Path

    $projectConfigInput = [string]$bootstrapConfig.framework.project_config_path
    if ([IO.Path]::IsPathRooted($projectConfigInput)) {
        throw "Bootstrap repository path must be relative: $projectConfigInput"
    }
    $projectConfigPath = [IO.Path]::GetFullPath((Join-Path $repositoryRoot $projectConfigInput))
    if (-not (Test-PathWithinRoot -Candidate $projectConfigPath -Root $repositoryRoot)) {
        throw "Bootstrap path escapes the target repository: $projectConfigInput"
    }
    if (-not (Test-Path -LiteralPath $projectConfigPath -PathType Leaf)) {
        throw "Bootstrap input does not exist: $projectConfigPath"
    }
}
$config = Import-QaFoundryYaml -Path $projectConfigPath -Root $frameworkRoot
$null = & (Join-Path $PSScriptRoot "Validate-QaFoundryConfig.ps1") `
    -Config $config -Root $frameworkRoot

$ecosystems = @(Resolve-QaFoundryAutomationEcosystems -Automation $config.automation)
$selected = @($ecosystems | Where-Object { [string]$_.id -eq $Ecosystem })
if ($selected.Count -eq 0) {
    if ($Optional) { return '' }
    throw "This installation does not support the $Ecosystem ecosystem, so no runtime version is configured."
}
$runtimeKeys = @($selected[0].runtime.Keys)
if ($runtimeKeys -notcontains $RuntimeKey) {
    throw ("The $Ecosystem ecosystem is configured without $RuntimeKey, so the agent cannot be " +
        "pinned to it.")
}
return [string]$selected[0].runtime[$RuntimeKey]
