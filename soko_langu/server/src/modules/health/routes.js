const express = require('express');
const router = express.Router();
const { checkHealth } = require('./service');

// Tags external dev keep-alive traffic (GitHub Actions scheduler) so logs and
// analytics can distinguish it from real users. Header-only, never blocks.
function devKeepAliveMarker(req, res, next) {
  if ((req.get('user-agent') || '').startsWith('SokoVibe-Dev-KeepAlive')) {
    req.isDevKeepAlive = true;
    res.setHeader('x-keep-alive', 'dev');
  }
  next();
}

router.use(devKeepAliveMarker);

// Liveness-only probe for the external dev keep-alive scheduler. Zero I/O:
// no Firestore/Redis ping, no business logic — just proves the web process is
// alive and answering. The deeper /health stays for Render's healthCheckPath.
router.get('/live', (req, res) => {
  res.json({ status: 'ok' });
});

router.get('/', async (req, res) => {
  try {
    const health = await checkHealth();
    const status = health.status === 'ok' ? 200 : 503;
    res.status(status).json(health);
  } catch (error) {
    res.status(503).json({
      status: 'error',
      message: error.message,
      timestamp: new Date().toISOString(),
    });
  }
});

module.exports = router;
