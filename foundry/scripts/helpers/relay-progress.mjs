import fs from 'node:fs';
import path from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import { pathToFileURL } from 'node:url';

const read = p => JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
const hash = p => createHash('sha256').update(fs.readFileSync(p)).digest('hex');
function files(root) {
  if (!root || !fs.existsSync(root)) return [];
  return fs.readdirSync(root, { withFileTypes: true }).flatMap(e => {
    if (e.isSymbolicLink()) return [];
    const p = path.join(root, e.name);
    return e.isDirectory() && !['.scratch', 'command-home', 'archive', 'recovery-archive'].includes(e.name)
      ? files(p) : e.isFile() ? [p] : [];
  });
}
function unionSeconds(records) {
  let end = 0, total = 0;
  for (const [start, finish] of records.map(r => [Date.parse(r.startedAt), Date.parse(r.startedAt) + r.durationMs])
    .filter(([a,b]) => Number.isFinite(a) && Number.isFinite(b) && b >= a).sort((a,b) => a[0]-b[0])) {
    total += Math.max(0, finish - Math.max(start, end)); end = Math.max(end, finish);
  }
  return total / 1000;
}
export function snapshot(runRoot) {
  const statePath = runRoot && path.join(runRoot, 'workflow-state.json');
  const state = statePath && fs.existsSync(statePath) ? read(statePath) : {};
  const all = files(runRoot), accepted = [], calls = [], errors = [], technical = new Set();
  let verificationSeen = false;
  let aiSpending = null;
  const budgetPath=runRoot && path.join(runRoot,'call-budget.usage.json');
  if(budgetPath && fs.existsSync(budgetPath)) {
    try {
      const budget=read(budgetPath);
      aiSpending={limitUsd:budget.limitUsd,accountedUsd:budget.calls.reduce((s,c)=>s+(c.status==='reported'?c.highUsd:c.reserveUsd),0),
        unresolved:budget.calls.filter(c=>c.status!=='reported').length,calls:budget.calls.length};
    }catch { errors.push('call-budget.usage.json'); }
  }
  for (const p of all) {
    try {
      if (p.endsWith('.provider-metadata.json')) calls.push({ ...read(p), file: p });
      if (path.basename(p) === 'framework-verification.json') {
        const verification = read(p);
        if ((!state.runId || verification.runId === state.runId) && Array.isArray(verification.projects)) {
          verificationSeen = true;
          for (const project of verification.projects) {
            for (const step of project.steps ?? []) {
              if (step.status === 'passed' && ['build','test'].includes(step.name)) technical.add(`${project.projectPath}:${step.name}`);
            }
            if (project.outcome === 'verified' && project.negativeProbe?.failedAsExpected) technical.add(`${project.projectPath}:negative_probe`);
          }
        }
      }
      if (p.endsWith('.coverage.json') && !path.relative(runRoot,p).split(path.sep).includes('recovery')) {
        const c = read(p), artifact = p.slice(0, -'.coverage.json'.length);
        if (c.status === 'covered' && !c.deferrals?.length && fs.existsSync(artifact) && (!state.runId || c.runId === state.runId)) {
          accepted.push({ path: path.relative(runRoot, artifact).replaceAll('\\','/'), sha256: hash(artifact) });
        }
      }
    } catch { errors.push(path.relative(runRoot, p)); }
  }
  const completed = (state.stages ?? []).filter(s => ['completed','approved','approved_with_dissent','skipped'].includes(s.status)).map(s => s.id);
  const stageCalls = calls.filter(c => c.stageId === state.currentStage);
  const acceptedPaths = new Set(accepted.map(a => a.path));
  const assignments = all.filter(p => /^assignment-batch-\d+\.json$/.test(path.basename(p)) && path.basename(path.dirname(p)) === state.currentStage);
  const done = assignments.filter(p => acceptedPaths.has(path.relative(runRoot,p).replaceAll('\\','/').replace('assignment-batch-','change-set-batch-'))).length;
  const durationByArtifact = new Map();
  for (const c of stageCalls.filter(c=>c.purpose==='artifact')) {
    const artifact=path.relative(runRoot,c.file).replaceAll('\\','/').replace(/\.attempt-\d+\.provider-metadata\.json$/,'');
    if(acceptedPaths.has(artifact)) durationByArtifact.set(artifact,(durationByArtifact.get(artifact)??0)+c.durationMs/60000);
  }
  const durations=[...durationByArtifact.values()];
  const remainingKnownBatches = assignments.length - done;
  const estimate = durations.length >= 2 && remainingKnownBatches > 0 ? {
    scope: 'known generation assignments only; excludes unassigned work, later stages and repairs',
    // Bounds reflect serial dependency layers versus the maximum three-way concurrency.
    minMinutes: Math.ceil(remainingKnownBatches * Math.min(...durations) / 3),
    maxMinutes: Math.ceil(remainingKnownBatches * Math.max(...durations)), samples: durations.length
  } : null;
  return { runId: state.runId ?? (runRoot ? path.basename(runRoot) : null), currentStage: state.currentStage ?? null,
    completedStages: completed, totalStages: (state.stages ?? []).length, accepted, calls: calls.length,
    retries: calls.filter(c => c.purpose === 'artifact' && c.attempt > 1).length,
    fieldRepairs: calls.filter(c => c.purpose === 'field_repair').length,
    providerActiveSeconds: unionSeconds(calls), knownBatches: assignments.length, completedBatches: done,
    remainingKnownBatches, estimate, verificationSeen, technicalUnits: [...technical].sort(), aiSpending, unreadableEvidence: errors };
}
function save(root, ledger) {
  fs.mkdirSync(root, {recursive:true});
  const dest = path.join(root,'relay-progress.json'), temp = dest + '.' + randomUUID() + '.tmp';
  fs.writeFileSync(temp, JSON.stringify(ledger,null,2)); fs.renameSync(temp,dest);
}
function load(root, current) {
  const p = path.join(root,'relay-progress.json');
  if (!fs.existsSync(p)) {
    if (current.unreadableEvidence.length) throw new Error('Cannot account for legacy run with unreadable evidence.');
    return {version:1, runId:current.runId, baselineSeconds:current.providerActiveSeconds,
      baselineBasis:'Legacy imports count observed provider wall time; earlier orchestration overhead is unknown.',
      seen:[...current.completedStages.map(s=>'stage:'+s),...current.accepted.map(a=>a.path+':'+a.sha256)],
      noProgressLegs:0, entries:[]};
  }
  const x=read(p);
  if (x.version!==1 || !Array.isArray(x.entries) || !Array.isArray(x.seen) || !Number.isFinite(x.baselineSeconds) || x.baselineSeconds<0 || !Number.isInteger(x.noProgressLegs) || x.noProgressLegs<0 || x.entries.some(e=>!Number.isFinite(e.seconds)||e.seconds<0||!Number.isFinite(e.startedAt))) throw new Error('Invalid relay budget ledger; refusing to reset accounting.');
  if (x.runId && current.runId && x.runId!==current.runId) throw new Error('Relay budget ledger belongs to another run.');
  return x;
}
export function updateProgress({root, runRoot, action, budgetMinutes=720, legBudgetMinutes=40, maxNoProgressLegs=3,
  legIndex=1, buildId='', status='', now=Date.now(), sourceVersion=''}) {
  if (!(budgetMinutes>0) || !(legBudgetMinutes>0) || !Number.isInteger(maxNoProgressLegs) || maxNoProgressLegs<1) throw new Error('Relay budgets and stagnation limit must be positive.');
  const current=snapshot(runRoot), ledger=load(root,current);
  ledger.seenTechnicalUnits ??= current.technicalUnits;
  ledger.verificationSeen ||= current.verificationSeen;
  ledger.runId ??= current.runId;
  const spent=()=>ledger.baselineSeconds+ledger.entries.reduce((n,e)=>n+e.seconds,0);
  if (action==='begin') {
    // An interrupted invocation retains its full reservation, including when resumed
    // from another build. A killed process must not receive a fresh free allowance.
    for(const e of ledger.entries.filter(e=>e.status==='running')) { e.status='interrupted'; ledger.noProgressLegs++; }
    const previous=ledger.entries.at(-1);
    // Restoring a fallback artifact must not give missing jobs free time.
    if(buildId && previous?.buildId===buildId) {
      for(let missing=previous.legIndex+1;missing<legIndex;missing++) {
        ledger.entries.push({buildId,legIndex:missing,startedAt:now,seconds:legBudgetMinutes*60,status:'missing_evidence'});
        ledger.noProgressLegs++;
      }
    }
    const remaining=budgetMinutes*60-spent();
    const reason=remaining<=120?'run_time_budget_exhausted':ledger.noProgressLegs>=maxNoProgressLegs?'no_progress':null;
    if (!reason) ledger.entries.push({buildId,legIndex,startedAt:now,seconds:Math.min(remaining,legBudgetMinutes*60),status:'running'});
    save(root,ledger);
    return {allowed:!reason,reason,remainingSeconds:Math.max(0,remaining),spentSeconds:spent()-(reason?0:ledger.entries.at(-1).seconds)};
  }
  if(action!=='finish') throw new Error('Unknown relay progress action.');
  const active=ledger.entries.at(-1);
  if(active?.status==='running') {
    active.seconds=Math.max(0,(now-active.startedAt)/1000); active.status=status;
    const units=[...current.completedStages.map(s=>'stage:'+s),...current.accepted.map(a=>a.path+':'+a.sha256)];
    const fresh=units.filter(s=>!ledger.seen.includes(s));
    active.acceptedChanges=fresh.length;
    const technicalFresh=current.technicalUnits.filter(unit=>!ledger.seenTechnicalUnits.includes(unit));
    const meaningful=ledger.verificationSeen ? technicalFresh.length || fresh.some(unit=>unit.startsWith('stage:')) : fresh.length;
    ledger.noProgressLegs=meaningful?0:ledger.noProgressLegs+1;
    active.newTechnicalChecks=technicalFresh;
    ledger.seenTechnicalUnits=[...new Set([...ledger.seenTechnicalUnits,...current.technicalUnits])];
    ledger.seen=[...new Set([...ledger.seen,...units])];
  }
  const reason=spent()>=budgetMinutes*60-120?'run_time_budget_exhausted':ledger.noProgressLegs>=maxNoProgressLegs?'no_progress':null;
  ledger.latest={...current,spentSeconds:spent(),remainingSeconds:Math.max(0,budgetMinutes*60-spent()),reason,sourceVersion};
  save(root,ledger);
  const s=ledger.latest;
  const report=[`# Foundry progress`, '', `Outcome: **${status}**${reason?' — '+reason:''}.`,
    `Stage: ${s.currentStage??'not started'}. Completed stages: ${s.completedStages.length}/${s.totalStages}.`,
    `Accepted artifact versions currently on disk: ${s.accepted.length}. Provider calls: ${s.calls}; retries: ${s.retries}; field repairs: ${s.fieldRepairs}.`,
    ...(ledger.verificationSeen?[`Technical checks achieved: ${s.technicalUnits.length}. After verification begins, rewritten documents alone do not reset stagnation.`]:[]),
    ...(s.aiSpending?[`Additional AI allowance: $${s.aiSpending.accountedUsd.toFixed(2)} accounted/reserved of $${s.aiSpending.limitUsd.toFixed(2)}; ${s.aiSpending.unresolved} unresolved call(s). CLI caps are soft and may overshoot by the final response.`]:[]),
    `Accounted work: ${(s.spentSeconds/60).toFixed(1)} min; remaining run allowance: ${(s.remainingSeconds/60).toFixed(1)} min. Consecutive legs without new accepted results: ${ledger.noProgressLegs}/${maxNoProgressLegs}.`,
    `Known generation assignments completed: ${s.completedBatches}/${s.knownBatches}.`,
    s.estimate?`Estimated remaining work: ${s.estimate.minMinutes}–${s.estimate.maxMinutes} min (${s.estimate.scope}; ${s.estimate.samples} observations).`:'Remaining time: not yet estimable from comparable completed work. Stage counts are not a time percentage.',
    ...(s.unreadableEvidence.length?[`Unreadable diagnostic records: ${s.unreadableEvidence.length}. Progress estimates are incomplete.`]:[]),
    ...(ledger.baselineSeconds?[ledger.baselineBasis]:[]),''];
  fs.writeFileSync(path.join(root,'relay-progress.md'),report.join('\n'));
  return {...s,noProgressLegs:ledger.noProgressLegs};
}
if(process.argv[1] && import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href) {
  try { const options=read(process.argv[2]); console.log(JSON.stringify(updateProgress(options))); }
  catch(error){console.error(error.message);process.exitCode=1;}
}
