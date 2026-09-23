const { getStore, getReadStore } = require('../../config/database');
const cache = require('../../../cache');

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

// Campaign lifecycle statuses. Mirrors the state machine enforced in the
// service: draft -> payment_pending -> active -> (paused | completed | cancelled).
// Admin moderation can additionally move a campaign to rejected, and the
// system sweep marks lapsed campaigns expired or out_of_budget.
const CAMPAIGN_STATUSES = {
  DRAFT: 'draft',
  PAYMENT_PENDING: 'payment_pending',
  ACTIVE: 'active',
  PAUSED: 'paused',
  COMPLETED: 'completed',
  CANCELLED: 'cancelled',
  REJECTED: 'rejected',
  EXPIRED: 'expired',
  OUT_OF_BUDGET: 'out_of_budget',
};

// Statuses a seller may set directly through the update endpoint. Moderation
// outcomes (rejected/expired/out_of_budget) are admin/system only.
const SELLER_SETTABLE_STATUSES = [
  CAMPAIGN_STATUSES.DRAFT,
  CAMPAIGN_STATUSES.PAYMENT_PENDING,
  CAMPAIGN_STATUSES.ACTIVE,
  CAMPAIGN_STATUSES.PAUSED,
  CAMPAIGN_STATUSES.COMPLETED,
  CAMPAIGN_STATUSES.CANCELLED,
];

// Terminal states can no longer transition.
const TERMINAL_STATUSES = [
  CAMPAIGN_STATUSES.COMPLETED,
  CAMPAIGN_STATUSES.CANCELLED,
  CAMPAIGN_STATUSES.REJECTED,
  CAMPAIGN_STATUSES.EXPIRED,
];

// Admin settings keys controlling budget/duration limits for new campaigns.
const SETTING_KEYS = {
  MIN_BUDGET: 'sponsored_min_budget_tzs',
  MAX_BUDGET: 'sponsored_max_budget_tzs',
  MIN_DURATION: 'sponsored_min_duration_days',
  MAX_DURATION: 'sponsored_max_duration_days',
};

// Defaults applied when an admin has not configured a limit.
const SETTING_DEFAULTS = {
  [SETTING_KEYS.MIN_BUDGET]: 1000,
  [SETTING_KEYS.MAX_BUDGET]: 10000000,
  [SETTING_KEYS.MIN_DURATION]: 1,
  [SETTING_KEYS.MAX_DURATION]: 90,
};


// Placement surfaces a campaign can appear in. `search`/`listing`/`detail`
// are the original three; the rest extend the surfaces exposed by the app
// navigation (category browse, recommendations, product feed, store discovery)
// plus the premium featured slot.
const PLACEMENT_TYPES = [
  'search',
  'listing',
  'detail',
  'category',
  'recommendations',
  'product_feed',
  'store_discovery',
  'featured',
];

// Default budget tiers matching legacy Boost tier economics, so sellers
// recognise the pricing when migrating: Bronze/Silver/Gold.
const DEFAULT_BUDGET_TIERS = [
  { key: 'bronze', name: 'Bronze', dailyBudget: 1500, durationDays: 3, color: '#CD7F32' },
  { key: 'silver', name: 'Silver', dailyBudget: 3000, durationDays: 7, color: '#C0C0C0' },
  { key: 'gold', name: 'Gold', dailyBudget: 10000, durationDays: 30, color: '#FFD700' },
];

// Resolve a seller (and their profile id) by Firebase UID. The v2 auth
// middleware attaches the Postgres `users` row to req.user, but callers may
// also pass a Firebase UID string from legacy client calls.
async function resolveSellerProfile(userId) {
  const store = getStore();
  if (userId && userId.length === 36) {
    const profile = await store.sellerProfile.findUnique({
      where: { id: userId },
      select: { id: true, storeName: true, userId: true },
    });
    if (profile) return profile;
  }
  const profile = await store.sellerProfile.findFirst({
    where: { userId: userId },
    select: { id: true, storeName: true, userId: true },
  });
  return profile;
}

// Validate that the authenticated user owns the seller profile for the
// campaign, or is an admin.
async function requireSellerForCampaign(campaignId, reqUser) {
  const store = getStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { sellerId: true, name: true },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (reqUser && (reqUser.id === campaign.sellerId || reqUser.role === 'admin' || reqUser.role === 'super_admin')) {
    return campaign;
  }
  throw httpError(403, 'NOT_CAMPAIGN_OWNER');
}

// Create a draft campaign. The campaign starts in `draft` status and must
// have its payment confirmed before it can be activated.
async function createCampaign({ sellerProfileId, data }) {
  const store = getStore();

  const {
    name,
    dailyBudgetTzs,
    totalBudgetTzs,
    bidAmountTzs,
    placement = 'search',
    startsAt,
    expiresAt,
    productIds = [],
    isAllProducts = false,
  } = data;

  if (!name || name.trim().length < 1) throw httpError(400, 'CAMPAIGN_NAME_REQUIRED');
  if (!placement || !PLACEMENT_TYPES.includes(placement)) throw httpError(400, 'INVALID_PLACEMENT');
  if (dailyBudgetTzs == null || dailyBudgetTzs <= 0) throw httpError(400, 'BUDGET_REQUIRED');
  if (totalBudgetTzs == null || totalBudgetTzs <= 0) throw httpError(400, 'TOTAL_BUDGET_REQUIRED');
  if (bidAmountTzs == null || bidAmountTzs <= 0) throw httpError(400, 'BID_AMOUNT_REQUIRED');
  if (!startsAt || !expiresAt) throw httpError(400, 'SCHEDULE_REQUIRED');

  const start = new Date(startsAt);
  const end = new Date(expiresAt);
  if (end <= start) throw httpError(400, 'EXPIRY_MUST_BE_AFTER_START');

  const now = new Date();
  if (start <= now) throw httpError(400, 'START_MUST_BE_IN_FUTURE');

  // Enforce the admin-configured budget/duration limits so the settings panel
  // is authoritative rather than decorative.
  const limits = await getSponsorshipLimits();
  if (dailyBudgetTzs < limits.minBudgetTzs || totalBudgetTzs > limits.maxBudgetTzs) {
    throw httpError(400, 'BUDGET_OUT_OF_RANGE');
  }
  const durationDays = Math.ceil((end - start) / (24 * 60 * 60 * 1000));
  if (durationDays < limits.minDurationDays || durationDays > limits.maxDurationDays) {
    throw httpError(400, 'DURATION_OUT_OF_RANGE');
  }

  // Verify all product ids belong to this seller.
  if (productIds.length > 0 && !isAllProducts) {
    const ownedCount = await store.product.count({
      where: { id: { in: productIds }, sellerId: sellerProfileId, deletedAt: null },
    });
    if (ownedCount !== productIds.length) throw httpError(403, 'PRODUCT_NOT_OWNED');
  }

  return await store.$transaction(async (tx) => {
    const campaign = await tx.sponsoredCampaign.create({
      data: {
        sellerId: sellerProfileId,
        name: name.trim(),
        dailyBudgetTzs,
        totalBudgetTzs,
        bidAmountTzs,
        placement,
        startsAt: start,
        expiresAt: end,
        status: CAMPAIGN_STATUSES.DRAFT,
        placements: isAllProducts
          ? undefined
          : {
              create: productIds.map((pid) => ({
                productId: pid,
                isAllProducts: false,
              })),
            },
      },
      include: { placements: true },
    });

    await tx.campaignAuditLog.create({
      data: {
        campaignId: campaign.id,
        actorId: sellerProfileId,
        actorType: 'user',
        action: 'campaign.created',
        newState: { name, dailyBudgetTzs, totalBudgetTzs, bidAmountTzs, placement, status: 'draft' },
      },
    });

    return campaign;
  });
}

// Update a draft/paused campaign. Only non-financial fields can be edited
// after creation to prevent bid manipulation mid-flight.
async function updateCampaign({ campaignId, sellerProfileId, data }) {
  const store = getStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { sellerId: true, status: true },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (campaign.sellerId !== sellerProfileId) throw httpError(403, 'NOT_CAMPAIGN_OWNER');
  if (campaign.status !== CAMPAIGN_STATUSES.DRAFT && campaign.status !== CAMPAIGN_STATUSES.PAUSED) {
    throw httpError(409, 'CANNOT_EDIT_ACTIVE_CAMPAIGN');
  }

  const { name, bidAmountTzs, status } = data;
  const patch = {};
  if (name !== undefined) patch.name = name.trim();
  if (bidAmountTzs !== undefined) patch.bidAmountTzs = bidAmountTzs;
  if (status !== undefined) {
    if (!SELLER_SETTABLE_STATUSES.includes(status)) throw httpError(400, 'INVALID_STATUS');
    patch.status = status;
  }

  const updated = await store.sponsoredCampaign.update({
    where: { id: campaignId },
    data: patch,
  });

  await store.campaignAuditLog.create({
    data: {
      campaignId,
      actorId: sellerProfileId,
      actorType: 'user',
      action: 'campaign.updated',
      oldState: { status: campaign.status },
      newState: { status: updated.status, name: updated.name },
    },
  });

  cache.delPattern(`sponsored:campaigns:${sellerProfileId}:*`);
  return updated;
}

// Pause an active campaign.
async function pauseCampaign({ campaignId, sellerProfileId }) {
  const store = getStore();
  const campaign = await getOwnedCampaign(store, campaignId, sellerProfileId);
  if (campaign.status !== CAMPAIGN_STATUSES.ACTIVE) throw httpError(409, 'CANNOT_PAUSE_INACTIVE');

  await store.sponsoredCampaign.update({
    where: { id: campaignId },
    data: { status: CAMPAIGN_STATUSES.PAUSED },
  });
  await store.campaignAuditLog.create({
    data: {
      campaignId,
      actorId: sellerProfileId,
      actorType: 'user',
      action: 'campaign.paused',
      oldState: { status: campaign.status },
      newState: { status: 'paused' },
    },
  });
  cache.delPattern(`sponsored:campaigns:${sellerProfileId}:*`);
}

// Resume a paused campaign.
async function resumeCampaign({ campaignId, sellerProfileId }) {
  const store = getStore();
  const campaign = await getOwnedCampaign(store, campaignId, sellerProfileId);
  if (campaign.status !== CAMPAIGN_STATUSES.PAUSED) throw httpError(409, 'CANNOT_RESUME');
  if (new Date() > campaign.expiresAt) throw httpError(400, 'CAMPAIGN_EXPIRED');

  await store.sponsoredCampaign.update({
    where: { id: campaignId },
    data: { status: CAMPAIGN_STATUSES.ACTIVE },
  });
  await store.campaignAuditLog.create({
    data: {
      campaignId,
      actorId: sellerProfileId,
      actorType: 'user',
      action: 'campaign.resumed',
      oldState: { status: campaign.status },
      newState: { status: 'active' },
    },
  });
  cache.delPattern(`sponsored:campaigns:${sellerProfileId}:*`);
}

// Cancel a campaign (any state except completed).
async function cancelCampaign({ campaignId, sellerProfileId }) {
  const store = getStore();
  const campaign = await getOwnedCampaign(store, campaignId, sellerProfileId);
  if (campaign.status === CAMPAIGN_STATUSES.COMPLETED) throw httpError(409, 'CANNOT_CANCEL_COMPLETED');

  await store.sponsoredCampaign.update({
    where: { id: campaignId },
    data: { status: CAMPAIGN_STATUSES.CANCELLED },
  });
  await store.campaignAuditLog.create({
    data: {
      campaignId,
      actorId: sellerProfileId,
      actorType: 'user',
      action: 'campaign.cancelled',
      oldState: { status: campaign.status },
      newState: { status: 'cancelled' },
    },
  });
  cache.delPattern(`sponsored:campaigns:${sellerProfileId}:*`);
}

// Mark a campaign as active (called by the payment webhook after confirmation).
async function activateCampaign({ campaignId, paymentId }) {
  const store = getStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { status: true, sellerId: true, startsAt: true, expiresAt: true, payment: { select: { id: true, status: true } } },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (campaign.status !== CAMPAIGN_STATUSES.PAYMENT_PENDING) throw httpError(409, 'CANNOT_ACTIVATE');

  await store.$transaction(async (tx) => {
    await tx.sponsoredCampaign.update({
      where: { id: campaignId },
      data: { status: CAMPAIGN_STATUSES.ACTIVE },
    });
    if (paymentId) {
      await tx.campaignPayment.update({
        where: { id: paymentId },
        data: { status: 'completed', verifiedAt: new Date() },
      });
    }
    await tx.campaignAuditLog.create({
      data: {
        campaignId,
        actorId: null,
        actorType: 'system',
        action: 'campaign.activated',
        oldState: { status: campaign.status },
        newState: { status: 'active' },
      },
    });
  });
  cache.delPattern(`sponsored:campaigns:${campaign.sellerId}:*`);
  cache.delPattern('sponsored:placements:*');
}

async function getOwnedCampaign(store, campaignId, sellerProfileId) {
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { sellerId: true, status: true, expiresAt: true, startsAt: true },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (campaign.sellerId !== sellerProfileId) throw httpError(403, 'NOT_CAMPAIGN_OWNER');
  return campaign;
}

// List a seller's campaigns with optional status filter and pagination.
async function listSellerCampaigns({ sellerProfileId, status, page = 1, limit = 20 }) {
  const store = getReadStore();
  const cacheKey = `sponsored:campaigns:${sellerProfileId}:${status || 'all'}:p${page}:l${limit}`;
  const cached = await cache.get(cacheKey);
  if (cached) return cached;

  // Opportunistically reconcile lapsed/exhausted campaigns so the dashboard
  // reflects reality. Throttled internally; failures never block the list.
  try {
    await sweepCampaignStatuses();
  } catch (e) {
    console.error('[Sponsored] status sweep failed:', e.message);
  }

  const where = { sellerId: sellerProfileId, ...(status ? { status } : {}) };
  const [items, total] = await Promise.all([
    store.sponsoredCampaign.findMany({
      where,
      include: { placements: { include: { product: { select: { id: true, title: true } } } } },
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    store.sponsoredCampaign.count({ where }),
  ]);

  const result = { items, pagination: { page: Number(page), limit: Number(limit), total } };
  await cache.set(cacheKey, result, 15 * 1000);
  return result;
}

// Get a single campaign with placements and payment info.
async function getCampaign({ campaignId, sellerProfileId }) {
  const store = getStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    include: {
      placements: {
        include: {
          product: {
            select: { id: true, title: true, slug: true, price: true },
          },
        },
      },
      payment: { select: { id: true, status: true, amountTzs: true, provider: true, providerOrderId: true, createdAt: true } },
      auditLogs: { orderBy: { createdAt: 'desc' }, take: 50 },
    },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (campaign.sellerId !== sellerProfileId) throw httpError(403, 'NOT_CAMPAIGN_OWNER');
  return campaign;
}

// Get active sponsored placements for a product category (used by the search/catalog
// engine to interleave sponsored results). Fraud protection: deduplicates by IP+userAgent
// so a single client can't inflate impression counts.
async function getActivePlacements({ categoryId, placement, limit = 10, ipAddress, userAgent }) {
  const cacheKey = `sponsored:placements:${placement || 'all'}:${categoryId || 'all'}:l${limit}`;
  const cached = await cache.get(cacheKey);
  if (cached) return cached;

  const store = getReadStore();
  const now = new Date();

  // Fraud protection: deduplicate impressions per (campaign, ip, userAgent) within a 60s window.
  // This prevents impression inflation via rapid refreshes.
  const recentImpressions = await store.campaignEvent.findMany({
    where: {
      eventType: 'impression',
      createdAt: { gte: new Date(now.getTime() - 60000) },
      ipAddress: ipAddress || undefined,
    },
    select: { campaignId: true },
    distinct: ['campaignId'],
  });
  const dedupedCampaignIds = new Set(recentImpressions.map((r) => r.campaignId));

  const query = {
    where: {
      status: CAMPAIGN_STATUSES.ACTIVE,
      startsAt: { lte: now },
      expiresAt: { gte: now },
      ...(placement ? { placement } : {}),
      ...(categoryId
        ? { placements: { some: { product: { categoryId: categoryId } } } }
        : {}),
    },
    orderBy: { bidAmountTzs: 'desc' },
    take: Number(limit),
    include: {
      placements: {
        where: { product: { categoryId: categoryId || undefined } },
        include: {
          product: {
            select: {
              id: true,
              title: true,
              slug: true,
              price: true,
              currency: true,
              originalPrice: true,
              seller: { select: { id: true, storeName: true, storeSlug: true } },
              media: { orderBy: { sortOrder: 'asc' }, take: 1 },
            },
          },
        },
      },
    },
  };

  let placements = await store.sponsoredCampaign.findMany(query);

  // Filter out campaigns that have hit their daily budget or total budget.
  placements = placements.filter((c) => {
    if (dedupedCampaignIds.has(c.id)) return false;
    const spend = Number(c.spendTzs) || 0;
    if (spend >= Number(c.totalBudgetTzs)) return false;
    return true;
  });

  // Sort by effective bid (bid minus spend ratio) and take top N.
  placements.sort((a, b) => {
    const aScore = Number(a.bidAmountTzs) * (1 - (spendRatio(a) || 0));
    const bScore = Number(b.bidAmountTzs) * (1 - (spendRatio(b) || 0));
    return bScore - aScore;
  });

  const result = placements.slice(0, limit);

  // Record impression events asynchronously (non-blocking).
  if (ipAddress && userAgent) {
    placements.slice(0, limit).forEach(async (c) => {
      try {
        await store.campaignEvent.create({
          data: {
            campaignId: c.id,
            eventType: 'impression',
            productId: c.placements[0]?.productId,
            ipAddress,
            userAgent,
            bidAmountTzs: c.bidAmountTzs,
          },
        });
        await store.campaignImpression.create({
          data: {
            campaignId: c.id,
            productId: c.placements[0]?.productId || '',
            ipAddress,
            userAgent,
          },
        });
        await store.sponsoredCampaign.update({
          where: { id: c.id },
          data: {
            impressions: { increment: 1 },
            spendTzs: { increment: c.bidAmountTzs },
          },
        });
      } catch (e) {
        // Non-blocking: impression tracking failure shouldn't break the feed.
        console.error('[Sponsored] impression tracking failed:', e.message);
      }
    });
  }

  await cache.set(cacheKey, result, 30 * 1000);
  return result;
}

function spendRatio(campaign) {
  const total = Number(campaign.totalBudgetTzs) || 1;
  const spent = Number(campaign.spendTzs) || 0;
  return Math.min(spent / total, 1);
}

// Record a click on a sponsored placement. Prevents self-clicking by
// checking that the clicker is not the campaign owner.
async function recordClick({ campaignId, productId, userId, ipAddress, userAgent }) {
  const store = getStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { sellerId: true, status: true },
  });
  if (!campaign) return;
  if (userId && campaign.sellerId === userId) {
    // Self-click fraud protection: log but don't count.
    await store.campaignEvent.create({
      data: {
        campaignId,
        eventType: 'self_click_blocked',
        productId,
        userId,
        ipAddress,
        userAgent,
      },
    });
    return;
  }

  await store.$transaction(async (tx) => {
    await tx.campaignEvent.create({
      data: { campaignId, eventType: 'click', productId, userId, ipAddress, userAgent },
    });
    await tx.campaignClick.create({
      data: { campaignId, productId, userId, ipAddress, userAgent },
    });
    await tx.sponsoredCampaign.update({
      where: { id: campaignId },
      data: { clicks: { increment: 1 } },
    });
  });
}

// Get campaign performance metrics for a seller's campaign.
async function getCampaignMetrics({ campaignId, sellerProfileId, days = 30 }) {
  const store = getReadStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { sellerId: true, name: true },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (campaign.sellerId !== sellerProfileId) throw httpError(403, 'NOT_CAMPAIGN_OWNER');

  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

  const [impressions, clicks, spend] = await Promise.all([
    store.campaignImpression.count({ where: { campaignId, createdAt: { gte: since } } }),
    store.campaignClick.count({ where: { campaignId, createdAt: { gte: since } } }),
    store.sponsoredCampaign.findUnique({
      where: { id: campaignId },
      select: { spendTzs: true, impressions: true, clicks: true },
    }),
  ]);

  return {
    campaignId,
    campaignName: campaign.name,
    impressions: impressions,
    clicks: clicks,
    spendTzs: Number(spend?.spendTzs) || 0,
    ctr: clicks > 0 ? clicks / impressions : 0,
  };
}

// Get platform-wide ad performance for the admin dashboard.
async function getAdminSponsoredMetrics({ days = 30 }) {
  const store = getReadStore();
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

  try {
    await sweepCampaignStatuses();
  } catch (e) {
    console.error('[Sponsored] status sweep failed:', e.message);
  }

  const [campaigns, impressions, clicks, payments] = await Promise.all([
    store.sponsoredCampaign.findMany({
      where: { createdAt: { gte: since } },
      select: { id: true, name: true, status: true, dailyBudgetTzs: true, totalBudgetTzs: true, spendTzs: true, impressions: true, clicks: true, createdAt: true },
    }),
    store.campaignImpression.count({ where: { createdAt: { gte: since } } }),
    store.campaignClick.count({ where: { createdAt: { gte: since } } }),
    store.campaignPayment.findMany({
      where: { createdAt: { gte: since }, status: 'completed' },
      select: { amountTzs: true, createdAt: true },
    }),
  ]);

  const totalSpend = campaigns.reduce((sum, c) => sum + (Number(c.spendTzs) || 0), 0);
  const totalRevenue = payments.reduce((sum, p) => sum + (Number(p.amountTzs) || 0), 0);
  const totalImpressions = impressions;
  const totalClicks = clicks;

  const countByStatus = (s) => campaigns.filter((c) => c.status === s).length;

  return {
    campaigns,
    summary: {
      totalCampaigns: campaigns.length,
      activeCampaigns: countByStatus(CAMPAIGN_STATUSES.ACTIVE),
      pendingCampaigns: countByStatus(CAMPAIGN_STATUSES.PAYMENT_PENDING),
      rejectedCampaigns: countByStatus(CAMPAIGN_STATUSES.REJECTED),
      totalImpressions,
      totalClicks,
      totalSpendTzs: totalSpend,
      totalRevenueTzs: totalRevenue,
      ctr: totalImpressions > 0 ? totalClicks / totalImpressions : 0,
    },
  };
}

// Initiate a ClickPesa payment for a campaign budget. Returns order reference.
async function initiateCampaignPayment({ campaignId, sellerProfileId, phone, paymentMethod }) {
  const { clickpesaCollect, clickpesaCreateBillPayOrder, calcGatewayFee } = require('../../../clickpesa');
  const { v4: uuidv4 } = require('uuid');

  const store = getStore();

  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { sellerId: true, status: true, totalBudgetTzs: true, name: true, payment: { select: { id: true } } },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (campaign.sellerId !== sellerProfileId) throw httpError(403, 'NOT_CAMPAIGN_OWNER');
  if (campaign.status !== CAMPAIGN_STATUSES.DRAFT) throw httpError(409, 'CAMPAIGN_NOT_DRAFT');

  const isBillPay = paymentMethod === 'billpay';
  const amount = Number(campaign.totalBudgetTzs);
  const gatewayFee = calcGatewayFee(isBillPay ? 'billpay' : 'ussd_push', amount);
  const totalToCollect = isBillPay ? amount + gatewayFee : amount;
  const orderReference = `camp_${Date.now()}_${uuidv4().slice(0, 8)}`;

  return await store.$transaction(async (tx) => {
    const payment = await tx.campaignPayment.create({
      data: {
        campaignId,
        provider: isBillPay ? 'clickpesa_billpay' : 'clickpesa_ussd',
        amountTzs: totalToCollect,
        status: 'pending',
        providerOrderId: orderReference,
      },
    });

    await tx.sponsoredCampaign.update({
      where: { id: campaignId },
      data: { status: CAMPAIGN_STATUSES.PAYMENT_PENDING, paymentId: payment.id },
    });

    await tx.campaignAuditLog.create({
      data: {
        campaignId,
        actorId: sellerProfileId,
        actorType: 'user',
        action: 'campaign.payment_initiated',
        newState: { paymentId: payment.id, amountTzs: totalToCollect, method: paymentMethod },
      },
    });

    let providerResponse = {};
    try {
      if (isBillPay) {
        providerResponse = await clickpesaCreateBillPayOrder({
          billAmount: totalToCollect,
          billDescription: `Soko Vibe Sponsored: ${campaign.name}`,
          billPaymentMode: 'EXACT',
          billReference: orderReference,
        });
      } else {
        const normalizedPhone = normalizePhone(phone || '');
        providerResponse = await clickpesaCollect({
          amount: totalToCollect,
          orderReference,
          phoneNumber: normalizedPhone,
        });
      }
    } catch (e) {
      await tx.campaignPayment.update({
        where: { id: payment.id },
        data: { status: 'failed' },
      });
      throw httpError(502, `Payment provider error: ${e.message}`);
    }

    return {
      paymentId: payment.id,
      orderReference,
      amount,
      gatewayFee,
      totalAmount: totalToCollect,
      providerResponse,
    };
  });
}

function normalizePhone(phone) {
  const digits = String(phone || '').replace(/\D/g, '');
  if (digits.startsWith('0')) return '255' + digits.slice(1);
  return digits.startsWith('255') ? digits : '255' + digits;
}

// Process a webhook/confirm callback for a campaign payment.
async function confirmPayment({ orderReference, status, paymentId }) {
  const store = getStore();
  const payment = await store.campaignPayment.findUnique({
    where: orderReference ? { providerOrderId: orderReference } : { id: paymentId },
    select: { id: true, campaignId: true, status: true, amountTzs: true },
  });
  if (!payment) throw httpError(404, 'PAYMENT_NOT_FOUND');
  if (payment.status === 'completed') return { alreadyProcessed: true };

  if (status === 'completed' || status === 'success') {
    await activateCampaign({ campaignId: payment.campaignId, paymentId: payment.id });
    return { activated: true, paymentId: payment.id, campaignId: payment.campaignId };
  } else {
    await store.campaignPayment.update({
      where: { id: payment.id },
      data: { status: 'failed' },
    });
    return { activated: false, paymentId: payment.id };
  }
}

// Get all admin settings (masked for secrets).
async function getSettings() {
  const store = getReadStore();
  const settings = await store.adminSetting.findMany();
  const masked = settings.map((s) => ({
    key: s.key,
    value: s.value,
    description: s.description,
  }));
  return masked;
}

// Update an admin setting.
async function updateSetting(key, value, description) {
  const store = getStore();
  return await store.adminSetting.upsert({
    where: { key },
    update: { value, description, updatedAt: new Date() },
    create: { key, value, description },
  });
}

// Resolve the effective budget/duration limits, falling back to defaults when
// an admin has not configured them. Values are stored as strings in
// AdminSetting, so coerce defensively.
async function getSponsorshipLimits() {
  const store = getReadStore();
  const rows = await store.adminSetting.findMany({
    where: { key: { in: Object.values(SETTING_KEYS) } },
    select: { key: true, value: true },
  });
  const map = new Map(rows.map((r) => [r.key, r.value]));
  const read = (key) => {
    const parsed = Number(map.get(key));
    return Number.isFinite(parsed) && parsed > 0 ? parsed : SETTING_DEFAULTS[key];
  };
  return {
    minBudgetTzs: read(SETTING_KEYS.MIN_BUDGET),
    maxBudgetTzs: read(SETTING_KEYS.MAX_BUDGET),
    minDurationDays: read(SETTING_KEYS.MIN_DURATION),
    maxDurationDays: read(SETTING_KEYS.MAX_DURATION),
  };
}

// List campaigns platform-wide for the admin panel.
async function adminListCampaigns({ status, page = 1, limit = 50 }) {
  const store = getReadStore();
  const where = status ? { status } : {};
  const [campaigns, total] = await Promise.all([
    store.sponsoredCampaign.findMany({
      where,
      include: {
        seller: { select: { id: true, storeName: true, userId: true } },
        payment: { select: { id: true, status: true, amountTzs: true } },
      },
      orderBy: { createdAt: 'desc' },
      take: Number(limit),
      skip: (Number(page) - 1) * Number(limit),
    }),
    store.sponsoredCampaign.count({ where }),
  ]);
  return { campaigns, pagination: { page: Number(page), limit: Number(limit), total } };
}

// Get a single campaign with full audit history for the admin panel.
async function adminGetCampaign(campaignId) {
  const store = getReadStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    include: {
      seller: { select: { id: true, storeName: true, userId: true } },
      placements: {
        include: { product: { select: { id: true, title: true, slug: true, price: true } } },
      },
      payment: true,
      auditLogs: { orderBy: { createdAt: 'desc' }, take: 100 },
    },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  return campaign;
}

// Apply an audited status transition driven by an admin. Centralising this
// keeps every moderation action consistent and auditable.
async function adminSetStatus({
  campaignId,
  adminActorId,
  nextStatus,
  action,
  reason,
  ipAddress,
  userAgent,
}) {
  const store = getStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { id: true, status: true, sellerId: true },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (campaign.status === nextStatus) return campaign;

  const updated = await store.$transaction(async (tx) => {
    const c = await tx.sponsoredCampaign.update({
      where: { id: campaignId },
      data: { status: nextStatus },
    });
    await tx.campaignAuditLog.create({
      data: {
        campaignId,
        actorId: adminActorId || null,
        actorType: 'admin',
        action,
        oldState: { status: campaign.status },
        newState: { status: nextStatus, ...(reason ? { reason } : {}) },
        ipAddress: ipAddress || null,
        userAgent: userAgent || null,
      },
    });
    return c;
  });

  cache.delPattern(`sponsored:campaigns:${campaign.sellerId}:*`);
  cache.delPattern('sponsored:placements:*');
  return updated;
}

// Admin: approve a campaign into active service (overrides the payment gate,
// but every override is recorded in the audit log).
async function adminApproveCampaign({ campaignId, adminActorId, ipAddress, userAgent }) {
  const store = getStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { status: true },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (![CAMPAIGN_STATUSES.DRAFT, CAMPAIGN_STATUSES.PAYMENT_PENDING, CAMPAIGN_STATUSES.PAUSED].includes(campaign.status)) {
    throw httpError(409, 'CANNOT_APPROVE');
  }
  return adminSetStatus({
    campaignId,
    adminActorId,
    nextStatus: CAMPAIGN_STATUSES.ACTIVE,
    action: 'campaign.approved',
    ipAddress,
    userAgent,
  });
}

// Admin: reject a campaign (terminal). Any non-terminal campaign can be rejected.
async function adminRejectCampaign({ campaignId, adminActorId, reason, ipAddress, userAgent }) {
  const store = getStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { status: true },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (TERMINAL_STATUSES.includes(campaign.status)) throw httpError(409, 'CAMPAIGN_TERMINAL');
  return adminSetStatus({
    campaignId,
    adminActorId,
    nextStatus: CAMPAIGN_STATUSES.REJECTED,
    action: 'campaign.rejected',
    reason,
    ipAddress,
    userAgent,
  });
}

// Admin: pause any active campaign.
async function adminPauseCampaign({ campaignId, adminActorId, ipAddress, userAgent }) {
  const store = getStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { status: true },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (campaign.status !== CAMPAIGN_STATUSES.ACTIVE) throw httpError(409, 'CANNOT_PAUSE_INACTIVE');
  return adminSetStatus({
    campaignId,
    adminActorId,
    nextStatus: CAMPAIGN_STATUSES.PAUSED,
    action: 'campaign.paused',
    ipAddress,
    userAgent,
  });
}

// Admin: resume a paused campaign (unless it has already lapsed).
async function adminResumeCampaign({ campaignId, adminActorId, ipAddress, userAgent }) {
  const store = getStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { status: true, expiresAt: true },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (campaign.status !== CAMPAIGN_STATUSES.PAUSED) throw httpError(409, 'CANNOT_RESUME');
  if (new Date() > campaign.expiresAt) throw httpError(400, 'CAMPAIGN_EXPIRED');
  return adminSetStatus({
    campaignId,
    adminActorId,
    nextStatus: CAMPAIGN_STATUSES.ACTIVE,
    action: 'campaign.resumed',
    ipAddress,
    userAgent,
  });
}

// Admin: end a campaign early (terminal completed).
async function adminEndCampaign({ campaignId, adminActorId, ipAddress, userAgent }) {
  const store = getStore();
  const campaign = await store.sponsoredCampaign.findUnique({
    where: { id: campaignId },
    select: { status: true },
  });
  if (!campaign) throw httpError(404, 'CAMPAIGN_NOT_FOUND');
  if (![CAMPAIGN_STATUSES.ACTIVE, CAMPAIGN_STATUSES.PAUSED].includes(campaign.status)) {
    throw httpError(409, 'CANNOT_END');
  }
  return adminSetStatus({
    campaignId,
    adminActorId,
    nextStatus: CAMPAIGN_STATUSES.COMPLETED,
    action: 'campaign.ended',
    ipAddress,
    userAgent,
  });
}

// Sweep active campaigns whose schedule lapsed (expired) or whose budget is
// exhausted (out_of_budget). Throttled so it runs at most once a minute, and
// safe to call from any read path.
let lastSweepAt = 0;
async function sweepCampaignStatuses({ force = false } = {}) {
  const now = Date.now();
  if (!force && now - lastSweepAt < 60 * 1000) return { skipped: true };
  lastSweepAt = now;

  const store = getStore();
  const nowDate = new Date();
  const active = await store.sponsoredCampaign.findMany({
    where: { status: CAMPAIGN_STATUSES.ACTIVE },
    select: { id: true, expiresAt: true, spendTzs: true, totalBudgetTzs: true },
  });

  const expiredIds = [];
  const outOfBudgetIds = [];
  for (const c of active) {
    if (c.expiresAt < nowDate) expiredIds.push(c.id);
    else if (Number(c.spendTzs) >= Number(c.totalBudgetTzs)) outOfBudgetIds.push(c.id);
  }

  await store.$transaction([
    store.sponsoredCampaign.updateMany({
      where: { id: { in: expiredIds } },
      data: { status: CAMPAIGN_STATUSES.EXPIRED },
    }),
    store.sponsoredCampaign.updateMany({
      where: { id: { in: outOfBudgetIds } },
      data: { status: CAMPAIGN_STATUSES.OUT_OF_BUDGET },
    }),
  ]);

  if (expiredIds.length || outOfBudgetIds.length) {
    cache.delPattern('sponsored:placements:*');
  }
  return { expired: expiredIds.length, outOfBudget: outOfBudgetIds.length };
}

module.exports = {
  CAMPAIGN_STATUSES,
  SELLER_SETTABLE_STATUSES,
  TERMINAL_STATUSES,
  SETTING_KEYS,
  SETTING_DEFAULTS,
  PLACEMENT_TYPES,
  DEFAULT_BUDGET_TIERS,
  httpError,
  resolveSellerProfile,
  createCampaign,
  updateCampaign,
  pauseCampaign,
  resumeCampaign,
  cancelCampaign,
  activateCampaign,
  confirmPayment,
  listSellerCampaigns,
  getCampaign,
  getCampaignMetrics,
  getActivePlacements,
  recordClick,
  initiateCampaignPayment,
  getAdminSponsoredMetrics,
  adminListCampaigns,
  adminGetCampaign,
  adminApproveCampaign,
  adminRejectCampaign,
  adminPauseCampaign,
  adminResumeCampaign,
  adminEndCampaign,
  sweepCampaignStatuses,
  getSponsorshipLimits,
  getSettings,
  updateSetting,
};
