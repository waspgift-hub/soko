'use strict';

const { Router } = require('express');
const crypto = require('crypto');
const { getFirebaseFirestore } = require('../../config/firebase');
const settingsService = require('../admin/settings-service');
const {
  DEFAULT_TZ,
  localDayKey,
  campaignId,
  isEligibleUser,
  buildMessages,
  validateOutbound,
} = require('./daily-campaign');

const router = Router();
const BATCH = 40;

function verifyCronSecret(secret) {
  const expected = process.env.CRON_SECRET || process.env.ADMIN_SECRET;
  if (!expected || !secret) return false;
  const a = Buffer.from(String(secret));
  const b = Buffer.from(String(expected));
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function makeUnsubscribeToken(userId) {
  const secret = process.env.UNSUBSCRIBE_SECRET || process.env.ADMIN_SECRET || process.env.CRON_SECRET || '';
  if (!secret) return '';
  return crypto.createHmac('sha256', secret).update(String(userId)).digest('base64url');
}

function verifyUnsubscribeToken(userId, token) {
  if (!token || !userId) return false;
  const expected = makeUnsubscribeToken(userId);
  if (!expected) return false;
  const a = Buffer.from(String(token));
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

async function processCampaign({ db, cfg, now, timeZone, dayKey, dryRun, limit }) {
  const usersSnap = await db.collection('users').limit(limit).get();
  let prepared = 0;
  let sent = 0;
  let skipped = 0;

  for (const doc of usersSnap.docs) {
    const user = { id: doc.id, ...doc.data() };
    const prefsSnap = await db.collection('notification_preferences').doc(doc.id).get();
    const prefs = prefsSnap.exists ? prefsSnap.data() : {};
    if (!isEligibleUser({
      lastLoginAt: toDate(user.lastLoginAt),
      prefs,
      now,
      timeZone,
    })) {
      skipped += 1;
      continue;
    }

    const id = campaignId(doc.id, dayKey);
    const existing = await db.collection('daily_campaigns').doc(id).get();
    if (existing.exists) {
      skipped += 1;
      continue;
    }

    const locale = user.langCode === 'en' ? 'en' : 'sw';
    const message = buildMessages({ locale, feature: 'search' });
    if (!validateOutbound(message)) {
      skipped += 1;
      continue;
    }

    prepared += 1;
    if (dryRun) continue;

    const channelPlan = {
      email: cfg.channels?.email !== false,
      push: cfg.channels?.push !== false,
      sms: false,
    };
    const delivery = { email: 'skipped', push: 'skipped' };

    const unsubToken = makeUnsubscribeToken(doc.id);
    const unsubUrl = unsubToken
      ? `https://www.sokovibe.co.tz/api/v1/unsubscribe?token=${unsubToken}&uid=${encodeURIComponent(doc.id)}`
      : 'https://www.sokovibe.co.tz';

    if (channelPlan.email && user.email) {
      try {
        const { sendMail } = require('../../services/mailer');
        const dest = `https://www.sokovibe.co.tz${message.destination}`;
        const html = `<p>${String(message.emailBody).replace(/[<>]/g, '')}</p><p><a href="${dest}">Soko Vibe</a></p><p style="font-size:12px;color:#888;margin-top:24px">Huwezi kupokea barua hizi tena? <a href="${unsubUrl}">Jiondoe hapa</a>.</p>`;
        const ok = await sendMail(user.email, message.subject, html, undefined, {
          headers: {
            'Precedence': 'bulk',
            'X-Mailer': 'Soko Vibe',
            'List-Unsubscribe': `<${unsubUrl}>`,
            'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
          },
        });
        delivery.email = ok ? 'accepted' : 'failed';
      } catch (_) {
        delivery.email = 'failed';
      }
    }
    if (channelPlan.push) {
      try {
        const push = require('../../services/push-service');
        const uid = user.firebaseUid || doc.id;
        const r = await push.sendPush(uid, message.pushTitle, message.pushBody, {
          type: 'daily_engagement',
          destination: message.destination,
        });
        delivery.push = r && r.success ? 'accepted' : (r && r.error) || 'failed';
      } catch (_) {
        delivery.push = 'failed';
      }
    }

    await db.collection('daily_campaigns').doc(id).set({
      userId: doc.id,
      dayKey,
      status: 'attempted',
      channels: channelPlan,
      delivery,
      message,
      createdAt: now,
    });
    sent += 1;
  }

  return { prepared, recorded: sent, skipped };
}

router.post('/cron/daily-engagement', async (req, res) => {
  if (!verifyCronSecret(req.headers['x-cron-secret'])) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const settings = await settingsService.getSettings();
  const cfg = settings.dailyEngagement || {};
  if (cfg.enabled === false) {
    return res.json({
      success: true,
      skipped: true,
      reason: 'paused',
    });
  }

  const db = getFirebaseFirestore();
  if (!db) {
    return res.status(503).json({ error: 'Database not configured' });
  }

  const now = new Date();
  const timeZone = cfg.timezone || DEFAULT_TZ;
  const dayKey = localDayKey(now, timeZone);
  const dryRun = req.body?.dryRun === true;
  const limit = Math.min(Number(req.body?.limit) || BATCH, 200);

  // Dry runs are fast (no sending) — answer synchronously.
  if (dryRun) {
    const result = await processCampaign({ db, cfg, now, timeZone, dayKey, dryRun: true, limit });
    return res.json({
      success: true,
      dayKey,
      prepared: result.prepared,
      recorded: result.recorded,
      skipped: result.skipped,
      dryRun: true,
      note: 'Live channel send runs only when dailyEngagement.enabled is true.',
    });
  }

  // Live sends can take a while (one mail per user). Respond immediately and
  // process in the background so the caller (cron/Render) does not time out.
  res.status(202).json({
    success: true,
    started: true,
    dayKey,
    note: 'Processing in background. Counts are not returned synchronously.',
  });

  processCampaign({ db, cfg, now, timeZone, dayKey, dryRun: false, limit })
    .then((result) => {
      console.log('[DAILY-ENGAGEMENT] finished:', JSON.stringify(result));
    })
    .catch((e) => {
      console.error('[DAILY-ENGAGEMENT] failed:', e?.message || e);
    });
});

// One-click unsubscribe for marketing/daily-engagement emails.
router.get('/unsubscribe', async (req, res) => {
  const token = String(req.query.token || '');
  const uid = String(req.query.uid || '');
  if (!uid || !verifyUnsubscribeToken(uid, token)) {
    return res.status(400).send('<!doctype html><html><body style="font-family:sans-serif;padding:40px"><h1>Linki si sahihi</h1><p>Linki ya kuondoa imeisha au si sahihi.</p></body></html>');
  }
  try {
    const db = getFirebaseFirestore();
    if (db) {
      const ref = db.collection('notification_preferences').doc(uid);
      await ref.set({ daily_reminders: false, marketing: false, updatedAt: new Date() }, { merge: true });
    }
  } catch (e) {
    // best effort
  }
  res.send('<!doctype html><html><head><meta charset="utf-8"><title>Soko Vibe</title></head><body style="font-family:sans-serif;padding:40px;text-align:center"><h1>Umeondolewa</h1><p>Hutapokea barua pepe za matangazo tena. Unaweza kurejesha kwenye mipangilio ya app.</p><p><a href="https://www.sokovibe.co.tz">Rudi Soko Vibe</a></p></body></html>');
});

router.processCampaign = processCampaign;
module.exports = router;