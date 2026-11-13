# SDLC Foundry for Azure DevOps

SDLC Foundry is a prompt-driven, multi-agent automation system that is placed inside an existing product repository. Its first supported delivery platform is Azure DevOps. It reads the product code, local documentation, requirements and architecture inputs, proposes an automation structure, creates a reviewed change set, and installs the permanent ADO pipelines that keep the lifecycle running.

Automatic merge and production deployment are deliberately unsupported.

Bootstrap also produces an interactive HTML report with project size, verified test
results, technology decisions and model token usage. It accepts project documentation
links and provides concise English progress logs. See
[reports and documentation inputs](docs/reports-and-documentation.md) for launch parameters,
private-source credentials, report locations and measurement limits.

## Product independence and local execution

Foundry must work across product repositories and technologies. The current product is input to a
run, not a platform default. Languages, frameworks, paths and build/start commands come from that
repository's evidence. Technology-specific behavior belongs in ecosystem adapters and generated
Automation projects. Never encode sample-product names or startup assumptions in the shared workflow.
The product repository is read-only; generated implementation belongs in authorized Automation projects.

Local UI execution is an option when the product supports it. Its Automation setup contract must
identify the product checkout, install/build/start commands, runtime configuration, readiness check
and process cleanup, using existing product configuration interfaces. Local startup does not remove
dependencies on identity providers, APIs or other services. Report substituted dependencies explicitly
and distinguish local smoke checks from complete end-to-end coverage. The isolated framework verifier
contains generated artifacts; a product checkout and its resources require an explicit setup contract.

## Updating Foundry while a run is paused

Before recommending resume after a fix, compare the saved run's `run-inputs.json` with the proposed
checkout using `Get-QaFoundryRunInputs` and `Assert-QaFoundryRunInputs`. A selected restart stage does
not waive this check. Prompts and schemas are part of the saved contract: even an additive instruction
invalidates reuse. Keep runtime-only repairs separate from prompt changes. If a prompt change is not
needed for the repair, restore the saved contract before resuming; if it is required, start again from
the first stage with the changed inputs. Never edit saved fingerprints or disable their validation.

When verification exposes a contradiction in an approved file contract, restart `implementation`
on the saved run. The runtime supplies the archived inventories and failed verification as recovery
context, merges incremental inventory revisions, and reuses generated source whose file contracts
remain unchanged. Changed and new contracts receive generation assignments; removed files leave
the plan. Reuse requires matching run inputs and recorded artifact hashes, and selects the last
completed change plan rather than a later blocked partial answer. Reviews, dependency resolution
and executable verification still run. The materialization planner receives carried manifests,
without repeating every unchanged source file in its request.

Verification executes installed tools in an isolated directory on the workspace filesystem.
Only .NET test-platform IPC uses a short private temporary path; placing `node_modules` in a
system temporary directory can prevent execution on agents where that filesystem is `noexec`.
An installed runner denied execution is an infrastructure failure, not a reason to regenerate
its project. Repair batches receive their assigned contracts, existing source, dependencies and
distinct failure details without replaying unrelated reviews or the complete previous change set.

## What is implemented

The runtime currently contains eight SDLC workflows:

| Event | Workflow | Main outcome |
| --- | --- | --- |
| First start / manual | `bootstrap-automation` | repository analysis, test strategy, automation change set and installation plan |
| Push / pull request | `change-impact` | impact analysis and justified ADO backlog items |
| Failed build | `failed-build-triage` | live build, timeline and failed-test evidence; root-cause decision and remediation plan |
| Ready work item | `implement-work-item` | scoped implementation, deterministic quality checks and draft PR |
| Schedule | `requirements-backlog` | requirements gaps converted into reviewed backlog items, each handed to implementation |
| Release candidate | `release-readiness` | functionality, security and operability decision |
| Incident | `incident-response` | evidence-led incident analysis and bounded remediation, started rather than only filed |
| Documentation change | `documentation-update` | documentation/code consistency analysis and reviewed update |

High-risk stages use multiple independent specialists. Critical decisions require three independent reviewers and unanimous approval in the default `maximum` assurance mode. Agent output must satisfy JSON Schema before another stage can consume it.

Deterministic code, not an LLM, performs all external writes:

- scoped repository file creation and update;
- branch, commit and non-force push;
- Azure DevOps draft pull request creation;
- Azure Boards PBI, Task and Bug creation;
- live Azure Pipelines build, timeline and failed-test collection;
- Azure Pipeline definition registration and optional smoke queueing.

Executed actions use stable idempotency keys. Repeated work-item, repository and delivery actions are reused instead of duplicated.

## First start: opening the factory gate

The installer is intentionally two-phase.

1. A person creates one Azure Pipeline from [`pipelines/azure-devops/first-start-bootstrap.yml`](pipelines/azure-devops/first-start-bootstrap.yml) and runs it manually.
2. `Plan` validates the configuration, optionally runs the full multi-agent bootstrap analysis, and requires unanimous review of the generated change set.
3. The deterministic installer adds managed ADO YAML, an installation plan and a pre-merge state marker.
4. Scope and quality checks run. If enabled by both config and policy, Foundry creates one automation branch and one **draft** PR.
5. After a person merges that PR into the configured target branch, the same bootstrap pipeline runs `Finalize` automatically.
6. `Finalize` verifies the configuration hash and every managed YAML hash, then creates or reuses the permanent ADO pipeline definitions. An optional smoke run can be queued.
7. The bootstrap pipeline remains manual-capable as a repair and upgrade entrance. It does not delete itself.

On a feature or PR branch, `Auto` detects the merged plan is not yet on the target branch and exits with `awaiting_merge`. On the target branch it finalizes. Repeated finalization is safe because definitions are matched by exact folder and name.

## Repository layout after installation

Assuming the framework folder is named `foundry`:

```text
product-repository/
├── foundry/                         # this framework
│   ├── bootstrap/foundry.bootstrap.yaml
│   └── config/project.yaml
├── .foundry/                        # installer-owned, reviewed files
│   ├── installation-plan.json
│   ├── installation-state.json      # awaiting-merge marker
│   └── pipelines/
│       ├── sdlc-router.yml
│       └── failed-build-triage.yml
├── automation/                      # agent-selected test project(s)
└── .qa-foundry-artifacts/           # ignored run evidence
```

The final `installed` state, including ADO pipeline IDs and smoke-run IDs, is published as a bootstrap pipeline artifact. It is not committed directly to the protected target branch.

## Minimal setup

1. In [`bootstrap/foundry.bootstrap.yaml`](bootstrap/foundry.bootstrap.yaml), set the ADO organization, project and repository ID.
2. In [`config/project.yaml`](config/project.yaml), set the target paths. When Foundry is a `foundry/` folder inside the product repo, `target.repository_path` is normally `../..`.
3. Add `.foundry/` and the desired automation roots to `repository.allowed_write_paths`.
4. Point the bootstrap config at [`policies/bootstrap-policy.yaml`](policies/bootstrap-policy.yaml). It permits only reviewable repository delivery; merge, production deployment and work-item creation stay denied. The stricter [`policies/default-policy.yaml`](policies/default-policy.yaml) denies every external write.
5. Create or reuse the `sdlc-foundry-secrets` variable group and add a secret variable named `AZURE_DEVOPS_TOKEN`. It must be a PAT owned by the person whose identity should appear on commits, pushes, pull requests and work items. Grant only the ADO scopes required by the enabled writers. `System.AccessToken` is deliberately not accepted for writes because it acts as the build service.
6. Configure every live ADO writer with `auth_env: AZURE_DEVOPS_TOKEN` and `auth_scheme: basic`. `expected_user_id` can pin the PAT to one ADO identity; `match_build_requester: true` also rejects a manually requested build when the requester does not own the PAT. Scheduled and completion-triggered builds continue to use the configured PAT owner.
7. Add a secret pipeline or variable-group variable named `COPILOT_GITHUB_TOKEN`. It must authenticate a user who has an active Copilot seat. A fine-grained personal access token needs the account-level **Copilot Requests** permission; a classic `ghp_` PAT is not supported by Copilot CLI. The token's **resource owner must be the user account, not an organisation** — an organisation-owned token is not offered the Copilot permission at all, so it authenticates against GitHub normally and is then refused by every agent.
8. Create the first-start pipeline from the YAML above and run it with `phase: Auto`.

The credential value is never stored in project configuration. Configuration names the
environment variable that supplies it:

```yaml
delivery:
  azure_devops:
    auth_env: AZURE_DEVOPS_TOKEN
    auth_scheme: basic
    expected_user_id: ""
    match_build_requester: true
```

For local runs, `secrets.source` may be `environment` or an uncommitted external file.
Hosted pipelines obtain the same variable from `sdlc-foundry-secrets`.

The bootstrap and every generated ADO job that calls Foundry first run the reusable [`setup-copilot-cli.yml`](pipelines/azure-devops/templates/setup-copilot-cli.yml) step template. It selects Node.js 22, downloads the official `@github/copilot` npm package on that job's agent, and verifies the CLI before any agent starts. This is a step in the consuming job, not a separate job: Microsoft-hosted jobs do not share an installed filesystem.

Safe defaults are dry-run. A real draft-PR plan requires both configuration and policy opt-in:

```yaml
# config/project.yaml
delivery:
  provider: azure-devops
  dry_run: false
  apply_changes: true
  create_branch: true
  commit_changes: true
  push_branch: true
  create_draft_pull_request: true
  # ...
```

```yaml
# project policy
delivery:
  allow_repository_changes: true
  allow_branch_creation: true
  allow_commit: true
  allow_push: true
  allow_draft_pull_request: true
  allow_merge: false
  allow_production_deploy: false
```

## Agent model configuration

The active profile remains the fallback for a deliberately single-model run. Normal live
multi-agent runs enable a collaboration pool so independent agents are distributed across
different model families without increasing the number of model calls:

```yaml
ai:
  active_profile: copilot
  collaboration:
    enabled: true
    profiles: [copilot, codex, sol]
    assignment: deterministic_round_robin
  profiles:
    copilot:
      provider: copilot-cli
      model: claude-opus-5
      reasoning_effort: high
      command: copilot
      timeout_seconds: 1500
      secret_env: [COPILOT_GITHUB_TOKEN, GH_TOKEN, GITHUB_TOKEN]
      provider_options:
        install_mode: npx-if-missing
        package: "@github/copilot"
        package_version: latest
        auth_mode: auto
        allow_stored_credentials_in_ci: false
    codex:
      provider: copilot-cli
      model: gpt-5.3-codex
      # same transport, timeout, secret_env and provider_options
```

The configured pool currently combines Claude Opus, GPT-5.6 Sol and GPT-5.3 Codex.
Gemini remains configured for a one-run `-AiProfile` override but no longer
receives agents by default. A stable stage offset and agent ordinal assign
adjacent agents distinct profiles until the pool is exhausted. The same run, stage and
iteration therefore receive the same assignment after a relay resume. Every parallel
agent gets a private configuration copy, so model selection cannot race between runspaces.

The model is configuration, not runtime code. The Copilot account and CLI decide whether a configured model is available. A missing or unavailable configured model fails its stage; Foundry does not silently substitute an unconfigured model. Supplying a one-run `-AiProfile`, `-Model`, `-ReasoningEffort`, or `-Demo` override disables collaboration for that run. `mock` is a deterministic no-key profile used by tests and demos; it never proves that a live model or customer ADO instance works.

Copilot authentication follows the CLI's precedence: `COPILOT_GITHUB_TOKEN`, then `GH_TOKEN`, then `GITHUB_TOKEN`, then a stored Copilot OAuth login or `gh auth token`. The last two options are convenient locally. A Microsoft-hosted ADO agent is ephemeral, so the normal CI setup is the secret `COPILOT_GITHUB_TOKEN`. A deliberately pre-authenticated self-hosted agent can opt in to stored credentials with `allow_stored_credentials_in_ci: true`.

Secrets can come from the process environment or from a file outside the target repository. Model processes receive only the environment names listed by the selected AI profile. Undefined ADO macros such as literal `$(COPILOT_GITHUB_TOKEN)` are discarded rather than sent as fake credentials. Surrounding whitespace is stripped, because a token pasted into a variable group often carries a trailing newline that GitHub then rejects. The ADO token is kept in the deterministic action environment and is not forwarded to agents.

The bootstrap pipeline verifies the Copilot credential before it installs dependencies or starts any agent, so a bad credential fails in seconds with one actionable line instead of surfacing later as a parallel-agent exception. It checks two separate things, because they fail separately. First the token is authenticated against `api.github.com/user`, which rejects classic `ghp_` tokens outright and reports the login on success. That proves only that the token is a real GitHub credential; it says nothing about Copilot, because a token with no Copilot access answers that endpoint just as happily. The second check therefore makes an actual Copilot call. There is no cheaper substitute — the token exchange Copilot clients perform answers `404` for a working credential and a broken one alike, so it cannot distinguish them. A single prompt can, and since it is billed as one premium request it runs on the first leg only rather than on all twelve. Only an authentication failure or an exhausted quota stops the run; anything else is reported as a warning, because the smoke check is not the job itself and the stages retry their own calls.

The failure this catches most often is a fine-grained token whose **resource owner is an organisation**. Such a token is never offered the **Copilot Requests** permission at all, so it authenticates correctly everywhere else and is refused only by Copilot.

## Direct commands

Validate a project without running agents:

```powershell
./scripts/Invoke-Foundry.ps1 `
  -ConfigPath ./config/project.yaml `
  -ValidateOnly
```

Run the installer locally without publishing anything. `-Demo` is the rehearsal switch: the agents
run against recorded answers and the installation is written to the working tree, but nothing leaves
the machine — no push, no pull request, no work items, no Azure DevOps registration. `-Phase Plan`
on its own is not a rehearsal: it is the phase that proposes the installation, and with
`delivery.dry_run: false` it commits, pushes and opens the pull request for real.

```powershell
./scripts/Start-FoundryBootstrap.ps1 `
  -ConfigPath ./bootstrap/foundry.bootstrap.yaml `
  -Phase Plan `
  -Demo
```

## Traceable delivery

Work is only traceable if the trail survives the handover. Two links carry it.

A work item plan may declare a `parentRef` on any item, and a task must declare one: a task with no
parent is a task nobody can find. The writer orders the plan topologically, creates each parent before
its children, and attaches the child with a `System.LinkTypes.Hierarchy-Reverse` relation at creation
time, so the hierarchy exists from the first moment the item does. A plan whose references do not form
a tree — a missing parent, a task used as a parent, a cycle, a duplicate reference — is rejected before
a single item is created, rather than leaving half a backlog behind.

The pull request then closes the loop back to that backlog. Every work item the run created is
attached to the pull request, so the branch, the review and the backlog item point at each other.
Reviewers are added only when configured, and a group identity is accepted in the same field as a
person. The pull request is opened as a normal one by default; set `pull_request_draft: true` to open
it as a draft instead. Merging stays manual — that boundary does not move.

```yaml
delivery:
  pull_request_draft: false
  require_reviewer_group: false
```
## Safety boundary

- no automatic merge;
- no production deployment;
- no force push or destructive Git history rewrite;
- no repository write outside `allowed_write_paths`;
- no traversal through `.git`, `..` or symlinked write directories;
- no overwrite of pre-existing dirty paths;
- updates require the exact pre-review SHA-256;
- installer-owned `.foundry/` paths cannot be supplied by an agent;
- finalization is allowed only on the configured target branch;
- managed pipeline hashes and the bootstrap config hash are verified before ADO registration;
- external writes require config opt-in, policy opt-in and the narrowly mapped token.

These controls make failures bounded and auditable. They cannot prove that requirements, test data, environments or an AI model are perfect.

## Who writes the files

No agent writes anything. Agents have a read tool and nothing else, and the runtime never grants a
shell or an editing tool, so the working tree cannot be touched from inside a prompt. Files reach the
repository along one path only: the change generator emits a change set, three reviewers approve it
unanimously, and `Apply-ScopedChangeSet.ps1` applies it under the whitelist above.

That makes the stages before it specifications rather than edits. The `implementation` stage returns
a `plannedFiles` inventory — path, operation, purpose and a content contract precise enough to write
against — and the change generator turns that inventory into file bodies. An earlier version of the
stage asked the agent to "create or modify files and report every change", which the agent could not
do and correctly refused to pretend it had; the run failed with nothing written. Asking for the
specification instead is what the runtime can actually deliver.

Because the change set is the only artifact carrying whole file bodies, its agent gets a larger
output budget than the reasoning agents, set per agent in the workflow with `max_artifact_bytes`.
When the inventory still will not fit, the generator emits fewer complete files and lists the omitted
paths in `unknowns`, rather than truncating the last one.

## Agents are told where they may write

Telling an agent to "respect the configured write paths" without showing it the list makes it guess,
and a reasonable guess outside the whitelist costs the entire run: every path is refused at the end
and nothing is written. Each agent request therefore carries a **Repository write scope** section
listing the actual writable prefixes and the forbidden ones, and stating that the applier is a
whitelist.

The runtime also checks what came back. Any path an artifact reports — `filesChanged`,
`plannedFiles[].path`, `changes[].path` or `details.automationProjects[].path` — is validated against
the same whitelist before the artifact is accepted, and a rejection quotes the writable prefixes so
the retry has something to act on. A blueprint that puts the suite somewhere unwritable is now caught
in the architecture stage instead of at delivery.

## How many automation projects

`details.automationProjects` is the blueprint's definitive list of automation frameworks, and the
schema accepts two to four: an API project and a UI project are required; agents may justify up to
two additional projects. Each entry carries a name, a writable path and a purpose explaining the
split. Independent execution, isolation, dependencies or maintenance can justify separate projects
even with the same language and runner; several layers can also share one project. Extra projects
must earn their maintenance cost through a concrete benefit, not merely another tag or folder.
Agents decide the grouping by comparing shared and separate frameworks for this product. Test levels,
components, protocols and languages do not prescribe project boundaries. The maximum is permission,
not a quota; an existing project's decomposition is evidence to assess, not a template to copy.

Product code is unwritable by construction — every `CommodityPricingService.*` directory and the
Angular client are on the forbidden list, and the whitelist refuses everything else that is not
automation, docs, pipelines or the installer's own directory.

### Several projects, one package

Several automation projects do not mean several npm packages. The `npm-package-lock` recipe resolves
one non-workspace package: it rebuilds the manifest from the approved profile, runs `npm install
--package-lock-only` against it, and refuses any lock the profile does not account for. A manifest
that declares `workspaces`, hangs child manifests under itself, or depends on anything by `file:` or
link would resolve to something that manifest does not describe, and the mismatch surfaces as a
failed `npm ci` in whatever pipeline installs it later.

So the projects are directories and runner-native projects inside one package — Playwright
`projects` and root scripts — with one `package.json` and its lock beside it. Build 466 spent
twenty-three minutes generating a plan that made them into a workspace, and the materialiser at the
far end refused it with no way back to the generator. `Test-PlannedManifest.ps1` now runs twice: once
the moment the generator answers, where a rejection costs one retry and the reason is handed back as
feedback, and once inside the materialiser, for a plan that arrived without passing the first.

## Automation that is named like the rest of the repository

Automation that is called `automation-api` in a repository whose every other component is called
`CommodityPricingService.Something` reads as a bolt-on, and people treat bolt-ons as disposable. So
the convention is not configured by hand, it is read out of the repository: `Get-RepositoryNamingConvention.ps1`
takes the names the repository already uses — project files first, then package manifests, then
top-level directories — finds the separator most of them share, and takes the longest leading token
sequence that covers at least half of them.

For the pricing service that yields `CommodityPricingService`, so every automation project must be
named `CommodityPricingService.Automation.{scope}`. For a repository of `acme-billing-api` and
`acme-billing-worker` it yields `acme-billing-automation-{scope}`, lower case and hyphenated, because
the casing is copied from the repository rather than imposed. Where the names have nothing in common
the detector says so, no convention is injected, and the architect names the projects itself.

Every agent request carries the derived pattern, and `Test-AutomationProjectName.ps1` rejects a
blueprint whose project names do not follow it, in the same way a path outside the whitelist is
rejected — a convention that is only advice is one that gets ignored on a long run. `automation.naming`
in `config/project.yaml` can pin the prefix (`mode: fixed`), change the middle segment, or turn the
whole thing off.

The automation is named like the repository but does not join its build. `CommodityPricingService.slnx`
sits at the repository root, outside every writable prefix, so the new projects cannot be registered
in it — which is the correct outcome, not a limitation to work around. The automation carries its own
solution inside the automation root and every proposed command runs against that, so a clean checkout
can select its own suites without editing product build manifests. Read-only product references and
isolated product builds are legitimate architecture choices, but their checkout, dependency graph,
private-feed access and runner support must be explicit execution prerequisites.

### Evidence-based architecture decisions

Architects and independent reviewers share `prompts/shared/architecture-decision-rules.md`.
They compare materially different testing architectures and record the options, decisive criteria,
selected option, tradeoffs and change conditions in `details.decision`. `details.testTaxonomy` maps
major product risks to layers, stimuli, assertions and observation points. Existing frameworks and
the product language are candidates, not compulsory winners. Versions still need a compatibility
rationale; the user's two-to-four project boundary and product write restrictions still apply.

Reviewers challenge coverage, delivery and security independently rather than treating agreement
or a successful dependency restore as proof of quality. Missing credentials, a private feed or a
local test runtime must not silently turn component/integration coverage into support-only checks.
The architect resolves substantive disagreement using evidence and preserves valid prior controls.

This decision freedom does not add missing execution capabilities. The current standalone resolver
and verifier do not automatically restore complete product/workspace dependency graphs or provision
product checkouts and private credentials. Agents must expose such prerequisites and affected suites;
they must not invent support, weaken the target architecture or claim unexecuted product tests passed.
Planning, implementation, support checks and executed product behavior remain separate evidence.

UI foundation and maintenance decisions follow `prompts/shared/ui-maintenance-rules.md` across
architecture, planning, generation, change-impact, implementation, triage and review. Agents justify
BDD versus direct tests and specify stable journey identities with source/route/assertion traceability.
An evidenced path or locator change becomes a scoped Automation repair with verification and PR;
it must not silently alter the expected business behavior. See
[UI maintenance analysis](docs/ui-automation-maintenance.md) for the inspected scaffold, adopted ideas
and the distinction between these instructions and an executed maintenance integration.

### Configured language runtimes

This installation enables C#/.NET, JavaScript/TypeScript, Python, Java and Go through the NuGet,
npm, PyPI, Maven and Go adapters. The bootstrap prepares configured tooling before agent work;
Python/Java/Go archives and the Python tool environment are cached under `Agent.ToolsDirectory`.
An installation without one of those ecosystems skips its preparation. Container execution still
requires the chosen runtime inside the container image.

The additional defaults are Python 3.13 (a maintained line with broad wheel availability), Java 21
(LTS), Maven 3.9.11 (Maven 3 plugin compatibility), and Go 1.26 (a supported stable line).
Python provisioning uses uv 0.12.17 and pip-tools 7.6.1; Java uses Temurin. Downloads are verified
against publisher checksums. Python, Java and Go select a stable patch within the configured line
when filling an empty cache and reuse that installation on subsequent legs; the actual versions
are printed and the resolver verifies compatibility. These defaults are installation capabilities,
not evidence that every framework or package works. Agents must justify library versions and the
generated framework must still restore, compile and execute its tests.

Validation status: local Windows checks installed these three runtimes and resolved a real lock for
each. Python and Go also passed a minimal test and correctly failed an intentionally broken assertion.
Java/JUnit now also passes a real clean-cache restore, offline compilation and test execution,
including a deliberately failing assertion. Maven preparation reads the effective Surefire version
and resolved dependency tree, fetches the dynamically selected provider and aligned JUnit launcher,
and includes their artifacts in the checked lock. Build and test retain offline mode; preparation
does not run generated tests. Reproduce this integration check with Java 21, Maven 3.9 and `pwsh`
on PATH: `./foundry/tests/powershell/Invoke-MavenOfflineSmoke.ps1 -WorkRoot <new-empty-directory>`.
It downloads public Maven artifacts and preserves logs; it does not call an AI model.
Maven verification images must include PowerShell 7 alongside Java and Maven for dependency preparation.
The additional runtime installer has not been exercised on the target Linux pool in this change.

The [language validation matrix](docs/language-validation.md) also covers real C#/.NET,
JavaScript, TypeScript, Vitest, pytest, Robot Framework and Go execution through Foundry's
adapters, including lock validation and deliberately failing assertions.

## Reviewers that know what has been built and what has not

The workflow decides everything before it writes anything: files are applied at stage nine of ten, so
the review and delivery stages at five through eight reason about an inventory of planned files, not
a working tree. That is deliberate — no agent gets a write tool — but it makes a plausible reviewer
instinct fatal. A reviewer told to "block when test artifacts are missing" will find no tests on disk,
block, and end a run that had done nothing wrong.

So every stage that runs before the applier states plainly what exists when it runs, and every review
prompt separates `revision_required`, which sends work back, from `blocked`, which ends the run for a
human and throws away every completed stage. The shared principles say the same thing once for all
agents: work a later stage has not performed yet is not missing evidence.

## Automation written in what the product is written in

The architect used to pick a stack from a list of pre-approved profiles, which is how a .NET
repository ends up with a TypeScript test suite nobody on the team maintains. The choice is now made
from the repository itself. Discovery reads `.sln`/`.slnx`, `.csproj`, `global.json`,
`Directory.Build.props`, `Directory.Packages.props`, `NuGet.config`, `package.json`, lock files, test
projects and pipeline YAML, and reports a `componentStacks` entry per component and one
`primaryStack` for the repository, each carrying the repository-relative paths it was read from.
Vendored dependencies, generated output and the Foundry installation's own directory are listed in
`excludedFromStackDetermination` with a reason, because a file count is won by whichever of those is
largest, not by what the product is.

The architect works down a fixed order: extend automation that already exists and is suitable, then
the product's own ecosystem, then a different ecosystem only against a demonstrated need. A browser
suite on its own is not that need — a .NET product gets .NET automation with a .NET browser driver
unless something concrete says otherwise. The reasoning is not left in the chat: every automation
project carries a `toolchain` decision in the blueprint naming the discovered stack and its evidence,
the chosen language, runtime and test tooling, what it reuses, how it meets the coverage
requirements, the alternatives it rejected and why, the dependencies and CI capabilities it adds, and
— when it leaves the product's ecosystem — the reason. All three architecture critics reject a
blueprint that changes ecosystem without one, and the same text is carried into each project's
`technology-choices.md` and into the pull request description.

Once the bootstrap pull request is merged the decision is a fact, not a question. The merged change
set leaves `automation-toolchain.json` in the repository (`automation.toolchain_record` in
`config/project.yaml` names it), the architecture request carries it, and a blueprint that proposes a
different ecosystem than the recorded one is refused rather than re-litigated. An ordinary product
change never redesigns the automation; a migration is its own pull request with its own justification.

## Proving the technology by running it

A change set that looks right is not a framework that works, so the bootstrap workflow runs one
between materialization and review. `verify_framework` lays the change set out in a scratch
directory and, for every manifest a locked ecosystem owns, prepares the runtime, installs, builds,
runs the tests, and then breaks one expectation on purpose to confirm the suite can still go red.

The refusals are the point. Zero discovered tests is not a pass. A test summary the adapter cannot
parse is not a pass. A suite that stays green with a deliberately broken assertion is not a pass —
it proves the run was reporting on nothing. Each of those returns `revision_required`, which sends
the run back to `bootstrap-change-generation` with the concrete output, for at most three attempts
before the stage blocks. A failure the markers identify as an unreachable feed, a missing SDK or a
proxy is reported as `infrastructure_unavailable` and blocks instead, because a broken agent is not
evidence against the technology that was chosen.

Proving the framework is the one stage that both reaches a package registry and executes code the
run wrote minutes earlier, so it is gated the way every other side effect is. `automation.verification.dry_run`
suppresses it, `-Demo` forces that flag on alongside the delivery, work-tracking and pipeline ones,
and a suppressed verification writes `not_attempted` and states in its own artifact that it proved
nothing. It is never reported as a verified framework. A real bootstrap leaves the flag false, which
is what it is when the key is absent.

Proving the framework is not, however, the only place this runtime executes code an agent wrote.
An execution plan's install and build steps and the quality suite that runs the generated tests do
the same, so all three run behind one boundary rather than three that drift apart.
`automation.isolation.mode` governs it. In both modes the child's environment is built rather than
inherited — no token reaches it through a variable, every package manager's per-user configuration
is pointed somewhere empty, and each cache is kept under the work root so an install step's
downloads are still there when the build step runs. `process` is honest about what it does not do:
the child shares this run's operating system user and file permissions. `container` closes that,
mounting only the work root, and there is deliberately no fallback between the two — a run
configured for a container on an agent that has none stops, because a run that believes it is
isolated and is not is worse than one that refuses. The setting used to live under
`automation.verification`; that place is still read, so an installation that already configured it
keeps the boundary it asked for.

Resolving dependencies is gated the same way, for a second reason. It reaches a registry and it also
insists that the exact toolchain the decision was settled on — for npm, that npm version to the
patch — is installed on the agent running it, which is right for a run that delivers a lock file and
wrong for a rehearsal that has to be runnable anywhere. `automation.materialization.dry_run` makes
the stage perform every check that reads this run's own files and then stop: no resolver is started,
no lock is written, and the change set it produces is marked `details.dryRun`. That mark is what
stops it: applying or delivering a rehearsed change set is refused outright unless the delivery is
itself a rehearsal, so a framework whose dependencies were never resolved cannot reach a repository
with an approval attached to it.

Two mistakes this stage made and no longer can: a tool was started by name, which on Windows finds
the `npm` shell script rather than `npm.cmd` and fails to launch at all — read, for three attempts in
a row, as the chosen framework being defective; and the recorded toolchain's runtime block was
translated a second time, looking up the configuration's `node_major` in an artifact that holds
`nodeMajor`, so every pin read as absent and the run reported it had checked "Node.js 0.x". A lock
whose runtime block does not carry the names its adapter reads is now refused outright, because
reading a pin as zero is worse than refusing to read it.

## Verification

Bootstrap's early `execution` stage assesses the accepted implementation file contracts
deterministically. It records zero executed commands and explicitly states that no build,
test or audit result exists yet. It does not call models to classify failures of files
that have not been generated. This assessment is permitted only while the workflow
retains a blocking `framework-verification` gate over the materialized change set before
final change review. That later gate installs, builds and tests the generated framework
in isolation and checks that a deliberately broken expectation makes the suite fail.
Unfinished or modified implementation inventories still block the assessment.

If an executed regression reveals a product defect, Foundry retains its failing
assertion and files an Azure Boards Bug through the existing idempotent work-item
writer. Independent analysts must agree on the observed failure, the delivered
test and a repository requirement; ambiguous requirements and broken test fixtures
or validators do not qualify. The bootstrap policy already permits Bug creation.
Reports include the test identity, source hashes, expected and actual behavior,
and the originating build. Retries reuse an existing Bug instead of creating a duplicate.
Each analyst must cite the same failed test and valid product requirement sources;
the sources may span multiple documents or differ between independent analysts.
All cited requirement paths and hashes are retained in the Bug.

`config/work-item-defaults.json` supplies process-specific field values scoped by
Azure DevOps organization, project and work-item type. `@authenticated-user` resolves
to the PAT owner's verified identity. Explicit plan fields take precedence, and an
unsupported configured field stops creation. The X AI Mission Bug defaults use
Development, Regression Test, TradingIT and an initial Small size estimate; these
are triage values for team review. Other projects do not inherit these defaults.

Framework verification can finish with product regressions only when every failed
test has this confirmation and a real Bug receipt, and a negative probe adds exactly
one failure without hiding any existing failure. The original failed-test count,
nonzero exit code and failed step remain in the evidence. Product tests remain red
until the product is corrected; Foundry does not change product code or skip tests.
Build, setup, framework and unclassified failures still block readiness. Test output
whose individual failures cannot be identified cannot receive this exception.
Analysis reuse is bound to the source manifest, delivered code and execution logs.

The installation quality gate selects derived test commands after the build, so a
newly built Microsoft.Testing.Platform application uses the same runner as framework
verification. A repeated product failure may proceed only with hash-verified analysis,
unchanged installed source and requirement files, three independent confirmations,
a real Bug receipt, the same test counts and the same failing assertions. The quality
report retains the failed command and exit code and explains the exception in warnings.
New failures, skipped tests, missing evidence and build errors still stop installation.

During bootstrap, secret scanning covers every file in the installation change set.
Other quality runs retain the whole-repository scan. Credential patterns are matched
with their declared case sensitivity; source expressions, environment-variable name
constants and explicitly symbolic test fixtures are reported as reviewed warnings.
Provider redaction remains conservative and continues to redact those values.

An interrupted repair need not have produced a merged plan. A later repair uses the
last completed generation recorded in workflow state when the immediately preceding
attempt has no plan. The plan and inventory basis must still match their recorded
hashes, the current approved inventory and the source that verification actually ran.
Missing or modified records stop recovery instead of silently buying a full rewrite.
This also handles a verification restart whose counter was reset independently of
generation; verification recorded before materialization cannot authorize a repair.
Generation, materialization and verification counters can diverge after a repair.
The latest materialized bodies and subsequent execution establish the repair source,
so unrelated, previously passing projects stay out of the next repair assignment.

When a source-only repair carries the previous files forward but supplies no resolver
recipes, materialization recovers those recipes from the carried plan's recorded SHA256.
Only unchanged manifests qualify; the current blueprint and locked toolchain still apply.
Verified resolver checkpoints are reused when available, otherwise dependencies are
resolved normally. This also works when resuming a saved materialization failure,
without regenerating source or modifying the saved plan.

Supervisor decisions are scoped by the reason, permitted decisions and saved stage
evidence. A repeated escalation reuses its answer, while changed evidence receives
a separate immutable decision even if the stage iteration number was reset.

Ordinary execution stages still run their commands. An empty plan now writes a current
empty execution result, so failure analysis cannot mistake a prior attempt's failures
for results of the current plan. A zero-command result is not passing test evidence.

```powershell
./scripts/Invoke-Tests.ps1
```

The suite covers schema validation, workflow assurance, scoped writes, ADO work items and draft PRs, realtime CI normalization, Copilot isolation, bootstrap plan/finalize behavior, pipeline idempotency, no-token dry runs, conversational agent-response recovery, bounded request context, interrupted-run accounting and a complete mock workflow. Node tests cover the YAML/JSON helpers.

## Agent response handling

A conversational CLI does not always answer with a bare JSON document. It may narrate before the artifact, wrap it in a fenced code block, or add a closing remark. The runtime therefore recovers the largest self-consistent JSON object from the raw response, ignoring braces inside JSON strings and unbalanced braces in prose. The unmodified response is still written to `<artifact>.attempt-N.raw.txt` for audit, and schema validation, the write-path scope check and the bounded retry are unchanged. A response with no parsable JSON object fails the attempt with the first 400 characters quoted as validation feedback.

Recovered text is also repaired before it is accepted. Models routinely emit a literal newline or tab inside a JSON string value. PowerShell's `ConvertFrom-Json` tolerates that; the JSON specification does not, and the schema validator running on Node rejects it. A response that the runtime had already accepted would then fail validation with `Bad control character in string literal`, costing a full retry. Raw characters below `0x20` inside string literals are therefore escaped — as `\n`, `\r`, `\t`, `\b`, `\f`, or `\uXXXX` — so both parsers agree on the same artifact. Escape sequences the model wrote correctly are left alone, and whitespace used to format the document outside string literals is untouched.

A run process that is killed, stopped or interrupted cannot report a result. Such a run is not left advertising `running`: the workflow persists a `failed` state with an `interrupted` attempt record, and resuming a state that is still `running` records the abandoned attempt before the stage is retried.

A retry that succeeds must not be punished for the attempt it recovered from. Agents in a review stage run in parallel runspaces, and a runspace keeps its `HadErrors` flag set once anything has reached its error stream — including output a caught, retried failure left behind. Build 465 lost a leg to exactly that: `architecture-critic` returned an empty first answer, its retry produced a schema-valid approval, and the stage was killed afterwards with `Parallel agent 'architecture-critic' failed:` and nothing after the colon, because the error stream held only blank noise. An agent returns a result only after its artifact has passed schema and write-path validation, so the returned result is what the collector trusts. A genuine unhandled failure leaves no result and surfaces through `EndInvoke` instead. Diagnostics left on the error stream by a recovered attempt are reported as a warning against that agent and nothing more, and a budget stop is still recognised whether it arrives through `EndInvoke` or through the error stream of an agent that produced nothing.

## A blueprint that cannot grow its way out of a review

Three critics reviewed the architecture blueprint for three rounds and never agreed, and the reason
was visible in the artifacts rather than in the reviews. Between the first draft and the third,
`details` went from 30 KB to 71 KB and from 19 sections to 25. Nothing was ever removed. Six sections
were invented — `secretScanning`, `artifactPolicy`, `dependencyAcquisition`, `requirementDisposition`,
an `openQuestions` list duplicating the top-level `unknowns`, and a 7 KB `revisionResponse` arguing
with the critics. Each new section named machinery that did not exist, so each one became the next
round's finding: *"'npm run secretscan' has no implementing tool"*, *"the sanitiser is specified as an
outcome, not as a mechanism"*. The producer was answering findings by adding surface area, and the
surface area was the problem.

Nothing stopped it, because the blueprint schema was `details: { "type": "object" }` with
`additionalProperties: true`. A 94 KB document of invented structure passed validation without a
single complaint, and the only limit on size was a sentence in the prompt that the model ignored:
asked for 64 KB it returned 94 KB, and asked for 32 KB after a truncation it returned 84 KB.

`details` is now a closed set of sections with the shape the architect already writes, and the
schema — which the runtime already enforces with an automatic retry — carries the limits the prompt
could only request. Any string is capped at 800 characters, any list at 20 entries, any object at 20
properties, at every depth. `decision`, `stack`, `structure`, `proposedCommands` and `milestones` are
required; the remaining fourteen sections are optional; anything else is rejected by name. There is
deliberately no section in which to reply to a critic, and open items have one home: `unknowns`.

Validation feedback now names what it rejected. Ajv reports the offending property in its error
parameters rather than its message, so `must NOT have additional properties` used to reach the agent
with no indication of which property was meant — six identical, useless sentences. The failure is now
reported as `must NOT have additional properties ('revisionResponse')`, which is something a retry can
act on. The prompt carries the matching rule: every mechanism the blueprint names must be implemented
by a declared dependency, an existing file or a proposed command, and a concern that cannot be
resolved with something real belongs in `unknowns` rather than in a new invented control.

The first-round blueprint from that run is kept as `tests/fixtures/blueprints/bounded-blueprint.json`
and the schema is tested against it, so the contract stays fitted to what an architect genuinely
produces rather than to an idealised shape.

## Revisions that hold their ground

The bootstrap architect writes a full blueprint once. Later producer rounds return
`blueprint-revision.schema.json`: edits at named JSON Pointer paths, bound to the
previous artifact's SHA-256. The runtime preserves all other content, checks the
base identity, applies the edits, and validates the complete blueprint against its
original schema and semantic rules before critics see it. Removing an existing
deferral requires an explicit resolution tied to an actual edit. Revision responses
are retained beside the resulting blueprint and reused across relay legs.

An incomplete producer uses the next round to finish its own work; critics wait.
The producer/critic loop shares the configured round limit with completion recovery,
so four inner rounds cannot become sixteen through an outer restart. Unfinished
deliverables at exhaustion block the run, and external blockers remain blockers
even when a review also requests a revision. Recorded review dissent retains the
workflow's existing exhaustion policy. Architecture specifies execution contracts
and references discovered requirements; full pipeline and test bodies belong to
implementation, and concrete deployment credentials belong to execution setup.

A producer-critic loop only converges if each revision keeps what the last one earned. Left with
nothing but the discovery input, the producer rewrote its document from scratch every round: it
fixed the findings it had just been given and, in the same pass, quietly relaxed a control an
earlier critic had already accepted. The critics were right to reject it again, and the loop spent
its iterations trading one requirement for another.

From the second revision onward the runtime therefore writes `revision-ledger.json` beside the new
draft and hands it to the producer ahead of everything else, together with the draft it produced
last time. The ledger is built from the reviews themselves, not from the model's memory of them:

- `settledCritics` — every critic that has already approved, and the revision it approved at.
  What those critics cleared is closed; weakening it is a regression, not a tradeoff.
- `honouredCommitments` — the changes earlier rounds demanded and the producer already made.
  They must still hold in the new draft.
- `outstandingFindings` and `outstandingChanges` — the only open items, taken from the latest
  round's rejecting critics alone.

The producer is told to revise rather than rewrite, to leave untouched anything no outstanding item
requires changing, and to keep the stricter of two genuinely conflicting requirements while
recording the conflict as an open question. The ledger is validated against
`schemas/architecture/revision-ledger.schema.json` like any other artifact, and a resumed run
rebuilds it byte for byte, so the relay still treats it as already produced.

### Findings the producer can act on

A ledger only converges if the items on it are ones the producer can close. Build 464 spent all four
architecture iterations without consensus: two critics approved, and the third kept demanding
canonical endpoints, credentials, topic names and dataset identifiers. Those facts were in no input
to the run and nobody in the run could supply them, so the producer could not have satisfied the
demand at any iteration count. The loop was not strict, it was unsatisfiable.

Every finding a blueprint critic returns therefore carries a `resolutionScope`:

- `blueprint_revision` — the producer can settle it inside the blueprint from evidence it already
  has. A missing correlation rule, an identifier named in one section and omitted from another, an
  unpinned version, an absent fail-closed path.
- `external_prerequisite` — it waits on a concrete value from outside the run. The producer must
  still define the symbolic input, the role that supplies it, its constraints, the preflight
  validation and the fail-closed behaviour, and record the unavailable value in `unknowns`, but it
  must not invent the value and must not be asked for it again.

The schema, not the prompt, enforces what follows: `revision_required` needs at least one `error` or
`critical` finding scoped `blueprint_revision`, and `approved` may carry no blocking finding at all.
A critic that considers a missing external fact fatal has to say so once, with `blocked`, rather than
spend the remaining iterations restating it. The scope travels into the ledger so the producer sees
which outstanding items it is expected to close and which it is only expected to describe.

## Bounded agent answers

The request budget stops a prompt growing without limit. Nothing used to stop the answer. A model has
a maximum output length, and an agent that keeps writing past it does not get an error: it gets a
document that simply stops, mid-string, mid-object. The runtime then recovers the largest balanced
JSON object it can find, which in a cut-off answer is some incidental fragment of narration, and
rejects it with `must have required property 'agentId'`. The retry echoes that message back, the
model concludes it forgot a field, writes the same oversized document again, and the run burns another
full call at the same wall. A live run lost thirty-five minutes this way: two revisions of 267.8 KB
and 258.0 KB from which 1.2 KB and 318 B were recovered.

Two changes close that loop. A truncated answer is now recognised as such — an answer that ends inside
an unterminated string or object, and from which only a small fraction was recovered, is reported as
a cut-off, not as a schema violation. And the feedback matches the diagnosis: the agent is told its
answer was cut off, given a concrete byte budget for the retry, and asked to shorten the artifact
rather than to add the missing field it never actually omitted. The budget halves with each truncated
attempt, so successive retries converge instead of repeating.

The budget is stated up front too, per AI profile:

```yaml
ai:
  profiles:
    copilot:
      max_artifact_bytes: 65536
```

Every request then carries an output size budget telling the agent to decide everything the schema
asks for and write it densely. Set it to `0` to state no budget. An accepted artifact that still
exceeds the budget is logged as a warning, because it is the artifact a critic round will ask to be
revised — and a revision of something already near the limit is what gets cut off.
## Bounded agent requests

Evidence is collected once and stored immutably, but it is not stuffed into every prompt. Each agent request is assembled against an inline budget:

```yaml
runtime:
  context:
    max_file_bytes: 262144
    max_total_bytes: 524288
    max_request_bytes: 131072
    max_inventory_entries: 2000
```

Artifacts are inlined in priority order: the direct inputs of the stage, then shared run evidence, then the repository context, then artifacts accumulated by earlier stages. An artifact that does not fit the remaining budget is not dropped. It is named with its absolute path, byte count and SHA-256, and the agent is told to read it with its file-view tool. The direct inputs of a stage sort first and so get first claim on the budget, but they do not get to ignore it: a producer output large enough to exhaust the budget on its own is referenced by path like anything else. Every request opens with a context manifest recording exactly what was inlined, projected or referenced.

The repository context is additionally projected before inlining. Every file whose content was actually collected is kept verbatim; the per-file inventory is bounded by `max_inventory_entries`; and entries that carry no content collapse into skip-reason counts, because those entries only repeat paths the inventory already lists. The complete artifact, including every per-file hash, stays on disk and is named in the request.

Without these bounds a request grows with both repository size and run length. On a 507-file repository the first discovery request was 799,941 bytes, roughly 197,000 tokens, and every later stage re-embedded all earlier artifacts. The same run now issues a 10,966-byte first request, and the largest request in the whole workflow is 43,100 bytes.

## Progress reporting

A live run is long. The multi-agent analysis on a real repository takes tens of minutes, and every unit of that time is spent waiting on a model. Without output an operator cannot tell a working run from a hung one, so the runtime reports what it is doing on the console and therefore in the pipeline log.

Reporting is hierarchical. The bootstrap announces its resolved phase and each phase transition, the workflow announces every stage with its index, iteration and type, and each agent reports the size of the request it sends, the size of the response it receives and how long the provider took. Schema acceptance, schema rejection with the retry reason, and recovery of a JSON artifact from surrounding prose are all reported as they happen. Stages close with their status and duration.

Two details make this work in practice. While the Copilot CLI process is running, the provider emits a heartbeat every thirty seconds with the elapsed and permitted time, so the longest silence in a run is half a minute rather than the whole timeout. Parallel agents execute in runspaces, which buffer host output instead of writing it to the console, so the parent drains each agent's information stream while the batch runs and prefixes every line with the agent id. Without that drain the busiest part of a run would be its quietest.

Progress output never travels through the success stream, so it cannot corrupt the objects that scripts return to each other.

## What the agents are saying

Sizes and durations tell an operator that a run is alive, but not what it is deciding. Once an artifact passes its schema, the runtime therefore reads it and prints a few short lines of what the agent actually concluded:

```
  -  [architecture-critic] Artifact accepted against its schema.
    -  [architecture-critic] Thinks: The blueprint routes every stage through one shared runspace pool.
    [!] [architecture-critic] Verdict: revision_required (confidence 0.72).
    [x] [architecture-critic] Finds (critical): Apply writes outside allowed_write_paths.
    [!] [architecture-critic] Asks for: Scope the retry budget per stage.
```

Every artifact shares a common shape, so one narrator serves every agent. It reads the summary, a non-completed status, the review verdict and its confidence, the outcome, the reasoning and recommendation, the findings, the requested changes, the proposals, the planned file changes, the warnings and the open questions. Findings are ordered by severity so the worst is shown first, critical and error findings are marked as errors and a rejected verdict as a warning, and anything beyond the item limit is counted rather than printed. Long prose is collapsed onto one line and cut at a word boundary, so a paragraph never floods the log.

Narration is configured under `runtime.progress`:

```yaml
runtime:
  progress:
    narrate_agent_output: true
    narration_max_items: 2
    narration_max_length: 160
```

Setting `narrate_agent_output: false` returns the log to sizes and durations only.

Parallel agents receive a private copy of the configuration rather than a shared reference. A PowerShell object builds its member table lazily and that construction is not thread safe, so reading the same configuration from several runspaces at once fails intermittently with `The property 'Properties' cannot be found on this object`.

## Surviving a job time limit

A live run of the ten-stage bootstrap workflow takes hours, because an agent's runtime is governed by how much it has to write. A hosted CI job is killed the moment it reaches its time limit, and the work in flight dies with it. A run can therefore carry a deadline of its own and stop before that happens:

```yaml
runtime:
  relay:
    budget_minutes: 0
    max_legs: 12
```

`budget_minutes: 0` disables the deadline, which is the default: a job that comfortably fits its limit should not be split. Setting it to a value below the job limit changes the behaviour in three ways.

The deadline is checked on agent boundaries, never mid-call. When the budget is spent, the current agent finishes, the run writes `status: "paused"` into `workflow-state.json` and returns successfully. Nothing is lost and nothing is half-written.

A paused run keeps every artifact it produced. Resuming with `-ResumeRunRoot` re-enters the stage it stopped in and the agents that already answered are reused instead of called again, provided their artifact still validates against its schema. An artifact truncated by a kill is discarded and produced again.

Immutability still holds everywhere else. Reuse is only permitted for the single stage a leg resumes into; every later stage in the same leg must produce its own artifacts, and outside resume an existing artifact is still a hard error.

Command line equivalents are `-BudgetMinutes` on `Invoke-Foundry.ps1` and `Start-FoundryBootstrap.ps1`, which override the configured value.

### The pipeline runs the relay, not one long job

For a long time the relay existed only in the runtime: nothing invoked it, so
`budget_minutes` stayed at `0` and the bootstrap ran as a single job. That job
does not survive a real run. The last single-job build lost its agent after
82 minutes with no diagnostic beyond `We stopped hearing from agent`, having
completed four of ten stages — an unattributable death, not a clean timeout.

`first-start-bootstrap.yml` therefore runs the bootstrap as a chain of jobs, one
per leg, built from `templates/relay-leg.yml`. Each leg gets `-BudgetMinutes`, so
it stops on an agent boundary rather than being killed mid-call, and publishes
the whole evidence root as a pipeline artifact. The next leg downloads that
artifact, restores it, finds the run directory that still has a
`workflow-state.json`, and resumes that analysis run.

A leg only starts when its predecessor reported `paused`, so a run that finishes
early leaves the remaining legs skipped and costs one job. The last leg in the
chain fails loudly if the analysis is still paused, because silently stopping
one leg short of delivery looks exactly like success.

The resume boundary is deliberately narrow. Each invocation creates a new
`bootstrap-*` wrapper ID, and only `.qa-foundry-artifacts/run-*` analysis state
crosses hosted jobs. Apply, quality collection, commit, push, and pull-request
creation happen after analysis completes; a failure there is terminal because
the next checkout does not contain the prior `.git` state, repository mutations,
or `.sdlc-foundry` registry. Inspect the remote branch and pull requests before a
fresh run, since a remote write may have succeeded before its response was lost.
Fully completed delivery records remain idempotent in the same preserved
worktree; partial delivery is never reported as recovered automatically.

A fresh agent per leg is a second benefit rather than a cost. Memory, disk and
CLI process state do not accumulate across an entire multi-hour run, which is
the most likely explanation for the agent that stopped responding.

## Current boundary

The DevOps integration is Azure DevOps only. There are no GitHub Actions, GitHub Issues or GitHub pull-request adapters in this release. AI transport remains configurable because model access and DevOps delivery are separate concerns.

The permanent installation currently registers the router and failed-build-triage definitions. The event workflows for backlog, implementation, release, incident and documentation are implemented in the runtime and can already be invoked through the router or API; dedicated ADO service-hook and pipeline-completion wiring is the next installation layer.
