// An architect that has read the approved profiles and found none of them covers
// the work it was asked to do. It has no design to report, so it reports the gap
// instead. Demanding a blueprint here is how a refusal turns into an invented
// design that nobody can build.
process.stdout.write(JSON.stringify({
  agentId: "automation-architect",
  stageId: "architecture",
  runId: "run-blocked-blueprint",
  status: "blocked",
  summary: "No approved toolchain profile covers the load testing the request asks for.",
  evidence: [],
  assumptions: [],
  unknowns: ["Which profile a person wants load testing built on."],
  warnings: [],
  outcome: "blocked",
  details: {}
}));
