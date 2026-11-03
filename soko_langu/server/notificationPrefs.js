// Notification preference gating shared by index.js and listener.js.
//
// The client stores per-user preferences in Firestore `notification_preferences`
// (see notification.js). `general` is the master switch: when explicitly false,
// ALL push is suppressed regardless of the per-channel flags. Otherwise a push
// is allowed only when its mapped channel is not false.
const admin = require('firebase-admin');

const db = admin.firestore();

const CHANNELS = ['general', 'payments', 'orders', 'chat', 'marketing'];

// Map notification type -> preference channel. Unknown types fall back to
// `general` so they are only gated by the master switch.
const CHANNEL_BY_TYPE = {
  // payments
  payment: 'payments', payment_failed: 'payments', payment_received: 'payments',
  payout: 'payments', payout_completed: 'payments', payout_failed: 'payments',
  auto_payout: 'payments', auto_withdrawal: 'payments',
  withdrawal: 'payments', withdrawal_failed: 'payments',
  refund: 'payments', refund_processed: 'payments',
  dispute: 'payments', disputed: 'payments', dispute_resolved: 'payments',
  escrow_release: 'payments', escrow_auto_release: 'payments',
  kyc: 'payments', deposit: 'payments', deposit_failed: 'payments',
  delivery_confirmed: 'payments', cancelled: 'payments', paid: 'payments',
  // orders
  order: 'orders', order_placed: 'orders', order_dispatched: 'orders',
  order_delivered: 'orders', order_disputed: 'orders', dispatched: 'orders',
  // chat
  chat: 'chat', chat_message: 'chat', group_chat: 'chat', group_chat_message: 'chat',
  // marketing
  marketing: 'marketing', flash_sale: 'marketing', product_boost: 'marketing',
  boost: 'marketing', new_product: 'marketing', product: 'marketing',
  // system / everything else -> master-gated only
  system: 'general', admin: 'general', alert: 'general', account: 'general', general: 'general',
};

function typeToChannel(type) {
  return CHANNEL_BY_TYPE[type] || 'general';
}

async function getPrefs(userId) {
  try {
    const doc = await db.collection('notification_preferences').doc(userId).get();
    return doc.exists ? doc.data() : {};
  } catch (e) {
    console.error(`[PREFS] read error user=${userId}: ${e.message}`);
    return {};
  }
}

// Master switch: only `false` suppresses — missing/true keeps the channel active.
async function isPushAllowed(userId, type) {
  const prefs = await getPrefs(userId);
  if (prefs.general === false) return false;
  const channel = typeToChannel(type);
  if (channel === 'general') return true;
  return prefs[channel] !== false;
}

async function isSmsAllowed(userId) {
  const prefs = await getPrefs(userId);
  return prefs.sms_enabled !== false;
}

// Filter a user list down to those who may receive a push of this type.
// Used by bulk sends where OneSignal segments can't be preference-filtered.
async function filterAllowedUserIds(userIds, type) {
  if (!userIds || userIds.length === 0) return [];
  const channel = typeToChannel(type);
  const allowed = [];
  const BATCH = 400;
  for (let i = 0; i < userIds.length; i += BATCH) {
    const batch = userIds.slice(i, i + BATCH);
    let snaps;
    try {
      snaps = await db.getAll(...batch.map((id) => db.collection('notification_preferences').doc(id)));
    } catch (e) {
      console.error(`[PREFS] bulk read error: ${e.message}`);
      return allowed;
    }
    for (let j = 0; j < snaps.length; j++) {
      const prefs = snaps[j].exists ? snaps[j].data() : {};
      if (prefs.general === false) continue;
      if (channel !== 'general' && prefs[channel] === false) continue;
      allowed.push(batch[j]);
    }
  }
  return allowed;
}

module.exports = { CHANNELS, typeToChannel, getPrefs, isPushAllowed, isSmsAllowed, filterAllowedUserIds };
