// Firestore data access for subscriptions, entitlements and AI usage.
//
// Follows the same pattern as chat-store.js: Admin SDK directly, ownership
// enforced in every function, ISO timestamps for lexicographic ordering.

const crypto = require('crypto');
const { getFirebaseFirestore } = require('../../config/firebase');

const COLLECTIONS = {
  subscriptions: 'ai_subscriptions',
  entitlements: 'ai_entitlements',
  usage: 'ai_usage',
};

function httpError(status, code) {
  const e = new Error(code);
  e.status = status;
  e.code = code;
  return e;
}

function requireStore() {
  const db = getFirebaseFirestore();
  if (!db) throw httpError(503, 'SUBSCRIPTION_STORE_UNAVAILABLE');
  return db;
}

function nowIso() {
  return new Date().toISOString();
}

function todayKey(tz = 'Africa/Dar_es_Salaam') {
  // YYYY-MM-DD in the configured timezone. Using Intl rather than a date lib so
  // there is no dependency to keep in sync with the server's tzdata.
  const fmt = new Intl.DateTimeFormat('en-CA', {
    timeZone: tz,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  });
  return fmt.format(new Date());
}

async function getSubscription({ userId }) {
  const db = requireStore();
  const snap = await db.collection(COLLECTIONS.subscriptions).doc(String(userId)).get();
  if (!snap.exists) return null;
  return { id: snap.id, ...snap.data() };
}

async function upsertSubscription({ userId, planId, status, trialEndsAt = null, currentPeriodEnd = null }) {
  const db = requireStore();
  const ref = db.collection(COLLECTIONS.subscriptions).doc(String(userId));
  const now = nowIso();
  const doc = {
    userId,
    planId,
    status,
    trialEndsAt,
    currentPeriodEnd,
    updatedAt: now,
  };
  const existing = await ref.get();
  if (!existing.exists) doc.createdAt = now;
  await ref.set(doc, { merge: true });
  return { id: ref.id, ...doc };
}

async function getEntitlements({ userId }) {
  const db = requireStore();
  const snap = await db.collection(COLLECTIONS.entitlements).doc(String(userId)).get();
  if (!snap.exists) return null;
  return { id: snap.id, ...snap.data() };
}

async function setEntitlements({ userId, planId, aiActionsPerDay, features = [] }) {
  const db = requireStore();
  const ref = db.collection(COLLECTIONS.entitlements).doc(String(userId));
  await ref.set({
    userId,
    planId,
    aiActionsPerDay,
    features,
    updatedAt: nowIso(),
  }, { merge: true });
  return { id: ref.id, userId, planId, aiActionsPerDay, features };
}

/**
 * Atomically increments AI usage for today and returns the new count.
 *
 * Uses a Firestore transaction so concurrent requests cannot both pass the quota
 * check. Firestore transactions are OCC (optimistic concurrency control) — if two
 * requests race, one retries. This is the correct primitive here; a plain read-then-
 * write would let both through.
 */
async function incrementAiUsage({ userId, dateKey }) {
  const db = requireStore();
  const key = `${userId}_${dateKey}`;
  const ref = db.collection(COLLECTIONS.usage).doc(key);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.exists ? (Number(snap.data().count) || 0) : 0;
    const next = current + 1;
    tx.set(ref, {
      userId,
      dateKey,
      count: next,
      updatedAt: nowIso(),
    }, { merge: true });
    return next;
  });
}

async function getAiUsage({ userId, dateKey }) {
  const db = requireStore();
  const key = `${userId}_${dateKey}`;
  const snap = await db.collection(COLLECTIONS.usage).doc(key).get();
  if (!snap.exists) return 0;
  return Number(snap.data().count) || 0;
}

module.exports = {
  COLLECTIONS,
  getSubscription,
  upsertSubscription,
  getEntitlements,
  setEntitlements,
  incrementAiUsage,
  getAiUsage,
  todayKey,
  httpError,
  requireStore,
};