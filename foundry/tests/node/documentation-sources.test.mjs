import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import YAML from 'yaml';
import { parseLinks, resolveSource, download, downloadPage, extractDownloaded, collectSources, displayUrl } from '../../scripts/helpers/documentation-sources.mjs';
test('documentation input accepts multiple HTTPS URLs and rejects embedded passwords and shell text', () => {
  assert.equal(parseLinks('https://a.test/a\nhttps://b.test/b').length, 2);
  assert.deepEqual(parseLinks('none'), []);
  assert.throws(() => parseLinks('https://user:secret@a.test/'));
  assert.throws(() => parseLinks('file:///secrets'));
  assert.match(displayUrl('https://a.test/?sig=secret&path=doc'), /redacted/);
});
test('every relay receives documentation as environment data and defaults to the authorized pool', () => {
  const pipeline = YAML.parse(fs.readFileSync(new URL('../../pipelines/azure-devops/first-start-bootstrap.yml', import.meta.url), 'utf8'));
  assert.equal(pipeline.parameters.find(p => p.name === 'agentPool').default, 'TRADING-CLOUD-01');
  assert.equal(pipeline.jobs.length, 1);
  for (const job of pipeline.jobs) assert.equal(job.parameters.documentationLinks, '${{ parameters.documentationLinks }}');
  const chain = YAML.parse(fs.readFileSync(new URL('../../pipelines/azure-devops/templates/relay-chain.yml', import.meta.url), 'utf8'));
  const loop = chain.jobs[0]['${{ each slot in parameters.slots }}'][0]['${{ if ge(parameters.maxLegCount, slot.index) }}'][0];
  assert.equal(loop.parameters.documentationLinks, '${{ parameters.documentationLinks }}');
  const relay = YAML.parse(fs.readFileSync(new URL('../../pipelines/azure-devops/templates/relay-leg.yml', import.meta.url), 'utf8'));
  const step = relay.jobs[0].steps.find(s => s.name === 'bootstrap');
  assert.equal(step.env.FOUNDRY_DOCUMENTATION_LINKS, '${{ parameters.documentationLinks }}');
  assert.ok(step.inputs.script.includes('-DocumentationLinks $env:FOUNDRY_DOCUMENTATION_LINKS'));
  assert.ok(!step.inputs.script.includes('${{ parameters.documentationLinks }}'));
});
test('source adapters resolve ADO Wiki/Git and Confluence pages to content APIs', () => {
  assert.match(resolveSource('https://dev.azure.com/org/project/_wiki/wikis/wiki/123/Title').request, /wiki\/wikis\/wiki\/pages\/123\?/);
  const git = new URL(resolveSource('https://dev.azure.com/org/project/_git/repo?path=%2Fdoc.pdf&version=GBmain').request);
  assert.equal(git.searchParams.get('versionDescriptor.version'), 'main');
  assert.equal(git.searchParams.get('path'), '/doc.pdf');
  assert.equal(resolveSource('https://example.atlassian.net/wiki/spaces/TEAM/pages/123/Title').request, 'https://example.atlassian.net/wiki/rest/api/content/123?expand=body.storage');
});
test('redirects never forward source credentials to a different origin', async () => {
  const requests = [];
  await download({ request: 'https://source.test/doc', authorization: 'Bearer private' }, async (url, options) => {
    requests.push({ url, headers: options.headers });
    return requests.length === 1 ? new Response(null, { status: 302, headers: { location: 'https://files.test/doc.pdf' } }) : new Response('doc');
  });
  assert.equal(requests[0].headers.Authorization, 'Bearer private');
  assert.equal(requests[1].headers.Authorization, undefined);
});
test('SharePoint modern pages use Graph text web parts, not the sign-in or JavaScript shell', async () => {
  const source = { request: 'https://graph.microsoft.com/v1.0/sites/tenant.sharepoint.com:/sites/project', authorization: 'Bearer fixture', pageName: 'Requirements.aspx', format: 'sharepoint-page' };
  let call = 0;
  const fetched = await downloadPage(source, async (url, options) => {
    assert.equal(new URL(url).hostname, 'graph.microsoft.com');
    assert.equal(options.headers.Authorization, 'Bearer fixture');
    const values = [{ id: 'site-id' }, { value: [{ id: 'page-id', name: 'Requirements.aspx' }] },
      { canvasLayout: { horizontalSections: [{ columns: [{ webparts: [{ innerHtml: '<p>' + 'A recorded project requirement. '.repeat(5) + '</p>' }] }] }] } }];
    return Response.json(values[call++]);
  });
  const extracted = extractDownloaded(fetched, source);
  assert.equal(call, 3); assert.match(extracted.bytes.toString(), /recorded project requirement/);
});
test('sign-in pages and empty API content are not reported as usable documentation', () => {
  assert.throws(() => extractDownloaded({ bytes: Buffer.from('<input type="password">'), type: 'text/html' }, { format: 'auto' }), /sign-in/);
  assert.throws(() => extractDownloaded({ bytes: Buffer.from('{}'), type: 'application/json' }, { format: 'confluence' }), /no page content/);
});
test('snapshots survive relay resumes without network calls, and reject changed or missing contents', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'foundry-docs-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const links = parseLinks('https://source.test/doc.md'); let calls = 0;
  const fetcher = async () => { calls++; return new Response('Project requirements', { headers: { 'content-type': 'text/markdown' } }); };
  const first = await collectSources({ links, directory, fetcher });
  assert.equal(first.sources[0].status, 'downloaded');
  await collectSources({ links: [], directory, resume: true, fetcher }); assert.equal(calls, 1);
  await assert.rejects(collectSources({ links: ['https://different.test/doc.md'], directory, resume: true, fetcher }), /links changed/);
  fs.writeFileSync(path.join(directory, first.sources[0].file), 'altered');
  await assert.rejects(collectSources({ links, directory, resume: true, fetcher }), /changed/);
});
test('unavailable sources retain explicit failure evidence instead of failing the whole collection', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'foundry-docs-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const report = await collectSources({ links: ['https://private.test/page'], directory, fetcher: async () => new Response('', { status: 403 }) });
  assert.equal(report.sources[0].status, 'unavailable'); assert.match(report.sources[0].detail, /HTTP 403/);
});
