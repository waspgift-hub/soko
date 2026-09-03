const { Router } = require('express');
const { productOgMeta, sellerOgMeta } = require('./og-generator');

const router = Router();

// OG meta for a product share
router.get('/product/:slugOrId', async (req, res) => {
  const meta = await productOgMeta(req.params.slugOrId);
  if (!meta) return res.status(404).json({ success: false, error: 'NOT_FOUND' });
  res.type('html').send(`<!DOCTYPE html><html><head><title>Soko Vibe</title>${meta}</head><body></body></html>`);
});

// OG meta for a seller share
router.get('/seller/:username', async (req, res) => {
  const meta = await sellerOgMeta(req.params.username);
  if (!meta) return res.status(404).json({ success: false, error: 'NOT_FOUND' });
  res.type('html').send(`<!DOCTYPE html><html><head><title>Soko Vibe</title>${meta}</head><body></body></html>`);
});

module.exports = router;
