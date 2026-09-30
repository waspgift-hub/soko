// Prod capacity test: BACKEND (api.sokovibe.co.tz -> Cloudflare Worker -> Render -> Firestore).
// Read-only catalog/search paths. Excludes /auth/send-otp (bills real SMS).
// Run: k6 run k6/prod-backend.js -e BASE_URL=https://api.sokovibe.co.tz
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL || 'https://api.sokovibe.co.tz';

const KEYWORDS = ['phone', 'samsung', 'nguo', 'kofia', 'begi', 'sapatu', 'dress', 'shoes', 'vitanda'];

const jsonHeaders = () => ({ 'Content-Type': 'application/json' });

export const options = {
  scenarios: {
    ramp_ceiling: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 500 },
        { duration: '30s', target: 2000 },
        { duration: '45s', target: 5000 },
        { duration: '45s', target: 8000 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    // 429 = legal per-IP limiting / CF protection, NOT a server failure.
    http_req_failed: ['rate<0.10'],
    http_req_duration: ['p(95)<4000'],
  },
};

export default function () {
  const pick = Math.random();
  let resp;
  let name;

  if (pick < 0.40) {
    name = 'products';
    resp = http.get(`${BASE}/api/v1/products?limit=10`, { tags: { name } });
  } else if (pick < 0.65) {
    name = 'search_products';
    const q = KEYWORDS[Math.floor(Math.random() * KEYWORDS.length)];
    resp = http.get(`${BASE}/api/v1/search/products?q=${encodeURIComponent(q)}&limit=10`, { tags: { name } });
  } else if (pick < 0.80) {
    name = 'trending';
    resp = http.post(`${BASE}/api/search/trending`, '{}', { headers: jsonHeaders(), tags: { name } });
  } else if (pick < 0.90) {
    name = 'most_rated';
    resp = http.post(`${BASE}/api/search/most-rated`, '{}', { headers: jsonHeaders(), tags: { name } });
  } else {
    name = 'categories';
    resp = http.get(`${BASE}/api/v1/products/categories`, { tags: { name } });
  }

  check(resp, { [`${name} 200`]: (r) => r.status === 200 });
}