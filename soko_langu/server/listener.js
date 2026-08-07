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

const notifPrefs = require('./notificationPrefs');

// ─── OneSignal helpers (adapted from index.js) ──────────────────
const ONE_SIGNAL_APP_ID = process.env.ONE_SIGNAL_APP_ID;
const ONE_SIGNAL_REST_API_KEY = process.env.ONE_SIGNAL_REST_API_KEY;

function getChannelId(data = {}) {
  const type = (data && data.type) || 'general';
  if (type === 'chat' || type === 'group_chat') return 'chat_messages_v6';
  if (type === 'system' || type === 'admin' || type === 'alert') return 'system_alerts_v6';
  if (['payment','order','payout','dispute','refund','withdrawal',
       'escrow_release','auto_payout','escrow_auto_release',
       'dispute_resolved','cancelled','auto_withdrawal',
       'delivery_confirmed','payment_failed','kyc','deposit','deposit_failed'].includes(type)) return 'payments_notifications_v6';
  return 'general_notifications_v6';
}

async function sendOsNotification(userId, title, body, data = {}) {
  if (!userId) { console.log('[LISTENER][OS] No userId'); return null; }
  if (!ONE_SIGNAL_APP_ID || !ONE_SIGNAL_REST_API_KEY) {
    console.error('[LISTENER][OS] Missing ONE_SIGNAL_APP_ID or ONE_SIGNAL_REST_API_KEY');
    return null;
  }
  const notifType = (data && data.type) || 'general';
  if (!(await notifPrefs.isPushAllowed(userId, notifType))) {
    console.log(`[LISTENER][OS] skipped push to ${userId} type=${notifType} (preferences)`);
    return null;
  }
  try {
    const axios = require('axios');
    const resp = await axios.post('https://onesignal.com/api/v1/notifications', {
      app_id: ONE_SIGNAL_APP_ID,
      include_external_user_ids: [userId],
      headings: { en: title || '' },
      contents: { en: body || '' },
      data: { ...(data || {}), type: (data && data.type) || 'general' },
      existing_android_channel_id: getChannelId(data),
      android_sound: 'soko_notification',
      android_icon: 'ic_notification',
      priority: 10,
      android_priority: 'high',
      android_visibility: 1,
      small_icon: 'ic_notification',
      large_icon: 'ic_notification',
      android_accent_color: 'FF40916C',
    }, { headers: { 'Authorization': `Basic ${ONE_SIGNAL_REST_API_KEY}` } });
    const result = resp.data;
    if (result.id) {
      console.log(`[LISTENER][OS] sent to ${userId} type=${(data && data.type) || 'general'} id=${result.id}`);
    } else {
      console.error(`[LISTENER][OS] send failed:`, JSON.stringify(result));
    }
    return result;
  } catch (e) {
    const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
    console.error(`[LISTENER][OS] FAILED user=${userId}: ${errBody}`);
    return null;
  }
}

// ─── SMS sender (same pattern as index.js) ──────────────────────────
async function sendSms(phone, message, userId) {
  if (userId && !(await notifPrefs.isSmsAllowed(userId))) {
    console.log(`[LISTENER][SMS] skipped to ${userId} (sms preferences)`);
    return;
  }
  const apiKey = process.env.MESEJI_API_KEY;
  if (!apiKey) {
    console.error('[LISTENER] MESEJI_API_KEY not configured');
    return;
  }
  const digits = phone.replace(/\D/g, '');
  const normalized = digits.startsWith('0') ? '255' + digits.slice(1) : !digits.startsWith('255') ? '255' + digits : digits;
  try {
    const axios = require('axios');
    const resp = await axios.post('https://meseji.co.tz/api/v1/sms/send', {
      sender_id: process.env.MESEJI_SENDER_ID || 'MESEJI',
      message,
      contacts: normalized,
    }, {
      headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
      timeout: 15000,
    });
    if (resp.status !== 200) {
      console.error(`[LISTENER] SMS failed (${resp.status}): ${JSON.stringify(resp.data)}`);
    }
  } catch (e) {
    const errBody = e.response?.data ? JSON.stringify(e.response.data) : e.message;
    console.error(`[LISTENER] SMS error: ${errBody}`);
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

          // Notify buyer via OneSignal
          if (buyerId) {
            const title = 'Payment Received – Escrow Held';
            const body = `Your payment for ${productName} is held in escrow.`;
            sendOsNotification(buyerId, title, body, { type: 'payment', orderId, status: newStatus })
              .then(() => console.log(`[LISTENER] ${orderId}: push sent to buyer ${buyerId}`))
              .catch((err) => console.error(`[LISTENER] ${orderId}: push failed for buyer:`, err.message));
          }

          // SMS buyer + seller
          const grandTotal = (after.productPrice || 0) + (after.shippingCost || 0);
          Promise.all([
            getUserPhone(buyerId).then(phone => phone && sendSms(phone, `Soko Vibe: Malipo ya TZS ${grandTotal.toLocaleString()} kwa Oda #${orderId} yamepokelewa na kuwekwa salama Escrow. Muuzaji anajiandaa kutuma mzigo wako.`, buyerId)),
            getUserPhone(sellerId).then(phone => phone && sendSms(phone, `Soko Vibe: Oda #${orderId} imelipiwa! Fedha ipo salama Escrow. Tafadhali kamilisha usafirishaji stendi na ujaze risiti ya basi kwenye app.`, sellerId)),
          ]);
        }

        // ── escrow_hold / paid_escrow_held → dispatched ──
        if ((beforeStatus === 'escrow_hold' || beforeStatus === 'paid_escrow_held') && newStatus === 'dispatched') {
          console.log(`[LISTENER] ${orderId}: ${beforeStatus} → dispatched`);

          const busName = after.busName || 'basi';
          const plateNumber = after.plateNumber || '';

          // SMS buyer
          getUserPhone(buyerId).then(phone => {
            if (phone) sendSms(phone, `Soko Vibe: Mzigo wa Oda #${orderId} umesafirishwa kupitia basi la ${busName} (${plateNumber}). Fungua app kuona risiti yako ya kidijitali.`, buyerId);
          });
        }

        // ── dispatched → delivered ──
        if (beforeStatus === 'dispatched' && newStatus === 'delivered') {
          console.log(`[LISTENER] ${orderId}: dispatched → delivered`);

          const sellerReceives = after.sellerReceives || after.totalAmount || 0;

          // SMS seller
          getUserPhone(sellerId).then(phone => {
            if (phone) sendSms(phone, `Soko Vibe: Mteja amethibitisha kupokea mzigo #${orderId}. TZS ${sellerReceives.toLocaleString()} zimetolewa Escrow na kuwekwa kwenye pochi yako.`, sellerId);
          });
        }

        // ── any → failed (payment failure, cancellation, etc.) ──
        if (newStatus === 'failed' && beforeStatus !== 'failed') {
          console.log(`[LISTENER] ${orderId}: ${beforeStatus} → failed`);

          // Push to buyer
          if (buyerId) {
            const title = 'Malipo Yameshindikana';
            const body = `Malipo ya ${productName} hayakukamilika. Fungua app ili ujaribu tena.`;
            sendOsNotification(buyerId, title, body, { type: 'payment_failed', orderId, status: 'failed' })
              .catch((err) => console.error(`[LISTENER] ${orderId}: push failed for buyer:`, err.message));
          }

          // SMS buyer
          getUserPhone(buyerId).then(phone => {
            if (phone) sendSms(phone, `Soko Vibe: Malipo ya ${productName} hayakukamilika. Tafadhali fungua app na ujaribu tena.`, buyerId);
          });
        }

        // ── any → refunded ──
        if (newStatus === 'refunded' && beforeStatus !== 'refunded') {
          console.log(`[LISTENER] ${orderId}: ${beforeStatus} → refunded`);

          if (buyerId) {
            const title = 'Fedha Zimerudishwa';
            const body = `Fedha za ${productName} zimerudishwa kwenye akaunti yako.`;
            sendOsNotification(buyerId, title, body, { type: 'refund', orderId, status: 'refunded' })
              .catch((err) => console.error(`[LISTENER] ${orderId}: push failed for buyer:`, err.message));
          }

          // SMS buyer
          getUserPhone(buyerId).then(phone => {
            if (phone) sendSms(phone, `Soko Vibe: Fedha za ${productName} (Oda #${orderId}) zimerudishwa kwenye akaunti yako.`, buyerId);
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

                  // Send via OneSignal
                  const title = senderName;
                  const body = text;
                  return sendOsNotification(receiverId, title, body, { type: 'chat', senderId, senderName, roomId })
                    .then(() => {
                      console.log(`[LISTENER] Chat notification sent to ${receiverId}`);
                    })
                    .catch((err) => {
                      console.error('[LISTENER] Chat push error:', err.message);
                    })
                    .then(() => {
                      // Create in-app notification doc
                      return db.collection('notifications').add({
                        userId: receiverId,
                        title: senderName,
                        body: text,
                        type: 'chat',
                        data: { senderId, senderName, roomId },
                        isRead: false,
                        createdAt: admin.firestore.FieldValue.serverTimestamp(),
                      }).catch((err) => {
                        console.error('[LISTENER] Chat in-app notification error:', err.message);
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
              sendOsNotification(other, title, body, { type: 'product', productId, sellerId, productName }).catch(() => {});
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

// ─── District listener: notify users who opted into a district ───────
// When a new product carries a `district`, every user whose
// `notification_preferences.interested_districts` array-contains it gets an
// in-app row + push. Push is additionally gated by the marketing channel and
// master switch via notificationPrefs (`new_product` maps to marketing).
function normalizeDistrict(district) {
  return String(district || '').trim();
}

function startDistrictProductListener() {
  console.log('[LISTENER] Starting district product listener...');
  let knownDistrictIds = new Set();
  const listenerStartedAt = admin.firestore.Timestamp.now();

  db.collection('products')
    .orderBy('createdAt', 'desc')
    .limit(200)
    .get()
    .then((snap) => {
      snap.docs.forEach((doc) => knownDistrictIds.add(doc.id));
      console.log(`[LISTENER] Loaded ${snap.docs.length} products for district matching`);
    })
    .catch((err) => console.error('[LISTENER] Failed to load products for district matching:', err.message));

  db.collection('products').onSnapshot(
    (snapshot) => {
      snapshot.docChanges().forEach((change) => {
        if (change.type !== 'added') return;
        const productId = change.doc.id;
        if (knownDistrictIds.has(productId)) return;
        const product = change.doc.data();
        const productTime = product.createdAt;
        if (productTime && productTime < listenerStartedAt) return;
        knownDistrictIds.add(productId);

        const district = normalizeDistrict(product.district);
        if (!district) return;
        const sellerId = product.sellerId;
        if (!sellerId) return;
        const sellerName = product.sellerName || 'Mfanyabiashara';
        const productName = product.name || 'bidhaa mpya';

        db.collection('notification_preferences')
          .where('interested_districts', 'array-contains', district)
          .get()
          .then((snap) => {
            const title = `Bidhaa Mpya katika ${district}!`;
            const body = `${sellerName} ameweka bidhaa mpya: ${productName} — katika ${district}.`;
            const data = { type: 'new_product', productId, sellerId, district };
            for (const doc of snap.docs) {
              const prefs = doc.data();
              if (prefs.district_new_products === false) continue;
              if (doc.id === sellerId) continue;
              db.collection('notifications').add({
                userId: doc.id, title, body,
                data, isRead: false,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
              }).catch(() => {});
              sendOsNotification(doc.id, title, body, data).catch(() => {});
            }
            if (snap.size > 0) {
              console.log(`[LISTENER] District "${district}": notified ${snap.size} interested users about product ${productId}`);
            }
          })
          .catch((err) => console.error('[LISTENER] District interest lookup error:', err.message));
      });
    },
    (error) => console.error('[LISTENER] District listener error:', error)
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
    startDistrictProductListener();
  });
