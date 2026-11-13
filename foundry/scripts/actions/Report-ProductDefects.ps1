[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$VerificationPath,
    [Parameter(Mandatory)][string]$ChangeSetPath,
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$RunId,
    [Parameter(Mandatory)][object]$Config,
    [Parameter(Mandatory)][object]$Policy,
    [Parameter(Mandatory)][scriptblock]$Analyzer,
    [hashtable]$ActionEnvironment = @{},
    [AllowNull()][scriptblock]$Writer = $null
)
. (Join-Path $PSScriptRoot '../Common.ps1')
. (Join-Path $PSScriptRoot '../ProductDefects.ps1')
. (Join-Path $PSScriptRoot '../GenerationRepair.ps1')
$verification = Get-Content $VerificationPath -Raw | ConvertFrom-Json -Depth 100
$changeSet = Get-Content $ChangeSetPath -Raw | ConvertFrom-Json -Depth 100
if ($verification.runId -cne $RunId -or $changeSet.runId -cne $RunId) { throw 'Product-defect evidence belongs to another run.' }
$cases = @()
$logs = @()
foreach ($project in @($verification.projects)) {
    if ($project.testsFailed -le 0 -or $project.outcome -eq 'infrastructure_unavailable') { continue }
    foreach ($step in @($project.steps | Where-Object { $_.name -eq 'test' -and $_.status -eq 'failed' })) {
        $reference = [regex]::Match($step.detail, 'Full output: (commands/[\w.-]+\.log) \[sha256: ([a-f0-9]{64})\]')
        if (-not $reference.Success) { continue }
        $path = Join-Path (Split-Path $VerificationPath) $reference.Groups[1].Value
        if (-not (Test-PathWithinRoot -Candidate $path -Root (Split-Path $VerificationPath)) -or
            -not (Test-Path -LiteralPath $path -PathType Leaf) -or
            (Get-FileHash $path).Hash -ne $reference.Groups[2].Value) { throw 'Product-defect test log changed after verification.' }
        $text = Get-Content $path -Raw
        $cases += @(Get-QaFoundryFailedTestCases -Text $text -ProjectPath $project.projectPath)
        $logs += [pscustomobject]@{ path = $path; text = $text }
    }
}
if ($cases.Count -eq 0) { return [pscustomobject]@{ artifacts = @(); confirmed = @(); bugActions = @() } }
$sourceManifest = Get-Content (Join-Path $RunRoot run-inputs.json) -Raw
$key = Get-QaFoundryInputHash -Text ($sourceManifest + (ConvertTo-Json $changeSet.changes -Depth 100 -Compress) +
    (ConvertTo-Json @($cases.sourceRef) -Compress) +
    (ConvertTo-Json @($logs | ForEach-Object { Get-QaFoundryInputHash -Text $_.text }) -Compress))
$directory = Join-Path (Split-Path $VerificationPath) ('product-defects-' + $key.Substring(0,16))
New-Item -ItemType Directory $directory -Force | Out-Null
$inputPath = Join-Path $directory product-defect-evidence.md
$instructions = @'
# Preserve product regression tests and file confirmed defects
Classify actual failed tests using the supplied test identities as sourceRef. These are real execution results; do not substitute older CI events or planning claims.
Report product_defect only when repository requirements establish the expected behavior and the observed execution establishes the product violation. An inconsistent specification, unsupported schema library, incorrect assertion, bad fixture, skipped test or setup failure is not proof of a product bug. Use requirement_mismatch or unknown when the intended behavior is unresolved.
For each product_defect finding, name exactly one supplied test identity as sourceRef and include exactly one "test-path:<delivered relative test path>" and one or more "requirement-path:<repository-relative requirement/source path>" evidence strings. Inspect the cited files. Cite expected and actual behavior in the hypothesis and evidence. Each confirmed product test gets its own traceable finding. Other failure classes may be grouped.
Keep the test and its assertion. Never skip it, mark it expected-failure, change the product or weaken the expectation to obtain a green result. A deterministic writer files a Bug after independent agreement. You cannot create work items yourself.
The evidence auditor must independently check the source and execution. It receives the same evidence, not the first analyst's conclusion.
'@
$parts = @($instructions, "Run: $RunId", "Repository: $RepositoryRoot", "Delivered source artifact: $ChangeSetPath",
    "Failed test identities:`n" + (ConvertTo-Json @($cases | Select-Object sourceRef,testName,projectPath) -Depth 10))
foreach ($log in $logs) { $parts += "Full log: $($log.path)`n$(Get-QaFoundryVerificationFailureDigest $log.text)" }
foreach ($change in @($changeSet.changes)) {
    $leaf = [IO.Path]::GetFileName($change.path)
    if (@($cases | Where-Object { $_.output.Replace('\','/').Contains($leaf) }).Count -gt 0) {
        $parts += "Delivered file: $($change.path)`n$($change.content)"
    }
}
$parts -join "`n`n" | Set-Content $inputPath -Encoding utf8
$analysisPath = Join-Path $directory product-defect-analysis.json
$analysis = & $Analyzer 'failure-root-cause-analyst' $inputPath $analysisPath
$artifacts = @($inputPath,$analysisPath)
$confirmed = @()
if ($analysis.status -eq 'completed' -and @($analysis.findings | Where-Object classification -eq product_defect).Count -gt 0) {
    $minimum = 2
    if ($Config.PSObject.Properties['assurance'] -and $Config.assurance.PSObject.Properties['high_risk_minimum_reviewers']) {
        $minimum = [Math]::Max(2, [int]$Config.assurance.high_risk_minimum_reviewers)
    }
    if ($minimum -gt 3) { throw 'Product-defect reporting supports up to three independent confirmations.' }
    $reviews = @()
    $roles = @('failure-evidence-auditor','failure-change-analyst')
    for ($index = 0; $index -lt ($minimum - 1); $index++) {
        $reviewPath = Join-Path $directory "product-defect-review-$($index + 1).json"
        $reviews += & $Analyzer $roles[$index] $inputPath $reviewPath
        $artifacts += $reviewPath
    }
    $confirmed = @(Get-QaFoundryConfirmedProductDefects -Cases $cases -Analysis $analysis -Review $reviews `
        -ChangeSet $changeSet -RepositoryRoot $RepositoryRoot -MinimumConfirmations $minimum)
}
$buildUrl = ''
if ($env:SYSTEM_COLLECTIONURI -and $env:SYSTEM_TEAMPROJECT -and $env:BUILD_BUILDID) {
    $buildUrl = $env:SYSTEM_COLLECTIONURI.TrimEnd('/') + '/' + [uri]::EscapeDataString($env:SYSTEM_TEAMPROJECT) + '/_build/results?buildId=' + $env:BUILD_BUILDID
}
$plan = New-QaFoundryProductBugPlan -Defects $confirmed -RunId $RunId -BuildUrl $buildUrl
$planPath = Join-Path $directory product-defect-plan.json
$plan | ConvertTo-Json -Depth 100 | Set-Content $planPath -Encoding utf8
$null = & (Join-Path $PSScriptRoot '../Validate-JsonArtifact.ps1') -ArtifactPath $planPath `
    -SchemaPath (Join-Path $PSScriptRoot '../../schemas/actions/work-item-plan.schema.json') `
    -SchemaRoot (Join-Path $PSScriptRoot '../../schemas')
$artifacts += $planPath
$bugActions = @()
if ($confirmed.Count -gt 0) {
    if (-not [bool]$Policy.work_tracking.allow_create -and [bool]$Config.work_tracking.enabled -and -not [bool]$Config.work_tracking.dry_run) {
        throw 'Policy denies creating product-defect Bugs.'
    }
    if ($null -eq $Writer) {
        $receipt = & (Join-Path $PSScriptRoot '../writers/New-WorkItems.ps1') -PlanPath $planPath -Config $Config `
            -RepositoryRoot $RepositoryRoot -RunId $RunId -StageId framework-verification -ActionEnvironment $ActionEnvironment
    }
    else { $receipt = & $Writer $planPath }
    $receiptPath = Join-Path $directory product-defect-bugs.json
    $receipt | ConvertTo-Json -Depth 100 | Set-Content $receiptPath -Encoding utf8
    $null = & (Join-Path $PSScriptRoot '../Validate-JsonArtifact.ps1') -ArtifactPath $receiptPath `
        -SchemaPath (Join-Path $PSScriptRoot '../../schemas/actions/action-result.schema.json') `
        -SchemaRoot (Join-Path $PSScriptRoot '../../schemas')
    $artifacts += $receiptPath
    if (-not $receipt.dryRun -and $receipt.status -eq 'completed') { $bugActions = @($receipt.actions) }
}
return [pscustomobject]@{ artifacts = @($artifacts); confirmed = @($confirmed); bugActions = @($bugActions); cases = @($cases) }
