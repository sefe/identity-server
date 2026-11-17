import { test } from 'node:test';
import assert from 'node:assert/strict';
import { priceInvocation, estimateEconomics } from '../../scripts/helpers/report-economics.mjs';

const record = { id: 'call', startedAt: '2026-09-13T10:00:00Z', durationMs: 3600000, provider: 'copilot-cli', model: 'claude-opus-5',
  usage: { source: 'provider', inputTokens: 1000000, cachedInputTokens: 800000, outputTokens: 100000, totalTokens: 1100000 } };
test('pricing subtracts cached input once and bounds unknown cache writes', () => {
  const p = priceInvocation(record);
  assert.equal(p.low, 3.9); // 0.2M * $5 + 0.8M * $0.5 + 0.1M * $25
  assert.equal(p.high, 4.15); // uncached input could include cache creation at $6.25
  assert.equal(p.basis, 'reported-breakdown');
});
test('request tier ambiguity widens a Sol estimate instead of pricing aggregate context as one call', () => {
  const p = priceInvocation({ ...record, model: 'gpt-5.6-sol' });
  assert.equal(p.low, 3.12); assert.equal(p.high, 5.64);
});

test('current profile models retain priced usage with cache and long-context bounds', () => {
  for (const [model, low, high] of [
    ['claude-opus-5.5', 2.96, 3.16],
    ['gpt-6-astra', 7.8, 14.1],
    ['gpt-6.1-sol', 1.48, 2.66],
    ['gemini-4-argon', 1.48, 1.48],
    ['gemini-3.8-flash', .585, .585]
  ]) {
    const price = priceInvocation({ ...record, model }, '2026-11-12');
    assert.ok(price, `${model} must have known pricing`);
    assert.ok(Math.abs(price.low - low) < 1e-9, `${model}: lower estimate`);
    assert.ok(Math.abs(price.high - high) < 1e-9, `${model}: upper estimate`);
  }
  assert.equal(priceInvocation({ ...record, model: 'gemini-3.8-flash' }, '2027-01-01'), null);
  assert.ok(priceInvocation({ ...record, model: 'gemini-4-argon' }, '2026-11-30'));
  assert.equal(priceInvocation({ ...record, model: 'gemini-4-argon' }, '2026-12-01'), null);
});
test('unknown providers, unknown models and expired promotions remain unpriced', () => {
  assert.equal(priceInvocation({ ...record, provider: 'direct-api' }), null);
  assert.equal(priceInvocation({ ...record, model: 'unknown' }), null);
  assert.equal(priceInvocation({ ...record, model: 'gemini-3.7-flash' }, '2027-01-01'), null);
});
test('missing token split and missing cache detail produce explicit ranges', () => {
  const total = priceInvocation({ ...record, usage: { source: 'provider', totalTokens: 1000000 } });
  assert.equal(total.low, .5); assert.equal(total.high, 25); assert.equal(total.basis, 'reported-total-only');
  const cached = priceInvocation({ ...record, usage: { source: 'provider', inputTokens: 1000000, outputTokens: 0 } });
  assert.equal(cached.low, .5); assert.equal(cached.high, 6.25);
  const estimated = priceInvocation({ ...record, usage: null, request: { bytes: 400 }, response: { bytes: 40 } });
  assert.equal(estimated.basis, 'payload-estimate'); assert.ok(estimated.low > 0 && estimated.high > estimated.low);
});
test('cost aggregation deduplicates restored calls, includes retries, and keeps unknown costs visible', () => {
  const result = estimateEconomics([record, record, { ...record, startedAt: '2026-09-13T12:00:00Z' }, { ...record, id: 'unknown', model: 'new-model' }, { ...record, id: 'simulated', provider: 'mock' }]);
  assert.equal(result.pricedCalls, 2); assert.equal(result.unpricedCalls, 1);
  assert.equal(result.low, 7.8); assert.equal(result.high, 8.3);
  assert.equal(result.observedSpanHours, 3); assert.equal(result.activeCallHours, 3);
  assert.equal(result.byModel.find(m => m.name === 'new-model').pricedCalls, 0);
});
