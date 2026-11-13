'use strict';

// Load test — mixed realistic workload against landing page, public form,
// and admin triage API.
// Run in VS Code (Run Test) or CLI:
//   k6 run k6/load-test.js -e BASE_URL=http://localhost:3000 -e ADMIN_SECRET=...
// The public create endpoint is intentionally anti-abuse capped at
// 5 req/hour/IP, so after the first few real requests the limiter returns
// 429. 429 is an expected outcome here (the limiter working), not a failure.

import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  scenarios: {
    // Heavy readers: the page + admin triage list.
    readers: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '20s', target: 15 },
        { duration: '40s', target: 15 },
        { duration: '10s', target: 0 },
      ],
      gracefulRampDown: '5s',
    },
    // Small trickle of genuine deletions that pass the rate limiter.
    submitters: {
      executor: 'constant-vus',
      vus: 2,
      duration: '70s',
      startTime: '10s',
    },
  },
  thresholds: {
    // Local tolerance — this test runs against a single dev machine where
    // k6 and the server share one CPU/network stack (no Redis; Firestore
    // round-trips included). Readers must stay under ~2s p95 with no 5xx.
    'http_req_failed{scenario:readers}': ['rate < 0.05'],
    'http_req_duration{scenario:readers}': ['p(95) < 2000'],
    // Submitters are intentionally rate-limited (429 = limiter working, not a
    // server failure), so tolerate a high 429 share while checks still assert
    // every response is a validate/create/limiter outcome, never a 5xx.
    'http_req_failed{scenario:submitters}': ['rate < 0.9'],
    'http_req_duration': ['p(95) < 2000', 'p(99) < 3000'],
    checks: ['rate > 0.95'],
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

http.expectedStatuses(200, 201, 400, 404, 429);

export default function () {
  if (__ENV.SCENARIO === 'submit' || Math.random() < 0.12) {
    const r = http.post(`${BASE}/api/v1/data-deletion/requests`,
      JSON.stringify({
        fullName: `Load ${__VU}`,
        email: `load${__VU}.${Date.now()}@example.com`,
        phone: `+25570000${String(__VU).padStart(4, '0')}`,
        reason: 'k6 load test',
      }), { headers: jsonHeaders() });
    check(r, {
      'submit 201 or 429': (res) => res.status === 201 || res.status === 429,
      'submit no server error': (res) => res.status !== 500 && res.status !== 502 && res.status !== 503,
    });
    return;
  }

  http.get(`${BASE}/data-deletion`);
  const list = http.get(
    `${BASE}/api/v1/admin/data-deletion-requests?status=new&limit=20`, { headers: jsonHeaders(true) });
  check(list, {
    'admin list 200': (r) => r.status === 200 && r.json().success === true,
  });

  sleep(Math.random() * 1.5);
}