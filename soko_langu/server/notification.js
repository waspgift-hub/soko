const express = require('express');
const admin = require('firebase-admin');

const router = express.Router();
const db = admin.firestore();

const NOTIFICATION_CHANNELS = {
  general: { id: 'general_notifications_v5', name: 'Maelezo ya Jumla' },
  payments: { id: 'payments_notifications_v5', name: 'Malipo' },
  chat: { id: 'chat_messages_v5', name: 'Chat Messages' },
  orders: { id: 'orders_notifications_v5', name: 'Orders' },
  rides: { id: 'ride_notifications_v5', name: 'Rides' },
  marketing: { id: 'marketing_notifications_v5', name: 'Marketing' },
};

const NOTIFICATION_TYPES = {
  payment_received: { channel: 'payments' },
  payment_failed: { channel: 'payments' },
  escrow_release: { channel: 'payments' },
  escrow_auto_release: { channel: 'payments' },
  payout_completed: { channel: 'payments' },
  payout_failed: { channel: 'payments' },
  withdrawal_failed: { channel: 'payments' },
  refund_processed: { channel: 'payments' },
  order_placed: { channel: 'orders' },
  order_dispatched: { channel: 'orders' },
  order_delivered: { channel: 'orders' },
  order_disputed: { channel: 'orders' },
  dispute_resolved: { channel: 'orders' },
  delivery_confirmed: { channel: 'orders' },
  ride_driver_found: { channel: 'rides' },
  ride_driver_accepted: { channel: 'rides' },
  ride_driver_arrived: { channel: 'rides' },
  ride_trip_started: { channel: 'rides' },
  ride_trip_completed: { channel: 'rides' },
  ride_cancelled: { channel: 'rides' },
  ride_no_drivers: { channel: 'rides' },
  chat_message: { channel: 'chat' },
  group_chat_message: { channel: 'chat' },
  flash_sale: { channel: 'marketing' },
  product_boost: { channel: 'marketing' },
  new_product: { channel: 'marketing' },
};

async function authenticate(req) {
  const authHeader = req.headers.authorization || req.headers['Authorization'] || '';
  if (!authHeader.startsWith('Bearer ')) return null;
  try {
    return await admin.auth().verifyIdToken(authHeader.slice(7));
  } catch { return null; }
}

// ════════════════════════════════════════════════════════════
// GET NOTIFICATION PREFERENCES
// ════════════════════════════════════════════════════════════
router.post('/preferences/get', async (req, res) => {
  try {
    const decoded = await authenticate(req);
    if (!decoded) return res.status(401).json({ error: 'Unauthorized' });
    const doc = await db.collection('notification_preferences').doc(decoded.uid).get();
    const defaults = {};
    for (const key of Object.keys(NOTIFICATION_CHANNELS)) defaults[key] = true;
    for (const key of Object.keys(NOTIFICATION_TYPES)) defaults[key] = true;
    defaults['sms_enabled'] = true;
    const preferences = doc.exists ? { ...defaults, ...doc.data() } : defaults;
    res.json({ preferences });
  } catch (e) {
    console.error('[NOTIFY] preferences get error:', e.message);
    res.status(400).json({ error: e.message });
  }
});

// ════════════════════════════════════════════════════════════
// SET NOTIFICATION PREFERENCES
// ════════════════════════════════════════════════════════════
router.post('/preferences/set', async (req, res) => {
  try {
    const decoded = await authenticate(req);
    if (!decoded) return res.status(401).json({ error: 'Unauthorized' });
    const { preferences } = req.body;
    if (!preferences || typeof preferences !== 'object') {
      return res.status(400).json({ error: 'preferences object required' });
    }
    await db.collection('notification_preferences').doc(decoded.uid).set(preferences, { merge: true });
    res.json({ success: true });
  } catch (e) {
    console.error('[NOTIFY] preferences set error:', e.message);
    res.status(400).json({ error: e.message });
  }
});

module.exports = { router };
