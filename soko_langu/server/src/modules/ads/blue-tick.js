/**
 * Authoritative Blue Tick derivation.
 *
 * Trust boundary
 * --------------
 * This module is the ONLY place a Blue Tick is decided. Nothing a client sends
 * can influence the outcome:
 *
 *   1. `kyc.status === 'approved' && kyc.approved === true` — written only by
 *      `kyc-service.reviewKyc` through the admin SDK.
 *   2. `sellerProfile.verificationStatus === 'verified'` — written only by
 *      `PUT /api/v1/admin/sellers/:sellerId/verification`, behind
 *      `authenticateAdmin`.
 *   3. `trust.blueTick === 'active'` — an admin grant recorded in
 *      `users/{uid}.trust`. `firestore.rules` lists `trust` in
 *      `noSensitiveFieldChanges` / `noSensitiveCreateFields`, so no client can
 *      author it.
 *   4. Nothing is revoked.
 *
 * All three must hold. A pending, rejected or revoked KYC never yields a tick
 * even if a stale grant survives in `trust.blueTick`, and that reconciliation is
 * the reason the grant is *derived* here rather than trusted from the doc.
 */

/** Blue Tick states. Mirrors the Dart `BlueTickStatus` enum exactly. */
const BLUE_TICK = {
  NONE: 'none',
  PENDING: 'pending',
  ACTIVE: 'active',
  REVOKED: 'revoked',
};

function kycBlock(userDoc) {
  const kyc = userDoc && userDoc.kyc && typeof userDoc.kyc === 'object' ? userDoc.kyc : {};
  return {
    status: String(kyc.status || 'none'),
    approved: kyc.approved === true,
    revokedAt: kyc.revokedAt || null,
  };
}

function trustBlock(userDoc) {
  const trust = userDoc && userDoc.trust && typeof userDoc.trust === 'object' ? userDoc.trust : {};
  return {
    blueTick: String(trust.blueTick || BLUE_TICK.NONE),
    blueTickGrantedAt: trust.blueTickGrantedAt || null,
    blueTickRevokedAt: trust.blueTickRevokedAt || null,
  };
}

/**
 * Decides Blue Tick state for one seller.
 *
 * @param {object|null} userDoc     Firestore `users/{uid}` document data.
 * @param {object|null} sellerRow   Postgres `SellerProfile` row, when available.
 * @returns {{blueTick: string, adsExempt: boolean, reason: string, kyc: object, grantedAt: ?string, revokedAt: ?string}}
 */
function deriveBlueTick(userDoc, sellerRow) {
  const kyc = kycBlock(userDoc);
  const trust = trustBlock(userDoc);
  const sellerVerification = sellerRow ? String(sellerRow.verificationStatus || 'pending') : null;

  const kycOk = kyc.status === 'approved' && kyc.approved === true && !kyc.revokedAt;
  const sellerOk = sellerVerification === null ? true : sellerVerification === 'verified';
  const grantOk = trust.blueTick === BLUE_TICK.ACTIVE;

  if (kycOk && sellerOk && grantOk) {
    return {
      blueTick: BLUE_TICK.ACTIVE,
      adsExempt: true,
      reason: 'kyc_approved_and_granted',
      kyc,
      grantedAt: trust.blueTickGrantedAt,
      revokedAt: null,
    };
  }

  // An explicit revocation always wins and is reported as such so the admin UI
  // can distinguish "never granted" from "granted then revoked".
  if (trust.blueTick === BLUE_TICK.REVOKED) {
    return {
      blueTick: BLUE_TICK.REVOKED,
      adsExempt: false,
      reason: kycOk ? 'revoked_by_admin' : 'revoked_and_kyc_not_approved',
      kyc,
      grantedAt: trust.blueTickGrantedAt,
      revokedAt: trust.blueTickRevokedAt,
    };
  }

  let reason;
  if (!kycOk) {
    reason = `kyc_${kyc.status}`;
  } else if (!sellerOk) {
    reason = 'seller_not_verified';
  } else {
    reason = 'not_granted';
  }

  return {
    blueTick: trust.blueTick === BLUE_TICK.PENDING ? BLUE_TICK.PENDING : BLUE_TICK.NONE,
    adsExempt: false,
    reason,
    kyc,
    grantedAt: trust.blueTickGrantedAt,
    revokedAt: trust.blueTickRevokedAt,
  };
}

/**
 * Whether the signed-in seller is excluded from normal AdMob inventory.
 *
 * The only condition is a genuinely ACTIVE Blue Tick. Everyone else — anonymous
 * buyers, buyers, sellers with pending, rejected or revoked KYC, and sellers
 * whose grant was withdrawn — sees normal advertising.
 */
function isAdExempt(userDoc, sellerRow) {
  return deriveBlueTick(userDoc, sellerRow).adsExempt === true;
}

module.exports = { BLUE_TICK, deriveBlueTick, isAdExempt, kycBlock, trustBlock };