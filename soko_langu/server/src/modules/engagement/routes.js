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

function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

router.post('/cron/daily-engagement', async (req, res) => {
  if (!verifyCronSecret(req.headers['x-cron-secret'])) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const settings = await settingsService.getSettings();
  const cfg = settings.dailyEngagement || {};
  if (!cfg.enabled) {
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
    if (channelPlan.email && user.email) {
      try {
        const { sendMail } = require('../../services/mailer');
        const dest = `https://www.sokovibe.co.tz${message.destination}`;
        const html = `<p>${String(message.emailBody).replace(/[<>]/g, '')}</p><p><a href="${dest}">Soko Vibe</a></p>`;
        const ok = await sendMail(user.email, message.subject, html);
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

  res.json({
    success: true,
    dayKey,
    prepared,
    recorded: sent,
    skipped,
    dryRun,
    note: 'Live channel send runs only when dailyEngagement.enabled is true.',
  });
});

module.exports = router;
