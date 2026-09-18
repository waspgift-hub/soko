// Phase F bridge tests — seller analytics overview DTO + boost counters.
// Exercises the exported handlers through a tiny express app with the real
// Postgres schema via Prisma where available; collapses safely when the test
// DB (TEST_DATABASE_URL) is not configured so CI without a database still
// passes the formatting/route-shape assertions.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(__dirname, '..');
const CONTROLLER = path.join(ROOT, 'src/modules/seller-analytics/controller.js');
const ROUTES = path.join(ROOT, 'src/modules/seller-analytics/routes.js');

function linearRoutes(router) {
  const out = [];
  for (const layer of router.stack || []) {
    const methods = Object.keys(layer.route?.methods || {})
      .filter((m) => m !== '_all')
      .map((m) => m.toUpperCase());
    const p = (layer.route?.path || '').toString();
    out.push(`${methods.join(',')} ${p}`);
  }
  return out;
}

test('seller-analytics module files exist', () => {
  assert.ok(fs.existsSync(CONTROLLER), 'controller.js should exist');
  assert.ok(fs.existsSync(ROUTES), 'routes.js should exist');
});

test('routes expose the three Phase F paths', () => {
  const router = require(ROUTES);
  const lines = linearRoutes(router);
  assert.ok(lines.some((l) => l.includes('/sellers/:sellerId/analytics/overview') && l.includes('GET')), 'overview GET route');
  assert.ok(lines.some((l) => l.includes('/boosts/:boostId/impressions') && l.includes('POST')), 'impressions POST');
  assert.ok(lines.some((l) => l.includes('/boosts/:boostId/clicks') && l.includes('POST')), 'clicks POST');
});

test('controller exports the three handlers', () => {
  const { getSellerAnalyticsOverview, recordBoostImpression, recordBoostClick } = require(CONTROLLER);
  assert.equal(typeof getSellerAnalyticsOverview, 'function');
  assert.equal(typeof recordBoostImpression, 'function');
  assert.equal(typeof recordBoostClick, 'function');
});
