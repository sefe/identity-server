import { readFileSync } from "node:fs";

// An agent whose first answer is cut off by the model's output limit is asked
// for a smaller one. That is the runtime deciding to leave work undone, and
// this provider plays out the two ways an agent can respond to it: by saying
// what it dropped, or by handing back a short answer that claims to be whole.
const requestPath = process.argv[process.argv.length - 1];
const request = readFileSync(requestPath, "utf8");
// The provider runs in a cleaned environment, so the scenario arrives as
// arguments rather than as variables.
const [BEHAVIOUR = "declares"] = process.argv.slice(2, -1);

const agentId = (request.match(/- Agent ID: (\S+)/) ?? [, "risk-test-planner"])[1];
const stageId = (request.match(/- Stage ID: (\S+)/) ?? [, "test-planning"])[1];
const runId = (request.match(/- Run ID: (\S+)/) ?? [, "run-deferral"])[1];
const attempt = Number((request.match(/- Schema retry attempt: (\d+)/) ?? [, "1"])[1]);
const stageIteration = Number((request.match(/- Stage iteration: (\d+)/) ?? [, "1"])[1]);

// A repeated stage is given a full budget again, so the second time round the
// agent answers the whole question. Anything else would make the repeat
// pointless.
const coversEverything = BEHAVIOUR === "declaresThenCovers" && stageIteration > 1;

// Cut off mid-value and long enough that the runtime reads it as the output
// limit rather than as narration around a complete object.
if (attempt === 1 && !coversEverything && !["productGap", "executionPrerequisite", "planningPrerequisite", "ownerDependency"].includes(BEHAVIOUR)) {
  process.stdout.write('{"agentId":"' + agentId + '","summary":"' + "y".repeat(60000));
  process.exit(0);
}

const scenario = (id, rationale) => ({
  id,
  category: "security",
  priority: "high",
  rationale,
});

const artifact = {
  agentId,
  stageId,
  runId,
  status: "completed",
  summary: "Risk scenarios for the parts of the system that were covered.",
  evidence: [],
  assumptions: [],
  unknowns: [],
  warnings: [],
  details: {},
  riskScenarios: [scenario("RISK-1", "Authentication is the highest-value target here.")],
};

if (BEHAVIOUR === "declares" || (BEHAVIOUR === "declaresThenCovers" && !coversEverything)) {
  artifact.deferrals = [
    {
      kind: "output_budget",
      item: "Resilience scenarios for the payment gateway",
      reason: "The budget left room for the authentication scenarios only.",
    },
    {
      kind: "output_budget",
      item: "Accessibility scenarios for the checkout journey",
      reason: "Same budget; these were the least likely to hide a release blocker.",
    },
  ];
}
else if (BEHAVIOUR === "ownerDependency" && stageIteration === 1) {
  artifact.deferrals = agentId === "foundation"
    ? [{ kind: "output_budget", item: "QueryClient.cs", reason: "The client contract needs a continuation of this inventory." }]
    : [{ kind: "external_prerequisite", item: "QueryTests.cs", reason: "The foundation did not provide QueryClient.cs." }];
}
else if (BEHAVIOUR === "ownerDependency") {
  artifact.details.completedFiles = agentId === "foundation" ? ["QueryClient.cs"] : ["QueryTests.cs"];
}
else if (BEHAVIOUR === "productGap") {
  artifact.deferrals = [{ kind: "product_gap", item: "Create quote through the UI", reason: "The inspected UI does not implement a quote submission control." }];
}
else if (BEHAVIOUR === "executionPrerequisite") {
  artifact.details.executionPrerequisites = [{ scenarioIds: ["RISK-1"], input: "ADMIN_TOKEN", owner: "Environment owner", validation: "Require an administrator account before running the deployed suite." }];
  artifact.unknowns = ["The non-production administrator account is not provisioned; execution is pending."];
  artifact.details.assertions = [{ scenarioId: "RISK-1", expected: "A non-admin account receives 403 on the protected endpoint." }];
}
else if (BEHAVIOUR === "planningPrerequisite") {
  artifact.deferrals = [{ kind: "external_prerequisite", item: "Specify the required latency assertion", reason: "The latency objective has not been defined by the owner." }];
}
else if (coversEverything) {
  artifact.riskScenarios.push(
    scenario("RISK-2", "The payment gateway fails in ways the suite has to prove."),
    scenario("RISK-3", "Checkout has to stay usable without a mouse."));
}

process.stdout.write(JSON.stringify(artifact));
