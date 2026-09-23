/* Soko Vibe — coming-soon page: i18n (sw/en) + Firebase waitlist/feedback/comments. */
(function () {
  'use strict';

  var LANG_KEY = 'soko_vibe_waitlist_lang';
  var THEME_KEY = 'soko_vibe_waitlist_theme';

  /* ───────────────────────── i18n ───────────────────────── */
  var I18N = {
    sw: {
      doc_title: 'Soko Vibe — App ipo kwenye maendeleo',
      hero_badge: 'App ipo kwenye maendeleo',
      hero_h1_1: 'Soko la Tanzania,',
      hero_h1_2: 'Hivi karibuni.',
      hero_sub: 'Tunajenga Soko Vibe — soko la mtandaoni salama la kununua na kuuza. Jiunge na orodha ya wapokeaji taarifa na ushike nafasi ya mwanzo.',
      wl_title: 'Jiandikishe, upate taarifa',
      wl_sub: 'Tumekuthibitishie kupewa taarifa mara app itakapokamilika.',
      wl_name: 'Jina lako',
      wl_name_ph: 'Jina (si lazima)',
      wl_email: 'Barua pepe',
      wl_email_ph: 'mwandishi@mfano.co.tz',
      wl_cta: 'Nipe taarifa',
      wl_note: 'Barua pepe yako inatumika tu kukutangazia app. Hakuna spam.',
      wl_done_title: 'Umefanikiwa!',
      wl_done_body: 'Umeingizwa kwenye orodha. Tutakuarifu app inapokamilika.',
      peek_eyebrow: 'Kinachokuja',
      peek_h2: 'Tumekutengenezee kitu kizuri.',
      peek_lead: 'Hii ndiyo app tunayojenga sasa hivi kwa ajili yako.',
      peek_p1_t: 'Escrow Salama', peek_p1_b: 'Fedha zinasimama salama hadi uthibitishe bidhaa yako imefika.',
      peek_p2_t: 'Mazungumzo ya Moja kwa Moja', peek_p2_b: 'Ongea na wauzaji, jadiliana bei, kabla ya kununua.',
      peek_p3_t: 'Utafutaji wa Sauti', peek_p3_b: 'Tafuta bidhaa kwa kusema — msaidizi wetu wa AI anakuelewa.',
      peek_p4_t: 'Kupandisha Uuzaji', peek_p4_b: 'Pandisha bidhaa yako juu na uza haraka kwa mguso mmoja.',
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
      cta_h2: 'Usijiondoke bila kuachia maoni.',
      cta_p: 'App inakamilika hivi karibuni — na itabeba kila jambo ulilolisema.',
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
      wl_ok: 'Umesajiliwa! Tukutajie barua pepe tumekupata.',
      wl_dup: 'Barua pepe hii tayari ipo kwenye orodha. Asante!',
      fb_err: 'Samahani, maoni yako yalishindikana. Jaribu tena baadaye.',
      cm_err: 'Samahani, tushindwe kutuma. Jaribu tena baadaye.',
      wl_err: 'Samahani, tushindwe kukusajili. Jaribu tena baadaye.',
      theme_lbl: 'Badili mwonekano', lang_lbl: 'Badili lugha'
    },
    en: {
      doc_title: 'Soko Vibe — App is under development',
      hero_badge: 'App is under development',
      hero_h1_1: 'Tanzania\u2019s marketplace,',
      hero_h1_2: 'Coming soon.',
      hero_sub: 'We\u2019re building Soko Vibe — a safe online marketplace to buy and sell. Join the early-access list and grab your spot.',
      wl_title: 'Join the early list',
      wl_sub: 'We\u2019ll notify you the moment the app goes live.',
      wl_name: 'Your name',
      wl_name_ph: 'Name (optional)',
      wl_email: 'Email address',
      wl_email_ph: 'you@example.com',
      wl_cta: 'Notify me', wl_note: 'Your email is only used to tell you when the app launches. No spam.',
      wl_done_title: 'You\u2019re in!',
      wl_done_body: 'You\u2019re on the list. We\u2019ll let you know when the app is ready.',
      peek_eyebrow: 'What\u2019s coming',
      peek_h2: 'We\u2019re cooking up something great.',
      peek_lead: 'This is the app we\u2019re building for you right now.',
      peek_p1_t: 'Safe Escrow', peek_p1_b: 'Money is held safely until you confirm your product arrived.',
      peek_p2_t: 'Live Chat', peek_p2_b: 'Talk to sellers and negotiate prices before you buy.',
      peek_p3_t: 'Voice Search', peek_p3_b: 'Search products by speaking — our AI assistant gets you.',
      peek_p4_t: 'Boost Sales', peek_p4_b: 'Push your product to the top and sell faster with one tap.',
      fb_eyebrow: 'Your voice counts',
      fb_h2: 'What do you want the app to have?',
      fb_sub: 'Pick your features and tell us your thoughts. We listen to every voice.',
      fb_features: 'Features you want',
      fb_f1: 'Safe Escrow', fb_f2: 'Live Chat', fb_f3: 'Nationwide delivery',
      fb_f4: 'Voice Search / AI', fb_f5: 'Seller Store', fb_f6: 'Mobile Wallet',
      fb_f7: 'Seller Ratings', fb_f8: 'Multiple languages',
      fb_details: 'Feedback / more details',
      fb_details_ph: 'E.g. I\u2019d love a price calculator...',
      fb_name: 'Name', fb_email: 'Email', fb_cta: 'Send feedback',
      cm_eyebrow: 'The community has spoken',
      cm_h2: 'Public comments',
      cm_name: 'Your name', cm_email: 'Email', cm_text: 'Your comment',
      cm_text_ph: 'Your thoughts about Soko Vibe...',
      cm_cta: 'Post comment',
      cta_h2: 'Don\u2019t leave without a comment.',
      cta_p: 'The app is almost here — and it\u2019ll carry every word you said.',
      cta_btn: 'Sign up now',
      f_tagline: 'Tanzania\u2019s trusted marketplace — secure and effortless.',
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
      wl_ok: 'Registered! We\u2019ve got your email.',
      wl_dup: 'This email is already on the list. Thanks!',
      fb_err: 'Sorry, we couldn\u2019t save your feedback. Please try again later.',
      cm_err: 'Sorry, we couldn\u2019t post your comment. Please try again later.',
      wl_err: 'Sorry, we couldn\u2019t register you. Please try again later.',
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
    document.getElementById('langLabel').textContent = state.lang === 'sw' ? 'EN' : 'SW';
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

    var payload = {
      name: name,
      text: text,
      createdAt: serverTimestamp(),
      lang: state.lang
    };
    if (email) payload.email = email;

    var btn = cmForm.querySelector('[type="submit"]');
    btn.disabled = true;

    db.collection('landing_comments').add(payload).then(function () {
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