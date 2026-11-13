[CmdletBinding()]
param(
    [Parameter(Mandatory)][object]$Toolchain,
    [Parameter(Mandatory)][string]$WorkRoot,
    # The identity of the project the lock will live in. Both are optional
    # because some ecosystems ask a private package for neither, and a field this
    # runtime invented would put a name or a version in the lock that the
    # manifest beside it never claimed.
    [string]$ManifestName = "",
    [string]$ManifestVersion = "",
    # A test seam, not a configuration knob: a test needs to point the resolver
    # at a stub instead of a real package manager, and nothing in a workflow
    # file may choose which resolver runs, or the isolation around it would be a
    # suggestion rather than a guarantee. Keys are the adapter's tool keys.
    [hashtable]$ToolCommandOverrides = @{},
    [switch]$BuildProbe,
    [AllowNull()][object]$Deadline = $null
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../Common.ps1")

# Resolving a lock is the same act in every ecosystem: check the agent runs the
# tooling the decision was settled on, write a manifest from the approved
# packages alone, run the resolver in an environment that carries nothing in
# from the machine, and read back the file it produced. Only the tools, the
# arguments and the manifest differ, and those come from the adapter. Keeping
# the isolation and the budgeting here means a new ecosystem inherits both
# rather than reimplementing whichever parts its author thought of.

# A leg that spends its last second inside the resolver has no time left to
# write evidence and hand over, so the resolver is never allowed to run right up
# to the deadline.
$script:HandoverReserveSeconds = 120
$script:ResolverCeilingSeconds = 600
$script:VersionProbeSeconds = 60

function New-Failure {
    param(
        [string]$Detail,
        [int]$ExitCode = -1,
        [double]$Duration = 0,
        [switch]$DeadlineReached,
        # Told apart deliberately. A missing tool or an unreachable feed is the
        # agent's problem and the same decision will work once it is fixed; a
        # resolver that refuses the packages is the decision's problem. Reporting
        # both as one failure would send a sound design back for redesign.
        [switch]$InfrastructureUnavailable
    )
    return [pscustomobject][ordered]@{
        succeeded = $false
        detail = $Detail
        exitCode = $ExitCode
        durationSeconds = $Duration
        deadlineReached = [bool]$DeadlineReached
        infrastructureUnavailable = [bool]$InfrastructureUnavailable
        lockJson = ""
    }
}

$ecosystem = [string]$Toolchain.ecosystem
try { $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $ecosystem }
catch {
    return New-Failure -Detail "No adapter can resolve a $ecosystem lock: $($_.Exception.Message)"
}

function Resolve-ToolPath {
    param([string]$Name)
    # Shared with every other place this runtime starts a child process, so that
    # a tool found by one stage is the same file another stage runs. In
    # particular it answers with npm.cmd rather than with the npm shell script or
    # the npm.ps1 shim, neither of which can be started without a shell.
    return (Resolve-QaFoundryExecutablePath -Name $Name)
}

$projectRoot = Join-Path $WorkRoot "project"
$homeRoot = Join-Path $WorkRoot "home"
$cacheRoot = Join-Path $WorkRoot "cache"
$tempRoot = Join-Path $WorkRoot "temp"
foreach ($directory in @($projectRoot, $homeRoot, $cacheRoot, $tempRoot)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

$requiredTools = @(& $adapter.GetResolverTools $Toolchain)
if ($requiredTools.Count -eq 0) {
    return New-Failure -Detail "The $($adapter.displayName) adapter names no resolver to run."
}

$toolPaths = @{}
foreach ($tool in $requiredTools) {
    $commandName = [string]$tool.command
    if ($ToolCommandOverrides.ContainsKey([string]$tool.key)) {
        $commandName = [string]$ToolCommandOverrides[[string]$tool.key]
    }
    $path = Resolve-ToolPath -Name $commandName
    if ([string]::IsNullOrWhiteSpace($path)) {
        return New-Failure -InfrastructureUnavailable -Detail (
            "This agent has no '$commandName' on its PATH, so a " +
            "$($adapter.displayName) lock cannot be produced here.")
    }
    $toolPaths[[string]$tool.key] = $path
}

# Every child process this script starts is built here. Asking a tool for its
# version is not a lesser act than installing with it: an inherited variable
# such as NODE_OPTIONS is enough to run someone else's code during a version
# probe, so the ambient environment is left behind for both.
function New-IsolatedStartInfo {
    param(
        [Parameter(Mandatory)][string]$FileName,
        [string[]]$Arguments = @(),
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [hashtable]$Environment = @{}
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FileName
    foreach ($argument in $Arguments) { $null = $startInfo.ArgumentList.Add($argument) }
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    # Start from nothing rather than from whatever the agent happens to export,
    # so a proxy, a CA override or a package-manager variable cannot reach the
    # child and change what it installs.
    $startInfo.EnvironmentVariables.Clear()

    $pathEntries = [System.Collections.Generic.List[string]]::new()
    foreach ($path in @($toolPaths.Values)) {
        $directory = Split-Path $path -Parent
        if ($directory -and -not $pathEntries.Contains($directory)) { $pathEntries.Add($directory) }
    }
    if (-not $IsWindows) {
        # Cached SDKs are not installed beside the operating-system utilities.
        # Maven's launcher needs dirname/uname even during a version probe.
        # Add known system directories without importing the ambient PATH.
        foreach ($directory in @('/usr/bin', '/bin')) {
            if ((Test-Path -LiteralPath $directory -PathType Container) -and -not $pathEntries.Contains($directory)) {
                $pathEntries.Add($directory)
            }
        }
    }
    $startInfo.EnvironmentVariables["PATH"] = ($pathEntries -join [IO.Path]::PathSeparator)
    $startInfo.EnvironmentVariables["HOME"] = $homeRoot
    $startInfo.EnvironmentVariables["USERPROFILE"] = $homeRoot
    $startInfo.EnvironmentVariables['DOTNET_CLI_HOME'] = $homeRoot
    $startInfo.EnvironmentVariables['APPDATA'] = $homeRoot
    $startInfo.EnvironmentVariables['LOCALAPPDATA'] = $homeRoot
    $startInfo.EnvironmentVariables["TMPDIR"] = $tempRoot
    $startInfo.EnvironmentVariables["TMP"] = $tempRoot
    $startInfo.EnvironmentVariables["TEMP"] = $tempRoot
    $startInfo.EnvironmentVariables["CI"] = "true"
    $startInfo.EnvironmentVariables["LANG"] = "C.UTF-8"
    $startInfo.EnvironmentVariables["LC_ALL"] = "C.UTF-8"
    if ($IsWindows) {
        # NuGet on Windows resolves its machine settings directory from these
        # platform paths even with an explicit --configfile. Omitting them makes
        # restore crash in ConfigurationDefaults before it reads the manifest.
        foreach ($required in @("SystemRoot", "ComSpec", "PATHEXT", "ProgramFiles", "ProgramFiles(x86)")) {
            $value = [Environment]::GetEnvironmentVariable($required)
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $startInfo.EnvironmentVariables[$required] = $value
            }
        }
    }
    # An ecosystem whose only way to point a tool somewhere is a variable says so
    # here, and it is added last so it cannot quietly replace the isolation above.
    foreach ($name in @($Environment.Keys)) {
        if ($startInfo.EnvironmentVariables.ContainsKey([string]$name)) { continue }
        $startInfo.EnvironmentVariables[[string]$name] = [string]$Environment[$name]
    }
    return $startInfo
}

function Invoke-IsolatedProcess {
    param(
        [Parameter(Mandatory)][System.Diagnostics.ProcessStartInfo]$StartInfo,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $StartInfo
    $standardOutput = ""
    $standardError = ""
    $exitCode = -1
    $timedOut = $false
    try {
        $null = $process.Start()
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try { $process.Kill($true) } catch { }
            # A killed process is only killed once it is gone. Returning while it
            # still runs would leave a resolver writing into the work directory
            # the next attempt is about to use.
            if (-not $process.WaitForExit(30 * 1000)) {
                throw "The resolver did not stop after being killed, so this agent is no longer in a known state."
            }
            $timedOut = $true
        }
        else {
            $standardOutput = [string]$outputTask.Result
            $standardError = [string]$errorTask.Result
            # Read the exit code before the process object is disposed, or the
            # refusal ends up quoting a blank code and blaming the wrong thing.
            $exitCode = $process.ExitCode
        }
    }
    finally {
        $stopwatch.Stop()
        $process.Dispose()
    }

    return [pscustomobject][ordered]@{
        timedOut = $timedOut
        exitCode = $exitCode
        standardOutput = $standardOutput
        standardError = $standardError
        durationSeconds = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
    }
}

# How long a child may run: never past the point where this leg still has time
# to hand over, and never past the standing ceiling either.
function Get-BudgetedTimeout {
    param([Parameter(Mandatory)][int]$Ceiling)

    $timeout = $Ceiling
    $boundedByDeadline = $false
    if ($null -ne $Deadline) {
        $remaining = [int](([DateTime]$Deadline).ToUniversalTime() - [DateTime]::UtcNow).TotalSeconds
        $usable = $remaining - $script:HandoverReserveSeconds
        if ($usable -lt $timeout) {
            $timeout = $usable
            $boundedByDeadline = $true
        }
    }
    return [pscustomobject]@{ seconds = $timeout; boundedByDeadline = $boundedByDeadline }
}

# The decision states the tooling it was settled on. A different resolver can
# emit a different lock shape from the same manifest, so the versions are
# checked rather than assumed.
function Get-ToolVersion {
    param([string]$Path, [string[]]$Arguments)

    $budget = Get-BudgetedTimeout -Ceiling $script:VersionProbeSeconds
    if ($budget.seconds -le 0) {
        return [pscustomobject]@{ version = ""; deadlineReached = $true; reason = "" }
    }
    $startInfo = New-IsolatedStartInfo -FileName $Path -Arguments $Arguments -WorkingDirectory $projectRoot
    $result = Invoke-IsolatedProcess -StartInfo $startInfo -TimeoutSeconds $budget.seconds
    # Why the probe produced nothing decides what a reader should do next, and
    # the three reasons call for three different actions: a timeout is an agent
    # that is wedged or starved, a non-zero exit is a broken installation, and
    # output with no number in it is a tool that is not the tool it was taken
    # for. Reporting all three as "would not report a version" sent every one of
    # them to the same place, which was nowhere.
    if ($result.timedOut) {
        return [pscustomobject]@{
            version = ""; deadlineReached = [bool]$budget.boundedByDeadline
            reason = "it did not answer within $($budget.seconds)s"
        }
    }
    if ($result.exitCode -ne 0) {
        $output = (("$([string]$result.standardError) $([string]$result.standardOutput)").Trim() -replace "\s+", " ")
        if ($output.Length -gt 200) { $output = $output.Substring(0, 200) + "..." }
        return [pscustomobject]@{
            version = ""; deadlineReached = $false
            reason = ("it exited with code $($result.exitCode)" +
                $(if ($output) { " and said: $output" } else { " and said nothing" }))
        }
    }
    # A tool that prints a banner before its version is common enough that the
    # first number in the output is a safer reading than the first line.
    $text = [string]$result.standardOutput
    if ([string]::IsNullOrWhiteSpace($text)) { $text = [string]$result.standardError }
    if ($text -match "(\d+(?:\.\d+)*)") {
        return [pscustomobject]@{ version = [string]$Matches[1]; deadlineReached = $false; reason = "" }
    }
    return [pscustomobject]@{
        version = ""; deadlineReached = $false
        reason = "it printed no version number"
    }
}

foreach ($tool in $requiredTools) {
    $expected = [string]$tool.expectedVersion
    $comparison = [string]$tool.match
    if ([string]::IsNullOrWhiteSpace($comparison)) { $comparison = "exact" }
    if ($comparison -eq "none" -or [string]::IsNullOrWhiteSpace($expected)) { continue }

    $arguments = @("--version")
    if ($null -ne $tool.PSObject.Properties["versionArguments"] -and
        @($tool.versionArguments).Count -gt 0) {
        $arguments = @($tool.versionArguments)
    }
    $probe = Get-ToolVersion -Path $toolPaths[[string]$tool.key] -Arguments $arguments
    if ($probe.deadlineReached) {
        return New-Failure -Detail "No time is left in this leg to resolve dependencies." -DeadlineReached
    }
    $label = [string]$tool.label
    if ([string]::IsNullOrWhiteSpace($label)) { $label = [string]$tool.command }
    if ([string]::IsNullOrWhiteSpace($probe.version)) {
        $because = [string]$probe.reason
        if ([string]::IsNullOrWhiteSpace($because)) { $because = "it would not report a version" }
        return New-Failure -InfrastructureUnavailable -Detail (
            "This agent's '$([string]$tool.command)' cannot be confirmed as the $label the decision " +
            "was settled on, because $because.")
    }
    if ($comparison -eq "major") {
        $expectedMajor = 0
        $actualMajor = -1
        if ($expected -match "^(\d+)") { $expectedMajor = [int]$Matches[1] }
        if ($probe.version -match "^(\d+)") { $actualMajor = [int]$Matches[1] }
        if ($actualMajor -ne $expectedMajor) {
            return New-Failure -InfrastructureUnavailable -Detail (
                "This agent runs $label $($probe.version), but the decision was settled on $label $expectedMajor.x.")
        }
    }
    elseif ($comparison -eq "minor") {
        # Some runtimes are only ever named to two segments - Go and Python both
        # are - and their third segment is a patch nobody pinned. Comparing all
        # three would refuse an agent that is running exactly what was asked for.
        $normalise = {
            param([string]$Value)
            $segments = @(([string]$Value) -split "\.")
            if ($segments.Count -ge 2) { return "$($segments[0]).$($segments[1])" }
            return [string]$Value
        }
        if ((& $normalise $probe.version) -ne (& $normalise $expected)) {
            return New-Failure -InfrastructureUnavailable -Detail (
                "This agent runs $label $($probe.version), but the decision was settled on $label $expected.")
        }
    }
    elseif ($probe.version -ne $expected) {
        return New-Failure -InfrastructureUnavailable -Detail (
            "This agent runs $label $($probe.version), but the decision was settled on $label $expected.")
    }
}

# The manifest a model wrote never reaches the resolver. This one is built from
# the locked toolchain alone, so whatever the model put in its own manifest
# cannot change what gets installed.
$manifestContent = & $adapter.NewManifestContent $Toolchain $ManifestName $ManifestVersion
# The adapter names the file, because an ecosystem whose manifest is named after
# its project has no constant to read. The answer is checked before it is joined
# to a path: the project name it is derived from came from a model, and a name
# carrying a separator would write the manifest somewhere other than the project.
$manifestFileName = [string](& $adapter.GetManifestFileName $ManifestName)
if ([string]::IsNullOrWhiteSpace($manifestFileName) -or
    $manifestFileName -match "[\\/]" -or $manifestFileName -match "^\.\.?$") {
    return New-Failure -Detail ("The $([string]$adapter.id) adapter named '$manifestFileName' as its " +
        "manifest file, which is not a file name inside the project.")
}
$manifestPath = Join-Path $projectRoot $manifestFileName
$manifestDirectory = Split-Path $manifestPath -Parent
if (-not (Test-Path $manifestDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
}
Set-Content -LiteralPath $manifestPath -Value $manifestContent -Encoding utf8 -NoNewline

# Most package managers read user and machine configuration unless they are
# pointed at empty files, and an inherited one could redirect the feed or add a
# credential. The adapter names the files its tooling would otherwise read.
$configFiles = @{}
$neutralFiles = @()
if ($null -ne $adapter.PSObject.Properties["NewNeutralConfigFiles"]) {
    $neutralFiles = @(& $adapter.NewNeutralConfigFiles $Toolchain $WorkRoot)
}
foreach ($file in $neutralFiles) {
    $path = [string]$file.path
    if (-not [IO.Path]::IsPathRooted($path)) { $path = Join-Path $WorkRoot $path }
    $directory = Split-Path $path -Parent
    if ($directory -and -not (Test-Path $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    Set-Content -LiteralPath $path -Value ([string]$file.content) -Encoding utf8 -NoNewline
    $configFiles[[string]$file.key] = $path
}

$context = [pscustomobject][ordered]@{
    workRoot = $WorkRoot
    projectRoot = $projectRoot
    homeRoot = $homeRoot
    cacheRoot = $cacheRoot
    tempRoot = $tempRoot
    toolPaths = $toolPaths
    configFiles = $configFiles
    manifestPath = $manifestPath
}

$invocation = & $adapter.GetResolveCommand $Toolchain $context
# An ecosystem whose resolution takes more than one step says so by returning a
# list. Maven is the case that forces it: nothing it ships writes a lock, so the
# dependencies are fetched first and the lock is written from what arrived.
$invocationKeys = @($invocation.PSObject.Properties | ForEach-Object { $_.Name })
$steps = @()
if ($invocationKeys -contains "commands") { $steps = @($invocation.commands) }
else { $steps = @($invocation) }
if ($steps.Count -eq 0) {
    return New-Failure -Detail "The $($adapter.displayName) adapter named no resolver command to run."
}

$duration = 0
$exitCode = 0
foreach ($step in $steps) {
    $stepKeys = @($step.PSObject.Properties | ForEach-Object { $_.Name })
    $executable = ""
    if ($stepKeys -contains "executable") { $executable = [string]$step.executable }
    if ([string]::IsNullOrWhiteSpace($executable) -and $stepKeys -contains "toolKey") {
        $executable = [string]$toolPaths[[string]$step.toolKey]
    }
    if ([string]::IsNullOrWhiteSpace($executable)) {
        return New-Failure -Detail "The $($adapter.displayName) adapter named no resolver executable to run."
    }

    $environment = @{}
    if ($stepKeys -contains "environment" -and $null -ne $step.environment) {
        foreach ($name in @(($step.environment).Keys)) {
            $environment[[string]$name] = [string]($step.environment)[$name]
        }
    }

    $budget = Get-BudgetedTimeout -Ceiling $script:ResolverCeilingSeconds
    if ($budget.seconds -le 0) {
        return New-Failure -Detail "No time is left in this leg to resolve dependencies." -DeadlineReached
    }

    $startInfo = New-IsolatedStartInfo -FileName $executable -Arguments @($step.arguments) `
        -WorkingDirectory $projectRoot -Environment $environment
    $result = Invoke-IsolatedProcess -StartInfo $startInfo -TimeoutSeconds $budget.seconds
    $duration += $result.durationSeconds
    if ($result.timedOut) {
        # Hitting a deadline-derived timeout means the leg ran out of time;
        # hitting the standing ceiling means the resolver itself is stuck. Only
        # the first is a handover.
        if ($budget.boundedByDeadline) {
            return New-Failure -Detail "The leg ran out of time while the resolver was working." `
                -Duration $duration -DeadlineReached
        }
        return New-Failure -Detail "The resolver did not finish within $($budget.seconds) second(s)." `
            -Duration $duration
    }

    $exitCode = $result.exitCode
    if ($exitCode -ne 0) {
        $standardError = [string]$result.standardError
        if ([string]::IsNullOrWhiteSpace($standardError)) { $standardError = [string]$result.standardOutput }
        $trimmed = ([string]$standardError).Trim()
        if ($trimmed.Length -gt 600) { $trimmed = $trimmed.Substring(0, 600) }
        $detail = if ([string]::IsNullOrWhiteSpace($trimmed)) {
            "The resolver exited with code $exitCode."
        }
        else {
            "The resolver exited with code $exitCode : $trimmed"
        }
        # A feed that cannot be reached is not a bad decision, and sending one
        # back for redesign would replace a sound choice over a network problem.
        $unreachable = $standardError -match ("(?i)ENOTFOUND|ECONNREFUSED|ETIMEDOUT|EAI_AGAIN|getaddrinfo|" +
            "could not resolve host|unable to access|network is unreachable|proxy|" +
            "unable to load the service index|\b(401|403|502|503)\b|transfer failed|connection timed out")
        if ($unreachable) {
            return New-Failure -InfrastructureUnavailable -Detail $detail -ExitCode $exitCode -Duration $duration
        }
        return New-Failure -Detail $detail -ExitCode $exitCode -Duration $duration
    }
}

$lockPath = Join-Path $projectRoot ([string]$adapter.lockFileName)
# An ecosystem with no lock file of its own writes one here, from the artefacts
# its tooling actually fetched. Doing it after the commands rather than instead
# of them means the file describes a resolution that really happened.
if (-not (Test-Path $lockPath -PathType Leaf) -and
    $null -ne $adapter.PSObject.Properties["NewLockFromWorkspace"]) {
    try { $synthesised = [string](& $adapter.NewLockFromWorkspace $Toolchain $context) }
    catch {
        return New-Failure -Detail ("The resolver finished but no lock could be written from what it " +
            "produced: $($_.Exception.Message)") -ExitCode $exitCode -Duration $duration
    }
    if (-not [string]::IsNullOrWhiteSpace($synthesised)) {
        Set-Content -LiteralPath $lockPath -Value $synthesised -Encoding utf8 -NoNewline
    }
}

if (-not (Test-Path $lockPath -PathType Leaf)) {
    return New-Failure -Detail "The resolver reported success but produced no $([string]$adapter.lockFileName)." `
        -ExitCode $exitCode -Duration $duration
}

if ($BuildProbe) {
    # Prove a minimal project works before inventory generation. These files are
    # deterministic and live only in the resolver's isolated scratch directory.
    $probeSteps = @()
    if ($ecosystem -eq 'nuget') {
        'internal static class FoundryProbe { public static int Value => 1; }' |
            Set-Content -LiteralPath (Join-Path $projectRoot 'FoundryProbe.cs') -Encoding utf8
        $probeSteps = @([pscustomobject]@{
            key = 'dotnet'; arguments = @('build', '--no-restore', '--configuration', 'Release', "/p:RestorePackagesPath=$cacheRoot")
            environment = @{ NUGET_PACKAGES = $cacheRoot; DOTNET_CLI_TELEMETRY_OPTOUT = '1'; DOTNET_NOLOGO = '1' }
        })
    }
    elseif ($ecosystem -eq 'npm') {
        "if (1 + 1 !== 2) process.exit(1); console.log('Foundry runtime probe passed');" |
            Set-Content -LiteralPath (Join-Path $projectRoot 'foundry-probe.mjs') -Encoding utf8
        $probeSteps = @(
            [pscustomobject]@{key='npm';arguments=@('ci','--ignore-scripts','--no-audit','--no-fund');environment=@{}},
            [pscustomobject]@{key='node';arguments=@('foundry-probe.mjs');environment=@{}}
        )
    }
    else { return New-Failure -Detail "No minimal build probe is implemented for $ecosystem." }
    foreach ($step in $probeSteps) {
        $budget = Get-BudgetedTimeout -Ceiling 180
        if ($budget.seconds -le 0) { return New-Failure -DeadlineReached -Detail 'No leg time remains for the minimal build probe.' }
        $startInfo = New-IsolatedStartInfo -FileName $toolPaths[$step.key] -Arguments $step.arguments `
            -WorkingDirectory $projectRoot -Environment $step.environment
        $probe = Invoke-IsolatedProcess -StartInfo $startInfo -TimeoutSeconds $budget.seconds
        $duration += $probe.durationSeconds
        if ($probe.timedOut) {
            if ($budget.boundedByDeadline) { return New-Failure -DeadlineReached -Detail 'The minimal build probe reached the leg deadline.' }
            return New-Failure -InfrastructureUnavailable -Detail 'The minimal build probe exceeded its 180 second limit.'
        }
        if ($probe.exitCode -ne 0) {
            $detail = "$($probe.standardOutput) $($probe.standardError)".Trim()
            $unreachable = $detail -match '(?i)ENOTFOUND|ECONNREFUSED|ETIMEDOUT|EAI_AGAIN|getaddrinfo|could not resolve host|network is unreachable|unable to load the service index|\b(401|403|502|503)\b'
            if ($detail.Length -gt 1600) { $detail = $detail.Substring($detail.Length - 1600) }
            return New-Failure -Detail "Minimal $ecosystem project failed: $detail" -ExitCode $probe.exitCode -InfrastructureUnavailable:$unreachable
        }
    }
}

return [pscustomobject][ordered]@{
    succeeded = $true
    detail = ("Resolved $(@($Toolchain.packages).Count) approved package(s) against " +
        "$([string]$Toolchain.source.registry) with $($adapter.displayName).")
    exitCode = $exitCode
    durationSeconds = $duration
    deadlineReached = $false
    infrastructureUnavailable = $false
    lockJson = (Get-Content -LiteralPath $lockPath -Raw)
}
