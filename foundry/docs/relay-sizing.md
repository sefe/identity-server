# Bootstrap relay sizing

The relay defaults to 12 jobs per build segment. `maxLegCount` selects 1–24 jobs;
finished analysis skips the remainder. A segment boundary is not a promise that
the analysis is finished and does not discard completed work.

Build 979783 failed after approximately 5 hours 40 minutes in job 11, at source
generation (stage 10 of 13). Its failing assignment was batch 5 of 20; some
parallel siblings had already completed. Materialization, framework verification
and final change review had not run. The same three-file response was requested
three times, consuming 55 minutes before its JSON was truncated again. The
provider ledger contains 93 calls and approximately 305 minutes of active
provider wall time after removing overlaps. Thus the elapsed time cannot be
explained by agent setup alone.

Independent source files now receive separate assignments, with up to three
calls in parallel. Dependency layers still control ordering. A cyclic group
that truncates is continued as single-file assignments with the whole group's
contracts and completed sibling bodies available as context. Each completed
part is validated and checkpointed; the merged result must cover the original
assignment exactly. No assertions or file contracts are removed to fit output.
Compilation, execution and review still decide whether that source is correct.

The ordinary 1,500-second provider timeout previously required at least 750
seconds of usable time before starting any call, plus 120 seconds for handover.
A 40-minute job could therefore hand over with almost 14.5 minutes remaining.
The runtime now admits shorter calls when at least two covered answers from the
same run, stage, provider and model support it. It uses the longest comparable
observed duration plus 50% and 60 seconds, never less than five minutes. Unknown
work, substantially larger requests and recorded provider failures retain the
conservative threshold. Handover time is still reserved.

For the next validation run on TRADING-CLOUD-01, use up to 24 jobs with
`legBudgetMinutes: 60` and the existing 90-minute whole-job ceiling. This reduces
handoffs and provides time for verification repairs without adding generation
retries. It is a self-hosted run setting, not a change to the 40-minute portable
default. The ceiling does not delay successful completion. A successful live
run is still needed to measure whether this reserve is sufficient.

## Run allowance, progress and continuation

`runBudgetMinutes` defaults to 720 work minutes across all legs and resumed
builds of the same analysis. It measures bootstrap invocation time, including
agent calls and deterministic work, excluding agent setup and time waiting
between builds. Existing operation-boundary checks use the earlier of the leg
deadline and the remaining run allowance. Final accounting records actual elapsed
time, including any boundary overrun. This is not an Azure billing limit.

`maxNoProgressLegs` defaults to 3. A new completed stage or a newly accepted
artifact version counts as progress. Calls, rejected responses and repeated
identical artifacts do not. The counter and elapsed time live in
`relay-progress.json` and travel in the integrity-checked relay evidence.
An interrupted invocation retains its reserved time. A fallback restore charges
the full work allowance for missing legs in the same build. Old evidence without
a ledger imports observed provider wall time, without double-counting concurrent
calls; its unrecorded orchestration overhead cannot be reconstructed.

Each leg uploads `relay-progress.md` to the build summary: completed stages,
accepted artifacts, retries, field repairs, remaining allowance and stagnation.
An ETA is shown only when comparable completed generation assignments exist;
it covers known pending assignments, not later stages or future repairs. Until
then the estimate is explicitly unavailable. Stage counts are not time percentages.

When the final leg pauses, it reports `continuation_required` and the Azure task
finishes with issues, not delivery success. `relay-continuation.json` records the
source version, run identity, artifact and queue parameters. Queue the same
pipeline at that source version with `resumeFromBuildId` and `resumeRunId` from
the manifest, retaining the same configuration. `restartStage: none` continues
the checkpoint; normal fingerprint validation still applies. The next build does
not reset time, accepted evidence or recovery counts. No build is queued implicitly.
Time exhaustion and stagnation stop further work even if unused leg slots remain;
continuation then requires addressing that reason or explicitly changing its limit.

## Build 980052: architecture response repair

This run stopped on leg 3, stage 2 of 13, after 126 minutes. Architecture used
about 99 minutes of provider wall time. Three rejected responses in the last
revision consumed 26.7 minutes. Its revision schema allowed a 3000-character
summary although the merged blueprint allowed 2000; the last response had 2757.
`howItIsMet` had 456 characters against a limit of 400.

Both schemas now reference one summary constraint. Revision summaries are
validated and repaired before merging. Known architecture prose locations also
use the existing bounded field repair, so only offending text is requested again.
All other content is preserved, and the complete artifact is validated before
acceptance. Paths, arbitrary configuration values and executable commands are
not automatically shortened. Raw answers and repair records remain available.
