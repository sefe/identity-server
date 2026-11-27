import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import YAML from 'yaml';
import { prepareContinuation, prepareCheckpoint, continueBootstrap } from '../../scripts/github/bootstrap-continuation.mjs';

const identity = { repository: 'example/product', branch: 'main', sha: 'a'.repeat(40), id: '100' };
const inputs = { model: 'claude-opus-5.5', publish: 'true', budget_usd: '12.50',
  auto_resume: 'true', max_continuations: '3', resume_run_id: '' };
const fresh = () => prepareContinuation({ ...identity, inputs });
const options = (state = fresh()) => ({ ...identity, state, status: 'paused', attempt: '1', token: 'test-secret' });
const response = (status, body = {}) => ({ status, json: async () => body });
function api({ sha = identity.sha, status = 200 } = {}) {
  const calls = [];
  return { calls, request: async (url, init) => {
    calls.push({ url, ...init });
    return init.method === 'GET' ? response(200, { object: { sha } }) : response(status, { workflow_run_id: 101 });
  } };
}

function scratch(t) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'foundry-continuation-test-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

test('checkpoint replacement preserves the previous snapshot and unrelated budget evidence', t => {
  const directory = scratch(t);
  const file = path.join(directory, 'bootstrap-continuation.json');
  const first = prepareCheckpoint(directory, { ...identity, inputs });
  // A hard link observes the original inode. In-place truncation would change it.
  const snapshot = path.join(directory, 'previous.json');
  fs.linkSync(file, snapshot);
  const ledger = path.join(directory, 'call-budget.usage.json');
  fs.writeFileSync(ledger, 'existing spending evidence');
  const second = prepareCheckpoint(directory, { ...identity, id: '101', inputs: { ...inputs, resume_run_id: '100' } });
  assert.deepEqual(JSON.parse(fs.readFileSync(snapshot, 'utf8')), first);
  assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')), second);
  assert.equal(second.leg, 2);
  assert.equal(fs.readFileSync(ledger, 'utf8'), 'existing spending evidence');
  assert.equal(fs.readdirSync(directory).some(name => name.startsWith('.continuation-')), false);
});

test('malformed or incompatible checkpoints are retained instead of resetting the chain', t => {
  const directory = scratch(t);
  const file = path.join(directory, 'bootstrap-continuation.json');
  for (const content of ['invalid checkpoint', 'null', 'false', '0', '[]', JSON.stringify({ ...fresh(), sha: 'b'.repeat(40) })]) {
    fs.writeFileSync(file, content);
    assert.throws(() => prepareCheckpoint(directory, { ...identity, id: '101', inputs: { ...inputs, resume_run_id: '100' } }));
    assert.equal(fs.readFileSync(file, 'utf8'), content);
  }
});

test('malformed network responses never reach the summary or CLI error output', async t => {
  const directory = scratch(t);
  fs.writeFileSync(path.join(directory, 'bootstrap-continuation.json'), JSON.stringify(fresh()));
  const summaryFile = path.join(directory, 'summary.md');
  const hostile = '<script>network-secret-do-not-copy</script>';
  let requests = 0;
  const server = http.createServer((request, response) => {
    requests++;
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(hostile);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const script = fileURLToPath(new URL('../../scripts/github/bootstrap-continuation.mjs', import.meta.url));
  const child = spawn(process.execPath, [script, 'continue', directory], { env: {
    ...process.env, GITHUB_REPOSITORY: identity.repository, GITHUB_REF_NAME: identity.branch,
    GITHUB_SHA: identity.sha, GITHUB_RUN_ID: identity.id, GITHUB_RUN_ATTEMPT: '1',
    BOOTSTRAP_STATUS: 'paused', GH_TOKEN: 'test-secret', GITHUB_STEP_SUMMARY: summaryFile,
    GITHUB_API_URL: `http://127.0.0.1:${server.address().port}`, GITHUB_SERVER_URL: 'https://github.com',
  } });
  let output = '';
  child.stdout.on('data', chunk => { output += chunk; });
  child.stderr.on('data', chunk => { output += chunk; });
  const code = await new Promise((resolve, reject) => { child.on('error', reject); child.on('close', resolve); });
  assert.equal(code, 1);
  assert.equal(requests, 1, 'must not dispatch after a malformed branch response');
  const summary = fs.readFileSync(summaryFile, 'utf8');
  assert.match(summary, /continuation needs attention/);
  assert.match(summary, /resume_run_id=100/);
  assert.match(output, /Could not parse the branch verification response/);
  assert.equal((output + summary).includes(hostile), false);
  assert.doesNotMatch(output + summary, /network-secret|test-secret/);
});

test('continuations retain chain identity and spending allowance without resetting the counter', () => {
  const first = fresh();
  const second = prepareContinuation({ ...identity, id: '101', previous: first, inputs: { ...inputs, resume_run_id: '100' } });
  const third = prepareContinuation({ ...identity, id: '102', previous: second, inputs: { ...inputs, resume_run_id: '101' } });
  assert.equal(first.leg, 1);
  assert.equal(third.leg, 3);
  assert.equal(third.rootRunId, '100');
  assert.equal(third.parentRunId, '101');
  assert.equal(third.budget_usd, '12.50');
});

test('manual resume from a legacy checkpoint starts a bounded chain', () => {
  const state = prepareContinuation({ ...identity, inputs: { ...inputs, resume_run_id: '99' } });
  assert.equal(state.leg, 1);
  assert.equal(state.rootRunId, '99');
});

test('explicit recovery updates runtime identity but pins the original product and retains the ledger chain', () => {
  const previous = fresh();
  delete previous.sourceSha; // Artifact from before recovery support.
  const state = prepareContinuation({ ...identity, sha: 'b'.repeat(40), id: '101', previous,
    inputs: { ...inputs, resume_run_id: '100', restart_stage: 'implementation' } });
  assert.equal(state.sha, 'b'.repeat(40));
  assert.equal(state.sourceSha, identity.sha);
  assert.equal(state.previousRuntimeSha, identity.sha);
  assert.equal(state.leg, 2);
  assert.equal(state.rootRunId, '100');
  assert.equal(state.budget_usd, previous.budget_usd);
  const next = prepareContinuation({ ...identity, sha: state.sha, id: '102', previous: state,
    inputs: { ...inputs, resume_run_id: '101' } });
  assert.equal(next.sourceSha, identity.sha);
  assert.equal(next.restartStage, undefined, 'ordinary continuation must not reset stages again');
  assert.throws(() => prepareContinuation({ ...identity, previous, inputs: { ...inputs, restart_stage: 'implementation' } }), /requires/);
  assert.throws(() => prepareContinuation({ ...identity, inputs: { ...inputs, resume_run_id: '100', restart_stage: 'implementation' } }), /requires/);
  assert.throws(() => prepareContinuation({ ...identity, previous, inputs: { ...inputs, resume_run_id: '100', restart_stage: 'delivery-preparation' } }), /restart_stage/);
  for (const change of [{ model: 'other' }, { publish: 'false' }, { budget_usd: '20' }]) {
    assert.throws(() => prepareContinuation({ ...identity, previous, inputs: {
      ...inputs, resume_run_id: '100', restart_stage: 'implementation', ...change } }), /changed/);
  }
});

test('recovery checks stopped state and source identity before replacing checkpoint', t => {
  const directory = scratch(t);
  const file = path.join(directory, 'bootstrap-continuation.json');
  prepareCheckpoint(directory, { ...identity, inputs });
  const original = fs.readFileSync(file, 'utf8');
  const recovery = { ...identity, sha: 'b'.repeat(40), id: '101', inputs: {
    ...inputs, resume_run_id: '100', restart_stage: 'implementation' } };
  assert.throws(() => prepareCheckpoint(directory, recovery), /exactly one/);
  const root = path.join(directory, 'run-saved');
  fs.mkdirSync(root);
  fs.writeFileSync(path.join(root, 'run-inputs.json'), JSON.stringify({ sourceCommit: identity.sha }));
  fs.writeFileSync(path.join(root, 'workflow-state.json'), JSON.stringify({ status: 'completed' }));
  assert.throws(() => prepareCheckpoint(directory, recovery), /stopped analysis/);
  fs.writeFileSync(path.join(root, 'workflow-state.json'), JSON.stringify({ status: 'blocked' }));
  fs.writeFileSync(path.join(root, 'run-inputs.json'), JSON.stringify({ sourceCommit: 'c'.repeat(40) }));
  assert.throws(() => prepareCheckpoint(directory, recovery), /saved source/);
  assert.equal(fs.readFileSync(file, 'utf8'), original);
  fs.writeFileSync(path.join(root, 'run-inputs.json'), JSON.stringify({ sourceCommit: identity.sha }));
  assert.equal(prepareCheckpoint(directory, recovery).sourceSha, identity.sha);
});

test('automatic continuation after recovery never dispatches another stage reset', async () => {
  const state = { ...fresh(), sourceSha: 'b'.repeat(40), restartStage: 'implementation' };
  const mock = api();
  await continueBootstrap({ ...options(state), request: mock.request });
  assert.equal(JSON.parse(mock.calls[1].body).inputs.restart_stage, undefined);
  const next = prepareContinuation({ ...identity, id: '101', previous: state,
    inputs: JSON.parse(mock.calls[1].body).inputs });
  assert.equal(next.sourceSha, state.sourceSha);
});

test('materialization recovery changes runtime only and requires completed generation', t => {
  const directory = scratch(t);
  const previous = prepareCheckpoint(directory, { ...identity, inputs });
  const root = path.join(directory, 'run-saved');
  fs.mkdirSync(root);
  fs.writeFileSync(path.join(root, 'run-inputs.json'), JSON.stringify({ sourceCommit: identity.sha }));
  const recovery = { ...identity, sha: 'b'.repeat(40), id: '101', inputs: {
    ...inputs, resume_run_id: '100', restart_stage: 'bootstrap-change-materialization' } };
  for (const stages of [[], [{ id: 'bootstrap-change-generation', status: 'failed' }]]) {
    fs.writeFileSync(path.join(root, 'workflow-state.json'), JSON.stringify({ status: 'blocked', stages }));
    assert.throws(() => prepareCheckpoint(directory, recovery), /requires completed change generation/);
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(directory, 'bootstrap-continuation.json'))), previous);
  }
  const savedState = JSON.stringify({ status: 'blocked', stages: [{ id: 'bootstrap-change-generation', status: 'completed' }] });
  fs.writeFileSync(path.join(root, 'workflow-state.json'), savedState);
  const recovered = prepareCheckpoint(directory, recovery);
  assert.equal(recovered.restartStage, 'bootstrap-change-materialization');
  assert.equal(recovered.sourceSha, identity.sha);
  assert.equal(recovered.sha, recovery.sha);
  assert.equal(fs.readFileSync(path.join(root, 'workflow-state.json'), 'utf8'), savedState);
  const next = prepareContinuation({ ...identity, sha: recovered.sha, id: '102', previous: recovered,
    inputs: { ...inputs, resume_run_id: '101' } });
  assert.equal(next.sourceSha, identity.sha);
  assert.equal(next.restartStage, undefined);
});

test('delivery recovery changes runtime without resetting completed analysis or approvals', t => {
  const directory = scratch(t);
  const previous = prepareCheckpoint(directory, { ...identity, inputs });
  const root = path.join(directory, 'run-saved');
  fs.mkdirSync(root);
  fs.writeFileSync(path.join(root, 'run-inputs.json'), JSON.stringify({ sourceCommit: identity.sha }));
  const recovery = { ...identity, sha: 'b'.repeat(40), id: '101', inputs: {
    ...inputs, resume_run_id: '100', restart_stage: 'delivery' } };
  for (const state of [
    { status: 'blocked', stages: [] }, { status: 'completed', stages: [] },
    { status: 'completed', stages: [{ id: 'bootstrap-change-review', status: 'revision_required' }] },
    { status: 'completed', stages: [{ id: 'bootstrap-change-review', status: 'approved' }, { id: 'generation', status: 'pending' }] },
  ]) {
    fs.writeFileSync(path.join(root, 'workflow-state.json'), JSON.stringify(state));
    assert.throws(() => prepareCheckpoint(directory, recovery), /recovery requires/);
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(directory, 'bootstrap-continuation.json'))), previous);
  }
  const saved = JSON.stringify({ status: 'completed', stages: [
    { id: 'bootstrap-change-materialization', status: 'completed' },
    { id: 'bootstrap-change-review', status: 'approved' },
  ] });
  fs.writeFileSync(path.join(root, 'workflow-state.json'), saved);
  const recovered = prepareCheckpoint(directory, recovery);
  assert.equal(recovered.sourceSha, identity.sha);
  assert.equal(recovered.sha, recovery.sha);
  assert.equal(recovered.restartStage, 'delivery');
  assert.equal(fs.readFileSync(path.join(root, 'workflow-state.json'), 'utf8'), saved);
});

test('rejects mismatched parent, commit, branch and settings before any model work', () => {
  const previous = fresh();
  const valid = { ...identity, id: '101', previous, inputs: { ...inputs, resume_run_id: '100' } };
  for (const change of [{ sha: 'b'.repeat(40) }, { branch: 'other' }, { repository: 'other/product' }]) {
    assert.throws(() => prepareContinuation({ ...valid, ...change }), /changed/);
  }
  for (const change of [{ model: 'different' }, { publish: 'false' }, { budget_usd: '' }]) {
    assert.throws(() => prepareContinuation({ ...valid, inputs: { ...valid.inputs, ...change } }), /changed/);
  }
  assert.throws(() => prepareContinuation({ ...valid, inputs: { ...valid.inputs, resume_run_id: '999' } }), /does not match/);
});

test('rejects invalid limits, booleans and budgets', () => {
  for (const max_continuations of [-1, 11, 1.5, 'oops']) {
    assert.throws(() => prepareContinuation({ ...identity, inputs: { ...inputs, max_continuations } }), /max_continuations/);
  }
  assert.throws(() => prepareContinuation({ ...identity, inputs: { ...inputs, publish: 'yes' } }), /boolean/);
  assert.throws(() => prepareContinuation({ ...identity, inputs: { ...inputs, budget_usd: '-1' } }), /budget_usd/);
});

test('only paused runs dispatch; failure, blocking and final delivery never do', async () => {
  for (const status of ['failed', 'blocked', 'pull_request_created', 'plan_applied', 'dry_run']) {
    const mock = api();
    assert.equal((await continueBootstrap({ ...options(), status, request: mock.request })).outcome, 'not_paused');
    assert.equal(mock.calls.length, 0);
  }
});

test('opt-out, reached limit and reruns require manual action without network writes', async () => {
  for (const change of [
    { state: { ...fresh(), autoResume: false } },
    { state: { ...fresh(), leg: 4 } },
    { state: { ...fresh(), maxContinuations: 0 } },
    { attempt: '2' },
  ]) {
    const mock = api();
    const result = await continueBootstrap({ ...options(), ...change, request: mock.request });
    assert.equal(result.outcome, 'manual_required');
    assert.match(result.message, /NOT finished/);
    assert.match(result.message, /resume_run_id=100/);
    assert.equal(mock.calls.length, 0);
  }
});

test('last allowed continuation keeps original inputs and points to the most recent evidence', async () => {
  const mock = api();
  const result = await continueBootstrap({ ...options({ ...fresh(), leg: 3 }), request: mock.request });
  assert.equal(result.outcome, 'queued');
  assert.equal(result.nextRunId, '101');
  assert.equal(result.url, 'https://github.com/example/product/actions/runs/101');
  assert.equal(mock.calls.length, 2);
  assert.deepEqual(JSON.parse(mock.calls[1].body), { ref: 'main', inputs: { ...inputs, resume_run_id: '100' } });
  assert.match(mock.calls[1].url, /actions\/workflows\/foundry-bootstrap.yml\/dispatches$/);
  assert.match(result.message, /3 of 3/);
});

test('supports dispatch responses without a run URL without claiming the successor completed', async () => {
  const mock = api({ status: 204 });
  const result = await continueBootstrap({ ...options(), request: mock.request });
  assert.equal(result.outcome, 'queued');
  assert.match(result.url, /actions\/workflows\/foundry-bootstrap.yml$/);
  assert.match(result.message, /NOT finished/);
});

test('moving branch never silently starts a new analysis on changed code', async () => {
  const mock = api({ sha: 'b'.repeat(40) });
  const result = await continueBootstrap({ ...options(), request: mock.request });
  assert.equal(result.outcome, 'manual_required');
  assert.match(result.message, /branch has moved/);
  assert.equal(mock.calls.length, 1);
});

test('authentication and network failures do not leak credentials or retry the POST', async () => {
  for (const failure of [response(403), new Error('test-secret in transport diagnostics')]) {
    let posts = 0;
    const request = async (url, init) => {
      if (init.method === 'GET') return response(200, { object: { sha: identity.sha } });
      posts++;
      if (failure instanceof Error) throw failure;
      return failure;
    };
    await assert.rejects(continueBootstrap({ ...options(), request }), error => {
      assert.doesNotMatch(error.message, /test-secret/);
      assert.match(error.message, /not retried/);
      return true;
    });
    assert.equal(posts, 1);
  }
});

test('invalid checkpoint identity is rejected without a dispatch', async () => {
  const mock = api();
  await assert.rejects(continueBootstrap({ ...options({ ...fresh(), runId: '99' }), request: mock.request }), /Invalid continuation evidence/);
  assert.equal(mock.calls.length, 0);
});

test('workflow dispatch is isolated from generation and waits for uploaded evidence', () => {
  // The installed copy also ships reference workflows under foundry/.github;
  // test the root workflow GitHub actually executes.
  const doc = YAML.parse(fs.readFileSync(new URL('../../../.github/workflows/foundry-bootstrap.yml', import.meta.url), 'utf8'));
  assert.equal(doc.permissions.actions, 'read');
  assert.equal(doc.jobs.continue_bootstrap.permissions.actions, 'write');
  assert.equal(doc.jobs.continue_bootstrap.needs, 'bootstrap');
  assert.match(doc.jobs.continue_bootstrap.if, /result == 'success'.*status == 'paused'/);
  const steps = doc.jobs.bootstrap.steps;
  assert.ok(steps.findIndex(s => s.name?.startsWith('Validate continuation')) < steps.findIndex(s => s.id === 'generate'));
  for (const name of ['foundry-evidence', 'foundry-output']) {
    assert.ok(steps.some(s => s.uses?.startsWith('actions/upload-artifact@') && s.with.name === name));
  }
  assert.equal(doc.on.workflow_dispatch.inputs.auto_resume.default, true);
  assert.equal(doc.on.workflow_dispatch.inputs.max_continuations.default, 3);
  assert.ok(doc.on.workflow_dispatch.inputs.restart_stage.options.includes('bootstrap-change-materialization'));
});
