// Prod frontend calibration: fixed visitors plateau, page + one asset.
// Run: k6 run k6/prod-frontend-cal.js -e VU=100 -e D=35s
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL || 'https://www.sokovibe.co.tz';
const VU = Number(__ENV.VU || 100);
const DUR = __ENV.D || '35s';

const PAGES = ['/', '/tanzania-marketplace', '/categories', '/how-soko-vibe-works', '/privacy-policy', '/terms-of-service', '/support'];
const CSS = ['/waitlist.css', '/styles.css', '/premium.css'];
const JS = ['/waitlist.js', '/i18n.js'];

export const options = {
  scenarios: { visitors: { executor: 'constant-vus', vus: VU, duration: DUR } },
  thresholds: {},
};

export default function () {
  const page = PAGES[Math.floor(Math.random() * PAGES.length)];
  const css = CSS[Math.floor(Math.random() * CSS.length)];
  const js = JS[Math.floor(Math.random() * JS.length)];
  const p = http.get(`${BASE}${page}`, { tags: { name: 'page' } });
  check(p, { 'page': (r) => r.status === 200 });
  const c = http.get(`${BASE}${css}`, { tags: { name: 'css' } });
  const j = http.get(`${BASE}${js}`, { tags: { name: 'js' } });
  check(c, { 'css': (r) => r.status === 200 });
  check(j, { 'js': (r) => r.status === 200 });
}