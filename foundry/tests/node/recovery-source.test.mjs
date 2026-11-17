import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sourceHash, verifyRecoverySource } from '../../scripts/helpers/recovery-source.mjs';
test('only the exact complete locally checked source satisfies recovery evidence',()=>{
 const base={changes:[{path:'a.cs',operation:'create',content:'original'},{path:'b.cs',operation:'create',content:'retained'}]};
 const changed={path:'a.cs',operation:'create',content:'corrected'};
 const candidate={changes:[changed],verification:{sourceSha256:sourceHash([changed,base.changes[1]]),projects:[{outcome:'verified',testsDiscovered:2,testsFailed:0,negativeProbe:{failedAsExpected:true}}]}};
 assert.equal(verifyRecoverySource(base,candidate),true);
 assert.throws(()=>verifyRecoverySource(base,{...candidate,changes:[{...changed,content:'unverified edit'}]}),/differs/);
 assert.throws(()=>verifyRecoverySource({changes:base.changes.slice(0,1)},candidate),/differs/);
 assert.throws(()=>verifyRecoverySource(base,{...candidate,verification:{...candidate.verification,projects:[]}}),/no complete/);
});
