[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$WorkRoot,
    [switch]$ReuseResolution
)

# Explicit network integration check (not part of the mock/unit suite).
# Requires configured Java, Maven and pwsh on PATH. Keeps evidence in WorkRoot.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $root 'scripts/Common.ps1')
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
$toolchain = [pscustomobject]@{
    ecosystem = 'maven'
    runtime = [pscustomobject]@{ javaVersion = '21'; mavenVersion = '3.9' }
    source = [pscustomobject]@{ registry = 'https://repo.maven.apache.org/maven2' }
    packages = @([pscustomobject]@{ name = 'org.junit.jupiter:junit-jupiter'; version = '5.11.3'; scope = 'dev' })
}
$resultPath = Join-Path $WorkRoot 'resolution.json'
if ($ReuseResolution) { $resolution = Get-Content $resultPath -Raw | ConvertFrom-Json }
else {
    $resolution = & (Join-Path $root 'scripts/actions/Resolve-EcosystemLock.ps1') `
        -Toolchain $toolchain -WorkRoot (Join-Path $WorkRoot 'resolve') -ManifestName smoke -ManifestVersion '1.0.0'
    $resolution | ConvertTo-Json -Depth 30 | Set-Content $resultPath
}
if (-not $resolution.succeeded) { throw $resolution.detail }
$project = Join-Path $WorkRoot 'verify'
if (Test-Path $project) { throw 'Use a new WorkRoot: the verification repository must start empty.' }
New-Item -ItemType Directory $project | Out-Null
Copy-Item (Join-Path $WorkRoot 'resolve/project/pom.xml') (Join-Path $project 'pom.xml')
$resolution.lockJson | Set-Content (Join-Path $project 'dependency-lock.txt')
$sourceDir = Join-Path $project 'src/test/java/foundry'
New-Item -ItemType Directory -Path $sourceDir -Force | Out-Null
@'
package foundry;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;
class SmokeTest {
    @Test void executesAnAssertion() { assertEquals(2, 1 + 1); }
}
'@ | Set-Content (Join-Path $sourceDir 'SmokeTest.java')
$adapter = Get-QaFoundryEcosystemAdapter -Ecosystem maven
function Run-Command($Command, [string]$Name, [int]$ExpectedExitCode = 0) {
    Push-Location $Command.workingDirectory
    try {
        $arguments = @($Command.arguments)
        $output = & $Command.executable @arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
        $output | Set-Content (Join-Path $WorkRoot "$Name.log")
        if (($ExpectedExitCode -eq 0 -and $code -ne 0) -or ($ExpectedExitCode -ne 0 -and $code -eq 0)) {
            throw "$Name returned $code; see $WorkRoot/$Name.log"
        }
        Write-Host "$Name exit code: $code"
        return [pscustomobject]@{ output = $output; exitCode = $code }
    }
    finally { Pop-Location }
}
$null = Run-Command (& $adapter.GetInstallCommand $toolchain $project) 'install'
$findings = @(& $adapter.GetInstalledArtefactFindings $toolchain $project $resolution.lockJson)
if ($findings.Count) { throw ($findings -join "`n") }
$null = Run-Command (& $adapter.GetBuildCommand $toolchain $project) 'offline-build'
$positive = Run-Command (& $adapter.GetTestCommand $toolchain $project) 'offline-positive'
$summary = & $adapter.ReadTestRunSummary $positive.output $positive.exitCode
if (-not $summary.parsed -or $summary.total -ne 1 -or $summary.failed -ne 0 -or $summary.skipped -ne 0) {
    throw 'JUnit did not execute exactly one passing test.'
}
$probe = & $adapter.NewNegativeProbe $toolchain $project
if (-not $probe.supported) { throw 'JUnit negative probe is unavailable.' }
$probe.content | Set-Content (Join-Path $project $probe.relativePath)
$negative = Run-Command (& $adapter.GetTestCommand $toolchain $project) 'offline-negative' 1
$summary = & $adapter.ReadTestRunSummary $negative.output $negative.exitCode
if (-not $summary.parsed -or $summary.total -ne 2 -or $summary.failed -ne 1 -or $summary.skipped -ne 0) {
    throw 'The negative probe did not produce exactly one failed assertion out of two tests.'
}
$findings = @(& $adapter.GetInstalledArtefactFindings $toolchain $project $resolution.lockJson)
if ($findings.Count) { throw ($findings -join "`n") }
Write-Host 'PASS: clean restore matches lock; offline JUnit passes and detects a broken assertion; lock still matches.'
