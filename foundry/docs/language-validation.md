# Language adapter validation

Validated locally on Windows on 2026-09-22 using isolated dependency caches and public registries.
These are executable compatibility fixtures, not prescribed framework or package versions for agents.

| Scenario | Runtime and test fixture | Result |
| --- | --- | --- |
| C# | .NET SDK 10.0.400; MSTest 3.6.4; Test SDK 17.12.0 | Pass |
| JavaScript | Node 22.23.2; npm 10.9.4; node:test; picomatch 4.0.2 | Pass |
| TypeScript | Node 22.23.2; TypeScript 5.8.3; Playwright 1.51.1 | Pass |
| Vitest | Node 22.23.2; Vitest 2.1.9 with explicit imports | Pass |
| Python | Python 3.13.15; pytest 8.3.5 | Pass |
| Robot Framework | Python 3.13.15; Robot Framework 7.2.2 | Pass |
| Go | Go 1.26.8; testify v1.9.0 imported by a real test | Pass |
| Java (preceding validation) | Temurin 21; Maven 3.9.11; JUnit 5.11.3 | Pass |

Each scenario resolves and verifies its dependency lock, installs into a separate project/cache,
builds or checks syntax, executes one passing test, then adds Foundry's negative probe and
requires exactly two executed tests with one failed assertion. The delivered lock must remain
unchanged. Java additionally runs compilation and tests in Maven offline mode. Go build/test
use `-mod=readonly` and `-count=1` disables cached test results.

The Go change-set materializer was also exercised with two sibling automation projects: both
delivered manifests included their verified indirect requirements.

## Defects corrected by these checks

- Go now completes its indirect module graph before publishing `go.mod` and `go.sum`.
  Preparation repeats until the graph stabilizes, with a bounded number of passes; compilation
  does not select dependencies. Authored indirect requirements must match the resolved graph.
- NuGet, Maven, Go and Python readers no longer claim their lock formats contain an owning
  project name/version. npm still verifies that identity because its lock does record it.
- Python preparation explicitly records its approved index when pip-tools omits the default
  PyPI URL, retaining hash and source checks in the subsequent verification stage.
- Robot result parsing reads the final aggregate rather than combining child suite summaries.
- Vitest negative probes import their APIs explicitly. Jest/Vitest result parsing reads test
  counts separately from file/suite counts, so a failed import is not a failed assertion.

## Reproduce

Provision the configured runtimes on PATH (Node 22/npm 10.9.4, .NET 10, Python 3.13 with
pip-tools, Go 1.26, PowerShell 7). Use a fresh work directory for each invocation:

```powershell
./foundry/tests/powershell/Invoke-LanguageSmoke.ps1 -Case csharp -WorkRoot C:/temp/foundry-csharp-check
```

Other `-Case` values: `javascript`, `typescript`, `vitest`, `python`, `robot`, `go`.
Logs, resolved files and `summary.json` remain in the chosen directory. For Java, use
`Invoke-MavenOfflineSmoke.ps1` in the same folder. These commands download public dependencies;
they do not invoke a model or start an Azure pipeline.

This matrix verifies Foundry's dependency and test execution path for the named fixtures.
The TypeScript check executes the Playwright runner without a browser. It does not prove UI
login, credentials, a deployed API, every package combination or the target Linux agent pool.
