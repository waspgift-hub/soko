'use strict';

const { SITE, t, icon } = require('../core');
const { pageMeta, layout, pageHero, contactForm, ctaSection } = require('../components');
const seo = require('../seo');

function contactPage() {
  const title = 'Mawasiliano | Contact Soko Vibe';
  const description = 'Wasiliana na Soko Vibe kwa maswali, msaada au taarifa za uzinduzi. Barua pepe: support@sokovibe.co.tz. WhatsApp: +255 693 273 241.';
  const meta = pageMeta({
    title,
    description,
    path: '/contact',
    jsonLd: [
      seo.organization(),
      seo.webpage({ path: '/contact', title, description }),
      seo.breadcrumbs([{ name: 'Mwanzo', path: '/' }, { name: 'Mawasiliano', path: '/contact' }]),
    ],
  });

  const body = `${pageHero({
    eyebrow: { sw: 'Mawasiliano', en: 'Contact' },
    title: { sw: 'Tuko hapa kusikiliza.', en: 'We are here to listen.' },
    lead: { sw: 'Tuma swali, pendekezo au tatizo. Tutakujibu kwa uwazi na kwa heshima.', en: 'Send a question, suggestion or problem. We will reply honestly and respectfully.' },
    breadcrumb: 'Mawasiliano',
  })}

<section class="sv-section">
  <div class="sv-container sv-contact">
    <div class="sv-contact__form">
      ${t('h2', 'Tutumie ujumbe', 'Send us a message', { class: 'sv-h2' })}
      ${t('p', 'Sehemu zote zilizo na * zinahitajika. Ujumbe wako unatumwa kwa usalama na huhifadhiwa kwa ajili ya kujibu tu.', 'Fields marked * are required. Your message is sent securely and stored only so we can reply.', { class: 'sv-muted' })}
      ${contactForm()}
    </div>
    <aside class="sv-contact__aside" aria-label="Njia nyingine za mawasiliano" data-en-aria-label="Other ways to contact us">
      <div class="sv-contactcard">
        <span>${icon('mail')}</span>
        <div>
          <h2 data-en="Email support">Msaada wa barua pepe</h2>
          <a href="mailto:${SITE.email}">${SITE.email}</a>
          <p data-en="For general questions, waitlist and account help.">Kwa maswali ya jumla, orodha ya uzinduzi na msaada wa akaunti.</p>
        </div>
      </div>
      <div class="sv-contactcard">
        <span>${icon('chat')}</span>
        <div>
          <h2 data-en="WhatsApp">WhatsApp</h2>
          <a href="https://wa.me/${SITE.phone.replace('+', '')}" rel="noopener">${SITE.phoneDisplay}</a>
          <p data-en="Message us during working hours in Tanzania (EAT).">Tutumie ujumbe wakati wa saa za kazi Tanzania (EAT).</p>
        </div>
      </div>
      <div class="sv-contactcard">
        <span>${icon('lock')}</span>
        <div>
          <h2 data-en="Privacy and data">Faragha na data</h2>
          <a href="mailto:${SITE.privacyEmail}">${SITE.privacyEmail}</a>
          <p data-en="For access, correction or deletion requests.">Kwa maombi ya kufikia, kurekebisha au kufuta data.</p>
        </div>
      </div>
      <div class="sv-contactcard sv-contactcard--quiet">
        <span>${icon('document')}</span>
        <div>
          <h2 data-en="Before you write">Kabla ya kuandika</h2>
          <p data-en="Many answers are already in the FAQ, including launch timing, pricing and data use.">Majibu mengi yapo kwenye maswali ya kawaida, ikiwa ni pamoja na muda wa uzinduzi, bei na matumizi ya data.</p>
          <a class="sv-link" href="/faq">${t('span', 'Soma maswali', 'Read the FAQ')} ${icon('arrow', 'sv-icon--sm')}</a>
        </div>
      </div>
    </aside>
  </div>
</section>

<section class="sv-section sv-section--tint">
  <div class="sv-container sv-narrow sv-center">
    ${t('h2', 'Tunajibu lini?', 'When do we reply?', { class: 'sv-h2' })}
    ${t('p', 'Kwa kawaida ndani ya siku mbili za kazi. Kama ujumbe wako unahusu usalama au data, tutautanguliza.', 'Usually within two working days. If your message concerns safety or data, we will prioritise it.', { class: 'sv-lead' })}
    <p class="sv-disclaimer">${icon('document', 'sv-icon--sm')} ${t('span', 'Hatutawahi kukuomba nenosiri, OTP au namba ya kadi kwa barua pepe au simu.', 'We will never ask for your password, OTP or card number by email or phone.')}</p>
  </div>
</section>`;

  return { file: 'contact.html', html: layout({ meta, active: '/contact', body }) };
}

function successPage() {
  const title = 'Umejiunga na Orodha | You are on the Soko Vibe list';
  const description = 'Asante kwa kujiunga na orodha ya uzinduzi ya Soko Vibe. Tutakutumia taarifa tutakapozindua.';
  const meta = pageMeta({
    title,
    description,
    path: '/waitlist/success',
    noindex: true,
    jsonLd: [seo.webpage({ path: '/waitlist/success', title, description })],
  });

  const body = `<section class="sv-success">
  <div class="sv-container sv-success__inner">
    <span class="sv-success__mark">${icon('check')}</span>
    ${t('p', 'Orodha ya uzinduzi', 'Launch list', { class: 'sv-eyebrow' })}
    ${t('h1', 'Umejiunga na orodha!', 'You are on the list!', { class: 'sv-h1' })}
    ${t('p', 'Tutakutumia taarifa tutakapozindua Soko Vibe. Asante kwa kuwa sehemu ya safari hii.', 'We will let you know when Soko Vibe launches. Thank you for being part of the journey.', { class: 'sv-lead sv-lead--lg' })}
    <div class="sv-success__steps">
      <div><b>1</b><h2 data-en="Check your inbox">Angalia barua pepe yako</h2><p data-en="If email delivery is configured, a confirmation will arrive shortly. Check spam if you do not see it.">Kama utumaji wa barua pepe umewekwa, uthibitisho utafika hivi karibuni. Angalia spam kama hauoni.</p></div>
      <div><b>2</b><h2 data-en="We keep building">Tunaendelea kujenga</h2><p data-en="We are completing the core app experience before inviting people in.">Tunakamilisha uzoefu wa msingi wa app kabla ya kukaribisha watu.</p></div>
      <div><b>3</b><h2 data-en="You hear from us">Tutawasiliana nawe</h2><p data-en="We will send a short update when we are ready. No spam.">Tutatumia taarifa fupi tutakapokuwa tayari. Hakuna barua taka.</p></div>
    </div>
    <div class="sv-actions sv-actions--center">
      <a class="sv-btn sv-btn--primary" href="/" data-en="Back to home">Rudi mwanzo</a>
      <a class="sv-btn sv-btn--ghost" href="/features" data-en="Explore features">Chunguza vipengele</a>
    </div>
    <p class="sv-muted">${t('span', 'Hauoni barua pepe? Angalia folda ya spam au wasiliana nasi kwa support@sokovibe.co.tz.', 'No email? Check your spam folder or contact us at support@sokovibe.co.tz.')}</p>
  </div>
</section>`;

  return { file: 'waitlist-success.html', html: layout({ meta, active: '', body }) };
}

function unsubscribePage() {
  const title = 'Jiondoe kwenye Orodha | Unsubscribe from Soko Vibe';
  const description = 'Jiondoe kwenye taarifa za Soko Vibe.';
  const meta = pageMeta({
    title,
    description,
    path: '/unsubscribe',
    noindex: true,
    jsonLd: [],
  });

  const body = `<section class="sv-success">
  <div class="sv-container sv-success__inner">
    <span class="sv-success__mark sv-success__mark--muted">${icon('mail')}</span>
    ${t('p', 'Orodha ya uzinduzi', 'Launch list', { class: 'sv-eyebrow' })}
    ${t('h1', 'Jiondoe kwenye taarifa.', 'Unsubscribe from updates.', { class: 'sv-h1' })}
    ${t('p', 'Tunapenda kuheshimu chaguo lako. Bonyeza kitufe hapa chini ili kuondoa barua pepe hii kwenye orodha yetu ya uzinduzi.', 'We respect your choice. Press the button below to remove this email from our launch list.', { class: 'sv-lead' })}
    <div class="sv-unsub" data-unsub>
      <p class="sv-status" role="status" aria-live="polite" data-unsub-status></p>
      <div class="sv-actions sv-actions--center" data-unsub-actions hidden>
        <button class="sv-btn sv-btn--primary" type="button" data-unsub-confirm data-en="Confirm unsubscribe">Thibitisha kujiondoa</button>
        <a class="sv-btn sv-btn--ghost" href="/" data-en="Keep me subscribed">Nibaki kwenye orodha</a>
      </div>
      <p class="sv-muted" data-unsub-fallback hidden>${t('span', 'Kiungo hiki si sahihi au kimekwisha tumika. Wasiliana nasi kwa support@sokovibe.co.tz tukusaidie.', 'This link is invalid or has already been used. Contact us at support@sokovibe.co.tz and we will help.')}</p>
    </div>
    <p class="sv-muted">${t('span', 'Unaweza pia kuwasiliana nasi kwa support@sokovibe.co.tz.', 'You can also contact us at support@sokovibe.co.tz.')}</p>
  </div>
</section>`;

  return { file: 'unsubscribe.html', html: layout({ meta, active: '', body }) };
}

function founderPage() {
  const title = 'Gift Henry Wapalila — Mwanzilishi wa Soko Vibe';
  const description = 'Gift Henry Wapalila ni mwanzilishi wa Soko Vibe, soko la mtandaoni la Tanzania linalojengwa kwa wanunuzi na wauzaji.';
  const meta = pageMeta({
    title,
    description,
    path: '/about/founder',
    jsonLd: [
      seo.organization(),
      seo.webpage({ path: '/about/founder', title, description }),
      seo.breadcrumbs([{ name: 'Mwanzo', path: '/' }, { name: 'Kuhusu', path: '/about' }, { name: 'Mwanzilishi', path: '/about/founder' }]),
      {
        '@context': 'https://schema.org',
        '@type': 'Person',
        '@id': `${SITE.host}/#founder`,
        name: 'Gift Henry Wapalila',
        jobTitle: 'Founder of Soko Vibe',
        worksFor: { '@id': `${SITE.host}/#organization` },
      },
    ],
  });

  const body = `${pageHero({
    eyebrow: { sw: 'Mwanzilishi', en: 'Founder' },
    title: { sw: 'Gift Henry Wapalila', en: 'Gift Henry Wapalila' },
    lead: { sw: 'Mwanzilishi wa Soko Vibe — soko la mtandaoni linalojengwa Dar es Salaam kwa ajili ya Tanzania.', en: 'Founder of Soko Vibe — an online marketplace being built in Dar es Salaam for Tanzania.' },
    breadcrumb: 'Mwanzilishi',
  })}

<section class="sv-section">
  <div class="sv-container sv-split">
    <div class="sv-split__copy">
      ${t('h2', 'Kwa nini Soko Vibe?', 'Why Soko Vibe?', { class: 'sv-h2' })}
      ${t('p', 'Gift Henry Wapalila ndiye mwanzilishi wa Soko Vibe. Anajenga jukwaa hili kwa lengo la kuleta ununuzi na mauzo ya mtandaoni Tanzania kwenye njia rahisi, yenye mpangilio na inayotumainika zaidi.', 'Gift Henry Wapalila is the founder of Soko Vibe. He is building the platform to bring online buying and selling in Tanzania onto a simpler, better organised and more trustworthy path.', { class: 'sv-lead' })}
      ${t('p', 'Wazo linaanzia kwenye uzoefu wa kila siku: wauzaji wazuri wapo, wanunuzi wapo, lakini njia ya kuwaunganisha bado inahitaji maboresho. Soko Vibe ni jitihada ya kujenga sehemu moja inayoeleweka kwa wote wawili.', 'The idea comes from everyday experience: good sellers exist, buyers exist, but the way to connect them still needs work. Soko Vibe is an effort to build one place that makes sense to both sides.')}
      ${t('h3', 'Kile tunachojenga', 'What we are building', { class: 'sv-h3' })}
      ${t('p', 'App bado iko kwenye maendeleo. Tovuti hii inaeleza kile tunachojenga na inakusanya nia ya wanunuzi na wauzaji kupitia orodha ya uzinduzi. Hatuwasilishi huduma ambayo haijakamilika kama inapatikana.', 'The app is still in development. This website explains what we are building and collects buyer and seller interest through the launch list. We do not present an unfinished service as available.')}
      <div class="sv-actions">
        <a class="sv-btn sv-btn--primary" href="/#waitlist" data-en="Join the launch list">Jiunge na orodha ya uzinduzi</a>
        <a class="sv-btn sv-btn--ghost" href="/about" data-en="About Soko Vibe">Kuhusu Soko Vibe</a>
      </div>
    </div>
    <div class="sv-split__aside">
      <div class="sv-person">
        <img src="/assets/icon-192.png" alt="" width="72" height="72">
        <h2>Gift Henry Wapalila</h2>
        <p data-en="Founder, Soko Vibe">Mwanzilishi, Soko Vibe</p>
        <p data-en="Dar es Salaam, Tanzania">Dar es Salaam, Tanzania</p>
        <a class="sv-link" href="mailto:${SITE.email}">${SITE.email}</a>
      </div>
      <div class="sv-statcard"><span class="sv-statcard__icon">${icon('pin')}</span>${t('h3', 'Dar es Salaam', 'Dar es Salaam', { class: 'sv-h3' })}${t('p', 'Soko Vibe linajengwa Tanzania, kwa ajili ya soko la Tanzania.', 'Soko Vibe is being built in Tanzania, for the Tanzanian market.')}</div>
    </div>
  </div>
</section>

${ctaSection({
  title: { sw: 'Kuwa sehemu ya safari.', en: 'Be part of the journey.' },
  lead: { sw: 'Jiunge na orodha ya uzinduzi na upokee taarifa za maendeleo.', en: 'Join the launch list for development updates.' },
})}`;

  return { file: 'about-founder.html', html: layout({ meta, active: '/about', body }) };
}

module.exports = { contactPage, successPage, unsubscribePage, founderPage };
