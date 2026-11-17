# Recovery inventory validation in build 981190

The framework implementation agent returned eight changed/new contracts on each
of three calls. Each response passed its schema. Merging it with the 38-file
previous foundation produced 41 files, and the runtime rejected that aggregate
against the same 40-item schema limit. Asking the model again could not repair
the conflict. The previous candidate rehearsal exercised generation reuse but
did not run this implementation acceptance path.

The implementation schema no longer caps membership of planned, unchanged,
removed or cumulative removed file lists. Every file's structure, field lengths,
ownership and writable scope are still checked. Per-call output/time/spending
budgets and incremental revisions still bound model work. The architecture
determines the inventory, and generation partitions that inventory into batches.

Resume recognizes only the exact additive schema transition by its before/after
hashes. It reconstructs the previous whole-contract fingerprint using all current
other contracts; changing any other prompt/schema still prevents reuse. Product,
configuration, workflow, policy and analysis-input checks remain in force.
Historical input manifests and original evidence are not rewritten.

A second recovery can archive an invocation that failed before producing any
accepted artifact. Archive selection now searches past such empty stage records
for substantive evidence, stopping at incompatible inputs or run identities.
It still checks artifact hashes and refuses corrupt/missing recorded files.

Validation includes the 38+8-to-41 merge, downstream batch planning, repeat merge,
malformed file 41 rejection, exact schema compatibility, and repeated recovery.
All three original build responses were also replayed through Invoke-Agent with
a local command provider: each passed schema, merge and semantic checks on the
first attempt, producing 41 foundation contracts. Combining the first response
with the prior test inventory planned 72 files and regenerated only eight
foundation paths; test-agent changes remain subject to normal planning/review.
The ten-file verified source candidate and original verification logs survived
the second reset. No paid model calls were made for these rehearsals.

Build 981190's ledger reports three calls totaling an estimated $0.550150575.
Continuation must resume that build, retaining the same $15 additional allowance
and ledger rather than starting the allowance again from build 980930.
Successful local replay does not establish Linux CI or deployed product coverage.
