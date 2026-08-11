// Batch promotional push notification sender (OneSignal, heads-up priority).
//
// Two delivery channels:
//  1. OneSignal push — heads-up on subscribed devices. Sent per user so one
//     bad subscription can't abort the run (unsubscribed users are dropped by
//     the provider, "email disabled" failures are logged and skipped).
//  2. In-app Firestore notification records — always written for every account,
//     so the message appears in the app's notification center, and users who
//     denied push still see it as a heads-up via the Firestore fallback
//     listener (notification_service.dart).
//
// Honors the marketing opt-out (notification_preferences.marketing === false).
//
// Run a dry run first (no writes, prints recipient list):
//   node send_promo_push.js --dry-run
// Then send for real:
//   node send_promo_push.js
require('dotenv').config();
const axios = require('axios');
const { randomUUID } = require('node:crypto');
const admin = require('firebase-admin');

const DRY_RUN = process.argv.includes('--dry-run');

const ONE_SIGNAL_APP_ID = process.env.ONE_SIGNAL_APP_ID;
const ONE_SIGNAL_REST_API_KEY = process.env.ONE_SIGNAL_REST_API_KEY;
const OS_URL = 'https://api.onesignal.com/notifications';

const TITLE = 'Tangaza Bidhaa Zako!';
const BODY = 'Pakia Soko Vibe na ueneze neno kwa marafiki na familia. Kila agizo linalolipwa linakusaidia kukua. Wanunuzi wengi = mauzo zaidi!';

let db;
try {
  const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
  admin.initializeApp({ credential: admin.credential.cert(sa) });
  db = admin.firestore();
} catch (e) {
  console.error('[FIREBASE] Init failed:', e.message);
  process.exit(1);
}

// Same heads-up channel mapping as server notifTypeToChannel() — a marketing
// push goes to the max-importance general channel so Android shows it head-up.
function notifTypeToChannel(type) {
  if (!type) return 'general_notifications_v6';
  if (type === 'chat' || type === 'group_chat') return 'chat_messages_v6';
  if (type === 'system' || type === 'admin' || type === 'alert') return 'system_alerts_v6';
  if (['payment','order','payout','dispute','refund','withdrawal',
       'escrow_release','auto_payout','escrow_auto_release',
       'dispute_resolved','cancelled','auto_withdrawal',
       'delivery_confirmed','payment_failed','kyc','deposit','deposit_failed'].includes(type)) return 'payments_notifications_v6';
  return 'general_notifications_v6';
}

// Filter a user list down to those whose prefs allow marketing pushes.
async function filterMarketingAllowed(userIds) {
  const allowed = [];
  const BATCH = 400;
  for (let i = 0; i < userIds.length; i += BATCH) {
    const batch = userIds.slice(i, i + BATCH);
    const snaps = await db.getAll(...batch.map((id) => db.collection('notification_preferences').doc(id)));
    for (let j = 0; j < snaps.length; j++) {
      const prefs = snaps[j].exists ? snaps[j].data() : {};
      if (prefs.general === false) continue;
      if (prefs.marketing === false) continue;
      allowed.push(batch[j]);
    }
  }
  return allowed;
}

async function sendPushOne(userId) {
  try {
    const resp = await axios.post(OS_URL, {
      app_id: ONE_SIGNAL_APP_ID,
      idempotency_key: randomUUID(),
      include_external_user_ids: [userId],
      channel_for_external_user_ids: 'push',
      headings: { en: TITLE, sw: TITLE },
      contents: { en: BODY, sw: BODY },
      data: { type: 'marketing', promo: 'promo_push_2026' },
      priority: 10, android_priority: 'high', android_visibility: 1,
      existing_android_channel_id: notifTypeToChannel('marketing'),
      android_sound: 'soko_notification',
      android_icon: 'ic_notification',
    }, {
      headers: { 'Content-Type': 'application/json', Authorization: `Key ${ONE_SIGNAL_REST_API_KEY}` },
      timeout: 30000,
    });
    const data = resp.data;
    if (data.id) {
      return { ok: true, recipients: data.recipients ?? 0, id: data.id };
    }
    const errs = (data.errors || []).join('; ');
    console.error(`  [OS] no id for ${userId}: ${errs}`);
    return { ok: false, error: errs };
  } catch (e) {
    const errBody = e.response?.data?.errors ? e.response.data.errors.join('; ') : (e.response?.data ? JSON.stringify(e.response.data) : e.message);
    console.error(`  [OS] ${userId}: ${errBody}`);
    return { ok: false, error: errBody };
  }
}

async function main() {
  console.log(`Mode: ${DRY_RUN ? 'DRY RUN (no writes)' : 'SEND (real push + in-app records!)'}`);
  console.log(`Title: ${TITLE}\nBody: ${BODY}\n`);

  if (!ONE_SIGNAL_APP_ID || !ONE_SIGNAL_REST_API_KEY) {
    console.error('[OS] Missing ONE_SIGNAL_APP_ID or ONE_SIGNAL_REST_API_KEY');
    process.exit(1);
  }

  const usersSnap = await db.collection('users').get();
  const allUserIds = usersSnap.docs.map((doc) => doc.id);
  console.log(`Total accounts: ${allUserIds.length}`);

  const allowed = DRY_RUN ? allUserIds : await filterMarketingAllowed(allUserIds);
  const optedOut = allUserIds.length - allowed.length;
  if (optedOut > 0) console.log(`Opted out of marketing: ${optedOut}`);

  console.log(`\nRecipients: ${allowed.length}`);
  if (DRY_RUN) {
    for (const uid of allowed) console.log(`  ${uid}`);
    console.log(`\nDry run complete — ${allowed.length} users targeted.`);
    return;
  }

  // Channel 1 — OneSignal push, one call per user so a single bad subscription
  // or the app-level "email disabled" setting can't abort the whole run.
  console.log('\nSending OneSignal pushes...');
  let pushed = 0;
  for (let i = 0; i < allowed.length; i++) {
    process.stdout.write(`[${i + 1}/${allowed.length}] ${allowed[i]} ... `);
    const result = await sendPushOne(allowed[i]);
    if (result.ok) { pushed += result.recipients; console.log(`accepted (recipients=${result.recipients})`); }
    else console.log('skipped');
  }

  // Channel 2 — in-app notification records (notification center + heads-up
  // fallback for push-denied users). This is the reliable channel.
  console.log('\nWriting in-app notification records...');
  let written = 0;
  for (const uid of allowed) {
    try {
      await db.collection('notifications').add({
        userId: uid,
        title: TITLE,
        body: BODY,
        isRead: false,
        type: 'marketing',
        data: { type: 'marketing', promo: 'promo_push_2026' },
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      written++;
    } catch (e) {
      console.error(`  in-app write error for ${uid}: ${e.message}`);
    }
  }

  console.log(`\nDone. OneSignal delivered to ${pushed} subscribed device(s) of ${allowed.length} targeted. In-app records: ${written}/${allowed.length}.`);
  const fs = require('fs');
  fs.writeFileSync('promo_push_report.json', JSON.stringify({ sentAt: new Date().toISOString(), title: TITLE, body: BODY, targeted: allowed.length, pushed, inApp: written }, null, 2));
  console.log('Report: promo_push_report.json');
}

main().catch((e) => {
  console.error('FATAL:', e.message);
  process.exit(1);
});
