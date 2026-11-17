# Bootstrap readiness and short feedback loops

The preliminary deliverable is an Automation API project and an Automation UI project,
with tests for behaviour evidenced in the current product, a reviewed change set and a PR.
Agents may justify up to two additional projects, for a maximum of four. Product implementation and product package
configuration are read-only. Unimplemented product features are documented as unavailable
coverage, never reported as tested or used as a reason to invent product changes.

Build 973331 passed authentication and dependency resolution, then stopped at test planning:
execution inputs (administrator accounts, deployed services, broker access) were classified as
omitted planning deliverables. Plans must retain supported scenarios and link their future inputs
and owners through `details.executionPrerequisites`. Implement their real assertions against
symbolic configuration; a deployed suite rejects missing configuration before execution. Local
validation remains environment-free, and deployed coverage remains unexecuted until verified.
Do not clear real omitted work, invent load thresholds, or replace functional coverage with smoke.

Package range notation is checked when the architect's artifact is accepted, before specialist
reviews. Feed lookup and restore/build compatibility are still checked by toolchain resolution.
The NuGet adapter accepts versions and intervals, but not partial wildcards such as `10.0.*`.

Build 973338 exposed a second boundary: a sequential stage passed an incomplete framework
inventory to the test agent. That turned four repairable output-budget omissions into downstream
dependency blockers. Sequential agents now wait until their predecessor's artifact and coverage
sidecar declare no omitted work; bounded owner revisions use the existing inventory merge before
dependent agents run. Real external blockers and unreadable coverage records still stop the stage.

A known error response is not evidence of an available fault-injection mechanism. Planning must
identify a supported stimulus before requiring a controlled-fault test; otherwise it records the
requirement and missing trigger as an uncovered risk without inventing a product modification.

Build 973357 stopped because the test agent assumed that valid XLSX upload data required a new
ZIP-writing dependency. `prompts/shared/fixtures/single-column-prices.json` now supplies a real,
hash-identified XLSX with numeric A1=10 and A2=20. Relevant implementation and change-generation
requests include its bytes; generated Automation owns its copy and uploads the decoded buffer.
It was checked with the product's SheetJS 0.18.5 parser and its array-to-matrix options. This proves
the fixture is readable, not that the browser journey passed. Regenerate it with
`scripts/New-SpreadsheetFixture.ps1 -OutputPath prompts/shared/fixtures/single-column-prices.json`.

## Before a cloud run

Run the fast regression group from the checkout root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File foundry/scripts/Invoke-Tests.ps1 -Suite Stability
```

This group covers relay identity/integrity, interrupted handovers, controlled recovery,
completion reasons and an isolated minimal .NET build when the SDK is installed.
It does not certify the generated product tests or cloud credentials.

The cloud job checks credentials and tools before agent work. After architecture, a
deterministic probe installs the selected npm/NuGet dependencies and checks a minimal
project before spending time on implementation. Final framework verification still builds
and checks the actual generated files. Local checks must not require a deployed product;
deployed UI/API suites require their declared endpoints, credentials and test data.

Publish the Foundry changes to the branch the build will use before queuing it. For the
first build with these contracts use:

| Parameter | Value |
| --- | --- |
| `phase` | `Plan` |
| `resumeFromBuildId` | `none` |
| `resumeRunId` | `none` |
| `restartStage` | `none` |

Keep the existing agent pool and credential variable group. A local PAT read check does
not prove the pipeline variable group has the same valid token or write permissions.

`Plan` produces the PR. After the reviewed installation is merged into the target branch,
`Auto`/`Finalize` registers the pipeline definitions from the merged plan. A passing mock
rehearsal is not evidence that cloud delivery or deployed tests have run successfully.

## Reproduce a failed deterministic stage without agent calls

Download the evidence and select the exact `run-*` directory named in its state:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File foundry/scripts/Replay-FoundryStage.ps1 `
  -RunRoot '<downloaded-evidence>/run-<id>' `
  -StageId bootstrap-change-materialization
```

`framework-verification` is the other supported stage. Replay copies the evidence into a
sibling directory and executes only that stage with the current Foundry implementation.
It makes no agent calls or delivery mutations and preserves the original workflow state.
It is diagnostic: it does not certify that old source or prompts match the current run.
The recorded toolchain must be installed locally; a different Node/npm version is a
prerequisite failure. On Windows use a short workspace path for package/build output.

## Resume and recover

Each relay artifact has a build/leg identity, an explicit active run and a complete SHA-256
file manifest. Restore validates it before copying into an empty destination. It never
chooses an analysis run by directory age and never overlays another build's evidence.

Ordinary paused runs resume with matching source, configuration, policy, workflow and
prompt/schema fingerprints. Budget changes may extend a run without invalidating its inputs.
An explicit `restartStage` archives that stage and downstream evidence before retrying;
upstream evidence is retained. Recovery refuses stages that may already have external effects.

Changed product inputs or contracts require restarting from `discovery` or a fresh run.
Legacy artifacts without fingerprints cannot safely resume downstream. Importing them
requires the exact `resumeRunId` and `restartStage: discovery`; use diagnostic replay when
the purpose is to reproduce one old failure cheaply.

Budget omissions and repairable generated-artifact defects may request a bounded revision.
Missing access, an explicitly required unavailable product capability and unclassified
legacy omissions stop with their own reason instead of consuming generation retries.

## Discovery reconciliation

Discovery publishes its three source artifacts and a compact model decision. The runtime
composes `discovery-result.json` by copying complete stack facts from repository discovery
and recording each source's path and SHA-256. Downstream agents retain the full requirements,
flows, contradictions and execution prerequisites in those sources; synthesis does not need
to transcribe them or report their omission from a summary as unfinished work.

A completed reconciliation cannot also declare deferred discovery work. Its schema rejects
that inconsistency during the model retry loop. Real discovery blockers require an explicit
`blockingContext`; future environment provisioning, unresolved product expectations and
unimplemented features are preserved as findings for planning, not prerequisites for discovery.
Interrupted composition reuses validated source artifacts and the compact decision.

## Dependency changes during implementation

Implementation agents can emit `dependencyRequests` for a new package or a version change.
Each request names an existing toolchain, package, exact version or compatibility range,
scope, scenario need, version rationale and inspected evidence. Prefer a suitable stable
release; an explicit prerelease requires a capability stable versions cannot provide.
The project config has no fixed direct-package count limit (`max_direct_packages: 0`).
Configured package feeds, ecosystem adapters and project write scopes still apply.

`Resolve-DependencyRequests.ps1` checks published versions and installs/builds a minimal
candidate project with `Test-ToolchainReadiness.ps1`. It keeps unrelated pins, writes an
immutable lock under `dependency-updates/`, and promotes `context/toolchain-current.json`
only after the probe succeeds. Failed updates leave the active lock unchanged. Requests,
probe results and resolution results remain in relay evidence for review.

The same implementation stage then repeats: the framework owner updates manifests,
configuration and technology rationale before the test agent revises its dependent files.
Discovery and architecture do not repeat. Materialization and verification use the active
lock, whose hash is checked on read. A relay replay preserves the requirement to revise
old inventories even when dependency promotion already completed. Full framework validation
still checks the generated code; a minimal dependency probe does not certify product tests.

The active model pool is Claude Opus 5, Gemini 3.7 Flash and GPT-5.6 Sol. Profiles request
`high`, now passed to Copilot CLI as `--reasoning-effort=high`, rather than only an internal
Foundry environment variable. Model availability and supported effort levels are ultimately
provided by the Copilot account and model backend.
