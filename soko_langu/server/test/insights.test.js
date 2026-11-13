'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { buildFacts, templateSummary, maybePolish } = require('../src/modules/admin/insights');

test('buildFacts copies dashboard numbers and does not invent extras', () => {
  const facts = buildFacts({
    kpis: { users: 12, newUsersToday: 2, orders: 4, completedOrders: 1, products: 9, commissionRevenue: 500, escrowHeld: 100, activeDisputes: 3 },
    metrics: { gmv: 900, withdrawalsPending: 1 },
    generatedAt: '2026-10-28T00:00:00.000Z',
  });
  assert.equal(facts.users, 12);
  assert.equal(facts.gmvTzs, 900);
  assert.equal(facts.disputesOpen, 3);
  assert.ok(facts.sources.includes('adminService.getDashboard'));
});

test('template summary includes the reporting timestamp', () => {
  const facts = buildFacts({ kpis: { users: 1 }, metrics: {}, generatedAt: 'stamp' });
  const out = templateSummary(facts);
  assert.match(out.summary, /stamp/);
  assert.equal(out.aiUsed, false);
});

test('maybePolish keeps template numbers if the model invents nothing usable', async () => {
  const facts = buildFacts({ kpis: { users: 7 }, metrics: {}, generatedAt: 't' });
  const out = await maybePolish(facts, async () => 'As an AI I cannot access your database');
  assert.equal(out.aiUsed, false);
  assert.match(out.summary, /Watumiaji 7/);
});
