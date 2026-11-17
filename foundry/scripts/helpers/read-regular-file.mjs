import fs from 'node:fs';
import path from 'node:path';

const fail = (code, message) => Object.assign(new Error(message), { code });

// Check and read the same opened file. Never reopen a checked pathname for data.
// The caller owns root; parent directories must not be writable by other users.
export function readRegularFile(file, { root = path.dirname(file), maxBytes = 16 * 1024 * 1024 } = {}) {
  const flags = fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW ?? 0) | (fs.constants.O_NONBLOCK ?? 0);
  const fd = fs.openSync(file, flags);
  try {
    const before = fs.fstatSync(fd, { bigint: true });
    // Windows lacks O_NOFOLLOW. Check the pathname against the already-open
    // handle as well, rejecting symlinks and replacements before reading bytes.
    const named = fs.lstatSync(file, { bigint: true });
    const relative = path.relative(fs.realpathSync(root), fs.realpathSync(file));
    if (!before.isFile() || !named.isFile() || before.dev !== named.dev || before.ino !== named.ino ||
        relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
      throw fail('EFILEUNSAFE', 'Expected a regular file inside the supplied root.');
    }
    if (before.size > BigInt(maxBytes)) throw fail('EFILETOOLARGE', 'File exceeds the read limit.');
    const chunks = []; let total = 0;
    // Bound the actual read too: a file can grow after fstat.
    while (total <= maxBytes) {
      const chunk = Buffer.alloc(Math.min(64 * 1024, maxBytes + 1 - total));
      const count = fs.readSync(fd, chunk, 0, chunk.length, null);
      if (!count) break;
      total += count;
      if (total > maxBytes) throw fail('EFILETOOLARGE', 'File exceeds the read limit.');
      chunks.push(chunk.subarray(0, count));
    }
    const after = fs.fstatSync(fd, { bigint: true });
    if (before.size !== after.size || before.mtimeNs !== after.mtimeNs || before.ctimeNs !== after.ctimeNs) {
      throw fail('EFILECHANGED', 'File changed while being read.');
    }
    return Buffer.concat(chunks, total);
  } finally {
    fs.closeSync(fd);
  }
}
