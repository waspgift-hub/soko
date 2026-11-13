const axios = require('axios');
const config = require('../config');

/**
 * OneSignal Push Notification Service
 * Handles communication with OneSignal API to trigger heads-up notifications.
 */
class PushService {
  constructor() {
    this.appId = config.onesignal.appId;
    this.restApiKey = process.env.ONESIGNAL_REST_API_KEY || config.onesignal.apiKey;
    this.baseUrl = config.onesignal.baseUrl;
  }

  /**
   * Sends a push notification to a specific user using their External ID
   * (the app calls OneSignal.login(uid), so the Firebase UID is the alias).
   */
  async sendPush(userId, title, body, data = {}) {
    if (!this.appId || !this.restApiKey) {
      console.error('[PushService] Missing OneSignal configuration');
      return { success: false, error: 'CONFIG_MISSING' };
    }

    try {
      const response = await axios.post(
        `${this.baseUrl}/notifications`,
        {
          app_id: this.appId,
          include_external_user_ids: [userId],
          headings: { 'en': title, 'sw': title },
          contents: { 'en': body, 'sw': body },
          data: data,
        },
        {
          headers: {
            'Authorization': `Basic ${this.restApiKey}`,
            'Content-Type': 'application/json',
          },
          timeout: 10000,
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
        `${this.baseUrl}/notifications`,
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
          timeout: 10000,
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
