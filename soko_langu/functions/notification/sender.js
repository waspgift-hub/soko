const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { NOTIFICATION_TYPES } = require('./channels');

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;

const PAYMENT_TYPES = new Set([
  'payment_received', 'payment_failed', 'escrow_release',
  'escrow_auto_release', 'payout_completed', 'payout_failed',
  'withdrawal_failed', 'refund_processed',
]);

async function shouldSend(userId, type) {
  try {
    const prefDoc = await db.collection('notification_preferences').doc(userId).get();
    if (!prefDoc.exists) return true;
    const prefs = prefDoc.data();
    const channel = (NOTIFICATION_TYPES[type] || {}).channel || 'general';
    return prefs[channel] !== false && prefs[type] !== false;
  } catch {
    return true;
  }
}

async function sendFcm(uid, title, body, data) {
  const topic = `user_${uid}`;
  const msg = {
    topic,
    notification: { title, body },
    data: Object.fromEntries(Object.entries(data || {}).map(([k, v]) => [k, String(v)])),
    android: { priority: 'high', notification: { sound: 'default' } },
    apns: { payload: { aps: { sound: 'default' } } },
  };
  try {
    await admin.messaging().send(msg);
    return;
  } catch {
    // topic may not exist
  }
  try {
    const userDoc = await db.collection('users').doc(uid).get();
    const token = userDoc.data()?.fcmToken;
    if (token) {
      await admin.messaging().send({ ...msg, topic: undefined, token });
    }
  } catch {
    // token stale
  }
}

async function sendSms(phone, message) {
  if (!phone || !message) return;
  const apiKey = process.env.MESEJI_API_KEY;
  if (!apiKey) return;
  const digits = phone.replace(/\D/g, '');
  // Meseji only accepts local-format numbers (07XXXXXXXX) inside a contacts
  // ARRAY — string or +255 format both come back HTTP 500 from the provider.
  const local = digits.startsWith('255')
    ? '0' + digits.slice(3)
    : !digits.startsWith('0')
      ? '0' + digits
      : digits;
  const configured = process.env.MESEJI_SENDER_ID || 'MESEJI';
  const senders = configured === 'MESEJI' ? ['MESEJI'] : [configured, 'MESEJI'];
  for (const sender of senders) {
    try {
      const url = process.env.MESEJI_API_URL || 'https://meseji.co.tz/api/v1/sms/send';
      const resp = await fetch(url, {
        method: 'POST',
        headers: {
          'x-api-key': apiKey,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          sender_id: sender,
          message,
          contacts: [local],
        }),
      });
      if (resp.ok) return;
      const err = await resp.text();
      console.error(`[NOTIFY] SMS failed (${resp.status}): ${err}`);
    } catch (e) {
      console.error(`[NOTIFY] SMS error: ${e.message}`);
    }
  }
}

async function notifyUser({ userId, title, body, type = 'general', data = {} }) {
  if (!userId) return;

  const send = await shouldSend(userId, type);
  if (!send) return;

  await sendFcm(userId, title, body, { ...data, type });

  try {
    await db.collection('notifications').add({
      userId, title, body, data: { ...data, type }, isRead: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch {
    // non-critical
  }

  if (PAYMENT_TYPES.has(type)) {
    try {
      const userDoc = await db.collection('users').doc(userId).get();
      const phone = userDoc.data()?.phone;
      if (phone) {
        await sendSms(phone, `${title}: ${body}`);
      }
    } catch {
      // non-critical
    }
  }
}

module.exports = { notifyUser, sendSms };
