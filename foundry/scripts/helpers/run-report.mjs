import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { estimateEconomics } from './report-economics.mjs';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const read = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const exists = file => fs.existsSync(file);
const inside = (root, file) => { const rel = path.relative(root, file); return rel !== '..' && !rel.startsWith(`..${path.sep}`) && !path.isAbsolute(rel); };
function* walk(root) {
  if (!exists(root)) return;
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const file = path.join(root, entry.name);
    if (entry.isDirectory()) yield* walk(file);
    else if (entry.isFile()) yield file; // Never follow links to other workspaces or secrets.
  }
}

export function tokenUsage(runRoot) {
  const totals = { calls: 0, reportedTokens: 0, estimatedTokens: 0, unmeasuredCalls: 0,
    partialCalls: 0, unreadableRecords: 0, duplicatesIgnored: 0, simulatedCalls: 0, byStage: [], byModel: [] };
  const seen = new Set(), stages = new Map(), models = new Map();
  const number = n => Number.isSafeInteger(n) && n >= 0;
  for (const file of walk(runRoot)) {
    if (!file.endsWith('.provider-metadata.json')) continue;
    let record;
    try { record = read(file); } catch { totals.unreadableRecords++; continue; }
    // A restarted stage may reuse an id. A restored copy of the same invocation must
    // count once, while a new invocation with the same id and a new start counts again.
    const key = `${record.id}\0${record.startedAt}`;
    if (!record.id || !record.startedAt) { totals.unreadableRecords++; continue; }
    if (seen.has(key)) { totals.duplicatesIgnored++; continue; }
    seen.add(key);
    if (record.provider === 'mock') { totals.simulatedCalls++; continue; }
    const u = record.usage ?? {};
    const measured = u.source === 'provider' && (number(u.totalTokens) || (number(u.inputTokens) && number(u.outputTokens)));
    const reported = measured ? (u.totalTokens ?? u.inputTokens + u.outputTokens) : 0;
    const partial = !measured && u.source === 'provider' && (number(u.inputTokens) || number(u.outputTokens));
    const estimated = measured ? 0 : Math.ceil(((record.request?.bytes ?? 0) + (record.response?.bytes ?? 0)) / 4);
    for (const group of [totals, ...[[stages, record.stageId], [models, record.model]].map(([map, name]) => {
      name ||= 'Unknown';
      if (!map.has(name)) map.set(name, { name, calls: 0, reportedTokens: 0, estimatedTokens: 0, unmeasuredCalls: 0, partialCalls: 0 });
      return map.get(name);
    })]) {
      group.calls++; group.reportedTokens += reported; group.estimatedTokens += estimated;
      if (!measured) group.unmeasuredCalls++;
      if (partial) group.partialCalls++;
    }
  }
  totals.byStage = [...stages.values()]; totals.byModel = [...models.values()];
  totals.complete = totals.calls > 0 && !totals.unmeasuredCalls && !totals.unreadableRecords;
  return totals;
}

const languages = { '.cs': 'C#', '.fs': 'F#', '.vb': 'Visual Basic', '.ts': 'TypeScript', '.tsx': 'TypeScript',
  '.js': 'JavaScript', '.jsx': 'JavaScript', '.mjs': 'JavaScript', '.cjs': 'JavaScript', '.vue': 'Vue', '.svelte': 'Svelte',
  '.py': 'Python', '.java': 'Java', '.kt': 'Kotlin', '.kts': 'Kotlin', '.go': 'Go', '.rs': 'Rust', '.rb': 'Ruby',
  '.php': 'PHP', '.c': 'C', '.h': 'C/C++', '.cpp': 'C++', '.hpp': 'C++', '.swift': 'Swift', '.dart': 'Dart',
  '.scala': 'Scala', '.sql': 'SQL', '.sh': 'Shell', '.ps1': 'PowerShell', '.html': 'HTML', '.css': 'CSS', '.scss': 'SCSS' };
const manifest = /(?:\.(?:csproj|fsproj|vbproj|vcxproj)$|(?:^|\/)(?:package\.json|pyproject\.toml|setup\.py|pom\.xml|build\.gradle(?:\.kts)?|go\.mod|Cargo\.toml|Gemfile|composer\.json|pubspec\.yaml|Package\.swift)$)/i;
const omitted = /(?:^|\/)(?:\.git|\.foundry|\.qa-foundry-artifacts|\.sdlc-foundry|node_modules|vendor|bin|obj|dist|build|coverage|TestResults|\.venv|venv|__pycache__|\.next)(?:\/|$)/i;
const generated = /(?:\.g\.[^.]+|\.generated\.[^.]+|\.designer\.[^.]+|\.min\.(?:js|css)|\.d\.ts)$/i;
const testFile = /(?:^|\/)(?:tests?|__tests__|specs?)(?:\/|$)|(?:[._](?:test|spec)|Tests?|Specs?)\.[^/]+$/i;
export function repositoryMetrics(repositoryRoot, frameworkRoot) {
  const result = { sourceFiles: 0, physicalLines: 0, nonBlankLines: 0, existingTestFiles: 0,
    projects: [], languages: [], omittedFiles: 0, unreadableFiles: 0,
    method: 'Git-tracked source files only. Physical lines include comments; nonblank lines exclude empty lines, not comments. Dependencies, generated files, Foundry and Automation are excluded. Project count means detected build manifests, not deployed services.' };
  const tracked = execFileSync('git', ['-C', repositoryRoot, 'ls-files', '-z'], { encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 }).split('\0').filter(Boolean);
  const byLanguage = new Map();
  for (const relative of tracked) {
    const file = path.resolve(repositoryRoot, relative), normalized = relative.replaceAll('\\', '/');
    if (!inside(repositoryRoot, file) || normalized === 'foundry-report.html' || inside(frameworkRoot, file) || omitted.test(normalized) || generated.test(normalized) || /(?:^|[/.])automation(?:[/.]|$)/i.test(normalized)) { result.omittedFiles++; continue; }
    try {
      if (fs.lstatSync(file).isSymbolicLink() || !inside(repositoryRoot, fs.realpathSync(file))) { result.omittedFiles++; continue; }
      if (manifest.test(normalized)) result.projects.push({ path: normalized, category: /test|spec/i.test(normalized) ? 'Existing tests' : 'Product / build project' });
      const language = languages[path.extname(file).toLowerCase()];
      if (!language) continue;
      if (fs.statSync(file).size > 8 * 1024 * 1024) { result.omittedFiles++; continue; }
      const content = fs.readFileSync(file, 'utf8');
      if (content.includes('\0')) { result.omittedFiles++; continue; }
      const lines = content ? content.split(/\r\n|\n|\r/) : [];
      if (lines.at(-1) === '') lines.pop();
      const nonBlank = lines.filter(line => line.trim()).length;
      result.sourceFiles++; result.physicalLines += lines.length; result.nonBlankLines += nonBlank;
      if (testFile.test(normalized)) result.existingTestFiles++;
      if (!byLanguage.has(language)) byLanguage.set(language, { name: language, files: 0, physicalLines: 0, nonBlankLines: 0 });
      const item = byLanguage.get(language); item.files++; item.physicalLines += lines.length; item.nonBlankLines += nonBlank;
    } catch { result.unreadableFiles++; }
  }
  result.languages = [...byLanguage.values()].sort((a, b) => b.physicalLines - a.physicalLines);
  return result;
}

export function buildReport({ repositoryRoot, frameworkRoot, runRoot, bootstrapResultPath = '' }) {
  const warnings = [], artifacts = [], stateFile = path.join(runRoot, 'workflow-state.json');
  const state = exists(stateFile) ? read(stateFile) : { status: 'unavailable', stages: [] };
  for (const stage of state.stages ?? []) {
    if (!['completed', 'approved', 'approved_with_dissent'].includes(stage.status)) continue;
    const attempt = stage.attempts?.filter(a => ['completed', 'approved', 'approved_with_dissent'].includes(a.status)).at(-1);
    for (const ref of attempt?.artifacts ?? []) {
      if (!ref.name.endsWith('.json')) continue;
      const file = path.resolve(runRoot, ref.relativePath);
      try {
        if (!inside(runRoot, file) || !inside(runRoot, fs.realpathSync(file)) || hash(fs.readFileSync(file)) !== ref.sha256) throw Error('Evidence identity mismatch');
        artifacts.push({ stage: stage.id, name: ref.name, data: read(file) });
      } catch { warnings.push(`Evidence unavailable or changed: ${stage.id} / ${ref.name}. Its results are not counted.`); }
    }
  }
  const blueprint = artifacts.find(a => a.name === 'automation-blueprint.json')?.data;
  const verification = artifacts.find(a => a.name === 'framework-verification.json')?.data;
  const contextPath = path.join(runRoot, 'context', 'repository.json');
  const context = exists(contextPath) ? read(contextPath) : {};
  const docsPath = path.join(runRoot, 'documentation', 'sources.json');
  const docs = exists(docsPath) ? read(docsPath) : { sources: [] };
  const documentation = docs.sources.map(s => {
    const input = (context.analysisInputs ?? []).find(i => i.path.replaceAll('\\', '/').endsWith(s.file ?? '\0'));
    return { url: s.url, status: s.status === 'downloaded' ? (input?.included ? 'Provided to analysis' : input?.skipReason ?? 'Downloaded; not yet analysed') : s.status,
      detail: s.detail, sha256: s.sha256 };
  });
  for (const input of context.analysisInputs ?? []) {
    if (input.category === 'repository' || /\/documentation\/sources\.json$/.test(input.path.replaceAll('\\', '/')) ||
      docs.sources.some(s => s.file && input.path.replaceAll('\\', '/').endsWith(s.file))) continue;
    documentation.push({ url: input.path, status: input.included ? 'Provided to analysis' : input.skipReason,
      detail: `Local ${input.category} input`, sha256: input.sha256 });
  }
  const bootstrap = bootstrapResultPath && exists(bootstrapResultPath) ? read(bootstrapResultPath) : null;
  const eventPath = path.join(runRoot, 'context', 'sdlc-event.json');
  let repositoryUrl = '', projectUrl = '';
  const github = bootstrap?.provider === 'github';
  if (github && /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(bootstrap?.repositoryUrl ?? '')) repositoryUrl = bootstrap.repositoryUrl;
  if (exists(eventPath)) {
    try {
      const url = new URL(read(eventPath).repository?.url);
      if (url.protocol === 'https:' && url.pathname.includes('/_git/')) {
        url.username = ''; url.password = ''; url.search = ''; url.hash = '';
        repositoryUrl = url.href; projectUrl = url.href.split('/_git/')[0];
      }
    } catch { /* Local-only runs have no remote links. */ }
  }
  const usage = tokenUsage(runRoot);
  const priceRecords = [];
  for (const file of walk(runRoot)) {
    if (file.endsWith('.provider-metadata.json')) {
      try { priceRecords.push(read(file)); } catch { /* Token accounting flags unreadable records. */ }
    }
  }
  const economics = estimateEconomics(priceRecords, new Date().toISOString().slice(0, 10));
  if (!usage.complete) warnings.push('Token accounting is incomplete. Provider-reported totals and size-based estimates are shown separately. Calls interrupted before a ledger record was written may be absent.');
  return {
    version: 1, generatedAt: new Date().toISOString(), runId: state.runId ?? path.basename(runRoot),
    status: bootstrap?.status ?? state.status, repository: path.basename(repositoryRoot),
    metrics: repositoryMetrics(repositoryRoot, frameworkRoot), usage, economics,
    stages: (state.stages ?? []).map(s => ({ name: s.id, status: s.status, attempts: s.attempts?.length ?? 0 })),
    automationProjects: blueprint?.details?.automationProjects ?? [],
    verification: verification ? { outcome: verification.outcome, projects: verification.projects, findings: verification.findings } : null,
    summaries: artifacts.filter(a => a.data.summary).map(a => ({ stage: a.stage, name: a.name, summary: a.data.summary,
      details: /blueprint|test-plan|coverage|execution|defect|discovery/.test(a.name)
        ? { ...a.data.details, ...(a.data.findings ? { findings: a.data.findings } : {}), ...(a.data.actions ? { actions: a.data.actions } : {}) } : undefined,
      unknowns: a.data.unknowns ?? [], warnings: a.data.warnings ?? [] })),
    documentation,
    pipelines: (bootstrap?.pipelines ?? []).map(p => ({ ...p, ...(github ? {provider:'github'} : {}), url: github && repositoryUrl && p.yamlPath ? `${repositoryUrl}/actions/workflows/${encodeURIComponent(p.yamlPath.split('/').at(-1))}` : projectUrl && p.pipelineId ? `${projectUrl}/_build?definitionId=${encodeURIComponent(p.pipelineId)}` : '' })),
    delivery: bootstrap?.delivery?.actions?.map(a => ({ type: a.type, status: a.status, detail: a.message ?? a.detail, externalId: a.externalId,
      url: a.type === 'pull-request.draft' && repositoryUrl && /^\d+$/.test(a.externalId ?? '') ? `${repositoryUrl}/${github ? 'pull' : 'pullrequest'}/${a.externalId}` : '' })) ?? [],
    warnings,
    limits: ['Test counts come from the recorded runner summary, not from counting test method names.',
      'Discovered tests are not a measurement of line coverage. Line coverage is not available unless an instrumented coverage result is supplied.',
      'Framework verification proves the reported local scenarios. It does not prove a deployment or all integrations.',
      'Tokens are usage, not a monetary bill. Cached input is part of input tokens and is not added again.',
      'This report is a snapshot. Before publication, delivery and pipeline registration may still be pending.']
  };
}

export function renderReport(data) {
  // Keep the download standalone: no CDN, browser network calls or build step.
  const asset = name => fs.readFileSync(new URL(name, import.meta.url), 'utf8');
  const json = JSON.stringify(data).replaceAll('<', '\\u003c').replaceAll('>', '\\u003e').replaceAll('&', '\\u0026');
  return asset('report-shell.html')
    .replace('/*FOUNDRY_STYLE*/', () => asset('report-ui.css'))
    .replace('/*FOUNDRY_SCRIPT*/', () => asset('report-ui.js'))
    .replace('/*FOUNDRY_DATA*/', () => json);
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const [repositoryRoot, frameworkRoot, runRoot, outputPath, bootstrapResultPath] = process.argv.slice(2);
  const data = buildReport({ repositoryRoot, frameworkRoot, runRoot, bootstrapResultPath });
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, renderReport(data), 'utf8');
  fs.writeFileSync(outputPath.replace(/\.html$/i, '') + '.json', JSON.stringify(data, null, 2), 'utf8');
}
