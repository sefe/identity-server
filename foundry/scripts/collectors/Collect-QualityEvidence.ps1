[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][object]$Policy,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$AnalysisRunRoot = '',
    [string]$AnalysisChangeSetPath = '',
    [string]$InstallationChangeSetPath = '',
    [switch]$DeferExecution,
    [AllowNull()][object]$Deadline = $null
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../Common.ps1")
if ($DeferExecution) {
    # Keep static evidence and secret scanning, without running any suite or
    # operator command. Clone so later lifecycle configuration is unaffected.
    $Config = $Config | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    $Config.quality.auto_detect = $false
    $Config.quality.commands = @()
    $Config.quality | Add-Member -NotePropertyName automation_gates -NotePropertyValue @() -Force
}
$commandSpecs = [System.Collections.Generic.List[object]]::new()
$seenIds = @{}
function Add-QualityCommand {
    param(
        [string]$Id,
        [string]$Category,
        [string]$Executable,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [bool]$Required,
        [string]$Ecosystem = "",
        [string]$ManifestPath = ''
    )
    if ($seenIds.ContainsKey($Id)) { return }
    $seenIds[$Id] = $true
    $commandSpecs.Add([pscustomobject]@{
        id = $Id
        category = $Category
        executable = $Executable
        arguments = @($Arguments)
        workingDirectory = $WorkingDirectory
        required = $Required
        # Which runner's summary this command's output can be read with. Empty
        # for a hand-written command that does not say, and a test command that
        # does not say is judged by its exit code alone - which is why every
        # command this runtime derives itself carries one.
        ecosystem = $Ecosystem
        manifestPath = $ManifestPath
    })
}

$qualityWarnings = [System.Collections.Generic.List[string]]::new()
if ($DeferExecution) {
    $qualityWarnings.Add('Bootstrap generation only: build and test commands were not executed. Credentials and execution are deferred until after delivery; no passing-test or coverage claim is made.')
}
# A gate that was configured and could not be derived. Kept rather than only
# warned about: the required-failure count is computed from command results, so
# a gate that produced no result at all was a required gate that passed by not
# being there.
$unresolvedGates = [System.Collections.Generic.List[object]]::new()
# The gates for automation this programme generated itself. They are expanded
# first and win any id collision on purpose: where a configuration still carries
# a hand-written command for the same thing, the derived one is the one that
# knows which ecosystem is actually on disk. An operator who wants a command of
# their own gives it its own id, or declares no gate for that path at all.
$gateNames = @(Get-QaFoundryPropertyNames -InputObject $Config.quality)
if ($gateNames -contains "automation_gates") {
    $configuredEcosystems = @()
    if (@(Get-QaFoundryPropertyNames -InputObject $Config) -contains "automation") {
        $configuredEcosystems = @(Get-QaFoundryPropertyNames -InputObject $Config.automation.ecosystems)
    }
    foreach ($gate in @($Config.quality.automation_gates)) {
        $gatePath = [string]$gate.path
        $gateRequired = $true
        if (@(Get-QaFoundryPropertyNames -InputObject $gate) -contains "required") {
            $gateRequired = [bool]$gate.required
        }
        if ($configuredEcosystems.Count -eq 0) {
            $reason = ("The automation gate on '$gatePath' could not be derived because this " +
                "installation configures no ecosystems to derive it from.")
            $qualityWarnings.Add($reason)
            $unresolvedGates.Add([pscustomobject]@{
                path = $gatePath; required = $gateRequired; reason = $reason
            })
            continue
        }
        $resolvedGate = Resolve-QaFoundryAutomationGate -RepositoryRoot $RepositoryRoot `
            -Path $gatePath -EcosystemIds $configuredEcosystems
        if (-not $resolvedGate.resolved) {
            # Recorded as a blocked command rather than thrown here, so that one
            # unusable gate does not hide whatever the others found. Whether it
            # ends the run is decided the same way it is for a gate that ran and
            # failed: by whether the gate was required.
            $reason = "No quality gate ran for '$gatePath'. $([string]$resolvedGate.reason)"
            $qualityWarnings.Add($reason)
            $unresolvedGates.Add([pscustomobject]@{
                path = $gatePath; required = $gateRequired; reason = $reason
            })
            continue
        }
        foreach ($problem in @($resolvedGate.problems)) {
            # A gate over several projects can resolve most of them and still
            # have one it cannot read. That one is recorded exactly as a whole
            # unresolved gate is, so a required gate is not quietly reduced to
            # the projects that happened to be legible.
            $reason = "No quality gate ran for '$([string]$problem.path)'. $([string]$problem.reason)"
            $qualityWarnings.Add($reason)
            $unresolvedGates.Add([pscustomobject]@{
                path = [string]$problem.path; required = $gateRequired; reason = $reason
            })
        }
        foreach ($derived in @($resolvedGate.commands)) {
            # A derived id that has already been seen is not a duplicate to be
            # ignored: two gates resolved to the same commands, and dropping one
            # of them would leave a configured gate silently unrun. The id is
            # built from the project path, so this states a real defect.
            if ($seenIds.ContainsKey([string]$derived.id)) {
                throw ("Two automation gates produced the same command id " +
                    "'$([string]$derived.id)'. One of them would never run, and a gate that does " +
                    "not run is not a gate that passed. Give each gate a path of its own.")
            }
            Add-QualityCommand -Id ([string]$derived.id) `
                -Category ([string]$derived.category) `
                -Executable ([string]$derived.executable) `
                -Arguments @($derived.arguments) `
                -WorkingDirectory ([string]$derived.workingDirectory) `
                -Required $gateRequired `
                -Ecosystem ([string]$derived.ecosystem) `
                -ManifestPath ([string]$derived.manifestPath)
            # The derived id carries the project so two gates cannot collide.
            # The name it used to carry is claimed as well, so a configuration
            # still pinning a hand-written command under the old id is
            # superseded rather than run alongside this one.
            $seenIds[[string]$derived.supersedes] = $true
        }
    }
}

foreach ($command in @($Config.quality.commands)) {
    # A hand-written command may name the runner its output comes from, and one
    # that does gets the same empty-suite check a derived gate gets.
    $commandEcosystem = ""
    if (@(Get-QaFoundryPropertyNames -InputObject $command) -contains "ecosystem") {
        $commandEcosystem = [string]$command.ecosystem
    }
    Add-QualityCommand -Id ([string]$command.id) `
        -Category ([string]$command.category) `
        -Executable ([string]$command.executable) `
        -Arguments @($command.arguments) `
        -WorkingDirectory ([string]$command.working_directory) `
        -Required ([bool]$command.required) `
        -Ecosystem $commandEcosystem
}
if ([bool]$Config.quality.auto_detect) {
    $packagePath = Join-Path $RepositoryRoot "package.json"
    if (Test-Path $packagePath -PathType Leaf) {
        $package = Get-Content -Path $packagePath -Raw | ConvertFrom-Json -Depth 30
        # A manifest with no scripts block, or an empty one, is ordinary. Reading
        # its property names directly is what turns that into a crash.
        $packageScripts = if (
            (Get-QaFoundryPropertyNames -InputObject $package) -contains "scripts"
        ) { $package.scripts } else { $null }
        $scriptNames = @(Get-QaFoundryPropertyNames -InputObject $packageScripts)
        if ($scriptNames -contains "test") {
            Add-QualityCommand -Id "auto-node-test" -Category "test" `
                -Executable "npm" -Arguments @("test") -WorkingDirectory "." -Required $true
        }
        if ($scriptNames -contains "lint") {
            Add-QualityCommand -Id "auto-node-lint" -Category "lint" `
                -Executable "npm" -Arguments @("run", "lint") -WorkingDirectory "." -Required $true
        }
        if ($scriptNames -contains "build") {
            Add-QualityCommand -Id "auto-node-build" -Category "build" `
                -Executable "npm" -Arguments @("run", "build") -WorkingDirectory "." -Required $true
        }
        if ([bool]$Config.quality.security.dependency_audit) {
            Add-QualityCommand -Id "auto-npm-audit" -Category "dependency" `
                -Executable "npm" -Arguments @("audit", "--json") -WorkingDirectory "." -Required $false
        }
    }
    $dotnetProjects = @(Get-ChildItem -Path $RepositoryRoot -File -Recurse -Include "*.sln", "*.slnx", "*.csproj" |
        Where-Object { $_.FullName -notmatch "[\\/]node_modules[\\/]" } |
        Select-Object -First 1)
    if ($dotnetProjects.Count -gt 0) {
        Add-QualityCommand -Id "auto-dotnet-test" -Category "test" `
            -Executable "dotnet" -Arguments @("test") -WorkingDirectory "." -Required $true
        if ([bool]$Config.quality.security.dependency_audit) {
            Add-QualityCommand -Id "auto-dotnet-vulnerable" -Category "dependency" `
                -Executable "dotnet" -Arguments @("list", "package", "--vulnerable", "--include-transitive") `
                -WorkingDirectory "." -Required $false
        }
    }
    if ((Test-Path (Join-Path $RepositoryRoot "pytest.ini")) -or
        (Test-Path (Join-Path $RepositoryRoot "pyproject.toml"))) {
        Add-QualityCommand -Id "auto-pytest" -Category "test" `
            -Executable "python" -Arguments @("-m", "pytest") -WorkingDirectory "." -Required $true
        if ([bool]$Config.quality.security.dependency_audit) {
            Add-QualityCommand -Id "auto-pip-check" -Category "dependency" `
                -Executable "python" -Arguments @("-m", "pip", "check") -WorkingDirectory "." -Required $false
        }
    }
    if (Test-Path (Join-Path $RepositoryRoot "pom.xml") -PathType Leaf) {
        Add-QualityCommand -Id "auto-maven-test" -Category "test" `
            -Executable "mvn" -Arguments @("test") -WorkingDirectory "." -Required $true
    }
    if (Test-Path (Join-Path $RepositoryRoot "build.gradle") -PathType Leaf) {
        Add-QualityCommand -Id "auto-gradle-test" -Category "test" `
            -Executable "gradle" -Arguments @("test") -WorkingDirectory "." -Required $true
    }
}
else {
    # Detection off is a deliberate narrowing of the gate, and a narrowed gate
    # that says nothing about itself reads exactly like a gate that passed. A
    # comment in the configuration would not have travelled this far: whoever
    # reads the evidence, or the pull request built from it, sees only what is
    # written here.
    $qualityWarnings.Add(
        "Automatic quality command detection is disabled, so only the explicitly configured " +
        "commands were eligible to run. Whatever this repository contains beyond them - test " +
        "suites, builds, linters in other ecosystems - was not executed and is not evidenced here.")
}

function Limit-Text {
    param([string]$Text, [int]$Maximum = 32768)
    if ($null -eq $Text) { return "" }
    if ($Text.Length -le $Maximum) { return $Text }
    return $Text.Substring(0, $Maximum)
}
# The configured working directory is written by hand, but the directory layout
# it points at is chosen by the architecture stage. When the two disagree the
# tool reports its own confusion - "npm ci requires an existing package-lock.json"
# - which reads like a broken change set rather than a misaimed gate, and the
# whole run is spent before anyone can tell the difference. Rather than trust the
# blueprint to name the gate's target, which would let the work under review
# choose its own examiner, the configured path stays authoritative and this only
# rescues the near miss: the manifest must sit inside the configured subtree, and
# there must be exactly one candidate, or the command runs where it was told and
# fails honestly.
$manifestPatterns = @{
    "npm" = @("package.json"); "npx" = @("package.json")
    "pnpm" = @("package.json"); "yarn" = @("package.json"); "node" = @("package.json")
    "dotnet" = @("*.sln", "*.csproj"); "mvn" = @("pom.xml")
    "gradle" = @("build.gradle"); "python" = @("pyproject.toml")
}
function Resolve-QualityWorkingDirectory {
    param([object]$Spec)
    $executable = ([string]$Spec.executable).ToLowerInvariant() -replace "\.(cmd|exe|bat)$", ""
    if (-not $manifestPatterns.ContainsKey($executable)) { return [string]$Spec.workingDirectory }
    $patterns = @($manifestPatterns[$executable])
    $configured = Resolve-QaFoundryPath -Root $RepositoryRoot -Path ([string]$Spec.workingDirectory)
    if (-not (Test-PathWithinRoot -Candidate $configured -Root $RepositoryRoot)) {
        return [string]$Spec.workingDirectory
    }
    foreach ($pattern in $patterns) {
        if (@(Get-ChildItem -Path $configured -Filter $pattern -File -ErrorAction SilentlyContinue).Count -gt 0) {
            return [string]$Spec.workingDirectory
        }
    }
    # Walking up past an absent directory keeps the search inside the subtree the
    # operator named. It deliberately stops short of the repository root, where
    # every unrelated workspace would become a candidate.
    $searchRoot = $configured
    while (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) {
        $parent = Split-Path -Path $searchRoot -Parent
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $searchRoot) { return [string]$Spec.workingDirectory }
        $searchRoot = $parent
    }
    if ((Resolve-Path -LiteralPath $searchRoot).Path -eq (Resolve-Path -LiteralPath $RepositoryRoot).Path) {
        return [string]$Spec.workingDirectory
    }
    $found = @()
    foreach ($pattern in $patterns) {
        $found += @(Get-ChildItem -Path $searchRoot -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch "[\\/](node_modules|bin|obj|\.git)[\\/]" })
    }
    $directories = @($found | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique)
    if ($directories.Count -ne 1) { return [string]$Spec.workingDirectory }
    $resolved = ([System.IO.Path]::GetRelativePath($RepositoryRoot, $directories[0])) -replace "\\", "/"
    $qualityWarnings.Add(
        "Quality command '$($Spec.id)' was configured to run in '$($Spec.workingDirectory)', which holds no " +
        "$($patterns -join " or ") manifest. Exactly one was found at '$resolved', so the command ran there " +
        "instead. The configured path and the layout this repository actually has are out of step, and the " +
        "configuration is what should be corrected - this fallback is not a substitute for it.")
    return $resolved
}

$results = [System.Collections.Generic.List[object]]::new()
$trackedProductFailures = [System.Collections.Generic.HashSet[string]]::new()
# Ahead of the commands that did run, so that a gate which could not even be
# derived is the first thing read in the evidence.
foreach ($gate in $unresolvedGates) {
    $slug = ([string]$gate.path -replace "[^a-zA-Z0-9]+", "-").Trim("-").ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = "root" }
    $results.Add([pscustomobject][ordered]@{
        id = "automation-gate-$slug"
        category = "test"
        required = [bool]$gate.required
        command = ""
        workingDirectory = [string]$gate.path
        exitCode = 0
        status = "blocked"
        durationMs = 0
        standardOutput = ""
        standardError = [string]$gate.reason
    })
}
foreach ($spec in $commandSpecs) {
    $workingDirectory = Resolve-QualityWorkingDirectory -Spec $spec
    if ($spec.category -eq 'test' -and $spec.manifestPath) {
        # Some runners are selected by evaluated build output (for example MTP).
        # Derivation before restore/build cannot know which runner was built.
        $adapter = Get-QaFoundryEcosystemAdapter -Ecosystem $spec.ecosystem
        $fresh = @(New-QaFoundryAutomationGateCommands -Adapter $adapter `
            -ManifestPath $spec.manifestPath -ProjectPath $workingDirectory | Where-Object category -eq 'test')
        if ($fresh.Count -ne 1) { throw "Cannot derive the built test runner for '$workingDirectory'." }
        $spec.executable = $fresh[0].executable
        $spec.arguments = @($fresh[0].arguments)
    }
    $commandResult = & (Join-Path $PSScriptRoot "../Invoke-CommandSafely.ps1") `
        -CommandSpec ([pscustomobject]@{
            id = $spec.id
            executable = $spec.executable
            arguments = @($spec.arguments)
            workingDirectory = $workingDirectory
            environment = [pscustomobject]@{}
        }) `
        -Policy $Policy `
        -RepositoryRoot $RepositoryRoot `
        -Isolation (Get-QaFoundryIsolationSetting -Config $Config) `
        -Deadline $Deadline
    $commandStatus = [string]$commandResult.status
    $commandStandardError = [string]$commandResult.standardError
    if ($commandStatus -eq "completed" -and [string]$spec.category -eq "test" -and
        -not [string]::IsNullOrWhiteSpace([string]$spec.ecosystem)) {
        # A test runner exits zero when every test passed and when there was
        # nothing to run. Accepting the exit code alone is what let a change that
        # deletes the tests, or skips all of them, come back green - the gate
        # that is meant to notice being the one thing that would not.
        $verdict = Get-QaFoundryTestRunVerdict -Ecosystem ([string]$spec.ecosystem) `
            -Output (([string]$commandResult.standardOutput) + "`n" +
                ([string]$commandResult.standardError)) `
            -ExitCode ([int]$commandResult.exitCode)
        if (-not $verdict.proved) {
            $commandStatus = "failed"
            $commandStandardError = (("Quality command '$([string]$spec.id)' exited " +
                "$([int]$commandResult.exitCode), and the run it reports proves nothing: " +
                "$([string]$verdict.reason)") + "`n" + $commandStandardError)
            $qualityWarnings.Add("Quality command '$([string]$spec.id)': $([string]$verdict.reason)")
        }
    }
    if ($commandStatus -eq 'failed' -and $spec.category -eq 'test' -and $spec.manifestPath -and $AnalysisRunRoot) {
        . (Join-Path $PSScriptRoot '../QualityProductDefects.ps1')
        try {
            $context = Get-QaFoundryQualityProductDefectContext -RunRoot $AnalysisRunRoot `
                -ChangeSetPath $AnalysisChangeSetPath -RepositoryRoot $RepositoryRoot
            $bugs = @(Get-QaFoundryQualityProductBugIds -Context $context -ProjectPath $workingDirectory `
                -Ecosystem $spec.ecosystem -ExitCode ([int]$commandResult.exitCode) `
                -Output (([string]$commandResult.standardOutput) + "`n" + ([string]$commandResult.standardError)))
            if ($bugs.Count -gt 0) {
                [void]$trackedProductFailures.Add([string]$spec.id)
                $qualityWarnings.Add("Quality command '$($spec.id)' retains its failing tests and exit code. " +
                    "Only the unchanged, independently confirmed product regression(s) tracked by Bug(s) $($bugs -join ', ') failed; installation may proceed.")
            }
        }
        catch { $qualityWarnings.Add("Product defect evidence could not authorize '$($spec.id)': $($_.Exception.Message)") }
    }
    $results.Add([pscustomobject][ordered]@{
        id = [string]$commandResult.id
        category = [string]$spec.category
        required = [bool]$spec.required
        command = [string]$commandResult.command
        workingDirectory = [string]$workingDirectory
        exitCode = [int]$commandResult.exitCode
        status = $commandStatus
        durationMs = [int]$commandResult.durationMs
        standardOutput = Limit-Text -Text ([string]$commandResult.standardOutput)
        standardError = Limit-Text -Text $commandStandardError
    })
}

$secretFindings = [System.Collections.Generic.List[object]]::new()
if ([bool]$Config.quality.security.secret_scan) {
    . (Join-Path $PSScriptRoot '../SecretScan.ps1')
    # The same rules the context collector redacts with, so a value that is
    # hidden from a model provider is also one this gate knows to look for. The
    # exception is deliberate and marked on the rule: a shape that is worth
    # hiding from a provider is not always worth failing a build over, and a
    # gate that cries wolf is a gate everyone learns to override.
    $rules = @(Get-QaFoundrySecretRules | Where-Object {
        @(Get-QaFoundryPropertyNames -InputObject $_) -notcontains "failsBuild" -or
            [bool]$_.failsBuild
    })
    # git ls-files lists what the index already knows about. During a bootstrap
    # the files most worth scanning are the ones this run just generated, and
    # they are untracked until something adds them, so listing tracked files
    # alone excludes exactly the new code from the secret gate. Untracked but
    # unignored files are therefore scanned as well.
    $trackedFiles = @(& git -C $RepositoryRoot ls-files 2>$null)
    $listingSucceeded = $LASTEXITCODE -eq 0
    $untrackedFiles = @(& git -C $RepositoryRoot ls-files --others --exclude-standard 2>$null)
    if ($LASTEXITCODE -ne 0) { $untrackedFiles = @() }
    if ($listingSucceeded) {
        $scanPaths = @($trackedFiles + $untrackedFiles | Sort-Object -Unique)
        if ($InstallationChangeSetPath) {
            $installation = Get-Content -LiteralPath $InstallationChangeSetPath -Raw | ConvertFrom-Json -Depth 100
            if ($installation.runId -cne $RunId) { throw 'Secret scan installation scope belongs to a different run.' }
            $scanPaths = @($installation.changes | Where-Object operation -ne 'delete' | ForEach-Object path | Sort-Object -Unique)
            $qualityWarnings.Add("Installation secret scan covers $($scanPaths.Count) delivered file(s); unchanged repository files are outside this delivery.")
        }
        foreach ($relative in $scanPaths) {
            $absolute = Join-Path $RepositoryRoot $relative
            if (-not (Test-PathWithinRoot -Candidate $absolute -Root $RepositoryRoot)) { throw 'Secret scan scope escapes the repository.' }
            if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
                if ($InstallationChangeSetPath) { throw "Delivered file is missing from the secret scan: $relative" }
                continue
            }
            # PowerShell marks a dot-prefixed file hidden on Linux, and the file
            # system provider withholds a hidden item unless it is forced. The
            # build agents are Linux, so build 470 applied its whole change set
            # and then died on the repository's own .dockerignore. Test-Path sees
            # such a file, which is what made the gap look impossible.
            $file = Get-Item -LiteralPath $absolute -Force
            if ($file.Length -gt [int64]$Config.quality.security.max_file_bytes) { continue }
            $lineNumber = 0
            foreach ($line in @(Get-Content -LiteralPath $absolute -Force -ErrorAction SilentlyContinue)) {
                $lineNumber++
                foreach ($finding in @(Get-QaFoundrySecretLineFindings -Line $line -Path $relative -Rules $rules)) {
                    if ($finding.ignored) {
                        $qualityWarnings.Add("Secret scan reviewed $($relative):$lineNumber ($($finding.rule)): $($finding.reason).")
                    } else {
                        $secretFindings.Add([pscustomobject][ordered]@{
                            path = ([string]$relative).Replace("\", "/")
                            line = $lineNumber
                            rule = [string]$finding.rule
                        })
                    }
                }
            }
        }
    }
}
$manifestNames = @(
    "package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml",
    "packages.lock.json", "packages.config", "requirements.txt", "poetry.lock",
    "Pipfile.lock", "pom.xml", "build.gradle", "gradle.lockfile", "Cargo.lock", "go.sum"
)
$manifests = [System.Collections.Generic.List[object]]::new()
foreach ($file in @(Get-ChildItem -Path $RepositoryRoot -File -Recurse | Where-Object {
    $_.Name -in $manifestNames -and $_.FullName -notmatch "[\\/]node_modules[\\/]"
})) {
    $relative = [IO.Path]::GetRelativePath($RepositoryRoot, $file.FullName).Replace("\", "/")
    $manifestHash = Get-FileSha256Safe -Path $file.FullName
    if (-not $manifestHash) {
        continue
    }
    $manifests.Add([pscustomobject][ordered]@{
        path = $relative
        sha256 = $manifestHash
    })
}
$failed = @($results | Where-Object { $_.status -eq "failed" })
# A command that never ran proves nothing. Counting it as a pass is how a gate
# comes to approve work it never inspected: during a bootstrap the directories
# these commands need are created by the run itself, so "no directory to run in"
# is the common case rather than the exception.
$unexecuted = @($results | Where-Object { $_.status -in @("skipped", "rejected", "blocked") })
$requiredFailures = @(@($failed) + @($unexecuted) | Where-Object {
    $_.required -and -not $trackedProductFailures.Contains([string]$_.id)
})
if (@($unexecuted | Where-Object { $_.required }).Count -gt 0) {
    $qualityWarnings.Add(
        "Required quality command(s) did not run: " +
        (@($unexecuted | Where-Object { $_.required } | ForEach-Object {
            "$([string]$_.id) ($([string]$_.status))"
        }) -join ", ") +
        ". They are counted as failures because the evidence they were required to produce " +
        "does not exist.")
}
$status = if ($requiredFailures.Count -gt 0 -or $secretFindings.Count -gt 0) {
    "failed"
}
elseif ($results.Count -eq 0 -and $secretFindings.Count -eq 0) {
    "no_action_needed"
}
else {
    "completed"
}
$evidence = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    collectedAt = [DateTime]::UtcNow.ToString("o")
    status = $status
    commands = @($results)
    secretFindings = @($secretFindings)
    dependencyManifests = @($manifests)
    summary = [ordered]@{
        commandCount = $results.Count
        failedCommandCount = $failed.Count
        unexecutedCommandCount = $unexecuted.Count
        requiredFailureCount = $requiredFailures.Count
        secretFindingCount = $secretFindings.Count
        dependencyManifestCount = $manifests.Count
    }
    warnings = @($qualityWarnings)
}
New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force | Out-Null
$evidence | ConvertTo-Json -Depth 100 | Set-Content -Path $OutputPath -Encoding utf8
if ([bool]$Config.quality.fail_on_required_failure -and $requiredFailures.Count -gt 0) {
    throw ("Required quality commands did not pass: " +
        (@($requiredFailures | ForEach-Object { "$([string]$_.id) ($([string]$_.status))" }) -join ", "))
}
if ($secretFindings.Count -gt 0) {
    throw "Secret scan found $($secretFindings.Count) potential secret(s)."
}
return [pscustomobject]$evidence
