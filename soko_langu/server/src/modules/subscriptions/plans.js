// Plan definitions for Soko Vibe subscriptions.
//
// Hard-coded here rather than in Firestore because the plans are a product
// decision that ships with a release, not an operator-tunable value. A plan
// change needs a deploy and a migration of existing subscribers, so it should
// never be editable at runtime by an admin who can fat-finger it. If operator
// tuning becomes necessary, move these to a `plans` collection with a seed script
// and a version field, and keep this file as the fallback default.
//
// All monetary values are TZS (integer) — the marketplace's currency, and a
// number that fits a JS safe integer.

const PLANS = {
  buyer: {
    id: 'buyer',
    name: 'Buyer / Normal',
    priceTzs: 0,
    billingCycle: 'free',
    aiActionsPerDay: 5,
    features: ['browse', 'search', 'favorites', 'buyer_requests', 'flash_sales', 'basic_chat', 'notifications'],
  },
  seller_basic: {
    id: 'seller_basic',
    name: 'Seller Basic',
    priceTzs: 0,
    billingCycle: 'free',
    aiActionsPerDay: 5,
    features: ['seller_profile', 'product_listings', 'order_management', 'basic_analytics', 'notifications', 'ai_basic'],
  },
  seller_plus: {
    id: 'seller_plus',
    name: 'Seller Plus',
    priceTzs: 14900,
    billingCycle: 'monthly',
    aiActionsPerDay: 50,
    features: ['seller_basic', 'advanced_analytics', 'priority_support', 'priority_ai', 'seller_productivity_tools', 'subscription_badge'],
  },
  seller_pro: {
    id: 'seller_pro',
    name: 'Seller Pro',
    priceTzs: 29900,
    billingCycle: 'monthly',
    aiActionsPerDay: 200,
    features: ['seller_plus', 'advanced_analytics_pro', 'higher_quotas', 'premium_reporting'],
  },
  business: {
    id: 'business',
    name: 'Business',
    priceTzs: 79900,
    billingCycle: 'monthly',
    aiActionsPerDay: 500,
    features: ['seller_pro', 'business_tools', 'team_management', 'business_analytics', 'business_reporting'],
  },
};

// Subscription states. Kept as string constants so a typo is a compile-time
// (well, lint-time) error rather than a silently-wrong state in Firestore.
const SUBSCRIPTION_STATUS = {
  INACTIVE: 'inactive',
  TRIALING: 'trialing',
  PENDING_PAYMENT: 'pending_payment',
  ACTIVE: 'active',
  PAST_DUE: 'past_due',
  CANCEL_PENDING: 'cancel_pending',
  EXPIRED: 'expired',
  SUSPENDED: 'suspended',
  PAYMENT_FAILED: 'payment_failed',
};

// Valid transitions. Anything not listed is rejected by `transition()`.
const VALID_TRANSITIONS = {
  inactive: ['trailing', 'pending_payment', 'active'],
  trailing: ['active', 'expired', 'pending_payment'],
  pending_payment: ['active', 'payment_failed', 'expired'],
  active: ['cancel_pending', 'past_due', 'suspended', 'expired'],
  past_due: ['active', 'expired', 'suspended'],
  cancel_pending: ['expired', 'active'],
  expired: ['pending_payment', 'active'],
  suspended: ['active', 'expired'],
  payment_failed: ['pending_payment', 'expired'],
};

function planById(id) {
  return PLANS[id] || null;
}

function planForRole(role) {
  // Buyers and unverified sellers are on the free buyer plan. A seller who has
  // not subscribed is on seller_basic, not buyer — the distinction matters for
  // which AI quota applies.
  if (role === 'seller' || role === 'admin' || role === 'super_admin') {
    return PLANS.seller_basic;
  }
  return PLANS.buyer;
}

function aiQuotaForPlan(planId) {
  const plan = PLANS[planId];
  return plan ? plan.aiActionsPerDay : 5;
}

module.exports = { PLANS, SUBSCRIPTION_STATUS, VALID_TRANSITIONS, planById, planForRole, aiQuotaForPlan };