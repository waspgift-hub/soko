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
  check('lang="sw"', /<html\s+lang="sw"/.test(t));
  check('exactly one H1', count(/<h1[\s>]/g, t) === 1);
  check('og:title present', /<meta\s+property="og:title"/.test(t));
  check('og:image present', /<meta\s+property="og:image"/.test(t));
  check('og:image:width present', /<meta\s+property="og:image:width"/.test(t));
  check('twitter:card present', /<meta\s+name="twitter:card"/.test(t));
  check('JSON-LD present', t.includes('application/ld+json'));
  check('WebSite schema', /"@type"\s*:\s*"WebSite"/.test(t));
  check('Organization schema', /"@type"\s*:\s*"Organization"/.test(t));
  check('Person schema (founder)', /"@type"\s*:\s*"Person"/.test(t));
  check('FAQPage schema', /"@type"\s*:\s*"FAQPage"/.test(t));

  // AI / generative-search grounding: the official entity statement must be
  // visible text (not only schema) so LLMs and crawlers resolve "Soko Vibe"
  // consistently.
  check(
    'visible official entity statement (short)',
    t.includes('Soko Vibe is a Tanzania-based online marketplace connecting buyers and sellers across Tanzania.'),
  );

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

  const publicPages = [
    '/privacy-policy',
    '/terms-of-service',
    '/support',
    '/tanzania-marketplace',
    '/categories',
    '/how-soko-vibe-works',
    '/soko-vibe-fees',
    '/soko-vibe-escrow',
    '/about',
    '/about/founder',
  ];
  // Entity identity used in every page's Organization JSON-LD (single source
  // of truth — mirror of src/seo/meta.js). Kept in sync so crawlers and AI
  // systems answer "what is Soko Vibe" identically across the site.
  const ORG_DESCRIPTION =
    'Soko Vibe is a Tanzania-based online marketplace connecting buyers and sellers across Tanzania.';
  for (const p of publicPages) {
    try {
      const page = await request(p);
      check(`${p} 200`, page.status === 200, `got ${page.status}`);
      if (page.status === 200) {
        check(`${p} single <title>`, count(/<title>/g, page.text) === 1);
        check(`${p} meta description`, /<meta\s+name="description"\s+content="[^"]+"/.test(page.text));
        check(`${p} canonical points at www host`, page.text.includes(`<link rel="canonical" href="https://www.sokovibe.co.tz${p}">`));
        check(`${p} org entity description`, page.text.includes(ORG_DESCRIPTION));
        if (p !== '/privacy-policy' && p !== '/terms-of-service' && p !== '/support') {
          check(`${p} BreadcrumbList schema`, page.text.includes('BreadcrumbList'));
        }
      }
    } catch (e) {
      check(`${p} 200`, false, e.message);
    }
  }

  // Canonical URL normalization: /about/ must resolve to the single canonical
  // /about form so no URL variant duplicates content.
  try {
    const slash = await request('/about/');
    check('trailing slash /about/ -> 301 /about', slash.status === 301 && (slash.headers.get('location') || '').endsWith('/about'), `${slash.status} -> ${slash.headers.get('location')}`);
  } catch (e) {
    check('trailing slash /about/ -> 301 /about', false, e.message);
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
    check('/marketing redirects to root', mk.status === 301 && (mk.headers.get('location') || '').endsWith('/'), `got ${mk.status} -> ${mk.headers.get('location')}`);
  } catch (e) {
    check('/marketing redirects to root', false, e.message);
  }

  let robots;
  try {
    robots = await request('/robots.txt');
    check('robots.txt 200', robots.status === 200, `got ${robots.status}`);
    check('robots.txt Allow /', robots.text.includes('Allow: /'));
    check('robots.txt disallows /api/', robots.text.includes('Disallow: /api/'));
    check('robots.txt disallows /admin/', robots.text.includes('Disallow: /admin/'));
    check('robots.txt disallows /dashboard', robots.text.includes('Disallow: /dashboard'));
    check('robots.txt disallows /account', robots.text.includes('Disallow: /account'));
    check('robots.txt disallows /checkout', robots.text.includes('Disallow: /checkout'));
    check('robots.txt Sitemap pointer', /Sitemap:\s+https:\/\/www\.sokovibe\.co\.tz\/sitemap\.xml/.test(robots.text));
  } catch (e) {
    check('robots.txt 200', false, e.message);
  }

  const sitemapPaths = ['/', '/privacy-policy', '/terms-of-service', '/support', '/tanzania-marketplace', '/categories', '/how-soko-vibe-works', '/soko-vibe-fees', '/soko-vibe-escrow', '/about', '/about/founder'];
  let sitemap;
  try {
    sitemap = await request('/sitemap.xml');
    check('sitemap.xml 200', sitemap.status === 200, `got ${sitemap.status}`);
    check('sitemap is urlset', sitemap.text.includes('<urlset'));
    check('sitemap has home loc', sitemap.text.includes('<loc>https://www.sokovibe.co.tz/</loc>'));
    check('sitemap has all public locs', sitemapPaths.every((p) => sitemap.text.includes(`<loc>https://www.sokovibe.co.tz${p}</loc>`)));
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