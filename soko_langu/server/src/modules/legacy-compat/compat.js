// Legacy-compat mounts: serves the proven old routers (payouts, delivery
// OTP, search, notifications) under their ORIGINAL /api paths inside the
// new v2 app. Zero Flutter changes needed for these flows. Firestore is the
// same project, so data continues where it left off.
const crypto = require('crypto');
const admin = require('firebase-admin');
const { getFirebaseApp, getFirebaseFirestore } = require('../../config/firebase');
const { getRedis } = require('../../config/redis');
const { requireUser, requireAdmin, isOwnerOrAdmin, checkSuspended } = require('./auth-helpers');
const { sendOneSignalNotification, notifyAdmins } = require('./notify');

const { clickpesaPayout, getPayoutFee, createPayloadChecksum } = require('../../../clickpesa');
const payoutHelpers = require('../../../helpers/payouts');
const cache = require('../../../cache');

let ipRangeCheck = null;
try {
  ipRangeCheck = require('ip-range-check');
} catch (_) {
  ipRangeCheck = null;
}

function webhookIpWhitelist(req, res, next) {
  const allowedRaw = process.env.CLICKPESA_ALLOWED_IPS;
  if (!allowedRaw) {
    if (process.env.NODE_ENV === 'production') {
      console.error('[SECURITY] CLICKPESA_ALLOWED_IPS not set — rejecting webhook in production');
      return res.status(503).json({ error: 'Webhook IP whitelist not configured' });
    }
    return next();
  }
  const clientIp = req.ip || (req.connection && req.connection.remoteAddress) || '';
  const cleanIp = String(clientIp).replace(/^::ffff:/, '');
  const allowed = allowedRaw.split(',').map((s) => s.trim()).filter(Boolean);
  if (ipRangeCheck) {
    if (ipRangeCheck(cleanIp, allowed)) return next();
  } else if (allowed.includes(cleanIp)) {
    return next();
  }
  console.warn(`[SECURITY] Webhook from unauthorized IP: ${cleanIp}`);
  return res.status(403).json({ error: 'IP not whitelisted' });
}

function verifyWebhook(req, res, next) {
  const secret = process.env.CLICKPESA_CHECKSUM_KEY;
  if (!secret) {
    console.error('[WEBHOOK] CLICKPESA_CHECKSUM_KEY not set — rejecting webhook for security');
    return res.status(503).json({ error: 'Webhook verification not configured' });
  }
  const body = req.body || {};
  const provided = typeof body.checksum === 'string' ? body.checksum : '';
  if (!provided) {
    console.warn('[WEBHOOK] missing checksum — rejecting forged callback');
    return res.status(401).json({ error: 'invalid checksum' });
  }
  const { checksum: _omit, checksumMethod: _omitMethod, ...rest } = body;
  const expected = createPayloadChecksum(rest);
  const match =
    expected &&
    crypto.timingSafeEqual(Buffer.from(provided, 'hex'), Buffer.from(expected, 'hex'));
  if (!expected || !match) {
    console.warn('[WEBHOOK] invalid checksum — rejecting callback');
    return res.status(401).json({ error: 'invalid checksum' });
  }
  next();
}

// Wire shared handles onto the Express app (delivery_otp reads req.app.locals).
function setupCompat(app) {
  getFirebaseApp();
  const db = getFirebaseFirestore();
  const redis = getRedis();

  try {
    cache.setRedisClient(redis);
  } catch (e) {
    console.error('[COMPAT] cache redis wiring failed:', e.message);
  }

  const { generatePayoutReference, PAYOUT_STATUSES, auditLog } = payoutHelpers({ admin, db });

  Object.assign(app.locals, {
    admin,
    db,
    redis,
    requireUser,
    sendOneSignalNotification,
    clickpesaPayout,
    getPayoutFee,
    generatePayoutReference,
    PAYOUT_STATUSES,
    auditLog,
    checkSuspended,
    notifyAdmins,
  });

  const payoutsFactory = require('../../../routes/payouts');
  const { router: payoutsRouter } = payoutsFactory({
    admin,
    db,
    requireUser,
    requireAdmin,
    isOwnerOrAdmin,
    sendOneSignalNotification,
    webhookIpWhitelist,
    verifyWebhook,
  });

  // eslint-disable-next-line global-require
  const deliveryRouter = require('../../../routes/delivery_otp');
  // eslint-disable-next-line global-require
  const { router: searchRouter } = require('../../../search');
  // eslint-disable-next-line global-require
  const { router: notificationRouter } = require('../../../notification');
  // eslint-disable-next-line global-require
  const escrowRouter = require('./escrow-compat');
  // eslint-disable-next-line global-require
  const ordersCompatRouter = require('./orders-compat');

  return { payoutsRouter, deliveryRouter, searchRouter, notificationRouter, escrowRouter, ordersCompatRouter };
}

module.exports = { setupCompat, webhookIpWhitelist, verifyWebhook };
