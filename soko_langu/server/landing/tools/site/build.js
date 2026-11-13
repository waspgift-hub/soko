'use strict';

/* Static site build.
 *
 *   node tools/site/build.js
 *
 * Renders every page from the shared components and writes plain HTML into the
 * landing directory. The output is committed so production serves static files
 * with no build step at deploy time.
 */

const fs = require('fs');
const path = require('path');
const { homePage } = require('./pages/home');
const { aboutPage } = require('./pages/about');
const { howPage } = require('./pages/how-it-works');
const { featuresPage } = require('./pages/features');
const { buyersPage } = require('./pages/buyers');
const { sellersPage } = require('./pages/sellers');
const { pricingPage } = require('./pages/pricing');
const { faqPage } = require('./pages/faq');
const { contactPage, successPage, unsubscribePage, founderPage } = require('./pages/misc');
const { privacyPage, termsPage, cookiesPage, dataDeletionPage } = require('./pages/legal');
const { notFoundPage } = require('./pages/not-found');

const LANDING = path.resolve(__dirname, '..', '..');

const PAGES = [
  homePage(),
  aboutPage(),
  howPage(),
  featuresPage(),
  buyersPage(),
  sellersPage(),
  pricingPage(),
  faqPage(),
  contactPage(),
  successPage(),
  unsubscribePage(),
  founderPage(),
  privacyPage(),
  termsPage(),
  cookiesPage(),
  dataDeletionPage(),
  notFoundPage(),
];

const ROUTES = new Set([
  '/', '/about', '/about/founder', '/how-it-works', '/features', '/buyers',
  '/sellers', '/pricing', '/faq', '/contact', '/privacy', '/terms', '/cookies',
  '/data-deletion', '/waitlist/success', '/unsubscribe',
]);

const ALLOWED_ASSET_PREFIXES = ['/css/', '/js/', '/assets/', '/.well-known/'];

function checkInternalLinks(file, html, problems) {
  const matches = html.match(/href="([^"]+)"/g) || [];
  for (const attr of matches) {
    let href = attr.slice(6, -1);
    if (!href || href.startsWith('#') || href.startsWith('mailto:') || href.startsWith('tel:') || href.startsWith('http')) continue;
    href = href.split('#')[0].split('?')[0];
    if (!href) continue;
    if (ALLOWED_ASSET_PREFIXES.some((prefix) => href.startsWith(prefix))) continue;
    if (href === '/manifest.json' || href === '/favicon.ico') continue;
    if (!ROUTES.has(href)) problems.push(`${file}: link to unknown route ${href}`);
  }

  const ids = new Set((html.match(/\sid="([^"]+)"/g) || []).map((m) => m.slice(5, -1)));
  const anchors = html.match(/href="#([^"]+)"/g) || [];
  for (const attr of anchors) {
    const id = attr.slice(7, -1);
    if (id && !ids.has(id)) problems.push(`${file}: anchor #${id} has no matching id`);
  }
}

function main() {
  const problems = [];
  const written = [];

  for (const page of PAGES) {
    if (!page || !page.file || typeof page.html !== 'string') {
      throw new Error('A page module returned no file/html pair');
    }
    const target = path.join(LANDING, page.file);
    fs.writeFileSync(target, page.html, 'utf8');
    written.push({ file: page.file, bytes: Buffer.byteLength(page.html) });
    checkInternalLinks(page.file, page.html, problems);

    if (!/<html lang="sw"/.test(page.html)) problems.push(`${page.file}: missing lang="sw"`);
    if (!/<main id="main">/.test(page.html)) problems.push(`${page.file}: missing main landmark`);
    if (!/<h1[ >]/.test(page.html)) problems.push(`${page.file}: missing h1`);
  }

  // One canonical title/description/canonical per page.
  for (const page of PAGES) {
    const titles = (page.html.match(/<title>/g) || []).length;
    const descriptions = (page.html.match(/<meta name="description"/g) || []).length;
    const canonicals = (page.html.match(/rel="canonical"/g) || []).length;
    if (titles !== 1) problems.push(`${page.file}: expected one <title>, found ${titles}`);
    if (descriptions !== 1) problems.push(`${page.file}: expected one meta description, found ${descriptions}`);
    if (canonicals !== 1) problems.push(`${page.file}: expected one canonical, found ${canonicals}`);
  }

  for (const item of written.sort((a, b) => a.file.localeCompare(b.file))) {
    console.log(`  ${item.file.padEnd(24)} ${(item.bytes / 1024).toFixed(1)} kB`);
  }

  if (problems.length) {
    console.error('\nBuild checks failed:');
    for (const problem of problems) console.error(`  - ${problem}`);
    process.exitCode = 1;
    return;
  }

  console.log(`\nBuilt ${written.length} pages into ${LANDING}`);
}

main();
