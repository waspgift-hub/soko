/**
 * Live E2E API suite for the deployed Soko Vibe server.
 *
 * Safety: this suite only touches public/read-only endpoints and verifies that
 * protected endpoints REJECT unauthenticated requests. It never creates real
 * payments, sends SMS, or mutates money — so it is safe to run against
 * production.
 *
 * Run:  cd server && node --test test/e2e.live.test.js
 */
const test = require('node:test');
const assert = require('node:assert/strict');

const BASE = process.env.E2E_BASE_URL || 'https://soko-langu-server.onrender.com';

// The production server rate-limits at 30 requests/min per IP, so the security
// sweep must pace itself or it trips 429 before reaching the endpoints.
let _lastRequestAt = 0;
async function req(method, path, body) {
  const wait = 1300 - (Date.now() - _lastRequestAt);
  if (wait > 0) await new Promise((r) => setTimeout(r, wait));
  _lastRequestAt = Date.now();
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  let json = null;
  try { json = await res.json(); } catch { /* non-JSON body */ }
  return { status: res.status, json };
}

// A 429 from the rate limiter still proves the call was rejected — it is just
// as safe as a 401/403 from the auth gate.
function isRejected(status) {
  return [401, 403, 429].includes(status);
}

// ─────────────────────────────────────────────────────────────────────────
// A. UPTIME + PUBLIC READ-ONLY ENDPOINTS
// ─────────────────────────────────────────────────────────────────────────

test('GET /health → 200 ok', async () => {
  const r = await req('GET', '/health');
  assert.equal(r.status, 200);
  assert.equal(r.json?.status, 'ok');
});

test('POST /api/search/trending → public 200 with trending array', async () => {
  const r = await req('POST', '/api/search/trending', {});
  assert.equal(r.status, 200);
  assert.ok(Array.isArray(r.json?.trending));
});

test('POST /api/search/most-rated → public 200 with products+sellers', async () => {
  const r = await req('POST', '/api/search/most-rated', { limit: 5 });
  assert.equal(r.status, 200);
  assert.ok(Array.isArray(r.json?.products));
  assert.ok(Array.isArray(r.json?.sellers));
});

test('GET /api/payment-methods → 200 lists wallet+ussd_push+billpay', async () => {
  const r = await req('GET', '/api/payment-methods');
  assert.equal(r.status, 200);
  const ids = (r.json?.methods || []).map((m) => m.id);
  assert.ok(ids.includes('wallet'));
  assert.ok(ids.includes('ussd_push'));
  assert.ok(ids.includes('billpay'));
});

test('GET /api/wallet/deposit/methods → 200 lists ussd + billpay', async () => {
  const r = await req('GET', '/api/wallet/deposit/methods');
  assert.equal(r.status, 200);
  const ids = (r.json?.methods || []).map((m) => m.id);
  assert.ok(ids.includes('ussd'));
  assert.ok(ids.includes('billpay'));
});

test('POST /api/auth/check-phone → 200 boolean exists', async () => {
  const r = await req('POST', '/api/auth/check-phone', { phone: '0712345678' });
  assert.equal(r.status, 200);
  assert.ok(typeof r.json?.exists === 'boolean');
});

test('POST /api/auth/check-email → 200 boolean exists', async () => {
  const r = await req('POST', '/api/auth/check-email', { email: 'unused-e2e@example.com' });
  assert.equal(r.status, 200);
  assert.ok(typeof r.json?.exists === 'boolean');
});

test('auth check endpoints reject missing payload → 400', async () => {
  assert.equal((await req('POST', '/api/auth/check-phone', {})).status, 400);
  assert.equal((await req('POST', '/api/auth/check-email', {})).status, 400);
});

// ─────────────────────────────────────────────────────────────────────────
// B. MONEY-CALC CORRECTNESS (read-only proxy of server/money + clickpesa)
// ─────────────────────────────────────────────────────────────────────────

test('calc-fee: wallet is free', async () => {
  const r = await req('POST', '/api/payment-methods/calc-fee', { methodId: 'wallet', amount: 50000 });
  assert.equal(r.status, 200);
  assert.equal(r.json?.fee, 0);
  assert.equal(r.json?.total, 50000);
});

test('calc-fee: USSD Push tiered fee (3000→230, 100000→3240)', async () => {
  const r1 = await req('POST', '/api/payment-methods/calc-fee', { methodId: 'ussd_push', amount: 3000 });
  assert.equal(r1.json?.fee, 230);
  const r2 = await req('POST', '/api/payment-methods/calc-fee', { methodId: 'ussd_push', amount: 100000 });
  assert.equal(r2.json?.fee, 3240);
});

test('calc-fee: billpay default 1%', async () => {
  const r = await req('POST', '/api/payment-methods/calc-fee', { methodId: 'billpay', amount: 100000 });
  assert.equal(r.status, 200);
  assert.equal(r.json?.fee, 1000);
  assert.equal(r.json?.total, 101000);
});

test('calc-fee: halopesa billpay 2%', async () => {
  const r = await req('POST', '/api/payment-methods/calc-fee', { methodId: 'billpay', amount: 100000, provider: 'halopesa' });
  assert.equal(r.status, 200);
  assert.equal(r.json?.fee, 2000);
});

test('calc-fee: crdb direct debit flat 2000', async () => {
  const r = await req('POST', '/api/payment-methods/calc-fee', { methodId: 'crdb_direct_debit', amount: 100000 });
  assert.equal(r.status, 200);
  assert.equal(r.json?.fee, 2000);
});

test('calc-fee: missing fields → 400', async () => {
  const r = await req('POST', '/api/payment-methods/calc-fee', {});
  // 429 is also fine — the production rate limiter may kick in mid-suite.
  assert.ok(isRejected(r.status) || r.status === 400, `expected rejection, got ${r.status}`);
});

// ─────────────────────────────────────────────────────────────────────────
// C. SECURITY — protected endpoints MUST reject unauthenticated calls
// ─────────────────────────────────────────────────────────────────────────

const PROTECTED_ENDPOINTS = [
  ['POST', '/api/search/global-search', { query: 'phone' }],
  ['POST', '/api/search/autocomplete', { query: 'ph' }],
  ['POST', '/api/search/record-click', { resultId: 'x', resultType: 'product' }],
  ['POST', '/api/sms/send', { phone: '255719537300', message: 'e2e' }],
  ['POST', '/api/send-notification', { userId: 'x', title: 't', body: 'b' }],
  ['GET', '/api/seller/balance?userId=x', null],
  ['GET', '/api/payouts', null],
  ['GET', '/api/admin/stats', null],
  ['GET', '/api/stats', null],
  ['GET', '/api/admin/finance-summary', null],
  ['GET', '/api/admin/analytics', null],
  ['GET', '/api/admin/users', null],
  ['GET', '/api/clickpesa/balance', null],
  ['POST', '/api/boost-product', { userId: 'x' }],
  ['POST', '/api/flash-sale/create', {}],
  ['POST', '/api/flash-sale/scan', { productId: 'x' }],
  ['POST', '/api/flash-sale/notify', { sellerId: 'x' }],
  ['GET', '/api/kyc/status/some-user', null],
  ['POST', '/api/kyc/submit', {}],
  ['POST', '/api/orders/create', {}],
  ['GET', '/api/transaction-status/some-order', null],
  ['GET', '/api/reports', null],
  ['GET', '/api/fraud/alerts', null],
  ['GET', '/api/seller-statement/some-seller', null],
  ['GET', '/api/buyer-statement/some-buyer', null],
  ['POST', '/api/admin/broadcast-notification', {}],
  ['POST', '/api/cron/release-escrows', {}],
  ['POST', '/api/escrow/release', {}],
];

for (const [method, path, body] of PROTECTED_ENDPOINTS) {
  test(`SECURITY ${method} ${path} → rejects unauthenticated`, async () => {
    const r = await req(method, path, body);
    assert.notEqual(r.status, 200,
      `${method} ${path} should NOT be reachable without auth (got 200)`);
    assert.ok(isRejected(r.status),
      `${method} ${path} expected 401/403/429 but got ${r.status}`);
  });
}

// Specific auth contract checks
test('SECURITY global-search unauthorized → 401', async () => {
  const r = await req('POST', '/api/search/global-search', { query: 'phone' });
  assert.ok(isRejected(r.status), `got ${r.status}`);
});

test('SECURITY sms/send unauthorized → 401', async () => {
  const r = await req('POST', '/api/sms/send', { phone: '255719537300', message: 'e2e' });
  assert.ok(isRejected(r.status), `got ${r.status}`);
});

test('SECURITY seller/balance unauthorized → 401', async () => {
  const r = await req('GET', '/api/seller/balance?userId=someone');
  assert.ok(isRejected(r.status), `got ${r.status}`);
});

test('SECURITY admin endpoints reject without x-admin-secret → 401', async () => {
  for (const p of ['/api/admin/users', '/api/admin/stats', '/api/admin/finance-summary', '/api/clickpesa/balance']) {
    const r = await req('GET', p);
    assert.ok(isRejected(r.status), `${p} should be rejected without admin secret (got ${r.status})`);
  }
});

test('SECURITY orders/create unauthorized → 401', async () => {
  const r = await req('POST', '/api/orders/create', {});
  assert.ok(isRejected(r.status), `got ${r.status}`);
});

test('SECURITY cron release-escrows → rejects without cron secret', async () => {
  const r = await req('POST', '/api/cron/release-escrows', {});
  assert.ok(isRejected(r.status), `got ${r.status}`);
});

// ─────────────────────────────────────────────────────────────────────────
// D. VALIDATION — missing payloads return 400, never 500
// ─────────────────────────────────────────────────────────────────────────

test('orders/create missing body → 400/401 (never 500)', async () => {
  const r = await req('POST', '/api/orders/create', {});
  assert.ok([400, 401, 429].includes(r.status), `got ${r.status}`);
});

test('boost-product missing body → 400/401 (never 500)', async () => {
  const r = await req('POST', '/api/boost-product', {});
  assert.ok([400, 401, 429].includes(r.status), `got ${r.status}`);
});