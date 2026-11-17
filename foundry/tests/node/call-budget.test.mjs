import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { reserve, settle, transact } from '../../scripts/helpers/call-budget.mjs';
const request = {limitUsd:5,credits:250,model:'gemini-3.7-flash',owner:'job-1',metadataPath:'receipt.json',now:'2026-09-24T00:00:00Z'};
const receipt = {provider:'copilot-cli',model:request.model,startedAt:request.now,usage:{source:'provider',inputTokens:1000000,cachedInputTokens:0,outputTokens:0,totalTokens:1000000}};
test('concurrent callers reserve one shared allowance',async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'foundry-budget-'));
 try {
  const results=await Promise.allSettled(Array.from({length:5},()=>transact(dir,s=>reserve(s,request))));
  assert.equal(results.filter(r=>r.status==='fulfilled').length,2);
  const ledger=JSON.parse(fs.readFileSync(path.join(dir,'call-budget.usage.json')));
  assert.equal(ledger.calls.length,2);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
test('settlement replaces reservation with measured cost and preserves remainder',()=>{
 const first=reserve(null,request); const settled=settle(first.ledger,first.result.id,receipt);
 assert.equal(settled.result.highUsd,.75);assert.equal(settled.result.status,'reported');
 assert.equal(reserve(settled.ledger,request).result.remainingUsd,1.75);
});
test('model response overshoot is charged and blocks subsequent work',()=>{
 const first=reserve(null,request);
 settle(first.ledger,first.result.id,{...receipt,usage:{...receipt.usage,inputTokens:10000000,totalTokens:10000000}});
 assert.throws(()=>reserve(first.ledger,request),/exhausted/);
});
test('interrupted prior job remains charged and blocks resumption',()=>{
 const first=reserve(null,request);
 assert.throws(()=>reserve(first.ledger,{...request,owner:'job-2'}),/unresolved usage/);
});
test('missing, stale, estimated or wrong-model receipts are unknown, never free',()=>{
 for(const record of [null,{...receipt,startedAt:'2026-09-23T00:00:00Z'},{...receipt,usage:{source:'estimate'}},{...receipt,model:'claude-opus-5'}]){
  const first=reserve(null,request);assert.equal(settle(first.ledger,first.result.id,record).result.status,'unknown');
  assert.throws(()=>reserve(first.ledger,request),/unresolved usage/);
 }
});
test('resuming does not silently enlarge budget; lowering it is permitted',()=>{
 const first=reserve(null,request);settle(first.ledger,first.result.id,receipt);
 assert.throws(()=>reserve(first.ledger,{...request,limitUsd:10}),/Increasing/);
 assert.equal(reserve(first.ledger,{...request,limitUsd:4}).ledger.limitUsd,4);
});
test('unknown models and invalid limits fail closed',()=>{
 for(const overrides of [{limitUsd:0},{limitUsd:NaN},{credits:29},{credits:250.5},{model:'unknown'}])assert.throws(()=>reserve(null,{...request,...overrides}));
});
test('duplicate settlement cannot refund an invocation twice',()=>{
 const first=reserve(null,request);settle(first.ledger,first.result.id,receipt);
 assert.throws(()=>settle(first.ledger,first.result.id,receipt),/already settled/);
});
test('corrupt ledger is not reset',async()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'foundry-budget-'));
 try {
  fs.writeFileSync(path.join(dir,'call-budget.usage.json'),'{broken');
  await assert.rejects(transact(dir,s=>reserve(s,request)));
  assert.equal(fs.readFileSync(path.join(dir,'call-budget.usage.json'),'utf8'),'{broken');
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
});
