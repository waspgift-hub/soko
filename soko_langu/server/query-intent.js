// Swahili/English free-text query intent parser.
// Turns "simu chini ya 800k dar" into structured search inputs:
//   { searchQuery: 'simu', filters: { maxPrice: 800000, location: 'Dar es Salaam' } }
// Pure functions only (no Firebase) so they can be unit-tested like ../money.
// Spec: §4–§7 (intent extraction), §55–§57 (Swahili / price / location language).

const NUMBER_WORDS = {
  elfu: 1e3,
  laki: 1e5,
  milioni: 1e6,
  million: 1e6,
  milion: 1e6,
  mil: 1e6,
};

// Swahili digit words, used ONLY right after a multiplier (milioni mbili,
// laki tano) so words like "tatu" in a product name are never mis-parsed.
const SW_DIGITS = {
  moja: 1, mbili: 2, tatu: 3, nne: 4, tano: 5, sita: 6, saba: 7,
  nane: 8, tisa: 9, kumi: 10, ishirini: 20, thelathini: 30,
  arubaini: 40, hamsini: 50, sitini: 60, sabini: 70, themanini: 80,
  tisini: 90, mia: 100,
};

// "X na chini" (X and below) means maxPrice; "X na zaidi" means minPrice.
const MAX_PRICE_HINTS = ['chini ya', 'chini', 'under', 'below', 'na chini', 'max'];
const MIN_PRICE_HINTS = ['zaidi ya', 'zaidi', 'above', 'over', 'na zaidi', 'min'];

const LOCATION_ALIASES = {
  'dar es salaam': 'Dar es Salaam',
  dsm: 'Dar es Salaam',
  dar: 'Dar es Salaam',
  arusha: 'Arusha',
  mwanza: 'Mwanza',
  dodoma: 'Dodoma',
  mbeya: 'Mbeya',
  tanga: 'Tanga',
  zanzibar: 'Zanzibar',
  morogoro: 'Morogoro',
  iringa: 'Iringa',
  songea: 'Songea',
  tabora: 'Tabora',
  kigoma: 'Kigoma',
  moshi: 'Moshi',
  kili: 'Kilimanjaro',
};

// Swahili → English product synonyms are ADDED as candidate terms only; the
// relevance scorer still weighs the user's original words highest, so
// "simu" finds phone listings without burying exact "simu" matches.
const PRODUCT_SYNONYMS = {
  simu: ['phone', 'mobile'],
  gari: ['car', 'vehicle'],
  pikipiki: ['motorcycle', 'bike', 'boda'],
  baiskeli: ['bicycle'],
  nguo: ['clothes', 'clothing'],
  shati: ['shirt'],
  suruali: ['trousers', 'pants'],
  viatu: ['shoes'],
  kofia: ['hat'],
  mfuko: ['bag'],
  mkoba: ['bag'],
  kompyuta: ['computer', 'laptop'],
  laptop: ['computer'],
  jokofu: ['fridge', 'refrigerator'],
  skimba: ['refrigerator', 'fridge'],
  jiko: ['stove', 'cooker'],
  tv: ['television'],
  runinga: ['television'],
  kamera: ['camera'],
  kitanda: ['bed'],
  kabati: ['wardrobe', 'closet'],
  meza: ['table'],
  kiti: ['chair'],
  nyumba: ['house', 'home'],
  ghorofa: ['apartment', 'flat'],
};

const NUMERIC_TOKEN = /^(\d{1,3}(?:[.,]\d{3})+|\d+(?:\.\d+)?)$/;

// Reads one money token starting at `words[i]`; `tokens` = how many words it
// consumed (compound forms like "nusu milioni" / "laki 5" consume two).
function parseMoney(words, i) {
  const w = words[i];
  const suffixed = w.match(/^(\d+(?:\.\d+)?)([km])$/);
  if (suffixed) {
    const mult = suffixed[2] === 'k' ? 1e3 : 1e6;
    return { value: Math.round(parseFloat(suffixed[1]) * mult), tokens: 1 };
  }
  if (w === 'nusu' && words[i + 1] === 'milioni') {
    return { value: 5e5, tokens: 2 };
  }
  if (NUMBER_WORDS[w]) {
    const next = words[i + 1];
    if (next && NUMERIC_TOKEN.test(next.replace(/,/g, ''))) {
      return { value: Math.round(parseFloat(next.replace(/,/g, '')) * NUMBER_WORDS[w]), tokens: 2 };
    }
    if (next && SW_DIGITS[next]) {
      return { value: Math.round(NUMBER_WORDS[w] * SW_DIGITS[next]), tokens: 2 };
    }
    return { value: NUMBER_WORDS[w], tokens: 1 };
  }
  if (NUMERIC_TOKEN.test(w)) {
    const clean = parseFloat(w.replace(/,/g, ''));
    // Numbers below 10,000 are usually model/length tokens ("iphone 13"),
    // not prices — only treat 4+ digit numbers as prices.
    if (clean >= 10000) return { value: Math.round(clean), tokens: 1 };
  }
  return null;
}

function parseIntent(raw) {
  const original = (raw || '').trim();
  const result = {
    original,
    searchQuery: original.toLowerCase(),
    keywords: [],
    synonyms: [],
    filters: {},
    detected: {},
  };
  if (!original) return result;
  const words = original.toLowerCase().split(/\s+/).filter(Boolean);

  const moneyValues = [];
  const keep = [];
  for (let i = 0; i < words.length;) {
    const money = parseMoney(words, i);
    if (money) { moneyValues.push(money.value); i += money.tokens; continue; }
    keep.push(words[i]);
    i += 1;
  }
  result.detected.money = moneyValues;

  const joined = ` ${keep.join(' ')} `;
  const hasHint = (hints) => hints.some((h) => joined.includes(` ${h.trim()} `));

  let maxPrice = null;
  let minPrice = null;
  if (moneyValues.length > 0) {
    const price = moneyValues[0];
    if (hasHint(MIN_PRICE_HINTS)) minPrice = price;
    else maxPrice = price; // bare price and "X na chini" both mean a ceiling
  }
  if (maxPrice != null) result.filters.maxPrice = maxPrice;
  if (minPrice != null) result.filters.minPrice = minPrice;

  let matchedLocationWord = null;
  const locKeys = Object.keys(LOCATION_ALIASES).sort((a, b) => b.length - a.length);
  for (const key of locKeys) {
    if (joined.includes(` ${key} `)) { matchedLocationWord = key; break; }
  }
  if (matchedLocationWord) {
    result.detected.location = LOCATION_ALIASES[matchedLocationWord];
    result.filters.location = result.detected.location;
  }

  const HINT_WORDS = new Set([...MAX_PRICE_HINTS, ...MIN_PRICE_HINTS]
    .map((h) => h.split(' ')).flat());
  const isNoise = (w) =>
    HINT_WORDS.has(w) || w === 'ya' || w === 'na' ||
    (matchedLocationWord !== null && w === matchedLocationWord) ||
    /^\d{3,}$/.test(w);
  const keywords = keep.filter((w) => w.length >= 2 && !isNoise(w));
  result.keywords = Array.from(new Set(keywords));

  const synonyms = new Set();
  for (const k of result.keywords) {
    for (const alt of PRODUCT_SYNONYMS[k] || []) synonyms.add(alt);
  }
  result.synonyms = Array.from(synonyms);
  result.searchQuery = result.keywords.join(' ');
  return result;
}

// Spec §06–§07: only auto-apply a correction when confidence is high; this
// means ≤ 2 edits AND within a third of the query length (samsng→samsung,
// iphne→iphone qualify; "cam" never fires).
function isHighConfidence(correction) {
  if (!correction) return false;
  const len = correction.query.length;
  return correction.distance > 0 &&
    correction.distance <= 2 &&
    correction.distance <= Math.floor(len / 3);
}

module.exports = { parseIntent, parseMoney, isHighConfidence, NUMERIC_TOKEN };