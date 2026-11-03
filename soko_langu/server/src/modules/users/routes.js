const express = require('express');
const router = express.Router();
const userSettingsRouter = express.Router();
const { authenticate, requireActive } = require('../../middleware/auth');
const { 
  getSettings, 
  updateSettings, 
  requestDeletion, 
  exportData,
  getMe,
  updateMe,
  getPublicProfile,
  checkUsername 
} = require('./controller');
const contactDiscovery = require('./contact-discovery');

// Profile bridge (Phase D): mounted at /api/v1/users. These must not live under
// /api/v1/users/settings (where the settings router is mounted) because the
// settings domain routes (PUT /:domain) would swallow /me.
router.get('/me', authenticate, getMe);

// Update the current user's profile (whitelisted storefront fields)
router.put('/me', authenticate, updateMe);

// Username uniqueness check (profile edit flow)
router.get('/check-username', authenticate, checkUsername);

// Public profile of another user by Firebase UID or Postgres uuid (no auth:
// chat/review flows read it for any counterparty)
router.get('/public/:identifier', getPublicProfile);

router.get('/contact-discovery/status', authenticate, async (req, res) => {
  try {
    const data = await contactDiscovery.status(req.firebaseUid);
    res.json(data);
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

router.post('/contact-discovery/opt-in', authenticate, async (req, res) => {
  try {
    const data = await contactDiscovery.optIn(req.firebaseUid, req.body?.phone);
    res.json(data);
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

router.post('/contact-discovery/opt-out', authenticate, async (req, res) => {
  try {
    const data = await contactDiscovery.optOut(req.firebaseUid);
    res.json(data);
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

router.post('/contact-discovery/match', authenticate, async (req, res) => {
  try {
    const data = await contactDiscovery.matchPhones(req.firebaseUid, req.body?.phones);
    res.json(data);
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message });
  }
});

// Get all settings for current user
userSettingsRouter.get('/', authenticate, requireActive, getSettings);

// Update settings for a specific domain
userSettingsRouter.put('/:domain', authenticate, requireActive, updateSettings);

// Request account deletion
userSettingsRouter.post('/request-deletion', authenticate, requireActive, requestDeletion);

// Export user data
userSettingsRouter.post('/export', authenticate, exportData);

module.exports = userSettingsRouter;
module.exports.profileRouter = router;