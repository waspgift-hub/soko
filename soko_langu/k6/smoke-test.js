'use strict';

// Smoke test — validates every endpoint path is wired and healthy.
// Run in VS Code via the k6 extension (Run Test) or from CLI:
//   k6 run k6/smoke-test.js -e BASE_URL=http://localhost:3000 -e ADMIN_SECRET=...
// Note: the public POST is rate-limited to 5/hour/IP, so this test creates
// at most one real request document per run (plus admin-status audit rows).

import http from 'k6/http';
import { check } from 'k6';
import { Trend } from 'k6/metrics';

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    checks: ['rate >= 1'],
  },
};

const BASE = __ENV.BASE_URL || 'http://localhost:3000';
const ADMIN_SECRET = __ENV.ADMIN_SECRET || '';

// k6 v2 mutates a shared headers object across requests (drops Content-Type),
// so build a fresh map for every call.
function jsonHeaders(withAdmin = false) {
  const h = { 'Content-Type': 'application/json' };
  if (withAdmin) h['x-admin-secret'] = ADMIN_SECRET;
  return h;
}

// 201 is BOTH the frozen honeypot ack and the create-success response;
// 400/404/429 are expected client-side outcomes, not failures.
http.expectedStatuses(200, 201, 400, 404, 429);

const pageTrend = new Trend('page_fetch_ms', true);

export default function () {
  const health = http.get(`${BASE}/health`);
  check(health, {
    'health is 200 and ok': (r) => r.status === 200 && JSON.parse(r.body).status === 'ok',
  });

  const t0 = Date.now();
  const page = http.get(`${BASE}/data-deletion`);
  pageTrend.add(Date.now() - t0);
  check(page, {
    'form page 200': (r) => r.status === 200,
    'form page renders form': (r) => r.body.includes('deletionForm') && r.body.includes('del_submit'),
  });

  const sitemap = http.get(`${BASE}/sitemap.xml`);
  check(sitemap, {
    'sitemap 200 + contains /data-deletion': (r) => r.status === 200 && r.body.includes('/data-deletion'),
  });

  // Honeypot request (website field filled by bots) — acked 201, never saved.
  const hp = http.post(`${BASE}/api/v1/data-deletion/requests`,
    JSON.stringify({ website: 'http://spam.example' }), { headers: jsonHeaders() });
  check(hp, {
    'honeypot acked': (r) => r.status === 201 && r.json().success === true,
  });

  // Validation: garbage email never reaches the store.
  const bad = http.post(`${BASE}/api/v1/data-deletion/requests`,
    JSON.stringify({ email: 'not-an-email' }), { headers: jsonHeaders() });
  check(bad, {
    'invalid email rejected 400': (r) => r.status === 400 && r.json().code === 'VALIDATION_ERROR',
  });

  // Happy path — creates the one request document this smoke run persists.
  const created = http.post(`${BASE}/api/v1/data-deletion/requests`,
    JSON.stringify({
      fullName: 'Smoke Test User',
      email: 'smoke@example.com',
      phone: '+255700000000',
      reason: 'k6 smoke test',
    }), { headers: jsonHeaders() });
  const createdOk = created.status === 201 && created.json().success === true && !!created.json().requestId;
  check(created, { 'create request 201 + id': () => createdOk });

  const adminList = http.get(`${BASE}/api/v1/admin/data-deletion-requests`, { headers: jsonHeaders(true) });
  check(adminList, {
    'admin list auth-gated': (r) => r.status !== 401 && r.status !== 403,
    'admin list 200': (r) => r.status === 200,
    'admin list contains created': (r) => r.status === 200 && r.json().success === true
      && r.json().data.items.some((i) => i.id === created.json().requestId),
  });

  if (createdOk) {
    const put = http.put(`${BASE}/api/v1/admin/data-deletion-requests/${created.json().requestId}/status`,
      JSON.stringify({ status: 'in_progress', note: 'k6 smoke' }), { headers: jsonHeaders(true) });
    check(put, {
      'admin status change 200': (r) => r.status === 200 && r.json().data.status === 'in_progress',
    });
  }

  const miss = http.put(`${BASE}/api/v1/admin/data-deletion-requests/nope/status`,
    JSON.stringify({ status: 'resolved' }), { headers: jsonHeaders(true) });
  check(miss, {
    'unknown id 404': (r) => r.status === 404,
  });
}