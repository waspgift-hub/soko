const express = require('express');
const router = express.Router();
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

// Get the current user's profile (Firestore users/{uid} shape)
router.get('/me', authenticate, getMe);

// Update the current user's profile (whitelisted storefront fields)
router.put('/me', authenticate, updateMe);

// Public profile of another user by Firebase UID or Postgres uuid (no auth:
// chat/review flows read it for any counterparty)
router.get('/public/:identifier', getPublicProfile);

// Get all settings for current user
router.get('/', authenticate, requireActive, getSettings);

// Update settings for a specific domain
router.put('/:domain', authenticate, requireActive, updateSettings);

// Request account deletion
router.post('/request-deletion', authenticate, requireActive, requestDeletion);

// Export user data
router.post('/export', authenticate, exportData);

module.exports = router;
