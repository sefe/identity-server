import { readFileSync } from 'node:fs';
const requestPath = process.argv.at(-1);
const request = readFileSync(requestPath, 'utf8');
const mode = process.argv[2];
const metadata = name => request.match(new RegExp(`- ${name}: (\\S+)`))[1];
const agentId = metadata('Agent ID');
if (!agentId.includes('-part-')) {
  process.stdout.write('{"agentId":' + JSON.stringify(agentId) + ',"summary":"' + 'x'.repeat(60000));
  process.exit(0);
}
const ordinal = Number(agentId.match(/-part-(\d+)$/)[1]);
if (mode === 'interrupt' && ordinal === 2) throw new Error('Simulated process interruption');
const blocked = mode === 'blocked' && ordinal === 2;
const change = {
  path: `automation/lib/file-${ordinal}.ts`, operation: 'create',
  content: `export const value${ordinal} = ${ordinal};\n`,
  reason: 'Implements the assigned contract.', expectedSha256: '', sourceRefs: []
};
if (mode === 'wrong-path' && ordinal === 2) change.path = 'automation/lib/unassigned.ts';
process.stdout.write(JSON.stringify({
  agentId, stageId: metadata('Stage ID'), runId: metadata('Run ID'),
  status: blocked ? 'blocked' : 'completed', outcome: blocked ? 'blocked' : 'proposed',
  batchId: `batch-01-part-${ordinal}`, summary: 'Single file result.',
  evidence: [], assumptions: [], unknowns: [], warnings: [], deferrals: [],
  details: blocked ? { requiredRepairPaths: ['automation/lib/dependency.ts'] } : {},
  changes: blocked ? [] : [change]
}));
