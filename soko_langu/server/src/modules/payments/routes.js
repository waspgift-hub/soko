const { Router } = require('express');
const { verifyProviderWebhook } = require('./payment-webhooks');

const router = Router();

// ClickPesa collection webhook - publicly callable but HMAC-verified
router.post('/webhook/clickpesa', verifyProviderWebhook('clickpesa'));

module.exports = router;
