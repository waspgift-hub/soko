const service = require('./request-service');
const store = require('./request-store');

function fail(res, error, fallback) {
  const status = error.status || 500;
  const code = error.code || error.message || fallback;
  if (status >= 500) console.error('[BUYER-REQUESTS]', error.message);
  return res.status(status).json({ success: false, error: code, code, message: error.message || fallback });
}

function ok(res, data, status = 200) {
  return res.status(status).json({ success: true, data });
}

// Reads
async function getConfig(req, res) {
  try {
    const data = await service.getConfig(Date.now());
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to load config'); }
}

async function listFeed(req, res) {
  try {
    const viewerUid = req.firebaseUid || null;
    const data = await service.listFeed({ viewerUid, query: req.query || {}, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to load requests'); }
}

async function listMine(req, res) {
  try {
    const data = await service.listMine({ buyerUid: req.firebaseUid, query: req.query || {}, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to load my requests'); }
}

async function getDetail(req, res) {
  try {
    const viewerUid = req.firebaseUid || null;
    const viewer = viewerUid ? await store.getUserSnapshot(viewerUid) : null;
    const data = await service.getDetail({ requestId: req.params.id, viewerUid, viewer, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to load request'); }
}

async function getViews(req, res) {
  try {
    const data = await service.listViews({ requestId: req.params.id, buyerUid: req.firebaseUid });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to load views'); }
}

async function getOffers(req, res) {
  try {
    const viewerRole = req.isAdmin ? 'admin' : 'user';
    const data = await service.listOffersFor({ requestId: req.params.id, viewerUid: req.firebaseUid, viewerRole, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to load offers'); }
}

async function getHistory(req, res) {
  try {
    const viewerRole = req.isAdmin ? 'admin' : 'user';
    const data = await service.getHistory({ requestId: req.params.id, buyerUid: req.firebaseUid, viewerRole });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to load history'); }
}

async function getSellerContact(req, res) {
  try {
    const lang = (req.query && req.query.lang) || 'sw';
    const data = await service.sellerContact({ requestId: req.params.id, buyerUid: req.firebaseUid, sellerId: req.params.sellerId, lang, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to load seller contact'); }
}

async function getNotificationPrefs(req, res) {
  try {
    const db = require('../../config/firebase').getFirebaseFirestore();
    const uid = req.firebaseUid;
    if (!db) return ok(res, { pushEnabled: true, buyerRequestViews: true, buyerRequestOffers: true });
    const snap = await db.collection('user_notification_preferences').doc(uid).get();
    const prefs = snap.exists ? snap.data() : {};
    const cats = (prefs && prefs.categoryPreferences) || {};
    return ok(res, {
      pushEnabled: prefs.pushEnabled !== false,
      buyerRequestViews: cats.buyerRequestViews !== false,
      buyerRequestOffers: cats.buyerRequestOffers !== false,
    });
  } catch (e) { return fail(res, e, 'Failed to load notification preferences'); }
}

async function updateNotificationPrefs(req, res) {
  try {
    const db = require('../../config/firebase').getFirebaseFirestore();
    const uid = req.firebaseUid;
    const body = req.body || {};
    if (!db) return ok(res, { updated: false });
    const ref = db.collection('user_notification_preferences').doc(uid);
    const snap = await ref.get();
    const existing = snap.exists ? snap.data() : {};
    const cats = { ...((existing && existing.categoryPreferences) || {}) };
    if (typeof body.buyerRequestViews === 'boolean') cats.buyerRequestViews = body.buyerRequestViews;
    if (typeof body.buyerRequestOffers === 'boolean') cats.buyerRequestOffers = body.buyerRequestOffers;
    const updates = { categoryPreferences: cats, updatedAt: new Date().toISOString() };
    if (typeof body.pushEnabled === 'boolean') updates.pushEnabled = body.pushEnabled;
    await ref.set(updates, { merge: true });
    return ok(res, { updated: true, pushEnabled: updates.pushEnabled !== false, buyerRequestViews: cats.buyerRequestViews !== false, buyerRequestOffers: cats.buyerRequestOffers !== false });
  } catch (e) { return fail(res, e, 'Failed to update notification preferences'); }
}

// Writes
async function create(req, res) {
  try {
    const data = await service.create({ buyerUid: req.firebaseUid, input: req.body || {}, nowMs: Date.now() });
    return ok(res, data, 201);
  } catch (e) { return fail(res, e, 'Failed to create request'); }
}

async function update(req, res) {
  try {
    const data = await service.update({ requestId: req.params.id, buyerUid: req.firebaseUid, patch: req.body || {}, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to update request'); }
}

async function extend(req, res) {
  try {
    const data = await service.extend({ requestId: req.params.id, buyerUid: req.firebaseUid, hours: req.body && req.body.hours, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to extend request'); }
}

async function close(req, res) {
  try {
    const data = await service.close({ requestId: req.params.id, buyerUid: req.firebaseUid, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to close request'); }
}

async function reopen(req, res) {
  try {
    const data = await service.reopen({ requestId: req.params.id, buyerUid: req.firebaseUid, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to reopen request'); }
}

async function trackView(req, res) {
  try {
    const data = await service.trackView({ requestId: req.params.id, viewerUid: req.firebaseUid, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to track view'); }
}

async function createOffer(req, res) {
  try {
    const data = await service.createOffer({ requestId: req.params.id, sellerUid: req.firebaseUid, input: req.body || {}, nowMs: Date.now() });
    return ok(res, data, 201);
  } catch (e) { return fail(res, e, 'Failed to submit offer'); }
}

async function withdrawOffer(req, res) {
  try {
    const data = await service.withdrawOffer({ requestId: req.params.id, offerId: req.params.offerId, sellerUid: req.firebaseUid, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to withdraw offer'); }
}

async function decideOffer(req, res) {
  try {
    const action = (req.body && req.body.action) || req.params.action;
    const data = await service.decideOffer({ requestId: req.params.id, offerId: req.params.offerId, buyerUid: req.firebaseUid, action, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to decide offer'); }
}

async function recordWhatsappClick(req, res) {
  try {
    const data = await service.recordWhatsappClick({ requestId: req.params.id, buyerUid: req.firebaseUid, sellerId: req.params.sellerId, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to track click'); }
}

// Admin
async function adminConfig(req, res) {
  try {
    const data = await service.adminConfig();
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to load admin config'); }
}

async function adminUpdateConfig(req, res) {
  try {
    const data = await service.adminUpdateConfig(req.body || {});
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to update config'); }
}

async function adminDashboard(req, res) {
  try {
    const data = await service.adminDashboard();
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to load dashboard'); }
}

async function adminListRequests(req, res) {
  try {
    const data = await service.adminListRequests({ status: req.query.status, buyerUid: req.query.buyerUid, page: req.query.page, limit: req.query.limit });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to list requests'); }
}

async function adminDetail(req, res) {
  try {
    const data = await service.adminDetail({ requestId: req.params.id });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to load request'); }
}

async function adminModerate(req, res) {
  try {
    const adminId = req.adminStaff ? req.adminStaff.id : (req.firebaseUid || 'admin');
    const data = await service.adminModerate({ requestId: req.params.id, action: req.body && req.body.action, reason: req.body && req.body.reason, hourList: req.body && req.body.hours, adminId, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to moderate request'); }
}

async function adminModerateOffer(req, res) {
  try {
    const adminId = req.adminStaff ? req.adminStaff.id : (req.firebaseUid || 'admin');
    const data = await service.adminModerateOffer({ requestId: req.params.id, offerId: req.params.offerId, action: req.body && req.body.action, reason: req.body && req.body.reason, adminId, nowMs: Date.now() });
    return ok(res, data);
  } catch (e) { return fail(res, e, 'Failed to moderate offer'); }
}

module.exports = {
  getConfig, listFeed, listMine, getDetail, getViews, getOffers, getHistory, getSellerContact,
  create, update, extend, close, reopen, trackView, createOffer, withdrawOffer, decideOffer, recordWhatsappClick,
  getNotificationPrefs, updateNotificationPrefs,
  adminConfig, adminUpdateConfig, adminDashboard, adminListRequests, adminDetail, adminModerate, adminModerateOffer,
};