'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  localDayKey,
  campaignId,
  isEligibleUser,
  pickRecommendation,
  buildMessages,
  validateOutbound,
} = require('../src/modules/engagement/daily-campaign');

test('campaign id is unique per user and local day', () => {
  assert.equal(campaignId('u1', '2026-10-28'), 'daily:u1:2026-10-28');
});

test('local day key uses Africa/Dar_es_Salaam by default', () => {
  const utcEvening = new Date('2026-10-27T22:30:00Z');
  assert.equal(localDayKey(utcEvening), '2026-10-28');
});

test('users who already opened the app today are not eligible', () => {
  const now = new Date('2026-10-28T10:00:00+03:00');
  const eligible = isEligibleUser({
    lastLoginAt: now,
    prefs: { marketing: true, daily_reminders: true },
    now,
  });
  assert.equal(eligible, false);
});

test('opted-out marketing users are not eligible', () => {
  const now = new Date('2026-10-28T10:00:00+03:00');
  const eligible = isEligibleUser({
    lastLoginAt: new Date('2026-10-27T10:00:00+03:00'),
    prefs: { marketing: false, daily_reminders: true },
    now,
  });
  assert.equal(eligible, false);
});

test('daily reminders are off until the user opts in', () => {
  const now = new Date('2026-10-28T10:00:00+03:00');
  const eligible = isEligibleUser({
    lastLoginAt: new Date('2026-10-27T10:00:00+03:00'),
    prefs: {},
    now,
  });
  assert.equal(eligible, false);
});

test('opted-in users who have not opened today are eligible', () => {
  const now = new Date('2026-10-28T10:00:00+03:00');
  const eligible = isEligibleUser({
    lastLoginAt: new Date('2026-10-27T10:00:00+03:00'),
    prefs: { daily_reminders: true, marketing: true },
    now,
  });
  assert.equal(eligible, true);
});

test('pickRecommendation skips purchased and dismissed products', () => {
  const rec = pickRecommendation({
    products: [
      { id: 'a', title: 'A', price: 1000, status: 'active' },
      { id: 'b', title: 'B', price: 2000, status: 'active' },
    ],
    viewedIds: ['a', 'b'],
    purchasedIds: ['a'],
    dismissedIds: [],
  });
  assert.equal(rec.type, 'product');
  assert.equal(rec.product.id, 'b');
});

test('insufficient product evidence falls back to a feature message', () => {
  const rec = pickRecommendation({ products: [] });
  assert.equal(rec.type, 'feature');
  const msg = buildMessages({ locale: 'sw', feature: rec.feature });
  assert.equal(msg.destination, '/search');
  assert.equal(validateOutbound(msg), true);
});

test('outbound messages reject script and absolute URLs', () => {
  assert.equal(validateOutbound({
    subject: 'Hi',
    pushTitle: 'Hi',
    pushBody: 'x',
    emailBody: '<script>alert(1)</script>',
    destination: '/search',
  }), false);
  assert.equal(validateOutbound({
    subject: 'Hi',
    pushTitle: 'Hi',
    pushBody: 'x',
    destination: 'https://evil.example',
  }), false);
});
