// Reproduces the provider fault that ended build 474 on the last stage of
// eleven: one call came back 400 while the same profile answered eight other
// calls in the same run. The first invocation fails the way the Copilot CLI
// failed; the second answers normally, which is what the endpoint did moments
// later. The marker lives beside the request file so the two invocations of
// this process can tell each other apart.
import { openSync, closeSync } from "node:fs";
import { dirname, join } from "node:path";

const requestPath = process.argv[process.argv.length - 1];
const counterPath = join(dirname(requestPath), "faltering-provider.count");
let firstAttempt = false;
try {
  // Exclusive creation elects exactly one failing call, without a check/write
  // race or truncating an existing file (including a symlink target).
  const fd = openSync(counterPath, 'wx');
  closeSync(fd);
  firstAttempt = true;
} catch (error) {
  if (error.code !== 'EEXIST') throw error;
}

if (firstAttempt) {
  process.stderr.write(
    "Execution failed: 400 The resource you requested was not found. " +
      "(Request ID: 9083:3F6DE9:1F48D55:238D784:6A968E9A)"
  );
  process.exit(1);
}

process.stdout.write(JSON.stringify({
  agentId: "repository-discovery",
  stageId: "discovery",
  runId: "run-faltering-provider-test",
  status: "completed",
  summary: "The repository exposes an automation prefix and one Node service.",
  evidence: [],
  assumptions: [],
  unknowns: [],
  warnings: [],
  details: {
    componentStacks: [
      {
        name: "Demo service",
        path: "src/service",
        role: "product",
        primaryLanguage: "TypeScript",
        buildSystem: "npm scripts",
        testFrameworks: [],
        packageFeeds: ["https://registry.npmjs.org"],
        evidence: ["src/service/package.json"],
      },
    ],
    primaryStack: {
      language: "TypeScript",
      buildSystem: "npm scripts",
      rationale: "The only shipped component is a Node service.",
      evidence: ["src/service/package.json"],
    },
    excludedFromStackDetermination: [],
  },
}));
