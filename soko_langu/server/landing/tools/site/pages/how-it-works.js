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

function conceptDiagram() {
  const steps = [
    { sw: '1. Gundua', en: '1. Discover', color: '#00c853' },
    { sw: '2. Chat', en: '2. Chat', color: '#00c853' },
    { sw: '3. Oda', en: '3. Order', color: '#00c853' },
    { sw: '4. Lipa', en: '4. Pay', color: '#009624' },
    { sw: '5. Usafirishaji', en: '5. Delivery', color: '#6b6b6b' },
    { sw: '6. Kukamilisha', en: '6. Complete', color: '#6b6b6b' },
  ];
  const stepW = 132;
  const gap = 18;
  const startX = 24;
  const y = 150;
  const rects = steps.map((st, i) => {
    const x = startX + i * (stepW + gap);
    return `<g>
      <rect x="${x}" y="${y}" width="${stepW}" height="74" rx="14" fill="#ffffff" stroke="${st.color}" stroke-width="2"/>
      <circle cx="${x + 22}" cy="${y + 24}" r="11" fill="${st.color}"/>
      <text x="${x + 22}" y="${y + 28}" text-anchor="middle" font-size="11" font-weight="800" fill="#ffffff">${i + 1}</text>
      <text x="${x + stepW / 2}" y="${y + 52}" text-anchor="middle" font-size="13" font-weight="700" fill="#141414" data-en="${st.en}">${st.sw}</text>
    </g>
    ${i < steps.length - 1 ? `<path d="M${x + stepW} ${y + 37} L${x + stepW + gap - 4} ${y + 37}" stroke="#c9cec9" stroke-width="2" marker-end="url(#sv-arrow)"/>` : ''}`;
  }).join('');

  return `<section class="sv-section sv-section--tint">
  <div class="sv-container">
    ${sectionHead({
      eyebrow: { sw: 'Mchoro wa dhana', en: 'Concept diagram' },
      title: { sw: 'Safari ya biashara moja, kwa picha.', en: 'One sale, in one picture.' },
      lead: { sw: 'Mchoro huu unaonyesha jinsi tunavyopanga Soko Vibe kufanya kazi. Kijani inaonyesha kile kinachoendelezwa; kijivu ni kinachopangwa.', en: 'This diagram shows how we intend Soko Vibe to work. Green marks what is being built; grey marks what is planned.' },
    })}
    <div class="sv-diagram" role="img" aria-labelledby="sv-diagram-title sv-diagram-desc">
      <svg viewBox="0 0 920 460" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMid meet">
        <title id="sv-diagram-title" data-en="Soko Vibe sale flow concept diagram">Mchoro wa dhana: safari ya biashara ya Soko Vibe</title>
        <desc id="sv-diagram-desc" data-en="Buyer discovers a product, chats with the seller, places an order, pays with mobile money held safely, receives delivery, and completes the sale; the seller is then settled.">Mnunuzi hugundua bidhaa, anazungumza na muuza, anaagiza, analipa kwa mobile money inayoshikiliwa kwa usalama, anapokea bidhaa, anathibitisha; muuza analipwa.</desc>
        <defs>
          <marker id="sv-arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
            <path d="M0,0 L10,5 L0,10 z" fill="#c9cec9"/>
          </marker>
        </defs>

        <g>
          <rect x="24" y="40" width="150" height="70" rx="14" fill="#0a0a0a"/>
          <text x="99" y="72" text-anchor="middle" font-size="15" font-weight="800" fill="#ffffff" data-en="Buyer">Mnunuzi</text>
          <text x="99" y="92" text-anchor="middle" font-size="11" fill="#a7a7a7" data-en="searches, chats, pays">hutafuta, huzungumza, analipa</text>
        </g>

        <g>
          <rect x="746" y="40" width="150" height="70" rx="14" fill="#0a0a0a"/>
          <text x="821" y="72" text-anchor="middle" font-size="15" font-weight="800" fill="#ffffff" data-en="Seller">Muuza</text>
          <text x="821" y="92" text-anchor="middle" font-size="11" fill="#a7a7a7" data-en="lists, verifies, gets paid">huuza, huthibitishwa, analipwa</text>
        </g>

        <path d="M174 75 L200 75 L200 120" stroke="#c9cec9" stroke-width="2" fill="none"/>
        <path d="M746 75 L720 75 L720 120" stroke="#c9cec9" stroke-width="2" fill="none"/>

        ${rects}

        <g>
          <rect x="24" y="260" width="872" height="62" rx="14" fill="#e9f9ef" stroke="#00c853" stroke-width="1.5"/>
          <text x="460" y="286" text-anchor="middle" font-size="14" font-weight="800" fill="#007a1d" data-en="Money is held safely (escrow) between payment and delivery">Fedha zinashikiliwa kwa usalama (escrow) kati ya malipo na usafirishaji</text>
          <text x="460" y="308" text-anchor="middle" font-size="12" fill="#4c514c" data-en="Released to the seller only after the buyer confirms receipt (in development)">Zinaachiliwa kwa muuza baada ya mnunuzi kuthibitisha upokeaji (inaendelezwa)</text>
        </g>

        <g>
          <circle cx="40" cy="360" r="7" fill="#00c853"/>
          <text x="54" y="364" font-size="12" fill="#4c514c" data-en="Being built">Inaendelezwa</text>
          <circle cx="200" cy="360" r="7" fill="#6b6b6b"/>
          <text x="214" y="364" font-size="12" fill="#4c514c" data-en="Planned">Imepangwa</text>
          <text x="40" y="392" font-size="11" fill="#a7a7a7" data-en="Pre-launch: orders, payments and seller registration are not open yet.">Kabla ya uzinduzi: oda, malipo na usajili wa wauzaji bado havijafunguliwa.</text>
        </g>
      </svg>
    </div>
  </div>
</section>`;
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

${conceptDiagram()}

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
