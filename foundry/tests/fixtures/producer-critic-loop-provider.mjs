// Plays both sides of a producer_critic_loop so the runtime's exhaustion
// handling can be exercised without a model. The agent identity is read from
// the request the runtime wrote, and the identity also states the verdict:
// a critic called '...-dissents' asks for a revision every round, one called
// '...-blocks' refuses. One fixture therefore covers both outcomes without
// environment plumbing that the provider deliberately does not forward.
import { readFileSync } from "node:fs";

const requestPath = process.argv[2];
const request = readFileSync(requestPath, "utf8");
const field = (name) => (request.match(new RegExp(`^- ${name}: (.+)$`, "m")) || [])[1]?.trim() ?? "";
const agentId = field("Agent ID");

const base = {
  agentId,
  stageId: field("Stage ID"),
  runId: field("Run ID"),
  status: "completed",
  summary: `Deterministic loop fixture result for ${agentId}.`,
  evidence: [{ source: requestPath, description: "The request the runtime wrote." }],
  assumptions: [],
  unknowns: [],
  warnings: [],
  details: {}
};

if (request.includes('## Incremental revision response')) {
  const baseSha256 = request.match(/SHA-256 ([a-f0-9]{64})/)?.[1];
  const invalidMergedValue = agentId.includes('retry') && field('Schema retry attempt') === '1';
  process.stdout.write(JSON.stringify({baseSha256, summary: 'Applied the requested change.', status: 'completed',
    edits: invalidMergedValue ? [{path: '/evidence', value: 17}] : [{path: '/details/contract', value: 'revised'}],
    deferrals: [], resolvedDeferrals: []}));
}
else if (agentId === "supervisor") {
  // The runtime asks the supervisor for advice before it blocks a run. The
  // fixture answers so the test observes the block itself rather than a schema
  // failure on the way to it.
  process.stdout.write(JSON.stringify({
    ...base,
    reason: "iteration_limit_reached",
    recommendation: "block"
  }));
}
else if (agentId.includes("producer")) {
  process.stdout.write(JSON.stringify({
    ...base,
    details: {contract: 'initial', preserved: 'Previously approved requirements stay intact.'},
    deferrals: agentId.includes('budget') ? [{kind: 'output_budget', item: 'Missing contract', reason: 'Required architecture work is incomplete.'}]
      : agentId.includes('external') ? [{kind: 'external_prerequisite', item: 'Product scope', reason: 'No authorized target can be identified.'}] : [],
    findings: [
      {
        sourceRef: requestPath,
        severity: "info",
        title: "Revision produced.",
        description: "The producer answered with the revision the critics then judged.",
        recommendation: "None.",
        confidence: 0.9
      }
    ]
  }));
}
else {
  const decision = agentId.includes('converges') && /"contract"\s*:\s*"revised"/.test(request) ? 'approved' : agentId.includes("blocks")
    ? "blocked"
    : agentId.includes("approves")
      ? "approved"
      : "revision_required";
  process.stdout.write(JSON.stringify({
    ...base,
    deferrals: agentId.includes('external') ? [{kind: 'external_prerequisite', item: 'Missing authority', reason: 'A required external decision is unavailable.'}] : [],
    decision,
    findings: decision === "approved" ? [] : [
      {
        severity: decision === "blocked" ? "critical" : "error",
        message: `The fixture critic answered ${decision}.`,
        evidence: "Deterministic fixture finding.",
        resolutionScope: "blueprint_revision"
      }
    ],
    requiredChanges: decision === "approved" ? [] : ["Address the fixture finding."],
    confidence: 0.9
  }));
}
