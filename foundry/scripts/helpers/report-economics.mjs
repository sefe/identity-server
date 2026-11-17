// Dated reference prices, not a billing integration. No network calls when reporting.
export const copilotPricing = {
  currency: 'USD', checkedAt: '2026-11-12',
  source: 'https://docs.github.com/en/copilot/reference/copilot-billing/models-and-pricing',
  unit: 'USD per million tokens',
  models: {
    'claude-opus-5.5': { input: 4, cached: .2, cacheWrite: 5, output: 20 },
    'gpt-6-astra': { input: 10, cached: 1, cacheWrite: 12.5, output: 50, long: { input: 20, cached: 2, cacheWrite: 25, output: 75 } },
    'gpt-6.1-sol': { input: 2, cached: .1, cacheWrite: 2.5, output: 10, long: { input: 4, cached: .2, cacheWrite: 5, output: 15 } },
    'gemini-4-argon': { input: 2, cached: .1, output: 10, validThrough: '2026-11-30' },
    'gemini-3.8-flash': { input: .75, cached: .075, output: 3.75, validThrough: '2026-12-31' },
    // Retain previous model rates for historical run receipts and regression fixtures.
    'claude-opus-5': { input: 5, cached: .5, cacheWrite: 6.25, output: 25 },
    'gpt-5.6-sol': { input: 4, cached: .4, cacheWrite: 5, output: 20, long: { input: 8, cached: .8, cacheWrite: 10, output: 30 } },
    'gemini-3.7-flash': { input: .75, cached: .075, output: 3.75, validThrough: '2026-12-31' }
  }
};
const number = n => Number.isSafeInteger(n) && n >= 0;
export function priceInvocation(record, date = copilotPricing.checkedAt) {
  const rates = copilotPricing.models[record.model], u = record.usage ?? {};
  if (record.provider !== 'copilot-cli' || !rates || (rates.validThrough && date > rates.validThrough)) return null;
  const upper = rates.long ?? rates, measured = u.source === 'provider';
  if (measured && number(u.inputTokens) && number(u.outputTokens) && (!number(u.totalTokens) || u.totalTokens === u.inputTokens + u.outputTokens)) {
    const cacheKnown = number(u.cachedInputTokens) && u.cachedInputTokens <= u.inputTokens;
    const cachedLow = cacheKnown ? u.cachedInputTokens : u.inputTokens;
    const cachedHigh = cacheKnown ? u.cachedInputTokens : 0;
    // A CLI invocation spans multiple requests; its total does not identify
    // each request's context tier or ordinary input versus cache creation.
    return {
      low: ((u.inputTokens - cachedLow) * rates.input + cachedLow * rates.cached + u.outputTokens * rates.output) / 1e6,
      high: ((u.inputTokens - cachedHigh) * Math.max(upper.input, upper.cacheWrite ?? 0) + cachedHigh * upper.cached + u.outputTokens * upper.output) / 1e6,
      basis: 'reported-breakdown', input: u.inputTokens, output: u.outputTokens, cached: cacheKnown ? u.cachedInputTokens : null
    };
  }
  const tokens = measured && number(u.totalTokens) ? u.totalTokens : Math.ceil(((record.request?.bytes ?? 0) + (record.response?.bytes ?? 0)) / 4);
  if (!number(tokens) || tokens === 0) return null;
  return { low: tokens * Math.min(rates.input, rates.cached, rates.output) / 1e6,
    high: tokens * Math.max(upper.input, upper.cacheWrite ?? 0, upper.output) / 1e6,
    basis: measured && number(u.totalTokens) ? 'reported-total-only' : 'payload-estimate' };
}
export function estimateEconomics(records, date = copilotPricing.checkedAt) {
  const result = { currency: 'USD', kind: 'reference-estimate', pricing: copilotPricing, asOf: date,
    low: 0, high: 0, pricedCalls: 0, unpricedCalls: 0, estimatedCalls: 0, byModel: [], activeCallHours: 0, observedSpanHours: null,
    market: { low: 20, high: 60, currency: 'USD', unit: 'hour', checkedAt: '2026-09-22', source: 'https://www.upwork.com/hire/qa-engineers/cost/', description: 'Worldwide historical QA engineering contracts on Upwork; not a universal salary or fully loaded enterprise cost.' },
    limits: [
      'Reference usage value at the displayed Copilot prices, not an invoice or the amount charged after subscription allowances.',
      'The range accounts for missing cache-write detail and per-request context tiers. Cached input is counted once.',
      'Total-only and payload-based records have wider bounds. Unknown or expired model prices and calls without records are excluded.',
      'This run only, including recorded retries and resumed legs. Foundry development and other independent runs are excluded.',
      'CI infrastructure, subscriptions, taxes and human supervision are excluded from the AI usage estimate.',
      'Call-hours can overlap; the observed calendar span can include pauses. Neither is measured human effort saved.'
    ] };
  const seen = new Set(), groups = new Map(), starts = [], ends = [];
  for (const r of records) {
    if (!r.id || !r.startedAt || r.provider === 'mock') continue;
    const id = r.id + '\0' + r.startedAt; if (seen.has(id)) continue; seen.add(id);
    const start = Date.parse(r.startedAt);
    if (Number.isFinite(start) && Number.isFinite(r.durationMs) && r.durationMs >= 0) { starts.push(start); ends.push(start + r.durationMs); result.activeCallHours += r.durationMs / 3600000; }
    const price = priceInvocation(r, date);
    if (!groups.has(r.model)) groups.set(r.model, { name: r.model ?? 'Unknown', low: 0, high: 0, pricedCalls: 0, unpricedCalls: 0, estimatedCalls: 0, inputTokens: 0, outputTokens: 0, cachedInputTokens: 0 });
    const group = groups.get(r.model);
    if (!price) { result.unpricedCalls++; group.unpricedCalls++; continue; }
    for (const target of [result, group]) { target.low += price.low; target.high += price.high; target.pricedCalls++; if (price.basis !== 'reported-breakdown') target.estimatedCalls++; }
    group.inputTokens += price.input ?? 0; group.outputTokens += price.output ?? 0; group.cachedInputTokens += price.cached ?? 0;
  }
  if (starts.length) result.observedSpanHours = (Math.max(...ends) - Math.min(...starts)) / 3600000;
  result.byModel = [...groups.values()];
  return result;
}
