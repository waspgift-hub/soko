const { Router } = require('express');
const { verifyProviderWebhook } = require('./payment-webhooks');

const router = Router();

// AzamPay collection webhook - publicly callable but HMAC-verified
router.post('/webhook/azampay', verifyProviderWebhook('azampay'));

module.exports = router;
