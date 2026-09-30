'use strict';

// Read-path ceiling probe: finds the VU level where the landing page starts
// to degrade (latency blow-up or errors). No write path, so nothing is
// persisted to Firestore.
//   k6 run k6/capacity-push.js -e BASE_URL=http://localhost:3000

import http from 'k6/http';

const BASE = __ENV.BASE_URL || 'http://localhost:3000';

export const options = {
  scenarios: {
    ramp: {
      executor: 'ramping-vus',
      startVUs: 1,
      stages: [
        { duration: '15s', target: 150 },
        { duration: '20s', target: 150 },
        { duration: '15s', target: 300 },
        { duration: '20s', target: 300 },
        { duration: '15s', target: 500 },
        { duration: '20s', target: 500 },
        { duration: '10s', target: 0 },
      ],
      gracefulRampDown: '10s',
    },
  },
  thresholds: {
    'http_req_failed': ['rate < 0.01'],
    'http_req_duration': ['p(95) < 1500'],
  },
};

export default function () {
  http.get(`${BASE}/data-deletion`);
}