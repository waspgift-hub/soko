// Prod capacity test: FRONTEND marketing site (www.sokovibe.co.tz -> Cloudflare -> Render).
// Simulates a visitor loading a landing page + its shared css/js assets.
// Run: k6 run k6/prod-frontend.js -e BASE_URL=https://www.sokovibe.co.tz
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL || 'https://www.sokovibe.co.tz';

const PAGES = [
  '/',
  '/tanzania-marketplace',
  '/categories',
  '/how-soko-vibe-works',
  '/soko-vibe-fees',
  '/soko-vibe-escrow',
  '/about',
  '/about/founder',
  '/privacy-policy',
  '/terms-of-service',
  '/support',
];

const CSS = ['/waitlist.css', '/styles.css', '/premium.css'];
const JS = ['/waitlist.js', '/i18n.js'];

export const options = {
  scenarios: {
    ramp_visitors: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 200 },
        { duration: '30s', target: 500 },
        { duration: '30s', target: 1000 },
        { duration: '30s', target: 2000 },
        { duration: '30s', target: 0 },
      ],
      gracefulRampDown: '30s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.10'],
    http_req_duration: ['p(95)<3000'],
  },
};

export default function () {
  const page = PAGES[Math.floor(Math.random() * PAGES.length)];
  const css = CSS[Math.floor(Math.random() * CSS.length)];
  const js = JS[Math.floor(Math.random() * JS.length)];

  const pageResp = http.get(`${BASE}${page}`, { tags: { name: 'page' } });
  check(pageResp, { 'page 200': (r) => r.status === 200 });

  const cssResp = http.get(`${BASE}${css}`, { tags: { name: 'css' } });
  check(cssResp, { 'css 200': (r) => r.status === 200 });

  const jsResp = http.get(`${BASE}${js}`, { tags: { name: 'js' } });
  check(jsResp, { 'js 200': (r) => r.status === 200 });
}