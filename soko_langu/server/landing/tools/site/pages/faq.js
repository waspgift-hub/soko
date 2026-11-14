'use strict';

const { t } = require('../core');
const { pageMeta, layout, pageHero, accordion, ctaSection } = require('../components');
const seo = require('../seo');

const GROUPS = [
  {
    id: 'general',
    title: { sw: 'Maswali ya jumla', en: 'General questions' },
    items: [
      { q: 'Soko Vibe ni nini?', a: 'Soko Vibe ni soko la mtandaoni la Tanzania linalojengwa kwa wanunuzi na wauzaji. Tunalenga kuunganisha bidhaa, huduma, wauzaji na wanunuzi kwenye uzoefu mmoja rahisi.', enQ: 'What is Soko Vibe?', enA: 'Soko Vibe is a Tanzanian online marketplace being built for buyers and sellers. We aim to bring products, services, sellers and buyers together in one simple experience.' },
      { q: 'Soko Vibe iko wapi?', a: 'Soko Vibe inajengwa Dar es Salaam, Tanzania, kwa ajili ya soko la Tanzania.', enQ: 'Where is Soko Vibe based?', enA: 'Soko Vibe is being built in Dar es Salaam, Tanzania, for the Tanzanian market.' },
      { q: 'Je, Soko Vibe ni kampuni halisi?', a: 'Ndiyo. Soko Vibe ni jukwaa linaloendelezwa na timu ya Tanzania. Tovuti hii inaeleza kile tunachojenga kwa uwazi.', enQ: 'Is Soko Vibe a real company?', enA: 'Yes. Soko Vibe is a platform being developed by a Tanzanian team. This website explains what we are building, openly.' },
      { q: 'Kwa nini tovuti inaonyesha “inaendelezwa”?', a: 'Kwa sababu app na baadhi ya vipengele bado havijakamilika. Tunapendelea kuwa wazi badala ya kuonyesha huduma ambayo haijafanya kazi bado.', enQ: 'Why does the website say “in development”?', enA: 'Because the app and some features are not finished yet. We would rather be clear than present a service that does not work yet.' },
    ],
  },
  {
    id: 'buyers',
    title: { sw: 'Wanunuzi', en: 'Buyers' },
    items: [
      { q: 'Nitaweza kununua lini?', a: 'Hakuna tarehe ya uzinduzi iliyotangazwa. Jiunge na orodha ya uzinduzi na tutakutumia taarifa tutakapokuwa tayari.', enQ: 'When will I be able to buy?', enA: 'No launch date has been announced. Join the launch list and we will let you know when we are ready.' },
      { q: 'Je, naweza kuwasiliana na muuza kabla ya kununua?', a: 'Mazungumzo ndani ya app yanaendelezwa. Lengo ni uweze kuuliza maswali na kukubaliana maelezo kabla ya malipo.', enQ: 'Can I talk to a seller before buying?', enA: 'In-app messaging is in development. The goal is for you to ask questions and agree details before paying.' },
      { q: 'Je, bidhaa zote zitakuwa halisi?', a: 'Tunapanga uthibitisho wa wauzaji na ukaguzi wa maudhui. Hakuna mfumo unaoweza kuondoa hatari yote, kwa hiyo tunajenga hatua kadhaa za ulinzi na tunaeleza wazi.', enQ: 'Will every product be genuine?', enA: 'We are planning seller verification and content moderation. No system can remove all risk, so we are building several layers of protection and will explain them clearly.' },
      { q: 'Je, naweza kurudisha bidhaa?', a: 'Sera ya kurudisha bidhaa itatangazwa kabla ya uzinduzi. Hatua za mgogoro na ulinzi wa malipo zinaendelezwa.', enQ: 'Can I return a product?', enA: 'The returns policy will be published before launch. Dispute and payment-protection steps are in development.' },
    ],
  },
  {
    id: 'sellers',
    title: { sw: 'Wauzaji', en: 'Sellers' },
    items: [
      { q: 'Ninawezaje kuuza kwenye Soko Vibe?', a: 'Usajili wa wauzaji bado haujafunguliwa. Sajili nia yako kupitia orodha ya wauzaji na tutakuwasiliana tutakapofungua.', enQ: 'How can I sell on Soko Vibe?', enA: 'Seller registration is not open yet. Register your interest through the seller list and we will contact you when it opens.' },
      { q: 'Je, nitahitaji uthibitisho?', a: 'Ndiyo. Uthibitisho wa utambulisho unapangwa kwa wauzaji wote kabla ya kuuza, kwa usalama wa wanunuzi.', enQ: 'Will I need verification?', enA: 'Yes. Identity verification is planned for all sellers before they can sell, for buyer safety.' },
      { q: 'Je, mnaahidi mauzo?', a: 'Hapana. Hatuwezi kuahidi mauzo, mapato au mwonekano. Tunatoa zana; matokeo yanategemea bidhaa, bei na huduma yako.', enQ: 'Do you guarantee sales?', enA: 'No. We cannot guarantee sales, revenue or visibility. We provide tools; results depend on your products, pricing and service.' },
      { q: 'Je, naweza kuuza huduma?', a: 'Tunalenga kuwezesha bidhaa na huduma. Huduma zitafuata masharti na vigezo vitakavyotangazwa kabla ya uzinduzi.', enQ: 'Can I sell services?', enA: 'We aim to support products and services. Services will follow terms and criteria published before launch.' },
    ],
  },
  {
    id: 'accounts',
    title: { sw: 'Akaunti', en: 'Accounts' },
    items: [
      { q: 'Je, naweza kuunda akaunti sasa?', a: 'Hapana. Usajili wa akaunti utafunguliwa tutakapokuwa tayari. Kwa sasa unaweza kujiunga na orodha ya uzinduzi au kuwasiliana nasi.', enQ: 'Can I create an account now?', enA: 'No. Account registration will open when we are ready. For now you can join the launch list or contact us.' },
      { q: 'Nitahitaji nini kujiunga?', a: 'Tunapanga kutumia namba ya simu na uthibitisho wa OTP, kwa sababu ndiyo njia inayotumika zaidi Tanzania.', enQ: 'What will I need to sign up?', enA: 'We plan to use a phone number and OTP verification, since that is the method most people in Tanzania use.' },
      { q: 'Je, ninaweza kufuta akaunti yangu?', a: 'Ndiyo. Ukishafungua akaunti, utakuwa na njia ya kuomba kufuta akaunti na data yako. Taarifa za sasa za kufuta data zinapatikana kwenye ukurasa wa kufuta data.', enQ: 'Can I delete my account?', enA: 'Yes. Once accounts open, you will have a way to request deletion of your account and data. Current data-deletion information is on the data deletion page.' },
    ],
  },
  {
    id: 'payments',
    title: { sw: 'Malipo', en: 'Payments' },
    items: [
      { q: 'Nitalipa vipi?', a: 'Tunajenga malipo kupitia mobile money kwa kutumia mtoa huduma wa malipo aliyethibitishwa. Njia kamili zitatangazwa kabla ya uzinduzi.', enQ: 'How will I pay?', enA: 'We are building mobile money payments through a verified payment provider. The full methods will be announced before launch.' },
      { q: 'Je, mnatoza kamisheni?', a: 'Ndiyo. Soko Vibe inatoza kamisheni ya jukwaa inayolipwa na mnunuzi juu ya bei ya bidhaa (kwa sasa asilimia 3.5); muuzaji hupokea bei kamili ya bidhaa pamoja na usafirishaji. Kiwango kilicho hai kinaonyeshwa kabla ya malipo. Watoa huduma wa mobile money wanaweza kutoza ada zao.', enQ: 'Do you charge a commission?', enA: 'Yes. Soko Vibe charges a buyer-pays-top platform commission on the item price (currently 3.5%); the seller still receives the full item price plus shipping. The live rate is shown before payment. Mobile money providers may charge their own fees.' },
      { q: 'Je, malipo yangu yanalindwa?', a: 'Mchakato wa escrow unaendelezwa ili fedha zishikiliwe na kuachiliwa baada ya makubaliano kutimizwa. Hii haijafunguliwa bado.', enQ: 'Is my payment protected?', enA: 'An escrow flow is in development so funds are held and released once the agreed outcome is met. This is not open yet.' },
      { q: 'Je, mnapokea malipo kwenye tovuti hii?', a: 'Hapana. Tovuti hii haipokei malipo ya bidhaa. Malipo yatakuwa ndani ya app baada ya uzinduzi.', enQ: 'Do you take payments on this website?', enA: 'No. This website does not process product payments. Payments will be inside the app after launch.' },
    ],
  },
  {
    id: 'delivery',
    title: { sw: 'Usafirishaji', en: 'Delivery' },
    items: [
      { q: 'Je, mnafanya usafirishaji?', a: 'Uratibu wa usafirishaji unapangwa. Hatujafungua huduma ya usafirishaji bado.', enQ: 'Do you deliver?', enA: 'Delivery coordination is planned. We have not opened a delivery service yet.' },
      { q: 'Je, nitaweza kufuatilia oda?', a: 'Ufuatiliaji wa oda kwa hatua unaendelezwa ili ujue bidhaa iko wapi hadi inapofika.', enQ: 'Will I be able to track my order?', enA: 'Step-by-step order tracking is in development so you can see where a product is until it arrives.' },
      { q: 'Je, uthibitisho wa upokeaji utahitajika?', a: 'Tunapanga uthibitisho wa upokeaji kabla ya malipo kuachiliwa kwa muuza, kwa ulinzi wa pande zote.', enQ: 'Will receipt confirmation be required?', enA: 'We plan to require receipt confirmation before funds are released to the seller, to protect both sides.' },
    ],
  },
  {
    id: 'security',
    title: { sw: 'Usalama', en: 'Security' },
    items: [
      { q: 'Je, data yangu ni salama?', a: 'Tunakusanya data ndogo tu inayohitajika na tunaitunza kwa udhibiti wa ufikiaji. Sera ya faragha inaeleza zaidi.', enQ: 'Is my data safe?', enA: 'We collect only the data we need and keep it behind access controls. The privacy policy explains more.' },
      { q: 'Je, mtaniuzia barua pepe yangu?', a: 'Hapana. Hatuna mauzo ya data ya wanunuzi au wauzaji. Tutatumia barua pepe yako kwa taarifa ulizozikubali.', enQ: 'Will you sell my email address?', enA: 'No. We do not sell buyer or seller data. We use your email for the updates you agreed to receive.' },
      { q: 'Je, mna uthibitisho wa wauzaji?', a: 'Uthibitisho wa utambulisho (KYC) kwa wauzaji unaendelezwa. Utahitajika kabla ya kuuza.', enQ: 'Do you verify sellers?', enA: 'Identity verification (KYC) for sellers is in development. It will be required before selling.' },
    ],
  },
  {
    id: 'subscriptions',
    title: { sw: 'Usajili', en: 'Subscriptions' },
    items: [
      { q: 'Je, kuna mpango wa bure?', a: 'Ndiyo. Mpango wa mnunuzi na Seller Basic ni bure kwenye usanidi wa sasa.', enQ: 'Is there a free plan?', enA: 'Yes. The buyer plan and Seller Basic are free in the current configuration.' },
      { q: 'Bei za mipango ya kulipia ni zipi?', a: 'Seller Plus ni TSH 14,900 kwa mwezi, Seller Pro ni TSH 29,900 kwa mwezi na Business ni TSH 79,900 kwa mwezi. Bei hizi ni za kabla ya uzinduzi.', enQ: 'What do paid plans cost?', enA: 'Seller Plus is TZS 14,900 per month, Seller Pro is TZS 29,900 per month and Business is TZS 79,900 per month. These are pre-launch prices.' },
      { q: 'Je, naweza kughairi?', a: 'Masharti ya kughairi yatakuwa wazi ndani ya app kabla ya malipo yoyote. Hatuwezi kukubali usajili wa kulipia kabla ya uzinduzi.', enQ: 'Can I cancel?', enA: 'Cancellation terms will be clear inside the app before any payment. We cannot accept paid subscriptions before launch.' },
    ],
  },
  {
    id: 'launch',
    title: { sw: 'Taarifa za uzinduzi', en: 'Launch information' },
    items: [
      { q: 'Mtazindua lini?', a: 'Hatujatangaza tarehe. Tunakamilisha vipengele muhimu kwanza, kisha tutatangaza kwa orodha ya uzinduzi.', enQ: 'When will you launch?', enA: 'We have not announced a date. We are completing the important features first, then we will announce to the launch list.' },
      { q: 'Nitapata taarifa gani?', a: 'Taarifa za uzinduzi na masasisho muhimu. Hatutuma barua taka.', enQ: 'What updates will I receive?', enA: 'Launch news and important updates. We do not send spam.' },
      { q: 'Naweza kujiondoa vipi?', a: 'Kila barua pepe ya taarifa itakuwa na kiungo cha kujiondoa. Unaweza pia kuwasiliana nasi tukuondoe.', enQ: 'How do I unsubscribe?', enA: 'Every update email will include an unsubscribe link. You can also contact us and we will remove you.' },
      { q: 'Je, nitapata app kwenye Play Store?', a: 'Tunapanga kutoa app ya Android. Tarehe na maelezo ya usambazaji yatatangazwa tutakapokuwa tayari.', enQ: 'Will the app be on the Play Store?', enA: 'We plan to release an Android app. Timing and distribution details will be announced when we are ready.' },
    ],
  },
];

function faqPage() {
  const title = 'Maswali ya Kawaida | Soko Vibe FAQ';
  const description = 'Majibu ya maswali kuhusu Soko Vibe: wanunuzi, wauzaji, akaunti, malipo, usafirishaji, usalama, usajili na uzinduzi.';

  const allItems = GROUPS.flatMap((group) => group.items);
  const meta = pageMeta({
    title,
    description,
    path: '/faq',
    jsonLd: [
      seo.webpage({ path: '/faq', title, description }),
      seo.breadcrumbs([{ name: 'Mwanzo', path: '/' }, { name: 'Maswali', path: '/faq' }]),
      seo.faqPage(allItems),
    ],
  });

  const quickNav = GROUPS.map((group) => `<a href="#${group.id}">${t('span', group.title.sw, group.title.en)}</a>`).join('\n      ');

  const body = `${pageHero({
    eyebrow: { sw: 'Maswali', en: 'FAQ' },
    title: { sw: 'Majibu ya maswali yanayoulizwa mara kwa mara.', en: 'Answers to the questions people ask most.' },
    lead: { sw: 'Kama jibu halipo hapa, wasiliana nasi. Tutakujibu kwa uwazi.', en: 'If your answer is not here, contact us. We will answer honestly.' },
    breadcrumb: 'Maswali',
  })}

<section class="sv-section sv-section--tight">
  <div class="sv-container">
    <nav class="sv-quicknav" aria-label="Makundi ya maswali" data-en-aria-label="FAQ categories">
      ${quickNav}
    </nav>
  </div>
</section>

${GROUPS.map((group) => `<section class="sv-section sv-section--tint" id="${group.id}">
  <div class="sv-container sv-narrow">
    ${t('h2', group.title.sw, group.title.en, { class: 'sv-h2' })}
    ${accordion(group.items.map((item) => ({
      sw: { q: item.q, a: item.a },
      en: { q: item.enQ, a: item.enA },
    })), `faq-${group.id}`)}
  </div>
</section>`).join('\n\n')}

<section class="sv-section">
  <div class="sv-container sv-narrow sv-center">
    ${t('h2', 'Bado una swali?', 'Still have a question?', { class: 'sv-h2' })}
    ${t('p', 'Tutumie ujumbe na tutakujibu ndani ya siku mbili za kazi.', 'Send us a message and we will reply within two working days.', { class: 'sv-lead' })}
    <div class="sv-actions sv-actions--center">
      <a class="sv-btn sv-btn--primary" href="/contact" data-en="Contact us">Wasiliana nasi</a>
      <a class="sv-btn sv-btn--ghost" href="mailto:support@sokovibe.co.tz">support@sokovibe.co.tz</a>
    </div>
  </div>
</section>

${ctaSection({
  title: { sw: 'Pata taarifa za uzinduzi.', en: 'Get launch updates.' },
  lead: { sw: 'Jiunge na orodha ya uzinduzi na upokee taarifa muhimu.', en: 'Join the launch list and receive important updates.' },
})}`;

  return { file: 'faq.html', html: layout({ meta, active: '/faq', body }) };
}

module.exports = { faqPage };
