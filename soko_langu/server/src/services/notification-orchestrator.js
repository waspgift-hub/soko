// Central Notification Orchestrator for Soko Vibe
// Handles: event categorization, user preferences, channel selection,
// localization, deduplication, retry, rate limiting, and delivery tracking.

const { ObjectId } = require('mongodb');
const Joi = require('joi');

// ---------------------------------------------------------------------------
// Event Catalogue — Categories and templates
// ---------------------------------------------------------------------------

const notificationCategories = {
  // A. SECURITY
  security: {
    name: 'SECURITY',
    description: 'Security-critical events requiring user attention',
    isTransactional: true,
    priority: 10,
    channels: {
      push: true,
      email: true,
      sms: false, // SMS only for high-risk
    },
  },
  // B. ACCOUNT
  account: {
    name: 'ACCOUNT',
    description: 'Account management events',
    isTransactional: true,
    priority: 8,
    channels: {
      push: true,
      email: true,
      sms: false,
    },
  },
  // C. VERIFICATION
  verification: {
    name: 'VERIFICATION',
    description: 'Email/phone/KYC verification events',
    isTransactional: true,
    priority: 9,
    channels: {
      push: true,
      email: true,
      sms: false,
    },
  },
  // D. PAYMENT
  payment: {
    name: 'PAYMENT',
    description: 'Payment success, failure, refund events',
    isTransactional: true,
    priority: 9,
    channels: {
      push: true,
      sms: true, // Important for payments
      email: true,
    },
  },
  // E. ORDER
  order: {
    name: 'ORDER',
    description: 'Order creation, shipping, completion events',
    isTransactional: true,
    priority: 7,
    channels: {
      push: true,
      sms: false,
      email: true,
    },
  },
  // F. ESCROW
  escrow: {
    name: 'ESCROW',
    description: 'Escrow held, released, shipment events',
    isTransactional: true,
    priority: 8,
    channels: {
      push: true,
      email: true,
      sms: false,
    },
  },
  // G. DELIVERY
  delivery: {
    name: 'DELIVERY',
    description: 'Delivery confirmation events',
    isTransactional: true,
    priority: 6,
    channels: {
      push: true,
      email: false,
      sms: false,
    },
  },
  // H. KYC
  kyc: {
    name: 'KYC',
    description: 'KYC submission, approval, rejection events',
    isTransactional: true,
    priority: 8,
    channels: {
      push: true,
      email: true,
      sms: false,
    },
  },
  // I. WALLET
  wallet: {
    name: 'WALLET',
    description: 'Wallet balance, deposit, withdrawal events',
    isTransactional: true,
    priority: 7,
    channels: {
      push: true,
      email: true,
      sms: false,
    },
  },
  // J. WITHDRAWAL
  withdrawal: {
    name: 'WITHDRAWAL',
    description: 'Withdrawal initiated, completed, failed events',
    isTransactional: true,
    priority: 8,
    channels: {
      push: true,
      sms: true, // Critical for user money
      email: true,
    },
  },
  // K. CHAT
  chat: {
    name: 'CHAT',
    description: 'New messages, reactions in chats',
    isTransactional: true,
    priority: 5,
    channels: {
      push: true,
      email: false,
      sms: false,
    },
  },
  // L. SELLER
  seller: {
    name: 'SELLER',
    description: 'Seller-specific events (listings, orders, sales)',
    isTransactional: true,
    priority: 6,
    channels: {
      push: true,
      email: true,
      sms: false,
    },
  },
  // M. BUYER
  buyer: {
    name: 'BUYER',
    description: 'Buyer-specific events',
    isTransactional: true,
    priority: 6,
    channels: {
      push: true,
      email: true,
      sms: false,
    },
  },
  // N. CUSTOMER SERVICE
  customerService: {
    name: 'CUSTOMER_SERVICE',
    description: 'Support, dispute, admin events',
    isTransactional: true,
    priority: 7,
    channels: {
      push: true,
      email: true,
      sms: false,
    },
  },
  // O. LIFECYCLE
  lifecycle: {
    name: 'LIFECYCLE',
    description: 'Onboarding, re-engagement, milestone events',
    isTransactional: false,
    priority: 3,
    channels: {
      push: true,
      email: false,
      sms: false,
    },
  },
  // P. RE-ENGAGEMENT
  reEngagement: {
    name: 'RE_ENGAGEMENT',
    description: 'Re-activation and retention journeys',
    isTransactional: false,
    priority: 4,
    channels: {
      push: true,
      email: false,
      sms: false,
    },
  },
  // Q. MARKETING
  marketing: {
    name: 'MARKETING',
    description: 'Promotional messages — requires explicit consent',
    isTransactional: false,
    priority: 1,
    channels: {
      push: false, // Only if user consented
      email: false, // Only if user consented
      sms: false, // Never SMS for marketing
    },
  },
};

// ---------------------------------------------------------------------------
// User Preferences Model
// ---------------------------------------------------------------------------

class UserPreferences {
  constructor(userId, prefsData = {}) {
    this.userId = userId;
    this.pushEnabled = prefsData.pushEnabled !== false;
    this.emailEnabled = prefsData.emailEnabled !== false;
    this.smsEnabled = prefsData.smsEnabled !== false;
    this.categoryPreferences = {
      ...notificationCategories,
      ...(prefsData.categoryPreferences || {}),
    };
    this.lastUpdated = new Date();
  }

  static async load(userId) {
    // Load from Firestore
    const db = require('../../config/firebase').getFirebaseFirestore();
    const doc = await db
      .collection('user_notification_preferences')
      .doc(userId)
      .get();

    if (doc.exists) {
      const data = doc.data();
      return new UserPreferences(userId, data);
    }

    // Return defaults
    return new UserPreferences(userId);
  }

  async save() {
    const db = require('../../config/firebase').getFirebaseFirestore();
    await db
      .collection('user_notification_preferences')
      .doc(this.userId)
      .set(this.toJSON(), { merge: true });
  }

  toJSON() {
    return {
      pushEnabled: this.pushEnabled,
      emailEnabled: this.emailEnabled,
      smsEnabled: this.smsEnabled,
      categoryPreferences: Object.assign(
        {},
        ...Object.entries(this.categoryPreferences).map(
          ([key, val]) => ({ [key]: val })
        )
      ),
    };
  }

  // Check if a specific channel is allowed for a category
  isChannelAllowed(category, channel) {
    const cat = notificationCategories[category];
    if (!cat) return true; // Default allow

    // First check category-level preference
    const pref = this.categoryPreferences[category];
    if (pref === false) return false; // Explicitly disabled

    // Then check channel availability in category definition
    const channelDef = cat.channels[channel];
    if (channelDef === undefined) return true; // Default allow

    return channelPref && channelDef ? channelPref : true;
  }
}

// ---------------------------------------------------------------------------
// Deduplication Store (in-memory with Firestore persistence)
// ---------------------------------------------------------------------------

class DeduplicationStore {
  constructor() {
    this.seenEvents = new Map(); // userId:eventId -> {sentAt, notificationId}
  }

  async recordSent({ userId, eventId, notificationId }) {
    const key = `${userId}:${eventId}`;
    const now = new Date();

    // Store in memory
    this.seenEvents.set(key, { sentAt: now, notificationId });

    // Persist to Firestore with TTL
    const db = require('../../config/firebase').getFirebaseFirestore();
    await db
      .collection('notification_dedup')
      .doc(key)
      .set({
        userId,
        eventId,
        notificationId,
        sentAt: now,
        expiresAt: new Date(now.getTime() + 24 * 60 * 60 * 1000), // 24h TTL
      });
  }

  async shouldSend({ userId, eventId }) {
    const key = `${userId}:${eventId}`;

    // Check memory
    const memoryResult = this.seenEvents.has(key)
      ? this.seenEvents.get(key).sentAt > new Date(Date.now() - 24 * 60 * 60 * 1000)
      : true;

    if (!memoryResult) return false; // Recently sent

    // Check Firestore with TTL
    const db = require('../../config/firebase').getFirebaseFirestore();
    const doc = await db.collection('notification_dedup').doc(key).get();

    if (doc.exists) {
      const sentAt = doc.data().sentAt.toDate();
      const diffHours = (new Date() - sentAt) / (1000 * 60 * 60);
      if (diffHours < 24) return false; // Within 24h window
    }

    // Clean up old entries (let Firestore TTL handle it)
    return true;
  }
}

// ---------------------------------------------------------------------------
// Rate Limiting
// ---------------------------------------------------------------------------

class RateLimiter {
  constructor() {
    this.cache = new Map(); // userId -> [timestamps]
  }

  // Check if user is within rate limit for a category
  check({ userId, category, windowMinutes }) {
    const now = DateTime.now().millisecondsSinceEpoch;
    if (!this.cache.has(userId)) {
      this.cache.set(userId, []);
    }

    const timestamps = this.cache.get(userId);
    // Remove timestamps outside the window
    const validTimestamps = timestamps.filter(
      ts => now - ts < windowMinutes * 60 * 1000
    );

    // Determine max based on category
    const maxPerWindow = this.maxForCategory(category, windowMinutes);
    if (validTimestamps.length >= maxPerWindow) {
      return false;
    }

    // Add current timestamp
    validTimestamps.push(now);
    this.cache.set(userId, validTimestamps);

    return true;
  }

  maxForCategory(category, windowMinutes) {
    // Transactional events have higher limits
    if (windowMinutes >= 1440) {
      // Per day
      return category === 'marketing' ? 20 : 100;
    }
    if (windowMinutes >= 60) {
      // Per hour
      return category === 'marketing' ? 10 : 30;
    }
    if (windowMinutes >= 30) {
      return 10;
    }
    return 3; // Per 15 min
  }
}

// ---------------------------------------------------------------------------
// Channel Selection Logic
// ---------------------------------------------------------------------------

function selectChannels(category, preferences, isUrgent = false) {
  const cat = notificationCategories[category];
  if (!cat) return [];

  const allowed = [];

  // Determine which channels to consider
  const candidates = isUrgent || cat.isTransactional
    ? ['push', 'email', 'sms']
    : ['push', 'email'];

  for (const channel of candidates) {
    // Check category definition
    const channelAllowed = cat.channels[channel];
    if (channelAllowed === false) continue;

    // Check user preferences
    const prefOk = preferences.isChannelAllowed(category, channel);
    if (!prefOk) continue;

    allowed.push(channel);
  }

  return allowed;
}

// ---------------------------------------------------------------------------
// Template Rendering (Localization)
// ---------------------------------------------------------------------------

const paymentTemplates = {
  sw: {
    success: 'Malipo yako ya {{amount}} yamepokelewa.',
    failed: 'Malipo yako ya {{amount}} hayakukamilika. Jaribu tena.',
    refunded: 'Fedha yako ya {{amount}} zimerudishwa kwenye salio lako.',
  },
  en: {
    success: 'Your payment of {{amount}} has been received.',
    failed: 'Your payment of {{amount}} did not complete. Try again.',
    refunded: 'Your payment of {{amount}} has been refunded to your balance.',
  },
};

const orderTemplates = {
  sw: {
    created: 'Umeandaliwa bidhaa cha #{{orderId}}. Toa gharama ya usafirishaji sasa.',
    shipped: 'Mnunuzi amefichushewa. Thaibitisha upokeaji ukishapata mzigo.',
    delivered: 'Umepokeaje bidhaa yako? Asante kwa kutumia Soko Vibe.',
    completed: 'Agizo lako limekamilika. Asante kwa kutumia Soko Vibe.',
  },
  en: {
    created: 'Your order #{{orderId}} has been placed. Set the shipping cost now.',
    shipped: '${m[1]} has been shipped. Confirm receipt once you receive the goods.',
    delivered: 'You have received your order. Thank you for buying on Soko Vibe.',
    completed: 'Your order has been completed. Thank you for buying on Soko Vibe.',
  },
};

// ... more templates for kyc, escrow, etc.

// ---------------------------------------------------------------------------
// Main Orchestrator Class
// ---------------------------------------------------------------------------

class NotificationOrchestrator {
  constructor() {
    this.dedup = new DeduplicationStore();
    this.rateLimiter = new RateLimiter();
    this.rateLimiterInstance = new RateLimiter();
    this.preferencesCache = new Map();
  }

  // Load user preferences
  async loadPreferences(userId) {
    if (this.preferencesCache.has(userId)) {
      return this.preferencesCache.get(userId);
    }
    const prefs = await UserPreferences.load(userId);
    this.preferencesCache.set(userId, prefs);
    return prefs;
  }

  // Send a notification event
  async sendEvent({ userId, eventType, eventData, language = 'en' }) {
    // 1. Build the notification event from the catalogue
    const event = this.buildEvent(eventType, eventData);
    if (!event) {
      debugPrint(`[Orchestrator] Unknown event type: ${eventType}`);
      return { success: false, error: 'unknown_event_type' };
    }

    // 2. Load user preferences
    const prefs = await this.loadPreferences(userId);

    // 3. Check deduplication
    const dedupOk = await this.dedup.shouldSend({
      userId,
      eventId: event.id,
    });
    if (!dedupOk) {
      debugPrint(`[Orchestrator] Duplicate event suppressed: ${event.id}`);
      return {
        success: false,
        suppressed: true,
        reason: 'duplicate_within_window',
      };
    }

    // 4. Check rate limits
    const rateOk = this.rateLimiter.check({
      userId,
      category: event.category,
      windowMinutes: this.rateWindow(event.category),
    });
    if (!rateOk) {
      debugPrint(`[Orchestrator] Rate limit exceeded for ${userId}`);
      return {
        success: false,
        suppressed: true,
        reason: 'rate_limit_exceeded',
      };
    }

    // 5. Select channels
    const channels = selectChannels(event.category, prefs, event.isTransactional);

    if (channels.length === 0) {
      debugPrint(`[Orchestrator] No channels allowed for ${event.category}`);
      return {
        success: false,
        suppressed: true,
        reason: 'no_allowed_channels',
      };
    }

    // 6. Render localized message
    const templateSet = this.getTemplateSet(event.category);
    const rendered = this.renderTemplate(templateSet, event.variables, language);

    // 7. Send via each channel (priority order)
    for (const channel of channels) {
      try {
        const result = await this.sendViaChannel({
          channel,
          userId,
          title: rendered.title,
          body: rendered.body,
          data: event.variables,
          event,
        });

        if (result.success) {
          // Record as sent
          await this.dedup.recordSent({
            userId,
            eventId: event.id,
            notificationId: result.notificationId,
          });

          // Update rate limit cache
          this.rateLimiterInstance.cache.get(userId).push(Date.now());

          return {
            success: true,
            notificationId: result.notificationId,
            channel,
            title: rendered.title,
            body: rendered.body,
          };
        }
      } catch (err) {
        debugPrint(`[Orchestrator] Channel ${channel} failed: ${err.message}`);
        continue; // Try next channel
      }
    }

    // All channels failed
    return {
      success: false,
      suppressed: false,
      reason: 'all_channels_failed',
      error: 'All selected channels failed',
    };
  }

  // Build event from catalogue
  buildEvent(type, data) {
    const templates = {
      paymentSuccess: {
        id: `payment_success_${Date.now()}`,
        type: 'payment_success',
        category: 'payment',
        titleKey: 'payment.success',
        bodyKey: undefined, // use title as body
        variables: { amount: data.amount },
        isTransactional: true,
      },
      orderCreated: {
        id: `order_created_${Date.now()}`,
        type: 'order_created',
        category: 'order',
        titleKey: 'order.created',
        variables: { orderId: data.orderId },
        isTransactional: true,
      },
      kycApproved: {
        id: `kyc_approved_${Date.now()}`,
        type: 'kyc_approved',
        category: 'kyc',
        titleKey: 'kyc.approved',
        variables: {},
        isTransactional: true,
      },
      kycRejected: {
        id: `kyc_rejected_${Date.now()}`,
        type: 'kyc_rejected',
        category: 'kyc',
        titleKey: 'kyc.rejected',
        variables: { reason: data.reason },
        isTransactional: true,
      },
      // Add more as needed
    };

    return templates[type] || null;
  }

  // Get template set for category
  getTemplateSet(category) {
    const sets = {
      payment: paymentTemplates,
      order: orderTemplates,
      kyc: kycTemplates,
    };
    return sets[category] || paymentTemplates; // fallback
  }

  // Render template with variables
  renderTemplate(templateSet, variables, language) {
    const langSet = templateSet[language] || templateSet.en;
    const titleKey = variables.titleKey || 'general.title';
    const bodyKey = variables.bodyKey || 'general.body';

    const title = langSet[titleKey] || titleKey;
    const body = langSet[bodyKey] || bodyKey;

    // Replace variables
    let resultTitle = title;
    let resultBody = body;

    for (const [key, value] of Object.entries(variables)) {
      if (key === 'titleKey' || key === 'bodyKey' || key === 'variables') continue;
      const regex = new RegExp(`{{${key}}}`, 'g');
      resultTitle = resultTitle.replace(regex, value);
      resultBody = resultBody.replace(regex, value);
    }

    return { title: resultTitle, body: resultBody };
  }

  // Send via specific channel
  async sendViaChannel({ channel, userId, title, body, data, event }) {
    switch (channel) {
      case 'push':
        return await this.sendPush(userId, title, body, data);
      case 'email':
        return await this.sendEmail(userId, title, body, data);
      case 'sms':
        return await this.sendSms(userId, title, body, data);
      default:
        return { success: false, error: 'unknown_channel' };
    }
  }

  // Push via OneSignal
  async sendPush(userId, title, body, data) {
    // Use existing OneSignal integration
    const onesignal = require('./push-service');
    const result = await onesignal.sendPush(userId, title, body, data);
    return result;
  }

  // Email via mailer service
  async sendEmail(userId, title, body, data) {
    // Use existing mailer service
    // Would call server-side /api/send-mail
    try {
      // For now, simulate success if email enabled
      return {
        success: true,
        notificationId: `email_${Date.now()}`,
        providerMessageId: `msg_${Date.now()}`,
      };
    } catch (e) {
      return { success: false, error: e.message };
    }
  }

  // SMS via Meseji/NotifyAfrica
  async sendSms(userId, title, body, data) {
    // Use existing SMS service
    // Would call server-side sms-service
    try {
      // For now, simulate success if SMS enabled
      return {
        success: true,
        notificationId: `sms_${Date.now()}`,
        providerMessageId: `sms_${Date.now()}`,
      };
    } catch (e) {
      return { success: false, error: e.message };
    }
  }

  // Rate window per category
  rateWindow(category) {
    const windows = {
      security: 60,    // per hour
      payment: 30,     // per 30 min
      order: 60,       // per hour
      kyc: 1440,       // per day
      escrow: 60,      // per hour
      delivery: 1440,  // per day
      chat: 30,        // per 30 min
      seller: 60,      // per hour
      buyer: 60,       // per hour
      customerService: 60,
      lifecycle: 1440, // per day
      reEngagement: 1440,
      marketing: 1440, // per day
    };
    return windows[category] || 60;
  }

  // Delayed send (for journeys)
  async sendDelayed({ userId, eventType, eventData, delayMs, language = 'en' }) {
    await new Promise(resolve => setTimeout(resolve, delayMs));
    return await this.sendEvent({
      userId,
      eventType,
      eventData,
      language,
    });
  }

  // Cancel a pending journey
  cancelJourney(journeyId) {
    // Remove from tracking
  }
}

module.exports = new NotificationOrchestrator();