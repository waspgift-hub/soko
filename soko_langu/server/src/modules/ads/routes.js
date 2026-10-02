const { Router } = require('express');
const { authenticateAdmin, requireActiveAdmin } = require('../../middleware/auth');
const { getFirebaseFirestore } = require('../../config/firebase');
const { writeAudit, auditFromReq } = require('../../services/audit');
const adsConfig = require('./ads-config');
const { deriveBlueTick, BLUE_TICK } = require('./blue-tick');

const router = Router();

/**
 * Admin controls for advertising and Blue Tick visibility.
 *
 * Both features are driven by `app_settings/ad_config`, so nothing here needs a
 * mobile release: the Flutter `AdRemoteConfigService` streams the same document
 * and `AdManager` re-evaluates on every change.
 *
 * `router.use(authenticateAdmin)` mirrors the general admin router — a correct
 * `x-admin-secret`, or strict Firebase auth plus an admin role. There is no
 * client-writable path to any of these values.
 */

// ─── Advertising configuration ─────────────────────────────────────────────

router.get('/config/ads', async (req, res) => {
  const data = await adsConfig.load();
  res.json({ success: true, data });
});

router.put('/config/ads', requireActiveAdmin, async (req, res) => {
  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const patch = body.config && typeof body.config === 'object' ? body.config : body;

  const next = await adsConfig.save(patch, { actor: req.user?.id || 'admin-secret' });
  await writeAudit(
    auditFromReq(req, {
      action: 'ads.config.update',
      entityType: 'app_settings',
      entityId: adsConfig.DOC_ID,
      newState: next,
    }),
  );
  res.json({ success: true, data: next });
});

// ─── Blue Tick ──────────────────────────────────────────────────────────────

/** Reads the derived Blue Tick for any seller without mutating anything. */
router.get('/sellers/:userId/blue-tick', async (req, res) => {
  const db = getFirebaseFirestore();
  const uid = String(req.params.userId || '').trim();
  if (!uid) return res.status(400).json({ success: false, error: 'VALIDATION', message: 'userId required' });

  const snap = await db.collection('users').doc(uid).get();
  const derived = deriveBlueTick(snap.exists ? snap.data() : null, null);
  res.json({ success: true, data: { userId: uid, ...derived } });
});

/**
 * Grants or revokes the Blue Tick.
 *
 * A grant is refused unless KYC is genuinely APPROVED — the same condition the
 * client-side derivation enforces — so an admin mistake cannot create a tick
 * that the derivation would immediately discard, and cannot mark an unverified
 * seller as exempt from ads.
 *
 * Revocation is always allowed and is immediate: it flips `trust.blueTick` to
 * `revoked`, which makes `deriveBlueTick` return `adsExempt: false`, restores
 * normal advertising, and — because the Flutter service subscribes to the user's
 * `trust` subdocument — removes the badge on the seller's own device without a
 * restart.
 */
router.put('/sellers/:userId/blue-tick', requireActiveAdmin, async (req, res) => {
  const db = getFirebaseFirestore();
  const uid = String(req.params.userId || '').trim();
  const action = String((req.body && req.body.action) || '').trim().toLowerCase();
  if (!uid) return res.status(400).json({ success: false, error: 'VALIDATION', message: 'userId required' });
  if (action !== 'grant' && action !== 'revoke') {
    return res.status(400).json({ success: false, error: 'VALIDATION', message: 'action must be grant or revoke' });
  }

  const ref = db.collection('users').doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    return res.status(404).json({ success: false, error: 'USER_NOT_FOUND', message: 'No such user' });
  }

  const current = snap.data() || {};
  const before = deriveBlueTick(current, null);

  if (action === 'grant') {
    const kyc = current.kyc && typeof current.kyc === 'object' ? current.kyc : {};
    const kycApproved = kyc.status === 'approved' && kyc.approved === true && !kyc.revokedAt;
    if (!kycApproved) {
      return res.status(409).json({
        success: false,
        error: 'KYC_NOT_APPROVED',
        message: `Blue Tick requires approved KYC. Current kyc.status=${kyc.status || 'none'}.`,
        data: before,
      });
    }
  }

  const patch =
    action === 'grant'
      ? {
          blueTick: BLUE_TICK.ACTIVE,
          blueTickGrantedAt: new Date().toISOString(),
          blueTickRevokedAt: null,
          blueTickGrantedBy: req.user?.id || 'admin-secret',
        }
      : {
          blueTick: BLUE_TICK.REVOKED,
          blueTickRevokedAt: new Date().toISOString(),
          blueTickRevokedBy: req.user?.id || 'admin-secret',
        };

  await ref.set({ trust: patch }, { merge: true });

  // Keep the denormalised product flag consistent so search ranking follows the
  // decision. Writing it here (admin SDK) is what `firestore.rules` requires —
  // a seller cannot set this field on their own product doc.
  const productFlag = action === 'grant';
  const products = await db.collection('products').where('sellerId', '==', uid).get();
  const batch = db.batch();
  let touched = 0;
  products.forEach((doc) => {
    if (doc.data()?.sellerKycApproved === productFlag) return;
    batch.update(doc.ref, { sellerKycApproved: productFlag });
    touched += 1;
  });
  if (touched > 0) await batch.commit();

  const after = deriveBlueTick({ ...current, trust: { ...(current.trust || {}), ...patch } }, null);
  await writeAudit(
    auditFromReq(req, {
      action: `ads.blue_tick.${action}`,
      entityType: 'user',
      entityId: uid,
      oldState: { blueTick: before.blueTick, adsExempt: before.adsExempt, reason: before.reason },
      newState: { blueTick: after.blueTick, adsExempt: after.adsExempt, productsTouched: touched },
    }),
  );

  res.json({ success: true, data: { userId: uid, productsTouched: touched, ...after } });
});

/**
 * Ad eligibility for the caller's own account.
 *
 * Useful for the admin screen's "who is currently exempt" view and for support
 * debugging. Reads trusted state only; the caller cannot influence the answer.
 */
router.get('/ads/eligibility', async (req, res) => {
  const db = getFirebaseFirestore();
  const uid = req.user?.id || null;
  if (!uid) {
    return res.status(401).json({
      success: false,
      error: 'AUTH_REQUIRED',
      message: 'Present a Firebase admin token to read your own eligibility.',
    });
  }

  const snap = await db.collection('users').doc(uid).get();
  const derived = deriveBlueTick(snap.exists ? snap.data() : null, null);
  const cfg = await adsConfig.load();

  res.json({
    success: true,
    data: {
      userId: uid,
      blueTick: derived.blueTick,
      adsExempt: derived.adsExempt && cfg.adsExemptBlueTickEnabled,
      reason: derived.reason,
    },
  });
});

module.exports = router;