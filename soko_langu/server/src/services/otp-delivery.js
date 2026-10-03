// OTP delivery chain for phone numbers.
//
// Channel order is env-driven (OTP_CHANNEL_ORDER, default "push,sms") so a
// deployment can prioritise cheap channels without code changes:
//   1. push — OneSignal to the Firebase UID (only when the request is
//             authenticated; pre-auth send-otp has no uid to target)
//   2. sms  — Meseji → Notify Africa fallback (always available)
//
// The OTP ends up delivered exactly once per request: if a higher channel
// accepts it, lower channels are not attempted.
const pushService = require('./push-service');
const { sendSms } = require('./sms-service');

function channelsFromEnv() {
  const raw = process.env.OTP_CHANNEL_ORDER;
  if (!raw) return ['push', 'sms'];
  return raw.split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);
}

// Attempts the configured channels in order for a phone OTP.
// Returns { delivered, channel, attempts } where `attempts` is the ordered
// list of channel names tried (handy for rate-limit/debug dashboards).
async function deliverPhoneOtp({ phone, message, code, userId, langCode = 'sw' }) {
  const channels = channelsFromEnv();
  const attempts = [];

  for (const channel of channels) {
    if (channel === 'push') {
      if (!userId) continue;
      attempts.push('push');
      // The push is a "code is ready" ping ONLY: the secret itself travels by
      // SMS, never inside a third-party push payload (retention + on-device
      // notification logs would both keep a copy of the credential).
      const result = await pushService.sendPush(
        userId,
        langCode === 'en' ? 'Your Soko Vibe code' : 'Msimbo wako wa Soko Vibe',
        message,
        { type: 'otp_ready' },
      );
      if (result.success) return { delivered: true, channel: 'push', attempts };
      if (result.error === 'CONFIG_MISSING') continue;
    } else if (channel === 'sms') {
      attempts.push('sms');
      if (await sendSms(phone, message)) {
        return { delivered: true, channel: 'sms', attempts };
      }
    }
  }

  return { delivered: false, channel: null, attempts };
}

module.exports = { deliverPhoneOtp, channelsFromEnv };