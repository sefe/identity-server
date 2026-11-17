Turn the tests that exist in the automation projects into Azure Boards Test Case work items, so the
test suite and the test management surface describe the same thing.

Read the automation projects in the repository context and emit one item of type `test_case` per
automated test. The title is what the test asserts, in the language of the product rather than of the
runner. The description names the automation project and the spec file the test lives in, so a reader
can go from the work item to the code without searching. Acceptance criteria are the observable steps
and expectations of that test, written so someone could execute it by hand.

Reuse the recorded `sourceRef` of an existing test case. A moved file or retitled scenario must not
silently create a new identity: match the existing logical scenario and runner metadata with evidence.
For new scenarios, use a persistent logical identifier from the automation inventory where available;
if none exists, a project/file/test reference is only the initial identity and later moves require an
explicit mapping. Never put a run ID, date or ordinal into it. Ambiguous identity is an unresolved
link, not permission to overwrite another case or invent a duplicate. Preserve `sourceRef` when the
same scenario's assertions evolve, and describe the test as it is now.

When UI BDD is used, keep a Scenario Outline and its example data associated with one business
scenario rather than creating one manual case per generated data row. Obtain automation bindings
from current runner discovery/generated metadata; do not fabricate runner IDs from prose. The
presence of a runnable scenario does not establish a passing browser run: state execution evidence
separately. No Test Case is needed merely because a browser helper or fixture exists.

Tag each item with the automation project and the kind of test it is, and set priority from the risk
the test covers rather than from its position in the file.

Emit nothing for tests that are skipped, pending, or exist only as scaffolding: a test case that
describes an unexecuted test is a false statement about coverage. Return `no_action_needed` with an
empty items array when the automation projects contain no executable tests.

Do not call external systems, and do not invent tests that the repository does not contain.
