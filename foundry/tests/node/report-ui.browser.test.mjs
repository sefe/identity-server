import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';
import { renderReport } from '../../scripts/helpers/run-report.mjs';
import { estimateEconomics } from '../../scripts/helpers/report-economics.mjs';

// An actual browser exercises native dialogs, layout, tab focus and DOM escaping.
// Set FOUNDRY_REPORT_BROWSER to a Chromium executable on non-Windows machines.
const browser = process.env.FOUNDRY_REPORT_BROWSER || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const fixture = {
  version: 1, repository: 'Example', runId: 'report-ui-test', generatedAt: '2026-09-22T10:00:00Z', status: 'pull_request_created',
  metrics: { projects: [{ path: 'api/App.csproj', category: 'Product / build project' }], physicalLines: 100, nonBlankLines: 80,
    languages: [{ name: 'C#', files: 2, physicalLines: 100, nonBlankLines: 80 }], method: 'Tracked source', unreadableFiles: 0, omittedFiles: 0 },
  usage: { calls: 2, reportedTokens: 1000, estimatedTokens: 25, unmeasuredCalls: 1, unreadableRecords: 0, complete: false,
    byStage: [{ name: 'discovery', calls: 2, reportedTokens: 1000, estimatedTokens: 25, unmeasuredCalls: 1 }],
    byModel: [{ name: 'Example model', calls: 2, reportedTokens: 1000, estimatedTokens: 25, unmeasuredCalls: 1 }] },
  verification: { projects: [{ projectPath: 'automation/Api', outcome: 'verified', testsDiscovered: 10, testsFailed: 1, steps: [{ name: 'test', status: 'failed' }] }],
    findings: [{ projectPath: 'automation/Api', message: 'Confirmed product regression, tracked by Bug(s) 123. Assertion retained.' }] },
  automationProjects: [{ name: 'Example.Automation.Api', path: 'automation/Api', purpose: 'Verify the API contract.', toolchain: { language: 'C#', ecosystem: 'nuget', testFramework: 'MSTest',
    reusedConventions: ['Same language as product'], alternativesRejected: [{ option: 'Alternative', reason: 'Does not fit the existing conventions' }], packages: [{ name: 'Test package', version: '1.0', purpose: 'Provides assertions' }] } }],
  summaries: [
    { name: 'api-test-plan.json', stage: 'test-planning', summary: 'Eight planned checks.', details: { coverageGaps: [{ id: 'EARLY-NOTE', reason: 'Early missing environment' }], scenarios: Array.from({ length: 8 }, (_, i) => ({ id: 'API-' + i, title: 'Contract scenario ' + i, priority: i % 2 ? 'P1' : 'P0', assertions: ['Exact status'] })) } },
    { name: 'ui-test-plan.json', stage: 'test-planning', summary: 'Login journey.', details: { journeys: [{ id: 'UI-1', title: 'Sign-in route', priority: 'critical' }] } },
    { name: 'product-defect-analysis.json', stage: 'verification', summary: 'Defect observed', details: { findings: [{ signature: 'Contract mismatch', hypothesis: 'An expected enum value is missing', recommendedAction: 'Review the product contract', classification: 'product_defect' }] } },
    { name: 'quality-review.json', stage: 'final-review', summary: 'Reviewed delivery', unknowns: ['Deployed suites still await credentials.'], warnings: [] }
  ],
  stages: [{ name: 'discovery', status: 'completed', attempts: 1 }], documentation: [{ url: 'javascript:alert(1)', status: 'Unavailable', detail: 'Untrusted URL' }],
  delivery: [{ type: 'pull-request.draft', status: 'executed', externalId: '42', url: 'https://dev.azure.com/example/project/_git/repo/pullrequest/42' }],
  pipelines: [{ key: 'agent-Api', name: 'API checks', pipelineId: '8', status: 'created', url: 'https://dev.azure.com/example/project/_build?definitionId=8' }],
  warnings: ['Token accounting is incomplete.'], limits: ['Discovered tests are not line coverage.'],
  economics: estimateEconomics([{ id: 'cost', startedAt: '2026-09-13T10:00:00Z', provider: 'copilot-cli', model: 'claude-opus-5', usage: { source: 'provider', inputTokens: 1000000, cachedInputTokens: 800000, outputTokens: 100000 } }])
};

function inBrowser(data, script, width = 1440) {
  // Keep browser profiles in the test temp folder; no access to the user's profile.
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'foundry-report-browser-'));
  const file = path.join(root, 'report.html');
  const harness = `<script>try { const check=(value,message)=>{if(!value)throw Error(message)}; ${script}; document.body.dataset.testResult='passed'; } catch(e) {document.body.dataset.testResult='failed: '+e.message;}</script>`;
  fs.writeFileSync(file, renderReport(data).replace('</body>', harness + '</body>'));
  let output;
  try {
    output = execFileSync(browser, ['--headless=new', '--disable-gpu', '--no-first-run', '--disable-background-networking', `--user-data-dir=${path.join(root, 'profile')}`, `--window-size=${width},1000`, '--virtual-time-budget=1500', '--dump-dom', pathToFileURL(file).href], { encoding: 'utf8', timeout: 15000, windowsHide: true, maxBuffer: 5 * 1024 * 1024, stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (error) {
    // Managed Edge can print the completed DOM but stall during shutdown.
    // Still require the page's explicit assertion result; no result is a failure.
    if (error.code !== 'ETIMEDOUT' || !/data-test-result="(?:passed|failed:)/.test(error.stdout ?? '')) throw error;
    output = error.stdout;
  }
  assert.ok(/data-test-result="passed"/.test(output), output.match(/data-test-result="[^"]*"/)?.[0] ?? 'Browser did not execute the report');
  return output;
}

test('report supports drill-down, filter pagination, keyboard tabs, usage grouping and safe evidence links', { skip: !fs.existsSync(browser) }, () => {
  inBrowser(fixture, `
    const $=id=>document.getElementById(id), click=id=>$(id).click();
    check(document.querySelectorAll('[role=tabpanel]:not([hidden])').length===1,'Only one section is visible');
    document.querySelectorAll('#cards button')[3].click();
    check(!$('coverage').hidden,'Metric opens coverage');
    check(document.querySelectorAll('#coverage-cards button.scenario').length===6,'Scenario list is paged');
    document.querySelector('#coverage-pages button:last-child').click();
    check(document.querySelectorAll('#coverage-cards button.scenario').length===3,'Next page works');
    $('coverage-area').value='UI'; $('coverage-area').dispatchEvent(new Event('change'));
    check(document.querySelectorAll('#coverage-cards button.scenario').length===1,'Filter resets page');
    document.querySelector('#coverage-cards button').click();
    check($('detail-dialog').open && $('dialog-title').textContent==='Sign-in route','Scenario opens details');
    check($('dialog-body').textContent.includes('does not claim'),'Planned does not imply passed');
    click('dialog-close'); check(!$('detail-dialog').open,'Close works');
    $('coverage-search').value='no matching scenario'; $('coverage-search').dispatchEvent(new Event('input'));
    check($('coverage-cards').textContent.includes('No scenarios match'),'Empty filter feedback');
    click('tab-technology'); document.querySelector('#technology-cards .tech-actions button').click();
    check($('detail-dialog').open && $('dialog-body').textContent.includes('Same language'),'Rationale works'); click('dialog-close');
    $('tab-technology').focus(); $('tab-technology').dispatchEvent(new KeyboardEvent('keydown',{key:'ArrowRight',bubbles:true}));
    check(document.activeElement.id==='tab-usage' && !$('usage').hidden,'Keyboard tab navigation');
    $('group').value='byModel'; $('group').dispatchEvent(new Event('change'));
    check($('usage-chart').textContent.includes('Example model'),'Usage groups by model');
    document.querySelector('#usage-chart button').click();
    check($('dialog-body').textContent.includes('1,000') && $('dialog-body').textContent.includes('25'),'Measured and estimated separate'); click('dialog-close');
    click('tab-overview'); document.querySelector('#issue-summary button').click();
    check($('dialog-body').querySelector('a').href.endsWith('/_workitems/edit/123'),'Bug link opens correct project'); click('dialog-close');
    click('tab-evidence');
    check($('evidence-kind').value==='handover','Delivery results open first');
    check($('evidence-list').textContent.includes('Conditions for rollout'),'Rollout conditions are visible in the handover');
    $('evidence-kind').value='documentation'; $('evidence-kind').dispatchEvent(new Event('change'));
    document.querySelector('#evidence-list button').click();
    check(!$('dialog-body').querySelector('a'),'Unsafe URL is not a link'); click('dialog-close');
    $('evidence-kind').value='findings'; $('evidence-kind').dispatchEvent(new Event('change'));
    check(!$('evidence-list').textContent.includes('Early missing environment'),'Early planning gaps are not final findings');
    check(!$('evidence-list').textContent.includes('Deployed suites still await credentials'),'Environment observations are separate from product findings');
    $('evidence-kind').value='rollout'; $('evidence-kind').dispatchEvent(new Event('change'));
    check($('evidence-list').textContent.includes('Deployed suites still await credentials'),'Final review limitation remains accessible');
    $('evidence-kind').value='planning'; $('evidence-kind').dispatchEvent(new Event('change'));
    check($('evidence-list').textContent.includes('Early missing environment'),'Planning evidence stays accessible');
    check($('evidence-context').textContent.includes('not a verified list'),'Historical status is explicit');
    click('tab-overview'); check(document.documentElement.scrollWidth<=window.innerWidth,'No horizontal overflow');
    click('tab-value'); check($('cost-total').textContent.includes('$4'),'AI cost is visible');
    check($('savings').textContent.includes('Potential saving'),'Baseline comparison works');
    $('actual-ai-cost').value='10000'; $('actual-ai-cost').dispatchEvent(new Event('input'));
    check($('savings').textContent.includes('costs more'),'An unfavorable result is not hidden');
    $('hourly-rate').value='-1'; $('hourly-rate').dispatchEvent(new Event('input'));
    check($('cost-comparison').textContent.includes('valid'),'Invalid numeric assumptions rejected');
    click('reset-cost'); check($('savings').textContent.includes('Potential saving'),'Reset restores scenario');
    click('tab-pipelines'); check($('pipeline-detail').textContent.includes('What starts it'),'Pipeline role details are available');
    check($('pipeline-detail').querySelector('a').href.includes('definitionId=8'),'Pipeline link is correct');
  `);
});

test('GitHub pipeline views show Actions activation and proposal-only triage', { skip: !fs.existsSync(browser) }, () => {
  const configured = ['sdlc-router','failed-build-triage','finalize','agent-api','agent-ui'].map(key => ({key,name:key,provider:'github',status:'awaiting_merge',url:'https://github.com/example/product/actions/workflows/'+key+'.yml'}));
  inBrowser({...fixture,pipelines:configured}, `
    const $=id=>document.getElementById(id), choose=kind=>document.querySelector('[data-scenario="'+kind+'"]').click();
    $('tab-pipelines').click();
    check($('pipeline-count').textContent.includes('workflow definitions'),'Workflow definitions are not called Azure registrations');
    check($('pipeline-map').textContent.includes('API/UI'),'Push runs generated suites');
    choose('failure');
    check($('pipeline-map').textContent.includes('workflow_run'),'GitHub failure trigger is named');
    check($('pipeline-map').textContent.includes('not enabled'),'No invented repair dispatch');
    check($('pipeline-detail').textContent.includes('GitHub Actions'),'Link identifies GitHub');
    check(!$('pipeline-detail').textContent.includes('Azure'),'No Azure instructions in GitHub triage');
    choose('schedule');check($('pipeline-map').textContent.includes('No recurring schedule'),'No invented weekly trigger');
  `);
});

test('empty and hostile evidence renders safely on a narrow viewport', { skip: !fs.existsSync(browser) }, () => {
  inBrowser({ ...fixture, verification: null, automationProjects: [], summaries: [], stages: [], delivery: [], pipelines: [], usage: {},
    repository: '</script><img src=x onerror=alert(1)>', documentation: [], economics: undefined }, `
    const $=id=>document.getElementById(id);
    check(!document.querySelector('img'),'Artifact text cannot inject markup');
    check($('subtitle').textContent.includes('<img'),'Hostile text is retained as text');
    check($('test-chart').textContent.includes('not been recorded'),'Missing verification remains unknown');
    $('tab-coverage').click(); check($('coverage-cards').textContent.includes('No structured scenario'),'Empty coverage works');
    $('tab-technology').click(); check($('technology-cards').textContent.includes('No approved'),'Empty technology works');
    $('tab-usage').click(); check($('usage-chart').textContent.includes('No usage records'),'Empty usage works');
    $('tab-evidence').click(); check($('evidence-list').textContent.includes('No records'),'Empty evidence works');
    $('tab-value').click(); check($('cost-total').textContent.includes('not available'),'Missing prices are not zero');
    $('tab-overview').click(); check(document.documentElement.scrollWidth<=window.innerWidth,'Mobile fits viewport');
  `, 390);
});

test('pipeline event views distinguish conditional handoffs, human review and independent triggers', { skip: !fs.existsSync(browser) }, () => {
  const configured = ['sdlc-router', 'implement-work-item', 'failed-build-triage', 'test-case-sync', 'sprint-report', 'scheduled-backlog'].map((key, i) => ({
    key, name: 'Foundry - ' + key, status: key === 'scheduled-backlog' ? 'disabled' : 'created', defaultBranch: 'refs/heads/develop', pipelineId: String(100 + i)
  }));
  inBrowser({ ...fixture, pipelines: [...fixture.pipelines, ...configured] }, `
    const $=id=>document.getElementById(id), choose=key=>document.querySelector('[data-scenario="'+key+'"]').click();
    $('tab-pipelines').click();
    check($('pipeline-map').textContent.includes('merged or pushed to develop'),'Actual target branch is shown');
    check($('pipeline-map').textContent.includes('one run per eligible task'),'Task handoff is explicit');
    check($('pipeline-map').textContent.includes('A person reviews and merges'),'Human merge is a separate step');
    check($('pipeline-map').textContent.includes('does not wait for Router'),'Test sync runs independently');
    choose('failure');
    check($('pipeline-map').textContent.includes('failed build ID'),'Failure handoff identifies its input');
    check($('pipeline-map').textContent.includes('If it is an automation issue') && $('pipeline-map').textContent.includes('If it is a product defect'),'Triage outcomes branch');
    document.querySelector('#pipeline-map [data-pipeline="implement-work-item"]').click();
    check($('pipeline-detail').textContent.includes('Turn one approved task'),'Click retains the full description');
    choose('schedule');
    check($('pipeline-map').textContent.includes('Friday · 16:00 UTC'),'Schedule time is explicit');
    check($('pipeline-map').textContent.includes('always: false'),'Schedule condition is disclosed');
    check($('pipeline-map').textContent.includes('Not active'),'Disabled sweep stays outside active chain');
    choose('manual');
    check($('pipeline-map').textContent.includes('needs a work item ID'),'Manual parameters are explained');
    check(!document.querySelector('#pipeline-map [data-pipeline="scheduled-backlog"]'),'Disabled workflow is not a registered manual choice');
    check(document.documentElement.scrollWidth<=window.innerWidth,'Pipeline view fits viewport');
  `, 1100);
});
