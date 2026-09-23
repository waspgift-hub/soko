// Phase 3 (Firestore-ONLY comments): comments live in the flat `comments`
// collection — the same layout the AI assistant already reads — and the
// mongoose-era Postgres `comment` rows are dropped. userId is the Firebase UID
// with denormalized author snapshot so list/build needs no join. Queries need
// two composite indexes ((targetId,parentId,createdAt), (parentId,createdAt))
// now declared in firestore.indexes.json.
const crypto = require('crypto');
const { getFirebaseFirestore } = require('../../config/firebase');

const DEFAULT_LIMIT = 100;
const MAX_CONTENT = 2000;

function httpError(status, message) {
  const e = new Error(message);
  e.status = status;
  return e;
}

function requireStore() {
  const db = getFirebaseFirestore();
  if (!db) throw httpError(503, 'COMMENT_STORE_UNAVAILABLE');
  return db;
}

function iso(value) {
  if (value == null) return null;
  if (typeof value === 'object' && typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

function serialize(doc, replyCount) {
  return {
    id: doc.id,
    userId: doc.userId,
    userName: doc.userName || 'Unknown',
    userImage: doc.userImage || null,
    text: doc.content,
    createdAt: iso(doc.createdAt),
    replyCount,
  };
}

// A comment targets a product only; existence is proven by the authorative
// products/{targetId} doc (absent = product deleted), never by Postgres.
async function productExists(targetId) {
  const db = requireStore();
  const snap = await db.collection('products').doc(String(targetId)).get();
  return snap.exists;
}

async function listComments({ targetId, page = 1, limit = DEFAULT_LIMIT }) {
  const db = requireStore();
  const col = db.collection('comments');
  const base = col
    .where('targetId', '==', String(targetId))
    .where('parentId', '==', null);

  const [countSnap, snap] = await Promise.all([
    base.count().get(),
    base.orderBy('createdAt', 'desc').limit((Number(page) - 1) * Number(limit) + Number(limit) + 1).get(),
  ]);

  const start = (Number(page) - 1) * Number(limit);
  const window = snap.docs.slice(start, start + Number(limit));
  const counts = await Promise.all(window.map((d) => replyCountOf(d.id)));
  const items = window.map((d, i) => serialize({ ...d.data(), id: d.id }, counts[i]));
  return {
    items,
    page: Number(page),
    limit: Number(limit),
  };
}

// Soft-deleted replies still sit in the parentId bucket, so subtract them in
// JS (count over a single-field query needs no extra index).
async function replyCountOf(parentId) {
  const db = requireStore();
  const snap = await db.collection('comments').where('parentId', '==', parentId).limit(200).get();
  return snap.docs.filter((d) => !d.data().deletedAt).length;
}

async function listReplies(commentId) {
  const db = requireStore();
  const parent = await getComment(commentId);
  if (!parent) throw httpError(404, 'COMMENT_NOT_FOUND');
  const snap = await db.collection('comments')
    .where('parentId', '==', commentId)
    .orderBy('createdAt', 'asc')
    .limit(200)
    .get();
  return snap.docs
    .filter((d) => !d.data().deletedAt)
    .map((d) => serialize({ ...d.data(), id: d.id }, 0));
}

async function getComment(commentId) {
  const db = requireStore();
  const snap = await db.collection('comments').doc(String(commentId)).get();
  if (!snap.exists || snap.data().deletedAt) return null;
  return { ...snap.data(), id: snap.data().id || commentId };
}

async function addComment({ targetId, userId, userName, userImage, content }) {
  const db = requireStore();
  const text = String(content || '').trim();
  if (!text) throw httpError(400, 'EMPTY_TEXT');
  const id = crypto.randomUUID();
  const createdAt = iso(new Date());
  await db.collection('comments').doc(id).set({
    id,
    targetId: String(targetId),
    targetType: 'product',
    parentId: null,
    userId,
    userName: String(userName || 'Unknown').slice(0, 100),
    userImage: userImage || null,
    content: text.slice(0, MAX_CONTENT),
    createdAt,
    deletedAt: null,
  });
  return serialize({ id, userId, userName, userImage, content: text, createdAt }, 0);
}

async function addReply({ commentId, userId, userName, userImage, content }) {
  const db = requireStore();
  const parent = await getComment(commentId);
  if (!parent) throw httpError(404, 'COMMENT_NOT_FOUND');
  const text = String(content || '').trim();
  if (!text) throw httpError(400, 'EMPTY_TEXT');
  const id = crypto.randomUUID();
  const createdAt = iso(new Date());
  await db.collection('comments').doc(id).set({
    id,
    targetId: parent.targetId,
    targetType: parent.targetType,
    parentId: commentId,
    userId,
    userName: String(userName || 'Unknown').slice(0, 100),
    userImage: userImage || null,
    content: text.slice(0, MAX_CONTENT),
    createdAt,
    deletedAt: null,
  });
  return serialize({ id, userId, userName, userImage, content: text, createdAt }, 0);
}

// Ownership: the author (doc.userId === firebaseUid) or the product owner
// (products/{targetId}.sellerId === firebaseUid) may soft-delete.
async function deleteComment({ commentId, userId }) {
  const db = requireStore();
  const doc = await db.collection('comments').doc(String(commentId)).get();
  if (!doc.exists || doc.data().deletedAt) throw httpError(404, 'COMMENT_NOT_FOUND');

  const row = doc.data();
  const owner = userId === row.userId || (await isProductOwner(row.targetId, userId));
  if (!owner) throw httpError(403, 'FORBIDDEN');

  await doc.ref.update({ deletedAt: iso(new Date()) });
  return true;
}

async function isProductOwner(targetId, userId) {
  const db = requireStore();
  const snap = await db.collection('products').doc(String(targetId)).get();
  return snap.exists && snap.data().sellerId === userId;
}

module.exports = {
  listComments,
  listReplies,
  addComment,
  addReply,
  deleteComment,
  productExists,
  serialize,
};