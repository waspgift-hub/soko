// Subscription service: resolves effective entitlements for a user.
//
// The backend is the source of truth. The Flutter app may cache entitlements for
// responsiveness, but every protected operation must call resolveEntitlements()
// (or checkAiQuota()) on the server.
//
// Entitlements are derived from: (1) the user's subscription row, (2) the plan
// definition, (3) whether the subscription is in a usable state (active/trialing).
// If no subscription row exists, the user gets the free plan for their role.

const { getSubscription, getEntitlements, setEntitlements, getAiUsage, incrementAiUsage, todayKey } = require('./subscription-store');
const { planById, planForRole, aiQuotaForPlan, SUBSCRIPTION_STATUS } = require('./plans');
const { getFirebaseFirestore } = require('../../config/firebase');

async function getUserRole(userId) {
  const db = getFirebaseFirestore();
  if (!db) return 'buyer';
  try {
    const snap = await db.collection('users').doc(String(userId)).get();
    if (!snap.exists) return 'buyer';
    return snap.data().role || 'buyer';
  } catch {
    return 'buyer';
  }
}

const USABLE_STATUSES = new Set([SUBSCRIPTION_STATUS.ACTIVE, SUBSCRIPTION_STATUS.TRIALING]);

async function resolveEntitlements(userId) {
  const sub = await getSubscription({ userId });
  const role = await getUserRole(userId);

  let planId;
  let status = SUBSCRIPTION_STATUS.INACTIVE;

  if (sub && USABLE_STATUSES.has(sub.status)) {
    planId = sub.planId;
    status = sub.status;
  } else {
    planId = role === 'seller' ? 'seller_basic' : 'buyer';
  }

  const plan = planById(planId) || planById('buyer');
  const ent = {
    userId,
    planId: plan.id,
    planName: plan.name,
    priceTzs: plan.priceTzs,
    status,
    aiActionsPerDay: plan.aiActionsPerDay,
    features: plan.features,
    subscription: sub || null,
  };

  // Persist the resolved entitlement so the Flutter app can read it without
  // recomputing. This is a cache, not the source of truth — resolveEntitlements
  // always recomputes.
  await setEntitlements({ userId, planId: plan.id, aiActionsPerDay: plan.aiActionsPerDay, features: plan.features });

  return ent;
}

/**
 * Checks whether the user can perform an AI action. If yes, increments the
 * counter and returns { allowed: true, used, limit }. If no, returns
 * { allowed: false, used, limit } without incrementing.
 *
 * The increment happens AFTER the check, in the same transaction, so two
 * concurrent requests cannot both slip through at the limit.
 */
async function checkAiQuota(userId) {
  const ent = await resolveEntitlements(userId);
  const limit = ent.aiActionsPerDay;
  const dateKey = todayKey();
  const used = await getAiUsage({ userId, dateKey });

  if (used >= limit) {
    return { allowed: false, used, limit, planId: ent.planId };
  }

  const newCount = await incrementAiUsage({ userId, dateKey });
  return { allowed: true, used: newCount, limit, planId: ent.planId };
}

async function startTrial({ userId, planId }) {
  const { upsertSubscription } = require('./subscription-store');
  const plan = planById(planId);
  if (!plan || plan.priceTzs === 0) {
    throw Object.assign(new Error('INVALID_TRIAL_PLAN'), { status: 400, code: 'INVALID_TRIAL_PLAN' });
  }
  const existing = await getSubscription({ userId });
  if (existing && existing.status !== SUBSCRIPTION_STATUS.INACTIVE) {
    throw Object.assign(new Error('TRIAL_ALREADY_USED'), { status: 409, code: 'TRIAL_ALREADY_USED' });
  }
  const trialEndsAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
  const sub = await upsertSubscription({
    userId,
    planId,
    status: SUBSCRIPTION_STATUS.TRIALING,
    trialEndsAt,
  });
  await setEntitlements({ userId, planId, aiActionsPerDay: plan.aiActionsPerDay, features: plan.features });
  return sub;
}

module.exports = { resolveEntitlements, checkAiQuota, startTrial, getUserRole };