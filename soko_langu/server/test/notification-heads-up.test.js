const test = require('node:test');
const assert = require('node:assert/strict');

process.env.ONE_SIGNAL_APP_ID = process.env.ONE_SIGNAL_APP_ID || 'test-app-id';
process.env.ONE_SIGNAL_REST_API_KEY =
  process.env.ONE_SIGNAL_REST_API_KEY || 'test-rest-key';
process.env.ONE_SIGNAL_BASE_URL =
  'https://onesignal.test/api/v1';

const axios = require('axios');
const {
  CHANNELS,
  notificationChannelForType,
  oneSignalHeadsUpOptions,
} = require('../src/utils/notification-channels');

test('notification types map to v6 heads-up channels', () => {
  assert.equal(notificationChannelForType('chat'), CHANNELS.CHAT);
  assert.equal(notificationChannelForType('group_chat'), CHANNELS.CHAT);
  assert.equal(notificationChannelForType('payment'), CHANNELS.PAYMENTS);
  assert.equal(notificationChannelForType('order'), CHANNELS.PAYMENTS);
  assert.equal(notificationChannelForType('dispatched'), CHANNELS.PAYMENTS);
  assert.equal(notificationChannelForType('kyc'), CHANNELS.PAYMENTS);
  assert.equal(notificationChannelForType('alert'), CHANNELS.SYSTEM);
  assert.equal(notificationChannelForType('ride_request'), CHANNELS.RIDE);
  assert.equal(notificationChannelForType('flash_sale'), CHANNELS.GENERAL);
  assert.equal(notificationChannelForType(undefined), CHANNELS.GENERAL);
});

test('OneSignal options force a high-priority public heads-up', () => {
  const options = oneSignalHeadsUpOptions('chat');

  assert.equal(options.priority, 10);
  assert.equal(options.android_priority, 'high');
  assert.equal(options.android_visibility, 1);
  assert.equal(options.existing_android_channel_id, CHANNELS.CHAT);
  assert.equal(options.android_sound, 'soko_notification');
  assert.equal(options.android_icon, 'ic_notification');
});

test('PushService targets the Firebase UID as an external id', async () => {
  const originalPost = axios.post;
  const calls = [];
  axios.post = async (...args) => {
    calls.push(args);
    return { data: { id: 'push-1' } };
  };

  try {
    const pushService = require('../src/services/push-service');
    const result = await pushService.sendPush('user-1', 'Malipo', 'Paid', {
      type: 'payment',
      orderId: 'ord-1',
    });

    assert.deepEqual(result, { success: true, id: 'push-1' });
    assert.equal(calls.length, 1);
    const [url, payload, options] = calls[0];
    assert.equal(url, 'https://onesignal.test/api/v1/notifications');
    assert.deepEqual(payload.include_external_user_ids, ['user-1']);
    assert.equal(payload.channel_for_external_user_ids, 'push');
    assert.equal(payload.data.type, 'payment');
    assert.equal(payload.data.orderId, 'ord-1');
    assert.equal(
      payload.existing_android_channel_id,
      CHANNELS.PAYMENTS,
    );
    assert.equal(payload.android_priority, 'high');
    assert.equal(payload.android_sound, 'soko_notification');
    assert.equal(options.headers.Authorization, 'Basic test-rest-key');
  } finally {
    axios.post = originalPost;
  }
});

test('PushService segment sends keep the same heads-up channel metadata',
  async () => {
    const originalPost = axios.post;
    const calls = [];
    axios.post = async (...args) => {
      calls.push(args);
      return { data: { id: 'segment-1' } };
    };

    try {
      const pushService = require('../src/services/push-service');
      const result = await pushService.sendSegmentPush(
        'All',
        'Taarifa',
        'Update',
        { type: 'system' },
      );

      assert.deepEqual(result, { success: true, id: 'segment-1' });
      const payload = calls[0][1];
      assert.deepEqual(payload.included_segments, ['All']);
      assert.equal(payload.existing_android_channel_id, CHANNELS.SYSTEM);
      assert.equal(payload.android_visibility, 1);
    } finally {
      axios.post = originalPost;
    }
  });
