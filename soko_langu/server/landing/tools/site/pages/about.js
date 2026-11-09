'use strict';

const { t, icon } = require('../core');
const { pageMeta, layout, pageHero, sectionHead, ctaSection } = require('../components');
const seo = require('../seo');

const VALUES = [
  {
    iconName: 'scale',
    title: { sw: 'Uwazi', en: 'Honesty' },
    text: { sw: 'Tunaeleza kile kilichokamilika na kile kinachoendelezwa. Hatuuzi ndoto kama bidhaa iliyokwisha.', en: 'We say what is finished and what is still being built. We do not sell a dream as a finished product.' },
  },
  {
    iconName: 'users',
    title: { sw: 'Mtu kwanza', en: 'People first' },
    text: { sw: 'Kila uamuzi wa bidhaa unaanza na swali: je, hii inarahisisha maisha ya mnunuzi au muuza wa Tanzania?', en: 'Every product decision starts with one question: does this make life easier for a Tanzanian buyer or seller?' },
  },
  {
    iconName: 'shield',
    title: { sw: 'Uaminifu', en: 'Trust' },
    text: { sw: 'Uaminifu hujengwa kwa mchakato wazi, si kwa ahadi. Tunajenga ulinzi kabla ya kukaribisha biashara.', en: 'Trust is built through clear processes, not promises. We build protection before inviting commerce in.' },
  },
  {
    iconName: 'sparkles',
    title: { sw: 'Urahisi', en: 'Simplicity' },
    text: { sw: 'Tunapunguza msongamano wa huduma. Kilicho muhimu kinaonekana; kilicho kingine hakizuii.', en: 'We reduce clutter. What matters is visible; everything else stays out of the way.' },
  },
];

function aboutPage() {
  const title = 'Kuhusu Soko Vibe | About Soko Vibe Tanzania';
  const description = 'Soko Vibe ni soko la mtandaoni la Tanzania linalojengwa kuunganisha wanunuzi na wauzaji kwa uzoefu rahisi, salama na wa kijamii.';
  const meta = pageMeta({
    title,
    description,
    path: '/about',
    jsonLd: [
      seo.organization(),
      seo.webpage({ path: '/about', title, description }),
      seo.breadcrumbs([{ name: 'Mwanzo', path: '/' }, { name: 'Kuhusu', path: '/about' }]),
    ],
  });

  const body = `${pageHero({
    eyebrow: { sw: 'Kuhusu sisi', en: 'About us' },
    title: { sw: 'Tunajenga soko la mtandaoni linaloeleweka kwa Tanzania.', en: 'We are building an online marketplace that makes sense for Tanzania.' },
    lead: { sw: 'Soko Vibe ni jukwaa la biashara ya kijamii linalojengwa Dar es Salaam kwa wanunuzi na wauzaji kote nchini.', en: 'Soko Vibe is a social-commerce platform being built in Dar es Salaam for buyers and sellers across the country.' },
    breadcrumb: 'Kuhusu',
  })}

<section class="sv-section">
  <div class="sv-container sv-split">
    <div class="sv-split__copy">
      ${t('p', 'Tunatoka wapi', 'Where we started', { class: 'sv-eyebrow' })}
      ${t('h2', 'Tatizo si ukosefu wa bidhaa. Ni njia ya kuzipata.', 'The problem is not a lack of products. It is how we find them.', { class: 'sv-h2' })}
      ${t('p', 'Tanzania ina wauzaji wengi wenye bidhaa nzuri na wanunuzi wanaotafuta kila siku. Lakini mazungumzo yanasambaa kwenye mitandao tofauti, bei na maelezo hayana mpangilio, na mnunuzi mara nyingi anabahatisha kama muuza ni wa kuaminika.', 'Tanzania has many sellers with good products and buyers searching every day. But conversations are scattered across different networks, prices and details are inconsistent, and buyers often have to guess whether a seller can be trusted.', { class: 'sv-lead' })}
      ${t('p', 'Soko Vibe inalenga kuweka ugunduzi, mazungumzo na biashara mahali pamoja — kwa mfumo unaoeleweka, unaotumia simu, na unaozingatia uaminifu.', 'Soko Vibe aims to put discovery, conversation and commerce in one place — in a system that is understandable, mobile-first and built around trust.')}
    </div>
    <div class="sv-quote">
      ${icon('message', 'sv-icon--lg')}
      ${t('p', 'Tunajenga kwa watu wanaonunua na kuuza kila siku — si kwa ajili ya onyesho la teknolojia.', 'We are building for the people who buy and sell every day — not for a technology showcase.', { class: 'sv-quote__text' })}
      <span class="sv-quote__by" data-en="The Soko Vibe team">Timu ya Soko Vibe</span>
    </div>
  </div>
</section>

<section class="sv-section sv-section--tint">
  <div class="sv-container sv-grid sv-grid--2">
    <article class="sv-card sv-card--pad">
      <span class="sv-feature__icon">${icon('sparkles')}</span>
      ${t('h2', 'Dhamira yetu', 'Our vision', { class: 'sv-h3' })}
      ${t('p', 'Kuwa soko la mtandaoni linalotumainika zaidi Tanzania — mahali ambapo mtu yeyote anaweza kugundua, kuungana na kufanya biashara kwa ujasiri, popote alipo.', 'To be Tanzania’s most trusted online marketplace — a place where anyone can discover, connect and trade with confidence, wherever they are.', { class: 'sv-lead' })}
    </article>
    <article class="sv-card sv-card--pad">
      <span class="sv-feature__icon">${icon('pin')}</span>
      ${t('h2', 'Misheni yetu', 'Our mission', { class: 'sv-h3' })}
      ${t('p', 'Kujenga uzoefu rahisi wa biashara unaounganisha bidhaa, huduma na wauzaji kwa wanunuzi wa Tanzania, kwa teknolojia inayofanya kazi kwenye simu na mitandao ya kawaida.', 'To build a simple commerce experience that connects products, services and sellers with Tanzanian buyers, using technology that works on ordinary phones and networks.', { class: 'sv-lead' })}
    </article>
  </div>
</section>

<section class="sv-section">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Tunavyoamini', en: 'What we believe' },
      title: { sw: 'Maadili yanayoongoza kazi yetu', en: 'The values that guide our work' },
      lead: { sw: 'Haya si maneno ya ukutani. Yanaonekana kwenye jinsi tunavyojenga na kuwasiliana.', en: 'These are not wall slogans. They show up in how we build and how we communicate.' },
    })}
    <div class="sv-grid sv-grid--2">
      ${VALUES.map((v) => `<article class="sv-card sv-feature">
        <span class="sv-feature__icon">${icon(v.iconName)}</span>
        <div class="sv-feature__body">${t('h3', v.title.sw, v.title.en)}${t('p', v.text.sw, v.text.en)}</div>
      </article>`).join('\n')}
    </div>
  </div>
</section>

<section class="sv-section sv-section--tint">
  <div class="sv-container sv-split">
    <div class="sv-split__copy">
      ${t('p', 'Mbinu yetu', 'Our approach', { class: 'sv-eyebrow' })}
      ${t('h2', 'Teknolojia inayotumikia soko, si kinyume chake.', 'Technology that serves the market, not the other way round.', { class: 'sv-h2' })}
      ${t('p', 'Tunaanza na matatizo halisi: jinsi ya kupata bidhaa, jinsi ya kujua muuza ni wa kuaminika, na jinsi ya kukamilisha malipo kwa usalama. Kisha tunajenga hatua kwa hatua, tukithibitisha kila kipengele kabla ya kukitangaza.', 'We start with real problems: how to find a product, how to know a seller can be trusted, and how to complete a payment safely. Then we build step by step, validating each feature before announcing it.')}
      <ul class="sv-checks">
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Simu kwanza: uzoefu unabuniwa kwa skrini ndogo na data ndogo.', 'Mobile first: the experience is designed for small screens and limited data.')}</li>
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Lugha mbili: Kiswahili kwanza, Kiingereza kinapatikana.', 'Bilingual: Kiswahili first, with English available.')}</li>
        <li>${icon('check', 'sv-icon--sm')} ${t('span', 'Uwazi wa hali: kila kipengele kinaonyesha kama kinapatikana au kinaendelezwa.', 'Honest status: every feature shows whether it is available or in progress.')}</li>
      </ul>
    </div>
    <div class="sv-split__aside">
      <div class="sv-statcard"><span class="sv-statcard__icon">${icon('bag')}</span>${t('h3', 'Kwa wanunuzi', 'For buyers', { class: 'sv-h3' })}${t('p', 'Ugunduzi rahisi, maelezo wazi na njia ya kuwasiliana na wauzaji kabla ya kuamua.', 'Simple discovery, clear details and a way to talk to sellers before deciding.')}</div>
      <div class="sv-statcard"><span class="sv-statcard__icon">${icon('store')}</span>${t('h3', 'Kwa wauzaji', 'For sellers', { class: 'sv-h3' })}${t('p', 'Mahali pa kuwasilisha bidhaa, kujenga wasifu na kufikia wanunuzi wanaotafuta.', 'A place to present products, build a profile and reach buyers who are looking.')}</div>
      <a class="sv-link" href="/about/founder">${t('span', 'Kuhusu mwanzilishi', 'About the founder')} ${icon('arrow', 'sv-icon--sm')}</a>
    </div>
  </div>
</section>

<section class="sv-section">
  <div class="sv-container sv-narrow">
    ${sectionHead({
      eyebrow: { sw: 'Mbele yetu', en: 'Where we are going' },
      title: { sw: 'Tunaanza Tanzania. Tunaenda taratibu, kwa makusudi.', en: 'We start with Tanzania. We move deliberately.' },
    })}
    ${t('p', 'Soko Vibe bado liko kwenye maendeleo. Hatua zinazofuata ni kukamilisha uzoefu wa msingi wa wauzaji na wanunuzi, kuthibitisha malipo na ulinzi, kisha kukaribisha watu wa kwanza kwa awamu. Tutatumia orodha ya uzinduzi na tovuti hii kueleza maendeleo kwa uwazi.', 'Soko Vibe is still in development. The next steps are to complete the core seller and buyer experience, validate payments and protection, then invite the first people in phases. We will use the launch list and this website to share progress openly.', { class: 'sv-lead' })}
    <div class="sv-actions">
      <a class="sv-btn sv-btn--primary" href="/#waitlist" data-en="Join the launch list">Jiunge na orodha ya uzinduzi</a>
      <a class="sv-btn sv-btn--ghost" href="/contact" data-en="Talk to us">Wasiliana nasi</a>
    </div>
  </div>
</section>

${ctaSection({
  title: { sw: 'Tujenge soko la Tanzania pamoja.', en: 'Let’s build Tanzania’s marketplace together.' },
  lead: { sw: 'Jiunge na orodha ya uzinduzi na upokee taarifa za maendeleo na uzinduzi.', en: 'Join the launch list for development news and launch updates.' },
})}`;

  return { file: 'about.html', html: layout({ meta, active: '/about', body }) };
}

module.exports = { aboutPage };
