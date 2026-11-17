Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-QaFoundryRoot {
    [CmdletBinding()]
    param([string]$StartPath = $PSScriptRoot)

    return (Resolve-Path (Join-Path $StartPath "..")).Path
}

function Resolve-QaFoundryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $Root $Path))
}

function Import-QaFoundryYaml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Root
    )

    $helper = Join-Path $Root "scripts/helpers/ConvertFrom-Yaml.mjs"
    if (-not (Test-Path $helper -PathType Leaf)) {
        throw "YAML helper not found: $helper"
    }
    $output = & node $helper $Path
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to parse YAML: $Path"
    }
    return ($output | ConvertFrom-Json -Depth 100)
}

function ConvertFrom-QaFoundryYamlText {
    # A change set carries pipeline YAML as text that is not on disk yet, and
    # deciding what that text means by searching it for substrings is how a
    # pipeline that never runs gets registered as one that does. The same parser
    # the rest of the installation uses is given the text through a temporary
    # file so that there is exactly one definition of what this YAML says.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)][string]$Root
    )

    $helper = Join-Path $Root "scripts/helpers/ConvertFrom-Yaml.mjs"
    if (-not (Test-Path $helper -PathType Leaf)) {
        throw "YAML helper not found: $helper"
    }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ("qa-foundry-yaml-" + [Guid]::NewGuid().ToString("n") + ".yml")
    try {
        Set-Content -LiteralPath $temporary -Value $Text -Encoding utf8 -NoNewline
        $output = & node $helper $temporary 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "The text is not valid YAML: $((@($output) -join ' ').Trim())"
        }
        $joined = (@($output) -join "")
        if ([string]::IsNullOrWhiteSpace($joined)) { return $null }
        return ($joined | ConvertFrom-Json -Depth 100)
    }
    finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Test-PathWithinRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Root
    )

    $candidateFull = [System.IO.Path]::GetFullPath($Candidate).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar
    )
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar
    )
    return $candidateFull.Equals(
        $rootFull,
        [System.StringComparison]::OrdinalIgnoreCase
    ) -or $candidateFull.StartsWith(
        "$rootFull$([System.IO.Path]::DirectorySeparatorChar)",
        [System.StringComparison]::OrdinalIgnoreCase
    )
}

function Get-QaFoundryPlatformEnvironment {
    [CmdletBinding()]
    param([string[]]$AdditionalNames = @())

    $platformNames = @(
        "PATH", "SystemRoot", "windir", "SystemDrive", "COMSPEC", "PATHEXT",
        "ProgramFiles", "ProgramFiles(x86)",
        "NUMBER_OF_PROCESSORS", "PROCESSOR_ARCHITECTURE", "OS",
        "TMPDIR", "TMP", "TEMP", "LANG", "LC_ALL"
    )
    $environment = [ordered]@{}
    foreach ($name in ($platformNames + $AdditionalNames)) {
        if ([string]::IsNullOrWhiteSpace($name) -or $environment.Contains($name)) {
            continue
        }
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) {
            $environment[$name] = $value
        }
    }
    return $environment
}

# A rehearsed materialisation resolves nothing and carries no lock file, so a
# change set it produced describes a framework whose dependencies were never
# proved to exist. Producing one is the point of a rehearsal; delivering one is
# how an unresolvable framework reaches a repository with an approval attached.
#
# The check lives here, next to the scripts that actually write, because a guard
# placed only in the caller that usually invokes them is not an invariant: the
# bootstrap wrapper calls both directly, and did so without it.
#
# What it guards is the effects that leave this machine - a pushed branch, a
# pull request - because those are what put unresolved content in front of a
# reviewer as though it had been proved. Writing a rehearsal into a working tree
# is the thing being rehearsed: the installation has to appear on disk for
# anyone to look at it, and a tree nothing is published from is scratch.
function Test-QaFoundryDeliveryLeavesMachine {
    [CmdletBinding()]
    param([AllowNull()][object]$DeliveryConfig = $null)

    if ($null -eq $DeliveryConfig) { return $false }
    if ([bool]$DeliveryConfig.dry_run) { return $false }
    return ([bool]$DeliveryConfig.push_branch -or [bool]$DeliveryConfig.create_draft_pull_request)
}

function Assert-QaFoundryRehearsalNotDelivered {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$ChangeSet = $null,
        [string]$ChangeSetPath = "",
        [Parameter(Mandatory)][bool]$DeliveryIsLive,
        [Parameter(Mandatory)][string]$Context
    )
    if (-not $DeliveryIsLive) { return }
    $document = $ChangeSet
    if ($null -eq $document) {
        if ([string]::IsNullOrWhiteSpace($ChangeSetPath) -or
            -not (Test-Path -LiteralPath $ChangeSetPath -PathType Leaf)) {
            return
        }
        $document = Get-Content -LiteralPath $ChangeSetPath -Raw |
            ConvertFrom-Json -Depth 100 -ErrorAction Stop
    }
    if (@(Get-QaFoundryPropertyNames -InputObject $document) -notcontains "details") { return }
    $details = $document.details
    if ($null -eq $details) { return }
    if ((@(Get-QaFoundryPropertyNames -InputObject $details) -contains "dryRun") -and
        [bool]$details.dryRun) {
        $named = if ($ChangeSetPath) { ": $ChangeSetPath" } else { "" }
        throw ("$Context was given a rehearsed change set$named. It carries no resolved lock " +
            "file, so publishing it would put a framework whose dependencies were never " +
            "resolved in front of a reviewer as if they had been.")
    }
}

# Every Azure DevOps request in this runtime is authorised here, from the settings
# block that owns it. The two schemes are not interchangeable and the mistake is
# silent: a personal access token is sent as Basic with an empty user name, while
# a pipeline's own System.AccessToken is a bearer token that Basic-encoding turns
# into an HTML sign-in page with a 200 on it. A caller that hard-codes one scheme,
# or one variable name, works until an installation configures the other and then
# reports that the work item does not exist.
function Get-QaFoundryAzureDevOpsHeaders {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$AzureDevOpsConfig = $null,
        [hashtable]$Environment = @{},
        # A pipeline step maps its credential into the process rather than into a
        # provider environment, so the writers that run there are allowed to look
        # for it. Agents are not: an agent that could read the process environment
        # could read every other secret in it too.
        [switch]$AllowProcessEnvironment,
        [string]$Purpose = "This Azure DevOps request"
    )

    $secretName = ""
    $scheme = ""
    if ($null -ne $AzureDevOpsConfig) {
        $names = @(Get-QaFoundryPropertyNames -InputObject $AzureDevOpsConfig)
        if ($names -contains "auth_env") { $secretName = [string]$AzureDevOpsConfig.auth_env }
        if ($names -contains "auth_scheme") { $scheme = [string]$AzureDevOpsConfig.auth_scheme }
    }
    if ([string]::IsNullOrWhiteSpace($secretName)) { $secretName = "AZURE_DEVOPS_TOKEN" }
    $scheme = ([string]$scheme).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($scheme)) { $scheme = "basic" }

    $token = ""
    if ($Environment.ContainsKey($secretName)) { $token = [string]$Environment[$secretName] }
    if ([string]::IsNullOrWhiteSpace($token) -and $AllowProcessEnvironment) {
        $token = [string][Environment]::GetEnvironmentVariable($secretName)
    }
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw "$Purpose requires the mapped credential '$secretName'."
    }

    $authorization = switch ($scheme) {
        "basic" {
            "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$token"))
        }
        "bearer" { "Bearer $token" }
        default {
            throw ("$Purpose was configured with auth_scheme '$scheme', which this runtime does " +
                "not know how to send. Use 'basic' for a personal access token or 'bearer' for a " +
                "pipeline access token.")
        }
    }
    return [pscustomobject]@{
        headers = @{ Authorization = $authorization }
        environmentName = $secretName
        scheme = $scheme
    }
}

function Get-QaFoundryAzureDevOpsUserContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$AzureDevOpsConfig,
        [Parameter(Mandatory)][hashtable]$ActionEnvironment
    )

    $organization = ([string]$AzureDevOpsConfig.organization_url).TrimEnd("/")
    $secretName = [string]$AzureDevOpsConfig.auth_env
    $authScheme = ([string]$AzureDevOpsConfig.auth_scheme).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($organization)) {
        throw "User-attributed Azure DevOps access requires organization_url."
    }
    if ([string]::IsNullOrWhiteSpace($secretName) -or
        -not $ActionEnvironment.ContainsKey($secretName) -or
        [string]::IsNullOrWhiteSpace([string]$ActionEnvironment[$secretName])) {
        throw "User-attributed Azure DevOps access requires mapped PAT '$secretName'."
    }
    if ($authScheme -ne "basic") {
        throw (
            "User-attributed Azure DevOps writes require auth_scheme 'basic' and a user PAT. " +
            "Bearer/System.AccessToken credentials act as a build service."
        )
    }

    $token = ([string]$ActionEnvironment[$secretName]).Trim()
    $encoded = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$token"))
    $authorization = "Basic $encoded"
    $connection = Invoke-RestMethod -Method Get `
        -Uri "$organization/_apis/connectionData?connectOptions=1&lastChangeId=-1&lastChangeId64=-1" `
        -TimeoutSec 30 `
        -Headers @{ Authorization = $authorization }
    $identity = $connection.authenticatedUser
    if ($null -eq $identity) {
        throw "Azure DevOps did not return the user authenticated by the configured PAT."
    }

    function Get-IdentityProperty {
        param([Parameter(Mandatory)][string]$Name)
        if ($null -eq $identity.properties) { return "" }
        $property = $identity.properties.PSObject.Properties[$Name]
        if ($null -eq $property) { return "" }
        if ($property.Value -is [string]) { return [string]$property.Value }
        foreach ($valueName in @('$value', 'value')) {
            $valueProperty = $property.Value.PSObject.Properties[$valueName]
            if ($null -ne $valueProperty) { return [string]$valueProperty.Value }
        }
        return ""
    }

    $userId = ([string]$identity.id).Trim()
    $displayName = ([string]$identity.providerDisplayName).Trim()
    if ([string]::IsNullOrWhiteSpace($displayName)) {
        $displayName = ([string]$identity.customDisplayName).Trim()
    }
    $email = (Get-IdentityProperty -Name "Mail").Trim()
    if ([string]::IsNullOrWhiteSpace($email)) {
        $email = (Get-IdentityProperty -Name "Account").Trim()
    }
    if ([string]::IsNullOrWhiteSpace($userId) -or
        [string]::IsNullOrWhiteSpace($displayName) -or
        [string]::IsNullOrWhiteSpace($email)) {
        throw "The configured Azure DevOps PAT did not resolve to a complete user identity."
    }

    $configuredUserId = if (
        $AzureDevOpsConfig.PSObject.Properties.Name -contains "expected_user_id"
    ) {
        ([string]$AzureDevOpsConfig.expected_user_id).Trim()
    }
    else { "" }
    if (-not [string]::IsNullOrWhiteSpace($configuredUserId) -and
        -not $userId.Equals($configuredUserId, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The configured Azure DevOps PAT belongs to a different user than expected_user_id."
    }

    $matchBuildRequester = (
        $AzureDevOpsConfig.PSObject.Properties.Name -contains "match_build_requester"
    ) -and [bool]$AzureDevOpsConfig.match_build_requester
    $buildReason = [Environment]::GetEnvironmentVariable("BUILD_REASON")
    $automatedReasons = @("Schedule", "BuildCompletion", "ResourceTrigger")
    $requestedForId = [Environment]::GetEnvironmentVariable("BUILD_REQUESTEDFORID")
    if ($matchBuildRequester -and
        -not [string]::IsNullOrWhiteSpace($requestedForId) -and
        $buildReason -notin $automatedReasons -and
        -not $userId.Equals($requestedForId.Trim(), [StringComparison]::OrdinalIgnoreCase)) {
        throw "The configured Azure DevOps PAT does not belong to the user who requested this build."
    }

    return [pscustomobject][ordered]@{
        authorization = $authorization
        userId = $userId
        displayName = $displayName
        email = $email
    }
}

function Resolve-QaFoundryExecutable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    # Kept as the older $null-on-miss spelling that its callers read, but no
    # longer a second way of searching: one answer to "what will actually start"
    # is the point, and Resolve-QaFoundryExecutablePath is it.
    $path = Resolve-QaFoundryExecutablePath -Name $Name
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    return $path
}

# Being installed is not the same as being able to reach its package feed. This
# repository's NuGet.Config clears every source and leaves one private host on a
# 10.x address, so on a hosted agent `dotnet restore` resolves nothing and simply
# waits until the command timeout kills it. Build 500 spent fifty minutes and a
# whole leg discovering that ten times over, at three hundred seconds each, and
# recorded ten failures that said nothing about the product. A feed that does not
# answer is a fact about the environment, and it is cheaper to establish it once
# than to let every .NET command rediscover it the slow way.
function Test-QaFoundryTcpEndpointReachable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMilliseconds = 4000
    )

    $client = $null
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $operation = $client.BeginConnect($HostName, $Port, $null, $null)
        if (-not $operation.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) { return $false }
        $client.EndConnect($operation)
        return $true
    }
    catch { return $false }
    finally {
        if ($null -ne $client) { $client.Dispose() }
    }
}

function Get-QaFoundryPackageFeedStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [int]$TimeoutMilliseconds = 4000,
        [switch]$Refresh
    )

    if ([string]::IsNullOrWhiteSpace($RepositoryRoot) -or -not (Test-Path $RepositoryRoot)) {
        return $null
    }
    $resolvedRoot = (Resolve-Path $RepositoryRoot).Path
    if (-not (Get-Variable -Name "QaFoundryPackageFeedStatus" -Scope Global -ErrorAction SilentlyContinue)) {
        $global:QaFoundryPackageFeedStatus = @{}
    }
    if (-not $Refresh -and $global:QaFoundryPackageFeedStatus.ContainsKey($resolvedRoot)) {
        return $global:QaFoundryPackageFeedStatus[$resolvedRoot]
    }

    $configPath = @(Get-ChildItem -Path $resolvedRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq "nuget.config" } |
        Select-Object -First 1 -ExpandProperty FullName)
    if ($configPath.Count -eq 0) {
        # No configuration of its own means the ordinary public default, which
        # needs no warning and no probing.
        $global:QaFoundryPackageFeedStatus[$resolvedRoot] = $null
        return $null
    }
    $configPath = $configPath[0]

    $sources = [System.Collections.Generic.List[object]]::new()
    try {
        [xml]$document = Get-Content -LiteralPath $configPath -Raw
        $disabled = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($node in @($document.SelectNodes("//disabledPackageSources/add"))) {
            if ([string]$node.value -match "^\s*true\s*$") { [void]$disabled.Add([string]$node.key) }
        }
        foreach ($node in @($document.SelectNodes("//packageSources/add"))) {
            $key = [string]$node.key
            if ($disabled.Contains($key)) { continue }
            $sources.Add([pscustomobject]@{ Key = $key; Value = [string]$node.value })
        }
    }
    catch {
        # An unreadable configuration is not evidence that the feed is down, and
        # guessing either way would be worse than saying nothing.
        $global:QaFoundryPackageFeedStatus[$resolvedRoot] = $null
        return $null
    }

    $reachable = [System.Collections.Generic.List[string]]::new()
    $unreachable = [System.Collections.Generic.List[string]]::new()
    foreach ($source in $sources) {
        $isReachable = $false
        $uri = $null
        if ([System.Uri]::TryCreate($source.Value, [System.UriKind]::Absolute, [ref]$uri) -and
            $uri.Scheme -in @("http", "https")) {
            $isReachable = Test-QaFoundryTcpEndpointReachable `
                -HostName $uri.Host `
                -Port $uri.Port `
                -TimeoutMilliseconds $TimeoutMilliseconds
        }
        else {
            $localPath = if ([System.IO.Path]::IsPathRooted($source.Value)) { $source.Value }
            else { Join-Path $resolvedRoot $source.Value }
            $isReachable = Test-Path -LiteralPath $localPath
        }
        if ($isReachable) { $reachable.Add($source.Key) } else { $unreachable.Add($source.Key) }
    }

    $status = [pscustomobject]@{
        ConfigPath = $configPath
        SourceCount = $sources.Count
        Reachable = @($reachable)
        Unreachable = @($unreachable)
        Descriptions = @($sources | ForEach-Object { "$($_.Key) ($($_.Value))" })
        AnyReachable = ($sources.Count -eq 0 -or $reachable.Count -gt 0)
    }
    $global:QaFoundryPackageFeedStatus[$resolvedRoot] = $status
    return $status
}

# The extensions Windows can start directly. PATHEXT is deliberately not used as
# the whole answer: it also lists .PS1, .VBS and .MSC, and Get-Command resolves
# 'npm' to npm.ps1, which CreateProcess cannot launch at all. Every child process
# in this runtime is started with UseShellExecute disabled, so a name has to
# resolve to something the operating system will execute on its own.
$script:QaFoundryNativeExecutableExtensions = @(".com", ".exe", ".bat", ".cmd")

function Get-QaFoundryExecutableExtensions {
    if (-not $IsWindows) { return @("") }

    $ordered = [System.Collections.Generic.List[string]]::new()
    $pathExtensions = [Environment]::GetEnvironmentVariable("PATHEXT")
    if (-not [string]::IsNullOrWhiteSpace($pathExtensions)) {
        # PATHEXT states the machine's own preference order, which is the order a
        # user's shell would have used. Only the launchable ones are kept.
        foreach ($extension in ($pathExtensions -split ";")) {
            $trimmed = ([string]$extension).Trim()
            if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
            if ($script:QaFoundryNativeExecutableExtensions -notcontains $trimmed.ToLowerInvariant()) { continue }
            if (-not $ordered.Contains($trimmed)) { $ordered.Add($trimmed) }
        }
    }
    foreach ($extension in $script:QaFoundryNativeExecutableExtensions) {
        if (-not ($ordered | Where-Object { $_ -ieq $extension })) { $ordered.Add($extension) }
    }
    return @($ordered)
}

# Turns the name of a tool into a path the operating system will start, or an
# empty string when the tool is not installed here. Get-Command is not used: it
# marks a runspace as having errored even when the failure is caught, and a
# parallel agent is judged by that flag, and on Windows it answers with the
# PowerShell shim rather than with something CreateProcess accepts.
function Resolve-QaFoundryExecutablePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }

    $extensions = Get-QaFoundryExecutableExtensions
    try {
        if ([System.IO.Path]::IsPathRooted($Name) -or $Name -match "[\\/]") {
            # A caller that already names a location is answered from that
            # location only, so a PATH entry can never stand in for it.
            $rooted = if ([System.IO.Path]::IsPathRooted($Name)) { $Name }
            else { [System.IO.Path]::GetFullPath($Name) }
            if ([System.IO.File]::Exists($rooted)) {
                $suffix = [System.IO.Path]::GetExtension($rooted)
                if (-not $IsWindows -or [string]::IsNullOrWhiteSpace($suffix) -or
                    ($extensions | Where-Object { $_ -ieq $suffix })) {
                    return $rooted
                }
            }
            foreach ($extension in $extensions) {
                if ([string]::IsNullOrWhiteSpace($extension)) { continue }
                $candidate = $rooted + $extension
                if ([System.IO.File]::Exists($candidate)) { return $candidate }
            }
            return ""
        }

        $pathValue = [Environment]::GetEnvironmentVariable("PATH")
        if ([string]::IsNullOrWhiteSpace($pathValue)) { return "" }
        foreach ($directory in ($pathValue -split [System.IO.Path]::PathSeparator)) {
            if ([string]::IsNullOrWhiteSpace($directory)) { continue }
            foreach ($extension in $extensions) {
                $candidate = try { [System.IO.Path]::Combine($directory.Trim(), $Name + $extension) }
                catch { $null }
                if ($null -eq $candidate) { continue }
                if ([System.IO.File]::Exists($candidate)) { return $candidate }
            }
        }
    }
    catch { return "" }
    return ""
}

function Test-QaFoundryExecutableAvailable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)

    return -not [string]::IsNullOrWhiteSpace((Resolve-QaFoundryExecutablePath -Name $Name))
}

$script:QaFoundryPackageRestoringVerbs = @("restore", "build", "test", "publish", "pack", "run", "msbuild")

function Test-QaFoundryCommandNeedsPackageFeed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Executable,
        [AllowEmptyCollection()][string[]]$Arguments = @()
    )

    if ([System.IO.Path]::GetFileNameWithoutExtension($Executable) -ine "dotnet") { return $false }
    foreach ($argument in @($Arguments)) {
        if ([string]::IsNullOrWhiteSpace($argument)) { continue }
        if ($argument.StartsWith("-")) { continue }
        return ($argument.ToLowerInvariant() -in $script:QaFoundryPackageRestoringVerbs)
    }
    return $false
}

function Get-FileSha256Safe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $stream = $null
    try {
        $stream = [IO.File]::Open(
            $Path,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try {
            return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace("-", "").ToLowerInvariant()
        }
        finally { $algorithm.Dispose() }
    }
    catch {
        return $null
    }
    finally {
        if ($stream) { $stream.Dispose() }
    }
}

function Get-UtcTimestamp {
    return [DateTime]::UtcNow.ToString("o")
}

# One definition of what a secret looks like, read by the scan that fails a
# build and by the redaction that runs before anything leaves this machine. Two
# lists would drift, and drift here means a value is sent to a model provider
# and then reported as a finding in the same run.
function Get-QaFoundrySecretRules {
    return @(
        [pscustomobject][ordered]@{
            id = "private-key"
            pattern = "-----BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY-----"
            # Detection only needs the header. Redaction has to take the key
            # material with it, and a truncated file leaves the header without
            # its footer, so the open-ended form follows the closed one.
            redactPatterns = @(
                "-----BEGIN[^-]*PRIVATE KEY-----[\s\S]*?-----END[^-]*PRIVATE KEY-----",
                "-----BEGIN[^-]*PRIVATE KEY-----[\s\S]*"
            )
            replacement = "[redacted:private-key]"
        },
        [pscustomobject][ordered]@{
            id = "github-token"
            pattern = "gh[pousr]_[A-Za-z0-9_]{30,}"
            replacement = "[redacted:github-token]"
        },
        [pscustomobject][ordered]@{
            id = "aws-access-key-id"
            pattern = "(A3T[A-Z0-9]|AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}"
            replacement = "[redacted:aws-access-key-id]"
        },
        [pscustomobject][ordered]@{
            id = "slack-token"
            pattern = "xox[abprs]-[A-Za-z0-9-]{10,}"
            replacement = "[redacted:slack-token]"
        },
        [pscustomobject][ordered]@{
            id = "json-web-token"
            pattern = "eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"
            replacement = "[redacted:json-web-token]"
        },
        [pscustomobject][ordered]@{
            id = "connection-string-secret"
            # The shape an appsettings.json actually carries: a key=value pair
            # inside a longer string, where the surrounding string is worth
            # keeping and the value is not. A value that starts as a placeholder
            # or an environment reference is left alone - flagging '${DB_PWD}'
            # trains everyone to ignore this rule.
            pattern = "(?i)(AccountKey|SharedAccessKey|SharedSecret|Password|Pwd)(\s*=\s*)([^;`"'\s$<%{#][^;`"'\s]{7,})"
            replacement = '${1}${2}[redacted:connection-string-secret]'
        },
        [pscustomobject][ordered]@{
            id = "generic-secret-assignment"
            pattern = '(?i)((?:api[_-]?key|apikey|secret|password|passwd|token|client[_-]?secret|access[_-]?key)[""'']?\s*[:=]\s*)([""''])([^""''\r\n$<%{#][^""''\r\n]{11,})(\2)'
            # The key stays. An agent reading a configuration file has to see
            # that a password is configured and where; it never has to see which
            # one.
            replacement = '${1}${2}[redacted:secret-assignment]${4}'
        },
        [pscustomobject][ordered]@{
            id = "unquoted-secret-assignment"
            # YAML and env-style files write the value bare. Redaction can
            # afford to be wrong here - the cost is an agent seeing a marker
            # instead of a value - but a gate that fails a build cannot, because
            # 'token = process.env.SOMETHING' has this exact shape. So this rule
            # redacts and does not accuse.
            pattern = '(?im)^(\s*-?\s*[A-Za-z0-9_.\-]*(?:api[_-]?key|apikey|secret|password|passwd|token|client[_-]?secret|access[_-]?key)\s*[:=]\s*)([^\s""''$<%{#][^\s""'']{7,})\s*$'
            replacement = '${1}[redacted:secret-assignment]'
            failsBuild = $false
        }
    )
}

# Returns the text with secret values replaced, and says what it replaced. The
# caller is expected to record that: a redaction nobody can see is
# indistinguishable from a file that never held a secret.
function Protect-QaFoundrySecretText {
    [CmdletBinding()]
    param([AllowNull()][AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return [pscustomobject]@{ text = [string]$Text; redactions = @() }
    }
    $result = [string]$Text
    $applied = [System.Collections.Generic.List[string]]::new()
    foreach ($rule in @(Get-QaFoundrySecretRules)) {
        $patterns = if (@(Get-QaFoundryPropertyNames -InputObject $rule) -contains "redactPatterns") {
            @($rule.redactPatterns)
        }
        else { @([string]$rule.pattern) }
        foreach ($pattern in $patterns) {
            $found = [regex]::Matches($result, $pattern)
            if ($found.Count -eq 0) { continue }
            $applied.Add([string]$rule.id)
            $result = [regex]::Replace($result, $pattern, [string]$rule.replacement)
        }
    }
    return [pscustomobject]@{
        text = $result
        redactions = @($applied | Sort-Object -Unique)
    }
}

# The isolation every untrusted command runs under, whichever stage started it.
# Bootstrap verification, an execution plan and the quality suite all run code
# this programme did not write and did not review, so they run behind one
# boundary rather than three that drift apart. The mount path is fixed because
# the environment handed to a container has to name places inside it.
$script:QaFoundryContainerMountPath = "/qa-foundry/work"

# One setting, read the same way by everything that runs untrusted code. It used
# to live under 'automation.verification', which said what it isolated at the
# time and stopped being true the moment execution plans and the quality suite
# ran generated commands too: a run could be configured for a container and
# still execute most of the code an agent wrote directly on the agent. The key
# is now 'automation.isolation', and the old place is still read so an existing
# configuration keeps the boundary it asked for rather than silently losing it.
function Get-QaFoundryIsolationSetting {
    [CmdletBinding()]
    param([AllowNull()][object]$Config = $null)

    if ($null -eq $Config) { return $null }
    $automation = if (@(Get-QaFoundryPropertyNames -InputObject $Config) -contains "automation") {
        $Config.automation
    } else { $null }
    if ($null -eq $automation) { return $null }
    $automationNames = @(Get-QaFoundryPropertyNames -InputObject $automation)
    if ($automationNames -contains "isolation" -and $null -ne $automation.isolation) {
        return $automation.isolation
    }
    if ($automationNames -contains "verification" -and $null -ne $automation.verification) {
        $verification = $automation.verification
        if (@(Get-QaFoundryPropertyNames -InputObject $verification) -contains "isolation") {
            return $verification.isolation
        }
    }
    return $null
}

function Resolve-QaFoundryExecutionIsolation {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Isolation = $null,
        # What is being isolated, for the messages a person has to act on.
        [string]$Subject = "Execution",
        [string]$ConfigurationKey = "automation.isolation"
    )

    $mode = "process"
    if ($null -ne $Isolation -and
        @(Get-QaFoundryPropertyNames -InputObject $Isolation) -contains "mode" -and
        -not [string]::IsNullOrWhiteSpace([string]$Isolation.mode)) {
        $mode = "$($Isolation.mode)".Trim().ToLowerInvariant()
    }
    if ($mode -notin @("process", "container")) {
        throw ("$Subject isolation mode '$mode' is not one this runtime implements. It runs " +
            "untrusted code either in a child process of this run ('process') or in a container " +
            "of its own ('container').")
    }
    if ($mode -eq "process") {
        return [pscustomobject][ordered]@{
            mode = "process"
            detail = ("The command ran as a child process of this run, with an environment built " +
                "rather than inherited.")
            limitations = @(
                ("The child runs as the same operating system user as this run and with the same " +
                 "file permissions, so generated code can read any path that user can read, " +
                 "including this checkout and the real user profile, by absolute path."),
                ("On Windows, .NET and the tools built on it ask the operating system where the " +
                 "user's data lives rather than reading APPDATA, so redirecting the variable does " +
                 "not move them."),
                ("Only a container or an operating system identity of its own closes these; set " +
                 "$ConfigurationKey.mode to 'container' where one is available.")
            )
            executable = ""
            image = ""
            network = ""
            extraArguments = @()
        }
    }

    $container = if (@(Get-QaFoundryPropertyNames -InputObject $Isolation) -contains "container") {
        $Isolation.container
    } else { $null }
    if ($null -eq $container) {
        throw ("$Subject isolation asks for a container and names none. Configure " +
            "$ConfigurationKey.container with the runtime and image to use.")
    }
    $containerNames = @(Get-QaFoundryPropertyNames -InputObject $container)
    $executable = if ($containerNames -contains "executable") { "$($container.executable)".Trim() } else { "" }
    $image = if ($containerNames -contains "image") { "$($container.image)".Trim() } else { "" }
    if ([string]::IsNullOrWhiteSpace($executable) -or [string]::IsNullOrWhiteSpace($image)) {
        throw ("$Subject isolation asks for a container without naming both the runtime " +
            "executable and the image to run. Neither can be guessed: the image decides which " +
            "toolchain is present, and getting it wrong reports the design as broken.")
    }
    # No silent fall back to a child process. A run that believes it is isolated
    # and is not is worse than one that stops: the whole point of the setting is
    # that somebody decided the code being run is not to be trusted with this
    # machine.
    $resolvedExecutable = Resolve-QaFoundryExecutablePath -Name $executable
    if ([string]::IsNullOrWhiteSpace($resolvedExecutable)) {
        throw ("$Subject isolation asks for a container and '$executable' is not installed on " +
            "this agent, so the command was not run. Install a container runtime or set " +
            "$ConfigurationKey.mode to 'process' and accept what that does not isolate.")
    }
    $network = if ($containerNames -contains "network" -and
        -not [string]::IsNullOrWhiteSpace([string]$container.network)) {
        "$($container.network)".Trim()
    } else { "bridge" }
    $extraArguments = if ($containerNames -contains "extra_args") {
        @(@($container.extra_args) | ForEach-Object { "$_" } | Where-Object { $_ })
    } else { @() }
    return [pscustomobject][ordered]@{
        mode = "container"
        detail = ("The command ran inside a '$image' container started with $executable, with " +
            "only the work root mounted.")
        limitations = @(
            ("Only the work root is mounted, so the container cannot reach the agent's profile " +
             "or any credential file outside it - but a container is a boundary the host kernel " +
             "enforces, not a virtual machine."),
            ("Network access is '$network'. Installing dependencies needs one, so a suite that " +
             "reaches further than a package registry is not prevented by this setting alone.")
        )
        executable = $resolvedExecutable
        image = $image
        network = $network
        extraArguments = @($extraArguments)
    }
}

# The environment an untrusted command is given. Built rather than inherited: a
# real profile holds the files package managers keep credentials in - .npmrc,
# NuGet.config, .git-credentials - and pointing generated code at it hands over
# those tokens as surely as exporting them would.
#
# Emptying the environment is not enough on its own. The tools this child runs
# look for credentials in files as well: git reads a global and a system config
# and whatever credential helper they name, curl and Go read .netrc, and npm,
# pip, Composer, Bundler and Maven each read a per-user config. Each is
# therefore pointed somewhere inside the isolated home, or at the platform's
# null device where the tool understands one.
#
# pip is the exception that has to be named: it treats a configuration file that
# does not exist as "no file was named here" and carries on reading the global,
# user and site files anyway. Only the null device makes it stop, so that is
# what it is given.
#
# What this does not do is change who the child runs as. It shares this
# process's user and its file permissions, and on Windows .NET resolves the real
# profile through the OS rather than through APPDATA, so a tool that asks the
# platform where the user's data lives will still be told. The complete answer
# is an identity or a container of its own; this closes the paths a package
# manager takes by default, which is what a generated test or an install script
# would find without looking for one.
function Set-QaFoundryIsolatedEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Diagnostics.ProcessStartInfo]$StartInfo,
        # Where this command's home, caches and neutral configuration live. It
        # has to sit inside whatever the container mounts, or a cache written by
        # one command is gone by the next.
        [Parameter(Mandatory)][string]$IsolationHome,
        [AllowNull()][object]$CommandEnvironment = $null
    )

    $StartInfo.EnvironmentVariables.Clear()
    foreach ($entry in (Get-QaFoundryPlatformEnvironment).GetEnumerator()) {
        $StartInfo.EnvironmentVariables[[string]$entry.Key] = [string]$entry.Value
    }

    $isolatedTemp = Join-Path $IsolationHome "tmp"
    New-Item -ItemType Directory -Path $isolatedTemp -Force | Out-Null
    foreach ($name in @("HOME", "USERPROFILE")) {
        $StartInfo.EnvironmentVariables[$name] = $IsolationHome
    }
    foreach ($name in @("TMPDIR", "TMP", "TEMP")) {
        $StartInfo.EnvironmentVariables[$name] = $isolatedTemp
    }
    $StartInfo.EnvironmentVariables["CI"] = "true"

    # npm refuses to start when two of its configuration files resolve to the
    # same path - it reads that as one file loaded twice under two names - so
    # each of its two is pointed somewhere of its own rather than at the shared
    # neutral one. A live npm run would otherwise fail before it began.
    $neutralConfig = Join-Path $IsolationHome "no-such-config"
    $nullDevice = if ($IsWindows) { "NUL" } else { "/dev/null" }
    $isolatedAppData = Join-Path $IsolationHome "appdata"
    $isolatedLocalAppData = Join-Path $IsolationHome "localappdata"
    New-Item -ItemType Directory -Path $isolatedAppData -Force | Out-Null
    New-Item -ItemType Directory -Path $isolatedLocalAppData -Force | Out-Null
    $isolationPaths = [ordered]@{
        GIT_CONFIG_GLOBAL = $neutralConfig
        GIT_CONFIG_SYSTEM = $neutralConfig
        GIT_TERMINAL_PROMPT = "0"
        NETRC = $neutralConfig
        npm_config_userconfig = (Join-Path $IsolationHome "no-such-user-config")
        npm_config_globalconfig = (Join-Path $IsolationHome "no-such-global-config")
        PIP_CONFIG_FILE = $nullDevice
        COMPOSER_HOME = (Join-Path $IsolationHome "composer")
        BUNDLE_USER_HOME = (Join-Path $IsolationHome "bundle")
        DOTNET_CLI_HOME = $IsolationHome
        DOTNET_CLI_TELEMETRY_OPTOUT = "1"
        # Maven resolves '~/.m2/settings.xml' - where a developer's feed
        # credentials live - from the JVM's user.home, which on Windows comes
        # from the OS rather than from HOME. Naming it outright is the only way
        # to move it. Maven's installation-global settings are deliberately left
        # alone: that is where a build agent's mirror is configured, and it is
        # not where a person's credentials are kept.
        MAVEN_OPTS = "-Duser.home=`"$IsolationHome`" -Djava.awt.headless=true"
        # The two Windows profile directories. They do not stop .NET asking the
        # platform, but they do stop every tool that reads the variable.
        APPDATA = $isolatedAppData
        LOCALAPPDATA = $isolatedLocalAppData
        XDG_CONFIG_HOME = (Join-Path $IsolationHome "config")
        XDG_DATA_HOME = (Join-Path $IsolationHome "data")
        # Where each package manager keeps what it downloaded. These are named
        # rather than left to default for two reasons. The first is the same
        # isolation as everything above: a default cache sits in the agent's
        # profile, beside the credentials this function exists to keep out of
        # reach. The second only shows itself in container mode, where every
        # command is a separate throwaway container and the work root is the one
        # thing that outlives it. A cache under the container's own home is gone
        # by the next command, so a restore step would install packages that the
        # build step - told not to restore again - then cannot find. Under the
        # work root they survive, because the work root is the mount.
        NUGET_PACKAGES = (Join-Path $IsolationHome "nuget/packages")
        NUGET_HTTP_CACHE_PATH = (Join-Path $IsolationHome "nuget/http-cache")
        npm_config_cache = (Join-Path $IsolationHome "npm-cache")
        PIP_CACHE_DIR = (Join-Path $IsolationHome "pip-cache")
        GRADLE_USER_HOME = (Join-Path $IsolationHome "gradle")
        GOPATH = (Join-Path $IsolationHome "go")
        GOMODCACHE = (Join-Path $IsolationHome "go/pkg/mod")
        GOCACHE = (Join-Path $IsolationHome "go-build")
        CARGO_HOME = (Join-Path $IsolationHome "cargo")
    }
    # Maven's local repository is part of the same argument, and Maven takes it
    # as a property rather than as a variable of its own.
    $isolationPaths["MAVEN_OPTS"] = "$($isolationPaths["MAVEN_OPTS"]) " +
        "-Dmaven.repo.local=`"$(Join-Path $IsolationHome "m2/repository")`""
    foreach ($entry in $isolationPaths.GetEnumerator()) {
        $StartInfo.EnvironmentVariables[[string]$entry.Key] = [string]$entry.Value
    }
    # The cache directories are made here rather than left to the tool. In
    # container mode the tool runs as the container's user, and a directory it
    # creates inside the mount belongs to that user afterwards - which is how a
    # later step on the agent, or the cleanup, finds a work root it cannot write.
    foreach ($name in @("NUGET_PACKAGES", "NUGET_HTTP_CACHE_PATH", "npm_config_cache",
        "PIP_CACHE_DIR", "GRADLE_USER_HOME", "GOPATH", "GOMODCACHE", "GOCACHE", "CARGO_HOME")) {
        New-Item -ItemType Directory -Path ([string]$isolationPaths[$name]) -Force | Out-Null
    }

    # Added last and never over the isolation above, so an ecosystem cannot
    # reintroduce a credential by naming a variable this function already set.
    if ($null -ne $CommandEnvironment) {
        foreach ($name in @(Get-QaFoundryPropertyNames -InputObject $CommandEnvironment)) {
            if ($StartInfo.EnvironmentVariables.ContainsKey([string]$name)) { continue }
            $StartInfo.EnvironmentVariables[[string]$name] = [string]$CommandEnvironment.$name
        }
    }
}

# Every path built for the isolated environment is a path on the agent -
# 'C:\...\work\.command-home\nuget\packages' or its POSIX equivalent. Handed to
# a container unchanged it names nothing: the directory does not exist there,
# and a package manager told to keep its cache at a name it cannot create either
# fails or silently falls back to a cache that the next '--rm' throws away.
# Since every one of these paths is already inside the work root, and the work
# root is the mount, the value only has to be said in the container's terms.
function ConvertTo-QaFoundryContainerEnvironmentValue {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory)][string]$HostRoot,
        [string]$MountPath = $script:QaFoundryContainerMountPath
    )

    if ([string]::IsNullOrEmpty($Value)) { return $Value }
    # 'NUL' is the platform's null device on Windows and nowhere else.
    if ($Value -eq "NUL") { return "/dev/null" }

    $resolvedRoot = (Resolve-Path -LiteralPath $HostRoot).Path.TrimEnd([char]'\', [char]'/')
    $result = $Value
    foreach ($form in @($resolvedRoot, ($resolvedRoot -replace '\\', '/'))) {
        if ([string]::IsNullOrEmpty($form)) { continue }
        while ($true) {
            $index = $result.IndexOf($form, [StringComparison]::OrdinalIgnoreCase)
            if ($index -lt 0) { break }
            # Only the part that named a place inside the work root is rewritten.
            # The rest of the value - a Maven property name, a quote - is left as
            # its own author wrote it.
            $tail = $result.Substring($index + $form.Length)
            $cut = $tail.IndexOfAny([char[]]@('"', "'", ';'))
            if ($cut -lt 0) { $cut = $tail.Length }
            $result = $result.Substring(0, $index) + $MountPath +
                ($tail.Substring(0, $cut) -replace '\\', '/') + $tail.Substring($cut)
        }
    }
    return $result
}

# The few variables that tell a container client which daemon to talk to. The
# client is started with a built environment like everything else, so these have
# to be named. They reach the client, never the container.
function Get-QaFoundryContainerClientEnvironment {
    $clientEnvironment = [ordered]@{}
    foreach ($name in @("DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_CONFIG",
        "DOCKER_CERT_PATH", "DOCKER_TLS_VERIFY", "CONTAINER_HOST", "XDG_RUNTIME_DIR")) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) { $clientEnvironment[$name] = $value }
    }
    return $clientEnvironment
}

# Turns a command into the container run that carries it. The command itself is
# not changed, only where it runs: the work root is the single mount, so the
# agent's profile and every credential file on the machine are outside it and
# generated code cannot reach them by absolute path either.
function New-QaFoundryContainerInvocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Isolation,
        [Parameter(Mandatory)][string]$HostRoot,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][System.Diagnostics.ProcessStartInfo]$BuiltEnvironment,
        [string]$NamePrefix = "qa-foundry",
        [string]$MountPath = $script:QaFoundryContainerMountPath
    )

    $resolvedRoot = (Resolve-Path -LiteralPath $HostRoot).Path
    $relativeWorkingDirectory = ([System.IO.Path]::GetRelativePath($resolvedRoot, $WorkingDirectory)) `
        -replace "\\", "/"
    $containerWorkingDirectory = if ($relativeWorkingDirectory -in @(".", "")) {
        $MountPath
    } else { "$MountPath/$relativeWorkingDirectory" }
    $containerArguments = [System.Collections.Generic.List[string]]::new()
    # The client is not the container. Killing 'docker run' on a timeout ends the
    # process holding the console; the daemon goes on running what it started,
    # still holding the work directory the next attempt is about to use, and
    # '--rm' does not fire because the container never exited. The only way to
    # reach it afterwards is by a name given before it started.
    $containerName = "$NamePrefix-" + [guid]::NewGuid().ToString("N").Substring(0, 12)
    foreach ($argument in @(
        "run", "--rm",
        "--name", $containerName,
        "--network", [string]$Isolation.network,
        "--volume", "$($resolvedRoot):$MountPath",
        "--workdir", $containerWorkingDirectory)) {
        $containerArguments.Add([string]$argument)
    }
    # The environment is handed over by name rather than by inheritance, exactly
    # as it is for a child process, so a container run and a process run agree on
    # what the code may see.
    foreach ($name in @($BuiltEnvironment.EnvironmentVariables.Keys | Sort-Object)) {
        # PATH, HOME and the temp directories describe the host and are wrong
        # inside the image, which brings its own.
        if ([string]$name -in @("PATH", "HOME", "USERPROFILE", "TMPDIR", "TMP", "TEMP",
            "APPDATA", "LOCALAPPDATA", "SystemRoot", "windir", "SystemDrive", "COMSPEC",
            "PATHEXT", "ProgramFiles", "ProgramFiles(x86)")) { continue }
        $containerArguments.Add("--env")
        $containerArguments.Add("$name=$(ConvertTo-QaFoundryContainerEnvironmentValue `
            -Value ([string]$BuiltEnvironment.EnvironmentVariables[[string]$name]) `
            -HostRoot $resolvedRoot -MountPath $MountPath)")
    }
    foreach ($argument in @($Isolation.extraArguments)) { $containerArguments.Add([string]$argument) }
    $containerArguments.Add([string]$Isolation.image)
    $containerArguments.Add([string]$Executable)
    foreach ($argument in @($Arguments)) { $containerArguments.Add([string]$argument) }
    return [pscustomobject][ordered]@{
        executable = [string]$Isolation.executable
        arguments = @($containerArguments)
        containerName = $containerName
        workingDirectory = $resolvedRoot
        clientEnvironment = [pscustomobject](Get-QaFoundryContainerClientEnvironment)
    }
}

# A container outlives the client that started it. When a run is killed on a
# timeout, what is killed is 'docker run' - the process holding the console -
# and the daemon carries on running what it was asked for, still holding the
# work directory the next attempt is about to write into. '--rm' does not help:
# it fires when a container exits, and this one has not.
#
# The name given before the container started is the only handle left, and this
# is what it is for. Whether the removal worked is reported rather than
# swallowed, because an agent with a container still on it is not in a state the
# next command can trust.
function Remove-QaFoundryIsolationContainer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Runtime,
        [string]$WorkingDirectory = "",
        [AllowNull()][scriptblock]$Remover = $null
    )

    if ([string]::IsNullOrWhiteSpace($Name)) { return "" }
    if ($null -ne $Remover) {
        return [string](& $Remover $Runtime $Name)
    }
    $executable = Resolve-QaFoundryExecutablePath -Name $Runtime
    if ([string]::IsNullOrWhiteSpace($executable)) {
        return (" The container '$Name' may still be running: the runtime " +
            "'$Runtime' could not be found to remove it.")
    }
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $executable
    foreach ($argument in @("rm", "--force", $Name)) { $startInfo.ArgumentList.Add($argument) }
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $startInfo.WorkingDirectory = $WorkingDirectory
    }
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.EnvironmentVariables.Clear()
    foreach ($entry in (Get-QaFoundryPlatformEnvironment).GetEnumerator()) {
        $startInfo.EnvironmentVariables[[string]$entry.Key] = [string]$entry.Value
    }
    foreach ($entry in (Get-QaFoundryContainerClientEnvironment).GetEnumerator()) {
        $startInfo.EnvironmentVariables[[string]$entry.Key] = [string]$entry.Value
    }
    $remover = [System.Diagnostics.Process]::new()
    $remover.StartInfo = $startInfo
    try {
        $null = $remover.Start()
        if (-not $remover.WaitForExit(60 * 1000)) {
            try { $remover.Kill($true) } catch { }
            return " The container '$Name' may still be running: removing it did not finish."
        }
        if ($remover.ExitCode -ne 0) {
            return (" The container '$Name' may still be running: removing it exited " +
                "$($remover.ExitCode).")
        }
        return " The container '$Name' was removed."
    }
    catch {
        return " The container '$Name' may still be running: $($_.Exception.Message)"
    }
    finally { $remover.Dispose() }
}

function Get-QaFoundryBalancedJsonCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $candidates = [System.Collections.Generic.List[string]]::new()
    $depth = 0
    $start = -1
    $inString = $false
    $escaped = $false
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ($inString) {
            if ($escaped) { $escaped = $false; continue }
            if ($character -eq '\') { $escaped = $true; continue }
            if ($character -eq '"') { $inString = $false }
            continue
        }
        if ($character -eq '"') { $inString = $true; continue }
        if ($character -eq '{') {
            if ($depth -eq 0) { $start = $index }
            $depth++
            continue
        }
        if ($character -eq '}' -and $depth -gt 0) {
            $depth--
            if ($depth -eq 0 -and $start -ge 0) {
                $candidates.Add($Text.Substring($start, $index - $start + 1))
                $start = -1
            }
        }
    }
    return $candidates.ToArray()
}

# A conversational CLI may wrap the required artifact in narration, a fenced code
# block, or trailing commentary. Recover the largest self-consistent JSON object
# instead of rejecting an otherwise valid agent answer.
# PowerShell accepts raw control characters inside JSON string literals, but the
# JSON specification does not and stricter validators reject them. Agents emit
# them whenever they paste a literal newline or tab into a string value, so the
# characters are escaped rather than the whole artifact discarded.
function Repair-QaFoundryJsonControlCharacters {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$JsonText)

    $builder = [System.Text.StringBuilder]::new($JsonText.Length)
    $insideString = $false
    $escaped = $false
    foreach ($character in $JsonText.ToCharArray()) {
        if (-not $insideString) {
            if ($character -eq [char]'"') { $insideString = $true }
            $null = $builder.Append($character)
            continue
        }
        if ($escaped) {
            $escaped = $false
            $null = $builder.Append($character)
            continue
        }
        if ($character -eq [char]'\') {
            $escaped = $true
            $null = $builder.Append($character)
            continue
        }
        if ($character -eq [char]'"') {
            $insideString = $false
            $null = $builder.Append($character)
            continue
        }
        if ([int]$character -lt 0x20) {
            $replacement = switch ([int]$character) {
                8 { '\b' }
                9 { '\t' }
                10 { '\n' }
                12 { '\f' }
                13 { '\r' }
                default { '\u{0:x4}' -f [int]$character }
            }
            $null = $builder.Append($replacement)
            continue
        }
        $null = $builder.Append($character)
    }
    return $builder.ToString()
}

$script:QaFoundryTruncationMarker = "QAFOUNDRY_TRUNCATED_RESPONSE"

# An answer that stops in the middle of a JSON value was cut off by the model's
# output limit. That is a different failure from narration around a complete
# artifact, and it needs different advice, so it is detected on its own.
function Test-QaFoundryJsonTruncated {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $depth = 0
    $inString = $false
    $escaped = $false
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ($inString) {
            if ($escaped) { $escaped = $false; continue }
            if ($character -eq '\') { $escaped = $true; continue }
            if ($character -eq '"') { $inString = $false }
            continue
        }
        if ($character -eq '"') { $inString = $true; continue }
        if ($character -eq '{') { $depth++; continue }
        if ($character -eq '}' -and $depth -gt 0) { $depth-- }
    }
    return ($inString -or $depth -gt 0)
}

function Test-QaFoundryTruncationFailure {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Message)

    return (([string]$Message).Contains($script:QaFoundryTruncationMarker))
}

$script:QaFoundryRedactionMarker = "QAFOUNDRY_REDACTED_RESPONSE"

# The provider runs its own secret filter over the answer before this runtime
# ever sees it, and that filter matches an authorization scheme followed by a
# value. A generated `Bearer ${token}` header, and the credential-shaped canary
# strings a secret scanner has to carry, come back as a row of asterisks with
# the surrounding quote or backtick eaten with them. The result is source code
# that does not compile and a review that correctly calls it critical.
#
# Nothing here can restore the removed characters, because the filter does not
# say how many it took. So the answer is refused and the agent is told to write
# the same value in a shape the filter does not match, which is why the pattern
# is detected rather than repaired.
$script:QaFoundryRedactionPattern = "\*{6,}"

function Test-QaFoundryRedactedText {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Text)

    return ([string]$Text) -match $script:QaFoundryRedactionPattern
}

function Test-QaFoundryRedactionFailure {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Message)

    return (([string]$Message).Contains($script:QaFoundryRedactionMarker))
}

function Get-QaFoundryRedactionAdvice {
    [CmdletBinding()]
    param()

    return @'
The provider filtered your answer before this runtime received it: a literal authorization scheme
followed by a value was replaced with a row of asterisks, and the quote or backtick next to it was
removed with it. Nothing can restore those characters, so the answer is unusable and repeating it
verbatim will fail the same way. Write the same value in a shape the filter does not match: build
the header from parts, so that the scheme sits in its own literal and is concatenated with the
value, rather than writing the scheme and its value adjacent in one literal. The same applies to
credential-shaped sample strings a scanner needs and to prose in comments.
'@
}

# The required top-level field names of the artifact a stage asks for, read from
# the schema it is validated against. Agent schemas name their common fields
# once, in a shared file pulled in through allOf, so the composition is followed
# rather than the names repeated here and left to drift.
function Get-QaFoundryArtifactRequiredProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$SchemaPath,
        [int]$MaxDepth = 4
    )

    $names = [System.Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($SchemaPath) -or -not (Test-Path -LiteralPath $SchemaPath)) {
        return $names.ToArray()
    }

    $pending = [System.Collections.Generic.Queue[object]]::new()
    $pending.Enqueue([pscustomobject]@{ path = (Resolve-Path -LiteralPath $SchemaPath).Path; depth = 0 })
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($pending.Count -gt 0) {
        $item = $pending.Dequeue()
        if ($item.depth -gt $MaxDepth -or -not $seen.Add([string]$item.path)) { continue }
        if (-not (Test-Path -LiteralPath $item.path)) { continue }
        $schema = $null
        try { $schema = Get-Content -LiteralPath $item.path -Raw | ConvertFrom-Json -Depth 100 -ErrorAction Stop }
        catch { continue }
        $branches = [System.Collections.Generic.List[object]]::new()
        $branches.Add($schema)
        $allOf = $schema.PSObject.Properties['allOf']
        if ($null -ne $allOf) {
            foreach ($branch in @($allOf.Value)) { $branches.Add($branch) }
        }
        foreach ($branch in $branches) {
            if ($null -eq $branch) { continue }
            $requiredNames = $branch.PSObject.Properties['required']
            foreach ($name in @(if ($null -ne $requiredNames) { $requiredNames.Value })) {
                if (-not [string]::IsNullOrWhiteSpace($name) -and -not $names.Contains([string]$name)) {
                    $names.Add([string]$name)
                }
            }
            $referenceProperty = $branch.PSObject.Properties['$ref']
            if ($null -eq $referenceProperty) { continue }
            $reference = [string]$referenceProperty.Value
            if ([string]::IsNullOrWhiteSpace($reference) -or $reference.StartsWith("#")) { continue }
            $referenced = Join-Path (Split-Path -Parent $item.path) $reference
            $pending.Enqueue([pscustomobject]@{ path = $referenced; depth = $item.depth + 1 })
        }
    }
    return $names.ToArray()
}

# A model that abandons a half-written artifact and starts it again leaves the
# first copy open inside a string value, so the brace scanner closes it at the
# wrong place and every object after that looks top-level. # A model that abandons a half-written artifact and starts it again leaves the
# first copy open inside a string value, so the brace scanner closes it at the
# wrong place and every object after that looks top-level. The restart itself is
# intact, so each opening brace that is closely followed by a field the artifact
# must have is offered as a possible start, and the ranking decides between them.
function Get-QaFoundryRestartedJsonCandidate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string[]]$AnchorProperty,
        [int]$MaxCandidates = 24
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    $lastClose = $Text.LastIndexOf("}")
    $anchors = @(@($AnchorProperty) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($anchors.Count -eq 0 -or $lastClose -lt 0) { return $candidates.ToArray() }

    # A brace with a required field a few characters after it opens the object
    # that field belongs to. A brace with one far away is an outer or unrelated
    # object that merely contains it, so the near ones are tried first and a
    # name that appears on every entry cannot crowd the real start out.
    $nearest = [System.Collections.Generic.Dictionary[int, int]]::new()
    foreach ($anchor in $anchors) {
        $needle = '"' + $anchor + '"'
        $index = 0
        $seen = 0
        while ($index -ge 0 -and $index -lt $Text.Length -and $seen -lt 8) {
            $index = $Text.IndexOf($needle, $index)
            if ($index -lt 0) { break }
            $seen++
            $opening = $index
            for ($step = 0; $step -lt 3; $step++) {
                if ($opening -le 0) { break }
                $opening = $Text.LastIndexOf("{", $opening - 1)
                if ($opening -lt 0) { break }
                if ($opening -ge $lastClose) { continue }
                $distance = $index - $opening
                if (-not $nearest.ContainsKey($opening) -or $distance -lt $nearest[$opening]) {
                    $nearest[$opening] = $distance
                }
            }
            $index += $needle.Length
        }
    }

    $ordered = @($nearest.GetEnumerator() |
        Sort-Object @{ Expression = { $_.Value } }, @{ Expression = { $_.Key } } |
        Select-Object -First $MaxCandidates)
    foreach ($entry in $ordered) {
        $candidates.Add($Text.Substring($entry.Key, $lastClose - $entry.Key + 1))
    }
    return $candidates.ToArray()
}

function Measure-QaFoundryArtifactFieldMention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string[]]$RequiredProperty
    )

    $count = 0
    foreach ($name in @($RequiredProperty)) {
        if ($Text.Contains('"' + $name + '"')) { $count++ }
    }
    return $count
}

function Measure-QaFoundryArtifactField {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Parsed,
        [string[]]$RequiredProperty
    )

    if ($null -eq $Parsed) { return 0 }
    $present = @($Parsed.PSObject.Properties.Name)
    $count = 0
    foreach ($name in @($RequiredProperty)) {
        if ($present -contains $name) { $count++ }
    }
    return $count
}

function ConvertFrom-QaFoundryAgentJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$RawText,
        [string[]]$RequiredProperty,
        [int]$UnbalancedProbeLimit = 200
    )

    $text = ([string]$RawText).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "The agent returned an empty response instead of the required JSON object."
    }

    # The largest parsable object is the right answer only while every candidate
    # is equally artifact-shaped. When the stage names the fields its artifact
    # must carry, an object that has them outranks a longer one that has none,
    # so an incidental fragment is never mistaken for the artifact.
    $required = @(@($RequiredProperty) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $best = $null
    $bestScore = -1
    foreach ($candidate in (@($text) +
        @(Get-QaFoundryRestartedJsonCandidate -Text $text -AnchorProperty $required) +
        @(Get-QaFoundryBalancedJsonCandidate -Text $text))) {
        $raw = ([string]$candidate).Trim()
        if (-not $raw.StartsWith("{") -or -not $raw.EndsWith("}")) { continue }
        # Ranked before the control characters are escaped, because escaping walks
        # the whole candidate and the field names it is ranked on do not move.
        # A field absent from the text is absent from the object, so this bounds
        # the score from above and skips the work for candidates that cannot win.
        $mentions = Measure-QaFoundryArtifactFieldMention -Text $raw -RequiredProperty $required
        if ($mentions -lt $bestScore) { continue }
        if ($mentions -eq $bestScore -and $null -ne $best -and $raw.Length -le $best.Length) { continue }
        $trimmed = Repair-QaFoundryJsonControlCharacters -JsonText $raw
        $parsed = $null
        try { $parsed = $trimmed | ConvertFrom-Json -Depth 100 -ErrorAction Stop }
        catch { continue }
        $score = Measure-QaFoundryArtifactField -Parsed $parsed -RequiredProperty $required
        if ($score -lt $bestScore) { continue }
        if ($score -eq $bestScore -and $null -ne $best -and $trimmed.Length -le $best.Length) { continue }
        $best = $trimmed
        $bestScore = $score
    }

    if ($null -eq $best) {
        # Unbalanced narration such as "use {curly" keeps the brace scanner open,
        # so probe a bounded set of opening braces against the final closing brace.
        $lastClose = $text.LastIndexOf("}")
        $openings = [System.Collections.Generic.List[int]]::new()
        for ($index = 0; $index -lt $lastClose; $index++) {
            if ($text[$index] -eq '{') { $openings.Add($index) }
        }
        foreach ($opening in @($openings | Select-Object -Last $UnbalancedProbeLimit)) {
            $candidate = Repair-QaFoundryJsonControlCharacters `
                -JsonText $text.Substring($opening, $lastClose - $opening + 1)
            if ($null -ne $best -and $candidate.Length -le $best.Length) { continue }
            $parsed = $null
            try { $parsed = $candidate | ConvertFrom-Json -Depth 100 -ErrorAction Stop }
            catch { continue }
            $best = $candidate
            $bestScore = Measure-QaFoundryArtifactField -Parsed $parsed -RequiredProperty $required
        }
    }

    if ($null -eq $best) {
        # Checked before truncation: an oversized answer that the filter also
        # touched is unusable for a reason no smaller budget can fix, and
        # reporting it as truncation shrinks the budget on the next attempt
        # while hiding the cause.
        if (Test-QaFoundryRedactedText -Text $text) {
            throw (("{0}: the response of {1} could not be parsed and carries the provider's " +
                "redaction marker, so the filter removed part of it. {2}") -f
                $script:QaFoundryRedactionMarker,
                (Format-QaFoundryBytes ([long]$text.Length)),
                (Get-QaFoundryRedactionAdvice))
        }
        if ($text.Length -gt 32768 -and (Test-QaFoundryJsonTruncated -Text $text)) {
            throw ("{0}: the response of {1} ends inside an unterminated JSON value, so nothing could be recovered." -f
                $script:QaFoundryTruncationMarker, (Format-QaFoundryBytes ([long]$text.Length)))
        }
        $preview = $text.Substring(0, [Math]::Min(400, $text.Length))
        throw "The agent response did not contain a parsable JSON object. First 400 characters: $preview"
    }
    # A recovered fragment far smaller than the answer that carried it means the
    # real artifact never closed and some incidental object was picked up instead.
    if ($text.Length -gt 32768 -and $best.Length -lt ($text.Length / 4) -and
        (Test-QaFoundryJsonTruncated -Text $text)) {
        throw ("{0}: the response of {1} ends inside an unterminated JSON value and only {2} could be recovered from it." -f
            $script:QaFoundryTruncationMarker,
            (Format-QaFoundryBytes ([long]$text.Length)),
            (Format-QaFoundryBytes ([long]$best.Length)))
    }
    # The answer names the artifact's fields somewhere, yet nothing carrying them
    # could be parsed out of it. Handing back the unrelated object that did parse
    # spends the attempt on a schema report about missing fields and never says
    # what went wrong, so the real fault is named instead.
    if ($required.Count -gt 0 -and $bestScore -le 0 -and
        (Measure-QaFoundryArtifactFieldMention -Text $text -RequiredProperty $required) -gt 0) {
        throw (("The response of {0} names the required fields ({1}) but no object carrying them " +
            "could be parsed out of it; the largest parsable object was {2} and carried none of " +
            "them. An artifact that is started, abandoned part-way through and then started again " +
            "reads this way, because the abandoned copy leaves a string open and everything after " +
            "it is read as part of that string. Write the artifact once, as a single JSON object " +
            "with no earlier partial copy, and put any narration before it.") -f
            (Format-QaFoundryBytes ([long]$text.Length)),
            (@($required | Select-Object -First 4) -join ", "),
            (Format-QaFoundryBytes ([long]$best.Length)))
    }
    return $best
}

# The full repository context stays on disk as immutable evidence. Prompts get a
# projection: every file whose content was actually collected is kept verbatim,
# while the per-file inventory is bounded and the entries that carry no content
# collapse into skip-reason counts. Those entries only duplicate paths that the
# inventory already lists.
function ConvertTo-QaFoundryRepositoryDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Context,
        [int]$MaxInventoryEntries = 2000
    )

    $inputs = @($Context.analysisInputs)
    $included = @($inputs | Where-Object { $_.included })
    $omitted = @($inputs | Where-Object { -not $_.included })
    $inventory = @($Context.files)
    $keptInventory = @($inventory | Select-Object -First $MaxInventoryEntries)
    $byReason = @($omitted |
        Group-Object skipReason |
        Sort-Object Count -Descending |
        ForEach-Object { [ordered]@{ skipReason = [string]$_.Name; count = $_.Count } })

    return [ordered]@{
        runId = $Context.runId
        collectedAt = $Context.collectedAt
        repositoryRoot = $Context.repositoryRoot
        fileCount = $Context.fileCount
        extensionSummary = @($Context.extensionSummary)
        inventory = [ordered]@{
            totalFiles = @($inventory).Count
            listedHere = @($keptInventory).Count
            truncated = @($inventory).Count -gt @($keptInventory).Count
            files = @($keptInventory)
        }
        analysisInputs = @($included)
        omittedInputs = [ordered]@{
            count = @($omitted).Count
            byReason = @($byReason)
            note = "These inputs carry no collected content. Their paths and sizes are in inventory.files, and their per-file SHA-256 hashes are in the complete artifact."
        }
        contextBytes = $Context.contextBytes
        limits = $Context.limits
        notes = @($Context.notes)
    }
}

function Write-QaFoundryLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [ValidateSet("info", "step", "warn", "error")][string]$Level = "info",
        [int]$Indent = 0,
        [string]$Scope = "",
        [ValidateSet('technical', 'business')][string]$Audience = 'technical'
    )

    $diagnostics = [Environment]::GetEnvironmentVariable('FOUNDRY_DIAGNOSTICS_DIRECTORY')
    if ($diagnostics) {
        New-Item -ItemType Directory -Path $diagnostics -Force | Out-Null
        $streamId = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId
        $record = @{ at = [DateTime]::UtcNow.ToString('o'); level = $Level; scope = $Scope; message = $Message }
        $record | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $diagnostics "$PID-$streamId.jsonl") -Encoding utf8
    }
    if ([Environment]::GetEnvironmentVariable('FOUNDRY_LOG_STYLE') -eq 'summary' -and $Audience -ne 'business' -and
        ($Level -eq 'info' -or ($Level -eq 'step' -and $Scope))) { return }

    $marker = switch ($Level) {
        "step" { "==>" }
        "warn" { "[!] " }
        "error" { "[x] " }
        default { "  - " }
    }
    $padding = " " * ([Math]::Max(0, $Indent) * 2)
    $prefix = if ($Scope) { "[$Scope] " } else { "" }
    Write-Host ("{0}{1} {2}{3}" -f $padding, $marker, $prefix, $Message)
}

function Format-QaFoundryDuration {
    [CmdletBinding()]
    param([Parameter(Mandatory)][TimeSpan]$Duration)

    if ($Duration.TotalSeconds -lt 60) {
        return ("{0:0.0}s" -f $Duration.TotalSeconds)
    }
    return ("{0}m {1:00}s" -f [int]$Duration.TotalMinutes, $Duration.Seconds)
}

function Format-QaFoundryBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory)][long]$Bytes)

    if ($Bytes -lt 1024) { return "$Bytes B" }
    if ($Bytes -lt 1048576) { return ("{0:0.0} KB" -f ($Bytes / 1024)) }
    return ("{0:0.0} MB" -f ($Bytes / 1048576))
}

# Set-StrictMode turns member enumeration over an empty property collection into
# "The property 'Name' cannot be found on this object", so reading the property
# names of an object a model returned as {} throws instead of yielding nothing.
# Build 460 lost leg 1 to that: architecture-critic returned a schema-valid
# review that approved the blueprint but carried "details": {}, reading its
# property names threw, and the catch that treats every failure as a rejected
# artifact deleted the approval and fed the PowerShell fault back to the model
# as schema feedback three times over.
function Get-QaFoundryPropertyNames {
    [CmdletBinding()]
    param([AllowNull()]$InputObject)

    if ($null -eq $InputObject) { return @() }
    if ($InputObject -is [System.Collections.IDictionary]) {
        return @($InputObject.Keys | ForEach-Object { [string]$_ })
    }
    if ($null -eq $InputObject.PSObject) { return @() }
    return @($InputObject.PSObject.Properties | ForEach-Object { $_.Name })
}

# The digest of a string as the repository would hold it: UTF-8, no byte order
# mark, exactly the bytes the applier writes. Named once because a second
# reading that encoded differently would produce a different digest for the same
# file, and two digests for one file is the same as no digest at all.
function Get-QaFoundryTextSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
    return [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

# Whether the repository already holds the result a change describes. This is a
# question about the working tree, asked because an idempotency record is not
# evidence about it: a fresh checkout carries the record - it is committed with
# the run - without carrying the file, and believing the record there would skip
# the only write standing between an approved change set and an empty delivery.
function Test-QaFoundryChangeAlreadyApplied {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    if ($Operation -eq "delete") { return (-not $exists) }
    if (-not $exists) { return $false }
    $actual = [Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData(
            [IO.File]::ReadAllBytes($Path))).ToLowerInvariant()
    return ($actual -eq (Get-QaFoundryTextSha256 -Text $Content))
}

# A JSON pointer as the schema validator reports it, resolved against the parsed
# document. Ajv names the offending value by pointer rather than by property, so
# acting on one specific complaint means being able to read and write exactly
# what it pointed at.
function Get-QaFoundryPointerSegments {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Pointer)

    if (-not $Pointer -or $Pointer -eq "/") { return @() }
    return @($Pointer.TrimStart("/") -split "/" | ForEach-Object {
        ([string]$_).Replace("~1", "/").Replace("~0", "~")
    })
}

function Get-QaFoundryPointerValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Document, [Parameter(Mandatory)][AllowEmptyString()][string]$Pointer)

    $node = $Document
    foreach ($segment in @(Get-QaFoundryPointerSegments -Pointer $Pointer)) {
        if ($null -eq $node) { return $null }
        if ($segment -match "^\d+$" -and
            ($node -is [System.Collections.IList] -or $node -is [array])) {
            $index = [int]$segment
            if ($index -lt 0 -or $index -ge @($node).Count) { return $null }
            $node = @($node)[$index]
            continue
        }
        if (@(Get-QaFoundryPropertyNames -InputObject $node) -notcontains $segment) { return $null }
        $node = $node.$segment
    }
    return $node
}

function Set-QaFoundryPointerValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Document,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Pointer,
        [AllowNull()]$Value
    )

    $segments = @(Get-QaFoundryPointerSegments -Pointer $Pointer)
    if ($segments.Count -eq 0) { return $false }
    $parent = $Document
    foreach ($segment in @($segments | Select-Object -First ($segments.Count - 1))) {
        if ($null -eq $parent) { return $false }
        if ($segment -match "^\d+$" -and
            ($parent -is [System.Collections.IList] -or $parent -is [array])) {
            $index = [int]$segment
            if ($index -lt 0 -or $index -ge @($parent).Count) { return $false }
            $parent = @($parent)[$index]
            continue
        }
        if (@(Get-QaFoundryPropertyNames -InputObject $parent) -notcontains $segment) { return $false }
        $parent = $parent.$segment
    }
    if ($null -eq $parent) { return $false }
    $leaf = [string]$segments[$segments.Count - 1]
    if ($leaf -match "^\d+$" -and ($parent -is [System.Collections.IList])) {
        $index = [int]$leaf
        if ($index -lt 0 -or $index -ge $parent.Count) { return $false }
        $parent[$index] = $Value
        return $true
    }
    if (@(Get-QaFoundryPropertyNames -InputObject $parent) -notcontains $leaf) { return $false }
    $parent.$leaf = $Value
    return $true
}

# The ecosystems this installation can actually install, build and run, shaped
# the same way everywhere they are read. The hash covers everything that changes
# what a resolver would produce - registry, authentication, runtime - so a
# materialiser can later refuse to reuse a lock file that was produced under a
# different ecosystem definition than the one this run was configured with. It
# deliberately says nothing about packages: those are chosen per project from the
# product's own solution and pinned by the resolver, not listed here.
function Resolve-QaFoundryAutomationEcosystems {
    [CmdletBinding()]
    param([AllowNull()]$Automation)

    if ($null -eq $Automation) { return @() }
    $names = @(Get-QaFoundryPropertyNames -InputObject $Automation)
    if ($names -notcontains "ecosystems") { return @() }
    $resolved = foreach ($ecosystemId in @(Get-QaFoundryPropertyNames -InputObject $Automation.ecosystems) | Sort-Object) {
        $ecosystem = $Automation.ecosystems.$ecosystemId
        $sourceId = [string]$ecosystem.source
        $source = $null
        if ($names -contains "dependency_sources") {
            $source = $Automation.dependency_sources.$sourceId
        }
        $runtime = [ordered]@{}
        foreach ($key in @(Get-QaFoundryPropertyNames -InputObject $ecosystem.runtime) | Sort-Object) {
            $runtime[$key] = $ecosystem.runtime.$key
        }
        # An ecosystem is only supported if something here can act on it, and an
        # adapter that is handed a runtime block missing what it needs fails much
        # later, in the middle of a build, with the design already written.
        $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $ecosystemId
        $missingRuntimeKeys = @($adapter.requiredRuntimeKeys | Where-Object { $runtime.Keys -notcontains $_ })
        if ($missingRuntimeKeys.Count -gt 0) {
            throw ("Ecosystem '$ecosystemId' declares no $($missingRuntimeKeys -join ', ') under its " +
                "runtime, and the $([string]$adapter.displayName) adapter cannot build anything " +
                "without it.")
        }
        $canonical = [ordered]@{
            id = [string]$ecosystemId
            recipe = [string]$adapter.recipe
            source = [ordered]@{
                id = $sourceId
                registry = [string]$source.registry
                authentication = [string]$source.authentication
            }
            runtime = $runtime
            canonicalRuntime = (& $adapter.ReadRuntime $runtime)
        }
        $canonicalJson = $canonical | ConvertTo-Json -Depth 10 -Compress
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $digest = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($canonicalJson))
        }
        finally {
            $sha256.Dispose()
        }
        $canonical.sha256 = ([System.BitConverter]::ToString($digest) -replace "-", "").ToLowerInvariant()
        $canonical
    }
    return @($resolved)
}

# The architect states the runtime the design is for in whatever words the
# ecosystem uses for it - "net10.0", ".NET 10", "Node.js 22", "3.12". What the
# resolver needs is the number in it, so that the design's choice can be checked
# against the runtime this installation actually has instead of being replaced
# by it without a word.
function Get-QaFoundryProposedRuntimeVersion {
    [CmdletBinding()]
    param([string]$Name = "", [string]$Version = "")

    # A stated version decides on its own. Falling through to the name when the
    # version cannot be read was how 'latest' passed for a design whose name
    # happened to carry a number: "Node.js 22" with version "latest" was locked
    # as Node 22, which is a version nobody stated and nobody checked. The name
    # is read only when no version was stated at all.
    $candidates = if (-not [string]::IsNullOrWhiteSpace([string]$Version)) { @($Version) }
        else { @($Name) }
    foreach ($candidate in $candidates) {
        $text = ([string]$candidate).Trim()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        # Read the primary version in source order. Preferring a trailing or
        # dotted number interpreted "22 (npm 10.9.4)" as Node 10 and
        # "net8.0 on SDK 10" as target net10.0. Later tool versions are context.
        # 'net10.0' and 'netcoreapp3.1' carry the number in the word itself.
        if ($text -match '(\d+(?:\.\d+)*)') {
            return [string]$Matches[1]
        }
    }
    return ""
}

function Get-QaFoundryRuntimeVersionMajor {
    [CmdletBinding()]
    param([string]$Version = "")

    $text = ([string]$Version).Trim()
    if ($text -match '^(\d+)') { return [int]$Matches[1] }
    return 0
}

# A design may leave the runtime version unstated, and then the configured one
# stands. What it may not do is state one this runtime cannot read: "LTS",
# "current" and "latest" all name a moving target, and a version nobody can pin
# is a version nobody can check the installation against. The runtime's name is
# an identity rather than a version, so naming "node" and no number states
# nothing that needs checking.
function Test-QaFoundryProposedRuntimeReadable {
    [CmdletBinding()]
    param([string]$Label = "runtime", [string]$ProposedName = "", [string]$ProposedVersion = "")

    if ([string]::IsNullOrWhiteSpace($ProposedVersion)) { return }
    throw ("The design states its $Label version as '$(([string]$ProposedVersion).Trim())', which " +
        "names no version this runtime can check against the installed one. State the version " +
        "the automation is written for, such as a major and minor number.")
}

# A design that asks for '3.12' is satisfied by an installation running '3.12.4'
# and is not satisfied by one running '3.1'. Comparing the text alone would
# accept the second, because '3.1' is a prefix of '3.12' as characters; the
# comparison has to be by component.
function Test-QaFoundryRuntimeVersionSatisfied {
    [CmdletBinding()]
    param([string]$Requested = "", [string]$Installed = "")

    if ([string]::IsNullOrWhiteSpace($Requested)) { return $true }
    $requestedParts = @(([string]$Requested).Trim().Split(".") | Where-Object { $_ -ne "" })
    $installedParts = @(([string]$Installed).Trim().Split(".") | Where-Object { $_ -ne "" })
    if ($requestedParts.Count -eq 0) { return $true }
    if ($installedParts.Count -lt $requestedParts.Count) { return $false }
    for ($index = 0; $index -lt $requestedParts.Count; $index++) {
        if ($requestedParts[$index] -ne $installedParts[$index]) { return $false }
    }
    return $true
}

# Most ecosystems name their runtime as a plain version string and are not
# backward-compatible across it, so the rule is the same in all of them: the
# version the design asks for has to be the one this installation runs. Written
# once because an adapter that got it slightly differently would refuse, or
# accept, a design its neighbours would not.
function Resolve-QaFoundryVersionedRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Canonical,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Label,
        [string]$ProposedName = "",
        [string]$ProposedVersion = ""
    )

    $installed = [string]$Canonical[$Key]
    $requested = Get-QaFoundryProposedRuntimeVersion -Name $ProposedName -Version $ProposedVersion
    if ([string]::IsNullOrWhiteSpace($requested)) {
        # Silence and unreadability are not the same answer. A design that named
        # no runtime leaves the configured one standing; a design that named
        # "LTS" or "current" stated something this runtime cannot check, and
        # accepting it would be the silent overwrite this whole rule exists to
        # stop, only with an extra step.
        Test-QaFoundryProposedRuntimeReadable -Label $Label `
            -ProposedName $ProposedName -ProposedVersion $ProposedVersion
        return $Canonical
    }
    if (Test-QaFoundryRuntimeVersionSatisfied -Requested $requested -Installed $installed) {
        return $Canonical
    }
    throw ("The design is written for $Label $requested, and this installation runs $Label " +
        "$installed. Either configure the automation ecosystem for $requested or design " +
        "against $installed.")
}

# What a test command actually proved, read from the runner's own summary rather
# than from its exit code. A runner exits zero when every test passed and when it
# found nothing to run, so an exit code alone cannot tell a green suite from a
# deleted one - which is how a repository can lose its tests and stay green.
#
# This is the one place the rule lives. The bootstrap stage that first proves a
# framework and the quality gate that guards every later change both read it
# here, because a rule enforced in one of those places and not the other is a
# rule that only applies until the code is merged.
function Get-QaFoundryTestRunVerdict {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Ecosystem,
        [AllowNull()][AllowEmptyString()][string]$Output = "",
        [int]$ExitCode = 0
    )

    $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $Ecosystem
    $summary = & $adapter.ReadTestRunSummary "$Output" $ExitCode
    $summaryNames = @(Get-QaFoundryPropertyNames -InputObject $summary)
    $parsed = [bool]$summary.parsed
    $total = [int]$summary.total
    $failed = [int]$summary.failed
    $skipped = if ($summaryNames -contains "skipped") { [int]$summary.skipped } else { 0 }
    # What has to move is the number of tests that ran, not the number the runner
    # listed: a skipped test is in the total and asserted nothing.
    $executed = $total - $skipped
    if ($executed -lt 0) { $executed = 0 }

    $verdict = "proved"
    $reason = ""
    if (-not $parsed) {
        $verdict = "unreadable"
        $reason = ("The runner printed no summary this runtime can read, so the number of tests " +
            "that ran is unknown and nothing has been proved.")
    }
    elseif ($total -le 0) {
        $verdict = "empty"
        $reason = ("The runner discovered no tests. An empty suite passes every time and reports " +
            "nothing, so it is not a suite that can go red.")
    }
    elseif ($executed -le 0) {
        # A suite whose every test is skipped exits zero and prints a summary, so
        # it satisfies both checks above while asserting nothing whatever.
        $verdict = "all-skipped"
        $reason = ("All $total test(s) the runner found were skipped, so nothing was asserted. " +
            "A suite that does not run proves no more than an empty one.")
    }
    elseif ($ExitCode -ne 0 -or $failed -gt 0) {
        $verdict = "failed"
        $reason = "$failed of $total test(s) failed."
    }

    return [pscustomobject][ordered]@{
        verdict = $verdict
        proved = ($verdict -eq "proved")
        reason = $reason
        parsed = $parsed
        total = $total
        executed = $executed
        skipped = $skipped
        failed = $failed
    }
}

# The three commands one automation project answers to, with an id that carries
# the project they belong to. Split out of the gate resolver because a gate
# covers however many projects the architecture stage chose, and every one of
# them needs its own install, build and test.
function New-QaFoundryAutomationGateCommands {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Adapter,
        [Parameter(Mandatory)][string]$ManifestPath,
        [Parameter(Mandatory)][string]$ProjectPath
    )

    # Two adapters choose their test command from what the project depends on -
    # cucumber rather than rspec, behat rather than phpunit - so the packages are
    # read back out of the manifest that is there. The lock this was resolved
    # from belongs to the bootstrap run and is long gone by the time a work item
    # is implemented; the manifest is what survives in the repository.
    $packages = @()
    try {
        $manifestContent = Get-Content -LiteralPath $ManifestPath -Raw
        $packages = @(@(& $Adapter.ReadManifestDependencies $manifestContent) | ForEach-Object {
            [pscustomobject]@{ name = [string]$_.name; version = [string]$_.version }
        })
    }
    catch {
        $packages = @()
    }
    $toolchain = [pscustomobject]@{
        ecosystem = [string]$Adapter.id
        packages = @($packages)
        runtime = [pscustomobject]@{}
    }

    # The id carries the project it belongs to. Without it every project produced
    # the same three ids, and the collector, which ignores an id it has already
    # seen, silently ran only the first: the second automation project was never
    # installed, built or tested and its absence looked like agreement.
    #
    # The readable part of the id is lossy on purpose - 'automation/a/b' and
    # 'automation/a-b' both read as 'automation-a-b' - so a short digest of the
    # exact path is carried with it. The name stays readable in a report and the
    # id stays one-to-one with the directory it ran in.
    $normalisedPath = "$ProjectPath" -replace "\\", "/"
    $slug = ($normalisedPath -replace "[^a-zA-Z0-9]+", "-").Trim("-").ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = "root" }
    $digest = [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::UTF8.GetBytes($normalisedPath))
    ).Replace("-", "").ToLowerInvariant().Substring(0, 8)
    $slug = "$slug-$digest"

    $commands = [System.Collections.Generic.List[object]]::new()
    foreach ($stage in @(
        @{ key = "GetInstallCommand"; id = "automation-install"; category = "dependency" },
        @{ key = "GetBuildCommand"; id = "automation-build"; category = "build" },
        @{ key = "GetTestCommand"; id = "automation-test"; category = "test" }
    )) {
        $command = & $Adapter."$($stage.key)" $toolchain (Split-Path $ManifestPath -Parent)
        $commands.Add([pscustomobject]@{
            id = "$([string]$stage.id)-$slug"
            # The name this gate used to answer to. A configuration that still
            # pins a hand-written command under it is superseded by this one,
            # which is what kept a stale pin from running instead.
            supersedes = [string]$stage.id
            category = [string]$stage.category
            # Carried so the gate that runs this command can read the runner's
            # own summary afterwards. Without it a test command is judged by its
            # exit code, and a suite with no tests left in it exits zero.
            ecosystem = [string]$Adapter.id
            manifestPath = $ManifestPath
            executable = [string]$command.executable
            arguments = @($command.arguments)
            workingDirectory = $ProjectPath
        })
    }
    return @($commands)
}

function Get-QaFoundryWorkspaceMembers {
    # What a manifest says belongs to it. A root that claims the tree below it
    # without listing what is down there installs nothing for those projects,
    # and they go untested behind a gate that reports success - so the claim is
    # read from the file rather than assumed from the file's position.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Adapter,
        [Parameter(Mandatory)][string]$ManifestPath
    )

    if (@(Get-QaFoundryPropertyNames -InputObject $Adapter) -notcontains "ReadWorkspaceMembers") {
        return @()
    }
    $members = @()
    try { $members = @(& $Adapter.ReadWorkspaceMembers $ManifestPath) }
    catch {
        # A manifest that cannot be read claims nothing. Treating it as a
        # workspace root on the strength of a parse failure would swallow the
        # projects below it, which is the outcome this exists to prevent.
        return @()
    }
    return @($members |
        ForEach-Object { ([string]$_).Replace("\", "/").Trim().Trim([char]"/") } |
        Where-Object { $_ -ne "" })
}

# The quality gate for generated automation used to be a command written by
# hand: an npm install, aimed at a directory, in a configuration file that was
# edited long before any architecture stage chose an ecosystem. When the two
# disagreed the gate ran the wrong tool in the right place and failed the run for
# a reason that had nothing to do with the work. What is configured now is the
# place; what runs there is decided by the manifest actually sitting in it, so
# the gate follows the design instead of predating it.
#
# A gate names a place, and the place normally holds several projects: this
# installation asks the architecture stage for at least two, an API suite and a
# UI suite being the ordinary answer. So the gate expands into one set of
# commands per project rather than refusing because it found more than one.
# Refusing was the older behaviour and it made the standard shape of the
# programme's own output unrunnable.
function Resolve-QaFoundryAutomationGate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$EcosystemIds
    )

    $absolute = Resolve-QaFoundryPath -Root $RepositoryRoot -Path $Path
    if (-not (Test-Path -LiteralPath $absolute -PathType Container)) {
        return [pscustomobject]@{
            resolved = $false
            reason = ("No directory at '$Path', so there is no generated automation to " +
                "install, build or test yet.")
            ecosystem = ""; projectPath = ""; commands = @(); projects = @(); problems = @()
        }
    }

    $files = @(Get-ChildItem -LiteralPath $absolute -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch "[\\/](node_modules|bin|obj|vendor|\.git|\.m2-repo)[\\/]" })
    $matched = [System.Collections.Generic.List[object]]::new()
    foreach ($ecosystemId in @($EcosystemIds | Sort-Object -Unique)) {
        $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $ecosystemId
        foreach ($file in $files) {
            $relative = ([System.IO.Path]::GetRelativePath($absolute, $file.FullName)) -replace "\\", "/"
            if ($relative -match [string]$adapter.manifestPattern) {
                $relativeDirectory = ([System.IO.Path]::GetRelativePath($absolute, $file.DirectoryName)) `
                    -replace "\\", "/"
                if ($relativeDirectory -eq ".") { $relativeDirectory = "" }
                $matched.Add([pscustomobject]@{
                    ecosystem = $ecosystemId
                    adapter = $adapter
                    file = $file
                    relativeDirectory = $relativeDirectory
                    depth = @(@($relativeDirectory -split "/") | Where-Object { $_ -ne "" }).Count
                })
            }
        }
    }

    if ($matched.Count -eq 0) {
        return [pscustomobject]@{
            resolved = $false
            reason = ("'$Path' holds no manifest belonging to any ecosystem this installation " +
                "supports ($(@($EcosystemIds | Sort-Object) -join ', ')), so no install, build or " +
                "test command could be derived for it.")
            ecosystem = ""; projectPath = ""; commands = @(); projects = @(); problems = @()
        }
    }

    # Grouping used to be by the first path segment under the gate, and that
    # segment is not a project. Two suites written where this installation asks
    # for them - automation/Suites/Api and automation/Suites/Ui - both grouped
    # under 'Suites', and only the shallowest manifest in the group was ever
    # read: the other suite was never installed, never built and never run, and
    # the gate reported success. Put an API project beside a UI project in two
    # different ecosystems and the same grouping refused the gate outright for
    # holding more than one ecosystem, which is the ordinary shape here.
    #
    # A project is the directory its manifest sits in. A manifest below another
    # one belongs to it only when that other one says so - a workspace root
    # naming its members, a POM naming its modules - because a root that claims
    # a tree it does not list installs nothing for what is under it, and the
    # suites down there go untested while the gate passes.
    $candidates = [ordered]@{}
    foreach ($entry in @($matched | Sort-Object depth, relativeDirectory)) {
        $key = "$([string]$entry.relativeDirectory)"
        if (-not $candidates.Contains($key)) {
            $candidates[$key] = [System.Collections.Generic.List[object]]::new()
        }
        $candidates[$key].Add($entry)
    }
    $groups = [ordered]@{}
    foreach ($key in @($candidates.Keys)) {
        $group = @($candidates[$key])
        # $null, not "": the gate's own directory is a legitimate owner and its
        # key is the empty string, so an empty owner is not the same as none.
        $owner = $null
        foreach ($accepted in @($groups.Keys)) {
            $prefix = if ("$accepted" -eq "") { "" } else { "$accepted/" }
            if ("$key" -eq "$accepted") { continue }
            if ("$prefix" -ne "" -and -not "$key".StartsWith($prefix, [StringComparison]::Ordinal)) {
                continue
            }
            $relative = if ("$prefix" -eq "") { "$key" } else { "$key".Substring($prefix.Length) }
            if ("$relative" -eq "") { continue }
            foreach ($rootEntry in @($groups[$accepted])) {
                if ([string]$rootEntry.ecosystem -ne [string]$group[0].ecosystem) { continue }
                $members = @(Get-QaFoundryWorkspaceMembers -Adapter $rootEntry.adapter `
                    -ManifestPath $rootEntry.file.FullName)
                foreach ($member in $members) {
                    if ($relative -like $member -or "$relative/" -like "$member/") {
                        $owner = [string]$accepted
                        break
                    }
                }
                if ($null -ne $owner) { break }
            }
            if ($null -ne $owner) { break }
        }
        if ($null -ne $owner) { continue }
        $groups[$key] = $group
    }

    $projects = [System.Collections.Generic.List[object]]::new()
    $problems = [System.Collections.Generic.List[object]]::new()
    $allCommands = [System.Collections.Generic.List[object]]::new()
    foreach ($key in @($groups.Keys | Sort-Object)) {
        $group = @($groups[$key])
        $groupPath = if ([string]::IsNullOrWhiteSpace($key)) { $Path } else { "$Path/$key" }
        $ecosystemsFound = @(@($group | ForEach-Object { [string]$_.ecosystem }) | Sort-Object -Unique)
        if ($ecosystemsFound.Count -ne 1) {
            # Two ecosystems inside one project is the one case that stays a
            # refusal: nothing on disk says which of them the suite is written
            # in, and guessing would leave the other untested.
            $problems.Add([pscustomobject]@{
                path = $groupPath
                reason = ("'$groupPath' holds manifests from more than one ecosystem " +
                    "($($ecosystemsFound -join ', ')). Guessing which one the gate is for would " +
                    "silently leave the other untested.")
            })
            continue
        }
        # A group is one directory, so anything left in it is a second manifest
        # of the same ecosystem for the same project - a csproj beside a
        # Directory.Build.props, say. The first by name is the project's own.
        $entry = @($group | Sort-Object depth, relativeDirectory)[0]
        $projectPath = ([System.IO.Path]::GetRelativePath($RepositoryRoot, $entry.file.DirectoryName)) `
            -replace "\\", "/"
        $commands = @(New-QaFoundryAutomationGateCommands -Adapter $entry.adapter `
            -ManifestPath $entry.file.FullName -ProjectPath $projectPath)
        foreach ($command in $commands) { $allCommands.Add($command) }
        $projects.Add([pscustomobject]@{
            ecosystem = [string]$entry.adapter.id
            projectPath = $projectPath
            commands = @($commands)
        })
    }

    if ($projects.Count -eq 0) {
        return [pscustomobject]@{
            resolved = $false
            reason = (@($problems | ForEach-Object { [string]$_.reason }) -join " ")
            ecosystem = ""; projectPath = ""; commands = @()
            projects = @(); problems = @($problems)
        }
    }

    # 'ecosystem' and 'projectPath' describe the first project only. They are the
    # whole answer for a gate over one project and a summary for a gate over
    # several; 'projects' is what carries the rest.
    return [pscustomobject]@{
        resolved = $true
        reason = ""
        ecosystem = [string]$projects[0].ecosystem
        projectPath = [string]$projects[0].projectPath
        commands = @($allCommands)
        projects = @($projects)
        problems = @($problems)
    }
}

# The constraints every resolved dependency set has to satisfy, with the defaults
# a configuration may leave out. Read in one place so the resolver, the critics
# and the prompt all describe the same limits.
function Resolve-QaFoundryPackagePolicy {    [CmdletBinding()]
    param([AllowNull()]$Automation)

    $policy = [ordered]@{
        maxDirectPackages = 12
        allowPrerelease = $false
        deniedPackages = @()
        deniedLicenses = @()
    }
    if ($null -eq $Automation) { return $policy }
    if (@(Get-QaFoundryPropertyNames -InputObject $Automation) -notcontains "package_policy") { return $policy }
    $configured = $Automation.package_policy
    $configuredNames = @(Get-QaFoundryPropertyNames -InputObject $configured)
    if ($configuredNames -contains "max_direct_packages") { $policy.maxDirectPackages = [int]$configured.max_direct_packages }
    if ($configuredNames -contains "allow_prerelease") { $policy.allowPrerelease = [bool]$configured.allow_prerelease }
    if ($configuredNames -contains "denied_packages") { $policy.deniedPackages = @($configured.denied_packages | ForEach-Object { [string]$_ }) }
    if ($configuredNames -contains "denied_licenses") { $policy.deniedLicenses = @($configured.denied_licenses | ForEach-Object { [string]$_ }) }
    return $policy
}

# Version arithmetic the resolver does instead of the architect. A proposal may
# be a range; what ends up in a manifest and a lock file is one exact version,
# chosen the same way every time so two runs of one blueprint against one
# registry produce the same bytes.
function ConvertTo-QaFoundryVersionParts {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Version)

    $text = ([string]$Version).Trim().TrimStart("vV")
    # Build metadata never participates in ordering, so it is dropped before
    # anything compares two versions.
    $text = ($text -split "\+", 2)[0]
    $prerelease = ""
    $separator = $text.IndexOf("-")
    if ($separator -ge 0) {
        $prerelease = $text.Substring($separator + 1)
        $text = $text.Substring(0, $separator)
    }
    $numbers = @($text -split "\.")
    $parts = @(0, 0, 0)
    for ($index = 0; $index -lt 3; $index++) {
        if ($index -lt $numbers.Count -and $numbers[$index] -match "^\d+$") {
            $parts[$index] = [int]$numbers[$index]
        }
    }
    return [pscustomobject]@{
        major = $parts[0]
        minor = $parts[1]
        patch = $parts[2]
        prerelease = $prerelease
        isPrerelease = -not [string]::IsNullOrEmpty($prerelease)
        valid = ($numbers.Count -gt 0 -and $numbers[0] -match "^\d+$")
    }
}

function Compare-QaFoundryVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Left,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Right
    )

    $a = ConvertTo-QaFoundryVersionParts -Version $Left
    $b = ConvertTo-QaFoundryVersionParts -Version $Right
    foreach ($field in @("major", "minor", "patch")) {
        if ($a.$field -ne $b.$field) { return [Math]::Sign($a.$field - $b.$field) }
    }
    # A release outranks any pre-release of the same numbers, which is what makes
    # "the highest published version" mean a version somebody shipped.
    if ($a.isPrerelease -and -not $b.isPrerelease) { return -1 }
    if (-not $a.isPrerelease -and $b.isPrerelease) { return 1 }
    return [string]::CompareOrdinal($a.prerelease, $b.prerelease)
}

function New-QaFoundryRangeVerdict {
    [CmdletBinding()]
    param([Parameter(Mandatory)][bool]$Valid, [string]$Reason = "")
    return [pscustomobject]@{ valid = $Valid; reason = $Reason }
}

# Every ecosystem writes ranges in its own notation, and a range written in
# another one is not a near miss: it matches nothing. Build 972137 asked npm for
# '[1.49.0,2.0.0)' - NuGet's interval, which the architect had just used for the
# .NET half of the same design - and the resolver reported that nothing
# published satisfied it. Nothing was wrong with the feed, the package or the
# versions: 1.63.0 was there and '^1.49.0' would have chosen it. The run stopped
# two stages in with a message pointing at the registry.
#
# So the notation is read before the feed is asked, and a range this reader
# cannot honour is named as such, in the notation the ecosystem actually uses.
function Test-QaFoundryNodeStyleRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][string]$Ecosystem
    )

    $request = ([string]$Requested).Trim()
    if ($request -in @("", "*", "x", "X", "latest")) { return New-QaFoundryRangeVerdict -Valid $true }
    if ($request -match "[\[\]\(\)]") {
        return New-QaFoundryRangeVerdict -Valid $false -Reason (
            "'$Requested' is interval notation, which belongs to NuGet and Maven. $Ecosystem uses " +
            "semver comparators: write '^1.49.0' for the same intent, or '>=1.49.0' for a lower " +
            "bound alone.")
    }
    if ($request -match "~>") {
        return New-QaFoundryRangeVerdict -Valid $false -Reason (
            "'$Requested' uses RubyGems' pessimistic operator. $Ecosystem writes the same intent " +
            "as '~1.49.0' or '^1.49.0'.")
    }
    if ($request -match "\|\||,|\s") {
        return New-QaFoundryRangeVerdict -Valid $false -Reason (
            "'$Requested' joins several constraints, and this resolver pins from one comparator so " +
            "that two runs of the same design resolve to the same bytes. Write the single " +
            "constraint that matters, such as '^1.49.0'.")
    }
    if ($request -notmatch "^(\^|~|>=|>|<=|<|=)?(\d+|[xX*])(\.(\d+|[xX*])){0,2}([-+][0-9A-Za-z.\-]+)?$") {
        return New-QaFoundryRangeVerdict -Valid $false -Reason (
            "'$Requested' is not a version or a $Ecosystem range. Expected something like '1.49.0', " +
            "'^1.49.0', '~1.49', '>=1.49.0' or '1.x'.")
    }
    return New-QaFoundryRangeVerdict -Valid $true
}

function Test-QaFoundryIntervalRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][string]$Ecosystem,
        [string[]]$FloatingWords = @("", "*", "latest")
    )

    $request = ([string]$Requested).Trim()
    if ($request -in $FloatingWords) { return New-QaFoundryRangeVerdict -Valid $true }
    if ($request -match "^(\^|~)") {
        return New-QaFoundryRangeVerdict -Valid $false -Reason (
            "'$Requested' uses npm's caret or tilde. $Ecosystem takes a bare version, which means " +
            "'at least this', or an interval such as '[1.49.0,2.0.0)'.")
    }
    if ($request -match "^[\[\(]") {
        if ($request -notmatch "^[\[\(]\s*[^,\[\]\(\)]*\s*(,\s*[^,\[\]\(\)]*\s*)?[\]\)]$") {
            return New-QaFoundryRangeVerdict -Valid $false -Reason (
                "'$Requested' opens an interval it does not close correctly. Expected '[1.49.0]' " +
                "for exactly that version, or '[1.49.0,2.0.0)' for a half-open range.")
        }
        if ($request -match "^[\[\(]\s*,\s*[\]\)]$") {
            return New-QaFoundryRangeVerdict -Valid $false -Reason (
                "'$Requested' is an interval with no bound at either end, which no version can be " +
                "checked against. Name at least one bound.")
        }
        return New-QaFoundryRangeVerdict -Valid $true
    }
    if ($request -notmatch "^\d+(\.\d+)*([-+][0-9A-Za-z.\-]+)?$") {
        return New-QaFoundryRangeVerdict -Valid $false -Reason (
            "'$Requested' is not a version or a $Ecosystem range. Expected something like '1.49.0' " +
            "or '[1.49.0,2.0.0)'.")
    }
    return New-QaFoundryRangeVerdict -Valid $true
}

function Test-QaFoundryClauseRange {
    # PEP 440 and RubyGems both read a comma-separated conjunction; only the set
    # of operators differs.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][string]$Ecosystem,
        [Parameter(Mandatory)][string]$OperatorPattern,
        [Parameter(Mandatory)][string]$Example
    )

    $request = ([string]$Requested).Trim()
    if ($request -in @("", "*", "latest")) { return New-QaFoundryRangeVerdict -Valid $true }
    if ($request -match "[\[\]\(\)]") {
        return New-QaFoundryRangeVerdict -Valid $false -Reason (
            "'$Requested' is interval notation, which belongs to NuGet and Maven. $Ecosystem writes " +
            "the same intent as '$Example'.")
    }
    if ($request -match "\^") {
        return New-QaFoundryRangeVerdict -Valid $false -Reason (
            "'$Requested' uses npm's caret. $Ecosystem writes the same intent as '$Example'.")
    }
    foreach ($clause in @($request -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        if ($clause -notmatch "^($OperatorPattern)?\s*[0-9][0-9A-Za-z.\-+!*]*$") {
            return New-QaFoundryRangeVerdict -Valid $false -Reason (
                "'$clause' in '$Requested' is not a $Ecosystem constraint. Expected something like " +
                "'$Example'.")
        }
    }
    return New-QaFoundryRangeVerdict -Valid $true
}

function Test-QaFoundryVersionRange {
    # Asked before the feed is, so that a range written in the wrong notation is
    # reported as a range written in the wrong notation rather than as a package
    # nobody published.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Ecosystem,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Range
    )

    $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $Ecosystem
    if (@(Get-QaFoundryPropertyNames -InputObject $adapter) -notcontains "TestVersionRange") {
        return New-QaFoundryRangeVerdict -Valid $true
    }
    return (& $adapter.TestVersionRange $Range)
}

function Select-QaFoundryNodeStyleVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Published,
        [bool]$AllowPrerelease = $false
    )

    $candidates = @($Published | Where-Object {
        (ConvertTo-QaFoundryVersionParts -Version $_).valid -and
        ($AllowPrerelease -or -not (ConvertTo-QaFoundryVersionParts -Version $_).isPrerelease)
    })
    if ($candidates.Count -eq 0) { return "" }
    $request = ([string]$Requested).Trim()
    $unbounded = $request -in @("", "*", "x", "latest")
    if ($unbounded) {
        $highest = ''
        foreach ($candidate in $candidates) {
            if (-not $highest -or (Compare-QaFoundryVersion -Left $candidate -Right $highest) -ge 0) {
                $highest = [string]$candidate
            }
        }
        return $highest
    }

    $operator = ""
    if ($request -match "^(\^|~|>=|>|<=|<|=)\s*(.+)$") {
        $operator = $Matches[1]
        $request = $Matches[2].Trim()
    }
    $numeric = (($request -split "\+", 2)[0] -split "-", 2)[0]
    $wildcard = $numeric -match "(^|\.)(x|X|\*)($|\.)"
    $base = ConvertTo-QaFoundryVersionParts -Version ($numeric -replace "(x|X|\*)", "0")
    if (-not $base.valid) { return "" }
    $specified = @(@($numeric -split "\.") | Where-Object { $_ -match "^\d+$" }).Count

    $satisfies = {
        param([string]$Candidate)
        $parts = ConvertTo-QaFoundryVersionParts -Version $Candidate
        $baseText = if ($request -match '-[0-9A-Za-z]') { $request }
            else { "$($base.major).$($base.minor).$($base.patch)" }
        $order = Compare-QaFoundryVersion -Left $Candidate -Right $baseText
        switch ($operator) {
            ">=" { return $order -ge 0 }
            ">" { return $order -gt 0 }
            "<=" { return $order -le 0 }
            "<" { return $order -lt 0 }
            "^" {
                if ($order -lt 0) { return $false }
                if ($base.major -gt 0) { return $parts.major -eq $base.major }
                if ($base.minor -gt 0) { return $parts.major -eq 0 -and $parts.minor -eq $base.minor }
                return $parts.major -eq 0 -and $parts.minor -eq 0 -and $parts.patch -eq $base.patch
            }
            "~" {
                if ($order -lt 0) { return $false }
                return $parts.major -eq $base.major -and $parts.minor -eq $base.minor
            }
            default {
                if ($wildcard -or $specified -lt 3) {
                    if ($specified -ge 1 -and $parts.major -ne $base.major) { return $false }
                    if ($specified -ge 2 -and $parts.minor -ne $base.minor) { return $false }
                    return $true
                }
                return $order -eq 0
            }
        }
    }

    # Only the highest matching version is needed. Sorting the entire registry
    # with nested loops made packages with thousands of releases take minutes.
    # Equal versions retain the last occurrence, as the previous stable sort did.
    $highest = ''
    foreach ($candidate in $candidates) {
        if ((& $satisfies $candidate) -and
            (-not $highest -or (Compare-QaFoundryVersion -Left $candidate -Right $highest) -ge 0)) {
            $highest = [string]$candidate
        }
    }
    return $highest
}

# NuGet writes its ranges in interval notation and treats a bare version as a
# lower bound, so it needs its own reading of the same question.
function Select-QaFoundryNuGetVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Requested,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Published,
        [bool]$AllowPrerelease = $false
    )

    $request = ([string]$Requested).Trim()
    if ($request -match "^\[\s*([^,\]\[\)]+)\s*\]$") {
        # An exact interval. Nothing else will do, so an absent version is a
        # refusal rather than the nearest match.
        $exact = $Matches[1].Trim()
        $match = @($Published | Where-Object { $_ -ieq $exact })
        return $(if ($match.Count -gt 0) { [string]$match[0] } else { "" })
    }
    if ($request -match "^[\[\(]\s*([^,]*)\s*,\s*([^\]\)]*)\s*[\]\)]$") {
        $lower = $Matches[1].Trim()
        $upper = $Matches[2].Trim()
        $lowerInclusive = $request.StartsWith("[")
        $upperInclusive = $request.EndsWith("]")
        $candidates = @($Published | Where-Object {
            $parts = ConvertTo-QaFoundryVersionParts -Version $_
            if (-not $parts.valid) { return $false }
            if (-not $AllowPrerelease -and $parts.isPrerelease) { return $false }
            if ($lower) {
                $order = Compare-QaFoundryVersion -Left $_ -Right $lower
                if ($order -lt 0 -or (-not $lowerInclusive -and $order -eq 0)) { return $false }
            }
            if ($upper) {
                $order = Compare-QaFoundryVersion -Left $_ -Right $upper
                if ($order -gt 0 -or (-not $upperInclusive -and $order -eq 0)) { return $false }
            }
            return $true
        })
        if ($candidates.Count -eq 0) { return "" }
        return Get-QaFoundryHighestVersion -Versions $candidates
    }
    # A bare version in NuGet means "at least this", and restore then takes the
    # lowest version that satisfies it rather than the newest. Pinning the newest
    # here would put a version in the project file that restore would not have
    # chosen, and the lock would disagree with the manifest beside it. A floating
    # version is the Node reading of a wildcard, so that one is answered by the
    # same code rather than by a second copy of it that will drift.
    if ($request -match "^\d") {
        $candidates = @($Published | Where-Object {
            $parts = ConvertTo-QaFoundryVersionParts -Version $_
            $parts.valid -and ($AllowPrerelease -or -not $parts.isPrerelease) -and
                (Compare-QaFoundryVersion -Left $_ -Right $request) -ge 0
        })
        if ($candidates.Count -eq 0) { return "" }
        $lowest = ""
        foreach ($candidate in $candidates) {
            if ([string]::IsNullOrWhiteSpace($lowest) -or
                (Compare-QaFoundryVersion -Left $candidate -Right $lowest) -lt 0) {
                $lowest = [string]$candidate
            }
        }
        return $lowest
    }
    return Select-QaFoundryNodeStyleVersion -Requested $request -Published $Published `
        -AllowPrerelease $AllowPrerelease
}

function Get-QaFoundryHighestVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Versions)

    $highest = ""
    foreach ($version in @($Versions)) {
        if ([string]::IsNullOrWhiteSpace($highest) -or
            (Compare-QaFoundryVersion -Left $version -Right $highest) -gt 0) {
            $highest = [string]$version
        }
    }
    return $highest
}

# Whether a dependency asks for exactly one released version rather than a range
# a resolver would be free to satisfy differently tomorrow. Only the ecosystem
# knows its own spelling - a dot separates a RubyGems pre-release where a hyphen
# separates an npm one - so the rule is read from the adapter instead of being
# fixed here. An ecosystem that states no rule gets no exemption: nothing is
# accepted, because an unverifiable pin is the failure this guards against.
function Test-QaFoundryExactVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Ecosystem,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Version
    )

    $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $Ecosystem
    $names = @(Get-QaFoundryPropertyNames -InputObject $adapter)
    if ($names -notcontains "exactVersionPattern") { return $false }
    $pattern = [string]$adapter.exactVersionPattern
    if ([string]::IsNullOrWhiteSpace($pattern)) { return $false }
    return ([string]$Version).Trim() -match $pattern
}

# The one spelling of a package name that decides whether two mentions of it are
# the same package. Whether case matters is the registry's rule and differs by
# ecosystem: NuGet and Packagist fold it, PyPI folds it and collapses separators,
# and npm, RubyGems, Maven and Go keep the name as published. PowerShell's own
# -eq folds case for all of them, which would have let a locked "Newtonsoft.Json"
# be satisfied by whatever a feed serves for "newtonsoft.JSON" on RubyGems too.
# An ecosystem that states no rule is compared as written, because inventing a
# fold is how one package becomes another.
function Get-QaFoundryNormalisedPackageName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Ecosystem,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Name
    )

    $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $Ecosystem
    $names = @(Get-QaFoundryPropertyNames -InputObject $adapter)
    if ($names -notcontains "NormalizePackageName") { return ([string]$Name).Trim() }
    return [string](& $adapter.NormalizePackageName ([string]$Name))
}

# Whether two package names refer to one package in the given ecosystem. Callers
# read better for asking the question than for comparing two normalisations, and
# the comparison stays ordinal in one place rather than in each of them.
function Test-QaFoundrySamePackageName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Ecosystem,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Left,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Right
    )

    $left = Get-QaFoundryNormalisedPackageName -Ecosystem $Ecosystem -Name $Left
    $right = Get-QaFoundryNormalisedPackageName -Ecosystem $Ecosystem -Name $Right
    return ($left -ceq $right)
}

# Whether a value is actually a hash, in any of the spellings the ecosystems
# use: subresource integrity, an algorithm-prefixed hex digest, Go's dirhash, or
# a bare hex digest. It is decoded rather than pattern-matched, because
# "sha512-a" looks like an integrity value and carries a single byte - and a
# hash that cannot be read is not a hash, since there would be nothing to
# compare a download against.
function Test-QaFoundryPackageDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    $text = ([string]$Value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }

    $byAlgorithm = @{ "md5" = 16; "sha1" = 20; "sha256" = 32; "sha384" = 48; "sha512" = 64 }
    $decodeBase64 = {
        param([string]$Encoded, [int]$ExpectedBytes)
        try { $bytes = [Convert]::FromBase64String($Encoded) } catch { return $false }
        return ($bytes.Length -eq $ExpectedBytes)
    }

    # Go records a dirhash as "h1:" followed by a base64 SHA-256.
    if ($text -match "^h1:(.+)$") { return (& $decodeBase64 $Matches[1] 32) }

    # Three separators, because three ecosystems chose differently: npm writes
    # subresource integrity with a hyphen, pip writes "sha256:" with a colon,
    # and Bundler writes "sha256=" in a Gemfile.lock CHECKSUMS section. A reader
    # that knew only two of them would reject a real lock file as unhashed.
    #
    # Only a named algorithm makes this the prefixed spelling. Base64 pads with
    # "=", so a bare digest whose characters happen to all be alphanumeric ends
    # in a separator this pattern recognises - which is how NuGet's own
    # contentHash, a padded base64 SHA-512, was read as an algorithm called
    # "kQTWtbMbzGDwgyW3ZIrm..." and rejected. Roughly one NuGet hash in fifteen
    # avoids "+" and "/" entirely, so the failure landed on a different package
    # every run. An unrecognised name means this is not the prefixed form, and
    # the bare spellings below still get their turn.
    if ($text -match "^([A-Za-z0-9]+)[-:=](.+)$" -and
        $byAlgorithm.ContainsKey((([string]$Matches[1]).ToLowerInvariant()))) {
        $algorithm = ([string]$Matches[1]).ToLowerInvariant()
        $digest = [string]$Matches[2]
        $expected = [int]$byAlgorithm[$algorithm]
        if ($digest -match "^[0-9a-fA-F]+$" -and $digest.Length -eq ($expected * 2)) { return $true }
        return (& $decodeBase64 $digest $expected)
    }

    # A bare digest names no algorithm, so its length has to identify one.
    if ($text -match "^[0-9a-fA-F]+$") {
        return (@($byAlgorithm.Values | ForEach-Object { $_ * 2 }) -contains $text.Length)
    }
    # A bare base64 digest, which is how NuGet records a content hash.
    foreach ($length in @($byAlgorithm.Values)) {
        if (& $decodeBase64 $text $length) { return $true }
    }
    return $false
}

# One adapter per ecosystem, loaded from disk and cached for the process.
# Everything ecosystem-specific - the manifest name, where dependencies are
# declared, which resolver produces a lock, what installs and builds and runs the
# tests - lives behind this call, so a runtime that used to assume package.json
# now has to ask. An ecosystem with no adapter throws rather than falling back to
# a supported one: silently materialising npm for a .NET decision is how a
# design gets replaced by whatever the runtime happened to know.
$script:QaFoundryEcosystemAdapters = @{}
$script:QaFoundryEcosystemAdapterIds = @()
$script:QaFoundryEcosystemAdapterFaults = @{}

# The adapter files are dot-sourced here, into the scope that holds every other
# shared helper, and not on demand inside the accessor below. Dot-sourcing from
# within a function would put an adapter's private helpers - its version
# selector, its comparable-version conversion - into that function's scope,
# where they cease to exist the moment the function returns. The adapter's own
# script blocks resolve those helpers by name when they are eventually invoked,
# so the failure would not appear at load time: it would appear much later, as
# an ecosystem that could resolve no version at all.
foreach ($adapterFile in @(
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "ecosystems") -File -Filter "*.Ecosystem.ps1" -ErrorAction SilentlyContinue |
        Sort-Object -Property Name)) {
    $adapterId = ($adapterFile.Name -replace "\.Ecosystem\.ps1$", "").ToLowerInvariant()
    try {
        . $adapterFile.FullName
        $script:QaFoundryEcosystemAdapterIds += $adapterId
    }
    catch {
        # One unusable adapter must not take the whole runtime with it. The
        # failure is held here and reported if - and only if - something asks
        # for that ecosystem, so the reader is told which file is broken rather
        # than that their ecosystem is unsupported.
        $script:QaFoundryEcosystemAdapterFaults[$adapterId] = [string]$_.Exception.Message
    }
}

function Get-QaFoundryEcosystemAdapter {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Ecosystem)

    $id = ([string]$Ecosystem).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($id)) {
        throw "No package ecosystem was named, so nothing can be installed, built or run."
    }
    if ($script:QaFoundryEcosystemAdapters.ContainsKey($id)) {
        return $script:QaFoundryEcosystemAdapters[$id]
    }
    # Constrained to a single path segment, because the ecosystem name arrives
    # from a model-authored artifact and is reported back inside file paths.
    if ($id -notmatch "^[a-z0-9]+(-[a-z0-9]+)*$") {
        throw "'$Ecosystem' is not a package ecosystem name this runtime recognises."
    }
    $adapterPath = Join-Path (Join-Path $PSScriptRoot "ecosystems") "$id.Ecosystem.ps1"
    if ($script:QaFoundryEcosystemAdapterFaults.ContainsKey($id)) {
        throw ("The adapter at $adapterPath could not be loaded, so the '$id' package ecosystem " +
            "cannot install, build or run anything: " +
            "$($script:QaFoundryEcosystemAdapterFaults[$id])")
    }
    if (@($script:QaFoundryEcosystemAdapterIds) -cnotcontains $id) {
        throw ("This installation has no adapter for the '$id' package ecosystem, so it cannot " +
            "install, build or run anything designed on it. Supported ecosystems: " +
            "$((Get-QaFoundryEcosystemAdapterNames) -join ', ').")
    }
    $factory = "New-QaFoundry" + ($id.Substring(0, 1).ToUpperInvariant() + $id.Substring(1)) + "EcosystemAdapter"
    if ($null -eq (Get-Command -Name $factory -CommandType Function -ErrorAction SilentlyContinue)) {
        throw "The adapter at $adapterPath does not define $factory, so it cannot be used."
    }
    $adapter = & $factory
    # An adapter that answers to a different name would be selected for one
    # ecosystem and then install another one's packages.
    if ([string]$adapter.id -cne $id) {
        throw "The adapter at $adapterPath calls itself '$([string]$adapter.id)' rather than '$id'."
    }
    $script:QaFoundryEcosystemAdapters[$id] = $adapter
    return $adapter
}

# Only the adapters that actually loaded are named, because a caller reading this
# list is deciding what it can hand work to, and a file that failed to load
# cannot perform any.
function Get-QaFoundryEcosystemAdapterNames {
    [CmdletBinding()]
    param()

    return @($script:QaFoundryEcosystemAdapterIds | Sort-Object)
}

# A plan names the recipe it wants materialised rather than the ecosystem, because
# the recipe is what the resolver actually performs. Two ecosystems answering to
# one recipe would make that name ambiguous, so this refuses rather than picking
# the first it finds.
function Get-QaFoundryEcosystemAdapterByRecipe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Recipe)

    $wanted = ([string]$Recipe).Trim()
    if ([string]::IsNullOrWhiteSpace($wanted)) {
        throw "No materialisation recipe was named, so no resolver can be selected."
    }
    $matched = @()
    foreach ($id in @(Get-QaFoundryEcosystemAdapterNames)) {
        $candidate = Get-QaFoundryEcosystemAdapter -Ecosystem $id
        if ([string]$candidate.recipe -ceq $wanted) { $matched += $candidate }
    }
    if ($matched.Count -eq 0) {
        throw ("No adapter in this installation performs the '$wanted' recipe, so nothing here " +
            "can produce a lock file for it.")
    }
    if ($matched.Count -gt 1) {
        throw ("The recipe '$wanted' is claimed by " +
            "$(($matched | ForEach-Object { [string]$_.id }) -join ', '), so it does not identify " +
            "one resolver.")
    }
    return $matched[0]
}

# The names a recorded toolchain's runtime block carries. ReadRuntime is the one
# place that decides them, so they are asked of it rather than repeated: an
# adapter that renames a runtime key renames it here too, and a reader that
# expects the old name is told so instead of silently reading zero.
function Get-QaFoundryCanonicalRuntimeKeys {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Adapter)

    $canonical = & $Adapter.ReadRuntime @{}
    return @(Get-QaFoundryPropertyNames -InputObject $canonical)
}

# The names a resolver owns, across every ecosystem this installation ships. A
# lock file records the exact version, origin URL and content hash of every
# package in a tree, so it can only come from running the resolver; one written
# as literal content by an agent is an invented lock file. Derived from the
# adapters rather than listed, because a hand-kept list and a new adapter drift
# apart silently, and the two ways that drift shows are both bad: a batch is
# assigned work that the change contract will refuse, or a file meant to be
# authored is quietly withheld from every batch.
function Get-QaFoundryResolverOwnedLockFileNames {
    [CmdletBinding()]
    param()

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($id in @(Get-QaFoundryEcosystemAdapterNames)) {
        $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $id
        $name = [string]$adapter.lockFileName
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if (-not ($names | Where-Object { $_ -ceq $name })) { $names.Add($name) }
    }
    return @($names | Sort-Object -CaseSensitive)
}

# The same names as one expression, in the spelling both this runtime and the
# change contract use. The schema is ECMA-262 and cannot carry an inline
# case-insensitivity flag, so the pattern itself is case-sensitive and the
# runtime applies it case-insensitively: of the two, the runtime stays the
# stricter, which is the safe direction for a refusal.
function Get-QaFoundryResolverOwnedPathPattern {
    [CmdletBinding()]
    param()

    $alternatives = @(Get-QaFoundryResolverOwnedLockFileNames |
        ForEach-Object { [regex]::Escape($_) })
    if ($alternatives.Count -eq 0) {
        throw "No ecosystem adapter in this installation names a lock file, so no path can be recognised as one a resolver owns."
    }
    return "(^|[\\/])(" + ($alternatives -join "|") + ")$"
}

function Get-QaFoundryArtifactField {
    [CmdletBinding()]
    param([AllowNull()]$Artifact, [Parameter(Mandatory)][string]$Name)

    if ($null -eq $Artifact) { return $null }
    if ($Artifact -is [System.Collections.IDictionary]) {
        if ($Artifact.Contains($Name)) { return $Artifact[$Name] }
        return $null
    }
    if ($null -eq $Artifact.PSObject) { return $null }
    if ((Get-QaFoundryPropertyNames -InputObject $Artifact) -notcontains $Name) { return $null }
    return $Artifact.$Name
}

function Format-QaFoundryNarrationText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string]$Text,
        [int]$MaxLength = 160
    )

    $collapsed = (([string]$Text) -replace "\s+", " ").Trim()
    if ($collapsed.Length -le $MaxLength) { return $collapsed }
    $cut = $collapsed.Substring(0, $MaxLength)
    $lastSpace = $cut.LastIndexOf(" ")
    if ($lastSpace -gt [int]($MaxLength * 0.6)) { $cut = $cut.Substring(0, $lastSpace) }
    return ($cut.TrimEnd(" ", ",", ";", ":", ".", "-") + "...")
}

# Reads the shape every agent artifact shares - summary, findings, required
# changes, proposals - and turns it into a handful of short lines, so the log
# shows what an agent concluded rather than only that it answered.
function Get-QaFoundryArtifactNarration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Artifact,
        [int]$MaxItems = 2,
        [int]$MaxLength = 160
    )

    $lines = [System.Collections.Generic.List[psobject]]::new()
    if ($null -eq $Artifact) { return @() }

    $add = {
        param([string]$Level, [string]$Text)
        $clean = Format-QaFoundryNarrationText -Text $Text -MaxLength $MaxLength
        if ($clean) { $lines.Add([pscustomobject]@{ level = $Level; text = $clean }) }
    }

    $summary = Get-QaFoundryArtifactField -Artifact $Artifact -Name "summary"
    if ($summary -is [string] -and $summary) { & $add "info" "Thinks: $summary" }

    $status = [string](Get-QaFoundryArtifactField -Artifact $Artifact -Name "status")
    if ($status -and $status -ne "completed") {
        & $add "warn" "Status: $status."
    }

    $decision = [string](Get-QaFoundryArtifactField -Artifact $Artifact -Name "decision")
    if ($decision) {
        $confidence = Get-QaFoundryArtifactField -Artifact $Artifact -Name "confidence"
        $suffix = if ($null -ne $confidence) { " (confidence {0:0.00})" -f [double]$confidence } else { "" }
        $level = if ($decision -eq "approved") { "info" } else { "warn" }
        & $add $level "Verdict: $decision$suffix."
    }

    $outcome = Get-QaFoundryArtifactField -Artifact $Artifact -Name "outcome"
    if ($outcome -is [string] -and $outcome) { & $add "info" "Outcome: $outcome." }

    foreach ($field in @("reason", "recommendation", "recommendedAction")) {
        $value = Get-QaFoundryArtifactField -Artifact $Artifact -Name $field
        if ($value -is [string] -and $value) {
            $label = if ($field -eq "reason") { "Because" } else { "Recommends" }
            & $add "info" "${label}: $value"
        }
    }

    $severityRank = @{ critical = 0; error = 1; warning = 2; info = 3 }
    $findings = @(Get-QaFoundryArtifactField -Artifact $Artifact -Name "findings" | Where-Object { $_ })
    if ($findings.Count -gt 0) {
        $ranked = @($findings | Sort-Object -Property @{ Expression = {
            $severity = [string](Get-QaFoundryArtifactField -Artifact $_ -Name "severity")
            if ($severityRank.ContainsKey($severity)) { $severityRank[$severity] } else { 4 }
        } })
        foreach ($finding in @($ranked | Select-Object -First $MaxItems)) {
            $severity = [string](Get-QaFoundryArtifactField -Artifact $finding -Name "severity")
            $message = [string](Get-QaFoundryArtifactField -Artifact $finding -Name "message")
            if (-not $message) { continue }
            $level = switch ($severity) {
                "critical" { "error" }
                "error" { "error" }
                "warning" { "warn" }
                default { "info" }
            }
            $label = if ($severity) { "Finds ($severity)" } else { "Finds" }
            & $add $level "${label}: $message"
        }
        if ($findings.Count -gt $MaxItems) {
            & $add "info" "...and $($findings.Count - $MaxItems) further finding(s)."
        }
    }

    $required = @(Get-QaFoundryArtifactField -Artifact $Artifact -Name "requiredChanges" |
        Where-Object { $_ -is [string] -and $_ })
    foreach ($change in @($required | Select-Object -First $MaxItems)) {
        & $add "warn" "Asks for: $change"
    }
    if ($required.Count -gt $MaxItems) {
        & $add "info" "...and $($required.Count - $MaxItems) further requested change(s)."
    }

    $proposals = @(Get-QaFoundryArtifactField -Artifact $Artifact -Name "proposals" | Where-Object { $_ })
    foreach ($proposal in @($proposals | Select-Object -First $MaxItems)) {
        $title = [string](Get-QaFoundryArtifactField -Artifact $proposal -Name "title")
        if (-not $title) { $title = [string](Get-QaFoundryArtifactField -Artifact $proposal -Name "description") }
        if (-not $title) { continue }
        $priority = [string](Get-QaFoundryArtifactField -Artifact $proposal -Name "priority")
        $suffix = if ($priority) { " [$priority]" } else { "" }
        & $add "info" "Proposes: $title$suffix"
    }
    if ($proposals.Count -gt $MaxItems) {
        & $add "info" "...and $($proposals.Count - $MaxItems) further proposal(s)."
    }

    $changes = @(Get-QaFoundryArtifactField -Artifact $Artifact -Name "changes" | Where-Object { $_ })
    if ($changes.Count -gt 0) {
        & $add "info" "Plans $($changes.Count) file change(s)."
        foreach ($change in @($changes | Select-Object -First $MaxItems)) {
            $operation = [string](Get-QaFoundryArtifactField -Artifact $change -Name "operation")
            $path = [string](Get-QaFoundryArtifactField -Artifact $change -Name "path")
            if (-not $path) { continue }
            $prefix = if ($operation) { "$operation " } else { "" }
            & $add "info" "Change: $prefix$path"
        }
    }

    $warnings = @(Get-QaFoundryArtifactField -Artifact $Artifact -Name "warnings" |
        Where-Object { $_ -is [string] -and $_ })
    foreach ($warning in @($warnings | Select-Object -First $MaxItems)) {
        & $add "warn" "Warns: $warning"
    }

    $unknowns = @(Get-QaFoundryArtifactField -Artifact $Artifact -Name "unknowns" |
        Where-Object { $_ -is [string] -and $_ })
    if ($unknowns.Count -gt 0) {
        & $add "info" "Leaves $($unknowns.Count) open question(s), first: $($unknowns[0])"
    }

    return $lines.ToArray()
}

function Write-QaFoundryArtifactNarration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Artifact,
        [string]$Scope = "",
        [int]$Indent = 3,
        [int]$MaxItems = 2,
        [int]$MaxLength = 160
    )

    foreach ($line in @(Get-QaFoundryArtifactNarration -Artifact $Artifact -MaxItems $MaxItems -MaxLength $MaxLength)) {
        Write-QaFoundryLog -Level $line.level -Indent $Indent -Scope $Scope -Message $line.text -Audience business
    }
}

# A PowerShell object builds its member table lazily, and that construction is
# not thread safe. Handing one configuration object to several runspaces at once
# therefore fails intermittently with "The property 'Properties' cannot be
# found on this object", so every parallel agent receives a private copy.
function Copy-QaFoundryConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Config)

    return ($Config | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -Depth 100)
}

function Set-QaFoundryResolvedAiProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][object]$Profile
    )

    foreach ($property in @(
        $Profile.PSObject.Properties |
            Where-Object { $_.Name -notin @("name", "required_secret_env", "secret_env") } |
            ForEach-Object { $_.Name }
    )) {
        $Config.ai | Add-Member `
            -NotePropertyName $property `
            -NotePropertyValue $Profile.$property `
            -Force
    }
    $Config.ai | Add-Member `
        -NotePropertyName resolved_profile `
        -NotePropertyValue ([string]$Profile.name) `
        -Force
    $Config.ai | Add-Member `
        -NotePropertyName resolved_secret_env `
        -NotePropertyValue @($Profile.secret_env) `
        -Force
    $Config.ai | Add-Member `
        -NotePropertyName resolved_required_secret_env `
        -NotePropertyValue @($Profile.required_secret_env) `
        -Force
    return $Config
}

function Get-QaFoundryCollaborationProfileNames {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Config)

    if ($Config.ai.PSObject.Properties.Name -notcontains "collaboration" -or
        -not [bool]$Config.ai.collaboration.enabled) {
        return @()
    }
    $names = @($Config.ai.collaboration.profiles | ForEach-Object {
        ([string]$_).Trim()
    })
    if ($names.Count -lt 2) {
        throw "AI collaboration requires at least two configured profiles."
    }
    if (@($names | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or
        @($names | Select-Object -Unique).Count -ne $names.Count) {
        throw "AI collaboration profiles must be non-empty and unique."
    }
    foreach ($name in $names) {
        if ($null -eq $Config.ai.profiles.PSObject.Properties[$name]) {
            throw "AI collaboration profile does not exist: $name"
        }
    }
    $models = @($names | ForEach-Object {
        [string]$Config.ai.profiles.PSObject.Properties[[string]$_].Value.model
    })
    if (@($models | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0 -or
        @($models | Select-Object -Unique).Count -lt 2) {
        throw "AI collaboration must contain at least two distinct configured models."
    }
    $assignment = [string]$Config.ai.collaboration.assignment
    if ($assignment -ne "deterministic_round_robin") {
        throw "Unsupported AI collaboration assignment: $assignment"
    }
    return @($names)
}

function Select-QaFoundryAgentProfileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Config,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$StageId,
        [int]$StageIteration = 1,
        [int]$AgentOrdinal = 0
    )

    $profiles = @(Get-QaFoundryCollaborationProfileNames -Config $Config)
    if ($profiles.Count -eq 0) {
        if ($Config.ai.PSObject.Properties.Name -contains "resolved_profile") {
            return [string]$Config.ai.resolved_profile
        }
        return [string]$Config.ai.active_profile
    }
    if ($AgentOrdinal -lt 0) {
        throw "AgentOrdinal may not be negative."
    }
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $seed = "$RunId|$StageId|$StageIteration"
        $digest = $algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($seed))
        $hex = [BitConverter]::ToString($digest).Replace("-", "")
        $offset = [int]([Convert]::ToUInt32($hex.Substring(0, 8), 16) % $profiles.Count)
    }
    finally {
        $algorithm.Dispose()
    }
    return [string]$profiles[($offset + $AgentOrdinal) % $profiles.Count]
}

# A hosted CI job is killed without warning when it reaches its time limit, and
# whatever the current agent was writing is lost with it. A run therefore
# carries a deadline of its own, stops on an agent boundary while it still has
# time to save its state, and lets the next leg of the relay continue.
$script:QaFoundryBudgetMarker = "QAFOUNDRY_BUDGET_EXHAUSTED"

function Test-QaFoundryBudgetExhausted {
    [CmdletBinding()]
    param([AllowNull()][object]$Deadline)

    if ($null -eq $Deadline) { return $false }
    return ([DateTime]::UtcNow -ge ([DateTime]$Deadline).ToUniversalTime())
}

function Stop-QaFoundryForBudget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Reason)

    throw "${script:QaFoundryBudgetMarker}: $Reason"
}

# A budget stop raised inside a parallel runspace reaches the workflow wrapped in
# the MethodInvocationException that EndInvoke throws, so the marker is no longer
# at the start of the message the caller sees. Build 459 lost seven unused legs
# that way: the handover signal read as an ordinary crash. The marker is
# therefore looked for along the whole inner-exception chain rather than on the
# outermost message alone.
function Get-QaFoundryExceptionMessageChain {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][object]$Source)

    if ($null -eq $Source) { return @() }
    $messages = @()
    $current = $Source
    if ($current -is [System.Management.Automation.ErrorRecord]) {
        $messages += [string]$current.Exception.Message
        $current = $current.Exception
    }
    while ($current -is [Exception]) {
        $messages += [string]$current.Message
        $current = $current.InnerException
    }
    if ($messages.Count -eq 0) { $messages += [string]$Source }
    return @($messages)
}

function Get-QaFoundryBudgetStopMessage {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][object]$Message)

    foreach ($text in (Get-QaFoundryExceptionMessageChain -Source $Message)) {
        if ($text.StartsWith($script:QaFoundryBudgetMarker)) { return $text }
    }
    return ""
}

function Test-QaFoundryBudgetStop {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][object]$Message)

    return ((Get-QaFoundryBudgetStopMessage -Message $Message) -ne "")
}

# The run's bill, unlike the leg's clock, is spent for good. It travels by the
# same route - thrown from wherever the next call was about to be made, read off
# the message chain by the workflow - but carries its own marker, because the
# two ask for opposite things: a paused run is meant to be resumed, and a run
# that has spent its budget must not be.
$script:QaFoundryRunBudgetMarker = "QAFOUNDRY_RUN_BUDGET_EXHAUSTED"

function Stop-QaFoundryForRunBudget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Reason)

    throw "${script:QaFoundryRunBudgetMarker}: $Reason"
}

function Get-QaFoundryRunBudgetStopMessage {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][object]$Message)

    foreach ($text in (Get-QaFoundryExceptionMessageChain -Source $Message)) {
        if ($text.StartsWith($script:QaFoundryRunBudgetMarker)) { return $text }
    }
    return ""
}

function Test-QaFoundryRunBudgetStop {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][object]$Message)

    return ((Get-QaFoundryRunBudgetStopMessage -Message $Message) -ne "")
}

# A run recorded before states said why they stopped leaves only its own shape
# to read. Build 972449 is the case this exists for: twenty-five million tokens
# of finished work behind a 'blocked' that names no cause, in an artifact that
# cannot be re-created.
#
# The shape is not guesswork, because the workflow appends an attempt to a stage
# the moment that stage returns a result, and every block that follows from a
# judgement - a critic that refused, coverage a stage could not finish, an
# iteration limit reached - happens after that point. A stage blocked with no
# attempt at all therefore never ran and nothing about it was judged, which no
# judgement block can be true of. 'Every judgement records its attempt' is held
# in place by a test rather than by this comment.
#
# The reading is deliberately narrow. It refuses when anything else in the run
# is unresolved, so a reviewer's refusal elsewhere can never be walked past, and
# it refuses for a run that never called a model, which cannot have been stopped
# by spending. What it cannot establish is the ceiling that was in force, so it
# confirms the kind of stop and leaves the arithmetic to the caller, which tests
# the run against the ceiling in force now.
function Get-QaFoundryConfirmedBudgetBlock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$State,
        [Parameter(Mandatory)][AllowEmptyString()][string]$RunRoot
    )

    $refuse = {
        param([string]$Because)
        [ordered]@{ confirmed = $false; reason = $Because }
    }
    # The state file is written by another process, and an older or half-written
    # one has to produce a refusal rather than an exception. Build 973302's leg
    # reported "crashed: the property 'stages' cannot be found" for a run whose
    # state said plainly that it had blocked - the reader of the blocker threw
    # before the blocker could be carried forward.
    $field = {
        param([object]$Object, [string]$Name)
        if ($null -eq $Object) { return $null }
        if (@(Get-QaFoundryPropertyNames -InputObject $Object) -notcontains $Name) { return $null }
        return $Object.$Name
    }

    if ([string](& $field $State "status") -ne "blocked") {
        return (& $refuse "the run is not blocked")
    }
    if (-not [string]::IsNullOrWhiteSpace([string](& $field $State "blockedReason"))) {
        return (& $refuse "the run already states why it stopped, so nothing has to be inferred")
    }

    $stages = @(& $field $State "stages")
    if ($stages.Count -eq 0) {
        return (& $refuse "the run records no stages")
    }
    # A reviewer that asked for changes is unresolved work whoever the run is
    # handed to has to see. Continuing past it would be exactly the thing a
    # block exists to prevent.
    $unresolved = @($stages | Where-Object { [string](& $field $_ "status") -eq "revision_required" })
    if ($unresolved.Count -gt 0) {
        return (& $refuse (
            "stage '$([string](& $field $unresolved[0] "id"))' is still waiting on a revision a reviewer asked for"))
    }

    $blocked = @($stages | Where-Object { [string](& $field $_ "status") -eq "blocked" })
    if ($blocked.Count -ne 1) {
        return (& $refuse "$($blocked.Count) stage(s) are blocked, so no single cause can be read")
    }
    $stopped = $blocked[0]
    $stoppedId = [string](& $field $stopped "id")
    if ($stoppedId -ne [string](& $field $State "currentStage")) {
        return (& $refuse (
            "the blocked stage '$stoppedId' is not the stage the run stopped at"))
    }
    $attempts = @(& $field $stopped "attempts")
    if ($attempts.Count -gt 0) {
        return (& $refuse (
            "stage '$stoppedId' recorded $($attempts.Count) attempt(s), " +
            "so its result was judged rather than never produced"))
    }

    $spent = Get-QaFoundryRunTokensSpent -RunRoot $RunRoot
    if ([int]$spent.calls -le 0) {
        return (& $refuse "the run recorded no model calls, so spending cannot have stopped it")
    }

    return [ordered]@{
        confirmed = $true
        reason = (
            "stage '$stoppedId' is blocked without having produced or been judged on " +
            "anything, nothing else in the run is unresolved, and the run had spent " +
            "$($spent.tokens) token(s) across $($spent.calls) call(s)")
    }
}

function Get-QaFoundryBudgetSecondsRemaining {
    [CmdletBinding()]
    param([AllowNull()][object]$Deadline)

    if ($null -eq $Deadline) { return [int]::MaxValue }
    $remaining = ([DateTime]$Deadline).ToUniversalTime() - [DateTime]::UtcNow
    if ($remaining.TotalSeconds -le 0) { return 0 }
    if ($remaining.TotalSeconds -ge [int]::MaxValue) { return [int]::MaxValue }
    return [int][Math]::Floor($remaining.TotalSeconds)
}

# A model that does not answer within its timeout has produced nothing, which is
# the same position a rejected artifact leaves the run in. Build 453 lost three
# completed legs because that case threw instead, so it carries a marker and is
# retried with a smaller budget like any other rejected attempt.
$script:QaFoundryProviderTimeoutMarker = "QAFOUNDRY_PROVIDER_TIMEOUT"

# Saving state, writing the stage result and publishing the evidence artifact all
# happen after an agent returns, so a leg keeps this much of its budget back
# rather than spending the last second of it on a model call.
$script:QaFoundryHandoverReserveSeconds = 120

function Get-QaFoundryMinimumAttemptSeconds {
    param(
        [int]$ConfiguredTimeout, [string]$Directory, [string]$RunId,
        [string]$StageId, [string]$Provider, [string]$Model, [long]$RequestBytes
    )
    $fallback = [int][Math]::Max(300, [Math]::Floor($ConfiguredTimeout / 2))
    $durations = @{}
    $historyRoot = $Directory
    $ancestor = Get-Item -LiteralPath $Directory -ErrorAction SilentlyContinue
    while ($null -ne $ancestor) {
        if ((Test-Path -LiteralPath (Join-Path $ancestor.FullName 'workflow-state.json') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $ancestor.FullName 'context') -PathType Container)) {
            $historyRoot = $ancestor.FullName
            break
        }
        $ancestor = $ancestor.Parent
    }
    # Only comparable, accepted answers from this stage and model can justify
    # using a short remainder. Unknown work keeps the conservative old threshold.
    foreach ($file in @(Get-ChildItem -LiteralPath $historyRoot -Filter '*.provider-metadata.json' -File -Recurse -ErrorAction SilentlyContinue)) {
        try {
            $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 30
            if ($record.runId -cne $RunId -or $record.stageId -cne $StageId -or
                $record.provider -cne $Provider -or $record.model -cne $Model -or
                $record.purpose -ne 'artifact') { continue }
            if ($record.status -ne 'answered') { return $fallback }
            $artifactPath = $file.FullName -replace '\.attempt-\d+\.provider-metadata\.json$', ''
            if ($artifactPath -eq $file.FullName -or -not (Test-Path -LiteralPath "$artifactPath.coverage.json") -or
                -not (Test-Path -LiteralPath $artifactPath)) { continue }
            $artifact = Get-Content -LiteralPath $artifactPath -Raw | ConvertFrom-Json -Depth 100
            if ($artifact.status -ne 'completed') { continue }
            $coverage = Get-Content -LiteralPath "$artifactPath.coverage.json" -Raw | ConvertFrom-Json -Depth 30
            if ($coverage.status -ne 'covered' -or @($coverage.deferrals).Count -gt 0 -or
                $RequestBytes -gt ([long]$record.request.bytes * 1.25) -or [double]$record.durationMs -le 0) { continue }
            # Retries of one artifact are one observation, using its slowest call.
            $durations[$artifactPath] = [Math]::Max([double]$durations[$artifactPath], [double]$record.durationMs / 1000)
        }
        catch { continue } # A parallel writer may not have closed its metadata yet.
    }
    if ($durations.Count -lt 2) { return $fallback }
    $observed = ($durations.Values | Measure-Object -Maximum).Maximum
    return [int][Math]::Min($fallback, [Math]::Max(300, [Math]::Ceiling($observed * 1.5 + 60)))
}

function Test-QaFoundryProviderTimeout {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Message)

    return (([string]$Message).Contains($script:QaFoundryProviderTimeoutMarker))
}

# A model endpoint that refuses one call and serves the next is not a broken
# configuration, it is weather. Build 474 lost a two-hour relay on the last
# stage of eleven because a single request came back 400 while the same profile
# answered eight other calls in the same run. Only a timeout used to be worth a
# second attempt; these are worth one too, because the alternative is discarding
# completed work over a fault that has already cleared.
#
# Most 4xx answers are a verdict rather than weather: 401, 403, 404, 413 and 422
# will say exactly the same thing however many times they are asked. So the
# client errors listed here are only the ones that invite another attempt, plus
# the precise signature of the fault seen in build 474.
$script:QaFoundryTransientProviderPatterns = @(
    'Execution failed: (408|425|429) ',
    'Execution failed: 5\d\d ',
    'HTTP (408|425|429|5\d\d)\b',
    'status code (408|425|429|5\d\d)\b',
    'The resource you requested was not found',
    'socket hang up',
    'ECONNRESET',
    'ETIMEDOUT',
    'EAI_AGAIN',
    'fetch failed',
    'network error',
    'rate limit',
    'temporarily unavailable',
    'service unavailable',
    'internal server error'
)

function Test-QaFoundryProviderTransientFailure {
    [CmdletBinding()]
    param([AllowEmptyString()][AllowNull()][string]$Message)

    $text = [string]$Message
    if ([string]::IsNullOrWhiteSpace($text)) { return $false }
    foreach ($pattern in $script:QaFoundryTransientProviderPatterns) {
        if ($text -match $pattern) { return $true }
    }
    return $false
}

function Format-QaFoundryRemainingBudget {
    [CmdletBinding()]
    param([AllowNull()][object]$Deadline)

    if ($null -eq $Deadline) { return "no deadline" }
    $remaining = ([DateTime]$Deadline).ToUniversalTime() - [DateTime]::UtcNow
    if ($remaining.TotalSeconds -le 0) { return "no time left" }
    return (Format-QaFoundryDuration -Duration $remaining) + " left"
}

function New-QaFoundryRevisionLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$StageId,
        [Parameter(Mandatory)][int]$Revision,
        [AllowEmptyCollection()][object[]]$History = @()
    )

    $previous = @($History | Where-Object { [int]$_.revision -lt $Revision })
    $lastRevision = if ($previous.Count -gt 0) {
        ($previous | Measure-Object -Property revision -Maximum).Maximum
    }
    else { 0 }

    # A critic is settled while its most recent verdict is an approval. Reading any past
    # approval as permanent told the producer a critic was satisfied after that critic had
    # already reopened the work, so the standing here is the one the critic holds now.
    $settled = @()
    foreach ($criticId in @($previous | ForEach-Object { [string]$_.criticId } |
        Sort-Object -Unique)) {
        $ordered = @($previous |
            Where-Object { [string]$_.criticId -eq $criticId } |
            Sort-Object -Property revision)
        $approvedSince = $null
        for ($i = $ordered.Count - 1; $i -ge 0; $i--) {
            if ([string]$ordered[$i].decision -ne "approved") { break }
            $approvedSince = [int]$ordered[$i].revision
        }
        if ($null -eq $approvedSince) { continue }
        $settled += [ordered]@{
            criticId = $criticId
            approvedAtRevision = $approvedSince
        }
    }

    # The loop moves on after a rejection, not after anyone confirms the last round was
    # answered, so reaching a later round proves nothing about the changes it demanded.
    # A demand is honoured once the critic that raised it approves a later revision; until
    # then calling it settled hands the producer a commitment it may never have met.
    $commitments = @()
    foreach ($entry in @($previous | Where-Object { [int]$_.revision -lt $lastRevision })) {
        $criticId = [string]$entry.criticId
        $entryRevision = [int]$entry.revision
        $confirmed = @($previous | Where-Object {
            [string]$_.criticId -eq $criticId -and
            [int]$_.revision -gt $entryRevision -and
            [string]$_.decision -eq "approved"
        })
        if ($confirmed.Count -eq 0) { continue }
        foreach ($change in @($entry.requiredChanges)) {
            if ([string]::IsNullOrWhiteSpace([string]$change)) { continue }
            $commitments += [ordered]@{
                criticId = $criticId
                revision = $entryRevision
                change = [string]$change
            }
        }
    }

    $outstandingFindings = @()
    $outstandingChanges = @()
    foreach ($entry in @($previous | Where-Object {
        [int]$_.revision -eq $lastRevision -and [string]$_.decision -ne "approved"
    })) {
        foreach ($finding in @($entry.findings)) {
            $record = [ordered]@{
                criticId = [string]$entry.criticId
                severity = [string]$finding.severity
                message = [string]$finding.message
                evidence = [string]$finding.evidence
            }
            # Workflows whose critics do not classify findings leave this absent, so it is
            # copied only when the critic supplied it. Writing an empty string instead would
            # tell the producer a scope was decided when none was.
            if ((Get-QaFoundryPropertyNames -InputObject $finding) -contains "resolutionScope" -and
                -not [string]::IsNullOrWhiteSpace([string]$finding.resolutionScope)) {
                $record.resolutionScope = [string]$finding.resolutionScope
            }
            $outstandingFindings += $record
        }
        foreach ($change in @($entry.requiredChanges)) {
            if ([string]::IsNullOrWhiteSpace([string]$change)) { continue }
            $outstandingChanges += [ordered]@{
                criticId = [string]$entry.criticId
                change = [string]$change
            }
        }
    }

    return [ordered]@{
        runId = $RunId
        stageId = $StageId
        revision = $Revision
        # A producer may revise an incomplete draft before any critic can review it.
        # The base is the preceding producer revision; findings still come from
        # the last actual review, if one exists.
        previousRevision = $Revision - 1
        settledCritics = @($settled)
        honouredCommitments = @($commitments)
        outstandingFindings = @($outstandingFindings)
        outstandingChanges = @($outstandingChanges)
    }
}

# A run may now deliver work its reviewers never unanimously approved, because
# destroying three completed legs over an unresolved finding is worse than
# handing a human the finding. That only holds if the human is told, so the
# dissent is read back out of the run and written into the pull request.
function Get-QaFoundryDeliveryDissent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RunRoot)

    $statePath = Join-Path $RunRoot "workflow-state.json"
    if (-not [IO.File]::Exists($statePath)) { return @() }
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -Depth 100
    }
    catch { return @() }

    $dissentingStages = @(@($state.stages) |
        Where-Object { $_ -and [string]$_.status -eq "approved_with_dissent" } |
        ForEach-Object { [string]$_.id } |
        Select-Object -Unique)
    if ($dissentingStages.Count -eq 0) { return @() }

    $latestByAgent = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $RunRoot -Filter "*.json" -Recurse -File |
            Sort-Object LastWriteTimeUtc)) {
        try {
            $artifact = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 100
        }
        catch { continue }
        if ($null -eq $artifact) { continue }
        $names = Get-QaFoundryPropertyNames -InputObject $artifact
        if ($names -notcontains "decision" -or $names -notcontains "agentId") { continue }
        if ($names -notcontains "stageId") { continue }
        if ([string]$artifact.stageId -notin $dissentingStages) { continue }
        if ([string]$artifact.decision -eq "approved") { continue }
        $latestByAgent[[string]$artifact.agentId] = $artifact
    }

    $lines = @()
    foreach ($agentId in $latestByAgent.Keys) {
        $artifact = $latestByAgent[$agentId]
        $lines += "- **$agentId** returned ``$([string]$artifact.decision)``."
        foreach ($finding in @($artifact.findings)) {
            if ($null -eq $finding) { continue }
            if ([string]$finding.severity -notin @("error", "critical")) { continue }
            $lines += "  - [$([string]$finding.severity)] $([string]$finding.message)"
        }
        foreach ($change in @($artifact.requiredChanges)) {
            if ([string]::IsNullOrWhiteSpace([string]$change)) { continue }
            $lines += "  - asked for: $([string]$change)"
        }
    }
    return @($lines)
}

# The reason a stack was chosen is the one thing a reviewer of the bootstrap pull
# request cannot reconstruct from the diff: the diff shows a .NET project, not
# why it is not a TypeScript one. The blueprint holds that reasoning and the run
# directory is deleted, so it is rendered here and travels into the pull request
# description with the change it explains.
function Get-QaFoundryToolchainNarrative {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [string]$BlueprintName = "automation-blueprint.json"
    )

    $blueprint = $null
    foreach ($file in @(Get-ChildItem -LiteralPath $RunRoot -Filter $BlueprintName -Recurse -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc)) {
        try { $candidate = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 100 }
        catch { continue }
        if ($null -eq $candidate) { continue }
        # Only an approved blueprint explains anything: a rejected revision left
        # on disk would put a rationale nobody accepted in front of a reviewer.
        if ([string]$candidate.status -ne "completed") { continue }
        $blueprint = $candidate
    }
    if ($null -eq $blueprint) { return @() }
    if ((Get-QaFoundryPropertyNames -InputObject $blueprint) -notcontains "details") { return @() }
    $details = $blueprint.details
    if ($null -eq $details -or
        (Get-QaFoundryPropertyNames -InputObject $details) -notcontains "automationProjects") {
        return @()
    }

    $lines = @()
    foreach ($project in @($details.automationProjects)) {
        if ($null -eq $project) { continue }
        $names = Get-QaFoundryPropertyNames -InputObject $project
        if ($names -notcontains "toolchain" -or $null -eq $project.toolchain) { continue }
        $toolchain = $project.toolchain
        $fields = Get-QaFoundryPropertyNames -InputObject $toolchain
        $read = {
            param($name)
            if ($fields -contains $name) { return [string]$toolchain.$name }
            return ""
        }

        $lines += "### $([string]$project.name)"
        $runtimeText = ""
        if ($fields -contains "runtime" -and $null -ne $toolchain.runtime) {
            $runtimeNames = Get-QaFoundryPropertyNames -InputObject $toolchain.runtime
            if ($runtimeNames -contains "name" -and $runtimeNames -contains "version") {
                $runtimeText = "$([string]$toolchain.runtime.name) $([string]$toolchain.runtime.version)"
            }
        }
        $chosenText = @((& $read "language"), $runtimeText, (& $read "testFramework")) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        if (@($chosenText).Count -gt 0) {
            $lines += "- Chosen: $((@($chosenText)) -join ", ") on ``$(& $read 'ecosystem')``."
        }

        if ($fields -contains "detectedStack" -and $null -ne $toolchain.detectedStack) {
            $stack = $toolchain.detectedStack
            $stackNames = Get-QaFoundryPropertyNames -InputObject $stack
            $detected = @()
            foreach ($key in @("language", "runtime", "buildSystem")) {
                if ($stackNames -contains $key -and -not [string]::IsNullOrWhiteSpace([string]$stack.$key)) {
                    $detected += [string]$stack.$key
                }
            }
            if ($detected.Count -gt 0) {
                $line = "- Detected development stack: $($detected -join ", ")"
                if ($stackNames -contains "evidence") {
                    $evidence = @(@($stack.evidence) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
                    if ($evidence.Count -gt 0) {
                        $line += " (from " + ((@($evidence | Select-Object -First 5) |
                            ForEach-Object { "``$([string]$_)``" }) -join ", ") + ")"
                    }
                }
                $lines += "$line."
            }
        }

        if ($fields -contains "deviatesFromDetectedStack" -and [bool]$toolchain.deviatesFromDetectedStack) {
            $lines += "- **Deviates from the product's stack.** $(& $read 'deviationReason')"
        }

        foreach ($rejected in @($toolchain.alternativesRejected)) {
            if ($null -eq $rejected) { continue }
            $lines += "- Rejected $([string]$rejected.option): $([string]$rejected.reason)"
        }
        foreach ($requirement in @($toolchain.ciRequirements)) {
            if ([string]::IsNullOrWhiteSpace([string]$requirement)) { continue }
            $lines += "- CI requirement: $([string]$requirement)"
        }
        $lines += ""
    }
    if ($lines.Count -eq 0) { return @() }
    return @("## Why this technology") + @($lines)
}

# The decision a merged bootstrap left behind in the repository it automates.
# Everything about the choice lives in a run directory that is deleted, so
# without this a second run has no way to know the question was already answered
# and answers it again - which is how a repository ends up with two frameworks in
# two languages, neither of them chosen twice on purpose.
function Get-QaFoundryToolchainRecordPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][AllowNull()]$Config
    )

    $relative = Get-QaFoundryToolchainRecordRelativePath -Config $Config
    if ([string]::IsNullOrWhiteSpace($relative)) { return "" }
    return (Join-Path $RepositoryRoot ($relative -replace "/", [IO.Path]::DirectorySeparatorChar))
}

# The same path as the repository sees it. A change set names files the way the
# repository does, so the record cannot be described by an absolute path on
# whichever agent happened to resolve it.
function Get-QaFoundryToolchainRecordRelativePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Config)

    if ($null -eq $Config) { return "" }
    $names = @(Get-QaFoundryPropertyNames -InputObject $Config)
    if ($names -notcontains "automation" -or $null -eq $Config.automation) { return "" }
    if ((Get-QaFoundryPropertyNames -InputObject $Config.automation) -notcontains "toolchain_record") {
        return ""
    }
    $fileName = ([string]$Config.automation.toolchain_record).Trim()
    if ([string]::IsNullOrWhiteSpace($fileName)) { return "" }
    $automationRoot = Get-QaFoundryAutomationRoot -Config $Config
    return (($automationRoot.Replace("\", "/").Trim("/")) + "/" + $fileName.Replace("\", "/").TrimStart("/"))
}

# Where this repository keeps its automation, as the repository spells it. Read
# in one place because two readings that drift apart would disagree about which
# files a rule applies to, and a rule that is not applied is not a rule.
function Test-QaFoundryDeferredVerification {
    param([AllowNull()][object]$Config)
    return ($null -ne $Config -and $null -ne $Config.PSObject.Properties['automation'] -and
        $null -ne $Config.automation.PSObject.Properties['verification'] -and
        $null -ne $Config.automation.verification.PSObject.Properties['mode'] -and
        $Config.automation.verification.mode -eq 'deferred')
}

function Get-QaFoundryAutomationRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Config)

    $automationRoot = "automation"
    if ($null -eq $Config) { return $automationRoot }
    $names = @(Get-QaFoundryPropertyNames -InputObject $Config)
    if ($names -contains "project" -and $null -ne $Config.project -and
        (Get-QaFoundryPropertyNames -InputObject $Config.project) -contains "automation_root") {
        $configured = ([string]$Config.project.automation_root).Trim()
        if (-not [string]::IsNullOrWhiteSpace($configured)) { $automationRoot = $configured }
    }
    return ($automationRoot.Replace("\", "/").Trim("/"))
}

function Get-QaFoundryRecordedToolchain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][AllowNull()]$Config
    )

    $path = Get-QaFoundryToolchainRecordPath -RepositoryRoot $RepositoryRoot -Config $Config
    if ([string]::IsNullOrWhiteSpace($path)) { return $null }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    # A record nobody can parse is worse than none: it would be read as "no
    # decision yet" and the run would quietly choose a second time. It stops the
    # caller instead.
    try {
        $record = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
    }
    catch {
        throw ("The recorded automation toolchain at $path could not be read as JSON, so this run " +
            "cannot tell whether the technology question was already answered: $($_.Exception.Message)")
    }
    if ($null -eq $record -or
        (Get-QaFoundryPropertyNames -InputObject $record) -notcontains "toolchains" -or
        @($record.toolchains).Count -eq 0) {
        throw "The recorded automation toolchain at $path names no toolchain, so it records nothing."
    }
    return $record
}

# Whether a proposed set of per-project toolchains keeps faith with the one this
# repository already recorded. Asked in two places - of the architect's blueprint
# while a retry is still cheap, and of the resolved lock just before the change
# set is built - so it is answered once here rather than twice in two dialects
# that could disagree.
#
# The record names which toolchain was settled for which project. Comparing only
# the set of ecosystems throws that away: a repository with a .NET API suite and
# a TypeScript UI suite would accept either stack for either project, so the API
# suite could be rewritten in the UI's stack and still read as reuse. A project
# the record names is held to the entry that names it; a project it does not name
# is new, and a new project still has to be built on a toolchain this repository
# already maintains.
function Get-QaFoundryToolchainRecordConflicts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Recorded,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Proposed
    )

    $findings = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Recorded) { return @($findings) }

    $normalisePath = {
        param([AllowEmptyString()][string]$Value)
        return ((([string]$Value).Replace("\", "/") -replace "^\./", "").Trim("/"))
    }
    # Free text is compared with its shape removed, because "MSTest" and
    # "mstest " are the same answer written twice and refusing the second would
    # be pedantry rather than protection.
    $normaliseChoice = {
        param([AllowEmptyString()][string]$Value)
        return ((([string]$Value) -replace "\s+", " ").Trim().ToLowerInvariant())
    }

    $recordedByProject = @{}
    foreach ($entry in @($Recorded.toolchains)) {
        foreach ($recordedProject in @($entry.projects)) {
            $key = & $normalisePath ([string]$recordedProject)
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if (-not $recordedByProject.ContainsKey($key)) { $recordedByProject[$key] = $entry }
        }
    }
    $recordedEcosystems = @(@($Recorded.toolchains) |
        ForEach-Object { ([string]$_.ecosystem).Trim().ToLowerInvariant() } |
        Select-Object -Unique)
    $runId = [string]$Recorded.runId

    foreach ($proposal in @($Proposed)) {
        if ($null -eq $proposal) { continue }
        $fields = @(Get-QaFoundryPropertyNames -InputObject $proposal)
        if ($fields -notcontains "ecosystem") { continue }
        $chosen = ([string]$proposal.ecosystem).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($chosen)) { continue }
        $projectPath = & $normalisePath ([string]$proposal.path)
        $label = $projectPath
        if ($fields -contains "name" -and -not [string]::IsNullOrWhiteSpace([string]$proposal.name)) {
            $label = "$([string]$proposal.name)' at '$projectPath"
        }

        $recordedHere = $null
        foreach ($candidate in @($recordedByProject.Keys)) {
            if ($candidate -ceq $projectPath) { $recordedHere = $recordedByProject[$candidate]; break }
        }
        if ($null -eq $recordedHere) {
            if ($chosen -notin $recordedEcosystems) {
                $findings.Add("Automation project '$label' is designed on the '$chosen' ecosystem, " +
                    "but this repository already records automation on " +
                    "($($recordedEcosystems -join ', ')) from run '$runId'. Changing the toolchain " +
                    "is a migration and needs its own pull request, its own justification and its " +
                    "own verification, so it cannot be done as part of this work. Design on the " +
                    "recorded toolchain, or return blocked naming the requirement it cannot meet.")
            }
            continue
        }
        $recordedEcosystem = ([string]$recordedHere.ecosystem).Trim().ToLowerInvariant()
        if ($chosen -cne $recordedEcosystem) {
            $findings.Add("Automation project '$label' is designed on the '$chosen' ecosystem, but " +
                "this repository records that very project on '$recordedEcosystem' from run " +
                "'$runId'. Moving an existing suite to another ecosystem is a migration and needs " +
                "its own pull request, its own justification and its own verification. Design on " +
                "the recorded toolchain, or return blocked naming the requirement it cannot meet.")
            continue
        }
        $recordedFields = @(Get-QaFoundryPropertyNames -InputObject $recordedHere)
        foreach ($field in @("language", "testFramework")) {
            if ($recordedFields -notcontains $field -or $fields -notcontains $field) { continue }
            $recordedValue = [string]$recordedHere.$field
            $chosenValue = [string]$proposal.$field
            if ([string]::IsNullOrWhiteSpace($recordedValue) -or
                [string]::IsNullOrWhiteSpace($chosenValue)) {
                continue
            }
            if ((& $normaliseChoice $chosenValue) -cne (& $normaliseChoice $recordedValue)) {
                $findings.Add("Automation project '$label' is designed with $field " +
                    "'$chosenValue', but this repository records that project with $field " +
                    "'$recordedValue' from run '$runId'. A second $field beside the first is a " +
                    "migration and needs its own pull request. Design on the recorded toolchain, " +
                    "or return blocked naming the requirement it cannot meet.")
            }
        }
    }
    return @($findings)
}

# The blueprint check above holds an architect to the record. Nothing held an
# ordinary implementation run to it: a task to add a test could arrive at
# 'implement-work-item', and the change generator could put a package.json
# beside a .NET suite - a second toolchain nobody decided on, arriving as a side
# effect of a task about something else. That change set never passes through
# the blueprint, so it is checked here on what it actually writes: the manifests.
#
# Only the automation is held to this. The product's own manifests are the
# product's business, and this record says nothing about them.
function Get-QaFoundryToolchainManifestConflicts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$Recorded,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Paths,
        [AllowEmptyString()][string]$AutomationRoot = "automation"
    )

    $findings = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Recorded) { return @($findings) }

    $normalisePath = {
        param([AllowEmptyString()][string]$Value)
        return ((([string]$Value).Replace("\", "/") -replace "^\./", "").Trim("/"))
    }
    $root = & $normalisePath $AutomationRoot
    $recordedByProject = [ordered]@{}
    foreach ($entry in @($Recorded.toolchains)) {
        foreach ($recordedProject in @($entry.projects)) {
            $key = & $normalisePath ([string]$recordedProject)
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            if (-not $recordedByProject.Contains($key)) { $recordedByProject[$key] = $entry }
        }
    }
    $recordedEcosystems = @(@($Recorded.toolchains) |
        ForEach-Object { ([string]$_.ecosystem).Trim().ToLowerInvariant() } |
        Select-Object -Unique)
    $runId = [string]$Recorded.runId

    # Asked of the adapters rather than written out here, so an installation that
    # gains an ecosystem gains this protection with it and not one release later.
    $manifestPatterns = [ordered]@{}
    foreach ($id in @(Get-QaFoundryEcosystemAdapterNames)) {
        try { $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $id } catch { continue }
        $pattern = [string]$adapter.manifestPattern
        if (-not [string]::IsNullOrWhiteSpace($pattern)) { $manifestPatterns[$id] = $pattern }
    }

    foreach ($candidate in @($Paths)) {
        $path = & $normalisePath ([string]$candidate)
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        # The gate onto the automation root is deliberately case-insensitive
        # where the ownership match below is not. Widening what gets checked
        # costs nothing; narrowing it would let a manifest through unexamined.
        if ([string]::IsNullOrWhiteSpace($root) -or
            -not ($path -eq $root -or $path.StartsWith("$root/", [StringComparison]::OrdinalIgnoreCase))) {
            continue
        }
        $ecosystem = ""
        foreach ($id in @($manifestPatterns.Keys)) {
            if ($path -match [string]$manifestPatterns[$id]) { $ecosystem = [string]$id; break }
        }
        if ([string]::IsNullOrWhiteSpace($ecosystem)) { continue }

        # The project this manifest belongs to is the recorded project it sits
        # deepest inside. Longest match rather than first, or a record naming
        # both 'automation' and 'automation/Ui' would answer for the wrong one.
        # Compared as written, exactly as the sibling check above does: two
        # directories differing only in case are two directories on the agents
        # this runs on, and the record does not speak for the second.
        $owner = $null
        $ownerPath = ""
        foreach ($key in @($recordedByProject.Keys)) {
            $recordedPath = [string]$key
            if ([string]::IsNullOrWhiteSpace($recordedPath)) { continue }
            $contains = $path.StartsWith("$recordedPath/", [StringComparison]::Ordinal) -or
                $path -ceq $recordedPath
            if (-not $contains) { continue }
            if ($recordedPath.Length -gt $ownerPath.Length) {
                $owner = $recordedByProject[$key]
                $ownerPath = $recordedPath
            }
        }

        if ($null -ne $owner) {
            $recordedEcosystem = ([string]$owner.ecosystem).Trim().ToLowerInvariant()
            if ($ecosystem -cne $recordedEcosystem) {
                $findings.Add("This change writes '$path', which is a '$ecosystem' manifest, into " +
                    "the automation project at '$ownerPath' that this repository records on " +
                    "'$recordedEcosystem' from run '$runId'. Adding a second toolchain to an " +
                    "existing suite is a migration: it needs its own pull request, its own " +
                    "justification and its own verification that both stacks still build. Do the " +
                    "work in the recorded toolchain, or return blocked naming what about " +
                    "'$recordedEcosystem' makes it unreachable.")
            }
            continue
        }
        if ($ecosystem -notin $recordedEcosystems) {
            $findings.Add("This change writes '$path', which is a '$ecosystem' manifest, under the " +
                "automation root, but this repository records automation on " +
                "($($recordedEcosystems -join ', ')) from run '$runId'. A new suite is still built " +
                "on a toolchain this repository already maintains; introducing another one is a " +
                "migration with its own pull request. Do the work in a recorded toolchain, or " +
                "return blocked naming the requirement none of them can meet.")
        }
    }
    return @($findings)
}

# The lock is a run artifact and the record is a repository file, but they say
# the same thing, so one is derived from the other rather than written twice.
function ConvertTo-QaFoundryToolchainRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Lock,
        [string]$RecordedBy = "sdlc-foundry"
    )

    $toolchains = foreach ($toolchain in @($Lock.toolchains)) {
        $fields = @(Get-QaFoundryPropertyNames -InputObject $toolchain)
        $entry = [ordered]@{
            id = [string]$toolchain.id
            ecosystem = [string]$toolchain.ecosystem
        }
        foreach ($optional in @("language", "testFramework")) {
            if ($fields -contains $optional -and -not [string]::IsNullOrWhiteSpace([string]$toolchain.$optional)) {
                $entry[$optional] = [string]$toolchain.$optional
            }
        }
        if ($fields -contains "runtime" -and $null -ne $toolchain.runtime) {
            $runtime = [ordered]@{}
            foreach ($key in @(Get-QaFoundryPropertyNames -InputObject $toolchain.runtime) | Sort-Object) {
                $runtime[$key] = $toolchain.runtime.$key
            }
            if ($runtime.Count -gt 0) { $entry["runtime"] = $runtime }
        }
        $entry["projects"] = @(@($toolchain.decidedFor) | ForEach-Object { [string]$_ })
        if ($fields -contains "sha256") { $entry["sha256"] = [string]$toolchain.sha256 }
        $entry
    }

    $record = [ordered]@{
        recordedBy = $RecordedBy
        recordedAt = (Get-Date).ToUniversalTime().ToString("o")
        runId = [string]$Lock.runId
    }
    if ((Get-QaFoundryPropertyNames -InputObject $Lock) -contains "blueprintSha256") {
        $record["blueprintSha256"] = [string]$Lock.blueprintSha256
    }
    $record["toolchains"] = @($toolchains)
    return $record
}


function Get-QaFoundryRunRelativePath {
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$Path
    )

    $runFull = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RunRoot).Path).TrimEnd([char]"\", [char]"/")
    $full = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
    $prefix = $runFull + [IO.Path]::DirectorySeparatorChar
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Artifact '$full' is outside the run directory '$runFull'."
    }
    return $full.Substring($prefix.Length).Replace("\", "/")
}

function Resolve-QaFoundryRunArtifactPath {
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$RelativePath,
        [string]$Description = "artifact"
    )

    # A path recorded in run state is data, and data can be wrong. Treat it the
    # way the change applier treats a path from a model: refuse anything rooted,
    # anything that climbs out of the run, and any link that could redirect the
    # read somewhere the run does not own.
    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        throw "The recorded path for $Description is empty."
    }
    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '^[A-Za-z]:' -or
        $RelativePath.StartsWith("\\")) {
        throw "The recorded path for $Description is absolute, which run state never records: $RelativePath"
    }
    $runFull = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RunRoot).Path).TrimEnd([char]"\", [char]"/")
    $combined = [IO.Path]::GetFullPath((Join-Path $runFull $RelativePath))
    $prefix = $runFull + [IO.Path]::DirectorySeparatorChar
    if (-not $combined.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "The recorded path for $Description escapes the run directory: $RelativePath"
    }
    if (-not (Test-Path -LiteralPath $combined -PathType Leaf)) {
        throw "The recorded $Description is missing from the run: $RelativePath"
    }
    $current = Get-Item -LiteralPath $combined -Force
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq [IO.FileAttributes]::ReparsePoint) {
            throw "The recorded path for $Description passes through a link: $($current.FullName)"
        }
        $currentFull = [IO.Path]::GetFullPath($current.FullName).TrimEnd([char]"\", [char]"/")
        if ($currentFull.Equals($runFull, [StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = Split-Path $currentFull -Parent
        if ([string]::IsNullOrEmpty($parent)) { break }
        $current = Get-Item -LiteralPath $parent -Force
    }
    return $combined
}


function Resolve-QaFoundryDeclaredInputs {
    param(
        [Parameter(Mandatory)][string]$RunRoot,
        [Parameter(Mandatory)][string]$StageId,
        [Parameter(Mandatory)][object]$Inputs,
        [string]$RunId = ""
    )

    # A stage that needs a specific earlier artifact says which stage produced
    # it and what it is called. Searching the run directory instead would find
    # every superseded draft of the same name, and the newest file on disk is
    # not the one the run carried forward.
    $statePath = Join-Path $RunRoot "workflow-state.json"
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "Stage '$StageId' declares inputs, but this run has no state to resolve them from."
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -Depth 100
    # A stage that ran, decided nothing was warranted and said so has succeeded.
    # It still writes the artifact that records that decision, and a stage that
    # reads it is entitled to be told "nothing" rather than to fail. Whether the
    # named artifact is actually there is settled below, so admitting this
    # status cannot let a stage read something that was never produced.
    $succeeded = @("completed", "approved", "approved_with_dissent", "no_action_needed")
    $resolved = [ordered]@{}
    foreach ($property in @($Inputs.PSObject.Properties)) {
        $inputName = [string]$property.Name
        $specification = $property.Value
        $sourceStage = [string]$specification.stage
        $artifactName = [string]$specification.artifact
        if ([string]::IsNullOrWhiteSpace($sourceStage) -or [string]::IsNullOrWhiteSpace($artifactName)) {
            throw "Stage '$StageId' declares input '$inputName' without naming a stage and an artifact."
        }
        $sourceState = @($state.stages | Where-Object { [string]$_.id -ceq $sourceStage })
        if ($sourceState.Count -ne 1) {
            throw "Stage '$StageId' needs stage '$sourceStage', which this workflow does not run."
        }
        $attempts = @($sourceState[0].attempts | Where-Object { [string]$_.status -in $succeeded })
        if ($attempts.Count -eq 0) {
            throw "Stage '$StageId' needs '$artifactName' from stage '$sourceStage', which never succeeded."
        }
        $attempt = $attempts[-1]
        $records = @($attempt.artifacts | Where-Object { [string]$_.name -ceq $artifactName })
        if ($records.Count -ne 1) {
            throw ("Stage '$StageId' cannot resolve '$artifactName' from stage '$sourceStage': that " +
                "attempt recorded $($records.Count) artifact(s) by that name.")
        }
        $full = Resolve-QaFoundryRunArtifactPath -RunRoot $RunRoot `
            -RelativePath ([string]$records[0].relativePath) `
            -Description "input '$inputName' of stage '$StageId'"
        # State records what the file was when it was produced. A file that has
        # changed since is not the artifact anybody approved.
        $actual = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -cne [string]$records[0].sha256) {
            throw ("Stage '$StageId' found '$artifactName' changed since stage '$sourceStage' " +
                "produced it.")
        }
        $resolved[$inputName] = [pscustomobject][ordered]@{
            input = $inputName
            stage = $sourceStage
            name = $artifactName
            relativePath = [string]$records[0].relativePath
            sha256 = $actual
            path = $full
        }
        if (-not [string]::IsNullOrWhiteSpace($RunId) -or
            ($specification.PSObject.Properties.Name -contains "schema")) {
            $document = Get-Content -LiteralPath $full -Raw | ConvertFrom-Json -Depth 100
            if ($specification.PSObject.Properties.Name -contains "schema") {
                $foundryRoot = Get-QaFoundryRoot
                $null = & (Join-Path $foundryRoot "scripts/Validate-JsonArtifact.ps1") `
                    -ArtifactPath $full `
                    -SchemaPath (Join-Path $foundryRoot ([string]$specification.schema)) `
                    -SchemaRoot (Join-Path $foundryRoot "schemas")
            }
            # A document carried between stages says which run and which stage
            # made it. Those fields exist so that a file recovered from the
            # wrong run cannot quietly stand in for this one.
            if (-not [string]::IsNullOrWhiteSpace($RunId) -and
                ($document.PSObject.Properties.Name -contains "runId") -and
                ([string]$document.runId -cne $RunId)) {
                throw ("Stage '$StageId' resolved '$artifactName' from run " +
                    "'$([string]$document.runId)', not from this run.")
            }
            if (($document.PSObject.Properties.Name -contains "stageId") -and
                ([string]$document.stageId -cne $sourceStage)) {
                throw ("Stage '$StageId' resolved '$artifactName' claiming stage " +
                    "'$([string]$document.stageId)', but stage '$sourceStage' recorded producing it.")
            }
        }
    }
    return $resolved
}

# What a single call to a provider cost, written beside the artifact the call was
# meant to produce. Recorded for attempts that produced nothing as well as for
# ones that answered: a call that timed out spent the budget just the same, and a
# ledger holding only the successes would report a run as cheaper the worse it
# went.
#
# Sizes are bytes actually written and received, so they are exact. Token counts
# are only ever copied from a provider that reported them, and are left null
# otherwise. The temptation is to divide bytes by four and call the result
# tokens, but an estimate stored in the field a measurement would occupy cannot
# afterwards be told apart from one, and every later comparison would inherit the
# guess without knowing it.
function Write-QaFoundryProviderMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][string]$StageId,
        [Parameter(Mandatory)][string]$AgentId,
        [int]$StageIteration = 0,
        [Parameter(Mandatory)][int]$Attempt,
        [Parameter(Mandatory)][string]$Provider,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Model,
        [AllowEmptyString()][string]$ReasoningEffort = "",
        [Parameter(Mandatory)][ValidateSet("answered", "timed_out", "faltered", "failed")][string]$Status,
        [ValidateSet("artifact", "field_repair")][string]$Purpose = "artifact",
        [Parameter(Mandatory)][DateTime]$StartedAt,
        [Parameter(Mandatory)][double]$DurationMs,
        [AllowEmptyString()][string]$RequestText = "",
        [AllowEmptyString()][string]$ResponseText = "",
        [object[]]$RequestSections = @(),
        [AllowNull()][object]$ProviderUsage = $null,
        [AllowEmptyString()][string]$ErrorMessage = ""
    )

    $measure = {
        param([string]$Text)
        [ordered]@{
            bytes = [int][System.Text.Encoding]::UTF8.GetByteCount([string]$Text)
            characters = [int]([string]$Text).Length
        }
    }

    $request = & $measure $RequestText
    if (@($RequestSections).Count -gt 0) {
        $request["sections"] = @($RequestSections | ForEach-Object {
            [ordered]@{ name = [string]$_.name; bytes = [int]$_.bytes }
        })
    }

    # A model has to be named for the record to mean anything, and an empty one
    # says the configuration never chose. It is recorded as unnamed rather than
    # dropped, because a call that happened is a cost whether or not it can be
    # attributed.
    $modelName = ([string]$Model).Trim()
    if ([string]::IsNullOrWhiteSpace($modelName)) { $modelName = "unnamed" }

    $record = [ordered]@{
        id = "$RunId/$StageId/$AgentId/$StageIteration/$Attempt/$Purpose"
        runId = $RunId
        stageId = $StageId
        agentId = $AgentId
        stageIteration = [int]$StageIteration
        attempt = [int]$Attempt
        provider = $Provider
        model = $modelName
        reasoningEffort = [string]$ReasoningEffort
        status = $Status
        purpose = $Purpose
        startedAt = $StartedAt.ToUniversalTime().ToString("o")
        durationMs = [int][Math]::Max(0, [Math]::Round($DurationMs))
        request = $request
        response = (& $measure $ResponseText)
        usage = (ConvertTo-QaFoundryProviderUsage -Reported $ProviderUsage)
        error = $null
    }
    if (-not [string]::IsNullOrWhiteSpace($ErrorMessage)) {
        $record["error"] = [ordered]@{ message = [string]$ErrorMessage }
    }

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $record | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8
    return $record
}

# The Copilot CLI states what a call cost in its own shape: a per-model breakdown
# under modelMetrics, each with its own usage block. Translated here rather than
# in the provider so that the one place which knows what a usage record means is
# also the place that decides what counts as one.
#
# A session may touch more than one model - a fallback, a sub-agent - so the
# counts are summed across all of them and the model is named only when exactly
# one answered. Naming one of several would attribute the whole cost to it.
function ConvertTo-QaFoundryCopilotUsage {
    [CmdletBinding()]
    param([AllowNull()][object]$Reported)

    if ($null -eq $Reported) { return $null }
    $names = @(Get-QaFoundryPropertyNames -InputObject $Reported)
    if ($names -notcontains "modelMetrics" -or $null -eq $Reported.modelMetrics) { return $null }

    $modelNames = @(Get-QaFoundryPropertyNames -InputObject $Reported.modelMetrics)
    if ($modelNames.Count -eq 0) { return $null }

    $inputTokens = 0
    $outputTokens = 0
    $cachedInputTokens = 0
    $counted = 0
    foreach ($modelName in $modelNames) {
        $metrics = $Reported.modelMetrics.$modelName
        if ($null -eq $metrics) { continue }
        if (@(Get-QaFoundryPropertyNames -InputObject $metrics) -notcontains "usage") { continue }
        $usageBlock = $metrics.usage
        if ($null -eq $usageBlock) { continue }
        $usageNames = @(Get-QaFoundryPropertyNames -InputObject $usageBlock)
        # Counts what was read, not what was looked at. A usage block that is
        # empty, or whose every figure is missing, is a block that measured
        # nothing: adding zero for it and calling the result a measurement would
        # put a call that cost nothing in the ledger beside calls that genuinely
        # did.
        #
        # A counter that is present and unreadable is a different thing again. It
        # is not silence, it is a figure this runtime failed to understand, and
        # carrying the rest of the block without it would report a call as
        # cheaper than it was - the one direction a cost ledger must never err
        # in. So the whole block is refused rather than partly believed.
        #
        # $null means the figure was not stated; -1 means it was stated and could
        # not be read.
        $read = {
            param([string]$Field)
            if ($usageNames -notcontains $Field) { return $null }
            $raw = $usageBlock.$Field
            # An explicit null is the CLI declining to state the figure, which is
            # the same as not stating it at all.
            if ($null -eq $raw) { return $null }
            $parsed = 0
            if (-not [int]::TryParse([string]$raw, [ref]$parsed) -or $parsed -lt 0) { return -1 }
            return $parsed
        }
        # inputTokens already carries whatever was written to cache on this call;
        # cacheReadTokens is the part that was served from it. Adding them would
        # count the same prompt twice.
        $readInput = & $read "inputTokens"
        $readOutput = & $read "outputTokens"
        $readCached = & $read "cacheReadTokens"
        if (@($readInput, $readOutput, $readCached) -contains -1) { continue }
        if ($null -eq $readInput -and $null -eq $readOutput -and $null -eq $readCached) { continue }
        if ($null -ne $readInput) { $inputTokens += $readInput }
        if ($null -ne $readOutput) { $outputTokens += $readOutput }
        if ($null -ne $readCached) { $cachedInputTokens += $readCached }
        $counted++
    }
    if ($counted -eq 0) { return $null }

    $usage = [ordered]@{
        source = "provider"
        inputTokens = $inputTokens
        outputTokens = $outputTokens
        cacheReadTokens = $cachedInputTokens
        totalTokens = $inputTokens + $outputTokens
    }
    if ($modelNames.Count -eq 1) { $usage["model"] = [string]$modelNames[0] }
    return $usage
}

# Providers report usage under whatever names their own APIs use. Only the counts
# that are actually present are carried across, and a report that names no count
# at all is treated as no report: an object saying nothing but "source" would
# claim a measurement exists where none does.
function ConvertTo-QaFoundryProviderUsage {
    [CmdletBinding()]
    param([AllowNull()][object]$Reported)

    if ($null -eq $Reported) { return $null }
    $names = @(Get-QaFoundryPropertyNames -InputObject $Reported)
    if ($names.Count -eq 0) { return $null }

    $aliases = [ordered]@{
        inputTokens = @("inputTokens", "input_tokens", "promptTokens", "prompt_tokens")
        outputTokens = @("outputTokens", "output_tokens", "completionTokens", "completion_tokens")
        cachedInputTokens = @("cachedInputTokens", "cached_input_tokens", "cacheReadTokens", "cache_read_input_tokens")
        totalTokens = @("totalTokens", "total_tokens")
    }
    $usage = [ordered]@{ source = "provider" }
    $counted = 0
    foreach ($field in $aliases.Keys) {
        foreach ($alias in $aliases[$field]) {
            if ($names -notcontains $alias) { continue }
            $value = $Reported.$alias
            if ($null -eq $value) { continue }
            $parsed = 0
            if (-not [int]::TryParse([string]$value, [ref]$parsed)) { continue }
            if ($parsed -lt 0) { continue }
            $usage[$field] = $parsed
            $counted++
            break
        }
    }
    # Counted, not keys. A report naming only the model would otherwise pass as a
    # measurement carrying no number, which is the one thing this must not do:
    # every later comparison would read it as a call that cost nothing.
    if ($counted -eq 0) { return $null }
    if ($names -contains "model" -and -not [string]::IsNullOrWhiteSpace([string]$Reported.model)) {
        $usage["model"] = [string]$Reported.model
    }
    return $usage
}

# A relay leg carries a clock; the run as a whole carries a bill. The two stop
# for different reasons and must not be confused: a leg out of time pauses and
# hands the remaining work to the next leg, while a run out of budget has to
# stop for good. Pausing it would only move the spending to the leg after.
function Get-QaFoundryRunTokenBudget {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Config)

    if (@(Get-QaFoundryPropertyNames -InputObject $Config) -notcontains "ai") { return 0 }
    $ai = $Config.ai
    if ($null -eq $ai) { return 0 }
    if (@(Get-QaFoundryPropertyNames -InputObject $ai) -notcontains "run_budget") { return 0 }
    $budget = $ai.run_budget
    if ($null -eq $budget) { return 0 }
    if (@(Get-QaFoundryPropertyNames -InputObject $budget) -notcontains "max_total_tokens") { return 0 }
    $parsed = 0
    if (-not [int]::TryParse([string]$budget.max_total_tokens, [ref]$parsed)) { return 0 }
    if ($parsed -lt 0) { return 0 }
    return $parsed
}

# What one call cost, read back from the ledger the call itself wrote.
#
# A provider that declines to state its usage must not be a way for a run to
# spend without being counted, so a call that reported nothing is charged an
# estimate from what was demonstrably sent and received. Four bytes to the token
# is the conventional rough figure and it under-states rather than over-states
# for English prose, which is the safe direction here only because the
# alternative - charging nothing - lets an unmeasured provider run forever.
function Get-QaFoundryCallTokenCost {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Record)

    $readCount = {
        param([object]$Container, [string]$Field)
        if ($null -eq $Container) { return $null }
        if (@(Get-QaFoundryPropertyNames -InputObject $Container) -notcontains $Field) { return $null }
        $raw = $Container.$Field
        if ($null -eq $raw) { return $null }
        $parsed = 0
        if (-not [int]::TryParse([string]$raw, [ref]$parsed) -or $parsed -lt 0) { return $null }
        return $parsed
    }

    $usage = $null
    if (@(Get-QaFoundryPropertyNames -InputObject $Record) -contains "usage") { $usage = $Record.usage }
    if ($null -ne $usage) {
        $total = & $readCount $usage "totalTokens"
        if ($null -ne $total) {
            return [ordered]@{ tokens = [int]$total; estimated = $false }
        }
        $inputCount = & $readCount $usage "inputTokens"
        $outputCount = & $readCount $usage "outputTokens"
        if ($null -ne $inputCount -or $null -ne $outputCount) {
            $sum = 0
            if ($null -ne $inputCount) { $sum += $inputCount }
            if ($null -ne $outputCount) { $sum += $outputCount }
            return [ordered]@{ tokens = [int]$sum; estimated = $false }
        }
    }

    $bytes = 0
    foreach ($side in @("request", "response")) {
        if (@(Get-QaFoundryPropertyNames -InputObject $Record) -notcontains $side) { continue }
        $measured = & $readCount $Record.$side "bytes"
        if ($null -ne $measured) { $bytes += $measured }
    }
    return [ordered]@{ tokens = [int][Math]::Ceiling($bytes / 4.0); estimated = $true }
}

# What the run has spent so far, summed from every call it recorded. The ledger
# on disk is the only account that survives a leg boundary, so it is also the
# only one a budget can be enforced against.
function Get-QaFoundryRunTokensSpent {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string]$RunRoot)

    $spent = [ordered]@{ tokens = 0; calls = 0; estimatedCalls = 0 }
    if ([string]::IsNullOrWhiteSpace($RunRoot) -or -not (Test-Path -LiteralPath $RunRoot)) {
        return $spent
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $RunRoot -File -Recurse -Filter "*.provider-metadata.json" -ErrorAction SilentlyContinue)) {
        $record = $null
        try {
            $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -Depth 20
        }
        catch {
            # A half-written record from an interrupted call is not a reason to
            # abandon the accounting; the calls that did record cleanly still
            # have to be paid for.
            continue
        }
        if ($null -eq $record) { continue }
        $cost = Get-QaFoundryCallTokenCost -Record $record
        $spent.tokens += [int]$cost.tokens
        $spent.calls++
        if ($cost.estimated) { $spent.estimatedCalls++ }
    }
    return $spent
}

# Checked before a call rather than after one, because a budget that only
# notices afterwards has already been exceeded.
function Test-QaFoundryRunBudgetExhausted {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$RunRoot,
        [Parameter(Mandatory)][object]$Config
    )

    $budget = Get-QaFoundryRunTokenBudget -Config $Config
    if ($budget -le 0) { return $null }
    $spent = Get-QaFoundryRunTokensSpent -RunRoot $RunRoot
    if ([int]$spent.tokens -lt $budget) { return $null }
    $detail = "$($spent.tokens) token(s) across $($spent.calls) call(s) against a run budget of $budget"
    if ([int]$spent.estimatedCalls -gt 0) {
        $detail += " ($($spent.estimatedCalls) call(s) counted by measured size because the provider reported no usage)"
    }
    return $detail
}
