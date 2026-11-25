import fs from 'node:fs';

const [scenario, repair, requestPath] = process.argv.slice(2);
const request = fs.readFileSync(requestPath, 'utf8');
const base = JSON.parse(fs.readFileSync(new URL('./mock-responses/repository-discovery.json', import.meta.url), 'utf8'));
const valueAt = pointer => pointer.split('/').slice(1).reduce((value, key) => value[key], base);

if (request.includes('# Repair only the listed repository discovery fields')) {
  if (repair === 'malformed') {
    process.stdout.write('not JSON');
  } else {
    const fields = JSON.parse(request.split('## Requested fields')[1].split('## Existing discovery document')[0].trim());
    const replacements = [fields].flat().map(field => ({ pointer: field.pointer, value: valueAt(field.pointer) }));
    if (repair === 'stillLong') replacements[0].value = 'x'.repeat(401);
    if (repair === 'wrongPointer') replacements[0].pointer = '/details/componentStacks/0/path';
    if (repair === 'duplicate') replacements[1] = replacements[0];
    if (repair === 'missing') replacements.pop();
    if (repair === 'fallback') replacements.length = 0;
    if (repair === 'invalidArray') replacements.find(r => r.pointer.endsWith('excludedFromStackDetermination')).value = [{ path: 'foundry', reason: 'invented' }];
    if (repair === 'wrongType') replacements.find(r => r.pointer.endsWith('excludedFromStackDetermination')).value = '[]';
    if (repair === 'extraProperty') replacements[0].unrequested = 'change';
    const answer = { replacements };
    if (repair === 'extraRoot') answer.details = base.details;
    process.stdout.write(JSON.stringify(answer));
  }
} else {
  if (['name', 'buildSystem', 'configurationApproach'].includes(scenario)) {
    const limit = scenario === 'configurationApproach' ? 400 : 120;
    base.details.componentStacks[0][scenario] += ' explanatory wording'.repeat(Math.ceil(limit / 19));
  } else if ((scenario === 'mixed' || scenario === 'missing') && !(repair === 'fallback' && requestPath.includes('.attempt-2.request.md'))) {
    delete base.details.excludedFromStackDetermination;
    if (scenario === 'mixed') base.details.componentStacks[0].configurationApproach += 'x'.repeat(401);
  } else if (scenario === 'longPath') {
    base.details.componentStacks[0].path = 'x'.repeat(201);
  } else if (scenario === 'otherRequired') {
    delete base.details.primaryStack;
  }
  process.stdout.write(JSON.stringify(base));
}
