'use strict';

const { t, icon } = require('../core');
const {
  pageMeta, layout, pageHero, sectionHead, featureCard, waitlistForm, ctaSection, statusBadge,
} = require('../components');
const seo = require('../seo');

const BUYER_FEATURES = [
  {
    iconName: 'search',
    title: { sw: 'Pata unachokitafuta', en: 'Find what you need' },
    text: { sw: 'Tafuta kwa kategoria, eneo au maelezo na upate matokeo yanayofaa badala ya orodha isiyo na mwisho.', en: 'Search by category, location or description and get relevant results instead of an endless list.' },
    status: 'dev',
  },
  {
    iconName: 'user',
    title: { sw: 'Jua unayenunua kutoka kwake', en: 'Know who you are buying from' },
    text: { sw: 'Wasifu wa muuza unaonyesha bidhaa, maelezo na hali ya uthibitisho.', en: 'Seller profiles show products, details and verification status.' },
    status: 'dev',
  },
  {
    iconName: 'video',
    title: { sw: 'Ona bidhaa vizuri', en: 'See the product properly' },
    text: { sw: 'Picha na video husaidia kuelewa bidhaa kabla ya kuamua.', en: 'Photos and video help you understand a product before deciding.' },
    status: 'dev',
  },
  {
    iconName: 'shield',
    title: { sw: 'Lipa kwa ujasiri', en: 'Pay with confidence' },
    text: { sw: 'Mchakato wa malipo unaolinda mnunuzi na muuza unaendelezwa kwa uangalifu.', en: 'A payment flow that protects buyer and seller is being built carefully.' },
    status: 'dev',
  },
];

const UPCOMING = [
  { sw: 'Vipendwa na orodha za ununuzi', en: 'Favourites and shopping lists', status: 'dev' },
  { sw: 'Maombi ya bidhaa kwa wauzaji', en: 'Product requests to sellers', status: 'planned' },
  { sw: 'Ufuatiliaji wa oda kwa hatua', en: 'Step-by-step order tracking', status: 'dev' },
  { sw: 'Mapendekezo yanayobinafsishwa', en: 'Personalised recommendations', status: 'planned' },
  { sw: 'Njia za usafirishaji kanda mbalimbali', en: 'Delivery options across regions', status: 'planned' },
  { sw: 'Mazungumzo salama na muuza', en: 'Safe conversations with sellers', status: 'dev' },
];

function buyersPage() {
  const title = 'Kwa Wanunuzi | Soko Vibe for Buyers';
  const description = 'Gundua uzoefu wa mnunuzi kwenye Soko Vibe: ugunduzi rahisi, wasifu wa wauzaji, maudhui ya bidhaa na malipo yanayolindwa. Jiunge na orodha ya uzinduzi.';
  const meta = pageMeta({
    title,
    description,
    path: '/buyers',
    jsonLd: [
      seo.webpage({ path: '/buyers', title, description }),
      seo.breadcrumbs([{ name: 'Mwanzo', path: '/' }, { name: 'Wanunuzi', path: '/buyers' }]),
    ],
  });

  const body = `${pageHero({
    eyebrow: { sw: 'Kwa wanunuzi', en: 'For buyers' },
    title: { sw: 'Nunua kwa ujasiri. Elewa unachonunua.', en: 'Shop with confidence. Understand what you are buying.' },
    lead: { sw: 'Soko Vibe linajengwa ili ugunduzi uwe rahisi, maelezo yawe wazi, na malipo yawe na ulinzi kwa pande zote.', en: 'Soko Vibe is being built so discovery is simple, product details are clear, and payments protect both sides.' },
    breadcrumb: 'Wanunuzi',
    actions: `<a class="sv-btn sv-btn--primary" href="#buyer-waitlist" data-en="Join as a buyer">Jiunge kama mnunuzi</a><a class="sv-btn sv-btn--ghost" href="/how-it-works" data-en="See the journey">Ona safari</a>`,
  })}

<section class="sv-section">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Kile tunachojenga', en: 'What we are building' },
      title: { sw: 'Uzoefu unaokusaidia kuamua kwa uhakika.', en: 'An experience that helps you decide with confidence.' },
      lead: { sw: 'Vipengele vya mnunuzi vinaendelezwa. Hatuwasilishi kama huduma iliyokwisha.', en: 'Buyer features are in development. We do not present them as a finished service.' },
    })}
    <div class="sv-grid sv-grid--2">
      ${BUYER_FEATURES.map((item) => featureCard(item)).join('\n')}
    </div>
  </div>
</section>

<section class="sv-section sv-section--tint">
  <div class="sv-container sv-split">
    <div class="sv-split__copy">
      ${t('p', 'Safari yako', 'Your journey', { class: 'sv-eyebrow' })}
      ${t('h2', 'Hatua nne rahisi, kuanzia utafutaji hadi upokeaji.', 'Four simple steps, from search to receipt.', { class: 'sv-h2' })}
      <ol class="sv-numbered">
        <li><b>01</b><div>${t('h3', 'Tafuta', 'Search')}${t('p', 'Tumia neno, kategoria au eneo kupata bidhaa zinazofaa.', 'Use a keyword, category or location to find relevant products.')}</div></li>
        <li><b>02</b><div>${t('h3', 'Linganisha', 'Compare')}${t('p', 'Tazama bei, maelezo, picha na wasifu wa muuza.', 'Review price, details, photos and the seller profile.')}</div></li>
        <li><b>03</b><div>${t('h3', 'Uliza', 'Ask')}${t('p', 'Wasiliana na muuza kuhusu ukubwa, hali na usafirishaji.', 'Contact the seller about size, condition and delivery.')}</div></li>
        <li><b>04</b><div>${t('h3', 'Pokea', 'Receive')}${t('p', 'Fuatilia oda na uthibitishe upokeaji kabla ya malipo kuachiliwa.', 'Track the order and confirm receipt before funds are released.')}</div></li>
      </ol>
    </div>
    <div class="sv-split__aside">
      <div class="sv-statcard"><span class="sv-statcard__icon">${icon('message')}</span>${t('h3', 'Mazungumzo, si dhana', 'Conversation, not guesswork', { class: 'sv-h3' })}${t('p', 'Muuza anapaswa kujibu maswali muhimu kabla hujalipa. Tunapanga mazungumzo yabaki kwenye rekodi.', 'A seller should answer the important questions before you pay. We plan to keep conversations on record.')}</div>
      <div class="sv-statcard"><span class="sv-statcard__icon">${icon('pin')}</span>${t('h3', 'Kwa maeneo yote', 'For every region', { class: 'sv-h3' })}${t('p', 'Tunazingatia mahitaji ya wanunuzi mijini na vijijini, kwa mtandao wa kawaida.', 'We are designing for urban and rural buyers, on ordinary networks.')}</div>
    </div>
  </div>
</section>

<section class="sv-section">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Inakuja', en: 'Coming' },
      title: { sw: 'Vipengele vya mnunuzi vinavyoendelezwa', en: 'Buyer features in the works' },
      lead: { sw: 'Orodha hii inaonyesha kile kinachofuata. Vipengele vinavyoendelezwa havipatikani bado.', en: 'This list shows what comes next. Features in development are not available yet.' },
    })}
    <div class="sv-grid sv-grid--3">
      ${UPCOMING.map((item) => `<article class="sv-mini">
        <div class="sv-mini__top">${statusBadge(item.status)}</div>
        ${t('h3', item.sw, item.en)}
      </article>`).join('\n')}
    </div>
  </div>
</section>

<section class="sv-waitlist-section" id="buyer-waitlist">
  <div class="sv-container sv-waitlist-section__inner">
    <div>
      ${t('p', 'Orodha ya wanunuzi', 'Buyer list', { class: 'sv-eyebrow' })}
      ${t('h2', 'Kuwa mmoja wa wanunuzi wa kwanza.', 'Be one of the first buyers.', { class: 'sv-h2' })}
      ${t('p', 'Jiunge na orodha ya uzinduzi kama mnunuzi. Tutakutumia taarifa moja tutakapozindua — hakuna barua taka.', 'Join the launch list as a buyer. We will send one update when we launch — no spam.', { class: 'sv-lead' })}
      <ul class="sv-checks">
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Barua pepe moja ya uzinduzi', 'One launch email')}</li>
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Unaweza kujiondoa wakati wowote', 'Unsubscribe anytime')}</li>
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Data yako haitauzwa', 'Your data is not sold')}</li>
      </ul>
    </div>
    <div class="sv-waitlist-section__form">
      ${waitlistForm({ id: 'buyers', source: 'buyers_page', defaultType: 'buyer' })}
    </div>
  </div>
</section>

${ctaSection({
  title: { sw: 'Soko bora linaanza na wanunuzi wake.', en: 'A better marketplace starts with its buyers.' },
  lead: { sw: 'Jiunge na orodha ya uzinduzi na tusikilize kile unachohitaji.', en: 'Join the launch list and tell us what you need.' },
})}`;

  return { file: 'buyers.html', html: layout({ meta, active: '/buyers', body }) };
}

module.exports = { buyersPage };
