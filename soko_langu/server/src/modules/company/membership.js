'use strict';

const { getFirebaseFirestore } = require('../../config/firebase');

const COLLECTION = 'company_memberships';

async function getMembership(firebaseUid) {
  if (!firebaseUid) return null;
  const db = getFirebaseFirestore();
  if (!db) return null;
  const snap = await db.collection(COLLECTION).doc(firebaseUid).get();
  if (!snap.exists) return null;
  return { id: snap.id, ...snap.data() };
}

async function upsertMembership(firebaseUid, data) {
  const db = getFirebaseFirestore();
  if (!db) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const ref = db.collection(COLLECTION).doc(firebaseUid);
  const existing = await ref.get();
  if (existing.exists) {
    await ref.update({ ...data, updated_at: now });
  } else {
    await ref.set({ ...data, created_at: now, updated_at: now });
  }
  const snap = await ref.get();
  return { id: snap.id, ...snap.data() };
}

// Middleware: attach req.companyMembership if a membership exists. Does not
// reject; routes decide whether membership is required.
async function loadCompanyMembership(req, res, next) {
  try {
    req.companyMembership = await getMembership(req.firebaseUid);
    next();
  } catch (e) {
    next(e);
  }
}

module.exports = { getMembership, upsertMembership, loadCompanyMembership, COLLECTION };
