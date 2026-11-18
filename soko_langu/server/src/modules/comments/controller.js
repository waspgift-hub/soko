// Firestore-only product comments. The flat `comments` collection is the single
// store; author info is denormalized per comment (Firebase UID + display
// fields) so list/serialize need no join.
//
// Response contracts stay backwards compatible with the shipped Flutter build:
//   GET  /products/:id/comments   → data.items[] (+ pagination fields)
//   GET  /comments/:id/replies    → data[]           (+ top-level page object)
//   POST/PATCH/DELETE             → data = the affected comment
//
// Ownership is always proven server-side from the product doc or the comment
// doc — never from a role or uid supplied by the client.
const store = require('./comment-store');
const notifications = require('./comment-notifications');
const { containsProfanity } = require('../../services/profanity');

const DEFAULT_LIMIT = store.DEFAULT_LIMIT;

function fail(res, error, fallback) {
  const status = error.status || 500;
  const code = error.code || error.message || fallback;
  if (status >= 500) console.error('[COMMENTS]', error.message);
  return res.status(status).json({ success: false, error: code, code, message: error.message || fallback });
}

async function authorOf(req) {
  const uid = req.firebaseUid;
  const profile = await store.resolveAuthor(uid);
  return {
    userId: uid,
    userName: profile.userName,
    username: profile.username,
    userImage: profile.userImage,
  };
}

function assertClean(text) {
  if (containsProfanity(text)) {
    const e = new Error('PROFANITY_DETECTED');
    e.status = 422;
    e.code = 'PROFANITY_DETECTED';
    throw e;
  }
}

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

async function listComments(req, res) {
  try {
    const product = await store.getProduct(req.params.id);
    if (!product) {
      return res.status(404).json({ success: false, error: 'PRODUCT_NOT_FOUND' });
    }
    const data = await store.listComments({
      targetId: req.params.id,
      userId: req.firebaseUid || null,
      sort: req.query.sort,
      cursor: req.query.cursor || null,
      limit: req.query.limit || DEFAULT_LIMIT,
    });
    // The seller can switch comments off per listing; the client must know
    // before it renders a composer that the server will reject.
    return res.json({
      success: true,
      data: {
        ...data,
        // Legacy pagination echo: builds shipped before cursor pagination read
        // these two fields. They are informational only.
        page: 1,
        limit: data.items.length,
        commentsEnabled: product.commentsEnabled !== false,
      },
    });
  } catch (error) {
    return fail(res, error, 'Failed to load comments');
  }
}

async function listReplies(req, res) {
  try {
    const data = await store.listReplies({
      parentId: req.params.id,
      userId: req.firebaseUid || null,
      cursor: req.query.cursor || null,
      limit: req.query.limit || 30,
    });
    // `data` stays an array for the shipped client; `page` carries the cursor.
    return res.json({
      success: true,
      data: data.items,
      page: { nextCursor: data.nextCursor, hasMore: data.hasMore },
    });
  } catch (error) {
    return fail(res, error, 'Failed to load replies');
  }
}

// ---------------------------------------------------------------------------
// Writes
// ---------------------------------------------------------------------------

async function addComment(req, res) {
  try {
    const product = await store.getProduct(req.params.id);
    if (!product) return res.status(404).json({ success: false, error: 'PRODUCT_NOT_FOUND' });

    const text = String((req.body && req.body.text) || '');
    assertClean(text);

    const author = await authorOf(req);
    const mentions = await store.resolveMentions(text).catch(() => []);
    const data = await store.addComment({
      targetId: req.params.id,
      ...author,
      content: text,
      mentions,
    });

    // The comment is durable; notifications must not hold the HTTP response
    // open while they write the inbox and call the push provider.
    res.status(201).json({ success: true, data });
    void notifications
      .notifySellerOfComment({ product, comment: data, actorName: author.userName })
      .catch(() => {});
    void notifications
      .notifyMentions({
        mentions,
        comment: data,
        productId: req.params.id,
        actorId: author.userId,
        actorName: author.userName,
      })
      .catch(() => {});
    return;
  } catch (error) {
    return fail(res, error, 'Failed to add comment');
  }
}

async function addReply(req, res) {
  try {
    const parent = await store.getComment(req.params.id);
    if (!parent || parent.deletedAt) {
      return res.status(404).json({ success: false, error: 'COMMENT_NOT_FOUND' });
    }

    const text = String((req.body && req.body.text) || '');
    assertClean(text);

    const author = await authorOf(req);
    const mentions = await store.resolveMentions(text).catch(() => []);
    const data = await store.addReply({
      commentId: req.params.id,
      replyToId: (req.body && req.body.replyToId) || null,
      ...author,
      content: text,
      mentions,
    });

    res.status(201).json({ success: true, data });
    void notifications
      .notifyReply({ parent, reply: data, productId: parent.targetId, actorName: author.userName })
      .catch(() => {});
    void notifications
      .notifyMentions({
        mentions,
        comment: data,
        productId: parent.targetId,
        actorId: author.userId,
        actorName: author.userName,
      })
      .catch(() => {});
    return;
  } catch (error) {
    return fail(res, error, 'Failed to add reply');
  }
}

async function editComment(req, res) {
  try {
    const text = String((req.body && req.body.text) || '');
    assertClean(text);
    const data = await store.editComment({
      commentId: req.params.id,
      userId: req.firebaseUid,
      content: text,
    });
    return res.json({ success: true, data });
  } catch (error) {
    return fail(res, error, 'Failed to edit comment');
  }
}

async function deleteComment(req, res) {
  try {
    await store.deleteComment({ commentId: req.params.id, userId: req.firebaseUid });
    return res.json({ success: true });
  } catch (error) {
    return fail(res, error, 'Failed to delete comment');
  }
}

async function deleteReply(req, res) {
  try {
    const reply = await store.getComment(req.params.replyId);
    if (!reply || reply.deletedAt || String(reply.parentId) !== String(req.params.id)) {
      return res.status(404).json({ success: false, error: 'REPLY_NOT_FOUND' });
    }
    await store.deleteComment({ commentId: req.params.replyId, userId: req.firebaseUid });
    return res.json({ success: true });
  } catch (error) {
    return fail(res, error, 'Failed to delete reply');
  }
}

async function toggleLike(req, res) {
  try {
    const result = await store.toggleLike({
      commentId: req.params.id,
      userId: req.firebaseUid,
    });

    if (result.liked) {
      const [comment, author] = await Promise.all([
        store.getComment(req.params.id).catch(() => null),
        authorOf(req).catch(() => null),
      ]);
      void notifications
        .notifyLike({
          comment,
          actorId: req.firebaseUid,
          actorName: author && author.userName,
          productId: comment && comment.targetId,
        })
        .catch(() => {});
    }

    return res.json({ success: true, data: { liked: result.liked, likeCount: result.likeCount } });
  } catch (error) {
    return fail(res, error, 'Failed to update like');
  }
}

async function pinComment(req, res) {
  try {
    const data = await store.setPinned({
      commentId: req.params.id,
      userId: req.firebaseUid,
      pinned: true,
    });
    return res.json({ success: true, data });
  } catch (error) {
    return fail(res, error, 'Failed to pin comment');
  }
}

async function unpinComment(req, res) {
  try {
    const data = await store.setPinned({
      commentId: req.params.id,
      userId: req.firebaseUid,
      pinned: false,
    });
    return res.json({ success: true, data });
  } catch (error) {
    return fail(res, error, 'Failed to unpin comment');
  }
}

async function reportComment(req, res) {
  try {
    const data = await store.reportComment({
      commentId: req.params.id,
      userId: req.firebaseUid,
      reason: req.body && req.body.reason,
    });
    return res.status(201).json({ success: true, data });
  } catch (error) {
    return fail(res, error, 'Failed to report comment');
  }
}

// Toggles the per-product comments switch. Only the product owner or a
// platform moderator may call it; the store re-proves ownership.
async function updateCommentSettings(req, res) {
  try {
    const body = req.body || {};
    const enabled = body.enabled !== false;
    const data = await store.setCommentsEnabled({
      productId: req.params.id,
      userId: req.firebaseUid,
      enabled,
    });
    return res.json({ success: true, data });
  } catch (error) {
    return fail(res, error, 'Failed to update comment settings');
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
  editComment,
  deleteComment,
  deleteReply,
  toggleLike,
  pinComment,
  unpinComment,
  reportComment,
  updateCommentSettings,
  serializeComment,
};
