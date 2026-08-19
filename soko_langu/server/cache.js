// Two-tier cache: Redis (distributed, cross-instance) with in-memory fallback.
//
// Purpose: cut Firestore reads on hot public endpoints (most-rated, trending,
// autocomplete, popular products) so the Spark free tier's 50K reads/day
// isn't exhausted by repeat visitors. Redis handles multi-instance invalidation
// on Render; in-memory LRU handles single-instance fast path.

const MAX_ENTRIES = 500;

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

module.exports = { get, set, del, delPattern, setRedisClient };
