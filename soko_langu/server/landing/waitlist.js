/* Soko Vibe — coming-soon page: i18n (sw/en) + Firebase waitlist/feedback/comments. */
(function () {
  'use strict';

  var LANG_KEY = 'soko_vibe_waitlist_lang';
  var THEME_KEY = 'soko_vibe_waitlist_theme';

  /* ───────────────────────── i18n ───────────────────────── */
  var I18N = {
    sw: {
      doc_title: 'Soko Vibe — Soko la Mtandaoni Tanzania | Tanzania Online Marketplace',
      doc_desc: 'Soko Vibe ni soko la mtandaoni la Tanzania. Weka bidhaa bure, nunua kwa malipo ya escrow kupitia ClickPesa, na upokee bidhaa nchi nzima.',

      nav_sifa: 'Sifa',
      nav_how: 'Jinsi Inavyofanya Kazi',
      nav_fees: 'Ada',
      nav_faq: 'Maswali',
      nav_app: 'App',
      nav_menu: 'Menyu',

      hero_badge: 'Soko la Tanzania · hatua ya awali',
      hero_h1_1: 'Nunua na uza Tanzania,',
      hero_h1_2: 'kwa malipo yaliyolindwa.',
      hero_sub: 'Soko Vibe ni soko la mtandaoni la Tanzania linalounganisha wanunuzi na wauzaji. Weka bidhaa bure, wasiliana moja kwa moja na muuzaji, na lipa kwa escrow — kote nchini.',
      hero_cta_1: 'Jiunge na orodha ya taarifa',
      hero_cta_2: 'Vinjari kategoria',
      fact_escrow: 'Escrow kupitia ClickPesa',
      fact_kyc: 'Wauzaji waliothibitishwa (KYC)',
      fact_delivery: 'Usafirishaji nchi nzima',

      sifa_eyebrow: 'Soko Vibe ni nini',
      sifa_h2: 'Soko moja la Tanzania, kwa wanunuzi na wauzaji.',
      sifa_lead: 'Soko Vibe ni jukwaa la kidijitali linaloendeshwa kutoka Dar es Salaam. Linawaunganisha wanunuzi na wauzaji wa bidhaa kote Tanzania, kwa mazungumzo ya moja kwa moja na malipo yanayolindwa.',
      aud_b_t: 'Kwa wanunuzi',
      aud_b_p: 'Tafuta bidhaa mpya na za mitumba, linganisha bei, na uliza muuzaji moja kwa moja kabla ya kununua. Malipo yako yanalindwa hadi uthibitishe kupokea.',
      aud_s_t: 'Kwa wauzaji na biashara',
      aud_s_p: 'Weka bidhaa bure, thibitisha utambulisho (KYC), na simamia duka lako kwenye dashboard moja — pamoja na boost za hiari na takwimu za mauzo.',
      aud_c_t: 'Kategoria halisi',
      aud_c_p: 'Elektroniki, mavazi, nyumba na bustani, magari, afya na urembo, chakula, na huduma — bidhaa zimepangwa ili kuvinjari kwa urahisi.',
      lnk_market: 'Soko la Tanzania',
      lnk_cats: 'Kategoria zote',
      lnk_how: 'Jinsi inavyofanya kazi',
      lnk_about: 'Kuhusu Soko Vibe',

      how_eyebrow: 'Jinsi inavyofanya kazi',
      how_h2: 'Hatua nne kutoka kutafuta hadi kupokea.',
      how_lead: 'Kila agizo linafuata mchakato mmoja unaolinda pande zote mbili.',
      st1_n: 'Hatua 01',
      st1_t: 'Fungua akaunti',
      st1_p: 'Jisajili kama mnunuzi au muuzaji. Wauzaji huthibitisha utambulisho (KYC) kabla ya kuanza kuuza.',
      st2_n: 'Hatua 02',
      st2_t: 'Tafuta na zungumza',
      st2_p: 'Vinjari kategoria au tafuta kwa maandishi na kwa sauti, kisha uliza muuzaji ndani ya app.',
      st3_n: 'Hatua 03',
      st3_t: 'Lipa kwa escrow',
      st3_p: 'Lipa kwa mobile money. Fedha zinashikiliwa kwa escrow kupitia ClickPesa, si kwa muuzaji bado.',
      st4_n: 'Hatua 04',
      st4_t: 'Thibitisha na kadiria',
      st4_p: 'Pokea bidhaa, thibitisha kwa OTP, na fedha hutolewa kwa muuzaji. Kama kuna tatizo, fungua mgogoro.',
      lnk_how_full: 'Soma maelezo kamili ya jinsi inavyofanya kazi →',

      fee_eyebrow: 'Ada zilizo wazi',
      fee_h2: 'Hakuna ada zilizofichwa.',
      fee_lead: 'Unajua unalipa nini kabla ya kukamilisha ununuzi.',
      fee1_t: 'Kufungua orodha',
      fee1_amt: 'Bure',
      fee1_basis: 'Kwa kila muuzaji',
      fee1_p: 'Weka bidhaa bila gharama. Hakuna ada ya kuuza na hakuna usajili wa kudumu.',
      fee2_t: 'Ada ya jukwaa',
      fee2_amt: '3.5%',
      fee2_basis: 'Kwa mnunuzi, wakati wa ununuzi',
      fee2_p: 'Muuzaji hupokea bei kamili ya bidhaa. Ada inaonekana wazi kabla ya malipo kukamilika.',
      lnk_fees: 'Ada zote na udhamini →',
      lnk_escrow: 'Escrow na usalama wa malipo →',

      faq_eyebrow: 'Maswali',
      faq_h2: 'Maswali yanayoulizwa mara kwa mara.',
      q1: 'Soko Vibe ni nini?',
      a1: 'Soko Vibe ni soko la mtandaoni la Tanzania linalounganisha wanunuzi na wauzaji. Huduma inaendeshwa kutoka Dar es Salaam, na bidhaa zinapatikana kote nchini.',
      q2: 'Ninawezaje kununua bidhaa kwenye Soko Vibe?',
      a2: 'Fungua akaunti, tafuta bidhaa kwa maandishi au kwa sauti, zungumza na muuzaji ndani ya app, lipa kwa escrow, kisha thibitisha kupokea kwa OTP.',
      q3: 'Malipo yangu yanalindwaje?',
      a3: 'Malipo yanaingia escrow kupitia ClickPesa na hutolewa kwa muuzaji tu baada ya mnunuzi kuthibitisha kupokea bidhaa. Mgogoro unaweza kufunguliwa na kushughulikiwa hadi siku 14.',
      q4: 'Je, kuweka bidhaa kwenye Soko Vibe ni bure?',
      a4: 'Ndiyo. Kufungua orodha ni bure na muuzaji hupokea bei kamili ya bidhaa. Soko Vibe hutoza ada ya jukwaa ya 3.5% kwa mnunuzi wakati wa ununuzi. Udhamini (boost) ni wa hiari.',
      q5: 'Naipataje app ya Soko Vibe?',
      a5: 'App ya Android inapatikana kwa link rasmi kupitia WhatsApp ya Soko Vibe. Viungo vya Google Play na App Store vitaongezwa mara app itakapochapishwa kwenye maduka.',
      q6: 'Ninawezaje kupata msaada?',
      a6: 'Wasiliana nasi kwa barua pepe support@sokovibe.co.tz, kwa WhatsApp +255 693 273 241, au tembelea kituo cha msaada.',
      lnk_support: 'Kituo cha msaada →',

      app_eyebrow: 'App',
      app_h2: 'Soko Vibe mfukoni mwako.',
      app_p: 'App ya Android inapatikana kwa link rasmi kupitia WhatsApp. Viungo vya Google Play na App Store vitaongezwa mara app itakapochapishwa kwenye maduka — hakuna kiungo cha kubuni kinachoonekana hapa.',
      app_cta: 'Omba app kwa WhatsApp',
      app_cta2: 'Nipe taarifa za uzinduzi',
      app_note: 'Msaada: support@sokovibe.co.tz · WhatsApp +255 693 273 241',

      wl_title: 'Jiandikishe, upate taarifa',
      wl_sub: 'Tutakuarifu kuhusu uzinduzi, masasisho na viungo vya maduka ya app.',
      wl_name: 'Jina lako',
      wl_name_ph: 'Jina (si lazima)',
      wl_email: 'Barua pepe',
      wl_email_ph: 'mwandishi@mfano.co.tz',
      wl_cta: 'Nipe taarifa',
      wl_note: 'Barua pepe yako inatumika tu kukutumia taarifa za Soko Vibe. Hakuna spam.',
      wl_done_title: 'Umefanikiwa!',
      wl_done_body: 'Umeingizwa kwenye orodha. Tutakuarifu mara app na viungo vya maduka vitakapozinduliwa.',

      fb_eyebrow: 'Maoni yako yanahesabika',
      fb_h2: 'Unataka app iwe na nini?',
      fb_sub: 'Chagua vipengele na utueleze maoni yako. Tunasikiliza kila mmoja.',
      fb_features: 'Vipengele unavyovipenda',
      fb_f1: 'Escrow Salama', fb_f2: 'Chat ya Moja kwa Moja', fb_f3: 'Usafirishaji nchi nzima',
      fb_f4: 'Utafutaji wa Sauti / AI', fb_f5: 'Duka la Mfanyabiashara', fb_f6: 'Pochi ya Simu',
      fb_f7: 'Ukadiriaji wa Wauzaji', fb_f8: 'Lugha nyingi',
      fb_details: 'Maoni / maelezo zaidi',
      fb_details_ph: 'Mfano: ningependa aina ya kikokotoo cha bei...',
      fb_name: 'Jina', fb_email: 'Barua pepe', fb_cta: 'Tuma maoni',

      cm_eyebrow: 'Jamii imesema',
      cm_h2: 'Maoni ya wananchi',
      cm_name: 'Jina lako', cm_email: 'Barua pepe', cm_text: 'Maoni yako',
      cm_text_ph: 'Maoni yako kuhusu Soko Vibe...',
      cm_cta: 'Chapisha maoni',

      cta_h2: 'Tayari kuanza?',
      cta_p: 'Jiunge na orodha ya taarifa, au wasiliana nasi moja kwa moja — tunajibu kwa Kiswahili na Kiingereza.',
      cta_btn: 'Jiandikishe sasa',

      f_tagline: 'Soko linaloaminika la Tanzania — kwa usalama na urahisi.',
      f_company: 'Kampuni', f_privacy: 'Sera ya Faragha', f_terms: 'Masharti ya Huduma',
      f_support: 'Msaada', f_help: 'Kituo cha Msaada',
      f_rights: 'Soko Vibe Limited. Haki zote zimehifadhiwa.',
      f_made: 'Imetengenezwa kwa upendo nchini Tanzania 🇹🇿',

      cm_tag_lbl: 'Anaitaka:',
      cm_empty: 'Hakuna maoni bado — kuwa wa kwanza kutoa maoni!',
      cm_bad_name: 'Andika jina lako (hatua 2+).',
      cm_bad_email: 'Andika barua pepe halali.',
      cm_bad_text: 'Andika maoni yako (hatua 3+).',
      fb_bad_empty: 'Chagua angalau kipengele kimoja au andika maelezo.',
      wl_bad_email: 'Andika barua pepe halali.',
      fb_ok: 'Asante! Maoni yako yamesajiliwa.',
      cm_ok: 'Asante! Maoni yako yamechapishwa.',
      wl_ok: 'Umesajiliwa! Tutakuarifu kuhusu uzinduzi.',
      wl_dup: 'Barua pepe hii tayari ipo kwenye orodha. Asante!',
      fb_err: 'Samahani, maoni yako yalishindikana. Jaribu tena baadaye.',
      cm_err: 'Samahani, tushindwe kutuma. Jaribu tena baadaye.',
      wl_err: 'Samahani, tushindwe kukusajili. Jaribu tena baadaye.',
      theme_lbl: 'Badili mwonekano', lang_lbl: 'Badili lugha'
    },
    en: {
      doc_title: 'Soko Vibe — Tanzania Online Marketplace | Buy & Sell in Tanzania',
      doc_desc: 'Soko Vibe is a Tanzania-based online marketplace. List products for free, buy with ClickPesa escrow protection, and get delivery nationwide.',

      nav_sifa: 'Why Soko Vibe',
      nav_how: 'How It Works',
      nav_fees: 'Fees',
      nav_faq: 'FAQ',
      nav_app: 'App',
      nav_menu: 'Menu',

      hero_badge: 'Tanzania’s marketplace · early stage',
      hero_h1_1: 'Buy and sell in Tanzania,',
      hero_h1_2: 'with protected payments.',
      hero_sub: 'Soko Vibe is a Tanzania-based online marketplace connecting buyers and sellers. List for free, talk to the seller directly, and pay through escrow — nationwide.',
      hero_cta_1: 'Join the launch list',
      hero_cta_2: 'Browse categories',
      fact_escrow: 'Escrow via ClickPesa',
      fact_kyc: 'Verified sellers (KYC)',
      fact_delivery: 'Nationwide delivery',

      sifa_eyebrow: 'What Soko Vibe is',
      sifa_h2: 'One Tanzanian marketplace, for buyers and sellers.',
      sifa_lead: 'Soko Vibe is a digital platform operated from Dar es Salaam. It connects buyers and sellers of goods across Tanzania, with direct chat and protected payments.',
      aud_b_t: 'For buyers',
      aud_b_p: 'Find new and pre-owned products, compare prices, and ask the seller directly before you buy. Your payment stays protected until you confirm delivery.',
      aud_s_t: 'For sellers and businesses',
      aud_s_p: 'List for free, verify your identity (KYC), and manage your shop from one dashboard — including optional boosts and sales insights.',
      aud_c_t: 'Real categories',
      aud_c_p: 'Electronics, fashion, home and garden, automotive, health and beauty, food, and services — products are organised so browsing stays simple.',
      lnk_market: 'Tanzania marketplace',
      lnk_cats: 'All categories',
      lnk_how: 'How it works',
      lnk_about: 'About Soko Vibe',

      how_eyebrow: 'How it works',
      how_h2: 'Four steps from search to delivery.',
      how_lead: 'Every order follows one process that protects both sides.',
      st1_n: 'Step 01',
      st1_t: 'Create an account',
      st1_p: 'Sign up as a buyer or a seller. Sellers complete identity verification (KYC) before they start selling.',
      st2_n: 'Step 02',
      st2_t: 'Search and chat',
      st2_p: 'Browse categories or search by text and voice, then ask the seller inside the app.',
      st3_n: 'Step 03',
      st3_t: 'Pay via escrow',
      st3_p: 'Pay with mobile money. Funds are held in escrow via ClickPesa — not with the seller yet.',
      st4_n: 'Step 04',
      st4_t: 'Confirm and rate',
      st4_p: 'Receive the item, confirm with the OTP, and the seller is paid. If anything is wrong, open a dispute.',
      lnk_how_full: 'Read the full how-it-works guide →',

      fee_eyebrow: 'Transparent fees',
      fee_h2: 'No hidden charges.',
      fee_lead: 'You know what you pay before you complete a purchase.',
      fee1_t: 'Listing',
      fee1_amt: 'Free',
      fee1_basis: 'For every seller',
      fee1_p: 'List products at no cost. No selling fee and no recurring subscription.',
      fee2_t: 'Platform fee',
      fee2_amt: '3.5%',
      fee2_basis: 'For buyers, at checkout',
      fee2_p: 'The seller receives the full product price. The fee is shown clearly before payment completes.',
      lnk_fees: 'All fees and boosts →',
      lnk_escrow: 'Escrow and payment safety →',

      faq_eyebrow: 'FAQ',
      faq_h2: 'Frequently asked questions.',
      q1: 'What is Soko Vibe?',
      a1: 'Soko Vibe is a Tanzania-based online marketplace connecting buyers and sellers. The service is operated from Dar es Salaam, and products are available across the country.',
      q2: 'How do I buy something on Soko Vibe?',
      a2: 'Create an account, search by text or voice, chat with the seller inside the app, pay through escrow, then confirm delivery with the OTP.',
      q3: 'How is my payment protected?',
      a3: 'Payments go into escrow via ClickPesa and are released to the seller only after the buyer confirms delivery. A dispute can be opened and handled for up to 14 days.',
      q4: 'Is it free to list on Soko Vibe?',
      a4: 'Yes. Listing is free and the seller receives the full product price. Soko Vibe charges a 3.5% platform fee to the buyer at checkout. Boosts are optional.',
      q5: 'How do I get the Soko Vibe app?',
      a5: 'The Android app is available through an official link on Soko Vibe WhatsApp. Google Play and App Store links will be added once the app is published on the stores.',
      q6: 'How do I get support?',
      a6: 'Email support@sokovibe.co.tz, message WhatsApp +255 693 273 241, or visit the help centre.',
      lnk_support: 'Visit the help centre →',

      app_eyebrow: 'App',
      app_h2: 'Soko Vibe in your pocket.',
      app_p: 'The Android app is available through an official link on WhatsApp. Google Play and App Store links will be added once the app is published — no invented store link appears here.',
      app_cta: 'Request the app on WhatsApp',
      app_cta2: 'Get launch updates',
      app_note: 'Support: support@sokovibe.co.tz · WhatsApp +255 693 273 241',

      wl_title: 'Join the launch list',
      wl_sub: 'We’ll tell you about the launch, updates, and the app store links.',
      wl_name: 'Your name',
      wl_name_ph: 'Name (optional)',
      wl_email: 'Email address',
      wl_email_ph: 'you@example.com',
      wl_cta: 'Notify me',
      wl_note: 'Your email is only used to send you Soko Vibe updates. No spam.',
      wl_done_title: 'You’re in!',
      wl_done_body: 'You’re on the list. We’ll let you know when the app and store links go live.',

      fb_eyebrow: 'Your voice counts',
      fb_h2: 'What do you want the app to have?',
      fb_sub: 'Pick your features and tell us your thoughts. We listen to every voice.',
      fb_features: 'Features you want',
      fb_f1: 'Safe Escrow', fb_f2: 'Live Chat', fb_f3: 'Nationwide delivery',
      fb_f4: 'Voice Search / AI', fb_f5: 'Seller Store', fb_f6: 'Mobile Wallet',
      fb_f7: 'Seller Ratings', fb_f8: 'Multiple languages',
      fb_details: 'Feedback / more details',
      fb_details_ph: 'E.g. I’d love a price calculator...',
      fb_name: 'Name', fb_email: 'Email', fb_cta: 'Send feedback',

      cm_eyebrow: 'The community has spoken',
      cm_h2: 'Public comments',
      cm_name: 'Your name', cm_email: 'Email', cm_text: 'Your comment',
      cm_text_ph: 'Your thoughts about Soko Vibe...',
      cm_cta: 'Post comment',

      cta_h2: 'Ready to start?',
      cta_p: 'Join the launch list, or contact us directly — we reply in Swahili and English.',
      cta_btn: 'Sign up now',

      f_tagline: 'Tanzania’s trusted marketplace — secure and effortless.',
      f_company: 'Company', f_privacy: 'Privacy Policy', f_terms: 'Terms of Service',
      f_support: 'Support', f_help: 'Help Center',
      f_rights: 'Soko Vibe Limited. All rights reserved.',
      f_made: 'Made with care in Tanzania 🇹🇿',

      cm_tag_lbl: 'Wants:',
      cm_empty: 'No comments yet — be the first to share!',
      cm_bad_name: 'Please enter your name (2+ chars).',
      cm_bad_email: 'Please enter a valid email.',
      cm_bad_text: 'Please write your comment (3+ chars).',
      fb_bad_empty: 'Pick at least one feature or write some details.',
      wl_bad_email: 'Please enter a valid email.',
      fb_ok: 'Thanks! Your feedback was saved.',
      cm_ok: 'Thanks! Your comment was posted.',
      wl_ok: 'Registered! We’ll keep you posted about the launch.',
      wl_dup: 'This email is already on the list. Thanks!',
      fb_err: 'Sorry, we couldn’t save your feedback. Please try again later.',
      cm_err: 'Sorry, we couldn’t post your comment. Please try again later.',
      wl_err: 'Sorry, we couldn’t register you. Please try again later.',
      theme_lbl: 'Toggle theme', lang_lbl: 'Switch language'
    }
  };

  var FEATURE_KEYS = ['fb_f1', 'fb_f2', 'fb_f3', 'fb_f4', 'fb_f5', 'fb_f6', 'fb_f7', 'fb_f8'];

  var state = { lang: detectLang() };

  function detectLang() {
    var saved;
    try { saved = localStorage.getItem(LANG_KEY); } catch (e) { saved = null; }
    if (saved === 'sw' || saved === 'en') return saved;
    return (navigator.language || '').toLowerCase().startsWith('sw') ? 'sw' : 'sw';
  }

  function t(key) { return (I18N[state.lang] || I18N.sw)[key]; }

  function applyI18n() {
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var key = el.getAttribute('data-i18n');
      if (I18N[state.lang][key]) el.textContent = I18N[state.lang][key];
    });
    document.querySelectorAll('[data-ph-i18n]').forEach(function (el) {
      var key = el.getAttribute('data-ph-i18n');
      el.placeholder = I18N[state.lang][key];
    });
    document.documentElement.lang = state.lang;
    document.title = t('doc_title');

    var desc = document.querySelector('meta[name="description"]');
    if (desc && t('doc_desc')) desc.setAttribute('content', t('doc_desc'));

    // The static English summary is only useful while the UI is in Swahili.
    var enSummary = document.querySelector('.en-summary');
    if (enSummary) enSummary.style.display = state.lang === 'en' ? 'none' : '';

    var label = document.getElementById('langLabel');
    if (label) label.textContent = state.lang === 'sw' ? 'EN' : 'SW';
  }

  /* ───────────────────────── theme ───────────────────────── */
  function detectTheme() {
    var saved;
    try { saved = localStorage.getItem(THEME_KEY); } catch (e) { saved = null; }
    if (saved === 'dark' || saved === 'light') return saved;
    return window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function applyTheme(mode) {
    document.body.dataset.theme = mode;
    var meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute('content', mode === 'dark' ? '#141218' : '#221c4a');
  }

  /* ───────────────────────── firebase ───────────────────────── */
  var db = null;
  var firebaseReady = false;

  function initFirebase() {
    if (typeof firebase === 'undefined') return false;
    try {
      firebase.initializeApp({
        apiKey: 'AIzaSyBrh5W9VwbC3qTtSTm8LJbTQeYufRGil5s',
        authDomain: 'sokonimoko-8c171-a8d14.firebaseapp.com',
        projectId: 'sokonimoko-8c171-a8d14',
        storageBucket: 'sokonimoko-8c171-a8d14.appspot.com',
        appId: '1:344682929526:web:5d3732578d6f012ac26e57'
      });
      db = firebase.firestore();
      db.settings({ ignoreUndefinedProperties: true });
      firebaseReady = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  /* ───────────────────────── helpers ───────────────────────── */
  var EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

  function validEmail(v) { return EMAIL_RE.test((v || '').trim()); }

  function normalize(v) { return (v || '').trim(); }

  function escapeHtml(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function showMsg(el, text, ok) {
    el.textContent = text;
    el.className = 'form-msg show ' + (ok ? 'ok' : 'err');
  }

  function clearMsg(el) { el.className = 'form-msg'; el.textContent = ''; }

  function markInvalid(input, bad) {
    input.setAttribute('aria-invalid', bad ? 'true' : 'false');
  }

  function serverTimestamp() { return firebase.firestore.FieldValue.serverTimestamp(); }

  function featureKeyOf(inputEl) {
    // input is inside a label; feature key is input.value mapped via label's span key
    var label = inputEl.closest('label');
    var span = label && label.querySelector('span[data-i18n]');
    return span ? span.getAttribute('data-i18n') : '';
  }

  function featureLabel(key) { return I18N[state.lang][key] || key; }

  /* ───────────────────────── waitlist ───────────────────────── */
  var wlForm = document.getElementById('waitlistForm');
  var wlMsg = document.getElementById('waitlistMsg');
  var wlDone = document.getElementById('waitlistDone');

  function submitWaitlist(e) {
    e.preventDefault();
    clearMsg(wlMsg);
    var email = normalize(document.getElementById('wlEmail').value);
    var name = normalize(document.getElementById('wlName').value);

    if (!validEmail(email)) {
      markInvalid(document.getElementById('wlEmail'), true);
      showMsg(wlMsg, t('wl_bad_email'), false);
      return;
    }
    markInvalid(document.getElementById('wlEmail'), false);

    if (!firebaseReady) { showMsg(wlMsg, t('wl_err'), false); return; }

    var docId = email.toLowerCase();
    var payload = { email: email, createdAt: serverTimestamp(), lang: state.lang };
    if (name) payload.name = name;

    var btn = wlForm.querySelector('[type="submit"]');
    btn.disabled = true;

    db.collection('landing_waitlist').doc(docId).set(payload).then(function () {
      btn.disabled = false;
      wlForm.classList.add('hidden');
      wlDone.classList.remove('hidden');
    }).catch(function (err) {
      btn.disabled = false;
      // A permission-denied on set(docId=email) means the doc already exists
      // (public creates are allowed for new emails only), i.e. a duplicate.
      var dup = err && /permission-denied/i.test(String(err.code || err.message || ''));
      showMsg(wlMsg, dup ? t('wl_dup') : t('wl_err'), dup === true);
    });
  }

  /* ───────────────────────── feedback ───────────────────────── */
  var fbForm = document.getElementById('feedbackForm');
  var fbMsg = document.getElementById('feedbackMsg');
  var fbChips = document.getElementById('featureChips');

  function selectedFeatures() {
    return Array.prototype.filter.call(fbChips.querySelectorAll('input:checked'), function (i) {
      return i.checked;
    }).map(featureKeyOf);
  }

  function submitFeedback(e) {
    e.preventDefault();
    clearMsg(fbMsg);
    var details = normalize(document.getElementById('fbDetails').value);
    var name = normalize(document.getElementById('fbName').value);
    var email = normalize(document.getElementById('fbEmail').value);
    var features = selectedFeatures();

    if (features.length === 0 && details.length < 5) {
      showMsg(fbMsg, t('fb_bad_empty'), false);
      return;
    }
    if (email && !validEmail(email)) {
      markInvalid(document.getElementById('fbEmail'), true);
      showMsg(fbMsg, t('cm_bad_email'), false);
      return;
    }
    markInvalid(document.getElementById('fbEmail'), false);
    if (!firebaseReady) { showMsg(fbMsg, t('fb_err'), false); return; }

    var payload = {
      features: features,
      details: details,
      createdAt: serverTimestamp(),
      lang: state.lang
    };
    if (name) payload.name = name;
    if (email) payload.email = email;

    var btn = fbForm.querySelector('[type="submit"]');
    btn.disabled = true;

    db.collection('landing_feature_suggestions').add(payload).then(function () {
      btn.disabled = false;
      fbForm.reset();
      showMsg(fbMsg, t('fb_ok'), true);
    }).catch(function () {
      btn.disabled = false;
      showMsg(fbMsg, t('fb_err'), false);
    });
  }

  /* ───────────────────────── comments ───────────────────────── */
  var commentList = document.getElementById('commentList');
  var cmForm = document.getElementById('commentForm');
  var cmMsg = document.getElementById('commentMsg');
  var AVATAR_COLORS = ['--primary-container', '--secondary-container', '--tertiary-container', '--amber-container'];

  function avatarLetter(name) {
    var chars = name.split(/\s+/);
    return ((chars[0] || '')[0] || '?').toUpperCase();
  }

  function renderComment(doc) {
    var d = doc.data();
    var name = d.name || '?';
    var text = d.text || '';
    var ts = d.createdAt && d.createdAt.toDate ? d.createdAt.toDate() : null;
    var when = ts
      ? new Intl.DateTimeFormat(state.lang === 'sw' ? 'sw-TZ' : 'en', { dateStyle: 'medium', timeStyle: 'short' }).format(ts)
      : (d.lang === 'sw' ? 'hivi karibuni' : 'recently');

    var tag = '';
    if (d.featureKey) {
      tag = '<span class="comment-tag">' + escapeHtml(t('cm_tag_lbl') + ' ' + featureLabel(d.featureKey)) + '</span>';
    }
    var color = AVATAR_COLORS[(d._c || 0) % AVATAR_COLORS.length];

    var el = document.createElement('div');
    el.className = 'comment';
    el.innerHTML =
      '<div class="comment-avatar" style="background:var(' + color + ')">' + escapeHtml(avatarLetter(name)) + '</div>' +
      '<div class="comment-body">' +
        '<div class="comment-head"><span class="comment-name">' + escapeHtml(name) + '</span><span class="comment-time">' + escapeHtml(when) + '</span></div>' +
        '<p class="comment-text">' + escapeHtml(text) + '</p>' + tag +
      '</div>';
    return el;
  }

  function renderComments(list) {
    commentList.innerHTML = '';
    if (!list.length) {
      var empty = document.createElement('p');
      empty.className = 'comment-text';
      empty.textContent = t('cm_empty');
      commentList.appendChild(empty);
      return;
    }
    list.forEach(function (doc, i) { doc._c = i; commentList.appendChild(renderComment(doc)); });
  }

  function initComments() {
    if (!firebaseReady) {
      commentList.innerHTML = '';
      var p = document.createElement('p');
      p.className = 'comment-text';
      p.textContent = '';
      commentList.appendChild(p);
      return;
    }
    db.collection('landing_comments')
      .orderBy('createdAt', 'desc')
      .limit(30)
      .onSnapshot(function (snap) {
        renderComments(snap.docs);
      }, function () {
        commentList.innerHTML = '';
      });
  }

  function submitComment(e) {
    e.preventDefault();
    clearMsg(cmMsg);
    var name = normalize(document.getElementById('cmName').value);
    var email = normalize(document.getElementById('cmEmail').value);
    var text = normalize(document.getElementById('cmText').value);

    if (name.length < 2) { showMsg(cmMsg, t('cm_bad_name'), false); return; }
    if (text.length < 3) { showMsg(cmMsg, t('cm_bad_text'), false); return; }
    if (email && !validEmail(email)) { showMsg(cmMsg, t('cm_bad_email'), false); return; }

    if (!firebaseReady) { showMsg(cmMsg, t('cm_err'), false); return; }

    // Comment doc carries ONLY public fields; the optional contact email goes
    // into the admin-only landing_comment_contacts collection (same doc id) so
    // submitter PII is never world-readable via the comment feed.
    var ref = db.collection('landing_comments').doc();
    var batch = db.batch();
    batch.set(ref, {
      name: name,
      text: text,
      createdAt: serverTimestamp(),
      lang: state.lang
    });
    if (email) {
      batch.set(db.collection('landing_comment_contacts').doc(ref.id), {
        email: email,
        createdAt: serverTimestamp()
      });
    }

    var btn = cmForm.querySelector('[type="submit"]');
    btn.disabled = true;

    batch.commit().then(function () {
      btn.disabled = false;
      cmForm.reset();
      showMsg(cmMsg, t('cm_ok'), true);
    }).catch(function () {
      btn.disabled = false;
      showMsg(cmMsg, t('cm_err'), false);
    });
  }

  /* ───────────────────────── boot ───────────────────────── */
  document.getElementById('langBtn').addEventListener('click', function () {
    state.lang = state.lang === 'sw' ? 'en' : 'sw';
    try { localStorage.setItem(LANG_KEY, state.lang); } catch (e) {}
    applyI18n();
  });

  document.getElementById('themeBtn').addEventListener('click', function () {
    var next = document.body.dataset.theme === 'dark' ? 'light' : 'dark';
    try { localStorage.setItem(THEME_KEY, next); } catch (e) {}
    applyTheme(next);
  });

  document.getElementById('ctaBtn').addEventListener('click', function () {
    var hd = wlDone.classList.contains('hidden') ? wlForm : wlDone;
    hd.scrollIntoView({ behavior: 'smooth', block: 'center' });
  });

  wlForm.addEventListener('submit', submitWaitlist);
  fbForm.addEventListener('submit', submitFeedback);
  cmForm.addEventListener('submit', submitComment);

  document.querySelectorAll('.footer-bottom .year').forEach(function (el) {
    el.textContent = String(new Date().getFullYear());
  });

  applyTheme(detectTheme());
  applyI18n();
  initFirebase();
  initComments();
})();