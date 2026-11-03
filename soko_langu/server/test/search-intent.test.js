const test = require('node:test');
const assert = require('node:assert/strict');

const { parseIntent, parseMoney, isHighConfidence } = require('../query-intent');

// ---------------------------------------------------------------------------
// Money parsing (§56 price language)
// ---------------------------------------------------------------------------

test('parseMoney: "800k" suffix', () => {
  assert.deepEqual(parseMoney(['80kabc'], 0), null); // unit bounds, sio suffix
  assert.deepEqual(parseMoney(['800k'], 0), { value: 800000, tokens: 1 });
});

test('parseMoney: "2m" means two million', () => {
  assert.deepEqual(parseMoney(['2m'], 0), { value: 2000000, tokens: 1 });
});

test('parseMoney: comma/"500000" plain numbers', () => {
  assert.deepEqual(parseMoney(['500,000'], 0), { value: 500000, tokens: 1 });
  assert.deepEqual(parseMoney(['500000'], 0), { value: 500000, tokens: 1 });
});

test('parseMoney: "iphone 13" is NOT a price', () => {
  assert.deepEqual(parseMoney(['13'], 0), null);
});

test('parseMoney: Swahili multipliers laki/elfu/milioni', () => {
  assert.deepEqual(parseMoney(['laki', '5'], 0), { value: 500000, tokens: 2 });
  assert.deepEqual(parseMoney(['elfu', '800'], 0), { value: 800000, tokens: 2 });
  assert.deepEqual(parseMoney(['milioni', '2'], 0), { value: 2000000, tokens: 2 });
});

test('parseMoney: Swahili digit words "milioni mbili"', () => {
  assert.deepEqual(parseMoney(['milioni', 'mbili'], 0), { value: 2000000, tokens: 2 });
  assert.deepEqual(parseMoney(['laki', 'tano'], 0), { value: 500000, tokens: 2 });
});

test('parseMoney: "nusu milioni" = half million', () => {
  assert.deepEqual(parseMoney(['nusu', 'milioni'], 0), { value: 500000, tokens: 2 });
});

// ---------------------------------------------------------------------------
// Intent extraction (§4–§7, §55–§57)
// ---------------------------------------------------------------------------

test('parseIntent: "iphone 13 chini ya 800k dar"', () => {
  const r = parseIntent('iphone 13 chini ya 800k dar');
  assert.equal(r.searchQuery, 'iphone 13');
  assert.equal(r.filters.maxPrice, 800000);
  assert.equal(r.filters.minPrice, undefined);
  assert.equal(r.filters.location, 'Dar es Salaam');
  assert.deepEqual(r.detected.money, [800000]);
});

test('parseIntent: "simu nzuri ya camera chini ya 600000"', () => {
  const r = parseIntent('simu nzuri ya camera chini ya 600000');
  assert.equal(r.filters.maxPrice, 600000);
  assert.equal(r.searchQuery, 'simu nzuri camera');
  assert.deepEqual(r.synonyms, ['phone', 'mobile']);
});

test('parseIntent: "zaidi ya" becomes minPrice', () => {
  const r = parseIntent('gari zaidi ya 1m');
  assert.equal(r.filters.minPrice, 1000000);
  assert.equal(r.filters.maxPrice, undefined);
  assert.equal(r.searchQuery, 'gari');
});

test('parseIntent: bare price means a ceiling', () => {
  const r = parseIntent('tv 500k');
  assert.equal(r.filters.maxPrice, 500000);
  assert.equal(r.searchQuery, 'tv');
  assert.deepEqual(r.synonyms, ['television']);
});

test('parseIntent: "laptop ya gaming chini ya milioni mbili"', () => {
  const r = parseIntent('laptop ya gaming chini ya milioni mbili');
  assert.equal(r.filters.maxPrice, 2000000);
  assert.ok(r.keywords.includes('laptop'));
  assert.ok(r.keywords.includes('gaming'));
});

test('parseIntent: location aliases normalize', () => {
  assert.equal(parseIntent('phone dsm').filters.location, 'Dar es Salaam');
  assert.equal(parseIntent('gari 2m arusha').filters.location, 'Arusha');
  assert.equal(parseIntent('gari 2m arusha').filters.maxPrice, 2000000);
});

test('parseIntent: plain multiword keyword query untouched', () => {
  const r = parseIntent('iphone 13 128gb');
  assert.equal(r.searchQuery, 'iphone 13 128gb');
  assert.equal(r.filters.maxPrice, undefined);
  assert.equal(r.filters.location, undefined);
});

test('parseIntent: synonyms expand compy/laptop words', () => {
  const r = parseIntent('kompyuta');
  assert.deepEqual(r.synonyms, ['computer', 'laptop']);
});

test('parseIntent: empty input is safe', () => {
  const r = parseIntent('');
  assert.equal(r.original, '');
  assert.equal(r.searchQuery, '');
  assert.deepEqual(r.filters, {});
});

test('parseIntent: lowercase normalization', () => {
  assert.equal(parseIntent('TV Dar').detected.location, 'Dar es Salaam');
  assert.equal(parseIntent('TV Dar').filters.location, 'Dar es Salaam');
});

// ---------------------------------------------------------------------------
// Typo confidence (§06–§07: auto-apply only when high)
// ---------------------------------------------------------------------------

test('isHighConfidence: samsng→samsung, iphne→iphone apply', () => {
  assert.equal(isHighConfidence({ query: 'samsng', word: 'samsung', distance: 2 }), true);
  assert.equal(isHighConfidence({ query: 'iphne', word: 'iphone', distance: 1 }), true);
  assert.equal(isHighConfidence({ query: 'lapto', word: 'laptop', distance: 1 }), true);
});

test('isHighConfidence: short/low-confidence queries never auto-apply', () => {
  assert.equal(isHighConfidence({ query: 'cam', word: 'camera', distance: 2 }), false);
  assert.equal(isHighConfidence(null), false);
  // distance 3 exceeds the ≤2-edit bound → must NOT auto-apply
  assert.equal(isHighConfidence({ query: 'samsungggg', word: 'samsung', distance: 3 }), false);
});

// ---------------------------------------------------------------------------
// NO inverse-correction over-reach: real product words must not vanish
// ---------------------------------------------------------------------------

test('parseIntent: number-like model names stay keywords', () => {
  const r = parseIntent('samsung a54');
  assert.equal(r.searchQuery, 'samsung a54');
  assert.equal(r.filters.maxPrice, undefined);
});