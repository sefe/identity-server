import { readFileSync } from "node:fs";

// Reproduces build 498, which died on the last of twelve batches. That batch
// refused correctly: the contract of a file it owned needed operations the file
// it imports, written and final in a lower layer, did not offer. Owning files is
// what makes the layers safe and it is also what leaves a batch with nowhere to
// go. Here the refusal names the file it would have had to write as well, and
// the second answer writes both.
const requestPath = process.argv[process.argv.length - 1];
const request = readFileSync(requestPath, "utf8");
// The provider runs in a cleaned environment, so the scenario is passed as
// arguments: the batch that refuses, the paths its refusal names, and whether
// the merged second call refuses as well.
const [REFUSING_BATCH = "", requiredArgument = "none", escalationArgument = ""] =
  process.argv.slice(2, -1);
const REQUIRED =
  requiredArgument === "none"
    ? []
    : requiredArgument.split(",").map((p) => p.trim()).filter(Boolean);
const REFUSE_AGAIN = escalationArgument === "escalation:refuse";
// The escalation answers, but without the files it was given in order to
// rewrite. Merged as it stands, the plan keeps the versions the refusal was
// about and nothing anywhere says so.
const SKIP_REQUIRED = escalationArgument === "escalation:partial";

const agentId = (request.match(/- Agent ID: (\S+)/) ?? [, "bootstrap-change-generator"])[1];
const stageId = (request.match(/- Stage ID: (\S+)/) ?? [, "bootstrap-change-generation"])[1];
const runId = (request.match(/- Run ID: (\S+)/) ?? [, "run-batched-generation"])[1];

const base = {
  agentId,
  stageId,
  runId,
  status: "completed",
  summary: "Deterministic escalation fixture.",
  evidence: [],
  assumptions: [],
  unknowns: [],
  warnings: [],
  details: {},
};

const assignedPaths = [
  ...new Set(
    [...request.matchAll(/"(automation\/[A-Za-z0-9._\-/]+)"/g)].map((m) => m[1]),
  ),
];
const batchId = (request.match(/"batchId":\s*"([^"]+)"/) ?? [, ""])[1];

// The planner runs on the same provider. It has no assignment and a schema of
// its own, so answering it with a change set would fail validation rather than
// exercise anything.
if (!batchId) {
  process.stdout.write(
    JSON.stringify({ ...base, outcome: "no_action_needed", materializations: [] }),
  );
  process.exit(0);
}

// The assignment lists its own paths first and every approved path after them,
// so the assigned set is read from the field rather than from the whole file.
const assignedBlock = request.match(/"assignedPaths":\s*\[([^\]]*)\]/);
const own = assignedBlock
  ? [...assignedBlock[1].matchAll(/"([^"]+)"/g)].map((m) => m[1])
  : assignedPaths;

const isEscalation = batchId.includes("-escalated");
const refuses = isEscalation ? REFUSE_AGAIN : batchId === REFUSING_BATCH;

if (refuses) {
  process.stdout.write(
    JSON.stringify({
      ...base,
      status: "blocked",
      summary:
        "The assigned contract needs operations the files it imports do not offer.",
      details: { requiredRepairPaths: isEscalation ? [] : REQUIRED },
      outcome: "blocked",
      batchId,
      changes: [],
    }),
  );
  process.exit(0);
}

process.stdout.write(
  JSON.stringify({
    ...base,
    outcome: "proposed",
    batchId,
    changes: (isEscalation && SKIP_REQUIRED
      ? own.filter((path) => !REQUIRED.includes(path))
      : own
    ).map((path) => ({
      operation: "create",
      path,
      expectedSha256: "",
      content: isEscalation
        ? `// reconciled by ${batchId}\nexport const reconciled = true;\n`
        : `// written by ${batchId}\nexport const written = true;\n`,
      reason: "Deliver the approved file.",
      sourceRefs: ["work-item:42"],
    })),
  }),
);
