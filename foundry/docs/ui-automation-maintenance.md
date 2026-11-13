# UI automation: analysis and adoption decisions

Reviewed on 22 September 2026. The source is `C:/pricing-service`, local revision
`be0456555601634a8d1d8ea17dd3e7e5859a3b7e`. The inspected UI scaffold, UI analysis pipeline,
scenario-discovery/sync scripts and UI execution pipeline have no differences from the local
`origin/develop` snapshot `5aaf89821387465abfadcc651eb620a918ca725a`. This is a source review;
no authenticated browser journey or remote pipeline was run.

## What exists today

`CommodityPricingService.UI.Automation` is a C#/Playwright foundation with both Reqnroll bindings
and an MSTest base class. `Drivers/PlaywrightSession.cs` owns a browser context, navigation and
failure evidence. `Support/UiAutomationSettings.cs` combines defaults, JSON settings and environment
overrides. `Features/UiSmoke.feature` contains one ignored placeholder scenario.

`NavigateAsync` combines a supplied URL with a configured base URI. It does not inspect product
routes, infer moved controls or update test files. There is no implemented automatic route/locator
repair in this scaffold.

The complementary QA Copilot flow is more substantial:

- `qa-copilot/prompts/analyze-ui-spec-coverage.md` compares implemented UI behavior with browser
  scenarios, including validation, empty/error states, authorization and forbidden actions.
- `qa-copilot/pipelines/ui-spec-coverage-analysis.yml` runs that analysis weekly or manually.
  Task creation is optional and defaults to false; this is not a repair on every product commit.
- The common implementation and failure-triage flows can process UI work in Automation scope.
- `Get-UiTestScenarios.ps1` reads Gherkin and generated Reqnroll metadata; `Sync-TestCaseWorkItems.ps1`
  validates enriched descriptions against that inventory, updates changed fields and flags orphans.
  The generated fully qualified test name can itself change on a rename; generated-line matching
  alone does not provide a permanent cross-version business identity.

## What to carry into Foundry

| Existing idea | Decision for generated UI frameworks |
| --- | --- |
| Browser lifecycle separate from scenario steps | Keep the separation. Let agents choose a small page/component adapter design suited to the app and runner. |
| Central environment/browser settings | Keep explicit non-secret configuration and early validation; supply credentials from the secret store. |
| Screenshots, HTML and per-test logs | Keep useful bounded diagnostics, with redaction, unique paths and guaranteed cleanup even when capture fails. |
| Compare product behavior with scenarios | Keep evidence-based reconciliation, including rejection, loading, error and role-dependent states where relevant. |
| Shared implementor and failure triage | Reuse Foundry's existing change-impact, implementation and triage lanes for scoped repairs and reviewed PRs. |
| Gherkin plus generated runner metadata | Adopt the separation of deterministic identity and AI-authored business explanation when BDD/Test Case sync is selected. |
| Ignore placeholders in coverage claims | Preserve distinct discovered, implemented, skipped and actually executed states. |

BDD is an agent decision. It is useful when business participants maintain examples or there is a
real need to share scenario descriptions with test management. Otherwise direct runner tests with
clear business names avoid a second authoring layer. Change analysis and route/locator maintenance
must work with either style; neither requires one specific language.

## How paths should be maintained

Generate a versioned journey-to-source map in Automation, or reuse equivalent existing metadata.
Stable logical journey IDs point to business intent, source revision/repository, product files,
routes, role/state prerequisites, automation files and assertions. Paths and titles may change;
they must not be the sole permanent identity.

The intended maintenance flow is:

1. A product change supplies base/head revisions and changed-file evidence.
2. Agents assess affected journeys, including shared controls, navigation and authorization guards.
3. A proven move or equivalent locator change updates the appropriate adapters and map. A changed
   requirement needs separate evidence; a regression retains its failing assertion and follows triage.
4. The implementor verifies affected and relevant neighbouring tests and publishes the scoped PR.
   Missing credentials leave browser execution unverified, even if compilation passes.

Source file paths, URL routes and element locators are different things. A deleted/added file pair
does not prove a rename, and a similarly labelled button does not prove equivalent behavior. Foundry's
current event collector reports changed files using `--no-renames`; agents need the saved map or
additional evidence to establish correspondence. Incomplete/truncated baselines remain explicit.

For separate product and Automation repositories, an Automation-only CI trigger cannot observe
product commits. The generated delivery plan must name and verify the cross-repository event handoff.
The current scaffold's `pipelines/automation-ui.yaml` watches automation/configuration paths only;
that filter should not be copied as a complete product-change trigger.

## What not to copy unchanged

The scaffold uses `NetworkIdle` for navigation, permits arbitrary absolute navigation URLs, defaults
to ignoring HTTPS errors, and captures diagnostics before cleanup without a `finally` boundary.
Artifact names use second-level timestamps, so parallel scenarios with the same name may collide.
These are reasons to adopt the structure with stronger implementation contracts, not to copy files
verbatim or claim the scaffold is already a production-ready browser suite.

For Playwright-based choices, prefer observable readiness and existing role/label or suitable test-ID
locators, as described by the official [locator guidance](https://playwright.dev/docs/locators) and
[page readiness API](https://playwright.dev/docs/api/class-page#page-wait-for-load-state).
Do not modify product code to add test IDs. Diagnostic capture must not replace business assertions.

## Delivery status of this change

Foundry now has shared design/review instructions for these capabilities, connected to bootstrap
and maintenance agent requests. The configured framework ceiling is four, not a quota; agents decide
whether additional API frameworks are justified. API and UI remain the explicit minimum deliverables.

Existing `change-impact.yaml` can file reviewed work and queue `implement-work-item.yaml`, which
applies scoped changes, runs quality verification and performs delivery review. These existing lanes
are reused by the instructions. This change does not implement a universal UI parser, migrate the
current pricing scaffold, deploy a new cross-repository trigger or prove a successful live repair.
Generated maps/adapters, runner-specific test identities and event wiring still require implementation
and verification for the selected product. The pricing-service repository was not modified.
