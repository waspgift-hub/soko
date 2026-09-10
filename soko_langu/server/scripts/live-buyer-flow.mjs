import { randomUUID } from 'node:crypto';

// Live no-payment E2E driver for the deployed Soko Vibe server.
// Covers: fresh buyer sign-up -> order create (v2 PG order AWAITING_ESCROW_PAYMENT)
//         -> legacy-shop status mirror -> /api/v1 order status -> cancel.
// Deliberately does NOT initiate a ClickPesa USSD payment (no real money).
//
// Usage:  node scripts/live-buyer-flow.mjs [BASE_URL]
// Usage:  node scripts/live-buyer-flow.mjs https://soko-langu-server.onrender.com

const BASE = process.argv[2] || 'https://soko-langu-server.onrender.com';
const FIREBASE_API_KEY = 'AIzaSyBrh5W9VwbC3qTtSTm8LJbTQeYufRGil5s';
const FIREBASE_BAAS = 'https://identitytoolkit.googleapis.com/v1';

let pass = 0;
let fail = 0;
function check(name, cond, extra) {
  if (cond) { pass++; console.log(`  ✔ ${name}${extra ? ' — ' + extra : ''}`); }
  else { fail++; console.log(`  ✖ ${name}${extra ? ' — ' + extra : ''}`); }
}

async function api(path, { method = 'GET', token, body, retries = 0 } = {}) {
  for (let attempt = 0; ; attempt++) {
    const headers = { 'Content-Type': 'application/json' };
    if (token) headers.Authorization = 'Bearer ' + token;
    const res = await fetch(BASE + path, {
      method,
      headers,
      ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
    });
    let json = {};
    try { json = await res.json(); } catch (_) {}
    if ((res.status === 502 || res.status === 504) && attempt < retries) {
      await new Promise((r) => setTimeout(r, 6000));
      continue;
    }
    return { status: res.status, json };
  }
}

async function main() {
  const email = `buyer.e2e.${Date.now()}@sokovibe-e2e.test`;
  const password = 'SokoVibeE2E!' + randomUUID().slice(0, 6);

  console.log(`\n=== LIVE NO-PAYMENT BUYER E2E — ${BASE} ===\n`);

  // 1. Fresh Firebase buyer (REST sign-up)
  let token;
  let uid;
  try {
    const res = await fetch(`${FIREBASE_BAAS}/accounts:signUp?key=${FIREBASE_API_KEY}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    });
    const j = await res.json();
    token = j.idToken;
    uid = j.localId;
    check('buyer sign-up -> idToken + uid', !!(token && uid), email.slice(0, 24) + '…');
  } catch (e) {
    check('buyer sign-up', false, e.message);
    process.exitCode = 1;
    return;
  }

  const health = await api('/health', { retries: 3 });
  check('GET /health 200 ok', health.status === 200 && health.json.status === 'ok', 'status=' + health.json.status);

  // Warm the instance (Render cold starts + first-request DB pool wake-up)
  await api('/api/payment-methods', { retries: 2 });

  // 2. Pick a real product from the public catalog
  const most = await api('/api/search/most-rated', { method: 'POST', body: { limit: 5 } });
  const prods = (most.json && most.json.products) || [];
  check('POST /api/search/most-rated 200', most.status === 200, 'products=' + prods.length);
  if (!prods.length) {
    check('found a marketplace product', false, 'catalog empty');
    process.exitCode = 1;
    return;
  }
  // Public search payloads carry sellerName but not the Firestore sellerUid.
  // Use the canonical known seller from the test fixture ("soko vibe" store)
  // and pick its own product so the vendor relationship is real.
  const KNOWN_SELLER = { uid: 'gKZgi2GSxsgHgW6hUhr0p5l17YT2', name: 'soko vibe' };
  const mine = prods.find((x) => String(x.sellerName || '').toLowerCase() === KNOWN_SELLER.name) || prods[0];
  const p = { ...mine, sellerId: KNOWN_SELLER.uid, sellerName: KNOWN_SELLER.name };
  const price = Math.round(Number(p.price) || Number(p.productPrice) || 0);
  check('product has price + known seller', price > 0 && !!p.sellerId, p.displayName + ' · ' + KNOWN_SELLER.name);

  // 3. Buyer creates an order (legacy-shaped -> v2 PG order)
  const create = await api('/api/orders/create', {
    method: 'POST',
    token,
    retries: 4,
    body: {
      buyerId: uid,
      buyerName: 'E2E Buyer',
      buyerPhone: '+255700000000',
      sellerId: p.sellerId,
      sellerName: p.sellerName || 'Duka',
      productId: p.id,
      productName: p.displayName || p.name,
      productImage: p.image || ((p.images && p.images[0]) || ''),
      productPrice: price,
      quantity: 1,
      unitPrice: price,
      region: 'Dar es Salaam',
      district: 'Ilala',
      ward: 'Mchikichini',
      street: 'Kariakoo',
      deliveryType: 'local',
    },
  });
  const orderId = create.json && create.json.order && create.json.order.orderId;
  check('POST /api/orders/create 200 + orderId', create.status === 200 && !!orderId, 'order=' + (orderId || '').slice(0, 12) + '…');

  // 4. Legacy-shop status endpoint (also mirrors status to Firestore)
  const st1 = await api(`/api/orders/${orderId}/status`, { token });
  check('GET /api/orders/:id/status -> awaiting_escrow_payment (pending)', st1.status === 200 && st1.json.status === 'pending', `status=${st1.json.status}`);

  // 5. v2 order read-back
  const v1 = await api(`/api/v1/orders/${orderId}`, { token });
  const pgStatus = v1.json && v1.json.data && v1.json.data.status;
  check('GET /api/v1/orders/:id -> awaiting_escrow_payment', v1.status === 200 && pgStatus === 'awaiting_escrow_payment', `pg=${pgStatus}`);

  // 6. NOT initiating payment: no USSD, no money. Cancel instead (legal from AWAITING_ESCROW_PAYMENT).
  const cancel = await api(`/api/v1/orders/${orderId}/cancel`, {
    method: 'POST',
    token,
    body: { reason: 'E2E no-payment verification — not a real order' },
  });
  check('POST /api/v1/orders/:id/cancel 200', cancel.status === 200, 'status=' + cancel.status);

  // 7. Confirmed cancelled via both surfaces
  const st2 = await api(`/api/orders/${orderId}/status`, { token });
  check('GET /api/orders/:id/status -> cancelled', st2.status === 200 && st2.json.status === 'cancelled', `status=${st2.json.status}`);
  const v2 = await api(`/api/v1/orders/${orderId}`, { token });
  const v2s = v2.json && v2.json.data && v2.json.data.status;
  check('GET /api/v1/orders/:id -> cancelled', v2.status === 200 && v2s === 'cancelled', `pg=${v2s}`);

  // 8. Cross-user isolation: another random token must NOT read the order
  const res2 = await fetch(`${FIREBASE_BAAS}/accounts:signUp?key=${FIREBASE_API_KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: `bystander.${Date.now()}@sokovibe-e2e.test`, password: 'SokoVibeE2E!X912', returnSecureToken: true }),
  });
  const j2 = await res2.json();
  const stranger = await api(`/api/v1/orders/${orderId}`, { token: j2.idToken });
  check('cross-user isolation (403/404)', [403, 404, 401].includes(stranger.status), 'status=' + stranger.status);

  console.log(`\n=== RESULT: ${pass} pass, ${fail} fail ===\n`);
  process.exitCode = fail ? 1 : 0;
}

main().catch((e) => { console.error('DRIVER ERROR:', e); process.exitCode = 1; });