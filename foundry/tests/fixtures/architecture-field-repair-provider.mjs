import fs from 'node:fs';
import {createHash} from 'node:crypto';
const [basePath,requestPath]=process.argv.slice(2);
const request=fs.readFileSync(requestPath,'utf8');
if(request.includes('# Shorten the fields that are over their limit')) {
  process.stdout.write(JSON.stringify({replacements:[...request.matchAll(/^## (\/\S+)$/gm)].map(m=>({pointer:m[1],text:'Keep artifact publication gated on successful validation.'}))}));
} else {
  process.stdout.write(JSON.stringify({baseSha256:createHash('sha256').update(fs.readFileSync(basePath)).digest('hex'),
    summary:'s'.repeat(2757),status:'completed',deferrals:[],resolvedDeferrals:[],edits:[
      {path:'/details/ciIntegration/artifactGate',value:'Gate publication. '+ 'x'.repeat(820)},
      {path:'/details/automationProjects/0/toolchain/coverageFit/0/howItIsMet',value:'h'.repeat(456)},
      {path:'/details/configuration/topicNaming',value:'Isolate topics by run. '+ 'x'.repeat(810)},
      {path:'/details/configuration/authorityPolicy',value:'Validate authority before binding credentials. '+ 'x'.repeat(810)},
      {path:'/details/automationProjects/0/toolchain/packages/0/purpose',value:'p'.repeat(420)}
    ]}));
}
