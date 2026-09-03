const { Queue } = require('bullmq');
const { getRedisClient } = require('./redis');

// ---------------------------------------------------------------------------
// BullMQ Payment Queue
//
// WHY A QUEUE?
// Payment gateways enforce strict timeout limits (typically 5-10 seconds).
// If your database is slow (cold start on Render, connection pool exhaustion,
// or a slow migration), the gateway will time out and retry → chaos.
//
// BY USING A QUEUE:
//   1. API server enqueues the job in ~5ms and returns 200 OK immediately
//   2. Gateway is happy (fast response)
//   3. Worker processes at its own pace (retries if DB is busy)
//   4. Zero data loss — BullMQ persists jobs in Redis (AOF/RDB)
//
// WHY BULLMQ over simple Redis lists?
//   - Atomic job state transitions (waiting → active → completed/failed)
//   - Built-in retry with exponential backoff
//   - Job prioritization, rate limiting, concurrency control
//   - Dashboard (Bull Board) for monitoring
// ---------------------------------------------------------------------------

const QUEUE_NAME = 'payment-webhooks';

let queue = null;

/**
 * Returns the shared BullMQ queue instance.
 * We pass the Redis client directly instead of a URL to reuse connections.
 */
function getPaymentQueue() {
  if (!queue) {
    queue = new Queue(QUEUE_NAME, {
      connection: getRedisClient(),
      defaultJobOptions: {
        // Remove completed jobs after 24 hours (disk safety)
        removeOnComplete: { age: 86400 },
        // Keep failed jobs for 7 days (for debugging)
        removeOnFail: { age: 604800 },
        // 3 attempts: initial + 2 retries (worker handles 3rd retry internally)
        attempts: 2,
        backoff: {
          type: 'exponential',
          delay: 1000, // 1s, 2s, 4s...
        },
      },
    });
  }
  return queue;
}

async function closeQueue() {
  if (queue) {
    await queue.close();
    queue = null;
  }
}

module.exports = { getPaymentQueue, closeQueue, QUEUE_NAME };
