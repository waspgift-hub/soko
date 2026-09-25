/**
 * Canonical Soko Vibe order state machine.
 *
 * Database truth uses lowercase strings. Constants retain descriptive names so
 * calling code stays readable, while every persisted state uses one vocabulary.
 *
 * Financial invariant: no client may move money by changing order status.
 * Money movement is performed only by payment/escrow/refund services.
 */

const ORDER_STATES = Object.freeze({
  DRAFT: 'draft',
  PUBLISHED: 'published',
  ADDRESS_REQUIRED: 'address_required',
  PENDING_SHIPPING_FEE: 'pending_shipping_fee',
  SHIPPING_FEE_SUBMITTED: 'shipping_fee_submitted',
  SHIPPING_FEE_REVIEW: 'shipping_fee_review',
  AWAITING_ESCROW_PAYMENT: 'awaiting_escrow_payment',
  PAYMENT_PENDING: 'payment_pending',
  PAYMENT_PROCESSING: 'payment_processing',
  PAID: 'paid',
  ESCROW_HELD: 'in_escrow',
  IN_ESCROW: 'in_escrow',
  SELLER_ACCEPTED: 'seller_accepted',
  DISPATCH_READY: 'ready_to_dispatch',
  READY_TO_DISPATCH: 'ready_to_dispatch',
  DISPATCHED: 'dispatched',
  IN_TRANSIT: 'in_transit',
  OUT_FOR_DELIVERY: 'out_for_delivery',
  DELIVERY_ATTEMPTED: 'delivery_attempted',
  ARRIVED: 'arrived',
  DELIVERED: 'delivered',
  INSPECTION_PERIOD: 'inspection_period',
  OTP_PENDING: 'otp_pending',
  DELIVERY_CONFIRMED: 'delivery_confirmed',
  COMPLETED: 'completed',
  WALLET_CREDITED: 'wallet_credited',
  PAYOUT_PENDING: 'payout_pending',
  PAYOUT_COMPLETE: 'payout_complete',
  PAYMENT_FAILED: 'failed',
  FAILED: 'failed',
  CANCELLED: 'cancelled',
  REFUND_PENDING: 'refund_pending',
  REFUNDED: 'refunded',
  DISPUTED: 'disputed',
  EXPIRED: 'expired',
});

const STATE_TRANSITIONS = Object.freeze({
  draft: ['published', 'address_required', 'cancelled', 'expired'],
  published: ['address_required', 'pending_shipping_fee', 'cancelled', 'expired'],
  address_required: ['pending_shipping_fee', 'cancelled'],
  pending_shipping_fee: ['shipping_fee_submitted', 'cancelled', 'expired'],
  shipping_fee_submitted: ['shipping_fee_review', 'awaiting_escrow_payment', 'cancelled'],
  shipping_fee_review: ['awaiting_escrow_payment', 'pending_shipping_fee', 'cancelled'],
  awaiting_escrow_payment: ['payment_pending', 'payment_processing', 'cancelled', 'expired', 'failed'],
  payment_pending: ['payment_processing', 'in_escrow', 'cancelled', 'expired', 'failed'],
  payment_processing: ['paid', 'in_escrow', 'cancelled', 'failed'],
  paid: ['in_escrow', 'cancelled', 'refund_pending'],
  in_escrow: ['seller_accepted', 'ready_to_dispatch', 'disputed', 'refund_pending', 'cancelled'],
  seller_accepted: ['ready_to_dispatch', 'disputed', 'cancelled'],
  ready_to_dispatch: ['dispatched', 'disputed', 'refund_pending', 'cancelled'],
  dispatched: ['in_transit', 'delivered', 'disputed'],
  in_transit: ['out_for_delivery', 'arrived', 'delivery_attempted', 'delivered', 'disputed'],
  out_for_delivery: ['delivery_attempted', 'arrived', 'delivered', 'disputed'],
  delivery_attempted: ['out_for_delivery', 'arrived', 'delivered', 'disputed'],
  arrived: ['delivered', 'disputed'],
  delivered: ['inspection_period', 'delivery_confirmed', 'disputed'],
  inspection_period: ['otp_pending', 'delivery_confirmed', 'completed', 'disputed', 'refund_pending'],
  otp_pending: ['completed', 'disputed', 'refund_pending'],
  delivery_confirmed: ['completed', 'disputed'],
  completed: ['wallet_credited', 'disputed'],
  wallet_credited: ['payout_pending', 'completed'],
  payout_pending: ['payout_complete'],
  payout_complete: [],
  failed: ['payment_pending', 'cancelled'],
  cancelled: [],
  refund_pending: ['refunded', 'in_escrow'],
  refunded: [],
  disputed: ['completed', 'refund_pending', 'cancelled'],
  expired: [],
});

const STATE_FINANCIAL_RULES = Object.freeze({
  draft: 'NO_FINANCIAL_MOVEMENT',
  published: 'NO_FINANCIAL_MOVEMENT',
  address_required: 'NO_FINANCIAL_MOVEMENT',
  pending_shipping_fee: 'NO_FINANCIAL_MOVEMENT',
  shipping_fee_submitted: 'NO_FINANCIAL_MOVEMENT',
  shipping_fee_review: 'NO_FINANCIAL_MOVEMENT',
  awaiting_escrow_payment: 'NO_FINANCIAL_MOVEMENT',
  payment_pending: 'NO_FINANCIAL_MOVEMENT',
  payment_processing: 'FUNDS_AT_PROVIDER',
  paid: 'FUNDS_CAPTURED',
  in_escrow: 'FUNDS_PROTECTED_IN_ESCROW',
  seller_accepted: 'FUNDS_PROTECTED_IN_ESCROW',
  ready_to_dispatch: 'FUNDS_PROTECTED_IN_ESCROW',
  dispatched: 'FUNDS_PROTECTED_IN_ESCROW',
  in_transit: 'FUNDS_PROTECTED_IN_ESCROW',
  out_for_delivery: 'FUNDS_PROTECTED_IN_ESCROW',
  delivery_attempted: 'FUNDS_PROTECTED_IN_ESCROW',
  arrived: 'FUNDS_PROTECTED_IN_ESCROW',
  delivered: 'FUNDS_PROTECTED_IN_ESCROW',
  inspection_period: 'FUNDS_PROTECTED_IN_ESCROW',
  otp_pending: 'FUNDS_PROTECTED_IN_ESCROW',
  delivery_confirmed: 'SETTLEMENT_AUTHORIZED',
  completed: 'SETTLEMENT_AUTHORIZED',
  wallet_credited: 'SETTLED_TO_WALLET',
  payout_pending: 'PAYOUT_PROCESSING',
  payout_complete: 'FUNDS_DISBURSED',
  failed: 'NO_FINANCIAL_MOVEMENT',
  cancelled: 'REFUND_IF_PAID',
  refund_pending: 'FUNDS_PROTECTED_OR_REFUNDING',
  refunded: 'FUNDS_RETURNED',
  disputed: 'FUNDS_LOCKED',
  expired: 'REFUND_IF_PAID',
});

const TRANSITION_ACTORS = Object.freeze({
  published: ['buyer', 'system'],
  address_required: ['buyer', 'system'],
  pending_shipping_fee: ['seller', 'system', 'admin'],
  shipping_fee_submitted: ['seller'],
  shipping_fee_review: ['seller', 'system'],
  awaiting_escrow_payment: ['buyer', 'admin', 'system'],
  payment_pending: ['buyer', 'system'],
  payment_processing: ['system', 'buyer'],
  paid: ['system'],
  in_escrow: ['system'],
  seller_accepted: ['seller', 'system'],
  ready_to_dispatch: ['seller', 'system', 'admin'],
  dispatched: ['seller'],
  in_transit: ['courier', 'system', 'seller'],
  out_for_delivery: ['courier', 'system'],
  delivery_attempted: ['courier', 'system'],
  arrived: ['courier', 'system'],
  delivered: ['courier', 'seller', 'system'],
  inspection_period: ['buyer', 'system'],
  otp_pending: ['buyer', 'system'],
  delivery_confirmed: ['buyer', 'system'],
  completed: ['system', 'admin'],
  wallet_credited: ['system'],
  payout_pending: ['system', 'admin'],
  payout_complete: ['system', 'admin'],
  failed: ['system'],
  cancelled: ['buyer', 'seller', 'admin', 'system'],
  refund_pending: ['admin', 'system'],
  refunded: ['system', 'admin'],
  disputed: ['buyer', 'seller', 'admin'],
  expired: ['system'],
});

const VALID_STATES = new Set(Object.values(ORDER_STATES));

class OrderStateMachine {
  constructor(state = ORDER_STATES.DRAFT) {
    this.state = normalizeState(state);
    this.history = [];
  }

  canTransition(toState) {
    const target = normalizeState(toState);
    return (STATE_TRANSITIONS[this.state] || []).includes(target);
  }

  transition(toState, { actor, actorId, reason } = {}) {
    const from = this.state;
    const target = normalizeState(toState);

    if (!this.canTransition(target)) {
      throw new Error(`Invalid order transition: ${from} -> ${target}`);
    }

    const allowedActors = TRANSITION_ACTORS[target] || [];
    if (actor && !allowedActors.includes(actor)) {
      throw new Error(`Actor ${actor} cannot transition to ${target}`);
    }

    this.state = target;
    const event = {
      from,
      to: target,
      financialRule: STATE_FINANCIAL_RULES[target],
      actor: actor || null,
      actorId: actorId || null,
      reason: reason || null,
      timestamp: new Date().toISOString(),
    };
    this.history.push(event);
    return event;
  }

  getFinancialRule() {
    return STATE_FINANCIAL_RULES[this.state];
  }

  static getFinancialRule(state) {
    return STATE_FINANCIAL_RULES[normalizeState(state)];
  }

  static canReleaseFunds(state) {
    return ['delivery_confirmed', 'completed'].includes(normalizeState(state));
  }

  static isProtectedState(state) {
    return ['disputed', 'refund_pending'].includes(normalizeState(state));
  }

  static isValidState(state) {
    return VALID_STATES.has(normalizeState(state));
  }
}

function normalizeState(value) {
  const raw = String(value || '').trim();
  if (VALID_STATES.has(raw)) return raw;
  const lower = raw.toLowerCase();
  if (VALID_STATES.has(lower)) return lower;
  return raw;
}

module.exports = {
  ORDER_STATES,
  STATE_TRANSITIONS,
  STATE_FINANCIAL_RULES,
  TRANSITION_ACTORS,
  OrderStateMachine,
};
