'use strict';

// Localization audit for the admin panel.
//
// The panel renders Kiswahili first and translates to English at runtime with a
// longest-match phrase dictionary (SW2EN in admin/admin.js). A missing phrase
// silently ships Swahili to English-speaking operators, so this script checks
// every user-visible fragment in admin/admin.js and admin/index.html against
// that dictionary.
//
// Usage:
//   node scripts/i18n-admin-audit.js           # report + exit 1 on Swahili gaps
//   node scripts/i18n-admin-audit.js --json    # machine-readable report
//
// A fragment is a "definite" gap when it still contains a Swahili function word
// after translation. "Possible" gaps are fragments whose words are mostly
// outside the English vocabulary harvested from the dictionary's own
// translations; these can be proper nouns or technical labels and need review.

const fs = require('fs');
const path = require('path');

const ADMIN_DIR = path.join(__dirname, '..', 'admin');
const JS_FILE = path.join(ADMIN_DIR, 'admin.js');
const HTML_FILE = path.join(ADMIN_DIR, 'index.html');

// Swahili function words and high-frequency nouns. A fragment still containing
// one of these after translation is definitely untranslated.
const SWAHILI_MARKERS = new Set(
  (
    'ya wa kwa na za la cha vya hii hizi hizo huo huu huyu hawa yote kila bado tena sasa hivi ' +
    'kutoka kwenye kuwa ni au pia hakuna ina una ana wote mbali ndani juu chini bila kama ili ' +
    'hata sana zaidi moja mbili tatu nne tano siku wiki mwezi mwaka taarifa bidhaa mtumiaji ' +
    'watumiaji agizo maagizo malipo pesa salio duka mauzo mnunuzi muuzaji wauzaji wanunuzi hali ' +
    'tarehe jina namba barua akaunti uthibitisho ripoti tahadhari hitilafu kosa makosa sababu ' +
    'maelezo tafuta chuja angalia ongeza hariri futa hifadhi tuma thibitisha kataa sasisha ' +
    'inapakia zote mpya zamani jumla bei idadi ombi maombi msaada mfumo kampuni sheria sera ' +
    'kanuni tumia tumika bonyeza chagua andika rudisha badilisha ondoa weka fungua funga ' +
    'wasilisha pokea kamilisha subiri imekamilika imeshindwa imefanikiwa mafanikio hitaji ' +
    'mahitaji matumizi mapato gharama faida hasara deni madeni ankara risiti muamala miamala ' +
    'mteja wateja godown ghala usafirishaji usafiri mzigo mizigo kiasi nyingi wengi manunuzi ' +
    'historia rekodi hesabu benki nenosiri siri funguo ufunguo matangazo arifa mwaliko rufaa ' +
    'zawadi muhtasari dashibodi biashara matengenezo mipangilio wasifu leo jana kesho wiki ' +
    'mwisho mwanzo kati juu chini ndani nje nyuma mbele karibu mbali pamoja peke yake ' +
    'washa ruhusu lazimisha safisha andika chagua hakiki dondoo jumlisha punguza ongezeko ' +
    'kifungo kitufe dirisha jedwali orodha safu kichwa mwili mstari rangi picha kipengele'
  ).split(/\s+/)
);

// Proper nouns and technical tokens that are intentionally English.
const ALLOWED = new Set(
  (
    'sokovibe soko vibe azampay beem twilio google firebase firestore onesignal admob facebook ' +
    'mfa totp kyc gmv tzs tsh sms cdn json http https api url ui ux id ids ip otp qr pdf csv ' +
    'xls mb kb gb ttl tls ssl s3 ga fb pixel oauth clientid clientsecret appid appsecret ' +
    'merchantid apikey webhook webhooks stripe selcom clickpesa tigo airtel halopesa mkesh voda ' +
    'mpesa app apps admin script style textarea select option input radio chip section nav item ' +
    'noindex nofollow com net org html css js rgba rgb px rem em toast show strict delivery ' +
    'attempted ready dispatch inspection visibility credit actual comma application deletion ' +
    'hold signature wished wishes service max otpauth wholesale format featured transit secure ' +
    'boosted pass bucket sec briefing rate auth lang quot middot'
  ).split(/\s+/)
);

// English words that already have a Kiswahili equivalent in this panel. The
// source is written in Kiswahili first, so finding one of these in a label means
// the string was half-translated even though `applyLang` cannot detect it.
const SWAHILI_FIRST_LEAKS = new Set(
  (
    'verified unverified buyer buyers success failed failure fraud pending processing ' +
    'withdrawals ledger reconciliation overview dashboard description reason search filter'
  ).split(/\s+/)
);

/** Extract `'key': 'value'` pairs from the SW2EN object literal. */
function readDictionary(source) {
  const start = source.indexOf('const SW2EN = {');
  if (start < 0) throw new Error('SW2EN dictionary not found in admin.js');
  const end = source.indexOf('\n};', start);
  if (end < 0) throw new Error('SW2EN dictionary is not closed');
  const body = source.slice(start, end);
  const dict = new Map();
  const pairRe = /'((?:[^'\\]|\\.)*)'\s*:\s*(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")/g;
  const unescape = (s) => s.replace(/\\'/g, "'").replace(/\\\\/g, '\\');
  let m;
  while ((m = pairRe.exec(body))) {
    dict.set(unescape(m[1]), unescape(m[2] !== undefined ? m[2] : m[3]));
  }
  return dict;
}

/** Build the same longest-match translator the browser uses. */
function buildTranslator(dict) {
  const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pairs = [...dict.entries()].sort((a, b) => b[0].length - a[0].length);
  const re = new RegExp(
    pairs.map(([k]) => (/^[\p{L}\p{N}]+$/u.test(k) ? '\\b' + escapeRe(k) + '\\b' : escapeRe(k))).join('|'),
    'gu'
  );
  return (text) => String(text).replace(re, (match) => dict.get(match) || match);
}

/** Collect text nodes and translatable attributes from a literal or document. */
function collectFragments(source, isJs) {
  const out = new Set();
  const add = (v) => {
    if (typeof v !== 'string') return;
    const text = v.replace(/&nbsp;|&amp;|&#\d+;/g, ' ').trim();
    if (text.length >= 3 && /\p{L}/u.test(text)) out.add(text);
  };
  const scanMarkup = (markup) => {
    let m;
    const textRe = />([^<>]+)</g;
    while ((m = textRe.exec(markup))) add(m[1]);
    const attrRe = /(?:placeholder|title|aria-label|alt|content)="([^"]*)"/g;
    while ((m = attrRe.exec(markup))) add(m[1]);
    if (!/[<>]/.test(markup)) add(markup);
  };

  if (isJs) {
    const litRe = /'((?:[^'\\\n]|\\.)*)'/g;
    let m;
    while ((m = litRe.exec(source))) {
      const literal = m[1].replace(/\\'/g, "'").replace(/\\\\/g, '\\');
      if (literal.length < 3 || !/\p{L}/u.test(literal)) continue;
      scanMarkup(literal);
    }
  } else {
    scanMarkup(source);
  }
  return out;
}

function looksLikeIdentifier(text) {
  return (
    /:\/\//.test(text) ||
    /^\/|^\d|^st-|^rel-|^[A-Za-z0-9]+$|^[a-z-]+$/.test(text) ||
    /[=<>{}[\]#]/.test(text)
  );
}

function audit(dict, fragments) {
  const translate = buildTranslator(dict);
  const vocab = new Set();
  for (const value of dict.values()) {
    for (const word of value.toLowerCase().match(/[a-z]+/g) || []) vocab.add(word);
  }
  const definite = [];
  const possible = [];
  for (const fragment of fragments) {
    if (looksLikeIdentifier(fragment)) continue;
    const translated = translate(fragment);
    const remaining = (translated.toLowerCase().match(/[a-z]+/g) || []).filter(
      (word) => SWAHILI_MARKERS.has(word) && !ALLOWED.has(word)
    );
    if (remaining.length) {
      definite.push({ fragment, translated, words: [...new Set(remaining)] });
      continue;
    }
    const unknown = (translated.match(/\p{L}+/gu) || []).filter((token) => {
      const low = token.toLowerCase();
      if (vocab.has(low) || ALLOWED.has(low)) return false;
      if (/[A-Z_0-9]/.test(token)) return false;
      return low.length > 2;
    });
    if (unknown.length) possible.push({ fragment, translated, words: [...new Set(unknown)] });
  }
  return { definite, possible };
}

/** Fragments that are already Kiswahili but still contain an English-only word. */
function findLeaks(fragments) {
  const leaks = [];
  for (const fragment of fragments) {
    if (looksLikeIdentifier(fragment)) continue;
    // Status enums (deletion_pending, refund_pending, …) are wire values, not copy.
    if (/^[a-z0-9_]+$/i.test(fragment)) continue;
    const words = [...new Set((fragment.toLowerCase().match(/[a-z]+/g) || []))]
      .filter((word) => SWAHILI_FIRST_LEAKS.has(word) && !ALLOWED.has(word));
    if (words.length) leaks.push({ fragment, words });
  }
  return leaks;
}

/** JS source with the SW2EN literal removed, so dictionary values are not scanned. */
function stripDictionary(source) {
  // The English nav/title maps hold English on purpose; the leak check is about
  // Kiswahili strings, so remove those literals too.
  let out = source;
  for (const marker of ['const SW2EN = {', 'const NAV_EN = {', 'const TITLES_EN = {']) {
    const start = out.indexOf(marker);
    if (start < 0) continue;
    const end = out.indexOf('\n};', start);
    if (end < 0) continue;
    out = out.slice(0, start) + ' ' + out.slice(end + 3);
  }
  return out;
}

function main() {
  const json = process.argv.includes('--json');
  const jsSource = fs.readFileSync(JS_FILE, 'utf8');
  const htmlSource = fs.readFileSync(HTML_FILE, 'utf8');
  const dict = readDictionary(jsSource);
  const fragments = new Set([
    ...collectFragments(jsSource, true),
    ...collectFragments(htmlSource, false),
  ]);
  const { definite, possible } = audit(dict, fragments);
  const leaks = findLeaks(new Set([
    ...collectFragments(stripDictionary(jsSource), true),
    ...collectFragments(htmlSource, false),
  ]));

  if (json) {
    console.log(JSON.stringify({ dictionaryEntries: dict.size, fragments: fragments.size, definite, possible, leaks }, null, 2));
  } else {
    console.log(`dictionary entries: ${dict.size}`);
    console.log(`fragments scanned: ${fragments.size}`);
    console.log(`definite Swahili gaps: ${definite.length}`);
    for (const item of definite) {
      console.log(`  ${JSON.stringify(item.fragment)}\n    -> ${JSON.stringify(item.translated)} [${item.words.join(', ')}]`);
    }
    console.log(`possible gaps (review): ${possible.length}`);
    for (const item of possible) {
      console.log(`  ${JSON.stringify(item.fragment)} [${item.words.join(', ')}]`);
    }
    console.log(`english words left in Kiswahili source: ${leaks.length}`);
    for (const item of leaks) {
      console.log(`  ${JSON.stringify(item.fragment)} [${item.words.join(', ')}]`);
    }
  }

  // Only definite Swahili gaps fail the check. The "possible" list is advisory:
  // it contains proper nouns, enum values and English-only technical labels.
  if (definite.length) process.exitCode = 1;
}

main();
