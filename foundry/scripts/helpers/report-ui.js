/* This script is embedded in the standalone report. Evidence is always text. */
(() => {
  'use strict';
  const d = JSON.parse(document.getElementById('report-data').textContent);
  const $ = id => document.getElementById(id);
  const list = value => Array.isArray(value) ? value : [];
  const entries = value => Array.isArray(value) ? value : value && typeof value === 'object' ? Object.entries(value).map(([id, item]) => typeof item === 'object' && item ? { id, ...item } : { id, title: String(item) }) : [];
  const fmt = n => Number.isFinite(n) ? new Intl.NumberFormat('en').format(n) : 'Not recorded';
  const compact = n => Number.isFinite(n) ? new Intl.NumberFormat('en', { notation: 'compact', maximumFractionDigits: 1 }).format(n) : 'Not recorded';
  const human = text => String(text ?? '').replace(/\.json$/, '').replace(/([a-z])([A-Z])/g, '$1 $2').replace(/[-_]/g, ' ').replace(/^./, c => c.toUpperCase());
  const clip = (text, max = 160) => { text = String(text ?? '').replace(/\s+/g, ' ').trim(); return text.length > max ? text.slice(0, max).replace(/\s+\S*$/, '') + '…' : text; };
  const valueText = value => value == null ? 'Not recorded' : typeof value === 'object' ? JSON.stringify(value) : String(value);
  const metrics = d.metrics ?? {}, usage = d.usage ?? {}, projects = list(d.automationProjects), verified = list(d.verification?.projects);
  const summaries = list(d.summaries), pipelines = list(d.pipelines), delivery = list(d.delivery);
  const githubPipelines = pipelines.some(p => p.provider === 'github');
  const counted = verified.filter(p => Number.isFinite(p.testsDiscovered) && Number.isFinite(p.testsFailed));
  const discovered = counted.length ? counted.reduce((n, p) => n + p.testsDiscovered, 0) : undefined;
  const failed = counted.length ? counted.reduce((n, p) => n + p.testsFailed, 0) : undefined;
  const palette = ['#3677c9', '#39877e', '#8670ad', '#ba7d3c', '#64748b', '#a95879'];
  function el(tag, text, parent, className) {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = String(text);
    if (className) node.className = className;
    if (parent) parent.append(node);
    return node;
  }
  function button(parent, text, action, className = '') { const b = el('button', text, parent, className); b.type = 'button'; b.onclick = action; return b; }
  function badge(parent, text, tone = 'neutral') { return el('span', text, parent, 'badge ' + tone); }
  function safeLink(parent, label, url) {
    try {
      const u = new URL(url);
      if (u.protocol === 'https:' && !u.username && !u.password) {
        const a = el('a', label, parent); a.href = u.href; a.target = '_blank'; a.rel = 'noopener noreferrer'; return a;
      }
    } catch { /* Local paths are labels, never executable navigation. */ }
    return el('span', label, parent);
  }
  function empty(parent, message = 'No evidence recorded yet.') { el('p', message, parent, 'empty'); }
  function fields(parent, object) {
    const dl = el('dl', undefined, parent, 'fields');
    for (const [key, value] of Object.entries(object)) { el('dt', human(key), dl); el('dd', valueText(value), dl); }
  }
  // Large evidence trees are created only as a reader opens each branch.
  function tree(parent, title, value) {
    if (value == null || (Array.isArray(value) && !value.length)) return;
    const node = el('details', undefined, parent, 'tree');
    el('summary', human(title) + (Array.isArray(value) ? ' · ' + value.length : ''), node);
    let built = false;
    node.ontoggle = () => {
      if (!node.open || built) return;
      built = true;
      const body = el('div', undefined, node, 'tree-content');
      if (typeof value !== 'object') el('p', value, body);
      else if (Array.isArray(value)) {
        value.forEach((v, i) => {
          if (v && typeof v === 'object') tree(body, clip(v.title ?? v.name ?? v.capability ?? v.id ?? 'Item ' + (i + 1), 100), v);
          else el('p', valueText(v), body);
        });
      } else {
        const plain = {};
        for (const [key, item] of Object.entries(value)) {
          if (item && typeof item === 'object') tree(body, key, item);
          else plain[key] = item;
        }
        if (Object.keys(plain).length) fields(body, plain);
      }
    };
    return node;
  }
  function modal(title, render) {
    $('dialog-title').textContent = title;
    $('dialog-body').replaceChildren();
    render($('dialog-body'));
    if (!$('detail-dialog').open) $('detail-dialog').showModal();
    $('dialog-body').parentElement.scrollTop = 0;
  }
  $('dialog-close').onclick = () => $('detail-dialog').close();
  $('detail-dialog').addEventListener('click', event => { if (event.target === $('detail-dialog')) { const r = event.target.getBoundingClientRect(); if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) event.target.close(); } });
  function tab(name, focus = false) {
    document.querySelectorAll('[role=tab]').forEach(b => { const active = b.dataset.tab === name; b.setAttribute('aria-selected', String(active)); b.tabIndex = active ? 0 : -1; });
    document.querySelectorAll('[role=tabpanel]').forEach(p => { p.hidden = p.id !== name; });
    if (focus) $('tab-' + name).focus();
  }
  document.querySelectorAll('[data-tab]').forEach(b => b.onclick = () => tab(b.dataset.tab));
  document.querySelectorAll('[data-go]').forEach(b => b.onclick = () => tab(b.dataset.go, true));
  document.querySelector('[role=tablist]').addEventListener('keydown', event => {
    const tabs = [...document.querySelectorAll('[role=tab]')], index = tabs.indexOf(document.activeElement);
    if (index < 0 || !['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
    event.preventDefault();
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
    tab(tabs[next].dataset.tab, true);
  });
  function gridTable(parent, headers, rows) {
    const wrap = el('div', undefined, parent, 'table-wrap'), t = el('table', undefined, wrap);
    const tr = el('tr', undefined, el('thead', undefined, t));
    headers.forEach(h => { el('th', h, tr).scope = 'col'; });
    const body = el('tbody', undefined, t);
    rows.forEach(row => { const line = el('tr', undefined, body); row.forEach(c => el('td', c ?? 'Not recorded', line)); });
  }
  function showProjects(language = '') {
    modal(language ? language + ' source footprint' : 'Projects in the analysed repository', body => {
      el('p', 'These are detected build manifests, including existing test projects. They are not a count of deployed services.', body, 'dialog-intro');
      if (language) {
        const row = list(metrics.languages).find(l => l.name === language);
        fields(body, { language, files: fmt(row?.files), physicalLines: fmt(row?.physicalLines), nonblankLines: fmt(row?.nonBlankLines) });
      } else {
        gridTable(body, ['Project manifest', 'Category'], list(metrics.projects).map(p => [p.path, p.category]));
      }
      tree(body, 'Counting method', metrics.method);
    });
  }
  function usageMethod() {
    modal('How AI usage is counted', body => {
      el('p', 'Provider-reported usage and estimates are kept separate. Tokens are consumption, not a monetary bill.', body, 'dialog-intro');
      fields(body, { recordedCalls: fmt(usage.calls), reportedTokens: fmt(usage.reportedTokens), additionalEstimatedTokens: fmt(usage.estimatedTokens), callsWithoutFullUsage: fmt(usage.unmeasuredCalls), unreadableRecords: fmt(usage.unreadableRecords), accounting: usage.complete ? 'Complete for recorded calls' : 'Incomplete' });
      el('p', 'Retries and repairs are included. Restored copies count once. Estimates use request and response size; calls interrupted before a usage record was written may be absent. Cached input is already part of input tokens.', body);
    });
  }
  $('subtitle').textContent = (d.repository ?? 'Repository') + ' · ' + human(d.status ?? 'unavailable');
  $('identity').textContent = 'Run ' + (d.runId ?? 'not recorded') + ' · ' + new Date(d.generatedAt).toLocaleString('en');
  const metricCards = [
    [list(metrics.projects).length, 'Detected projects', 'Explore repository', () => showProjects()],
    [metrics.physicalLines, 'Source lines', 'Explore languages', () => modal('Source size by language', body => { gridTable(body, ['Language', 'Files', 'Physical lines', 'Nonblank lines'], list(metrics.languages).map(l => [l.name, fmt(l.files), fmt(l.physicalLines), fmt(l.nonBlankLines)])); tree(body, 'Counting method', metrics.method); })],
    [projects.length, 'Automation projects', 'Explore technology choices', () => tab('technology', true)],
    [discovered, 'Tests discovered', 'Explore verification & plans', () => tab('coverage', true)],
    [usage.calls ? usage.reportedTokens : undefined, 'Reported tokens', usage.complete ? 'Explore AI usage' : 'Partial accounting · explore', () => tab('usage', true)]
  ];
  for (const [value, label, hint, action] of metricCards) {
    const b = button($('cards'), '', action, 'metric');
    el('span', label === 'Reported tokens' ? compact(value) : fmt(value), b, 'number');
    el('span', label, b, 'label'); el('span', hint, b, 'hint');
    b.setAttribute('aria-label', label + ': ' + fmt(value) + '. ' + hint);
  }
  const warningCount = list(d.warnings).length;
  if (failed > 0 || warningCount || /failed|blocked|unavailable/.test(d.status ?? '')) {
    const box = el('div', undefined, $('attention'), 'alert');
    const message = failed > 0 ? fmt(failed) + ' failing test' + (failed === 1 ? '' : 's') + ' retained. Review the finding before treating the product as fully verified.' : /failed|blocked|unavailable/.test(d.status ?? '') ? 'This run has not completed successfully. Review the recorded evidence.' : 'Some report data is incomplete. The available results are shown below.';
    el('span', message, box); button(box, 'View details', () => showNotes());
  }
  function bar(parent, label, value, max, note, action, color = palette[0]) {
    const b = button(parent, '', action, 'bar-row'), row = el('div', undefined, b, 'bar-label');
    el('span', label, row); el('strong', fmt(value), row);
    const fill = el('div', undefined, el('div', undefined, b, 'track'), 'fill');
    fill.style.width = Math.max(0, Math.min(100, max > 0 ? value / max * 100 : 0)) + '%'; fill.style.backgroundColor = color;
    if (note) el('div', note, b, 'bar-note');
    b.setAttribute('aria-label', label + ': ' + fmt(value) + '. ' + note + '. Open details');
  }
  function projectLabel(p) { return projects.find(a => a.path === p.projectPath)?.name ?? String(p.projectPath ?? 'Automation project').split('/').at(-1); }
  function verificationDetail(p) {
    modal(projectLabel(p), body => {
      fields(body, { frameworkVerification: human(p.outcome), testsDiscovered: fmt(p.testsDiscovered), failedTests: fmt(p.testsFailed), testExecution: human(list(p.steps).find(s => s.name === 'test')?.status ?? 'Not recorded') });
      el('p', 'Framework verification and product test results are different signals. A retained product failure can coexist with verified framework execution.', body, 'dialog-intro');
      gridTable(body, ['Check', 'Result'], list(p.steps).map(s => [human(s.name), human(s.status)]));
      list(d.verification?.findings).filter(f => f.projectPath === p.projectPath).forEach(f => el('p', f.message, body));
      tree(body, 'Full recorded project evidence', p);
    });
  }
  if (!verified.length) empty($('test-chart'), 'Verification has not been recorded yet.');
  verified.forEach((p, i) => {
    bar($('test-chart'), projectLabel(p).replace(/^.*\.Automation\./, '') + ' automation', p.testsDiscovered, Math.max(1, ...verified.map(x => x.testsDiscovered || 0)), fmt(p.testsFailed) + ' failed · ' + human(list(p.steps).find(s => s.name === 'test')?.status ?? 'Execution not recorded'), () => verificationDetail(p), palette[i % palette.length]);
    const row = el('div', undefined, $('verification'), 'verification-row');
    button(row, projectLabel(p), () => verificationDetail(p), 'text-button');
    const numbers = el('div', undefined, row, 'numbers');
    el('strong', fmt(p.testsDiscovered) + ' discovered', numbers); el('span', fmt(p.testsFailed) + ' failed', numbers);
  });
  if (!verified.length) {
    if (d.verification?.outcome === 'not_attempted') {
      el('p', 'Tests were not executed during bootstrap. Configure credentials and run the delivered workflows afterwards. Measured coverage is unavailable.', $('verification'), 'muted');
      list(d.verification.findings).forEach(f => el('p', f.message, $('verification'), 'muted'));
    } else empty($('verification'));
  }
  const prs = delivery.filter(a => a.type === 'pull-request.draft');
  prs.forEach(a => { const row = el('div', undefined, $('delivery-summary'), 'delivery-line'); safeLink(row, 'Pull request #' + (a.externalId || 'pending'), a.url); badge(row, human(a.status)); });
  if (!prs.length) el('p', 'Pull request publication is not recorded in this snapshot.', $('delivery-summary'), 'muted');
  const pipeRow = el('div', undefined, $('delivery-summary'), 'delivery-line');
  button(pipeRow, fmt(pipelines.filter(p => ['created', 'reused'].includes(p.status)).length) + ' pipelines registered', () => openCollection('delivery'), 'text-button');
  badge(pipeRow, 'Registration ≠ execution');
  const phaseRow = el('div', undefined, $('delivery-summary'), 'delivery-line');
  const completeStages = list(d.stages).filter(s => ['completed', 'approved', 'approved_with_dissent'].includes(s.status)).length;
  button(phaseRow, completeStages + ' / ' + list(d.stages).length + ' stages completed', () => openCollection('progress'), 'text-button');
  badge(phaseRow, human(d.status ?? 'Unavailable'));
  const langs = list(metrics.languages), languageBox = $('language-chart');
  el('span', fmt(metrics.physicalLines), languageBox, 'big-inline'); el('span', 'physical source lines', languageBox, 'inline-muted');
  const stacked = el('div', undefined, languageBox, 'stacked'), legend = el('div', undefined, languageBox, 'language-legend');
  langs.forEach((l, i) => {
    const color = palette[i % palette.length], segment = button(stacked, '', () => showProjects(l.name));
    segment.style.flex = String(l.physicalLines || 0); segment.style.backgroundColor = color; segment.title = l.name + ': ' + fmt(l.physicalLines) + ' lines'; segment.setAttribute('aria-label', segment.title + '. Open details');
    const b = button(legend, '', () => showProjects(l.name)); el('span', undefined, b, 'swatch').style.backgroundColor = color; el('span', l.name + ' ' + compact(l.physicalLines), b);
  });
  $('show-projects').onclick = () => showProjects();

  // Findings come from the final analysis once, not from every reviewer repeating it.
  const defectSummary = summaries.find(s => s.name === 'product-defect-analysis.json');
  const issues = list(defectSummary?.details?.findings).map(f => ({ title: f.signature ?? f.title ?? human(f.classification), summary: f.hypothesis ?? f.message ?? f.example, data: f, source: defectSummary.name, category: 'Product finding' }));
  if (!issues.length) {
    const seen = new Set();
    list(d.verification?.findings).forEach(f => { const key = f.projectPath ?? f.message; if (seen.has(key)) return; seen.add(key); issues.push({ title: 'Verification finding', summary: f.message, data: f, category: 'Verification' }); });
  }
  const notes = list(d.warnings).map(w => ({ title: /token/i.test(w) ? 'Incomplete token accounting' : 'Evidence needs attention', summary: w, data: w, category: 'Report note' }));
  const gaps = [];
  for (const s of summaries) {
    if (!/test-plan\.json$/.test(s.name)) continue;
    for (const gap of [...list(s.details?.coverageGaps), ...list(s.details?.unresolvedRisks)]) {
      gaps.push({ title: typeof gap === 'string' ? clip(gap, 95) : gap.title ?? gap.area ?? gap.id ?? 'Planning question', summary: typeof gap === 'string' ? gap : gap.reason ?? gap.description ?? gap.risk ?? '', data: gap, source: s.name, category: 'Earlier planning note · not reassessed' });
    }
  }
  function issueDetail(issue) {
    modal(issue.title, body => {
      badge(body, issue.category, 'warning'); el('p', issue.summary, body, 'dialog-intro');
      if (issue.category.startsWith('Earlier planning')) el('p', 'Recorded before implementation. This entry may describe missing product behavior, an environment prerequisite or a potential test gap. It has not been reconciled against the final delivered tests and must not be counted as a confirmed remaining coverage gap.', body);
      if (issue.data?.recommendedAction) { el('h3', 'Recommended next step', body); el('p', issue.data.recommendedAction, body); }
      if (issue.category === 'Product finding') {
        const ids = new Set(list(d.verification?.findings).flatMap(f => [...String(f.message ?? '').matchAll(/Bug(?:\(s\)| ID\(s\))?[:\s]+([\d, ]+)/gi)].flatMap(m => m[1].match(/\d+/g) ?? [])));
        const repoLink = prs.find(p => p.url)?.url;
        if (repoLink) for (const id of ids) safeLink(el('p', undefined, body), 'Open recorded Bug #' + id, repoLink.split('/_git/')[0] + '/_workitems/edit/' + id);
      }
      tree(body, 'Supporting evidence', issue.data);
      if (issue.source) el('p', 'Source: ' + issue.source, body, 'footnote');
    });
  }
  function showNotes() { openCollection(issues.length ? 'findings' : 'notes'); }
  const overviewIssues = [...issues.slice(0, 1), ...notes.slice(0, 1)];
  overviewIssues.forEach(issue => {
    const box = el('div', undefined, $('issue-summary'), 'issue');
    const product = issue.category === 'Product finding';
    button(box, product ? 'Product finding to review' : clip(issue.title, 110), () => issueDetail(issue), 'text-button issue-title');
    el('p', product ? 'Open the observed failure, supporting evidence and recommended next step.' : clip(issue.summary, 125), box, 'short-copy');
  });
  if (!overviewIssues.length) el('p', 'No findings recorded in the available verification evidence.', $('issue-summary'), 'muted');
  $('show-notes').onclick = showNotes;

  const scenarios = [];
  for (const s of summaries) {
    if (!/test-plan\.json$/.test(s.name)) continue;
    for (const key of ['scenarios', 'journeys', 'riskScenarios']) for (const item of entries(s.details?.[key])) {
      const area = s.name.replace(/-test-plan\.json$/, '').toUpperCase();
      const priority = String(item.priority ?? item.riskLevel ?? 'Not specified');
      scenarios.push({ title: item.title ?? item.name ?? item.scenario ?? item.id ?? 'Planned scenario', id: item.id, area, priority, item, source: s.name });
    }
  }
  for (const [id, values] of [['coverage-area', scenarios.map(s => s.area)], ['coverage-priority', scenarios.map(s => s.priority)]]) {
    [...new Set(values)].sort().forEach(v => { const o = el('option', v, $(id)); o.value = v; });
  }
  let coveragePage = 0, evidencePage = 0;
  function pagination(parent, count, page, change, size = 6) {
    parent.replaceChildren();
    const pages = Math.ceil(count / size);
    if (pages < 2) return;
    const prev = button(parent, 'Previous', () => change(page - 1)); prev.disabled = page === 0;
    el('span', 'Page ' + (page + 1) + ' of ' + pages, parent);
    const next = button(parent, 'Next', () => change(page + 1)); next.disabled = page >= pages - 1;
  }
  function scenarioDetail(s) {
    modal(s.title, body => {
      badge(body, s.area); badge(body, s.priority); badge(body, 'Planned scenario');
      el('p', 'This is a test plan entry. The report does not claim that this individual scenario was executed successfully.', body, 'dialog-intro');
      for (const [key, value] of Object.entries(s.item)) {
        if (['id', 'title', 'name', 'priority'].includes(key)) continue;
        if (typeof value === 'object') tree(body, key, value);
        else fields(body, { [key]: value });
      }
      el('p', 'Source: ' + s.source + (s.id ? ' · ' + s.id : ''), body, 'footnote');
    });
  }
  function coverage() {
    const q = $('coverage-search').value.toLowerCase().trim();
    const matches = scenarios.filter(s => ($('coverage-area').value === 'all' || s.area === $('coverage-area').value) && ($('coverage-priority').value === 'all' || s.priority === $('coverage-priority').value) && JSON.stringify(s).toLowerCase().includes(q));
    const box = $('coverage-cards'); box.replaceChildren();
    $('coverage-count').textContent = matches.length + ' of ' + scenarios.length + ' planned scenarios · select a card for steps, assertions and prerequisites';
    matches.slice(coveragePage * 6, coveragePage * 6 + 6).forEach(s => { const b = button(box, '', () => scenarioDetail(s), 'scenario'); const meta = el('div', undefined, b, 'badges'); badge(meta, s.area); badge(meta, s.priority); el('h3', s.title, b); el('span', 'Planned · ' + (s.id ?? 'View scenario'), b, 'card-meta'); });
    if (!matches.length) empty(box, scenarios.length ? 'No scenarios match these filters. Try another search or choose All areas.' : 'No structured scenario plan is recorded in this snapshot.');
    pagination($('coverage-pages'), matches.length, coveragePage, page => { coveragePage = page; coverage(); });
  }
  ['coverage-area', 'coverage-priority', 'coverage-search'].forEach(id => $(id).addEventListener(id.endsWith('search') ? 'input' : 'change', () => { coveragePage = 0; coverage(); }));
  coverage();

  projects.forEach(p => {
    const tc = p.toolchain ?? {}, panel = el('article', undefined, $('technology-cards'), 'panel');
    badge(panel, tc.language ?? 'Language not recorded'); badge(panel, tc.ecosystem ?? 'Ecosystem not recorded');
    el('h3', tc.testFramework ?? p.name, panel, 'tech-title'); el('p', p.name, panel, 'tech-project');
    el('p', clip(p.purpose, 190), panel, 'short-copy');
    const capabilities = el('div', undefined, panel, 'capabilities');
    list(tc.coverageFit).slice(0, 4).forEach(c => button(capabilities, clip(c.capability, 55), () => modal(c.capability, body => el('p', c.howItIsMet, body)), 'capability'));
    const actions = el('div', undefined, panel, 'tech-actions');
    button(actions, 'Why this choice?', () => modal('Why ' + (tc.testFramework ?? p.name) + '?', body => {
      el('p', p.purpose, body, 'dialog-intro');
      el('h3', 'Fit with the existing project', body);
      const conventions = el('ul', undefined, body); list(tc.reusedConventions).forEach(c => el('li', c, conventions));
      tree(body, 'Capabilities and how they are supported', tc.coverageFit);
      tree(body, 'Detected product stack', tc.detectedStack);
      tree(body, 'Execution requirements', tc.ciRequirements);
    }), 'text-button');
    button(actions, 'Alternatives (' + list(tc.alternativesRejected).length + ')', () => modal('Alternatives considered', body => {
      if (!list(tc.alternativesRejected).length) empty(body);
      list(tc.alternativesRejected).forEach(a => { el('h3', a.option, body); el('p', a.reason, body); });
    }), 'text-button');
    button(actions, 'Packages & versions', () => modal('Proposed packages and version rationale', body => {
      el('p', 'These versions come from the approved architecture. Exact installed versions require the resolved dependency records.', body, 'dialog-intro');
      list(tc.packages).forEach(pkg => { el('h3', pkg.name + ' · ' + pkg.version, body); el('p', pkg.purpose, body); });
      tree(body, 'Complete technology decision', tc);
    }), 'text-button');
  });
  if (!projects.length) empty($('technology-cards'), 'No approved technology decision recorded yet.');
  for (const [n, label, note] of [[usage.reportedTokens, 'Provider-reported tokens', usage.complete ? 'Complete for recorded calls' : 'Partial accounting'], [usage.calls, 'Recorded AI calls', 'Includes retries and repairs'], [usage.estimatedTokens, 'Additional estimated tokens', fmt(usage.unmeasuredCalls) + ' calls without full usage']]) {
    const box = el('div', undefined, $('usage-cards'), 'usage-stat'); el('strong', compact(n), box); el('span', label, box); el('p', note, box);
  }
  function usageChart() {
    const rows = [...list(usage[$('group').value])].sort((a, b) => b.reportedTokens - a.reportedTokens), box = $('usage-chart'); box.replaceChildren();
    if (!rows.length) empty(box, 'No usage records available.');
    rows.forEach((r, i) => bar(box, $('group').value === 'byStage' ? human(r.name) : r.name, r.reportedTokens, Math.max(1, ...rows.map(x => x.reportedTokens || 0)), fmt(r.calls) + ' calls' + (r.unmeasuredCalls ? ' · ' + r.unmeasuredCalls + ' unmeasured' : ''), () => modal(r.name + ' · AI usage', body => { fields(body, { recordedCalls: fmt(r.calls), reportedTokens: fmt(r.reportedTokens), additionalEstimatedTokens: fmt(r.estimatedTokens), callsWithoutFullUsage: fmt(r.unmeasuredCalls) }); el('p', 'The bar compares provider-reported usage only. Estimates are additional and are not mixed into the measured total.', body, 'dialog-intro'); }), palette[i % 2]));
  }
  $('group').onchange = usageChart; $('usage-method').onclick = usageMethod; usageChart();

  function openCollection(kind) { $('evidence-kind').value = kind; $('evidence-search').value = ''; evidencePage = 0; evidence(); tab('evidence', true); }
  function collections() {
    const reviews = summaries.filter(s => /^(?:correctness|quality|security)-review\.json$/.test(s.name));
    const finalReviews = reviews.filter(s => s.stage === reviews.at(-1)?.stage);
    const finalNotes = finalReviews.flatMap(s => [...list(s.unknowns), ...list(s.warnings)].map(note => ({ title: 'Final review · ' + human(s.name), summary: valueText(note), data: note, source: s.name, category: 'Final review observation' })));
    return {
      handover: [
        ...(projects.length ? [{ title: projects.length + ' automation projects', summary: 'The approved design records the chosen frameworks, project responsibilities and technology rationale.', category: 'Automation design', data: projects, destination: 'technology' }] : []),
        ...(verified.length ? [{ title: fmt(discovered) + ' tests discovered · ' + fmt(failed) + ' failed', summary: 'Recorded local verification results. Deployed API and browser execution are separate checks; discovery alone does not prove full coverage.', category: 'Verification evidence', data: d.verification, destination: 'coverage' }] : []),
        ...(prs.length || pipelines.length ? [{ title: prs.length + ' pull request(s) · ' + pipelines.filter(p => ['created', 'reused'].includes(p.status)).length + ' registered pipelines', summary: 'Review the published changes and pipeline definitions. Registration is recorded separately from execution.', category: 'Published outputs', data: { pullRequests: prs, pipelines }, collection: 'delivery' }] : []),
        ...(finalNotes.length ? [{ title: 'Conditions for rollout', summary: 'The final review records prerequisites and observations for using and maintaining the automation. Review these before running it against a deployed environment.', category: 'Handover to the team', data: finalNotes, collection: 'rollout' }] : [])
      ],
      decisions: summaries.map(s => ({ title: human(s.name), summary: s.summary, category: human(s.stage), data: s })),
      findings: issues,
      rollout: finalNotes,
      notes,
      planning: gaps,
      documentation: list(d.documentation).map(s => ({ title: String(s.url ?? '').replaceAll('\\', '/').split('/').at(-1) || s.url, summary: s.detail, category: s.status, data: s, url: s.url })),
      delivery: [...prs.map(p => ({ title: 'Pull request #' + (p.externalId || 'pending'), summary: p.detail, category: human(p.status), data: p, url: p.url })), ...pipelines.map(p => ({ title: p.name ?? p.key, summary: 'Pipeline registration · execution results are not included here', category: human(p.status), data: p, url: p.url }))],
      progress: list(d.stages).map(s => ({ title: human(s.name), summary: fmt(s.attempts) + ' recorded attempt(s)', category: human(s.status), data: s }))
    };
  }
  function evidenceDetail(item, kind) {
    if (item.destination) return tab(item.destination, true);
    if (item.collection) return openCollection(item.collection);
    if (['findings', 'planning', 'rollout', 'notes'].includes(kind)) return issueDetail(item);
    modal(item.title, body => {
      badge(body, item.category); if (item.summary) el('p', item.summary, body, 'dialog-intro');
      if (item.url) safeLink(el('p', undefined, body), 'Open source', item.url);
      if (kind === 'decisions') {
        tree(body, 'Decision details', item.data.details);
        tree(body, 'Unknowns', item.data.unknowns); tree(body, 'Warnings', item.data.warnings);
        el('p', 'Source: ' + item.data.name + ' · ' + item.data.stage, body, 'footnote');
      } else tree(body, 'Recorded evidence', item.data);
    });
  }
  function evidence() {
    const kind = $('evidence-kind').value, q = $('evidence-search').value.toLowerCase().trim(), rows = collections()[kind] ?? [];
    $('evidence-context').textContent = kind === 'planning' ? 'Archive: questions recorded during planning, before the delivered result existed. These are not a verified list of remaining gaps; some refer to product features that do not exist or to environment prerequisites.' : kind === 'findings' ? 'Findings detected by the automation. A product defect is different from a defect in the test framework; retained failures remain visible here.' : kind === 'rollout' ? 'Observations retained by the final reviewers: environment prerequisites, execution limits and maintenance responsibilities. These still need to be considered before rollout.' : kind === 'notes' ? 'How complete the report measurements are, including usage accounting and unavailable evidence.' : kind === 'decisions' ? 'Archive: what was known at each stage. Earlier statements may have been superseded by later implementation and verification.' : '';
    const matches = rows.filter(s => JSON.stringify(s).toLowerCase().includes(q));
    const box = $('evidence-list'); box.replaceChildren();
    $('evidence-count').textContent = matches.length + ' of ' + rows.length + ' records · showing up to 6 at a time';
    matches.slice(evidencePage * 6, evidencePage * 6 + 6).forEach(item => {
      const row = el('article', undefined, box, 'evidence-row'), copy = el('div', undefined, row, 'copy');
      badge(copy, item.category, kind === 'findings' ? 'warning' : 'neutral');
      el('h3', clip(item.title, 110), copy); if (item.summary) el('p', clip(item.summary, 170), copy, 'short-copy');
      button(row, 'Details', () => evidenceDetail(item, kind));
    });
    if (!matches.length) empty(box, q ? 'No records match this search.' : 'No records in this collection yet.');
    pagination($('evidence-pages'), matches.length, evidencePage, page => { evidencePage = page; evidence(); });
  }
  $('evidence-kind').onchange = () => { evidencePage = 0; evidence(); };
  $('evidence-search').oninput = () => { evidencePage = 0; evidence(); }; evidence();
  $('download').onclick = () => {
    const url = URL.createObjectURL(new Blob([JSON.stringify(d, null, 2)], { type: 'application/json' }));
    const a = el('a'); a.href = url; a.download = 'foundry-report-evidence.json'; document.body.append(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
  };
  $('report-method').onclick = () => modal('How to read the numbers', body => {
    const limits = el('ul', undefined, body); list(d.limits).forEach(l => el('li', l, limits)); tree(body, 'Source inventory method', metrics.method);
    fields(body, { unreadableSourceFiles: fmt(metrics.unreadableFiles), omittedFiles: fmt(metrics.omittedFiles), existingTestFiles: fmt(metrics.existingTestFiles) });
  });
  const economics = d.economics;
  const money = n => Number.isFinite(n) ? new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 }).format(n) : 'Unavailable';
  const moneyRange = (low, high) => money(low) === money(high) ? money(low) : money(low) + '–' + money(high);
  const hasEstimate = economics?.pricedCalls > 0 && Number.isFinite(economics.low) && Number.isFinite(economics.high);
  $('cost-total').textContent = hasEstimate ? moneyRange(economics.low, economics.high) : 'Cost not available';
  $('cost-confidence').textContent = hasEstimate ? economics.pricedCalls + ' recorded calls priced · ' + economics.estimatedCalls + ' with incomplete token breakdown · ' + economics.unpricedCalls + ' unpriced. Reference value, not an invoice.' : 'This snapshot has no priceable invocation records. You can enter a known AI charge below.';
  if (hasEstimate) {
    const row = el('div', undefined, $('delivery-summary'), 'delivery-line');
    button(row, moneyRange(economics.low, economics.high) + ' estimated AI usage', () => tab('value', true), 'text-button');
    badge(row, 'Reference rates');
  }
  const proofCards = [
    [projects.length, 'Automation projects designed', 'Framework choice and rationale', () => tab('technology', true)],
    [discovered, 'Tests discovered in verification', 'Inspect failures and execution scope', () => tab('coverage', true)],
    [pipelines.filter(p => ['created', 'reused'].includes(p.status)).length, 'Pipelines registered', 'Explore the ongoing delivery workflow', () => tab('pipelines', true)]
  ];
  proofCards.forEach(([n, title, note, action]) => { const b = button($('value-proof'), '', action, 'metric'); el('span', fmt(n), b, 'number'); el('span', title, b, 'label'); el('span', note, b, 'hint'); });
  function costMethod() {
    modal('Cost sources and scenario assumptions', body => {
      if (economics) {
        el('p', 'Reference model rates checked ' + economics.pricing.checkedAt + '; estimate generated ' + economics.asOf + '. Prices can change.', body, 'dialog-intro');
        safeLink(el('p', undefined, body), 'GitHub Copilot model pricing', economics.pricing.source);
        safeLink(el('p', undefined, body), 'Upwork QA engineering rate reference', economics.market.source);
        el('p', economics.market.description + ' Published range: $' + economics.market.low + '–$' + economics.market.high + '/hour. The default $40 is the midpoint, not an observed universal average.', body);
        const ul = el('ul', undefined, body); economics.limits.forEach(l => el('li', l, ul));
        tree(body, 'Exact reference prices per million tokens', economics.pricing.models);
        fields(body, { observedCalendarSpanHours: economics.observedSpanHours == null ? 'Unavailable' : economics.observedSpanHours.toFixed(1), summedModelCallHours: economics.activeCallHours?.toFixed(1) });
      }
      el('p', 'The comparison assumes the selected specialists would deliver equivalent frameworks, tests, review and pipeline setup in the hours entered. Those hours are illustrative. It does not claim that Foundry replaces the selected number of full-time roles, nor that the first run will always succeed.', body);
      el('p', 'The controls apply only to this open report and are not saved into the evidence. Enter an actual AI charge if you have a billing export. Otherwise the range uses reference rates before any plan allowance.', body);
    });
  }
  $('cost-method').onclick = costMethod;
  $('cost-breakdown').onclick = () => modal('Estimated AI usage by model', body => {
    if (!hasEstimate) return empty(body, 'No priceable invocation evidence available.');
    gridTable(body, ['Model', 'Estimated value (USD)', 'Priced calls', 'Unpriced'], economics.byModel.map(m => [m.name, m.pricedCalls ? moneyRange(m.low, m.high) : 'Unknown', m.pricedCalls, m.unpricedCalls]));
    el('p', 'The range keeps missing cache-write detail, request tiers and estimated token usage visible. It is not an invoice.', body, 'footnote');
    safeLink(el('p', undefined, body), 'Pricing source · checked ' + economics.pricing.checkedAt, economics.pricing.source);
  });
  if (economics?.market) safeLink($('market-source'), 'Market reference: QA engineers $20–$60/hour · Upwork worldwide historical contracts', economics.market.source);
  else $('market-source').textContent = 'Illustrative rate and workload. No market snapshot is embedded in this report.';
  const costFields = ['team-size', 'manual-hours', 'hourly-rate', 'review-hours', 'other-costs', 'actual-ai-cost'];
  function compareCost() {
    const box = $('cost-comparison'), saving = $('savings'); box.replaceChildren(); saving.replaceChildren();
    const values = Object.fromEntries(costFields.map(id => [id, $(id).value === '' ? null : Number($(id).value)]));
    if (costFields.filter(id => id !== 'actual-ai-cost').some(id => values[id] == null || !Number.isFinite(values[id]) || values[id] < 0 || !$(id).checkValidity()) || (values['actual-ai-cost'] != null && (!Number.isFinite(values['actual-ai-cost']) || ! $('actual-ai-cost').checkValidity()))) {
      empty(box, 'Enter valid, non-negative assumptions. Team size, hours and hourly rate must be positive.'); return;
    }
    const actual = values['actual-ai-cost'];
    if (actual == null && (!hasEstimate || economics.unpricedCalls > 0 || usage.unreadableRecords > 0)) {
      empty(box, 'An overall comparison needs a complete priceable record set or an actual AI charge. Enter the known amount above.'); return;
    }
    const manualHours = values['team-size'] * values['manual-hours'], rate = values['hourly-rate'];
    const manual = manualHours * rate, overhead = values['review-hours'] * rate + values['other-costs'];
    const low = (actual ?? economics.low) + overhead, high = (actual ?? economics.high) + overhead;
    const max = Math.max(manual, high, 1);
    for (const [label, lowValue, highValue, color] of [['Manual delivery scenario', manual, manual, palette[0]], ['Foundry + supervision', low, high, palette[1]]]) {
      const row = el('div', undefined, box, 'cost-bar'), title = el('div', undefined, row, 'bar-label');
      el('span', label, title); el('strong', moneyRange(lowValue, highValue), title);
      const track = el('div', undefined, row, 'cost-track');
      const fill = el('div', undefined, track, 'cost-fill'); fill.style.width = (highValue / max * 100) + '%'; fill.style.backgroundColor = color;
      if (highValue > lowValue) { const uncertainty = el('div', undefined, fill, 'cost-uncertainty'); uncertainty.style.width = ((highValue - lowValue) / highValue * 100) + '%'; }
    }
    const diffLow = manual - high, diffHigh = manual - low;
    const title = diffLow > 0 ? 'Potential saving in this scenario' : diffHigh < 0 ? 'Foundry costs more in this scenario' : 'The estimated ranges overlap';
    el('span', title, saving);
    el('strong', diffLow > 0 ? moneyRange(diffLow, diffHigh) : diffHigh < 0 ? moneyRange(-diffHigh, -diffLow) : 'No clear cost advantage', saving);
    el('p', manualHours + ' assumed manual hours vs ' + values['review-hours'] + ' supervision hours. Break-even manual effort: ' + Math.ceil(low / rate) + '–' + Math.ceil(high / rate) + ' total hours at this rate.', saving);
    if (actual == null && !usage.complete) el('p', 'Usage accounting is partial. Unrecorded calls could increase Foundry costs.', saving, 'footnote');
  }
  costFields.forEach(id => $(id).addEventListener(id === 'team-size' ? 'change' : 'input', compareCost));
  $('reset-cost').onclick = () => { for (const [id, val] of Object.entries({ 'team-size': '2', 'manual-hours': '40', 'hourly-rate': '40', 'review-hours': '8', 'other-costs': '0', 'actual-ai-cost': '' })) $(id).value = val; compareCost(); };
  compareCost();

  const roles = {
    'sdlc-router': { title: 'Analyse a code change', purpose: 'Assess the change, identify affected automation and create reviewed follow-up work.', trigger: 'A push to the configured target branch, or a manual event. Azure Repos PR validation requires a separate branch policy.', next: 'New implementation tasks can be handed to the Implement Work Item pipeline.', output: 'Change-impact evidence and tracked tasks.' },
    'implement-work-item': { title: 'Implement a task', purpose: 'Turn one approved task into a reviewed change within the allowed automation scope.', trigger: 'Explicit handoff with a work item ID from an analysis workflow, or an authorized manual run.', next: 'Publish a pull request for review. A later merge can trigger analysis and test synchronization.', output: 'An implementation pull request and execution evidence.' },
    'failed-build-triage': { title: 'Investigate a failed run', purpose: 'Separate automation issues from product defects, retain valid failing assertions and create tracked work.', trigger: 'The shared failure-reporting step queues this pipeline with the failed build ID. It can also run manually.', next: 'Automation repair tasks may go to the implementor. Product defects are tracked for the product team.', output: 'Failure analysis, bugs and eligible automation repair tasks.' },
    'test-case-sync': { title: 'Keep test cases in sync', purpose: 'Reflect the automated tests in Azure Boards so coverage is visible outside the code.', trigger: 'A change under automation on the configured target branch, or a manual run.', next: 'Updates test case records; it does not execute the automated test suite.', output: 'Traceable Azure Boards test cases.' },
    'sprint-report': { title: 'Report sprint progress', purpose: 'Summarize recorded delivery for stakeholders.', trigger: 'Standard template: Friday at 16:00 UTC when schedule conditions are met, or manually.', next: 'Produces a report rather than queueing another implementation.', output: 'Sprint delivery evidence and summary.' },
    'scheduled-backlog': { title: 'Scheduled backlog sweep', purpose: 'Analyse requirements and propose work on a schedule.', trigger: 'Only when explicitly enabled. This installation may leave it disabled to avoid duplicate work.', next: 'Eligible tasks can be handed to the implementor.', output: 'Reviewed backlog proposals.' }
  };
  const roleFor = p => roles[p.key] ?? (p.key?.startsWith('agent-') ? { title: 'Run ' + String(p.name ?? '').split('.').at(-1).replace(/^Api$/, 'API').replace(/^Ui$/, 'UI') + ' checks', purpose: 'Execute the generated automation suite and publish its test results.', trigger: 'Defined by the generated suite YAML; inspect the registered pipeline for its exact branch, schedule and environment settings.', next: 'The standard failure-reporting step can hand a failed run to triage.', output: 'Automated test results and failure diagnostics.' } : { title: p.name ?? 'Registered pipeline', purpose: 'A registered pipeline with a custom role.', trigger: 'Inspect its YAML definition.', next: 'No standard handoff recorded.', output: 'Defined by the pipeline.' });
  if (githubPipelines) Object.assign(roles, {
    'sdlc-router': { title: 'Analyze release or documentation', purpose: 'Run the selected lifecycle analysis and retain its proposals.', trigger: 'Manual workflow_dispatch.', next: 'A person reviews the report and proposed changes.', output: 'Analysis and budget evidence; no automatic issue dispatch.' },
    'failed-build-triage': { title: 'Investigate a failed workflow', purpose: 'Analyze failure evidence without hiding failing assertions.', trigger: 'workflow_run after a generated suite fails on a trusted target-branch push.', next: 'A person reviews the proposed remediation.', output: 'Failure analysis and budget report.' },
    'finalize': { title: 'Verify merged installation', purpose: 'Check the installation plan and workflow hashes.', trigger: 'Relevant files change on the target branch, or workflow_dispatch.', next: 'GitHub discovers installed workflow files.', output: 'Installation verification evidence.' }
  });
  const registered = pipelines.filter(p => ['created', 'reused'].includes(p.status));
  $('pipeline-count').textContent = githubPipelines ? pipelines.length + ' workflow definitions · activate after merge' : registered.length + ' registered · ' + pipelines.filter(p => p.status === 'disabled').length + ' disabled';
  let selectedPipeline;
  function selectPipeline(p) {
    selectedPipeline = p.key;
    document.querySelectorAll('[data-pipeline]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.pipeline === selectedPipeline)));
    const box = $('pipeline-detail'), role = roleFor(p); box.replaceChildren();
    badge(box, human(p.status), p.status === 'disabled' ? 'warning' : 'neutral');
    el('h3', role.title, box); el('p', p.name, box, 'tech-project'); el('p', role.purpose, box, 'muted');
    for (const [label, text] of [['What starts it', role.trigger], ['What happens next', role.next], ['What it produces', role.output]]) { el('h4', label, box); el('p', text, box); }
    if (p.url) safeLink(el('p', undefined, box), p.provider === 'github' ? 'Open workflow in GitHub Actions' : 'Open pipeline in Azure DevOps', p.url);
    el('p', p.provider === 'github' ? 'GitHub activates these workflow files after merge. File presence does not prove a successful workflow run. Router analysis is manual; suite failure triage uses workflow_run.' : 'Standard Foundry template behavior. A registration record does not prove the pipeline or its handoff has run successfully.', box, 'footnote');
  }
  function pipelineNode(parent, key) {
    const p = pipelines.find(item => item.key === key);
    if (!p) { const missing = el('div', undefined, parent, 'pipeline-node missing-pipeline'); el('strong', roles[key]?.title ?? key, missing); badge(missing, 'Registration not recorded'); return; }
    const b = button(parent, '', () => selectPipeline(p), 'pipeline-node');
    b.dataset.pipeline = p.key; b.setAttribute('aria-pressed', String(p.key === selectedPipeline));
    el('strong', roleFor(p).title, b); el('span', p.name, b); badge(b, human(p.status), p.status === 'disabled' ? 'warning' : 'neutral');
  }
  function flowBox(parent, label, detail, tone = 'neutral') {
    const box = el('div', undefined, parent, 'flow-event ' + tone); el('strong', label, box); if (detail) el('p', detail, box); return box;
  }
  function connector(parent, text, tone = 'automatic') { const row = el('div', undefined, parent, 'flow-connector'); el('span', '↓', row, 'flow-arrow').setAttribute('aria-hidden', 'true'); badge(row, text, tone === 'person' ? 'warning' : tone === 'conditional' ? 'neutral' : ''); }
  function reviewEnd(parent) {
    connector(parent, 'Creates a pull request');
    flowBox(parent, 'A person reviews and merges the PR', 'Creating a PR does not start another implementation. After merge, the target-branch change can start the code-change flow again.', 'person');
  }
  function triggerScenario(kind) {
    document.querySelectorAll('[data-scenario]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.scenario === kind)));
    const map = $('pipeline-map'); map.replaceChildren();
    const lane = el('article', undefined, map, 'panel event-flow');
    const configuredBranch = registered.find(p => p.defaultBranch)?.defaultBranch?.replace(/^refs\/heads\//, '') || 'the configured target branch';
    if (githubPipelines) {
      const scenarios = {
        change: ['Product pull request or target-branch push', 'Each generated API/UI suite runs its own workflow and publishes test evidence.', p => p.key?.startsWith('agent-')],
        failure: ['Generated suite fails on a trusted target-branch push', 'workflow_run starts bounded failure analysis. The report records proposals; automatic issue creation and repair dispatch are not enabled.', p => p.key === 'failed-build-triage'],
        schedule: ['No recurring schedule installed', 'Use the manual router for release or documentation analysis.', () => false],
        manual: ['Run workflow in GitHub Actions', 'Choose Foundry Router for lifecycle analysis or Foundry Finalize to verify merged file hashes.', p => ['sdlc-router', 'finalize'].includes(p.key)]
      };
      const [title, detail, include] = scenarios[kind];
      flowBox(lane, title, detail);
      const selected = pipelines.filter(include);
      selected.forEach(p => pipelineNode(lane, p.key));
      if (selected.length) selectPipeline(selected[0]);
      return;
    }
    if (kind === 'change') {
      flowBox(lane, 'Code is merged or pushed to ' + configuredBranch, 'The trigger is the target branch changing. Opening a PR alone is a different event.', 'person');
      connector(lane, 'Automatic · target-branch push'); pipelineNode(lane, 'sdlc-router');
      connector(lane, 'Only when new implementation tasks are created', 'conditional'); pipelineNode(lane, 'implement-work-item');
      el('p', 'Router explicitly queues one run per eligible task, passing its work item ID. Changing a task status alone does not trigger it.', lane, 'flow-caption');
      reviewEnd(lane);
      const side = el('div', undefined, lane, 'flow-side-branch');
      badge(side, 'Independent branch from the same push');
      el('p', 'If the push changes files under automation/, Test Case Sync also runs. It does not wait for Router or Implement Work Item.', side, 'flow-caption');
      pipelineNode(side, 'test-case-sync');
      el('p', 'Generated test suites follow their own YAML triggers. PR validation in Azure Repos needs a configured branch policy.', lane, 'footnote');
    } else if (kind === 'failure') {
      flowBox(lane, 'An automation test run fails', 'API and UI suites report their own failures. This is not triggered by a successful run.');
      const suiteButtons = el('div', undefined, lane, 'pipeline-nodes'); pipelines.filter(p => p.key?.startsWith('agent-')).forEach(p => pipelineNode(suiteButtons, p.key));
      connector(lane, 'Automatic · failure-reporting step queues triage'); pipelineNode(lane, 'failed-build-triage');
      el('p', 'The suite passes the failed build ID so triage can read that run’s evidence.', lane, 'flow-caption');
      const forks = el('div', undefined, lane, 'flow-forks');
      const repair = el('div', undefined, forks, 'flow-branch'); badge(repair, 'If it is an automation issue');
      connector(repair, 'Eligible repair task is created', 'conditional'); pipelineNode(repair, 'implement-work-item');
      el('p', 'Queues a repair → opens a PR → a person reviews it.', repair, 'flow-caption');
      const defect = el('div', undefined, forks, 'flow-branch'); badge(defect, 'If it is a product defect', 'warning');
      connector(defect, 'Create a bug; keep the failing test', 'conditional');
      flowBox(defect, 'Product team investigates', 'The product defect is not handed to the automation implementor to rewrite the product or hide the assertion.', 'person');
    } else if (kind === 'schedule') {
      flowBox(lane, 'Friday · 16:00 UTC', 'Standard weekly schedule on ' + configuredBranch + '.');
      connector(lane, 'Only when the schedule detects relevant changes', 'conditional'); pipelineNode(lane, 'sprint-report');
      connector(lane, 'Publishes the sprint summary'); flowBox(lane, 'Sprint summary is ready to review', 'This flow ends with a report. It does not launch an implementation pipeline.');
      el('p', 'The standard schedule uses always: false: a scheduled run depends on source or pipeline-setting changes since the last successful scheduled run. A manual run remains possible.', lane, 'footnote');
      const optional = pipelines.find(p => p.key === 'scheduled-backlog');
      if (optional) { const side = el('div', undefined, lane, 'flow-side-branch'); badge(side, optional.status === 'disabled' ? 'Not active · separate optional schedule' : 'Separate optional workflow', 'warning'); pipelineNode(side, optional.key); el('p', optional.status === 'disabled' ? 'Disabled in this installation. It does not start on Friday with Sprint Report.' : 'Its own schedule controls it; Sprint Report does not trigger it.', side, 'flow-caption'); }
    } else {
      flowBox(lane, 'A person chooses “Run pipeline” in Azure DevOps', 'Choose the pipeline and supply the inputs it needs.', 'person');
      connector(lane, 'Manual · explicit user action', 'person');
      const choices = el('div', undefined, lane, 'pipeline-nodes');
      registered.forEach(p => pipelineNode(choices, p.key));
      if (!registered.length) empty(choices, 'No registered pipeline recorded.');
      flowBox(lane, 'Required inputs depend on the pipeline', 'Implement Work Item needs a work item ID. Failed Build Triage needs a failed build ID. Test-suite inputs are defined in their generated YAML.');
      el('p', 'A ready work item, an open PR or a registered pipeline does not by itself start an implementation run.', lane, 'flow-caption');
    }
    const preferred = kind === 'change' ? 'sdlc-router' : kind === 'failure' ? 'failed-build-triage' : kind === 'schedule' ? 'sprint-report' : selectedPipeline;
    const selected = pipelines.find(p => p.key === preferred) ?? registered[0] ?? pipelines[0];
    if (selected) selectPipeline(selected);
  }
  for (const [key, title] of [['change', 'Code merged / pushed'], ['failure', 'A test run fails'], ['schedule', 'Weekly schedule'], ['manual', 'Manual start']]) {
    const b = button($('pipeline-scenarios'), title, () => triggerScenario(key)); b.dataset.scenario = key; b.setAttribute('aria-pressed', 'false');
  }
  pipelines.forEach(p => pipelineNode($('pipeline-catalog'), p.key));
  triggerScenario('change');
  if (pipelines.length) selectPipeline(registered[0] ?? pipelines[0]);
  else { $('pipeline-map').replaceChildren(); document.querySelectorAll('[data-scenario]').forEach(b => { b.disabled = true; }); empty($('pipeline-map'), 'Pipeline registration is not recorded in this snapshot.'); empty($('pipeline-detail'), 'Details appear after pipelines have been registered.'); }
  $('print').onclick = () => window.print();
})();
