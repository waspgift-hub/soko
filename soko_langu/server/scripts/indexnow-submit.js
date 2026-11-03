#!/usr/bin/env node
'use strict';

/*
 * IndexNow submission helper for Soko Vibe.
 *
 * IndexNow is a ping protocol (Bing/Yandex/Seznam) for "URL changed, please
 * re-crawl". It only makes sense for frequently-changing or newly-published
 * pages. This site's web pages are few and static, so this script is meant to
 * be run BY OPERATOR DISCRETION after publishing a new/changed page — it is not
 * wired into the deploy pipeline automatically.
 *
 * Prerequisites (see SEO report, section K):
 *   1. Set INDEXNOW_KEY in the environment to a 32-char lowercase hex key you
 *      generated yourself. The server serves the key file at /{KEY}.txt
 *      automatically when this env var is set (server/src/seo/routes.js).
 *   2. Confirm https://www.sokovibe.co.tz/{KEY}.txt returns "{KEY}".
 *   3. Submit URLs that are canonical, public and return 200.
 *
 * Usage (PowerShell):
 *   $env:INDEXNOW_KEY="<your-32-hex-key>"
 *   node scripts/indexnow-submit.js https://www.sokovibe.co.tz/some-public-page
 *   # or submit multiple URLs:
 *   node scripts/indexnow-submit.js https://www.sokovibe.co.tz/about https://www.sokovibe.co.tz/categories
 *
 * Exit codes: 0 success/no-op, 1 configuration error, 2 submission rejected.
 */

const host = 'www.sokovibe.co.tz';
const key = process.env.INDEXNOW_KEY;

const urls = process.argv.slice(2).map((u) => u.replace(/\/$/, ''));
if (!key) {
  console.error('[INDEXNOW] INDEXNOW_KEY is not set. Set it to your 32-char lowercase hex key (see report section K).');
  process.exit(1);
}
if (!/^[a-f0-9]{32}$/.test(key)) {
  console.error('[INDEXNOW] INDEXNOW_KEY must be 32 lowercase hex characters. Got:', key);
  process.exit(1);
}
if (urls.length === 0) {
  console.error('[INDEXNOW] No URLs provided. Usage: node scripts/indexnow-submit.js <url> [<url> ...]');
  process.exit(1);
}
const bad = urls.filter((u) => !u.startsWith(`https://${host}/`));
if (bad.length) {
  console.error('[INDEXNOW] Only canonical https://www.sokovibe.co.tz URLs are allowed:', bad.join(', '));
  process.exit(1);
}

const payload = {
  host,
  key,
  keyLocation: `https://${host}/${key}.txt`,
  urlList: urls,
};

(async () => {
  let res;
  try {
    res = await fetch('https://api.indexnow.org/indexnow', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    console.error('[INDEXNOW] Network error submitting:', e.message);
    process.exit(2);
  }
  if (res.status === 200) {
    console.log(`[INDEXNOW] OK submitted ${urls.length} URL(s) for ${host}:`);
    urls.forEach((u) => console.log('  - ' + u));
    process.exit(0);
  }
  console.error(`[INDEXNOW] Submission failed (HTTP ${res.status}): ${await res.text()}`);
  process.exit(2);
})();