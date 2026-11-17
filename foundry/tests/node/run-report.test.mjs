import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { buildReport, repositoryMetrics, tokenUsage, renderReport } from '../../scripts/helpers/run-report.mjs';
function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'foundry-report-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const write = (name, data) => { const file = path.join(root, name); fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, typeof data === 'string' ? data : JSON.stringify(data)); return file; };
  execFileSync('git', ['init', '-q', root]);
  return { root, write };
}
test('token accounting counts retries and repairs, deduplicates restored records, and separates estimates', t => {
  const { root, write } = fixture(t);
  const record = { id: 'a', startedAt: '2026-09-22T01:00:00Z', stageId: 'implementation', model: 'example', usage: { source: 'provider', inputTokens: 100, outputTokens: 30, cachedInputTokens: 50 }, request: { bytes: 400 }, response: { bytes: 40 } };
  write('a.provider-metadata.json', record);
  write('copy/a.provider-metadata.json', record);
  write('retry.provider-metadata.json', { ...record, startedAt: '2026-09-22T02:00:00Z', usage: null });
  write('repair.provider-metadata.json', { ...record, id: 'repair', usage: { source: 'provider', totalTokens: 20 } });
  write('partial.provider-metadata.json', { ...record, id: 'partial', usage: { source: 'provider', inputTokens: 100 } });
  write('broken.provider-metadata.json', '{');
  const result = tokenUsage(root);
  assert.equal(result.calls, 4); assert.equal(result.reportedTokens, 150);
  assert.equal(result.estimatedTokens, 220); assert.equal(result.unmeasuredCalls, 2);
  assert.equal(result.partialCalls, 1); assert.equal(result.duplicatesIgnored, 1);
  assert.equal(result.unreadableRecords, 1); assert.equal(result.complete, false);
  assert.equal(result.byStage[0].reportedTokens, 150);
});
test('deferred bootstrap reports unexecuted tests and usage cost without a budget ledger', t => {
  const { root, write } = fixture(t);
  const runRoot = path.join(root, '.qa-foundry-artifacts/run');
  const proof = JSON.stringify({ outcome: 'not_attempted', projects: [], findings: [{ severity: 'info', message: 'Execution deferred until after delivery.' }] });
  write('.qa-foundry-artifacts/run/proof.json', proof);
  write('.qa-foundry-artifacts/run/workflow-state.json', { runId: 'run', status: 'completed', stages: [{ id: 'framework-verification', status: 'completed', attempts: [{ status: 'completed', artifacts: [{ name: 'framework-verification.json', relativePath: 'proof.json', sha256: createHash('sha256').update(proof).digest('hex') }] }] }] });
  write('.qa-foundry-artifacts/run/call.provider-metadata.json', { id: 'call', startedAt: '2026-11-12T01:00:00Z', provider: 'copilot-cli', model: 'claude-opus-5', usage: { source: 'provider', inputTokens: 1000, outputTokens: 100, cachedInputTokens: 0 } });
  const report = buildReport({ repositoryRoot: root, frameworkRoot: path.join(root, 'foundry'), runRoot });
  assert.equal(report.verification.outcome, 'not_attempted');
  assert.deepEqual(report.verification.projects, []);
  assert.equal(report.usage.calls, 1);
  assert.equal(report.economics.pricedCalls, 1);
  assert.ok(report.economics.low > 0);
  assert.match(renderReport(report), /Tests were not executed during bootstrap/);
});

test('inventory counts tracked project source, excluding runtime, dependencies and generated automation', t => {
  const { root, write } = fixture(t);
  write('api/App.csproj', '<Project/>'); write('api/Main.cs', 'line one\r\n\r\n// comment\r\n');
  write('ui/package.json', '{}'); write('ui/index.ts', 'one\ntwo');
  write('api/Generated.g.cs', 'generated'); write('ui/node_modules/x/index.js', 'dependency');
  write('Example.Automation.Api/Test.cs', 'generated test'); write('foundry/Runtime.ps1', 'runtime');
  execFileSync('git', ['-C', root, 'add', '.']); write('untracked.py', 'exclude');
  const result = repositoryMetrics(root, path.join(root, 'foundry'));
  assert.equal(result.projects.length, 2); assert.equal(result.sourceFiles, 2);
  assert.equal(result.physicalLines, 5); assert.equal(result.nonBlankLines, 4);
});
test('report uses hash-verified artifacts from completed attempts, never a stale or tampered result', t => {
  const { root, write } = fixture(t); const runRoot = path.join(root, '.qa-foundry-artifacts/run');
  const verification = JSON.stringify({ outcome: 'verified', projects: [{ projectPath: 'automation/api', testsDiscovered: 12, testsFailed: 1, steps: [{ name: 'test', status: 'failed' }] }] });
  const sha256 = createHash('sha256').update(verification).digest('hex');
  write('.qa-foundry-artifacts/run/proof.json', verification);
  write('.qa-foundry-artifacts/run/workflow-state.json', { runId: 'run', status: 'completed', stages: [{ id: 'framework-verification', status: 'completed', attempts: [{ status: 'completed', artifacts: [{ name: 'framework-verification.json', relativePath: 'proof.json', sha256 }] }] }] });
  const options = { repositoryRoot: root, frameworkRoot: path.join(root, 'foundry'), runRoot };
  assert.equal(buildReport(options).verification.projects[0].testsDiscovered, 12);
  write('.qa-foundry-artifacts/run/proof.json', verification.replace('12', '999'));
  const changed = buildReport(options); assert.equal(changed.verification, null);
  assert.match(changed.warnings.join(), /changed/);
});
test('artifact prose cannot execute HTML or escape the embedded JSON', () => {
  const html = renderReport({ summary: '</script><img src=x onerror=alert(1)>', literal: '&' });
  assert.ok(!html.includes('</script><img')); assert.ok(html.includes('\\u003c/script\\u003e'));
  assert.ok(!html.includes('innerHTML'));
});
