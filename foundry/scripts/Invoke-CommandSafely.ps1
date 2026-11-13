[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$CommandSpec,
    [Parameter(Mandatory)][object]$Policy,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [AllowNull()][object]$Deadline = $null,
    # How far this command is kept from the machine it runs on. Every caller of
    # this script is running something an agent wrote: an execution plan's
    # install and build steps, and the quality suite's tests. They are no more
    # trusted than the bootstrap verification that has been isolated all along,
    # so they are isolated the same way and by the same code.
    [AllowNull()][object]$Isolation = $null,
    # Where the command's home, caches and neutral tool configuration live. It
    # defaults inside the repository because that is what a container mounts,
    # and because a cache written by an install step has to still be there when
    # the build step runs.
    [string]$IsolationHome = ""
)

. (Join-Path $PSScriptRoot "Common.ps1")

# A command killed because the leg ran out of time has proved nothing about the
# command. Build 500 lost a whole leg to the opposite assumption: eleven
# commands were started against a deadline that had already passed, each was
# killed at the policy timeout, and every one of them was recorded as a failure
# it had not earned. A budget stop is therefore a distinct outcome that the
# caller is expected to discard rather than keep.
function New-BlockedCommandResult {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][string]$Reason,
        [int]$DurationMs = 0
    )

    return [ordered]@{
        id = $Id
        command = $Command
        exitCode = 0
        standardOutput = ""
        standardError = "Not run to completion: $Reason Nothing is claimed about this command."
        durationMs = $DurationMs
        status = "blocked"
    }
}

function New-RefusedCommandResult {
    param([Parameter(Mandatory)][string]$Id, [Parameter(Mandatory)][string]$Command, [Parameter(Mandatory)][string]$Reason)

    # An agent proposing a command the policy will not run is the guardrail working,
    # not a crash. Refuse it, say why, and let the run carry on: the command never
    # executes either way, and throwing here would discard every completed stage.
    return [ordered]@{
        id = $Id
        command = $Command
        exitCode = 0
        standardOutput = ""
        standardError = "Not run: $Reason Nothing is claimed about this command."
        durationMs = 0
        status = "rejected"
    }
}

$executable = [string]$CommandSpec.executable
$allowed = @($Policy.commands.allowed_executables)
$arguments = @($CommandSpec.arguments | ForEach-Object { [string]$_ })
$displayCommand = (@($executable) + $arguments) -join " "
if ($executable -notin $allowed) {
    return New-RefusedCommandResult -Id ([string]$CommandSpec.id) -Command $displayCommand -Reason (
        "the executable '$executable' is not on the policy's allowed list, which permits " +
        (@($allowed) -join ", ") + ".")
}

foreach ($pattern in @($Policy.commands.forbidden_patterns)) {
    if ($displayCommand -match [string]$pattern) {
        return New-RefusedCommandResult -Id ([string]$CommandSpec.id) -Command $displayCommand -Reason (
            "the policy's forbidden pattern '$pattern' matches it.")
    }
}

$workingDirectory = Resolve-QaFoundryPath `
    -Root $RepositoryRoot `
    -Path ([string]$CommandSpec.workingDirectory)
if (-not (Test-PathWithinRoot -Candidate $workingDirectory -Root $RepositoryRoot)) {
    throw "Working directory is outside the repository: $workingDirectory"
}
if (-not (Test-Path $workingDirectory -PathType Container)) {
    # In a bootstrap run the automation is specified long before it is written:
    # files reach the repository from the reviewed change set at the end of the
    # workflow, so a command aimed at an automation directory has nothing to run
    # in yet. That is a fact about ordering, not a failure of the product, and it
    # must not destroy an hour of completed stages. Record it and move on.
    return [ordered]@{
        id = [string]$CommandSpec.id
        command = $displayCommand
        exitCode = 0
        standardOutput = ""
        standardError = (
            "Not run: the working directory '$([string]$CommandSpec.workingDirectory)' does not " +
            "exist in the repository yet. Nothing is claimed about this command.")
        durationMs = 0
        status = "skipped"
    }
}

$providedEnvironment = if ($CommandSpec.PSObject.Properties.Name -contains "environment") {
    $CommandSpec.environment
}
else {
    [pscustomobject]@{}
}
$allowedEnvironment = @($Policy.commands.allowed_environment_variables)
foreach ($property in $providedEnvironment.PSObject.Properties) {
    if ($property.Name -notin $allowedEnvironment) {
        return New-RefusedCommandResult -Id ([string]$CommandSpec.id) -Command $displayCommand -Reason (
            "it sets the environment variable '$($property.Name)', which the policy does not allow. " +
            "Allowed variables are: " + (@($allowedEnvironment) -join ", ") + ".")
    }
}

# How long this command may run: never past the point where the leg still has
# time to record what it already has and hand the rest to the next one. The
# ceiling from the policy applies as well, whichever is smaller.
$policyTimeoutSeconds = [int]$Policy.commands.timeout_seconds
$timeoutSeconds = $policyTimeoutSeconds
$boundedByDeadline = $false
if ($null -ne $Deadline) {
    $usable = (Get-QaFoundryBudgetSecondsRemaining -Deadline $Deadline) -
        $script:QaFoundryHandoverReserveSeconds
    if ($usable -lt $timeoutSeconds) {
        $timeoutSeconds = $usable
        $boundedByDeadline = $true
    }
}
if ($timeoutSeconds -le 0) {
    return New-BlockedCommandResult -Id ([string]$CommandSpec.id) -Command $displayCommand -Reason (
        "this leg ran out of time before it started, so it was not started at all.")
}

$resolvedIsolation = Resolve-QaFoundryExecutionIsolation -Isolation $Isolation -Subject "Command"
if ([string]::IsNullOrWhiteSpace($IsolationHome)) {
    $IsolationHome = Join-Path $RepositoryRoot ".qa-foundry-artifacts/command-home"
}
New-Item -ItemType Directory -Path $IsolationHome -Force | Out-Null

$processInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processInfo.UseShellExecute = $false
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.CreateNoWindow = $true

# The environment is built rather than inherited, and the same builder serves
# both modes so that a container run and a process run agree on what the code is
# allowed to see. Anything the command asked for is added last and never over
# the isolation, so an allowed variable cannot put a credential back.
Set-QaFoundryIsolatedEnvironment -StartInfo $processInfo -IsolationHome $IsolationHome `
    -CommandEnvironment $providedEnvironment

$containerName = ""
if ($resolvedIsolation.mode -eq "container") {
    # The command is not changed, only where it runs. The repository is the
    # single mount: the agent's profile and every credential file on the machine
    # are outside it, so generated code cannot reach them by absolute path.
    $invocation = New-QaFoundryContainerInvocation -Isolation $resolvedIsolation `
        -HostRoot $RepositoryRoot -WorkingDirectory $workingDirectory `
        -Executable $executable -Arguments $arguments `
        -BuiltEnvironment $processInfo -NamePrefix "qa-foundry-command"
    $containerName = [string]$invocation.containerName
    $launchName = [string]$resolvedIsolation.executable
    $processInfo.FileName = $launchName
    foreach ($argument in @($invocation.arguments)) { $processInfo.ArgumentList.Add([string]$argument) }
    $processInfo.WorkingDirectory = [string]$invocation.workingDirectory
    # The client is not the container: what it is given here reaches the runtime
    # that starts the work, never the work itself.
    $processInfo.EnvironmentVariables.Clear()
    foreach ($item in (Get-QaFoundryPlatformEnvironment).GetEnumerator()) {
        $processInfo.EnvironmentVariables[[string]$item.Key] = [string]$item.Value
    }
    foreach ($name in @(Get-QaFoundryPropertyNames -InputObject $invocation.clientEnvironment)) {
        $processInfo.EnvironmentVariables[[string]$name] = [string]$invocation.clientEnvironment.$name
    }
}
else {
    # The policy allows a name; the operating system starts a file. On Windows the
    # two are not the same thing — 'npm' on PATH is a shell script that CreateProcess
    # refuses — so the allowed name is resolved to something launchable here, after
    # it has passed the allow-list and never in place of it. A name that resolves to
    # nothing is left to the failure path below: an allowed tool the agent does not
    # have is a command that failed, which the failure-analysis stage exists to
    # reason about, and not a reason to discard every stage that already completed.
    $launchName = $executable
    $executablePath = Resolve-QaFoundryExecutablePath -Name $executable
    if ([string]::IsNullOrWhiteSpace($executablePath)) { $executablePath = $executable }
    $processInfo.FileName = $executablePath
    $processInfo.WorkingDirectory = $workingDirectory
    foreach ($argument in $arguments) {
        $processInfo.ArgumentList.Add($argument)
    }
}

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $processInfo
try {
    $null = $process.Start()
}
catch {
    # An executable the policy allows is not necessarily installed on this
    # machine. That is a command that failed, which the failure-analysis stage
    # is there to reason about - not a reason to discard every completed stage.
    $stopwatch.Stop()
    $process.Dispose()
    return [ordered]@{
        id = [string]$CommandSpec.id
        command = $displayCommand
        exitCode = 127
        standardOutput = ""
        standardError = ("Could not start '$launchName': " + $_.Exception.Message +
            " The executable is allowed by policy but was not found on this machine.")
        durationMs = [int]$stopwatch.ElapsedMilliseconds
        status = "failed"
    }
}
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$completed = $process.WaitForExit($timeoutSeconds * 1000)
$containerRemoval = ""
if (-not $completed) {
    # The whole tree, because a test runner's browsers and language servers are
    # children and killing only the parent leaves them holding the working
    # directory the next command is about to use.
    $process.Kill($true)
    # In container mode the tree that was killed is the client. The daemon goes
    # on running what it started, and '--rm' does not fire because the container
    # never exited, so it is removed by the name it was given before it started.
    $containerRemoval = Remove-QaFoundryIsolationContainer -Name $containerName `
        -Runtime ([string]$resolvedIsolation.executable) -WorkingDirectory $RepositoryRoot
    $process.WaitForExit()
}
$stopwatch.Stop()
$stdout = $stdoutTask.GetAwaiter().GetResult()
$stderr = $stderrTask.GetAwaiter().GetResult()

foreach ($property in $providedEnvironment.PSObject.Properties) {
    foreach ($maskPattern in @($Policy.commands.mask_name_patterns)) {
        if ($property.Name -match [string]$maskPattern -and [string]$property.Value) {
            $stdout = $stdout.Replace([string]$property.Value, "***")
            $stderr = $stderr.Replace([string]$property.Value, "***")
        }
    }
}

$exitCode = if ($completed) { $process.ExitCode } else { 124 }
if (-not $completed -and $boundedByDeadline) {
    # The command was stopped by this leg's clock, not by its own timeout. It
    # may well have succeeded given the ceiling the policy allows, so recording
    # it as a failure would put a claim on the record that nothing supports.
    return New-BlockedCommandResult -Id ([string]$CommandSpec.id) -Command $displayCommand `
        -DurationMs ([int]$stopwatch.ElapsedMilliseconds) -Reason (
            "this leg ran out of time after $timeoutSeconds second(s), short of the " +
            "$policyTimeoutSeconds second(s) the policy allows it.$containerRemoval")
}
$successCodes = @($Policy.commands.success_exit_codes | ForEach-Object { [int]$_ })
$status = if ($completed -and $exitCode -in $successCodes) { "completed" } else { "failed" }
return [ordered]@{
    id = [string]$CommandSpec.id
    command = $displayCommand
    exitCode = $exitCode
    standardOutput = $stdout
    standardError = if ($completed) { $stderr } else { "$stderr`nCommand timed out.$containerRemoval" }
    durationMs = [int]$stopwatch.ElapsedMilliseconds
    status = $status
}

