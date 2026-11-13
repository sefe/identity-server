import { readFileSync } from "node:fs";

// Build 972914 reached stage 11 of 13 and blocked there because a .csproj asked
// for MSTest@[4.2.3,5.0.0). A resolver pins one version and writes that version
// into the lock, so a range is a lock the manifest cannot match - and the stage
// that says so is deterministic, with no way back to the agent that wrote it.
// Here the first answer carries the range and the second names the version.
const requestPath = process.argv[process.argv.length - 1];
const request = readFileSync(requestPath, "utf8");

const agentId = (request.match(/- Agent ID: (\S+)/) ?? [, "bootstrap-change-generator-batch-01"])[1];
const stageId = (request.match(/- Stage ID: (\S+)/) ?? [, "bootstrap-change-generation"])[1];
const runId = (request.match(/- Run ID: (\S+)/) ?? [, "run-version-range"])[1];
const attempt = Number((request.match(/- Schema retry attempt: (\d+)/) ?? [, "1"])[1]);

const version = attempt === 1 ? "[4.2.3,5.0.0)" : "4.2.3";
const manifest = [
  '<Project Sdk="Microsoft.NET.Sdk">',
  "  <PropertyGroup>",
  "    <TargetFramework>net8.0</TargetFramework>",
  "  </PropertyGroup>",
  "  <ItemGroup>",
  `    <PackageReference Include="MSTest" Version="${version}" />`,
  "  </ItemGroup>",
  "</Project>",
].join("\n");

process.stdout.write(
  JSON.stringify({
    agentId,
    stageId,
    runId,
    status: "completed",
    summary: "A batch that authors one automation manifest.",
    evidence: [],
    assumptions: [],
    unknowns: [],
    warnings: [],
    details: {},
    outcome: "proposed",
    batchId: "batch-01",
    changes: [
      {
        path: "automation/Widget.Automation.Api/Widget.Automation.Api.csproj",
        operation: "create",
        expectedSha256: "",
        content: manifest,
        reason: "An isolated automation test manifest on the locked toolchain.",
        sourceRefs: ["context/toolchain-lock.json"],
      },
    ],
  }));
