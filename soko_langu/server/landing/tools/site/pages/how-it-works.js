'use strict';

const { t, icon } = require('../core');
const { pageMeta, layout, pageHero, sectionHead, step, ctaSection, statusBadge } = require('../components');
const seo = require('../seo');

function journeyCard({ title, text, status, iconName }) {
  return `<li class="sv-journey__item">
    <span class="sv-journey__icon">${icon(iconName)}</span>
    <div>
      <div class="sv-journey__top">${t('h3', title.sw, title.en)} ${statusBadge(status)}</div>
      ${t('p', text.sw, text.en)}
    </div>
  </li>`;
}

function howPage() {
  const title = 'Jinsi Soko Vibe Inavyofanya Kazi | How Soko Vibe Works';
  const description = 'Elewa safari ya mnunuzi na muuza kwenye Soko Vibe: ugunduzi, mazungumzo, oda, malipo, usafirishaji na kukamilisha biashara.';
  const meta = pageMeta({
    title,
    description,
    path: '/how-it-works',
    jsonLd: [
      seo.webpage({ path: '/how-it-works', title, description }),
      seo.breadcrumbs([{ name: 'Mwanzo', path: '/' }, { name: 'Jinsi inavyofanya kazi', path: '/how-it-works' }]),
    ],
  });

  const body = `${pageHero({
    eyebrow: { sw: 'Jinsi inavyofanya kazi', en: 'How it works' },
    title: { sw: 'Safari moja wazi, kuanzia ugunduzi hadi kukamilisha biashara.', en: 'One clear journey, from discovery to a completed sale.' },
    lead: { sw: 'Hivi ndivyo tunavyopanga uzoefu wa Soko Vibe kufanya kazi. Vipengele vinavyoendelezwa vinaonyeshwa kwa uwazi.', en: 'This is how we intend the Soko Vibe experience to work. Features still in development are marked clearly.' },
    breadcrumb: 'Jinsi inavyofanya kazi',
  })}

<section class="sv-section">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Kwa wanunuzi', en: 'For buyers' },
      title: { sw: 'Kutoka “nahitaji” hadi “nimekamilisha”.', en: 'From “I need this” to “order complete”.' },
      lead: { sw: 'Hatua za safari ya mnunuzi, kama zinavyoundwa.', en: 'The buyer journey, as we are designing it.' },
    })}
    <ol class="sv-journey">
      ${journeyCard({ iconName: 'search', status: 'dev', title: { sw: '1. Gundua bidhaa', en: '1. Discover products' }, text: { sw: 'Tafuta kwa neno, kategoria au eneo. Matokeo yanapangwa ili yanayofaa zaidi yaonekane kwanza.', en: 'Search by keyword, category or location. Results are arranged so the most relevant appear first.' } })}
      ${journeyCard({ iconName: 'user', status: 'dev', title: { sw: '2. Chunguza muuza', en: '2. Check the seller' }, text: { sw: 'Fungua wasifu wa muuza kuona bidhaa, maelezo na mchakato wa uthibitisho.', en: 'Open the seller profile to see their products, details and verification status.' } })}
      ${journeyCard({ iconName: 'chat', status: 'dev', title: { sw: '3. Uliza na jadiliana', en: '3. Ask and agree' }, text: { sw: 'Tumia mazungumzo ndani ya app kujua ukubwa, hali ya bidhaa, usafirishaji na maelezo mengine.', en: 'Use in-app messaging to confirm size, condition, delivery and other details.' } })}
      ${journeyCard({ iconName: 'bag', status: 'dev', title: { sw: '4. Weka oda', en: '4. Place the order' }, text: { sw: 'Chagua bidhaa, idadi na anwani ya usafirishaji, kisha thibitisha oda.', en: 'Choose the product, quantity and delivery address, then confirm the order.' } })}
      ${journeyCard({ iconName: 'wallet', status: 'dev', title: { sw: '5. Lipa', en: '5. Pay' }, text: { sw: 'Malipo yanapangwa kupitia mobile money, yakichakatwa na mtoa huduma wa malipo aliyethibitishwa.', en: 'Payments are being designed for mobile money, processed by a verified payment provider.' } })}
      ${journeyCard({ iconName: 'truck', status: 'planned', title: { sw: '6. Pokea bidhaa', en: '6. Receive the product' }, text: { sw: 'Uratibu wa usafirishaji na uthibitisho wa upokeaji vinaendelezwa kwa kanda mbalimbali.', en: 'Delivery coordination and receipt confirmation are in development across regions.' } })}
      ${journeyCard({ iconName: 'check', status: 'planned', title: { sw: '7. Kamilisha', en: '7. Complete' }, text: { sw: 'Baada ya bidhaa kupokelewa na kuridhika, biashara inakamilika na malipo yanafunguliwa kwa muuza.', en: 'Once the product is received and confirmed, the sale completes and the seller is settled.' } })}
    </ol>
  </div>
</section>

<section class="sv-section sv-section--tint">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Kwa wauzaji', en: 'For sellers' },
      title: { sw: 'Kutoka wasifu hadi oda iliyokamilika.', en: 'From profile to completed order.' },
      lead: { sw: 'Hatua tunazopanga kwa wauzaji, kuanzia kujiunga hadi kupokea malipo.', en: 'The steps we are designing for sellers, from joining to getting paid.' },
    })}
    <ol class="sv-journey">
      ${journeyCard({ iconName: 'user', status: 'dev', title: { sw: '1. Jiunge na uthibitishe', en: '1. Join and verify' }, text: { sw: 'Tengeneza akaunti na ukamilishe uthibitisho wa utambulisho ili wanunuzi wajue wanafanya biashara na nani.', en: 'Create an account and complete identity verification so buyers know who they are dealing with.' } })}
      ${journeyCard({ iconName: 'store', status: 'dev', title: { sw: '2. Jenga wasifu', en: '2. Build your profile' }, text: { sw: 'Ongeza jina la biashara, maelezo, eneo na taarifa zinazosaidia wanunuzi kukuamini.', en: 'Add your business name, description, location and details that help buyers trust you.' } })}
      ${journeyCard({ iconName: 'tag', status: 'dev', title: { sw: '3. Weka bidhaa', en: '3. List products' }, text: { sw: 'Ongeza bidhaa kwa bei, maelezo, picha na video. Simamia orodha mahali pamoja.', en: 'Add products with price, description, photos and video. Manage listings in one place.' } })}
      ${journeyCard({ iconName: 'chat', status: 'dev', title: { sw: '4. Wasiliana na wanunuzi', en: '4. Talk to buyers' }, text: { sw: 'Jibu maswali, eleza usafirishaji na kamilisha maelezo kabla ya oda.', en: 'Answer questions, explain delivery and confirm details before an order.' } })}
      ${journeyCard({ iconName: 'wallet', status: 'dev', title: { sw: '5. Pokea malipo', en: '5. Get paid' }, text: { sw: 'Malipo yanashikiliwa kwa usalama na kuachiliwa baada ya biashara kukamilika, kama ilivyoundwa.', en: 'Funds are held safely and released after the sale completes, as designed.' } })}
    </ol>
  </div>
</section>

<section class="sv-section" id="malipo">
  <div class="sv-container sv-split">
    <div class="sv-split__copy">
      ${t('p', 'Malipo na usafirishaji', 'Payments and delivery', { class: 'sv-eyebrow' })}
      ${t('h2', 'Malipo ya mobile money, yaliyoundwa kwa ulinzi.', 'Mobile money payments, designed around protection.', { class: 'sv-h2' })}
      ${t('p', 'Tunajenga muunganisho wa malipo kupitia mtoa huduma wa malipo aliyethibitishwa, kwa kutumia njia za mobile money ambazo watu wa Tanzania wanazitumia kila siku. Malipo yanashikiliwa kwa weledi na kuachiliwa baada ya makubaliano kutimizwa.', 'We are building payment integration through a verified payment provider, using the mobile money methods people in Tanzania already use every day. Funds are held carefully and released once the agreed outcome is met.')}
      <ul class="sv-checks">
        <li>${icon('lock', 'sv-icon--sm')} ${t('span', 'Maelezo ya malipo hayahifadhiwi kwenye kifaa cha mnunuzi.', 'Payment details are not stored on the buyer’s device.')}</li>
        <li>${icon('shield', 'sv-icon--sm')} ${t('span', 'Escrow na uthibitisho wa upokeaji vinaendelezwa.', 'Escrow and receipt confirmation are in development.')}</li>
        <li>${icon('truck', 'sv-icon--sm')} ${t('span', 'Uratibu wa usafirishaji unapangwa kwa kanda mbalimbali.', 'Delivery coordination is planned for different regions.')}</li>
      </ul>
      <p class="sv-disclaimer">${icon('document', 'sv-icon--sm')} ${t('span', 'Hakuna malipo yanayopokelewa kwenye tovuti hii. Tovuti hii haikubali malipo ya bidhaa.', 'No payments are accepted on this website. This website does not process product payments.')}</p>
    </div>
    <div class="sv-split__aside">
      <div class="sv-statcard"><span class="sv-statcard__icon">${icon('wallet')}</span>${t('h3', 'Mobile money', 'Mobile money', { class: 'sv-h3' })}${t('p', 'Tunazingatia njia za malipo zinazotumika nchini, kupitia mtoa huduma aliyethibitishwa.', 'We are focusing on the payment methods used in the country, through a verified provider.')}</div>
      <div class="sv-statcard"><span class="sv-statcard__icon">${icon('refresh')}</span>${t('h3', 'Ulinzi wa pande zote', 'Protection for both sides', { class: 'sv-h3' })}${t('p', 'Lengo ni muuza asipoteze bidhaa na mnunuzi asipoteze fedha.', 'The aim is that sellers do not lose products and buyers do not lose money.')}</div>
    </div>
  </div>
</section>

<section class="sv-section sv-section--tint">
  <div class="sv-container sv-narrow">
    ${sectionHead({
      eyebrow: { sw: 'Kabla ya uzinduzi', en: 'Before launch' },
      title: { sw: 'Kile ambacho hakijafunguliwa bado', en: 'What is not open yet' },
    })}
    ${t('p', 'Kwa sasa, Soko Vibe haipokei oda, malipo au usajili wa wauzaji kwenye app. Tovuti hii inakusanya nia ya wanunuzi na wauzaji kupitia orodha ya uzinduzi ili tuweze kuwasiliana na watu wa kwanza tutakapokuwa tayari.', 'Right now, Soko Vibe does not accept orders, payments or seller registrations in the app. This website collects buyer and seller interest through the launch list so we can contact the first people when we are ready.', { class: 'sv-lead' })}
    <div class="sv-actions">
      <a class="sv-btn sv-btn--primary" href="/#waitlist" data-en="Join the launch list">Jiunge na orodha ya uzinduzi</a>
      <a class="sv-btn sv-btn--ghost" href="/features" data-en="See feature status">Ona hali ya vipengele</a>
    </div>
  </div>
</section>

${ctaSection({
  title: { sw: 'Kuwa wa kwanza kujua tutakapozindua.', en: 'Be the first to know when we launch.' },
  lead: { sw: 'Jiunge na orodha ya uzinduzi. Tutawasiliana nawe tutakapokuwa tayari.', en: 'Join the launch list. We will be in touch when we are ready.' },
})}`;

  return { file: 'how-it-works.html', html: layout({ meta, active: '/how-it-works', body }) };
}

module.exports = { howPage };
