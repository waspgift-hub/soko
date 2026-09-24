const { Router } = require('express');
const { authenticate, optionalAuth } = require('../../middleware/auth');
const feedService = require('./feed-service');

const router = Router();

// Public feed, cursor paginated. Ads need the caller's IP/UA for impression
// dedupe and fraud logging, so forward them from the request.
router.get('/', optionalAuth, async (req, res) => {
  const result = await feedService.getFeed({
    requesterId: req.user ? req.user.id : null,
    cursor: req.query.cursor,
    limit: req.query.limit || 15,
    ipAddress: req.ip,
    userAgent: req.headers['user-agent'] || '',
  });
  res.json({ success: true, data: result });
});

module.exports = router;
