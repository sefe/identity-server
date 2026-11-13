# Evidence-based UI automation maintenance

Apply these rules when UI automation is in scope. They prescribe capabilities and evidence, not a
language, runner, mandatory BDD layer or additional framework. Keep all implementation in authorized
Automation paths; inspect product source read-only.

## Choose the authoring style

Compare BDD with runner-native tests in the blueprint's existing `uiStrategy` and `decisionTradeoffs`.
Choose BDD when maintained business examples, stakeholder collaboration or a concrete test-management
need justify its feature files and bindings. Otherwise prefer direct tests with readable business
names. Explain the choice; neither BDD nor its absence proves stronger coverage. Keep scenario intent
separate from route/locator details through small reusable page/component or equivalent adapters.

## Make changes traceable

Specify a compact, versioned UI coverage map in an authorized automation path. Reuse an existing
traceability mechanism when it provides the same information. Give each journey a stable logical ID,
business intent, source revision/repository, relevant product source paths, routes, role/state inputs,
automation files and observable assertions. Source paths and display titles are mutable metadata,
not the sole identity. Record discovered, implemented, skipped and executed states separately.
Store no credentials or browser session secrets in the map.

Read actual screens/components, router/navigation configuration, guards and shared controls. Assess
applicable validation, loading, empty, error, recovery and forbidden-action states as well as the
positive journey. Do not count an ignored scaffold or an API/unit check as browser execution. Do not
turn every source file or every unit-tested detail into a mandatory browser test.

## Update navigation without changing the meaning of a test

Treat URL routes, element locators and repository file paths as different kinds of change.
Use the supplied base/head revisions, changed-file evidence, the saved coverage map and current
implementation to establish correspondence. A deleted/added file pair alone does not prove a rename.
If baseline evidence is missing or truncated, state that limitation and the extra inspection needed.
Do not silently claim full change analysis from the current source alone.

For a proven move or equivalent control change, update the affected navigation/page adapters,
locators, source references and relevant pipeline filters together. Preserve the journey ID and
business assertions. A changed requirement needs its own evidence and review; current behavior alone
does not authorize rewriting an expectation to match a regression. Missing controls, broken guards,
changed roles and unrelated replacement pages are not harmless path drift.

Use stable existing user-facing locators or explicit test IDs where appropriate to the chosen runner.
Never add test IDs to product code. Do not silently retry with progressively broader locators, pick an
arbitrary match, skip a failed step or weaken an assertion to obtain a pass. Keep navigation targets
and required auth origins explicitly configured. Credentials must be checked before a protected
journey runs; missing accounts are execution prerequisites, not successful coverage.

## Reuse the maintenance workflow

For UI changes, use the existing change-impact / work-item implementation / failed-build triage lanes
to propose focused Automation changes, verify them and publish a reviewed PR. Analyse shared routes,
guards and components for all affected journeys. Reuse existing findings and scenario identities;
do not regenerate the entire framework or duplicate work items on every change.

Describe which product repository event and revision start analysis, which paths/dependencies matter,
and which automation pipeline runs the result. If product and Automation repositories are separate,
an Automation-only path trigger does not observe product changes: name the actual cross-repository
handoff and report it as unverified until wired and tested. Do not modify a product pipeline to invent
that handoff outside the authorized scope.

Run affected tests and justified neighbouring journeys. Broaden the selection when shared components
or incomplete mapping make narrow selection unreliable. Retain commands, discovered/executed counts,
failures and diagnostics. Missing credentials or a browser environment leave execution unverified;
compilation and mapping checks cannot establish that a repaired user journey works.

Use isolated scenario state, guaranteed cleanup even if diagnostics fail, unique artifact paths and
bounded/redacted failure evidence. Prefer observable readiness and retrying assertions over sleeps or
blanket network-idle waits. A trace/screenshot is useful evidence, not a substitute for an assertion.

If synchronizing business scenarios to Test Cases, use real runner discovery/metadata to establish
identity and AI only to explain behavior. Do not invent runner IDs, trust stale generated metadata or
derive permanent identity solely from a mutable title/path. Keep examples associated with their
scenario, retain rename history and flag ambiguous/orphaned links without silently deleting them.

These are design and review requirements. Do not claim that describing them implemented or validated
a route updater, test-management adapter or live maintenance pipeline.
