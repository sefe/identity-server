Write the report of what was delivered during the sprint, as a change set that adds one Markdown
document under the documentation write path.

Build it from evidence in the repository context: the commit history of the period, the pull requests
merged in it, the work items referenced by those commits and pull requests, and the automation and
quality evidence the runs produced. Name the period explicitly at the top of the report, with its
start and end dates, so a reader never has to infer which sprint it describes.

Cover what changed and why it mattered, what was completed against what was planned, where the gap
was and what caused it, and what remains open going into the next sprint. Where the evidence supports
a count - work items closed, pull requests merged, tests added, failures triaged - give the count and
say what it was derived from. Include the diagrams the evidence justifies as Mermaid blocks inside
the document, so they render without any external tool and stay in version control with the text.

Report the sprint as it was, not as it was meant to be. Work that slipped, tests that were disabled,
reviews that never reached unanimity and defects found late are the parts of a sprint report that
carry information; a report that lists only successes tells the reader nothing they could act on. If
the available evidence does not support a claim, leave the claim out and say which evidence was
missing.

Use one file per sprint and a stable, dated file name, so reports accumulate as a record rather than
overwriting each other. Return `no_action_needed` with an empty changes array when the period
contains no delivered work.

Do not call external systems, do not modify anything outside the documentation write path, and do not
put credentials, tokens or personal data in the report.
