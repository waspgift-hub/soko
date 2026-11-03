const axios = require('axios');
const config = require('../config');

/**
 * OneSignal Push Notification Service
 * Handles communication with OneSignal API to trigger heads-up notifications.
 */
class PushService {
  constructor() {
    this.appId = config.oneSignalAppId;
    this.restApiKey = process.env.ONESIGNAL_REST_API_KEY || config.oneSignalRestApiKey;
  }

  /**
   * Sends a push notification to a specific user using their External ID (Postgres userId).
   */
  async sendPush(userId, title, body, data = {}) {
    if (!this.appId || !this.restApiKey) {
      console.error('[PushService] Missing OneSignal configuration');
      return { success: false, error: 'CONFIG_MISSING' };
    }

    try {
      const response = await axios.post(
        'https://onesignal.com/api/v1/notifications',
        {
          app_id: this.appId,
          include_external_user_ids: [userId],
          headings: { 'en': title, 'sw': title }, // Simplified: usually uses translation keys
          contents: { 'en': body, 'sw': body },
          data: data,
        },
        {
          headers: {
            'Authorization': `Basic ${this.restApiKey}`,
            'Content-Type': 'application/json',
          },
        }
      );

      console.log(`[PushService] Push sent to ${userId}: ${response.data.id}`);
      return { success: true, id: response.data.id };
    } catch (error) {
      console.error('[PushService] Error sending push:', error.response?.data || error.message);
      return { success: false, error: error.message };
    }
  }

  /**
   * Sends a push notification to a segment (e.g., 'All Users').
   */
  async sendSegmentPush(segmentId, title, body, data = {}) {
    try {
      const response = await axios.post(
        'https://onesignal.com/api/v1/notifications',
        {
          app_id: this.appId,
          included_segments: [segmentId],
          headings: { 'en': title, 'sw': title },
          contents: { 'en': body, 'sw': body },
          data: data,
        },
        {
          headers: {
            'Authorization': `Basic ${this.restApiKey}`,
            'Content-Type': 'application/json',
          },
        }
      );
      return { success: true, id: response.data.id };
    } catch (error) {
      console.error('[PushService] Segment push error:', error.message);
      return { success: false, error: error.message };
    }
  }
}

module.exports = new PushService();
