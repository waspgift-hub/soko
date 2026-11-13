'use strict';

const crypto = require('crypto');

function firestore() {
  return require('../../config/firebase').getFirebaseFirestore();
}

const MAX_HASHES = 200;

function discoverySecret() {
  return process.env.CONTACT_DISCOVERY_HMAC_SECRET || '';
}

function normalizePhone(raw) {
  const digits = String(raw || '').replace(/\D/g, '');
  if (!digits) return '';
  if (digits.startsWith('255') && digits.length >= 12) return digits;
  if (digits.startsWith('0') && digits.length === 10) return `255${digits.slice(1)}`;
  if (digits.length === 9) return `255${digits}`;
  return digits;
}

function hmacPhone(phone, secret) {
  return crypto.createHmac('sha256', secret).update(normalizePhone(phone)).digest('hex');
}

async function optIn(uid, phone) {
  const secret = discoverySecret();
  if (!secret) {
    const err = new Error('CONTACT_DISCOVERY_UNCONFIGURED');
    err.status = 503;
    throw err;
  }
  const hash = hmacPhone(phone, secret);
  if (!hash) {
    const err = new Error('PHONE_REQUIRED');
    err.status = 400;
    throw err;
  }
  const db = firestore();
  const userRef = db.collection('contact_discovery_opt_in').doc(uid);
  const prev = await userRef.get();
  const prevHash = prev.exists ? prev.data().phoneHash : null;

  const batch = db.batch();
  if (prevHash && prevHash !== hash) {
    batch.delete(db.collection('contact_hash_index').doc(prevHash).collection('users').doc(uid));
  }
  batch.set(userRef, {
    enabled: true,
    phoneHash: hash,
    updatedAt: new Date(),
  });
  batch.set(db.collection('contact_hash_index').doc(hash).collection('users').doc(uid), {
    uid,
    updatedAt: new Date(),
  });
  await batch.commit();
  return { enabled: true };
}

async function optOut(uid) {
  const db = firestore();
  const userRef = db.collection('contact_discovery_opt_in').doc(uid);
  const prev = await userRef.get();
  const batch = db.batch();
  if (prev.exists && prev.data().phoneHash) {
    batch.delete(
      db.collection('contact_hash_index').doc(prev.data().phoneHash).collection('users').doc(uid),
    );
  }
  batch.set(userRef, { enabled: false, phoneHash: null, updatedAt: new Date() });
  await batch.commit();
  return { enabled: false };
}

async function status(uid) {
  const db = firestore();
  const snap = await db.collection('contact_discovery_opt_in').doc(uid).get();
  return { enabled: snap.exists ? snap.data().enabled === true : false };
}

async function matchPhones(uid, phones, deps = {}) {
  const secret = deps.secret !== undefined ? deps.secret : discoverySecret();
  if (!secret) {
    const err = new Error('CONTACT_DISCOVERY_UNCONFIGURED');
    err.status = 503;
    throw err;
  }
  const list = Array.isArray(phones) ? phones.slice(0, MAX_HASHES) : [];
  const db = deps.db || firestore();
  const found = [];
  for (const raw of list) {
    const hash = hmacPhone(raw, secret);
    if (!hash) continue;
    const snap = await db
      .collection('contact_hash_index')
      .doc(hash)
      .collection('users')
      .limit(5)
      .get();
    snap.docs.forEach((d) => {
      if (d.id !== uid) found.push(d.id);
    });
  }
  return { matches: [...new Set(found)].slice(0, 50) };
}

module.exports = {
  normalizePhone,
  hmacPhone,
  optIn,
  optOut,
  status,
  matchPhones,
  discoverySecret,
};
