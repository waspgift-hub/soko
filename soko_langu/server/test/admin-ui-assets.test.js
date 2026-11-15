// Static contract tests for the admin console assets.
//
// The panel has no bundler, framework or type checker: `index.html` and
// `admin.js` are served as-is. A typo in a DOM id or a Kiswahili string without
// an English pair therefore fails silently in production (the handler just
// never binds, the label stays untranslated). These tests treat the two files
// as a contract so those failures surface in CI instead.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ADMIN_DIR = path.join(__dirname, '..', 'admin');
const JS_SRC = fs.readFileSync(path.join(ADMIN_DIR, 'admin.js'), 'utf8');
const HTML_SRC = fs.readFileSync(path.join(ADMIN_DIR, 'index.html'), 'utf8');

const htmlIds = [...HTML_SRC.matchAll(/\bid="([^"]+)"/g)].map((m) => m[1]);
// Markup rendered from admin.js counts as existing: it is injected into the DOM
// before any handler looks the element up.
const jsIds = [...JS_SRC.matchAll(/\bid="([A-Za-z][\w-]*)"/g)].map((m) => m[1]);
const knownIds = new Set([...htmlIds, ...jsIds]);

test('index.html declares every element id at most once', () => {
  const seen = new Set();
  const dupes = new Set();
  for (const id of htmlIds) (seen.has(id) ? dupes : seen).add(id);
  assert.deepEqual([...dupes], []);
});

test('every static $() lookup targets an id the panel renders', () => {
  const refs = [...JS_SRC.matchAll(/\$\('([A-Za-z][\w-]*)'\)/g)].map((m) => m[1]);
  const missing = [...new Set(refs)].filter((id) => !knownIds.has(id));
  assert.deepEqual(missing, [], 'lookup of unknown ids: ' + missing.join(', '));
});

test('every nav section has a loader, so clicking it never shows an empty pane', () => {
  const nav = [...HTML_SRC.matchAll(/class="nav-item" data-sec="([a-z]+)"/g)].map((m) => m[1]);
  const start = JS_SRC.indexOf('const LOADERS = {');
  assert.ok(start >= 0, 'LOADERS registry not found');
  const body = JS_SRC.slice(start, JS_SRC.indexOf('\n};', start));
  const loaders = new Set([...body.matchAll(/(\w+):\s*load\w+/g)].map((m) => m[1]));
  assert.ok(nav.length >= 20, 'expected the full navigation');
  const missing = nav.filter((sec) => !loaders.has(sec));
  assert.deepEqual(missing, [], 'nav sections without a loader: ' + missing.join(', '));
});

test('SW2EN has no duplicate key with a conflicting translation', () => {
  const start = JS_SRC.indexOf('const SW2EN = {');
  assert.ok(start >= 0, 'SW2EN dictionary not found');
  const body = JS_SRC.slice(start, JS_SRC.indexOf('\n};', start));
  const pairRe = /'((?:[^'\\]|\\.)*)'\s*:\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")/g;
  const values = new Map();
  const conflicts = [];
  let m;
  while ((m = pairRe.exec(body))) {
    const key = m[1];
    const value = m[2] !== undefined ? m[2] : m[3];
    // A later duplicate silently wins at runtime, so a differing value means
    // one of the two call sites is mistranslated.
    if (values.has(key) && values.get(key) !== value) conflicts.push([key, values.get(key), value]);
    values.set(key, value);
  }
  assert.deepEqual(conflicts, []);
});

test('the localization audit reports no definite Swahili gaps', () => {
  const report = execFileSync(process.execPath, [path.join(__dirname, '..', 'scripts', 'i18n-admin-audit.js')], {
    encoding: 'utf8',
  });
  assert.match(report, /definite Swahili gaps: 0/);
  // The panel renders Kiswahili first, so an English word in a label is a
  // half-translated string that the EN toggle cannot fix.
  assert.match(report, /english words left in Kiswahili source: 0/);
});

test('every inlined brand logo decodes to the same valid SVG', () => {
  const srcs = [...HTML_SRC.matchAll(/src="(data:image\/svg\+xml;base64,[^"]+)"/g)].map((m) => m[1]);
  assert.ok(srcs.length >= 2, 'expected the brand logo on the splash and the sidebar');
  // A hand-edited base64 payload can lose a character and still look valid; the
  // browser then rejects the URI and renders an empty box on the sign-in screen.
  for (const src of srcs) {
    const svg = Buffer.from(src.split(',')[1], 'base64').toString('utf8');
    assert.ok(svg.trim().endsWith('</svg>'), 'truncated brand logo payload');
    assert.match(svg, /viewBox="0 0 512 512"/, 'brand logo must be the 512x512 mark');
  }
  assert.equal(new Set(srcs).size, 1, 'every logo instance must share one payload');
});

test('the admin shell keeps the Soko Vibe brand, not the legacy name', () => {
  assert.ok(!/Dukani Admin/.test(HTML_SRC), 'legacy "Dukani Admin" title is still in index.html');
  assert.ok(/Soko Vibe Admin/.test(HTML_SRC), 'sign-in screen must name the Soko Vibe admin console');
});
