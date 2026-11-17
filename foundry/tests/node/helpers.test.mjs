import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "../..");

test("workflow YAML parses with expected stages", () => {
  const output = execFileSync(
    process.execPath,
    [
      path.join(root, "scripts/helpers/ConvertFrom-Yaml.mjs"),
      path.join(root, "workflows/bootstrap-automation.yaml"),
    ],
    { encoding: "utf8" },
  );
  const workflow = JSON.parse(output);
  assert.equal(workflow.name, "bootstrap-automation");
  assert.deepEqual(
    workflow.stages.map((stage) => stage.type),
    [
      "parallel_with_synthesis",
      "producer_critic_loop",
      "deterministic_action",
      "parallel_with_synthesis",
      "sequential",
      "sequential",
      "parallel_review",
      "sequential",
      "parallel_review",
      "batched_agent",
      "deterministic_action",
      "deterministic_action",
      "parallel_review",
    ],
  );
  assert.equal(workflow.stages[0].agents.length, 3);
  assert.equal(workflow.stages[1].critics.length, 3);
  // Which packages exist at which versions is a fact about a feed, not a
  // judgement, so the stage that turns the architect's proposal into a lock
  // file runs no agent and sits directly behind the architecture it locks.
  assert.equal(workflow.stages[2].action.handler, "resolve_toolchain");
  assert.equal(workflow.stages[3].agents.length, 3);
  assert.equal(workflow.stages[6].agents.length, 3);
  assert.equal(workflow.stages[8].agents.length, 3);
  // The change set is produced in assignments a model can finish, so this stage
  // carries the batch generator alongside the materialization planner.
  assert.equal(workflow.stages[9].agents.length, 2);
  // A lock file's integrity hashes come from a resolver, so the stage between
  // the plan and its review runs no agent at all.
  assert.equal(workflow.stages[10].agents, undefined);
  // Reviewers read a change set; only a run of the materialised framework can
  // say the chosen technology installs, builds and can still fail a test.
  assert.equal(workflow.stages[11].action.handler, "verify_framework");
  assert.equal(workflow.stages[12].agents.length, 3);
});

test("failed-build triage workflow files the work its analysis found", () => {
  const output = execFileSync(
    process.execPath,
    [
      path.join(root, "scripts/helpers/ConvertFrom-Yaml.mjs"),
      path.join(root, "workflows/failed-build-triage.yaml"),
    ],
    { encoding: "utf8" },
  );
  const workflow = JSON.parse(output);
  assert.equal(workflow.name, "failed-build-triage");
  // Analysis, review, a plan of the work, its review, creation, and the hand-off that starts the
  // implementation. A lane that stopped at the review would only ever produce a document.
  assert.deepEqual(
    workflow.stages.map((stage) => stage.type),
    [
      "parallel_with_synthesis",
      "sequential",
      "parallel_review",
      "sequential",
      "parallel_review",
      "deterministic_action",
      "deterministic_action",
    ],
  );
  assert.equal(workflow.stages[0].agents.length, 3);
  assert.equal(workflow.stages[2].agents.length, 3);
  assert.equal(workflow.stages[5].action.handler, "create_work_items");
  assert.equal(workflow.stages[6].action.handler, "queue_pipeline");
});

// Filing a task is not doing it, and Azure DevOps has no trigger for a work item
// becoming ready: nothing in the repository changes when one is filed. A lane
// that stops at creation therefore produces a backlog nobody will ever act on,
// which is the one failure mode that looks like success in every log.
test("every lane that files work also starts it", () => {
  const readWorkflow = (name) =>
    JSON.parse(
      execFileSync(
        process.execPath,
        [
          path.join(root, "scripts/helpers/ConvertFrom-Yaml.mjs"),
          path.join(root, "workflows", name),
        ],
        { encoding: "utf8" },
      ),
    );
  // Test cases are cards describing what the suites already cover. There is no
  // pipeline that implements a test case, so this lane files and stops on
  // purpose rather than by omission.
  const filesRecordsRatherThanWork = new Set(["test-case-sync.yaml"]);
  const lanes = [
    "change-impact.yaml",
    "failed-build-triage.yaml",
    "incident-response.yaml",
    "requirements-backlog.yaml",
    "test-case-sync.yaml",
  ];
  let checked = 0;
  for (const name of lanes) {
    const workflow = readWorkflow(name);
    const handlers = workflow.stages.map((stage) => stage.action?.handler);
    assert.ok(
      handlers.includes("create_work_items"),
      `${name} is listed as a lane that files work but files none`,
    );
    if (filesRecordsRatherThanWork.has(name)) continue;
    const creates = handlers.indexOf("create_work_items");
    const queues = handlers.indexOf("queue_pipeline");
    assert.ok(queues !== -1, `${name} files work and never starts it`);
    assert.ok(
      queues > creates,
      `${name} starts the work before the work item exists`,
    );
    checked += 1;
  }
  assert.equal(checked, lanes.length - filesRecordsRatherThanWork.size);
});

test("schema helper accepts a valid artifact and rejects an invalid one", () => {
  const helper = path.join(root, "scripts/helpers/Validate-JsonSchema.mjs");
  const schema = path.join(
    root,
    "schemas/discovery/repository-discovery.schema.json",
  );
  const valid = path.join(root, "tests/fixtures/mock-responses/repository-discovery.json");
  const validRun = spawnSync(process.execPath, [helper, schema, valid, path.join(root, "schemas")]);
  assert.equal(validRun.status, 0, validRun.stderr.toString());

  const invalid = path.join(root, "tests/fixtures/invalid-agent-result.json");
  const invalidRun = spawnSync(process.execPath, [helper, schema, invalid, path.join(root, "schemas")]);
  assert.equal(invalidRun.status, 1);
});

test("runtime schemas accept normalised SDLC and CI evidence", () => {
  const helper = path.join(root, "scripts/helpers/Validate-JsonSchema.mjs");
  const schemaRoot = path.join(root, "schemas");
  const cases = [
    [
      "schemas/runtime/sdlc-event.schema.json",
      "tests/fixtures/events/azure-devops-build-failed.json",
    ],
    [
      "schemas/runtime/ci-evidence.schema.json",
      "tests/fixtures/mock-responses/ci-evidence-not-applicable.json",
    ],
  ];
  for (const [schema, artifact] of cases) {
    const validation = spawnSync(process.execPath, [
      helper,
      path.join(root, schema),
      path.join(root, artifact),
      schemaRoot,
    ]);
    assert.equal(validation.status, 0, validation.stderr.toString());
  }
});

test("the lifecycle catalogue contains every routed SDLC lane", () => {
  const expected = new Map([
    ["change-impact.yaml", "change-impact"],
    ["requirements-backlog.yaml", "requirements-backlog"],
    ["implement-work-item.yaml", "implement-work-item"],
    ["documentation-update.yaml", "documentation-update"],
    ["release-readiness.yaml", "release-readiness"],
    ["incident-response.yaml", "incident-response"],
  ]);
  for (const [file, name] of expected) {
    const output = execFileSync(process.execPath, [
      path.join(root, "scripts/helpers/ConvertFrom-Yaml.mjs"),
      path.join(root, "workflows", file),
    ], { encoding: "utf8" });
    const workflow = JSON.parse(output);
    assert.equal(workflow.name, name);
    for (const stage of workflow.stages.filter((item) => item.type === "parallel_review")) {
      assert.ok(stage.agents.length >= 3, `${name}/${stage.id} needs three reviewers`);
      assert.equal(stage.approval.strategy, "unanimous");
    }
    for (const stage of workflow.stages.filter((item) => item.type === "deterministic_action")) {
      assert.ok(stage.action.handler);
      assert.ok(stage.action.output);
    }
  }
});
