const { test } = require('node:test');
const assert = require('node:assert');

const { deriveBlueTick, isAdExempt, BLUE_TICK } = require('../src/modules/ads/blue-tick');
const ranking = require('../src/modules/search/search-ranking');
const adsConfig = require('../src/modules/ads/ads-config');

/**
 * Fixtures mirror exactly what the server writes.
 *
 * `kyc` is written only by kyc-service.reviewKyc via the admin SDK.
 * `sellerProfile.verificationStatus` is written only by
 * PUT /api/v1/admin/sellers/:id/verification.
 * `trust.blueTick` is written only by PUT /api/v1/admin/sellers/:id/blue-tick.
 */
const approvedKyc = { status: 'approved', approved: true };
const pendingKyc = { status: 'pending', approved: false };
const rejectedKyc = { status: 'rejected', approved: false };
const revokedKyc = { status: 'revoked', approved: false, revokedAt: '2026-02-01T00:00:00.000Z' };

const verifiedSeller = { verificationStatus: 'verified' };
const pendingSeller = { verificationStatus: 'pending' };

test('Blue Tick — a seller is exempt only when KYC is approved and the tick is active', () => {
  const doc = { kyc: approvedKyc, trust: { blueTick: BLUE_TICK.ACTIVE } };
  const result = deriveBlueTick(doc, verifiedSeller);
  assert.equal(result.blueTick, BLUE_TICK.ACTIVE);
  assert.equal(result.adsExempt, true);
  assert.equal(result.reason, 'kyc_approved_and_granted');
});

test('Blue Tick — every other state is not exempt', () => {
  const cases = [
    ['no kyc at all', {}, null, 'kyc_none'],
    ['kyc pending', { kyc: pendingKyc }, verifiedSeller, 'kyc_pending'],
    ['kyc rejected', { kyc: rejectedKyc }, verifiedSeller, 'kyc_rejected'],
    ['kyc revoked', { kyc: revokedKyc }, verifiedSeller, 'kyc_revoked'],
    [
      'kyc approved but no grant',
      { kyc: approvedKyc },
      verifiedSeller,
      'not_granted',
    ],
    [
      'kyc approved and granted but seller not verified',
      { kyc: approvedKyc, trust: { blueTick: BLUE_TICK.ACTIVE } },
      pendingSeller,
      'seller_not_verified',
    ],
  ];

  for (const [label, doc, seller, reason] of cases) {
    const result = deriveBlueTick(doc, seller);
    assert.equal(result.adsExempt, false, `${label} must not be exempt`);
    assert.equal(result.blueTick !== BLUE_TICK.ACTIVE, true, `${label} must not show a tick`);
    assert.equal(result.reason, reason, `${label} reason`);
  }
});

test('Blue Tick — an active grant cannot survive a KYC revocation', () => {
  // This is the case that proves the tick is *derived* rather than read straight
  // off the document: a stale grant left behind by a revocation must not buy an
  // ad-free account.
  const result = deriveBlueTick(
    { kyc: revokedKyc, trust: { blueTick: BLUE_TICK.ACTIVE } },
    verifiedSeller,
  );
  assert.equal(result.adsExempt, false);
  assert.equal(result.blueTick, BLUE_TICK.NONE);
  assert.equal(result.reason, 'kyc_revoked');
});

test('Blue Tick — revocation is reported distinctly from never-granted', () => {
  const revoked = deriveBlueTick(
    { kyc: approvedKyc, trust: { blueTick: BLUE_TICK.REVOKED } },
    verifiedSeller,
  );
  assert.equal(revoked.blueTick, BLUE_TICK.REVOKED);
  assert.equal(revoked.adsExempt, false);
  assert.equal(revoked.reason, 'revoked_by_admin');
});

test('Blue Tick — a missing Firestore doc downgrades rather than inventing a tick', () => {
  assert.equal(isAdExempt(null, null), false);
  assert.equal(deriveBlueTick(null, null).adsExempt, false);
});

test('Blue Tick — a malformed doc is treated as unverified', () => {
  for (const doc of [{}, { kyc: 'approved' }, { trust: null }, { kyc: { approved: 'yes' } }]) {
    assert.equal(deriveBlueTick(doc, null).adsExempt, false, JSON.stringify(doc));
  }
});

test('Ranking — relevance dominates the verified boost by default', () => {
  ranking.setRankingConfig(adsConfig.DEFAULTS);

  // An exact-title match with poor ratings, unverified.
  const exact = { name: 'iPhone 15', rating: 3.0, reviewCount: 1, soldCount: 0, sellerKycApproved: false };
  // A near-match from a highly-rated, heavily-selling verified seller.
  const fuzzyVerified = {
    name: 'iPhone 15 case',
    rating: 5.0,
    reviewCount: 900,
    soldCount: 900,
    sellerKycApproved: true,
  };

  const rows = [
    { id: 'fuzzy', d: fuzzyVerified, score: 30 },
    { id: 'exact', d: exact, score: 100 },
  ];

  const ordered = ranking.sortRows(rows, { sort: 'relevance' });
  assert.equal(ordered[0].id, 'exact',
    'a verified seller must never displace a strictly better relevance match');
});

test('Ranking — the verified boost breaks ties within the same relevance', () => {
  ranking.setRankingConfig(adsConfig.DEFAULTS);

  const verified = { name: 'x', rating: 4, reviewCount: 5, soldCount: 5, sellerKycApproved: true };
  const plain = { name: 'x', rating: 4, reviewCount: 5, soldCount: 5, sellerKycApproved: false };

  const rows = [
    { id: 'plain', d: plain, score: 40 },
    { id: 'verified', d: verified, score: 40 },
  ];
  const ordered = ranking.sortRows(rows, { sort: 'relevance' });
  assert.equal(ordered[0].id, 'verified');
});

test('Ranking — the boost magnitude is configurable', () => {
  const verified = { name: 'x', rating: 4, reviewCount: 5, soldCount: 5, sellerKycApproved: true };

  ranking.setRankingConfig({
    version: 1,
    searchVerifiedBoost: 0,
    maxSearchVerifiedBoost: 0.25,
    allowBoostToOutrankRelevance: false,
  });
  const noBoost = ranking.finalScore({ relevance: 50, doc: verified });
  assert.equal(noBoost, ranking.finalScore({ relevance: 50, doc: { ...verified, sellerKycApproved: false } }));

  ranking.setRankingConfig({
    version: 2,
    searchVerifiedBoost: 0.25,
    maxSearchVerifiedBoost: 0.25,
    allowBoostToOutrankRelevance: false,
  });
  const withBoost = ranking.finalScore({ relevance: 50, doc: verified });
  assert.ok(withBoost > noBoost, 'a configured boost must be observable');
});

test('Ranking — the boost is clamped by the admin ceiling', () => {
  const verified = { name: 'x', sellerKycApproved: true };
  ranking.setRankingConfig({
    version: 3,
    searchVerifiedBoost: 5,
    maxSearchVerifiedBoost: 0.25,
    allowBoostToOutrankRelevance: false,
  });
  ranking.setRankingConfig({
    version: 3,
    searchVerifiedBoost: 0.25,
    maxSearchVerifiedBoost: 0.25,
    allowBoostToOutrankRelevance: false,
  });
  // relevance 100 => max boost 25, halved and then clamped to 50% of relevance.
  const boosted = ranking.finalScore({ relevance: 100, doc: verified });
  assert.ok(boosted <= 125, `boost must stay inside the relevance band, got ${boosted}`);
  assert.ok(ranking.verifiedSellerBoost(verified) > 0);
});

test('Ranking — price sorts bypass the boost entirely', () => {
  ranking.setRankingConfig(adsConfig.DEFAULTS);
  const cheapUnverified = { name: 'a', price: 10, sellerKycApproved: false };
  const dearVerified = { name: 'b', price: 900, sellerKycApproved: true };

  const asc = ranking.sortRows(
    [
      { id: 'dear', d: dearVerified, score: 100 },
      { id: 'cheap', d: cheapUnverified, score: 1 },
    ],
    { sort: 'price_asc' },
  );
  assert.equal(asc[0].id, 'cheap', 'price_asc must be cheapest-first');

  const desc = ranking.sortRows(
    [
      { id: 'cheap', d: cheapUnverified, score: 1 },
      { id: 'dear', d: dearVerified, score: 100 },
    ],
    { sort: 'price_desc' },
  );
  assert.equal(desc[0].id, 'dear', 'price_desc must be dearest-first');
});

test('Ranking — non-matching results are never scored or returned', () => {
  ranking.setRankingConfig(adsConfig.DEFAULTS);
  assert.equal(ranking.finalScore({ relevance: 0, doc: { sellerKycApproved: true } }), 0);
});

test('Ranking — the boost is one signal, not a quality multiplier', () => {
  ranking.setRankingConfig({
    version: 4,
    searchVerifiedBoost: 0.25,
    maxSearchVerifiedBoost: 0.25,
    allowBoostToOutrankRelevance: false,
  });

  // Equal relevance: a well-reviewed unverified seller must still beat a
  // poorly-reviewed verified one once quality and engagement are counted.
  const strongPlain = { rating: 4.8, reviewCount: 200, soldCount: 150, sellerKycApproved: false };
  const weakVerified = { rating: 1.0, reviewCount: 1, soldCount: 0, sellerKycApproved: true };

  const rows = [
    { id: 'weak', d: weakVerified, score: 60 },
    { id: 'strong', d: strongPlain, score: 60 },
  ];
  const ordered = ranking.sortRows(rows, { sort: 'relevance' });
  assert.equal(ordered[0].id, 'strong',
    'verification must not outweigh quality and engagement at equal relevance');
});

test('Ranking — pagination is stable across identical scores', () => {
  ranking.setRankingConfig(adsConfig.DEFAULTS);
  const rows = [
    { id: 'b', d: { createdAt: '2026-01-01', price: 1 }, score: 10 },
    { id: 'a', d: { createdAt: '2026-01-01', price: 1 }, score: 10 },
  ];
  const first = ranking.sortRows(rows, { sort: 'relevance' }).map((r) => r.id);
  const second = ranking.sortRows([...rows].reverse(), { sort: 'relevance' }).map((r) => r.id);
  assert.deepEqual(first, second, 'tie-break must not depend on input order');
});

test('Ad config — coercion clamps and falls back safely', () => {
  const coerced = adsConfig.coerce({
    adsEnabled: 'yes',
    searchVerifiedBoost: 99,
    maxSearchVerifiedBoost: 0.1,
    disabledPlacements: 'not-a-list',
    frequency: { maxInterstitialsPerSession: -5, retryBackoffBaseMs: 'soon' },
  });

  assert.equal(coerced.adsEnabled, true, 'a non-boolean must not read as false');
  assert.ok(coerced.searchVerifiedBoost <= coerced.maxSearchVerifiedBoost);
  assert.equal(coerced.frequency.maxInterstitialsPerSession, 0,
    'a negative cap must clamp to 0, not fall back to the default');
  assert.equal(coerced.frequency.retryBackoffBaseMs, adsConfig.DEFAULTS.frequency.retryBackoffBaseMs);
  assert.deepEqual(coerced.disabledPlacements, []);
});

test('Ad config — defaults are safe: ads on, exemption on, boost bounded', () => {
  assert.equal(adsConfig.DEFAULTS.adsEnabled, true);
  assert.equal(adsConfig.DEFAULTS.adsExemptBlueTickEnabled, true);
  assert.ok(adsConfig.DEFAULTS.searchVerifiedBoost > 0);
  assert.ok(adsConfig.DEFAULTS.searchVerifiedBoost <= adsConfig.DEFAULTS.maxSearchVerifiedBoost);
  assert.equal(adsConfig.DEFAULTS.allowBoostToOutrankRelevance, false);
  assert.ok(adsConfig.DEFAULTS.frequency.maxInterstitialsPerSession > 0);
  assert.ok(adsConfig.DEFAULTS.frequency.minTimeAfterLaunchMs > 0,
    'an interstitial must never be allowed straight after launch');
});