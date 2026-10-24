// Minimal login risk layer (spec: progressive protection, no permanent locks).
//
// Two jobs, deliberately small:
//   1. Probing detection — one IP touching MANY distinct targets (phones /
//      emails) inside a window is enumeration, not usage. Flagged once per
//      IP per window via audit event `auth_probing_detected`; requests are
//      still served (availability first — the per-target ceilings already
//      bound the damage).
//   2. Auth event counters — every authAudit() call increments a counter, so
//      login/OTP/reset success-vs-failure rates are observable without
//      another instrumentation pass. Query the auditLog table for history;
//      snapshot() is the live view.
//
// Counting is best-effort (memory fallback diverges across instances, Redis
// HyperLogLog merges when available); it drives ALERTS, never blocks.
const { getRedis } = require('../config/redis');

const PROBE_WINDOW_SEC = parseInt(process.env.AUTH_PROBE_WINDOW_SEC || '900', 10);
const PROBE_THRESHOLD = parseInt(process.env.AUTH_PROBE_THRESHOLD || '20', 10);

const counts = new Map();
function inc(action) {
  counts.set(action, (counts.get(action) || 0) + 1);
}
function snapshot() {
  return Object.fromEntries(counts);
}

// In-memory fallback: ip -> { targets: Set, windowStart }. Bounded: probing
// state must never become an unbounded memory sink under the attack it tracks.
const MEMORY_MAX_IPS = parseInt(process.env.AUTH_RISK_MEMORY_MAX || '2000', 10);
const memory = new Map();
const flagged = new Map(); // ip -> windowStart (already alerted this window)

function memoryRecord(ip, target) {
  const now = Date.now();
  let entry = memory.get(ip);
  if (!entry || now - entry.windowStart > PROBE_WINDOW_SEC * 1000) {
    entry = { targets: new Set(), windowStart: now };
    if (!memory.has(ip) && memory.size >= MEMORY_MAX_IPS) {
      const oldest = memory.keys().next();
      if (!oldest.done) memory.delete(oldest.value);
    }
    memory.set(ip, entry);
  }
  entry.targets.add(target);
  return entry.targets.size;
}

// Records one account-touching probe (existence check or verify attempt
// against a target). Returns { probing, distinct }: probing is true the FIRST
// time the IP crosses the threshold inside the window.
async function recordProbe(ip, target) {
  const key = `authprobe:${ip}`;
  try {
    const redis = getRedis();
    if (redis && redis.status === 'ready') {
      await redis.pfadd(key, String(target));
      await redis.expire(key, PROBE_WINDOW_SEC);
      const distinct = await redis.pfcount(key);
      if (distinct >= PROBE_THRESHOLD) {
        const flagKey = `authprobeflag:${ip}`;
        const fresh = await redis.set(flagKey, '1', 'NX', 'EX', PROBE_WINDOW_SEC);
        return { probing: fresh === 'OK', distinct };
      }
      return { probing: false, distinct };
    }
  } catch (e) {
    console.error('[AUTH-RISK] redis probe failed:', e.message);
  }
  const distinct = memoryRecord(ip || 'unknown', String(target));
  if (distinct >= PROBE_THRESHOLD) {
    const now = Date.now();
    const since = flagged.get(ip) || 0;
    if (now - since > PROBE_WINDOW_SEC * 1000) {
      flagged.set(ip, now);
      return { probing: true, distinct };
    }
  }
  return { probing: false, distinct };
}

module.exports = { inc, snapshot, recordProbe, PROBE_THRESHOLD };
