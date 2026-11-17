[CmdletBinding()]
param(
    [string]$BootstrapConfigPath,
    [string]$ProjectConfigPath = '',
    [Parameter(Mandatory)][string]$CacheRoot,
    [string[]]$Ecosystems = @('pypi', 'maven', 'go')
)

# Tooling lives in an agent-owned cache, never in the product checkout. Archives
# are checked against publisher metadata before extraction or execution.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$os = if ($IsWindows) { 'windows' } elseif ($IsLinux) { 'linux' } else { throw 'Runtime preparation supports Windows and Linux agents.' }
$cpu = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
if ($cpu -notin @('x64', 'arm64')) { throw "Unsupported agent architecture: $cpu" }
$cache = [IO.Path]::GetFullPath($CacheRoot)
New-Item -ItemType Directory -Path $cache -Force | Out-Null
$versionReader = Join-Path $PSScriptRoot 'Get-EcosystemRuntimeVersion.ps1'

function Read-Version([string]$Ecosystem, [string]$Key) {
    $value = [string](& $versionReader -BootstrapConfigPath $BootstrapConfigPath -ProjectConfigPath $ProjectConfigPath -Ecosystem $Ecosystem -RuntimeKey $Key -Optional)
    if (-not $value) { return '' }
    if ($value -notmatch '^\d+(\.\d+){0,2}$') { throw "Invalid runtime version for ${Ecosystem}/${Key}." }
    return $value
}
function Run-Tool([string]$Executable, [string[]]$Arguments) {
    & $Executable @Arguments | Out-Host
    if ($LASTEXITCODE -ne 0) { throw "Runtime preparation command failed: $([IO.Path]::GetFileName($Executable)) ($LASTEXITCODE)." }
}
function Add-ToolPath([string]$Directory) {
    $env:PATH = $Directory + [IO.Path]::PathSeparator + $env:PATH
    if ($env:GITHUB_PATH) { Add-Content -LiteralPath $env:GITHUB_PATH -Value $Directory -Encoding utf8 }
    else { Write-Host "##vso[task.prependpath]$Directory" }
}
function Fetch-Archive([string]$Url, [string]$Digest, [string]$Algorithm, [string]$Destination) {
    if ($Url -notmatch '^https://' -or $Digest -notmatch '^[a-fA-F0-9]+$') { throw 'Invalid publisher archive metadata.' }
    $archive = Join-Path $cache ([Guid]::NewGuid().ToString('N') + $(if ($Url -match '\.(zip|whl)(\?|$)') { '.zip' } else { '.tar.gz' }))
    try {
        Invoke-WebRequest -Uri $Url -OutFile $archive -TimeoutSec 180 -MaximumRetryCount 2 | Out-Null
        if ((Get-FileHash -LiteralPath $archive -Algorithm $Algorithm).Hash -ine $Digest) { throw 'Downloaded runtime checksum does not match publisher metadata.' }
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        if ($archive.EndsWith('.zip')) { [IO.Compression.ZipFile]::ExtractToDirectory($archive, $Destination, $true) }
        else { Run-Tool 'tar' @('-xzf', $archive, '-C', $Destination) }
    } finally {
        # Only the individually named temporary download is removed, never a tree.
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    }
}
function Find-One([string]$Directory, [string]$Name) {
    $files = @(Get-ChildItem -LiteralPath $Directory -Recurse -File -Filter $Name)
    if ($files.Count -ne 1) { throw "Expected one $Name under the tool cache; found $($files.Count)." }
    return $files[0].FullName
}

foreach ($ecosystem in $Ecosystems) {
    switch ($ecosystem) {
        'pypi' {
            $version = Read-Version 'pypi' 'python_version'
            if (-not $version) { continue }
            # uv supplies a managed Python without administrator rights or a
            # pre-existing interpreter. Pin the installer; Python stays on the
            # configured line. pip-tools is the adapter's lock writer.
            $uvVersion = '0.12.17'
            $pipToolsVersion = '7.6.1'
            $uvRoot = Join-Path $cache "uv-$uvVersion-$os-$cpu"
            $exeName = if ($IsWindows) { 'uv.exe' } else { 'uv' }
            if (-not (Test-Path -LiteralPath (Join-Path $uvRoot 'ready.txt'))) {
                $metadata = Invoke-RestMethod "https://pypi.org/pypi/uv/$uvVersion/json" -TimeoutSec 30
                $tag = if ($IsWindows) { if ($cpu -eq 'x64') { 'win_amd64' } else { 'win_arm64' } }
                       else { if ($cpu -eq 'x64') { 'manylinux_2_17_x86_64' } else { 'manylinux_2_17_aarch64' } }
                $wheels = @($metadata.urls | Where-Object { $_.filename -like "*$tag*.whl" })
                if ($wheels.Count -ne 1) { throw "No unique uv wheel for $os/$cpu." }
                Fetch-Archive $wheels[0].url $wheels[0].digests.sha256 'SHA256' $uvRoot
                $uv = Find-One $uvRoot $exeName
                if (-not $IsWindows) { Run-Tool 'chmod' @('+x', $uv) }
                Run-Tool $uv @('--version')
                Set-Content (Join-Path $uvRoot 'ready.txt') $uvVersion
            }
            $uv = Find-One $uvRoot $exeName
            $env:UV_CACHE_DIR = Join-Path $cache 'uv-cache'
            $env:UV_PYTHON_INSTALL_DIR = Join-Path $cache 'python-managed'
            $env:UV_NO_PROGRESS = '1'
            $venv = Join-Path $cache "python-$version-tools-$pipToolsVersion-$os-$cpu"
            $bin = Join-Path $venv $(if ($IsWindows) { 'Scripts' } else { 'bin' })
            $python = Join-Path $bin $(if ($IsWindows) { 'python.exe' } else { 'python' })
            if (-not (Test-Path -LiteralPath (Join-Path $venv 'ready.txt'))) {
                Run-Tool $uv @('python', 'install', $version)
                Run-Tool $uv @('venv', '--seed', '--python', $version, '--managed-python', $venv)
                Run-Tool $uv @('pip', 'install', '--python', $python, "pip-tools==$pipToolsVersion")
                Set-Content (Join-Path $venv 'ready.txt') $version
            }
            Add-ToolPath $bin
            Run-Tool $python @('--version')
            Run-Tool $python @('-m', 'piptools', 'compile', '--version')
        }
        'maven' {
            $javaVersion = Read-Version 'maven' 'java_version'
            if (-not $javaVersion) { continue }
            $mavenVersion = Read-Version 'maven' 'maven_version'
            $jdkRoot = Join-Path $cache "jdk-$javaVersion-$os-$cpu"
            if (-not (Test-Path -LiteralPath (Join-Path $jdkRoot 'ready.txt'))) {
                $architecture = if ($cpu -eq 'x64') { 'x64' } else { 'aarch64' }
                $assets = Invoke-RestMethod "https://api.adoptium.net/v3/assets/latest/$javaVersion/hotspot?architecture=$architecture&image_type=jdk&os=$os&vendor=eclipse" -TimeoutSec 30
                if (@($assets).Count -eq 0) { throw "No stable JDK $javaVersion archive for $os/$cpu." }
                $package = $assets[0].binary.package
                Fetch-Archive $package.link $package.checksum 'SHA256' $jdkRoot
                Set-Content (Join-Path $jdkRoot 'ready.txt') $assets[0].version.semver
            }
            $java = Find-One $jdkRoot $(if ($IsWindows) { 'java.exe' } else { 'java' })
            $env:JAVA_HOME = Split-Path (Split-Path $java -Parent) -Parent
            if ($env:GITHUB_ENV) { Add-Content -LiteralPath $env:GITHUB_ENV -Value "JAVA_HOME=$env:JAVA_HOME" -Encoding utf8 }
            else { Write-Host "##vso[task.setvariable variable=JAVA_HOME]$env:JAVA_HOME" }
            Add-ToolPath (Split-Path $java -Parent)
            $mavenRoot = Join-Path $cache "maven-$mavenVersion"
            if (-not (Test-Path -LiteralPath (Join-Path $mavenRoot 'ready.txt'))) {
                $url = "https://archive.apache.org/dist/maven/maven-3/$mavenVersion/binaries/apache-maven-$mavenVersion-bin.zip"
                $checksum = ([string](Invoke-RestMethod "$url.sha512" -TimeoutSec 30)).Trim().Split(' ')[0]
                Fetch-Archive $url $checksum 'SHA512' $mavenRoot
                if (-not $IsWindows) { Run-Tool 'chmod' @('+x', (Find-One $mavenRoot 'mvn')) }
                Set-Content (Join-Path $mavenRoot 'ready.txt') $mavenVersion
            }
            $mvn = Find-One $mavenRoot $(if ($IsWindows) { 'mvn.cmd' } else { 'mvn' })
            Add-ToolPath (Split-Path $mvn -Parent)
            Run-Tool $java @('-version')
            Run-Tool $mvn @('-v')
        }
        'go' {
            $version = Read-Version 'go' 'go_version'
            if (-not $version) { continue }
            $goRoot = Join-Path $cache "go-$version-$os-$cpu"
            if (-not (Test-Path -LiteralPath (Join-Path $goRoot 'ready.txt'))) {
                $releases = Invoke-RestMethod 'https://go.dev/dl/?mode=json&include=all' -TimeoutSec 30
                $release = @($releases | Where-Object { $_.stable -and ($_.version -eq "go$version" -or $_.version.StartsWith("go$version.")) }) | Select-Object -First 1
                if (-not $release) { throw "No stable Go release on configured line $version." }
                $arch = if ($cpu -eq 'x64') { 'amd64' } else { 'arm64' }
                $archive = @($release.files | Where-Object { $_.os -eq $os -and $_.arch -eq $arch -and $_.kind -eq 'archive' })
                if ($archive.Count -ne 1) { throw "No unique Go archive for $os/$cpu." }
                Fetch-Archive ("https://go.dev/dl/" + $archive[0].filename) $archive[0].sha256 'SHA256' $goRoot
                Set-Content (Join-Path $goRoot 'ready.txt') $release.version
            }
            $go = Join-Path $goRoot ('go/bin/' + $(if ($IsWindows) { 'go.exe' } else { 'go' }))
            Add-ToolPath (Split-Path $go -Parent)
            Run-Tool $go @('version')
        }
        default { throw "No additional runtime preparation for $ecosystem." }
    }
}
