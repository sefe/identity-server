[CmdletBinding()]
param(
    [switch]$InstallPester,
    [ValidateSet('All', 'Stability')][string]$Suite = 'All',
    [string[]]$FullName = @()
)

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not (Test-Path (Join-Path $root "node_modules/yaml/package.json"))) {
    & npm ci --prefix $root
    if ($LASTEXITCODE -ne 0) {
        throw "npm ci failed."
    }
}

if (-not (Get-Module -ListAvailable -Name Pester | Where-Object {
    $_.Version -ge [version]"5.5.0"
})) {
    if (-not $InstallPester) {
        throw "Pester 5.5+ is required. Re-run with -InstallPester once to install it for the current user."
    }
    Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser -Force -SkipPublisherCheck
}

Get-Module -Name Pester | Where-Object { $_.Version -lt [version]"5.5.0" } |
    Remove-Module -Force
Import-Module -Name Pester -MinimumVersion 5.5.0 -Force

& npm run test:helpers --prefix $root
if ($LASTEXITCODE -ne 0) {
    throw "Node helper tests failed."
}

$settings = New-PesterConfiguration
$settings.Run.Path = if ($Suite -eq 'Stability') {
    @((Join-Path $root 'tests/powershell/Stability.Tests.ps1'), (Join-Path $root 'tests/powershell/RelayLeg.Tests.ps1'))
} else { @(Join-Path $root 'tests/powershell') }
$settings.Run.PassThru = $true
if ($FullName.Count) { $settings.Filter.FullName = $FullName }
$result = Invoke-Pester -Configuration $settings
if ($result.FailedCount -gt 0) {
    throw "$($result.FailedCount) Pester test(s) failed."
}
return $result
