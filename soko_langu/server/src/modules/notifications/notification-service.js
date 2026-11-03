// Firestore-only in-app notifications (Phase 4). The flat `notifications`
// collection is the single store — the client renders it directly and the
// legacy-compat notifiers (orders, escrow, kyc, admin, boost, flash-sale)
// already add docs there. This service keeps the old module contract
// (`{ notifications, pagination }`) backed by that same collection so the
// `/api/v1/notifications` endpoints and the client fallback list stay green.
// OneSignal heads-up delivery is deliberately not sent here: it lives in
// legacy-compat/notify.js, which addresses users by Firebase UID (matching
// `OneSignal.login(user.uid)`), unlike the old Postgres-id push service.
const commerceStore = require('../../services/commerce-store');

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
  if (!doc) return null;
  const d = doc || {};
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
  const docId = await commerceStore.addDocument('notifications', {
    userId,
    title,
    body,
    type,
    data: data || {},
    isRead: false,
    createdAt: commerceStore.serverTimestamp(),
  });
  const snap = await commerceStore.getDocument('notifications', docId);
  return serializeDoc(snap);
}

async function listNotifications(firebaseUid, { page = 1, limit = PAGE_SIZE } = {}) {
  const take = Math.min(Math.max(1, limit), MAX_PAGE_SIZE);
  const skip = (Math.max(1, page) - 1) * take;

  const items = await commerceStore.listDocuments('notifications', {
    where: { userId: firebaseUid },
    orderBy: 'createdAt',
    direction: 'desc',
    limit: HYDRATE_CAP,
  });

  const serializedItems = items.map((d) => serializeDoc(d));
  const total = serializedItems.length;
  const pageItems = serializedItems.slice(skip, skip + take);

  return {
    notifications: pageItems,
    pagination: { page, limit: take, total, totalPages: Math.ceil(total / take) },
  };
}

async function unreadCount(firebaseUid) {
  const items = await commerceStore.listDocuments('notifications', {
    where: { userId: firebaseUid, isRead: false },
  });
  return items.length;
}

async function markRead(firebaseUid, notificationId) {
  const doc = await commerceStore.getDocument('notifications', notificationId);
  if (!doc || doc.userId !== firebaseUid) return false;
  if (doc.isRead) return true;
  await commerceStore.updateDocument('notifications', notificationId, { isRead: true, readAt: new Date() });
  return true;
}

async function markAllRead(firebaseUid) {
  const items = await commerceStore.listDocuments('notifications', {
    where: { userId: firebaseUid, isRead: false },
  });
  if (items.length === 0) return 0;
  const updates = items.map(d => ({
    id: d.id,
    updates: { isRead: true, readAt: new Date() }
  }));
  await commerceStore.batchUpdate('notifications', updates);
  return items.length;
}

async function deleteNotification(firebaseUid, notificationId) {
  const doc = await commerceStore.getDocument('notifications', notificationId);
  if (!doc || doc.userId !== firebaseUid) return false;
  await commerceStore.deleteDocument('notifications', notificationId);
  return true;
}

async function deleteAll(firebaseUid) {
  const items = await commerceStore.listDocuments('notifications', {
    where: { userId: firebaseUid },
  });
  if (items.length === 0) return 0;
  const docIds = items.map(d => d.id);
  await commerceStore.batchDelete('notifications', docIds);
  return items.length;
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