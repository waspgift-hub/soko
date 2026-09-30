// Origin calibration v2: Mix=core (products+categories only) or full (search heavy).
// Run: k6 run k6/prod-origin-cal.js -e VU=300 -e D=45s -e MIX=core
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL || 'https://soko-langu-server.onrender.com';
const VU = Number(__ENV.VU || 300);
const DUR = __ENV.D || '45s';
const MIX = __ENV.MIX || 'full';

const KEYWORDS = ['phone', 'samsung', 'nguo', 'kofia', 'begi', 'sapatu', 'dress', 'shoes', 'vitanda'];

export const options = {
  scenarios: {
    plateau: { executor: 'constant-vus', vus: VU, duration: DUR },
  },
  thresholds: {},
};

export default function () {
  const headers = {
    'Content-Type': 'application/json',
    'X-Forwarded-For': `10.${__VU % 250}.${(__VU / 250) % 250}.${__VU % 250}`,
  };
  const pick = Math.random();
  let resp;
  let name;

  if (MIX === 'core') {
    name = pick < 0.7 ? 'products' : 'categories';
    resp = name === 'products'
      ? http.get(`${BASE}/api/v1/products?limit=10`, { headers, tags: { name } })
      : http.get(`${BASE}/api/v1/products/categories`, { headers, tags: { name } });
  } else if (pick < 0.40) {
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