// SMS sender: Meseji first, Notify Africa fallback.
// Ported from the legacy server (verified live): Meseji wants `contacts`
// as a single local-format STRING, not an array.
const axios = require('axios');
const config = require('../config');

const NOTIFY_SMS_BASE = 'https://api.notify.africa';

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

async function sendViaMeseji(phone, message) {
  const apiKey = config.sms.mesejiApiKey;
  if (!apiKey) return false;
  const local = toLocal(phone);
  const configured = config.sms.mesejiSenderId || 'MESEJI';
  const senders = configured === 'MESEJI' ? ['MESEJI'] : [configured, 'MESEJI'];
  for (const sender of senders) {
    try {
      const resp = await axios.post('https://meseji.co.tz/api/v1/sms/send', {
        sender_id: sender,
        message,
        contacts: local,
      }, {
        headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
        timeout: 15000,
      });
      console.log(`[SMS] meseji ok sender=${sender} to=${local} batch=${resp.data?.batch_id || ''}`);
      return true;
    } catch (e) {
      const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
      console.error(`[SMS] meseji sender ${sender} error: ${errBody}`);
    }
  }
  return false;
}

async function sendViaNotifyAfrica(phone, message) {
  const apiKey = process.env.NOTIFY_AFRICA_SMS_API_KEY || config.sms.notifyAfricaApiKey;
  const senderId = process.env.NOTIFY_AFRICA_SENDER_ID;
  if (!apiKey || !senderId) return false;
  try {
    const resp = await axios.post(`${NOTIFY_SMS_BASE}/api/v1/api/messages/send`, {
      phone_number: toInternational(phone),
      message,
      sender_id: senderId,
    }, {
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      timeout: 15000,
    });
    const data = resp.data || {};
    const ok = data.status === 200 || (data.data && data.data.messageId);
    if (ok) console.log(`[SMS] notify-africa ok to=${toInternational(phone)}`);
    return ok;
  } catch (e) {
    const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
    console.error(`[SMS] notify-africa error: ${errBody}`);
    return false;
  }
}

// Sends an SMS, Meseji first then Notify Africa. Returns true if delivered.
async function sendSms(phone, message) {
  if (!phone || !message) return false;
  if (await sendViaMeseji(phone, message)) return true;
  if (await sendViaNotifyAfrica(phone, message)) return true;
  console.error('[SMS] no provider delivered');
  return false;
}

module.exports = { sendSms, toLocal, toInternational };
