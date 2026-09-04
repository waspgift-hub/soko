// Lean OneSignal sender for compat-mounted old routers.
// Sends directly via OneSignal REST (push channel). Preference gating and
// localization live in the old server; compat keeps delivery only.
const axios = require('axios');
const { randomUUID } = require('crypto');
const config = require('../../config');
const { getFirebaseFirestore } = require('../../config/firebase');

async function sendOneSignalNotification(userId, title, body, data = {}) {
  if (!userId) return null;
  const appId = config.onesignal.appId;
  const apiKey = config.onesignal.apiKey;
  if (!appId || !apiKey) {
    console.error('[OS-COMPAT] missing OneSignal config');
    return null;
  }
  try {
    const resp = await axios.post('https://onesignal.com/api/v1/notifications', {
      app_id: appId,
      idempotency_key: randomUUID(),
      include_external_user_ids: [userId],
      channel_for_external_user_ids: 'push',
      headings: { en: title || '', sw: title || '' },
      contents: { en: body || '', sw: body || '' },
      data: { ...(data || {}), type: (data && data.type) || 'general' },
    }, {
      headers: { Authorization: `Basic ${apiKey}`, 'Content-Type': 'application/json' },
      timeout: 15000,
    });
    return resp.data || null;
  } catch (e) {
    console.error('[OS-COMPAT] send failed:', e.response?.data ? JSON.stringify(e.response.data) : e.message);
    return null;
  }
}

async function notifyAdmins(title, body, data = {}) {
  try {
    const store = getFirebaseFirestore();
    if (!store) return;
    const admin = require('firebase-admin');
    const snap = await store.collection('users').where('isAdmin', '==', true).get();
    const promises = [];
    snap.forEach((doc) => {
      const uid = doc.id;
      promises.push(
        store.collection('notifications').add({
          userId: uid,
          title,
          body,
          isRead: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          data,
        })
      );
      promises.push(sendOneSignalNotification(uid, title, body, data));
    });
    await Promise.allSettled(promises);
  } catch (e) {
    console.error('[OS-COMPAT] notifyAdmins failed:', e.message);
  }
}

module.exports = { sendOneSignalNotification, notifyAdmins };
