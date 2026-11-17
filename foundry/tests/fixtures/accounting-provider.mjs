import { readFileSync, writeFileSync } from "node:fs";

// A provider that reports what its call cost, and can fail in the one way the
// run does not retry. Token counts are the part the foundry cannot measure for
// itself, so they arrive the way a real provider leaves them: in a sidecar
// beside the request that was answered. The runtime has to read that sidecar
// into the call's record and then remove it, because a file of provider
// accounting left in the run directory is swept into the next agent's context
// and, on a resumed run, credited to the call that replaced this one.
const requestPath = process.argv[process.argv.length - 1];
const request = readFileSync(requestPath, "utf8");
const [MODE = "reports"] = process.argv.slice(2, -1);

if (MODE !== "silent") {
  writeFileSync(
    `${requestPath}.usage.json`,
    JSON.stringify({
      model: "accounting-model",
      input_tokens: 1234,
      output_tokens: 56,
      total_tokens: 1290,
    })
  );
}

if (MODE === "permanent") {
  // Neither a timeout nor a fault that clears on its own, so the run stops
  // here. The call still happened and still has to appear in the account of
  // what the run cost.
  process.stderr.write("Execution failed: 401 the credential was rejected.");
  process.exit(1);
}

const agentId = (request.match(/- Agent ID: (\S+)/) ?? [, "framework-implementation"])[1];
const stageId = (request.match(/- Stage ID: (\S+)/) ?? [, "implementation"])[1];
const runId = (request.match(/- Run ID: (\S+)/) ?? [, "run-accounting"])[1];

const LIMIT = 4500;
if (request.includes("# Shorten the fields that are over their limit")) {
  const pointers = [...request.matchAll(/^## (\/\S+)$/gm)].map((m) => m[1]);
  process.stdout.write(
    JSON.stringify({
      replacements: pointers.map((pointer) => ({
        pointer,
        text: "Tightened. " + "y".repeat(200),
      })),
    })
  );
  process.exit(0);
}

process.stdout.write(
  JSON.stringify({
    agentId,
    stageId,
    runId,
    status: "completed",
    summary: "Deterministic accounting fixture.",
    evidence: [{ source: "fixture", description: "Deterministic." }],
    assumptions: [],
    unknowns: [],
    warnings: [],
    details: {},
    plannedFiles: [
      {
        path: "automation/widget.mjs",
        operation: "create",
        purpose: "Hold the widget.",
        contentContract:
          MODE === "repair"
            ? "x".repeat(LIMIT + 35)
            : "The widget contract, which is within its limit.",
      },
    ],
    unchangedFiles: ["automation/untouched.mjs"],
    commandsProposed: ["dotnet build"],
  })
);
