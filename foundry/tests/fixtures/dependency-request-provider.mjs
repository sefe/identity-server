import { readFileSync } from 'node:fs';
const request = readFileSync(process.argv.at(-1), 'utf8');
const field = (name) => request.match(new RegExp(`- ${name}: (\\S+)`))?.[1];
const agentId = field('Agent ID');
const iteration = Number(field('Stage iteration'));
const artifact = {
  agentId, stageId: field('Stage ID'), runId: field('Run ID'),
  status: 'completed', summary: 'Dependency evolution fixture', evidence: [],
  assumptions: [], unknowns: [], warnings: [], deferrals: [], details: {},
  plannedFiles: [{
    path: agentId === 'foundation' ? 'automation/package.json' : 'automation/upload.spec.ts',
    operation: 'create', purpose: 'Upload automation',
    contentContract: agentId === 'foundation'
      ? `Pin TypeScript 5.9.3${iteration > 1 ? ' and fixture-reader 1.2.0' : ''} in devDependencies.`
      : 'Decode the uploaded fixture and assert its two prices.',
  }],
  commandsProposed: [],
};
if (agentId === 'dependent' && iteration === 1) {
  artifact.dependencyRequests = [{
    toolchainId: 'npm-tests', name: 'fixture-reader', version: '^1.0.0', scope: 'dev',
    reason: 'Decode uploaded fixture', versionReason: 'Node 22 and existing upload contract',
    evidence: ['Inspected target upload component'],
  }];
} else if (iteration > 1) {
  artifact.details.receivedActiveLock = request.includes('dependency-updates') && request.includes('1.2.0');
  artifact.details.receivedRationale = request.includes('Decode uploaded fixture');
}
process.stdout.write(JSON.stringify(artifact));
