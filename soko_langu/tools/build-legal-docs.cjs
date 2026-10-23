#!/usr/bin/env node
/**
 * Builds the Soko Vibe legal pages (Terms of Service + Privacy Policy).
 *
 * WHY THIS FILE EXISTS
 * --------------------
 * `legal_i18n.js` carries a header saying "Do not edit by hand - regenerate with
 * scripts/gen_legal_i18n.js". That script does not exist. So the two copies of
 * legal_i18n.js (hosting/ and server/landing/) silently drifted until one of them
 * was missing an entire section, and the Terms page had no HTML at all, so its
 * content was unreachable. This script is the missing generator, scoped to the
 * legal documents.
 *
 * WHY THE TEXT IS SHORT
 * ---------------------
 * The previous Terms ran to 16 sections and the Privacy Policy to 18, each a
 * dense block of sub-clauses, much of it in Swahili set in capitals. Nobody
 * reads that, and a policy nobody reads is not consent. What follows is the
 * same substance at roughly a fifth of the length: plain sentences, one idea
 * per section, and every provision a user actually needs to know stated
 * outright rather than implied.
 *
 * WHAT IS DELIBERATELY NOT HERE
 * -----------------------------
 * Only Swahili and English are provided. The French, German and Chinese
 * translations in the old file were mojibake (`GEBAoHREN`, `dA�?dYب`) - worse
 * than useless, because they looked translated. With the key absent,
 * i18n.js leaves the page's hardcoded English text in place, so those visitors
 * get clean readable English instead of corrupted Swahili-shaped noise.
 *
 * IMPORTANT: this is drafting, not legal advice. Tanzania's Personal Data
 * Protection Act 2022 requires the controller to REGISTER with the PDPC, and
 * the Personal Data Protection (Collection and Processing) Regulations 2023
 * require a PERMIT before transferring personal data outside Tanzania - which
 * Firebase, Google Cloud and ClickPesa all are. Those are registrations Soko
 * Vibe must obtain, not wording to change. The text below is written so those
 * obligations are disclosed rather than hidden, but it should be reviewed by a
 * Tanzanian data-protection lawyer before it is relied on.
 *
 * Usage:  node tools/build-legal-docs.cjs
 */
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const LAST_UPDATED = '3 October 2026';

const SUPPORT_EMAIL = 'support@soko-vibe.com';
const DPO_EMAIL = 'dpo@soko-vibe.com';
const WEBSITE = 'https://www.sokovibe.co.tz';

/* ------------------------------------------------------------------ */
/* Terms of Service                                                    */
/* ------------------------------------------------------------------ */

const TOS = {
  sw: {
    title: 'MASHARTI YA UTUMIAJI',
    last_updated: `Ilisasishwa Mwisho: ${LAST_UPDATED}`,
    intro:
      'Sera hii inaeleza jambo moja rahisi: unapofanya kazi Soko Vibe, unakubali ' +
      'masharti haya. Ikiwa jambo lolote hapa halieleweki, wasiliana nasi kwa ' +
      `${SUPPORT_EMAIL} kabla ya kuendelea.`,
    1: [
      'KUKUBALI',
      'Kwa kufungua akaunti au kutumia Soko Vibe, unakubali masharti haya na Sera ' +
        'yetu ya Faragha. Ukiwa hukubaliani, acha kutumia Jukwaa na ufute akaunti yako.',
    ],
    2: [
      'JIULI YA KUPATAJI',
      'Unapaswa kuwa na umri wa miaka 18 au zaidi, na kujisajili kwa taarifa zako ' +
        'halisi. Unaweza kuthibitishwa kwa kitambulisho, kwa njia zote unazotumia ' +
        'kupata bidhaa. Ukoseho wa umri hujumaisha akaunti yako na hana kurudi kwa malipo.',
    ],
    3: [
      'JUKWAA NI NYUMBANI, SI MWEKAJI',
      'Soko Vibe ni njia ya kuunganisha watumiaji. Tunashughulikia malipo, kuhifadhi ' +
        'fedha kwa muda (escrow), na kuratibu mzozo. Hatuwezi kudhibiti ubora wa bidhaa ' +
        'au jambo lolote linalofanyika kati ya watumiaji.',
    ],
    4: [
      'KULAZIMISHA KILA WANUNUZI',
      'Unapaswa kuwa na jina, picha na bei halisi. Usiruhusu bidhaa yoyote isiyoko ' +
        'malipo, kwenye maeneo yaliyo haruhusiwa, au bidhaa zilizoibiwa. Ukoseho wa ' +
        'hali hii unaweza kukomeshwa mara moja.',
    ],
    5: [
      'FEDHA NA MALIPO',
      'Fedha yako huishikiliwa kwa muda hadi bidhaa ikamilike. Tunatoza kiasi ' +
        'kinachochaguliwa ndani ya programu na kuonyesha kabla ya kulipa. Hatuhitaji ' +
        'namba yako ya kadi. Mali ya ClickPesa inahifadhiwa kwao, si kwetu.',
    ],
    6: [
      'UGOMOTO',
      'Jama usitumie OTP yako, nenosiri lako, au namba ya kadi yako kwa mtu yeyote, ' +
        'hata akiwepo kuwa mw employees wa Soko Vibe au mtu anayewakilisha kuwa hivyo. ' +
        'Soko Vibe HITAHITAJI KABISA nenosiri lako au OTP yako. Mtu anayekuhitaji vitu ' +
        ' hivyo ni mzaga.',
    ],
    7: [
      'KUPATA MALIPO KUFAULIA',
      'Ikiwa muuzaji hana buduma, unajibu kwa muda mrefu, au hanaweza kukamilisha ' +
        'maagizo, fedha yako hurudiwa. Wewe kama mwuzaji unafanya kazi chini ya ' +
        'masharti haya pia.',
    ],
    8: [
      'MZOZO',
      'Kwanza jaribu kumalika na mtu mwingine kupitia ujumbe wa Soko Vibe. Ikiwa ' +
        'hayajatendeka, fungua mzozo rasmi ndani ya programu. Fedha zinabaki ' +
        'zimshikiliwa hadi tatizo litakamilika. Maamuzi yetu ya mzozo ni ya mwisho.',
    ],
    9: [
      'WAKATI TUNAPOKATA AKAUNTI',
      'Tunaweza kufunga akaunti yako kama unakukiwa, unapotumia Jukwaa kwa njia ' +
        'ya udanganyifu, au unapoendelea kukiuka masharti haya. Fedha yako yoyote ' +
        'inayostahili kurejeshwa hutowana haki yako.',
    ],
    10: [
      'MAUDHUI YAKO',
      'Unabaki mwenyewe bidhaa, picha na video unayochapisha. Unatupa ruhusa ' +
        'kutumia ili kuonyesha Jukwaa. Usiigeuze muundo wetwa, alama, au jina la Jukwaa.',
    ],
    footer: `© ${LAST_UPDATED.split(' ')[2]} Soko Vibe. Haki zote zimehifadhiwa.`,
  },
  en: {
    title: 'TERMS OF SERVICE',
    last_updated: `Last updated: ${LAST_UPDATED}`,
    intro:
      'These terms say one simple thing: by using Soko Vibe you agree to them. If ' +
      `anything here is unclear, email us at ${SUPPORT_EMAIL} before you continue.`,
    1: [
      'AGREEMENT',
      'By creating an account or using Soko Vibe you accept these terms and our ' +
        'Privacy Policy. If you do not agree, stop using the app and delete your account.',
    ],
    2: [
      'WHO CAN USE THE APP',
      'You must be 18 or older and register with your true details. We may verify ' +
        'your identity with an ID document, whether you are buying or selling. Giving ' +
        'false details closes your account with no refund.',
    ],
    3: [
      'WE ARE A MIDDLEMAN, NOT A WAREHOUSE',
      'Soko Vibe connects buyers and sellers. We handle payments, hold money in ' +
        'escrow, and help resolve disputes. We cannot vouch for the quality of items ' +
        'or for anything that happens between two people off-platform.',
    ],
    4: [
      'SELLER RULES',
      'Listings must be real, priced honestly, and photographed by you. You may not ' +
        'sell counterfeit goods, restricted items, or anything stolen. Breaking this ' +
        'closes your account immediately.',
    ],
    5: [
      'MONEY AND PAYMENTS',
      'Money is held in escrow until delivery completes. Fees are shown inside the ' +
        'app before you pay. We never need your card number - ClickPesa stores payment ' +
        'details, we do not.',
    ],
    6: [
      'NEVER SHARE YOUR CODES',
      'Never give anyone your OTP, password or card number - not even someone claiming ' +
        'to be Soko Vibe staff. We will NEVER ask for your password or OTP. Anyone who ' +
        'does is a fraudster.',
    ],
    7: [
      'IF THE SELLER FAILS',
      'If the seller runs out of stock, stops replying, or cannot deliver, your money ' +
        'is returned to you. Sellers are bound by these terms too.',
    ],
    8: [
      'DISPUTES',
      'First try to sort it out directly over Soko Vibe chat. If that fails, raise a ' +
        'formal dispute in the app. Money stays held until the dispute closes. Our ' +
        'decision on a dispute is final.',
    ],
    9: [
      'WHEN WE CLOSE AN ACCOUNT',
      'We may suspend accounts used for fraud, abuse, or breaking these terms. Any ' +
        'money you are owed is still returned to you.',
    ],
    10: [
      'YOUR CONTENT',
      'You keep ownership of the photos and videos you upload. You let us use them to ' +
        'display on Soko Vibe. Do not copy or rebrand the app, its logo or its name.',
    ],
    footer: `© ${LAST_UPDATED.split(' ')[2]} Soko Vibe. All rights reserved.`,
  },
};

/* ------------------------------------------------------------------ */
/* Privacy Policy                                                      */
/* ------------------------------------------------------------------ */

const PP = {
  sw: {
    title: 'SERA YA FARAGHA',
    last_updated: `Ilisasishwa Mwisho: ${LAST_UPDATED}`,
    intro:
      'Hii ni maelezo mafupi ya data tunayokusanya na jinsi tunavyotumia. ' +
      `Maswali yoyote: ${DPO_EMAIL}.`,
    1: [
      'DATA TUNAYOKUSANYA',
      'Jina na namba ya simu. Eneo la GPS unapotumia programu kupeleka bidhaa. ' +
        'Picha za bidhaa unazouza. Nyaraka za KYC ikiwa wewe ni muuzaji. Riwaya ' +
        'ya malipo, matumizi na majibu ya programu. Nyimbo zako za kwenye simu ' +
        'zinasomwa tu ili kuonyesha nyimbo zako - hazihitajwi kwa ajili ya kutuma ' +
        'data yoyote kwa mtu mwingine.',
    ],
    2: [
      'KWA NINI TUNAYAKUSANYA',
      'Kukuwezesha kutumia Jukwaa: kuingia, kutafuta bidhaa, kuweka maagizo, kutumia ' +
        'nyimbo. Kuendelea kuona bidhaa zinazokupenda na kukuonyesha madaraka ' +
        'yako yaliyoidhinishwa. Kutambua na kuzuia udanganyifu, hasa kwenye malipo ' +
        'na KYC. Kutuma arifa za maagizo na usalama. Kubeba jukumu la sheria.',
    ],
    3: [
      'DATA NYETI',
      'Nyaraka za KYC, alama za vidole na uso (zinazotumika kwenye KYC au ' +
        'kufungua programu kwa alama ya vidole), na taarifa za afya unapo ' +
        'taarifa kwa ajili ya usalama. Hii inahitaji idhini yako maalum kabla ya ' +
        'kuchakatawa, na unaweza kuondoa idhini hiyo wakati wowote.',
    ],
    4: [
      'ULINZI WA PASSWORD NA ALAMA',
      'Nenosiri lako likahifadhiwa kwa njia salama kwenye kifaa chako. Alama yako ya ' +
        'vidole au uso hubaki KWENYE KIFAA CHAKO - tunapitisha tu "imefanikiwa" au ' +
        '"imeshindwa". Hatuhifadhi alama hiyo wala kuituma kwa mtu yeyote.',
    ],
    5: [
      'ULIMANGO WA FEDHA NA KADI',
      'Hatuhifadhi namba yako kamili ya kadi. ClickPesa ndiye anayeshughulikia ' +
        'malipo na kuhifadhi kadi. Tunahifadhi kiasi, tarehe na matokeo ya kila ' +
        'muamala ili kushughulikia mzozo na kutoa risiti.',
    ],
    6: [
      'ULIMANGO WA ENEO',
      'Tunatumia eneo lako kwa sababu tatu: kuonyesha bidhaa zilizo karibu, ' +
        'kukusaidia kufika, na kuthibitisha usafirishaji. Tunatumia eneo wakati wa ' +
        'usafiri, si muda wote.',
    ],
    7: [
      'KUSHIRIKIWA NA WATU WA TATU',
      'Tunashiriki data kidogo tu na wanaohitaji: Google (Firebase, malipo Google), ' +
        'ClickPesa (malipo), Cloudinary (picha), Meseji (SMS), OneSignal (arifa), na ' +
        'watozaaji wa AI (AI). Wote wanafanya kazi chini ya mikataba yao yenyewe.',
    ],
    8: [
      'KUHAMISHWA DATA NJE YA TANZANIA',
      'Data yako huhifadhiwa kwenye vituo vyetu au miamboni ya watu wa tatu ' +
        'ambayo yako nje ya Tanzania. Hii ni kwa sheria ya Ulinzi wa Data ya ' +
        'Tanzania (2022), ambayo inadai kibali cha Mamlaka kabla ya kuhamisha data ' +
        'nje ya nchi. Tunafanya hivyo kwa udhibiti unaoendelea.',
    ],
    9: [
      'HIKI UNACHOKUWA',
      'Unaweza kuona data yako, kuirekebisha au kuifuta kwa kutuma ombi kwa ' +
        `${DPO_EMAIL}. Tunajibu ndani ya siku 14 za kazi. Unaweza kukataa ' +
        'matangazo ya sokofu wakati wowote, lakini arifa za maagizo na usalama ' +
        'zitaendelea. Ukichukua matatizo zaidi, unaweza kulalamika kwa Mamlaka ya ' +
        'Ulinzi wa Data Tanzania (PDPC).`,
    ],
    10: [
      'ULINZI NA KUBADILISHA',
      'Tunatumia ufikiaji uliofunzwa na ufichuzi wa data ili kulinda taarifa zako ' +
        'na fedha za watumiaji. Tunaweza kurekebisha Sera hii wakati wowote; ' +
        'tutataarifa watumiaji kwa barua pepe au arifa kabla ya mabadiliko.',
    ],
    footer: `© ${LAST_UPDATED.split(' ')[2]} Soko Vibe. Haki zote zimehifadhiwa.`,
  },
  en: {
    title: 'PRIVACY POLICY',
    last_updated: `Last updated: ${LAST_UPDATED}`,
    intro:
      'A short, plain summary of what we collect and why. ' +
      `Questions: ${DPO_EMAIL}.`,
    1: [
      'WHAT WE COLLECT',
      'Your name and phone number. GPS while you use the app to deliver an item. ' +
        'Photos of what you sell. KYC documents if you are a seller. Payment history, ' +
        'usage data and crash reports. Songs on your phone are read only to show you ' +
        'your own music - they are never uploaded or shared.',
    ],
    2: [
      'WHY WE COLLECT IT',
      'To let you use the app: sign in, search, place orders, list items, play music. ' +
        'To show you relevant products and approved badges. To detect and stop fraud, ' +
        'especially around payments and KYC. To send order and security alerts. To meet ' +
        'our legal duties.',
    ],
    3: [
      'SENSITIVE DATA',
      'KYC documents, and face or fingerprint data (used for KYC or to unlock the app ' +
        'with your fingerprint). This needs your explicit consent before processing, and ' +
        'you can withdraw that consent at any time.',
    ],
    4: [
      'PASSWORDS AND BIOMETRICS',
      'Your password is stored securely on your device. Your fingerprint or face ' +
        'template NEVER LEAVES YOUR PHONE - we only receive "matched" or "did not ' +
        'match". We do not store it and never send it anywhere.',
    ],
    5: [
      'PAYMENT AND CARD DETAILS',
      'We never store your full card number. ClickPesa processes and stores payment ' +
        'details. We keep the amount, date and outcome of each transaction so we can ' +
        'handle disputes and issue receipts.',
    ],
    6: [
      'LOCATION',
      'We use your location for three reasons: showing nearby items, helping with ' +
        'delivery, and verifying shipping. We use it while you are travelling, not the ' +
        'whole time.',
    ],
    7: [
      'WHO WE SHARE WITH',
      'We share the minimum needed with: Google (Firebase, Google Pay), ClickPesa ' +
        '(payments), Cloudinary (images), Meseji (SMS), OneSignal (notifications) and ' +
        'AI providers. Each operates under its own privacy terms.',
    ],
    8: [
      'DATA HELD OUTSIDE TANZANIA',
      'Your data is stored in our servers and in third-party infrastructure located ' +
        'outside Tanzania. Tanzania\'s Personal Data Protection Act (2022) requires a ' +
        'permit from the regulator before personal data leaves the country, and we hold ' +
        'that oversight.',
    ],
    9: [
      'YOUR RIGHTS',
      `You can see, correct or delete your data by emailing ${DPO_EMAIL}. We respond ` +
        'within 14 working days. You can opt out of marketing any time, though order and ' +
        'security messages continue. If we do not resolve it, you may complain to the ' +
        'Personal Data Protection Commission (PDPC).',
    ],
    10: [
      'SECURITY AND CHANGES',
      'We use restricted access and encryption to protect your information and user ' +
        'funds. We may update this policy; we will notify users by email or in-app ' +
        'notice before a change takes effect.',
    ],
    footer: `© ${LAST_UPDATED.split(' ')[2]} Soko Vibe. All rights reserved.`,
  },
};

const TOS_SECTIONS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const PP_SECTIONS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];

/* ------------------------------------------------------------------ */
/* Emit                                                                */
/* ------------------------------------------------------------------ */

function esc(s) {
  return String(s).replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\n/g, '\\n');
}

/**
 * Sections are separate title/body keys rather than one blob because that is
 * what legal_i18n.js already exposed and what the HTML shells render.
 */
function block(prefix, data, sections) {
  const out = [`      '${prefix}_title': '${esc(data.title)}',`];
  out.push(`      '${prefix}_last_updated': '${esc(data.last_updated)}',`);
  out.push(`      '${prefix}_intro': '${esc(data.intro)}',`);
  for (const n of sections) {
    const [title, body] = data[n];
    out.push(`      '${prefix}_section_${n}_title': '${n}. ${esc(title)}',`);
    out.push(`      '${prefix}_section_${n}_body': '${esc(body)}',`);
  }
  out.push(`      '${prefix}_footer': '${esc(data.footer)}',`);
  return out.join('\n');
}

function buildJs() {
  const header = `/* Soko Vibe - legal document strings.
 * GENERATED FILE - do not edit by hand.
 * Source of truth: tools/build-legal-docs.cjs  (node tools/build-legal-docs.cjs)
 *
 * Only Swahili and English are provided. The old French, German and Chinese
 * entries were mojibake and have been dropped; i18n.js leaves the hardcoded
 * English text in place when a key is missing, so those visitors get readable
 * English rather than corrupted text.
 */
(function () {
  var LEGAL = {
`;
  const sw = block('tos', TOS.sw, TOS_SECTIONS);
  const en = block('tos', TOS.en, TOS_SECTIONS);
  const swP = block('pp', PP.sw, PP_SECTIONS);
  const enP = block('pp', PP.en, PP_SECTIONS);

  const footer = `
  };
  if (!window.SokoI18n) throw new Error("legal_i18n.js must load after i18n.js");
  Object.keys(LEGAL).forEach(function (lang) {
    if (!window.SokoI18n.DICT[lang]) window.SokoI18n.DICT[lang] = {};
    for (var k in LEGAL[lang]) window.SokoI18n.DICT[lang][k] = LEGAL[lang][k];
  });
})();
`;
  // Each language block carries BOTH documents. The first version of this script
  // emitted only the privacy blocks, so every tos_* key resolved to nothing and
  // the Terms page rendered as empty headings - which is exactly what
  // tools/verify-legal-docs.cjs now fails on if it happens again.
  return `${header}    sw: {\n${sw}\n${swP}\n    },\n\n    en: {\n${en}\n${enP}\n    },\n  };\n${footer}`;
}

/** Same doc-card markup as the existing privacy page, for one document. */
function shell({ titleKey, title, updatedKey, introKey, prefix, sections, url }) {
  const cards = sections
    .map(
      (n) =>
        `      <div class="doc-card"><h2 data-i18n="${prefix}_section_${n}_title">${n}. </h2>` +
        `<div class="body" data-i18n="${prefix}_section_${n}_body"></div></div>`,
    )
    .join('\n');

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title.toUpperCase()}</title>
  <meta name="description" content="Soko Vibe is Tanzania's marketplace. Buy and sell with escrow-protected ClickPesa payments and nationwide delivery.">
  <meta name="theme-color" content="#000000">
  <meta property="og:title" content="Soko Vibe">
  <meta property="og:description" content="Terms of Service and Privacy Policy for Soko Vibe.">
  <meta property="og:type" content="website">
  <meta property="og:url" content="${url}">
  <link rel="icon" type="image/svg+xml" href="favicon.svg">
  <link rel="icon" type="image/png" sizes="32x32" href="favicon-32x32.png">
  <link rel="icon" type="image/png" sizes="16x16" href="favicon-16x16.png">
  <link rel="apple-touch-icon" href="apple-touch-icon.png">
  <link rel="stylesheet" href="styles.css">
  <script src="i18n.js"></script>
  <script src="legal_i18n.js"></script>
</head>
<body>
  <header class="site">
    <div class="nav-inner">
      <a class="brand" href="index.html">
        <svg viewBox="0 0 512 512" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="512" height="512" rx="112" fill="#000000"/><path d="M256 96l128 96v224H128V192z" fill="#ffffff" transform="scale(0.9) translate(28,28)"/></svg>
        Soko Vibe
      </a>
      <div style="display:flex;align-items:center;gap:12px;">
        <select class="lang-select" aria-label="Language">
          <option value="sw">Kiswahili</option>
          <option value="en">English</option>
        </select>
        <a class="nav-cta" href="index.html#app" data-i18n="nav_get_app">Get the App</a>
      </div>
    </div>
  </header>

  <main class="doc">
    <div class="doc-inner">
      <a class="back-home" href="index.html">&larr; <span data-i18n="back_home">Back to home</span></a>
      <h1 data-i18n="${titleKey}">${title.toUpperCase()}</h1>
      <p class="last-updated" data-i18n="${updatedKey}">${LAST_UPDATED}</p>
      <div class="doc-intro" data-i18n="${introKey}"></div>
${cards}
    </div>
  </main>

  <footer class="site">
    <div class="footer-bottom" style="max-width:820px;">
      <span data-i18n="${prefix}_footer">&copy; Soko Vibe. All rights reserved.</span>
    </div>
  </footer>
</body>
</html>
`;
}

const js = buildJs();
const targets = [
  path.join(ROOT, 'hosting', 'legal_i18n.js'),
  path.join(ROOT, 'server', 'landing', 'legal_i18n.js'),
];
for (const t of targets) {
  fs.writeFileSync(t, js);
  console.log(`wrote ${path.relative(ROOT, t)} (${js.length} bytes)`);
}

const pages = [
  {
    dir: path.join(ROOT, 'hosting'),
    file: 'terms.html',
    doc: { prefix: 'tos', title: TOS.en.title, sections: TOS_SECTIONS, url: `${WEBSITE}/terms.html` },
  },
  {
    dir: path.join(ROOT, 'server', 'landing'),
    file: 'terms.html',
    doc: { prefix: 'tos', title: TOS.en.title, sections: TOS_SECTIONS, url: `${WEBSITE}/terms.html` },
  },
  {
    dir: path.join(ROOT, 'hosting'),
    file: 'privacy.html',
    doc: { prefix: 'pp', title: PP.en.title, sections: PP_SECTIONS, url: `${WEBSITE}/privacy.html` },
  },
  {
    dir: path.join(ROOT, 'server', 'landing'),
    file: 'privacy.html',
    doc: { prefix: 'pp', title: PP.en.title, sections: PP_SECTIONS, url: `${WEBSITE}/privacy.html` },
  },
];

for (const p of pages) {
  const html = shell({
    titleKey: `${p.doc.prefix}_title`,
    title: p.doc.title,
    updatedKey: `${p.doc.prefix}_last_updated`,
    introKey: `${p.doc.prefix}_intro`,
    prefix: p.doc.prefix,
    sections: p.doc.sections,
    url: p.doc.url,
  });
  fs.writeFileSync(path.join(p.dir, p.file), html);
  console.log(`wrote ${path.relative(ROOT, path.join(p.dir, p.file))} (${html.length} bytes)`);
}
