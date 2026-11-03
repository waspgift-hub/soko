'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { productFallbackHtml, buildHtml } = require('../src/modules/sharing/fallback-html');
const { buildProductSitemapXml } = require('../src/seo/sitemaps');

test('missing product image uses a placeholder, not a broken img', async () => {
  const html = await productFallbackHtml({
    id: 'prod-1',
    title: 'Kikapu',
    price: 5000,
    description: 'Kikapu cha asili',
    media: [],
    snapshot: {},
    seller: { storeName: 'Mama Ntilie' },
  });
  assert.match(html, /Hakuna picha/);
  assert.match(html, /og:title/);
  assert.match(html, /\/product\/prod-1/);
  assert.doesNotMatch(html, /play\.google\.com/);
  assert.match(html, /\/support/);
});

test('404 fallback page is HTML, not a blank redirect', () => {
  const html = buildHtml({
    title: 'Bidhaa haipo',
    description: 'Haipo',
    canonical: 'https://www.sokovibe.co.tz/product/missing',
    ogType: 'website',
    body: '<p>gone</p>',
  });
  assert.match(html, /<title>Bidhaa haipo/);
  assert.match(html, /property="og:title"/);
});

test('product sitemap uses canonical /product paths and skips unsafe ids', () => {
  const xml = buildProductSitemapXml(['abc-1', '<script>', '']);
  assert.match(xml, /https:\/\/www\.sokovibe\.co\.tz\/product\/abc-1/);
  assert.doesNotMatch(xml, /script/);
});
