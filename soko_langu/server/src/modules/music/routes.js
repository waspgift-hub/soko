// GET /api/v1/music/lyrics?title=&artist=&album=&durationMs=
//
// Authenticated (Firebase token) for the same reason as YouTube search: lyrics
// generation can spend AI tokens, and an unauthenticated endpoint on a paid API
// is an open wallet. Rate limited because the AI fallback is billable.
const { Router } = require('express');
const { authenticate } = require('../../middleware/auth');
const { getLyrics } = require('./lyrics-service');

const router = Router();

router.get('/lyrics', authenticate, async (req, res) => {
  try {
    const data = await getLyrics({
      title: req.query.title,
      artist: req.query.artist,
      album: req.query.album,
      durationMs: req.query.durationMs != null ? Number(req.query.durationMs) : undefined,
      // `ai=0` lets a caller ask only for real lyrics, without spending tokens.
      allowAi: req.query.ai !== '0',
    });
    res.json({ success: true, data });
  } catch (e) {
    res.status(e.status || 500).json({
      success: false,
      error: e.message || 'LYRICS_FAILED',
    });
  }
});

module.exports = router;