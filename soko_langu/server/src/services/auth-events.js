// Append-only login/security event log.
//
// Every successful (and denied) sign-in, OTP delivery failure, and logout
// lands here so admins can monitor authentication activity without reading the
// audit log. The collection is written exclusively by the Admin SDK (these
// rules bypass), and firestore.rules denies all client access to it, so users
// can never read or modify their own (or anyone else's) history. The only
// field that is ever updated on a row is `notificationStatus`, and only by the
// service that created it.
const crypto = require('crypto');
const { getFirebaseFirestore } = require('../config/firebase');

const COLLECTION = 'auth_security_events';
const RETENTION_DAYS = 90;
const DEVICE_LOOKBACK_DAYS = 90;
const LIST_LIMIT_DEFAULT = 100;

function collectionRef() {
  const db = getFirebaseFirestore();
  if (!db) return null;
  return db.collection(COLLECTION);
}

function parseUserAgent(uaRaw) {
  const ua = String(uaRaw || '');
  let os = 'Unknown';
  if (/Windows NT 10/.test(ua)) os = 'Windows 10/11';
  else if (/Windows NT 6\.3/.test(ua)) os = 'Windows 8.1';
  else if (/Windows NT 6\.1/.test(ua)) os = 'Windows 7';
  else if (/Mac OS X/.test(ua)) os = 'macOS';
  else if (/Android/.test(ua)) {
    const m = ua.match(/Android ([0-9.]+)/);
    os = `Android${m ? ` ${m[1]}` : ''}`;
  } else if (/iPhone|iPad|iPod/.test(ua)) {
    const m = ua.match(/OS ([0-9_]+)/);
    os = `iOS${m ? ` ${m[1].replace(/_/g, '.')}` : ''}`;
  } else if (/CrOS/.test(ua)) os = 'ChromeOS';
  else if (/Linux/.test(ua)) os = 'Linux';

  let browser = 'Unknown';
  if (/Edg\//.test(ua)) browser = 'Edge';
  else if (/OPR\/|Opera/.test(ua)) browser = 'Opera';
  else if (/Chrome\//.test(ua) && !/Chromium/.test(ua)) browser = 'Chrome';
  else if (/Firefox\//.test(ua)) browser = 'Firefox';
  else if (/Safari\//.test(ua) && !/Chrome/.test(ua)) browser = 'Safari';
  else if (/okhttp|Dart|CFNetwork/.test(ua)) browser = 'Mobile app';

  let device = 'Desktop';
  if (/iPad|Tablet/.test(ua)) device = 'Tablet';
  else if (/Mobile|iPhone|Android.*Mobile/.test(ua)) device = 'Mobile';
  else if (/okhttp|Dart|CFNetwork/.test(ua)) device = 'Mobile app';

  return { os, browser, device };
}

function coarseLocation(headers) {
  const h = headers || {};
  const city = h['cf-ipcity'] || h['x-vercel-ip-city'] || '';
  const region = h['cf-region'] || h['x-vercel-ip-country-region'] || '';
  const country = h['cf-ipcountry'] || h['x-vercel-ip-country'] || '';
  const parts = [city, region, country]
    .map((s) => { try { return decodeURIComponent(String(s || '')); } catch (_) { return String(s || ''); } })
    .filter(Boolean);
  return [...new Set(parts)].join(', ');
}

function describeRequest(req) {
  const headers = (req && req.headers) || {};
  const userAgent = String(headers['user-agent'] || '');
  const ua = parseUserAgent(userAgent);
  let ip = '';
  try { const { clientIp } = require('../middleware/rateLimiter'); ip = clientIp(req) || ''; } catch (_) { ip = (req && req.ip) || ''; }
  const acceptLanguage = String(headers['accept-language'] || '');
  return {
    ip,
    userAgent: userAgent.slice(0, 512),
    device: ua.device,
    os: ua.os,
    browser: ua.browser,
    location: coarseLocation(headers),
    deviceHash: crypto.createHash('sha256').update(`${userAgent}|${acceptLanguage}`).digest('hex').slice(0, 32),
  };
}

async function isNewDevice(uid, deviceHash) {
  const col = collectionRef();
  if (!col || !uid || !deviceHash) return true;
  try {
    const snap = await col.where('uid', '==', uid).where('deviceHash', '==', deviceHash).where('outcome', '==', 'success').limit(1).get();
    return snap.empty;
  } catch (e) {
    console.error('[AUTH-EVENTS] isNewDevice failed:', e.message);
    return true;
  }
}

async function recordEvent({
  uid = null,
  emailMasked = null,
  method = 'unknown',
  outcome = 'unknown',
  req = null,
  newDevice = false,
  notificationStatus = 'none',
  reason = null,
  meta = null,
} = {}) {
  const col = collectionRef();
  const info = meta || describeRequest(req);
  const now = new Date();
  const doc = {
    uid: uid || null,
    emailMasked: emailMasked || null,
    method: String(method || 'unknown'),
    outcome: String(outcome || 'unknown'),
    createdAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + RETENTION_DAYS * 86400000),
    ip: info.ip,
    userAgent: info.userAgent,
    device: info.device,
    os: info.os,
    browser: info.browser,
    location: info.location,
    deviceHash: info.deviceHash,
    newDevice: Boolean(newDevice),
    notificationStatus: notificationStatus || 'none',
    reason: reason || null,
  };
  if (!col) {
    console.warn('[AUTH-EVENTS] Firestore not configured; event not persisted:', doc.method, doc.outcome);
    return null;
  }
  try {
    const ref = await col.add(doc);
    return ref.id;
  } catch (e) {
    console.error('[AUTH-EVENTS] recordEvent failed:', e.message);
    return null;
  }
}

async function setNotificationStatus(id, status) {
  const col = collectionRef();
  if (!col || !id) return;
  try {
    await col.doc(id).update({ notificationStatus: status });
  } catch (e) {
    console.error('[AUTH-EVENTS] setNotificationStatus failed:', e.message);
  }
}

async function listUserEvents(uid, limit = 20) {
  const col = collectionRef();
  if (!col || !uid) return [];
  const take = Math.min(Number(limit) || 20, 100);
  try {
    const snap = await col.where('uid', '==', uid).orderBy('createdAt', 'desc').limit(take).get();
    return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  } catch (e) {
    try {
      const snap = await col.where('uid', '==', uid).limit(200).get();
      return snap.docs.map((d) => ({ id: d.id, ...d.data() }))
        .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)))
        .slice(0, take);
    } catch (e2) {
      console.error('[AUTH-EVENTS] listUserEvents failed:', e2.message);
      return [];
    }
  }
}

async function lastSuccessfulEvent(uid) {
  const events = await listUserEvents(uid, 25);
  return events.find((e) => e.outcome === 'success') || null;
}

async function listAllEvents(query = {}) {
  const col = collectionRef();
  const limit = Math.min(Number(query.limit) || LIST_LIMIT_DEFAULT, 200);
  const method = query.method ? String(query.method) : null;
  const outcome = query.outcome ? String(query.outcome) : null;
  const uid = query.uid ? String(query.uid) : null;
  if (!col) return { events: [], summary: summarize([]) };
  let snap;
  try {
    snap = await col.orderBy('createdAt', 'desc').limit(500).get();
  } catch (e) {
    console.error('[AUTH-EVENTS] listAllEvents failed:', e.message);
    return { events: [], summary: summarize([]) };
  }
  let events = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  if (uid) events = events.filter((e) => e.uid === uid);
  if (method) events = events.filter((e) => e.method === method);
  if (outcome) events = events.filter((e) => e.outcome === outcome);
  const page = events.slice(0, limit);
  return { events: page, summary: summarize(events) };
}

function summarize(events) {
  const list = Array.isArray(events) ? events : [];
  const byOutcome = {};
  const byMethod = {};
  let newDevices = 0;
  const failedByIp = {};
  const failedByUser = {};
  for (const e of list) {
    byOutcome[e.outcome] = (byOutcome[e.outcome] || 0) + 1;
    byMethod[e.method] = (byMethod[e.method] || 0) + 1;
    if (e.newDevice) newDevices += 1;
    if (e.outcome !== 'success') {
      failedByIp[e.ip] = (failedByIp[e.ip] || 0) + 1;
      if (e.uid) failedByUser[e.uid] = (failedByUser[e.uid] || 0) + 1;
    }
  }
  const suspicious = [];
  for (const [ip, n] of Object.entries(failedByIp)) {
    if (n >= 5) suspicious.push({ type: 'ip_failures', ip, count: n });
  }
  for (const [u, n] of Object.entries(failedByUser)) {
    if (n >= 3) suspicious.push({ type: 'user_failures', uid: u, count: n });
  }
  return {
    total: list.length,
    success: byOutcome.success || 0,
    failed: (byOutcome.invalid_code || 0) + (byOutcome.locked || 0) + (byOutcome.denied || 0),
    otpSendFailed: byOutcome.otp_send_failed || 0,
    denied: byOutcome.denied || 0,
    newDevices,
    byOutcome,
    byMethod,
    suspicious,
  };
}

module.exports = {
  describeRequest,
  isNewDevice,
  recordEvent,
  setNotificationStatus,
  listUserEvents,
  lastSuccessfulEvent,
  listAllEvents,
  summarize,
};