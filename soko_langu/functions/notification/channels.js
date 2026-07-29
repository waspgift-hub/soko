const NOTIFICATION_CHANNELS = {
  general: {
    id: 'general_notifications_v5',
    name: 'Maelezo ya Jumla',
    description: 'Flash sale, announcements, alerts',
    importance: 'max',
  },
  payments: {
    id: 'payments_notifications_v5',
    name: 'Malipo',
    description: 'Malipo, escrow, payout, refund',
    importance: 'max',
  },
  chat: {
    id: 'chat_messages_v5',
    name: 'Chat Messages',
    description: 'New message notifications from chats',
    importance: 'max',
  },
  orders: {
    id: 'orders_notifications_v5',
    name: 'Orders',
    description: 'New orders, dispatch, delivery',
    importance: 'max',
  },
  rides: {
    id: 'ride_notifications_v5',
    name: 'Rides',
    description: 'Ride booking, driver matching, trip updates',
    importance: 'max',
  },
  marketing: {
    id: 'marketing_notifications_v5',
    name: 'Marketing',
    description: 'Promotions, flash sales, product boosts',
    importance: 'high',
  },
};

const NOTIFICATION_TYPES = {
  // Payments & Orders
  payment_received: { channel: 'payments', icon: 'account_balance_wallet' },
  payment_failed: { channel: 'payments', icon: 'warning_amber' },
  escrow_release: { channel: 'payments', icon: 'account_balance_wallet' },
  escrow_auto_release: { channel: 'payments', icon: 'account_balance_wallet' },
  payout_completed: { channel: 'payments', icon: 'check_circle' },
  payout_failed: { channel: 'payments', icon: 'error' },
  withdrawal_failed: { channel: 'payments', icon: 'error' },
  refund_processed: { channel: 'payments', icon: 'reply' },

  // Orders
  order_placed: { channel: 'orders', icon: 'shopping_bag' },
  order_dispatched: { channel: 'orders', icon: 'local_shipping' },
  order_delivered: { channel: 'orders', icon: 'check_circle' },
  order_disputed: { channel: 'orders', icon: 'gavel' },
  dispute_resolved: { channel: 'orders', icon: 'balance' },
  delivery_confirmed: { channel: 'orders', icon: 'check_circle' },

  // Rides
  ride_driver_found: { channel: 'rides', icon: 'directions_car' },
  ride_driver_accepted: { channel: 'rides', icon: 'directions_car' },
  ride_driver_arrived: { channel: 'rides', icon: 'location_on' },
  ride_trip_started: { channel: 'rides', icon: 'play_arrow' },
  ride_trip_completed: { channel: 'rides', icon: 'stop' },
  ride_cancelled: { channel: 'rides', icon: 'cancel' },
  ride_no_drivers: { channel: 'rides', icon: 'error_outline' },

  // Chat
  chat_message: { channel: 'chat', icon: 'chat' },
  group_chat_message: { channel: 'chat', icon: 'group' },

  // Marketing
  flash_sale: { channel: 'marketing', icon: 'flash_on' },
  product_boost: { channel: 'marketing', icon: 'rocket_launch' },
  new_product: { channel: 'marketing', icon: 'new_releases' },
};

module.exports = { NOTIFICATION_CHANNELS, NOTIFICATION_TYPES };
