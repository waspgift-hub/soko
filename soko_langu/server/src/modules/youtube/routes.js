// GET /api/v1/youtube/search?q=&maxResults= — authenticated (Firebase token)
// so anonymous bots can't burn the search quota. Quota math: 100 units per
// upstream call, cached 1h per query, 25 results max per call.
const { Router } = require('express');
const { authenticate } = require('../../middleware/auth');
const { searchYouTube } = require('./youtube-service');

const router = Router();

router.get('/search', authenticate, async (req, res) => {
  try {
    const data = await searchYouTube({
      q: req.query.q,
      maxResults: req.query.maxResults,
    });
    res.json(data);
  } catch (e) {
    res.status(e.status || 500).json({ success: false, error: e.message || 'YOUTUBE_SEARCH_FAILED' });
  }
});

module.exports = router;
