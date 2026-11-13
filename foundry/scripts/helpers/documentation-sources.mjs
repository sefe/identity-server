import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
const sha = value => createHash('sha256').update(value).digest('hex');
export function parseLinks(value = '') {
  if (!value.trim() || value.trim() === 'none') return [];
  let links;
  try { links = value.trim().startsWith('[') ? JSON.parse(value) : value.trim().split(/\s+|;(?=https:\/\/)/); }
  catch { throw Error('Documentation links must be HTTPS URLs separated by whitespace, or a JSON array of URLs.'); }
  if (!Array.isArray(links) || links.length > 50) throw Error('Supply at most 50 documentation links.');
  return [...new Set(links)].map(link => {
    let url;
    try { url = new URL(link); } catch { throw Error('A documentation link is not a valid absolute HTTPS URL.'); }
    if (url.protocol !== 'https:' || url.username || url.password) throw Error('Documentation links must use HTTPS without embedded credentials.');
    url.hash = ''; return url.href;
  });
}
export function displayUrl(value) {
  const url = new URL(value);
  for (const name of [...url.searchParams.keys()]) {
    if (/token|secret|password|signature|^sig$|^code$|^key$/i.test(name)) url.searchParams.set(name, '[redacted]');
  }
  return url.href;
}
export function resolveSource(value, auth = {}) {
  const url = new URL(value), source = { request: url.href, kind: 'web', format: 'auto', authorization: '' };
  const setting = auth[url.origin];
  if (setting) {
    const credential = process.env[setting.token_env] ?? '';
    if (credential && !/^\$\(/.test(credential)) {
      source.authorization = setting.scheme === 'basic'
        ? 'Basic ' + Buffer.from(`${setting.username ?? ''}:${credential}`).toString('base64')
        : 'Bearer ' + credential;
    }
  }
  const parts = url.pathname.split('/').filter(Boolean).map(decodeURIComponent);
  if (url.hostname === 'dev.azure.com' && parts.length >= 4) {
    const base = `https://dev.azure.com/${encodeURIComponent(parts[0])}/${encodeURIComponent(parts[1])}/_apis`;
    if (parts[2] === '_git' && url.searchParams.get('path')) {
      const api = new URL(`${base}/git/repositories/${encodeURIComponent(parts[3])}/items`);
      api.searchParams.set('path', url.searchParams.get('path')); api.searchParams.set('api-version', '7.1');
      api.searchParams.set('download', 'true');
      const version = url.searchParams.get('version');
      if (version && /^(GB|GT|GC)/.test(version)) {
        api.searchParams.set('versionDescriptor.version', version.slice(2));
        api.searchParams.set('versionDescriptor.versionType', { GB: 'branch', GT: 'tag', GC: 'commit' }[version.slice(0, 2)]);
      }
      source.request = api.href; source.kind = 'Azure DevOps Git';
      source.filename = path.basename(url.searchParams.get('path'));
    } else if (parts[2] === '_wiki' && parts[3] === 'wikis' && parts[4]) {
      const pageId = /^\d+$/.test(parts[5] ?? '') ? `/${parts[5]}` : '';
      const api = new URL(`${base}/wiki/wikis/${encodeURIComponent(parts[4])}/pages${pageId}`);
      if (!pageId) api.searchParams.set('path', url.searchParams.get('pagePath') ?? '/');
      api.searchParams.set('includeContent', 'true'); api.searchParams.set('api-version', '7.1');
      source.request = api.href; source.kind = 'Azure DevOps Wiki'; source.format = 'ado-wiki';
    }
  }
  const page = url.pathname.match(/^(.*?)(?:\/spaces\/[^/]+\/pages\/|\/pages\/viewpage\.action)(\d+)?/);
  const pageId = page?.[2] ?? url.searchParams.get('pageId');
  if (page && pageId && /^\d+$/.test(pageId)) {
    source.request = `${url.origin}${page[1]}/rest/api/content/${pageId}?expand=body.storage`;
    source.kind = 'Confluence'; source.format = 'confluence';
  }
  const legacy = url.pathname.match(/^(.*?)\/display\/([^/]+)\/(.+)$/);
  if (legacy) {
    const api = new URL(`${url.origin}${legacy[1]}/rest/api/content`);
    api.searchParams.set('spaceKey', decodeURIComponent(legacy[2]));
    api.searchParams.set('title', decodeURIComponent(legacy[3]).replaceAll('+', ' '));
    api.searchParams.set('expand', 'body.storage');
    source.request = api.href; source.kind = 'Confluence'; source.format = 'confluence';
  }
  if (url.hostname.endsWith('.sharepoint.com')) {
    source.kind = 'SharePoint';
    const modernPage = url.pathname.match(/^(.*?)\/SitePages\/([^/]+\.aspx)$/i);
    if (modernPage && !source.authorization.startsWith('Bearer ')) {
      throw Error('The documentation API requires a configured Graph bearer credential for SharePoint pages.');
    }
    // File sharing links resolve through Graph with a SharePoint/Graph bearer
    // credential explicitly assigned to this tenant. Download redirects receive no token.
    if (modernPage && source.authorization.startsWith('Bearer ')) {
      source.request = `https://graph.microsoft.com/v1.0/sites/${url.hostname}:${modernPage[1] || '/'}`;
      source.pageName = decodeURIComponent(modernPage[2]); source.format = 'sharepoint-page';
    } else if (source.authorization.startsWith('Bearer ') && /\/:\w:\//.test(url.pathname)) {
      source.request = `https://graph.microsoft.com/v1.0/shares/u!${Buffer.from(url.href).toString('base64url')}/driveItem/content`;
    } else if (!url.pathname.endsWith('.aspx')) {
      url.searchParams.set('download', '1'); source.request = url.href;
    }
  }
  return source;
}
export async function download(source, fetcher = fetch) {
  let url = source.request, authorization = source.authorization;
  const timeout = AbortSignal.timeout(30_000);
  for (let redirect = 0; redirect <= 5; redirect++) {
    const response = await fetcher(url, { redirect: 'manual', signal: timeout,
      headers: { Accept: '*/*', ...(authorization ? { Authorization: authorization } : {}) } });
    if (response.status >= 300 && response.status < 400) {
      const location = response.headers.get('location');
      await response.body?.cancel();
      if (!location) throw Error('Redirect has no destination.');
      const next = new URL(location, url);
      if (next.protocol !== 'https:' || next.username || next.password) throw Error('Unsafe documentation redirect.');
      if (next.origin !== new URL(url).origin) authorization = '';
      url = next.href; continue;
    }
    if (!response.ok) { await response.body?.cancel(); throw Error(`HTTP ${response.status}; check the link and configured source access.`); }
    const limit = 16 * 1024 * 1024;
    if (Number(response.headers.get('content-length')) > limit) { await response.body?.cancel(); throw Error('Document exceeds the 16 MB download limit.'); }
    const chunks = []; let size = 0;
    for await (const chunk of response.body ?? []) {
      size += chunk.length; if (size > limit) throw Error('Document exceeds the 16 MB download limit.');
      chunks.push(chunk);
    }
    return { bytes: Buffer.concat(chunks), type: (response.headers.get('content-type') ?? '').split(';')[0].trim().toLowerCase(), url };
  }
  throw Error('Too many redirects.');
}
export function extractDownloaded(downloaded, source) {
  let { bytes, type } = downloaded;
  if (source.format === 'ado-wiki' || source.format === 'confluence') {
    let value;
    try { value = JSON.parse(bytes.toString('utf8')); } catch { throw Error('The documentation API did not return readable page content.'); }
    if (source.format === 'confluence' && Array.isArray(value.results)) {
      if (value.results.length !== 1) throw Error('The documentation API returned an ambiguous page lookup.');
      value = value.results[0];
    }
    const content = source.format === 'ado-wiki' ? value.content : value.body?.storage?.value;
    if (typeof content !== 'string' || !content.trim()) throw Error('The documentation API returned no page content.');
    bytes = Buffer.from(content); type = source.format === 'ado-wiki' ? 'text/markdown' : 'text/html';
  }
  if (type === 'text/html') {
    const html = bytes.toString('utf8');
    if (/<input[^>]*type\s*=\s*["']?password|name=["']loginfmt|Sign in to your account/i.test(html)) throw Error('The source returned a sign-in page, not documentation.');
    const text = html.replace(/<(script|style|noscript)\b[^>]*>[\s\S]*?<\/\1>/gi, '')
      .replace(/<(?:br|\/p|\/div|\/h[1-6]|\/li|\/tr)[^>]*>/gi, '\n').replace(/<[^>]+>/g, ' ')
      .replace(/&#(x[\da-f]+|\d+);/gi, (_, n) => { const code = n[0].toLowerCase() === 'x' ? parseInt(n.slice(1), 16) : Number(n); return code <= 0x10ffff ? String.fromCodePoint(code) : ' '; })
      .replace(/&(amp|lt|gt|quot|apos|nbsp);/g, (_, n) => ({ amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: ' ' }[n]))
      .replace(/[ \t]+/g, ' ').replace(/\n\s*\n/g, '\n').trim();
    if (text.length < 80) throw Error('No substantive page text. Supply an export or direct file link for client-rendered pages.');
    return { bytes: Buffer.from(text), extension: '.txt' };
  }
  const known = { 'application/pdf': '.pdf', 'image/png': '.png', 'image/jpeg': '.jpg', 'image/webp': '.webp',
    'image/tiff': '.tiff', 'image/svg+xml': '.svg', 'text/markdown': '.md', 'text/plain': '.txt', 'application/json': '.json',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': '.docx',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation': '.pptx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': '.xlsx' };
  const extension = known[type] ?? path.extname(source.filename ?? new URL(downloaded.url).pathname).toLowerCase();
  if (!/^\.(?:pdf|png|jpe?g|webp|tiff?|svg|md|txt|json|ya?ml|xml|docx|pptx|xlsx|drawio|puml|mmd)$/.test(extension)) throw Error('Unsupported downloaded format; supply a document or diagram export.');
  return { bytes, extension };
}
export async function downloadPage(source, fetcher = fetch) {
  if (source.format !== 'sharepoint-page') return download(source, fetcher);
  const site = JSON.parse((await download(source, fetcher)).bytes.toString('utf8'));
  if (!site.id) throw Error('The documentation API returned no SharePoint site identity.');
  const pagesUrl = new URL(`https://graph.microsoft.com/v1.0/sites/${encodeURIComponent(site.id)}/pages/microsoft.graph.sitePage`);
  pagesUrl.searchParams.set('$filter', `name eq '${source.pageName.replaceAll("'", "''")}'`);
  const pages = JSON.parse((await download({ ...source, request: pagesUrl.href }, fetcher)).bytes.toString('utf8'));
  const matches = (pages.value ?? []).filter(p => p.name === source.pageName);
  if (matches.length !== 1 || !matches[0].id) throw Error('The documentation API could not identify one SharePoint page.');
  const pageUrl = `https://graph.microsoft.com/v1.0/sites/${encodeURIComponent(site.id)}/pages/${encodeURIComponent(matches[0].id)}/microsoft.graph.sitePage?$expand=canvasLayout`;
  const page = JSON.parse((await download({ ...source, request: pageUrl }, fetcher)).bytes.toString('utf8'));
  const text = [];
  function collect(node) {
    if (!node || typeof node !== 'object') return;
    for (const [key, value] of Object.entries(node)) {
      if (key === 'innerHtml' && typeof value === 'string') text.push(value);
      else if (typeof value === 'object') collect(value);
    }
  }
  collect(page.canvasLayout);
  if (!text.length) throw Error('The documentation API returned no text web parts. Supply a document export.');
  return { bytes: Buffer.from(text.join('\n')), type: 'text/html', url: pageUrl };
}
export async function collectSources({ links, directory, auth = {}, resume = false, fetcher = fetch }) {
  fs.mkdirSync(directory, { recursive: true });
  const manifestPath = path.join(directory, 'sources.json');
  if (resume && fs.existsSync(manifestPath)) {
    const previous = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    if (links.length && JSON.stringify(previous.identities) !== JSON.stringify(links.map(sha))) throw Error('Documentation links changed. Restart from discovery to collect a new snapshot.');
    for (const source of previous.sources) if (source.file) {
      const file = path.join(directory, source.file);
      if (!/^[a-f0-9]{64}\.[a-z0-9]+$/.test(source.file) || fs.lstatSync(file).isSymbolicLink() || sha(fs.readFileSync(file)) !== source.sha256) throw Error('The saved documentation snapshot has changed or is incomplete.');
    }
    return previous;
  }
  const manifest = { version: 1, identities: links.map(sha), sources: [] };
  async function collect(url) {
    const source = { url: displayUrl(url), status: 'unavailable', detail: '', file: null, sha256: null };
    try {
      const adapter = resolveSource(url, auth);
      const payload = extractDownloaded(await downloadPage(adapter, fetcher), adapter);
      source.file = sha(url) + payload.extension;
      // The normal context collector performs secret redaction before handing
      // any extracted content to a model. Keep credentials out of this manifest.
      fs.writeFileSync(path.join(directory, source.file), payload.bytes);
      source.status = 'downloaded'; source.sha256 = sha(payload.bytes);
      source.detail = `${adapter.kind}; immutable snapshot. Embedded links are not crawled. Images require OCR; OCR does not interpret diagram structure.`;
    } catch (error) {
      source.detail = /^(HTTP |Document exceeds|The documentation API|The source returned|No substantive|Unsupported downloaded|Too many|Unsafe documentation)/.test(error.message)
        ? error.message : 'Could not retrieve this source. Check connectivity, the URL and source credentials.';
    }
    return source;
  }
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(4, links.length) }, async () => {
    while (next < links.length) {
      const index = next++;
      manifest.sources[index] = await collect(links[index]);
    }
  }));
  fs.writeFileSync(manifestPath + '.tmp', JSON.stringify(manifest, null, 2));
  fs.renameSync(manifestPath + '.tmp', manifestPath);
  return manifest;
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const [directory, mode] = process.argv.slice(2);
  const authText = process.env.FOUNDRY_DOCUMENTATION_AUTH ?? '';
  const auth = authText.startsWith('{') ? JSON.parse(authText) : {};
  const organization = process.env.FOUNDRY_DOCUMENTATION_ADO_ORG;
  // Restrict the inherited PAT to this installation's Azure organization.
  const links = parseLinks(process.env.FOUNDRY_DOCUMENTATION_LINKS);
  for (const url of links) {
    if (organization && (url.startsWith(organization.replace(/\/$/, '') + '/'))) {
      auth[new URL(url).origin] ??= { token_env: 'FOUNDRY_DOCUMENTATION_ADO_TOKEN', scheme: process.env.FOUNDRY_DOCUMENTATION_ADO_SCHEME ?? 'basic' };
    }
  }
  // auth is normally origin scoped. For the shared dev.azure.com host, resolve
  // each source separately so one permitted organization cannot authorize others.
  const guardedFetch = (url, options) => {
    if (new URL(url).hostname === 'dev.azure.com' && organization && !url.startsWith(organization.replace(/\/$/, '') + '/')) {
      const headers = { ...options.headers }; delete headers.Authorization;
      return fetch(url, { ...options, headers });
    }
    return fetch(url, options);
  };
  await collectSources({ links, directory, auth, resume: mode === 'resume', fetcher: guardedFetch });
}
