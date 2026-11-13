// A blueprint that is well argued and completely unbuildable: it designs two
// automation projects on a package ecosystem this installation has no adapter
// for. Which language the automation is written in is the architect's decision
// and is judged by review; whether the runtime can install, build and run the
// result is not a matter of opinion, so it is caught here rather than an hour
// later when a resolver has nothing to install from.
const toolchain = {
  detectedStack: {
    language: "Rust",
    runtime: "cargo 1.83",
    buildSystem: "cargo",
    packageManager: "cargo",
    existingTestFrameworks: ["cargo test"],
    evidence: ["Cargo.toml", "crates/pricing/Cargo.toml"]
  },
  ecosystem: "cargo",
  language: "Rust 2021",
  runtime: { name: "cargo", version: "1.83" },
  testFramework: "cargo-nextest",
  packages: [
    {
      name: "reqwest",
      version: "^0.12",
      scope: "dev",
      purpose: "Drive the HTTP surface from the product's own ecosystem."
    }
  ],
  coverageFit: [
    {
      capability: "HTTP and contract coverage of the pricing API",
      howItIsMet: "The suite calls the public surface with the client the product itself uses."
    }
  ],
  alternativesRejected: [
    {
      option: "A TypeScript suite on npm",
      reason: "It would introduce a second toolchain for a team that maintains only Rust."
    }
  ],
  ciRequirements: ["A Rust toolchain on the agent."],
  deviatesFromDetectedStack: false
};

process.stdout.write(JSON.stringify({
  agentId: "automation-architect",
  stageId: "architecture",
  runId: "run-unknown-ecosystem",
  status: "completed",
  summary: "Automation blueprint designed on an ecosystem this installation cannot run.",
  evidence: [],
  assumptions: [],
  unknowns: [],
  warnings: [],
  outcome: "completed",
  details: {
    decision: {
      outcome: "proceed",
      scope: "Black-box automation for the discovered target.",
      rationale: "Fixture decision used to exercise the ecosystem contract."
    },
    stack: {
      language: "rust",
      runner: "cargo-nextest",
      runtime: "cargo",
      dependencies: ["reqwest"]
    },
    structure: {
      root: "automation",
      tree: ["automation/api", "automation/ui"],
      namingConvention: "snake_case crates"
    },
    automationProjects: [
      {
        name: "automation-api",
        path: "automation/api",
        purpose: "Cover HTTP contracts.",
        runsWith: "automation-install",
        toolchain
      },
      {
        name: "automation-ui",
        path: "automation/ui",
        purpose: "Cover browser journeys.",
        runsWith: "automation-install",
        toolchain
      }
    ],
    proposedCommands: [
      {
        id: "automation-install",
        command: "cargo fetch",
        workingDirectory: "automation",
        purpose: "Install the declared dependencies.",
        verified: false
      }
    ],
    milestones: [
      { id: "m1", title: "Scaffold the crates", outcome: "Both crates build." }
    ]
  }
}));
