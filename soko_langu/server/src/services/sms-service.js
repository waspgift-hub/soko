// SMS dispatch behind a provider interface.
//
// Auth logic must never couple to one SMS vendor (spec: provider-independent
// SMS abstraction). Every vendor implements the tiny SmsProvider surface:
//
//   { name, available(), send({ to, message }) }
//
// `sendSms` walks the configured providers in order and returns true on the
// first delivery. Switching vendors (or reordering) is an env change
// (SMS_PROVIDER_ORDER), not a code change. Higher-level helpers — sendOtp /
// sendSecurityNotification — own message wording so callers never format SMS
// inline and user-facing copy stays in one place.
const axios = require('axios');
const config = require('../config');
const { createBreaker } = require('../utils/circuit-breaker');
const { maskPhone } = require('../utils/pii');

// Per-provider breakers: a down SMS provider fails fast instead of holding the
// request for 15s×2 timeouts on every OTP send.
const mesejiBreaker = createBreaker('sms-meseji', { failureThreshold: 3 });
const notifyBreaker = createBreaker('sms-notify-africa', { failureThreshold: 3 });

// Concurrency cap for SMS egress: SMS gateways throttle (and bill) bursts, so
// during a 1000-user OTP day the requests queue here instead of stacking up at
// the provider. The cap only limits HOW MANY are in flight, not throughput.
const MAX_CONCURRENT_SMS = parseInt(process.env.SMS_MAX_CONCURRENT || '20', 10);
let smsActive = 0;
let smsWaiters = [];

function acquireSmsSlot() {
  if (smsActive < MAX_CONCURRENT_SMS) {
    smsActive += 1;
    return Promise.resolve();
  }
  return new Promise((resolve) => smsWaiters.push(resolve));
}

function releaseSmsSlot() {
  const next = smsWaiters.shift();
  if (next) next();
  else smsActive -= 1;
}

function toLocal(phone) {
  const digits = String(phone).replace(/\D/g, '');
  if (digits.startsWith('255')) return '0' + digits.slice(3);
  if (!digits.startsWith('0')) return '0' + digits;
  return digits;
}

function toInternational(phone) {
  const d = String(phone).replace(/\D/g, '');
  return d.startsWith('0') ? '255' + d.slice(1) : d;
}

// Ported from the legacy server (verified live): Meseji wants `contacts`
// as a single local-format STRING, not an array.
const MesejiProvider = {
  name: 'meseji',
  available() {
    return Boolean(config.sms.mesejiApiKey);
  },
  async send({ to, message }) {
    const apiKey = config.sms.mesejiApiKey;
    if (!apiKey) return false;
    const local = toLocal(to);
    const configured = config.sms.mesejiSenderId || 'MESEJI';
    const senders = configured === 'MESEJI' ? ['MESEJI'] : [configured, 'MESEJI'];
    for (const sender of senders) {
      try {
        const resp = await mesejiBreaker.call(
          () => axios.post(config.sms.mesejiBaseUrl, {
            sender_id: sender,
            message,
            contacts: local,
          }, {
            headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
            timeout: 15000,
          }),
          () => null,
        );
        if (!resp) return false; // breaker OPEN — skip straight to the other sender
        console.log(`[SMS] meseji ok sender=${sender} to=${maskPhone(local)} batch=${resp.data?.batch_id || ''}`);
        return true;
      } catch (e) {
        const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
        console.error(`[SMS] meseji sender ${sender} error: ${errBody}`);
      }
    }
    return false;
  },
};

const NotifyAfricaProvider = {
  name: 'notify-africa',
  available() {
    const apiKey = process.env.NOTIFY_AFRICA_SMS_API_KEY || config.sms.notifyAfricaApiKey;
    return Boolean(apiKey && process.env.NOTIFY_AFRICA_SENDER_ID);
  },
  async send({ to, message }) {
    const apiKey = process.env.NOTIFY_AFRICA_SMS_API_KEY || config.sms.notifyAfricaApiKey;
    const senderId = process.env.NOTIFY_AFRICA_SENDER_ID;
    if (!apiKey || !senderId) return false;
    try {
      const resp = await notifyBreaker.call(
        () => axios.post(`${config.sms.notifyAfricaBaseUrl}/api/v1/api/messages/send`, {
          phone_number: toInternational(to),
          message,
          sender_id: senderId,
        }, {
          headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
          timeout: 15000,
        }),
        () => null,
      );
      if (!resp) return false; // breaker OPEN — report no delivery
      const data = resp.data || {};
      const ok = data.status === 200 || (data.data && data.data.messageId);
      if (ok) console.log(`[SMS] notify-africa ok to=${maskPhone(to)}`);
      return ok;
    } catch (e) {
      const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
      console.error(`[SMS] notify-africa error: ${errBody}`);
      return false;
    }
  },
};

const ALL_PROVIDERS = [MesejiProvider, NotifyAfricaProvider];

function providerOrder() {
  const raw = (process.env.SMS_PROVIDER_ORDER || 'meseji,notify-africa')
    .split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
  const byName = new Map(ALL_PROVIDERS.map((p) => [p.name, p]));
  const ordered = raw.map((n) => byName.get(n)).filter(Boolean);
  for (const p of ALL_PROVIDERS) {
    if (!ordered.includes(p)) ordered.push(p);
  }
  return ordered;
}

// Sends an SMS via the first available provider in configured order.
// Returns true if delivered.
async function sendSms(phone, message) {
  if (!phone || !message) return false;
  await acquireSmsSlot();
  try {
    for (const provider of providerOrder()) {
      if (!provider.available()) continue;
      if (await provider.send({ to: phone, message })) return true;
    }
    console.error('[SMS] no provider delivered');
    return false;
  } finally {
    releaseSmsSlot();
  }
}

function otpMessage(code, lang = 'sw') {
  return lang === 'en'
    ? `Your Soko Vibe code is ${code}. It expires in 5 minutes. Never share it.`
    : `Msimbo wako wa Soko Vibe ni ${code}. Unaisha kwa dakika 5. Usimshirikie mtu yeyote.`;
}

// Passwordless/auth code delivery with standard wording.
async function sendOtp(phone, code, { lang = 'sw' } = {}) {
  return sendSms(phone, otpMessage(code, lang));
}

// Important security notifications (suspicious login, recovery events).
// Same delivery path as OTP, distinct call site so usage is auditable.
async function sendSecurityNotification(phone, message) {
  return sendSms(phone, message);
}

module.exports = {
  sendSms,
  sendOtp,
  sendSecurityNotification,
  toLocal,
  toInternational,
  MesejiProvider,
  NotifyAfricaProvider,
};
