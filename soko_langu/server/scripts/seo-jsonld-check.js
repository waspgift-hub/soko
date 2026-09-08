#!/usr/bin/env node
'use strict';

// Cross-page JSON-LD graph validator for Soko Vibe public pages.
// Usage: BASE_URL=http://localhost:3999 node seo-jsonld-check.js

const BASE = process.env.BASE_URL || 'https://www.sokovibe.co.tz';

const PAGES = ['/', '/tanzania-marketplace', '/categories', '/how-soko-vibe-works', '/soko-vibe-fees', '/soko-vibe-escrow', '/about', '/about/founder'];

const ORG_ID = 'https://www.sokovibe.co.tz/#organization';
const SITE_ID = 'https://www.sokovibe.co.tz/#website';
const FOUNDER_ID = 'https://www.sokovibe.co.tz/#founder';
// Entity description must be identical on every page (mirror of src/seo/meta.js).
const ORG_DESCRIPTION =
  'Soko Vibe is a Tanzania-based online marketplace connecting buyers and sellers across Tanzania.';

let failures = 0;
const fail = (m) => { failures += 1; console.log('FAIL ' + m); };
const pass = (m) => { console.log('PASS ' + m); };

function walk(node, path, visit) {
  if (Array.isArray(node)) { node.forEach((n, i) => walk(n, `${path}[${i}]`, visit)); return; }
  if (node && typeof node === 'object') {
    visit(node, path);
    for (const k of Object.keys(node)) {
      if (k.startsWith('@')) continue;
      walk(node[k], `${path}.${k}`, visit);
    }
  }
}

(async () => {
  const orgs = [];
  const sites = [];
  const people = [];
  const faq = [];

  for (const p of PAGES) {
    let res;
    try {
      res = await fetch(`${BASE}${p}`, { redirect: 'manual' });
    } catch (e) {
      fail(`${p} unreachable: ${e.message}`);
      continue;
    }
    if (res.status !== 200) { fail(`${p} status ${res.status}`); continue; }
    const html = await res.text();
    const blocks = [...html.matchAll(/<script\s+type="application\/ld\+json">([\s\S]*?)<\/script>/g)];
    if (blocks.length === 0) { fail(`${p} has no JSON-LD`); continue; }
    for (const [i, m] of blocks.entries()) {
      let json;
      try {
        json = JSON.parse(m[1]);
      } catch (e) {
        fail(`${p} ld+json block #${i + 1} is invalid JSON: ${e.message}`);
        continue;
      }
      walk(json, 'root', (node) => {
        if (node['@type'] === 'Organization') orgs.push({ page: p, node });
        if (node['@type'] === 'WebSite') sites.push({ page: p, node });
        if (node['@type'] === 'Person') people.push({ page: p, node });
        if (node['@type'] === 'FAQPage') faq.push({ page: p });
      });
    }
  }

  pass('JSON-LD parses on all pages');

  const orgIds = new Set(orgs.map((o) => o.node['@id']));
  if (orgs.length === PAGES.length && new Set(orgs.map((o) => (o.node['@id'] || '') + o.node['name'])).size === 1) {
    pass('one consistent Organization entity on every page');
  } else {
    fail(`inconsistent Organization: ${orgIds.size} distinct @id(s)`);
  }
  const siteOrg = sites.filter((s) => s.node['@id'] === SITE_ID);
  if (sites.length === PAGES.length && siteOrg.length === PAGES.length) {
    pass('consistent WebSite entity (#website) on every page');
  } else {
    fail(`WebSite not uniform (${sites.length}/${PAGES.length})`);
  }
  const personOrg = people.filter((pp) => pp.node['@id'] === FOUNDER_ID);
  if (people.length === orgs.length && personOrg.length === orgs.length) {
    pass(`consistent Person entity (#founder) on ${people.length} pages`);
  } else {
    fail(`Person not uniform (${people.length}/${orgs.length})`);
  }

  const brokenRefs = [];
  const refs = [];
  orgs.forEach(({ node }) => { refs.push({ id: node['@id'], kind: 'org' }); if ((node.founder || {})['@id'] !== FOUNDER_ID) brokenRefs.push('org.founder mismatch'); });
  sites.forEach(({ node }) => { refs.push({ id: node['@id'], kind: 'site' }); if ((node.publisher || {})['@id'] !== ORG_ID) brokenRefs.push('website.publisher mismatch'); });
  people.forEach(({ node }) => { refs.push({ id: node['@id'], kind: 'person' }); if ((node.worksFor || {})['@id'] !== ORG_ID) brokenRefs.push('person.worksFor mismatch'); });
  refs.filter(r => r.id === ORG_ID).length === orgs.length || brokenRefs.push('org @id count mismatch');
  if (brokenRefs.length) {
    fail(`broken @id references: ${[...new Set(brokenRefs)].join(', ')}`);
  } else {
    pass('@id graph edges correct (website→org, person→org, org→person)');
  }

  const badDesc = orgs.filter((o) => o.node['description'] !== ORG_DESCRIPTION);
  if (orgs.length === PAGES.length && badDesc.length === 0) {
    pass(`Organization description identical on every page (${ORG_DESCRIPTION})`);
  } else {
    fail(`Organization description mismatch on ${badDesc.map((o) => o.page).join(', ')} or org count ${orgs.length}/${PAGES.length}`);
  }

  const breadcrumbs = [];
  for (const p of PAGES) {
    const res = await fetch(`${BASE}${p}`, { redirect: 'manual' });
    const html = await res.text();
    breadcrumbs.push({ page: p, has: html.includes('BreadcrumbList') });
  }
  // Root (/) has no parent page, so a BreadcrumbList there is expected to be
  // absent; every other public page should carry one.
  const innerPages = breadcrumbs.filter((b) => b.page !== '/');
  const missingBc = innerPages.filter((b) => !b.has).map((b) => b.page);
  const hasRootBc = breadcrumbs.find((b) => b.page === '/')?.has;
  if (missingBc.length === 0 && !hasRootBc) {
    pass(`BreadcrumbList on all inner pages (${innerPages.length}), absent on root as expected`);
  } else {
    fail(`BreadcrumbList issue: missing on ${missingBc.join(', ') || 'none'}; root has one=${!!hasRootBc}`);
  }

  pass(faq.length === 0 || faq.length === 1 ? `FAQPage present on homepage only (${faq.length} page)` : `FAQPage on ${faq.length} pages (unexpected)`);

  console.log(failures === 0 ? '\nALL JSON-LD CHECKS PASSED' : `\n${failures} FAILURE(S)`);
  // Give Node a tick to close fetch handles before exiting — avoids a
  // Windows-only libuv assertion (0xC0000409) after global fetch + exit.
  setTimeout(() => process.exit(failures > 0 ? 1 : 0), 50);
})();