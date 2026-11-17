[CmdletBinding()]
param(
    # The resolved change set, not the plan. Verification runs the bytes that
    # will be committed; anything else proves a different framework works.
    [Parameter(Mandatory)][string]$ChangeSetPath,
    [Parameter(Mandatory)][string]$ToolchainLockPath,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$StageId,
    [Parameter(Mandatory)][string]$OutputPath,
    # Where the change set is laid out and executed. Outside the run directory:
    # a node_modules tree or an obj folder inside the run becomes context for
    # every later agent and an artifact the run-artifact check has no schema for.
    [Parameter(Mandatory)][string]$WorkRoot,
    [string]$PipeDirectory = '',
    # A test seam, not a configuration knob. Given a command it returns an exit
    # code and the output. Nothing in a workflow file may choose it, or "the
    # framework was proved to run" would mean whatever the workflow wanted it to
    # mean.
    [AllowNull()][scriptblock]$CommandRunner = $null,
    [AllowNull()][scriptblock]$ContainerRemover = $null,
    # A rehearsal installs nothing and executes nothing. Verification is the one
    # stage that reaches a package registry and then runs code that was written
    # minutes earlier, so it is gated the same way every other side effect in a
    # rehearsal is, and it says plainly that it proved nothing rather than
    # reporting a framework as verified.
    [switch]$DryRun,
    [switch]$DeferExecution,
    [AllowNull()][object]$Deadline = $null,
    # How the code an agent wrote minutes ago is kept away from this run. The
    # environment can be built rather than inherited whatever this says; what it
    # decides is whether the child also gets an identity and a file system of its
    # own. Passed in rather than read here so the one place that reads
    # configuration stays the one place that reads configuration.
    [AllowNull()][object]$Isolation = $null
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../Common.ps1")
. (Join-Path $PSScriptRoot '../ProductDefects.ps1')
$schemaRoot = (Resolve-Path (Join-Path $PSScriptRoot "../../schemas")).Path

$findings = [System.Collections.Generic.List[object]]::new()
$projects = [System.Collections.Generic.List[object]]::new()
$commandLogs = [System.Collections.Generic.List[string]]::new()
$lastCommandLog = ''

function Save-VerificationCommandOutput {
    param([string]$Text)
    $directory = Join-Path (Split-Path $OutputPath -Parent) 'commands'
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $name = 'command-{0:d3}.log' -f ($commandLogs.Count + 1)
    $path = Join-Path $directory $name
    Set-Content -LiteralPath $path -Value $Text -Encoding utf8 -NoNewline
    $commandLogs.Add($path)
    return "Full output: commands/$name [sha256: $((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant())]"
}

# What isolating the child actually amounts to on this run, settled once and
# written into the evidence. Emptying the environment closes the paths a package
# manager takes by default; it does not change who the child runs as. Saying so
# in the artifact rather than in a source comment is what lets a reader of the
# evidence - or a policy that reads it - know which of the two happened.
$containerMountPath = $script:QaFoundryContainerMountPath
function Resolve-VerificationIsolation {
    return Resolve-QaFoundryExecutionIsolation -Isolation $Isolation -Subject "Verification" `
        -ConfigurationKey "automation.isolation"
}
$isolation = Resolve-VerificationIsolation

function Add-Finding {
    param([string]$Severity, [string]$Message, [string]$ProjectPath = "")

    $finding = [ordered]@{ severity = $Severity; message = $Message }
    if (-not [string]::IsNullOrWhiteSpace($ProjectPath)) { $finding["projectPath"] = $ProjectPath }
    $findings.Add($finding)
}

# Everything a step can say about itself, in one shape, so a caller reading the
# evidence does not have to know which step produced which fields.
function New-Step {
    param(
        [string]$Name,
        [string]$Status,
        [int]$ExitCode = 0,
        [int]$DurationMs = 0,
        [string]$Command = "",
        [string]$Detail = ""
    )

    $step = [ordered]@{
        name = $Name
        status = $Status
        exitCode = $ExitCode
        durationMs = $DurationMs
        detail = if ($Command -and $Status -eq 'failed' -and $lastCommandLog) {
            "$Detail`n$lastCommandLog"
        } else { $Detail }
    }
    if (-not [string]::IsNullOrWhiteSpace($Command)) { $step["command"] = $Command }
    return $step
}

# A feed that did not answer, an SDK the agent does not have and a proxy that
# refused are not defects in the chosen technology. Sending the design back to be
# redesigned over one of them spends the repair budget on a decision that was
# never wrong, and the second attempt fails identically.
$script:InfrastructureMarkers = @(
    "ENOTFOUND", "EAI_AGAIN", "ETIMEDOUT", "ECONNRESET", "ECONNREFUSED",
    "ERR_SOCKET_TIMEOUT", "network is unreachable", "Temporary failure in name resolution",
    "407 Proxy Authentication Required", "503 Service Unavailable", "504 Gateway",
    "Unable to load the service index", "The SSL connection could not be established",
    "No such host is known", "getaddrinfo",
    # A tool that is absent is the plainest case of all, and the one this stage
    # met most often: without it the same design is sent back three times and
    # the run blocks on a verdict about a technology that was never exercised.
    "is not installed on this agent", "could not be started:"
)

function Test-InfrastructureFailure {
    param([string]$Output)

    # A package-manager-installed runner cannot be repaired by rewriting tests.
    if ($Output -match '(?im)node_modules[/\\]\.bin[/\\][^\r\n]*Permission denied') { return $true }
    foreach ($marker in $script:InfrastructureMarkers) {
        if ([string]$Output -like "*$marker*") { return $true }
    }
    return $false
}

# Adapters read their runtime block by key, and a lock read back from JSON is a
# property bag rather than a map. Converting here keeps the adapters written
# against one shape instead of two.
function ConvertTo-RuntimeMap {
    param([AllowNull()]$Runtime)

    $map = @{}
    if ($null -eq $Runtime) { return $map }
    foreach ($key in @(Get-QaFoundryPropertyNames -InputObject $Runtime)) {
        $map[$key] = $Runtime.$key
    }
    return $map
}

# Enough of a failed command's output to act on. The whole log would be several
# hundred kilobytes of restore chatter, and a stage artifact that large becomes
# context for every agent after it.
function Get-FailureTail {
    param([string]$Text, [int]$MaxLength = 2000)

    $trimmed = ([string]$Text).Trim()
    if ($trimmed.Length -le $MaxLength) { return $trimmed }
    return "..." + $trimmed.Substring($trimmed.Length - $MaxLength)
}

# A verification command may install a whole SDK's worth of packages, so it is
# given room; but never so much that the leg loses the time it needs to write
# what it learned and hand over. Mirrors the resolver's budget exactly.
$script:HandoverReserveSeconds = 120
$script:VerificationCeilingSeconds = 1800

function Get-VerificationTimeoutSeconds {
    $timeout = $script:VerificationCeilingSeconds
    if ($null -ne $Deadline) {
        $remaining = [int](([datetime]$Deadline).ToUniversalTime() - [datetime]::UtcNow).TotalSeconds
        $usable = $remaining - $script:HandoverReserveSeconds
        if ($usable -lt $timeout) { $timeout = $usable }
    }
    return $timeout
}

# The one place in this runtime that runs code an agent wrote minutes ago, and
# the packages that code depends on. A child that inherits this process's
# environment inherits the run's Azure DevOps and GitHub credentials with it, so
# a generated test - or a dependency's install script - could reach the very
# repositories and boards this run is waiting for a human to approve. The
# environment is therefore built rather than inherited: the platform variables a
# compiler genuinely needs, a home and a temp directory of its own, and nothing
# else. Anything an ecosystem needs beyond that it must name.
function Set-VerificationEnvironment {
    param(
        [Parameter(Mandatory)][System.Diagnostics.ProcessStartInfo]$StartInfo,
        [Parameter(Mandatory)][object]$Command
    )

    # A home of its own, not the agent's, and the same one every other
    # untrusted command in this programme is given. What it closes and what it
    # cannot close is written out in Set-QaFoundryIsolatedEnvironment.
    $commandEnvironment = if (@(Get-QaFoundryPropertyNames -InputObject $Command) -contains "environment") {
        $Command.environment
    } else { $null }
    Set-QaFoundryIsolatedEnvironment -StartInfo $StartInfo `
        -IsolationHome (Join-Path $WorkRoot ".verification-home") `
        -CommandEnvironment $commandEnvironment
    if ('executable' -in @(Get-QaFoundryPropertyNames -InputObject $Command) -and [string]$Command.executable -eq 'dotnet') {
        # A verification directory is disposable. Compiler/build servers must
        # not outlive the command and keep its assemblies locked on Windows.
        $StartInfo.EnvironmentVariables['UseSharedCompilation'] = 'false'
        $StartInfo.EnvironmentVariables['MSBUILDDISABLENODEREUSE'] = '1'
        $StartInfo.EnvironmentVariables['DOTNET_CLI_USE_MSBUILD_SERVER'] = '0'
        if (-not $IsWindows) {
            if ($isolation.mode -eq 'container') {
                $StartInfo.EnvironmentVariables['TESTINGPLATFORM_PIPE_DIRECTORY'] = '/tmp'
            }
            elseif ($PipeDirectory) {
                $StartInfo.EnvironmentVariables['TESTINGPLATFORM_PIPE_DIRECTORY'] = $PipeDirectory
            }
        }
    }
}

function ConvertTo-ContainerEnvironmentValue {
    param([AllowNull()][string]$Value)

    return ConvertTo-QaFoundryContainerEnvironmentValue -Value $Value -HostRoot $WorkRoot `
        -MountPath $containerMountPath
}

function Remove-VerificationContainer {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Name)

    return Remove-QaFoundryIsolationContainer -Name $Name `
        -Runtime ([string]$isolation.executable) -WorkingDirectory $WorkRoot `
        -Remover $ContainerRemover
}

function Invoke-VerificationCommand {
    param(
        [Parameter(Mandatory)][object]$Command,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    # Compared through the shared helper rather than against Get-Date. The
    # deadline is built as UTC and Get-Date answers local time, so on any agent
    # east of Greenwich the comparison read as "already past" and this stage
    # refused to run a single command - on a UTC agent it happened to work.
    if (Test-QaFoundryBudgetExhausted -Deadline $Deadline) {
        throw "The stage deadline passed before '$([string]$Command.executable)' could be run."
    }
    $arguments = @(@($Command.arguments) | ForEach-Object { [string]$_ })
    $containerName = ""
    if ($isolation.mode -eq "container") {
        # The command is not changed, only where it runs. The work root is the
        # single mount: the checkout this run was started from, the agent's
        # profile and every credential file on the machine are outside it, so
        # generated code cannot reach them by absolute path either.
        $containerEnvironment = [System.Diagnostics.ProcessStartInfo]::new()
        Set-VerificationEnvironment -StartInfo $containerEnvironment -Command $Command
        $invocation = New-QaFoundryContainerInvocation -Isolation $isolation `
            -HostRoot $WorkRoot -WorkingDirectory $WorkingDirectory `
            -Executable ([string]$Command.executable) -Arguments $arguments `
            -BuiltEnvironment $containerEnvironment -NamePrefix "qa-foundry-verify" `
            -MountPath $containerMountPath
        $containerName = [string]$invocation.containerName
        $Command = [pscustomobject]@{
            executable = [string]$invocation.executable
            arguments = @($invocation.arguments)
            environment = $invocation.clientEnvironment
        }
        $arguments = @($invocation.arguments)
        $WorkingDirectory = $WorkRoot
    }
    if ($null -ne $CommandRunner) {
        $outcome = & $CommandRunner $([string]$Command.executable) $arguments $WorkingDirectory
        return [pscustomobject]@{
            exitCode = [int]$outcome.exitCode
            output = [string]$outcome.output
            durationMs = if ((Get-QaFoundryPropertyNames -InputObject $outcome) -contains "durationMs") {
                [int]$outcome.durationMs
            }
            else { 0 }
        }
    }

    $started = Get-Date
    # A name is resolved to a path the operating system will actually start.
    # 'npm' on Windows is a shell script next to npm.cmd, and asking the process
    # API for it by name fails with "not a valid Win32 application" — which this
    # stage would otherwise report as the chosen framework being broken.
    $executable = Resolve-QaFoundryExecutablePath -Name ([string]$Command.executable)
    if ([string]::IsNullOrWhiteSpace($executable)) {
        return [pscustomobject]@{
            exitCode = 127
            output = ("The command '$([string]$Command.executable)' is not installed on this agent, " +
                "so the framework could not be exercised here.")
            durationMs = 0
        }
    }

    # The deadline used to be read once before the child started and never
    # again. A test runner that hangs - waiting on a browser that never opens is
    # the ordinary way it happens - then held the leg past the point where it
    # could save what it knew, and the whole run was lost rather than resumed.
    $timeoutSeconds = Get-VerificationTimeoutSeconds
    if ($timeoutSeconds -le 0) {
        throw "The stage deadline passed before '$([string]$Command.executable)' could be run."
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $executable
    foreach ($argument in $arguments) { $startInfo.ArgumentList.Add([string]$argument) }
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    Set-VerificationEnvironment -StartInfo $startInfo -Command $Command

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try { $null = $process.Start() }
    catch {
        # A missing executable throws rather than exiting non-zero, and it is the
        # single most common way this stage meets an agent that simply does not
        # have the SDK. Reported as output so the infrastructure test can see it.
        $process.Dispose()
        return [pscustomobject]@{
            exitCode = 127
            output = "The command '$([string]$Command.executable)' could not be started: $($_.Exception.Message)"
            durationMs = [int]((Get-Date) - $started).TotalMilliseconds
        }
    }
    try {
        # Read both streams while the process runs. A child that fills a pipe
        # nobody is draining blocks on the write and never exits, which reads
        # from here as a hang in the framework rather than in this loop.
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($timeoutSeconds * 1000)) {
            # The whole tree: a test runner's browsers and language servers are
            # children, and killing only the parent leaves them holding the
            # work directory the next attempt is about to use.
            try { $process.Kill($true) } catch { }
            $removal = Remove-VerificationContainer -Name $containerName
            if (-not $process.WaitForExit(30 * 1000)) {
                throw ("'$([string]$Command.executable)' did not stop after being killed, so this " +
                    "agent is no longer in a known state.$removal")
            }
            return [pscustomobject]@{
                exitCode = 124
                output = ("'$([string]$Command.executable)' was still running after $timeoutSeconds " +
                    "second(s) and was stopped, so the framework has not been proved to run here." +
                    $removal)
                durationMs = [int]((Get-Date) - $started).TotalMilliseconds
            }
        }
        return [pscustomobject]@{
            exitCode = [int]$process.ExitCode
            output = ([string]$outputTask.Result + [string]$errorTask.Result)
            durationMs = [int]((Get-Date) - $started).TotalMilliseconds
        }
    }
    finally {
        $process.Dispose()
    }
}

function Write-Verification {
    param([string]$Outcome)

    $document = [ordered]@{
        runId = $RunId
        stageId = $StageId
        verifiedAt = (Get-Date).ToUniversalTime().ToString("o")
        outcome = $Outcome
        isolation = [ordered]@{
            mode = [string]$isolation.mode
            detail = [string]$isolation.detail
            limitations = @($isolation.limitations)
        }
        projects = @($projects)
        findings = @($findings)
    }
    New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force | Out-Null
    $document | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $OutputPath -Encoding utf8 -NoNewline
    $null = & (Join-Path $PSScriptRoot "../Validate-JsonArtifact.ps1") -ArtifactPath $OutputPath `
        -SchemaPath (Join-Path $schemaRoot "runtime/framework-verification.schema.json") `
        -SchemaRoot $schemaRoot
}

# Three verdicts, because they need three different answers. A verified run goes
# on; a defect in the chosen technology goes back to be repaired within the
# stage's iteration budget; an agent that could not reach what it needed stops
# the run instead of redesigning around a problem that is not in the design.
function New-Result {
    param([string]$Outcome)

    Write-Verification -Outcome $Outcome
    $status = switch ($Outcome) {
        "verified" { "completed" }
        "toolchain_defect" { "revision_required" }
        default { "blocked" }
    }
    # A rehearsal did not attempt the proof, and that is not the run failing.
    # The artifact still says not_attempted, so nothing downstream can mistake
    # this for a framework that was executed.
    if ($DryRun -or ($DeferExecution -and $Outcome -eq 'not_attempted' -and
        @($findings | Where-Object severity -EQ 'error').Count -eq 0)) { $status = "completed" }
    return [pscustomobject][ordered]@{
        runId = $RunId
        stageId = $StageId
        handler = "verify_framework"
        status = $status
        dryRun = [bool]$DryRun
        actions = @()
        evidence = @($OutputPath) + @($commandLogs)
    }
}

foreach ($required in @($ChangeSetPath, $ToolchainLockPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        Add-Finding -Severity "error" -Message "Verification input does not exist: $required"
        return (New-Result -Outcome "not_attempted")
    }
}

$null = & (Join-Path $PSScriptRoot "../Validate-JsonArtifact.ps1") -ArtifactPath $ChangeSetPath `
    -SchemaPath (Join-Path $schemaRoot "actions/change-set.schema.json") -SchemaRoot $schemaRoot
$null = & (Join-Path $PSScriptRoot "../Validate-JsonArtifact.ps1") -ArtifactPath $ToolchainLockPath `
    -SchemaPath (Join-Path $schemaRoot "runtime/toolchain-lock.schema.json") -SchemaRoot $schemaRoot

$changeSet = Get-Content -LiteralPath $ChangeSetPath -Raw | ConvertFrom-Json -Depth 100
$lock = Get-Content -LiteralPath $ToolchainLockPath -Raw | ConvertFrom-Json -Depth 100

if ([string]$changeSet.runId -ne $RunId -or [string]$lock.runId -ne $RunId) {
    Add-Finding -Severity "error" -Message (
        "The change set and the toolchain lock must belong to run '$RunId', but they name " +
        "'$([string]$changeSet.runId)' and '$([string]$lock.runId)'.")
    return (New-Result -Outcome "not_attempted")
}

if ($DryRun) {
    Add-Finding -Severity "info" -Message (
        "This is a rehearsal: the framework was neither installed nor executed, so nothing here " +
        "says whether the chosen technology works. A run that is allowed to install and execute " +
        "is what proves that.")
    return (New-Result -Outcome "not_attempted")
}

$changes = @(@($changeSet.changes) | Where-Object { $null -ne $_ -and [string]$_.operation -ne "delete" })
if ($changes.Count -eq 0) {
    Add-Finding -Severity "error" -Message (
        "The change set writes no files, so there is no framework to verify. A run that reaches " +
        "verification with nothing to run has failed earlier and hidden it.")
    return (New-Result -Outcome "not_attempted")
}

if ($DeferExecution) {
    Add-Finding -Severity 'info' -Message (
        'Bootstrap generation only: framework execution, tests and negative probes were not attempted. ' +
        'Credentials and test execution will be configured after delivery. No passing tests or measured coverage are claimed.')
    return (New-Result -Outcome 'not_attempted')
}

# The layout is rebuilt from the change set rather than from a checkout, because
# a checkout would also carry the product's own build - and automation that only
# works when the product's build is present is automation that fails on the first
# agent that shallow-clones.
New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null
foreach ($change in $changes) {
    $relative = ([string]$change.path).Replace("\", "/")
    if ($relative -match "(^|/)\.\.(/|$)" -or [IO.Path]::IsPathRooted($relative)) {
        Add-Finding -Severity "error" -Message "The change set names a path outside the change set root: $relative"
        return (New-Result -Outcome "not_attempted")
    }
    $target = Join-Path $WorkRoot $relative
    New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null
    Set-Content -LiteralPath $target -Value ([string]$change.content) -Encoding utf8 -NoNewline
}

# Every locked toolchain, not one per ecosystem. Two decisions can share an
# ecosystem - one npm project on Playwright and another on Vitest is the
# ordinary case - and keeping only the first meant the second was never
# installed, never run, and reported as verified under the first one's id.
$toolchainsById = [ordered]@{}
$adaptersByEcosystem = [ordered]@{}
foreach ($toolchain in @($lock.toolchains)) {
    $toolchainId = [string]$toolchain.id
    if ($toolchainsById.Contains($toolchainId)) {
        Add-Finding -Severity "error" -Message (
            "The toolchain lock names '$toolchainId' more than once, so a manifest attributed to it " +
            "could be verified against either decision.")
        return (New-Result -Outcome "toolchain_defect")
    }
    $ecosystem = [string]$toolchain.ecosystem
    if (-not $adaptersByEcosystem.Contains($ecosystem)) {
        try { $adaptersByEcosystem[$ecosystem] = Get-QaFoundryEcosystemAdapter -Ecosystem $ecosystem }
        catch {
            Add-Finding -Severity "error" -Message $_.Exception.Message
            return (New-Result -Outcome "toolchain_defect")
        }
    }
    $toolchainsById[$toolchainId] = $toolchain
}

# The change set says which toolchain each manifest was materialised from. It is
# read rather than guessed at: the alternative is matching by ecosystem, which
# cannot tell two decisions in one ecosystem apart.
$declaredMaterializations = @()
$detailNames = @(Get-QaFoundryPropertyNames -InputObject $changeSet.details)
if ($detailNames -contains "materializations") {
    $declaredMaterializations = @($changeSet.details.materializations)
}
if ($declaredMaterializations.Count -eq 0) {
    Add-Finding -Severity "error" -Message (
        "The change set does not say which locked toolchain each manifest belongs to, so no manifest " +
        "here can be installed against the decision it was resolved from.")
    return (New-Result -Outcome "toolchain_defect")
}

$manifests = [System.Collections.Generic.List[object]]::new()
$claimedManifestPaths = [ordered]@{}
$coveredToolchainIds = [ordered]@{}
$changePaths = [ordered]@{}
foreach ($change in $changes) { $changePaths[(([string]$change.path).Replace("\", "/"))] = $true }

foreach ($materialization in $declaredMaterializations) {
    $toolchainId = [string]$materialization.toolchainId
    if (-not $toolchainsById.Contains($toolchainId)) {
        Add-Finding -Severity "error" -Message (
            "The change set attributes '$([string]$materialization.manifestPath)' to toolchain " +
            "'$toolchainId', which the lock for this run does not contain.")
        return (New-Result -Outcome "toolchain_defect")
    }
    $relative = ([string]$materialization.manifestPath).Replace("\", "/")
    if (-not $changePaths.Contains($relative)) {
        Add-Finding -Severity "error" -Message (
            "The change set names '$relative' as a materialised manifest and does not carry it, so " +
            "there is nothing at that path to install.")
        return (New-Result -Outcome "toolchain_defect")
    }
    if ($claimedManifestPaths.Contains($relative)) {
        Add-Finding -Severity "error" -Message (
            "Two materialisations claim the manifest '$relative', so it has no single toolchain to " +
            "be verified against.")
        return (New-Result -Outcome "toolchain_defect")
    }
    $claimedManifestPaths[$relative] = $true
    $toolchain = $toolchainsById[$toolchainId]
    $coveredToolchainIds[$toolchainId] = $true
    $manifests.Add([pscustomobject]@{
        ecosystem = [string]$toolchain.ecosystem
        adapter = $adaptersByEcosystem[[string]$toolchain.ecosystem]
        toolchain = $toolchain
        manifestPath = $relative
        # Repository-relative and forward-slashed, because this string lands
        # in a finding a reviewer reads and in an artifact another stage
        # matches against paths that came out of git.
        projectPath = ((Split-Path $relative -Parent) -replace "\\", "/")
    })
}

# A decision nobody materialised is a decision nothing proves. Reporting the run
# as verified while a locked toolchain was never installed is the reading this
# stage exists to prevent.
$uncoveredToolchains = @($toolchainsById.Keys | Where-Object { -not $coveredToolchainIds.Contains($_) })
if ($uncoveredToolchains.Count -gt 0) {
    Add-Finding -Severity "error" -Message (
        "The change set materialises nothing for locked toolchain(s) " +
        "$((@($uncoveredToolchains) | Sort-Object) -join ', '), so those decisions are unproved.")
    return (New-Result -Outcome "toolchain_defect")
}

# A manifest that looks like one of the locked ecosystems' manifests and belongs
# to no materialisation would be installed by nothing and verified by nothing.
foreach ($relative in @($changePaths.Keys)) {
    if ($claimedManifestPaths.Contains($relative)) { continue }
    foreach ($ecosystem in @($adaptersByEcosystem.Keys)) {
        $pattern = [string]$adaptersByEcosystem[$ecosystem].manifestPattern
        if ([string]::IsNullOrWhiteSpace($pattern)) { continue }
        if ($relative -notmatch $pattern) { continue }
        Add-Finding -Severity "error" -Message (
            "The change set carries '$relative', which is a $ecosystem manifest, and attributes it " +
            "to no locked toolchain.")
        return (New-Result -Outcome "toolchain_defect")
    }
}

if ($manifests.Count -eq 0) {
    Add-Finding -Severity "error" -Message (
        "The change set contains no manifest for any locked ecosystem, so nothing in it can be " +
        "installed or run. The framework has not been verified.")
    return (New-Result -Outcome "toolchain_defect")
}

$overall = "verified"
foreach ($manifest in $manifests) {
    $adapter = $manifest.adapter
    $toolchain = $manifest.toolchain
    $runtime = ConvertTo-RuntimeMap -Runtime $toolchain.runtime
    $resolved = [pscustomobject]@{
        id = [string]$toolchain.id
        ecosystem = $manifest.ecosystem
        runtime = $runtime
        packages = @($toolchain.packages)
    }
    $projectDirectory = if ([string]::IsNullOrWhiteSpace($manifest.projectPath)) {
        $WorkRoot
    }
    else { Join-Path $WorkRoot $manifest.projectPath }

    $steps = [System.Collections.Generic.List[object]]::new()
    $outcome = "verified"
    $discovered = 0
    $failedTests = 0
    $baselineFailures = @()
    $probe = [ordered]@{ attempted = $false; failedAsExpected = $false; detail = "" }

    # The recorded toolchain already carries the canonical runtime block: the
    # config-to-canonical translation happened once, where the toolchain was
    # recorded. Translating a second time would look up snake_case config keys
    # in a camelCase object and read every pin as absent, which is how a run
    # ends up asking for "Node.js 0.x" and believing it checked something. What
    # is checked instead is that the block a resolver wrote still carries the
    # names this adapter's readers use.
    $missingRuntimeKeys = @(Get-QaFoundryCanonicalRuntimeKeys -Adapter $adapter |
        Where-Object { @($runtime.Keys) -cnotcontains $_ })
    if ($missingRuntimeKeys.Count -gt 0) {
        $detail = ("The recorded toolchain '$([string]$toolchain.id)' has no " +
            "$(($missingRuntimeKeys | Sort-Object) -join ', ') in its runtime block, so the " +
            "versions this framework was resolved against are unknown and running it here would " +
            "prove nothing about them.")
        $steps.Add((New-Step -Name "runtime" -Status "failed" -Detail $detail))
        Add-Finding -Severity "error" -ProjectPath $manifest.projectPath -Message (
            "$($manifest.projectPath): $detail")
        $probe["detail"] = "Not attempted: the framework did not reach a passing run."
        $steps.Add((New-Step -Name "negative_probe" -Status "skipped" -Detail ([string]$probe["detail"])))
        $projects.Add([ordered]@{
            toolchainId = [string]$toolchain.id
            ecosystem = $manifest.ecosystem
            manifestPath = $manifest.manifestPath
            projectPath = if ([string]::IsNullOrWhiteSpace($manifest.projectPath)) { "." }
            else { $manifest.projectPath }
            outcome = "toolchain_defect"
            steps = @($steps)
            testsDiscovered = 0
            testsFailed = 0
            negativeProbe = $probe
        })
        if ($overall -ne "infrastructure_unavailable") { $overall = "toolchain_defect" }
        continue
    }

    $requirements = @(& $adapter.GetRuntimeRequirements $resolved)
    $steps.Add((New-Step -Name "runtime" -Status "passed" -Detail (
        "Requires " + (@($requirements) -join "; "))))

    foreach ($phase in @(
            [pscustomobject]@{ name = "install"; factory = $adapter.GetInstallCommand },
            [pscustomobject]@{ name = "build"; factory = $adapter.GetBuildCommand },
            [pscustomobject]@{ name = "test"; factory = $adapter.GetTestCommand })) {
        if ($outcome -ne "verified") { break }
        $command = & $phase.factory $resolved $projectDirectory
        $run = Invoke-VerificationCommand -Command $command -WorkingDirectory $projectDirectory
        $lastCommandLog = Save-VerificationCommandOutput -Text ([string]$run.output)
        $rendered = "$([string]$command.executable) $((@($command.arguments) | ForEach-Object { [string]$_ }) -join ' ')"

        if ($phase.name -eq "test") {
            # Read through the shared verdict rather than here, so the rule the
            # bootstrap enforces and the rule the quality gate enforces cannot
            # drift apart. A rule applied only before the code is merged is a
            # rule that stops applying the moment it matters.
            $verdict = Get-QaFoundryTestRunVerdict -Ecosystem ([string]$adapter.id) `
                -Output ([string]$run.output) -ExitCode ([int]$run.exitCode)
            $discovered = [int]$verdict.total
            $failedTests = [int]$verdict.failed
            $skippedTests = [int]$verdict.skipped
            $executedTests = [int]$verdict.executed
            $baselineFailures = @(Get-QaFoundryFailedTestCases -Text ([string]$run.output) -ProjectPath $manifest.projectPath)
            # A runner exits zero when everything passed and when it found
            # nothing to run. Treating the second as success is how a framework
            # that discovers no tests is declared verified, which is the precise
            # failure this stage exists to catch.
            if ([string]$verdict.verdict -eq "unreadable") {
                $outcome = "toolchain_defect"
                $steps.Add((New-Step -Name "test" -Status "failed" -ExitCode ([int]$run.exitCode) `
                    -DurationMs ([int]$run.durationMs) -Command $rendered -Detail (
                        "The runner printed no summary this runtime can read, so the number of tests " +
                        "that ran is unknown and nothing has been proved.`n" +
                        (Get-FailureTail -Text ([string]$run.output)))))
                Add-Finding -Severity "error" -ProjectPath $manifest.projectPath -Message (
                    "$($manifest.projectPath): the test run produced no readable summary.")
                break
            }
            if ([string]$verdict.verdict -eq "empty") {
                $outcome = "toolchain_defect"
                $steps.Add((New-Step -Name "test" -Status "failed" -ExitCode ([int]$run.exitCode) `
                    -DurationMs ([int]$run.durationMs) -Command $rendered -Detail (
                        "The runner discovered no tests. An empty suite passes every time and " +
                        "reports nothing, so it is not a verified framework.")))
                Add-Finding -Severity "error" -ProjectPath $manifest.projectPath -Message (
                    "$($manifest.projectPath): the framework discovered no tests.")
                break
            }
            if ([string]$verdict.verdict -eq "all-skipped") {
                # A suite whose every test is skipped exits zero and prints a
                # summary, so it satisfies both checks above while asserting
                # nothing whatever. Counted as passes, those skips are how a
                # framework that never runs is declared verified.
                $outcome = "toolchain_defect"
                $steps.Add((New-Step -Name "test" -Status "failed" -ExitCode ([int]$run.exitCode) `
                    -DurationMs ([int]$run.durationMs) -Command $rendered -Detail (
                        "All $discovered test(s) the runner found were skipped, so nothing was " +
                        "asserted. A suite that does not run proves no more than an empty one.")))
                Add-Finding -Severity "error" -ProjectPath $manifest.projectPath -Message (
                    "$($manifest.projectPath): all $discovered test(s) were skipped.")
                break
            }
            if ([string]$verdict.verdict -eq "failed") {
                $outcome = if (Test-InfrastructureFailure -Output ([string]$run.output)) {
                    "infrastructure_unavailable"
                }
                else { "toolchain_defect" }
                $steps.Add((New-Step -Name "test" -Status "failed" -ExitCode ([int]$run.exitCode) `
                    -DurationMs ([int]$run.durationMs) -Command $rendered -Detail (
                        "$failedTests of $discovered test(s) failed.`n" +
                        (Get-FailureTail -Text ([string]$run.output)))))
                Add-Finding -Severity "error" -ProjectPath $manifest.projectPath -Message (
                    "$($manifest.projectPath): $failedTests of $discovered test(s) failed on a clean checkout.")
                break
            }
            $steps.Add((New-Step -Name "test" -Status "passed" -ExitCode 0 `
                -DurationMs ([int]$run.durationMs) -Command $rendered -Detail (
                    "$executedTests test(s) ran and passed" +
                    $(if ($skippedTests -gt 0) { ", $skippedTests skipped." } else { "." }))))
            continue
        }

        if ([int]$run.exitCode -ne 0) {
            $outcome = if (Test-InfrastructureFailure -Output ([string]$run.output)) {
                "infrastructure_unavailable"
            }
            else { "toolchain_defect" }
            $steps.Add((New-Step -Name ([string]$phase.name) -Status "failed" `
                -ExitCode ([int]$run.exitCode) -DurationMs ([int]$run.durationMs) `
                -Command $rendered -Detail (Get-FailureTail -Text ([string]$run.output))))
            Add-Finding -Severity "error" -ProjectPath $manifest.projectPath -Message (
                "$($manifest.projectPath): $([string]$phase.name) failed with exit code $([int]$run.exitCode).")
            break
        }
        $steps.Add((New-Step -Name ([string]$phase.name) -Status "passed" -ExitCode 0 `
            -DurationMs ([int]$run.durationMs) -Command $rendered -Detail ""))

        # An installer that reads the lock has already refused anything the lock
        # does not name. An installer that does not read it leaves the lock
        # decorative unless someone compares the two, and this is the only
        # moment at which both the lock and the installed bytes exist.
        if ($phase.name -eq "install" -and [string]$adapter.lockEnforcement -eq "verified-after-install") {
            $lockPath = Join-Path $projectDirectory ([string]$adapter.lockFileName)
            if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
                $outcome = "toolchain_defect"
                $detail = ("The change set carries no $([string]$adapter.lockFileName) for this " +
                    "project, and $([string]$manifest.ecosystem) installs without consulting one, so " +
                    "nothing pins what was fetched.")
                $steps.Add((New-Step -Name "install_lock" -Status "failed" -Detail $detail))
                Add-Finding -Severity "error" -ProjectPath $manifest.projectPath -Message (
                    "$($manifest.projectPath): $detail")
                break
            }
            $lockFindings = @(& $adapter.GetInstalledArtefactFindings $resolved $projectDirectory `
                (Get-Content -LiteralPath $lockPath -Raw))
            if ($lockFindings.Count -gt 0) {
                $outcome = "toolchain_defect"
                $steps.Add((New-Step -Name "install_lock" -Status "failed" -Detail (
                    (@($lockFindings) | ForEach-Object { [string]$_ }) -join " ")))
                foreach ($lockFinding in $lockFindings) {
                    Add-Finding -Severity "error" -ProjectPath $manifest.projectPath -Message (
                        "$($manifest.projectPath): $([string]$lockFinding)")
                }
                break
            }
            $steps.Add((New-Step -Name "install_lock" -Status "passed" -ExitCode 0 -Detail (
                "Every artefact the install fetched is the one $([string]$adapter.lockFileName) pins.")))
        }
    }

    $testFailuresOnly = $outcome -eq 'toolchain_defect' -and $failedTests -gt 0 -and
        $baselineFailures.Count -eq $failedTests -and
        @($steps | Where-Object { $_.status -eq 'failed' -and $_.name -ne 'test' }).Count -eq 0
    if ($outcome -eq "verified" -or $testFailuresOnly) {
        # A suite that cannot go red cannot report a defect either, and a green
        # run is the same colour whether the assertions hold or whether nothing
        # is asserting at all. So the framework is asked to fail on purpose once.
        $probeSpec = & $adapter.NewNegativeProbe $resolved $projectDirectory
        if (-not [bool]$probeSpec.supported) {
            $outcome = "toolchain_defect"
            $probe["detail"] = [string]$probeSpec.reason
            $steps.Add((New-Step -Name "negative_probe" -Status "failed" -Detail ([string]$probeSpec.reason)))
            Add-Finding -Severity "error" -ProjectPath $manifest.projectPath -Message (
                "$($manifest.projectPath): $([string]$probeSpec.reason)")
        }
        else {
            $probePath = Join-Path $projectDirectory ([string]$probeSpec.relativePath)
            $probe["attempted"] = $true
            New-Item -ItemType Directory -Path (Split-Path $probePath -Parent) -Force | Out-Null
            Set-Content -LiteralPath $probePath -Value ([string]$probeSpec.content) -Encoding utf8 -NoNewline
            try {
                # Not the same command the suite was measured with. A compiled
                # ecosystem is told not to rebuild there, because the build step
                # has just run - but the probe is a source file written after
                # that build, so running it that way runs the previous binary,
                # counts the same tests as before, and reports that the
                # deliberate failure never ran. Where an ecosystem needs a
                # different command to pick the probe up, it says so.
                $command = if (@(Get-QaFoundryPropertyNames -InputObject $adapter) -contains
                    "GetNegativeProbeTestCommand") {
                    & $adapter.GetNegativeProbeTestCommand $resolved $projectDirectory
                }
                else { & $adapter.GetTestCommand $resolved $projectDirectory }
                $run = Invoke-VerificationCommand -Command $command -WorkingDirectory $projectDirectory
                $lastCommandLog = Save-VerificationCommandOutput -Text ([string]$run.output)
                $summary = & $adapter.ReadTestRunSummary ([string]$run.output) ([int]$run.exitCode)
                # A non-zero exit used to be enough, and unreadable output was
                # read as agreement. It is the opposite: a probe that does not
                # compile, a runner that will not start and a configuration
                # error all exit non-zero while printing no summary, and each
                # was recorded as proof that an assertion ran and failed. What
                # this step has to see is the suite running one more test than
                # it ran a moment ago, and that test failing.
                $probeName = [IO.Path]::GetFileName([string]$probeSpec.relativePath)
                $probeSkipped = if (@(Get-QaFoundryPropertyNames -InputObject $summary) -contains "skipped") {
                    [int]$summary.skipped
                } else { 0 }
                # Counted in tests that ran rather than tests reported, because a
                # runner that skips the probe reports one test more while running
                # exactly as many as before.
                $probeExecuted = [int]$summary.total - $probeSkipped
                $expectedExecuted = $executedTests + 1
                $probeFailureIds = @(Get-QaFoundryFailedTestCases -Text ([string]$run.output) -ProjectPath $manifest.projectPath | ForEach-Object sourceRef)
                $probeReason = ""
                if (-not [bool]$summary.parsed) {
                    $probeReason = ("The runner printed no summary this runtime can read after " +
                        "$probeName was added, so whether the deliberate failure ran at all is " +
                        "unknown. A probe that does not compile is not a suite that can go red.")
                }
                elseif ($probeExecuted -ne $expectedExecuted) {
                    $probeReason = ("The suite ran $probeExecuted test(s) with $probeName " +
                        "added and $executedTests without it, so the deliberately failing test was " +
                        "not the one that ran.")
                }
                elseif ([int]$summary.failed -ne ($failedTests + 1)) {
                    $probeReason = ("A deliberately broken expectation did not make the suite fail, " +
                        "so a real defect would not either.")
                }
                elseif ($testFailuresOnly -and @($baselineFailures | Where-Object {
                    $_.sourceRef -notin $probeFailureIds
                }).Count -gt 0) {
                    $probeReason = 'The baseline failed tests changed while running the negative probe; product-failure attribution is not stable.'
                }
                elseif ([int]$run.exitCode -eq 0) {
                    $probeReason = ("The runner reported $([int]$summary.failed) failed test(s) and " +
                        "still exited zero, so a pipeline reading the exit code would call this run " +
                        "green.")
                }
                $failedAsExpected = [string]::IsNullOrEmpty($probeReason)
                $probe["failedAsExpected"] = $failedAsExpected
                if ($failedAsExpected) {
                    $probe["detail"] = ("A deliberately broken expectation made the suite fail: " +
                        "$([int]$summary.failed) of $([int]$summary.total) test(s) failed.")
                    $steps.Add((New-Step -Name "negative_probe" -Status "passed" `
                        -ExitCode ([int]$run.exitCode) -DurationMs ([int]$run.durationMs) `
                        -Detail ([string]$probe["detail"])))
                }
                else {
                    $outcome = "toolchain_defect"
                    $probe["detail"] = $probeReason
                    $steps.Add((New-Step -Name "negative_probe" -Status "failed" `
                        -ExitCode ([int]$run.exitCode) -DurationMs ([int]$run.durationMs) `
                        -Detail ([string]$probe["detail"])))
                    Add-Finding -Severity "error" -ProjectPath $manifest.projectPath -Message (
                        "$($manifest.projectPath): $probeReason")
                }
            }
            finally {
                Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
            }
        }
    }
    else {
        $probe["detail"] = "Not attempted: the framework did not reach a passing run."
        $steps.Add((New-Step -Name "negative_probe" -Status "skipped" -Detail ([string]$probe["detail"])))
    }

    $projects.Add([ordered]@{
        toolchainId = [string]$toolchain.id
        ecosystem = $manifest.ecosystem
        manifestPath = $manifest.manifestPath
        projectPath = if ([string]::IsNullOrWhiteSpace($manifest.projectPath)) { "." } else { $manifest.projectPath }
        outcome = $outcome
        steps = @($steps)
        testsDiscovered = $discovered
        testsFailed = $failedTests
        negativeProbe = $probe
    })

    # Infrastructure wins over a defect: a run that could not reach a feed has
    # not shown the design to be wrong, and sending it back to be redesigned
    # would spend the repair budget answering the wrong question.
    if ($outcome -eq "infrastructure_unavailable") { $overall = "infrastructure_unavailable" }
    elseif ($outcome -eq "toolchain_defect" -and $overall -ne "infrastructure_unavailable") {
        $overall = "toolchain_defect"
    }
}

return (New-Result -Outcome $overall)
