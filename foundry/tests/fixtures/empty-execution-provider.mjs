import { readFileSync } from 'node:fs';
const request = readFileSync(process.argv[2], 'utf8');
const field = name => request.match(new RegExp(`^- ${name}: (.+)$`, 'm'))?.[1]?.trim();
const agentId = field('Agent ID');
const result = {agentId, stageId: field('Stage ID'), runId: field('Run ID'), status:'completed',
  summary:'Deterministic empty execution fixture.', evidence:[], assumptions:[], unknowns:[], warnings:[], details:{}};
if (agentId === 'execution') result.commands = [];
else {
  const path = request.match(/^## Context(?: reference, not inlined)?: (.*execution-result\.json)\s*$/m)?.[1]?.trim();
  result.failures = [];
  result.details.currentEvidence = path ? JSON.parse(readFileSync(path, 'utf8')) : null;
}
process.stdout.write(JSON.stringify(result));
