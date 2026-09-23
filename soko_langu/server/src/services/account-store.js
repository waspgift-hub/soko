// Phase 1 (Firestore-primary accounts): Firestore users/{firebaseUid} is the
// authoritative app-facing profile; the store seam (orders/wallet/payments join
// by uuid) reads the same Firestore docs. Reads never require Postgres; writes
// always land in Firestore first.
const { getFirebaseFirestore } = require('../config/firebase');
const { getStore } = require('../config/database');

function assertDb() {
  const db = getFirebaseFirestore();
  if (!db) throw new Error('Firestore not configured');
  return db;
}

// Fields the app's UserProfile.fromMap reads straight off the Firestore doc.
const COLUMN_FIELDS = {
  displayName: 'displayName',
  username: 'username',
  bio: 'bio',
  phone: 'phone',
  email: 'email',
  profileImage: 'avatarUrl',
  langCode: 'preferredLanguage',
};

// Extended profile fields stored under metadata.profile (no top-level column).
const PROFILE_META_FIELDS = [
  'location', 'mood', 'latitude', 'longitude', 'paymentNumbers',
  'shopBanner', 'shopBannerColor', 'shopAccentColor', 'gender', 'dateOfBirth',
];

function docRef(uid) {
  return assertDb().collection('users').doc(uid);
}

async function getProfile(uid) {
  const snap = await docRef(uid).get();
  return snap.exists ? snapshotData(snap) : null;
}

// firebase-admin returns a Firestore Timestamp for timestamp fields; the app
// expects ISO strings so normalize on read.
function snapshotData(snap) {
  const d = snap.data();
  const out = { ...d };
  for (const k of ['createdAt', 'updatedAt', 'lastActive']) {
    const v = d[k];
    if (v && typeof v.toDate === 'function') out[k] = v.toDate().toISOString();
  }
  return out;
}

// Serialize a Firestore users/{uid} doc into the exact response shape the app
// already consumes (previously serialized from Postgres rows).
function serializeFirestoreProfile(doc) {
  const meta = doc.metadata && typeof doc.metadata === 'object' ? doc.metadata : {};
  const p = meta.profile || {};
  return {
    id: doc.userId || '',
    displayName: doc.displayName || '',
    username: doc.username || '',
    bio: doc.bio || '',
    phone: doc.phone || '',
    email: doc.email || '',
    location: p.location || '',
    mood: p.mood || '',
    latitude: p.latitude ?? null,
    longitude: p.longitude ?? null,
    profileImage: doc.avatarUrl || '',
    paymentNumbers: p.paymentNumbers || {},
    shopBanner: p.shopBanner || '',
    shopBannerColor: p.shopBannerColor || '',
    shopAccentColor: p.shopAccentColor || '',
    kyc: { approved: Boolean(doc.kyc && doc.kyc.approved) },
    gender: p.gender || '',
    dateOfBirth: p.dateOfBirth || '',
    lastActive: doc.lastActive && typeof doc.lastActive === 'string' ? doc.lastActive : null,
    langCode: doc.preferredLanguage || 'sw',
    createdAt: doc.createdAt || null,
    updatedAt: doc.updatedAt || null,
  };
}

// Apply a client profile payload onto the Firestore doc: top-level columns plus
// merged metadata.profile. Returns { data, meta, columnPatch } for the mirror.
function applyProfileUpdate(doc, body) {
  const data = body && typeof body === 'object' ? body : {};
  const col = {};
  const metaFields = {};
  for (const [clientKey, dbKey] of Object.entries(COLUMN_FIELDS)) {
    if (clientKey in data) {
      const v = data[clientKey];
      col[dbKey] = (typeof v === 'string' && v.trim() === '') ? null : v;
    }
  }
  for (const f of PROFILE_META_FIELDS) {
    if (f in data) metaFields[f] = data[f];
  }
  const currentMeta = doc.metadata && typeof doc.metadata === 'object' ? doc.metadata : {};
  const mergedProfile = { ...(currentMeta.profile || {}), ...metaFields };
  const meta = { ...currentMeta, profile: mergedProfile };
  return { col, meta, columnPatch: col };
}

// Authoritative profile write to Firestore, then write the store seam (uuid
// join the money modules key on) so both reads agree.
async function writeProfile(uid, { col, meta }) {
  const data = { userId: uid, ...col, metadata: meta, updatedAt: adminNow() };
  await docRef(uid).set(data, { merge: true });

  try {
    const store = getStore();
    const row = await store.user.findUnique({ where: { firebaseUid: uid }, select: { id: true } });
    if (row) {
      await store.user.update({
        where: { id: row.id },
        data: { ...col, metadata: meta },
      });
    }
  } catch (e) {
    console.error('[ACCOUNT-STORE] store seam write failed:', e.message);
  }
}

// Set account-level flags (accountStatus, isSuspended, ...) on the Firestore
// doc, then set them on the store seam row too.
async function updateFlags(uid, flags) {
  await docRef(uid).set({ ...flags, updatedAt: adminNow() }, { merge: true });
  try {
    const store = getStore();
    const row = await store.user.findUnique({ where: { firebaseUid: uid }, select: { id: true } });
    if (row) {
      const map = {};
      if ('accountStatus' in flags) map.accountStatus = flags.accountStatus;
      if ('isSuspended' in flags) map.accountStatus = flags.isSuspended ? 'suspended' : 'active';
      if (Object.keys(map).length) await store.user.update({ where: { id: row.id }, data: map });
    }
  } catch (e) {
    console.error('[ACCOUNT-STORE] store flag write failed:', e.message);
  }
}

function adminNow() {
  // Keep Firestore timestamps consistent with the app's ISO-string reads.
  return new Date().toISOString();
}

// Firestore-first lookups for auth: query by phone variants or email, with a
// store-seam fallback for accounts that predate the Firestore records.
function phoneVariants(clean) {
  const last9 = clean.slice(-9);
  return [...new Set([clean, `0${last9}`, `+${clean}`])];
}

async function byPhoneFirestore(clean) {
  const db = assertDb();
  let found = null;
  for (const p of phoneVariants(clean)) {
    if (p.length === 0) continue;
    const snap = await db.collection('users').where('phone', '==', p).limit(1).get();
    if (!snap.empty) {
      found = { ...snapshotData(snap.docs[0]), _uid: snap.docs[0].id };
      break;
    }
  }
  return found;
}

async function byEmailFirestore(email) {
  if (!email) return null;
  const snap = await assertDb().collection('users').where('email', '==', email).limit(1).get();
  return snap.empty ? null : { ...snapshotData(snap.docs[0]), _uid: snap.docs[0].id };
}

async function byUsernameFirestore(username) {
  if (!username) return null;
  const snap = await assertDb().collection('users').where('username', '==', username).limit(1).get();
  return snap.empty ? null : { ...snapshotData(snap.docs[0]), _uid: snap.docs[0].id };
}

module.exports = {
  getProfile,
  serializeFirestoreProfile,
  applyProfileUpdate,
  writeProfile,
  updateFlags,
  byPhoneFirestore,
  byEmailFirestore,
  byUsernameFirestore,
  COLUMN_FIELDS,
  PROFILE_META_FIELDS,
};