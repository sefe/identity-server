# Reports, progress and project documentation

The bootstrap creates `foundry-report.html` in the product repository root as an
installer-owned file in the automation pull request. Product source and the Foundry
runtime remain outside the agents' write scope. Open the downloaded HTML in a browser;
it is self-contained and does not require a web server or external scripts.

The repository copy describes the completed analysis before publication. The pipeline
artifact also contains `bootstrap/<wrapper-run>/report.html`, updated with the pull
request and registered pipelines after delivery. Each analysis run has its own
`report.html` and `report.json`, including when a workflow pauses or fails. Earlier
prerequisite failures retain their diagnostic evidence even if no workflow exists yet.

## What the report measures

- Projects are detected build manifests, not an inferred count of deployed services.
- Source size counts Git-tracked files in recognized source languages. Physical lines
  include comments; nonblank lines exclude whitespace-only lines. Dependencies, generated
  files, Foundry, the report itself and conventional Automation paths are excluded.
  Existing product test source remains part of the repository inventory.
- Automation technology choices and findings come from the final recorded completed or
  approved stage attempt. Artifact hashes must match; a later draft cannot silently
  replace an approved result in the report.
- Test counts come from framework verification runner summaries. Discovered tests,
  failing tests and execution status are separate facts. A discovered test is not proof
  that every assertion ran, and these numbers are not a line-coverage percentage.
- Provider token records include failed calls, retries, repairs and earlier relay legs.
  Restored copies of one invocation are counted once using its ID and start time.
  Cached input is already part of input usage and is not added again. Calls without
  complete provider counts use a separately displayed byte-based estimate. Missing or
  interrupted records mean accounting is incomplete. Mock calls are not counted as AI
  spend. Token usage is not a monetary bill.

The report opens on a compact overview. Click a metric, chart bar or finding to explore
its evidence without expanding the whole page. Tabs separate scenario coverage,
technology choices, AI usage, and delivery evidence. Scenario cards support area,
priority and text filters; long collections show six records per page. Dialogs reveal
the full rationale, alternatives, packages, prerequisites and supporting records only
when requested. Tabs support arrow keys; Escape closes a dialog.

Scenario cards describe the approved **plan**, not individual passing results. Local
verification counts are displayed separately. The usage chart compares reported
tokens; unmeasured calls and additional estimates remain separate. Technology package
versions describe the architecture proposal, not proof of the installed lockfile.

**Delivery & readiness** opens on the delivered result: automation design, local
verification, publication and rollout conditions. Product/verification findings,
final review observations and report measurement notes have separate collections.
Stage decisions and planning questions sit in the **Historical evidence archive**.
Planning gaps are historical notes: missing product features, unknown requirements,
environment prerequisites and potential test gaps may all appear there. They have
not been reconciled against the delivered tests and are not counted as confirmed
remaining coverage gaps. A successful framework build and test discovery do not
establish exhaustive functional coverage; that requires behavior-to-test traceability
and execution evidence for each in-scope behavior.

The full report data can be downloaded as JSON. Print/PDF exports the selected tab.
Everything is embedded in the HTML, including styles, charts and interactions; there
are no CDN dependencies or extra model calls.

## Business value and pipeline map

**Value & cost** estimates this run's AI usage in USD using a dated Copilot pricing
snapshot, with input, cached input and output priced separately. Unknown cache-write
detail and request context tiers produce a range. Total-only and payload-size records
are explicitly estimates; unknown models/providers and expired promotional rates are
unpriced, never silently zero. This is reference usage value before plan allowances,
not a bill. The snapshot is in `scripts/helpers/report-economics.mjs`, with its source
and verification date. Update it when adopting another model or pricing period.

The interactive manual-delivery comparison uses a sourced worldwide freelance QA
engineering rate range and editable scenario assumptions: 1–5 specialists, hours,
rate, human supervision, other allocated costs and an optional actual AI charge.
The default workload is illustrative, not a measured manual benchmark. Savings can
be negative. The comparison does not prove headcount replacement, includes no assumed
annual saving, and excludes earlier independent runs and Foundry development unless
the viewer adds their cost. Input changes affect only the open report.

**Pipelines** explains the standard workflow through four selectable events: a
target-branch push/merge, a failed test run, the weekly schedule, and manual startup.
Labelled arrows distinguish automatic handoffs, conditions, and human review/merge.
The code-change view shows test-case synchronization as an independent branch of
the same push. The failure view separates automation repair from product bug tracking;
the schedule view keeps a disabled backlog sweep outside the active chain. Each
pipeline retains its purpose, trigger, output, handoff and definition link in the
details panel. A collapsed catalog provides access to every recorded pipeline.
The report distinguishes registration
from successful execution; the diagram describes standard template behavior rather
than claiming that every connection has been exercised in the live environment.

## Supplying project documentation

Use the **Project documentation URLs** bootstrap parameter. Paste HTTPS links separated
by whitespace, or use a JSON array of strings. `none` means no additional remote inputs.
The command-line equivalent is `-DocumentationLinks`. Existing local
`-DocumentationPath`, `-RequirementsPath` and `-ArchitecturePath` inputs still work.

Supported source adapters:

| Source | Input |
| --- | --- |
| Azure DevOps Git | File browser link with `path`; branch, tag and commit selectors are preserved |
| Azure DevOps Wiki | Page ID links or `pagePath` links |
| Confluence | Page ID links, `viewpage.action?pageId=...`, or `/display/SPACE/Title` |
| SharePoint | Direct file/export links, sharing links through Graph, and modern `SitePages/*.aspx` pages through Graph text web parts |
| Websites | Server-rendered HTML, text/Markdown and direct document or diagram exports |
| Documents and diagrams | DOCX, PPTX, XLSX, PDF, SVG, draw.io XML, Mermaid, PlantUML and common raster images |

Downloads are limited to 50 links, four concurrent requests, 30 seconds per request
chain, five redirects and 16 MB per document. Links inside pages are not crawled.
Client-rendered pages, interactive embeds and nontext web parts may require a direct
export. Images embedded in a page need their own links. PDF extraction requires
`pdftotext`; image OCR requires `tesseract` on the agent. OCR extracts labels, not a full
interpretation of diagram geometry. Office extraction is built in.

Downloaded documents still pass through the normal context size limits and secret
redaction. The report distinguishes unavailable downloads, missing extractors, content
excluded by a budget, and material actually included in analysis. A sign-in page or an
empty API response is not counted as project documentation. Documentation is evidence;
it is not permission to change product source or override the workflow policy.

Snapshots live in the analysis run's `documentation/` directory and travel with relay
evidence. Resume reuses and checks their hashes without contacting the sources again.
Changing the supplied link list requires restarting from discovery. A blank link list
on resume uses the saved snapshot, including when restarting discovery. To refresh
changed documentation at the same URLs, re-supply the links and start a new run or
restart discovery.

## Private sources

The Azure DevOps adapter reuses the installation's mapped PAT only for the configured
organization. For other origins, set `FOUNDRY_DOCUMENTATION_AUTH` to JSON containing
credential *environment variable names*, never the credentials themselves:

```json
{
  "https://example.atlassian.net": {
    "scheme": "basic",
    "username": "reader@example.com",
    "token_env": "FOUNDRY_CONFLUENCE_TOKEN"
  },
  "https://example.sharepoint.com": {
    "scheme": "bearer",
    "token_env": "FOUNDRY_SHAREPOINT_TOKEN"
  },
  "https://docs.example.com": {
    "scheme": "bearer",
    "token_env": "FOUNDRY_WEB_TOKEN"
  }
}
```

The bootstrap maps those three optional secret variables from its variable group.
For local invocation, supply them as process environment variables. The SharePoint
credential must be a Graph access token authorized to read the requested site/files;
Foundry does not perform an interactive sign-in or refresh expired tokens. Cross-origin
download redirects receive no source credential. If access is unavailable, collection
continues and the report records the gap.

The adapters follow the published [ADO Wiki page API](https://learn.microsoft.com/en-us/rest/api/azure/devops/wiki/pages/get-page-by-id?view=azure-devops-rest-7.1),
[Confluence content API](https://support.atlassian.com/confluence/kb/how-to-get-page-content-or-child-list-via-rest-api/),
[Graph file download API](https://learn.microsoft.com/en-us/graph/api/driveitem-get-content?view=graph-rest-1.0),
and [Graph site page API](https://learn.microsoft.com/en-us/graph/api/sitepage-get?view=graph-rest-1.0).

## Progress and diagnostics

Bootstrap uses `FOUNDRY_LOG_STYLE=summary`: stage transitions, concise findings and
failures remain in the English console log. Technical `Write-QaFoundryLog` messages go
to per-process/runspace JSONL files under the wrapper's `logs/` directory. Existing
provider and command evidence remains available in the build artifacts. Unset the
variable to show detailed console logging as well.

The bootstrap defaults to the authorized `TRADING-CLOUD-01` pool in this installation.
Other installations can choose their own pool in the launch parameters. Full-run
success still requires valid source/provider credentials, working registries and the
toolchains selected for that product; local mock validation is not a production run.
