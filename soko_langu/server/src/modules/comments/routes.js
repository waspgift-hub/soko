const express = require('express');
const router = express.Router();
const { authenticate, optionalAuth } = require('../../middleware/auth');
const { commentLimiter, commentLikeLimiter } = require('../../middleware/rateLimiter');
const {
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
} = require('./controller');

// Product comments live in the flat `comments` collection. Reads are public
// (the marketplace allows guests to read product pages); every write requires a
// verified Firebase token, and ownership/moderation is re-proven in the store.
router.get('/products/:id/comments', optionalAuth, listComments);
router.post('/products/:id/comments', authenticate, commentLimiter, addComment);
router.patch(
  '/products/:id/comments/settings',
  authenticate,
  commentLimiter,
  updateCommentSettings,
);

router.get('/comments/:id/replies', optionalAuth, listReplies);
router.post('/comments/:id/replies', authenticate, commentLimiter, addReply);

router.patch('/comments/:id', authenticate, commentLimiter, editComment);
router.delete('/comments/:id', authenticate, deleteComment);
router.delete('/comments/:id/replies/:replyId', authenticate, deleteReply);

router.post('/comments/:id/like', authenticate, commentLikeLimiter, toggleLike);
router.post('/comments/:id/pin', authenticate, pinComment);
router.delete('/comments/:id/pin', authenticate, unpinComment);
router.post('/comments/:id/report', authenticate, commentLimiter, reportComment);

module.exports = router;
