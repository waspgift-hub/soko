// Batch promotional SMS sender.
//
// Reads every user with a stored phone number, de-duplicates by normalized
// phone (so nobody gets the same message twice), skips users who opted out of
// SMS (notification_preferences.sms_enabled === false), then sends the message
// through Meseji (primary) with Notify Africa as fallback — identical provider
// logic to the live /api/sms/send route.
//
// Run a dry run first (no SMS sent, prints the recipient list):
//   node send_promo_sms.js --dry-run
// Then send for real (optional --message "..." overrides the default text):
//   node send_promo_sms.js
require('dotenv').config();
const axios = require('axios');
const admin = require('firebase-admin');
const { smsSafeForGateway } = require('./notif_lang');

const DRY_RUN = process.argv.includes('--dry-run');
const DELAY_MS = 1200; // Meseji is not a fan of bursts — space sends out.

const DEFAULT_MESSAGE =
  'Tangaza bidhaa zako kwa bei nafuu na wanunue zaidi! Sambaza neno kwa marafiki na familia. Kila agizo linalolipwa linakusaidia kukua. Pakia Soko Vibe leo!';

const MESEJI_API_KEY = process.env.MESEJI_API_KEY;
const MESEJI_SENDER_ID = process.env.MESEJI_SENDER_ID || 'MESEJI';
const NOTIFY_SMS_BASE = 'https://api.notify.africa';
const NOTIFY_AFRICA_API_KEY = process.env.NOTIFY_AFRICA_SMS_API_KEY;
const NOTIFY_AFRICA_SENDER_ID = process.env.NOTIFY_AFRICA_SENDER_ID;

let db;
try {
  const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
  admin.initializeApp({ credential: admin.credential.cert(sa) });
  db = admin.firestore();
} catch (e) {
  console.error('[FIREBASE] Init failed:', e.message);
  process.exit(1);
}

// Normalize to a single canonical 255XXXXXXXXX form so "0719..." and "+255719..."
// collapse to one recipient.
function normalizePhone(raw) {
  const digits = String(raw || '').replace(/\D/g, '');
  if (digits.startsWith('255') && digits.length === 12) return digits;
  if (digits.startsWith('0') && digits.length === 10) return '255' + digits.slice(1);
  return digits; // Non-TZ or malformed — caller decides whether to keep it.
}

async function sendMeseji(localPhone, message) {
  const senders = MESEJI_SENDER_ID === 'MESEJI' ? ['MESEJI'] : [MESEJI_SENDER_ID, 'MESEJI'];
  for (const sender of senders) {
    try {
      // Meseji expects `contacts` as a single local-format string; the array
      // form triggers `finalContacts.split is not a function` (verified live).
      const resp = await axios.post('https://meseji.co.tz/api/v1/sms/send', {
        sender_id: sender,
        message,
        contacts: localPhone,
      }, {
        headers: { 'x-api-key': MESEJI_API_KEY, 'Content-Type': 'application/json' },
        timeout: 15000,
      });
      console.log(`  [MESEJI] ok sender=${sender} to ${localPhone} batch=${resp.data?.batch_id || ''}`);
      return true;
    } catch (e) {
      const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
      console.error(`  [MESEJI] sender ${sender} error: ${errBody}`);
    }
  }
  return false;
}

async function sendNotifyAfrica(phone, message) {
  const local = normalizePhone(phone);
  const international = local.startsWith('255') ? local : '255' + local.replace(/^0/, '');
  try {
    const resp = await axios.post(`${NOTIFY_SMS_BASE}/api/v1/api/messages/send`, {
      phone_number: international,
      message,
      sender_id: NOTIFY_AFRICA_SENDER_ID,
    }, {
      headers: { Authorization: `Bearer ${NOTIFY_AFRICA_API_KEY}`, 'Content-Type': 'application/json' },
      timeout: 15000,
    });
    const data = resp.data || {};
    const ok = data.status === 200 || (data.data && data.data.messageId);
    console.log(`  [NOTIFY] ok to ${international} msgId=${data.data?.messageId || ''}`);
    return ok;
  } catch (e) {
    const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
    console.error(`  [NOTIFY] error: ${errBody}`);
    return false;
  }
}

async function sendSms(phone, message) {
  const local = normalizePhone(phone);
  if (MESEJI_API_KEY) {
    const ok = await sendMeseji(local.replace(/^255/, '0'), message);
    if (ok) return { ok: true, provider: 'meseji' };
  }
  if (NOTIFY_AFRICA_API_KEY && NOTIFY_AFRICA_SENDER_ID) {
    const ok = await sendNotifyAfrica(local, message);
    if (ok) return { ok: true, provider: 'notify_africa' };
  }
  return { ok: false, provider: 'none' };
}

async function main() {
  const message = process.argv.indexOf('--message') !== -1
    ? process.argv[process.argv.indexOf('--message') + 1]
    : DEFAULT_MESSAGE;

  console.log(`Mode: ${DRY_RUN ? 'DRY RUN (no SMS sent)' : 'SEND (real SMS!)'}\nMessage:\n${message}\n`);

  // Collect phones across users. Prefer the `phone` field, fall back to `phoneNumber`.
  const byPhone = new Map();
  const usersSnap = await db.collection('users').get();
  console.log(`Users scanned: ${usersSnap.size}`);

  for (const doc of usersSnap.docs) {
    const data = doc.data() || {};
    const raw = data.phone || data.phoneNumber || '';
    const normalized = normalizePhone(raw);
    if (normalized.length !== 12) continue; // Skip missing/malformed/TZ-format numbers
    if (!byPhone.has(normalized)) byPhone.set(normalized, { uids: [], names: [] });
    const entry = byPhone.get(normalized);
    if (!entry.uids.includes(doc.id)) {
      entry.uids.push(doc.id);
      const name = data.displayName || data.name || '';
      if (name && !entry.names.includes(name)) entry.names.push(name);
    }
  }

  // Respect SMS opt-out. A user has opted out only if their prefs doc explicitly
  // sets sms_enabled to false — missing doc / missing flag means allowed.
  const optedOut = new Set();
  const userLang = new Map();
  if (!DRY_RUN) {
    const prefsSnap = await db.collection('notification_preferences').get();
    for (const doc of prefsSnap.docs) {
      if (doc.data()?.sms_enabled === false) optedOut.add(doc.id);
    }
  }
  // Every broadcast SMS is one language: resolve each recipient's in-app
  // language (default Swahili) and localize the default message before send.
  for (const doc of usersSnap.docs) {
    userLang.set(doc.id, doc.data()?.langCode || 'sw');
  }

  const recipients = [];
  for (const [phone, entry] of byPhone) {
    const optedOutUids = entry.uids.filter((uid) => optedOut.has(uid));
    const stillIn = entry.uids.filter((uid) => !optedOut.has(uid));
    if (stillIn.length === 0) {
      console.log(`SKIP ${phone} — all ${entry.uids.length} account(s) opted out of SMS`);
      continue;
    }
    if (optedOutUids.length > 0 && optedOutUids.length < entry.uids.length) {
      console.log(`PARTIAL ${phone} — ${stillIn.length} account(s) receive, ${optedOutUids.length} opted out`);
    }
    recipients.push({ phone, uids: stillIn, names: entry.names });
  }

  console.log(`\nUnique phone numbers: ${byPhone.size} → will message ${recipients.length}\n`);

  if (DRY_RUN) {
    for (const r of recipients) {
      console.log(`  ${r.phone}  (${r.uids.length} account${r.uids.length > 1 ? 's' : ''}${r.names.length ? `, ${r.names.join(', ')}` : ''})`);
    }
    console.log(`\nDry run complete — ${recipients.length} SMS would be sent.`);
    return;
  }

  let sent = 0;
  let failed = 0;
  const results = [];
  for (let i = 0; i < recipients.length; i++) {
    const r = recipients[i];
    process.stdout.write(`[${i + 1}/${recipients.length}] ${r.phone} ... `);
    try {
      // Localize the broadcast to this recipient's in-app language so one SMS
      // is one language. Custom --message text stays verbatim (no rule match).
      const lang = userLang.get(r.uids[0]) || 'sw';
      const result = await sendSms(r.phone, smsSafeForGateway(lang, message));
      if (result.ok) { sent++; results.push({ phone: r.phone, status: 'sent', provider: result.provider }); }
      else { failed++; results.push({ phone: r.phone, status: 'failed' }); }
      console.log(result.ok ? `sent (${result.provider})` : 'FAILED');
    } catch (e) {
      failed++;
      results.push({ phone: r.phone, status: 'error', error: e.message });
      console.log(`ERROR: ${e.message}`);
    }
    await new Promise((resolve) => setTimeout(resolve, DELAY_MS));
  }

  console.log(`\nDone. Sent: ${sent}, failed: ${failed}`);
  const fs = require('fs');
  fs.writeFileSync('promo_sms_report.json', JSON.stringify({ sentAt: new Date().toISOString(), message, results }, null, 2));
  console.log('Report: promo_sms_report.json');
}

main().catch((e) => {
  console.error('FATAL:', e.message);
  process.exit(1);
});
