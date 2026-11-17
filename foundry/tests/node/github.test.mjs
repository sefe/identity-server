import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import YAML from 'yaml';
import { buildReport } from '../../scripts/helpers/run-report.mjs';

test('GitHub bootstrap and installed workflows parse with explicit trust boundaries', () => {
  const root = new URL('../../', import.meta.url);
  const bootstrap = YAML.parse(fs.readFileSync(new URL('.github/workflows/bootstrap.yml', root), 'utf8'));
  assert.deepEqual(Object.keys(bootstrap.on), ['workflow_dispatch']);
  assert.equal(bootstrap.permissions.contents, 'read');
  assert.deepEqual(bootstrap.permissions, { contents: 'read', actions: 'read' });
  assert.equal(bootstrap.jobs.bootstrap['timeout-minutes'], 350);
  assert.equal(bootstrap.concurrency['cancel-in-progress'], false);
  const steps = bootstrap.jobs.bootstrap.steps;
  const checkouts = steps.filter(s => s.uses?.startsWith('actions/checkout@'));
  assert.equal(checkouts.length, 1);
  assert.equal(checkouts[0].with.ref, '${{ github.sha }}');
  assert.equal(checkouts[0].with.path, 'target');
  assert.equal(checkouts[0].with['persist-credentials'], false);
  assert.equal(bootstrap.on.workflow_dispatch.inputs.target_repository, undefined);
  assert.equal(bootstrap.on.workflow_dispatch.inputs.target_branch, undefined);
  assert.equal(bootstrap.on.workflow_dispatch.inputs.publish.default, true);
  assert.equal(bootstrap.on.workflow_dispatch.inputs.budget_usd.default, '');
  const prepare = steps.find(s => s.run?.includes('Prepare-GitHubProject.ps1 -RepositoryRoot'));
  assert.match(prepare.run, /-Repository \$env:GITHUB_REPOSITORY -Branch \$env:GITHUB_REF_NAME/);
  const installed = new URL('../../../.github/workflows/foundry-bootstrap.yml', import.meta.url);
  if (fs.existsSync(installed)) {
    assert.deepEqual(YAML.parse(fs.readFileSync(installed, 'utf8')), bootstrap);
  }
  const templates = ['finalize', 'sdlc-router', 'failed-build-triage'];
  for (const name of templates) {
    const text = fs.readFileSync(new URL(`bootstrap/github/${name}.yml.template`, root), 'utf8')
      .replaceAll('{{RUNTIME_REPOSITORY}}', 'example/foundry').replaceAll('{{RUNTIME_REF}}', 'a'.repeat(40))
      .replaceAll('{{TARGET_BRANCH}}', 'main').replaceAll('{{AUTOMATION_WORKFLOW_NAMES}}', '"API", "UI"');
    const workflow = YAML.parse(text);
    assert.ok(workflow.on && workflow.jobs);
    assert.equal(workflow.on.pull_request_target, undefined);
    assert.equal(workflow.permissions.contents, 'read');
    const job = Object.values(workflow.jobs)[0];
    assert.equal(job.steps.filter(s => s.uses?.startsWith('actions/checkout@')).length, 1);
    const restore = job.steps.find(s => s.run?.includes('git restore'));
    assert.ok(restore);
    assert.match(restore.run, /--worktree -- foundry/);
    assert.ok(restore.run.includes('a'.repeat(40)));
    if (name === 'failed-build-triage') {
      assert.deepEqual(workflow.on.workflow_run.workflows, ['API', 'UI']);
      assert.match(workflow.jobs.triage.if, /head_repository.full_name == github.repository/);
      assert.match(workflow.jobs.triage.if, /event == 'push'/);
    }
  }
});

test('GitHub report uses workflow and PR URLs without Azure registration assumptions', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'foundry-github-report-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  execFileSync('git', ['init', '-q', root]);
  const bootstrap = path.join(root, 'bootstrap.json');
  fs.writeFileSync(bootstrap, JSON.stringify({provider:'github', repositoryUrl:'https://github.com/example/product', status:'pull_request_created',
    pipelines:[{key:'agent-api',yamlPath:'.github/workflows/automation-api.yml',status:'awaiting_merge'}],
    delivery:{actions:[{type:'pull-request.draft',externalId:'42',status:'executed'}]}}));
  const report=buildReport({repositoryRoot:root,frameworkRoot:path.join(root,'foundry'),runRoot:root,bootstrapResultPath:bootstrap});
  assert.equal(report.pipelines[0].url,'https://github.com/example/product/actions/workflows/automation-api.yml');
  assert.equal(report.pipelines[0].provider,'github');
  assert.equal(report.delivery[0].url,'https://github.com/example/product/pull/42');
  assert.equal(report.verification,null);
});
