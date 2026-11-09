'use strict';

const { t, icon } = require('../core');
const { pageMeta, layout, pageHero, sectionHead, featureCard, ctaSection } = require('../components');
const seo = require('../seo');

const GROUPS = [
  {
    id: 'discovery',
    iconName: 'search',
    title: { sw: 'Ununuzi na ugunduzi', en: 'Shopping and discovery' },
    lead: { sw: 'Kupata bidhaa na huduma unazohitaji, bila kupotea.', en: 'Finding the products and services you need, without getting lost.' },
    items: [
      { iconName: 'search', title: { sw: 'Utafutaji', en: 'Search' }, text: { sw: 'Tafuta kwa neno, kategoria na vichujio ili kupata matokeo yanayofaa.', en: 'Search by keyword, category and filters to find relevant results.' }, status: 'dev' },
      { iconName: 'tag', title: { sw: 'Kategoria', en: 'Categories' }, text: { sw: 'Bidhaa zimepangwa kwa makundi yanayoeleweka kwa urahisi.', en: 'Products are organised into categories that are easy to understand.' }, status: 'dev' },
      { iconName: 'heart', title: { sw: 'Vipendwa', en: 'Favourites' }, text: { sw: 'Hifadhi bidhaa unazozipenda ili kuzirudi baadaye.', en: 'Save products you like so you can come back to them.' }, status: 'dev' },
      { iconName: 'users', title: { sw: 'Maombi ya wanunuzi', en: 'Buyer requests' }, text: { sw: 'Eleza unachotafuta ili wauzaji wanaofaa waweze kukujibu.', en: 'Describe what you are looking for so relevant sellers can respond.' }, status: 'planned' },
    ],
  },
  {
    id: 'seller',
    iconName: 'store',
    title: { sw: 'Zana za wauzaji', en: 'Seller tools' },
    lead: { sw: 'Kusimamia biashara mahali pamoja, kwa hatua rahisi.', en: 'Managing a business in one place, in simple steps.' },
    items: [
      { iconName: 'user', title: { sw: 'Wasifu wa muuza', en: 'Seller profile' }, text: { sw: 'Onyesha biashara yako, eneo na bidhaa zako kwenye ukurasa mmoja.', en: 'Show your business, location and products on one page.' }, status: 'dev' },
      { iconName: 'tag', title: { sw: 'Usimamizi wa bidhaa', en: 'Product listings' }, text: { sw: 'Ongeza, hariri na simamia bidhaa, bei na hali ya stock.', en: 'Add, edit and manage products, prices and stock status.' }, status: 'dev' },
      { iconName: 'bag', title: { sw: 'Usimamizi wa oda', en: 'Order management' }, text: { sw: 'Fuatilia oda, hali ya usafirishaji na kukamilisha mauzo.', en: 'Track orders, delivery status and completed sales.' }, status: 'dev' },
      { iconName: 'scale', title: { sw: 'Takwimu za mauzo', en: 'Sales insight' }, text: { sw: 'Ona muhtasari wa shughuli za biashara yako bila takwimu za kupika.', en: 'See a summary of your business activity, with no invented numbers.' }, status: 'dev' },
    ],
  },
  {
    id: 'social',
    iconName: 'chat',
    title: { sw: 'Biashara ya kijamii', en: 'Social commerce' },
    lead: { sw: 'Kujenga mahusiano kati ya wauzaji na wanunuzi.', en: 'Building relationships between sellers and buyers.' },
    items: [
      { iconName: 'chat', title: { sw: 'Mazungumzo', en: 'Messaging' }, text: { sw: 'Uliza maswali na jadiliana maelezo ndani ya app.', en: 'Ask questions and agree details inside the app.' }, status: 'dev' },
      { iconName: 'heart', title: { sw: 'Kufuata wauzaji', en: 'Follow sellers' }, text: { sw: 'Fuatilia wauzaji unaowapenda na uone bidhaa zao mpya.', en: 'Follow sellers you like and see their new products.' }, status: 'planned' },
      { iconName: 'message', title: { sw: 'Maoni na mijadala', en: 'Comments and discussion' }, text: { sw: 'Shiriki maoni kuhusu bidhaa kwa njia inayosaidia wanunuzi wengine.', en: 'Share product feedback in a way that helps other buyers.' }, status: 'planned' },
      { iconName: 'arrow', title: { sw: 'Kushiriki bidhaa', en: 'Product sharing' }, text: { sw: 'Tuma kiungo cha bidhaa kwa rafiki au mtandao unaoutumia.', en: 'Share a product link with a friend or your network.' }, status: 'dev' },
    ],
  },
  {
    id: 'media',
    iconName: 'video',
    title: { sw: 'Maudhui ya bidhaa', en: 'Product media' },
    lead: { sw: 'Kuelewa bidhaa kwa picha na video halisi.', en: 'Understanding a product through real photos and video.' },
    items: [
      { iconName: 'video', title: { sw: 'Video za bidhaa', en: 'Product video' }, text: { sw: 'Wauzaji wataweza kuonyesha bidhaa kwa video fupi.', en: 'Sellers will be able to show products in short videos.' }, status: 'dev' },
      { iconName: 'sparkles', title: { sw: 'Matunzio ya picha', en: 'Photo galleries' }, text: { sw: 'Picha kadhaa kwa kila bidhaa, zilizopangwa kwa uwazi.', en: 'Several photos per product, arranged clearly.' }, status: 'dev' },
      { iconName: 'shield', title: { sw: 'Maudhui halisi', en: 'Authentic media' }, text: { sw: 'Tunapanga ukaguzi wa maudhui yanayokiuka sheria za jukwaa.', en: 'We are planning moderation for content that breaks platform rules.' }, status: 'planned' },
    ],
  },
  {
    id: 'payments',
    iconName: 'wallet',
    title: { sw: 'Malipo na miamala', en: 'Payments and transactions' },
    lead: { sw: 'Mchakato wa malipo unaolinda pande zote.', en: 'A payment flow that protects both sides.' },
    items: [
      { iconName: 'wallet', title: { sw: 'Mobile money', en: 'Mobile money' }, text: { sw: 'Malipo yanapangwa kupitia mtoa huduma wa malipo aliyethibitishwa.', en: 'Payments are being designed through a verified payment provider.' }, status: 'dev' },
      { iconName: 'shield', title: { sw: 'Escrow', en: 'Escrow' }, text: { sw: 'Fedha zinashikiliwa na kuachiliwa baada ya makubaliano kutimizwa.', en: 'Funds are held and released once the agreed outcome is met.' }, status: 'dev' },
      { iconName: 'scale', title: { sw: 'Daftari la miamala', en: 'Transaction ledger' }, text: { sw: 'Kila miamala inarekodiwa kwa uwazi kwa ufuatiliaji.', en: 'Each transaction is recorded clearly for tracking.' }, status: 'dev' },
      { iconName: 'sparkles', title: { sw: 'Kukuza bidhaa', en: 'Product boosts' }, text: { sw: 'Vifurushi vya hiari vya kuongeza mwonekano wa bidhaa.', en: 'Optional packages to increase a product’s visibility.' }, status: 'dev' },
    ],
  },
  {
    id: 'trust',
    iconName: 'shield',
    title: { sw: 'Uaminifu na usalama', en: 'Trust and security' },
    lead: { sw: 'Ulinzi unaojengwa kabla ya biashara kuanza.', en: 'Protection built before commerce begins.' },
    items: [
      { iconName: 'user', title: { sw: 'Uthibitisho wa wauzaji', en: 'Seller verification' }, text: { sw: 'Uthibitisho wa utambulisho (KYC) kwa wauzaji unaendelezwa.', en: 'Identity verification (KYC) for sellers is in development.' }, status: 'dev' },
      { iconName: 'lock', title: { sw: 'Ulinzi wa akaunti', en: 'Account protection' }, text: { sw: 'Uthibitisho wa namba na udhibiti wa kifaa kwa usalama wa akaunti.', en: 'Phone verification and device controls for account safety.' }, status: 'dev' },
      { iconName: 'refresh', title: { sw: 'Kuthibitisha upokeaji', en: 'Receipt confirmation' }, text: { sw: 'Mchakato wa kuthibitisha bidhaa imepokelewa kabla ya malipo kuachiliwa.', en: 'A flow to confirm the product was received before funds are released.' }, status: 'dev' },
      { iconName: 'document', title: { sw: 'Kuripoti na kuzuia', en: 'Reporting and moderation' }, text: { sw: 'Njia za kuripoti maudhui au tabia inayokiuka sheria.', en: 'Ways to report content or behaviour that breaks the rules.' }, status: 'dev' },
    ],
  },
  {
    id: 'notifications',
    iconName: 'bell',
    title: { sw: 'Arifa', en: 'Notifications' },
    lead: { sw: 'Taarifa muhimu, bila kukuchosha.', en: 'Important updates, without noise.' },
    items: [
      { iconName: 'bell', title: { sw: 'Arifa za app', en: 'Push notifications' }, text: { sw: 'Taarifa za oda, ujumbe na masasisho muhimu.', en: 'Order updates, messages and important news.' }, status: 'dev' },
      { iconName: 'mail', title: { sw: 'Barua pepe', en: 'Email' }, text: { sw: 'Barua pepe za miamala na taarifa muhimu za akaunti.', en: 'Transactional email and important account updates.' }, status: 'dev' },
      { iconName: 'chat', title: { sw: 'Udhibiti wa mapendeleo', en: 'Preference controls' }, text: { sw: 'Chagua unachotaka kupokea na kujiondoa kwa urahisi.', en: 'Choose what you receive and unsubscribe easily.' }, status: 'dev' },
    ],
  },
  {
    id: 'ai',
    iconName: 'sparkles',
    title: { sw: 'Uzoefu wenye akili', en: 'AI-assisted experiences' },
    lead: { sw: 'Msaada wa akili bandia unaopangwa kwa makusudi.', en: 'AI assistance planned deliberately.' },
    items: [
      { iconName: 'sparkles', title: { sw: 'Msaidizi wa ununuzi', en: 'Shopping assistant' }, text: { sw: 'Msaidizi wa kukusaidia kupata bidhaa na kujibu maswali, unaoendelezwa.', en: 'An assistant to help find products and answer questions, in development.' }, status: 'dev' },
      { iconName: 'search', title: { sw: 'Mapendekezo', en: 'Recommendations' }, text: { sw: 'Mapendekezo yanayozingatia mahitaji yako, yanapangwa baada ya uzinduzi.', en: 'Recommendations based on your needs, planned after launch.' }, status: 'planned' },
    ],
  },
];

function featuresPage() {
  const title = 'Vipengele vya Soko Vibe | Soko Vibe Features';
  const description = 'Gundua vipengele vya Soko Vibe: ugunduzi, wasifu wa wauzaji, video za bidhaa, mazungumzo, malipo na usalama — pamoja na hali ya maendeleo ya kila kipengele.';
  const meta = pageMeta({
    title,
    description,
    path: '/features',
    jsonLd: [
      seo.webpage({ path: '/features', title, description }),
      seo.breadcrumbs([{ name: 'Mwanzo', path: '/' }, { name: 'Vipengele', path: '/features' }]),
    ],
  });

  const body = `${pageHero({
    eyebrow: { sw: 'Vipengele', en: 'Features' },
    title: { sw: 'Kila kipengele, kwa hali yake halisi.', en: 'Every feature, with its real status.' },
    lead: { sw: 'Soko Vibe bado linajengwa. Kila kipengele hapa kinaonyesha kama kinaendelezwa, kimepangwa au kinapatikana.', en: 'Soko Vibe is still being built. Every feature here shows whether it is in development, planned or available.' },
    breadcrumb: 'Vipengele',
    actions: `<a class="sv-btn sv-btn--primary" href="/#waitlist" data-en="Join the launch list">Jiunge na orodha ya uzinduzi</a><a class="sv-btn sv-btn--ghost" href="/pricing" data-en="See pricing">Ona bei</a>`,
  })}

<section class="sv-section sv-section--tight">
  <div class="sv-container">
    <div class="sv-legend">
      <span class="sv-badge is-live" data-en="Available">Inapatikana</span>
      <span data-en="Works today, on this website.">Inafanya kazi leo, kwenye tovuti hii.</span>
      <span class="sv-badge is-dev" data-en="In development">Inaendelezwa</span>
      <span data-en="Being built; not open to the public yet.">Inajengwa; bado haijafunguliwa kwa umma.</span>
      <span class="sv-badge is-planned" data-en="Planned">Imepangwa</span>
      <span data-en="On the roadmap, not built yet.">Iko kwenye mpango, bado haijajengwa.</span>
    </div>
  </div>
</section>

${GROUPS.map((group) => `<section class="sv-section sv-section--tint" id="${group.id}">
  <div class="sv-container">
    <div class="sv-grouphead">
      <span class="sv-grouphead__icon">${icon(group.iconName)}</span>
      <div>
        ${t('h2', group.title.sw, group.title.en, { class: 'sv-h2' })}
        ${t('p', group.lead.sw, group.lead.en, { class: 'sv-lead' })}
      </div>
    </div>
    <div class="sv-grid sv-grid--3">
      ${group.items.map((item) => featureCard(item)).join('\n')}
    </div>
  </div>
</section>`).join('\n\n')}

<section class="sv-section">
  <div class="sv-container sv-narrow">
    ${sectionHead({
      eyebrow: { sw: 'Muhimu', en: 'Important' },
      title: { sw: 'Tunachokisema kinapaswa kusomwa kwa hali yake.', en: 'What we say should be read with its status.' },
    })}
    ${t('p', 'Vipengele vilivyoandikwa “inaendelezwa” au “imepangwa” havipatikani kwa umma bado. Tovuti hii haipokei oda wala malipo. Tunaweka hali hizi wazi ili usidhani huduma ambayo haijakamilika inafanya kazi.', 'Features marked “in development” or “planned” are not publicly available yet. This website does not accept orders or payments. We show these statuses so you do not assume an unfinished service is live.', { class: 'sv-lead' })}
    <div class="sv-actions">
      <a class="sv-btn sv-btn--primary" href="/how-it-works" data-en="How it will work">Jinsi itakavyofanya kazi</a>
      <a class="sv-btn sv-btn--ghost" href="/contact" data-en="Ask a question">Uliza swali</a>
    </div>
  </div>
</section>

${ctaSection({
  title: { sw: 'Pata taarifa tutakapozindua.', en: 'Get updates when we launch.' },
  lead: { sw: 'Jiunge na orodha ya uzinduzi na ufuatilie maendeleo ya Soko Vibe.', en: 'Join the launch list and follow Soko Vibe’s progress.' },
})}`;

  return { file: 'features.html', html: layout({ meta, active: '/features', body }) };
}

module.exports = { featuresPage };
