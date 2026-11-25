# Recover a bootstrap blocked after implementation review

Use **Foundry Bootstrap → Run workflow** after the recovery fix is merged. Select the same branch as the failed run, containing the repaired runtime, and supply:

| Input | Value |
| --- | --- |
| `resume_run_id` | The failed run with the complete `foundry-evidence` artifact |
| `restart_stage` | `implementation` |
| `model`, `publish`, `budget_usd` | Exactly the values from that run |
| `auto_resume`, `max_continuations` | The desired continuation controls; the existing chain counter and spending evidence are retained |

For run **45608676916**, use model `claude-opus-5.5`, `publish=true`, and an empty `budget_usd`, on `main`. Its saved product commit is `9975c892cd112ad51f25d143fd5f3c5dcdebd02d`.

The explicit restart permits a repaired runtime commit while restoring the original product commit from the checkpoint. Only `foundry/` is overlaid from the selected runtime. Product files, including the root workflow analyzed in the original run, remain at the saved commit. A recovery therefore describes that saved product revision, even if the branch now contains newer product changes. Source, configuration, workflow, policy and prompt/schema fingerprints are still checked before model work; an incompatible change requires a fresh analysis.

Stages 1–4 and their repository context remain intact. Stage 5 and later stages reset to pending; their old evidence is archived under `recovery/`. The implementation agents receive the prior accepted inventories and the latest hash-verified downstream reviews, required changes and delivery deferrals. Earlier rejections superseded by later reviews are not reused. `approved_with_dissent` does not hide the dissenting review. New review approval is required before delivery can proceed normally.

The existing review iteration limit is unchanged. Restarting implementation starts a new bounded review cycle; it does not fabricate approval or guarantee that the revised proposal passes review. No generated test execution is claimed when bootstrap verification is deferred.

If the recovered run pauses, subsequent automatic or manual continuations must leave `restart_stage` empty and use the **most recent** run ID. They retain the saved product SHA and use the same repaired runtime SHA. This prevents a continuation from repeatedly resetting implementation. Blocked or failed runs are never automatically restarted.

Do not edit `workflow-state.json` to mark reviews approved, restart delivery preparation to repair implementation, or use GitHub's **Re-run jobs** as a substitute for selecting this recovery input. The GitHub entry point forwards the selection to `Start-FoundryBootstrap.ps1 -Phase Plan -ResumeRunRoot ... -RestartStage implementation` only after locating exactly one saved analysis.

Offline regression tests cover checkpoint identity, source/runtime separation, unchanged fingerprint gates, review evidence integrity, superseded findings and entry-point forwarding. The downloaded evidence for run 45608676916 was additionally replayed on a temporary copy without model calls or GitHub writes: stages 1–4 and both inventories were retained, and the EnvironmentPicker response-filter repair reached the recovery context.
