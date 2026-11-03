const { getRedisClient } = require('./redis');

// ---------------------------------------------------------------------------
// Distributed Idempotency Lock
//
// PROBLEM: When you horizontally scale to N Render instances, the same
// webhook payload can hit multiple instances simultaneously. Without
// coordination, two workers might both see a "pending" payment and both
// try to process it → double spending, duplicate DB writes, corrupted state.
//
// SOLUTION: Before doing ANY work, every instance races to acquire a Redis
// SETNX lock keyed on the transaction ID. Only ONE instance wins the race.
// The lock auto-expires (TTL) so a crashed instance doesn't permanently
// block that transaction.
//
// WHY REDIS? Redis is single-threaded for command execution, so SETNX is
// atomic across all clients. Even if 10 Render instances hit Redis at the
// exact same nanosecond, exactly one SETNX will succeed.
//
// FLOW:
//   1. Webhook arrives at Instance A
//   2. Instance A runs: SET lock:txn_abc 1 NX EX 30
//   3. Redis returns OK → Instance A owns the lock
//   4. Instance B receives same webhook, runs same SETNX
//   5. Redis returns null → Instance B rejects (duplicate)
//   6. After 30 seconds, lock auto-expires (safety net for crashes)
// ---------------------------------------------------------------------------

const LOCK_TTL_SECONDS = 30;
const LOCK_PREFIX = 'idempotency:lock:';

/**
 * Attempts to acquire a distributed idempotency lock for a given transaction.
 *
 * @param {string} transactionId - The unique transaction identifier from the gateway
 * @returns {Promise<{acquired: boolean, alreadyProcessing: boolean}>}
 */
async function acquireIdempotencyLock(transactionId) {
  const redis = getRedisClient();
  const lockKey = `${LOCK_PREFIX}${transactionId}`;

  // SET NX = only set if key does not exist (atomic compare-and-set)
  // EX 30 = auto-expire after 30 seconds (crash safety net)
  const result = await redis.set(lockKey, '1', 'EX', LOCK_TTL_SECONDS, 'NX');

  if (result === 'OK') {
    return { acquired: true, alreadyProcessing: false };
  }

  // Key already exists → another instance is processing this exact transaction
  return { acquired: false, alreadyProcessing: true };
}

/**
 * Releases the idempotency lock. Called after the job is safely enqueued.
 * We release after enqueue (not after DB write) because the worker handles
 * the actual processing — the API server's only job is to accept or reject.
 *
 * @param {string} transactionId
 */
async function releaseIdempotencyLock(transactionId) {
  const redis = getRedisClient();
  await redis.del(`${LOCK_PREFIX}${transactionId}`);
}

/**
 * Generates the idempotency key from the raw webhook body.
 * This MUST be deterministic — same payload = same key.
 *
 * We use the transactionId from the gateway, which is guaranteed unique
 * per payment. If your gateway uses a different field, adjust accordingly.
 */
function extractIdempotencyKey(body) {
  // Adapt this to match your payment gateway's payload structure.
  // Common fields: body.transaction_id, body.id, body.reference
  return body.transaction_id || body.id || body.reference;
}

module.exports = {
  acquireIdempotencyLock,
  releaseIdempotencyLock,
  extractIdempotencyKey,
  LOCK_TTL_SECONDS,
};
