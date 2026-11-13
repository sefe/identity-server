# Evidence-based architecture deliberation

Choose the strongest testing design for this product, not the easiest framework to make green in
the bootstrap environment. Languages, libraries, versions, test levels, mocks, in-process hosts,
containers, emulators, local services and deployed targets are design choices to justify with
evidence. Product code remains read-only. Reading or building an isolated product copy is not
permission to modify product source; harnesses belong in authorized automation paths.

## Compare before selecting

In the existing `details.decision` section, record a compact comparison:
- `options`: at least two materially different candidate testing architectures, including the strongest
  relevant existing approach when available. Compare test boundaries, not just library names. Do not
  invent a weak alternative to make a favourite win. If only one is viable, explain the evidence
  excluding the others rather than fabricating a second viable choice.
- `criteria`: risk detection, controllable failures, assertion strength, diagnosis, reproducibility,
  maintenance, environment dependencies and execution cost. Explain the decisive criteria for this
  product. Mark estimates and unmeasured costs; never fabricate scores or benchmarks.
- `chosenOption`, `whyChosen`, `tradeoffs`, `changeConditions`: evidence, disadvantages accepted and
  facts that would change the choice. Cite repository evidence and official documentation actually
  read. Best practice is contextual evidence, not a slogan.

In `details.testTaxonomy`, map major product risks to layers, stimuli, assertions and observation
points. Component, contract, integration and user-journey tests are possible techniques, not a required
list of frameworks or project boundaries. Assess their relevance from this product's evidence.
For asynchronous products assess ordering, duplicates, persistence, recovery and state transitions.
Explain an omitted layer. Do not require every layer or a fixed pyramid ratio for every product.
Project count is not layer count: several suites may share a project within the user's bounds.

## Let evidence determine project boundaries

The agents decide the decomposition. Do not prescribe projects by test level, product component,
protocol or language, and do not copy an existing suite's split merely because it was used as an
example. Preserve the user's explicit deliverables and configured count bounds; those are constraints,
not a target number or a taxonomy to fill. The upper bound is permission, not a quota.

For each proposed boundary, compare keeping the tests in a shared framework with separating them.
Explain the concrete benefit and the added setup, duplicated fixtures, dependencies, execution and
maintenance costs. Separate only where independent execution, incompatible dependencies, isolation,
ownership or another evidenced need outweighs those costs. Otherwise keep tests together using the
runner's suites, tags or modules. Different test levels can share a framework; the same level can
span frameworks when justified. Record the chosen grouping and rejected alternatives in the blueprint.

Reviewers challenge unnecessary splits and harmful coupling independently. Neither more projects
nor fewer projects is inherently a better outcome; the justified fit to this product decides.

## Independent challenge and resolution

Each architecture critic independently challenges the most consequential tradeoff against the
strongest alternative through its specialty. Record the argument, evidence and disposition in the
review's existing details/findings. Another model's approval or confident prose is not evidence.
Do not manufacture objections or extra rounds when evidence already settles the comparison.

Coverage reviewers challenge missing failure paths and weak assertions. Delivery reviewers assess
reproducibility, dependencies, isolation, diagnosis and cost. Security reviewers assess concrete trust
boundaries without inventing blanket bans on a language, library, host or non-production test stack.
The architect resolves substantive disagreement explicitly. Reopen a settled choice only when new
evidence invalidates it, naming affected commitments and required re-review; never silently weaken it.

## Capability is different from availability

Missing feed credentials, a container runtime, an image or a target endpoint is an execution
prerequisite, not proof of inferior architecture. Distinguish verified absence from availability
not yet tested. Record the resource, owner, affected layers and concrete validation procedure.
Do not replace valuable product-behavior coverage with schema/configuration checks just to pass
bootstrap. Inspect available read-only source and existing test seams before declaring a fault
impossible to stimulate. Test-owned hosts, doubles and disposable infrastructure can provide those
seams without modifying product code.

Do not claim unsupported tooling works. When the selected architecture requires a graph layout,
restore flow or execution capability the current adapter lacks, name the precise gap and affected
command. Preserve the target design, and block affected execution honestly instead of disguising
a weaker fallback as equivalent coverage. Private dependencies require an authenticated restore
contract. Local stacks require startup, readiness, isolation and cleanup. Never invent credentials.

Report planned coverage, implemented tests, executed product behavior, support checks and unmet
prerequisites separately. Restore, schema checks and negative probes prove only what they execute;
they do not establish deployed business coverage. Every material omission needs a reason.

Before accepting an external blocker, both the producer and each critic must apply the shared
boundary analysis to the exact assertion. Require evidence that the missing external fact is
necessary for that assertion, rather than only for the currently selected topology. An unset
endpoint is not evidence that a source-backed protocol is unspecified. A backend name in a document
does not supply its query contract, nor require every export test to query that backend. Consider
automation-owned observation points without assuming permission to reconfigure a shared deployment.

Review planned harnesses as contracts for later implementation, not as already existing tools.
Request `blueprint_revision` for missing dependencies, observation semantics, real product stimuli,
isolation or failure behavior. Do not demand already-generated files at architecture time or a
specific language, framework count or backend. Preserve explicitly required integration boundaries;
an alternative that cannot exercise them must disclose that limitation. A genuinely unavailable
contract needed for every viable design remains an external prerequisite, not a waived assertion.

## Reference starting points

Consult relevant primary sources when available, recording what was actually read. These examples
do not mandate a technology or architecture:
- https://martinfowler.com/articles/practical-test-pyramid.html
- https://martinfowler.com/articles/microservice-testing/fallback.html
- https://learn.microsoft.com/en-us/aspnet/core/test/integration-tests

If a source cannot be retrieved, disclose that limit and use inspected repository evidence. Never
attribute a recommendation to unread documentation.
