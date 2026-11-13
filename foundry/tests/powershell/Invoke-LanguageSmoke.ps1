[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('javascript', 'typescript', 'vitest', 'csharp', 'python', 'robot', 'go')][string]$Case,
    [Parameter(Mandatory)][string]$WorkRoot
)

# Explicit network integration checks of the actual Foundry adapters. No AI,
# product checkout or external test environment is involved. Versions below
# are reproducible compatibility fixtures, not recommended project defaults.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $root 'scripts/Common.ps1')
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
if (Test-Path $WorkRoot) { throw 'Use a new empty work directory for every smoke run.' }
New-Item -ItemType Directory $WorkRoot | Out-Null
function Package([string]$Name, [string]$Version) {
    [pscustomobject]@{ name = $Name; version = $Version; scope = 'dev' }
}
$files = @{}
$scripts = @{}
switch ($Case) {
    'javascript' {
        $ecosystem = 'npm'; $packages = @(Package 'picomatch' '4.0.2')
        $scripts = @{ build = 'node --check tests/smoke.test.mjs'; test = 'node --test --test-reporter=tap tests/*.test.mjs' }
        $files['tests/smoke.test.mjs'] = "import { test } from 'node:test'; import assert from 'node:assert/strict'; import picomatch from 'picomatch'; test('uses installed dependency', () => assert.equal(picomatch('*.js')('app.js'), true));"
    }
    'typescript' {
        $ecosystem = 'npm'; $packages = @((Package '@playwright/test' '1.51.1'), (Package 'typescript' '5.8.3'))
        $scripts = @{ build = 'tsc --noEmit'; test = 'playwright test --reporter=list' }
        $files['tsconfig.json'] = '{"compilerOptions":{"target":"ES2022","module":"NodeNext","moduleResolution":"NodeNext","strict":true,"skipLibCheck":true},"include":["tests/**/*.ts"]}'
        $files['tests/smoke.spec.ts'] = "import { test, expect } from '@playwright/test'; test('executes TypeScript assertion', () => expect(1 + 1).toBe(2));"
    }
    'vitest' {
        $ecosystem = 'npm'; $packages = @(Package 'vitest' '2.1.9')
        $scripts = @{ test = 'vitest run --reporter=verbose' }
        $files['tests/smoke.test.js'] = "import { test, expect } from 'vitest'; test('executes imported assertion', () => expect(1 + 1).toBe(2));"
    }
    'csharp' {
        $ecosystem = 'nuget'
        $packages = @((Package 'Microsoft.NET.Test.Sdk' '17.12.0'), (Package 'MSTest.TestFramework' '3.6.4'), (Package 'MSTest.TestAdapter' '3.6.4'))
        $files['SmokeTests.cs'] = 'using Microsoft.VisualStudio.TestTools.UnitTesting; [TestClass] public sealed class SmokeTests { [TestMethod] public void ExecutesAssertion() { Assert.AreEqual(2, 1 + 1); } }'
    }
    'python' {
        $ecosystem = 'pypi'; $packages = @(Package 'pytest' '8.3.5')
        $files['tests/test_smoke.py'] = "def test_assertion():`n    assert 1 + 1 == 2`n"
    }
    'robot' {
        $ecosystem = 'pypi'; $packages = @(Package 'robotframework' '7.2.2')
        $files['tests/smoke.robot'] = "*** Test Cases ***`nExecutes Assertion`n    Should Be Equal As Integers    2    2`n"
    }
    'go' {
        $ecosystem = 'go'; $packages = @(Package 'github.com/stretchr/testify' 'v1.9.0')
        $files['smoke_test.go'] = "package automation`nimport (`n`t`"testing`"`n`t`"github.com/stretchr/testify/assert`"`n)`nfunc TestInstalledDependency(t *testing.T) { assert.Equal(t, 2, 1 + 1) }`n"
    }
}
$runtime = switch ($ecosystem) {
    'npm' { @{ nodeMajor = 22; npmVersion = '10.9.4'; lockfileVersion = 3 } }
    'nuget' { @{ sdkMajor = 10; targetFramework = 'net10.0' } }
    'pypi' { @{ pythonVersion = '3.13' } }
    'go' { @{ goVersion = '1.26'; modulePath = 'example.invalid/automation' } }
}
$registry = switch ($ecosystem) {
    'npm' { 'https://registry.npmjs.org' }
    'nuget' { 'https://api.nuget.org/v3/index.json' }
    'pypi' { 'https://pypi.org/simple' }
    'go' { 'https://proxy.golang.org' }
}
$toolchain = [pscustomobject]@{ ecosystem = $ecosystem; runtime = [pscustomobject]$runtime; source = [pscustomobject]@{ registry = $registry }; packages = $packages }
$toolchain | ConvertTo-Json -Depth 15 | Set-Content (Join-Path $WorkRoot 'toolchain.json')
$resolution = & (Join-Path $root 'scripts/actions/Resolve-EcosystemLock.ps1') -Toolchain $toolchain `
    -WorkRoot (Join-Path $WorkRoot 'resolve') -ManifestName 'foundry-smoke' -ManifestVersion '1.0.0'
$resolution | ConvertTo-Json -Depth 30 | Set-Content (Join-Path $WorkRoot 'resolution.json')
if (-not $resolution.succeeded) { throw $resolution.detail }
$adapter = Get-QaFoundryEcosystemAdapter $ecosystem
$project = Join-Path $WorkRoot 'verify'
New-Item -ItemType Directory $project | Out-Null
$manifest = & $adapter.GetManifestFileName 'foundry-smoke'
Copy-Item (Join-Path $WorkRoot "resolve/project/$manifest") (Join-Path $project $manifest)
$resolution.lockJson | Set-Content (Join-Path $project $adapter.lockFileName) -NoNewline
if ($adapter.PSObject.Properties['CompleteManifestFromLock']) {
    $completed = & $adapter.CompleteManifestFromLock (Get-Content (Join-Path $project $manifest) -Raw) $resolution.lockJson
    $completed | Set-Content (Join-Path $project $manifest)
}
$identity = & $adapter.ReadManifestIdentity (Get-Content (Join-Path $project $manifest) -Raw)
$verdict = & (Join-Path $root 'scripts/actions/Test-EcosystemLock.ps1') -Toolchain $toolchain `
    -LockJson $resolution.lockJson -ManifestName $identity.name -ManifestVersion $identity.version
if (-not $verdict.accepted) { throw ($verdict.findings -join "`n") }
if ($ecosystem -eq 'npm') {
    $document = Get-Content (Join-Path $project $manifest) -Raw | ConvertFrom-Json -AsHashtable
    $document.scripts = $scripts
    $document | ConvertTo-Json -Depth 15 | Set-Content (Join-Path $project $manifest)
}
if ($ecosystem -eq 'nuget') {
    '<configuration><packageSources><clear/><add key="approved" value="https://api.nuget.org/v3/index.json"/></packageSources></configuration>' | Set-Content (Join-Path $project 'NuGet.Config')
}
foreach ($file in $files.Keys) {
    $path = Join-Path $project $file
    New-Item -ItemType Directory (Split-Path $path -Parent) -Force | Out-Null
    $files[$file] | Set-Content $path
}
$saved = @{}
$environment = @{
    NUGET_PACKAGES = (Join-Path $WorkRoot 'nuget-cache')
    npm_config_cache = (Join-Path $WorkRoot 'npm-cache')
    PIP_CACHE_DIR = (Join-Path $WorkRoot 'pip-cache')
    PIP_DISABLE_PIP_VERSION_CHECK = '1'
    GOPATH = (Join-Path $WorkRoot 'go-path')
    GOMODCACHE = (Join-Path $WorkRoot 'go-modules')
    GOCACHE = (Join-Path $WorkRoot 'go-build')
    GOTOOLCHAIN = 'local'
    GOPROXY = 'https://proxy.golang.org'
    DOTNET_CLI_TELEMETRY_OPTOUT = '1'
    NO_COLOR = '1'
}
foreach ($key in $environment.Keys) {
    $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
    [Environment]::SetEnvironmentVariable($key, $environment[$key], 'Process')
}
function Run-Command($Command, [string]$Name, [switch]$ExpectFailure) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = Resolve-QaFoundryExecutablePath ([string]$Command.executable)
    foreach ($argument in $Command.arguments) { $start.ArgumentList.Add([string]$argument) }
    $start.WorkingDirectory = $project
    $start.UseShellExecute = $false; $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true; $start.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync(); $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(300000)) { $process.Kill($true); throw "$Name timed out" }
        $code = $process.ExitCode
        $output = $stdout.Result + $stderr.Result
        $output | Set-Content (Join-Path $WorkRoot "$Name.log")
        if (($ExpectFailure -and $code -eq 0) -or (-not $ExpectFailure -and $code -ne 0)) { throw "$Case/$Name returned $code; see $WorkRoot/$Name.log" }
        Write-Host "$Case/$Name exit code: $code"
        return [pscustomobject]@{ output = $output; exitCode = $code }
    }
    finally { $process.Dispose() }
}
try {
    $lockBefore = (Get-FileHash (Join-Path $project $adapter.lockFileName)).Hash
    $null = Run-Command (& $adapter.GetInstallCommand $toolchain $project) 'install'
    $null = Run-Command (& $adapter.GetBuildCommand $toolchain $project) 'build'
    $positive = Run-Command (& $adapter.GetTestCommand $toolchain $project) 'positive'
    $summary = & $adapter.ReadTestRunSummary $positive.output $positive.exitCode
    if (-not $summary.parsed -or $summary.total -ne 1 -or $summary.failed -ne 0 -or $summary.skipped -ne 0) { throw "$Case did not report exactly one passing test: $($summary | ConvertTo-Json -Compress)" }
    $probe = & $adapter.NewNegativeProbe $toolchain $project
    if (-not $probe.supported) { throw "$Case negative probe is unavailable" }
    $path = Join-Path $project $probe.relativePath
    New-Item -ItemType Directory (Split-Path $path -Parent) -Force | Out-Null
    $probe.content | Set-Content $path
    $factory = if ($adapter.PSObject.Properties.Name -contains 'GetNegativeProbeTestCommand') { $adapter.GetNegativeProbeTestCommand } else { $adapter.GetTestCommand }
    $negative = Run-Command (& $factory $toolchain $project) 'negative' -ExpectFailure
    if ($negative.output -match 'ReferenceError:|SyntaxError:|ImportError:|ModuleNotFoundError:') { throw "$Case negative probe failed before executing its assertion" }
    $summary = & $adapter.ReadTestRunSummary $negative.output $negative.exitCode
    if (-not $summary.parsed -or $summary.total -ne 2 -or $summary.failed -ne 1 -or $summary.skipped -ne 0) { throw "$Case did not report one failed assertion out of two tests: $($summary | ConvertTo-Json -Compress)" }
    if ((Get-FileHash (Join-Path $project $adapter.lockFileName)).Hash -ne $lockBefore) { throw "$Case changed its resolved lock during verification" }
    [pscustomobject]@{ case = $Case; passed = $true; positiveTests = 1; negativeTests = 2; negativeFailures = 1; lockUnchanged = $true } |
        ConvertTo-Json | Set-Content (Join-Path $WorkRoot 'summary.json')
    Write-Host "PASS: $Case restored, built, executed a real test and detected a broken assertion without changing its lock."
}
finally { foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') } }
