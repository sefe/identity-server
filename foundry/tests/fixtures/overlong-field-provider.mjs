import { readFileSync } from "node:fs";

// Reproduces build 499, which lost the run on the fourth of eleven stages
// because one contentContract was 3035 characters against a limit of 3000. The
// agent shortened it on every attempt and ran out of attempts one percent
// short, regenerating sixty-five kilobytes each time. Here the first answer is
// over the limit and the second call asks only about the field that is wrong.
const requestPath = process.argv[process.argv.length - 1];
const request = readFileSync(requestPath, "utf8");
// The provider runs in a cleaned environment, so the scenario arrives as
// arguments rather than as variables.
const [OVERAGE = "slight", REPAIR = "honours"] = process.argv.slice(2, -1);

const agentId = (request.match(/- Agent ID: (\S+)/) ?? [, "framework-implementation"])[1];
const stageId = (request.match(/- Stage ID: (\S+)/) ?? [, "implementation"])[1];
const runId = (request.match(/- Run ID: (\S+)/) ?? [, "run-repair"])[1];

const LIMIT = 4500;
const isRepair = request.includes("# Shorten the fields that are over their limit");

if (isRepair) {
  const pointers = [...request.matchAll(/^## (\/\S+)$/gm)].map((m) => m[1]);
  const limits = [...request.matchAll(/^Limit: (\d+) characters/gm)].map((m) => Number(m[1]));
  const shorten = (pointer, index) => ({
    pointer,
    text: "Tightened. " + "y".repeat(Math.min(200, (limits[index] ?? LIMIT) - 20)),
  });
  const answers = {
    // The wording is tightened and every field now fits, which is the only case
    // in which the artifact is allowed to be patched.
    honours: { replacements: pointers.map(shorten) },
    // Still over the limit: the shortening is refused and the ordinary retry
    // stands, because the runtime never accepts a field it knows is too long.
    stillLong: {
      replacements: pointers.map((pointer, index) => ({
        pointer,
        text: "z".repeat((limits[index] ?? LIMIT) + 10),
      })),
    },
    // A field nobody asked about. Answering more than was asked is as much a
    // failure of the call as answering less.
    wrongPointer: {
      replacements: [{ pointer: "/plannedFiles/1/contentContract", text: "Short contract." }],
    },
    prose: "I have shortened it for you, honestly.",
  };
  const answer = answers[REPAIR] ?? answers.honours;
  process.stdout.write(typeof answer === "string" ? answer : JSON.stringify(answer));
  process.exit(0);
}

// "slight" is build 499 to the character: over by well under a third, which is
// an edit. "gross" is half as long again, which is a rewrite and must not be
// asked for as one. "deferralItem" is build 972660: everything fits except one
// deferral's item, which is over by ten characters.
const contractLength =
  OVERAGE === "gross" ? Math.round(LIMIT * 1.6) : OVERAGE === "deferralItem" ? 40 : LIMIT + 35;

// Build 972660 left seven items undone and lost the run on the length of one of
// them. The entries either side of it are here because a repair must return the
// answer the agent gave, minus the ten characters that were too many.
const deferrals =
  OVERAGE === "deferralItem"
    ? [
        { item: "The gadget suite", reason: "The widget suite came first." },
        { item: "A".repeat(410), reason: "Ran out of room." },
        { item: "The harness README", reason: "It documents work not yet done." },
      ]
    : [];

const artifact = {
  agentId,
  stageId,
  runId,
  status: "completed",
  summary: "Deterministic overlong-field fixture.",
  evidence: [{ source: "fixture", description: "Deterministic." }],
  assumptions: [],
  unknowns: [],
  warnings: [],
  deferrals,
  details: {},
  plannedFiles: [
    {
      path: "automation/widget.mjs",
      operation: "create",
      purpose: OVERAGE === "badPurpose" ? "p".repeat(420) : "Hold the widget.",
      contentContract: "x".repeat(contractLength),
    },
    {
      path: "automation/gadget.mjs",
      operation: "create",
      purpose: "Hold the gadget.",
      contentContract: "The gadget contract, which is within its limit.",
    },
  ],
  unchangedFiles: OVERAGE === "longPath" ? ["u".repeat(220)] : ["automation/untouched.mjs"],
  commandsProposed: ["dotnet build"],
};

process.stdout.write(JSON.stringify(artifact));
