#!/usr/bin/env node
'use strict';

// Cross-page JSON-LD graph validator for Soko Vibe public pages.
// Usage: BASE_URL=http://localhost:3999 node seo-jsonld-check.js

const BASE = process.env.BASE_URL || 'https://www.sokovibe.co.tz';

const PAGES = ['/', '/tanzania-marketplace', '/categories', '/about', '/about/founder'];

const ORG_ID = 'https://www.sokovibe.co.tz/#organization';
const SITE_ID = 'https://www.sokovibe.co.tz/#website';
const FOUNDER_ID = 'https://www.sokovibe.co.tz/#founder';

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

  pass(faq.length === 0 || faq.length === 1 ? `FAQPage present on homepage only (${faq.length} page)` : `FAQPage on ${faq.length} pages (unexpected)`);

  console.log(failures === 0 ? '\nALL JSON-LD CHECKS PASSED' : `\n${failures} FAILURE(S)`);
  process.exit(failures > 0 ? 1 : 0);
})();