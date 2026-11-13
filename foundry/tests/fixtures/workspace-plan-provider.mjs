import { readFileSync } from "node:fs";

// Reproduces what bootstrap-change-generator produced in build 466: a
// schema-valid plan whose manifest turns three automation projects into an npm
// workspace. The materialiser cannot resolve that, and by the time it says so
// the generator is out of reach, so the runtime has to reject it while the agent
// still has an attempt left. The second answer is what the feedback asks for.
const requestPath = process.argv[process.argv.length - 1];
const request = readFileSync(requestPath, "utf8");
const corrected = request.includes("recipe cannot materialise that");

const workspaceManifest = {
  name: "automation",
  version: "0.0.0",
  private: true,
  workspaces: ["projects/*"],
  devDependencies: { "@playwright/test": "1.62.1", typescript: "5.9.3" },
};
const singlePackageManifest = {
  name: "automation",
  version: "0.0.0",
  private: true,
  devDependencies: { "@playwright/test": "1.62.1", typescript: "5.9.3" },
};

const changes = [
  {
    operation: "create",
    path: "automation/package.json",
    expectedSha256: "",
    content: JSON.stringify(
      corrected ? singlePackageManifest : workspaceManifest,
      null,
      2,
    ),
    reason: "Declare the approved toolchain.",
    sourceRefs: ["work-item:42"],
  },
];
if (!corrected) {
  changes.push({
    operation: "create",
    path: "automation/projects/ui/package.json",
    expectedSha256: "",
    content: JSON.stringify({ name: "ui", version: "0.0.0" }, null, 2),
    reason: "Give the UI project its own package.",
    sourceRefs: ["work-item:42"],
  });
}

process.stdout.write(
  JSON.stringify({
    agentId: "bootstrap-change-generator",
    stageId: "bootstrap-change-generation",
    runId: "run-workspace-plan-test",
    status: "completed",
    summary: "Propose the automation package.",
    evidence: [],
    assumptions: [],
    unknowns: [],
    warnings: [],
    details: {},
    outcome: "proposed",
    changes,
    materializations: [
      {
        recipe: "npm-package-lock",
        toolchainId: "npm-playwright-test",
        projectPaths: ["automation"],
        manifestPath: "automation/package.json",
        lockPath: "automation/package-lock.json",
        operation: "create",
        expectedSha256: "",
        reason: "Lock the approved toolchain.",
        sourceRefs: ["work-item:42"],
      },
    ],
  }),
);
