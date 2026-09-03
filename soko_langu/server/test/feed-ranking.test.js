const { test } = require('node:test');
const assert = require('node:assert');
const { rankItem, WEIGHTS } = require('../src/modules/feed/feed-ranking');

test('weights sum to 1', () => {
  const sum = Object.values(WEIGHTS).reduce((a, b) => a + b, 0);
  assert.ok(Math.abs(sum - 1) < 1e-9);
});

test('high all signals scores high', () => {
  const score = rankItem({
    watchTime: 1,
    completionRate: 1,
    productClickRate: 1,
    purchaseSignal: 1,
    shareRate: 1,
    engagementRate: 1,
    createdAt: new Date(),
  });
  assert.ok(score > 0.8);
});

test('low signals score low', () => {
  const score = rankItem({
    watchTime: 0,
    completionRate: 0,
    productClickRate: 0,
    purchaseSignal: 0,
    shareRate: 0,
    engagementRate: 0,
    createdAt: new Date('2030-01-01T00:00:00Z'), // very old -> zero freshness
  });
  assert.ok(score < 0.1);
});

test('clamps inputs to 0..1', () => {
  const score = rankItem({ watchTime: 999, createdAt: new Date() });
  assert.ok(score <= WEIGHTS.watchTime + WEIGHTS.freshness + 0.001);
});

test('fresh content outperforms stale with equal signals', () => {
  const fresh = rankItem({ engagementRate: 0.5, createdAt: new Date() });
  const stale = rankItem({ engagementRate: 0.5, createdAt: new Date('2020-01-01T00:00:00Z') });
  assert.ok(fresh > stale);
});
