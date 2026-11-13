// Reproduces what bootstrap-change-generator returned in build 462: a
// schema-valid change set that refuses to deliver, because the approved
// inventory required lock files it cannot honestly author. The refusal is a
// judgement about the work, so the run must report it as a stopped run rather
// than as a crash in the runtime.
process.stdout.write(JSON.stringify({
  agentId: "bootstrap-change-generator",
  stageId: "bootstrap-change-generation",
  runId: "run-blocked-change-set-test",
  status: "blocked",
  summary: "The approved inventory cannot be turned into a safe change set from the supplied evidence.",
  evidence: [],
  assumptions: [],
  unknowns: ["The approved exact versions of the test packages were never fixed."],
  warnings: ["Hand-authored lock files would break a clean-checkout restore."],
  details: { requiredRepairPaths: [] },
  outcome: "blocked",
  batchId: "batch-01",
  changes: []
}));
