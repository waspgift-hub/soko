'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { isBenignConnectError } = require('../src/config/redis');

test('duplicate ioredis connect errors are treated as benign', () => {
  assert.equal(
    isBenignConnectError(new Error('Redis is already connecting/connected')),
    true,
  );
  assert.equal(isBenignConnectError(new Error('ECONNREFUSED')), false);
});

test('finance workers are registered with locked-down names', () => {
  const { FINANCE_SCHEDULE } = require('../src/services/queue');
  const names = FINANCE_SCHEDULE.map((j) => j.name).sort();
  assert.deepEqual(names, [
    'finance.disputeEscalate',
    'finance.inspectionAutoRelease',
    'finance.paymentExpire',
    'finance.reconciliationRun',
    'finance.refundUnstuck',
    'finance.withdrawalProcess',
  ].sort());
});
