[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Command,
    [Parameter(Mandatory)][string]$RequestPath,
    [Parameter(Mandatory)][int]$TimeoutSeconds,
    [string]$Model = "",
    [string]$ReasoningEffort = "",
    [hashtable]$ProviderEnvironment = @{}
)

if ([string]::IsNullOrWhiteSpace($Command)) {
    throw "ai.command is required for the command provider."
}

$tokens = @($Command -split "\s+" | Where-Object { $_ })
$executable = $tokens[0]
$arguments = @($tokens | Select-Object -Skip 1)
$arguments += $RequestPath

. (Join-Path $PSScriptRoot "../Common.ps1")

try {
    $processInfo = [System.Diagnostics.ProcessStartInfo]::new()
    # A configured command names a tool; the process API needs a file it can
    # start. On Windows those differ for anything installed as a shim.
    $executablePath = Resolve-QaFoundryExecutablePath -Name $executable
    if ([string]::IsNullOrWhiteSpace($executablePath)) {
        throw "The configured ai.command executable '$executable' is not installed on this agent."
    }
    $processInfo.FileName = $executablePath
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true
    foreach ($argument in $arguments) {
        $processInfo.ArgumentList.Add($argument)
    }
    $processInfo.Environment.Clear()
    foreach ($item in (Get-QaFoundryPlatformEnvironment).GetEnumerator()) {
        $processInfo.Environment[$item.Key] = [string]$item.Value
    }
    $processInfo.Environment["QAF_MODEL"] = $Model
    $processInfo.Environment["QAF_REASONING_EFFORT"] = $ReasoningEffort
    foreach ($item in $ProviderEnvironment.GetEnumerator()) {
        $processInfo.Environment[$item.Key] = [string]$item.Value
    }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        throw ("${script:QaFoundryProviderTimeoutMarker}: Command provider did not answer " +
        "within $TimeoutSeconds seconds.")
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    foreach ($value in $ProviderEnvironment.Values) {
        if ($value) {
            $stdout = $stdout.Replace([string]$value, "***")
            $stderr = $stderr.Replace([string]$value, "***")
        }
    }
    if ($process.ExitCode -ne 0) {
        throw "Command provider exited with $($process.ExitCode): $stderr"
    }
    return $stdout
}
finally {
}
