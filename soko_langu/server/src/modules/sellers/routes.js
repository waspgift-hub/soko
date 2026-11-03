const express = require('express');
const router = express.Router();
const { authenticate, requireActive } = require('../../middleware/auth');
const { 
  requestSellerMode, 
  createSellerProfile, 
  getSellerProfile, 
  updateSellerProfile,
  getSellerDashboard 
} = require('./controller');

// Request to become a seller
router.post('/request', authenticate, requireActive, requestSellerMode);

// Create seller profile
router.post('/profile', authenticate, requireActive, createSellerProfile);

// Get own seller profile
router.get('/me', authenticate, getSellerProfile);

// Update seller profile
router.put('/me', authenticate, requireActive, updateSellerProfile);

// Get seller dashboard data
router.get('/dashboard', authenticate, getSellerDashboard);

module.exports = router;
