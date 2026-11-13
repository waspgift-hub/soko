const express = require('express');
const router = express.Router();
const { authenticate, optionalAuth } = require('../../middleware/auth');
const {
  listComments,
  addComment,
  listReplies,
  addReply,
  deleteComment,
  deleteReply,
} = require('./controller');

// Product comments (Phase E): keyed by Postgres product uuid OR the legacy
// opaque Firestore doc id (snapshot.legacyId), mirroring the Firestore
// products/{id}/comments sub-collection contract.
router.get('/products/:id/comments', optionalAuth, listComments);
router.post('/products/:id/comments', authenticate, addComment);

router.get('/comments/:id/replies', optionalAuth, listReplies);
router.post('/comments/:id/replies', authenticate, addReply);
router.delete('/comments/:id', authenticate, deleteComment);
router.delete('/comments/:id/replies/:replyId', authenticate, deleteReply);

module.exports = router;