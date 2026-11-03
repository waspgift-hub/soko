const { Router } = require('express');
const { authenticate, optionalAuth, requireActive } = require('../../middleware/auth');
const trustPassport = require('./trust-passport');
const sellerReliability = require('./seller-reliability');
const qualityGates = require('./quality-gates');

const router = Router();

// Get trust passport for a seller (public)
router.get('/sellers/:sellerId/passport', optionalAuth, async (req, res) => {
  const data = await trustPassport.getTrustPassport({ sellerId: req.params.sellerId });
  res.json({ success: true, data });
});

// Compute reliability score (internal/admin + seller self)
router.post(
  '/sellers/:sellerId/reliability',
  authenticate,
  requireActive,
  async (req, res) => {
    const score = await sellerReliability.computeSellerReliability({
      sellerId: req.params.sellerId,
    });
    res.json({ success: true, data: { score } });
  }
);

// Quality gates for a seller (with optional product)
router.get(
  '/sellers/:sellerId/gates',
  authenticate,
  requireActive,
  async (req, res) => {
    const result = await qualityGates.evaluateQualityGates({
      sellerId: req.params.sellerId,
      productId: req.query.productId,
    });
    res.json({ success: true, data: result });
  }
);

module.exports = router;
