/* Soko Vibe Duka — app-service parity module (buyer + seller + auth).
   Mirrors the Flutter app's services on the web shop using the same
   endpoints and Firestore collections the app uses. No new server routes. */

'use strict';

(function () {
  const FV = firebase.firestore.FieldValue;
  const recentsKey = 'sv_shop_recent';
  const searchHistKey = 'sv_shop_searchhist';

  function readArr(key) {
    try { const v = JSON.parse(localStorage.getItem(key) || '[]'); return Array.isArray(v) ? v : []; }
    catch (_) { return []; }
  }
  function saveArr(key, v) { localStorage.setItem(key, JSON.stringify(v)); }

  function recordRecent(id) {
    if (!id) return;
    const list = readArr(recentsKey).filter((x) => x.id !== id);
    list.unshift({ id: id, ts: Date.now() });
    saveArr(recentsKey, list.slice(0, 12));
  }
  function recordSearch(q) {
    if (!q || !String(q).trim()) return;
    const list = readArr(searchHistKey).filter((x) => x.toLowerCase() !== String(q).toLowerCase());
    list.unshift(String(q).trim());
    saveArr(searchHistKey, list.slice(0, 10));
  }
  function clearSearchHist() { saveArr(searchHistKey, []); renderSearchHist(); }

  async function myUserDoc() {
    const u = AUTH.currentUser;
    if (!u) return null;
    try { const s = await DB.collection('users').doc(u.uid).get(); return s.exists ? s.data() : null; }
    catch (_) { return null; }
  }

  function notifBadge() {
    const b = document.getElementById('bellBadge');
    if (!b) return;
    const u = AUTH.currentUser;
    if (!u) { b.hidden = true; return; }
    DB.collection('notifications').where('userId', '==', u.uid).where('isRead', '==', false).limit(1).get()
      .then((s) => { b.hidden = false; b.textContent = s.size ? Math.min(s.size, 99) : 0; })
      .catch(() => { b.hidden = true; });
  }

  let notifTimer = null;
  function notifPoll(on) {
    clearInterval(notifTimer);
    if (on) notifBadge();
    notifTimer = setInterval(notifBadge, 60000);
  }

  /* ---------- Auth parity: phone OTP + Google ---------- */

  async function phoneOtpStep1() {
    const phone = e164(document.getElementById('phPhone') ? document.getElementById('phPhone').value : '');
    const errEl = document.getElementById('parityErr');
    const clearErr = () => { if (errEl) errEl.classList.remove('show'); };
    if (!phone || phone.length < 9) { if (errEl) { errEl.textContent = 'Andika namba ya simu kwa usahihi (+255…).'; errEl.classList.add('show'); } return; }
    clearErr();
    const btn = document.getElementById('phNext');
    if (btn) btn.disabled = true;
    try {
      const data = await apiPost('/api/v1/auth/send-otp', { phone: '+255' + phone.replace(/^255/, '').replace(/^0/, ''), langCode: lang });
      if (data && data.sent) {
        document.getElementById('phStep1').style.display = 'none';
        document.getElementById('phStep2').style.display = '';
      }
    } catch (e) {
      if (errEl) { errEl.textContent = errMsg(e); errEl.classList.add('show'); }
    } finally {
      if (btn) btn.disabled = false;
    }
  }

  function otpPhoneDigits() {
    const el = document.getElementById('phPhone');
    const digits = (el ? el.value : '').replace(/\D/g, '');
    return digits.startsWith('0') ? '255' + digits.slice(1) : digits.startsWith('255') ? digits : ('255' + digits);
  }

  async function phoneOtpStep2() {
    const phone = otpPhoneDigits();
    const otp = (document.getElementById('phOtp') || {}).value || '';
    const errEl = document.getElementById('parityErr');
    if (!/^\d{6}$/.test(otp)) { if (errEl) { errEl.textContent = 'OTP ina tarakimu 6.'; errEl.classList.add('show'); } return; }
    try {
      const data = await apiPost('/api/v1/auth/phone-login', { phone: phone, otp: otp });
      if (data && data.token) {
        await AUTH.signInWithCustomToken(data.token);
      }
      const user = AUTH.currentUser;
      if (user) {
        await user.getIdToken(true).catch(() => {});
        toast('✔ ' + t('submit_signin'));
        await afterSignIn();
        renderAccount();
        return;
      }
      renderAuthForm('signin');
    } catch (e) {
      if (errEl) { errEl.textContent = errMsg(e); errEl.classList.add('show'); }
    }
  }

  async function afterSignIn() {
    refreshChip();
    const u = AUTH.currentUser;
    if (!u) return;
    const doc = await myUserDoc().catch(() => null);
    if (doc && doc.isSuspended) {
      toast('Akaunti yako imesitishwa. Wasiliana na msaada.');
      await AUTH.signOut().catch(() => {});
      refreshChip();
      return;
    }
    notifPoll(true);
  }

  async function googleSignIn() {
    if (!AUTH) return;
    try {
      const cred = await AUTH.signInWithPopup(new firebase.auth.GoogleAuthProvider());
      const user = cred.user;
      const snap = await DB.collection('users').doc(user.uid).get().catch(() => null);
      if (!snap || !snap.exists) {
        await DB.collection('users').doc(user.uid).set({
          name: user.displayName || (user.email || 'Google ' + user.uid.slice(0, 4)),
          email: user.email || '',
          phone: user.phoneNumber || '',
          isAdmin: false,
          isSuspended: false,
          isSeller: false,
          sellerBalance: 0,
          createdAt: FV.serverTimestamp(),
        });
      }
      await afterSignIn();
      renderAccount();
    } catch (e) {
      if (e && (e.code === 'auth/popup-blocked')) { toast('Ruhusu pop-up ili uingie kwa Google.'); return; }
      toast(errMsg(e));
    }
  }

  function authAltButtons() {
    return '<div class="auth-alt">'
      + '<button type="button" class="btn-outline btn-block" data-act="googlelogin">'
      + '<svg width="15" height="15" viewBox="0 0 24 24" aria-hidden="true"><path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.27-4.74 3.27-8.1z"/><path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84A11 11 0 0 0 12 23z"/><path fill="#FBBC05" d="M5.84 14.1a6.6 6.6 0 0 1 0-4.2V7.06H2.18a11 11 0 0 0 0 9.88l3.66-2.84z"/><path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15A11 11 0 0 0 2.18 7.06l3.66 2.84c.87-2.6 3.3-4.52 6.16-4.52z"/></svg>'
      + ' ' + t('signin_google') + '</button>'
      + '<button type="button" class="btn-outline btn-block" data-act="phonelogin">'
      + '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="5" y="2" width="14" height="20" rx="2"/><path d="M12 18h.01"/></svg>'
      + ' ' + t('signin_phone') + '</button>'
      + '</div>';
  }

  function renderPhoneSignin() {
    setLang(); setHero(false);
    view.innerHTML = '<div class="container-wide"><div class="auth-wrap">'
      + '<div class="form-card"><h2>' + t('signin_phone') + '</h2>'
      + '<div class="error-box" id="parityErr"></div>'
      + '<div id="phStep1">'
      + '<div class="field"><label>' + t('phone') + '</label><input id="phPhone" type="tel" inputmode="tel" placeholder="+255 7xx xxx xxx"></div>'
      + '<p class="muted" style="font-size:12px;margin-top:6px">Tutakutumia OTP kwa SMS ili uthibitishe namba yako.</p>'
      + '<button class="btn-dark btn-block mt16" id="phNext" data-act="phnext">' + t('continue') + '</button>'
      + '</div>'
      + '<div id="phStep2" style="display:none">'
      + '<div class="field"><label>OTP</label><input id="phOtp" type="text" inputmode="numeric" maxlength="6" placeholder="000000"></div>'
      + '<button class="btn-dark btn-block mt16" data-act="phverify">' + t('submit_signin') + '</button>'
      + '<button class="btn-sm mt16" style="background:none;border:none;color:var(--accent);cursor:pointer" data-act="phback">← ' + t('back') + '</button>'
      + '</div>'
      + '</div></div></div>';
  }

  function renderSearchHist() {
    const box = document.getElementById('suggestBox');
    if (!box) return;
    const hist = readArr(searchHistKey);
    if (!hist.length) { box.hidden = true; return; }
    box.innerHTML = hist.map((q) => '<button type="button" data-act="sugg" data-q="' + esc(q) + '">↺ ' + esc(q) + '</button>').join('')
      + '<button type="button" data-act="histclear">' + esc(t('clear_all')) + '</button>';
    box.hidden = false;
  }

  function enhanceSuggest(q) {
    const box = document.getElementById('suggestBox');
    if (!box) return;
    const ql = (q || '').trim();
    if (!ql) { renderSearchHist(); return; }
    box.innerHTML = '<button type="button" disabled style="cursor:default">' + esc(t('loading')) + '</button>';
    box.hidden = false;
    apiPost('/api/search/autocomplete', { query: ql })
      .then((data) => {
        const sugg = (data && data.suggestions) || [];
        if (!sugg.length) {
          if (box.hidden) return;
          box.hidden = true;
          return;
        }
        box.innerHTML = sugg.map((s) =>
          '<button type="button" data-act="sugg" data-q="' + esc(s.text || '') + '">'
          + (s.image ? '<img class="su-thumb" src="' + esc(s.image) + '" alt="" onerror="this.remove()">' : '')
          + '<span>' + esc(s.text || '') + '</span>'
          + (s.price ? '<b>' + fmtTZS(s.price) + '</b>' : '')
          + '</button>').join('');
        box.hidden = false;
      })
      .catch(() => {
        const hits = Feed.list.filter((p) => (p.name || '').toLowerCase().indexOf(ql.toLowerCase()) >= 0).slice(0, 6).map((p) => p.name);
        box.innerHTML = hits.length ? hits.map((n) => '<button type="button" data-act="sugg" data-q="' + esc(n) + '">' + esc(n) + '</button>').join('') : '<button type="button" disabled>—</button>';
      });
  }

  /* ---------- Server search ---------- */

  function resultCard(res, p) {
    if (p) return cardHtml(p);
    const im = res.image ? '<img src="' + esc(res.image) + '" alt="" loading="lazy" onerror="this.remove()">' : '<div class="ph">SOKO</div>';
    return '<a class="card" href="#/p/' + encodeURIComponent(res.id) + '" data-rec="' + encodeURIComponent(res.id) + '">'
      + '<div class="thumb">' + im + '</div>'
      + '<div class="card-body">'
      + '<div class="category">' + esc(res.category || '') + '</div>'
      + '<div class="title">' + esc(res.displayName || '') + '</div>'
      + (res.price ? '<div class="price">' + fmtTZS(res.price) + '</div>' : '')
      + (res.sellerName ? '<div class="seller-name">' + esc(res.sellerName) + '</div>' : '')
      + (res.rating ? '<div class="stars">' + starRow(Math.round(res.rating)) + (res.reviewCount ? '(' + res.reviewCount + ')' : '') + '</div>' : '')
      + '</div></a>';
  }

  async function paritySearch(q, cat) {
    recordSearch(q);
    const title = (q && String(q).trim()) ? String(q).trim() : (cat || t('feed_all'));
    const chips = chipsFor(cat || '');
    const ql = (String(q || '').trim());
    let extra = '';
    if (!ql) {
      apiPost('/api/search/trending', {}).then((data) => {
        const tr = (data && data.trending) || [];
        if (!tr.length) return;
        const hostEl = document.getElementById('trendChips');
        if (hostEl) hostEl.innerHTML = '<span class="muted">' + esc(t('trending')) + ':</span> ' + tr.slice(0, 8).map((x) =>
          '<button type="button" class="chip" data-q="' + esc(typeof x === 'string' ? x : (x.q || x.text || '')) + '" data-act="trendchip">'
          + esc(typeof x === 'string' ? x : (x.q || x.text || '')) + '</button>').join('');
      }).catch(() => {});
    }
    view.innerHTML = feedRegion(title, '', chips, '<div id="trendChips" class="trend-chips"></div>' + extra);
    const host = document.getElementById('feedGrid');
    if (!host) return;
    const sel = document.getElementById('catSelect');
    if (sel) sel.value = cat || '';
    if (!ql && !cat) {
      parityMostRated(host, ql, cat);
      return;
    }
    host.innerHTML = '';
    let qs = (host.innerHTML = '<span class="section-muted">' + esc(t('loading')) + '</span>');
    void qs;
    try {
      if (!Feed.list.length) await loadPageInto();
    } catch (_) {}
    host.innerHTML = '';
    try {
      const filters = cat ? { category: cat } : undefined;
      const data = await apiPost('/api/search/global-search', {
        query: ql,
        type: 'all',
        page: 0,
        pageSize: 24,
        filters: filters,
      });
      if (data && data.total > 0) {
        let html = '';
        if (data.autoCorrected && data.correction) {
          html += '<div class="search-note">' + esc(t('did_you_mean')) + ' <b>' + esc(data.correction) + '</b></div>';
        }
        const res = (data.results || []).slice(0, 24);
        const ids = res.filter((r) => r.type === 'product' && r.id).map((r) => r.id);
        const prodMap = {};
        if (ids.length) {
          await Promise.all(ids.map((id) => DB.collection('products').doc(id).get()
            .then((s) => { if (s.exists) prodMap[id] = norm(s); })
            .catch(() => {})));
        }
        html += res.map((r) => resultCard(r, prodMap[r.id] || null)).join('');
        host.innerHTML = html;
        $all('[data-rec]', host).forEach((el) => {
          el.addEventListener('click', () => {
            apiPost('/api/search/record-click', { resultId: el.dataset.rec, resultType: 'product', query: ql }).catch(() => {});
          });
        });
        return;
      }
    } catch (_) {}
    const hits = Feed.list.filter((p) => {
      const hit = !ql || (p.name || '').toLowerCase().indexOf(ql.toLowerCase()) >= 0 || (p.brand || '').toLowerCase().indexOf(ql.toLowerCase()) >= 0;
      if (!hit) return false;
      if (cat) return catMatch(p, cat);
      return true;
    });
    host.innerHTML = hits.length ? hits.map(cardHtml).join('') : emptyHtml(t('empty_filter'), ql || cat, t('home_browse'));
  }

  async function parityMostRated(host, ql, cat) {
    host.innerHTML = '<span class="section-muted">' + esc(t('loading')) + '</span>';
    try {
      const data = await apiPost('/api/search/most-rated', { limit: 6 });
      const prods = (data && data.products) || [];
      if (prods.length) {
        host.innerHTML = '<h3 class="section-head">' + esc(t('most_rated')) + '</h3>'
          + '<div class="grid">' + prods.map((r) => resultCard(r, null)).join('') + '</div>';
        return;
      }
    } catch (_) {}
    host.innerHTML = Feed.list.length
      ? sortFeed(Feed.list).slice(0, 24).map(cardHtml).join('')
      : emptyHtml(t('empty_filter'), '', t('home_browse'));
  }

  /* ---------- Follow sellers ---------- */

  function followKey(el) { return { sellerUid: decodeURIComponent(el.dataset.s || ''), btn: el }; }

  async function toggleFollow(btn, sellerUid) {
    const u = AUTH.currentUser;
    if (!u) { renderAuthForm('signin'); toast(t('need_auth')); return; }
    if (u.uid === sellerUid) { toast(t('cannot_follow_self')); return; }
    try {
      const ref = DB.collection('users').doc(u.uid).collection('following').doc(sellerUid);
      const snap = await ref.get().catch(() => null);
      const is = snap && snap.exists;
      const batch = DB.batch();
      if (is) {
        batch.delete(ref);
        batch.delete(DB.collection('users').doc(sellerUid).collection('followers').doc(u.uid));
        batch.update(DB.collection('users').doc(u.uid), { followingCount: FV.increment(-1) });
        batch.update(DB.collection('users').doc(sellerUid), { followersCount: FV.increment(-1) });
      } else {
        batch.set(ref, { userId: sellerUid, followedAt: FV.serverTimestamp() });
        batch.set(DB.collection('users').doc(sellerUid).collection('followers').doc(u.uid), { userId: u.uid, followedAt: FV.serverTimestamp() });
        batch.update(DB.collection('users').doc(u.uid), { followingCount: FV.increment(1) });
        batch.update(DB.collection('users').doc(sellerUid), { followersCount: FV.increment(1) });
      }
      await batch.commit();
      const t = btn;
      t.textContent = is ? t('follow') : t('following');
      t.classList.toggle('on', !is);
    } catch (e) { toast(errMsg(e)); }
  }

  /* ---------- Product extras: comments + chat + follow---------- */

  async function parityProductExtras(p) {
    const host = document.getElementById('revHost');
    if (!host) return;
    const u = AUTH.currentUser;
    const followBtn = u && u.uid !== p.sellerId
      ? '<button class="btn-outline" id="followBtn" data-following="' + esc(p.sellerId) + '">' + esc(t('follow')) + '</button>' : '';
    const chatBtn = '<a class="btn-outline" href="#/chat/' + encodeURIComponent(p.sellerId) + '?name=' + encodeURIComponent(p.sellerName || 'Muuzaji') + '">'
      + '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12a8 8 0 0 1-8 8H4l1.5-3.5A8 8 0 1 1 21 12Z"/><path d="M8 12h8M8 8h4"/></svg>'
      + ' ' + esc(t('chat_seller')) + '</a>';
    const socialRow = (followBtn || chatBtn) ? '<div class="rowbtns" style="margin-top:14px">' + chatBtn + followBtn + '</div>' : '';
    const commentWrap = '<div class="reviews" id="commentsHost" style="max-width:720px;margin:26px auto 0"></div>';
    host.insertAdjacentHTML('afterend', socialRow + commentWrap);
    if (u && u.uid !== p.sellerId) {
      DB.collection('users').doc(u.uid).collection('following').doc(p.sellerId).get()
        .then((s) => {
          const b = document.getElementById('followBtn');
          if (b && s.exists) {
            b.classList.add('on');
            b.textContent = t('following');
          }
        })
        .catch(() => {});
    }
    loadComments(p.id, p.sellerId, u);
  }

  function commentItemHtml(c, pid, uid) {
    const time = c.createdAt ? (c.createdAt.toDate ? ts2date(c.createdAt.toDate()) : ts2date(c.createdAt)) : '';
    const mine = uid && c.userId === uid;
    return '<div class="comment" data-cid="' + esc(c.id) + '">'
      + '<div class="who"><div class="avatar">' + esc((c.userName || '?').slice(0, 1).toUpperCase()) + '</div>'
      + '<div style="flex:1"><div class="nm">' + esc(c.userName || 'Mteja') + '</div>'
      + '<div class="loc">' + esc(time) + '</div></div>'
      + (mine ? '<button class="btn-sm danger" data-act="delcomment" data-p="' + esc(pid) + '" data-c="' + esc(c.id) + '">' + esc(t('delete')) + '</button>' : '')
      + '</div>'
      + '<p>' + esc(c.text || '') + '</p>'
      + '<div class="comment-replies">'
      + '<button class="minilink" data-act="togglereplies" data-p="' + esc(pid) + '" data-c="' + esc(c.id) + '">'
      + (c.replyCount || 0) + ' ' + esc(t('replies')) + '</button>'
      + '<div class="replies" hidden></div>'
      + (uid ? '<div class="reply-box" hidden><input class="reply-in" placeholder="' + esc(t('write_reply')) + '">'
        + '<button class="btn-sm" data-act="addreply" data-p="' + esc(pid) + '" data-c="' + esc(c.id) + '">' + esc(t('send')) + '</button></div>' : '')
      + '</div></div>';
  }

  async function loadComments(pid, sellerId, uid) {
    const host = document.getElementById('commentsHost');
    if (!host) return;
    host.innerHTML = '<h3>' + esc(t('comments')) + '</h3>'
      + (uid ? '<div class="comment-form"><textarea id="cmtText" rows="2" placeholder="' + esc(t('write_comment')) + '"></textarea>'
        + '<button class="btn-dark" data-act="addcomment" data-p="' + esc(pid) + '">' + esc(t('send')) + '</button></div>' : '<p class="muted">' + esc(t('login_to_comment')) + '</p>')
      + '<div id="cmtList"><span class="section-muted">' + esc(t('loading')) + '</span></div>';
    try {
      const snap = await DB.collection('products').doc(pid).collection('comments').orderBy('createdAt', 'desc').limit(60).get();
      const list = document.getElementById('cmtList');
      if (!list) return;
      list.innerHTML = snap.docs.length
        ? snap.docs.map((d) => commentItemHtml({ id: d.id, ...d.data() }, pid, uid)).join('')
        : '<p class="muted">' + esc(t('no_comments')) + '</p>';
    } catch (_) {
      const list = document.getElementById('cmtList');
      if (list) list.innerHTML = '<p class="muted">' + esc(t('err_generic')) + '</p>';
    }
  }

  async function toggleReplies(pid, cid, el) {
    const wrap = el && el.parentElement;
    const listEl = wrap ? wrap.querySelector('.replies') : null;
    if (!listEl) return;
    if (!listEl.querySelector('.reply-item')) {
      listEl.innerHTML = '<span class="section-muted">' + esc(t('loading')) + '</span>';
      try {
        const snap = await DB.collection('products').doc(pid).collection('comments').doc(cid).collection('replies').orderBy('createdAt').limit(60).get();
        const uid = AUTH.currentUser ? AUTH.currentUser.uid : null;
        listEl.innerHTML = snap.docs.length ? snap.docs.map((d) => {
          const r = { id: d.id, ...d.data() };
          return '<div class="reply-item"><div class="nm">' + esc(r.userName || 'Mteja') + '</div>'
            + '<p>' + esc(r.text || '') + '</p>'
            + (uid && r.userId === uid ? '<button class="btn-sm danger" data-act="delreply" data-p="' + esc(pid) + '" data-c="' + esc(cid) + '" data-r="' + esc(r.id) + '">' + esc(t('delete')) + '</button>' : '')
            + '</div>';
        }).join('') : '<p class="muted">' + esc(t('no_replies')) + '</p>';
      } catch (_) { listEl.innerHTML = ''; }
    }
    listEl.hidden = !listEl.hidden;
    const box = wrap ? wrap.querySelector('.reply-box') : null;
    if (box) box.hidden = !listEl.hidden;
  }

  async function sendComment(pid) {
    const u = AUTH.currentUser;
    if (!u) { renderAuthForm('signin'); return; }
    const el = document.getElementById('cmtText');
    const text = (el ? el.value : '').trim();
    if (!text) { toast(t('write_comment')); return; }
    try {
      await u.getIdToken(true);
      await DB.collection('products').doc(pid).collection('comments').add({
        userId: u.uid,
        userName: u.displayName || u.email || 'Unknown',
        userImage: u.photoURL || null,
        text: text,
        createdAt: FV.serverTimestamp(),
        replyCount: 0,
      });
      if (el) el.value = '';
      const p = await getProduct(pid);
      loadComments(pid, p ? p.sellerId : '', u);
      toast('✔');
    } catch (e) { toast(errMsg(e)); }
  }

  async function sendReply(pid, cid, el) {
    const u = AUTH.currentUser;
    if (!u) { renderAuthForm('signin'); return; }
    const input = el.previousElementSibling;
    const text = input ? input.value.trim() : '';
    if (!text) { toast(t('write_reply')); return; }
    try {
      await u.getIdToken(true);
      await DB.collection('products').doc(pid).collection('comments').doc(cid).collection('replies').add({
        userId: u.uid,
        userName: u.displayName || u.email || 'Unknown',
        userImage: u.photoURL || null,
        text: text,
        createdAt: FV.serverTimestamp(),
      });
      const cRef = DB.collection('products').doc(pid).collection('comments').doc(cid);
      const cSnap = await cRef.get().catch(() => null);
      if (cSnap && cSnap.exists) {
        await cRef.update({ replyCount: FV.increment(1) }).catch(() => {});
      } else {
        await cRef.set({ replyCount: 1, userId: '', userName: '', text: '', createdAt: FV.serverTimestamp() }, { merge: true }).catch(() => {});
      }
      if (input) input.value = '';
      const container = el.closest('.comment');
      const tog = container ? container.querySelector('[data-act="togglereplies"]') : null;
      if (container) { const rl = container.querySelector('.replies'); if (rl) { rl.innerHTML = ''; rl.hidden = true; } }
      if (tog) tog.click();
      toast('✔');
    } catch (e) { toast(errMsg(e)); }
  }

  async function deleteComment(pid, cid) {
    const u = AUTH.currentUser;
    if (!u) return;
    const snap = await DB.collection('products').doc(pid).collection('comments').doc(cid).get().catch(() => null);
    if (!snap || !snap.exists || snap.data().userId !== u.uid) { toast(t('own_only')); return; }
    try {
      const replies = await DB.collection('products').doc(pid).collection('comments').doc(cid).collection('replies').get();
      const batch = DB.batch();
      replies.docs.forEach((r) => batch.delete(r.ref));
      batch.delete(snap.ref);
      await batch.commit();
      loadComments(pid, '', u);
      toast('✔');
    } catch (e) { toast(errMsg(e)); }
  }

  async function deleteReply(pid, cid, rid) {
    const u = AUTH.currentUser;
    if (!u) return;
    const rRef = DB.collection('products').doc(pid).collection('comments').doc(cid).collection('replies').doc(rid);
    const snap = await rRef.get().catch(() => null);
    if (!snap || !snap.exists || snap.data().userId !== u.uid) { toast(t('own_only')); return; }
    try {
      await rRef.delete();
      await DB.collection('products').doc(pid).collection('comments').doc(cid).update({ replyCount: FV.increment(-1) }).catch(() => {});
      toast('✔');
    } catch (e) { toast(errMsg(e)); }
  }

  /* ---------- Chat ---------- */

  function roomIdFor(a, b) { return [a, b].sort().join('_'); }

  async function ensureRoom(otherUid) {
    const u = AUTH.currentUser;
    if (!u) throw new Error(t('need_auth'));
    const roomId = roomIdFor(u.uid, otherUid);
    const snap = await DB.collection('chat_rooms').doc(roomId).get();
    if (snap.exists) return roomId;
    await DB.collection('chat_rooms').doc(roomId).set({
      participants: [u.uid, otherUid],
      last_message: '',
      last_timestamp: FV.serverTimestamp(),
      unread_counts: { [u.uid]: 0, [otherUid]: 0 },
      unread_count_buyer: 0,
      unread_count_seller: 0,
    });
    return roomId;
  }

  async function renderChatInbox() {
    setLang(); setHero(false);
    const u = AUTH.currentUser;
    if (!u) { renderAuthForm('signin'); toast(t('need_auth')); return; }
    view.innerHTML = '<div class="container-wide"><div class="headline-row"><span style="font-family:var(--font-display);font-weight:700;color:var(--ink);font-size:16px">' + esc(t('chats')) + '</span></div>'
      + '<div id="chatInbox"><div class="skel" style="height:120px"></div></div></div>';
    const host = document.getElementById('chatInbox');
    let rooms = [];
    try {
      const snap = await DB.collection('chat_rooms').where('participants', 'array-contains', u.uid).orderBy('last_timestamp', 'desc').limit(60).get();
      rooms = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    } catch (_) {}
    if (!rooms.length) { host.innerHTML = emptyHtml(t('chats_empty'), '', t('home_browse')); return; }
    const rows = await Promise.all(rooms.map(async (r) => {
      const otherUid = (r.participants || []).find((x) => x !== u.uid) || '';
      let name = 'Muuzaji';
      try {
        const s = await DB.collection('users').doc(otherUid).get();
        if (s.exists) name = s.data().sellerName || s.data().name || s.data().displayName || name;
      } catch (_) {}
      const last = r.last_message || '';
      const time = r.last_timestamp ? (r.last_timestamp.toDate ? ts2date(r.last_timestamp.toDate()) : ts2date(r.last_timestamp)) : '';
      const mine = (r.unread_counts && r.unread_counts[u.uid]) || 0;
      return '<a class="chat-row" href="#/chat/' + encodeURIComponent(otherUid) + '?name=' + encodeURIComponent(name) + '">'
        + '<div class="avatar">' + esc(name.slice(0, 1).toUpperCase()) + '</div>'
        + '<div class="mid"><div class="nm">' + esc(name) + '</div><div class="loc">' + esc(last) + '</div></div>'
        + '<div class="rt">' + (mine ? '<span class="badge-cnt">' + mine + '</span>' : '') + '<div class="loc">' + esc(time) + '</div></div>'
        + '</a>';
    }));
    host.innerHTML = rows.join('');
  }

  async function markRoomRead(roomId) {
    const u = AUTH.currentUser;
    if (!u) return;
    try {
      await DB.collection('chat_rooms').doc(roomId).update({
        ['unread_counts.' + u.uid]: 0,
        unread_count_buyer: 0,
        unread_count_seller: 0,
      });
    } catch (_) {}
  }

  async function renderChatRoom(otherUid, name) {
    setLang(); setHero(false);
    const u = AUTH.currentUser;
    if (!u) { renderAuthForm('signin'); toast(t('need_auth')); return; }
    let roomId;
    try { roomId = await ensureRoom(otherUid); }
    catch (e) { toast(errMsg(e)); return; }
    view.innerHTML = '<div class="container-wide"><div class="headline-row"><a class="mini-link" href="#/chats">← ' + esc(t('back')) + '</a>'
      + '<span style="font-family:var(--font-display);font-weight:700;color:var(--ink);font-size:16px">' + esc(name || 'Muuzaji') + '</span></div>'
      + '<div class="chat-card">'
      + '<div class="chat-msgs" id="chatMsgs"><div class="skel" style="height:120px"></div></div>'
      + '<form id="chatForm" class="chat-send">'
      + '<input id="chatText" autocomplete="off" placeholder="' + esc(t('write_msg')) + '">'
      + '<button class="btn-accent" type="submit">' + esc(t('send')) + '</button>'
      + '</form></div></div>';
    const list = document.getElementById('chatMsgs');
    const render = (msgs) => {
      list.innerHTML = msgs.length ? msgs.map((m) => {
        const mine = m.senderId === u.uid;
        return '<div class="msg ' + (mine ? 'mine' : '') + '">'
          + '<div class="bubble">' + esc(m.text || '') + '</div>'
          + '<div class="meta">' + (m.productName ? esc(m.productName) + ' · ' : '') + esc(m.timestamp ? (m.timestamp.toDate ? ts2date(m.timestamp.toDate()) : ts2date(m.timestamp)) : '') + '</div>'
          + '</div>';
      }).join('') : '<p class="muted" style="padding:12px">' + esc(t('say_hi')) + '</p>';
      list.scrollTop = list.scrollHeight;
    };
    try {
      const snap = await DB.collection('chat_rooms').doc(roomId).collection('messages').orderBy('timestamp', 'asc').limit(100).get();
      render(snap.docs.length ? snap.docs.map((d) => ({ id: d.id, ...d.data() })) : []);
    } catch (_) { render([]); }
    await markRoomRead(roomId);
    let lastSeen = Date.now();
    try {
      DB.collection('chat_rooms').doc(roomId).collection('messages').where('timestamp', '>', new Date(lastSeen)).onSnapshot((snap) => {
        if (snap.docs.length) {
          const added = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
          const msgsEl = document.getElementById('chatMsgs');
          const forced = Array.prototype.slice.call(msgsEl ? msgsEl.querySelectorAll('.msg') : []);
          const have = new Set(forced.map((el) => {
            const mEl = el.querySelector('.bubble');
            return mEl ? mEl.textContent : '';
          }));
          added.forEach((m) => {
            if (m.senderId === u.uid || have.has(m.text)) return;
            const wrap = document.createElement('div');
            wrap.className = 'msg ' + (m.senderId === u.uid ? 'mine' : '');
            wrap.innerHTML = '<div class="bubble">' + esc(m.text || '') + '</div>'
              + '<div class="meta">' + esc(m.timestamp && m.timestamp.toDate ? ts2date(m.timestamp.toDate()) : '') + '</div>';
            const l = document.getElementById('chatMsgs');
            if (l) { l.appendChild(wrap); l.scrollTop = l.scrollHeight; }
          });
        }
      });
    } catch (_) {}
    const form = document.getElementById('chatForm');
    if (form) form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const txt = document.getElementById('chatText');
      const text = (txt ? txt.value : '').trim();
      if (!text) return;
      try {
        await apiPost('/api/chat/send', { senderId: u.uid, receiverId: otherUid, roomId: roomId, text: text });
        try {
          await DB.collection('chat_rooms').doc(roomId).update({
            last_message: text,
            last_timestamp: FV.serverTimestamp(),
          });
        } catch (_) {}
        if (txt) txt.value = '';
        const snap = await DB.collection('chat_rooms').doc(roomId).collection('messages').orderBy('timestamp', 'asc').limit(100).get().catch(() => null);
        if (snap) render(snap.docs.length ? snap.docs.map((d) => ({ id: d.id, ...d.data() })) : []);
      } catch (err) { toast(errMsg(err)); }
    });
  }

  /* ---------- Notifications ---------- */

  async function renderNotifications() {
    setLang(); setHero(false);
    const u = AUTH.currentUser;
    if (!u) { renderAuthForm('signin'); toast(t('need_auth')); return; }
    view.innerHTML = '<div class="container-wide"><div class="headline-row">'
      + '<span style="font-family:var(--font-display);font-weight:700;color:var(--ink);font-size:16px">' + esc(t('notifications')) + '</span>'
      + '<div class="rowbtns"><button class="btn-sm" data-act="notifreadall">' + esc(t('mark_all_read')) + '</button>'
      + '<a class="btn-sm btn-outline" href="#/notifprefs">' + esc(t('notif_settings')) + '</a></div>'
      + '</div><div id="notifList"><div class="skel" style="height:120px"></div></div></div>';
    const host = document.getElementById('notifList');
    let docs = [];
    try {
      const snap = await DB.collection('notifications').where('userId', '==', u.uid).orderBy('createdAt', 'desc').limit(80).get();
      docs = snap.docs;
    } catch (_) {}
    if (!docs.length) { host.innerHTML = emptyHtml(t('no_notifications'), '', t('home_browse')); return; }
    host.innerHTML = docs.map((d) => {
      const n = d.data();
      const isRead = n.isRead === true;
      const time = n.createdAt ? (n.createdAt.toDate ? ts2date(n.createdAt.toDate()) : ts2date(n.createdAt)) : '';
      return '<div class="notif-item' + (isRead ? '' : ' unread') + '" data-nid="' + esc(d.id) + '">'
        + '<div class="mid"><div class="nm">' + esc(n.title || '') + '</div>'
        + '<p>' + esc(n.body || '') + '</p>'
        + '<div class="loc">' + esc(time) + '</div></div>'
        + '<button class="btn-sm danger" data-act="notifdel" data-n="' + esc(d.id) + '">' + esc(t('delete')) + '</button>'
        + '</div>';
    }).join('');
    notifBadge();
  }

  async function notifTap(nid) {
    const u = AUTH.currentUser;
    if (!u) return;
    await DB.collection('notifications').doc(nid).set({ isRead: true }, { merge: true }).catch(() => {});
    notifBadge();
  }

  async function notifDelete(nid) {
    const u = AUTH.currentUser;
    if (!u) return;
    try { await DB.collection('notifications').doc(nid).delete(); toast('✔ ' + t('notification_deleted')); renderNotifications(); }
    catch (e) { toast(errMsg(e)); }
  }

  async function notifMarkAllRead() {
    const u = AUTH.currentUser;
    if (!u) return;
    try {
      const snap = await DB.collection('notifications').where('userId', '==', u.uid).where('isRead', '==', false).limit(200).get();
      const batch = DB.batch();
      snap.docs.forEach((d) => batch.update(d.ref, { isRead: true }));
      await batch.commit();
      toast('✔ ' + t('mark_all_read'));
      renderNotifications();
    } catch (e) { toast(errMsg(e)); }
  }

  async function renderNotifPrefs() {
    setLang(); setHero(false);
    const u = AUTH.currentUser;
    if (!u) { renderAuthForm('signin'); toast(t('need_auth')); return; }
    view.innerHTML = '<div class="container-wide"><div class="headline-row"><a class="mini-link" href="#/notifications">← ' + esc(t('back')) + '</a>'
      + '<span style="font-family:var(--font-display);font-weight:700;color:var(--ink);font-size:16px">' + esc(t('notif_settings')) + '</span></div>'
      + '<div id="prefsBox"><div class="skel" style="height:120px"></div></div></div>';
    let prefs = {};
    try {
      const data = await apiPost('/api/notifications/preferences/get', {});
      prefs = (data && data.preferences) || {};
    } catch (_) {}
    const box = document.getElementById('prefsBox');
    if (!box) return;
    const keys = Object.keys(prefs);
    box.innerHTML = '<div class="form-card">'
      + keys.map((k) => {
        const v = prefs[k];
        if (Array.isArray(v)) return '';
        if (typeof v === 'object' && v !== null) return '';
        return '<label class="chk"><input type="checkbox" data-pref="' + esc(k) + '"' + (v ? ' checked' : '') + '> <span>' + esc(k) + '</span></label>';
      }).join('')
      + '<button class="btn-dark btn-block mt16" data-act="prefssave">' + esc(t('save')) + '</button>'
      + '</div>';
    const userId = u.uid;
    hostParityPrefs = { box: box, userId: userId };
  }
  let hostParityPrefs = null;

  async function savePrefs() {
    if (!hostParityPrefs) return;
    const prefs = {};
    $all('[data-pref]', hostParityPrefs.box).forEach((c) => {
      const k = c.dataset.pref;
      if (/^[a-z_]+$/.test(k) && k.indexOf('interested_districts') < 0 && k.indexOf('sms_enabled') < 0) {
        prefs[k] = c.checked;
      }
    });
    try {
      await apiPost('/api/notifications/preferences/set', { preferences: prefs });
      toast('✔');
    } catch (e) { toast(errMsg(e)); }
  }

  /* ---------- Flash sale ---------- */

  function flashTimeCheck(s) {
    if (!s) return false;
    const now = Date.now();
    const st = s.startTime ? (s.startTime.toDate ? s.startTime.toDate().getTime() : new Date(s.startTime).getTime()) : 0;
    const en = s.endTime ? (s.endTime.toDate ? s.endTime.toDate().getTime() : new Date(s.endTime).getTime()) : 0;
    return now >= st && now <= en;
  }

  async function renderFlashSale() {
    setLang(); setHero(false);
    const u = AUTH.currentUser;
    view.innerHTML = '<div class="container-wide"><div class="headline-row">'
      + '<span style="font-family:var(--font-display);font-weight:700;color:var(--ink);font-size:16px">⚡ ' + esc(t('flash_sale')) + '</span>'
      + (u ? '<a class="btn-sm" href="#/seller?t=flash">' + esc(t('seller_flash')) + '</a>' : '')
      + '</div><div id="fsGrid" class="grid"><div class="skel" style="height:160px"></div></div></div>';
    const host = document.getElementById('fsGrid');
    let sales = [];
    try {
      const snap = await DB.collection('flash_sales').where('isActive', '==', true).get();
      sales = snap.docs.map((d) => ({ id: d.id, ...d.data() })).filter(flashTimeCheck).sort((a, b) => a.endTime - b.endTime);
    } catch (_) {}
    if (!sales.length) { host.innerHTML = emptyHtml(t('fs_empty'), '', t('home_browse')); return; }
    const cards = await Promise.all(sales.map(async (s) => {
      let p = null;
      try { p = await getProduct(s.productId); } catch (_) {}
      const im = p && p.images && p.images[0] ? p.images[0] : (s.productImage || '');
      const img = im ? '<img src="' + esc(im) + '" alt="" loading="lazy" onerror="this.remove()">' : '<div class="ph">SOKO</div>';
      const salePrice = Number(s.salePrice) || 0;
      const orig = Number(s.originalPrice) || 0;
      const disc = Number(s.discountPercent) || (orig > salePrice && orig ? Math.round((1 - salePrice / orig) * 100) : 0);
      const href = p ? '#/p/' + encodeURIComponent(s.productId) : '#/search?q=' + encodeURIComponent(s.productName || '');
      return '<a class="card fs-card" href="' + href + '">'
        + '<div class="fs-banner">-' + disc + '%</div>'
        + '<div class="thumb">' + img + '</div>'
        + '<div class="card-body"><div class="category">⚡ ' + esc(t('flash_sale')) + '</div>'
        + '<div class="title">' + esc(s.productName || 'Bidhaa') + '</div>'
        + '<div class="price">' + fmtTZS(salePrice) + (orig > salePrice ? ' <s class="strike">' + fmtTZS(orig) + '</s>' : '') + '</div>'
        + (s.stock != null ? '<div class="loc">' + s.stock + ' ' + esc(t('in_stock')) + '</div>' : '')
        + '</div></a>';
    }));
    host.innerHTML = cards.join('');
  }

  async function sellerFlashBody(body, user) {
    body.innerHTML = '<div class="sd-toolbar"><h3>⚡ ' + esc(t('seller_flash')) + '</h3>'
      + '<button class="btn-accent" data-act="fscreate">+ ' + esc(t('fs_new')) + '</button></div>'
      + '<div id="fsMine"><div class="skel" style="height:64px"></div></div>';
    const host = document.getElementById('fsMine');
    let list = [];
    try {
      const snap = await DB.collection('flash_sales').where('sellerId', '==', user.uid).get();
      list = snap.docs.map((d) => ({ id: d.id, ...d.data() })).sort((a, b) => (b.endTime ? b.endTime : 0) - (a.endTime ? a.endTime : 0));
    } catch (_) {}
    host.innerHTML = list.length ? list.map((s) => {
      const on = flashTimeCheck(s);
      return '<div class="rowline"><div class="thumb">' + (s.productImage ? '<img src="' + esc(s.productImage) + '" alt="">' : '') + '</div>'
        + '<div class="mid"><div class="nm">' + esc(s.productName || '') + '</div>'
        + '<div class="pr">' + fmtTZS(s.salePrice) + ' (-' + Number(s.discountPercent) + '%) · ' + s.stock + ' ' + esc(t('in_stock')) + '</div></div>'
        + '<div class="ctrls"><span class="pill ' + (on ? 'done' : 'wait') + '">' + esc(on ? t('fs_active') : t('fs_ended')) + '</span>'
        + '<button class="btn-sm danger" data-act="fsdel" data-f="' + esc(s.id) + '">' + esc(t('delete')) + '</button></div></div>';
    }).join('') : emptyHtml(t('fs_none'), '', t('seller_flash'));
  }

  async function fsCreateForm() {
    const u = AUTH.currentUser;
    if (!u) { toast(t('need_auth')); return; }
    let products = [];
    try {
      const snap = await DB.collection('products').where('sellerId', '==', u.uid).where('isActive', '==', true).limit(30).get();
      products = snap.docs.map(norm);
    } catch (_) {}
    if (!products.length) { toast(t('fs_need_product')); return; }
    const opt = products.map((p) => '<option value="' + esc(p.id) + '" data-img="' + esc((p.images && p.images[0]) || '') + '" data-price="' + p.price + '">' + esc(p.name) + ' — ' + fmtTZS(p.price) + '</option>').join('');
    const now = new Date();
    const start = new Date(now.getTime() + 5 * 60000);
    const end = new Date(now.getTime() + 24 * 3600000);
    const pad = (x) => String(x).padStart(2, '0');
    const local = (d) => d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + 'T' + pad(d.getHours()) + ':' + pad(d.getMinutes());
    const html = '<div class="form-card">'
      + '<div class="field"><label>Bidhaa</label><select id="fsProduct">' + opt + '</select></div>'
      + '<div class="field"><label>Bei ya mauzo (TZS)</label><input id="fsPrice" type="number" min="1" placeholder="0"></div>'
      + '<div class="field"><label>Idadi (stock)</label><input id="fsStock" type="number" min="1" value="1"></div>'
      + '<div class="form-row"><div class="field"><label>Anza</label><input id="fsStart" type="datetime-local" value="' + local(start) + '"></div>'
      + '<div class="field"><label>Mwisho</label><input id="fsEnd" type="datetime-local" value="' + local(end) + '"></div></div>'
      + '<div class="rowbtns"><button class="btn-dark" data-act="fscreate2">' + esc(t('submit')) + '</button>'
      + '<button class="btn-outline" data-act="fscancel">' + esc(t('cancel')) + '</button></div></div>';
    parityModal('⚡ ' + t('fs_new'), html);
    const sel = document.getElementById('fsProduct');
    if (sel) sel.addEventListener('change', () => {
      const o = sel.options[sel.selectedIndex];
      const pr = document.getElementById('fsPrice');
      if (pr && o && o.dataset.price) pr.value = o.dataset.price;
    });
    if (products.length && document.getElementById('fsPrice')) {
      document.getElementById('fsPrice').value = products[0].price;
    }
  }

  async function fsCreate2() {
    const u = AUTH.currentUser;
    if (!u) return;
    const pid = document.getElementById('fsProduct').value;
    const salePrice = Math.round(Number(document.getElementById('fsPrice').value) || 0);
    const stock = Math.max(1, Math.round(Number(document.getElementById('fsStock').value) || 1));
    const startIso = new Date(document.getElementById('fsStart').value).toISOString();
    const endIso = new Date(document.getElementById('fsEnd').value).toISOString();
    let p = null;
    try { p = await getProduct(pid); } catch (_) {}
    if (!p) { toast(t('fs_need_product')); return; }
    if (salePrice < 1 || salePrice >= p.price) { toast('Bei ya flash inaweza kuwa chini ya bei halisi.'); return; }
    const orig = p.price;
    const disc = Math.round((1 - salePrice / orig) * 100);
    try {
      const data = await apiPost('/api/flash-sale/create', {
        productId: pid,
        productName: p.name,
        productImage: (p.images && p.images[0]) || '',
        originalPrice: orig,
        salePrice: salePrice,
        discountPercent: disc,
        sellerId: u.uid,
        sellerName: p.sellerName || u.displayName || '',
        sellerPhone: p.sellerPhone || u.phoneNumber || '',
        location: p.location || '',
        stock: stock,
        startTime: startIso,
        endTime: endIso,
      });
      closeParityModal();
      toast('✔ ' + t('fs_created'));
      renderSellerPage('flash');
    } catch (e) { toast(errMsg(e)); }
  }

  async function fsDelete(fid) {
    if (!window.confirm(t('del_confirm'))) return;
    try {
      await apiPost('/api/flash-sales/delete', { flashSaleId: fid });
      toast('✔ ' + t('delete'));
      renderSellerPage('flash');
    } catch (e) { toast(errMsg(e)); }
  }

  /* ---------- Modal ---------- */

  function parityModal(title, bodyHtml) {
    let m = document.getElementById('parityModal');
    if (!m) {
      m = document.createElement('div');
      m.id = 'parityModal';
      m.className = 'pm-wrap';
      m.innerHTML = '<div class="pm" role="dialog" aria-modal="true"><div class="pm-head"><span></span><button type="button" class="icon-btn" data-act="pmclose">×</button></div><div class="pm-body"></div></div>';
      document.body.appendChild(m);
      m.addEventListener('click', (e) => { if (e.target === m) closeParityModal(); });
    }
    m.querySelector('.pm-head span').textContent = title || '';
    m.querySelector('.pm-body').innerHTML = bodyHtml || '';
    m.hidden = false;
  }
  function closeParityModal() {
    const m = document.getElementById('parityModal');
    if (m) m.hidden = true;
  }

  /* ---------- Seller ops: quote / dispatch / OTP ---------- */

  function pgOrderId(o) { return o && (o.orderId || o.id); }

  function isShopSellerSid(o, uid) { return o && o.sellerId && uid && o.sellerId === uid; }

  function sellerOrderActionsHtml(o, uid, pg) {
    if (!o || !uid || !isShopSellerSid(o, uid)) return '';
    const st = o.status || 'pending';
    const pgStatus = String(((pg && pg.status) || '').toLowerCase());
    const pgId = pgOrderId(o);
    const needsQuote = (pgStatus === 'pending_shipping_fee');
    const canCancel = (pgStatus === 'pending_shipping_fee');
    const canDispatch = ['in_escrow', 'ready_to_dispatch'].indexOf(pgStatus) >= 0;
    const canOtp = (st === 'delivered' || st === 'in_transit' || st === 'dispatched')
      && ['otp_pending', 'inspection_period'].indexOf(pgStatus) >= 0;
    let html = '<div class="seller-acts">';
    if (needsQuote) {
      html += '<button class="btn-sm" data-act="squote" data-o="' + esc(pgId) + '">' + esc(t('seller_set_ship')) + '</button>';
    }
    if (canCancel) {
      html += '<button class="btn-sm" data-act="scancel" data-o="' + esc(pgId) + '">' + esc(t('cancel_order')) + '</button>';
    }
    if (canDispatch) {
      html += '<button class="btn-sm" data-act="sdispatch" data-o="' + esc(pgId) + '">' + esc(t('dispatch')) + '</button>';
    }
    if (canOtp) {
      html += '<button class="btn-sm" data-act="sotp" data-o="' + esc(pgId) + '">' + esc(t('issue_otp')) + '</button>';
    }
    html += '</div>';
    return html;
  }

  async function sellerQuote(oid) {
    if (!oid) { toast(t('err_generic')); return; }
    parityModal(t('seller_set_ship'), '<div class="form-card">'
      + '<div class="field"><label>' + esc(t('ship_cost')) + ' (TZS)</label><input id="sqAmt" type="number" min="1"></div>'
      + '<div class="field"><label>' + esc(t('ship_days')) + '</label><input id="sqDays" type="number" min="1" max="60" value="3"></div>'
      + '<div class="field"><label>' + esc(t('ship_notes')) + '</label><input id="sqNotes" placeholder="' + esc(t('ship_notes_ph')) + '"></div>'
      + '<div class="rowbtns"><button class="btn-dark" data-act="squote2" data-o="' + esc(oid) + '">' + esc(t('submit')) + '</button>'
      + '<button class="btn-outline" data-act="pmclose">' + esc(t('cancel')) + '</button></div></div>');
  }

  async function sellerQuote2(oid) {
    const amount = Math.round(Number(document.getElementById('sqAmt').value) || 0);
    const estimatedDays = Math.min(60, Math.max(1, Math.round(Number(document.getElementById('sqDays').value) || 1)));
    const notes = (document.getElementById('sqNotes').value || '').trim();
    if (amount < 1) { toast('Andika gharama.'); return; }
    try {
      await apiPost('/v1/orders/' + encodeURIComponent(oid) + '/shipping-quote', { amount: amount, estimatedDays: estimatedDays, notes: notes });
      closeParityModal();
      toast('✔ ' + t('seller_set_ship'));
      renderSellerPage('orders');
    } catch (e) { toast(errMsg(e)); }
  }

  async function sellerDispatch(oid) {
    if (!oid) { toast(t('err_generic')); return; }
    parityModal(t('dispatch'), '<div class="form-card">'
      + '<div class="field"><label>' + esc(t('courier')) + '</label><input id="dpCourier" placeholder="Bodaboda / Express"></div>'
      + '<div class="field"><label>' + esc(t('tracking')) + '</label><input id="dpTrack" placeholder="Namba ya tracking"></div>'
      + '<label class="chk"><input type="checkbox" id="dpOtp" checked> <span>' + esc(t('issue_otp_after')) + '</span></label>'
      + '<div class="rowbtns"><button class="btn-dark" data-act="sdispatch2" data-o="' + esc(oid) + '">' + esc(t('submit')) + '</button>'
      + '<button class="btn-outline" data-act="pmclose">' + esc(t('cancel')) + '</button></div></div>');
  }

  async function sellerDispatch2(oid) {
    const courierName = (document.getElementById('dpCourier').value || 'Bodaboda').trim();
    const trackingNumber = (document.getElementById('dpTrack').value || 'TRK-' + Date.now().toString().slice(-8)).trim();
    const doOtp = !document.getElementById('dpOtp') || document.getElementById('dpOtp').checked;
    const btn = document.querySelector('[data-act="sdispatch2"]');
    if (btn) btn.disabled = true;
    try {
      const ord = await apiPost('/v1/orders/' + encodeURIComponent(oid) + '/dispatch', { courierName: courierName, trackingNumber: trackingNumber });
      if (doOtp) {
        try {
          const otp = await apiPost('/v1/handover/' + encodeURIComponent(oid) + '/otp/issue', {});
          closeParityModal();
          const code = (otp && otp.data && otp.data.otp) || '';
          parityModal(t('issue_otp'), '<div style="text-align:center">'
            + '<p>' + esc(t('otp_hand_to_buyer')) + '</p>'
            + '<div class="otp-code">' + esc(code) + '</div>'
            + '<p class="muted" style="font-size:12px">' + esc(t('otp_expires_note')) + '</p>'
            + '<button class="btn-dark btn-block" data-act="pmclose">' + esc(t('close')) + '</button></div>');
          toast('✔ ' + t('dispatch') + ' — ' + t('issue_otp'));
          return;
        } catch (e) { toast(errMsg(e)); }
      }
      closeParityModal();
      toast('✔ ' + t('dispatch'));
    } catch (e) {
      toast(errMsg(e));
    } finally {
      if (btn) btn.disabled = false;
    }
    renderSellerPage('orders');
  }

  async function sellerOtp(oid) {
    if (!oid) { toast(t('err_generic')); return; }
    const btn = document.querySelector('[data-act="sotp"]');
    if (btn) btn.disabled = true;
    try {
      const otp = await apiPost('/v1/handover/' + encodeURIComponent(oid) + '/otp/issue', {});
      const code = (otp && otp.data && otp.data.otp) || '';
      closeParityModal();
      parityModal(t('issue_otp'), '<div style="text-align:center">'
        + '<p>' + esc(t('otp_hand_to_buyer')) + '</p>'
        + '<div class="otp-code">' + esc(code) + '</div>'
        + '<p class="muted" style="font-size:12px">' + esc(t('otp_expires_note')) + '</p>'
        + '<button class="btn-dark btn-block" data-act="pmclose">' + esc(t('close')) + '</button></div>');
    } catch (e) { toast(errMsg(e)); }
  }

  /* ---------- Buyer: quote approve + delivery OTP + pay + dispute ---------- */

  async function parityBuyerOrderArea(order, pgOrder) {
    const host = $('.order-detail');
    if (!host || !order) return;
    const u = AUTH.currentUser;
    if (!u) return;
    const st = order.status || 'pending';
    const pg = pgOrder || {};
    const pgStatus = (pg.status || '').toLowerCase();
    const box = document.createElement('div');
    box.className = 'card-block';
    let inner = '';
    const canPay = (st === 'pending' || st === 'address_required' || st === 'shipping_fee_submitted')
      && ['pending_shipping_fee', 'awaiting_escrow_payment', 'payment_pending'].indexOf(pgStatus) >= 0;
    const pendingQuote = (pg.shippingQuotes || []).findIndex((q) => q.status === 'pending') >= 0;
    const awaitingApprove = pendingQuote && pgStatus === 'pending_shipping_fee';
    if (awaitingApprove) {
      const quote = (pg.shippingQuotes || []).filter((q) => q.status === 'pending')[0];
      const qAmt = Number(quote ? Number(quote.amount || 0) : 0);
      inner += '<h3>' + esc(t('ship_quote')) + '</h3>'
        + '<div class="sum-row"><span>' + esc(t('ship_cost')) + '</span><span class="order-no">' + fmtTZS(qAmt) + '</span></div>'
        + '<div class="rowbtns"><button class="btn-accent" data-act="quoteapp" data-o="' + esc(pg.id) + '">' + esc(t('approve')) + '</button>'
        + '<button class="btn-outline" data-act="quoterej" data-o="' + esc(pg.id) + '">' + esc(t('reject')) + '</button></div>';
    } else if (canPay) {
      const paid = (pg.payments || []).filter((p) => p.status === 'completed')
        .reduce((s, p) => s + Number(p.amount || 0), 0);
      const amt = Math.max(0, Math.round(Number(pg.totalAmount || 0) - paid));
      if (amt > 0) {
        inner += '<h3>' + esc(t('pay_now')) + '</h3>'
          + '<p class="muted">' + esc(t('pay_total')) + ': <b>' + fmtTZS(amt) + '</b></p>'
          + '<button class="btn-accent" data-act="buyerpay" data-o="' + esc(pg.id) + '" data-amt="' + amt + '">' + esc(t('pay_now')) + '</button>';
      }
    }
    const otpReady = (st === 'delivered' || st === 'in_transit' || st === 'dispatched')
      && ['otp_pending', 'inspection_period', 'delivery_attempted'].indexOf(pgStatus) >= 0;
    if (otpReady) {
      inner += '<h3>' + esc(t('otp_confirm')) + '</h3>'
        + '<p class="muted">' + esc(t('otp_enter_note')) + '</p>'
        + '<div class="otp-inline"><input id="buyerOtp" type="text" inputmode="numeric" maxlength="6" placeholder="000000">'
        + '<button class="btn-accent" data-act="buyerotp" data-o="' + esc(pg.id) + '">' + esc(t('confirm')) + '</button></div>';
    }
    if (st !== 'completed' && st !== 'cancelled' && st !== 'refunded'
      && ['completed', 'cancelled', 'refunded'].indexOf(pgStatus) < 0) {
      inner += '<button class="btn-outline mt16" data-act="dispute" data-o="' + esc(pg.id) + '">' + esc(t('open_dispute')) + '</button>';
    }
    if (!inner) return;
    box.innerHTML = inner;
    host.appendChild(box);
  }

  async function quoteApprove(oid) {
    try {
      await apiPost('/v1/orders/' + encodeURIComponent(oid) + '/shipping-quote/approve', {});
      toast('✔ ' + t('approve'));
      route();
    } catch (e) { toast(errMsg(e)); }
  }

  async function buyerPay(oid, amt) {
    const u = AUTH.currentUser;
    if (!u) { toast(t('need_auth')); return; }
    const phone = u.phoneNumber || '';
    parityModal(t('pay_now'), '<div class="form-card">'
      + '<div class="field"><label>' + esc(t('phone')) + '</label><input id="payPhone" value="' + esc(phone) + '" placeholder="+255 7xx xxx xxx"></div>'
      + '<p class="muted">' + esc(t('pay_total')) + ': <b>' + fmtTZS(amt) + '</b></p>'
      + '<div class="rowbtns"><button class="btn-accent" data-act="buyerpay2" data-o="' + esc(oid) + '" data-amt="' + amt + '">Lipa</button>'
      + '<button class="btn-outline" data-act="pmclose">' + esc(t('cancel')) + '</button></div></div>');
  }

  async function buyerPay2(oid, amt) {
    const phone = e164(document.getElementById('payPhone').value);
    if (!phone) { toast('Andika namba ya simu.'); return; }
    const btn = document.querySelector('[data-act="buyerpay2"]');
    if (btn) btn.disabled = true;
    try {
      const data = await apiPost('/v1/orders/' + encodeURIComponent(oid) + '/payments/initiate', {
        provider: 'clickpesa',
        amount: Math.round(amt),
        phoneNumber: phone,
      });
      closeParityModal();
      const ref = (data && data.data && (data.data.paymentLink || data.data.payUrl || data.data.link)) || '';
      if (ref) {
        window.open(ref, '_blank', 'noopener');
      }
      toast('✔ ' + t('pay_push_note') + ' — thibitisha kwenye simu yako.');
      startOrderPoll(oid);
    } catch (e) {
      toast(errMsg(e));
    } finally {
      if (btn) btn.disabled = false;
    }
  }

  let pollTimer2 = null;
  function startOrderPoll(oid) {
    clearInterval(pollTimer2);
    let tries = 0;
    pollTimer2 = setInterval(async () => {
      tries++;
      try {
        const pg = await apiGet('/v1/orders/' + encodeURIComponent(oid));
        const data = pg && pg.data ? pg.data : pg;
        const st = data && data.status;
        if (st && ['COMPLETED', 'WALLET_CREDITED', 'FAILED', 'CANCELLED'].indexOf(st) >= 0) {
          clearInterval(pollTimer2);
          toast('✔ ' + (st.indexOf('FAILED') >= 0 ? t('pay_failed') : t('pay_ok')));
          route();
          return;
        }
      } catch (_) {}
      if (tries > 60) { clearInterval(pollTimer2); }
    }, 4000);
  }

  async function buyerOtpConfirm(oid) {
    const otp = (document.getElementById('buyerOtp').value || '').trim();
    if (!/^\d{6}$/.test(otp)) { toast('OTP ina tarakimu 6.'); return; }
    const btn = document.querySelector('[data-act="buyerotp"]');
    if (btn) btn.disabled = true;
    try {
      await apiPost('/v1/orders/' + encodeURIComponent(oid) + '/complete', { otp: otp });
      toast('✔ ' + t('delivery_confirmed'));
      route();
    } catch (e) {
      toast(errMsg(e));
    } finally {
      if (btn) btn.disabled = false;
    }
  }

  async function openDispute(oid) {
    parityModal(t('open_dispute'), '<div class="form-card">'
      + '<div class="field"><label>' + esc(t('dispute_reason')) + '</label><select id="dpReason">'
      + '<option>' + esc(t('disp_not_received')) + '</option>'
      + '<option>' + esc(t('disp_wrong_item')) + '</option>'
      + '<option>' + esc(t('disp_damaged')) + '</option>'
      + '<option>' + esc(t('disp_other')) + '</option></select></div>'
      + '<div class="field"><label>' + esc(t('dispute_desc')) + '</label><textarea id="dpDesc" rows="3"></textarea></div>'
      + '<div class="rowbtns"><button class="btn-dark" data-act="dispute2" data-o="' + esc(oid) + '">' + esc(t('submit')) + '</button>'
      + '<button class="btn-outline" data-act="pmclose">' + esc(t('cancel')) + '</button></div></div>');
  }

  async function openDispute2(oid) {
    const reason = (document.getElementById('dpReason').value || '').trim();
    const description = (document.getElementById('dpDesc').value || '').trim();
    if (description.length < 5) { toast(t('dispute_desc')); return; }
    try {
      await apiPost('/v1/orders/' + encodeURIComponent(oid) + '/dispute', { reason: reason, description: description });
      closeParityModal();
      toast('✔ ' + t('dispute_filed'));
      route();
    } catch (e) { toast(errMsg(e)); }
  }

  /* ---------- Seller: wallet (v1 Postgres) ---------- */

  async function sellerWalletV1(user) {
    const body = document.getElementById('sellerBody');
    if (!body) return;
    body.innerHTML = '<div class="skel" style="height:200px"></div>';
    let wallet = null;
    try {
      const data = await apiGet('/v1/wallet');
      wallet = data && data.data ? data.data : null;
    } catch (_) { wallet = null; }
    if (!wallet) {
      body.innerHTML = emptyHtml(t('err_generic'), '', t('seller_wallet')) + '<p class="muted">' + esc(t('wallet_note')) + '</p>';
      return;
    }
    const bal = wallet.balances || {};
    const ledger = (wallet.ledger || []).slice(0, 30);
    const pages = wallet.pagination || {};
    body.innerHTML = '<div class="wallet-top">'
      + '<div class="wallet-card"><span>' + esc(t('seller_balance_lbl')) + '</span>'
      + '<b>' + fmtTZS(Number(bal.available) || 0) + '</b></div>'
      + '<div class="stat-row">'
      + '<div class="stat"><b>' + fmtTZS(Number(bal.pending) || 0) + '</b><span>' + esc(t('wallet_pending')) + '</span></div>'
      + '<div class="stat"><b>' + fmtTZS(Number(bal.frozen) || 0) + '</b><span>' + esc(t('wallet_frozen')) + '</span></div>'
      + '<div class="stat"><b>' + fmtTZS(Number(bal.totalEarned) || 0) + '</b><span>' + esc(t('wallet_earned')) + '</span></div>'
      + '<div class="stat"><b>' + fmtTZS(Number(bal.totalWithdrawn) || 0) + '</b><span>' + esc(t('withdrawn')) + '</span></div>'
      + '</div></div>'
      + '<div class="card-block"><h3>' + esc(t('withdraw')) + '</h3>'
      + '<form id="v1WdForm" class="wd-form"><div class="field"><label>' + esc(t('withdraw_amt')) + '</label>'
      + '<input id="v1WdAmt" type="number" min="1000" step="500"></div>'
      + '<div class="field"><label>' + esc(t('withdraw_phone')) + '</label>'
      + '<input id="v1WdPhone" value="' + esc((user.phoneNumber || wallet.wallet && user.phoneNumber || '')) + '" placeholder="+255 7xx xxx xxx"></div>'
      + '<button class="btn-accent" type="submit">' + esc(t('withdraw')) + '</button>'
      + '<p class="muted" style="font-size:12px;margin-top:10px">' + esc(t('min_withdraw') + ' 1000') + ' · ' + esc(t('wallet_note')) + '</p>'
      + '</form></div>'
      + '<div class="card-block"><h3>' + esc(t('wallet_history')) + '</h3>'
      + (ledger.length ? '<div class="ledger">' + ledger.map((l) => {
        const amt = Number(Number(l.amount) || 0);
        const cred = amt >= 0 || l.type === 'ORDER_SETTLEMENT';
        return '<div class="ledger-row"><div><span class="nm">' + esc(l.type || '') + '</span>'
          + '<div class="loc">' + esc(l.description || '') + '</div></div>'
          + '<b class="' + (cred ? 'pos' : 'neg') + '">' + (cred ? '+' : '') + fmtTZS(amt) + '</b></div>';
      }).join('') + '</div>' : '<p class="muted">' + esc(t('wallet_empty')) + '</p>')
      + '</div>';
    const form = document.getElementById('v1WdForm');
    if (form) form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const amount = Math.round(Number(document.getElementById('v1WdAmt').value) || 0);
      const phone = e164(document.getElementById('v1WdPhone').value);
      if (amount < 1000) { toast(t('min_withdraw')); return; }
      if (amount > (Number(bal.available) || 0)) { toast('Kiasi kikubwa kuliko salio.'); return; }
      const btn2 = form.querySelector('button[type=submit]');
      if (btn2) btn2.disabled = true;
      try {
        await apiPost('/v1/wallet/withdrawals', { amount: amount, phoneNumber: phone || undefined });
        toast('✔ ' + t('withdraw_ok'));
        renderSellerPage('wallet');
      } catch (err) { toast(errMsg(err)); }
      finally { if (btn2) btn2.disabled = false; }
    });
  }

  /* ---------- Seller: KYC ---------- */

  async function sellerKycBody(body, user) {
    body.innerHTML = '<div class="skel" style="height:120px"></div>';
    let kyc = null;
    try {
      const data = await apiGet('/api/kyc/status/' + encodeURIComponent(user.uid));
      kyc = data && data.kyc;
    } catch (_) {}
    const st = kyc && kyc.status;
    const badge = st === 'approved' ? '<span class="pill done">' + esc(t('kyc_approved')) + '</span>'
      : st ? '<span class="pill wait">' + esc(st) + '</span>' : '';
    body.innerHTML = '<h3>' + esc(t('kyc')) + '</h3>' + badge
      + '<div class="card-block" id="kycCard">' + (st === 'approved'
          ? '<p class="good">' + esc(t('kyc_done')) + '</p>'
          : kycFormHtml(kyc)) + '</div>';
    wireKycForm(user);
  }

  function kycFormHtml(kyc) {
    const ids = ['National ID', 'Passport', 'Drivers License', 'Voters ID'];
    const idOpts = ids.map((x) => '<option value="' + x + '"' + (kyc && kyc.idType === x ? ' selected' : '') + '>' + x + '</option>').join('');
    return '<div class="field"><label>' + esc(t('kyc_full_name')) + '</label><input id="kycName" value="' + esc((kyc && kyc.fullName) || '') + '" placeholder="Majina mawili"></div>'
      + '<div class="field"><label>' + esc(t('kyc_id_type')) + '</label><select id="kycType">' + idOpts + '</select></div>'
      + '<div class="field"><label>' + esc(t('kyc_id_number')) + '</label><input id="kycId" value="' + esc((kyc && kyc.idNumber) || '') + '"></div>'
      + '<button class="btn-outline btn-block mt16" data-act="kycpic" data-kind="id">' + esc(t('kyc_upload_id')) + '</button>'
      + '<p class="muted" style="font-size:11px" id="kycIdUrl">' + esc((kyc && kyc.idImageUrl) || '') + '</p>'
      + '<button class="btn-outline btn-block mt16" data-act="kycpic" data-kind="selfie">' + esc(t('kyc_upload_selfie')) + '</button>'
      + '<p class="muted" style="font-size:11px" id="kycSelfieUrl">' + esc((kyc && kyc.selfieUrl) || '') + '</p>'
      + '<button class="btn-dark btn-block mt16" data-act="kycsubmit">' + esc(t('submit')) + '</button>'
      + (kyc && kyc.reviewNotes ? '<p class="muted" style="font-size:12px;margin-top:8px">' + esc(kyc.reviewNotes) + '</p>' : '');
  }

  function wireKycForm(user) {
    const idUrl = document.getElementById('kycIdUrl');
    const selfieUrl = document.getElementById('kycSelfieUrl');
    if (!window.__kycUpload) window.__kycUpload = { id: '', selfie: '' };
    window.__kycUpload.id = '';
    window.__kycUpload.selfie = '';
    if (idUrl) idUrl.textContent = '';
    if (selfieUrl) selfieUrl.textContent = '';
  }

  async function kycUpload(kind) {
    const u = AUTH.currentUser;
    if (!u) return;
    const file = pickImageFile();
    if (!file) return;
    const btn = document.querySelector('[data-act="kycpic"][data-kind="' + kind + '"]');
    if (btn) btn.disabled = true;
    try {
      const url = await uploadToCloudinary(file, 'soko_langu_kyc');
      if (!window.__kycUpload) window.__kycUpload = { id: '', selfie: '' };
      window.__kycUpload[kind] = url;
      const el = kind === 'id' ? document.getElementById('kycIdUrl') : document.getElementById('kycSelfieUrl');
      if (el) el.textContent = url;
      toast('✔ ' + t('upload_ok'));
    } catch (e) { toast(errMsg(e)); }
    finally { if (btn) btn.disabled = false; }
  }

  function pickImageFile() {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'image/*';
    input.style.display = 'none';
    document.body.appendChild(input);
    return new Promise((resolve) => {
      input.onchange = () => {
        const f = input.files && input.files[0];
        input.remove();
        resolve(f || null);
      };
      input.click();
    });
  }

  async function uploadToCloudinary(file, folder) {
    const u = AUTH.currentUser;
    if (!u) throw new Error(t('need_auth'));
    const idToken = await u.getIdToken();
    const signRes = await apiPost('/api/cloudinary/sign', { folder: folder || 'soko_langu' });
    const fd = new FormData();
    fd.append('file', file);
    fd.append('folder', folder || 'soko_langu');
    fd.append('timestamp', String(signRes.timestamp));
    fd.append('signature', signRes.signature);
    fd.append('api_key', signRes.apiKey);
    const up = await fetch('https://api.cloudinary.com/v1_1/' + signRes.cloudName + '/image/upload', { method: 'POST', body: fd });
    const data = await up.json();
    if (!up.ok || !data.secure_url) throw new Error(data.error && data.error.message || 'Upload imeshindikana');
    return data.secure_url;
  }

  async function kycSubmit() {
    const u = AUTH.currentUser;
    if (!u) return;
    const fullName = (document.getElementById('kycName').value || '').trim();
    const idType = (document.getElementById('kycType').value || '').trim();
    const idNumber = (document.getElementById('kycId').value || '').trim();
    const idImageUrl = (window.__kycUpload && window.__kycUpload.id) || '';
    const selfieUrl = (window.__kycUpload && window.__kycUpload.selfie) || '';
    const btn = document.querySelector('[data-act="kycsubmit"]');
    if (btn) btn.disabled = true;
    try {
      const data = await apiPost('/api/kyc/submit', { userId: u.uid, fullName: fullName, idType: idType, idNumber: idNumber, idImageUrl: idImageUrl, selfieUrl: selfieUrl });
      if (data && data.success === false) { toast(errMsg({ message: data.error || '' })); return; }
      toast('✔ ' + t('kyc_submitted'));
      renderSellerPage('kyc');
    } catch (e) { toast(errMsg(e)); }
    finally { if (btn) btn.disabled = false; }
  }

  /* ---------- Seller: boost ---------- */

  async function sellerBoostBody(body, user) {
    body.innerHTML = '<h3>' + esc(t('boost')) + '</h3><div class="skel" style="height:120px"></div>';
    let products = [];
    try {
      const snap = await DB.collection('products').where('sellerId', '==', user.uid).where('isActive', '==', true).limit(20).get();
      products = snap.docs.map(norm);
    } catch (_) {}
    if (!products.length) {
      body.innerHTML = emptyHtml(t('boost_need_product'), '', t('boost'));
      return;
    }
    const tiers = [
      { name: 'bronze', label: t('boost_bronze'), days: 3, price: 1500, tag: t('boost_bronze_tag') },
      { name: 'silver', label: t('boost_silver'), days: 7, price: 3000, tag: t('boost_silver_tag') },
      { name: 'gold', label: t('boost_gold'), days: 30, price: 10000, tag: t('boost_gold_tag') },
    ];
    body.innerHTML = '<h3>' + esc(t('boost')) + '</h3>'
      + '<div class="field"><label>' + esc(t('product')) + '</label><select id="bpProd">'
      + products.map((p) => '<option value="' + esc(p.id) + '">' + esc(p.name) + ' — ' + fmtTZS(p.price) + '</option>').join('')
      + '</select></div>'
      + '<div class="boost-tiers">' + tiers.map((ti) =>
        '<div class="boost-tier" data-tier="' + ti.name + '" data-days="' + ti.days + '" data-price="' + ti.price + '">'
        + '<div class="nm">' + esc(ti.label) + '</div>'
        + '<div class="pr">' + fmtTZS(ti.price) + '</div>'
        + '<div class="loc">' + esc(ti.tag) + ' · ' + ti.days + ' ' + esc(t('days')) + '</div>'
        + '</div>').join('') + '</div>'
      + '<div class="field"><label>' + esc(t('phone')) + '</label><input id="bpPhone" value="' + esc((user.phoneNumber || '')) + '" placeholder="+255 7xx xxx xxx"></div>'
      + '<div class="rowbtns"><button class="btn-accent" data-act="bpgo">' + esc(t('boost_pay')) + '</button>'
      + '<a class="btn-outline" href="#/seller?t=overview">' + esc(t('back')) + '</a></div>'
      + '<div id="bpMsg"></div>';
    $all('.boost-tier').forEach((el) => {
      el.addEventListener('click', () => {
        $all('.boost-tier').forEach((x) => x.classList.remove('on'));
        el.classList.add('on');
      });
    });
    const first = $('.boost-tier');
    if (first) { first.classList.add('on'); window.__bpTier = { name: 'bronze', days: 3, price: 1500 }; }
  }

  async function boostGo() {
    const u = AUTH.currentUser;
    if (!u) return;
    const pid = document.getElementById('bpProd').value;
    const active = $('.boost-tier.on');
    if (!active) { toast('Chagua tier.'); return; }
    const tier = active.dataset.tier;
    const price = Number(active.dataset.price) || 0;
    const days = Number(active.dataset.days) || 3;
    const phone = e164(document.getElementById('bpPhone').value);
    if (!phone) { toast('Andika namba ya simu.'); return; }
    let p = null;
    try { p = await getProduct(pid); } catch (_) {}
    const btn = document.querySelector('[data-act="bpgo"]');
    if (btn) btn.disabled = true;
    try {
      const data = await apiPost('/api/boost-product', {
        productId: pid,
        tier: tier,
        amount: price,
        durationDays: days,
        phone: phone,
        userId: u.uid,
        productName: p ? p.name : '',
        productImage: p && p.images && p.images[0] ? p.images[0] : '',
        productPrice: p ? p.price : 0,
        paymentMethod: 'ussd_push',
      });
      const msgEl = document.getElementById('bpMsg');
      if (msgEl) msgEl.innerHTML = '<div class="search-note">' + esc(data.message || '') + '</div>';
      toast('✔ ' + t('pay_push_note'));
      if (data.order_id) boostPoll(data.order_id);
    } catch (e) { toast(errMsg(e)); }
    finally { if (btn) btn.disabled = false; }
  }

  function boostPoll(orderId) {
    let tries = 0;
    const t2 = setInterval(() => {
      tries++;
      DB.collection('transactions').doc(orderId).get()
        .then((s) => {
          if (!s.exists) return;
          const st = s.data().status || '';
          if (st === 'completed') {
            clearInterval(t2);
            toast('✔ ' + t('boost_done'));
            route();
          } else if (st === 'failed' || tries > 40) {
            clearInterval(t2);
            if (st === 'failed') toast(t('boost_failed'));
          }
        })
        .catch(() => {});
    }, 4000);
  }

  /* ---------- Seller: analytics ---------- */

  async function sellerAnalyticsBody(body, user) {
    body.innerHTML = '<h3>' + esc(t('analytics')) + '</h3><div id="anGrid" class="stat-grid"></div>'
      + '<div id="anChart" class="card-block"><h3>' + esc(t('sales_30d')) + '</h3><div id="anBars" class="an-bars"><div class="skel" style="height:120px"></div></div></div>';
    let ords = [];
    try {
      const snap = await DB.collection('orders').where('sellerId', '==', user.uid).limit(400).get();
      ords = snap.docs.map((d) => d.data());
    } catch (_) {}
    const done = ords.filter((o) => PAY_STATES.has(o.status || ''));
    const gross = done.reduce((s, o) => s + (Number(o.totalAmount) || 0), 0);
    const grid = document.getElementById('anGrid');
    if (grid) {
      grid.innerHTML = '<div class="stat"><b>' + ords.length + '</b><span>' + esc(t('stats_orders')) + '</span></div>'
        + '<div class="stat"><b>' + done.length + '</b><span>' + esc(t('stats_completed')) + '</span></div>'
        + '<div class="stat"><b>' + fmtTZS(gross) + '</b><span>' + esc(t('stats_gmv')) + '</span></div>'
        + '<div class="stat"><b>' + fmtTZS(done.length ? Math.round(gross / done.length) : 0) + '</b><span>' + esc(t('avg_order')) + '</span></div>';
    }
    const last30 = done.filter((o) => tsMillis(o.updatedAt || o.createdAt) >= Date.now() - 30 * 86400000);
    const buckets = [];
    for (let i = 0; i < 7; i++) {
      const start = new Date(Date.now() - i * 86400000);
      start.setHours(0, 0, 0, 0);
      const end = new Date(start.getTime() + 86400000);
      const sum = last30.filter((o) => { const t = new Date(tsMillis(o.updatedAt || o.createdAt)); return t >= start && t < end; })
        .reduce((s, o) => s + (Number(o.totalAmount) || 0), 0);
      buckets.unshift({ label: start.toLocaleDateString(lang === 'sw' ? 'sw-TZ' : 'en', { weekday: 'short' }), sum: sum });
    }
    const max = Math.max.apply(null, buckets.map((b) => b.sum).concat([1]));
    const bars = document.getElementById('anBars');
    if (bars) {
      bars.innerHTML = '<div class="an-bars">' + buckets.map((b) =>
        '<div class="an-col"><i style="height:' + Math.max(4, Math.round((b.sum / max) * 120)) + 'px"></i><span>' + esc(b.label) + '</span><b>' + fmtTZS(b.sum) + '</b></div>').join('') + '</div>';
    }
  }

  /* ---------- Actions ---------- */

  window.__PARITY_ACTIONS = {
    googlelogin: () => googleSignIn(),
    phonelogin: () => renderPhoneSignin(),
    phnext: () => phoneOtpStep1(),
    phverify: () => phoneOtpStep2(),
    phback: () => renderAuthForm('signin'),
    trendchip: (el) => searchSubmit(el.dataset.q || '', ''),
    follow: (el) => toggleFollow(el, decodeURIComponent(el.dataset.following || el.dataset.s || '')),
    addcomment: (el) => sendComment(decodeURIComponent(el.dataset.p || '')),
    addreply: (el) => sendReply(decodeURIComponent(el.dataset.p || ''), decodeURIComponent(el.dataset.c || ''), el),
    togglereplies: (el) => toggleReplies(decodeURIComponent(el.dataset.p || ''), decodeURIComponent(el.dataset.c || ''), el),
    delcomment: (el) => deleteComment(decodeURIComponent(el.dataset.p || ''), decodeURIComponent(el.dataset.c || '')),
    delreply: (el) => deleteReply(decodeURIComponent(el.dataset.p || ''), decodeURIComponent(el.dataset.c || ''), decodeURIComponent(el.dataset.r || '')),
    notifreadall: () => notifMarkAllRead(),
    notifdel: (el) => notifDelete(decodeURIComponent(el.dataset.n || '')),
    prefssave: () => savePrefs(),
    fscreate: () => fsCreateForm(),
    fscreate2: () => fsCreate2(),
    fscancel: () => closeParityModal(),
    fsdel: (el) => fsDelete(decodeURIComponent(el.dataset.f || '')),
    squote: (el) => sellerQuote(decodeURIComponent(el.dataset.o || '')),
    squote2: (el) => sellerQuote2(decodeURIComponent(el.dataset.o || '')),
    sdispatch: (el) => sellerDispatch(decodeURIComponent(el.dataset.o || '')),
    sdispatch2: (el) => sellerDispatch2(decodeURIComponent(el.dataset.o || '')),
    sotp: (el) => sellerOtp(decodeURIComponent(el.dataset.o || '')),
    scancel: async (el) => {
      const oid = decodeURIComponent(el.dataset.o || '');
      const reason = window.prompt(t('cancel_reason') + ':');
      if (!reason) return;
      try { await apiPost('/v1/orders/' + encodeURIComponent(oid) + '/cancel', { reason: reason }); toast('✔ ' + t('cancelled')); renderSellerPage('orders'); }
      catch (e) { toast(errMsg(e)); }
    },
    quoteapp: (el) => quoteApprove(decodeURIComponent(el.dataset.o || '')),
    quoterej: (el) => {
      toast(t('rejected'));
      route();
    },
    buyerpay: (el) => buyerPay(decodeURIComponent(el.dataset.o || ''), Number(el.dataset.amt) || 0),
    buyerpay2: (el) => buyerPay2(decodeURIComponent(el.dataset.o || ''), Number(el.dataset.amt) || 0),
    buyerotp: (el) => buyerOtpConfirm(decodeURIComponent(el.dataset.o || '')),
    dispute: (el) => openDispute(decodeURIComponent(el.dataset.o || '')),
    dispute2: (el) => openDispute2(decodeURIComponent(el.dataset.o || '')),
    kycpic: (el) => kycUpload(el.dataset.kind || 'id'),
    kycsubmit: () => kycSubmit(),
    bpgo: () => boostGo(),
    sugg: (el) => { if (el.dataset.q) { document.getElementById('searchInput').value = el.dataset.q; searchSubmit(el.dataset.q, document.getElementById('catSelect').value); } },
    histclear: () => clearSearchHist(),
    pmclose: () => closeParityModal(),
    notiftap: (el) => notifTap(decodeURIComponent(el.dataset.n || '')),
  };

  /* ---------- Parity page renderers (called from app.js) ---------- */

  window.paritySearch = paritySearch;
  window.parityProductExtras = parityProductExtras;
  window.renderNotifications = renderNotifications;
  window.renderNotifyPrefs = renderNotifPrefs;
  window.renderChatInbox = renderChatInbox;
  window.renderChatRoom = renderChatRoom;
  window.renderFlashSale = renderFlashSale;
  window.parityBuyerOrderArea = parityBuyerOrderArea;
  window.sellerOrderActionsHtml = sellerOrderActionsHtml;
  window.sellerWalletV1 = sellerWalletV1;
  window.sellerKycBody = sellerKycBody;
  window.sellerBoostBody = sellerBoostBody;
  window.sellerFlashBody = sellerFlashBody;
  window.sellerAnalyticsBody = sellerAnalyticsBody;
  window.authAltButtons = authAltButtons;
  window.renderPhoneSignin = renderPhoneSignin;
  window.enhanceSuggest = enhanceSuggest;
  window.afterSignIn = afterSignIn;
  window.notifBadge = notifBadge;
  window.notifPoll = notifPoll;
  window.recordRecent = recordRecent;
  window.renderSearchHist = renderSearchHist;

  window.addEventListener('DOMContentLoaded', () => {
    if (AUTH) AUTH.onAuthStateChanged(() => { notifPoll(true); });
  });
})();