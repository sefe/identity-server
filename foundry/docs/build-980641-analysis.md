# Build 980641: full blueprint regeneration after dependency rejection

Architecture completed four critic rounds and received all three approvals. The
toolchain smoke build then correctly rejected the Messaging project's Cosmos SDK
dependency set: Microsoft.Azure.Cosmos 3.63.1 requires an explicit Newtonsoft.Json
reference. The other two minimal projects passed. Product projects already declare
Newtonsoft.Json, but that does not supply a reference to a standalone automation
project.

Returning from toolchain resolution to architecture started workflow iteration 2.
Incremental revisions were enabled only after the first **critic** round inside a
stage invocation. The returning producer therefore received a full-blueprint response
contract, despite an existing approved blueprint. Two attempts were truncated at
approximately 231 KB. The intervening complete answer exceeded three string limits;
two configuration descriptions were outside the narrow field-repair allowlist. The
third leg failed with about 566 work minutes still available.

## Runtime correction

Incremental architecture re-entry now selects the last published producer artifact
from the workflow state, verifies its hash and identity, reconstructs the bounded
critic history and starts with a JSON Pointer revision. The original response schema
still validates the merged artifact; critics still review the result. Unchanged
sections are retained without asking the producer to regenerate them.

The selection ignores unrecorded drafts and failed attempts without a published
artifact. Recorded bases and final reviews that fail integrity checks stop execution.
Global revision numbering preserves approvals and honoured commitments across stage
returns, including a relay replay. The two additional repairable configuration fields
are exact prose locations (`topicNaming` and `authorityPolicy`); arbitrary values,
paths and commands are still excluded from shortening.

## Validation and continuation

Regression coverage exercises downstream rejection, final-round base selection,
preserved commitments, failed intervening attempts, relay reuse and tampered artifacts.
The field-repair fixture covers the three rejected field locations together with the
previous summary and coverage repairs. On the actual build evidence, selection returns
critic round 4, all 12 reviews, three settled critics and 34 honoured commitments.

Prompts, schemas, workflow and product inputs are unchanged. The saved analysis can
continue from build 980641 under the existing input compatibility checks and remaining
run budget. Its package correction still requires a fresh resolver smoke build; this
runtime fix does not assert that generated dependencies or product tests have passed.
