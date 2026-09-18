const { getPrisma } = require('../../config/database');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DEFAULT_LIMIT = 100;
const MAX_CONTENT = 2000;

// A product may be addressed by its Postgres uuid OR the legacy opaque
// Firestore doc id (the app still keys comment UIs off the legacy id for
// pre-backfill listings). uuid columns reject non-uuid values, so only the id
// arm runs when the parameter looks like a uuid.
async function resolveProduct(prisma, productId) {
  if (UUID_RE.test(productId)) {
    const byId = await prisma.product.findFirst({
      where: { id: productId, deletedAt: null },
      select: { id: true, sellerId: true },
    });
    if (byId) return byId;
  }
  const byLegacy = await prisma.product.findFirst({
    where: { snapshot: { path: ['legacyId'], equals: productId }, deletedAt: null },
    select: { id: true, sellerId: true },
  });
  return byLegacy;
}

const AUTHOR_SELECT = {
  firebaseUid: true,
  displayName: true,
  avatarUrl: true,
};

function serializeComment(comment, replyCount) {
  return {
    id: comment.id,
    userId: comment.user.firebaseUid,
    userName: comment.user.displayName || 'Unknown',
    userImage: comment.user.avatarUrl || null,
    text: comment.content,
    createdAt: comment.createdAt.toISOString(),
    replyCount,
  };
}

async function replyCountFor(prisma, commentId) {
  return prisma.comment.count({
    where: { parentId: commentId, deletedAt: null },
  });
}

// GET /api/v1/products/:id/comments?page&limit — top-level comments, newest first.
async function listComments(req, res) {
  try {
    const prisma = getPrisma();
    const product = await resolveProduct(prisma, req.params.id);
    if (!product) return res.status(404).json({ error: 'PRODUCT_NOT_FOUND' });

    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(100, Math.max(1, parseInt(req.query.limit, 10) || DEFAULT_LIMIT));

    const comments = await prisma.comment.findMany({
      where: { targetId: product.id, targetType: 'product', parentId: null, deletedAt: null },
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * limit,
      take: limit,
      include: { user: { select: AUTHOR_SELECT } },
    });

    const withCount = await Promise.all(
      comments.map(async (c) => serializeComment(c, await replyCountFor(prisma, c.id))),
    );

    res.json({ success: true, data: { items: withCount, page, limit } });
  } catch (error) {
    console.error('[COMMENTS] list error:', error.message);
    res.status(500).json({ error: 'Failed to load comments' });
  }
}

// POST /api/v1/products/:id/comments {text}
async function addComment(req, res) {
  try {
    const prisma = getPrisma();
    const product = await resolveProduct(prisma, req.params.id);
    if (!product) return res.status(404).json({ error: 'PRODUCT_NOT_FOUND' });
    const text = String(req.body && req.body.text || '').trim();
    if (!text) return res.status(400).json({ error: 'EMPTY_TEXT' });
    if (text.length > MAX_CONTENT) return res.status(400).json({ error: 'TEXT_TOO_LONG' });

    // userId is the req.user Prisma uuid (User.id, @db.Uuid). The API contract
    // below replays the Firestore users/{uid} shape (userId = Firebase UID).
    const comment = await prisma.comment.create({
      data: {
        userId: req.user.id,
        targetId: product.id,
        targetType: 'product',
        content: text,
      },
      include: { user: { select: AUTHOR_SELECT } },
    });

    res.status(201).json({
      success: true,
      data: serializeComment(comment, 0),
    });
  } catch (error) {
    console.error('[COMMENTS] add error:', error.message);
    res.status(500).json({ error: 'Failed to add comment' });
  }
}

// GET /api/v1/comments/:id/replies
async function listReplies(req, res) {
  try {
    const prisma = getPrisma();
    const parent = await prisma.comment.findUnique({ where: { id: req.params.id } });
    if (!parent || parent.deletedAt) return res.status(404).json({ error: 'COMMENT_NOT_FOUND' });

    const replies = await prisma.comment.findMany({
      where: { parentId: parent.id, deletedAt: null },
      orderBy: { createdAt: 'asc' },
      include: { user: { select: AUTHOR_SELECT } },
    });

    res.json({
      success: true,
      data: replies.map((r) => serializeComment(r, 0)),
    });
  } catch (error) {
    console.error('[COMMENTS] list replies error:', error.message);
    res.status(500).json({ error: 'Failed to load replies' });
  }
}

// POST /api/v1/comments/:id/replies {text}
async function addReply(req, res) {
  try {
    const prisma = getPrisma();
    const parent = await prisma.comment.findUnique({ where: { id: req.params.id } });
    if (!parent || parent.deletedAt) return res.status(404).json({ error: 'COMMENT_NOT_FOUND' });
    const text = String(req.body && req.body.text || '').trim();
    if (!text) return res.status(400).json({ error: 'EMPTY_TEXT' });
    if (text.length > MAX_CONTENT) return res.status(400).json({ error: 'TEXT_TOO_LONG' });

    const reply = await prisma.comment.create({
      data: {
        userId: req.user.id,
        targetId: parent.targetId,
        targetType: parent.targetType,
        content: text,
        parentId: parent.id,
      },
      include: { user: { select: AUTHOR_SELECT } },
    });

    res.status(201).json({
      success: true,
      data: serializeComment(reply, 0),
    });
  } catch (error) {
    console.error('[COMMENTS] add reply error:', error.message);
    res.status(500).json({ error: 'Failed to add reply' });
  }
}

// DELETE /api/v1/comments/:id — author or product owner (soft delete)
async function deleteComment(req, res) {
  try {
    const prisma = getPrisma();
    const comment = await prisma.comment.findUnique({ where: { id: req.params.id } });
    if (!comment || comment.deletedAt) return res.status(404).json({ error: 'COMMENT_NOT_FOUND' });

    const product = await prisma.product.findFirst({
      where: { id: comment.targetId, deletedAt: null },
      select: { sellerId: true },
    });
    const isAuthor = comment.userId === req.user.id;
    const isProductOwner = product && product.sellerId === req.user.id;
    if (!isAuthor && !isProductOwner) return res.status(403).json({ error: 'FORBIDDEN' });

    await prisma.comment.update({
      where: { id: comment.id },
      data: { deletedAt: new Date() },
    });

    res.json({ success: true });
  } catch (error) {
    console.error('[COMMENTS] delete error:', error.message);
    res.status(500).json({ error: 'Failed to delete comment' });
  }
}

// DELETE /api/v1/comments/:id/replies/:replyId — author or product owner
async function deleteReply(req, res) {
  try {
    const prisma = getPrisma();
    const parent = await prisma.comment.findUnique({ where: { id: req.params.id } });
    if (!parent || parent.deletedAt) return res.status(404).json({ error: 'COMMENT_NOT_FOUND' });

    const reply = await prisma.comment.findUnique({ where: { id: req.params.replyId } });
    if (!reply || reply.parentId !== parent.id || reply.deletedAt) {
      return res.status(404).json({ error: 'REPLY_NOT_FOUND' });
    }

    const product = await prisma.product.findFirst({
      where: { id: parent.targetId, deletedAt: null },
      select: { sellerId: true },
    });
    const isAuthor = reply.userId === req.user.id;
    const isProductOwner = product && product.sellerId === req.user.id;
    if (!isAuthor && !isProductOwner) return res.status(403).json({ error: 'FORBIDDEN' });

    await prisma.comment.update({
      where: { id: reply.id },
      data: { deletedAt: new Date() },
    });

    res.json({ success: true });
  } catch (error) {
    console.error('[COMMENTS] delete reply error:', error.message);
    res.status(500).json({ error: 'Failed to delete reply' });
  }
}

module.exports = {
  listComments,
  addComment,
  listReplies,
  addReply,
  deleteComment,
  deleteReply,
  serializeComment,
  resolveProduct,
};