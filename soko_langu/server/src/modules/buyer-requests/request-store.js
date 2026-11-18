// Firestore persistence for Buyer Requests.
//
// Collections (all server-owned; firestore.rules denies client access):
//   buyer_requests        one document per buyer request
//   buyer_request_offers  id = `${requestId}_${sellerId}` (one live offer/seller)
//   buyer_request_views   id = `${requestId}_${sellerId}` (unique seller views)
//   buyer_request_events  append-only activity trail (edits, moderation)
//
// Money never moves here. The module only proves ownership/eligibility, keeps
// counters atomic, and leaves settlement to the existing order/escrow flow.
const { FieldValue } = require('firebase-admin/firestore');
const commerceStore = require('../../services/commerce-store');
const { getFirebaseFirestore } = require('../../config/firebase');
const {
  httpError,
  statusFor,
  millis,
  changedFields,
  canEdit,
} = require('./request-config');

const COLLECTIONS = {
  requests: 'buyer_requests',
  offers: 'buyer_request_offers',
  views: 'buyer_request_views',
  events: 'buyer_request_events',
};

const LIVE_OFFER_STATUSES = ['pending', 'shortlisted', 'accepted'];

function iso(value) {
  if (value == null) return null;
  if (typeof value === 'object' && typeof value.toDate === 'function') return value.toDate().toISOString();
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'number') return new Date(value).toISOString();
  return String(value);
}

function requireDb() {
  const db = getFirebaseFirestore();
  if (!db) throw httpError(503, 'BUYER_REQUEST_STORE_UNAVAILABLE');
  return db;
}

function docId(...parts) {
  return parts.map((p) => String(p == null ? '' : p).replace(/\//g, '_')).join('_');
}

function offerId(requestId, sellerUid) {
  return docId(requestId, sellerUid);
}

function withId(snap) {
  return snap && snap.exists ? { id: snap.id, ...snap.data() } : null;
}

function serializeRequest(doc, { policy, viewerUid = null, nowMs = Date.now() } = {}) {
  if (!doc) return null;
  const status = statusFor(doc, policy, nowMs);
  const expiresAtMs = millis(doc.expiresAtMs || doc.expiresAt);
  const remaining = expiresAtMs ? Math.max(0, expiresAtMs - nowMs) : 0;
  const isOwner = Boolean(viewerUid) && viewerUid === doc.buyerUid;
  return {
    id: doc.id,
    buyerUid: doc.buyerUid,
    buyer: {
      uid: doc.buyerUid,
      displayName: doc.buyerName || '',
      avatarUrl: doc.buyerAvatarUrl || '',
      kycApproved: Boolean(doc.buyerKycApproved),
    },
    title: doc.title || '',
    description: doc.description || '',
    categoryId: doc.categoryId || '',
    categoryName: doc.categoryName || '',
    images: Array.isArray(doc.images) ? doc.images : [],
    brand: doc.brand || '',
    model: doc.model || '',
    condition: doc.condition || 'any',
    minBudget: Number(doc.minBudget || 0),
    maxBudget: Number(doc.maxBudget || 0),
    budget: { min: Number(doc.minBudget || 0), max: Number(doc.maxBudget || 0), currency: 'TZS' },
    location: doc.location || '',
    delivery: doc.delivery || 'negotiable',
    deliveryDetails: doc.deliveryDetails || '',
    requirements: doc.requirements || '',
    preferredContact: doc.preferredContact === 'whatsapp' ? 'whatsapp' : 'in_app',
    status,
    rawStatus: doc.status || 'active',
    isExpiringSoon: Boolean(policy)
      && (status === 'active' || status === 'limit_reached')
      && remaining > 0
      && remaining <= Number(policy.expiringSoonHours || 24) * 3600 * 1000,
    timeRemainingMs: remaining,
    offersCount: Number(doc.offersCount || 0),
    totalOfferCount: Number(doc.totalOfferCount || 0),
    viewCount: Number(doc.viewCount || 0),
    offerLimit: Number(doc.offerLimit || 0),
    editsUsed: Number(doc.editsUsed || 0),
    maxEdits: Number(policy?.maxEdits ?? doc.maxEdits ?? 0),
    version: Number(doc.version || 1),
    extensionsUsed: Number(doc.extensionsUsed || 0),
    canEdit: Boolean(policy) && canEdit(doc, policy, nowMs),
    canExtend: Boolean(policy)
      && policy.allowExtension
      && (status === 'active' || status === 'limit_reached' || status === 'expired')
      && Number(doc.extensionsUsed || 0) < Number(policy.maxExtensions || 0),
    canReopen: String(doc.status || '') === 'closed',
    canClose: status === 'active' || status === 'limit_reached',
    expiresAt: iso(doc.expiresAt || doc.expiresAtMs),
    createdAt: iso(doc.createdAt),
    updatedAt: iso(doc.updatedAt),
    closedAt: iso(doc.closedAt),
    completedAt: iso(doc.completedAt),
    isOwner,
    moderation: doc.moderation
      ? {
          hidden: Boolean(doc.moderation.hidden),
          reason: doc.moderation.reason || '',
          at: iso(doc.moderation.at),
        }
      : null,
  };
}

function serializeView(doc) {
  if (!doc) return null;
  return {
    sellerUid: doc.sellerUid,
    seller: {
      uid: doc.sellerUid,
      displayName: doc.sellerName || '',
      avatarUrl: doc.sellerAvatarUrl || '',
      storeName: doc.sellerStoreName || '',
      kycApproved: Boolean(doc.sellerKycApproved),
    },
    firstViewedAt: iso(doc.firstViewedAt),
    lastViewedAt: iso(doc.lastViewedAt),
    viewCount: Number(doc.viewCount || 1),
  };
}

function serializeOffer(doc, { viewerUid = null } = {}) {
  if (!doc) return null;
  return {
    id: doc.id,
    requestId: doc.requestId,
    sellerUid: doc.sellerUid,
    seller: {
      uid: doc.sellerUid,
      displayName: doc.sellerName || '',
      avatarUrl: doc.sellerAvatarUrl || '',
      storeName: doc.sellerStoreName || '',
      kycApproved: Boolean(doc.sellerKycApproved),
      whatsappEnabled: Boolean(doc.sellerWhatsappEnabled),
    },
    price: Number(doc.price || 0),
    currency: doc.currency || 'TZS',
    message: doc.message || '',
    deliveryDays: doc.deliveryDays == null ? null : Number(doc.deliveryDays),
    condition: doc.condition || '',
    brand: doc.brand || '',
    model: doc.model || '',
    warranty: doc.warranty || '',
    status: doc.status || 'pending',
    version: Number(doc.version || 1),
    requestVersion: Number(doc.requestVersion || 1),
    isMine: Boolean(viewerUid) && viewerUid === doc.sellerUid,
    createdAt: iso(doc.createdAt),
    updatedAt: iso(doc.updatedAt),
    decidedAt: iso(doc.decidedAt),
    withdrawnAt: iso(doc.withdrawnAt),
  };
}

async function getUserSnapshot(uid) {
  if (!uid) return null;
  try {
    const db = requireDb();
    const snap = await db.collection('users').doc(String(uid)).get();
    if (snap.exists) return { id: snap.id, ...snap.data() };
    // The public projection is a derived cache; a missing users doc should not
    // blank the seller card on an existing request.
    const pub = await db.collection('userPublic').doc(String(uid)).get();
    return pub.exists ? { id: pub.id, ...pub.data() } : null;
  } catch (e) {
    console.error('[buyer-requests] user snapshot failed:', e?.message || e);
    return null;
  }
}

function identityFromUser(uid, doc) {
  const sellerProfile = (doc && doc.sellerProfile) || {};
  return {
    uid: String(uid),
    displayName: doc?.displayName || sellerProfile.storeName || '',
    avatarUrl: doc?.avatarUrl || '',
    storeName: sellerProfile.storeName || doc?.displayName || '',
    kycApproved: Boolean(doc?.kyc && doc.kyc.approved),
    accountStatus: doc?.accountStatus || 'active',
    sellerStatus: sellerProfile.sellerStatus || (doc?.role === 'seller' ? 'seller' : ''),
  };
}

function contactFromUser(doc) {
  const profile = (doc && doc.sellerProfile) || {};
  return {
    whatsappEnabled: profile.whatsappEnabled === true,
    whatsappNumber: String(profile.whatsappNumber || profile.whatsapp || '').trim(),
    // `phone` is private profile data. It is only ever considered when the
    // seller explicitly turned on WhatsApp contact, never as a default.
    phone: String(doc?.phone || '').trim(),
    kycApproved: Boolean(doc?.kyc && doc.kyc.approved),
  };
}

async function getRequest(requestId) {
  const db = requireDb();
  const snap = await db.collection(COLLECTIONS.requests).doc(String(requestId)).get();
  return withId(snap);
}

async function findRequestByOfferId(id) {
  const db = requireDb();
  const snap = await db.collection(COLLECTIONS.offers).doc(String(id)).get();
  const offer = withId(snap);
  if (!offer) throw httpError(404, 'OFFER_NOT_FOUND');
  return offer;
}

async function createRequest(data) {
  return commerceStore.addDocument(COLLECTIONS.requests, data);
}

async function listRequests({ where = [], orderBy = 'createdAt', direction = 'desc', limit = 20, offset = 0 } = {}) {
  return commerceStore.listDocuments(COLLECTIONS.requests, { where, orderBy, direction, limit, offset });
}

async function countBuyerRequests(buyerUid, statuses) {
  const db = requireDb();
  const snap = await db.collection(COLLECTIONS.requests)
    .where('buyerUid', '==', buyerUid)
    .where('status', 'in', statuses)
    .count()
    .get();
  return snap.data().count;
}

async function listBuyerRequests(buyerUid, { limit = 200 } = {}) {
  return commerceStore.listDocuments(COLLECTIONS.requests, {
    where: { buyerUid },
    orderBy: 'createdAt',
    direction: 'desc',
    limit,
  });
}

/**
 * Applies a validated edit inside a transaction so the edit counter and the
 * version number can never be lost to a concurrent save.
 */
async function applyEdit({ requestId, buyerUid, updates, policy, nowMs = Date.now(), actorUid }) {
  const db = requireDb();
  return commerceStore.runTransaction(async (tx) => {
    const ref = db.collection(COLLECTIONS.requests).doc(String(requestId));
    const snap = await tx.get(ref);
    if (!snap.exists) throw httpError(404, 'REQUEST_NOT_FOUND');
    const doc = { id: snap.id, ...snap.data() };
    if (doc.buyerUid !== buyerUid) throw httpError(403, 'REQUEST_NOT_OWNED');
    if (!canEdit(doc, policy, nowMs)) {
      const status = statusFor(doc, policy, nowMs);
      throw httpError(409, status === 'active' || status === 'limit_reached'
        ? 'EDIT_LIMIT_REACHED'
        : 'REQUEST_NOT_EDITABLE');
    }

    const changed = changedFields(doc, updates);
    if (!changed.length) throw httpError(409, 'NO_MEANINGFUL_CHANGE');

    const before = {};
    changed.forEach((field) => { before[field] = doc[field] ?? null; });
    const after = {};
    changed.forEach((field) => { after[field] = updates[field] ?? null; });

    const version = Number(doc.version || 1) + 1;
    const entry = {
      version,
      at: new Date(nowMs).toISOString(),
      by: actorUid || buyerUid,
      changedFields: changed,
      from: before,
      to: after,
    };
    const history = Array.isArray(doc.editHistory) ? doc.editHistory.slice(-9) : [];
    history.push(entry);

    tx.update(ref, {
      ...updates,
      version,
      editsUsed: FieldValue.increment(1),
      updatedAt: new Date(nowMs).toISOString(),
      lastEditAt: new Date(nowMs).toISOString(),
      editHistory: history,
    });
    return { request: { ...doc, ...updates, version }, changed, version };
  });
}

async function applyExtend({ requestId, buyerUid, hours, maxExtensions, nowMs = Date.now() }) {
  const db = requireDb();
  return commerceStore.runTransaction(async (tx) => {
    const ref = db.collection(COLLECTIONS.requests).doc(String(requestId));
    const snap = await tx.get(ref);
    if (!snap.exists) throw httpError(404, 'REQUEST_NOT_FOUND');
    const doc = { id: snap.id, ...snap.data() };
    if (doc.buyerUid !== buyerUid) throw httpError(403, 'REQUEST_NOT_OWNED');
    if (Number(doc.extensionsUsed || 0) >= Number(maxExtensions || 0)) {
      throw httpError(409, 'EXTENSION_LIMIT_REACHED');
    }
    const currentMs = Math.max(millis(doc.expiresAtMs || doc.expiresAt), nowMs);
    const nextMs = currentMs + hours * 3600 * 1000;
    tx.update(ref, {
      expiresAt: new Date(nextMs).toISOString(),
      expiresAtMs: nextMs,
      extensionsUsed: FieldValue.increment(1),
      updatedAt: new Date(nowMs).toISOString(),
      status: doc.status === 'expired'
        ? (Number(doc.offersCount || 0) >= Number(doc.offerLimit || 0) ? 'limit_reached' : 'active')
        : doc.status,
      lastExtendedAt: new Date(nowMs).toISOString(),
    });
    return {
      request: {
        ...doc,
        expiresAt: new Date(nextMs).toISOString(),
        expiresAtMs: nextMs,
        status: doc.status === 'expired' ? 'active' : doc.status,
      },
      expiresAtMs: nextMs,
    };
  });
}

async function setRequestStatus({ requestId, buyerUid, from, to, nowMs = Date.now(), extra = {} }) {
  const db = requireDb();
  return commerceStore.runTransaction(async (tx) => {
    const ref = db.collection(COLLECTIONS.requests).doc(String(requestId));
    const snap = await tx.get(ref);
    if (!snap.exists) throw httpError(404, 'REQUEST_NOT_FOUND');
    const doc = { id: snap.id, ...snap.data() };
    if (doc.buyerUid !== buyerUid) throw httpError(403, 'REQUEST_NOT_OWNED');
    if (!from.includes(doc.status)) throw httpError(409, 'INVALID_STATUS_TRANSITION');
    const updates = {
      status: to,
      updatedAt: new Date(nowMs).toISOString(),
      ...extra,
    };
    if (to === 'closed') updates.closedAt = new Date(nowMs).toISOString();
    if (to === 'completed') updates.completedAt = new Date(nowMs).toISOString();
    if (to === 'active') {
      updates.closedAt = null;
      updates.completedAt = null;
    }
    tx.update(ref, updates);
    return { request: { ...doc, ...updates } };
  });
}

async function recordView({ requestId, seller, nowMs = Date.now() }) {
  const db = requireDb();
  const viewRef = db.collection(COLLECTIONS.views).doc(offerId(requestId, seller.uid));
  const requestRef = db.collection(COLLECTIONS.requests).doc(String(requestId));
  return commerceStore.runTransaction(async (tx) => {
    const requestSnap = await tx.get(requestRef);
    if (!requestSnap.exists) throw httpError(404, 'REQUEST_NOT_FOUND');
    const viewSnap = await tx.get(viewRef);
    const nowIso = new Date(nowMs).toISOString();
    if (viewSnap.exists) {
      const view = { id: viewSnap.id, ...viewSnap.data() };
      tx.update(viewRef, {
        lastViewedAt: nowIso,
        viewCount: FieldValue.increment(1),
        // Refresh the denormalized card in case the seller renamed the shop.
        sellerName: seller.displayName,
        sellerAvatarUrl: seller.avatarUrl,
        sellerStoreName: seller.storeName,
        sellerKycApproved: seller.kycApproved,
      });
      return { created: false, view: { ...view, lastViewedAt: nowIso } };
    }
    const view = {
      requestId: String(requestId),
      sellerUid: seller.uid,
      sellerName: seller.displayName,
      sellerAvatarUrl: seller.avatarUrl,
      sellerStoreName: seller.storeName,
      sellerKycApproved: seller.kycApproved,
      firstViewedAt: nowIso,
      lastViewedAt: nowIso,
      viewCount: 1,
      notified: false,
    };
    tx.set(viewRef, view);
    tx.update(requestRef, {
      viewCount: FieldValue.increment(1),
      lastViewedAt: nowIso,
    });
    return { created: true, view: { id: viewRef.id, ...view } };
  });
}

async function markViewNotified(requestId, sellerUid) {
  const db = requireDb();
  await db.collection(COLLECTIONS.views).doc(offerId(requestId, sellerUid))
    .set({ notified: true, notifiedAt: new Date().toISOString() }, { merge: true });
}

async function listViews(requestId, { limit = 100 } = {}) {
  return commerceStore.listDocuments(COLLECTIONS.views, {
    where: { requestId: String(requestId) },
    orderBy: 'firstViewedAt',
    direction: 'desc',
    limit,
  });
}

async function getView(requestId, sellerUid) {
  const db = requireDb();
  const snap = await db.collection(COLLECTIONS.views).doc(offerId(requestId, sellerUid)).get();
  return withId(snap);
}

async function getOfferById(id) {
  const db = requireDb();
  const snap = await db.collection(COLLECTIONS.offers).doc(String(id)).get();
  return withId(snap);
}

async function listOffers(requestId, { limit = 100 } = {}) {
  return commerceStore.listDocuments(COLLECTIONS.offers, {
    where: { requestId: String(requestId) },
    orderBy: 'createdAt',
    direction: 'desc',
    limit,
  });
}

async function listSellerOffers(sellerUid, { limit = 100 } = {}) {
  return commerceStore.listDocuments(COLLECTIONS.offers, {
    where: { sellerUid },
    orderBy: 'createdAt',
    direction: 'desc',
    limit,
  });
}

async function getOffer(requestId, sellerUid) {
  return getOfferById(offerId(requestId, sellerUid));
}

/**
 * Creates or replaces a seller's offer atomically.
 *
 * The limit counter lives on the request document and is incremented inside
 * the same transaction that reads it, so two sellers racing for the last slot
 * produce a Firestore conflict and exactly one wins. Counting `offers` with an
 * aggregation query inside the transaction is not supported by Firestore, and
 * a read-then-write counter outside a transaction would allow overrun.
 */
async function createOffer({ requestId, seller, input, policy, nowMs = Date.now() }) {
  const db = requireDb();
  const requestRef = db.collection(COLLECTIONS.requests).doc(String(requestId));
  const offerRef = db.collection(COLLECTIONS.offers).doc(offerId(requestId, seller.uid));
  return commerceStore.runTransaction(async (tx) => {
    const requestSnap = await tx.get(requestRef);
    if (!requestSnap.exists) throw httpError(404, 'REQUEST_NOT_FOUND');
    const doc = { id: requestSnap.id, ...requestSnap.data() };
    if (doc.buyerUid === seller.uid) throw httpError(403, 'CANNOT_OFFER_ON_OWN_REQUEST');

    const status = statusFor(doc, policy, nowMs);
    if (status === 'expired') throw httpError(409, 'REQUEST_EXPIRED');
    if (status === 'limit_reached') throw httpError(409, 'OFFER_LIMIT_REACHED');
    if (status !== 'active') throw httpError(409, 'REQUEST_NOT_ACCEPTING_OFFERS');

    const existingSnap = await tx.get(offerRef);
    const existing = withId(existingSnap);
    if (existing && existing.status !== 'withdrawn' && existing.status !== 'declined') {
      throw httpError(409, 'OFFER_ALREADY_EXISTS');
    }

    const nowIso = new Date(nowMs).toISOString();
    const offer = {
      requestId: String(requestId),
      sellerUid: seller.uid,
      sellerName: seller.displayName,
      sellerAvatarUrl: seller.avatarUrl,
      sellerStoreName: seller.storeName,
      sellerKycApproved: seller.kycApproved,
      sellerWhatsappEnabled: seller.whatsappEnabled === true,
      price: input.price,
      currency: 'TZS',
      message: input.message || '',
      deliveryDays: input.deliveryDays,
      condition: input.condition || doc.condition || '',
      brand: input.brand || '',
      model: input.model || '',
      warranty: input.warranty || '',
      status: 'pending',
      version: 1,
      // Snapshot the terms the seller saw. A later buyer edit bumps the
      // request version; this field proves what the offer was based on.
      requestVersion: Number(doc.version || 1),
      requestSnapshot: {
        title: doc.title || '',
        version: Number(doc.version || 1),
        minBudget: Number(doc.minBudget || 0),
        maxBudget: Number(doc.maxBudget || 0),
        expiresAt: iso(doc.expiresAt),
      },
      createdAt: nowIso,
      updatedAt: nowIso,
    };
    tx.set(offerRef, offer);

    const nextCount = Number(doc.offersCount || 0) + 1;
    const nextStatus = nextCount >= Number(doc.offerLimit || 0) ? 'limit_reached' : 'active';
    tx.update(requestRef, {
      offersCount: FieldValue.increment(1),
      totalOfferCount: FieldValue.increment(1),
      status: nextStatus,
      updatedAt: nowIso,
    });
    return {
      offer: { id: offerRef.id, ...offer },
      request: { ...doc, offersCount: nextCount, status: nextStatus },
      limitReached: nextStatus === 'limit_reached',
    };
  });
}

async function withdrawOffer({ requestId, sellerUid, nowMs = Date.now() }) {
  const db = requireDb();
  const requestRef = db.collection(COLLECTIONS.requests).doc(String(requestId));
  const offerRef = db.collection(COLLECTIONS.offers).doc(offerId(requestId, sellerUid));
  return commerceStore.runTransaction(async (tx) => {
    const offerSnap = await tx.get(offerRef);
    if (!offerSnap.exists) throw httpError(404, 'OFFER_NOT_FOUND');
    const offer = { id: offerSnap.id, ...offerSnap.data() };
    if (offer.sellerUid !== sellerUid) throw httpError(403, 'OFFER_NOT_OWNED');
    if (!['pending', 'shortlisted'].includes(offer.status)) {
      throw httpError(409, 'OFFER_NOT_WITHDRAWABLE');
    }
    const requestSnap = await tx.get(requestRef);
    if (!requestSnap.exists) throw httpError(404, 'REQUEST_NOT_FOUND');
    const request = { id: requestSnap.id, ...requestSnap.data() };
    const nextCount = Math.max(0, Number(request.offersCount || 0) - 1);
    const nextStatus = request.status === 'limit_reached' ? 'active' : request.status;
    const nowIso = new Date(nowMs).toISOString();
    tx.update(offerRef, { status: 'withdrawn', withdrawnAt: nowIso, updatedAt: nowIso });
    tx.update(requestRef, {
      offersCount: nextCount,
      status: nextStatus,
      updatedAt: nowIso,
    });
    return {
      offer: { ...offer, status: 'withdrawn', withdrawnAt: nowIso },
      request: { ...request, offersCount: nextCount, status: nextStatus },
    };
  });
}

async function decideOffer({ requestId, offerId: id, buyerUid, action, nowMs = Date.now() }) {
  const db = requireDb();
  const requestRef = db.collection(COLLECTIONS.requests).doc(String(requestId));
  const offerRef = db.collection(COLLECTIONS.offers).doc(String(id));
  return commerceStore.runTransaction(async (tx) => {
    const requestSnap = await tx.get(requestRef);
    if (!requestSnap.exists) throw httpError(404, 'REQUEST_NOT_FOUND');
    const request = { id: requestSnap.id, ...requestSnap.data() };
    if (request.buyerUid !== buyerUid) throw httpError(403, 'REQUEST_NOT_OWNED');

    const offerSnap = await tx.get(offerRef);
    if (!offerSnap.exists) throw httpError(404, 'OFFER_NOT_FOUND');
    const offer = { id: offerSnap.id, ...offerSnap.data() };
    if (offer.requestId !== String(requestId)) throw httpError(404, 'OFFER_NOT_FOUND');
    if (!['pending', 'shortlisted'].includes(offer.status)) {
      throw httpError(409, 'OFFER_ALREADY_DECIDED');
    }

    const nowIso = new Date(nowMs).toISOString();
    if (action === 'accept') {
      tx.update(offerRef, { status: 'accepted', decidedAt: nowIso, updatedAt: nowIso });
      tx.update(requestRef, {
        status: 'completed',
        completedAt: nowIso,
        updatedAt: nowIso,
        acceptedOfferId: id,
        acceptedSellerUid: offer.sellerUid,
      });
      return {
        request: { ...request, status: 'completed', acceptedOfferId: id },
        offer: { ...offer, status: 'accepted' },
      };
    }

    const nextCount = Math.max(0, Number(request.offersCount || 0) - 1);
    const nextStatus = request.status === 'limit_reached' ? 'active' : request.status;
    tx.update(offerRef, { status: 'declined', decidedAt: nowIso, updatedAt: nowIso });
    tx.update(requestRef, {
      offersCount: nextCount,
      status: nextStatus,
      updatedAt: nowIso,
    });
    return {
      request: { ...request, offersCount: nextCount, status: nextStatus },
      offer: { ...offer, status: 'declined' },
    };
  });
}

async function addEvent({ requestId, type, actorUid = null, actorRole = 'user', data = {} }) {
  try {
    await commerceStore.addDocument(COLLECTIONS.events, {
      requestId: String(requestId),
      type,
      actorUid,
      actorRole,
      data,
      at: new Date().toISOString(),
    });
  } catch (e) {
    // Activity history is supporting evidence, never the source of truth.
    console.error('[buyer-requests] event write failed:', e?.message || e);
  }
}

async function listEvents(requestId, { limit = 100 } = {}) {
  return commerceStore.listDocuments(COLLECTIONS.events, {
    where: { requestId: String(requestId) },
    orderBy: 'at',
    direction: 'desc',
    limit,
  });
}

// Admin mutations bypass buyer ownership on purpose but still go through a
// transaction so a moderator cannot race the buyer's own save.

async function adminSetStatus({ requestId, to, reason, adminId, nowMs = Date.now() }) {
  const db = requireDb();
  return commerceStore.runTransaction(async (tx) => {
    const ref = db.collection(COLLECTIONS.requests).doc(String(requestId));
    const snap = await tx.get(ref);
    if (!snap.exists) throw httpError(404, 'REQUEST_NOT_FOUND');
    const doc = { id: snap.id, ...snap.data() };
    const nowIso = new Date(nowMs).toISOString();
    const updates = {
      status: to,
      updatedAt: nowIso,
      moderation: {
        hidden: to === 'suspended',
        reason: reason || '',
        at: nowIso,
        by: adminId || null,
      },
    };
    if (to === 'closed') updates.closedAt = nowIso;
    if (to === 'active') {
      updates.closedAt = null;
      updates.suspendedAt = null;
      updates.moderation = { hidden: false, reason: reason || '', at: nowIso, by: adminId || null };
    }
    if (to === 'suspended') updates.suspendedAt = nowIso;
    tx.update(ref, updates);
    return { request: { ...doc, ...updates } };
  });
}

async function adminExtend({ requestId, hours, reason, adminId, nowMs = Date.now() }) {
  const db = requireDb();
  return commerceStore.runTransaction(async (tx) => {
    const ref = db.collection(COLLECTIONS.requests).doc(String(requestId));
    const snap = await tx.get(ref);
    if (!snap.exists) throw httpError(404, 'REQUEST_NOT_FOUND');
    const doc = { id: snap.id, ...snap.data() };
    const currentMs = Math.max(millis(doc.expiresAtMs || doc.expiresAt), nowMs);
    const nextMs = currentMs + hours * 3600 * 1000;
    const nowIso = new Date(nowMs).toISOString();
    tx.update(ref, {
      expiresAt: new Date(nextMs).toISOString(),
      expiresAtMs: nextMs,
      updatedAt: nowIso,
      status: doc.status === 'expired' ? 'active' : doc.status,
      moderation: {
        hidden: false,
        reason: reason || '',
        at: nowIso,
        by: adminId || null,
      },
    });
    return { request: { ...doc, expiresAt: new Date(nextMs).toISOString(), expiresAtMs: nextMs } };
  });
}

async function adminModerateOffer({ requestId, offerId: id, action, reason, adminId, nowMs = Date.now() }) {
  const db = requireDb();
  const requestRef = db.collection(COLLECTIONS.requests).doc(String(requestId));
  const offerRef = db.collection(COLLECTIONS.offers).doc(String(id));
  return commerceStore.runTransaction(async (tx) => {
    const offerSnap = await tx.get(offerRef);
    if (!offerSnap.exists) throw httpError(404, 'OFFER_NOT_FOUND');
    const offer = { id: offerSnap.id, ...offerSnap.data() };
    if (offer.requestId !== String(requestId)) throw httpError(404, 'OFFER_NOT_FOUND');
    const requestSnap = await tx.get(requestRef);
    if (!requestSnap.exists) throw httpError(404, 'REQUEST_NOT_FOUND');
    const request = { id: requestSnap.id, ...requestSnap.data() };
    const nowIso = new Date(nowMs).toISOString();

    if (action === 'hide') {
      const nextCount = ['pending', 'shortlisted'].includes(offer.status)
        ? Math.max(0, Number(request.offersCount || 0) - 1)
        : Number(request.offersCount || 0);
      tx.update(offerRef, {
        status: 'removed',
        moderation: { reason: reason || '', at: nowIso, by: adminId || null },
        updatedAt: nowIso,
      });
      tx.update(requestRef, {
        offersCount: nextCount,
        status: request.status === 'limit_reached' ? 'active' : request.status,
        updatedAt: nowIso,
      });
      return { offer: { ...offer, status: 'removed' }, request: { ...request, offersCount: nextCount } };
    }

    tx.update(offerRef, {
      moderation: { reason: reason || '', at: nowIso, by: adminId || null },
      updatedAt: nowIso,
    });
    return { offer, request };
  });
}

/**
 * Lazily expires a single request. Idempotent: only a still-open request is
 * updated, so two app instances racing the sweeper cannot double-notify.
 */
async function expireRequest(requestId, nowMs = Date.now()) {
  const db = requireDb();
  const ref = db.collection(COLLECTIONS.requests).doc(String(requestId));
  const nowIso = new Date(nowMs).toISOString();
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return null;
    const doc = { id: snap.id, ...snap.data() };
    if (!['active', 'limit_reached'].includes(doc.status)) return null;
    if (millis(doc.expiresAtMs || doc.expiresAt) > nowMs) return null;
    tx.update(ref, { status: 'expired', expiredAt: nowIso, updatedAt: nowIso });
    return { ...doc, status: 'expired' };
  });
  return result;
}

async function findDueForExpiry(nowMs, limit = 200) {
  const db = requireDb();
  const snap = await db.collection(COLLECTIONS.requests)
    .where('expiresAtMs', '<=', nowMs)
    .limit(limit)
    .get();
  return snap.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .filter((d) => ['active', 'limit_reached'].includes(d.status));
}

async function findExpiringSoon(nowMs, windowMs, limit = 200) {
  const db = requireDb();
  const snap = await db.collection(COLLECTIONS.requests)
    .where('expiresAtMs', '>', nowMs)
    .where('expiresAtMs', '<=', nowMs + windowMs)
    .limit(limit)
    .get();
  return snap.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .filter((d) => ['active', 'limit_reached'].includes(d.status) && !d.expiringNotifiedAt);
}

async function markExpiryNotified(requestId, nowMs = Date.now()) {
  const db = requireDb();
  await db.collection(COLLECTIONS.requests).doc(String(requestId))
    .set({ expiringNotifiedAt: new Date(nowMs).toISOString() }, { merge: true });
}

async function adminList({ status, buyerUid, limit = 50, offset = 0 } = {}) {
  const where = [];
  if (status) where.push({ field: 'status', op: '==', value: status });
  if (buyerUid) where.push({ field: 'buyerUid', op: '==', value: buyerUid });
  return commerceStore.listDocuments(COLLECTIONS.requests, {
    where,
    orderBy: 'createdAt',
    direction: 'desc',
    limit,
    offset,
  });
}

async function adminStats(nowMs = Date.now()) {
  const db = requireDb();
  const [
    total, active, expired, closed, completed, suspended,
    offers, views, withOffers, noActivity,
  ] = await Promise.all([
    db.collection(COLLECTIONS.requests).count().get(),
    db.collection(COLLECTIONS.requests).where('status', '==', 'active').count().get(),
    db.collection(COLLECTIONS.requests).where('status', '==', 'expired').count().get(),
    db.collection(COLLECTIONS.requests).where('status', '==', 'closed').count().get(),
    db.collection(COLLECTIONS.requests).where('status', '==', 'completed').count().get(),
    db.collection(COLLECTIONS.requests).where('status', '==', 'suspended').count().get(),
    db.collection(COLLECTIONS.offers).count().get(),
    db.collection(COLLECTIONS.views).count().get(),
    db.collection(COLLECTIONS.requests).where('offersCount', '>', 0).count().get(),
    db.collection(COLLECTIONS.requests).where('viewCount', '==', 0).count().get(),
  ]);
  return {
    generatedAt: new Date(nowMs).toISOString(),
    requests: {
      total: total.data().count,
      active: active.data().count,
      expired: expired.data().count,
      closed: closed.data().count,
      completed: completed.data().count,
      suspended: suspended.data().count,
      receivingOffers: withOffers.data().count,
      noSellerActivity: noActivity.data().count,
    },
    offers: offers.data().count,
    views: views.data().count,
    conversion: {
      // Share of requests that received at least one live offer.
      offerRate: total.data().count
        ? Math.round((withOffers.data().count / total.data().count) * 1000) / 10
        : 0,
    },
  };
}

module.exports = {
  COLLECTIONS,
  LIVE_OFFER_STATUSES,
  offerId,
  iso,
  getRequest,
  findRequestByOfferId,
  createRequest,
  listRequests,
  countBuyerRequests,
  listBuyerRequests,
  applyEdit,
  applyExtend,
  setRequestStatus,
  recordView,
  markViewNotified,
  listViews,
  getView,
  getOfferById,
  listOffers,
  listSellerOffers,
  getOffer,
  createOffer,
  withdrawOffer,
  decideOffer,
  addEvent,
  listEvents,
  adminSetStatus,
  adminExtend,
  adminModerateOffer,
  expireRequest,
  findDueForExpiry,
  findExpiringSoon,
  markExpiryNotified,
  adminList,
  adminStats,
  getUserSnapshot,
  identityFromUser,
  contactFromUser,
  serializeRequest,
  serializeView,
  serializeOffer,
};
