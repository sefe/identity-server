import fs from 'node:fs';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { priceInvocation } from './report-economics.mjs';

// This ledger limits additional work from its creation, across resumed builds.
// CLI credit limits are soft: the last model response can exceed its reservation.
const positive = n => Number.isFinite(n) && n > 0;
const read = p => JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
export async function transact(root, operation) {
  const file = path.join(root, 'call-budget.usage.json'), lock = file + '.lock';
  let fd;
  const deadline = Date.now() + 10000;
  while (fd === undefined) {
    try { fd = fs.openSync(lock, 'wx'); }
    catch (e) {
      if (e.code !== 'EEXIST' || Date.now() >= deadline) throw new Error('Budget ledger unavailable; refusing an unaccounted call.');
      await new Promise(resolve => setTimeout(resolve, 25));
    }
  }
  try {
    const state = fs.existsSync(file) ? read(file) : null;
    if (state && (state.version !== 1 || !positive(state.limitUsd) || !Array.isArray(state.calls) ||
      state.calls.some(c => !c.id || !positive(c.reserveUsd) || !['started','reported','unknown'].includes(c.status) ||
        (c.status === 'reported' && (!Number.isFinite(c.highUsd) || c.highUsd < 0))))) throw new Error('Invalid budget ledger; refusing to reset spending.');
    const { ledger, result } = operation(state);
    const temporary = file + '.' + randomUUID() + '.tmp';
    fs.writeFileSync(temporary, JSON.stringify(ledger, null, 2));
    fs.renameSync(temporary, file);
    return result;
  } finally { fs.closeSync(fd); fs.unlinkSync(lock); }
}
export function reserve(state, { limitUsd, credits, model, owner, metadataPath, now = new Date().toISOString() }) {
  if (!positive(limitUsd) || !Number.isInteger(credits) || credits < 30 || !owner || !metadataPath) throw new Error('Invalid AI spending limit.');
  const ledger = state ?? { version: 1, createdAt: now, limitUsd, calls: [] };
  // A new build must not silently raise an existing allowance.
  if (limitUsd > ledger.limitUsd) throw new Error('Increasing a saved AI allowance requires an explicit budget revision.');
  ledger.limitUsd = Math.min(ledger.limitUsd, limitUsd);
  if (ledger.calls.some(c => c.status === 'unknown' || (c.status === 'started' && c.owner !== owner))) {
    throw new Error('An interrupted AI call has unresolved usage; reconcile it before spending again.');
  }
  const reserveUsd = credits / 100;
  const accounted = ledger.calls.reduce((s,c) => s + (c.status === 'reported' ? c.highUsd : c.reserveUsd), 0);
  if (accounted + reserveUsd > ledger.limitUsd + 1e-9) throw new Error(`AI spending allowance exhausted: $${accounted.toFixed(2)} accounted/reserved of $${ledger.limitUsd.toFixed(2)}.`);
  // Unknown/expired tariffs cannot silently become zero-cost calls.
  if (!priceInvocation({provider:'copilot-cli', model, usage:{source:'provider',inputTokens:1,outputTokens:0,totalTokens:1,cachedInputTokens:0}}, now.slice(0,10))) throw new Error('No current price for selected model.');
  const call = { id: randomUUID(), owner, model, metadataPath: path.resolve(metadataPath), startedAt: now, reserveUsd, credits, status:'started' };
  ledger.calls.push(call);
  return { ledger, result: { id: call.id, credits, remainingUsd: ledger.limitUsd-accounted-reserveUsd } };
}
export function settle(ledger, id, record) {
  if (!ledger) throw new Error('Missing budget ledger.');
  const call=ledger.calls.find(c=>c.id===id);
  if (!call || call.status !== 'started') throw new Error('Unknown or already settled budget reservation.');
  const price=record && record.model===call.model && Date.parse(record.startedAt)>=Date.parse(call.startedAt) &&
    record.usage?.source==='provider' && priceInvocation(record, new Date().toISOString().slice(0,10));
  // Payload size estimates cannot bound a multi-turn CLI session.
  call.status = price && price.basis==='reported-breakdown' ? 'reported' : 'unknown';
  if (call.status==='reported') { call.lowUsd=price.low; call.highUsd=price.high; }
  return {ledger,result:{status:call.status,highUsd:call.highUsd,overReservation:call.highUsd>call.reserveUsd}};
}
if (process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const [action,root,...args]=process.argv.slice(2);
    const result=await transact(root, ledger=>{
      if(action==='reserve') return reserve(ledger,{limitUsd:Number(args[0]),credits:Number(args[1]),model:args[2],owner:args[3],metadataPath:args[4]});
      if(action==='settle') {
        const call=ledger?.calls.find(c=>c.id===args[0]);
        let record; try { if(call) record=read(call.metadataPath); } catch { /* retain unknown spending */ }
        return settle(ledger,args[0],record);
      }
      throw new Error('Unknown budget action.');
    });
    console.log(JSON.stringify(result));
  } catch(e) { console.error(e.message); process.exitCode=2; }
}
