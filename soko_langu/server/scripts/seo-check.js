#!/usr/bin/env node
'use strict';

/*
 * Soko Vibe SEO & domain health check.
 *
 * Usage:
 *   node scripts/seo-check.js            # against https://sokovibe.co.tz
 *   BASE_URL=http://localhost:3999 node scripts/seo-check.js
 *
 * Exits 0 when every required check passes, 1 otherwise.
 */

const BASE = process.env.BASE_URL || 'https://sokovibe.co.tz';

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
  check('canonical = apex host /', canon && canon[1] === 'https://sokovibe.co.tz/', canon && canon[1]);

  check('single meta description', count(/<meta\s+name="description"/g, t) === 1);
  check('meta description non-empty', /<meta\s+name="description"\s+content="[^"]+"/.test(t));

  const robotsMeta = t.match(/<meta\s+name="robots"\s+content="([^"]+)"/);
  check('home robots index,follow', robotsMeta && robotsMeta[1] === 'index, follow', robotsMeta && robotsMeta[1]);
  check('lang="sw"', /<html\s+lang="sw"/.test(t));
  check('og:title present', /<meta\s+property="og:title"/.test(t));
  check('og:image present', /<meta\s+property="og:image"/.test(t));
  check('twitter:card present', /<meta\s+name="twitter:card"/.test(t));
  check('JSON-LD present', t.includes('application/ld+json'));
  check('WebSite schema', /"@type"\s*:\s*"WebSite"/.test(t));
  check('Organization schema', /"@type"\s*:\s*"Organization"/.test(t));

  check('HSTS header', (home.headers.get('strict-transport-security') || '').startsWith('max-age=31536000'));
  check('X-Content-Type-Options: nosniff', home.headers.get('x-content-type-options') === 'nosniff');
  check('Content-Security-Policy header', !!home.headers.get('content-security-policy'));
  check('Referrer-Policy header', !!home.headers.get('referrer-policy'));
  check('X-Frame-Options: DENY', home.headers.get('x-frame-options') === 'DENY');

  const assets = [
    ['/css/site.css', ['text/css']],
    ['/js/site.js', ['javascript', 'text/javascript']],
    ['/assets/icon-512.png', ['image/png']],
    ['/assets/favicon.ico', []],
    ['/assets/apple-touch-icon.png', ['image/png']],
    ['/manifest.json', ['json']],
  ];
  for (const [path, cts] of assets) {
    try {
      const a = await request(path);
      check(`${path} 200`, a.status === 200, `got ${a.status}`);
      if (a.status === 200 && cts.length) {
        check(`${path} content-type`, cts.some((c) => (a.headers.get('content-type') || '').includes(c)), a.headers.get('content-type'));
      }
    } catch (e) {
      check(`${path} 200`, false, e.message);
    }
  }

  const legal = ['/privacy-policy', '/terms-of-service', '/support'];
  for (const p of legal) {
    try {
      const page = await request(p);
      check(`${p} 200`, page.status === 200, `got ${page.status}`);
    } catch (e) {
      check(`${p} 200`, false, e.message);
    }
  }

  const missing = await request('/this-page-does-not-exist');
  check('unknown path returns 404', missing.status === 404, `got ${missing.status}`);

  const prod = await request('/product/seo-check-non-existent-product');
  check('product deep link returns 404 (web app removed)', prod.status === 404, `got ${prod.status}`);

  try {
    const flutter = await request('/main.dart.js');
    check('main.dart.js 404 (no Flutter web build)', flutter.status === 404, `got ${flutter.status}`);
  } catch (e) {
    check('main.dart.js 404 (no Flutter web build)', false, e.message);
  }

  try {
    const mk = await request('/marketing');
    check('/marketing redirects to apex root', mk.status === 301 && (mk.headers.get('location') || '').endsWith('/'), `got ${mk.status} -> ${mk.headers.get('location')}`);
  } catch (e) {
    check('/marketing redirects to apex root', false, e.message);
  }

  let robots;
  try {
    robots = await request('/robots.txt');
    check('robots.txt 200', robots.status === 200, `got ${robots.status}`);
    check('robots.txt Allow /', robots.text.includes('Allow: /'));
    check('robots.txt disallows /api/', robots.text.includes('Disallow: /api/'));
    check('robots.txt disallows /admin/', robots.text.includes('Disallow: /admin/'));
    check('robots.txt Sitemap pointer', /Sitemap:\s+https:\/\/sokovibe\.co\.tz\/sitemap\.xml/.test(robots.text));
  } catch (e) {
    check('robots.txt 200', false, e.message);
  }

  let sitemap;
  try {
    sitemap = await request('/sitemap.xml');
    check('sitemap.xml 200', sitemap.status === 200, `got ${sitemap.status}`);
    check('sitemap is urlset', sitemap.text.includes('<urlset'));
    check('sitemap has home loc', sitemap.text.includes('<loc>https://sokovibe.co.tz/</loc>'));
    check('sitemap has legal locs', ['/privacy-policy', '/terms-of-service', '/support'].every((p) => sitemap.text.includes(`<loc>https://sokovibe.co.tz${p}</loc>`)));
  } catch (e) {
    check('sitemap.xml 200', false, e.message);
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