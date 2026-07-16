// DEPRECATED: This file is no longer deployed to Firebase Functions.
// All functionality (webhooks + Firestore notification listeners) now runs
// directly on the Render Express server via server/index.js and server/listener.js.
// Kept only as a reference.
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const FIELD_VALUE = admin.firestore.FieldValue;

const MONGIKE_COLLECTION_FEE = 180;
const MONGIKE_PAYOUT_FEE = 2000;
const PLATFORM_COMMISSION_RATE = 0.035;

async function notifyUser(uid, title, body, data) {
  const topic = `user_${uid}`;
  const msg = {
    topic,
    notification: { title, body },
    data: Object.fromEntries(
      Object.entries(data || {}).map(([k, v]) => [k, String(v)])
    ),
    android: { priority: 'high', notification: { sound: 'default' } },
    apns: { payload: { aps: { sound: 'default' } } },
  };
  try {
    await admin.messaging().send(msg);
  } catch {
    try {
      const userDoc = await db.collection('users').doc(uid).get();
      const token = userDoc.data()?.fcmToken;
      if (token) {
        await admin.messaging().send({ ...msg, topic: undefined, token });
      }
    } catch {
      // Token may be stale — ignore
    }
  }
  try {
    await db.collection('notifications').add({
      userId: uid,
      title,
      body,
      data: data || {},
      isRead: false,
      createdAt: FIELD_VALUE.serverTimestamp(),
    });
  } catch {
    // Non-critical
  }
}

function calculateSellerCredit(grossAmount) {
  const amount = Number(grossAmount);
  if (isNaN(amount) || amount <= 0) return 0;
  const commission = Math.round(amount * PLATFORM_COMMISSION_RATE);
  const net = amount - MONGIKE_COLLECTION_FEE - commission;
  return Math.max(net, 0);
}

function verifyMongikeSignature(req) {
  const signature = req.headers['x-signature'];
  if (signature) {
    return true;
  }
  const webhookSecret = req.headers['x-webhook-secret'];
  const expected = process.env.WEBHOOK_SECRET || '';
  if (webhookSecret && expected) {
    return webhookSecret === expected;
  }
  console.warn('Mongike webhook: no signature or secret provided — accepting anyway');
  return true;
}

exports.mongikeWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  if (!verifyMongikeSignature(req)) {
    console.error('Mongike webhook: invalid signature');
    res.status(401).send('Invalid signature');
    return;
  }

  const payload = req.body || {};
  const rawStatus = (payload.payment_status || payload.status || payload.paymentStatus || payload.event || '').toLowerCase();
  const status = rawStatus === 'completed' || rawStatus === 'success' || rawStatus === 'payment_received'
    ? 'success'
    : rawStatus === 'failed' || rawStatus === 'cancelled' || rawStatus === 'expired'
      ? 'failed'
      : rawStatus;
  const orderId = payload.order_id || payload.orderReference || payload.externalId || '';
  const grossAmount = Number(payload.amount || 0);
  const mongikeRef = payload.reference || payload.id || payload.transactionId || '';

  console.log(`Mongike webhook: orderId=${orderId}, status=${status}, amount=${grossAmount}, ref=${mongikeRef}`);

  if (!orderId) {
    res.status(400).send('Missing order_id');
    return;
  }

  try {
    await db.runTransaction(async (transaction) => {
      const txRef = db.collection('transactions').doc(orderId);
      const txSnap = await transaction.get(txRef);

      if (!txSnap.exists) {
        throw new Error(`Transaction ${orderId} not found`);
      }

      const txData = txSnap.data();

      if (txData.status === 'paid' || txData.status === 'escrow_hold' || txData.status === 'completed') {
        console.log(`Mongike webhook: transaction ${orderId} already processed`);
        return;
      }

      if (status === 'success') {
        const sellerId = txData.sellerId;
        const buyerId = txData.buyerId;
        const productName = txData.productName || 'Product';

        if (!sellerId) {
          throw new Error(`Transaction ${orderId} has no sellerId`);
        }

        const sellerCredit = calculateSellerCredit(grossAmount);
        const commission = Math.round(grossAmount * PLATFORM_COMMISSION_RATE);

        transaction.update(txRef, {
          status: 'escrow_hold',
          paidAt: FIELD_VALUE.serverTimestamp(),
          grossAmount: grossAmount,
          mongikeFee: MONGIKE_COLLECTION_FEE,
          platformCommission: commission,
          sellerReceives: sellerCredit,
          mongikeReference: mongikeRef,
          updatedAt: FIELD_VALUE.serverTimestamp(),
        });

        const sellerRef = db.collection('users').doc(sellerId);
        transaction.update(sellerRef, {
          pendingEscrow: FIELD_VALUE.increment(sellerCredit),
          totalSales: FIELD_VALUE.increment(1),
          grossSalesVolume: FIELD_VALUE.increment(grossAmount),
        });

        const revenueRef = db.collection('revenue_transactions').doc();
        transaction.set(revenueRef, {
          type: 'commission',
          transactionId: orderId,
          amount: commission,
          sellerId,
          buyerId,
          mongikeRef,
          createdAt: FIELD_VALUE.serverTimestamp(),
        });

        await notifyUser(
          sellerId,
          'Payment Received',
          `You received TSh ${sellerCredit.toLocaleString()} for ${productName} (after fees). Item is in escrow until buyer confirms.`,
          { type: 'order', transactionId: orderId, productName }
        );

        if (buyerId) {
          await notifyUser(
            buyerId,
            'Payment Successful',
            `Your payment of TSh ${grossAmount.toLocaleString()} for ${productName} is complete. The seller will dispatch shortly.`,
            { type: 'order', transactionId: orderId, productName }
          );
        }

        console.log(`Mongike webhook: processed ${orderId} — gross=${grossAmount}, fee=${MONGIKE_COLLECTION_FEE}, commission=${commission}, sellerCredit=${sellerCredit}`);
      } else if (status === 'failed') {
        transaction.update(txRef, {
          status: 'failed',
          mongikeReference: mongikeRef,
          failedAt: FIELD_VALUE.serverTimestamp(),
          updatedAt: FIELD_VALUE.serverTimestamp(),
        });

        const buyerId = txData.buyerId;
        if (buyerId) {
          await notifyUser(
            buyerId,
            'Payment Failed',
            `Your payment for ${txData.productName || 'product'} could not be processed. Please try again.`,
            { type: 'order', transactionId: orderId }
          );
        }

        console.log(`Mongike webhook: transaction ${orderId} marked as failed`);
      } else {
        console.log(`Mongike webhook: unknown status "${status}" for ${orderId} — ignoring`);
      }
    });

    res.status(200).json({ received: true });
  } catch (error) {
    console.error(`Mongike webhook error for ${orderId}:`, error.message);
    res.status(500).json({ error: error.message });
  }
});

exports.mongikePayoutWebhook = functions.https.onRequest(async (req, res) => {
  if (req.method !== 'POST') {
    res.status(405).send('Method Not Allowed');
    return;
  }

  if (!verifyMongikeSignature(req)) {
    console.error('Mongike payout webhook: invalid signature');
    res.status(401).send('Invalid signature');
    return;
  }

  const payload = req.body || {};
  const rawStatus = (payload.payment_status || payload.status || payload.paymentStatus || '').toLowerCase();
  const status = rawStatus === 'completed' || rawStatus === 'success'
    ? 'success'
    : rawStatus === 'failed' || rawStatus === 'cancelled'
      ? 'failed'
      : rawStatus;
  const payoutRef = payload.orderReference || payload.order_id || payload.externalReference || '';
  const amount = Number(payload.amount || 0);
  const mongikeTxnId = payload.reference || payload.id || payload.transactionId || '';

  console.log(`Mongike payout webhook: ref=${payoutRef}, status=${status}, amount=${amount}`);

  if (!payoutRef) {
    res.status(400).send('Missing reference');
    return;
  }

  try {
    await db.runTransaction(async (transaction) => {
      const payoutRef_ = db.collection('payouts').doc(payoutRef);
      const payoutSnap = await transaction.get(payoutRef_);

      if (!payoutSnap.exists) {
        throw new Error(`Payout ${payoutRef} not found`);
      }

      const payoutData = payoutSnap.data();

      if (payoutData.status === 'completed' || payoutData.status === 'failed') {
        console.log(`Payout ${payoutRef} already finalized (${payoutData.status})`);
        return;
      }

      if (status === 'success') {
        transaction.update(payoutRef_, {
          status: 'completed',
          mongikeReference: mongikeTxnId,
          completedAt: FIELD_VALUE.serverTimestamp(),
          updatedAt: FIELD_VALUE.serverTimestamp(),
        });

        if (payoutData.payoutType === 'admin') {
          const adminWRef = db.collection('admin_withdrawals').doc(payoutRef);
          transaction.update(adminWRef, {
            status: 'completed',
            mongikeReference: mongikeTxnId,
            completedAt: FIELD_VALUE.serverTimestamp(),
          });
        } else {
          const wRef = db.collection('withdrawals').doc(payoutRef);
          transaction.update(wRef, {
            status: 'completed',
            mongikeReference: mongikeTxnId,
            completedAt: FIELD_VALUE.serverTimestamp(),
          });
        }

        console.log(`Payout ${payoutRef} completed successfully`);
      } else if (status === 'failed') {
        const userId = payoutData.userId || payoutData.sellerId;
        const failedAmount = payoutData.amount || amount;
        const reversalAmount = failedAmount + MONGIKE_PAYOUT_FEE;

        transaction.update(payoutRef_, {
          status: 'failed',
          mongikeReference: mongikeTxnId,
          failedAt: FIELD_VALUE.serverTimestamp(),
          updatedAt: FIELD_VALUE.serverTimestamp(),
        });

        if (userId) {
          const userRef = db.collection('users').doc(userId);
          transaction.update(userRef, {
            sellerBalance: FIELD_VALUE.increment(reversalAmount),
          });
        }

        const wRef = db.collection('withdrawals').doc(payoutRef);
        transaction.update(wRef, {
          status: 'failed',
          mongikeReference: mongikeTxnId,
          failedAt: FIELD_VALUE.serverTimestamp(),
        });

        await notifyUser(
          userId,
          'Withdrawal Failed',
          `Your withdrawal of TSh ${failedAmount.toLocaleString()} could not be processed. The amount has been returned to your wallet.`,
          { type: 'payment' }
        );

        console.log(`Payout ${payoutRef} failed — funds reversed to user ${userId}`);
      }
    });

    res.status(200).json({ received: true });
  } catch (error) {
    console.error(`Mongike payout webhook error:`, error.message);
    res.status(500).json({ error: error.message });
  }
});

exports.notifyOnNewProduct = functions.firestore
  .document('products/{productId}')
  .onCreate(async (snap, context) => {
    const product = snap.data();
    const sellerId = product.sellerId;
    if (!sellerId) return;
    const sellerName = product.sellerName || 'Mfanyabiashara';
    const productName = product.name || 'bidhaa mpya';

    const roomsSnap = await db
      .collection('chat_rooms')
      .where('participants', 'array-contains', sellerId)
      .get();

    const notified = new Set();
    for (const roomDoc of roomsSnap.docs) {
      const room = roomDoc.data();
      const other = room.participants.find((p) => p !== sellerId);
      if (!other || notified.has(other)) continue;
      notified.add(other);
      await notifyUser(
        other,
        sellerName,
        `${sellerName} ameweka bidhaa mpya: ${productName}. Umewahi kushirikiana nao hivi karibuni.`,
        { type: 'product', productId: context.params.productId, sellerId }
      );
    }
  });

exports.notifyOnNewMessage = functions.firestore
  .document('chat_rooms/{roomId}/messages/{messageId}')
  .onCreate(async (snap, context) => {
    const message = snap.data();
    const senderId = message.sender_id || message.senderId;
    const text = message.text || message.content || '';
    if (!senderId) return;

    const roomId = context.params.roomId;
    const roomSnap = await db.collection('chat_rooms').doc(roomId).get();
    if (!roomSnap.exists) return;
    const room = roomSnap.data();
    const recipientId = room.participants.find((p) => p !== senderId);
    if (!recipientId) return;

    const senderDoc = await db.collection('users').doc(senderId).get();
    const senderName =
      senderDoc.data()?.displayName ||
      senderDoc.data()?.name ||
      'Mtumiaji';

    await notifyUser(recipientId, senderName, text, {
      type: 'chat',
      senderId,
      senderName,
      roomId,
      messageId: context.params.messageId,
    });
  });

exports.notifyOnPurchase = functions.firestore
  .document('transactions/{transactionId}')
  .onCreate(async (snap, context) => {
    const tx = snap.data();
    if (tx.type !== 'purchase') return;

    const sellerId = tx.sellerId;
    const buyerId = tx.buyerId;
    const productName = tx.productName || 'bidhaa';
    const buyerName = tx.buyerName || 'Mnunuzi';
    const sellerName = tx.sellerName || 'Mfanyabiashara';

    if (sellerId) {
      await notifyUser(
        sellerId,
        'Agizo Jipya',
        `${buyerName} amenunua ${productName}. Tayarisha bidhaa kwa usafirishaji.`,
        {
          type: 'order',
          transactionId: context.params.transactionId,
          productName,
          buyerId,
        }
      );
    }

    if (buyerId) {
      await notifyUser(
        buyerId,
        'Agizo Limewekwa',
        `Umeweka agizo la ${productName} kutoka kwa ${sellerName}. Tunakusaidia kufuatilia.`,
        {
          type: 'order',
          transactionId: context.params.transactionId,
          productName,
          sellerId,
        }
      );
    }
  });
