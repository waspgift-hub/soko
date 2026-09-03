const Redis = require('ioredis');

// ---------------------------------------------------------------------------
// Shared Redis client
//
// Why a singleton? Every connection costs ~10 KB of memory and a TCP socket.
// In a horizontally scaled deployment (2+ Render instances) each process MUST
// share the same Redis URL so idempotency locks and BullMQ jobs are visible
// across all instances.
// ---------------------------------------------------------------------------

let client = null;
let blocker = null;

/**
 * Returns the primary ioredis client used for idempotency locks and general
 * key-value operations. Reuses a single connection per process.
 */
function getRedisClient() {
  if (!client) {
    client = new Redis(process.env.REDIS_URL, {
      maxRetriesPerRequest: null,  // Required by BullMQ
      enableReadyCheck: true,
      retryStrategy(times) {
        // Exponential backoff capped at 5 seconds
        return Math.min(times * 200, 5000);
      },
    });

    client.on('error', (err) => {
      console.error('[Redis] Connection error:', err.message);
    });

    client.on('connect', () => {
      console.log('[Redis] Connected');
    });
  }
  return client;
}

/**
 * Returns a dedicated blocking Redis client for BullMQ.
 * BullMQ requires `maxRetriesPerRequest: null` on blocking connections.
 */
function getRedisBlocker() {
  if (!blocker) {
    blocker = new Redis(process.env.REDIS_URL, {
      maxRetriesPerRequest: null,
      enableReadyCheck: true,
    });
  }
  return blocker;
}

async function closeRedis() {
  if (client) {
    await client.quit();
    client = null;
  }
  if (blocker) {
    await blocker.quit();
    blocker = null;
  }
}

module.exports = { getRedisClient, getRedisBlocker, closeRedis };
