[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][string]$Root
)

# Loaded here rather than relied on from the caller. The helpers keep state -
# the ecosystem adapter cache among it - in their own script scope, and a script
# that borrows them from whoever happened to call it finds that state missing.
. (Join-Path $PSScriptRoot "Common.ps1")

$temporary = [System.IO.Path]::GetTempFileName()
try {
    $Config | ConvertTo-Json -Depth 100 |
        Set-Content -Path $temporary -Encoding utf8
    $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
        -ArtifactPath $temporary `
        -SchemaPath (Join-Path $Root "schemas/config/qa-foundry-config.schema.json") `
        -SchemaRoot (Join-Path $Root "schemas")
}
finally {
    Remove-Item -Path $temporary -Force -ErrorAction SilentlyContinue
}

# The schema can say an ecosystem is well formed, but not that it points at
# anything real. An ecosystem naming a source that does not exist, or naming one
# that serves a different kind of package, only fails once a resolver runs an hour
# into a relay, so both are settled here before the first model call.
$sourceNames = @(Get-QaFoundryPropertyNames -InputObject $Config.automation.dependency_sources)
$ecosystemNames = @(Get-QaFoundryPropertyNames -InputObject $Config.automation.ecosystems)
# A registry URL reaches every prompt and every evidence file. Anything that can
# carry a credential in a URL — user info, a query string, a fragment — would put
# that credential in all of them, and a source that declares no authentication has
# no business carrying one anyway.
foreach ($sourceName in $sourceNames) {
    $registry = [string]$Config.automation.dependency_sources.$sourceName.registry
    $uri = $null
    if (-not [Uri]::TryCreate($registry, [UriKind]::Absolute, [ref]$uri)) {
        throw "Dependency source '$sourceName' has a registry that is not an absolute URL: $registry"
    }
    if ($uri.Scheme -ne "https") {
        throw "Dependency source '$sourceName' must fetch over https, not '$($uri.Scheme)'."
    }
    if ([string]::IsNullOrWhiteSpace($uri.Host)) {
        throw "Dependency source '$sourceName' has a registry with no host: $registry"
    }
    if (-not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)) {
        throw ("Dependency source '$sourceName' carries credentials in its registry URL. That URL " +
            "travels into every prompt and every evidence file, so it must name a host and a path " +
            "and nothing else.")
    }
}
$adapterRoot = Join-Path $PSScriptRoot "ecosystems"
foreach ($ecosystemName in $ecosystemNames) {
    $ecosystem = $Config.automation.ecosystems.$ecosystemName
    $sourceName = [string]$ecosystem.source
    if ($sourceName -notin $sourceNames) {
        throw ("Ecosystem '$ecosystemName' resolves from '$sourceName', which is not one of " +
            "the configured dependency sources ($($sourceNames -join ', ')).")
    }
    $source = $Config.automation.dependency_sources.$sourceName
    if ([string]$source.ecosystem -ne [string]$ecosystemName) {
        throw ("Ecosystem '$ecosystemName' resolves from '$sourceName', which serves " +
            "$([string]$source.ecosystem) packages.")
    }
    # Declaring support the runtime cannot deliver is worse than declaring none:
    # the architect would be told it may design in this ecosystem, and the run
    # would die at materialisation with the design already written.
    $adapterPath = Join-Path $adapterRoot ("{0}.Ecosystem.ps1" -f $ecosystemName)
    if (-not (Test-Path -LiteralPath $adapterPath)) {
        throw ("Ecosystem '$ecosystemName' is declared supported but has no adapter at " +
            "scripts/ecosystems/$ecosystemName.Ecosystem.ps1. An ecosystem nothing can install, " +
            "build and run is not supported, whatever the configuration says.")
    }
    # The adapter file existing is not the same as the adapter working. It names
    # the scripts that produce and check its lock files, and an adapter pointing
    # at a script this installation does not ship would let the architect design
    # in an ecosystem nothing here can actually lock.
    $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $ecosystemName
    $adapterKeys = @(Get-QaFoundryPropertyNames -InputObject $adapter)
    foreach ($scriptKey in @("resolveScript", "verifyScript")) {
        if ($adapterKeys -notcontains $scriptKey) {
            throw ("The '$ecosystemName' adapter names no $scriptKey, so nothing here can " +
                "produce or check a lock file for it.")
        }
        $scriptName = [string]$adapter.$scriptKey
        if ([string]::IsNullOrWhiteSpace($scriptName)) {
            throw ("The '$ecosystemName' adapter leaves $scriptKey empty, so nothing here can " +
                "produce or check a lock file for it.")
        }
        $scriptPath = Join-Path (Join-Path $PSScriptRoot "actions") $scriptName
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            throw ("The '$ecosystemName' adapter names $scriptKey '$scriptName', which this " +
                "installation does not ship. An ecosystem whose lock file nothing can produce " +
                "is not supported.")
        }
    }
}
return [pscustomobject]@{ valid = $true }

