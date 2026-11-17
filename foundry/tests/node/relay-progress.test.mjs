import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { snapshot, updateProgress } from '../../scripts/helpers/relay-progress.mjs';

function fixture(t) {
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'relay-progress-'));
  t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
  const runRoot=path.join(root,'run-test');fs.mkdirSync(runRoot);
  const write=(name,x)=>{const p=path.join(runRoot,name);fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,JSON.stringify(x));};
  write('workflow-state.json',{runId:'run-test',currentStage:'generation',stages:[{id:'discovery',status:'completed'},{id:'generation',status:'running'}]});
  const update=options=>updateProgress({root,runRoot,budgetMinutes:60,legBudgetMinutes:10,maxNoProgressLegs:2,buildId:'100',...options});
  return {root,runRoot,write,update};
}
test('after verification starts, new JSON alone does not reset stagnation',t=>{
 const f=fixture(t);
 f.write('framework-verification/framework-verification.json',{runId:'run-test',projects:[{projectPath:'automation/api',outcome:'toolchain_defect',steps:[{name:'build',status:'failed'}]}]});
 f.update({action:'begin',now:0});
 f.write('generation/result.json',{revision:1});
 f.write('generation/result.json.coverage.json',{runId:'run-test',status:'covered',deferrals:[]});
 assert.equal(f.update({action:'finish',now:10000,status:'paused'}).noProgressLegs,1);
 f.update({action:'begin',now:20000});
 f.write('generation/result.json',{revision:2});
 assert.equal(f.update({action:'finish',now:30000,status:'paused'}).reason,'no_progress');
});
test('a newly passing build restores progress after verification failure',t=>{
 const f=fixture(t);
 f.write('framework-verification/framework-verification.json',{runId:'run-test',projects:[]});
 f.update({action:'begin',now:0});f.update({action:'finish',now:10000,status:'paused'});
 f.update({action:'begin',now:20000});
 f.write('framework-verification/iteration-2/framework-verification.json',{runId:'run-test',projects:[{projectPath:'automation/api',outcome:'toolchain_defect',steps:[{name:'build',status:'passed'}]}]});
 assert.equal(f.update({action:'finish',now:30000,status:'paused'}).noProgressLegs,0);
});
test('time and stagnation survive another build; failed calls do not constitute progress',t=>{
  const f=fixture(t);
  assert.equal(f.update({action:'begin',now:0}).allowed,true);
  f.write('generation/a.json.attempt-1.provider-metadata.json',{startedAt:new Date(0).toISOString(),durationMs:600000,purpose:'artifact',attempt:1});
  assert.equal(f.update({action:'finish',now:600000,status:'paused'}).spentSeconds,600);
  assert.equal(f.update({action:'begin',now:90000000,buildId:'101'}).remainingSeconds,3000);
  const stopped=f.update({action:'finish',now:90600000,status:'paused'});
  assert.equal(stopped.reason,'no_progress');assert.equal(stopped.spentSeconds,1200);
  assert.equal(f.update({action:'begin',now:91000000,buildId:'102'}).allowed,false);
});
test('new accepted evidence resets stagnation; replaying identical evidence does not',t=>{
  const f=fixture(t);f.update({action:'begin',now:0});f.update({action:'finish',now:10000,status:'paused'});
  f.update({action:'begin',now:20000});
  f.write('generation/result.json',{value:'accepted'});
  f.write('generation/result.json.coverage.json',{runId:'run-test',status:'covered',deferrals:[]});
  assert.equal(f.update({action:'finish',now:30000,status:'paused'}).noProgressLegs,0);
  f.update({action:'begin',now:40000});
  assert.equal(f.update({action:'finish',now:50000,status:'paused'}).noProgressLegs,1);
});
test('an interrupted leg retains its reservation on continuation',t=>{
  const f=fixture(t);f.update({action:'begin',now:0});
  const resumed=f.update({action:'begin',now:100000000,buildId:'101'});
  assert.equal(resumed.spentSeconds,600);assert.equal(resumed.remainingSeconds,3000);
});
test('time exhaustion stops admission without spending a new leg',t=>{
  const f=fixture(t);f.update({action:'begin',now:0,budgetMinutes:10});
  f.update({action:'finish',now:590000,status:'paused',budgetMinutes:10});
  assert.equal(f.update({action:'begin',now:600000,budgetMinutes:10}).reason,'run_time_budget_exhausted');
});
test('fallback restore charges missing legs and archived artifacts are not progress',t=>{
  const f=fixture(t);f.update({action:'begin',now:0,legIndex:1});f.update({action:'finish',now:60000,status:'paused'});
  const next=f.update({action:'begin',now:120000,legIndex:3,maxNoProgressLegs:4});
  assert.equal(next.spentSeconds,660);
  f.write('recovery/old/accepted.json',{value:'old'});
  f.write('recovery/old/accepted.json.coverage.json',{runId:'run-test',status:'covered'});
  assert.equal(snapshot(f.runRoot).accepted.length,0);
});
test('corrupt ledger and another run identity are refused',t=>{
  const f=fixture(t);f.update({action:'begin',now:0});
  f.write('workflow-state.json',{runId:'run-other',stages:[]});
  assert.throws(()=>f.update({action:'begin'}),/another run/);
  fs.writeFileSync(path.join(f.root,'relay-progress.json'),'{broken');
  assert.throws(()=>f.update({action:'begin'}));
});
test('legacy provider time counts once without parallel overlap or idle build time',t=>{
  const f=fixture(t);
  for(let i=0;i<2;i++)f.write(`a${i}.provider-metadata.json`,{startedAt:new Date(i*60000).toISOString(),durationMs:120000});
  assert.equal(f.update({action:'begin',now:9000000}).spentSeconds,180);
  assert.equal(f.update({action:'finish',now:9060000,status:'paused'}).spentSeconds,240);
});
test('ETA stays unknown until comparable generation results exist',t=>{
  const f=fixture(t);assert.equal(snapshot(f.runRoot).estimate,null);
  for(let i=1;i<=3;i++)f.write(`generation/assignment-batch-0${i}.json`,{});
  for(let i=1;i<=2;i++){
    f.write(`generation/change-set-batch-0${i}.json`,{value:i});
    f.write(`generation/change-set-batch-0${i}.json.coverage.json`,{runId:'run-test',status:'covered'});
    f.write(`generation/change-set-batch-0${i}.json.attempt-1.provider-metadata.json`,{purpose:'artifact',stageId:'generation',durationMs:600000,startedAt:new Date(0).toISOString()});
  }
  const s=snapshot(f.runRoot);assert.equal(s.remainingKnownBatches,1);assert.equal(s.estimate.samples,2);
  assert.match(s.estimate.scope,/excludes/);
});
