const { test } = require('node:test');
const assert = require('node:assert/strict');

const { assertCanIssueOtp } = require('../src/modules/handover/handover-service');

const order = { id: 'or-1', buyerId: 'buyer-1', sellerId: 'seller-1' };

test('handover OTP issue is allowed for the order buyer', () => {
  assert.doesNotThrow(() => assertCanIssueOtp(order, { userId: 'buyer-1', role: 'seller' }));
});

test('handover OTP issue is allowed for admins', () => {
  assert.doesNotThrow(() => assertCanIssueOtp(order, { userId: 'admin-1', role: 'admin' }));
  assert.doesNotThrow(() => assertCanIssueOtp(order, { userId: 'super-1', role: 'super_admin' }));
});

test('handover OTP issue is forbidden for a stranger who knows the orderId', () => {
  // Regression: issueOtp previously handed the plaintext credential to any
  // authenticated caller — a data-exposure hole for a known order UUID.
  assert.throws(() => assertCanIssueOtp(order, { userId: 'seller-1', role: 'seller' }), {
    status: 403,
    message: 'FORBIDDEN',
  });
  assert.throws(() => assertCanIssueOtp(order, { userId: 'buyer-2', role: 'buyer' }), {
    status: 403,
    message: 'FORBIDDEN',
  });
});