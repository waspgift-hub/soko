'use strict';

const { SITE, t, icon } = require('../core');
const {
  pageMeta, layout, sectionHead, featureCard, step, accordion, waitlistForm, ctaSection,
} = require('../components');
const seo = require('../seo');

const HIGHLIGHTS = [
  {
    iconName: 'search',
    title: { sw: 'Ugunduzi rahisi', en: 'Simple discovery' },
    text: { sw: 'Tafuta bidhaa na huduma kwa kategoria, eneo na kile unachokihitaji — bila kupotea kwenye orodha ndefu.', en: 'Find products and services by category, location and need — without getting lost in endless lists.' },
    status: 'dev',
  },
  {
    iconName: 'store',
    title: { sw: 'Wasifu wa wauzaji', en: 'Seller profiles' },
    text: { sw: 'Fahamu nani anauza, ana bidhaa gani na ana historia gani kabla ya kuamua kununua.', en: 'See who is selling, what they offer and their history before you decide to buy.' },
    status: 'dev',
  },
  {
    iconName: 'video',
    title: { sw: 'Video na picha za bidhaa', en: 'Product video and photos' },
    text: { sw: 'Wauzaji wataweza kuonyesha bidhaa kwa video na picha halisi, si maandishi pekee.', en: 'Sellers will be able to show products with real video and photos, not text alone.' },
    status: 'dev',
  },
  {
    iconName: 'chat',
    title: { sw: 'Mazungumzo ndani ya app', en: 'In-app conversations' },
    text: { sw: 'Uliza maswali, jadiliana bei na kufuatilia mazungumzo mahali pamoja.', en: 'Ask questions, discuss details and keep conversations in one place.' },
    status: 'dev',
  },
  {
    iconName: 'shield',
    title: { sw: 'Malipo yaliyolindwa', en: 'Protected payments' },
    text: { sw: 'Tunajenga mchakato wa malipo unaolinda mnunuzi na muuza hadi bidhaa inapokamilika.', en: 'We are building a payment flow that protects both buyer and seller until the order is complete.' },
    status: 'dev',
  },
  {
    iconName: 'sparkles',
    title: { sw: 'Uzoefu wenye akili', en: 'Smarter experience' },
    text: { sw: 'Mapendekezo na utafutaji unaokusaidia kupata bidhaa zinazofaa — tukikamilisha vipengele hivi.', en: 'Recommendations and search that help you find relevant products as we complete these features.' },
    status: 'planned',
  },
];

const HOME_FAQ = [
  {
    q: 'Soko Vibe ni nini?',
    a: 'Soko Vibe ni soko la mtandaoni la Tanzania linalojengwa kwa ajili ya wanunuzi na wauzaji. Lengo ni kuunganisha bidhaa, huduma, wauzaji na wanunuzi kwenye uzoefu mmoja rahisi na salama.',
    enQ: 'What is Soko Vibe?',
    enA: 'Soko Vibe is a Tanzanian online marketplace being built for buyers and sellers. The goal is to bring products, services, sellers and buyers together in one simple, safer experience.',
  },
  {
    q: 'Je, app ya Soko Vibe inapatikana sasa?',
    a: 'Hapana. App bado inaendelezwa. Tovuti hii inaelezea kile tunachojenga, na orodha ya uzinduzi ndiyo njia ya kupata taarifa tutakapozindua.',
    enQ: 'Is the Soko Vibe app available now?',
    enA: 'No. The app is still in development. This website explains what we are building, and the launch list is how you will hear when we launch.',
  },
  {
    q: 'Je, kujiunga na orodha ya uzinduzi kunanigharimu?',
    a: 'Hapana. Kujiunga ni bure. Tunatumia barua pepe yako pekee kukutumia taarifa za uzinduzi, na unaweza kujiondoa wakati wowote.',
    enQ: 'Does joining the launch list cost anything?',
    enA: 'No. Joining is free. We use your email only to send launch updates, and you can unsubscribe at any time.',
  },
  {
    q: 'Nitapokea barua pepe ngapi?',
    a: 'Tunalenga barua pepe chache zenye maana — taarifa ya uzinduzi na masasisho muhimu. Hatutuma barua taka.',
    enQ: 'How many emails will I receive?',
    enA: 'We aim to send few, meaningful emails — a launch update and important news. We do not send spam.',
  },
  {
    q: 'Soko Vibe inapatikana wapi?',
    a: 'Soko Vibe inajengwa kwa ajili ya Tanzania. Tunazingatia mazingira ya simu, mtandao wa mkononi na malipo ya mobile money yanayotumika nchini.',
    enQ: 'Where is Soko Vibe available?',
    enA: 'Soko Vibe is being built for Tanzania. We are designing for mobile-first use, local networks and the mobile money payments people already use.',
  },
];

function phonePreview() {
  return `<div class="sv-preview" role="img" aria-label="Mchoro wa dhana wa kiolesura cha Soko Vibe: utafutaji, kategoria na kadi za bidhaa" data-en-aria-label="Concept illustration of the Soko Vibe interface: search, categories and product cards">
  <div class="sv-phone">
    <div class="sv-phone__bar"><span></span><span></span><span></span></div>
    <div class="sv-phone__screen">
      <div class="sv-phone__top">
        <span class="sv-phone__logo">Soko Vibe</span>
        <span class="sv-phone__dot" aria-hidden="true"></span>
      </div>
      <div class="sv-phone__search">${icon('search', 'sv-icon--sm')}<span>Tafuta bidhaa…</span></div>
      <div class="sv-phone__chips">
        <span class="is-on">Zote</span><span>Mavazi</span><span>Elektroniki</span><span>Nyumbani</span>
      </div>
      <div class="sv-phone__grid">
        <div class="sv-phone__card"><div class="sv-phone__img sv-phone__img--a">${icon('bag')}</div><b>TSH 45,000</b><i>Dar es Salaam</i></div>
        <div class="sv-phone__card"><div class="sv-phone__img sv-phone__img--b">${icon('video')}</div><b>TSH 120,000</b><i>Arusha</i></div>
        <div class="sv-phone__card"><div class="sv-phone__img sv-phone__img--c">${icon('store')}</div><b>TSH 18,500</b><i>Mwanza</i></div>
        <div class="sv-phone__card"><div class="sv-phone__img sv-phone__img--d">${icon('sparkles')}</div><b>TSH 65,000</b><i>Dodoma</i></div>
      </div>
      <div class="sv-phone__nav" aria-hidden="true"><span class="is-on">${icon('bag')}</span><span>${icon('search')}</span><span>${icon('heart')}</span><span>${icon('user')}</span></div>
    </div>
  </div>
  <p class="sv-preview__note">${icon('sparkles', 'sv-icon--sm')} <span data-en="Concept illustration — the app is in development.">Mchoro wa dhana — app bado inatengenezwa.</span></p>
</div>`;
}

function hero() {
  return `<section class="sv-hero">
  <div class="sv-container sv-hero__inner">
    <div class="sv-hero__copy">
      <p class="sv-pill"><span class="sv-dot" aria-hidden="true"></span> <span data-en="Soko Vibe is in development">Soko Vibe iko kwenye maendeleo</span></p>
      ${t('h1', 'Gundua njia mpya ya kununua na kuuza Tanzania.', 'Discover a new way to buy and sell in Tanzania.', { class: 'sv-display' })}
      ${t('p', 'Soko Vibe linajenga soko la kidijitali lenye akili zaidi linalounganisha wanunuzi, wauzaji, bidhaa na huduma kwenye uzoefu mmoja rahisi.', 'Soko Vibe is building a smarter marketplace that brings buyers, sellers, products and services together in one simple experience.', { class: 'sv-hero__lead' })}
      <div class="sv-actions">
        <a class="sv-btn sv-btn--primary sv-btn--lg" href="#waitlist" data-en="Get early access">Pata ufikiaji wa mapema</a>
        <a class="sv-btn sv-btn--ghost sv-btn--lg" href="/features" data-en="Explore Soko Vibe">Chunguza Soko Vibe</a>
      </div>
      ${t('p', 'Soko Vibe bado linatengenezwa. Jiunge na orodha ya uzinduzi uwe wa kwanza kujua tutakapozindua.', 'Soko Vibe is currently under development. Join our launch list and be among the first to know when we launch.', { class: 'sv-hero__note' })}
      <ul class="sv-hero__facts">
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Imejengwa Tanzania', 'Built for Tanzania')}</li>
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Kwa simu kwanza', 'Mobile-first')}</li>
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Bila barua taka', 'No spam')}</li>
      </ul>
    </div>
    <div class="sv-hero__visual">${phonePreview()}</div>
  </div>
</section>`;
}

function homePage() {
  const title = 'Soko Vibe — Soko la Mtandaoni Tanzania | Tanzania Online Marketplace';
  const description = 'Soko Vibe ni soko la mtandaoni la Tanzania linalojengwa kwa wanunuzi na wauzaji. Jiunge na orodha ya uzinduzi kupata taarifa za kwanza.';
  const meta = pageMeta({
    title,
    description,
    path: '/',
    jsonLd: [
      seo.organization(),
      seo.website(),
      seo.webpage({ path: '/', title, description }),
    ],
  });

  const body = `${hero()}

<section class="sv-strip" aria-label="Kile tunachojenga" data-en-aria-label="What we are building">
  <div class="sv-container sv-strip__inner">
    <div><strong data-en="One place">Mahali pamoja</strong><span data-en="Products, services and sellers">Bidhaa, huduma na wauzaji</span></div>
    <div><strong data-en="Local by design">Kwa mazingira ya Tanzania</strong><span data-en="Mobile money, mobile networks, local needs">Mobile money, mtandao wa simu, mahitaji ya hapa</span></div>
    <div><strong data-en="Trust first">Uaminifu kwanza</strong><span data-en="Verification and protected payments in development">Uthibitisho na malipo yaliyolindwa vinaendelezwa</span></div>
  </div>
</section>

<section class="sv-section" id="kuhusu">
  <div class="sv-container sv-split">
    <div class="sv-split__copy">
      ${t('p', 'Soko Vibe ni nini?', 'What is Soko Vibe?', { class: 'sv-eyebrow' })}
      ${t('h2', 'Soko la kijamii na biashara linalojengwa kwa Tanzania.', 'A social-commerce marketplace being built for Tanzania.', { class: 'sv-h2' })}
      ${t('p', 'Soko Vibe ni jukwaa la kidijitali linalounganisha wanunuzi na wauzaji kote Tanzania. Tunalenga kuunganisha ugunduzi wa bidhaa, mazungumzo na biashara kwenye uzoefu mmoja unaoeleweka kwa urahisi — kuanzia simu ya mkononi.', 'Soko Vibe is a digital platform connecting buyers and sellers across Tanzania. We aim to bring product discovery, conversation and commerce into one experience that is easy to understand — starting on a phone.', { class: 'sv-lead' })}
      ${t('p', 'Tovuti hii inaelezea kile tunachojenga. App bado iko kwenye maendeleo, kwa hiyo tunaeleza vipengele kwa uwazi: kile kinachopatikana leo, kile kinachoendelezwa na kile kilichopangwa.', 'This website explains what we are building. The app is still in development, so we describe every feature honestly: what is available today, what is in progress and what is planned.', { class: 'sv-muted' })}
      <a class="sv-link" href="/about">${t('span', 'Soma kuhusu dhamira yetu', 'Read about our mission')} ${icon('arrow', 'sv-icon--sm')}</a>
    </div>
    <div class="sv-split__aside">
      <div class="sv-statcard">
        <span class="sv-statcard__icon">${icon('pin')}</span>
        ${t('h3', 'Tanzania ndio msingi', 'Tanzania first', { class: 'sv-h3' })}
        ${t('p', 'Tunajenga kwa ajili ya wanunuzi na wauzaji wa Tanzania: lugha, malipo na tabia za soko la hapa.', 'We are building for Tanzanian buyers and sellers: language, payments and the habits of this market.')}
      </div>
      <div class="sv-statcard">
        <span class="sv-statcard__icon">${icon('scale')}</span>
        ${t('h3', 'Uwazi wa maendeleo', 'Honest status', { class: 'sv-h3' })}
        ${t('p', 'Kila kipengele kinaonyeshwa na hali yake. Hatuwasilishi kipengele ambacho hakijakamilika kama huduma iliyokwisha.', 'Every feature shows its status. We never present unfinished work as a live service.')}
      </div>
    </div>
  </div>
</section>

<section class="sv-section sv-section--tint" id="sifa">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Kile tunachojenga', en: 'What we are building' },
      title: { sw: 'Vipengele vinavyounda uzoefu wa Soko Vibe', en: 'The features shaping the Soko Vibe experience' },
      lead: { sw: 'Hizi ni sehemu za bidhaa tunazojenga. Kila kadi inaonyesha hali yake ya maendeleo.', en: 'These are the parts of the product we are building. Every card shows its development status.' },
      center: true,
    })}
    <div class="sv-grid sv-grid--3">
      ${HIGHLIGHTS.map((item) => featureCard(item)).join('\n')}
    </div>
    <div class="sv-center">
      <a class="sv-btn sv-btn--ghost" href="/features" data-en="See all features">Ona vipengele vyote</a>
    </div>
  </div>
</section>

<section class="sv-section" id="jinsi">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Jinsi inavyofanya kazi', en: 'How it works' },
      title: { sw: 'Hatua tatu, uzoefu mmoja rahisi', en: 'Three steps, one simple experience' },
      lead: { sw: 'Tunapanga safari ya ununuzi na uuzaji iwe wazi kuanzia mwanzo hadi mwisho.', en: 'We are designing the buying and selling journey to be clear from start to finish.' },
    })}
    <ol class="sv-steps">
      ${step({
        number: '01', iconName: 'search',
        title: { sw: 'Gundua', en: 'Discover' },
        text: { sw: 'Tafuta bidhaa na huduma, chunguza kategoria na ugundue wauzaji wapya Tanzania.', en: 'Find products and services, explore categories and discover new sellers across Tanzania.' },
      })}
      ${step({
        number: '02', iconName: 'chat',
        title: { sw: 'Ungana', en: 'Connect' },
        text: { sw: 'Tazama wasifu wa muuza, uliza maswali na jadiliana maelezo muhimu kabla ya kuamua.', en: 'View the seller profile, ask questions and agree the important details before deciding.' },
      })}
      ${step({
        number: '03', iconName: 'bag',
        title: { sw: 'Nunua au uza', en: 'Shop or sell' },
        text: { sw: 'Tumia uzoefu wa marketplace pale tunapozindua — kwa malipo na ulinzi unaoendelezwa kwa uangalifu.', en: 'Use the marketplace experience when we launch — with payments and protection being built carefully.' },
      })}
    </ol>
    <div class="sv-center"><a class="sv-link" href="/how-it-works">${t('span', 'Angalia mchakato kamili', 'See the full journey')} ${icon('arrow', 'sv-icon--sm')}</a></div>
  </div>
</section>

<section class="sv-section sv-section--tint" id="wanunuzi">
  <div class="sv-container sv-split sv-split--reverse">
    <div class="sv-split__panel sv-panel--buyer">
      <span class="sv-split__badge">${icon('bag')} <span data-en="For buyers">Kwa wanunuzi</span></span>
      <div class="sv-mini-list">
        <div><span>${icon('search', 'sv-icon--sm')}</span><p data-en="Find what you need by category, location and description.">Pata unachokihitaji kwa kategoria, eneo na maelezo.</p></div>
        <div><span>${icon('chat', 'sv-icon--sm')}</span><p data-en="Ask sellers questions before you commit.">Uliza wauzaji maswali kabla ya kuamua.</p></div>
        <div><span>${icon('shield', 'sv-icon--sm')}</span><p data-en="A payment flow designed to protect both sides.">Mchakato wa malipo ulioundwa kulinda pande zote.</p></div>
      </div>
    </div>
    <div class="sv-split__copy">
      ${t('p', 'Kwa wanunuzi', 'For buyers', { class: 'sv-eyebrow' })}
      ${t('h2', 'Nunua kwa ujasiri zaidi.', 'Shop with more confidence.', { class: 'sv-h2' })}
      ${t('p', 'Tunajenga uzoefu unaokusaidia kuelewa unachonunua, kujua unayenunua kutoka kwake na kufuatilia mchakato hadi mwisho. Hakuna kupotea kwenye orodha ndefu, hakuna kubahatisha.', 'We are building an experience that helps you understand what you are buying, who you are buying from, and how the order is progressing. No getting lost in endless lists, no guessing.', { class: 'sv-lead' })}
      <a class="sv-btn sv-btn--primary" href="/buyers" data-en="Explore the buyer experience">Chunguza uzoefu wa mnunuzi</a>
    </div>
  </div>
</section>

<section class="sv-section" id="wauzaji">
  <div class="sv-container sv-split">
    <div class="sv-split__panel sv-panel--seller">
      <span class="sv-split__badge">${icon('store')} <span data-en="For sellers">Kwa wauzaji</span></span>
      <div class="sv-mini-list">
        <div><span>${icon('user', 'sv-icon--sm')}</span><p data-en="Build a seller profile that shows who you are.">Jenga wasifu wa muuza unaoonyesha wewe ni nani.</p></div>
        <div><span>${icon('video', 'sv-icon--sm')}</span><p data-en="Present products with photos and video.">Wasilisha bidhaa kwa picha na video.</p></div>
        <div><span>${icon('tag', 'sv-icon--sm')}</span><p data-en="Manage listings and orders in one place.">Simamia bidhaa na oda mahali pamoja.</p></div>
      </div>
    </div>
    <div class="sv-split__copy">
      ${t('p', 'Kwa wauzaji', 'For sellers', { class: 'sv-eyebrow' })}
      ${t('h2', 'Onyesha bidhaa zako kwa uwazi zaidi.', 'Show your products more clearly.', { class: 'sv-h2' })}
      ${t('p', 'Soko Vibe inalenga kuwapa wauzaji mahali pazuri pa kuwasilisha bidhaa, kujenga wasifu na kufikia wanunuzi wanaotafuta kile wanachouza. Hatua kwa hatua, kwa zana zinazoeleweka.', 'Soko Vibe aims to give sellers a better place to present products, build a profile and reach buyers who are looking for what they sell. Step by step, with tools that make sense.', { class: 'sv-lead' })}
      <a class="sv-btn sv-btn--primary" href="/sellers" data-en="Explore seller tools">Chunguza zana za muuza</a>
    </div>
  </div>
</section>

<section class="sv-section sv-section--dark" id="trust">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Uaminifu na usalama', en: 'Trust and safety' },
      title: { sw: 'Tunajenga uaminifu kwa uangalifu, si kwa matangazo.', en: 'We are building trust carefully, not advertising it.' },
      lead: { sw: 'Vipengele vya usalama vinaendelezwa. Hapa tunaeleza kile kinachoundwa na kile ambacho hakijakamilika bado.', en: 'Our safety features are in development. Here is what is being built and what is not finished yet.' },
      center: true,
    })}
    <div class="sv-grid sv-grid--4">
      <div class="sv-trust"><span>${icon('shield')}</span>${t('h3', 'Malipo yaliyolindwa', 'Protected payments')}${t('p', 'Mchakato wa escrow unaoendelezwa ili fedha zisitolewe kabla ya makubaliano kutimizwa.', 'An escrow flow in development so funds are not released before the agreed outcome.')}</div>
      <div class="sv-trust"><span>${icon('user')}</span>${t('h3', 'Uthibitisho wa wauzaji', 'Seller verification')}${t('p', 'Uthibitisho wa utambulisho (KYC) kwa wauzaji unaendelezwa kabla ya uzinduzi.', 'Identity verification (KYC) for sellers is being developed ahead of launch.')}</div>
      <div class="sv-trust"><span>${icon('chat')}</span>${t('h3', 'Mazungumzo ya wazi', 'Clear communication')}${t('p', 'Mazungumzo ndani ya app yanapangwa ili maagreement yabaki kwenye rekodi.', 'In-app conversations are planned so agreements stay on the record.')}</div>
      <div class="sv-trust"><span>${icon('lock')}</span>${t('h3', 'Faragha kwa msingi', 'Privacy by design')}${t('p', 'Tunakusanya data ndogo tu inayohitajika, na tunaeleza matumizi yake wazi.', 'We collect only the data we need, and we explain how it is used.')}</div>
    </div>
    <p class="sv-disclaimer">${icon('document', 'sv-icon--sm')} ${t('span', 'Hakuna huduma ya malipo, escrow au uthibitisho inayotangazwa kama inapatikana leo. Hali kamili imeelezwa kwenye ukurasa wa vipengele.', 'No payment, escrow or verification service is advertised as available today. Full status is listed on the features page.')}</p>
    <div class="sv-center"><a class="sv-link sv-link--light" href="/features#trust">${t('span', 'Angalia hali ya usalama', 'See the security status')} ${icon('arrow', 'sv-icon--sm')}</a></div>
  </div>
</section>

<section class="sv-section" id="hali">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Uwazi', en: 'Transparency' },
      title: { sw: 'Nini kinapatikana, nini kinaendelezwa', en: 'What is available, what is in progress' },
      lead: { sw: 'Tunapenda kuwa wazi kuhusu hatua tuliyofikia ili uamuzi wako uwe wa kweli.', en: 'We would rather be clear about where we are so your decision is based on facts.' },
    })}
    <div class="sv-statusboard">
      <div class="sv-statusboard__col sv-statusboard__col--live">
        <h3>${icon('check', 'sv-icon--sm')} <span data-en="Available today">Inapatikana leo</span></h3>
        <ul>
          <li data-en="This website and all information pages">Tovuti hii na kurasa zote za taarifa</li>
          <li data-en="The launch waitlist">Orodha ya uzinduzi</li>
          <li data-en="The contact form and support email">Fomu ya mawasiliano na barua pepe ya msaada</li>
        </ul>
      </div>
      <div class="sv-statusboard__col sv-statusboard__col--dev">
        <h3>${icon('refresh', 'sv-icon--sm')} <span data-en="In development">Inaendelezwa</span></h3>
        <ul>
          <li data-en="The Soko Vibe mobile app">App ya simu ya Soko Vibe</li>
          <li data-en="Seller profiles, listings and product media">Wasifu wa wauzaji, bidhaa na maudhui ya bidhaa</li>
          <li data-en="Protected payments and seller verification">Malipo yaliyolindwa na uthibitisho wa wauzaji</li>
        </ul>
      </div>
      <div class="sv-statusboard__col sv-statusboard__col--planned">
        <h3>${icon('sparkles', 'sv-icon--sm')} <span data-en="Planned">Imepangwa</span></h3>
        <ul>
          <li data-en="AI-assisted discovery and recommendations">Ugunduzi na mapendekezo yanayosaidiwa na AI</li>
          <li data-en="Delivery coordination across regions">Uratibu wa usafirishaji kanda mbalimbali</li>
          <li data-en="Expanded buyer and seller tools">Zana zaidi za wanunuzi na wauzaji</li>
        </ul>
      </div>
    </div>
  </div>
</section>

<section class="sv-section sv-section--tint" id="maswali">
  <div class="sv-container sv-faq-preview">
    ${sectionHead({
      eyebrow: { sw: 'Maswali', en: 'FAQ' },
      title: { sw: 'Maswali ya kawaida', en: 'Common questions' },
      lead: { sw: 'Majibu mafupi kuhusu Soko Vibe na uzinduzi wake.', en: 'Short answers about Soko Vibe and its launch.' },
    })}
    ${accordion(HOME_FAQ.map((item) => ({ sw: { q: item.q, a: item.a }, en: { q: item.enQ, a: item.enA } })), 'home-faq')}
    <a class="sv-link" href="/faq">${t('span', 'Soma maswali yote', 'Read all questions')} ${icon('arrow', 'sv-icon--sm')}</a>
  </div>
</section>

${ctaSection({
  title: { sw: 'Kuwa sehemu ya safari ya Soko Vibe.', en: 'Be part of the Soko Vibe journey.' },
  lead: { sw: 'Jiunge na orodha ya ufikiaji wa mapema na upokee taarifa tutakapozindua.', en: 'Join the early-access list and receive updates when we launch.' },
})}`;

  return { file: 'index.html', html: layout({ meta, active: '/', body }) };
}

module.exports = { homePage };
