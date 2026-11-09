/* Soko Vibe website behaviour.
 *
 * Progressive enhancement only: every page is readable and every form has a
 * server fallback. This file adds the language switch, mobile navigation,
 * accordions and fetch-based form submission with inline validation.
 */
(function () {
  'use strict';

  var STORAGE_KEY = 'sv_lang';
  var PAGE_STARTED = Date.now();
  var originalContent = new WeakMap();
  var originalAttrs = new WeakMap();
  var currentLang = 'sw';

  var MESSAGES = {
    sw: {
      email: 'Barua pepe si sahihi. Angalia jina@mfano.com.',
      name: 'Tafadhali weka jina lako.',
      consent: 'Tafadhali kubali kupokea taarifa ili kuendelea.',
      message: 'Ujumbe unahitaji herufi 20 au zaidi.',
      subject: 'Tafadhali chagua mada.',
      sending: 'Inatuma…',
      subscribed: 'Umejiunga! Tunakutumia taarifa tutakapozindua.',
      duplicate: 'Tayari uko kwenye orodha. Asante!',
      contactSent: 'Asante. Ujumbe wako umepokelewa; tutajibu ndani ya siku mbili za kazi.',
      deleted: 'Ombi lako limepokelewa. Tutathibitisha kwa barua pepe na kukamilisha ndani ya siku 14 za kazi.',
      rate: 'Maombi ni mengi kwa muda mfupi. Tafadhali subiri dakika chache.',
      network: 'Tatizo la mtandao. Angalia muunganisho na ujaribu tena.',
      generic: 'Jambo lilienda kombo. Tafadhali jaribu tena.',
      unsubConfirm: 'Bonyeza kitufe kuthibitisha kujiondoa kwenye orodha.',
      unsubDone: 'Umeondolewa kwenye orodha. Asante kwa muda wako.',
      unsubInvalid: 'Kiungo hiki si sahihi au kimekwisha tumika.',
      copied: 'Kiungo kimekopwa.',
    },
    en: {
      email: 'That email address is not valid. Check the name@example.com format.',
      name: 'Please enter your name.',
      consent: 'Please agree to receive updates to continue.',
      message: 'Your message needs at least 20 characters.',
      subject: 'Please choose a subject.',
      sending: 'Sending…',
      subscribed: 'You are on the list. We will email you when we launch.',
      duplicate: 'You are already on the list. Thank you!',
      contactSent: 'Thank you. Your message has been received; we will reply within two working days.',
      deleted: 'Your request has been received. We will confirm by email and complete it within 14 working days.',
      rate: 'Too many requests in a short time. Please wait a few minutes.',
      network: 'Network problem. Check your connection and try again.',
      generic: 'Something went wrong. Please try again.',
      unsubConfirm: 'Press the button to confirm you want to unsubscribe.',
      unsubDone: 'You have been removed from the list. Thank you for your time.',
      unsubInvalid: 'This link is invalid or has already been used.',
      copied: 'Link copied.',
    },
  };

  function m(key) {
    return (MESSAGES[currentLang] || MESSAGES.sw)[key] || MESSAGES.sw[key];
  }

  function htmlLang(lang) {
    document.documentElement.lang = lang === 'en' ? 'en' : 'sw';
    document.documentElement.setAttribute('data-lang', lang);
  }

  /* ---------- Language ---------- */

  function applyLang(lang, options) {
    var opts = options || {};
    currentLang = lang === 'en' ? 'en' : 'sw';
    var isEn = currentLang === 'en';

    document.querySelectorAll('[data-en]').forEach(function (el) {
      if (!originalContent.has(el)) originalContent.set(el, el.innerHTML);
      var value = el.getAttribute('data-en');
      el.innerHTML = isEn ? value : originalContent.get(el);
    });

    document.querySelectorAll('[data-en-html]').forEach(function (el) {
      if (!originalContent.has(el)) originalContent.set(el, el.innerHTML);
      var value = el.getAttribute('data-en-html');
      el.innerHTML = isEn ? value : originalContent.get(el);
    });

    document.querySelectorAll('[data-en-placeholder]').forEach(function (el) {
      if (!originalAttrs.has(el)) originalAttrs.set(el, el.getAttribute('placeholder'));
      el.setAttribute('placeholder', isEn ? el.getAttribute('data-en-placeholder') : (originalAttrs.get(el) || ''));
    });

    document.querySelectorAll('[data-en-aria-label]').forEach(function (el) {
      if (!originalAttrs.has(el)) originalAttrs.set(el, el.getAttribute('aria-label'));
      el.setAttribute('aria-label', isEn ? el.getAttribute('data-en-aria-label') : (originalAttrs.get(el) || ''));
    });

    document.querySelectorAll('[data-en-title]').forEach(function (el) {
      if (!originalAttrs.has(el)) originalAttrs.set(el, el.getAttribute('title'));
      el.setAttribute('title', isEn ? el.getAttribute('data-en-title') : (originalAttrs.get(el) || ''));
    });

    document.querySelectorAll('[data-lang-switch]').forEach(function (btn) {
      var active = btn.getAttribute('data-lang-switch') === currentLang;
      btn.classList.toggle('is-active', active);
      btn.setAttribute('aria-pressed', active ? 'true' : 'false');
    });

    htmlLang(currentLang);

    if (opts.persist !== false) {
      try { localStorage.setItem(STORAGE_KEY, currentLang); } catch (e) { /* storage may be blocked */ }
    }

    if (opts.updateUrl !== false && window.history && window.history.replaceState) {
      try {
        var url = new URL(window.location.href);
        if (currentLang === 'en') url.searchParams.set('lang', 'en');
        else url.searchParams.delete('lang');
        window.history.replaceState(null, '', url.pathname + (url.search ? url.search : '') + url.hash);
      } catch (e) { /* malformed URL, leave it alone */ }
    }
  }

  function initLanguage() {
    var params;
    try { params = new URLSearchParams(window.location.search); } catch (e) { params = null; }
    var fromUrl = params ? params.get('lang') : null;
    var stored = null;
    try { stored = localStorage.getItem(STORAGE_KEY); } catch (e) { stored = null; }
    var initial = fromUrl === 'en' || fromUrl === 'sw' ? fromUrl : (stored === 'en' ? 'en' : 'sw');
    applyLang(initial, { persist: false, updateUrl: false });

    document.querySelectorAll('[data-lang-switch]').forEach(function (btn) {
      btn.addEventListener('click', function () {
        applyLang(btn.getAttribute('data-lang-switch'));
      });
    });
  }

  /* ---------- Mobile navigation ---------- */

  function initNav() {
    var burger = document.querySelector('[data-burger]');
    var panel = document.getElementById('sv-mobile');
    if (!burger || !panel) return;

    function setOpen(open) {
      burger.setAttribute('aria-expanded', open ? 'true' : 'false');
      panel.hidden = !open;
      burger.setAttribute('aria-label', open
        ? (currentLang === 'en' ? 'Close menu' : 'Funga menyu')
        : (currentLang === 'en' ? 'Open menu' : 'Fungua menyu'));
    }

    burger.addEventListener('click', function () {
      setOpen(burger.getAttribute('aria-expanded') !== 'true');
    });

    panel.querySelectorAll('a').forEach(function (link) {
      link.addEventListener('click', function () { setOpen(false); });
    });

    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape' && burger.getAttribute('aria-expanded') === 'true') {
        setOpen(false);
        burger.focus();
      }
    });

    window.addEventListener('resize', function () {
      if (window.innerWidth > 1000) setOpen(false);
    });
  }

  /* ---------- Accordions ---------- */

  function initAccordions() {
    document.querySelectorAll('[data-accordion]').forEach(function (group) {
      group.querySelectorAll('.sv-acc__trigger').forEach(function (trigger) {
        trigger.addEventListener('click', function () {
          var open = trigger.getAttribute('aria-expanded') === 'true';
          var panel = document.getElementById(trigger.getAttribute('aria-controls'));
          trigger.setAttribute('aria-expanded', open ? 'false' : 'true');
          if (panel) panel.hidden = open;
        });
      });
    });
  }

  /* ---------- Toast ---------- */

  var toastTimer = null;
  function toast(message, kind) {
    var el = document.querySelector('[data-toast]');
    if (!el) return;
    el.textContent = message;
    el.classList.remove('is-error', 'is-success');
    if (kind) el.classList.add('is-' + kind);
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.hidden = true; }, 7000);
  }

  /* ---------- Fetch helpers ---------- */

  function postJson(url, payload) {
    return fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify(payload),
      credentials: 'same-origin',
    }).then(function (response) {
      return response.json().catch(function () { return {}; }).then(function (data) {
        return { ok: response.ok, status: response.status, data: data };
      });
    });
  }

  function setStatus(form, message, kind) {
    var status = form.querySelector('[data-form-status]');
    if (!status) return;
    status.textContent = message || '';
    status.classList.remove('is-error', 'is-success', 'is-loading');
    if (kind) status.classList.add('is-' + kind);
  }

  function markInvalid(field, invalid) {
    if (!field) return;
    if (invalid) field.setAttribute('aria-invalid', 'true');
    else field.removeAttribute('aria-invalid');
  }

  function setBusy(form, busy) {
    var button = form.querySelector('[type="submit"]');
    if (!button) return;
    if (busy) {
      button.setAttribute('aria-busy', 'true');
      button.dataset.originalLabel = button.querySelector('[data-en]') ? '' : button.textContent;
    } else {
      button.removeAttribute('aria-busy');
    }
  }

  function stampForms() {
    document.querySelectorAll('[data-started]').forEach(function (input) {
      input.value = String(PAGE_STARTED);
    });
  }

  function emailValid(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(String(value || '').trim());
  }

  function langValue() {
    return currentLang === 'en' ? 'en' : 'sw';
  }

  /* ---------- Waitlist ---------- */

  function initWaitlist() {
    document.querySelectorAll('[data-waitlist]').forEach(function (form) {
      form.addEventListener('submit', function (event) {
        event.preventDefault();
        var email = form.querySelector('[name="email"]');
        var consent = form.querySelector('[name="consent"]');
        var type = form.querySelector('[name="userType"]:checked');
        var honeypot = form.querySelector('[name="website"]');
        var started = form.querySelector('[name="formStartedAt"]');
        var value = String(email && email.value || '').trim();

        markInvalid(email, false);
        setStatus(form, '', null);

        if (!emailValid(value)) {
          markInvalid(email, true);
          setStatus(form, m('email'), 'error');
          if (email) email.focus();
          return;
        }
        if (consent && !consent.checked) {
          setStatus(form, m('consent'), 'error');
          consent.focus();
          return;
        }
        if (started) started.value = String(PAGE_STARTED);

        setBusy(form, true);
        setStatus(form, m('sending'), 'loading');

        postJson('/api/v1/launch/subscribe', {
          email: value,
          userType: type ? type.value : 'both',
          preferredLanguage: langValue(),
          consent: Boolean(consent && consent.checked),
          consentVersion: '2026-11',
          source: (form.querySelector('[name="source"]') || {}).value || 'website',
          website: honeypot ? honeypot.value : '',
          formStartedAt: PAGE_STARTED,
        }).then(function (res) {
          if (res.ok && res.data && res.data.success) {
            var status = res.data.data && res.data.data.status;
            if (status === 'duplicate') {
              setStatus(form, m('duplicate'), 'success');
              toast(m('duplicate'), 'success');
              setBusy(form, false);
              return;
            }
            setStatus(form, m('subscribed'), 'success');
            window.location.href = '/waitlist/success';
            return;
          }
          if (res.status === 429) throw new Error('rate');
          var detail = res.data && (res.data.message || res.data.error);
          throw new Error(detail || 'generic');
        }).catch(function (error) {
          setBusy(form, false);
          var key = error && error.message === 'rate' ? 'rate' : 'generic';
          if (error && error.name === 'TypeError') key = 'network';
          setStatus(form, m(key), 'error');
        });
      });
    });
  }

  /* ---------- Contact ---------- */

  function initContact() {
    document.querySelectorAll('[data-contact]').forEach(function (form) {
      var message = form.querySelector('[name="message"]');
      var counter = form.querySelector('[data-message-count]');
      if (message && counter) {
        var update = function () { counter.textContent = String(message.value.length); };
        message.addEventListener('input', update);
        update();
      }

      form.addEventListener('submit', function (event) {
        event.preventDefault();
        var name = form.querySelector('[name="name"]');
        var email = form.querySelector('[name="email"]');
        var subject = form.querySelector('[name="subject"]');
        var consent = form.querySelector('[name="consent"]');
        var honeypot = form.querySelector('[name="website"]');
        var started = form.querySelector('[name="formStartedAt"]');

        [name, email, subject, message].forEach(function (field) { markInvalid(field, false); });
        setStatus(form, '', null);

        if (!name || !name.value.trim()) {
          markInvalid(name, true);
          setStatus(form, m('name'), 'error');
          if (name) name.focus();
          return;
        }
        if (!emailValid(email && email.value)) {
          markInvalid(email, true);
          setStatus(form, m('email'), 'error');
          if (email) email.focus();
          return;
        }
        if (!subject || !subject.value) {
          markInvalid(subject, true);
          setStatus(form, m('subject'), 'error');
          if (subject) subject.focus();
          return;
        }
        if (!message || message.value.trim().length < 20) {
          markInvalid(message, true);
          setStatus(form, m('message'), 'error');
          if (message) message.focus();
          return;
        }
        if (consent && !consent.checked) {
          setStatus(form, m('consent'), 'error');
          consent.focus();
          return;
        }
        if (started) started.value = String(PAGE_STARTED);

        setBusy(form, true);
        setStatus(form, m('sending'), 'loading');

        postJson('/api/v1/contact', {
          name: name.value.trim(),
          email: email.value.trim(),
          subject: subject.value,
          message: message.value.trim(),
          consent: Boolean(consent && consent.checked),
          preferredLanguage: langValue(),
          website: honeypot ? honeypot.value : '',
          formStartedAt: PAGE_STARTED,
        }).then(function (res) {
          if (res.ok && res.data && res.data.success) {
            form.reset();
            if (counter) counter.textContent = '0';
            setStatus(form, m('contactSent'), 'success');
            toast(m('contactSent'), 'success');
            setBusy(form, false);
            return;
          }
          if (res.status === 429) throw new Error('rate');
          throw new Error('generic');
        }).catch(function (error) {
          setBusy(form, false);
          var key = error && error.message === 'rate' ? 'rate' : 'generic';
          if (error && error.name === 'TypeError') key = 'network';
          setStatus(form, m(key), 'error');
        });
      });
    });
  }

  /* ---------- Data deletion ---------- */

  function initDeletion() {
    document.querySelectorAll('[data-deletion]').forEach(function (form) {
      form.addEventListener('submit', function (event) {
        event.preventDefault();
        var email = form.querySelector('[name="email"]');
        var honeypot = form.querySelector('[name="website"]');
        markInvalid(email, false);
        setStatus(form, '', null);

        if (!emailValid(email && email.value)) {
          markInvalid(email, true);
          setStatus(form, m('email'), 'error');
          if (email) email.focus();
          return;
        }

        setBusy(form, true);
        setStatus(form, m('sending'), 'loading');

        var payload = {
          email: email.value.trim(),
          website: honeypot ? honeypot.value : '',
        };
        var fullName = form.querySelector('[name="fullName"]');
        var phone = form.querySelector('[name="phone"]');
        var reason = form.querySelector('[name="reason"]');
        if (fullName && fullName.value.trim()) payload.fullName = fullName.value.trim();
        if (phone && phone.value.trim()) payload.phone = phone.value.trim();
        if (reason && reason.value.trim()) payload.reason = reason.value.trim();

        postJson('/api/v1/data-deletion/requests', payload).then(function (res) {
          if (res.ok && res.data && res.data.success) {
            var holder = form.closest('.sv-doc__form') || form.parentNode;
            form.hidden = true;
            var message = document.createElement('p');
            message.className = 'sv-status is-success';
            message.setAttribute('role', 'status');
            message.textContent = m('deleted');
            holder.appendChild(message);
            toast(m('deleted'), 'success');
            setBusy(form, false);
            return;
          }
          if (res.status === 429) throw new Error('rate');
          throw new Error('generic');
        }).catch(function (error) {
          setBusy(form, false);
          var key = error && error.message === 'rate' ? 'rate' : 'generic';
          if (error && error.name === 'TypeError') key = 'network';
          setStatus(form, m(key), 'error');
        });
      });
    });
  }

  /* ---------- Unsubscribe ---------- */

  function initUnsubscribe() {
    var root = document.querySelector('[data-unsub]');
    if (!root) return;
    var params;
    try { params = new URLSearchParams(window.location.search); } catch (e) { params = null; }
    var token = params ? params.get('token') : null;
    var status = root.querySelector('[data-unsub-status]');
    var actions = root.querySelector('[data-unsub-actions]');
    var fallback = root.querySelector('[data-unsub-fallback]');
    var confirmButton = root.querySelector('[data-unsub-confirm]');

    function say(message, kind) {
      if (!status) return;
      status.textContent = message;
      status.classList.remove('is-error', 'is-success');
      if (kind) status.classList.add('is-' + kind);
    }

    if (!token || token.length < 16) {
      if (fallback) fallback.hidden = false;
      say(m('unsubInvalid'), 'error');
      return;
    }

    if (actions) actions.hidden = false;
    say(m('unsubConfirm'), null);

    if (confirmButton) {
      confirmButton.addEventListener('click', function () {
        confirmButton.setAttribute('aria-busy', 'true');
        postJson('/api/v1/launch/unsubscribe', { token: token }).then(function (res) {
          if (res.ok && res.data && res.data.success) {
            if (actions) actions.hidden = true;
            say(m('unsubDone'), 'success');
            toast(m('unsubDone'), 'success');
            return;
          }
          throw new Error('invalid');
        }).catch(function () {
          if (actions) actions.hidden = true;
          if (fallback) fallback.hidden = false;
          say(m('unsubInvalid'), 'error');
        }).then(function () {
          confirmButton.removeAttribute('aria-busy');
        });
      });
    }
  }

  /* ---------- Reveal on scroll ---------- */

  function initReveal() {
    var items = document.querySelectorAll('[data-reveal]');
    if (!items.length) return;
    if (!('IntersectionObserver' in window)) {
      items.forEach(function (el) { el.classList.add('is-visible'); });
      return;
    }
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    items.forEach(function (el) { observer.observe(el); });
  }

  function initYear() {
    var year = String(new Date().getFullYear());
    document.querySelectorAll('[data-year]').forEach(function (el) { el.textContent = year; });
  }

  function init() {
    document.documentElement.classList.add('js');
    initLanguage();
    initNav();
    initAccordions();
    stampForms();
    initWaitlist();
    initContact();
    initDeletion();
    initUnsubscribe();
    initReveal();
    initYear();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
