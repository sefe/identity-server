# Build 980930: framework verification and supervisor failure

The resumed run passed architecture and toolchain resolution, generated and materialized
automation, and reached framework verification (stage 12 of 13). The preceding
blueprint re-entry fix worked. Verification still found defects after three attempts:

- API: two CS0121 ambiguous `Eventually.UntilAsync` calls in SupportContractTests.cs.
- Messaging: CS1739 for the unsupported named `CreateChannelOptions` parameter
  `publisherConfirmationTracking` in RabbitMqProbe.cs.
- UI: typecheck passed, but `npm test` selected deployed Playwright scenarios. All
  23 executed tests failed in fixture preflight because CPS_TARGET_ENVIRONMENT was
  absent; another seven did not run. This is not evidence of a product defect.

After the configured verification attempts, the supervisor crashed before returning
its decision. Its immutable snapshot was named `workflow-state.json`; the Copilot
provider's ancestor search mistook that nested directory for the run root and tried
to write a nonexistent `context/copilot-preflight.json` there. Mock-provider tests
did not exercise that path.

## Corrections

- New supervisor snapshots use `workflow-snapshot.json`. Provider and timing-history
  root searches also require the workflow context directory, so legacy snapshots
  cannot shadow the actual root.
- Recovery selects the latest attempt carrying diagnostic artifacts. A subsequent
  supervisor exception with no artifacts no longer hides the verification report.
  Full compiler/test logs are passed by verified path with their recorded hashes.
- Agents receive the actual verification entry-point contract: adapters invoke
  `npm test`, or the .NET test runner without an automatically supplied category
  filter. Proposed CI commands and category labels alone do not create that default
  selection. Local verification must execute real assertions and its negative probe;
  deployed suites retain their explicit execution and prerequisite checks.
- When npm tests fail on missing execution configuration, targeted repair includes
  the manifest and approved runner configuration as well as the reported source
  locations. It must not weaken preflight, invent environment values or skip tests.

## Evidence and recovery boundary

A fake Copilot CLI reproduces the nested supervisor snapshot and verifies that
preflight is written at the real root. Recovery tests cover the later exception,
preserved original diagnostics and rejection of modified logs. A rehearsal on a
copy of the actual evidence successfully restarts implementation while retaining
discovery, architecture, resolved toolchains and generation iteration 3.

Restart implementation to revise the affected contracts and any missing local test
files. Existing artifact identity and source reuse rules still apply. Prompts and
schemas are unchanged, so the saved input compatibility checks remain applicable.
No existing product or deployed assertion is waived. The generated C# repairs and
default test selection still require a new real build/test/negative-probe result;
the runtime tests do not establish that those generated projects are now verified.
