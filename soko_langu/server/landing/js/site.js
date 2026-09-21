(function () {
  'use strict';

  var year = document.getElementById('year');
  if (year) year.textContent = new Date().getFullYear();

  var bar = document.getElementById('nav-bar');
  var btn = document.querySelector('.menu-btn');
  if (btn && bar) {
    btn.addEventListener('click', function () {
      var open = bar.classList.toggle('open');
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
    });
    bar.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () {
        bar.classList.remove('open');
        btn.setAttribute('aria-expanded', 'false');
      });
    });
  }

  if ('IntersectionObserver' in window && !window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    var items = document.querySelectorAll('[data-reveal]');
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('in');
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.12 });
    items.forEach(function (el) { io.observe(el); });
  } else {
    document.querySelectorAll('[data-reveal]').forEach(function (el) { el.classList.add('in'); });
  }

  // ---------- Language switcher (Kiswahili / English) ----------
  // The page ships in Kiswahili; English strings swap in via data-i18n.
  var LANG_KEY = 'soko_vibe_lang';
  var SUPPORTED_LANGS = ['sw', 'en'];
  var I18N = {
    sw: {
      doc_title: 'Soko Vibe — Tanzania Online Marketplace | Buy & Sell in Tanzania',
      doc_desc: 'Soko Vibe is a Tanzania online marketplace where buyers and sellers can discover, buy and sell products and services securely across Tanzania.',
      nav_sifa: 'Sifa', nav_jinsi: 'Jinsi Inavyofanya Kazi', nav_bei: 'Udhamini',
      nav_maswali: 'Maswali', nav_app: 'App', nav_cta: 'Pata App',
      hero_eyebrow: 'Soko Vibe · Dar es Salaam, Tanzania',
      hero_h1: 'Soko Vibe — Tanzania Online Marketplace',
      hero_sub: 'Nunua na uza bidhaa Tanzania kwa urahisi, usalama na urahisi wa kuwasiliana na wauzaji — malipo ya escrow, mazungumzo ya moja kwa moja, na usafirishaji nchi nzima.',
      hero_cta_wa: 'Pata App kwenye WhatsApp', hero_cta_how: 'Jinsi Inavyofanya Kazi',
      hero_proof: 'Orodha ni bure · Kila malipo linalindwa na escrow · Wauzaji wanahakikiwa (KYC)',
      mock_search: 'Tafuta bidhaa…', mock_chat: 'Habari, bidhaa ipo?',
      hero_note: 'Nunua na uza kwenye app — malipo ya escrow, mazungumzo ya moja kwa moja, na usafirishaji nchi nzima. App ya Android inapatikana sasa kupitia WhatsApp.',
      intro_p1: 'Kila kitu — orodha za bidhaa, malipo, mazungumzo na usafirishaji — kinapatikana kwenye app moja. Wauzaji wanaweka bidhaa bila gharama, na malipo yanalindwa kwa escrow hadi mnunuzi athibitishe kupokea.',
      intro_links: 'Vinjari masomo muhimu: <a class="intro-link" href="/how-soko-vibe-works">jinsi inavyofanya kazi</a>, <a class="intro-link" href="/soko-vibe-fees">ada za Soko Vibe</a> na <a class="intro-link" href="/soko-vibe-escrow">escrow na usalama wa malipo</a>.',
      intro_more: 'Jifunze zaidi kuhusu soko hili la Tanzania',
      feat_eyebrow: 'Sifa', feat_h2: 'Imejengwa kwa uaminifu, kwa Tanzania',
      feat_lead: 'Sifa muhimu za Soko Vibe zinazokulinda wewe — mnunuzi na muuzaji.',
      f1_t: 'Malipo ya escrow', f1_b: 'Fedha zinashikiliwa kwa escrow kupitia ClickPesa hadi mnunuzi athibitishe kupokea bidhaa. Ukitokea mgogoro, timu yetu inashughulikia.',
      f2_t: 'Mazungumzo ya wakati halisi', f2_b: 'Zungumza na muuzaji au mnunuzi ndani ya app kabla ya kuamua — maswali, picha na majadiliano ya bei.',
      f3_t: 'Msaidizi wa AI na utafutaji kwa sauti', f3_b: 'Tafuta kwa kuongea, au muulize msaidizi wa AI ndani ya app akusaidie kupata unachohitaji.',
      f4_t: 'Uwallet na mobile money', f4_b: 'Lipa kwa M-Pesa, Tigo Pesa, Airtel Money, HaloPesa au EzyPesa. Fedha zako zinaenda kwenye wallet yako ya Soko Vibe.',
      f5_t: 'Zana za wauzaji', f5_b: 'Orodha za bure, kampeni zilizodhaminiwa, flash sales, takwimu za wakati halisi na usimamizi wa duka — vyote kwenye dashboard moja.',
      f6_t: 'Uthibitisho wa OTP na usafirishaji', f6_b: 'Ukikamilisha usafirishaji, mnunuzi anathibitisha kupokea kwa OTP kabla ya malipo kutolewa kwa muuzaji.',
      how_eyebrow: 'Jinsi inavyofanya kazi', how_h2: 'Kutoka kutafuta hadi kupokea',
      how_lead: 'Agizo lolote kwenye Soko Vibe linafuata njia hii — pande zote mbili zinalindwa.',
      s1_t: 'Fungua akaunti', s1_b: 'Jisajili kama mnunuzi au muuzaji. Wauzaji huthibitishwa utambulisho (KYC) kabla ya kuanza kuuza.',
      s2_t: 'Tafuta na uchague', s2_b: 'Vinjari aina mbalimbali za bidhaa, tafuta kwa sauti, na ukubaliane na mwenzao kupitia mazungumzo.',
      s3_t: 'Lipa kwa escrow', s3_b: 'Malipo yanaingia escrow kupitia ClickPesa. Fedha hazitoki hadi uthibitishe kupokea bidhaa yako.',
      s4_t: 'Pokewa na uthibitishe', s4_b: 'Ukifika bidhaa, thibitisha kwa OTP. Kama kuna tatizo, fungua mgogoro na timu itashughulikia.',
      price_eyebrow: 'Udhamini', price_h2: 'Orodha ni bure. Dhamini bidhaa yako ionekane zaidi.',
      price_lead: 'Chagua mahali bidhaa yako ionekane — utafutaji, kategoria, au feed — pamoja na muda na bajeti ya kila siku. Unalipa tu unapodhamini.',
      p_t1_t: 'Utafutaji', p_t1_d: 'Matokeo ya juu', p_t1_f: 'Bidhaa yako inaonekana juu ya matokeo ya utafutaji.',
      p_popular: 'Maarufu zaidi',
      p_t2_t: 'Kategoria na Feed', p_t2_d: 'Ugunduzi wa kila siku', p_t2_f: 'Inaonekana kwenye kategoria, feed na mapendekezo.',
      p_t3_t: 'Duka Maalum', p_t3_d: 'Uonekano wa kibinafsi', p_t3_f: 'Duka lako linaonekana kwenye ugunduzi na maonyesho maalum.',
      price_cta: 'Anzisha udhamini kwenye app',
      price_note: 'Chagua muda (siku 1–30) na bajeti ya kila siku ndani ya app — hakuna mkataba wa kudumu, hakuna usajili. Takwimu za maoni na mibofyo kwa wakati halisi.',
      li1: 'Kuweka orodha ni bure — unalipa tu unapodhamini',
      li2: 'Takwimu za wakati halisi za maoni na mawasiliano',
      li3: 'Uwallet wenye kutoa pesa moja kwa moja kwenye namba yako',
      li4: 'Ada ya jukwaa ya 3.5% kwa mnunuzi — muuzaji anapokea bei kamili',
      li5: 'Beji ya muuzaji aliyethibitishwa baada ya KYC',
      trust_eyebrow: 'Uaminifu', trust_h2: 'Imejengwa kwa tahadhari na uwazi',
      t1_t: 'Escrow na ClickPesa', t1_b: 'Malipo yanasimamiwa na ClickPesa. Fedha hushikiliwa kwa escrow hadi ununuaji uthibitike — hadi siku 14 za mgogoro.',
      t2_t: 'Ada ya jukwaa — 3.5%', t2_b: 'Soko Vibe hutoza ada ya jukwaa ya 3.5% kwa mnunuzi wakati wa ununuzi. Muuzaji anapokea bei kamili ya bidhaa; hakuna ada yoyote iliyofichwa kwako.',
      t3_t: 'Uthibitisho wa utambulisho', t3_b: 'Wauzaji hupitia KYC kabla ya kuuza, na jukwaa lina mchakato maalum wa utatuzi wa mgogoro na malalamiko.',
      t4_t: 'Faragha na ulinzi wa data', t4_b: 'Tunafuata Sheria ya Ulinzi wa Data ya Tanzania, 2022. Maswali ya faragha: <a href="mailto:dpo@sokovibe.co.tz">dpo@sokovibe.co.tz</a>.',
      t5_t: 'Huduma za usaidizi', t5_b: 'Jukwaa linatumia wasambazaji waliothibitishwa: ClickPesa, OneSignal, Cloudinary, Meseji na Groq AI. Usaidizi: <a href="mailto:support@sokovibe.co.tz">support@sokovibe.co.tz</a>.',
      app_h2: 'Pakua app ya Soko Vibe',
      app_lead: 'App ya Android inapatikana sasa. Tutumie ujumbe kwa WhatsApp tukupatie link rasmi. Viungo vya Google Play na App Store vitaonekana hapa mara app itakapochapishwa.',
      app_cta: 'Pata App kwenye WhatsApp', store_status: 'Kiungo kitapatikana baadaye',
      faq_eyebrow: 'Maswali', faq_h2: 'Maswali yanayoulizwa mara kwa mara',
      q1: 'Je, kuweka bidhaa ni bure kweli?', a1: 'Ndiyo. Kufungua orodha haina gharama yoyote. Unalipa tu unapochagua kudhamini orodha yako ili ione kwa watu zaidi.',
      q2: 'Fedha zangu zinalindwaje?', a2: 'Malipo yanaingia escrow kupitia ClickPesa na yanatolewa kwa muuzaji tu baada ya wewe kuthibitisha kupokea bidhaa. Kama kuna tatizo, unafungua mgogoro na timu inashughulikia.',
      q3: 'Ninaweza kuzungumza na muuzaji kabla ya kununua?', a3: 'Ndiyo — kila orodha ina mazungumzo ya ndani ya app. Uliza maswali, chambua picha, na kubaliane bei au usafirishaji kabla ya kukamilisha.',
      q4: 'Usafirishaji unafanyaje kazi?', a4: 'Wauzaji hupanga usafirishaji nchi nzima na unafuatilia uwasilishaji kwenye app. Unathibitisha kupokea kwa OTP — hapo ndipo fedha zinatolewa.',
      q5: 'Kuna ada yoyote ya jukwaa?', a5: 'Ndiyo — Soko Vibe hutoza ada ya jukwaa ya 3.5% kwa mnunuzi wakati wa ununuzi. Muuzaji anapokea bei kamili ya bidhaa. Hakuna ada ya kufungua orodha au ya kuuza.',
      q6: 'Ninawezaje kupata app?', a6: 'Tutumie ujumbe kwa WhatsApp +255 693 273 241 na tutakupatia link rasmi ya app ya Android. Kiungo cha Google Play kitachapishwa baadaye.',
      f_tagline: 'Soko la Tanzania la kununua na kuuza kwa usalama — linatengenezwa kwa uangalifu nchini Tanzania.',
      f_col_soko: 'Soko', f_l1: 'Soko la Tanzania', f_l2: 'Kategoria', f_l3: 'Jinsi inavyofanya kazi',
      f_l4: 'Ada za Soko Vibe', f_l5: 'Escrow na usalama', f_l6: 'Kuhusu Soko Vibe', f_l7: 'Mwanzilishi', f_l8: 'Maswali',
      f_col_sheria: 'Sheria', f_privacy: 'Sera ya faragha', f_terms: 'Masharti ya matumizi', f_support: 'Usaidizi',
      f_col_contact: 'Wasiliana nasi'
    },
    en: {
      doc_title: 'Soko Vibe — Tanzania Online Marketplace | Buy & Sell in Tanzania',
      doc_desc: 'Buy and sell products across Tanzania with escrow payments, in-app chat with sellers, and nationwide delivery — all inside the Soko Vibe app.',
      nav_sifa: 'Features', nav_jinsi: 'How It Works', nav_bei: 'Sponsored',
      nav_maswali: 'FAQ', nav_app: 'App', nav_cta: 'Get the App',
      hero_eyebrow: 'Soko Vibe · Dar es Salaam, Tanzania',
      hero_h1: 'Soko Vibe — Tanzania Online Marketplace',
      hero_sub: 'Buy and sell products across Tanzania with ease, security, and direct communication with sellers — escrow payments, instant chat, and nationwide delivery.',
      hero_cta_wa: 'Get the App on WhatsApp', hero_cta_how: 'How It Works',
      hero_proof: 'Free to list · Every payment escrow-protected · Sellers KYC-verified',
      mock_search: 'Search products…', mock_chat: 'Hi, is this available?',
      hero_note: 'Buy and sell inside the app — escrow payments, instant chat, and nationwide delivery. The Android app is available now via WhatsApp.',
      intro_p1: 'Everything — product listings, payments, chat, and delivery — lives inside one app. Sellers list for free, and payments stay protected in escrow until the buyer confirms receipt.',
      intro_links: 'Explore key guides: <a class="intro-link" href="/how-soko-vibe-works">how it works</a>, <a class="intro-link" href="/soko-vibe-fees">Soko Vibe fees</a>, and <a class="intro-link" href="/soko-vibe-escrow">escrow and payment security</a>.',
      intro_more: 'Learn more about this Tanzanian marketplace',
      feat_eyebrow: 'Features', feat_h2: 'Built on trust, for Tanzania',
      feat_lead: 'Key Soko Vibe features that protect you — buyer and seller.',
      f1_t: 'Escrow payments', f1_b: 'Funds are held in escrow via ClickPesa until the buyer confirms receipt. If a dispute arises, our team steps in.',
      f2_t: 'Real-time chat', f2_b: 'Talk to the seller or buyer inside the app before you decide — questions, photos, and price negotiation.',
      f3_t: 'AI assistant & voice search', f3_b: 'Search by speaking, or ask the in-app AI assistant to help you find what you need.',
      f4_t: 'Wallet & mobile money', f4_b: 'Pay with M-Pesa, Tigo Pesa, Airtel Money, HaloPesa, or EzyPesa. Your money goes to your Soko Vibe wallet.',
      f5_t: 'Seller tools', f5_b: 'Free listings, sponsored campaigns, flash sales, real-time stats, and shop management — all in one dashboard.',
      f6_t: 'OTP confirmation & delivery', f6_b: 'Once delivery is complete, the buyer confirms receipt with an OTP before payment is released to the seller.',
      how_eyebrow: 'How it works', how_h2: 'From search to doorstep',
      how_lead: 'Every Soko Vibe order follows this path — both sides are protected.',
      s1_t: 'Create an account', s1_b: 'Sign up as a buyer or seller. Sellers verify their identity (KYC) before they start selling.',
      s2_t: 'Search & choose', s2_b: 'Browse product categories, search by voice, and agree terms with your counterpart over chat.',
      s3_t: 'Pay via escrow', s3_b: 'Payments go into escrow via ClickPesa. Funds are not released until you confirm receipt of your product.',
      s4_t: 'Receive & confirm', s4_b: 'When the product arrives, confirm with an OTP. If there is a problem, open a dispute and the team will handle it.',
      price_eyebrow: 'Sponsorship', price_h2: 'Listing is free. Sponsor your product to get seen.',
      price_lead: 'Choose where your product appears — search, categories, or feed — plus duration and daily budget. You only pay when you sponsor.',
      p_t1_t: 'Search', p_t1_d: 'Top of results', p_t1_f: 'Your product appears at the top of search results.',
      p_popular: 'Most popular',
      p_t2_t: 'Categories & Feed', p_t2_d: 'Everyday discovery', p_t2_f: 'Shown across categories, feed, and recommendations.',
      p_t3_t: 'Featured Store', p_t3_d: 'Standout presence', p_t3_f: 'Your shop appears in discovery and featured slots.',
      price_cta: 'Start sponsoring in the app',
      price_note: 'Pick a duration (1–30 days) and daily budget inside the app — no long-term contract, no subscription. Real-time impressions and clicks.',
      li1: 'Listing is free — you only pay when you sponsor',
      li2: 'Real-time stats for views and contacts',
      li3: 'Wallet with direct cash-out to your number',
      li4: '3.5% platform fee for the buyer — the seller receives the full price',
      li5: 'Verified-seller badge after KYC',
      trust_eyebrow: 'Trust', trust_h2: 'Built with care and transparency',
      t1_t: 'Escrow & ClickPesa', t1_b: 'Payments are processed by ClickPesa. Funds stay in escrow until the purchase is confirmed — up to 14 days of dispute cover.',
      t2_t: 'Platform fee — 3.5%', t2_b: 'Soko Vibe charges a 3.5% platform fee to the buyer at checkout. The seller receives the full product price; nothing hidden.',
      t3_t: 'Identity verification', t3_b: 'Sellers pass KYC before selling, and the platform runs a dedicated dispute and complaints process.',
      t4_t: 'Privacy & data protection', t4_b: 'We follow the Tanzania Data Protection Act, 2022. Privacy questions: <a href="mailto:dpo@sokovibe.co.tz">dpo@sokovibe.co.tz</a>.',
      t5_t: 'Support services', t5_b: 'The platform uses verified providers: ClickPesa, OneSignal, Cloudinary, Meseji, and Groq AI. Support: <a href="mailto:support@sokovibe.co.tz">support@sokovibe.co.tz</a>.',
      app_h2: 'Download the Soko Vibe app',
      app_lead: 'The Android app is available now. Message us on WhatsApp and we will send you the official link. Google Play and App Store links will appear here once the app is published.',
      app_cta: 'Get the App on WhatsApp', store_status: 'Link coming soon',
      faq_eyebrow: 'FAQ', faq_h2: 'Frequently asked questions',
      q1: 'Is listing products really free?', a1: 'Yes. Opening a listing costs nothing. You only pay when you choose to sponsor your listing so more people see it.',
      q2: 'How is my money protected?', a2: 'Payments go into escrow via ClickPesa and are released to the seller only after you confirm receipt. If anything goes wrong, open a dispute and the team handles it.',
      q3: 'Can I talk to the seller before buying?', a3: 'Yes — every listing has in-app chat. Ask questions, review photos, and agree on price or delivery before checkout.',
      q4: 'How does delivery work?', a4: 'Sellers arrange nationwide delivery and you track fulfilment in the app. You confirm receipt with an OTP — that is when funds are released.',
      q5: 'Is there any platform fee?', a5: 'Yes — Soko Vibe charges a 3.5% platform fee to the buyer at checkout. The seller receives the full product price. No listing or selling fees.',
      q6: 'How do I get the app?', a6: 'Message us on WhatsApp at +255 693 273 241 and we will send you the official Android app link. The Google Play link comes later.',
      f_tagline: 'The Tanzanian marketplace for safe buying and selling — crafted with care in Tanzania.',
      f_col_soko: 'Market', f_l1: 'Tanzanian marketplace', f_l2: 'Categories', f_l3: 'How it works',
      f_l4: 'Soko Vibe fees', f_l5: 'Escrow & security', f_l6: 'About Soko Vibe', f_l7: 'Founder', f_l8: 'FAQ',
      f_col_sheria: 'Legal', f_privacy: 'Privacy policy', f_terms: 'Terms of use', f_support: 'Support',
      f_col_contact: 'Contact us'
    }
  };

  function detectLang() {
    try {
      var saved = localStorage.getItem(LANG_KEY);
      if (saved && SUPPORTED_LANGS.indexOf(saved) !== -1) return saved;
    } catch (e) { /* private mode: fall through to browser default */ }
    var nav = (navigator.language || 'sw').toLowerCase().split('-')[0];
    if (SUPPORTED_LANGS.indexOf(nav) !== -1) return nav;
    return 'sw';
  }

  function applyLang(lang) {
    var dict = I18N[lang] || I18N.sw;
    document.documentElement.lang = lang;
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var key = el.getAttribute('data-i18n');
      if (dict[key] != null) el.innerHTML = dict[key];
    });
    if (dict.doc_title) document.title = dict.doc_title;
    // The intro carries a fixed English summary paragraph; hide it while the
    // English translation is active so it neither duplicates nor mixes in.
    var enSummary = document.querySelector('.intro .en');
    if (enSummary) enSummary.style.display = (lang === 'en') ? 'none' : '';
    var meta = document.querySelector('meta[name="description"]');
    if (meta && dict.doc_desc) meta.setAttribute('content', dict.doc_desc);
    document.querySelectorAll('select.lang-select').forEach(function (sel) {
      if (sel.value !== lang) sel.value = lang;
    });
    try { localStorage.setItem(LANG_KEY, lang); } catch (e) { /* ignore */ }
  }

  applyLang(detectLang());
  document.querySelectorAll('select.lang-select').forEach(function (sel) {
    sel.addEventListener('change', function (e) { applyLang(e.target.value); });
  });
})();