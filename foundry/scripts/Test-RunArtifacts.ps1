[CmdletBinding()]
param([Parameter(Mandatory)][string]$RunRoot)

if (-not (Test-Path -LiteralPath $RunRoot -PathType Container)) {
    throw "Run artifact directory does not exist: $RunRoot"
}

$root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$schemaByName = @{
    "repository.json" = "schemas/runtime/repository-context.schema.json"
    "run-configuration.json" = "schemas/runtime/run-configuration.schema.json"
    "sdlc-event.json" = "schemas/runtime/sdlc-event.schema.json"
    "ci-evidence.json" = "schemas/runtime/ci-evidence.schema.json"
    "work-item.json" = "schemas/runtime/work-item-context.schema.json"
    "toolchain-lock.json" = "schemas/runtime/toolchain-lock.schema.json"
    "copilot-preflight.json" = "schemas/runtime/copilot-preflight.schema.json"
    "workflow-state.json" = "schemas/runtime/workflow-state.schema.json"
    "repository-discovery.json" = "schemas/discovery/repository-discovery.schema.json"
    "requirements-discovery.json" = "schemas/discovery/requirements-discovery.schema.json"
    "delivery-environment-discovery.json" = "schemas/discovery/delivery-environment-discovery.schema.json"
    "discovery-result.json" = "schemas/discovery/discovery-result.schema.json"
    "automation-blueprint.json" = "schemas/architecture/automation-blueprint.schema.json"
    "revision-ledger.json" = "schemas/architecture/revision-ledger.schema.json"
    "architecture-review.json" = "schemas/architecture/architecture-review.schema.json"
    "architecture-security-review.json" = "schemas/architecture/architecture-specialist-review.schema.json"
    "architecture-delivery-review.json" = "schemas/architecture/architecture-specialist-review.schema.json"
    "api-test-plan.json" = "schemas/planning/api-test-plan.schema.json"
    "ui-test-plan.json" = "schemas/planning/ui-test-plan.schema.json"
    "risk-test-plan.json" = "schemas/planning/risk-test-plan.schema.json"
    "automation-plan.json" = "schemas/planning/automation-plan.schema.json"
    "framework-implementation.json" = "schemas/implementation/implementation-result.schema.json"
    "test-implementation.json" = "schemas/implementation/implementation-result.schema.json"
    "execution-plan.json" = "schemas/execution/execution-plan.schema.json"
    "execution-result.json" = "schemas/execution/execution-result.schema.json"
    "failure-analysis.json" = "schemas/execution/failure-analysis.schema.json"
    "root-cause-analysis.json" = "schemas/operations/failure-investigation.schema.json"
    "change-correlation-analysis.json" = "schemas/operations/failure-investigation.schema.json"
    "evidence-integrity-analysis.json" = "schemas/operations/failure-investigation.schema.json"
    "verified-failure-analysis.json" = "schemas/operations/verified-failure-analysis.schema.json"
    "remediation-plan.json" = "schemas/operations/remediation-plan.schema.json"
    "remediation-safety-review.json" = "schemas/operations/remediation-review.schema.json"
    "remediation-value-review.json" = "schemas/operations/remediation-review.schema.json"
    "remediation-operations-review.json" = "schemas/operations/remediation-review.schema.json"
    "code-review.json" = "schemas/review/code-review.schema.json"
    "test-quality-review.json" = "schemas/review/test-quality-review.schema.json"
    "security-resilience-review.json" = "schemas/review/security-resilience-review.schema.json"
    "change-summary.json" = "schemas/delivery/change-summary.schema.json"
    "pull-request-compliance.json" = "schemas/delivery/pull-request-compliance.schema.json"
    "delivery-security-review.json" = "schemas/delivery/delivery-specialist-review.schema.json"
    "release-risk-review.json" = "schemas/delivery/delivery-specialist-review.schema.json"
    "quality-evidence.json" = "schemas/runtime/quality-evidence.schema.json"
    "observability-evidence.json" = "schemas/runtime/observability-evidence.schema.json"
    "action-result.json" = "schemas/actions/action-result.schema.json"
    "work-item-plan.json" = "schemas/actions/work-item-plan.schema.json"
    "change-set.json" = "schemas/actions/change-set.schema.json"
    "change-set-plan.json" = "schemas/actions/change-set-plan.schema.json"
    "materialization-plan.json" = "schemas/actions/materialization-plan.schema.json"
    "approved-paths.json" = "schemas/runtime/approved-path-coverage.schema.json"
    "batch-basis.json" = "schemas/runtime/batch-basis.schema.json"
    "repair-instructions.json" = "schemas/runtime/repair-instructions.schema.json"
    "change-review-subject.json" = "schemas/actions/change-review-subject.schema.json"
    "resolver-evidence.json" = "schemas/runtime/resolver-evidence.schema.json"
    "toolchain-evidence.json" = "schemas/runtime/toolchain-resolution-evidence.schema.json"
    "framework-verification.json" = "schemas/runtime/framework-verification.schema.json"
    "correctness-review.json" = "schemas/sdlc/review.schema.json"
    "quality-review.json" = "schemas/sdlc/review.schema.json"
    "security-review.json" = "schemas/sdlc/review.schema.json"
    "impact-product.json" = "schemas/sdlc/analysis.schema.json"
    "impact-architecture.json" = "schemas/sdlc/analysis.schema.json"
    "impact-quality.json" = "schemas/sdlc/analysis.schema.json"
    "product-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "architecture-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "risk-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "testability-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "engineering-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "quality-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "accuracy-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "code-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "user-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "functionality-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "security-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "operations-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "application-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "infrastructure-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "change-analysis.json" = "schemas/sdlc/analysis.schema.json"
    "impact-synthesis.json" = "schemas/sdlc/synthesis.schema.json"
    "requirements-synthesis.json" = "schemas/sdlc/synthesis.schema.json"
    "implementation-synthesis.json" = "schemas/sdlc/synthesis.schema.json"
    "documentation-synthesis.json" = "schemas/sdlc/synthesis.schema.json"
    "release-synthesis.json" = "schemas/sdlc/synthesis.schema.json"
    "incident-synthesis.json" = "schemas/sdlc/synthesis.schema.json"
}

$validated = @()
$schemaByName['run-inputs.json'] = 'schemas/runtime/run-inputs.schema.json'
$schemaByName['prerequisites.json'] = 'schemas/runtime/prerequisites.schema.json'
$schemaByName['toolchain-smoke.json'] = 'schemas/runtime/prerequisites.schema.json'
$schemaByName['rejected-toolchain-lock.json'] = 'schemas/runtime/toolchain-lock.schema.json'
$schemaByName['toolchain-current.json'] = 'schemas/runtime/toolchain-current.schema.json'
$schemaByName['discovery-decision.json'] = 'schemas/discovery/discovery-decision.schema.json'
$schemaByName['product-defect-analysis.json'] = 'schemas/operations/failure-investigation.schema.json'
$schemaByName['product-defect-review-1.json'] = 'schemas/operations/failure-investigation.schema.json'
$schemaByName['product-defect-review-2.json'] = 'schemas/operations/failure-investigation.schema.json'
$schemaByName['product-defect-plan.json'] = 'schemas/actions/work-item-plan.schema.json'
$schemaByName['product-defect-bugs.json'] = 'schemas/actions/action-result.schema.json'
foreach ($artifact in @(Get-ChildItem -Path $RunRoot -Filter "*.json" -File -Recurse)) {
    # Recovery archives preserve previous contracts and are not current outputs.
    $relative = [IO.Path]::GetRelativePath($RunRoot, $artifact.FullName).Replace('\', '/')
    if ($relative.StartsWith('recovery/')) { continue }
    # Downloaded source documents are inputs, not generated agent artifacts.
    # Their exact bytes are verified by the source manifest and run fingerprint.
    if ($relative.StartsWith('documentation/') -and $artifact.Name -ne 'sources.json') { continue }
    if ($relative.StartsWith('supervisor/') -and $artifact.Name -like "escalation-*") {
        continue
    }
    # A provider's own token counts, left beside the request it answered. The
    # runtime reads them into the call's record and deletes the file; one that
    # survives an interruption is a provider's output in a provider's shape, not
    # an artifact of this run, and there is no schema of ours it could meet.
    if ($artifact.Name -like "*.usage.json") { continue }
    $schemaRelative = if ($relative -eq 'documentation/sources.json') {
        'schemas/runtime/documentation-sources.schema.json'
    }
    elseif ($relative -eq 'report.json') {
        'schemas/runtime/run-report.schema.json'
    }
    elseif ($relative.StartsWith('supervisor/') -and $artifact.Name -match '^supervisor-decision-\d+\.json$') {
        'schemas/supervisor/supervisor-decision.schema.json'
    }
    elseif ($artifact.Name -like '*.revision.json') {
        'schemas/architecture/blueprint-revision.schema.json'
    }
    elseif ($artifact.Name -like '*-dependency-resolution.json') {
        'schemas/common/agent-result.schema.json'
    }
    elseif ($relative.StartsWith('dependency-updates/') -and $artifact.Name -eq 'requests.json') {
        'schemas/runtime/dependency-requests.schema.json'
    }
    elseif ($relative.StartsWith('dependency-updates/') -and $artifact.Name -eq 'readiness.json') {
        'schemas/runtime/prerequisites.schema.json'
    }
    elseif ($artifact.Name -like "*.coverage.json") {
        # Written beside every agent artifact, saying whether the answer is the
        # whole answer. Matched before the run-time batch names below, because a
        # batch's coverage record is still a coverage record.
        "schemas/runtime/agent-coverage.schema.json"
    }
    elseif ($artifact.Name -like "*.provider-metadata.json") {
        "schemas/runtime/provider-metadata.schema.json"
    }
    elseif ($artifact.Name -like "*.repair.applied.json") {
        # Written beside an artifact whose overlong prose was shortened on
        # request rather than regenerated, so the evidence says what changed.
        "schemas/runtime/field-repair.schema.json"
    }
    elseif ($artifact.Name -like "change-set-batch-*.json") {
        # One batch per generator call, so the names are made at run time. They
        # are still artifacts of the run and still have to hold up to a schema.
        "schemas/actions/change-set-batch.schema.json"
    }
    elseif ($artifact.Name -like "assignment-batch-*.json") {
        "schemas/runtime/batch-assignment.schema.json"
    }
    elseif ($artifact.Name -like "carried-batch-*.json" -or $artifact.Name -like 'repair-source-batch-*.json') {
        "schemas/runtime/carried-batch-context.schema.json"
    }
    else {
        $schemaByName[$artifact.Name]
    }
    if (-not $schemaRelative) {
        throw "No schema mapping exists for generated artifact: $($artifact.FullName)"
    }
    $null = & (Join-Path $PSScriptRoot "Validate-JsonArtifact.ps1") `
        -ArtifactPath $artifact.FullName `
        -SchemaPath (Join-Path $root $schemaRelative) `
        -SchemaRoot (Join-Path $root "schemas")
    $validated += $artifact.FullName
}
return [pscustomobject]@{
    valid = $true
    artifactCount = $validated.Count
    artifacts = $validated
}
