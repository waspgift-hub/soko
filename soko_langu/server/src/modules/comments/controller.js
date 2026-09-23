// Firestore-only product comments (Phase 3). The flat `comments` collection is
// the single store; author info is denormalized per comment (Firebase UID +
// display fields) so list/serialize need no join. Handlers keep the previous
// response contract so the Flutter side is untouched.
const store = require('./comment-store');

const DEFAULT_LIMIT = 100;

async function listComments(req, res) {
  try {
    if (!(await store.productExists(req.params.id))) {
      return res.status(404).json({ error: 'PRODUCT_NOT_FOUND' });
    }
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || DEFAULT_LIMIT));
    const data = await store.listComments({ targetId: req.params.id, page, limit });
    res.json({ success: true, data });
  } catch (error) {
    console.error('[COMMENTS] list error:', error.message);
    res.status(500).json({ error: 'Failed to load comments' });
  }
}

async function addComment(req, res) {
  try {
    if (!(await store.productExists(req.params.id))) {
      return res.status(404).json({ error: 'PRODUCT_NOT_FOUND' });
    }
    const data = await store.addComment({
      targetId: req.params.id,
      userId: req.firebaseUid,
      userName: req.user.displayName || 'Unknown',
      userImage: req.user.avatarUrl || null,
      content: req.body && req.body.text,
    });
    res.status(201).json({ success: true, data });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message || 'Failed to add comment' });
  }
}

async function listReplies(req, res) {
  try {
    const data = await store.listReplies(req.params.id);
    res.json({ success: true, data });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message || 'Failed to load replies' });
  }
}

async function addReply(req, res) {
  try {
    const data = await store.addReply({
      commentId: req.params.id,
      userId: req.firebaseUid,
      userName: req.user.displayName || 'Unknown',
      userImage: req.user.avatarUrl || null,
      content: req.body && req.body.text,
    });
    res.status(201).json({ success: true, data });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message || 'Failed to add reply' });
  }
}

async function deleteComment(req, res) {
  try {
    await store.deleteComment({ commentId: req.params.id, userId: req.firebaseUid });
    res.json({ success: true });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message || 'Failed to delete comment' });
  }
}

async function deleteReply(req, res) {
  try {
    // A reply is just a comment doc whose parentId matches the parent route.
    const { listReplies: getReplies } = store;
    const replies = await getReplies(req.params.id);
    if (!replies.length) return res.status(404).json({ error: 'REPLY_NOT_FOUND' });
    const target = replies.find((r) => r.id === req.params.replyId);
    if (!target) return res.status(404).json({ error: 'REPLY_NOT_FOUND' });
    await store.deleteComment({ commentId: req.params.replyId, userId: req.firebaseUid });
    res.json({ success: true });
  } catch (error) {
    res.status(error.status || 500).json({ error: error.message || 'Failed to delete reply' });
  }
}

// Dual-shape serializer kept for its unit tests: accepts either a Firestore
// comment doc ({ userId, userName, userImage, content }) or a Prisma-era row
// ({ user: { firebaseUid, displayName, avatarUrl } }).
function serializeComment(comment, replyCount) {
  const author = comment.user || {};
  return {
    id: comment.id,
    userId: comment.userId || author.firebaseUid,
    userName: comment.userName || author.displayName || 'Unknown',
    userImage: comment.userImage != null ? comment.userImage : (author.avatarUrl || null),
    text: comment.content || comment.text,
    createdAt: comment.createdAt instanceof Date ? comment.createdAt.toISOString() : String(comment.createdAt),
    replyCount,
  };
}

module.exports = {
  listComments,
  addComment,
  listReplies,
  addReply,
  deleteComment,
  deleteReply,
  serializeComment,
};