// Reproduces the answer architecture-critic gave in build 460: a schema-valid
// review that approves the blueprint while carrying an empty details object.
// Reading the property names of that object threw under Set-StrictMode, so the
// approval was deleted and the leg crashed.
process.stdout.write(JSON.stringify({
  agentId: "architecture-critic",
  stageId: "architecture",
  runId: "run-empty-details-test",
  status: "completed",
  summary: "The blueprint keeps automation inside the writable prefix and proposes runnable commands.",
  evidence: [],
  assumptions: [],
  unknowns: [],
  warnings: [],
  details: {},
  decision: "approved",
  findings: [
    {
      severity: "info",
      message: "The blueprint restricts writes to the automation prefix.",
      evidence: "automation-blueprint.json structure.root",
      resolutionScope: "blueprint_revision"
    }
  ],
  requiredChanges: [],
  confidence: 0.95
}));
