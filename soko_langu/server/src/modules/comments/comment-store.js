// Firestore-only product comments.
//
// The flat `comments` collection is the single store: a top-level comment has
// `parentId: null`, a reply has `parentId: <root comment id>`. Replies to a
// reply are flattened onto the same root and keep `replyToId`/`replyToUserName`
// so the UI can render "@name" without unbounded nesting.
//
// Money never touches this module. It only reads `products/{id}` to prove the
// target exists and who owns it, and `users/{uid}`/`userPublic/{uid}` for the
// denormalized author snapshot.
const crypto = require('crypto');
const { getFirebaseFirestore } = require('../../config/firebase');

const COLLECTION = 'comments';
const LIKE_COLLECTION = 'comment_likes';
const REPORT_COLLECTION = 'comment_reports';

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 50;
const MAX_CONTENT = 2000;
const MAX_MENTIONS = 10;
const DUPLICATE_WINDOW_MS = 30 * 1000;

const MENTION_RE = /(?:^|[^\w@])@([a-zA-Z0-9_.]{2,30})/g;
const USERNAME_RE = /^[a-zA-Z0-9_.]{2,30}$/;

function httpError(status, message, code) {
  const e = new Error(message);
  e.status = status;
  if (code) e.code = code;
  return e;
}

function requireStore() {
  const db = getFirebaseFirestore();
  if (!db) throw httpError(503, 'COMMENT_STORE_UNAVAILABLE', 'COMMENT_STORE_UNAVAILABLE');
  return db;
}

function iso(value) {
  if (value == null) return null;
  if (typeof value === 'object' && typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

function toMillis(value) {
  if (value == null) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  const t = Date.parse(String(value));
  return Number.isFinite(t) ? t : 0;
}

function clampLimit(value, fallback = DEFAULT_LIMIT) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return fallback;
  return Math.min(MAX_LIMIT, Math.max(1, Math.floor(n)));
}

function normalizeContent(value) {
  const text = String(value == null ? '' : value).replace(/\r\n/g, '\n').trim();
  if (!text) throw httpError(400, 'EMPTY_TEXT', 'EMPTY_TEXT');
  return text.slice(0, MAX_CONTENT);
}

/**
 * Extracts unique `@handle` tokens from comment text.
 *
 * Pure so it can be unit-tested without Firestore. Matching requires a word
 * boundary before `@` so an email address (`a@b.com`) is never a mention.
 */
function extractMentionHandles(text) {
  const handles = new Set();
  const source = String(text || '');
  let match;
  MENTION_RE.lastIndex = 0;
  while ((match = MENTION_RE.exec(source)) !== null) {
    const handle = match[1].replace(/\.+$/, '');
    if (handle.length >= 2) handles.add(handle.toLowerCase());
    if (handles.size >= MAX_MENTIONS) break;
  }
  return [...handles];
}

function serialize(doc, replyCount) {
  const deleted = Boolean(doc.deletedAt);
  return {
    id: doc.id,
    userId: doc.userId || '',
    userName: doc.userName || 'Unknown',
    username: doc.username || '',
    userImage: doc.userImage || null,
    text: deleted ? '' : doc.content || '',
    createdAt: iso(doc.createdAt),
    replyCount: replyCount == null ? 0 : Number(replyCount) || 0,
    parentId: doc.parentId || null,
    replyToId: doc.replyToId || null,
    replyToUserName: doc.replyToUserName || null,
    pinned: Boolean(doc.pinned),
    editedAt: iso(doc.editedAt),
    likeCount: Number(doc.likeCount) || 0,
    likedByMe: Boolean(doc.likedByMe),
    mentions: Array.isArray(doc.mentions) ? doc.mentions : [],
    deleted,
  };
}

async function productExists(targetId) {
  const db = requireStore();
  const snap = await db.collection('products').doc(String(targetId)).get();
  return snap.exists;
}

async function getProduct(targetId) {
  const db = requireStore();
  const snap = await db.collection('products').doc(String(targetId)).get();
  return snap.exists ? { id: snap.id, ...snap.data() } : null;
}

async function isProductOwner(targetId, userId) {
  if (!targetId || !userId) return false;
  const product = await getProduct(targetId);
  return Boolean(product && product.sellerId === userId);
}

async function isPlatformModerator(userId) {
  if (!userId) return false;
  if (userId === 'admin') return true;
  try {
    const db = requireStore();
    const snap = await db.collection('users').doc(String(userId)).get();
    if (!snap.exists) return false;
    const data = snap.data() || {};
    return data.role === 'admin' || data.role === 'super_admin' || data.isAdmin === true;
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Author snapshot
// ---------------------------------------------------------------------------

const profileCache = new Map();
const PROFILE_TTL_MS = 5 * 60 * 1000;

async function resolveAuthor(userId) {
  if (!userId) return { userName: 'Unknown', username: '', userImage: null };
  const cached = profileCache.get(userId);
  if (cached && Date.now() - cached.at < PROFILE_TTL_MS) return cached.value;

  let value = { userName: 'Unknown', username: '', userImage: null };
  const db = getFirebaseFirestore();
  if (db) {
    try {
      const snap = await db.collection('users').doc(String(userId)).get();
      if (snap.exists) {
        const data = snap.data() || {};
        const name = data.displayName || data.name || data.username || '';
        value = {
          userName: String(name || 'Unknown').slice(0, 100),
          username: String(data.username || '').slice(0, 40),
          userImage: data.avatarUrl || data.photoURL || data.profileImage || null,
        };
      }
    } catch (_) {}
  }

  if (value.userName === 'Unknown') {
    try {
      const { getFirebaseAuth } = require('../../config/firebase');
      const auth = getFirebaseAuth();
      if (auth) {
        const rec = await auth.getUser(String(userId));
        value = {
          userName: String(rec.displayName || rec.email || 'Unknown').slice(0, 100),
          username: '',
          userImage: rec.photoURL || null,
        };
      }
    } catch (_) {}
  }

  // Only cache a resolved profile; unresolved uids are retried next time.
  if (value.userName !== 'Unknown') profileCache.set(userId, { at: Date.now(), value });
  return value;
}

async function resolveMentions(text) {
  const handles = extractMentionHandles(text).filter((h) => USERNAME_RE.test(h));
  if (!handles.length) return [];
  const db = requireStore();
  const byHandle = new Map();
  // A comment with many mentions used to cost one query per handle. Firestore
  // `in` accepts up to 10 values per query, so chunk and run the chunks in
  // parallel: at most ceil(n/10) round-trips instead of n.
  const chunks = [];
  for (let i = 0; i < handles.length; i += 10) chunks.push(handles.slice(i, i + 10));
  const snaps = await Promise.all(chunks.map((chunk) =>
    db
      .collection('userPublic')
      .where('usernameLower', 'in', chunk)
      .get()
      .catch(() => null)
  ));
  snaps.forEach((snap) => {
    if (!snap || snap.empty) return;
    snap.docs.forEach((doc) => {
      const data = doc.data();
      const key = String(data.usernameLower || '').toLowerCase();
      if (!key || byHandle.has(key)) return;
      byHandle.set(key, {
        userId: doc.id,
        userName: (data.displayName || data.username || key).slice(0, 100),
        username: data.username || key,
      });
    });
  });
  // Preserve mention order; a miss in userPublic must not fail the write.
  return handles.map((h) => byHandle.get(h)).filter(Boolean);
}

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

async function likedIdSet(commentIds, userId) {
  const set = new Set();
  if (!userId || !commentIds.length) return set;
  const db = requireStore();
  try {
    const refs = commentIds.map((id) => db.collection(LIKE_COLLECTION).doc(`${id}_${userId}`));
    const docs = await db.getAll(...refs);
    docs.forEach((doc) => {
      if (doc.exists) set.add(doc.id.slice(0, doc.id.length - userId.length - 1));
    });
  } catch (_) {}
  return set;
}

async function replyCountsFor(rootIds) {
  const counts = new Map();
  if (!rootIds.length) return counts;
  const db = requireStore();
  const unique = [...new Set(rootIds)];
  const chunks = [];
  for (let i = 0; i < unique.length; i += 30) chunks.push(unique.slice(i, i + 30));
  const snaps = await Promise.all(
    chunks.map((ids) =>
      db.collection(COLLECTION).where('parentId', 'in', ids).limit(1000).get().catch(() => null),
    ),
  );
  for (const snap of snaps) {
    if (!snap) continue;
    snap.docs.forEach((doc) => {
      const data = doc.data();
      if (data.deletedAt) return;
      counts.set(data.parentId, (counts.get(data.parentId) || 0) + 1);
    });
  }
  return counts;
}

/**
 * Cursor pagination over the newest-first top-level stream.
 *
 * The cursor is the id of the last document rendered. Using the document
 * snapshot (rather than a timestamp+id pair) keeps the existing
 * (targetId, parentId, createdAt) index as the only query index needed, and
 * stays stable when two comments share a millisecond.
 */
async function pageQuery({ targetId, cursor, limit, pinned }) {
  const db = requireStore();
  let query = db
    .collection(COLLECTION)
    .where('targetId', '==', String(targetId))
    .where('parentId', '==', null);

  if (pinned === true) {
    query = query.where('pinned', '==', true).orderBy('createdAt', 'desc').limit(5);
    const snap = await query.get();
    return snap.docs.filter((d) => !d.data().deletedAt);
  }

  query = query.orderBy('createdAt', 'desc');
  if (cursor) {
    const cursorSnap = await db.collection(COLLECTION).doc(String(cursor)).get();
    if (cursorSnap.exists) query = query.startAfter(cursorSnap);
  }
  const snap = await query.limit(limit + 1).get();
  return snap.docs.filter((d) => !d.data().deletedAt);
}

async function listComments({ targetId, userId = null, sort = 'newest', cursor = null, limit } = {}) {
  const db = requireStore();
  const pageSize = clampLimit(limit, DEFAULT_LIMIT);
  const normalizedSort = sort === 'relevant' ? 'relevant' : 'newest';

  let pinnedDocs = [];
  if (normalizedSort === 'relevant' && !cursor) {
    pinnedDocs = await pageQuery({ targetId, pinned: true, limit: pageSize });
  }

  const docs = await pageQuery({ targetId, cursor, limit: pageSize });
  const pinnedIds = new Set(pinnedDocs.map((d) => d.id));
  const remaining = docs.filter((d) => !pinnedIds.has(d.id));
  const hasMore = remaining.length > pageSize;
  const window = remaining.slice(0, pageSize);
  const allDocs = [...pinnedDocs, ...window];

  const ids = allDocs.map((d) => d.id);
  const [counts, liked] = await Promise.all([replyCountsFor(ids), likedIdSet(ids, userId)]);

  const items = allDocs.map((doc) => {
    const data = doc.data() || {};
    return serialize({ ...data, id: doc.id, likedByMe: liked.has(doc.id) }, counts.get(doc.id) || 0);
  });

  const last = window.length ? window[window.length - 1].id : cursor;

  const totalSnap = await db
    .collection(COLLECTION)
    .where('targetId', '==', String(targetId))
    .where('parentId', '==', null)
    .where('deletedAt', '==', null)
    .count()
    .get()
    .catch(() => null);

  return {
    items,
    sort: normalizedSort,
    nextCursor: hasMore ? last : null,
    hasMore,
    total: totalSnap ? totalSnap.data().count : items.length,
  };
}

async function listReplies(commentIdOrOptions, maybeOptions) {
  const options =
    typeof commentIdOrOptions === 'string'
      ? { parentId: commentIdOrOptions, ...(maybeOptions || {}) }
      : commentIdOrOptions || {};
  const parentId = options.parentId || options.commentId;
  if (!parentId) throw httpError(400, 'COMMENT_ID_REQUIRED', 'COMMENT_ID_REQUIRED');

  const db = requireStore();
  const pageSize = clampLimit(options.limit, 30);
  const userId = options.userId || null;

  let query = db.collection(COLLECTION).where('parentId', '==', String(parentId));
  query = query.orderBy('createdAt', 'asc');
  if (options.cursor) {
    const cursorSnap = await db.collection(COLLECTION).doc(String(options.cursor)).get();
    if (cursorSnap.exists) query = query.startAfter(cursorSnap);
  }

  const snap = await query.limit(pageSize + 1).get();
  const live = snap.docs.filter((d) => !d.data().deletedAt);
  const hasMore = live.length > pageSize;
  const window = live.slice(0, pageSize);
  const liked = await likedIdSet(window.map((d) => d.id), userId);
  const items = window.map((doc) => {
    const data = doc.data() || {};
    return serialize({ ...data, id: doc.id, likedByMe: liked.has(doc.id) }, 0);
  });

  return {
    items,
    nextCursor: hasMore && items.length ? items[items.length - 1].id : null,
    hasMore,
  };
}

async function getComment(commentId) {
  const db = requireStore();
  const snap = await db.collection(COLLECTION).doc(String(commentId)).get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  return { ...data, id: data.id || snap.id };
}

// ---------------------------------------------------------------------------
// Writes
// ---------------------------------------------------------------------------

async function assertNotDuplicate({ targetId, userId, content }) {
  const db = requireStore();
  const since = new Date(Date.now() - DUPLICATE_WINDOW_MS);
  try {
    const snap = await db
      .collection(COLLECTION)
      .where('targetId', '==', String(targetId))
      .where('userId', '==', String(userId))
      .where('createdAt', '>=', since.toISOString())
      .limit(10)
      .get();
    const duplicate = snap.docs.some(
      (d) => !d.data().deletedAt && String(d.data().content || '').trim() === content,
    );
    if (duplicate) throw httpError(429, 'DUPLICATE_COMMENT', 'DUPLICATE_COMMENT');
  } catch (error) {
    if (error && error.code === 'DUPLICATE_COMMENT') throw error;
    // A missing index must not block a legitimate comment.
  }
}

async function assertCommentsEnabled(targetId) {
  const product = await getProduct(targetId);
  if (product && product.commentsEnabled === false) {
    throw httpError(403, 'COMMENTS_DISABLED', 'COMMENTS_DISABLED');
  }
}

async function addComment({ targetId, userId, userName, username, userImage, content, mentions = [] }) {
  const db = requireStore();
  const text = normalizeContent(content);
  await assertCommentsEnabled(targetId);
  await assertNotDuplicate({ targetId, userId, content: text });

  const id = crypto.randomUUID();
  const createdAt = iso(new Date());
  const mentionIds = Array.isArray(mentions) ? mentions.map((m) => m.userId).filter(Boolean) : [];

  await db.collection(COLLECTION).doc(id).set({
    id,
    targetId: String(targetId),
    targetType: 'product',
    parentId: null,
    userId,
    userName: String(userName || 'Unknown').slice(0, 100),
    username: String(username || '').slice(0, 40),
    userImage: userImage || null,
    content: text,
    createdAt,
    editedAt: null,
    deletedAt: null,
    pinned: false,
    pinnedAt: null,
    likeCount: 0,
    reportCount: 0,
    mentions: mentionIds,
  });

  return serialize(
    { id, userId, userName, username, userImage, content: text, createdAt, mentions: mentionIds },
    0,
  );
}

/**
 * Adds a reply. Replying to a reply keeps the thread flat: the stored
 * `parentId` is always the root comment, and `replyToId`/`replyToUserName`
 * preserve who was addressed.
 */
async function addReply({
  commentId,
  replyToId = null,
  userId,
  userName,
  username,
  userImage,
  content,
  mentions = [],
}) {
  const db = requireStore();
  const target = await getComment(commentId);
  if (!target || target.deletedAt) throw httpError(404, 'COMMENT_NOT_FOUND', 'COMMENT_NOT_FOUND');

  const rootParentId = target.parentId || target.id;
  let replyTo = target;
  if (replyToId && replyToId !== target.id) {
    const parentReply = await getComment(replyToId);
    if (!parentReply || parentReply.deletedAt || (parentReply.parentId || parentReply.id) !== rootParentId) {
      throw httpError(400, 'INVALID_REPLY_TARGET', 'INVALID_REPLY_TARGET');
    }
    replyTo = parentReply;
  }

  const text = normalizeContent(content);
  await assertCommentsEnabled(target.targetId);
  await assertNotDuplicate({ targetId: target.targetId, userId, content: text });

  const id = crypto.randomUUID();
  const createdAt = iso(new Date());
  const mentionIds = Array.isArray(mentions) ? mentions.map((m) => m.userId).filter(Boolean) : [];

  await db.collection(COLLECTION).doc(id).set({
    id,
    targetId: target.targetId,
    targetType: target.targetType || 'product',
    parentId: rootParentId,
    replyToId: replyTo.id,
    replyToUserName: replyTo.userName || null,
    replyToUserId: replyTo.userId || null,
    userId,
    userName: String(userName || 'Unknown').slice(0, 100),
    username: String(username || '').slice(0, 40),
    userImage: userImage || null,
    content: text,
    createdAt,
    editedAt: null,
    deletedAt: null,
    pinned: false,
    likeCount: 0,
    reportCount: 0,
    mentions: mentionIds,
  });

  return serialize(
    {
      id,
      userId,
      userName,
      username,
      userImage,
      content: text,
      createdAt,
      parentId: rootParentId,
      replyToId: replyTo.id,
      replyToUserName: replyTo.userName || null,
      mentions: mentionIds,
    },
    0,
  );
}

async function editComment({ commentId, userId, content }) {
  const db = requireStore();
  const doc = await db.collection(COLLECTION).doc(String(commentId)).get();
  if (!doc.exists || doc.data().deletedAt) throw httpError(404, 'COMMENT_NOT_FOUND', 'COMMENT_NOT_FOUND');
  if (doc.data().userId !== userId) throw httpError(403, 'FORBIDDEN', 'FORBIDDEN');

  const text = normalizeContent(content);
  const editedAt = iso(new Date());
  await doc.ref.update({ content: text, editedAt });
  return serialize({ ...doc.data(), content: text, editedAt, id: doc.id }, 0);
}

async function deleteComment({ commentId, userId }) {
  const db = requireStore();
  const doc = await db.collection(COLLECTION).doc(String(commentId)).get();
  if (!doc.exists || doc.data().deletedAt) throw httpError(404, 'COMMENT_NOT_FOUND', 'COMMENT_NOT_FOUND');

  const row = doc.data();
  const owner =
    userId === row.userId ||
    (await isProductOwner(row.targetId, userId)) ||
    (await isPlatformModerator(userId));
  if (!owner) throw httpError(403, 'FORBIDDEN', 'FORBIDDEN');

  // Soft delete keeps the thread intact: replies still reference this doc, and
  // the serializer renders it as a tombstone without exposing the text.
  await doc.ref.update({
    deletedAt: iso(new Date()),
    content: '',
    deletedBy: userId === row.userId ? 'author' : 'moderator',
  });
  return true;
}

async function toggleLike({ commentId, userId }) {
  const db = requireStore();
  const commentRef = db.collection(COLLECTION).doc(String(commentId));
  const likeRef = db.collection(LIKE_COLLECTION).doc(`${commentId}_${userId}`);

  return db.runTransaction(async (tx) => {
    const [commentSnap, likeSnap] = await Promise.all([tx.get(commentRef), tx.get(likeRef)]);
    if (!commentSnap.exists || commentSnap.data().deletedAt) {
      throw httpError(404, 'COMMENT_NOT_FOUND', 'COMMENT_NOT_FOUND');
    }

    const current = Number(commentSnap.data().likeCount) || 0;
    if (likeSnap.exists) {
      tx.delete(likeRef);
      const next = Math.max(0, current - 1);
      tx.update(commentRef, { likeCount: next });
      return { liked: false, likeCount: next, authorId: commentSnap.data().userId };
    }

    tx.set(likeRef, { commentId: String(commentId), userId, createdAt: iso(new Date()) });
    const next = current + 1;
    tx.update(commentRef, { likeCount: next });
    return { liked: true, likeCount: next, authorId: commentSnap.data().userId };
  });
}

async function setPinned({ commentId, userId, pinned }) {
  const db = requireStore();
  const doc = await db.collection(COLLECTION).doc(String(commentId)).get();
  if (!doc.exists || doc.data().deletedAt) throw httpError(404, 'COMMENT_NOT_FOUND', 'COMMENT_NOT_FOUND');

  const row = doc.data();
  const canPin = (await isProductOwner(row.targetId, userId)) || (await isPlatformModerator(userId));
  if (!canPin) throw httpError(403, 'FORBIDDEN', 'FORBIDDEN');
  if (row.parentId) throw httpError(400, 'CANNOT_PIN_REPLY', 'CANNOT_PIN_REPLY');

  if (pinned) {
    // One pinned comment per product: unpin the previous one first.
    const existing = await db
      .collection(COLLECTION)
      .where('targetId', '==', String(row.targetId))
      .where('pinned', '==', true)
      .limit(10)
      .get()
      .catch(() => null);
    if (existing) {
      const batch = db.batch();
      existing.docs.forEach((d) => {
        if (d.id !== commentId) batch.update(d.ref, { pinned: false, pinnedAt: null });
      });
      batch.commit().catch(() => {});
    }
  }

  await doc.ref.update({ pinned: Boolean(pinned), pinnedAt: pinned ? iso(new Date()) : null });
  return { pinned: Boolean(pinned) };
}

async function setCommentsEnabled({ productId, userId, enabled }) {
  const db = requireStore();
  const product = await getProduct(productId);
  if (!product) throw httpError(404, 'PRODUCT_NOT_FOUND', 'PRODUCT_NOT_FOUND');
  const allowed =
    product.sellerId === userId || (await isPlatformModerator(userId));
  if (!allowed) throw httpError(403, 'FORBIDDEN', 'FORBIDDEN');

  await db.collection('products').doc(String(productId)).set(
    { commentsEnabled: Boolean(enabled), commentsUpdatedAt: iso(new Date()) },
    { merge: true },
  );
  return { commentsEnabled: Boolean(enabled) };
}

async function reportComment({ commentId, userId, reason }) {
  const db = requireStore();
  const commentRef = db.collection(COLLECTION).doc(String(commentId));
  const reportRef = db.collection(REPORT_COLLECTION).doc(`${commentId}_${userId}`);

  return db.runTransaction(async (tx) => {
    const [commentSnap, reportSnap] = await Promise.all([tx.get(commentRef), tx.get(reportRef)]);
    if (!commentSnap.exists || commentSnap.data().deletedAt) {
      throw httpError(404, 'COMMENT_NOT_FOUND', 'COMMENT_NOT_FOUND');
    }
    if (commentSnap.data().userId === userId) {
      throw httpError(400, 'CANNOT_REPORT_OWN_COMMENT', 'CANNOT_REPORT_OWN_COMMENT');
    }
    if (reportSnap.exists) {
      return { reported: true, duplicate: true };
    }

    tx.set(reportRef, {
      commentId: String(commentId),
      targetId: commentSnap.data().targetId,
      userId,
      reason: String(reason || 'other').slice(0, 40),
      createdAt: iso(new Date()),
      status: 'open',
    });
    tx.update(commentRef, { reportCount: (Number(commentSnap.data().reportCount) || 0) + 1 });
    return { reported: true, duplicate: false };
  });
}

module.exports = {
  // reads
  listComments,
  listReplies,
  getComment,
  productExists,
  getProduct,
  isProductOwner,
  resolveAuthor,
  resolveMentions,
  // writes
  addComment,
  addReply,
  editComment,
  deleteComment,
  toggleLike,
  setPinned,
  setCommentsEnabled,
  reportComment,
  // helpers (unit-tested)
  serialize,
  extractMentionHandles,
  clampLimit,
  // constants
  DEFAULT_LIMIT,
  MAX_LIMIT,
  MAX_CONTENT,
};
