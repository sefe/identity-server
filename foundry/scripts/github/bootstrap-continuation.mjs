import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const workflow = 'foundry-bootstrap.yml';
const stateFile = 'bootstrap-continuation.json';
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const bool = value => {
  if (value === true || value === 'true') return true;
  if (value === false || value === 'false') return false;
  throw new Error('Expected a boolean workflow input.');
};
const runId = value => {
  const id = String(value ?? '');
  if (!/^[1-9][0-9]*$/.test(id)) throw new Error('Expected a numeric Actions run ID.');
  return id;
};

export function prepareContinuation({ previous, inputs, repository, branch, sha, id }) {
  id = runId(id);
  if (!/^[a-f0-9]{40}$/.test(sha) || !repository || !branch) throw new Error('Missing checkout identity.');
  const max = Number(inputs.max_continuations ?? 3);
  if (!Number.isInteger(max) || max < 0 || max > 10) throw new Error('max_continuations must be an integer from 0 to 10.');
  const settings = {
    model: String(inputs.model), publish: bool(inputs.publish),
    budget_usd: String(inputs.budget_usd ?? '').trim(),
  };
  if (!settings.model || settings.model === 'undefined') throw new Error('Missing model.');
  if (settings.budget_usd && (!Number.isFinite(Number(settings.budget_usd)) || Number(settings.budget_usd) <= 0)) {
    throw new Error('budget_usd must be empty or a finite positive number.');
  }
  const parent = inputs.resume_run_id ? runId(inputs.resume_run_id) : '';
  const restartStage = String(inputs.restart_stage ?? '').trim();
  if (restartStage && !['implementation', 'bootstrap-change-materialization', 'delivery'].includes(restartStage)) {
    throw new Error('restart_stage must be empty, implementation, bootstrap-change-materialization or delivery.');
  }
  if (restartStage && (!parent || previous === undefined)) throw new Error('Stage recovery requires resume_run_id and a saved continuation checkpoint.');
  let sourceSha = sha;
  if (previous !== undefined) {
    if (!previous || typeof previous !== 'object' || Array.isArray(previous)) throw new Error('Invalid saved continuation checkpoint.');
    if (previous.version !== 1 || previous.runId !== parent || !Number.isInteger(previous.leg) || previous.leg < 1) {
      throw new Error('Saved continuation state does not match resume_run_id.');
    }
    for (const [key, value] of Object.entries({ repository, branch, ...settings })) {
      if (previous[key] !== value) throw new Error(`Cannot resume: ${key} changed. Use the original commit and inputs.`);
    }
    if (previous.sha !== sha && !restartStage) throw new Error('Cannot resume: sha changed. Use the original runtime commit or explicitly select a recovery stage.');
    sourceSha = previous.sourceSha ?? previous.sha;
    if (!/^[a-f0-9]{40}$/.test(sourceSha) || !/^[a-f0-9]{40}$/.test(previous.sha)) throw new Error('Invalid saved source/runtime commit.');
    runId(previous.rootRunId);
  }
  // A legacy manual resume starts a bounded chain here; Foundry still verifies
  // its saved source/configuration fingerprints before doing any model work.
  return {
    version: 1, repository, branch, sha, sourceSha, ...settings,
    ...(restartStage ? { restartStage, previousRuntimeSha: previous.sha } : {}),
    rootRunId: previous?.rootRunId ?? (parent || id), runId: id,
    parentRunId: parent, leg: previous ? previous.leg + 1 : 1,
    maxContinuations: max, autoResume: bool(inputs.auto_resume ?? true),
  };
}

export function prepareCheckpoint(directory, options) {
  fs.mkdirSync(directory, { recursive: true });
  const file = path.join(directory, stateFile);
  let previous;
  try { previous = readJson(file); }
  catch (error) {
    // Only a missing checkpoint means a fresh/legacy run. Never overwrite a
    // malformed or unreadable checkpoint as if it had not existed.
    if (error.code !== 'ENOENT') throw error;
  }
  const state = prepareContinuation({ ...options, previous });
  if (state.restartStage) {
    const roots = fs.readdirSync(directory, { withFileTypes: true })
      .filter(entry => entry.isDirectory() && entry.name.startsWith('run-') &&
        fs.existsSync(path.join(directory, entry.name, 'workflow-state.json')));
    if (roots.length !== 1) throw new Error('Stage recovery requires exactly one saved analysis root.');
    const root = path.join(directory, roots[0].name);
    const saved = readJson(path.join(root, 'workflow-state.json'));
    const manifest = readJson(path.join(root, 'run-inputs.json'));
    const delivery = state.restartStage === 'delivery';
    if (!(delivery ? saved.status === 'completed' : ['blocked', 'failed', 'paused'].includes(saved.status)) || manifest.sourceCommit !== state.sourceSha) {
      throw new Error('Stage recovery requires a stopped analysis on the saved source commit.');
    }
    if (delivery && (!Array.isArray(saved.stages) || !saved.stages.length ||
        saved.stages.some(stage => !['completed', 'approved'].includes(stage.status)) ||
        saved.stages.filter(stage => stage.id === 'bootstrap-change-review' && stage.status === 'approved').length !== 1)) {
      throw new Error('Delivery recovery requires completed stages and unanimous final review approval.');
    }
    if (state.restartStage === 'bootstrap-change-materialization') {
      const generation = saved.stages?.filter(stage => stage.id === 'bootstrap-change-generation');
      if (generation?.length !== 1 || generation[0].status !== 'completed') {
        throw new Error('Materialization recovery requires completed change generation; recover the earlier failure first.');
      }
    }
  }
  // Write a complete replacement in a private directory on the same filesystem.
  // Rename publishes it atomically and does not follow a destination symlink.
  const temporaryDirectory = fs.mkdtempSync(path.join(directory, '.continuation-'));
  const temporaryFile = path.join(temporaryDirectory, 'state.json');
  try {
    fs.writeFileSync(temporaryFile, JSON.stringify(state, null, 2), { flag: 'wx', mode: 0o600 });
    fs.renameSync(temporaryFile, file);
  } finally {
    try { fs.unlinkSync(temporaryFile); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    fs.rmdirSync(temporaryDirectory);
  }
  return state;
}

export async function continueBootstrap({ state, status, repository, branch, sha, id, attempt,
  token, apiUrl = 'https://api.github.com', serverUrl = 'https://github.com', request = fetch }) {
  if (status !== 'paused') return { outcome: 'not_paused', message: `No continuation for ${status}.` };
  if (!state || state.version !== 1 || state.runId !== runId(id) || state.repository !== repository ||
      state.branch !== branch || state.sha !== sha || !Number.isInteger(state.leg) || state.leg < 1 ||
      !/^[a-f0-9]{40}$/.test(state.sourceSha ?? state.sha) ||
      !Number.isInteger(state.maxContinuations) || state.maxContinuations < 0 || state.maxContinuations > 10) {
    throw new Error('Invalid continuation evidence for this run. No workflow was dispatched.');
  }
  const manual = reason => ({ outcome: 'manual_required', message: reason +
    ` Bootstrap is NOT finished; no PR was created by this paused run. Resume with resume_run_id=${id}, on the original runtime commit and with the same model, publish setting and budget. Leave restart_stage empty; the saved source commit is restored automatically.` });
  if (!bool(state.autoResume)) return manual('Automatic continuation is disabled.');
  if (state.leg > state.maxContinuations) return manual(`Automatic continuation limit (${state.maxContinuations}) reached.`);
  // A rerun can replay the last step after GitHub accepted the first POST. Do
  // not create a second successor. A manual new dispatch is an explicit choice.
  if (String(attempt) !== '1') return manual('This is a rerun; automatic dispatch is suppressed to avoid duplicate continuations. Check for an already queued successor.');
  if (!token) throw new Error('Missing workflow token. No continuation was dispatched.');
  const headers = { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2026-03-10', 'Content-Type': 'application/json' };
  const api = apiUrl.replace(/\/$/, '');
  const repoPath = repository.split('/').map(encodeURIComponent).join('/');
  const invoke = async (url, options) => {
    try { return await request(url, { ...options, headers, redirect: 'error', signal: AbortSignal.timeout(30000) }); }
    catch { throw new Error(options.method === 'POST'
      ? 'Continuation dispatch outcome is unknown. Check Actions for a queued successor before manually retrying; POST was not retried.'
      : 'Could not verify the branch before continuation. No workflow was dispatched.'); }
  };
  const ref = await invoke(`${api}/repos/${repoPath}/git/ref/heads/${branch.split('/').map(encodeURIComponent).join('/')}`, { method: 'GET' });
  if (ref.status !== 200) throw new Error(`Could not verify continuation branch (HTTP ${ref.status}). No workflow was dispatched.`);
  let refData;
  try { refData = await ref.json(); }
  catch { throw new Error('Could not parse the branch verification response. No workflow was dispatched.'); }
  if (refData?.object?.sha !== sha) return manual('The branch has moved since this run; automatic continuation is stopped.');
  const response = await invoke(`${api}/repos/${repoPath}/actions/workflows/${workflow}/dispatches`, {
    method: 'POST', body: JSON.stringify({ ref: branch, inputs: {
      model: state.model, publish: String(state.publish), budget_usd: state.budget_usd,
      resume_run_id: String(id), auto_resume: 'true', max_continuations: String(state.maxContinuations),
    } }),
  });
  if (![200, 204].includes(response.status)) {
    throw new Error(`Continuation dispatch returned HTTP ${response.status}. Check Actions before retrying; POST was not retried.`);
  }
  let nextId;
  if (response.status === 200) {
    try { nextId = runId((await response.json()).workflow_run_id); } catch { /* Accepted, but response details unavailable. */ }
  }
  const url = nextId ? `${serverUrl}/${repository}/actions/runs/${nextId}` : `${serverUrl}/${repository}/actions/workflows/${workflow}`;
  return { outcome: 'queued', nextRunId: nextId, url,
    message: `Bootstrap is NOT finished; no PR was created by this paused run. Continuation ${state.leg} of ${state.maxContinuations} was accepted by GitHub. The successor will restore this run's evidence and existing spending ledger.` };
}

async function main() {
  const [mode, directory] = process.argv.slice(2);
  if (!['prepare', 'continue'].includes(mode) || !directory) throw new Error('Usage: bootstrap-continuation.mjs prepare|continue <evidence-directory>');
  const env = process.env;
  const identity = { repository: env.GITHUB_REPOSITORY, branch: env.GITHUB_REF_NAME, sha: env.GITHUB_SHA, id: env.GITHUB_RUN_ID };
  const file = path.join(directory, stateFile);
  if (mode === 'prepare') {
    const event = readJson(env.GITHUB_EVENT_PATH);
    if (env.GITHUB_EVENT_NAME !== 'workflow_dispatch' || env.GITHUB_REF_TYPE !== 'branch') throw new Error('Bootstrap requires a branch workflow_dispatch.');
    const state = prepareCheckpoint(directory, { ...identity, inputs: event.inputs ?? {} });
    if (env.GITHUB_OUTPUT) fs.appendFileSync(env.GITHUB_OUTPUT, `source_sha=${state.sourceSha}\n`);
    console.log(`Bootstrap segment ${state.leg}; at most ${state.maxContinuations} automatic continuations. Spending allowance is shared across resumed segments.`);
    return;
  }
  try {
    const result = await continueBootstrap({ ...identity, state: readJson(file), status: env.BOOTSTRAP_STATUS,
      attempt: env.GITHUB_RUN_ATTEMPT, token: env.GH_TOKEN, apiUrl: env.GITHUB_API_URL, serverUrl: env.GITHUB_SERVER_URL });
    const heading = result.outcome === 'queued' ? 'PAUSED — continuation queued' : 'PAUSED — manual continuation required';
    const summary = `## Foundry bootstrap: ${heading}\n\n${result.message}\n\n` +
      (result.url ? `[Open continuation](${result.url})\n` : 'Saved work is available in **foundry-evidence** for this run.\n');
    if (env.GITHUB_STEP_SUMMARY) fs.appendFileSync(env.GITHUB_STEP_SUMMARY, summary);
    console.log(`${heading}: ${result.message}`);
    if (result.outcome === 'manual_required') console.log('::warning::Bootstrap is paused and needs manual continuation; see the job summary.');
  } catch (error) {
    if (env.GITHUB_STEP_SUMMARY) fs.appendFileSync(env.GITHUB_STEP_SUMMARY,
      `## Foundry bootstrap: PAUSED — continuation needs attention\n\nBootstrap is not complete and no PR was created by this paused run.\n\nContinuation failed. Check the job log and Actions for an already queued successor before retrying.\n\nSaved evidence: resume_run_id=${runId(env.GITHUB_RUN_ID)}.\n`);
    throw error;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
