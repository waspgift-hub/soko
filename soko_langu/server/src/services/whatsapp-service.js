// WhatsApp OTP delivery via the Meta WhatsApp Business Cloud API.
//
// WhatsApp is the cheapest reliable OTP channel in Tanzania (template messages
// are billed per conversation, not per message), intended as a high-volume
// alternative to SMS. It is OPT-IN by configuration: with no token/phone
// number id set, every call reports `available: false` and the delivery chain
// falls through to SMS — a zero-setup no-op until the Meta business is linked.
//
// REQUIRED upstream setup (outside this repo):
//   - a WhatsApp Business account + phone number id
//   - an approved `otp` message template with one text parameter
//     (e.g. "Msimbo wako ni {{1}}. Unaisha kwa dakika 5.")
//   - if the template is approved for only one language, pin that language via
//     WHATSAPP_LANGUAGE; the default sends `sw` then `en` bodies.
//
// All settings come straight from env (WHATSAPP_*) so the module boots even on
// deployments that have not linked a Meta business; the `configured()` gate
// keeps it a no-op until THEN.
const axios = require('axios');

const BASE_URL = process.env.WHATSAPP_BASE_URL || 'https://graph.facebook.com/v19.0';
const PHONE_NUMBER_ID = process.env.WHATSAPP_PHONE_NUMBER_ID || '';
const TOKEN = process.env.WHATSAPP_TOKEN || '';
const LANGUAGE = process.env.WHATSAPP_LANGUAGE || 'sw';
const TEMPLATE_NAME = process.env.WHATSAPP_TEMPLATE_NAME || 'otp';

function configured() {
  return Boolean(TOKEN && PHONE_NUMBER_ID);
}

function toE164(phone) {
  const d = String(phone).replace(/\D/g, '');
  if (d.startsWith('0')) return `255${d.slice(1)}`;
  if (d.startsWith('255')) return `+${d}`;
  return d;
}

// Sends the WhatsApp `otp` template with the code as its body parameter.
// Returns true when Meta accepted the message for delivery.
async function sendOtp(phone, code, langCode = 'sw') {
  if (!configured()) return false;

  const language = langCode === 'en' ? 'en' : LANGUAGE;

  try {
    const resp = await axios.post(
      `${BASE_URL}/${PHONE_NUMBER_ID}/messages`,
      {
        messaging_product: 'whatsapp',
        recipient_type: 'individual',
        to: toE164(phone),
        type: 'template',
        template: {
          name: TEMPLATE_NAME,
          language: { code: language },
          components: [
            { type: 'body', parameters: [{ type: 'text', text: String(code) }] },
          ],
        },
      },
      {
        headers: {
          Authorization: `Bearer ${TOKEN}`,
          'Content-Type': 'application/json',
        },
        timeout: 15000,
      },
    );
    const ok = resp.status === 200 && resp.data && resp.data.messages;
    if (ok) console.log(`[WA] otp template accepted for ${phone}`);
    return ok;
  } catch (e) {
    console.error('[WA] otp send failed:', e.response?.data || e.message);
    return false;
  }
}

module.exports = { sendOtp, configured };