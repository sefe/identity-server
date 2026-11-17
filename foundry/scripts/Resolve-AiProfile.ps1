[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$Config,
    [string]$ProfileName = "",
    [string]$Model = "",
    [string]$ReasoningEffort = "",
    [switch]$Demo
)

$selectedName = if ($Demo) {
    "mock"
}
elseif ($ProfileName) {
    $ProfileName
}
else {
    [string]$Config.ai.active_profile
}

$profileProperty = $Config.ai.profiles.PSObject.Properties[$selectedName]
if (-not $profileProperty) {
    throw "AI profile does not exist: $selectedName"
}
$profile = $profileProperty.Value | ConvertTo-Json -Depth 50 |
    ConvertFrom-Json -Depth 50
if ($Model) {
    $profile.model = $Model
}
if ($ReasoningEffort) {
    $profile.reasoning_effort = $ReasoningEffort
}
if ([string]$profile.provider -notin @(
    "mock", "command", "copilot-cli"
)) {
    throw "Unsupported provider in AI profile '$selectedName': $($profile.provider)"
}
if (-not [string]$profile.model) {
    throw "AI profile '$selectedName' must define a model."
}
if ($profile.provider -eq "command" -and -not [string]$profile.command) {
    throw "Command provider profile '$selectedName' must define command."
}
$requiredSecretEnvironment = if (
    $profile.PSObject.Properties.Name -contains "required_secret_env"
) { @($profile.required_secret_env) } else { @() }
$modelSecretEnvironment = if (
    $profile.PSObject.Properties.Name -contains "secret_env"
) { @($profile.secret_env) } else { @($requiredSecretEnvironment) }
foreach ($requiredName in $requiredSecretEnvironment) {
    if ([string]$requiredName -notin @($modelSecretEnvironment | ForEach-Object {
        [string]$_
    })) {
        throw "AI profile '$selectedName' must include required secret '$requiredName' in secret_env."
    }
}
return [pscustomobject]@{
    name = $selectedName
    provider = [string]$profile.provider
    model = [string]$profile.model
    reasoning_effort = [string]$profile.reasoning_effort
    command = [string]$profile.command
    timeout_seconds = [int]$profile.timeout_seconds
    max_artifact_bytes = if (
        $profile.PSObject.Properties.Name -contains "max_artifact_bytes"
    ) { [int]$profile.max_artifact_bytes } else { 0 }
    required_secret_env = @($requiredSecretEnvironment)
    secret_env = @($modelSecretEnvironment)
    provider_options = if (
        $profile.PSObject.Properties.Name -contains "provider_options"
    ) { $profile.provider_options } else { [pscustomobject]@{} }
}
