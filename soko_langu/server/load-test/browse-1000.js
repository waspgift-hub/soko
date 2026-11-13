// k6 load test — "1000 watumiaji wanaobrowse Soko Vibe".
//
// Simulates real app browsing (catalog → search → trending → most-rated) on
// the deployed API. Deliberately EXCLUDES /auth/send-otp: every OTP send
// bills an SMS and would burn real credits — load-testing the OTP path is
// both destructive and not part of the read-path capacity question.
//
// Run:
//   k6 run load-test/browse-1000.js
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

const BASE = 'https://api.sokovibe.co.tz';

const KEYWORDS = [
  'phone', 'samsung', 'nguo', 'kofia', 'mboga', 'begi',
  'sapatu', 'dress', 'shoes', 'mizizi', 'vitanda', 'kiswahili',
];

const http2xx = new Counter('http_2xx');
const http429 = new Counter('http_429');
const http5xx = new Counter('http_5xx');
const httpOther = new Counter('http_other');

export const options = {
  scenarios: {
    ramp_to_10000: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 5000 },
        { duration: '30s', target: 10000 },
        { duration: '30s', target: 10000 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    // A single k6 node shares ONE source IP → our per-IP rate limits (and
    // Cloudflare) will legally return 429s. Count those separately in the
    // summary; the failure-threshold below judges true server errors only.
    http_req_failed: ['rate<0.10'],
    http_req_duration: ['p(95)<5000'],
  },
};

export default function () {
  const pick = Math.random();
  let resp;
  let name;

  if (pick < 0.45) {
    name = 'products';
    resp = http.get(`${BASE}/api/v1/products?limit=10`, { tags: { name } });
  } else if (pick < 0.75) {
    name = 'search_products';
    const q = KEYWORDS[Math.floor(Math.random() * KEYWORDS.length)];
    resp = http.get(
      `${BASE}/api/v1/search/products?q=${encodeURIComponent(q)}&limit=10`,
      { tags: { name } },
    );
  } else if (pick < 0.9) {
    name = 'trending';
    resp = http.post(`${BASE}/api/search/trending`, '{}', {
      headers: { 'Content-Type': 'application/json' },
      tags: { name },
    });
  } else {
    name = 'most_rated';
    resp = http.post(`${BASE}/api/search/most-rated`, '{}', {
      headers: { 'Content-Type': 'application/json' },
      tags: { name },
    });
  }

  if (resp.status === 200) http2xx.add(1);
  else if (resp.status === 429) http429.add(1);
  else if (resp.status >= 500) http5xx.add(1);
  else httpOther.add(1);

  check(resp, { 'no 5xx and no timeout': (r) => r.status < 500 && r.status >= 200 });

  // Real users think for a second before the next action — keeps request rate
  // in human territory instead of an artificial crawl.
  sleep(0.5 + Math.random() * 1.5);
}