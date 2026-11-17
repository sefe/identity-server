import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFile } from 'node:child_process';

test('concurrent fixture calls fail exactly once without overwriting their marker', async t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'foundry-faltering-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const script = fileURLToPath(new URL('../fixtures/faltering-provider.mjs', import.meta.url));
  const invoke = () => new Promise(resolve => execFile(process.execPath, [script, path.join(root, 'request.json')],
    (error, stdout, stderr) => resolve({ code: error?.code ?? 0, stdout, stderr })));
  const results = await Promise.all([invoke(), invoke(), invoke()]);
  assert.equal(results.filter(r => r.code === 1 && r.stderr.includes('400')).length, 1);
  assert.equal(results.filter(r => r.code === 0 && JSON.parse(r.stdout).status === 'completed').length, 2);
  const marker = path.join(root, 'faltering-provider.count');
  fs.writeFileSync(marker, 'existing marker must be preserved');
  assert.equal((await invoke()).code, 0);
  assert.equal(fs.readFileSync(marker, 'utf8'), 'existing marker must be preserved');
});
