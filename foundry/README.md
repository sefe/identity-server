# SDLC Foundry for GitHub Actions

This copy of Foundry is embedded in `sefe/identity-server` at `foundry/`, beside
`src/`. Run **Foundry Bootstrap** to analyze the repository and design at least two
automation projects (API and UI), generate and review their tests, and produce a
report with work performed, model usage and estimated cost. Bootstrap defaults to
`automation.verification.mode: deferred`: generated tests, build/execution probes
and negative probes are not run. Credentials and endpoints are configured after
delivery. Dependency resolution, schema validation and static review still run.
Additional projects such as messaging are selected only when the product needs them.

The result includes one GitHub Actions workflow per automation project, failure
triage, installation verification and a manual lifecycle analysis workflow.
Publishing creates a **draft pull request**. Merge remains a human action. Generated
test workflows use manual dispatch until environment configuration is supplied;
publishing the bootstrap PR must not trigger the generated suites.

## Run it

1. Commit and push `foundry/`, the root `.github/workflows/foundry-bootstrap.yml`
   and `foundry-validate.yml`, and the root `.gitignore` changes. The bootstrap
   workflow must be present on the default branch to appear as a manual workflow
   in the Actions UI. Pushing a feature branch alone does not install that button.
2. Repository Actions secrets: `COPILOT_GITHUB_TOKEN` is a user-owned fine-grained
   PAT with Copilot Requests permission. `FOUNDRY_GITHUB_TOKEN` is authorized for
   this repository with Contents, Pull requests and Workflows write permissions.
   The current workflows use the explicit Copilot PAT; they do not require
   organization-billed `GITHUB_TOKEN` authentication or a separate runtime token.
3. Enable Actions and access to the GitHub-hosted `ubuntu-latest` runner and the
   official `actions/*` used in these files. No application credentials are needed.
4. Open **Actions → Foundry Bootstrap → Run workflow**. Select the branch to
   analyze and use as the generated draft PR's base (normally `main`). The exact
   selected commit supplies both the application and embedded Foundry. The model
   defaults to Opus 5.5; all profiles use high reasoning. Leave `budget_usd` empty
   for no Foundry spending cap and `publish=true` to create the draft PR.
5. Download `foundry-evidence` (HTML report, usage records, decisions and recovery
   state) and `foundry-output` (automation, workflows and configuration). With
   `publish=false`, files are still generated and uploaded but no branch or PR is
   published. Execution remains deferred in either mode.
6. Review and merge the generated PR. Add application credentials and endpoints
   afterwards, then run the generated API/UI workflows manually. Finalize checks
   installation hashes; it does not execute generated tests. Failure triage accepts
   failed manual runs on the configured base branch, as well as future push runs.

The installer writes `.foundry/`, `automation/`, generated `.github/workflows/`
and `foundry-report.html`. Product source and the existing Foundry launcher are
outside the generated change set. Subsequent Foundry workflows restore only
`foundry/` from the bootstrap commit within their disposable checkout; they do
not check out the whole repository inside `foundry/` or contact a separate runtime
repository. The nested `foundry/.github/workflows/` files are reference copies;
GitHub executes the workflows at the repository root.

`Validate Foundry` runs offline Foundry helper and integration checks on changes
to its code. It does not call a paid model or execute generated application tests.
Runtime provisioning reads versions from `foundry/config/project.yaml`, including
the package managers needed for Node, .NET, Python, Java and Go dependency locks.
Providing these tools does not choose the generated frameworks' technology.

## Budget and continuation

Model defaults follow the operator's available Copilot models, confirmed on 2026-11-12:
`copilot` uses `claude-opus-5.5`, `codex` and `sol` both use
`gpt-6.1-sol`, and `gemini` uses `gemini-4-argon`. Profile names are stable
configuration keys, not provider model IDs. Collaboration is disabled by default,
so all agents use the active `copilot` profile unless configured otherwise. The
bootstrap workflow's `model` input overrides that profile and defaults to
`claude-opus-5.5`. The mock profile and historical fixtures do not call a model.

References: [Copilot CLI model IDs](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference#supported-models),
[Copilot prices](https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing).

There is no Foundry spending cap by default: `budget_usd` is empty and
`ai.run_budget.max_total_tokens` is zero. Provider usage metadata and cost reporting
remain active independently of budget enforcement. To enable a cap for a larger
project, set a positive `budget_usd`; its durable ledger follows a resumed run and
does not reset its allowance. CLI per-call credit limits are soft; a final response
can overshoot. Estimates are based on the dated rates in
`scripts/helpers/report-economics.mjs`, not the organization's invoice. Unknown
models have unpriced usage in the report; when a spending cap is enabled, they are
refused by budget admission until their rates are configured and verified. An
arbitrary model ID is not automatically a supported billing model.

Bootstrap pauses at an agent boundary after its 280-minute working budget, before
the job's 350-minute limit. Resume by running the **same engine commit**, with
`resume_run_id` pointing to the previous Actions run, and unchanged target commit,
model, publish setting and allowance. Artifacts are retained for 14 days.
Saved-input fingerprints still reject incompatible changes. Delivery failure is
not a successful resumable analysis: inspect the remote branch/PR before retrying.

## What has and has not been verified

The offline integration test exercises configuration, workflow generation and
validation, scoped application, hash-checked finalization, remote PR discovery and
GitHub CI evidence collection with API fixtures. Node helper tests cover the
shared runtime, reports, recovery and budget accounting. These are not a real
organization run or proof of deployed API/UI coverage.

Default bootstrap reports test execution as **not attempted** and measured coverage
as unavailable. Planned scenarios are not passing tests. After credentials and
endpoints are added, run the delivered manual workflows. To restore bootstrap
execution explicitly, use `automation.verification.mode: execute`. Foundry's own
offline regression tests below are separate from generated product suites.

GitHub Issues creation, issue-driven implementation dispatch and Azure Boards test
case synchronization are outside this bootstrap migration. Work tracking stays
disabled, and unsupported live issue operations fail explicitly. Automatic failure
triage currently produces reviewed proposals and reports. Legacy Azure DevOps
adapters remain available; their examples are under `examples/azure-devops/` and
their previous documentation is in `docs/azure-devops-reference.md`.

## Local validation

```powershell
npm ci
npm run test:helpers
pwsh -NoProfile -File scripts/github/Test-GitHubIntegration.ps1
```

The integration test makes no paid model calls and no real GitHub changes.
It leaves its evidence in `.qa-foundry-artifacts/github-tests-*`.

References: [Copilot in GitHub Actions](https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli-in-actions),
[organization server-to-server authentication](https://docs.github.com/en/copilot/how-tos/copilot-sdk/auth/server-to-server-tokens),
[GitHub App workflow permissions](https://docs.github.com/en/apps/creating-github-apps/registering-a-github-app/choosing-permissions-for-a-github-app).
