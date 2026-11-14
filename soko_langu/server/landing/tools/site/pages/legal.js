'use strict';

const { SITE, t, icon } = require('../core');
const { pageMeta, layout, pageHero, ctaSection } = require('../components');
const seo = require('../seo');

const UPDATED_SW = '9 Novemba 2026';
const UPDATED_EN = '9 November 2026';

const PRIVACY = [
  {
    title: { sw: '1. Sera hii inahusu nini', en: '1. What this policy covers' },
    body: [
      { sw: 'Sera hii inaeleza jinsi Soko Vibe inavyokusanya, kutumia na kulinda taarifa binafsi unapotumia tovuti hii (www.sokovibe.co.tz) kabla ya uzinduzi wa app. Inazingatia Sheria ya Ulinzi wa Data Binafsi ya Tanzania ya mwaka 2022.', en: 'This policy explains how Soko Vibe collects, uses and protects personal data when you use this website (www.sokovibe.co.tz) before the app launches. It follows Tanzania’s Personal Data Protection Act 2022.' },
      { sw: 'Tovuti hii bado ni ya kabla ya uzinduzi. Hatuundezi akaunti, hatupokei malipo, na hatuuzi bidhaa kwenye tovuti hii.', en: 'This website is pre-launch. We do not create accounts, take payments, or sell products on this website.' },
    ],
  },
  {
    title: { sw: '2. Taarifa tunazokusanya', en: '2. Information we collect' },
    body: [
      { sw: 'Orodha ya uzinduzi: barua pepe, aina ya mtumiaji (mnunuzi, muuza au wote wawili), lugha uliyochagua, muda wa kukubali na anwani ya IP iliyotumika kuwasilisha fomu. Tunarekodi pia kwamba umeidhinisha kupokea taarifa.', en: 'Launch list: your email address, the type of user you selected (buyer, seller or both), your chosen language, the time you consented, and the IP address used to submit the form. We also record that you agreed to receive updates.' },
      { sw: 'Fomu ya mawasiliano: jina, barua pepe, mada, ujumbe na muda wa kuwasilisha. Tafadhali usitume nenosiri, OTP, namba ya kadi au nyaraka nyeti kupitia fomu hii.', en: 'Contact form: name, email address, subject, message and submission time. Please do not send passwords, OTP codes, card numbers or sensitive documents through this form.' },
      { sw: 'Fomu ya kufuta data: jina (hiari), barua pepe, namba ya simu (hiari) na sababu (hiari), ili tuweze kutambua ombi lako na kujibu.', en: 'Data deletion form: name (optional), email address, phone number (optional) and reason (optional), so we can identify your request and respond.' },
      { sw: 'Taarifa za kiufundi: anwani ya IP na metadata ya ombi zinatumika kuzuia spam na matumizi mabaya. Tovuti haitumii vidakuzi vya uchambuzi au matangazo.', en: 'Technical data: IP address and request metadata are used to prevent spam and abuse. The website does not use analytics or advertising cookies.' },
    ],
  },
  {
    title: { sw: '3. Kwa nini tunatumia taarifa', en: '3. Why we use your information' },
    body: [
      { sw: 'Kukutumia taarifa za uzinduzi ulizoomba kupokea, kukujibu ujumbe, kushughulikia maombi ya data, na kulinda tovuti dhidi ya spam na matumizi mabaya.', en: 'To send the launch updates you asked for, reply to your message, handle data requests, and protect the website against spam and abuse.' },
      { sw: 'Msingi wa kisheria ni ridhaa yako kwa taarifa za uzinduzi na mawasiliano, na maslahi halali kwa ulinzi wa tovuti na usalama. Unaweza kuondoa ridhaa wakati wowote.', en: 'Our lawful basis is your consent for launch updates and correspondence, and legitimate interests for website security and protection. You can withdraw consent at any time.' },
    ],
  },
  {
    title: { sw: '4. Barua pepe na kujiondoa', en: '4. Email and unsubscribing' },
    body: [
      { sw: 'Tunatumia barua pepe yako pekee kwa taarifa za uzinduzi na masasisho muhimu. Kila barua itakuwa na kiungo cha kujiondoa. Unaweza pia kuomba kuondolewa kwa kutuma barua pepe kwa support@sokovibe.co.tz.', en: 'We use your email address only for launch news and important updates. Every email will include an unsubscribe link. You can also ask to be removed by emailing support@sokovibe.co.tz.' },
      { sw: 'Hatuna mauzo ya data. Hatushiriki barua pepe zako na madalali au makampuni ya matangazo.', en: 'We do not sell data. We do not share your email address with brokers or advertising companies.' },
    ],
  },
  {
    title: { sw: '5. Watoa huduma', en: '5. Service providers' },
    body: [
      { sw: 'Tunatumia watoa huduma wanaotusaidia kuendesha tovuti na kutuma barua pepe, ikiwa ni pamoja na huduma za hosting na mtandao wa Cloudflare, huduma ya seva ya Render, na mtoa huduma wa barua pepe (kwa mfano Resend au seva ya SMTP). Wanashughulikia data kwa niaba yetu na chini ya mikataba yao.', en: 'We use service providers that help us run the website and send email, including Cloudflare’s hosting and network services, Render’s server hosting, and an email provider (for example Resend or an SMTP server). They process data on our behalf under their own terms.' },
      { sw: 'Tunaweza kufichua taarifa pale sheria inavyotaka, au kwa mamlaka husika pale inapohitajika kwa ulinzi wa haki zetu au za watumiaji.', en: 'We may disclose information where the law requires it, or to authorities where necessary to protect our rights or those of users.' },
    ],
  },
  {
    title: { sw: '6. Uhifadhi na uhamishaji nje ya Tanzania', en: '6. Retention and transfers outside Tanzania' },
    body: [
      { sw: 'Tunahifadhi barua pepe za orodha ya uzinduzi hadi utakapojiondoa au hadi uzinduzi ukamilike, na kisha kwa muda mfupi tu unaohitajika kwa kumbukumbu. Ujumbe wa mawasiliano huhifadhiwa kwa muda unaohitajika kujibu na kufuatilia.', en: 'We keep launch-list email addresses until you unsubscribe or until the launch process is complete, and then only briefly for records. Contact messages are kept for as long as needed to reply and follow up.' },
      { sw: 'Baadhi ya watoa huduma wetu wako nje ya Tanzania. Tunachukua hatua zinazofaa kuhakikisha data inalindwa kwa kiwango kinacholingana na sheria ya Tanzania.', en: 'Some of our service providers are outside Tanzania. We take appropriate steps to ensure data is protected to a standard consistent with Tanzanian law.' },
    ],
  },
  {
    title: { sw: '7. Haki zako', en: '7. Your rights' },
    body: [
      { sw: 'Kwa mujibu wa sheria, unaweza kuomba nakala ya data yako, kuirekebisha, kuifuta, kupinga matumizi fulani, au kuondoa ridhaa. Tuma ombi kwa dpo@sokovibe.co.tz. Tutajibu ndani ya siku 14 za kazi.', en: 'Under the law, you can request a copy of your data, correct it, delete it, object to certain uses, or withdraw consent. Send a request to dpo@sokovibe.co.tz. We will respond within 14 working days.' },
      { sw: 'Kama hukubaliani na jibu letu, unaweza kuwasilisha malalamiko kwa Mamlaka ya Ulinzi wa Data Binafsi (PDPC) nchini Tanzania.', en: 'If you are not satisfied with our response, you can complain to Tanzania’s Personal Data Protection Commission (PDPC).' },
    ],
  },
  {
    title: { sw: '8. Usalama', en: '8. Security' },
    body: [
      { sw: 'Tunatumia HTTPS, udhibiti wa ufikiaji wa data, na kanuni za kuzuia spam. Hakuna mfumo unaoweza kutoa uhakika kamili; kama una wasiwasi kuhusu usalama wa taarifa zako, wasiliana nasi mara moja.', en: 'We use HTTPS, access controls for data, and spam protections. No system can guarantee absolute security; if you are concerned about the safety of your information, contact us immediately.' },
    ],
  },
  {
    title: { sw: '9. Watoto', en: '9. Children' },
    body: [
      { sw: 'Tovuti hii haikusudiwi kwa watoto chini ya miaka 18. Hatuusanyi kwa makusudi taarifa za watoto. Kama unaamini mtoto ametutumia taarifa, wasiliana nasi tuzifute.', en: 'This website is not intended for children under 18. We do not knowingly collect children’s data. If you believe a child has sent us information, contact us and we will delete it.' },
    ],
  },
  {
    title: { sw: '10. Mabadiliko na mawasiliano', en: '10. Changes and contact' },
    body: [
      { sw: 'Tunaweza kusasisha sera hii. Tarehe ya juu itaonyesha toleo la sasa, na mabadiliko makubwa yatatangazwa kwenye tovuti kabla hayajaanza kutumika.', en: 'We may update this policy. The date above shows the current version, and significant changes will be announced on the website before they take effect.' },
      { sw: 'Kwa maswali yote kuhusu faragha, andika kwa dpo@sokovibe.co.tz au support@sokovibe.co.tz.', en: 'For all privacy questions, write to dpo@sokovibe.co.tz or support@sokovibe.co.tz.' },
    ],
  },
];

const TERMS = [
  {
    title: { sw: '1. Masharti haya', en: '1. These terms' },
    body: [
      { sw: 'Masharti haya yanatawala matumizi ya tovuti ya Soko Vibe. Kwa kutumia tovuti, unakubali masharti haya na sera yetu ya faragha. Kama hukubali, tafadhali acha kutumia tovuti.', en: 'These terms govern your use of the Soko Vibe website. By using the website, you agree to these terms and our privacy policy. If you do not agree, please stop using the website.' },
    ],
  },
  {
    title: { sw: '2. Hali ya huduma', en: '2. Service status' },
    body: [
      { sw: 'Soko Vibe bado inaendelezwa. Tovuti hii inaelezea kile tunachojenga na inakusanya nia kupitia orodha ya uzinduzi. Hatuuzi bidhaa, hatupokei malipo, na hatufungui akaunti kwenye tovuti hii.', en: 'Soko Vibe is still in development. This website explains what we are building and collects interest through the launch list. We do not sell products, take payments, or open accounts on this website.' },
      { sw: 'Vipengele vilivyoandikwa “inaendelezwa” au “imepangwa” hazipatikani kwa umma. Hali ya kila kipengele imeelezwa kwenye ukurasa wa vipengele.', en: 'Features marked “in development” or “planned” are not publicly available. Each feature’s status is described on the features page.' },
    ],
  },
  {
    title: { sw: '3. Orodha ya uzinduzi', en: '3. Launch list' },
    body: [
      { sw: 'Kujiunga na orodha ya uzinduzi ni bure. Unakubali kupokea taarifa za uzinduzi na masasisho muhimu kwa barua pepe. Unaweza kujiondoa wakati wowote kupitia kiungo kwenye barua pepe au kwa kuwasiliana nasi.', en: 'Joining the launch list is free. You agree to receive launch news and important updates by email. You can unsubscribe at any time through the link in an email or by contacting us.' },
      { sw: 'Kujiunga hakuhakikishi ufikiaji wa app, nafasi ya kuuza, au tarehe fulani ya uzinduzi.', en: 'Joining does not guarantee access to the app, a seller place, or any particular launch date.' },
    ],
  },
  {
    title: { sw: '4. Matumizi yanayokubalika', en: '4. Acceptable use' },
    body: [
      { sw: 'Usitumie tovuti hii kwa udanganyifu, kutuma spam, kujaribu kuingilia mifumo yetu, kukusanya data ya wengine kwa njia isiyoidhinishwa, au kukiuka sheria yoyote.', en: 'Do not use this website for fraud, spam, attempts to interfere with our systems, unauthorised collection of other people’s data, or any breach of the law.' },
      { sw: 'Tunaweza kuzuia ufikiaji wa tovuti kwa mtumiaji anayekiuka masharti haya au anayehatarisha usalama wa wengine.', en: 'We may block access to the website for anyone who breaks these terms or endangers the safety of others.' },
    ],
  },
  {
    title: { sw: '5. Bei na taarifa za bidhaa', en: '5. Pricing and product information' },
    body: [
      { sw: 'Bei zinazoonyeshwa ni za kabla ya uzinduzi, zinatokana na usanidi wa sasa wa mfumo, na zinaweza kubadilika. Bei halisi itakuwa wazi ndani ya app kabla ya malipo yoyote.', en: 'Prices shown are pre-launch, reflect the current system configuration, and may change. The price that applies will be clear inside the app before any payment.' },
      { sw: 'Soko Vibe inatoza kamisheni ya jukwaa inayolipwa na mnunuzi juu ya bei ya bidhaa (kwa sasa asilimia 3.5); muuzaji hupokea bei kamili ya bidhaa pamoja na usafirishaji. Kiwango kilicho hai kinaonyeshwa kabla ya malipo. Watoa huduma wa malipo wanaweza kutoza ada zao, na ada hizo hazidhibitiwi na Soko Vibe.', en: 'Soko Vibe charges a buyer-pays-top platform commission on the item price (currently 3.5%); the seller still receives the full item price plus shipping. The live rate is shown before payment. Payment providers may charge their own fees, and those fees are not controlled by Soko Vibe.' },
    ],
  },
  {
    title: { sw: '6. Haki miliki', en: '6. Intellectual property' },
    body: [
      { sw: 'Jina la Soko Vibe, nembo, maandishi, michoro na msimbo wa tovuti hii ni mali yetu au ya watoa huduma wetu. Huwezi kunakili, kurekebisha au kutumia kwa biashara bila idhini yetu.', en: 'The Soko Vibe name, logo, text, illustrations and website code belong to us or our licensors. You may not copy, modify or use them commercially without our permission.' },
    ],
  },
  {
    title: { sw: '7. Viungo vya nje', en: '7. External links' },
    body: [
      { sw: 'Tovuti inaweza kuwa na viungo vya tovuti nyingine. Hatuwajibiki kwa maudhui, sera au usalama wa tovuti hizo.', en: 'The website may link to other websites. We are not responsible for their content, policies or security.' },
    ],
  },
  {
    title: { sw: '8. Ukomo wa dhima', en: '8. Limitation of liability' },
    body: [
      { sw: 'Tovuti inatolewa “kama ilivyo”. Kwa kiwango cha juu kinachoruhusiwa na sheria, hatuwajibiki kwa hasara isiyo ya moja kwa moja au hasara inayotokana na kukosa ufikiaji wa tovuti. Hakuna kipengele cha masharti haya kinachozuia dhima kwa udanganyifu au kwa kile sheria isiyoweza kuzuia.', en: 'The website is provided “as is”. To the fullest extent permitted by law, we are not liable for indirect loss or loss caused by inability to access the website. Nothing in these terms limits liability for fraud or for anything the law does not allow to be excluded.' },
    ],
  },
  {
    title: { sw: '9. Sheria inayotawala', en: '9. Governing law' },
    body: [
      { sw: 'Masharti haya yanaongozwa na sheria za Jamhuri ya Muungano wa Tanzania. Migogoro itashughulikiwa na mahakama za Tanzania, isipokuwa pale sheria inavyolazimisha vingine.', en: 'These terms are governed by the laws of the United Republic of Tanzania. Disputes will be handled by the courts of Tanzania, except where the law requires otherwise.' },
    ],
  },
  {
    title: { sw: '10. Mawasiliano', en: '10. Contact' },
    body: [
      { sw: 'Kwa maswali kuhusu masharti haya, andika kwa support@sokovibe.co.tz. Tunaweza kusasisha masharti na tutaonyesha tarehe ya toleo la sasa.', en: 'For questions about these terms, write to support@sokovibe.co.tz. We may update these terms and will show the date of the current version.' },
    ],
  },
];

const COOKIE_SECTIONS = [
  {
    title: { sw: '1. Vidakuzi na hifadhi ya ndani', en: '1. Cookies and local storage' },
    body: [
      { sw: 'Tovuti hii inatumia hifadhi ya ndani ya kivinjari (localStorage) kwa jambo moja tu: kukumbuka lugha uliyochagua (Kiswahili au Kiingereza). Hii inabaki kwenye kifaa chako na haitumwi kwa seva.', en: 'This website uses browser local storage for one purpose only: to remember the language you chose (Kiswahili or English). It stays on your device and is not sent to our server.' },
    ],
  },
  {
    title: { sw: '2. Vidakuzi vya usalama', en: '2. Security cookies' },
    body: [
      { sw: 'Cloudflare, inayolinda tovuti yetu, inaweza kuweka vidakuzi vya usalama kama __cf_bm na cf_clearance. Hivi husaidia kutambua bots na kulinda tovuti dhidi ya mashambulizi. Ni vya lazima kwa huduma na havitumiki kwa matangazo.', en: 'Cloudflare, which protects our website, may set security cookies such as __cf_bm and cf_clearance. These help identify bots and protect the website from attacks. They are necessary for the service and are not used for advertising.' },
    ],
  },
  {
    title: { sw: '3. Hatuweki vidakuzi vya uchambuzi', en: '3. No analytics or advertising cookies' },
    body: [
      { sw: 'Kwa sasa hatutumii Google Analytics, pikseli za matangazo au vidakuzi vya ufuatiliaji wa tabia. Kwa hiyo hakuna bango la ridhaa ya vidakuzi. Kama tutaanzisha uchambuzi baadaye, tutasasisha sera hii na kuomba ridhaa inapohitajika.', en: 'We currently do not use Google Analytics, advertising pixels or behavioural tracking cookies. That is why there is no cookie consent banner. If we introduce analytics later, we will update this policy and ask for consent where required.' },
    ],
  },
  {
    title: { sw: '4. Jinsi ya kudhibiti', en: '4. How to control it' },
    body: [
      { sw: 'Unaweza kufuta hifadhi ya ndani na vidakuzi kupitia mipangilio ya kivinjari chako. Kufuta hifadhi ya lugha kutafanya tovuti ianze tena kwa Kiswahili. Kuzuia vidakuzi vya usalama kunaweza kuzuia ufikiaji wa tovuti.', en: 'You can clear local storage and cookies through your browser settings. Clearing the language store will make the site start in Kiswahili again. Blocking security cookies may prevent access to the website.' },
    ],
  },
];

function docSection(section) {
  return `<section class="sv-doc__section">
    ${t('h2', section.title.sw, section.title.en, { class: 'sv-h3' })}
    ${section.body.map((p) => t('p', p.sw, p.en)).join('\n    ')}
  </section>`;
}

function legalPage({ file, path, active, title, description, heading, lead, updated, sections, extra = '' }) {
  const meta = pageMeta({
    title,
    description,
    path,
    jsonLd: [
      seo.webpage({ path, title, description }),
      seo.breadcrumbs([{ name: 'Mwanzo', path: '/' }, { name: heading.sw, path }]),
    ],
  });

  const body = `${pageHero({
    eyebrow: { sw: 'Kisheria', en: 'Legal' },
    title: heading,
    lead,
    breadcrumb: heading.sw,
  })}

<section class="sv-section">
  <div class="sv-container sv-doc">
    <p class="sv-doc__updated">${t('span', `Ilisasishwa mwisho: ${updated.sw}`, `Last updated: ${updated.en}`)}</p>
    ${sections.map(docSection).join('\n')}
    ${extra}
    <nav class="sv-doc__nav" aria-label="Kurasa za kisheria" data-en-aria-label="Legal pages">
      <a href="/privacy"${path === '/privacy' ? ' aria-current="page"' : ''} data-en="Privacy policy">Sera ya faragha</a>
      <a href="/terms"${path === '/terms' ? ' aria-current="page"' : ''} data-en="Terms of use">Masharti ya matumizi</a>
      <a href="/cookies"${path === '/cookies' ? ' aria-current="page"' : ''} data-en="Cookie policy">Sera ya vidakuzi</a>
      <a href="/data-deletion"${path === '/data-deletion' ? ' aria-current="page"' : ''} data-en="Data deletion">Kufuta data</a>
    </nav>
    <div class="sv-doc__contact">
      ${icon('mail', 'sv-icon--sm')}
      <p>${t('span', 'Maswali? Andika kwa', 'Questions? Write to')} <a href="mailto:${SITE.privacyEmail}">${SITE.privacyEmail}</a> ${t('span', 'au', 'or')} <a href="mailto:${SITE.email}">${SITE.email}</a>.</p>
    </div>
  </div>
</section>

${ctaSection({
  title: { sw: 'Pata taarifa za uzinduzi.', en: 'Get launch updates.' },
  lead: { sw: 'Jiunge na orodha ya uzinduzi. Unaweza kujiondoa wakati wowote.', en: 'Join the launch list. You can unsubscribe at any time.' },
})}`;

  return { file, html: layout({ meta, active, body }) };
}

function privacyPage() {
  return legalPage({
    file: 'privacy.html',
    path: '/privacy',
    active: '',
    title: 'Sera ya Faragha | Soko Vibe Privacy Policy',
    description: 'Jinsi Soko Vibe inavyokusanya, kutumia na kulinda data yako kwenye tovuti ya kabla ya uzinduzi, pamoja na haki zako chini ya sheria ya Tanzania.',
    heading: { sw: 'Sera ya faragha', en: 'Privacy policy' },
    lead: { sw: 'Tunakusanya taarifa chache tu, tunaeleza kwa nini, na tunakupa njia ya kuzifuta.', en: 'We collect only a small amount of information, explain why, and give you a way to delete it.' },
    updated: { sw: UPDATED_SW, en: UPDATED_EN },
    sections: PRIVACY,
  });
}

function termsPage() {
  return legalPage({
    file: 'terms.html',
    path: '/terms',
    active: '',
    title: 'Masharti ya Matumizi | Soko Vibe Terms of Use',
    description: 'Masharti ya kutumia tovuti ya Soko Vibe kabla ya uzinduzi: hali ya huduma, orodha ya uzinduzi, matumizi yanayokubalika, bei na dhima.',
    heading: { sw: 'Masharti ya matumizi', en: 'Terms of use' },
    lead: { sw: 'Masharti rahisi yanayoeleza uhusiano kati yako na tovuti hii ya kabla ya uzinduzi.', en: 'Plain terms explaining the relationship between you and this pre-launch website.' },
    updated: { sw: UPDATED_SW, en: UPDATED_EN },
    sections: TERMS,
  });
}

function cookiesPage() {
  return legalPage({
    file: 'cookies.html',
    path: '/cookies',
    active: '',
    title: 'Sera ya Vidakuzi | Soko Vibe Cookie Policy',
    description: 'Tovuti ya Soko Vibe inatumia hifadhi ya lugha na vidakuzi vya usalama vya Cloudflare pekee. Hatuweki vidakuzi vya uchambuzi au matangazo.',
    heading: { sw: 'Sera ya vidakuzi', en: 'Cookie policy' },
    lead: { sw: 'Vidakuzi vichache, vinavyoeleweka, na hakuna ufuatiliaji wa matangazo.', en: 'Few cookies, clearly explained, and no advertising tracking.' },
    updated: { sw: UPDATED_SW, en: UPDATED_EN },
    sections: COOKIE_SECTIONS,
  });
}

function dataDeletionPage() {
  const title = 'Kufuta Data Yako | Delete Your Soko Vibe Data';
  const description = 'Omba Soko Vibe kufuta data yako ya orodha ya uzinduzi au mawasiliano. Maombi hushughulikiwa ndani ya siku 14 za kazi.';
  const meta = pageMeta({
    title,
    description,
    path: '/data-deletion',
    jsonLd: [
      seo.webpage({ path: '/data-deletion', title, description }),
      seo.breadcrumbs([{ name: 'Mwanzo', path: '/' }, { name: 'Kufuta data', path: '/data-deletion' }]),
    ],
  });

  const body = `${pageHero({
    eyebrow: { sw: 'Faragha', en: 'Privacy' },
    title: { sw: 'Omba kufuta data yako.', en: 'Request deletion of your data.' },
    lead: { sw: 'Tumia fomu hii kama unataka tuondoe barua pepe, ujumbe au taarifa nyingine uliyotuma kwenye tovuti hii.', en: 'Use this form if you want us to remove your email address, message or other information you sent through this website.' },
    breadcrumb: 'Kufuta data',
  })}

<section class="sv-section">
  <div class="sv-container sv-doc">
    <div class="sv-doc__form">
      <h2 class="sv-h3" data-en="Deletion request">Ombi la kufuta data</h2>
      <p data-en="We will confirm receipt by email and complete the request within 14 working days, unless the law requires us to keep something.">Tutathibitisha kupokea kwa barua pepe na kukamilisha ombi ndani ya siku 14 za kazi, isipokuwa sheria inatulazimu kuhifadhi jambo fulani.</p>
      <form class="sv-form" data-deletion novalidate>
        <div class="sv-form__grid">
          <div class="sv-field">
            <label for="del-name" data-en="Full name (optional)">Jina kamili (hiari)</label>
            <input id="del-name" name="fullName" type="text" autocomplete="name" maxlength="120" ${'' /* optional */}>
          </div>
          <div class="sv-field">
            <label for="del-email" data-en="Email address">Barua pepe</label>
            <input id="del-email" name="email" type="email" inputmode="email" autocomplete="email" required maxlength="254" placeholder="jina@mfano.com" data-en-placeholder="you@example.com" aria-describedby="del-status">
          </div>
        </div>
        <div class="sv-field">
          <label for="del-phone" data-en="Phone number (optional)">Namba ya simu (hiari)</label>
          <input id="del-phone" name="phone" type="tel" autocomplete="tel" maxlength="20" placeholder="+255 7XX XXX XXX">
        </div>
        <div class="sv-field">
          <label for="del-reason" data-en="What should we delete? (optional)">Tufute nini? (hiari)</label>
          <textarea id="del-reason" name="reason" rows="4" maxlength="2000" data-en-placeholder="For example: remove me from the launch list"></textarea>
        </div>
        <div class="sv-hp" aria-hidden="true">
          <label for="del-website">Website</label>
          <input id="del-website" name="website" type="text" tabindex="-1" autocomplete="off">
        </div>
        <div class="sv-form__actions">
          <button class="sv-btn sv-btn--primary" type="submit">
            <span data-en="Submit request">Tuma ombi</span>
            <span class="sv-btn__spinner" aria-hidden="true"></span>
          </button>
          <p class="sv-help" data-en="We will only use these details to handle your request.">Tutatumia taarifa hizi pekee kushughulikia ombi lako.</p>
        </div>
        <p class="sv-status" id="del-status" role="status" aria-live="polite" data-form-status></p>
      </form>
    </div>
    <div class="sv-doc__section">
      ${t('h2', 'Nini kinatokea baada ya ombi?', 'What happens after you ask?', { class: 'sv-h3' })}
      ${t('p', 'Tunathibitisha kupokea, tunatafuta taarifa zinazohusiana na barua pepe au namba uliyotoa, na tunazifuta au tunazifanya zisitambulike. Kama tuna hifadhi ya kisheria inayotulazimu kuendelea kushikilia taarifa fulani, tutakueleza.', 'We confirm receipt, look for information linked to the email address or phone number you provide, and delete it or make it non-identifiable. If a legal obligation requires us to keep something, we will tell you.')}
      ${t('p', 'Kama huna ufikiaji wa barua pepe uliyotumia, wasiliana nasi kwa support@sokovibe.co.tz na tutakusaidia kwa njia nyingine.', 'If you no longer have access to the email address you used, contact us at support@sokovibe.co.tz and we will help another way.')}
    </div>
    <nav class="sv-doc__nav" aria-label="Kurasa za kisheria" data-en-aria-label="Legal pages">
      <a href="/privacy" data-en="Privacy policy">Sera ya faragha</a>
      <a href="/terms" data-en="Terms of use">Masharti ya matumizi</a>
      <a href="/cookies" data-en="Cookie policy">Sera ya vidakuzi</a>
      <a href="/data-deletion" aria-current="page" data-en="Data deletion">Kufuta data</a>
    </nav>
  </div>
</section>

${ctaSection({
  title: { sw: 'Pata taarifa za uzinduzi.', en: 'Get launch updates.' },
  lead: { sw: 'Jiunge na orodha ya uzinduzi. Unaweza kujiondoa wakati wowote.', en: 'Join the launch list. You can unsubscribe at any time.' },
})}`;

  return { file: 'data-deletion.html', html: layout({ meta, active: '', body }) };
}

module.exports = { privacyPage, termsPage, cookiesPage, dataDeletionPage };
