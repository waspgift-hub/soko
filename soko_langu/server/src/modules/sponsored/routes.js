const { Router } = require('express');
const { authenticate, optionalAuth, requireActive, verifyAdmin } = require('../../middleware/auth');
const { validate } = require('../../middleware/validation');
const { z } = require('zod');
const service = require('./sponsored-service');
const { writeAudit, auditFromReq } = require('../../services/audit');

const router = Router();

// Admin moderation may authenticate either with the shared x-admin-secret (the
// legacy admin tooling) or a Firebase token whose Postgres user has an admin
// role. optionalAuth attaches req.user when a token is present without
// rejecting secret-only callers; verifyAdmin then accepts either.
const adminGate = [optionalAuth, verifyAdmin];

// ─── Seller-facing routes ─────────────────────────────────────────────────

// List all budget tier presets (bronze/silver/gold) for the creation flow.
router.get('/budget-tiers', authenticate, requireActive, (req, res) => {
  res.json({ success: true, data: service.DEFAULT_BUDGET_TIERS });
});

// List a seller's campaigns.
router.get(
  '/campaigns',
  authenticate,
  requireActive,
  validate({
    query: z.object({
      status: z.enum(['draft', 'payment_pending', 'active', 'paused', 'completed', 'cancelled', 'rejected', 'expired', 'out_of_budget']).optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(20),
    }),
  }),
  async (req, res) => {
    try {
      const profile = await service.resolveSellerProfile(req.user.id);
      if (!profile) throw { status: 404, message: 'SELLER_PROFILE_NOT_FOUND' };
      const data = await service.listSellerCampaigns({
        sellerProfileId: profile.id,
        status: req.query.status,
        page: Number(req.query.page),
        limit: Number(req.query.limit),
      });
      res.json({ success: true, data });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to list campaigns' });
    }
  }
);

// Create a draft campaign.
router.post(
  '/campaigns',
  authenticate,
  requireActive,
  validate({
    body: z.object({
      name: z.string().min(1).max(200),
      dailyBudgetTzs: z.number().int().positive(),
      totalBudgetTzs: z.number().int().positive(),
      bidAmountTzs: z.number().int().positive(),
      placement: z.enum(['search', 'listing', 'detail', 'category', 'recommendations', 'product_feed', 'store_discovery', 'featured']).default('search'),
      startsAt: z.string().datetime(),
      expiresAt: z.string().datetime(),
      productIds: z.array(z.string().uuid()).optional().default([]),
      isAllProducts: z.boolean().optional().default(false),
    }),
  }),
  async (req, res) => {
    try {
      const profile = await service.resolveSellerProfile(req.user.id);
      if (!profile) throw { status: 404, message: 'SELLER_PROFILE_NOT_FOUND' };
      const campaign = await service.createCampaign({
        sellerProfileId: profile.id,
        data: req.body,
      });
      await writeAudit({
        ...auditFromReq(req),
        action: 'sponsored.campaign.create',
        entityType: 'SponsoredCampaign',
        entityId: campaign.id,
        newState: { name: campaign.name, status: campaign.status },
      });
      res.status(201).json({ success: true, data: campaign });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to create campaign' });
    }
  }
);

// Get a single campaign.
router.get(
  '/campaigns/:id',
  authenticate,
  requireActive,
  validate({ params: z.object({ id: z.string().uuid() }) }),
  async (req, res) => {
    try {
      const profile = await service.resolveSellerProfile(req.user.id);
      if (!profile) throw { status: 404, message: 'SELLER_PROFILE_NOT_FOUND' };
      const data = await service.getCampaign({ campaignId: req.params.id, sellerProfileId: profile.id });
      res.json({ success: true, data });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to fetch campaign' });
    }
  }
);

// Update a campaign (name, bid, status).
router.put(
  '/campaigns/:id',
  authenticate,
  requireActive,
  validate({
    params: z.object({ id: z.string().uuid() }),
    body: z.object({
      name: z.string().min(1).max(200).optional(),
      bidAmountTzs: z.number().int().positive().optional(),
      status: z.enum(['draft', 'payment_pending', 'active', 'paused', 'completed', 'cancelled']).optional(),
    }),
  }),
  async (req, res) => {
    try {
      const profile = await service.resolveSellerProfile(req.user.id);
      if (!profile) throw { status: 404, message: 'SELLER_PROFILE_NOT_FOUND' };
      const campaign = await service.updateCampaign({
        campaignId: req.params.id,
        sellerProfileId: profile.id,
        data: req.body,
      });
      await writeAudit({
        ...auditFromReq(req),
        action: 'sponsored.campaign.update',
        entityType: 'SponsoredCampaign',
        entityId: req.params.id,
      });
      res.json({ success: true, data: campaign });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to update campaign' });
    }
  }
);

// Pause a campaign.
router.post(
  '/campaigns/:id/pause',
  authenticate,
  requireActive,
  validate({ params: z.object({ id: z.string().uuid() }) }),
  async (req, res) => {
    try {
      const profile = await service.resolveSellerProfile(req.user.id);
      if (!profile) throw { status: 404, message: 'SELLER_PROFILE_NOT_FOUND' };
      await service.pauseCampaign({ campaignId: req.params.id, sellerProfileId: profile.id });
      await writeAudit({ ...auditFromReq(req), action: 'sponsored.campaign.pause', entityType: 'SponsoredCampaign', entityId: req.params.id });
      res.json({ success: true });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to pause campaign' });
    }
  }
);

// Resume a paused campaign.
router.post(
  '/campaigns/:id/resume',
  authenticate,
  requireActive,
  validate({ params: z.object({ id: z.string().uuid() }) }),
  async (req, res) => {
    try {
      const profile = await service.resolveSellerProfile(req.user.id);
      if (!profile) throw { status: 404, message: 'SELLER_PROFILE_NOT_FOUND' };
      await service.resumeCampaign({ campaignId: req.params.id, sellerProfileId: profile.id });
      await writeAudit({ ...auditFromReq(req), action: 'sponsored.campaign.resume', entityType: 'SponsoredCampaign', entityId: req.params.id });
      res.json({ success: true });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to resume campaign' });
    }
  }
);

// Cancel a campaign.
router.post(
  '/campaigns/:id/cancel',
  authenticate,
  requireActive,
  validate({ params: z.object({ id: z.string().uuid() }) }),
  async (req, res) => {
    try {
      const profile = await service.resolveSellerProfile(req.user.id);
      if (!profile) throw { status: 404, message: 'SELLER_PROFILE_NOT_FOUND' };
      await service.cancelCampaign({ campaignId: req.params.id, sellerProfileId: profile.id });
      await writeAudit({ ...auditFromReq(req), action: 'sponsored.campaign.cancel', entityType: 'SponsoredCampaign', entityId: req.params.id });
      res.json({ success: true });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to cancel campaign' });
    }
  }
);

// Initiate payment for a campaign.
router.post(
  '/campaigns/:id/pay',
  authenticate,
  requireActive,
  validate({
    params: z.object({ id: z.string().uuid() }),
    body: z.object({
      phone: z.string().min(9).max(20),
      paymentMethod: z.enum(['ussd_push', 'billpay']).default('ussd_push'),
    }),
  }),
  async (req, res) => {
    try {
      const profile = await service.resolveSellerProfile(req.user.id);
      if (!profile) throw { status: 404, message: 'SELLER_PROFILE_NOT_FOUND' };
      const result = await service.initiateCampaignPayment({
        campaignId: req.params.id,
        sellerProfileId: profile.id,
        phone: req.body.phone,
        paymentMethod: req.body.paymentMethod,
      });
      await writeAudit({ ...auditFromReq(req), action: 'sponsored.campaign.pay', entityType: 'SponsoredCampaign', entityId: req.params.id });
      res.json({ success: true, data: result });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to initiate payment' });
    }
  }
);

// Get metrics for a single campaign.
router.get(
  '/campaigns/:id/metrics',
  authenticate,
  requireActive,
  validate({
    params: z.object({ id: z.string().uuid() }),
    query: z.object({ days: z.coerce.number().int().min(1).max(365).default(30).optional() }),
  }),
  async (req, res) => {
    try {
      const profile = await service.resolveSellerProfile(req.user.id);
      if (!profile) throw { status: 404, message: 'SELLER_PROFILE_NOT_FOUND' };
      const data = await service.getCampaignMetrics({
        campaignId: req.params.id,
        sellerProfileId: profile.id,
        days: Number(req.query.days),
      });
      res.json({ success: true, data });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to fetch metrics' });
    }
  }
);

// Record a click on a sponsored placement (public, for fraud tracking).
router.post(
  '/placement/click',
  validate({
    body: z.object({
      campaignId: z.string().uuid(),
      productId: z.string().uuid(),
    }),
  }),
  async (req, res) => {
    try {
      const ipAddress = req.ip;
      const userAgent = req.headers['user-agent'] || '';
      const userId = req.user?.id;
      await service.recordClick({
        campaignId: req.body.campaignId,
        productId: req.body.productId,
        userId,
        ipAddress,
        userAgent: typeof userAgent === 'string' ? userAgent : '',
      });
      res.json({ success: true });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to record click' });
    }
  }
);

// ─── Admin routes ─────────────────────────────────────────────────────────
// Mounted at /api/v1/sponsored/admin/*. Auth: x-admin-secret OR a Firebase
// admin token (see adminGate). Every moderation action is audited.

// Platform-wide sponsored metrics for the admin dashboard.
router.get('/admin/metrics', ...adminGate, async (req, res) => {
  try {
    const data = await service.getAdminSponsoredMetrics({
      days: Number(req.query.days) || 30,
    });
    res.json({ success: true, data });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message || 'Failed to fetch admin metrics' });
  }
});

// List all campaigns (admin), optionally filtered by status.
router.get(
  '/admin/campaigns',
  ...adminGate,
  validate({
    query: z.object({
      status: z.enum(['draft', 'payment_pending', 'active', 'paused', 'completed', 'cancelled', 'rejected', 'expired', 'out_of_budget']).optional(),
      page: z.coerce.number().int().min(1).default(1),
      limit: z.coerce.number().int().min(1).max(100).default(50),
    }),
  }),
  async (req, res) => {
    try {
      const data = await service.adminListCampaigns({
        status: req.query.status,
        page: Number(req.query.page),
        limit: Number(req.query.limit),
      });
      res.json({ success: true, data });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to list campaigns' });
    }
  }
);

// Single campaign with placement + payment + audit history.
router.get(
  '/admin/campaigns/:id',
  ...adminGate,
  validate({ params: z.object({ id: z.string().uuid() }) }),
  async (req, res) => {
    try {
      const data = await service.adminGetCampaign(req.params.id);
      res.json({ success: true, data });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to fetch campaign' });
    }
  }
);

// Moderation actions. Each requires a reason-free confirmation from the panel;
// reject accepts an optional reason that is stored in the audit log.
router.post(
  '/admin/campaigns/:id/approve',
  ...adminGate,
  validate({ params: z.object({ id: z.string().uuid() }) }),
  async (req, res) => {
    try {
      const data = await service.adminApproveCampaign({
        campaignId: req.params.id,
        adminActorId: req.user?.id || null,
        ipAddress: req.ip,
        userAgent: req.headers['user-agent'] || '',
      });
      await writeAudit({ ...auditFromReq(req), action: 'sponsored.campaign.approve', entityType: 'SponsoredCampaign', entityId: req.params.id });
      res.json({ success: true, data });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to approve campaign' });
    }
  }
);

router.post(
  '/admin/campaigns/:id/reject',
  ...adminGate,
  validate({
    params: z.object({ id: z.string().uuid() }),
    body: z.object({ reason: z.string().max(500).optional() }).optional().default({}),
  }),
  async (req, res) => {
    try {
      const data = await service.adminRejectCampaign({
        campaignId: req.params.id,
        adminActorId: req.user?.id || null,
        reason: req.body?.reason,
        ipAddress: req.ip,
        userAgent: req.headers['user-agent'] || '',
      });
      await writeAudit({ ...auditFromReq(req), action: 'sponsored.campaign.reject', entityType: 'SponsoredCampaign', entityId: req.params.id });
      res.json({ success: true, data });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to reject campaign' });
    }
  }
);

router.post(
  '/admin/campaigns/:id/pause',
  ...adminGate,
  validate({ params: z.object({ id: z.string().uuid() }) }),
  async (req, res) => {
    try {
      const data = await service.adminPauseCampaign({
        campaignId: req.params.id,
        adminActorId: req.user?.id || null,
        ipAddress: req.ip,
        userAgent: req.headers['user-agent'] || '',
      });
      await writeAudit({ ...auditFromReq(req), action: 'sponsored.campaign.pause', entityType: 'SponsoredCampaign', entityId: req.params.id });
      res.json({ success: true, data });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to pause campaign' });
    }
  }
);

router.post(
  '/admin/campaigns/:id/resume',
  ...adminGate,
  validate({ params: z.object({ id: z.string().uuid() }) }),
  async (req, res) => {
    try {
      const data = await service.adminResumeCampaign({
        campaignId: req.params.id,
        adminActorId: req.user?.id || null,
        ipAddress: req.ip,
        userAgent: req.headers['user-agent'] || '',
      });
      await writeAudit({ ...auditFromReq(req), action: 'sponsored.campaign.resume', entityType: 'SponsoredCampaign', entityId: req.params.id });
      res.json({ success: true, data });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to resume campaign' });
    }
  }
);

router.post(
  '/admin/campaigns/:id/end',
  ...adminGate,
  validate({ params: z.object({ id: z.string().uuid() }) }),
  async (req, res) => {
    try {
      const data = await service.adminEndCampaign({
        campaignId: req.params.id,
        adminActorId: req.user?.id || null,
        ipAddress: req.ip,
        userAgent: req.headers['user-agent'] || '',
      });
      await writeAudit({ ...auditFromReq(req), action: 'sponsored.campaign.end', entityType: 'SponsoredCampaign', entityId: req.params.id });
      res.json({ success: true, data });
    } catch (e) {
      res.status(e.status || 500).json({ error: e.message || 'Failed to end campaign' });
    }
  }
);

// Get or update admin settings.
router.get('/admin/settings', ...adminGate, async (req, res) => {
  try {
    const [data, limits] = await Promise.all([
      service.getSettings(),
      service.getSponsorshipLimits(),
    ]);
    res.json({ success: true, data: { settings: data, limits } });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message || 'Failed to fetch settings' });
  }
});

router.put('/admin/settings', ...adminGate, async (req, res) => {
  try {
    const { key, value, description } = req.body;
    if (!key) return res.status(400).json({ error: 'SETTING_KEY_REQUIRED' });
    const data = await service.updateSetting(key, value, description);
    res.json({ success: true, data });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message || 'Failed to update setting' });
  }
});

// Manually run the status reconciliation sweep (expired / out_of_budget).
router.post('/admin/sweep', ...adminGate, async (req, res) => {
  try {
    const data = await service.sweepCampaignStatuses({ force: true });
    res.json({ success: true, data });
  } catch (e) {
    res.status(e.status || 500).json({ error: e.message || 'Failed to run sweep' });
  }
});

module.exports = router;
