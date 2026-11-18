const express = require('express');
const router = express.Router();
const { authenticate, optionalAuth, authenticateAdmin } = require('../../middleware/auth');
const controller = require('./controller');
const {
  buyerRequestLimiter,
  buyerRequestWriteLimiter,
} = require('../../middleware/rateLimiter');

// Limiters run before auth so abusive traffic never pays for token verification
// or a user lookup.
router.get('/buyer-requests/config', buyerRequestLimiter, optionalAuth, controller.getConfig);
router.get('/buyer-requests', buyerRequestLimiter, optionalAuth, controller.listFeed);

router.post('/buyer-requests', buyerRequestWriteLimiter, authenticate, controller.create);
router.get('/buyer-requests/mine', buyerRequestLimiter, authenticate, controller.listMine);
router.get('/buyer-requests/notification-preferences', buyerRequestLimiter, authenticate, controller.getNotificationPrefs);
router.patch('/buyer-requests/notification-preferences', buyerRequestWriteLimiter, authenticate, controller.updateNotificationPrefs);
router.get('/buyer-requests/:id', buyerRequestLimiter, optionalAuth, controller.getDetail);
router.patch('/buyer-requests/:id', buyerRequestWriteLimiter, authenticate, controller.update);
router.post('/buyer-requests/:id/extend', buyerRequestWriteLimiter, authenticate, controller.extend);
router.post('/buyer-requests/:id/close', buyerRequestWriteLimiter, authenticate, controller.close);
router.post('/buyer-requests/:id/reopen', buyerRequestWriteLimiter, authenticate, controller.reopen);
router.post('/buyer-requests/:id/view', buyerRequestLimiter, authenticate, controller.trackView);
router.get('/buyer-requests/:id/views', buyerRequestLimiter, authenticate, controller.getViews);
router.get('/buyer-requests/:id/offers', buyerRequestLimiter, authenticate, controller.getOffers);
router.post('/buyer-requests/:id/offers', buyerRequestWriteLimiter, authenticate, controller.createOffer);
router.delete('/buyer-requests/:id/offers/:offerId', buyerRequestWriteLimiter, authenticate, controller.withdrawOffer);
router.post('/buyer-requests/:id/offers/:offerId/decide', buyerRequestWriteLimiter, authenticate, controller.decideOffer);
router.get('/buyer-requests/:id/sellers/:sellerId/contact', buyerRequestLimiter, authenticate, controller.getSellerContact);
router.post('/buyer-requests/:id/sellers/:sellerId/whatsapp-click', buyerRequestLimiter, authenticate, controller.recordWhatsappClick);
router.get('/buyer-requests/:id/history', buyerRequestLimiter, authenticate, controller.getHistory);

// Admin router (separate mount).
const adminRouter = express.Router();
adminRouter.get('/buyer-requests/config', buyerRequestLimiter, authenticateAdmin, controller.adminConfig);
adminRouter.patch('/buyer-requests/config', buyerRequestWriteLimiter, authenticateAdmin, controller.adminUpdateConfig);
adminRouter.get('/buyer-requests/dashboard', buyerRequestLimiter, authenticateAdmin, controller.adminDashboard);
adminRouter.get('/buyer-requests', buyerRequestLimiter, authenticateAdmin, controller.adminListRequests);
adminRouter.get('/buyer-requests/:id', buyerRequestLimiter, authenticateAdmin, controller.adminDetail);
adminRouter.post('/buyer-requests/:id/moderate', buyerRequestWriteLimiter, authenticateAdmin, controller.adminModerate);
adminRouter.post('/buyer-requests/:id/offers/:offerId/moderate', buyerRequestWriteLimiter, authenticateAdmin, controller.adminModerateOffer);

router.adminRouter = adminRouter;
module.exports = router;
module.exports.adminRouter = adminRouter;
