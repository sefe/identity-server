# Package ecosystem adapters

An adapter is everything this runtime needs to know about one package ecosystem.
Nothing outside this directory may assume a manifest is JSON, that dependencies
live under `dependencies` and `devDependencies`, that a lock file is called
`package-lock.json`, or that `^1.2.3` means what npm means by it. Where the
runtime needs such an answer it asks the adapter for the ecosystem the locked
toolchain names.

That is what lets the architect choose a technology from the product's own
solution rather than from a list written into a configuration file months
earlier. A C#/.NET product gets NuGet because the adapter exists, not because
someone remembered to add packages to an allowlist.

## Shipped adapters

| id | recipe | manifest | lock |
| --- | --- | --- | --- |
| `npm` | `npm-package-lock` | `package.json` | `package-lock.json` |
| `nuget` | `nuget-packages-lock` | `*.csproj` | `packages.lock.json` |
| `pypi` | `pip-requirements-lock` | `requirements.txt` | `requirements.lock` |
| `maven` | `maven-dependency-lock` | `pom.xml` | `dependency-lock.txt` |
| `rubygems` | `bundler-gemfile-lock` | `Gemfile` | `Gemfile.lock` |
| `go` | `go-module-sum` | `go.mod` | `go.sum` |
| `composer` | `composer-package-lock` | `composer.json` | `composer.lock` |

`npm` and `nuget` are proven end to end. The other five are complete and their
parsers are tested, but their resolve commands are written from documentation
rather than executed, because those tools are not installed on this agent.

## Adding one

Create `<id>.Ecosystem.ps1` defining a function named
`New-QaFoundry<Id>EcosystemAdapter` — `pypi` becomes `New-QaFoundryPypiEcosystemAdapter`
— that returns a hashtable with the members below. `Get-QaFoundryEcosystemAdapter`
finds it by file name and refuses an adapter whose `id` disagrees with its file
name. Nothing needs registering anywhere else.

Then add the ecosystem to `automation.ecosystems` in `config/project.yaml` with a
dependency source. `Validate-QaFoundryConfig.ps1` refuses a configuration that
declares an ecosystem with no adapter, or an adapter pointing at a resolve or
verify script this installation does not ship: declaring support the runtime
cannot deliver is worse than declaring none, because the architect would be told
it may design in that ecosystem and the run would die at materialisation with
the design already written.

## The contract

### Data

| member | meaning |
| --- | --- |
| `id` | Matches the file name. Checked. |
| `displayName` | How the ecosystem is named in a message to a person. |
| `recipe` | The materialisation recipe a plan asks for. Must be unique across adapters, and must appear in `materialization-item.schema.json`. |
| `GetManifestFileName` | Given the project's name, the file its manifest is written to. A constant for most ecosystems; NuGet names the file after the project. Must return a file name, not a path. |
| `manifestPattern` | Regex a manifest path must match. |
| `lockFileName`, `lockFilePattern` | The same for the lock file. |
| `requiredRuntimeKeys` | Runtime keys a configured ecosystem must pin, such as `npm_version`. |
| `resolveScript`, `verifyScript` | Scripts under `scripts/actions/`. Both are the generic pair; an adapter needs its own only if the generic one genuinely cannot serve it. |
| `unverifiableManifestKeys` | Declarations that change what gets installed in ways this runtime cannot check, such as npm `workspaces` or `overrides`. |
| `localDependencyPrefixes` | Specifier prefixes that point at a directory rather than a feed. |
| `exactVersionPattern` | What a single released version looks like written down. An ecosystem stating no rule pins nothing: an unverifiable pin is the failure this guards against. |

### Behaviour

| member | answers |
| --- | --- |
| `ReadRuntime` | The runtime block for a toolchain, from the configured ecosystem. |
| `ResolveProposedRuntime` | The runtime to lock, given the one the design asks for and the one this installation has. Returns the runtime that honours the design where the installation can serve it, and throws naming both versions where it cannot. An SDK builds older target frameworks and so may accept a lower request; a language runtime that is not backward-compatible must refuse anything but its own. |
| `NewManifestContent` | A manifest declaring exactly the locked packages. |
| `ReadManifestDependencies` | `{name, version, scope}` per declared dependency. |
| `ReadManifestIdentity` | `{name, version}`, either empty where the ecosystem does not ask a private package for one. |
| `GetPublishedVersions` | Every version the feed actually has. Nothing trusts a model's arithmetic here. |
| `SelectVersion` | The version a requirement resolves to, in this ecosystem's semantics. |
| `GetRuntimeRequirements` | Which tools must be present, and at which versions. |
| `GetInstallCommand`, `GetBuildCommand`, `GetTestCommand` | Argument lists, never shell strings. |
| `ReadTestRunSummary` | `{parsed, total, failed, skipped}` from the runner's own output. `parsed` is false where no counts could be read, which is not the same as a run of zero tests. |
| `NewNegativeProbe` | A deliberately broken expectation, used to prove the suite can go red. |
| `GetResolverTools` | `{key, command, label, expectedVersion, match}` per tool. `match` is `exact`, `major`, `minor` or `none`. |
| `NewNeutralConfigFiles` | Configuration that stops the resolver reading the machine's own settings. An inherited `.npmrc` could redirect the feed or attach a credential to a request the runtime believes is anonymous. |
| `GetResolveCommand` | The resolution to run. Return `{commands = @(...)}` for several steps — Maven needs `go-offline` then `dependency:tree`. |
| `ReadLockEntries` | The lock, read into the shape the verifier checks. |
| `NewLockFromWorkspace` | Optional. Synthesises a lock after the commands, from what the tools actually fetched, for an ecosystem that ships no lock file. |

### `ReadLockEntries`

```
{
  parsed, parseError, formatVersion,
  identity { name, version },
  direct  [ { name, version, scope } ],
  entries [ { key, name, version, integrity, resolvedUrl, isLocal } ],
  originRecorded, originIsPerFile, feeds []
}
```

The verifier reads the optional members defensively, so an adapter that omits
one gets the strict default rather than a silent exemption.

The three origin models are all honest, and none of them is a skip:

- **Per package.** npm and Composer record an address for every package, so
  every entry is checked against the approved feed.
- **Per file.** pip-compile and Bundler record the feed once for the file. Set
  `originIsPerFile`, and the feeds are checked once.
- **None.** NuGet and Go record no origin at all. Set `originRecorded = $false`,
  and the verifier then demands a content hash on every entry instead — a
  hostile feed can serve the request, but it cannot change the bytes.

## Writing one safely

Real bugs, each found in this directory:

- Inside a hashtable literal, `x = $a -replace "p", ""` parses the comma as a
  member separator. Wrap the whole expression in parentheses.
- `$matches` is an automatic variable. Do not assign to it.
- `-match "a" + "b"` matches first and concatenates afterwards. Parenthesise.
- `Set-StrictMode` in a caller reaches into dot-sourced code, so check for an
  optional property with `Get-QaFoundryPropertyNames` before reading it.

Version selection is where ecosystems differ most, and each of these is
implemented rather than approximated:

- A bare Maven version is a *soft requirement* — use that release, refuse a
  neighbour — while a bare NuGet version is a *lower bound*, resolved to the
  lowest version that satisfies it.
- Composer's `~1.2` reaches 1.9 where npm's `~1.2` stops inside 1.2.x.
- PEP 440 writes a pre-release without a hyphen (`2.0b1`), and `1.2.3.post1` is
  *newer* than `1.2.3`.
- RubyGems separates a pre-release with a dot (`4.0.0.rc1`).
- Go accepts only exact versions and throws on a range.

Deliberately excluded from "the newest release": Maven `-SNAPSHOT`, because it
is republished under the same coordinates; Go pseudo-versions, which name a
commit and are resolvable only when asked for by name; and yanked RubyGems and
PyPI releases with no files.

## Tests

`tests/powershell/Ecosystems.Tests.ps1` is the regression net for this whole
area and runs in about twenty seconds. Run it after every change here.
