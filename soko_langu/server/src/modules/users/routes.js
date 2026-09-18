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
  getPublicProfile 
} = require('./controller');

// Profile bridge (Phase D): mounted at /api/v1/users. These must not live under
// /api/v1/users/settings (where the settings router is mounted) because the
// settings domain routes (PUT /:domain) would swallow /me.
router.get('/me', authenticate, getMe);

// Update the current user's profile (whitelisted storefront fields)
router.put('/me', authenticate, updateMe);

// Public profile of another user by Firebase UID or Postgres uuid (no auth:
// chat/review flows read it for any counterparty)
router.get('/public/:identifier', getPublicProfile);

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