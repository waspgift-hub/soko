'use strict';

const { t, icon } = require('../core');
const {
  pageMeta, layout, pageHero, sectionHead, featureCard, waitlistForm, ctaSection, statusBadge,
} = require('../components');
const seo = require('../seo');

const SELLER_FEATURES = [
  {
    iconName: 'user',
    title: { sw: 'Wasifu wa biashara', en: 'A business profile' },
    text: { sw: 'Onyesha biashara yako, eneo na bidhaa zako kwenye ukurasa mmoja unaoeleweka.', en: 'Show your business, location and products on one clear page.' },
    status: 'dev',
  },
  {
    iconName: 'video',
    title: { sw: 'Picha na video', en: 'Photos and video' },
    text: { sw: 'Wasilisha bidhaa kwa picha halisi na video fupi zinazosaidia mnunuzi kuamua.', en: 'Present products with real photos and short videos that help buyers decide.' },
    status: 'dev',
  },
  {
    iconName: 'bag',
    title: { sw: 'Usimamizi wa oda', en: 'Order management' },
    text: { sw: 'Fuatilia oda, hali ya usafirishaji na kukamilisha mauzo mahali pamoja.', en: 'Track orders, delivery status and completed sales in one place.' },
    status: 'dev',
  },
  {
    iconName: 'scale',
    title: { sw: 'Ufahamu wa biashara', en: 'Business insight' },
    text: { sw: 'Muhtasari wa shughuli zako, bila takwimu za kupika au ahadi za mauzo.', en: 'A summary of your activity, with no invented statistics or sales promises.' },
    status: 'dev',
  },
];

function sellersPage() {
  const title = 'Kwa Wauzaji | Sell on Soko Vibe Tanzania';
  const description = 'Soko Vibe inawapa wauzaji wa Tanzania mahali pa kuwasilisha bidhaa, kujenga wasifu na kufikia wanunuzi. Jiunge na orodha ya wauzaji.';
  const meta = pageMeta({
    title,
    description,
    path: '/sellers',
    jsonLd: [
      seo.webpage({ path: '/sellers', title, description }),
      seo.breadcrumbs([{ name: 'Mwanzo', path: '/' }, { name: 'Wauzaji', path: '/sellers' }]),
    ],
  });

  const body = `${pageHero({
    eyebrow: { sw: 'Kwa wauzaji', en: 'For sellers' },
    title: { sw: 'Onyesha bidhaa zako kwa wanunuzi wanaozitafuta.', en: 'Show your products to buyers who are looking for them.' },
    lead: { sw: 'Soko Vibe linajengwa kuwapa wauzaji mahali pazuri pa kuwasilisha bidhaa, kujenga wasifu na kusimamia biashara kwa uwazi.', en: 'Soko Vibe is being built to give sellers a better place to present products, build a profile and manage business clearly.' },
    breadcrumb: 'Wauzaji',
    actions: `<a class="sv-btn sv-btn--primary" href="#seller-waitlist" data-en="Register seller interest">Sajili nia ya kuuza</a><a class="sv-btn sv-btn--ghost" href="/pricing" data-en="See seller plans">Ona mipango ya wauzaji</a>`,
  })}

<section class="sv-section">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Kile tunachojenga', en: 'What we are building' },
      title: { sw: 'Zana za kukuza biashara, hatua kwa hatua.', en: 'Tools to grow your business, step by step.' },
      lead: { sw: 'Zana hizi zinaendelezwa. Hatuahidi mauzo, mapato au mwonekano wa uhakika.', en: 'These tools are in development. We do not promise sales, revenue or guaranteed visibility.' },
    })}
    <div class="sv-grid sv-grid--2">
      ${SELLER_FEATURES.map((item) => featureCard(item)).join('\n')}
    </div>
  </div>
</section>

<section class="sv-section sv-section--tint">
  <div class="sv-container sv-split">
    <div class="sv-split__copy">
      ${t('p', 'Kuanza', 'Getting started', { class: 'sv-eyebrow' })}
      ${t('h2', 'Njia ya kujiandaa kwa uzinduzi.', 'How to get ready for launch.', { class: 'sv-h2' })}
      <ol class="sv-numbered">
        <li><b>01</b><div>${t('h3', 'Jiunge na orodha', 'Join the list')}${t('p', 'Sajili nia yako ya kuuza ili tukuwasiliane tutakapofungua usajili wa wauzaji.', 'Register your interest so we can contact you when seller onboarding opens.')}</div></li>
        <li><b>02</b><div>${t('h3', 'Andaa maelezo', 'Prepare your details')}${t('p', 'Jitayarishe kuwasilisha jina la biashara, eneo, bidhaa na maelezo yake.', 'Be ready to provide your business name, location, products and details.')}</div></li>
        <li><b>03</b><div>${t('h3', 'Kamilisha uthibitisho', 'Complete verification')}${t('p', 'Uthibitisho wa utambulisho utahitajika kabla ya kuuza, kwa usalama wa wanunuzi.', 'Identity verification will be required before selling, for buyer safety.')}</div></li>
        <li><b>04</b><div>${t('h3', 'Anza kuuza', 'Start selling')}${t('p', 'Ukipokea mwaliko, weka bidhaa zako na anza kusimamia oda.', 'Once invited, list your products and start managing orders.')}</div></li>
      </ol>
    </div>
    <div class="sv-split__aside">
      <div class="sv-statcard"><span class="sv-statcard__icon">${icon('refresh')}</span>${t('h3', 'Hakuna ahadi za mauzo', 'No sales promises', { class: 'sv-h3' })}${t('p', 'Hatuwezi kukuahidi mauzo au mapato. Tunajenga zana; matokeo yanategemea bidhaa, bei na huduma yako.', 'We cannot promise sales or revenue. We build tools; results depend on your products, pricing and service.')}</div>
      <div class="sv-statcard"><span class="sv-statcard__icon">${icon('shield')}</span>${t('h3', 'Ulinzi wa muuza', 'Seller protection', { class: 'sv-h3' })}${t('p', 'Malipo yanayolindwa yanaendelezwa ili muuza asipoteze bidhaa kwa oda za uongo.', 'Protected payments are being built so sellers do not lose products to fraudulent orders.')}</div>
    </div>
  </div>
</section>

<section class="sv-section">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Mipango', en: 'Plans' },
      title: { sw: 'Anza bure. Ongeza zana unapokua.', en: 'Start free. Add tools as you grow.' },
      lead: { sw: 'Mpango wa Seller Basic ni bure. Mipango ya kulipia itatoa zana zaidi kwa wauzaji wanaokua.', en: 'The Seller Basic plan is free. Paid plans will add more tools for sellers who are growing.' },
    })}
    <div class="sv-grid sv-grid--3">
      <article class="sv-price-mini">
        <h3>Seller Basic</h3>
        <p class="sv-price-mini__price">TSH 0 <span data-en="/ free">/ bure</span></p>
        <p data-en="Profile, listings, order management, basic insight and notifications.">Wasifu, bidhaa, usimamizi wa oda, ufahamu wa msingi na arifa.</p>
        ${statusBadge('dev')}
      </article>
      <article class="sv-price-mini">
        <h3>Seller Plus</h3>
        <p class="sv-price-mini__price">TSH 14,900 <span data-en="/ month">/ mwezi</span></p>
        <p data-en="Advanced insight, priority support, productivity tools and a subscription badge.">Ufahamu wa kina, msaada wa kipaumbele, zana za tija na beji ya usajili.</p>
        ${statusBadge('dev')}
      </article>
      <article class="sv-price-mini">
        <h3>Seller Pro</h3>
        <p class="sv-price-mini__price">TSH 29,900 <span data-en="/ month">/ mwezi</span></p>
        <p data-en="Everything in Plus, higher quotas and premium reporting.">Kila kitu kilicho kwenye Plus, viwango vya juu na ripoti za kina.</p>
        ${statusBadge('dev')}
      </article>
    </div>
    <div class="sv-center"><a class="sv-link" href="/pricing">${t('span', 'Ona mipango yote na bei', 'See all plans and pricing')} ${icon('arrow', 'sv-icon--sm')}</a></div>
  </div>
</section>

<section class="sv-waitlist-section" id="seller-waitlist">
  <div class="sv-container sv-waitlist-section__inner">
    <div>
      ${t('p', 'Orodha ya wauzaji', 'Seller list', { class: 'sv-eyebrow' })}
      ${t('h2', 'Sajili nia yako ya kuuza.', 'Register your interest to sell.', { class: 'sv-h2' })}
      ${t('p', 'Tutakuwasiliana tutakapofungua usajili wa wauzaji. Hii si usajili wa akaunti bado — ni taarifa ya nia.', 'We will contact you when seller onboarding opens. This is not an account registration yet — it is a statement of interest.', { class: 'sv-lead' })}
      <ul class="sv-checks">
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Taarifa za uzinduzi na nafasi za wauzaji', 'Launch news and seller opportunities')}</li>
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Bila ada ya kujiunga', 'No fee to register interest')}</li>
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Unaweza kujiondoa wakati wowote', 'Unsubscribe anytime')}</li>
      </ul>
    </div>
    <div class="sv-waitlist-section__form">
      ${waitlistForm({ id: 'sellers', source: 'sellers_page', defaultType: 'seller' })}
    </div>
  </div>
</section>

${ctaSection({
  title: { sw: 'Biashara yako ina nafasi kwenye Soko Vibe.', en: 'Your business has a place on Soko Vibe.' },
  lead: { sw: 'Jiunge na orodha ya wauzaji tukuwasiliane tutakapofungua usajili.', en: 'Join the seller list and we will be in touch when onboarding opens.' },
})}`;

  return { file: 'sellers.html', html: layout({ meta, active: '/sellers', body }) };
}

module.exports = { sellersPage };
