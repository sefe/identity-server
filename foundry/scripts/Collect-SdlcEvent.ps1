[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$EventPath = "",
    [string]$EventType = "auto",
    [string]$EventId = "",
    [string]$CiBuildId = "",
    [string]$CiRunId = "",
    # Where the working copy this event is about lives. Without it there is no
    # way to say which files the event actually changed, only which files exist.
    [string]$RepositoryRoot = "",
    # The commit the change is measured against, when the caller already knows
    # it. Otherwise it is worked out from the pull request or the commit's own
    # parent, and said plainly when it cannot be.
    [string]$BaseRef = ""
)

$ErrorActionPreference = "Stop"

# What a run is asked to reason about is a change, and until now it was handed a
# snapshot and a commit sha. Everything in the repository looked equally new, so
# an analyst had no way to tell the three files this push touched from the three
# thousand that were already there - which costs both accuracy and the tokens
# spent describing work nobody asked about. This is the difference itself, taken
# from the repository rather than inferred.
$script:MaxChangedFiles = 400

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = "git"
    foreach ($argument in (@("-C", $Root) + $Arguments)) {
        $startInfo.ArgumentList.Add([string]$argument)
    }
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try { $null = $process.Start() }
    catch {
        $process.Dispose()
        return [pscustomobject]@{ exitCode = 127; output = ""; error = $_.Exception.Message }
    }
    try {
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(60 * 1000)) {
            try { $process.Kill($true) } catch { }
            return [pscustomobject]@{ exitCode = 124; output = ""; error = "git did not finish in time." }
        }
        return [pscustomobject]@{
            exitCode = $process.ExitCode
            output = $outputTask.GetAwaiter().GetResult()
            error = $errorTask.GetAwaiter().GetResult()
        }
    }
    finally { $process.Dispose() }
}

function Resolve-GitCommit {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Reference
    )

    if ([string]::IsNullOrWhiteSpace($Reference)) { return "" }
    $resolved = Invoke-GitCommand -Root $Root -Arguments @("rev-parse", "--verify", "$Reference^{commit}")
    if ($resolved.exitCode -ne 0) { return "" }
    return ([string]$resolved.output).Trim()
}

function ConvertFrom-GitStatusLetter {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Letter)

    switch -Regex ($Letter) {
        "^A" { return "added" }
        "^M" { return "modified" }
        "^D" { return "deleted" }
        "^R" { return "renamed" }
        "^C" { return "copied" }
        "^T" { return "type_changed" }
        default { return "changed" }
    }
}

function Get-EnvironmentValue {
    param([Parameter(Mandatory)][string]$Name)
    $value = [Environment]::GetEnvironmentVariable($Name)
    return $(if ($null -eq $value) { "" } else { [string]$value })
}

function Get-ObjectValue {
    param(
        [object]$Object,
        [Parameter(Mandatory)][string]$Name,
        [object]$Default = ""
    )
    if ($null -eq $Object) { return $Default }
    # An object a model returned as {} has no properties, and strict mode turns
    # reading the names of an empty property set into an exception rather than
    # an empty list. An event without the field asked for is ordinary.
    $names = if ($null -eq $Object.PSObject) {
        @()
    }
    else {
        @($Object.PSObject.Properties | ForEach-Object { $_.Name })
    }
    if ($names -contains $Name) {
        return $Object.$Name
    }
    return $Default
}

function Convert-ToScalarMetadata {
    param([object]$Value)
    $result = [ordered]@{}
    if ($null -eq $Value) {
        return $result
    }
    foreach ($property in $Value.PSObject.Properties) {
        if ($null -eq $property.Value -or
            $property.Value -is [string] -or
            $property.Value -is [bool] -or
            $property.Value -is [int] -or
            $property.Value -is [long] -or
            $property.Value -is [double] -or
            $property.Value -is [decimal]) {
            $result[$property.Name] = $property.Value
        }
    }
    return $result
}

$inputEvent = $null
if (-not [string]::IsNullOrWhiteSpace($EventPath)) {
    if (-not (Test-Path $EventPath -PathType Leaf)) {
        throw "SDLC event file does not exist: $EventPath"
    }
    $inputEvent = Get-Content -Path $EventPath -Raw |
        ConvertFrom-Json -Depth 50 -ErrorAction Stop
}

$isAzureDevOps = (Get-EnvironmentValue -Name "TF_BUILD") -eq "True"
$source = [string](Get-ObjectValue -Object $inputEvent -Name "source" -Default "")
if ([string]::IsNullOrWhiteSpace($source)) {
    $source = if ($isAzureDevOps) {
        "azure-devops"
    }
    else {
        "local"
    }
}

$resolvedType = if ($EventType -ne "auto") {
    $EventType
}
elseif (-not [string]::IsNullOrWhiteSpace(
    [string](Get-ObjectValue -Object $inputEvent -Name "type" -Default ""))) {
    [string](Get-ObjectValue -Object $inputEvent -Name "type" -Default "")
}
elseif ($isAzureDevOps) {
    if ((Get-EnvironmentValue -Name "BUILD_REASON") -eq "PullRequest") {
        "pull_request.updated"
    }
    else {
        "ci.build.started"
    }
}
else {
    "manual"
}

$repositoryInput = Get-ObjectValue -Object $inputEvent -Name "repository" -Default $null
$repositoryProvider = [string](Get-ObjectValue -Object $repositoryInput -Name "provider" -Default "")
if ([string]::IsNullOrWhiteSpace($repositoryProvider)) {
    $repositoryProvider = if ($source -eq "azure-devops") {
        "azure-repos"
    }
    else {
        "local"
    }
}
$repositoryName = [string](Get-ObjectValue -Object $repositoryInput -Name "name" -Default "")
if ([string]::IsNullOrWhiteSpace($repositoryName)) {
    $repositoryName = if ($isAzureDevOps) {
        Get-EnvironmentValue -Name "BUILD_REPOSITORY_NAME"
    }
    else {
        ""
    }
}
$repositoryUrl = [string](Get-ObjectValue -Object $repositoryInput -Name "url" -Default "")
if ([string]::IsNullOrWhiteSpace($repositoryUrl) -and $isAzureDevOps) {
    $repositoryUrl = Get-EnvironmentValue -Name "BUILD_REPOSITORY_URI"
}
$repositoryRef = [string](Get-ObjectValue -Object $repositoryInput -Name "ref" -Default "")
if ([string]::IsNullOrWhiteSpace($repositoryRef)) {
    $repositoryRef = if ($isAzureDevOps) {
        Get-EnvironmentValue -Name "BUILD_SOURCEBRANCH"
    }
    else {
        ""
    }
}
$repositorySha = [string](Get-ObjectValue -Object $repositoryInput -Name "commitSha" -Default "")
if ([string]::IsNullOrWhiteSpace($repositorySha)) {
    $repositorySha = if ($isAzureDevOps) {
        Get-EnvironmentValue -Name "BUILD_SOURCEVERSION"
    }
    else {
        ""
    }
}

$correlationInput = Get-ObjectValue -Object $inputEvent -Name "correlation" -Default $null
function Resolve-CorrelationValue {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$EnvironmentName = "",
        [string]$Override = ""
    )
    if (-not [string]::IsNullOrWhiteSpace($Override)) {
        return $Override
    }
    $fromInput = [string](Get-ObjectValue -Object $correlationInput -Name $Name -Default "")
    if (-not [string]::IsNullOrWhiteSpace($fromInput)) {
        return $fromInput
    }
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentName)) {
        return Get-EnvironmentValue -Name $EnvironmentName
    }
    return ""
}

$ciRunId = Resolve-CorrelationValue -Name "ciRunId" `
    -EnvironmentName "BUILD_BUILDID" -Override $CiRunId
$buildId = Resolve-CorrelationValue -Name "buildId" `
    -EnvironmentName "BUILD_BUILDID" -Override $CiBuildId
$pipelineId = Resolve-CorrelationValue -Name "pipelineId" `
    -EnvironmentName "SYSTEM_DEFINITIONID"
$pipelineName = Resolve-CorrelationValue -Name "pipelineName" `
    -EnvironmentName "BUILD_DEFINITIONNAME"
$pullRequestId = Resolve-CorrelationValue -Name "pullRequestId" `
    -EnvironmentName "SYSTEM_PULLREQUEST_PULLREQUESTID"
$workItemId = Resolve-CorrelationValue -Name "workItemId"

$occurredAt = [string](Get-ObjectValue -Object $inputEvent -Name "occurredAt" -Default "")
if ([string]::IsNullOrWhiteSpace($occurredAt)) {
    $occurredAt = [DateTime]::UtcNow.ToString("o")
}
$resolvedEventId = if (-not [string]::IsNullOrWhiteSpace($EventId)) {
    $EventId
}
else {
    [string](Get-ObjectValue -Object $inputEvent -Name "eventId" -Default "")
}
if ([string]::IsNullOrWhiteSpace($resolvedEventId)) {
    $identity = [string](@($buildId, $ciRunId, $repositorySha) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 1)
    if ([string]::IsNullOrWhiteSpace($identity)) {
        $identity = [guid]::NewGuid().ToString("N")
    }
    $resolvedEventId = "$source`:$resolvedType`:$identity"
}

$metadata = Convert-ToScalarMetadata -Value (
    Get-ObjectValue -Object $inputEvent -Name "metadata" -Default $null
)
if ($isAzureDevOps) {
    $metadata["organizationUrl"] = Get-EnvironmentValue -Name "SYSTEM_COLLECTIONURI"
    $metadata["project"] = Get-EnvironmentValue -Name "SYSTEM_TEAMPROJECT"
    $metadata["reason"] = Get-EnvironmentValue -Name "BUILD_REASON"
    $metadata["actor"] = Get-EnvironmentValue -Name "BUILD_REQUESTEDFOR"
}

function Get-RepositoryChange {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Root,
        [AllowEmptyString()][string]$HeadSha = "",
        [AllowEmptyString()][string]$DeclaredBase = "",
        [AllowEmptyString()][string]$TargetBranch = ""
    )

    $unavailable = {
        param([string]$Reason, [string]$Base = "", [string]$Head = "", [string]$Basis = "none")
        return [ordered]@{
            baseCommitSha = $Base
            headCommitSha = $Head
            basis = $Basis
            available = $false
            reason = $Reason
            fileCount = 0
            truncated = $false
            files = @()
        }
    }

    if ([string]::IsNullOrWhiteSpace($Root) -or -not (Test-Path -LiteralPath $Root)) {
        return & $unavailable ("No working copy was given, so the files this event changed could " +
            "not be established. Everything in the repository has to be treated as equally new.")
    }
    $insideWorkTree = Invoke-GitCommand -Root $Root -Arguments @("rev-parse", "--is-inside-work-tree")
    if ($insideWorkTree.exitCode -ne 0) {
        return & $unavailable ("'$Root' is not a Git working copy this agent can read, so the files " +
            "this event changed could not be established.")
    }

    $head = Resolve-GitCommit -Root $Root -Reference $HeadSha
    if ([string]::IsNullOrWhiteSpace($head)) {
        $head = Resolve-GitCommit -Root $Root -Reference "HEAD"
    }
    if ([string]::IsNullOrWhiteSpace($head)) {
        return & $unavailable ("The commit this event is about could not be resolved in the working " +
            "copy at '$Root'.")
    }

    # In order of how much each one is actually known. A base the caller named is
    # the strongest; a pull request's target branch is what the change will be
    # merged into; the commit's own parent is what is left, and on a shallow
    # checkout there is not even that - which is said rather than guessed around.
    $basis = "none"
    $base = ""
    if (-not [string]::IsNullOrWhiteSpace($DeclaredBase)) {
        $base = Resolve-GitCommit -Root $Root -Reference $DeclaredBase
        if (-not [string]::IsNullOrWhiteSpace($base)) { $basis = "declared" }
    }
    if ([string]::IsNullOrWhiteSpace($base) -and -not [string]::IsNullOrWhiteSpace($TargetBranch)) {
        foreach ($candidate in @($TargetBranch, ($TargetBranch -replace "^refs/heads/", "origin/"),
            ($TargetBranch -replace "^refs/heads/", ""))) {
            if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
            $mergeBase = Invoke-GitCommand -Root $Root -Arguments @("merge-base", $candidate, $head)
            if ($mergeBase.exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($mergeBase.output)) {
                $base = ([string]$mergeBase.output).Trim()
                $basis = "merge_base"
                break
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($base)) {
        $base = Resolve-GitCommit -Root $Root -Reference "$head^"
        if (-not [string]::IsNullOrWhiteSpace($base)) { $basis = "parent" }
    }
    if ([string]::IsNullOrWhiteSpace($base)) {
        return & $unavailable -Reason ("No commit to compare '$head' against could be found. A " +
            "shallow checkout has no parent, and no base was named, so what this event changed " +
            "cannot be separated from what was already there.") -Head $head
    }

    $names = Invoke-GitCommand -Root $Root -Arguments @("diff", "--name-status", "--no-renames",
        "$base..$head")
    if ($names.exitCode -ne 0) {
        return & $unavailable -Reason ("Comparing '$base' with '$head' failed: " +
            (([string]$names.error).Trim())) -Base $base -Head $head -Basis $basis
    }
    $counts = Invoke-GitCommand -Root $Root -Arguments @("diff", "--numstat", "--no-renames",
        "$base..$head")
    $countsByPath = @{}
    if ($counts.exitCode -eq 0) {
        foreach ($line in (([string]$counts.output) -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split "`t"
            if ($parts.Count -lt 3) { continue }
            # A binary file is reported as '-', which is a fact about the file
            # rather than a count, and is recorded as no lines either way.
            $countsByPath[[string]$parts[2]] = [pscustomobject]@{
                insertions = $(if ($parts[0] -match "^\d+$") { [int]$parts[0] } else { 0 })
                deletions = $(if ($parts[1] -match "^\d+$") { [int]$parts[1] } else { 0 })
            }
        }
    }

    $files = [System.Collections.Generic.List[object]]::new()
    foreach ($line in (([string]$names.output) -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $parts = $line -split "`t"
        if ($parts.Count -lt 2) { continue }
        $path = [string]$parts[$parts.Count - 1]
        $counted = $countsByPath[$path]
        $files.Add([ordered]@{
            path = $path
            status = ConvertFrom-GitStatusLetter -Letter ([string]$parts[0])
            insertions = $(if ($null -ne $counted) { [int]$counted.insertions } else { 0 })
            deletions = $(if ($null -ne $counted) { [int]$counted.deletions } else { 0 })
        })
    }

    # A change of a thousand files is a fact worth recording; a thousand file
    # names in every prompt for the rest of the run is not. The count is kept
    # whole and the list is cut, with the cut declared so nobody reads the
    # shortened list as the whole change.
    $total = $files.Count
    $truncated = $total -gt $script:MaxChangedFiles
    $listed = if ($truncated) {
        @($files | Select-Object -First $script:MaxChangedFiles)
    } else { @($files) }

    return [ordered]@{
        baseCommitSha = $base
        headCommitSha = $head
        basis = $basis
        available = $true
        reason = ""
        fileCount = $total
        truncated = $truncated
        files = @($listed)
    }
}

$changeInput = Get-ObjectValue -Object $inputEvent -Name "change" -Default $null
$declaredBase = [string](Get-ObjectValue -Object $changeInput -Name "baseCommitSha" -Default "")
if ([string]::IsNullOrWhiteSpace($declaredBase)) { $declaredBase = $BaseRef }
$targetBranch = [string](Get-ObjectValue -Object $changeInput -Name "targetRef" -Default "")
if ([string]::IsNullOrWhiteSpace($targetBranch) -and $isAzureDevOps) {
    $targetBranch = Get-EnvironmentValue -Name "SYSTEM_PULLREQUEST_TARGETBRANCH"
}
$change = Get-RepositoryChange -Root $RepositoryRoot -HeadSha $repositorySha `
    -DeclaredBase $declaredBase -TargetBranch $targetBranch

$event = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    eventId = $resolvedEventId
    type = $resolvedType
    source = $source
    occurredAt = $occurredAt
    repository = [ordered]@{
        provider = $repositoryProvider
        name = $repositoryName
        url = $repositoryUrl
        ref = $repositoryRef
        commitSha = $repositorySha
    }
    correlation = [ordered]@{
        ciRunId = [string]$ciRunId
        buildId = [string]$buildId
        pipelineId = [string]$pipelineId
        pipelineName = [string]$pipelineName
        pullRequestId = [string]$pullRequestId
        workItemId = [string]$workItemId
    }
    change = $change
    metadata = $metadata
}

$parent = Split-Path $OutputPath -Parent
New-Item -ItemType Directory -Path $parent -Force | Out-Null
$event | ConvertTo-Json -Depth 30 |
    Set-Content -Path $OutputPath -Encoding utf8
return [pscustomobject]$event
