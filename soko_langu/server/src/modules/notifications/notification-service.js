// Firestore-only in-app notifications (Phase 4). The flat `notifications`
// collection is the single store — the client renders it directly and the
// legacy-compat notifiers (orders, escrow, kyc, admin, boost, flash-sale)
// already add docs there. This service keeps the old module contract
// (`{ notifications, pagination }`) backed by that same collection so the
// `/api/v1/notifications` endpoints and the client fallback list stay green.
// OneSignal heads-up delivery is deliberately not sent here: it lives in
// legacy-compat/notify.js, which addresses users by Firebase UID (matching
// `OneSignal.login(user.uid)`), unlike the old Postgres-id push service.
const { getFirebaseFirestore } = require('../../config/firebase');

const PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 100;
// Page-offset pagination over a single field-order query can't use Firestore
// cursors, and a per-user inbox is bounded, so we hydrate at most this many of
// the newest docs then slice.
const HYDRATE_CAP = 1000;

function toISO(value) {
  if (value == null) return null;
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

function serializeDoc(doc) {
  const d = doc.data();
  return {
    id: doc.id,
    userId: d.userId,
    type: d.type || 'INFO',
    title: d.title,
    body: d.body,
    data: d.data || {},
    isRead: Boolean(d.isRead),
    createdAt: toISO(d.createdAt),
  };
}

async function createNotification({ userId, title, body, type = 'INFO', data = {} }) {
  const db = getFirebaseFirestore();
  const ref = await db.collection('notifications').add({
    userId,
    title,
    body,
    type,
    data: data || {},
    isRead: false,
    createdAt: new Date(),
  });
  const snap = await ref.get();
  return serializeDoc(snap);
}

async function listNotifications(firebaseUid, { page = 1, limit = PAGE_SIZE } = {}) {
  const db = getFirebaseFirestore();
  const take = Math.min(Math.max(1, limit), MAX_PAGE_SIZE);
  const skip = (Math.max(1, page) - 1) * take;

  const snap = await db
    .collection('notifications')
    .where('userId', '==', firebaseUid)
    .orderBy('createdAt', 'desc')
    .limit(HYDRATE_CAP)
    .get();

  const items = snap.docs.map((d) => serializeDoc(d));
  const total = items.length;
  const pageItems = items.slice(skip, skip + take);

  return {
    notifications: pageItems,
    pagination: { page, limit: take, total, totalPages: Math.ceil(total / take) },
  };
}

async function unreadCount(firebaseUid) {
  const db = getFirebaseFirestore();
  const snap = await db
    .collection('notifications')
    .where('userId', '==', firebaseUid)
    .where('isRead', '==', false)
    .get();
  return snap.size;
}

async function markRead(firebaseUid, notificationId) {
  const db = getFirebaseFirestore();
  const ref = db.collection('notifications').doc(notificationId);
  const doc = await ref.get();
  if (!doc.exists || doc.data().userId !== firebaseUid) return false;
  if (doc.data().isRead) return true;
  await ref.update({ isRead: true, readAt: new Date() });
  return true;
}

async function markAllRead(firebaseUid) {
  const db = getFirebaseFirestore();
  const snap = await db
    .collection('notifications')
    .where('userId', '==', firebaseUid)
    .where('isRead', '==', false)
    .get();
  if (snap.size === 0) return 0;
  const batch = db.batch();
  snap.docs.forEach((d) => batch.update(d.ref, { isRead: true, readAt: new Date() }));
  await batch.commit();
  return snap.size;
}

async function deleteNotification(firebaseUid, notificationId) {
  const db = getFirebaseFirestore();
  const ref = db.collection('notifications').doc(notificationId);
  const doc = await ref.get();
  if (!doc.exists || doc.data().userId !== firebaseUid) return false;
  await ref.delete();
  return true;
}

async function deleteAll(firebaseUid) {
  const db = getFirebaseFirestore();
  const snap = await db
    .collection('notifications')
    .where('userId', '==', firebaseUid)
    .get();
  if (snap.size === 0) return 0;
  const batch = db.batch();
  snap.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
  return snap.size;
}

module.exports = {
  createNotification,
  listNotifications,
  unreadCount,
  markRead,
  markAllRead,
  deleteNotification,
  deleteAll,
};