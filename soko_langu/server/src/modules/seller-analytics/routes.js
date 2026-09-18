// Seller analytics bridge — Phase F routes.
// Mounted at /api/v1. The sellers/… and boosts/… paths are deliberately
// distinct from the existing sellersRouter (/request, /profile, /me, /dashboard)
// and products/boosts legacy paths, so both can share the /api/v1 prefix
// without shadowing each other.
const { Router } = require('express');
const { getSellerAnalyticsOverview, recordBoostImpression, recordBoostClick } = require('./controller');

const router = Router();

router.get('/sellers/:sellerId/analytics/overview', getSellerAnalyticsOverview);
router.post('/boosts/:boostId/impressions', recordBoostImpression);
router.post('/boosts/:boostId/clicks', recordBoostClick);

module.exports = router;
