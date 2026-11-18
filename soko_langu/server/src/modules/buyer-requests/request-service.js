// Buyer Request orchestration: policy, privacy boundaries, notifications and
// the handful of cross-document rules that do not belong in the store.
const settingsService = require('../admin/settings-service');
const store = require('./request-store');
const notify = require('./request-notifications');
const {
  httpError,
  badRequest,
  normalizePolicy,
  publicPolicy,
  validateCreateInput,
  validateEditInput,
  validateOfferInput,
  statusFor,
  categoryMatches,
  millis,
  canReopen,
  CATEGORIES,
} = require('./request-config');

const PAGE_SIZE = 20;
const MAX_PAGE = 50;

async function getPolicy() {
  const settings = await settingsService.getSettings();
  return normalizePolicy(settings && settings.buyerRequests);
}

function paging(query = {}) {
  const page = Math.max(1, Math.floor(Number(query.page) || 1));
  const limit = Math.min(MAX_PAGE, Math.max(1, Math.floor(Number(query.limit) || PAGE_SIZE)));
  return { page, limit, offset: (page - 1) * limit };
}

function assertAccountActive(user) {
  if (!user) return;
  const status = user.accountStatus || 'active';
  if (status === 'suspended' || status === 'deleted') {
    throw httpError(403, 'ACCOUNT_SUSPENDED');
  }
}

function isVerified(user) {
  return Boolean(user && user.kyc && user.kyc.approved);
}

function isSellerAccount(user) {
  if (!user) return false;
  const profile = user.sellerProfile || {};
  if (profile.sellerStatus === 'seller') return true;
  return user.role === 'seller';
}

function buyerIdentity(user, uid) {
  return {
    buyerUid: uid,
    buyerName: user?.displayName || user?.name || '',
    buyerAvatarUrl: user?.avatarUrl || '',
    buyerKycApproved: isVerified(user),
  };
}

function applyFeedFilters(rows, query, policy, nowMs) {
  const q = String(query.q || '').trim().toLowerCase();
  const location = String(query.location || '').trim().toLowerCase();
  const category = String(query.category || '').trim().toLowerCase();
  const minBudget = Number(query.minBudget) || 0;
  const maxBudget = Number(query.maxBudget) || 0;

  let out = rows.filter((row) => categoryMatches(row, 'all', policy, nowMs));
  if (q) {
    out = out.filter((row) => [
      row.title, row.description, row.brand, row.model, row.categoryName,
    ].some((value) => String(value || '').toLowerCase().includes(q)));
  }
  if (category) {
    out = out.filter((row) => [
      row.categoryId, row.categoryName,
    ].some((value) => String(value || '').toLowerCase().includes(category)));
  }
  if (location) {
    out = out.filter((row) => String(row.location || '').toLowerCase().includes(location));
  }
  if (minBudget > 0) out = out.filter((row) => Number(row.maxBudget || 0) >= minBudget);
  if (maxBudget > 0) out = out.filter((row) => Number(row.minBudget || 0) <= maxBudget);

  const sort = String(query.sort || 'newest');
  if (sort === 'expiring') {
    out.sort((a, b) => millis(a.expiresAtMs || a.expiresAt) - millis(b.expiresAtMs || b.expiresAt));
  } else if (sort === 'budget_high') {
    out.sort((a, b) => Number(b.maxBudget || 0) - Number(a.maxBudget || 0));
  } else {
    out.sort((a, b) => millis(b.createdAt) - millis(a.createdAt));
  }
  return out;
}

function decorate(row, { policy, viewerUid, nowMs }) {
  const serialized = store.serializeRequest(row, { policy, viewerUid, nowMs });
  return {
    ...serialized,
    isExpiringSoon: policy
      ? (serialized.status === 'active' || serialized.status === 'limit_reached')
        && serialized.timeRemainingMs > 0
        && serialized.timeRemainingMs <= policy.expiringSoonHours * 3600 * 1000
      : false,
  };
}

async function getConfig(nowMs = Date.now()) {
  const policy = await getPolicy();
  return {
    ...publicPolicy(policy),
    policy,
    categories: CATEGORIES,
    serverTime: new Date(nowMs).toISOString(),
    serverTimeMs: nowMs,
  };
}

async function create(buyerUidOrPayload, input = null, nowMs = Date.now()) {
  let buyerUid = buyerUidOrPayload;
  let payload = input || {};
  let time = nowMs;
  if (buyerUidOrPayload && typeof buyerUidOrPayload === 'object' && !Array.isArray(buyerUidOrPayload)) {
    buyerUid = buyerUidOrPayload.buyerUid;
    payload = buyerUidOrPayload.input || {};
    time = buyerUidOrPayload.nowMs || nowMs;
  }
  nowMs = time;
  const policy = await getPolicy();
  const buyer = await store.getUserSnapshot(buyerUid);
  assertAccountActive(buyer);
  if (!buyer) throw httpError(404, 'USER_NOT_FOUND');

  const normalized = validateCreateInput(payload, policy, nowMs);

  const activeCount = await store.countBuyerRequests(buyerUid, ['active', 'limit_reached']);
  if (activeCount >= policy.maxActivePerBuyer) {
    throw httpError(409, 'ACTIVE_REQUEST_LIMIT_REACHED');
  }

  const nowIso = new Date(nowMs).toISOString();
  const id = await store.createRequest({
    ...buyerIdentity(buyer, buyerUid),
    title: normalized.title,
    description: normalized.description,
    categoryId: normalized.categoryId,
    categoryName: normalized.categoryName,
    images: normalized.images,
    brand: normalized.brand,
    model: normalized.model,
    condition: normalized.condition,
    minBudget: normalized.minBudget,
    maxBudget: normalized.maxBudget,
    location: normalized.location,
    delivery: normalized.delivery,
    deliveryDetails: normalized.deliveryDetails,
    requirements: normalized.requirements,
    preferredContact: normalized.preferredContact,
    language: normalized.language,
    status: 'active',
    offersCount: 0,
    totalOfferCount: 0,
    viewCount: 0,
    offerLimit: normalized.offerLimit,
    editsUsed: 0,
    maxEdits: policy.maxEdits,
    version: 1,
    extensionsUsed: 0,
    expiresAt: new Date(normalized.expiresAtMs).toISOString(),
    expiresAtMs: normalized.expiresAtMs,
    createdAt: nowIso,
    updatedAt: nowIso,
  });

  await store.addEvent({
    requestId: id,
    type: 'created',
    actorUid: buyerUid,
    data: { offerLimit: normalized.offerLimit, expiresAt: new Date(normalized.expiresAtMs).toISOString() },
  });

  const doc = await store.getRequest(id);
  return decorate(doc, { policy, viewerUid: buyerUid, nowMs });
}

async function listFeed({ viewerUid, query = {}, nowMs = Date.now() }) {
  const policy = await getPolicy();
  if (!policy.enabled) throw httpError(403, 'BUYER_REQUESTS_DISABLED');
  const viewer = viewerUid ? await store.getUserSnapshot(viewerUid) : null;
  assertAccountActive(viewer);
  if (policy.requestVisibility === 'verified_sellers' && viewerUid && !isVerified(viewer)) {
    throw httpError(403, 'SELLER_VERIFICATION_REQUIRED');
  }

  // A feed is a browse surface, so we fetch one bounded window and filter the
  // free-text/budget facets in memory. Firestore has no full-text search; the
  // alternative (client-side Firestore reads) would bypass authorization.
  const rows = await store.listRequests({
    where: [{ field: 'status', op: '==', value: 'active' }],
    orderBy: 'createdAt',
    direction: 'desc',
    limit: 100,
  });
  const filtered = applyFeedFilters(rows, query, policy, nowMs);
  const { page, limit, offset } = paging(query);
  const slice = filtered.slice(offset, offset + limit);
  return {
    items: slice.map((row) => decorate(row, { policy, viewerUid, nowMs })),
    pagination: {
      page,
      limit,
      total: filtered.length,
      hasMore: offset + slice.length < filtered.length,
    },
    serverTime: new Date(nowMs).toISOString(),
    serverTimeMs: nowMs,
  };
}

function buyerCounts(rows, policy, nowMs) {
  const counts = {
    all: rows.length,
    active: 0,
    receiving_offers: 0,
    limit_reached: 0,
    expiring_soon: 0,
    expired: 0,
    completed: 0,
    closed: 0,
  };
  rows.forEach((row) => {
    CATEGORIES.forEach((category) => {
      if (category !== 'all' && categoryMatches(row, category, policy, nowMs)) counts[category] += 1;
    });
  });
  return counts;
}

async function listMine({ buyerUid, query = {}, nowMs = Date.now() }) {
  const policy = await getPolicy();
  const rows = await store.listBuyerRequests(buyerUid, { limit: 200 });
  const category = String(query.category || 'all');
  const counts = buyerCounts(rows, policy, nowMs);
  const filtered = rows
    .filter((row) => categoryMatches(row, category, policy, nowMs))
    .sort((a, b) => millis(b.createdAt) - millis(a.createdAt));
  const { page, limit, offset } = paging(query);
  const slice = filtered.slice(offset, offset + limit);
  return {
    items: slice.map((row) => decorate(row, { policy, viewerUid: buyerUid, nowMs })),
    counts,
    pagination: { page, limit, total: filtered.length, hasMore: offset + slice.length < filtered.length },
    serverTime: new Date(nowMs).toISOString(),
  };
}

async function getDetail({ requestId, viewerUid = null, viewer = null, nowMs = Date.now() }) {
  const policy = await getPolicy();
  const doc = await store.getRequest(requestId);
  if (!doc) throw httpError(404, 'REQUEST_NOT_FOUND');

  const isOwner = Boolean(viewerUid) && viewerUid === doc.buyerUid;
  if (doc.status === 'suspended' && !isOwner) throw httpError(404, 'REQUEST_NOT_FOUND');

  const user = viewer || (viewerUid ? await store.getUserSnapshot(viewerUid) : null);
  assertAccountActive(user);
  if (policy.requestVisibility === 'verified_sellers' && !isOwner && viewerUid && !isVerified(user)) {
    throw httpError(403, 'SELLER_VERIFICATION_REQUIRED');
  }

  const base = decorate(doc, { policy, viewerUid, nowMs });
  const myOffer = viewerUid && !isOwner
    ? await store.getOffer(doc.id, viewerUid).catch(() => null)
    : null;

  const block = offerBlockReason({ policy, user, viewerUid, request: doc, myOffer, nowMs });
  return {
    ...base,
    hasOffered: Boolean(myOffer && myOffer.status !== 'withdrawn'),
    myOffer: myOffer ? store.serializeOffer(myOffer, { viewerUid }) : null,
    canOffer: block.allowed,
    offerBlockReason: block.reason,
    // View counts are public; the identity of viewers is not.
    viewCount: Number(doc.viewCount || 0),
  };
}

function offerBlockReason({ policy, user, viewerUid, request, myOffer, nowMs }) {
  if (!policy.enabled) return { allowed: false, reason: 'disabled' };
  if (!viewerUid) return { allowed: false, reason: 'sign_in_required' };
  if (request.buyerUid === viewerUid) return { allowed: false, reason: 'own_request' };
  if (user && (user.accountStatus === 'suspended' || user.accountStatus === 'deleted')) {
    return { allowed: false, reason: 'account_suspended' };
  }
  const profile = (user && user.sellerProfile) || {};
  if (profile.sellerStatus && profile.sellerStatus !== 'seller') {
    return { allowed: false, reason: 'not_a_seller' };
  }
  if (policy.sellerEligibility === 'verified' && !isVerified(user)) {
    return { allowed: false, reason: 'kyc_required' };
  }
  const status = statusFor(request, policy, nowMs);
  if (status === 'expired') return { allowed: false, reason: 'expired' };
  if (status === 'limit_reached') return { allowed: false, reason: 'limit_reached' };
  if (status !== 'active') return { allowed: false, reason: 'not_accepting' };
  if (myOffer && !['withdrawn', 'declined'].includes(myOffer.status)) {
    return { allowed: false, reason: 'already_offered' };
  }
  return { allowed: true, reason: null };
}

async function update({ requestId, buyerUid, patch, nowMs = Date.now() }) {
  const policy = await getPolicy();
  const current = await store.getRequest(requestId);
  if (!current) throw httpError(404, 'REQUEST_NOT_FOUND');
  if (current.buyerUid !== buyerUid) throw httpError(403, 'REQUEST_NOT_OWNED');

  const validated = validateEditInput(patch, { request: current, policy, nowMs });
  const updates = { ...validated };
  // Keep the ISO value (display) and the numeric mirror (range queries) in sync.
  if (updates.expiresAtMs) {
    updates.expiresAt = new Date(updates.expiresAtMs).toISOString();
  }

  if (Object.prototype.hasOwnProperty.call(updates, 'offerLimit')) {
    const nextCount = Number(current.offersCount || 0);
    updates.status = nextCount >= updates.offerLimit ? 'limit_reached' : 'active';
  }

  const result = await store.applyEdit({
    requestId, buyerUid, updates, policy, nowMs, actorUid: buyerUid,
  });

  await store.addEvent({
    requestId,
    type: 'edited',
    actorUid: buyerUid,
    data: { version: result.version, changedFields: result.changed },
  });

  if (result.changed.length) {
    const offers = await store.listOffers(requestId);
    const sellerUids = [...new Set(
      offers
        .filter((offer) => ['pending', 'shortlisted'].includes(offer.status))
        .map((offer) => offer.sellerUid),
    )];
    if (sellerUids.length) {
      notify.requestUpdated({ sellerUids, request: result.request, changed: result.changed })
        .catch((e) => console.error('[buyer-requests] update notify failed:', e?.message || e));
    }
  }

  const fresh = await store.getRequest(requestId);
  return decorate(fresh, { policy, viewerUid: buyerUid, nowMs });
}

async function extend({ requestId, buyerUid, hours, nowMs = Date.now() }) {
  const policy = await getPolicy();
  if (!policy.allowExtension) throw httpError(403, 'EXTENSION_NOT_ALLOWED');
  const current = await store.getRequest(requestId);
  if (!current) throw httpError(404, 'REQUEST_NOT_FOUND');
  if (current.buyerUid !== buyerUid) throw httpError(403, 'REQUEST_NOT_OWNED');

  const requested = Math.floor(Number(hours) || policy.extensionHours);
  if (requested < 1 || requested > policy.extensionHours) {
    throw badRequest('INVALID_EXTENSION_HOURS');
  }
  if (Number(current.extensionsUsed || 0) >= policy.maxExtensions) {
    throw httpError(409, 'EXTENSION_LIMIT_REACHED');
  }

  const result = await store.applyExtend({
    requestId, buyerUid, hours: requested, maxExtensions: policy.maxExtensions, nowMs,
  });
  await store.addEvent({
    requestId,
    type: 'extended',
    actorUid: buyerUid,
    data: { hours: requested, expiresAt: result.request.expiresAt },
  });
  const fresh = await store.getRequest(requestId);
  return decorate(fresh, { policy, viewerUid: buyerUid, nowMs });
}

async function close({ requestId, buyerUid, nowMs = Date.now() }) {
  const policy = await getPolicy();
  const result = await store.setRequestStatus({
    requestId,
    buyerUid,
    from: ['active', 'limit_reached', 'expired'],
    to: 'closed',
    nowMs,
  });
  await store.addEvent({ requestId, type: 'closed', actorUid: buyerUid });
  const offers = await store.listOffers(requestId);
  const sellerUids = [...new Set(
    offers
      .filter((offer) => ['pending', 'shortlisted'].includes(offer.status))
      .map((offer) => offer.sellerUid),
  )];
  if (sellerUids.length) {
    notify.requestClosed({ sellerUids, request: result.request })
      .catch((e) => console.error('[buyer-requests] close notify failed:', e?.message || e));
  }
  return decorate(result.request, { policy, viewerUid: buyerUid, nowMs });
}

async function reopen({ requestId, buyerUid, nowMs = Date.now() }) {
  const policy = await getPolicy();
  if (!policy.enabled) throw httpError(403, 'BUYER_REQUESTS_DISABLED');
  const current = await store.getRequest(requestId);
  if (!current) throw httpError(404, 'REQUEST_NOT_FOUND');
  if (current.buyerUid !== buyerUid) throw httpError(403, 'REQUEST_NOT_OWNED');
  if (!canReopen(current, policy, nowMs)) throw httpError(409, 'REQUEST_CANNOT_BE_REOPENED');
  if (statusFor(current, policy, nowMs) === 'expired') throw httpError(409, 'REQUEST_EXPIRED_EXTEND_FIRST');

  const activeCount = await store.countBuyerRequests(buyerUid, ['active', 'limit_reached']);
  if (activeCount >= policy.maxActivePerBuyer) throw httpError(409, 'ACTIVE_REQUEST_LIMIT_REACHED');

  const result = await store.setRequestStatus({
    requestId,
    buyerUid,
    from: ['closed'],
    to: Number(current.offersCount || 0) >= Number(current.offerLimit || 0) ? 'limit_reached' : 'active',
    nowMs,
  });
  await store.addEvent({ requestId, type: 'reopened', actorUid: buyerUid });
  return decorate(result.request, { policy, viewerUid: buyerUid, nowMs });
}

async function trackView({ requestId, viewerUid, nowMs = Date.now() }) {
  const policy = await getPolicy();
  const request = await store.getRequest(requestId);
  if (!request) throw httpError(404, 'REQUEST_NOT_FOUND');
  if (request.buyerUid === viewerUid) return { tracked: false, reason: 'owner' };

  const user = await store.getUserSnapshot(viewerUid);
  if (!user) return { tracked: false, reason: 'unknown_user' };
  if (user.accountStatus === 'suspended' || user.accountStatus === 'deleted') {
    return { tracked: false, reason: 'suspended' };
  }
  if (policy.sellerEligibility === 'verified' && !isVerified(user)) {
    return { tracked: false, reason: 'kyc_required' };
  }

  const seller = store.identityFromUser(viewerUid, user);
  const result = await store.recordView({ requestId, seller, nowMs });
  if (result.created) {
    await store.addEvent({
      requestId,
      type: 'viewed',
      actorUid: viewerUid,
      actorRole: 'seller',
      data: { sellerName: seller.displayName, storeName: seller.storeName },
    });
    if (policy.sellerViewNotifications) {
      notify.sellerViewedRequest({ buyerUid: request.buyerUid, seller, request })
        .then(() => store.markViewNotified(requestId, viewerUid))
        .catch((e) => console.error('[buyer-requests] view notify failed:', e?.message || e));
    }
  }
  return {
    tracked: true,
    unique: result.created,
    viewCount: Number(request.viewCount || 0) + (result.created ? 1 : 0),
    serverTime: new Date(nowMs).toISOString(),
  };
}

async function listViews({ requestId, buyerUid }) {
  const request = await store.getRequest(requestId);
  if (!request) throw httpError(404, 'REQUEST_NOT_FOUND');
  if (request.buyerUid !== buyerUid) throw httpError(403, 'REQUEST_NOT_OWNED');
  const rows = await store.listViews(requestId, { limit: 100 });
  return { items: rows.map(store.serializeView), total: rows.length };
}

async function listOffersFor({ requestId, viewerUid, viewerRole = 'user', nowMs = Date.now() }) {
  const policy = await getPolicy();
  const request = await store.getRequest(requestId);
  if (!request) throw httpError(404, 'REQUEST_NOT_FOUND');
  const isOwner = request.buyerUid === viewerUid;
  if (!isOwner && viewerRole !== 'admin') {
    const mine = await store.getOffer(requestId, viewerUid);
    if (!mine) throw httpError(403, 'REQUEST_NOT_OWNED');
  }
  const rows = await store.listOffers(requestId, { limit: 100 });
  const visible = isOwner || viewerRole === 'admin'
    ? rows
    : rows.filter((row) => row.sellerUid === viewerUid);
  return {
    items: visible.map((row) => store.serializeOffer(row, { viewerUid })),
    offersCount: Number(request.offersCount || 0),
    offerLimit: Number(request.offerLimit || 0),
    status: statusFor(request, policy, nowMs),
    serverTime: new Date(nowMs).toISOString(),
  };
}

async function createOffer({ requestId, sellerUid, input, nowMs = Date.now() }) {
  const policy = await getPolicy();
  const request = await store.getRequest(requestId);
  if (!request) throw httpError(404, 'REQUEST_NOT_FOUND');
  const sellerDoc = await store.getUserSnapshot(sellerUid);
  if (!sellerDoc) throw httpError(404, 'USER_NOT_FOUND');

  const existing = await store.getOffer(requestId, sellerUid);
  const block = offerBlockReason({
    policy, user: sellerDoc, viewerUid: sellerUid, request, myOffer: existing, nowMs,
  });
  if (!block.allowed) throw httpError(409, block.reason.toUpperCase());

  const normalized = validateOfferInput(input);
  const seller = store.identityFromUser(sellerUid, sellerDoc);
  const contact = store.contactFromUser(sellerDoc);
  seller.whatsappEnabled = contact.whatsappEnabled && contact.kycApproved && normalizeWhatsapp(contact) !== null;

  const result = await store.createOffer({
    requestId, seller, input: normalized, policy, nowMs,
  });

  await store.addEvent({
    requestId,
    type: 'offer_created',
    actorUid: sellerUid,
    actorRole: 'seller',
    data: { offerId: result.offer.id, price: normalized.price },
  });

  const offer = store.serializeOffer(result.offer, { viewerUid: sellerUid });
  notify.offerReceived({
    buyerUid: request.buyerUid,
    seller,
    request: { ...request, id: requestId },
    offer,
  }).catch((e) => console.error('[buyer-requests] offer notify failed:', e?.message || e));

  if (result.limitReached) {
    notify.limitReached({
      buyerUid: request.buyerUid,
      request: {
        ...request,
        id: requestId,
        title: request.title,
        offersCount: result.request.offersCount,
        offerLimit: request.offerLimit,
      },
    }).catch((e) => console.error('[buyer-requests] limit notify failed:', e?.message || e));
  }

  return {
    requestId,
    offer,
    offersCount: result.request.offersCount,
    offerLimit: Number(request.offerLimit || 0),
    limitReached: result.limitReached,
    serverTime: new Date(nowMs).toISOString(),
  };
}

async function withdrawOffer({ requestId, offerId, sellerUid, nowMs = Date.now() }) {
  const offer = await store.getOfferById(offerId);
  if (!offer || offer.requestId !== String(requestId)) throw httpError(404, 'OFFER_NOT_FOUND');
  if (offer.sellerUid !== sellerUid) throw httpError(403, 'OFFER_NOT_OWNED');
  const result = await store.withdrawOffer({ requestId, sellerUid, nowMs });
  await store.addEvent({
    requestId,
    type: 'offer_withdrawn',
    actorUid: sellerUid,
    actorRole: 'seller',
    data: { offerId },
  });
  const request = await store.getRequest(requestId);
  notify.offerWithdrawn({
    buyerUid: request.buyerUid,
    seller: { uid: sellerUid, displayName: offer.sellerName, storeName: offer.sellerStoreName },
    request: { ...request, id: requestId },
  }).catch((e) => console.error('[buyer-requests] withdraw notify failed:', e?.message || e));
  return {
    offer: store.serializeOffer(result.offer, { viewerUid: sellerUid }),
    offersCount: result.request.offersCount,
    status: result.request.status,
  };
}

async function decideOffer({ requestId, offerId, buyerUid, action, nowMs = Date.now() }) {
  if (!['accept', 'decline'].includes(action)) throw badRequest('INVALID_DECISION');
  const offer = await store.getOfferById(offerId);
  if (!offer || offer.requestId !== String(requestId)) throw httpError(404, 'OFFER_NOT_FOUND');
  const request = await store.getRequest(requestId);
  if (!request) throw httpError(404, 'REQUEST_NOT_FOUND');
  if (request.buyerUid !== buyerUid) throw httpError(403, 'REQUEST_NOT_OWNED');

  const result = await store.decideOffer({ requestId, offerId, buyerUid, action, nowMs });

  if (action === 'accept') {
    // Close the loop on every other live offer so sellers are not left waiting
    // on a request that is already completed.
    const live = await store.listOffers(requestId);
    const others = live.filter(
      (row) => row.id !== offerId && ['pending', 'shortlisted'].includes(row.status),
    );
    await Promise.allSettled(others.map((row) => store.decideOffer({
      requestId, offerId: row.id, buyerUid, action: 'decline', nowMs,
    })));
    await Promise.allSettled(others.map((row) => notify.offerDecided({
      sellerUid: row.sellerUid,
      request: { ...request, id: requestId },
      accepted: false,
    })));
  }

  await store.addEvent({
    requestId,
    type: action === 'accept' ? 'offer_accepted' : 'offer_declined',
    actorUid: buyerUid,
    data: { offerId, sellerUid: result.offer.sellerUid },
  });

  notify.offerDecided({
    sellerUid: result.offer.sellerUid,
    request: { ...request, id: requestId },
    accepted: action === 'accept',
  }).catch((e) => console.error('[buyer-requests] decision notify failed:', e?.message || e));

  return {
    request: store.serializeRequest({ ...request, ...result.request }, {
      policy: await getPolicy(), viewerUid: buyerUid, nowMs,
    }),
    offer: store.serializeOffer(result.offer, { viewerUid: buyerUid }),
    serverTime: new Date(nowMs).toISOString(),
  };
}

function normalizeWhatsapp(contact) {
  const raw = String(contact.whatsappNumber || contact.phone || '').replace(/[^\d+]/g, '');
  if (!raw) return null;
  let digits = raw.replace(/\D/g, '');
  if (digits.startsWith('0')) digits = `255${digits.slice(1)}`;
  if (digits.length < 9 || digits.length > 15) return null;
  return digits;
}

async function sellerContact({ requestId, buyerUid, sellerId, lang = 'sw', nowMs = Date.now() }) {
  const request = await store.getRequest(requestId);
  if (!request) throw httpError(404, 'REQUEST_NOT_FOUND');
  if (request.buyerUid !== buyerUid) throw httpError(403, 'REQUEST_NOT_OWNED');

  const offer = await store.getOffer(requestId, sellerId);
  if (!offer) throw httpError(404, 'OFFER_NOT_FOUND');

  const sellerDoc = await store.getUserSnapshot(sellerId);
  if (!sellerDoc) throw httpError(404, 'SELLER_NOT_FOUND');

  const contact = store.contactFromUser(sellerDoc);
  const seller = store.identityFromUser(sellerId, sellerDoc);
  const digits = normalizeWhatsapp(contact);
  // Consent is three-part: the seller opted in, their identity is verified,
  // and we can build a valid international number. Anything less falls back to
  // in-app chat instead of leaking a private phone number.
  const whatsappEnabled = contact.whatsappEnabled && contact.kycApproved && Boolean(digits);

  const message = lang === 'en'
    ? `Hello ${seller.storeName || seller.displayName}, I saw your offer on my Soko Vibe request "${request.title}". Can we talk?`
    : `Habari ${seller.storeName || seller.displayName}, nimeona ofa yako kwenye ombi langu la "${request.title}" kwenye Soko Vibe. Tunaweza kuzungumza?`;

  return {
    seller: {
      uid: seller.uid,
      displayName: seller.displayName,
      storeName: seller.storeName,
      avatarUrl: seller.avatarUrl,
      kycApproved: seller.kycApproved,
    },
    offer: { id: offer.id, price: Number(offer.price || 0), status: offer.status },
    whatsappEnabled,
    whatsappNumber: whatsappEnabled ? `+${digits}` : null,
    deepLink: whatsappEnabled
      ? `https://wa.me/${digits}?text=${encodeURIComponent(message)}`
      : null,
    prefilledMessage: whatsappEnabled ? message : null,
    inAppChatAvailable: true,
    inAppChat: { sellerUid: seller.uid, requestId },
    serverTime: new Date(nowMs).toISOString(),
  };
}

async function recordWhatsappClick({ requestId, buyerUid, sellerId, nowMs = Date.now() }) {
  const request = await store.getRequest(requestId);
  if (!request) throw httpError(404, 'REQUEST_NOT_FOUND');
  if (request.buyerUid !== buyerUid) throw httpError(403, 'REQUEST_NOT_OWNED');

  const offer = await store.getOffer(requestId, sellerId);
  if (!offer) throw httpError(404, 'OFFER_NOT_FOUND');
  const sellerDoc = await store.getUserSnapshot(sellerId);
  const contact = store.contactFromUser(sellerDoc);
  if (!contact.whatsappEnabled || !contact.kycApproved) {
    throw httpError(403, 'WHATSAPP_NOT_AUTHORIZED');
  }

  const db = require('../../config/firebase').getFirebaseFirestore();
  if (db) {
    await Promise.allSettled([
      db.collection(store.COLLECTIONS.offers).doc(offer.id)
        .set({ whatsappClicks: require('firebase-admin/firestore').FieldValue.increment(1) }, { merge: true }),
      db.collection(store.COLLECTIONS.requests).doc(String(requestId))
        .set({ whatsappClicks: require('firebase-admin/firestore').FieldValue.increment(1) }, { merge: true }),
    ]);
  }
  await store.addEvent({
    requestId,
    type: 'whatsapp_click',
    actorUid: buyerUid,
    actorRole: 'buyer',
    data: { sellerUid: sellerId, offerId: offer.id },
  });
  return { tracked: true, serverTime: new Date(nowMs).toISOString() };
}

async function getHistory({ requestId, buyerUid, viewerRole = 'user' }) {
  const request = await store.getRequest(requestId);
  if (!request) throw httpError(404, 'REQUEST_NOT_FOUND');
  if (request.buyerUid !== buyerUid && viewerRole !== 'admin') {
    throw httpError(403, 'REQUEST_NOT_OWNED');
  }
  const events = await store.listEvents(requestId, { limit: 100 });
  return {
    version: Number(request.version || 1),
    edits: Array.isArray(request.editHistory) ? request.editHistory : [],
    events,
  };
}

// ---- Admin ----------------------------------------------------------------

async function adminConfig() {
  const policy = await getPolicy();
  const settings = await settingsService.getSettings();
  return {
    policy,
    public: publicPolicy(policy),
    raw: (settings && settings.buyerRequests) || {},
    serverTime: new Date().toISOString(),
  };
}

async function adminUpdateConfig(patch) {
  const current = await getPolicy();
  const merged = normalizePolicy({ ...current, ...(patch || {}) });
  await settingsService.saveSettings({ buyerRequests: merged });
  return adminConfig();
}

async function adminDashboard() {
  return store.adminStats(Date.now());
}

async function adminListRequests({ status, buyerUid, page = 1, limit = 30 }) {
  const take = Math.min(100, Math.max(1, Math.floor(Number(limit) || 30)));
  const skip = (Math.max(1, Math.floor(Number(page) || 1)) - 1) * take;
  const rows = await store.adminList({ status, buyerUid, limit: take, offset: skip });
  const policy = await getPolicy();
  const nowMs = Date.now();
  return {
    items: rows.map((row) => decorate(row, { policy, viewerUid: null, nowMs })),
    page: Math.max(1, Math.floor(Number(page) || 1)),
    limit: take,
    serverTime: new Date(nowMs).toISOString(),
  };
}

async function adminDetail({ requestId, nowMs = Date.now() }) {
  const policy = await getPolicy();
  const request = await store.getRequest(requestId);
  if (!request) throw httpError(404, 'REQUEST_NOT_FOUND');
  const [offers, views, events] = await Promise.all([
    store.listOffers(requestId, { limit: 100 }),
    store.listViews(requestId, { limit: 100 }),
    store.listEvents(requestId, { limit: 100 }),
  ]);
  return {
    request: decorate(request, { policy, viewerUid: null, nowMs }),
    offers: offers.map((row) => store.serializeOffer(row)),
    views: views.map(store.serializeView),
    events,
    serverTime: new Date(nowMs).toISOString(),
  };
}

async function adminModerate({ requestId, action, reason, hourList, adminId, nowMs = Date.now() }) {
  if (!['suspend', 'restore', 'close', 'extend'].includes(action)) {
    throw badRequest('INVALID_MODERATION_ACTION');
  }
  if (['suspend', 'close'].includes(action) && !String(reason || '').trim()) {
    throw badRequest('REASON_REQUIRED');
  }
  const policy = await getPolicy();
  let request;

  if (action === 'suspend') {
    request = (await store.adminSetStatus({ requestId, to: 'suspended', reason, adminId, nowMs })).request;
  } else if (action === 'restore') {
    request = (await store.adminSetStatus({ requestId, to: 'active', reason, adminId, nowMs })).request;
  } else if (action === 'close') {
    request = (await store.adminSetStatus({ requestId, to: 'closed', reason, adminId, nowMs })).request;
  } else {
    const hours = Math.floor(Number(hourList) || policy.extensionHours);
    if (hours < 1 || hours > policy.maxExpiryHours) throw badRequest('INVALID_EXTENSION_HOURS');
    request = (await store.adminExtend({ requestId, hours, reason, adminId, nowMs })).request;
  }

  await store.addEvent({
    requestId,
    type: `admin_${action}`,
    actorUid: adminId,
    actorRole: 'admin',
    data: { reason: reason || '', action },
  });
  notify.moderated({
    buyerUid: request.buyerUid,
    request: { ...request, id: requestId },
    action: action === 'suspend' ? 'suspended' : 'restored',
    reason,
  }).catch((e) => console.error('[buyer-requests] moderation notify failed:', e?.message || e));

  const fresh = await store.getRequest(requestId);
  return decorate(fresh, { policy, viewerUid: null, nowMs });
}

async function adminModerateOffer({ requestId, offerId, action, reason, adminId, nowMs = Date.now() }) {
  if (!['hide', 'review'].includes(action)) throw badRequest('INVALID_MODERATION_ACTION');
  if (action === 'hide' && !String(reason || '').trim()) throw badRequest('REASON_REQUIRED');
  const result = await store.adminModerateOffer({
    requestId, offerId, action, reason, adminId, nowMs,
  });
  await store.addEvent({
    requestId,
    type: `admin_offer_${action}`,
    actorUid: adminId,
    actorRole: 'admin',
    data: { offerId, reason: reason || '', action },
  });
  return {
    offer: store.serializeOffer(result.offer),
    serverTime: new Date(nowMs).toISOString(),
  };
}

module.exports = {
  getPolicy,
  getConfig,
  create,
  listFeed,
  listMine,
  getDetail,
  update,
  extend,
  close,
  reopen,
  trackView,
  listViews,
  listOffersFor,
  createOffer,
  withdrawOffer,
  decideOffer,
  sellerContact,
  recordWhatsappClick,
  getHistory,
  adminConfig,
  adminUpdateConfig,
  adminDashboard,
  adminListRequests,
  adminDetail,
  adminModerate,
  adminModerateOffer,
  buyerCounts,
  applyFeedFilters,
  normalizeWhatsapp,
  offerBlockReason,
  runExpirySweep,
};

async function runExpirySweep(nowMs = Date.now()) {
  const policy = await getPolicy();
  if (!policy.autoExpire) return { expired: 0, notified: 0 };
  const due = await store.findDueForExpiry(nowMs, 200);
  let expired = 0;
  for (const doc of due) {
    const res = await store.expireRequest(doc.id, nowMs);
    if (res) {
      expired += 1;
      try {
        const request = await store.getRequest(doc.id);
        notify.expired({ buyerUid: request.buyerUid, request: { ...request, id: doc.id } })
          .catch((e) => console.error('[buyer-requests] expired notify failed:', e?.message || e));
      } catch (e) {
        console.error('[buyer-requests] expired notify load failed:', e?.message || e);
      }
    }
  }
  const soon = await store.findExpiringSoon(nowMs, policy.expiringSoonHours * 3600 * 1000, 200);
  let notified = 0;
  for (const doc of soon) {
    await store.markExpiryNotified(doc.id, nowMs);
    const hoursLeft = Math.max(1, Math.round((millis(doc.expiresAtMs || doc.expiresAt) - nowMs) / 3600000));
    notify.expiringSoon({ buyerUid: doc.buyerUid, request: { ...doc, id: doc.id }, hoursLeft })
      .catch((e) => console.error('[buyer-requests] expiring notify failed:', e?.message || e));
    notified += 1;
  }
  return { expired, notified, serverTime: new Date(nowMs).toISOString() };
}
