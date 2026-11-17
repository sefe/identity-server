import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
export function sourceHash(changes) {
  const source=changes.map(c=>({path:c.path,operation:c.operation,content:c.content}))
    .sort((a,b)=>a.path<b.path?-1:a.path>b.path?1:0);
  return createHash('sha256').update(JSON.stringify(source)).digest('hex');
}
export function verifyRecoverySource(base, candidate) {
  const merged=new Map(base.changes.map(c=>[c.path,c]));
  for(const change of candidate.changes) merged.set(change.path,change);
  if(sourceHash([...merged.values()])!==candidate.verification?.sourceSha256) throw new Error('Recovery source differs from the locally verified candidate.');
  const projects=candidate.verification?.projects;
  if(!Array.isArray(projects)||!projects.length||projects.some(p=>p.outcome!=='verified'||p.testsDiscovered<=0||p.testsFailed!==0||!p.negativeProbe?.failedAsExpected)) throw new Error('Recovery candidate has no complete local verification.');
  return true;
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 try{const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));verifyRecoverySource(read(process.argv[2]),read(process.argv[3]));}
 catch(e){console.error(e.message);process.exitCode=2;}
}
