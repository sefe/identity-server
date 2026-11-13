[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RequestPath,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$Model,
    [string]$ReasoningEffort = "",
    [Parameter(Mandatory)][string]$Command,
    [Parameter(Mandatory)][int]$TimeoutSeconds,
    [object]$ProviderOptions = $null,
    [hashtable]$ProviderEnvironment = @{},
    [string]$ProgressScope = "",
    [ValidateRange(0, 1000000)][int]$MaxAiCredits = 0
)

. (Join-Path $PSScriptRoot "../Common.ps1")
if (-not (Test-PathWithinRoot -Candidate $RequestPath -Root $RepositoryRoot)) {
    throw "Copilot request file must be inside the target repository."
}

$installMode = if ($ProviderOptions -and
    $ProviderOptions.PSObject.Properties.Name -contains "install_mode") {
    [string]$ProviderOptions.install_mode
}
else {
    "required"
}
$packageName = if ($ProviderOptions -and
    $ProviderOptions.PSObject.Properties.Name -contains "package") {
    [string]$ProviderOptions.package
}
else {
    "@github/copilot"
}
$packageVersion = if ($ProviderOptions -and
    $ProviderOptions.PSObject.Properties.Name -contains "package_version") {
    [string]$ProviderOptions.package_version
}
else {
    "latest"
}
$authMode = if ($ProviderOptions -and
    $ProviderOptions.PSObject.Properties.Name -contains "auth_mode") {
    [string]$ProviderOptions.auth_mode
}
else {
    "auto"
}
$allowStoredCredentialsInCi = if ($ProviderOptions -and
    $ProviderOptions.PSObject.Properties.Name -contains "allow_stored_credentials_in_ci") {
    [bool]$ProviderOptions.allow_stored_credentials_in_ci
}
else {
    $false
}
if ($authMode -notin @("auto", "environment")) {
    throw "Unsupported Copilot authentication mode: $authMode"
}

# Azure Pipelines leaves an undefined $(VARIABLE) macro as literal text. Never
# forward such placeholders as credentials because Copilot would prefer them to
# a valid keychain or GitHub CLI login. Surrounding whitespace is stripped
# because a token pasted into a variable group often carries a trailing newline,
# which GitHub rejects as an invalid credential.
$filteredProviderEnvironment = @{}
foreach ($item in $ProviderEnvironment.GetEnumerator()) {
    $value = ([string]$item.Value).Trim()
    if ([string]::IsNullOrWhiteSpace($value) -or
        $value -match '^\$\([A-Za-z_][A-Za-z0-9_.-]*\)$') {
        continue
    }
    $filteredProviderEnvironment[[string]$item.Key] = $value
}
$copilotAuthenticationVariables = @(
    "COPILOT_GITHUB_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"
)
$environmentCredentialName = @($copilotAuthenticationVariables | Where-Object {
    $filteredProviderEnvironment.ContainsKey($_)
} | Select-Object -First 1)
$isCi = [Environment]::GetEnvironmentVariable("CI") -eq "true" -or
    [Environment]::GetEnvironmentVariable("TF_BUILD") -eq "True"
if ($authMode -eq "environment" -and $environmentCredentialName.Count -eq 0) {
    throw "Copilot environment authentication requires COPILOT_GITHUB_TOKEN, GH_TOKEN, or GITHUB_TOKEN."
}
if ($isCi -and $environmentCredentialName.Count -eq 0 -and
    -not $allowStoredCredentialsInCi) {
    throw "Copilot CLI has no mapped CI credential. Configure COPILOT_GITHUB_TOKEN (recommended), GH_TOKEN, or GITHUB_TOKEN; or explicitly allow stored credentials for a pre-authenticated self-hosted agent."
}
$authenticationSource = if ($environmentCredentialName.Count -gt 0) {
    [string]$environmentCredentialName[0]
}
else {
    "stored-oauth-or-gh-cli"
}

$commandTokens = @($Command -split "\s+" | Where-Object { $_ })
if ($commandTokens.Count -eq 0) {
    $commandTokens = @("copilot")
}
$configuredExecutable = $commandTokens[0]
$configuredArguments = @($commandTokens | Select-Object -Skip 1)
$resolvedCommand = Resolve-QaFoundryExecutable -Name $configuredExecutable
if ($resolvedCommand) {
    $executable = $resolvedCommand
    $prefixArguments = $configuredArguments
    $commandMode = "installed"
}
elseif ($installMode -eq "npx-if-missing") {
    $npxCommand = Resolve-QaFoundryExecutable -Name "npx"
    if ($npxCommand) {
        $executable = $npxCommand
        $prefixArguments = @("--yes", "$packageName@$packageVersion")
        $commandMode = "npx"
    }
    else {
        $npmCommand = Resolve-QaFoundryExecutable -Name "npm"
        if (-not $npmCommand) {
            throw "Copilot CLI is missing and neither npx nor npm is available."
        }
        $executable = $npmCommand
        $prefixArguments = @(
            "exec",
            "--yes",
            "--package=$packageName@$packageVersion",
            "--",
            "copilot"
        )
        $commandMode = "npm-exec"
    }
}
else {
    throw "Copilot CLI executable was not found: $configuredExecutable"
}

function Invoke-CopilotProcess {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][int]$Timeout
    )
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $executable
    $processInfo.WorkingDirectory = $RepositoryRoot
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true
    foreach ($argument in $Arguments) {
        $processInfo.ArgumentList.Add($argument)
    }
    $safeEnvironment = @(
        "HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA",
        "XDG_CONFIG_HOME", "GH_CONFIG_DIR",
        "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "http_proxy", "https_proxy",
        "no_proxy", "NODE_EXTRA_CA_CERTS", "SSL_CERT_FILE"
    )
    $inherited = Get-QaFoundryPlatformEnvironment -AdditionalNames $safeEnvironment
    $processInfo.Environment.Clear()
    foreach ($item in $inherited.GetEnumerator()) {
        $processInfo.Environment[$item.Key] = [string]$item.Value
    }
    $processInfo.Environment["COPILOT_MODEL"] = $Model
    $processInfo.Environment["COPILOT_TASK_WAIT_TIMEOUT_SECONDS"] = [string]$Timeout
    $processInfo.Environment["QAF_MODEL"] = $Model
    $processInfo.Environment["QAF_REASONING_EFFORT"] = $ReasoningEffort
    foreach ($item in $filteredProviderEnvironment.GetEnumerator()) {
        $processInfo.Environment[$item.Key] = [string]$item.Value
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $waitStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $nextHeartbeatSeconds = 30
    while (-not $process.HasExited) {
        if ($waitStopwatch.Elapsed.TotalSeconds -ge $Timeout) {
            $process.Kill($true)
            # Killing is asynchronous. Whatever the caller does next with the
            # files this process was writing has to happen after it has actually
            # gone, or a receipt left half-written stays locked behind it.
            $null = $process.WaitForExit(5000)
            throw ("${script:QaFoundryProviderTimeoutMarker}: Copilot CLI did not answer " +
                "within $Timeout seconds.")
        }
        if ($waitStopwatch.Elapsed.TotalSeconds -ge $nextHeartbeatSeconds) {
            Write-QaFoundryLog -Indent 3 -Scope $ProgressScope -Message (
                "Still waiting on Copilot CLI: " +
                "$([int]$waitStopwatch.Elapsed.TotalSeconds)s elapsed of ${Timeout}s allowed.")
            if ($env:FOUNDRY_LOG_STYLE -eq 'summary' -and $nextHeartbeatSeconds % 60 -eq 0) {
                Write-QaFoundryLog -Audience business -Message (
                    "Work continues on $($ProgressScope.Replace('-', ' ')); " +
                    "$(Format-QaFoundryDuration $waitStopwatch.Elapsed) elapsed.")
            }
            $nextHeartbeatSeconds += 30
        }
        Start-Sleep -Milliseconds 500
    }
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    foreach ($value in $filteredProviderEnvironment.Values) {
        if ($value) {
            $stdout = $stdout.Replace([string]$value, "***")
            $stderr = $stderr.Replace([string]$value, "***")
        }
    }
    if ($process.ExitCode -ne 0) {
        throw "Copilot CLI exited with $($process.ExitCode): $stderr"
    }
    return [pscustomobject]@{
        stdout = $stdout.Trim()
        stderr = $stderr.Trim()
    }
}

$runRoot = Split-Path $RequestPath -Parent
# Supervisor decisions retain immutable state snapshots below the actual run.
# A legacy snapshot has the same filename as the live state; it is not a run
# root. Require the context directory owned by the workflow as well.
while ($runRoot -and -not (
    (Test-Path -LiteralPath (Join-Path $runRoot 'workflow-state.json') -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $runRoot 'context') -PathType Container))) {
    $parent = Split-Path $runRoot -Parent
    if ($parent -eq $runRoot) {
        $runRoot = $null
        break
    }
    $runRoot = $parent
}
if (-not $runRoot) {
    throw "Unable to locate the workflow run root for Copilot preflight."
}
$preflightPath = Join-Path $runRoot "context/copilot-preflight.json"
if (-not (Test-Path $preflightPath -PathType Leaf)) {
    $versionResult = Invoke-CopilotProcess `
        -Arguments @($prefixArguments + @("--no-auto-update", "version")) `
        -Timeout ([Math]::Min($TimeoutSeconds, 120))
    [ordered]@{
        checkedAt = [DateTime]::UtcNow.ToString("o")
        commandMode = $commandMode
        package = $packageName
        packageVersion = $packageVersion
        cliVersion = $versionResult.stdout
        model = $Model
        authenticationMode = $authMode
        authenticationSource = $authenticationSource
        ci = $isCi
    } | ConvertTo-Json -Depth 10 |
        Set-Content -Path $preflightPath -Encoding utf8
}

$promptSegments = @(
    "Read the complete SDLC Foundry agent request from this file: $RequestPath",
    "Follow that file as the authoritative task.",
    "Use file access only to read the request and its explicitly referenced evidence.",
    "Do not execute shell commands, modify files, access URLs, use MCP tools,",
    "ask the user, or start remote work.",
    "Return only the final JSON object required by the request."
)
$prompt = ($promptSegments -join " ")
$arguments = @($prefixArguments + @(
    "-s",
    "--no-color",
    "--no-ask-user",
    "--no-auto-update",
    "--no-custom-instructions",
    "--no-experimental",
    "--disable-builtin-mcps",
    "--available-tools=view",
    "--allow-tool=view",
    "--model=$Model"
))
if (-not [string]::IsNullOrWhiteSpace($ReasoningEffort)) {
    $arguments += "--reasoning-effort=$ReasoningEffort"
}
foreach ($name in @($filteredProviderEnvironment.Keys | Sort-Object)) {
    $arguments += "--secret-env-vars=$name"
}
$arguments += @("-p", $prompt)
if ($MaxAiCredits -gt 0) {
    # Copilot checks credits after each model response, so one response may
    # exceed this soft cap. The outer ledger reserves this allowance across calls.
    $arguments += @('--max-ai-credits', [string]$MaxAiCredits)
}

# The CLI can state what the call actually cost. Until now nothing asked it to,
# so every entry in the run's cost ledger carried measured byte sizes and a null
# where the token counts belong - and a ledger that never holds a number cannot
# be compared against anything. The figures are written to a file of our own
# rather than parsed out of the answer, so nothing about the artifact has to
# change to carry them.
#
# The name ends in '.usage.json' deliberately: if a kill leaves the file locked
# and undeletable, the suffix is the one the context sweep and the run-artifact
# check already know to leave alone, so a stray receipt cannot become context
# for a later agent or an unexplained artifact.
$rawUsagePath = "$RequestPath.copilot.usage.json"
Remove-Item -LiteralPath $rawUsagePath -Force -ErrorAction SilentlyContinue
$arguments += @("--usage-output-file", $rawUsagePath)

try {
    $result = Invoke-CopilotProcess -Arguments $arguments -Timeout $TimeoutSeconds
}
finally {
    # A call that timed out or exited non-zero still spent whatever it spent, so
    # the figures are collected on the way out of every path. Accounting must not
    # be able to fail a call that produced an answer, nor mask the failure of one
    # that did not, so this is best-effort throughout.
    try {
        if (Test-Path -LiteralPath $rawUsagePath -PathType Leaf) {
            $reported = Get-Content -LiteralPath $rawUsagePath -Raw | ConvertFrom-Json -Depth 30
            $usage = ConvertTo-QaFoundryCopilotUsage -Reported $reported
            if ($null -ne $usage) {
                $usage | ConvertTo-Json -Depth 10 |
                    Set-Content -LiteralPath "$RequestPath.usage.json" -Encoding utf8
            }
        }
    }
    catch {
        Write-QaFoundryLog -Level warn -Indent 2 -Scope $ProgressScope -Message (
            "The Copilot CLI reported usage figures this runtime could not read, so the call is " +
            "recorded with measured sizes only: $($_.Exception.Message)")
    }
    Remove-Item -LiteralPath $rawUsagePath -Force -ErrorAction SilentlyContinue
}

return $result.stdout
