'use strict';

// Android channel IDs are immutable after first creation. Every OneSignal
// sender must use this map so pushes land in the same channels the app creates.
const CHANNELS = Object.freeze({
  GENERAL: 'general_notifications_v6',
  PAYMENTS: 'payments_notifications_v6',
  CHAT: 'chat_messages_v6',
  SYSTEM: 'system_alerts_v6',
  RIDE: 'ride_notifications_v6',
});

const PAYMENT_TYPES = new Set([
  'payment',
  'payment_failed',
  'refund',
  'cancelled',
  'withdrawal',
  'auto_withdrawal',
  'escrow_release',
  'escrow_auto_release',
  'dispute',
  'dispute_resolved',
  'auto_payout',
  'payout',
  'order',
  'order_update',
  'dispatched',
  'delivery_confirmed',
  'kyc',
  'kyc_approved',
  'kyc_rejected',
  'kyc_revoked',
  'deposit',
  'deposit_failed',
]);

function notificationChannelForType(type) {
  const value = typeof type === 'string' ? type : 'general';
  if (value === 'chat' || value === 'group_chat') return CHANNELS.CHAT;
  if (value === 'system' || value === 'admin' || value === 'alert') {
    return CHANNELS.SYSTEM;
  }
  if (value === 'ride' || value === 'ride_request' || value === 'trip_update') {
    return CHANNELS.RIDE;
  }
  if (PAYMENT_TYPES.has(value)) return CHANNELS.PAYMENTS;
  return CHANNELS.GENERAL;
}

function oneSignalHeadsUpOptions(type) {
  return {
    priority: 10,
    android_priority: 'high',
    android_visibility: 1,
    existing_android_channel_id: notificationChannelForType(type),
    android_sound: 'soko_notification',
    android_icon: 'ic_notification',
  };
}

module.exports = {
  CHANNELS,
  notificationChannelForType,
  oneSignalHeadsUpOptions,
};
