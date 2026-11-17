# Bounded recovery of build 980930

The saved projects failed compilation and default test selection. The recovery
candidate contains ten operator-authored changed/new files, bound to the hash of
the original materialized change set. It corrects two ambiguous C# calls, the
RabbitMQ constructor, and local/deployed runner selection. It retains deployed
scenarios and their prerequisite checks.

The complete candidate passed the actual verifier locally on Windows:

| Project | Passing local tests | Deliberate probe result |
| --- | ---: | --- |
| API | 5 | 1 failure among 6 tests |
| Messaging | 6 | 1 failure among 7 tests |
| UI | 4 | 1 failure among 5 tests |

The verifier detected another runner issue during this exercise: custom MTP entry
points do not produce the generated Main previously used for runner detection.
Detection now also recognizes the generated platform registration plus a runnable
build output. Ordinary test libraries retain VSTest selection.

Recovery restarts implementation to revise the affected contracts. It receives
the operator candidate as evidence. Generation may reuse candidate source only
for subsequently approved assignments, with explicit operator provenance and no
fabricated provider receipt. It checks both the archived base hash and the
complete source fingerprint. Later repair iterations do not automatically replay
the candidate. Materialization, Linux CI verification and final review still run.
No old evidence or approval is rewritten to claim these checks already passed.

The first-start pipeline now defaults to an additional estimated allowance of
$15, starting when its durable spending ledger is created. Reservations and
settlements are shared across parallel calls and carried through resume. Missing
usage or an abandoned reservation stops further spending; another build cannot
silently raise the allowance. Each CLI invocation receives a 250-credit session
limit ($2.50 at the documented credit conversion). This is a **soft** limit:
Copilot accounts after a response, so a final response can exceed it. The outer
ledger records the excess and refuses subsequent calls when the allowance is
spent. These controls are not a guaranteed invoice maximum or a replacement for
an account-level billing limit.

Additional deterministic safeguards reject a missing npm test entry point during
generation, and prevent rewritten documents alone from resetting stagnation once
framework verification has begun. Build/test/probe milestones and completed
stages count toward technical progress. Relay summaries show the additional AI
allowance and unresolved usage.

Validation: real restore/build/test/probe for all three saved projects; focused
PowerShell and Node regression tests for recovery, CLI limits, runner selection,
concurrent reservations and stagnation; rehearsal importing all ten candidate
files with zero provider calls and rejecting the wrong baseline hash.

Limits: this does not move the entire bootstrap workflow to an early executable
skeleton, prove deployed product behavior, or establish a probability of success
on the first attempt. Early manifest checks catch a specific contract error;
they do not substitute for compilation. Independent reviewers may reject the
candidate or revised contracts, and any new source still requires verification.
