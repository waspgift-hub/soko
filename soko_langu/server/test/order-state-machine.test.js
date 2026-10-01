const { test } = require('node:test');
const assert = require('node:assert');
const { OrderStateMachine, ORDER_STATES, STATE_TRANSITIONS, STATE_FINANCIAL_RULES } = require('../src/modules/orders/order-state-machine');

test('starts in DRAFT with correct financial rule', () => {
  const m = new OrderStateMachine();
  assert.strictEqual(m.state, ORDER_STATES.DRAFT);
  assert.strictEqual(m.getFinancialRule(), 'NO_MOVEMENT');
});

test('valid payment transitions follow the state machine', () => {
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.PENDING_PAYMENT].includes(ORDER_STATES.PAYMENT_PROCESSING));
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.PAYMENT_PROCESSING].includes(ORDER_STATES.PAID));
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.PAID].includes(ORDER_STATES.ESCROW_HELD));
});

test('escrow-held orders can move to REFUND_PENDING', () => {
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.ESCROW_HELD].includes(ORDER_STATES.REFUND_PENDING));
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.READY_TO_DISPATCH].includes(ORDER_STATES.REFUND_PENDING));
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.REFUND_PENDING].includes(ORDER_STATES.REFUNDED));
});

test('transition records history with financial rule', () => {
  const m = new OrderStateMachine(ORDER_STATES.DRAFT);
  const t = m.transition(ORDER_STATES.PENDING_PAYMENT, { actor: 'system', actorId: 'u1', reason: 'publish' });
  assert.strictEqual(m.state, ORDER_STATES.PENDING_PAYMENT);
  assert.strictEqual(t.from, ORDER_STATES.DRAFT);
  assert.strictEqual(t.to, ORDER_STATES.PENDING_PAYMENT);
  assert.strictEqual(t.financialRule, STATE_FINANCIAL_RULES[ORDER_STATES.PENDING_PAYMENT]);
  assert.strictEqual(m.history.length, 1);
});

test('rejects invalid transitions', () => {
  const m = new OrderStateMachine(ORDER_STATES.DRAFT);
  assert.throws(() => m.transition(ORDER_STATES.COMPLETED, {}), /Invalid order transition/);
});

test('shipping quote flow cannot skip straight to a fulfilled state', () => {
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

test('payment failure can be retried into an escrow hold', () => {
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.PAYMENT_PENDING].includes(ORDER_STATES.FAILED));
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.FAILED].includes(ORDER_STATES.ESCROW_HELD));
});

test('a customer-side payment decline returns the order to a payable state', () => {
  // A ClickPesa USSD push fails when the buyer's wallet is short (measured live:
  // "You do not have enough balance to do this transaction"). The order must
  // come back to AWAITING_ESCROW_PAYMENT so the buyer can top up and tap Pay
  // again — before this edge existed the only exits from PAYMENT_PENDING were
  // FAILED (dead order) or a webhook that would never arrive.
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.PAYMENT_PENDING].includes(ORDER_STATES.AWAITING_ESCROW_PAYMENT));

  const m = new OrderStateMachine(ORDER_STATES.PAYMENT_PENDING);
  const t = m.transition(ORDER_STATES.AWAITING_ESCROW_PAYMENT, {
    actor: 'system',
    reason: 'Collection failed, retryable',
  });
  assert.strictEqual(m.state, ORDER_STATES.AWAITING_ESCROW_PAYMENT);
  // No money moved, so the order must not claim funds are protected or returned.
  assert.strictEqual(t.financialRule, STATE_FINANCIAL_RULES[ORDER_STATES.AWAITING_ESCROW_PAYMENT]);
  assert.notStrictEqual(t.financialRule, 'FUNDS_RETURNED');
  // And it must be payable again.
  assert.ok(STATE_TRANSITIONS[ORDER_STATES.AWAITING_ESCROW_PAYMENT].includes(ORDER_STATES.PAYMENT_PENDING));
});

test('a declined payment is never mistaken for funds returned', () => {
  // REFUNDED/REFUND_PENDING carry money meanings; the decline path must not
  // land on either of them.
  const declined = STATE_TRANSITIONS[ORDER_STATES.PAYMENT_PENDING];
  assert.ok(!declined.includes(ORDER_STATES.REFUNDED));
  assert.ok(!declined.includes(ORDER_STATES.REFUND_PENDING));
});