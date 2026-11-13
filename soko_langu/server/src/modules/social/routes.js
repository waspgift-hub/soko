const { Router } = require('express');
const { authenticate, requireActive } = require('../../middleware/auth');
const svc = require('./social-service');

const router = Router();

function wrap(fn) {
  return async (req, res) => {
    try {
      const uid = req.firebaseUid;
      const body = req.body || {};
      const result = await fn(uid, body.targetId || body.requesterId);
      res.json({ success: true, data: result });
    } catch (e) {
      res.status(e.status || 500).json({ success: false, error: e.code || 'INTERNAL_ERROR', message: e.message });
    }
  };
}

router.post('/follow', authenticate, requireActive, wrap((u, t) => svc.follow(u, t)));
router.post('/unfollow', authenticate, requireActive, wrap((u, t) => svc.unfollow(u, t)));
router.post('/accept', authenticate, requireActive, wrap((u, t) => svc.accept(u, t)));
router.post('/reject', authenticate, requireActive, wrap((u, t) => svc.reject(u, t)));
router.post('/cancel', authenticate, requireActive, wrap((u, t) => svc.cancel(u, t)));
router.post('/block', authenticate, requireActive, wrap((u, t) => svc.block(u, t)));
router.post('/unblock', authenticate, requireActive, wrap((u, t) => svc.unblock(u, t)));

module.exports = router;
