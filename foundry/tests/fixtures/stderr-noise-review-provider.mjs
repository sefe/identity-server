// Reproduces what build 465 did to leg 1: an agent whose first attempt failed and
// whose retry succeeded. The recovered attempt still left output on stderr, which
// PowerShell records in the runspace error stream and which used to kill the stage
// after the artifact had already been accepted. The review below is valid, so the
// stage must complete and merely report the noise.
process.stderr.write("\n");
process.stderr.write("copilot: previous attempt returned an empty response\n");
process.stdout.write(JSON.stringify({
  agentId: "first-reviewer",
  stageId: "revision-review",
  runId: "run-stderr-noise",
  status: "completed",
  summary: "The subject carried forward is the one the run materialised last.",
  evidence: [],
  assumptions: [],
  unknowns: [],
  warnings: [],
  details: {},
  decision: "approved",
  findings: [],
  requiredChanges: [],
  confidence: 0.95
}));
