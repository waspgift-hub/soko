const { describe, it } = require('node:test');
const assert = require('node:assert/strict');

// Test plan definitions
const { PLANS, aiQuotaForPlan, planById } = require('../src/modules/subscriptions/plans');

describe('subscription plans', () => {
  it('defines all five plans', () => {
    assert.ok(PLANS.buyer);
    assert.ok(PLANS.seller_basic);
    assert.ok(PLANS.seller_plus);
    assert.ok(PLANS.seller_pro);
    assert.ok(PLANS.business);
  });

  it('seller_plus has 50 AI actions/day', () => {
    assert.equal(aiQuotaForPlan('seller_plus'), 50);
  });

  it('business has 500 AI actions/day', () => {
    assert.equal(aiQuotaForPlan('business'), 500);
  });

  it('buyer has 5 AI actions/day', () => {
    assert.equal(aiQuotaForPlan('buyer'), 5);
  });

  it('planById returns null for unknown', () => {
    assert.equal(planById('nonexistent'), null);
  });
});

// Test title generator
const { generateTitle, isUsefulFirstMessage } = require('../src/modules/ai/chat/title-generator');
describe('title generator', () => {
  it('generates Advertising for advertising question', () => {
    assert.equal(generateTitle('How do I advertise my store?'), 'Advertising');
  });

  it('rejects greeting as useful first message', () => {
    assert.equal(isUsefulFirstMessage('hi'), false);
  });

  it('accepts real question as useful', () => {
    assert.equal(isUsefulFirstMessage('How do I advertise my store?'), true);
  });
});

// Test memory extractor
const { extract, isSensitiveText, isForbiddenKey } = require('../src/modules/ai/chat/memory-extractor');
describe('memory extractor', () => {
  it('extracts preferred language from explicit instruction', () => {
    const result = extract([{ role: 'user', content: 'Please always reply in Swahili.' }]);
    assert.ok(result.some((r) => r.key === 'preferred_language' && r.value === 'Swahili'));
  });

  it('detects sensitive text', () => {
    assert.equal(isSensitiveText('my password is hunter2'), true);
    assert.equal(isSensitiveText('hello world'), false);
  });

  it('forbids sensitive keys', () => {
    assert.equal(isForbiddenKey('religion'), true);
    assert.equal(isForbiddenKey('preferred_language'), false);
  });
});

// Test redact
const { redactSecrets, hasSecrets } = require('../src/modules/ai/chat/redact');
describe('redact', () => {
  it('redacts password', () => {
    const out = redactSecrets('my password is hunter2');
    assert.ok(out.includes('[redacted]'));
    assert.ok(!out.includes('hunter2'));
  });

  it('hasSecrets returns false for clean text', () => {
    assert.equal(hasSecrets('hello world'), false);
  });
});