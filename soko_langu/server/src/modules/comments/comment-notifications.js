// Comment notifications.
//
// Every function here is best-effort: a failed notification must never fail the
// comment write that triggered it. Delivery reuses the two channels the rest of
// the server already uses for in-app events:
//   1. a `notifications` Firestore doc  → the inbox screen (and legacy app)
//   2. OneSignal push via push-service  → heads-up notification
//
// Deduplication is structural: each in-app doc has a deterministic id, so a
// retried request or a double-tap cannot create a second inbox row.
const { getFirebaseFirestore } = require('../../config/firebase');

const PREF_COLLECTION = 'user_notification_preferences';

function db() {
  return getFirebaseFirestore();
}

function notifyId(parts) {
  return parts.filter(Boolean).join('_').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 200);
}

async function commentNotificationsEnabled(userId) {
  const store = db();
  if (!store || !userId) return false;
  try {
    const snap = await store.collection(PREF_COLLECTION).doc(String(userId)).get();
    if (!snap.exists) return true;
    const data = snap.data() || {};
    if (data.comments === false) return false;
    const cats = data.categoryPreferences || {};
    const chat = cats.chat;
    if (chat && chat.channels && chat.channels.push === false && chat.channels.email === false) {
      return false;
    }
    return true;
  } catch (_) {
    // Defaulting to enabled is the safe direction: the dedupe id still prevents
    // a spam loop, and a Firestore blip must not silence real replies.
    return true;
  }
}

async function deliver({ userId, docId, title, body, type, data }) {
  const store = db();
  if (!store || !userId) return;

  try {
    await store.collection('notifications').doc(docId).set(
      {
        userId: String(userId),
        title,
        body,
        type,
        isRead: false,
        createdAt: new Date(),
        data: data || {},
      },
      { merge: true },
    );
  } catch (e) {
    console.warn('[COMMENT-NOTIFY] inbox write failed:', e.message);
  }

  try {
    const push = require('../../services/push-service');
    await push.sendPush(userId, title, body, { type, ...(data || {}) });
  } catch (e) {
    console.warn('[COMMENT-NOTIFY] push failed:', e.message);
  }
}

function truncate(text, max = 80) {
  const value = String(text || '').replace(/\s+/g, ' ').trim();
  return value.length > max ? `${value.slice(0, max)}…` : value;
}

async function notifySellerOfComment({ product, comment, actorName }) {
  if (!product || !product.sellerId || product.sellerId === comment.userId) return;
  if (!(await commentNotificationsEnabled(product.sellerId))) return;
  await deliver({
    userId: product.sellerId,
    docId: notifyId(['comment', comment.id, 'seller']),
    title: 'Maoni mapya kwenye bidhaa yako',
    body: `${actorName || 'Mtu'}: "${truncate(comment.text)}"`,
    type: 'comment',
    data: { productId: product.id, commentId: comment.id },
  });
}

async function notifyReply({ parent, reply, productId, actorName }) {
  if (!parent || !parent.userId || parent.userId === reply.userId) return;
  if (!(await commentNotificationsEnabled(parent.userId))) return;
  await deliver({
    userId: parent.userId,
    docId: notifyId(['comment_reply', reply.id, parent.userId]),
    title: 'Jibu jipya kwa maoni yako',
    body: `${actorName || 'Mtu'} amejibu: "${truncate(reply.text)}"`,
    type: 'comment_reply',
    data: { productId, commentId: parent.id, replyId: reply.id },
  });
}

async function notifyMentions({ mentions = [], comment, productId, actorId, actorName }) {
  if (!mentions.length) return;
  // One slow recipient must not delay the rest: run the fan-out concurrently
  // and swallow per-recipient failures.
  await Promise.all(mentions.map(async (mention) => {
    if (!mention.userId || mention.userId === actorId) return;
    try {
      if (!(await commentNotificationsEnabled(mention.userId))) return;
      await deliver({
        userId: mention.userId,
        docId: notifyId(['comment_mention', comment.id, mention.userId]),
        title: 'Umetajwa kwenye maoni',
        body: `${actorName || 'Mtu'} amekutaja: "${truncate(comment.text)}"`,
        type: 'comment_mention',
        data: { productId, commentId: comment.id, replyId: comment.parentId ? comment.id : null },
      });
    } catch (_) {}
  }));
}

async function notifyLike({ comment, actorId, actorName, productId }) {
  if (!comment || !comment.userId || comment.userId === actorId) return;
  if (!(await commentNotificationsEnabled(comment.userId))) return;
  await deliver({
    userId: comment.userId,
    docId: notifyId(['comment_like', comment.id, actorId]),
    title: 'Mtu amechukua maoni yako',
    body: `${actorName || 'Mtu'} ame-like maoni yako: "${truncate(comment.text, 60)}"`,
    type: 'comment_like',
    data: { productId, commentId: comment.id },
  });
}

module.exports = {
  notifySellerOfComment,
  notifyReply,
  notifyMentions,
  notifyLike,
  // exported for tests
  notifyId,
  truncate,
};
