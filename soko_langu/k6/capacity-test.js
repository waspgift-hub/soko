'use strict';

// Capacity test — answers: how many requests/second can the app serve, and
// how many concurrent users can it sustain before latency/errors degrade?
//
// Two scenarios:
//   ramp       — pure read path (landing page), no think time. Ramps 1 -> 20
//                -> 50 -> 100 VUs to find the sustainable-RPS ceiling and the
//                concurrency level where p95 latency stays healthy.
//   submitters — realistic form submissions. Each VU gets its own simulated
//                IP (X-Forwarded-For; the app sets trust proxy and buckets the
//                anti-spam limiter per IP), so it behaves like a real user on
//                their own network: at most 5 submissions/hour/IP succeed.
//
// Run:
//   k6 run k6/capacity-test.js -e BASE_URL=http://localhost:3000
// NOTE: submitters write REAL documents to Firestore — clean them up after.

import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:3000';

export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-vus',
      exec: 'readPage',
      startVUs: 1,
      stages: [
        { duration: '15s', target: 20 },
        { duration: '20s', target: 20 },
        { duration: '15s', target: 50 },
        { duration: '20s', target: 50 },
        { duration: '15s', target: 100 },
        { duration: '20s', target: 100 },
        { duration: '10s', target: 0 },
      ],
      gracefulRampDown: '5s',
    },
    submitters: {
      executor: 'constant-vus',
      exec: 'submitForm',
      vus: 8,
      duration: '95s',
      startTime: '15s',
      gracefulStop: '5s',
    },
  },
  thresholds: {
    'http_req_failed{scenario:ramp}': ['rate < 0.01'], // capacity ceiling = errors must stay ~0
    'http_req_duration{scenario:ramp}': ['p(95) < 1500', 'p(99) < 3000'],
    'http_req_duration{scenario:submitters}': ['p(95) < 3000', 'p(99) < 5000'],
    checks: ['rate > 0.99'],
  },
};

// One simulated public IP per VU so real (per-user) anti-spam buckets apply.
function myIp() {
  return `41.57.${(__VU % 250) < 1 ? 1 : __VU % 250}.${(__VU % 250)}`;
}

export function readPage() {
  http.get(`${BASE}/data-deletion`);
}

export function submitForm() {
  const r = http.post(
    `${BASE}/api/v1/data-deletion/requests`,
    JSON.stringify({
      fullName: `Capacity User ${__VU}`,
      email: `cap${__VU}.${Date.now()}@example.com`,
      phone: '+255700000000',
      reason: 'k6 capacity test',
    }),
    {
      headers: {
        'Content-Type': 'application/json',
        'X-Forwarded-For': myIp(),
      },
    }
  );
  check(r, {
    'submit 201 or 429 (per-user limit works)': (res) => res.status === 201 || res.status === 429,
    'submit never 5xx': (res) => res.status < 500,
  });
  sleep(1);
}