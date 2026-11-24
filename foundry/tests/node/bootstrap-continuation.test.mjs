import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import YAML from 'yaml';
import { prepareContinuation, continueBootstrap } from '../../scripts/github/bootstrap-continuation.mjs';

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
});
