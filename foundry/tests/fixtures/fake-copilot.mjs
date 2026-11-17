const args = process.argv.slice(2);
if (args.includes("version")) {
  process.stdout.write("fake-copilot 1.0.0");
  process.exit(0);
}

const modelArg = args.find((value) => value.startsWith("--model="));
const effortArg = args.find((value) => value.startsWith("--reasoning-effort="));
const promptIndex = args.indexOf("-p");

// The real CLI writes its final usage statistics to the file named by
// --usage-output-file. The model name selects which of the shapes it can
// produce this run stands in for, so no extra environment has to be threaded
// through a provider that deliberately scrubs it.
const usageIndex = args.indexOf("--usage-output-file");
const model = modelArg?.slice("--model=".length) || "";
const usageMode = model.startsWith("usage-") ? model.slice("usage-".length) : "single";
if (usageIndex >= 0 && usageMode !== "none") {
  const { writeFileSync } = await import("node:fs");
  const usagePath = args[usageIndex + 1];
  const modelMetrics = (input, output, cacheRead) => ({
    requests: { count: 1, cost: 15 },
    usage: {
      inputTokens: input,
      outputTokens: output,
      cacheReadTokens: cacheRead,
      cacheWriteTokens: 0,
      reasoningTokens: 0,
    },
  });
  let document = "";
  if (usageMode === "garbage") {
    document = "{ this is not json";
  } else if (usageMode === "empty") {
    document = JSON.stringify({ totalUserRequests: 1, modelMetrics: {} });
  } else if (usageMode === "partial") {
    document = JSON.stringify({
      currentModel: model,
      modelMetrics: {
        [model]: {
          requests: { count: 1, cost: 15 },
          usage: {
            inputTokens: 1234,
            outputTokens: "many",
            cacheReadTokens: 7,
          },
        },
      },
    });
  } else if (usageMode === "invalid") {
    document = JSON.stringify({
      currentModel: model,
      modelMetrics: {
        [model]: {
          requests: { count: 1, cost: 15 },
          usage: {
            inputTokens: -1,
            outputTokens: "many",
            cacheReadTokens: null,
          },
        },
      },
    });
  } else if (usageMode === "multi") {
    document = JSON.stringify({
      currentModel: "model-a",
      modelMetrics: {
        "model-a": modelMetrics(1000, 20, 4),
        "model-b": modelMetrics(234, 36, 3),
      },
    });
  } else {
    document = JSON.stringify({
      totalPremiumRequestCost: 15,
      totalUserRequests: 1,
      currentModel: model,
      modelMetrics: {
        [model]: modelMetrics(1234, 56, 7),
      },
    });
  }
  writeFileSync(usagePath, document, "utf8");
}

// Stands in for a call the CLI could not complete. The usage document above is
// written first on purpose: the real CLI leaves one behind on a failed call too.
if (args.includes("--fail")) {
  process.stderr.write("fake-copilot was asked to fail");
  process.exit(3);
}

process.stdout.write(
  JSON.stringify({
    model: model,
    reasoningEffort: effortArg?.slice("--reasoning-effort=".length) || "",
    prompt: promptIndex >= 0 ? args[promptIndex + 1] : "",
    viewOnly:
      args.includes("--available-tools=view") &&
      args.includes("--allow-tool=view"),
    noAskUser: args.includes("--no-ask-user"),
    maxAiCredits: args.includes('--max-ai-credits') ? Number(args[args.indexOf('--max-ai-credits') + 1]) : null,
    shellAllowed: args.some(
      (value) => value.startsWith("--allow-tool=") && value.includes("shell"),
    ),
    token:
      process.env.COPILOT_GITHUB_TOKEN ||
      process.env.GH_TOKEN ||
      process.env.GITHUB_TOKEN ||
      "",
    noAutoUpdate: args.includes("--no-auto-update"),
    taskTimeout: process.env.COPILOT_TASK_WAIT_TIMEOUT_SECONDS || "",
  }),
);
