// A container runtime that is real enough to catch what a fake one cannot.
//
// Asserting on the arguments a container command was built from proves that the
// arguments were built. It does not prove that a package manager can do
// anything with them, and the failure this exists to catch is exactly that: an
// environment full of paths that name places on the agent and nothing at all
// inside a container, plus a cache that a throwaway container loses between one
// command and the next.
//
// So this runs the command. It accepts the mount, refuses any value that still
// describes the host, translates the mount back to a real directory, gives each
// invocation a home of its own that it then discards - which is what '--rm'
// means - and reports what the command did.
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const argv = process.argv.slice(2);
if (argv[0] !== "run") {
    console.error(`fake-container: expected 'run', got '${argv[0]}'`);
    process.exit(90);
}

const valueFlags = new Set(["--network", "--volume", "--workdir", "--user", "--entrypoint", "--env", "--name"]);
const env = new Map();
let volume = "";
let workdir = "";
let image = "";
let command = [];

let index = 1;
while (index < argv.length) {
    const token = argv[index];
    if (token.startsWith("-")) {
        if (valueFlags.has(token)) {
            const value = argv[index + 1];
            index += 2;
            if (token === "--volume") { volume = value; }
            else if (token === "--workdir") { workdir = value; }
            else if (token === "--env") {
                const split = value.indexOf("=");
                env.set(value.slice(0, split), value.slice(split + 1));
            }
            continue;
        }
        index += 1;
        continue;
    }
    image = token;
    command = argv.slice(index + 1);
    break;
}

if (!image || command.length === 0) {
    console.error("fake-container: no image or no command was given.");
    process.exit(90);
}

// The mount is written as '<host path>:<container path>'. On Windows the host
// side carries a drive letter, so the separator is the last colon, not the
// first.
const separator = volume.lastIndexOf(":");
const hostRoot = volume.slice(0, separator);
const containerRoot = volume.slice(separator + 1);
if (!hostRoot || !containerRoot || !existsSync(hostRoot)) {
    console.error(`fake-container: '${volume}' is not a mount of a directory that exists.`);
    process.exit(90);
}

// Nothing outside the mount exists in here. A value that still names a place on
// the agent - a drive letter, a Windows separator, an absolute path that is not
// under the mount - would be a value the command cannot use, and failing on it
// is the whole point of running this instead of reading the arguments.
const toHostPath = (value) => value.split(containerRoot).join(hostRoot);
const looksLikeHostPath = (value) =>
    /[A-Za-z]:[\\/]/.test(value) || value.includes("\\");

const childEnvironment = { PATH: process.env.PATH ?? "" };
for (const [name, value] of env) {
    if (looksLikeHostPath(value)) {
        console.error(
            `fake-container: ${name} still names a place on the host: ${value}`);
        process.exit(91);
    }
    childEnvironment[name] = toHostPath(value);
}

if (!workdir.startsWith(containerRoot)) {
    console.error(`fake-container: the working directory ${workdir} is outside the mount.`);
    process.exit(92);
}
const hostWorkingDirectory = toHostPath(workdir);
if (!existsSync(hostWorkingDirectory)) {
    console.error(`fake-container: ${workdir} does not exist inside the mount.`);
    process.exit(92);
}

// Everything a container writes outside its mount is gone when it stops. A home
// that lives only for this one command is what makes a cache kept anywhere but
// the work root disappear between the install step and the build step, which is
// the failure this fixture was written to expose.
const throwawayHome = mkdtempSync(join(tmpdir(), "fake-container-"));
for (const name of ["HOME", "USERPROFILE", "TMPDIR", "TMP", "TEMP"]) {
    childEnvironment[name] = throwawayHome;
}
if (process.platform === "win32") {
    for (const name of ["SystemRoot", "windir", "SystemDrive", "COMSPEC", "PATHEXT"]) {
        if (process.env[name]) { childEnvironment[name] = process.env[name]; }
    }
    childEnvironment.APPDATA = throwawayHome;
    childEnvironment.LOCALAPPDATA = throwawayHome;
}

try {
    const result = spawnSync(command[0], command.slice(1), {
        cwd: hostWorkingDirectory,
        env: childEnvironment,
        encoding: "utf8",
        shell: process.platform === "win32"
    });
    if (result.stdout) { process.stdout.write(result.stdout); }
    if (result.stderr) { process.stderr.write(result.stderr); }
    if (result.error) {
        console.error(`fake-container: ${result.error.message}`);
        process.exit(93);
    }
    process.exit(result.status ?? 93);
} finally {
    rmSync(throwawayHome, { recursive: true, force: true });
}
