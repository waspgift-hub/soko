const Redis = require('ioredis');
const crypto = require('crypto');
const config = require('./index');

let redis = null;

function getRedis() {
  if (!redis) {
    redis = new Redis(config.redis.url, {
      // BullMQ requires this to be null (it manages its own retries). The
      // consequence for everyone ELSE sharing this client is that a command
      // issued while disconnected is queued and its promise NEVER settles,
      // which would hang a request handler forever. `redisReady()` +
      // `withTimeout()` below are the guard; keep them on every non-BullMQ
      // call site.
      maxRetriesPerRequest: null,
      retryStrategy(times) {
        return Math.min(times * 200, 5000);
      },
      lazyConnect: true,
    });

    redis.on('error', (error) => {
      console.error('[Redis] Connection error:', error.message);
    });

    redis.on('connect', () => {
      console.log('[Redis] Connected');
    });
  }
  return redis;
}

/**
 * True only when the client exists AND the socket is actually usable.
 *
 * `redis !== null` is not sufficient: `lazyConnect` leaves the client in
 * status 'wait' until first use, and a client that was created but never
 * connected is indistinguishable from a connected one by null-check alone.
 * Checking `status === 'ready'` is what makes fail-closed behaviour real.
 */
function redisReady() {
  return Boolean(redis && redis.status === 'ready');
}

/**
 * Rejects with an infrastructure error when Redis is not usable.
 *
 * Money-moving callers must use this instead of a null-check so a Redis
 * outage surfaces as a clean 503 to the client and a retryable log line,
 * rather than a request that hangs until the client gives up.
 */
async function assertRedisReady(operation) {
  if (redisReady()) return;
  const error = new Error(`REDIS_UNAVAILABLE:${operation}`);
  error.code = 'REDIS_UNAVAILABLE';
  error.status = 503;
  throw error;
}

async function connectRedis() {
  try {
    const client = getRedis();
    await client.connect();
    return client;
  } catch (error) {
    console.error('[Redis] Connection failed:', error.message);
    return null;
  }
}

async function disconnectRedis() {
  if (redis) {
    await redis.quit();
    console.log('[Redis] Disconnected');
  }
}

// Idempotency lock helpers
//
// The lock value is a per-acquisition random token, not a constant. That is
// what makes releaseLock safe: with a constant value, any process holding a
// reference to the key could DEL it, including one that FAILED to acquire the
// lock and is running its critical section anyway. The token plus the
// compare-and-delete below means a process can only ever release a lock it
// actually owns.
//
// FAIL CLOSED. When Redis cannot be reached we report `acquired: false` with
// `reason: 'redis_unavailable'` — never `acquired: true`. The previous
// behaviour returned success on both the "no client" and the "command threw"
// paths, which silently disabled mutual exclusion at exactly the moment the
// system was least healthy: overlapping money operations during a Redis
// outage. Callers that cannot tolerate losing the lock must branch on
// `acquired` (see `requireLock`).
//
// `skipped` is retained for callers that treat the lock purely as a
// best-effort optimisation (e.g. notification throttling), and is only ever
// true when the caller passed `optional: true`.
const ACQUIRE_TIMEOUT_MS = 3000;

// Keys scanned per SCAN iteration. Large enough to keep the round-trip count
// low, small enough that one page of work is a few microseconds of Redis time.
const SCAN_BATCH = 200;

/**
 * Test seam.
 *
 * Service modules destructure `acquireLock`/`requireLock` at require time, so a
 * test cannot simply monkey-patch the exported functions. Instead it installs
 * a whole implementation here BEFORE loading the service under test:
 *
 *   require('../src/config/redis').__setLockImpl({
 *     acquireLock: async () => ({ acquired: true, skipped: false, token: 't' }),
 *     releaseLock: async () => {},
 *   });
 *
 * This is intentionally a hard override rather than a flag: with fail-closed
 * behaviour, a test that forgot to stub would otherwise fail closed for the
 * wrong reason, and a production boot could never reach this path because
 * nothing in `src/` calls it. The override is null on every real start.
 */
let lockImpl = null;

function __setLockImpl(impl) {
  lockImpl = impl;
}

/**
 * @param {string} key
 * @param {number} ttlSeconds
 * @param {{ optional?: boolean }} [opts] `optional: true` returns
 *   `{ acquired: false, skipped: true }` on unavailability instead of
 *   `skipped: false`. Only for non-money work.
 */
async function acquireLock(key, ttlSeconds = 30, { optional = false } = {}) {
  if (lockImpl) return lockImpl.acquireLock(key, ttlSeconds, { optional });

  if (!redisReady()) {
    console.warn(`[Redis] Lock "${key}" unavailable — refusing (fail-closed)`);
    return {
      acquired: false,
      skipped: optional,
      token: null,
      reason: 'redis_unavailable',
    };
  }

  const token = crypto.randomUUID();
  try {
    const result = await redis
      .set(key, token, 'EX', ttlSeconds, 'NX')
      .timeout(ACQUIRE_TIMEOUT_MS);
    const acquired = result === 'OK';
    return {
      acquired,
      skipped: false,
      token: acquired ? token : null,
      reason: acquired ? null : 'held_by_other',
    };
  } catch (error) {
    console.warn(`[Redis] Lock "${key}" failed: ${error.message} — refusing`);
    return {
      acquired: false,
      skipped: optional,
      token: null,
      reason: 'redis_error',
    };
  }
}

/**
 * Acquire or throw a retryable 503.
 *
 * Use for every operation where proceeding without the lock could move money
 * twice. The thrown error carries `code: 'LOCK_UNAVAILABLE'` so routes can map
 * it to 503 + Retry-After instead of surfacing a 500.
 */
async function requireLock(key, ttlSeconds = 30, { message } = {}) {
  const lock = await acquireLock(key, ttlSeconds);
  if (!lock.acquired) {
    const error = new Error(
      message || `Could not acquire lock "${key}" (${lock.reason})`,
    );
    error.code = 'LOCK_UNAVAILABLE';
    error.status = 503;
    error.lockReason = lock.reason;
    throw error;
  }
  return lock;
}

/** True when the lock is held by another process (not by us). */
function isContended(lock) {
  return lock && !lock.acquired && lock.reason === 'held_by_other';
}

// Compare-and-delete: only remove the key if it still holds our token. A plain
// DEL would also delete a successor's lock when our TTL expired mid-flight and
// someone else already took the key.
const RELEASE_IF_OWNER = `
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("del", KEYS[1])
else
  return 0
end
`;

/**
 * Deletes keys matching a glob WITHOUT `KEYS`.
 *
 * `KEYS` is O(keyspace) and runs single-threaded on the Redis server, so one
 * call blocks every other client. `delPattern('catalog:list:v2:*')` was firing on
 * every product create/update/publish — meaning one seller listing a product
 * stalled rate limiting, OTP, queues and analytics for everyone.
 *
 * `SCAN` walks the keyspace incrementally and yields between pages, so the
 * server keeps serving other commands. `UNLINK` is used over `DEL` because it
 * frees memory on a background thread.
 *
 * Returns the number of keys removed so callers can assert the invalidation
 * actually did something.
 */
async function deleteByPattern(pattern) {
  if (!redisReady()) return 0;
  const match = `cache:${pattern}`;
  let cursor = '0';
  let removed = 0;
  const pending = [];

  do {
    const [next, keys] = await redis.scan(
      cursor,
      'MATCH',
      match,
      'COUNT',
      SCAN_BATCH,
    );
    cursor = next;
    for (const k of keys) {
      pending.push(k);
      // Keep one pipeline small; a huge keyspace would otherwise build a huge
      // command and risk a reply-buffer stall.
      if (pending.length >= SCAN_BATCH) {
        removed += await unlinkAll(pending.splice(0));
      }
    }
  } while (cursor !== '0');

  if (pending.length) removed += await unlinkAll(pending);
  return removed;
}

async function unlinkAll(keys) {
  try {
    if (typeof redis.unlink === 'function') return await redis.unlink(...keys);
    return await redis.del(...keys);
  } catch (e) {
    console.warn('[Redis] unlink failed:', e.message);
    return 0;
  }
}

async function releaseLock(key, token) {
  if (lockImpl) return lockImpl.releaseLock(key, token);
  if (!token) return;
  if (!redisReady()) {
    // The TTL will expire on its own; nothing to do and nothing to log at
    // error level, since the acquisition path already reported the outage.
    return;
  }
  try {
    await redis.eval(RELEASE_IF_OWNER, 1, key, token).timeout(ACQUIRE_TIMEOUT_MS);
  } catch (error) {
    console.warn('[Redis] Lock release failed:', error.message);
  }
}

module.exports = {
  getRedis,
  redisReady,
  assertRedisReady,
  connectRedis,
  disconnectRedis,
  acquireLock,
  requireLock,
  isContended,
  releaseLock,
  deleteByPattern,
  __setLockImpl,
};
