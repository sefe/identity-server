import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { readRegularFile } from '../../scripts/helpers/read-regular-file.mjs';

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'foundry-file-read-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const file = path.join(root, 'source.txt');
  fs.writeFileSync(file, 'original');
  return { root, file };
}

test('bounded file reads accept the limit and reject larger files and directories', t => {
  const { root, file } = fixture(t);
  assert.equal(readRegularFile(file, { root, maxBytes: 8 }).toString(), 'original');
  assert.throws(() => readRegularFile(file, { root, maxBytes: 7 }), { code: 'EFILETOOLARGE' });
  assert.throws(() => readRegularFile(root));
  assert.throws(() => readRegularFile(file, { root: path.join(root, 'absent') }));
});

test('a pathname swapped after open is rejected and its opened handle is closed', t => {
  const { root, file } = fixture(t);
  const open = fs.openSync;
  let descriptor;
  t.mock.method(fs, 'openSync', (...args) => {
    const fd = open(...args);
    if (args[0] === file) {
      descriptor = fd;
      fs.renameSync(file, path.join(root, 'original.txt'));
      fs.writeFileSync(file, 'replacement');
    }
    return fd;
  });
  assert.throws(() => readRegularFile(file, { root }), { code: 'EFILEUNSAFE' });
  assert.throws(() => fs.fstatSync(descriptor), { code: 'EBADF' });
});

test('growth after the size check cannot bypass the read limit', t => {
  const { root, file } = fixture(t);
  const stat = fs.fstatSync;
  let grown = false;
  t.mock.method(fs, 'fstatSync', (...args) => {
    const info = stat(...args);
    if (!grown) { grown = true; fs.appendFileSync(file, 'extra bytes'); }
    return info;
  });
  assert.throws(() => readRegularFile(file, { root, maxBytes: 8 }), { code: 'EFILETOOLARGE' });
});

test('symbolic links are rejected even when their target is inside the root', t => {
  const { root, file } = fixture(t);
  const link = path.join(root, 'link.txt');
  try { fs.symlinkSync(file, link); }
  catch (error) { if (error.code === 'EPERM') { t.skip('Symlink creation requires Windows privileges.'); return; } throw error; }
  assert.throws(() => readRegularFile(link, { root }), error => ['ELOOP', 'EFILEUNSAFE'].includes(error.code));
});
