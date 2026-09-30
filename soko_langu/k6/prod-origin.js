// Prod capacity test: Render ORIGIN directly (bypasses Cloudflare edge + its
// shared-IP rate limiting). Each VU sends a unique X-Forwarded-For so the
// origin's per-IP limiter treats it as its own user. Measures the true backend
// ceiling (Render + Firestore), which is the actual bottleneck.
// Run: k6 run k6/prod-origin.js
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL || 'https://soko-langu-server.onrender.com';

const KEYWORDS = ['phone', 'samsung', 'nguo', 'kofia', 'begi', 'sapatu', 'dress', 'shoes', 'vitanda'];
const jsonHeaders = () => ({ 'Content-Type': 'application/json' });

export const options = {
  scenarios: {
    ramp_origin: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 300 },
        { duration: '30s', target: 1000 },
        { duration: '45s', target: 2500 },
        { duration: '45s', target: 5000 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.10'],
    http_req_duration: ['p(95)<4000'],
  },
};

export default function () {
  const headers = {
    'Content-Type': 'application/json',
    'X-Forwarded-For': `10.${__VU % 250}.${(__VU / 250) % 250}.${__VU % 250}`,
  };
  const pick = Math.random();
  let resp;
  let name;

  if (pick < 0.40) {
    name = 'products';
    resp = http.get(`${BASE}/api/v1/products?limit=10`, { headers, tags: { name } });
  } else if (pick < 0.65) {
    name = 'search_products';
    const q = KEYWORDS[Math.floor(Math.random() * KEYWORDS.length)];
    resp = http.get(`${BASE}/api/v1/search/products?q=${encodeURIComponent(q)}&limit=10`, { headers, tags: { name } });
  } else if (pick < 0.80) {
    name = 'trending';
    resp = http.post(`${BASE}/api/search/trending`, '{}', { headers, tags: { name } });
  } else if (pick < 0.90) {
    name = 'most_rated';
    resp = http.post(`${BASE}/api/search/most-rated`, '{}', { headers, tags: { name } });
  } else {
    name = 'categories';
    resp = http.get(`${BASE}/api/v1/products/categories`, { headers, tags: { name } });
  }

  check(resp, { [`${name} 200`]: (r) => r.status === 200 });
}