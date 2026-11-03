const { getProvider } = require('./provider-factory');
const paymentService = require('./payment-service');

/**
 * Webhook verification & handling middleware for a given provider.
 * Extracts the raw body, signature header, verifies HMAC, and delegates
 * to paymentService.handleWebhook.
 */
function verifyProviderWebhook(providerName) {
  return async (req, res) => {
    try {
      const provider = getProvider(providerName);
      const signature =
        req.headers['x-signature'] ||
        req.headers['x-checksum'] ||
        req.headers['signature'] ||
        '';

      if (!provider.verifyWebhook(req.body, signature)) {
        return res.status(401).json({ error: 'INVALID_WEBHOOK_SIGNATURE' });
      }

      const result = await paymentService.handleWebhook({
        providerName,
        payload: req.body,
        signature,
        headers: req.headers,
      });

      res.json({ success: true, ...result });
    } catch (error) {
      console.error('[WEBHOOK]', providerName, error.message);
      res.status(error.status || 500).json({ error: error.message || 'WEBHOOK_ERROR' });
    }
  };
}

module.exports = { verifyProviderWebhook };
