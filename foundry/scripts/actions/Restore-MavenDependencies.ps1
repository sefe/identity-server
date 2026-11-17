[CmdletBinding()]
param(
    [string]$MavenPath = 'mvn',
    [Parameter(Mandatory)][string]$RepositoryPath,
    [string]$SettingsPath,
    [string]$Registry
)

# go-offline does not resolve Surefire's dynamically selected providers. Fetch
# them before writing/checking the lock, without compiling or running tests.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../ecosystems/maven.Ecosystem.ps1')

function Invoke-MavenRestoreStep([string[]]$Goals) {
    & $MavenPath '-B' '-ntp' '-C' '--settings' $SettingsPath '--global-settings' $SettingsPath `
        "-Dmaven.repo.local=$RepositoryPath" @Goals | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Maven dependency preparation failed ($LASTEXITCODE): $($Goals -join ' ')" }
}

try {
    if (-not $SettingsPath) {
        if (-not $Registry) {
            # Maintenance quality gates carry the manifest and lock, rather
            # than the original bootstrap toolchain decision.
            $registries = @(foreach ($line in Get-Content -LiteralPath 'dependency-lock.txt') {
                if ($line.Trim() -eq '' -or $line.TrimStart().StartsWith('#')) { continue }
                if ($line -notmatch '^(\S+):(\S+):(\S+)\s+\S+\s+(https://\S+)$') {
                    throw 'Cannot recover the approved registry from the Maven lock.'
                }
                $suffix = '/' + $Matches[1].Replace('.', '/') + '/' + $Matches[2] + '/' + $Matches[3] + '/'
                $address = $Matches[4]
                $offset = $address.LastIndexOf($suffix, [StringComparison]::Ordinal)
                if ($offset -le 0) { throw 'The Maven lock URL does not match its artifact coordinate.' }
                $address.Substring(0, $offset)
            }) | Sort-Object -Unique
            if (@($registries).Count -ne 1) { throw 'The Maven lock must identify one approved registry.' }
            $Registry = [string]@($registries)[0]
        }
        $url = [Security.SecurityElement]::Escape($Registry)
        $SettingsPath = Join-Path (Get-Location) 'foundry-maven-settings.xml'
        @"
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
  <interactiveMode>false</interactiveMode>
  <mirrors><mirror><id>approved</id><url>$url</url><mirrorOf>*</mirrorOf></mirror></mirrors>
</settings>
"@ | Set-Content -LiteralPath $SettingsPath -Encoding utf8
    }
    Invoke-MavenRestoreStep @('dependency:go-offline', 'help:effective-pom',
        '-Doutput=foundry-effective-pom.xml', 'dependency:tree',
        '-DoutputFile=dependency-tree.txt', '-DappendOutput=false')
    $pom = [xml](Get-Content -LiteralPath 'foundry-effective-pom.xml' -Raw)
    $tree = Get-Content -LiteralPath 'dependency-tree.txt' -Raw
    $artifacts = @(Get-QaFoundryMavenTestRuntimeArtifacts -EffectivePom $pom -DependencyTree $tree)
    foreach ($artifact in $artifacts) {
        Invoke-MavenRestoreStep @('dependency:get', "-Dartifact=$artifact", '-Dtransitive=true')
    }
}
catch {
    Write-Error $_ -ErrorAction Continue
    exit 1
}
