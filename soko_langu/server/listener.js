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
  const notifType = (data && data.type) || 'general';
  const channelId = notifType === 'chat' ? 'chat_messages_v4'
    : notifType === 'payment' || notifType === 'order' || notifType === 'withdrawal' ? 'payments_notifications_v4'
    : 'general_notifications_v4';
  const msg = {
    data: stringifyFcmData({ title: title || '', body: body || '', ...data }),
    notification: { title: title || '', body: body || '' },
    android: {
      priority: 'high',
      notification: { channel_id: channelId, sound: 'soko_notification', icon: 'ic_notification' },
    },
  };
  if (token) msg.token = token;
  return msg;
}

async function sendFcm(message, userIdForCleanup = null) {
  try {
    return await admin.messaging().send(message);
  } catch (e) {
    console.error(`[LISTENER][FCM] send failed for user ${userIdForCleanup || '?'}: ${e.code || e.message}`, e.errorInfo || '');
    if (userIdForCleanup && db &&
        (e.code === 'messaging/registration-token-not-registered' ||
         e.code === 'messaging/invalid-registration-token')) {
      console.log(`[LISTENER][FCM] Token stale for ${userIdForCleanup}, trying topic fallback...`);
      try {
        const topicMsg = {
          topic: `user_${userIdForCleanup}`,
          data: message.data || {},
          android: { priority: 'high' },
        };
        if (message.notification) topicMsg.notification = message.notification;
        const topicResult = await admin.messaging().send(topicMsg);
        console.log(`[LISTENER][FCM] Topic fallback succeeded for ${userIdForCleanup}: ${topicResult}`);
        return topicResult;
      } catch (topicErr) {
        console.error(`[LISTENER][FCM] Topic fallback failed for ${userIdForCleanup}: ${topicErr.code || topicErr.message}`);
      }
      await db.collection('users').doc(userIdForCleanup).update({ fcmToken: null });
    }
    throw e;
  }
}

// ─── SMS sender (same pattern as index.js) ──────────────────────────
async function sendSms(phone, message) {
  const apiKey = process.env.MESEJI_API_KEY;
  if (!apiKey) {
    console.error('[LISTENER] MESEJI_API_KEY not configured');
    return;
  }
  const digits = phone.replace(/\D/g, '');
  const normalized = digits.startsWith('0') ? '255' + digits.slice(1) : !digits.startsWith('255') ? '255' + digits : digits;
  try {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    const resp = await fetch('https://meseji.co.tz/api/v1/sms/send', {
      method: 'POST',
      signal: controller.signal,
      headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        sender_id: process.env.MESEJI_SENDER_ID || 'MESEJI',
        message,
        contacts: normalized,
      }),
    });
    clearTimeout(timeout);
    if (!resp.ok) {
      const err = await resp.text();
      console.error(`[LISTENER] SMS failed (${resp.status}): ${err}`);
    }
  } catch (e) {
    console.error(`[LISTENER] SMS error: ${e.message}`);
  }
}

// ─── Helpers: look up user phone ─────────────────────────────────────
async function getUserPhone(userId) {
  if (!userId || !db) return null;
  try {
    const snap = await db.collection('users').doc(userId).get();
    return snap.data()?.phone || null;
  } catch { return null; }
}

// ─── Track known statuses to avoid re-sending on every field update ───
const knownStatus = new Map();

// ─── Start listener after loading existing pending transactions ──────
console.log('[LISTENER] Loading existing pending transactions...');

function startListener() {
  console.log('[LISTENER] Starting Firestore transaction listener...');

  db.collection('transactions').onSnapshot(
    (snapshot) => {
      snapshot.docChanges().forEach((change) => {
        if (change.type !== 'modified') return;

        const orderId = change.doc.id;
        const after = change.doc.data();
        const beforeStatus = knownStatus.get(orderId);
        const newStatus = after?.status;

        knownStatus.set(orderId, newStatus);

        // Skip if we don't know the previous status (fresh restart)
        if (beforeStatus === undefined) return;

        const productName = after.productName || 'item';
        const buyerId = after.buyerId;
        const sellerId = after.sellerId;

        // ── pending → escrow_hold / paid_escrow_held / completed ──
        if (beforeStatus === 'pending' && (newStatus === 'escrow_hold' || newStatus === 'paid_escrow_held' || newStatus === 'completed')) {
          console.log(`[LISTENER] ${orderId}: ${beforeStatus} → ${newStatus}`);

          // Notify buyer via FCM
          if (buyerId) {
            db.collection('users').doc(buyerId).get()
              .then((userSnap) => {
                const fcmToken = userSnap.data()?.fcmToken;
                if (fcmToken) {
                  const title = 'Payment Received – Escrow Held';
                  const body = `Your payment for ${productName} is held in escrow.`;
                  return sendFcm(buildFcmMessage({ token: fcmToken, title, body, data: { type: 'payment', orderId, status: newStatus } }), buyerId);
                }
              })
              .then(() => console.log(`[LISTENER] ${orderId}: FCM sent to buyer ${buyerId}`))
              .catch((err) => console.error(`[LISTENER] ${orderId}: FCM failed for buyer:`, err.message));
          }

          // SMS buyer + seller
          const grandTotal = (after.productPrice || 0) + (after.shippingCost || 0);
          Promise.all([
            getUserPhone(buyerId).then(phone => phone && sendSms(phone, `Soko Vibe: Malipo ya TZS ${grandTotal.toLocaleString()} kwa Oda #${orderId} yamepokelewa na kuwekwa salama Escrow. Muuzaji anajiandaa kutuma mzigo wako.`)),
            getUserPhone(sellerId).then(phone => phone && sendSms(phone, `Soko Vibe: Oda #${orderId} imelipiwa! Fedha ipo salama Escrow. Tafadhali kamilisha usafirishaji stendi na ujaze risiti ya basi kwenye app.`)),
          ]);
        }

        // ── escrow_hold / paid_escrow_held → dispatched ──
        if ((beforeStatus === 'escrow_hold' || beforeStatus === 'paid_escrow_held') && newStatus === 'dispatched') {
          console.log(`[LISTENER] ${orderId}: ${beforeStatus} → dispatched`);

          const busName = after.busName || 'basi';
          const plateNumber = after.plateNumber || '';

          // SMS buyer
          getUserPhone(buyerId).then(phone => {
            if (phone) sendSms(phone, `Soko Vibe: Mzigo wa Oda #${orderId} umesafirishwa kupitia basi la ${busName} (${plateNumber}). Fungua app kuona risiti yako ya kidijitali.`);
          });
        }

        // ── dispatched → delivered ──
        if (beforeStatus === 'dispatched' && newStatus === 'delivered') {
          console.log(`[LISTENER] ${orderId}: dispatched → delivered`);

          const sellerReceives = after.sellerReceives || after.totalAmount || 0;

          // SMS seller
          getUserPhone(sellerId).then(phone => {
            if (phone) sendSms(phone, `Soko Vibe: Mteja amethibitisha kupokea mzigo #${orderId}. TZS ${sellerReceives.toLocaleString()} zimetolewa Escrow na kuwekwa kwenye pochi yako.`);
          });
        }

        // ── any → failed (payment failure, cancellation, etc.) ──
        if (newStatus === 'failed' && beforeStatus !== 'failed') {
          console.log(`[LISTENER] ${orderId}: ${beforeStatus} → failed`);

          // FCM to buyer
          if (buyerId) {
            db.collection('users').doc(buyerId).get()
              .then((userSnap) => {
                const fcmToken = userSnap.data()?.fcmToken;
                if (fcmToken) {
                  const title = 'Malipo Yameshindikana';
                  const body = `Malipo ya ${productName} hayakukamilika. Fungua app ili ujaribu tena.`;
                  return sendFcm(buildFcmMessage({ token: fcmToken, title, body, data: { type: 'payment_failed', orderId, status: 'failed' } }), buyerId);
                }
              })
              .catch((err) => console.error(`[LISTENER] ${orderId}: FCM failed for buyer:`, err.message));
          }

          // SMS buyer
          getUserPhone(buyerId).then(phone => {
            if (phone) sendSms(phone, `Soko Vibe: Malipo ya ${productName} hayakukamilika. Tafadhali fungua app na ujaribu tena.`);
          });
        }

        // ── any → refunded ──
        if (newStatus === 'refunded' && beforeStatus !== 'refunded') {
          console.log(`[LISTENER] ${orderId}: ${beforeStatus} → refunded`);

          if (buyerId) {
            db.collection('users').doc(buyerId).get()
              .then((userSnap) => {
                const fcmToken = userSnap.data()?.fcmToken;
                if (fcmToken) {
                  const title = 'Fedha Zimerudishwa';
                  const body = `Fedha za ${productName} zimerudishwa kwenye akaunti yako.`;
                  return sendFcm(buildFcmMessage({ token: fcmToken, title, body, data: { type: 'refund', orderId, status: 'refunded' } }), buyerId);
                }
              })
              .catch((err) => console.error(`[LISTENER] ${orderId}: FCM failed for buyer:`, err.message));
          }

          // SMS buyer
          getUserPhone(buyerId).then(phone => {
            if (phone) sendSms(phone, `Soko Vibe: Fedha za ${productName} (Oda #${orderId}) zimerudishwa kwenye akaunti yako.`);
          });
        }
      });
    },
    (error) => {
      console.error('[LISTENER] Fatal: Firestone listener error:', error);
    }
  );

  console.log('[LISTENER] Ready. Listening for transaction changes...');
}

// ─── Chat message listener: notify recipient on new message ─────
function startChatListener() {
  console.log('[LISTENER] Starting chat message listener...');

  let knownMessageIds = new Set();
  const listenerStartedAt = admin.firestore.Timestamp.now();

  // Load recent message IDs to avoid re-sending on startup
  db.collectionGroup('messages')
    .orderBy('timestamp', 'desc')
    .limit(200)
    .get()
    .then((snap) => {
      snap.docs.forEach((doc) => knownMessageIds.add(doc.id));
      console.log(`[LISTENER] Loaded ${snap.docs.length} recent chat messages`);
    })
    .catch((err) => {
      console.error('[LISTENER] Failed to load recent messages:', err.message);
    });

  // Watch all messages subcollections — no .where() to avoid needing a composite index.
  // We filter in-memory using knownMessageIds (dedup) and listenerStartedAt (cutoff).
  db.collectionGroup('messages')
    .onSnapshot(
      (snapshot) => {
        snapshot.docChanges().forEach((change) => {
          if (change.type !== 'added') return;
          const msgId = change.doc.id;
          // Skip messages already known from the initial load
          if (knownMessageIds.has(msgId)) return;
          const msgData = change.doc.data();
          // Skip messages older than listener start (in-memory filter, no index needed)
          const msgTime = msgData.timestamp;
          if (msgTime && msgTime < listenerStartedAt) return;
          knownMessageIds.add(msgId);

          const senderId = msgData.sender_id || '';
          const text = msgData.text || '';

          if (!senderId || !text) return;

          // Get the room ID from the document reference path
          const roomId = change.doc.ref.parent.parent?.id;
          if (!roomId) return;

          // Skip AI Dalali messages
          if (senderId === 'ai_dalali') return;

          console.log(`[LISTENER] New chat message in room ${roomId} from ${senderId}`);

          // Look up room participants
          db.collection('chat_rooms').doc(roomId).get()
            .then((roomSnap) => {
              if (!roomSnap.exists) return;
              const room = roomSnap.data();
              const participants = room.participants || [];

              // Find recipient (the other participant)
              const receiverId = participants.find(p => p !== senderId);
              if (!receiverId) return;

              // Look up sender's display name
              return db.collection('users').doc(senderId).get()
                .then((senderSnap) => {
                  const senderData = senderSnap.data() || {};
                  const senderName = senderData.displayName || senderData.name || 'Mtumiaji';

                  // Look up recipient's FCM token
                  return db.collection('users').doc(receiverId).get()
                    .then((receiverSnap) => {
                      const receiverData = receiverSnap.data() || {};
                      const fcmToken = receiverData.fcmToken;
                      if (!fcmToken) {
                        console.log(`[LISTENER] No FCM token for user ${receiverId}`);
                        return;
                      }

                      // Send notification (data-only — client background handler creates via Awesome Notifications)
                      const title = senderName;
                      const body = text;

                      const message = {
                        data: { title, body, type: 'chat', senderId, senderName, roomId },
                        token: fcmToken,
                        android: { priority: 'high' },
                      };

                      return sendFcm(message, receiverId)
                        .then(() => {
                          console.log(`[LISTENER] Chat notification sent to ${receiverId}`);
                        })
                        .catch((err) => {
                          // sendFcm already cleaned stale token and tried topic fallback
                          if (err.code !== 'messaging/registration-token-not-registered' &&
                              err.code !== 'messaging/invalid-registration-token') {
                            console.error('[LISTENER] Chat FCM error:', err.code || err.message);
                          }
                        });
                    });
                });
            })
            .catch((err) => {
              console.error('[LISTENER] Chat notification error:', err.message);
            });
        });
      },
      (error) => {
        console.error('[LISTENER] Chat listener error:', error);
      }
    );
}

// ─── Product listener: notify previous chat partners on new product ─────
function startProductListener() {
  console.log('[LISTENER] Starting product listener...');
  let knownProductIds = new Set();
  const listenerStartedAt = admin.firestore.Timestamp.now();

  db.collection('products')
    .orderBy('createdAt', 'desc')
    .limit(200)
    .get()
    .then((snap) => {
      snap.docs.forEach((doc) => knownProductIds.add(doc.id));
      console.log(`[LISTENER] Loaded ${snap.docs.length} recent products`);
    })
    .catch((err) => console.error('[LISTENER] Failed to load recent products:', err.message));

  db.collection('products').onSnapshot(
    (snapshot) => {
      snapshot.docChanges().forEach((change) => {
        if (change.type !== 'added') return;
        const productId = change.doc.id;
        if (knownProductIds.has(productId)) return;
        const product = change.doc.data();
        const productTime = product.createdAt;
        if (productTime && productTime < listenerStartedAt) return;
        knownProductIds.add(productId);

        const sellerId = product.sellerId;
        if (!sellerId) return;
        const sellerName = product.sellerName || 'Mfanyabiashara';
        const productName = product.name || 'bidhaa mpya';

        db.collection('chat_rooms')
          .where('participants', 'array-contains', sellerId)
          .get()
          .then((roomsSnap) => {
            const notified = new Set();
            for (const roomDoc of roomsSnap.docs) {
              const room = roomDoc.data();
              const other = (room.participants || []).find((p) => p !== sellerId);
              if (!other || notified.has(other)) continue;
              notified.add(other);
              const title = sellerName;
              const body = `${sellerName} ameweka bidhaa mpya: ${productName}.`;
              db.collection('notifications').add({
                userId: other, title, body,
                data: { type: 'product', productId, sellerId },
                isRead: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              }).catch(() => {});
              db.collection('users').doc(other).get()
                .then((userSnap) => {
                  const fcmToken = userSnap.data()?.fcmToken;
                  if (fcmToken) {
                    sendFcm(buildFcmMessage({
                      token: fcmToken, title, body,
                      data: { type: 'product', productId, sellerId, productName },
                    }), other).catch((err) => {
                      if (err.code?.startsWith('messaging/')) {
                        db.collection('users').doc(other).update({ fcmToken: null });
                      }
                    });
                  }
                }).catch(() => {});
            }
            if (notified.size > 0) {
              console.log(`[LISTENER] Notified ${notified.size} users about new product from ${sellerId}`);
            }
          }).catch((err) => console.error('[LISTENER] Product room lookup error:', err.message));
      });
    },
    (error) => console.error('[LISTENER] Product listener error:', error)
  );
}

// Seed and start both listeners
db.collection('transactions')
  .where('status', '==', 'pending')
  .get()
  .then((snap) => {
    snap.docs.forEach((doc) => knownStatus.set(doc.id, 'pending'));
    console.log(`[LISTENER] Loaded ${snap.docs.length} existing pending transactions`);
  })
  .catch((err) => {
    console.error('[LISTENER] Failed to load pending transactions:', err.message);
  })
  .finally(() => {
    startListener();
    startChatListener();
    startProductListener();
  });
