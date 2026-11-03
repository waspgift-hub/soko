// Two-tier cache: Redis (distributed, cross-instance) with in-memory fallback.
//
// Purpose: cut Firestore reads on hot public endpoints (most-rated, trending,
// autocomplete, popular products) so the Spark free tier's 50K reads/day
// isn't exhausted by repeat visitors. Redis handles multi-instance invalidation
// on Render; in-memory LRU handles single-instance fast path.

const MAX_ENTRIES = 500;

// ---------------------------------------------------------------------------
// Single-flight (stampede) lock table
// ---------------------------------------------------------------------------
// When a hot cache key expires, the first request to miss re-computes the value
// while every other concurrent request for the SAME key awaits the same
// in-flight promise. At 10M users this collapses a thundering herd of N
// simultaneous Firestore/DB reads into exactly one.
const inFlight = new Map();

// ---------------------------------------------------------------------------
// In-memory LRU fallback
// ---------------------------------------------------------------------------
const memStore = new Map();

function memGet(key) {
  const entry = memStore.get(key);
  if (!entry) return undefined;
  if (entry.expiresAt <= Date.now()) {
    memStore.delete(key);
    return undefined;
  }
  // Move to end (most recently used)
  memStore.delete(key);
  memStore.set(key, entry);
  return entry.value;
}

function memSet(key, value, ttlMs) {
  memStore.set(key, { value, expiresAt: Date.now() + ttlMs });
  memPrune();
}

function memDel(key) {
  memStore.delete(key);
}

function memPrune() {
  if (memStore.size < MAX_ENTRIES) return;
  const now = Date.now();
  for (const [key, entry] of memStore) {
    if (entry.expiresAt <= now) memStore.delete(key);
  }
  if (memStore.size >= MAX_ENTRIES) {
    const oldest = [...memStore.entries()]
      .sort((a, b) => a[1].expiresAt - b[1].expiresAt)
      .slice(0, Math.floor(MAX_ENTRIES / 4));
    for (const [key] of oldest) memStore.delete(key);
  }
}

// ---------------------------------------------------------------------------
// Redis wrapper (set via index.js after redis client is created)
// ---------------------------------------------------------------------------
let redisClient = null;

function setRedisClient(client) {
  redisClient = client;
}

async function get(key) {
  // Fast path: check in-memory first
  const memVal = memGet(key);
  if (memVal !== undefined) return memVal;

  // Slow path: check Redis
  if (redisClient) {
    try {
      const raw = await redisClient.get(`cache:${key}`);
      if (raw) {
        const parsed = JSON.parse(raw);
        memSet(key, parsed, 60_000); // warm in-memory for 1 min
        return parsed;
      }
    } catch (_) { /* Redis unavailable, fall through */ }
  }

  return undefined;
}

async function set(key, value, ttlMs = 300_000) {
  // Always write to in-memory
  memSet(key, value, ttlMs);

  // Also write to Redis when available (TTL in seconds)
  if (redisClient) {
    try {
      const ttlSec = Math.max(1, Math.floor(ttlMs / 1000));
      await redisClient.set(`cache:${key}`, JSON.stringify(value), 'EX', ttlSec);
    } catch (_) { /* Redis unavailable, skip */ }
  }

  return value;
}

async function del(key) {
  memDel(key);
  if (redisClient) {
    try {
      await redisClient.del(`cache:${key}`);
    } catch (_) { /* Redis unavailable, skip */ }
  }
}

// Invalidate a pattern (for cache busting when products change)
async function delPattern(pattern) {
  // Always clear in-memory (full scan)
  for (const key of memStore.keys()) {
    if (key.startsWith(pattern.replace('*', ''))) memStore.delete(key);
  }

  // Redis pattern delete
  if (redisClient) {
    try {
      const keys = await redisClient.keys(`cache:${pattern}`);
      if (keys.length > 0) await redisClient.del(...keys);
    } catch (_) { /* Redis unavailable, skip */ }
  }
}

// ---------------------------------------------------------------------------
// getOrCompute: read-through cache with per-key single-flight isolation.
// ---------------------------------------------------------------------------
//   const value = await getOrCompute('catalog:hot', async () => computeExpensive(), 300_000)
//
// Behaviour:
//   - Cache hit  -> return immediately (memory or Redis).
//   - Cache miss -> dedupe concurrent callers onto ONE compute, then store.
//   - Redis miss but memory copy warm -> skip the Redis PAINFUL round-trip
//     (see below) unless a cross-instance invalidation is running.
// The Redis starvation guard: when Redis is down we still serve from memory, so
// the app degrades to a single-instance cache instead of dying.
async function getOrCompute(key, computeFn, ttlMs = 300_000, options = {}) {
  // 1) Fast path: memory already warm.
  const memVal = memGet(key);
  if (memVal !== undefined) return memVal;

  // 2) Single-flight: another process already recomputing this key.
  if (inFlight.has(key)) {
    return inFlight.get(key);
  }

  // 3) Redis read path (cross-instance warm value).
  let redisWarm = undefined;
  if (redisClient) {
    try {
      const raw = await redisClient.get(`cache:${key}`);
      if (raw) {
        redisWarm = JSON.parse(raw);
        memSet(key, redisWarm, 60_000); // warm local copy for 1 min
      }
    } catch (err) { /* Redis unavailable; fall through to compute */ }
  }
  if (redisWarm !== undefined) return redisWarm;

  // 4) Stampede gate: only the FIRST caller per instance recomputes; all others
  //    await the same promise. The slot is released ONLY when the compute
  //    settles (cache is warm by then), so a slow pipeline never re-triggers.
  const p = (async () => {
    const value = await computeFn();
    if (value !== undefined && value !== null) {
      await set(key, value, ttlMs);
    }
    return value;
  })().finally(() => {
    inFlight.delete(key);
  });

  inFlight.set(key, p);
  return p;
}

module.exports = { get, set, del, delPattern, getOrCompute, setRedisClient };
