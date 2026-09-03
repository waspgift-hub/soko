const express = require('express');
const router = express.Router();
const { checkHealth } = require('./service');

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
