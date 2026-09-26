const { test } = require('node:test');
const assert = require('node:assert/strict');
const { OrderStateMachine, ORDER_STATES, canonicalizeState } = require('../src/modules/orders/order-state-machine');

test('canonicalizes legacy order states', () => {
  assert.equal(canonicalizeState('pending'), ORDER_STATES.AWAITING_SELLER_SHIPPING);
  assert.equal(canonicalizeState('quoted'), ORDER_STATES.AWAITING_PAYMENT);
  assert.equal(canonicalizeState('escrow_hold'), ORDER_STATES.PAID_IN_ESCROW);
  assert.equal(canonicalizeState('delivered'), ORDER_STATES.DELIVERED_PENDING_CONFIRMATION);
});

test('happy path follows the UI journey', () => {
  const m = new OrderStateMachine('pending');
  m.transition(ORDER_STATES.AWAITING_PAYMENT, { actor: 'seller' });
  m.transition(ORDER_STATES.PAYMENT_PROCESSING, { actor: 'buyer' });
  m.transition(ORDER_STATES.PAID_IN_ESCROW, { actor: 'system' });
  m.transition(ORDER_STATES.READY_FOR_DISPATCH, { actor: 'seller' });
  m.transition(ORDER_STATES.DISPATCHED, { actor: 'seller' });
  m.transition(ORDER_STATES.DELIVERED_PENDING_CONFIRMATION, { actor: 'courier' });
  m.transition(ORDER_STATES.COMPLETED, { actor: 'buyer' });
  assert.equal(m.state, ORDER_STATES.COMPLETED);
});

test('invalid financial shortcuts are rejected', () => {
  const m = new OrderStateMachine(ORDER_STATES.AWAITING_SELLER_SHIPPING);
  assert.equal(m.canTransition(ORDER_STATES.PAID_IN_ESCROW), false);
  assert.throws(() => m.transition(ORDER_STATES.PAID_IN_ESCROW, { actor: 'system' }), /INVALID_ORDER_TRANSITION/);
});
