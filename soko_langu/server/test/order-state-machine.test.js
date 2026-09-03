const { test } = require('node:test');
const assert = require('node:assert');
const { OrderStateMachine, ORDER_STATES, STATE_TRANSITIONS, STATE_FINANCIAL_RULES } = require('../src/modules/orders/order-state-machine');

test('starts in DRAFT with correct financial rule', () => {
  const m = new OrderStateMachine();
  assert.strictEqual(m.state, ORDER_STATES.DRAFT);
  assert.strictEqual(m.getFinancialRule(), 'NO_UNAUTHORIZED_FINANCIAL_MOVEMENT');
});

test('valid transitions follow the state machine', () => {
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.DRAFT].includes(ORDER_STATES.PUBLISHED));
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.PUBLISHED].includes(ORDER_STATES.ADDRESS_REQUIRED));
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.ADDRESS_REQUIRED].includes(ORDER_STATES.PENDING_SHIPPING_FEE));
});

test('transition records history with financial rule', () => {
  const m = new OrderStateMachine(ORDER_STATES.DRAFT);
  const t = m.transition(ORDER_STATES.PUBLISHED, { actor: 'buyer', actorId: 'u1', reason: 'publish' });
  assert.strictEqual(m.state, ORDER_STATES.PUBLISHED);
  assert.strictEqual(t.from, ORDER_STATES.DRAFT);
  assert.strictEqual(t.to, ORDER_STATES.PUBLISHED);
  assert.strictEqual(t.financialRule, STATE_FINANCIAL_RULES[ORDER_STATES.PUBLISHED]);
  assert.strictEqual(m.history.length, 1);
});

test('rejects invalid transitions', () => {
  const m = new OrderStateMachine(ORDER_STATES.DRAFT);
  assert.throws(() => m.transition(ORDER_STATES.COMPLETED, {}), /Invalid order transition/);
});

test('CANNOT skip directly to IN_ESCROW from DRAFT', () => {
  const m = new OrderStateMachine(ORDER_STATES.DRAFT);
  assert.throws(() => m.transition(ORDER_STATES.IN_ESCROW, { actor: 'system' }), /Invalid order transition/);
});

test('funds can only release in settled states', () => {
  assert.strictEqual(OrderStateMachine.canReleaseFunds(ORDER_STATES.COMPLETED), true);
  assert.strictEqual(OrderStateMachine.canReleaseFunds(ORDER_STATES.WALLET_CREDITED), true);
  assert.strictEqual(OrderStateMachine.canReleaseFunds(ORDER_STATES.IN_ESCROW), false);
  assert.strictEqual(OrderStateMachine.canReleaseFunds(ORDER_STATES.DISPUTED), false);
});

test('protected states are recognized', () => {
  assert.strictEqual(OrderStateMachine.isProtectedState(ORDER_STATES.DISPUTED), true);
  assert.strictEqual(OrderStateMachine.isProtectedState(ORDER_STATES.REFUND_PENDING), true);
  assert.strictEqual(OrderStateMachine.isProtectedState(ORDER_STATES.IN_ESCROW), false);
});

test('isValidState recognizes real and rejects fake', () => {
  assert.strictEqual(OrderStateMachine.isValidState(ORDER_STATES.IN_TRANSIT), true);
  assert.strictEqual(OrderStateMachine.isValidState('NOPE'), false);
});
