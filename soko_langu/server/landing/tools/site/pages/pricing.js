'use strict';

const { t, icon } = require('../core');
const { pageMeta, layout, pageHero, sectionHead, accordion, ctaSection, statusBadge } = require('../components');
const seo = require('../seo');

const PLANS = [
  {
    name: 'Buyer / Normal',
    price: 'TSH 0',
    cadence: { sw: 'bure', en: 'free' },
    summary: { sw: 'Kwa wanunuzi wanaotafuta bidhaa na huduma.', en: 'For buyers looking for products and services.' },
    features: [
      { sw: 'Kuvinjari na kutafuta bidhaa', en: 'Browse and search products' },
      { sw: 'Vipendwa na maombi ya bidhaa', en: 'Favourites and buyer requests' },
      { sw: 'Mazungumzo ya msingi', en: 'Basic messaging' },
      { sw: 'Arifa za oda na akaunti', en: 'Order and account notifications' },
    ],
    cta: { sw: 'Jiunge kama mnunuzi', en: 'Join as a buyer' },
    href: '/buyers',
  },
  {
    name: 'Seller Basic',
    price: 'TSH 0',
    cadence: { sw: 'bure', en: 'free' },
    summary: { sw: 'Kwa wauzaji wanaoanza kujenga uwepo wao.', en: 'For sellers starting to build their presence.' },
    features: [
      { sw: 'Wasifu wa muuza na bidhaa', en: 'Seller profile and listings' },
      { sw: 'Usimamizi wa oda', en: 'Order management' },
      { sw: 'Ufahamu wa msingi wa biashara', en: 'Basic business insight' },
      { sw: 'Arifa na msaada wa msingi', en: 'Notifications and basic support' },
    ],
    cta: { sw: 'Sajili nia ya kuuza', en: 'Register seller interest' },
    href: '/sellers',
    featured: false,
  },
  {
    name: 'Seller Plus',
    price: 'TSH 14,900',
    cadence: { sw: 'kwa mwezi', en: 'per month' },
    summary: { sw: 'Kwa wauzaji wanaotaka zana zaidi na kipaumbele.', en: 'For sellers who want more tools and priority.' },
    features: [
      { sw: 'Kila kitu kwenye Seller Basic', en: 'Everything in Seller Basic' },
      { sw: 'Ufahamu wa kina wa mauzo', en: 'Advanced sales insight' },
      { sw: 'Msaada wa kipaumbele', en: 'Priority support' },
      { sw: 'Zana za tija na beji ya usajili', en: 'Productivity tools and a subscription badge' },
    ],
    cta: { sw: 'Jiunge na orodha', en: 'Join the list' },
    href: '/#waitlist',
    featured: true,
  },
  {
    name: 'Seller Pro',
    price: 'TSH 29,900',
    cadence: { sw: 'kwa mwezi', en: 'per month' },
    summary: { sw: 'Kwa biashara zinazokua kwa kasi zaidi.', en: 'For businesses growing faster.' },
    features: [
      { sw: 'Kila kitu kwenye Seller Plus', en: 'Everything in Seller Plus' },
      { sw: 'Viwango vya juu vya matumizi', en: 'Higher usage limits' },
      { sw: 'Ripoti za kina', en: 'Premium reporting' },
      { sw: 'Msaada wa kipaumbele', en: 'Priority support' },
    ],
    cta: { sw: 'Jiunge na orodha', en: 'Join the list' },
    href: '/#waitlist',
  },
  {
    name: 'Business',
    price: 'TSH 79,900',
    cadence: { sw: 'kwa mwezi', en: 'per month' },
    summary: { sw: 'Kwa timu na biashara zenye mahitaji zaidi.', en: 'For teams and businesses with greater needs.' },
    features: [
      { sw: 'Kila kitu kwenye Seller Pro', en: 'Everything in Seller Pro' },
      { sw: 'Zana za biashara', en: 'Business tools' },
      { sw: 'Usimamizi wa timu', en: 'Team management' },
      { sw: 'Ripoti za biashara', en: 'Business reporting' },
    ],
    cta: { sw: 'Wasiliana nasi', en: 'Contact us' },
    href: '/contact',
  },
];

const BOOSTS = [
  { name: 'Bronze', price: 'TSH 1,500', days: { sw: 'siku 3', en: '3 days' } },
  { name: 'Silver', price: 'TSH 3,000', days: { sw: 'siku 7', en: '7 days' }, popular: true },
  { name: 'Gold', price: 'TSH 10,000', days: { sw: 'siku 30', en: '30 days' } },
];

const PRICING_FAQ = [
  {
    sw: { q: 'Je, bei hizi ni za mwisho?', a: 'Bei zilizoonyeshwa zinatokana na usanidi wa sasa wa mfumo. Zinaweza kubadilika kabla ya uzinduzi, na bei halisi itakuwa wazi kwenye app wakati wa usajili.' },
    en: { q: 'Are these prices final?', a: 'The prices shown reflect the current system configuration. They may change before launch, and the price you see in the app at sign-up will be the price that applies.' },
  },
  {
    sw: { q: 'Je, mnunuzi analipa kamisheni?', a: 'Kwa sasa hakuna kamisheni ya jukwaa iliyowekwa kwenye mfumo. Watoa huduma wa mobile money wanaweza kutoza ada zao za miamala.' },
    en: { q: 'Do buyers pay a platform commission?', a: 'No platform commission is currently configured in the system. Mobile money providers may charge their own transaction fees.' },
  },
  {
    sw: { q: 'Je, nikilipa Seller Plus naanza kupata mauzo?', a: 'Hapana. Mpango wa kulipia unatoa zana na uwezo zaidi; hauhakikishi mauzo, mapato au mwonekano.' },
    en: { q: 'If I pay for Seller Plus, am I guaranteed sales?', a: 'No. A paid plan provides more tools and capacity; it does not guarantee sales, revenue or visibility.' },
  },
  {
    sw: { q: 'Je, naweza kubadilisha mpango?', a: 'Mipango inaundwa ili uweze kuanza na mpango wa bure na kubadilisha baadaye. Masharti ya mabadiliko yatakuwa wazi ndani ya app.' },
    en: { q: 'Can I change plans?', a: 'Plans are designed so you can start free and change later. Change terms will be clear inside the app.' },
  },
  {
    sw: { q: 'Je, vifurushi vya boost ni vya lazima?', a: 'Hapana. Ni vya hiari. Vinatoa mwonekano zaidi kwa bidhaa kwa muda uliochagua.' },
    en: { q: 'Are product boosts mandatory?', a: 'No. They are optional and give a product more visibility for the period you choose.' },
  },
];

function planCard(plan) {
  return `<article class="sv-plan${plan.featured ? ' sv-plan--featured' : ''}">
    ${plan.featured ? `<span class="sv-plan__flag" data-en="Popular choice">Chaguo maarufu</span>` : ''}
    <h2 class="sv-plan__name">${plan.name}</h2>
    <p class="sv-plan__price">${plan.price} <span>${t('span', plan.cadence.sw, plan.cadence.en)}</span></p>
    ${t('p', plan.summary.sw, plan.summary.en, { class: 'sv-plan__summary' })}
    <ul class="sv-checks sv-checks--tight">
      ${plan.features.map((f) => `<li>${icon('check', 'sv-icon--sm')} ${t('span', f.sw, f.en)}</li>`).join('\n      ')}
    </ul>
    <a class="sv-btn ${plan.featured ? 'sv-btn--primary' : 'sv-btn--ghost'} sv-btn--block" href="${plan.href}">${t('span', plan.cta.sw, plan.cta.en)}</a>
    <div class="sv-plan__status">${statusBadge('dev')}</div>
  </article>`;
}

function pricingPage() {
  const title = 'Bei za Soko Vibe | Soko Vibe Pricing Tanzania';
  const description = 'Bei za Soko Vibe: mpango wa mnunuzi na Seller Basic ni bure; Seller Plus TSH 14,900, Seller Pro TSH 29,900 na Business TSH 79,900 kwa mwezi. Bei za kabla ya uzinduzi.';
  const meta = pageMeta({
    title,
    description,
    path: '/pricing',
    jsonLd: [
      seo.webpage({ path: '/pricing', title, description }),
      seo.breadcrumbs([{ name: 'Mwanzo', path: '/' }, { name: 'Bei', path: '/pricing' }]),
    ],
  });

  const body = `${pageHero({
    eyebrow: { sw: 'Bei', en: 'Pricing' },
    title: { sw: 'Bei zilizo wazi, kwa mipango inayoendelezwa.', en: 'Clear pricing, for plans still in development.' },
    lead: { sw: 'Mpango wa mnunuzi na Seller Basic ni bure. Mipango ya kulipia inaongeza zana. Bei hizi ni za kabla ya uzinduzi na zinaweza kubadilika.', en: 'The buyer plan and Seller Basic are free. Paid plans add tools. These are pre-launch prices and may change.' },
    breadcrumb: 'Bei',
  })}

<section class="sv-section sv-section--tight">
  <div class="sv-container">
    <div class="sv-notice">
      ${icon('document', 'sv-icon--sm')}
      <p data-en="Soko Vibe is not open yet. Nothing on this page can be purchased today; plans are shown so you know what we are preparing.">Soko Vibe bado haijafunguliwa. Hakuna kinachoweza kununuliwa leo kwenye ukurasa huu; mipango inaonyeshwa ili ujue tunachokiandaa.</p>
    </div>
  </div>
</section>

<section class="sv-section">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Mipango', en: 'Plans' },
      title: { sw: 'Chagua mpango unaofaa mahitaji yako.', en: 'Choose the plan that fits your needs.' },
      lead: { sw: 'Mipango yote iko kwenye maendeleo. Bei zinaonyeshwa kwa TSH na hazijumuishi ada za mtoa huduma wa malipo.', en: 'All plans are in development. Prices are shown in TZS and exclude payment-provider fees.' },
      center: true,
    })}
    <div class="sv-plans">
      ${PLANS.map(planCard).join('\n')}
    </div>
  </div>
</section>

<section class="sv-section sv-section--tint" id="boost">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Kukuza bidhaa', en: 'Product boosts' },
      title: { sw: 'Vifurushi vya hiari vya mwonekano.', en: 'Optional visibility packages.' },
      lead: { sw: 'Boost inaongeza mwonekano wa bidhaa kwa muda uliochagua. Haihakikishi mauzo au nafasi maalum kwenye matokeo.', en: 'A boost gives a product more visibility for the period you choose. It does not guarantee sales or a specific ranking.' },
    })}
    <div class="sv-grid sv-grid--3">
      ${BOOSTS.map((boost) => `<article class="sv-boost${boost.popular ? ' is-popular' : ''}">
        ${boost.popular ? `<span class="sv-boost__flag" data-en="Most popular">Maarufu zaidi</span>` : ''}
        <h3>${boost.name}</h3>
        <p class="sv-boost__price">${boost.price}</p>
        <p class="sv-boost__days">${t('span', boost.days.sw, boost.days.en)}</p>
        <p class="sv-boost__note" data-en="Adds visibility to one product for the selected period.">Inaongeza mwonekano kwa bidhaa moja kwa muda uliochagua.</p>
        ${statusBadge('dev')}
      </article>`).join('\n')}
    </div>
  </div>
</section>

<section class="sv-section">
  <div class="sv-container sv-split">
    <div class="sv-split__copy">
      ${t('p', 'Ada na kamisheni', 'Fees and commission', { class: 'sv-eyebrow' })}
      ${t('h2', 'Hakuna kamisheni ya jukwaa iliyowekwa kwa sasa.', 'No platform commission is configured today.', { class: 'sv-h2' })}
      ${t('p', 'Usanidi wa sasa wa mfumo hauweki kamisheni ya jukwaa. Watoa huduma wa mobile money wanaweza kutoza ada zao za miamala, na ada hizo hazidhibitiwi na Soko Vibe. Kama kamisheni itawekwa baadaye, itaonyeshwa wazi kabla ya malipo kukamilika.', 'The current system configuration does not set a platform commission. Mobile money providers may charge their own transaction fees, and those fees are not controlled by Soko Vibe. If a commission is introduced later, it will be shown clearly before a payment is completed.')}
      <div class="sv-actions">
        <a class="sv-btn sv-btn--ghost" href="/faq" data-en="Read pricing questions">Soma maswali ya bei</a>
        <a class="sv-btn sv-btn--ghost" href="/contact" data-en="Ask about pricing">Uliza kuhusu bei</a>
      </div>
    </div>
    <div class="sv-split__aside">
      <div class="sv-statcard"><span class="sv-statcard__icon">${icon('wallet')}</span>${t('h3', 'Malipo ya mobile money', 'Mobile money payments', { class: 'sv-h3' })}${t('p', 'Miamala ya malipo itachakatwa na mtoa huduma aliyethibitishwa, si kwa kuweka kadi kwenye tovuti hii.', 'Payment transactions will be processed by a verified provider, not by storing card details on this website.')}</div>
      <div class="sv-statcard"><span class="sv-statcard__icon">${icon('scale')}</span>${t('h3', 'Bila ada zilizofichwa', 'No hidden fees', { class: 'sv-h3' })}${t('p', 'Ada zote zinazoonyeshwa zinapaswa kueleweka kabla ya kuthibitisha malipo.', 'Every fee we show should be understood before you confirm a payment.')}</div>
    </div>
  </div>
</section>

<section class="sv-section sv-section--tint">
  <div class="sv-container sv-narrow">
    ${sectionHead({
      eyebrow: { sw: 'Maswali ya bei', en: 'Pricing questions' },
      title: { sw: 'Mambo ya kujua kuhusu bei', en: 'Things to know about pricing' },
    })}
    ${accordion(PRICING_FAQ, 'pricing-faq')}
  </div>
</section>

${ctaSection({
  title: { sw: 'Pata taarifa za bei na uzinduzi.', en: 'Get pricing and launch updates.' },
  lead: { sw: 'Jiunge na orodha ya uzinduzi. Tutakutumia taarifa tutakapofungua usajili.', en: 'Join the launch list. We will let you know when registration opens.' },
})}`;

  return { file: 'pricing.html', html: layout({ meta, active: '/pricing', body }) };
}

module.exports = { pricingPage };
