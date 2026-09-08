#!/usr/bin/env node
'use strict';

/*
 * Soko Vibe SEO & domain health check.
 *
 * Usage:
 *   node scripts/seo-check.js            # against https://www.sokovibe.co.tz
 *   BASE_URL=http://localhost:3999 node scripts/seo-check.js
 *
 * Exits 0 when every required check passes, 1 otherwise.
 */

const BASE = process.env.BASE_URL || 'https://www.sokovibe.co.tz';

const results = [];

function check(name, ok, detail) {
  results.push({ name, ok: !!ok, detail: detail || '' });
}

async function request(path, opts = {}) {
  const res = await fetch(`${BASE}${path}`, {
    redirect: 'manual',
    headers: { Accept: 'text/html,application/xhtml+xml' },
    ...opts,
  });
  return { status: res.status, headers: res.headers, text: await res.text() };
}

function count(re, text) {
  const m = text.match(re);
  return m ? m.length : 0;
}

(async () => {
  let home;
  try {
    home = await request('/');
  } catch (e) {
    check('homepage reachable', false, `${BASE} -> ${e.message}`);
    print();
    return;
  }

  check('homepage HTTP 200', home.status === 200, `got ${home.status}`);
  const t = home.text;

  const titleMatch = t.match(/<title>([^<]*)<\/title>/);
  check('single <title>', count(/<title>/g, t) === 1, titleMatch && titleMatch[1]);
  check('title has brand', titleMatch && /Soko Vibe/.test(titleMatch[1]), titleMatch && titleMatch[1]);

  const canon = t.match(/<link[^>]+rel="canonical"[^>]+?href="([^"]+)"/);
  check('exactly one canonical', count(/rel="canonical"/g, t) === 1, canon && canon[1]);
  check('canonical = www host /', canon && canon[1] === 'https://www.sokovibe.co.tz/', canon && canon[1]);

  check('single meta description', count(/<meta\s+name="description"/g, t) === 1);
  check('meta description non-empty', /<meta\s+name="description"\s+content="[^"]+"/.test(t));

  const robotsMeta = t.match(/<meta\s+name="robots"\s+content="([^"]+)"/);
  check('home robots index,follow', robotsMeta && robotsMeta[1] === 'index, follow', robotsMeta && robotsMeta[1]);
  check('og:title present', /<meta\s+property="og:title"/.test(t));
  check('og:image present', /<meta\s+property="og:image"/.test(t));
  check('twitter:card present', /<meta\s+name="twitter:card"/.test(t));
  check('JSON-LD present', t.includes('application/ld+json'));
  check('WebSite schema', t.includes('"@type":"WebSite"'));

  check('HSTS header', (home.headers.get('strict-transport-security') || '').startsWith('max-age=31536000'));
  check('X-Content-Type-Options: nosniff', home.headers.get('x-content-type-options') === 'nosniff');
  check('Content-Security-Policy header', !!home.headers.get('content-security-policy'));
  check('Referrer-Policy header', !!home.headers.get('referrer-policy'));
  check('X-Frame-Options: DENY', home.headers.get('x-frame-options') === 'DENY');

  try {
    const login = await request('/login');
    const lm = login.text.match(/<meta\s+name="robots"\s+content="([^"]+)"/);
    check('login noindex, nofollow', lm && lm[1] === 'noindex, nofollow', lm && lm[1]);
  } catch (e) {
    check('login noindex, nofollow', false, e.message);
  }

  const missing = await request('/this-page-does-not-exist');
  check('unknown path returns 404', missing.status === 404, `got ${missing.status}`);

  const prod = await request('/product/seo-check-non-existent-product');
  check('missing product returns 404', prod.status === 404, `got ${prod.status}`);

  let robots;
  try {
    robots = await request('/robots.txt');
    check('robots.txt 200', robots.status === 200, `got ${robots.status}`);
    check('robots.txt Allow /', robots.text.includes('Allow: /'));
    check('robots.txt disallows /admin/', robots.text.includes('Disallow: /admin/'));
    check('robots.txt Sitemap pointer', /Sitemap:\s+https:\/\/www\.sokovibe\.co\.tz\/sitemap\.xml/.test(robots.text));
  } catch (e) {
    check('robots.txt 200', false, e.message);
  }

  let sitemap;
  try {
    sitemap = await request('/sitemap.xml');
    check('sitemap.xml 200', sitemap.status === 200, `got ${sitemap.status}`);
    check('sitemap is sitemapindex', sitemap.text.includes('<sitemapindex'));
    check('sitemap has child loc', sitemap.text.includes('<sitemap><loc>'));
  } catch (e) {
    check('sitemap.xml 200', false, e.message);
  }

  let asset;
  try {
    asset = await request('/main.dart.js');
    const cc = asset.headers.get('cache-control') || '';
    check('main.dart.js 200', asset.status === 200, `got ${asset.status}`);
    check('main.dart.js immutable cache', cc.includes('immutable'), cc);
    check('main.dart.js JS content-type', (asset.headers.get('content-type') || '').includes('javascript'));
  } catch (e) {
    check('main.dart.js 200', false, e.message);
  }

  print();

  async function print() {
    const pass = results.filter((r) => r.ok).length;
    const fail = results.filter((r) => !r.ok).length;
    for (const r of results) {
      console.log(`${r.ok ? 'PASS' : 'FAIL'}  ${r.name}${r.detail ? `  [${r.detail}]` : ''}`);
    }
    console.log(`\n${pass} passed, ${fail} failed  (BASE_URL=${BASE})`);
    process.exit(fail > 0 ? 1 : 0);
  }
})();