# SDLC Foundry architecture

## Product boundary

The first product release integrates only with Azure DevOps: Azure Repos, Azure Pipelines and Azure Boards. AI access is a separate boundary and remains configurable because a team may obtain Claude through Copilot CLI or use another approved model endpoint.

The system never merges a pull request and never deploys to production.

## Control plane and intelligence plane

The control plane is deterministic PowerShell plus JSON Schema. It owns routing, artifact validation, iteration limits, repository scope, commands, secrets, external API calls and idempotency.

The intelligence plane is a set of prompt-defined agents. It can analyze evidence and propose structured actions, but it has no direct ADO writer and receives no ADO delivery token.

```text
ADO event / first start
        |
        v
deterministic collector ---> immutable evidence
        |                         |
        v                         v
parallel specialists ------> synthesis/producer
                                  |
                                  v
                         independent reviewers
                                  |
                           unanimous approval
                                  |
                                  v
                        deterministic action gate
                                  |
                    scoped files / ADO API / draft PR
```

Multiple samples of the same role are not treated as independent assurance. Maximum mode requires distinct specialist roles and three distinct reviewers for high-risk work. Their agreement supplements deterministic compilation, tests, scope checks and human review; it does not replace them.

## First-start state machine

```text
no plan
  |
  | manual Auto/Plan
  v
analysis -> reviewed change set -> scoped apply -> draft PR
                                           |
                                      awaiting_merge
                                           |
                                  human merge to target
                                           |
                                           v
hash verification -> create/reuse ADO definitions -> optional smoke run
                                           |
                                        installed
```

`Auto` never finalizes from a PR or feature ref. `Finalize` and `Repair` require the exact configured target ref. The configuration file hash and each managed pipeline file hash must match the merged installation plan.

The committed state marker says `awaiting_merge`. The final installed state is an immutable ADO artifact, because the finalizer is not allowed to write directly to the protected target branch.

### Relay resume boundary

Hosted relay jobs resume only `.qa-foundry-artifacts/run-*` analysis state. Each
`Start-FoundryBootstrap` invocation has a new `bootstrap-*` wrapper ID, while
`.git`, repository mutations, `.sdlc-foundry`, and wrapper state stay in the
ephemeral checkout. Apply, quality collection, commit, push, and pull-request
creation occur only after analysis completes. A failure in that post-analysis
delivery is terminal and requires inspection of the remote branch and pull
requests before a fresh run, because a remote write may have completed before
its response was lost. A fully completed delivery can be replayed idempotently
only when the same worktree, registry, and run ID are preserved; partial
delivery is never treated as automatically recovered.

## Bootstrap trust boundaries

Agent-generated automation files and installer-owned files are combined only after agent review. Agents cannot propose anything under the configured managed root (normally `.foundry/`). The installer itself creates:

- permanent Azure Pipeline YAML;
- `installation-plan.json`;
- the awaiting-merge state marker.

The combined change set passes the same path scope and optimistic SHA-256 checks as every other repository mutation. Existing dirty files are not touched. Live writes require both project config and policy permission.

## Runtime stages

Workflows support:

- parallel specialists followed by synthesis;
- producer/critic correction loops;
- sequential planning and execution;
- parallel unanimous review;
- deterministic actions;
- bounded supervisor decisions and resumable state.

All agent artifacts are validated before use. Agent change sets contain complete final file content and the expected SHA-256 for updates or deletes. Commands are structured executable/argument objects and are checked against an allowlist and forbidden patterns.

## Azure DevOps adapters

The implemented adapters are deliberately narrow:

- pipeline build, timeline and failed-test result reader;
- pipeline definition list/create and run queue;
- Azure Boards JSON Patch writer for PBI, Task and Bug;
- Azure Repos draft pull-request writer.

Pipeline registration is idempotent by exact folder and name. Work items and repository delivery use a SHA-256 idempotency registry. Tokens are read only from explicitly mapped environment names and are never written to artifacts.

## Model defaults

The default active AI profile is Copilot CLI with `claude-opus-5` and `high` reasoning effort. The configured model is passed through to Copilot without a hard-coded allowlist because availability is subscription- and rollout-specific. The profile remains replaceable in project YAML.

Every ADO job that invokes agents first uses the shared Copilot setup step: Node.js 22, `npm install --global @github/copilot@<configured-version>`, and a version check on the same agent. The default version is `latest` so account-enabled Copilot features are not hidden by an old CLI; a project can pin the pipeline parameter for reproducibility. Authentication accepts the CLI's three token environment variables in documented precedence. Hosted ADO agents normally use secret `COPILOT_GITHUB_TOKEN`; stored OAuth or GitHub CLI credentials are allowed locally and only by explicit opt-in in CI.

Tests use the deterministic mock provider, so they validate orchestration and safety without claiming live model or live ADO coverage.

Every call to a provider is written down beside the artifact it was meant to produce, whether or not it produced one, so a run carries its own cost with it. The Copilot CLI is asked for its own final usage statistics and the token counts it reports are recorded as measured; a provider that reports nothing leaves the counts empty rather than an estimate, because a guess written where a measurement belongs cannot afterwards be told apart from one.

Framework verification is the one place where code an agent wrote minutes earlier is executed. The child process is started with an empty environment: only what a compiler genuinely needs is put back, `HOME`, `USERPROFILE` and the temporary directories are redirected inside the run's own work root, and the delivery credentials this run holds are absent. Credentials also live in files, so `git`, `curl`, npm, pip, Composer, Bundler and the .NET CLI are each pointed at a configuration path inside that isolated home, which does not exist and therefore holds nothing. What this does not do is change who the process runs as; a container or a separate operating-system identity is the only complete answer, and this closes the paths a package manager takes by default.

## Implemented versus next

Implemented now:

- two-phase first start and repair entrance;
- multi-agent bootstrap analysis and reviewed automation change-set generation;
- eight SDLC workflows;
- permanent router and failed-build pipeline registration;
- realtime ADO failure evidence;
- scoped code changes, quality evidence, ADO work items and draft PR delivery.

Next installation layer:

- dedicated scheduled/backlog and work-item implementation definitions;
- ADO service-hook and pipeline-completion subscriptions;
- generated test-project execution pipelines chosen from the bootstrap blueprint;
- ADO Test Plans synchronization for UI cases;
- coverage ingestion and automated coverage-gap backlog creation.
