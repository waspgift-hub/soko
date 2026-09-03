const express = require('express');
const router = express.Router();
const { authenticate, requireActive } = require('../../middleware/auth');
const { 
  getSettings, 
  updateSettings, 
  requestDeletion, 
  exportData 
} = require('./controller');

// Get all settings for current user
router.get('/', authenticate, requireActive, getSettings);

// Update settings for a specific domain
router.put('/:domain', authenticate, requireActive, updateSettings);

// Request account deletion
router.post('/request-deletion', authenticate, requireActive, requestDeletion);

// Export user data
router.post('/export', authenticate, exportData);

module.exports = router;
