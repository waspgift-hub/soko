const { Router } = require('express');
const { authenticate, optionalAuth } = require('../../middleware/auth');
const feedService = require('./feed-service');

const router = Router();

// Public feed, cursor paginated
router.get('/', optionalAuth, async (req, res) => {
  const result = await feedService.getFeed({
    requesterId: req.user ? req.user.uid : null,
    cursor: req.query.cursor,
    limit: req.query.limit || 15,
  });
  res.json({ success: true, data: result });
});

module.exports = router;
