require('dotenv').config();
const admin = require('firebase-admin');

// ─── Firebase Admin Init ─────────────────────────────────────────────
const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
if (!serviceAccountJson) {
  console.error('[LISTENER] FIREBASE_SERVICE_ACCOUNT_JSON not set');
  process.exit(1);
}

let serviceAccount;
try {
  serviceAccount = JSON.parse(serviceAccountJson);
} catch (e) {
  console.error('[LISTENER] Failed to parse FIREBASE_SERVICE_ACCOUNT_JSON:', e.message);
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

// ─── Helpers (adapted from index.js) ─────────────────────────────────
function stringifyFcmData(data = {}) {
  const out = {};
  for (const [k, v] of Object.entries(data || {})) {
    if (v === undefined || v === null) continue;
    out[String(k)] = String(v);
  }
  return out;
}

function buildFcmMessage({ token, title, body, data = {} }) {
  return {
    notification: { title: title || 'Soko Vibe', body: body || '' },
    data: stringifyFcmData({ title: title || '', body: body || '', ...data }),
    android: { priority: 'high' },
    apns: {
      headers: { 'apns-priority': '10' },
      payload: {
        aps: {
          alert: { title: title || '', body: body || '' },
          sound: 'soko_notification.wav',
          badge: 1,
          'content-available': 1,
        },
      },
    },
  };
}

async function sendFcm(message, userIdForCleanup = null) {
  try {
    return await admin.messaging().send(message);
  } catch (e) {
    if (userIdForCleanup && db &&
        (e.code === 'messaging/registration-token-not-registered' ||
         e.code === 'messaging/invalid-registration-token')) {
      console.log(`[LISTENER] Cleaning stale FCM token for user ${userIdForCleanup}`);
      await db.collection('users').doc(userIdForCleanup).update({ fcmToken: null });
    }
    throw e;
  }
}

// ─── Track known statuses to avoid re-sending on every field update ───
const knownStatus = new Map();

// ─── Firestore Listener ─────────────────────────────────────────────
console.log('[LISTENER] Starting Firestore transaction listener...');

db.collection('transactions').onSnapshot(
  (snapshot) => {
    snapshot.docChanges().forEach((change) => {
      if (change.type !== 'modified') return;

      const orderId = change.doc.id;
      const after = change.doc.data();
      const beforeStatus = knownStatus.get(orderId);
      const newStatus = after?.status;

      // Store the new status for next comparison
      knownStatus.set(orderId, newStatus);

      // Only trigger on pending → completed / escrow_hold
      if (beforeStatus && beforeStatus !== 'pending') return;
      if (newStatus !== 'completed' && newStatus !== 'escrow_hold') return;

      const buyerId = after.buyerId;
      if (!buyerId) {
        console.log(`[LISTENER] ${orderId}: no buyerId, skipping`);
        return;
      }

      console.log(`[LISTENER] ${orderId}: ${beforeStatus} → ${newStatus} (buyer: ${buyerId})`);

      // Fetch buyer's FCM token
      db.collection('users').doc(buyerId).get()
        .then((userSnap) => {
          const fcmToken = userSnap.data()?.fcmToken;
          if (!fcmToken) {
            console.log(`[LISTENER] ${orderId}: no FCM token for buyer ${buyerId}`);
            return;
          }

          const productName = after.productName || 'item';
          const title = newStatus === 'completed'
            ? 'Payment Successful'
            : 'Payment Received – Escrow Held';
          const body = newStatus === 'completed'
            ? `Your payment for ${productName} has been completed.`
            : `Your payment for ${productName} is held in escrow.`;

          const message = buildFcmMessage({
            token: fcmToken,
            title,
            body,
            data: { type: 'payment', orderId, status: newStatus },
          });

          return sendFcm(message, buyerId);
        })
        .then(() => {
          console.log(`[LISTENER] ${orderId}: FCM sent to buyer ${buyerId}`);
        })
        .catch((err) => {
          console.error(`[LISTENER] ${orderId}: FCM failed for buyer ${buyerId}:`, err.message);
        });
    });
  },
  (error) => {
    console.error('[LISTENER] Fatal: Firestone listener error:', error);
    // Don't crash — let the process restart on Railway
  }
);

// Keep process alive
console.log('[LISTENER] Ready. Listening for transaction changes...');
