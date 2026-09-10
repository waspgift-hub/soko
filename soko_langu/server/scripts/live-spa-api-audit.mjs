import { performance } from 'node:perf_hooks';

// Live API-surface audit for the /shop SPA: every /api path referenced by
// parity.js + app.js must RESOLVE on the deployed server (exist as a route).
// A route exists even when it answers 400/401/403; only a generic 4xx route
// miss ("Not found" / "Cannot POST") counts as MISSING.
//
// Usage: node scripts/live-spa-api-audit.mjs [BASE_URL]

const BASE = process.argv[2] || 'https://soko-langu-server.onrender.com';

const probes = [
  ['GET',  '/api/orders/guest/list'],
  ['GET',  '/api/kyc/status/e2e-probe-user'],
  ['GET',  '/api/orders/e2e-probe-order/status'],
  ['GET',  '/api/v1/orders?limit=200'],
  ['GET',  '/api/v1/orders/e2e-probe-order'],
  ['POST', '/api/search/trending'],
  ['POST', '/api/search/most-rated'],
  ['POST', '/api/search/autocomplete'],
  ['POST', '/api/search/global-search'],
  ['POST', '/api/search/record-click'],
  ['POST', '/api/boost-product'],
  ['POST', '/api/chat/send'],
  ['POST', '/api/cloudinary/sign'],
  ['POST', '/api/create-marketplace-payment-link'],
  ['POST', '/api/flash-sale/create'],
  ['POST', '/api/flash-sales/delete'],
  ['POST', '/api/kyc/submit'],
  ['POST', '/api/notifications/preferences/get'],
  ['POST', '/api/notifications/preferences/set'],
  ['POST', '/api/orders/create'],
  ['POST', '/api/payouts/seller/withdraw'],
  ['POST', '/api/v1/auth/phone-login'],
  ['POST', '/api/v1/auth/send-otp'],
];

const GENERIC = /Not found|Cannot (GET|POST|PUT|DELETE)/;

function classify(status, body) {
  if (status === 404 && GENERIC.test(body)) return 'MISSING';
  if (status === 500) return 'WARN';
  return 'OK';
}

function short(body) {
  const s = String(body).replace(/\s+/g, ' ').trim();
  return s.length > 90 ? s.slice(0, 90) + '…' : s;
}

let pass = 0, miss = 0, warn = 0;
console.log(`\n=== SPA API-SURFACE AUDIT — ${BASE} ===\n`);
for (const [method, path] of probes) {
  let res;
  try {
    res = await fetch(BASE + path, { method, headers: { 'Content-Type': 'application/json' }, body: method === 'GET' ? undefined : '{}' });
  } catch (e) {
    console.log(`  ! ${method} ${path} — NETWORK ${e.message}`);
    warn++;
    continue;
  }
  const text = await res.text();
  const verdict = classify(res.status, text);
  if (verdict === 'MISSING') miss++;
  else if (verdict === 'WARN') warn++;
  else if (verdict === 'OK') pass++;
  console.log(`  ${verdict === 'OK' ? '✔' : verdict === 'MISSING' ? '✖' : '!'} ${res.status} ${method.padEnd(4)} ${path} — ${short(text)}`);
  await new Promise((r) => setTimeout(r, 1400)); // stay inside the 60/min rate limiter
}

console.log(`\n=== RESULT: ${pass} OK, ${warn} warn, ${miss} missing ===\n`);
process.exitCode = miss ? 1 : 0;