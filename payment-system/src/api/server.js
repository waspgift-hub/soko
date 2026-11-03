const express = require('express');
const logger = require('../shared/logger');
const { getPaymentQueue } = require('../shared/queue');
const {
  acquireIdempotencyLock,
  releaseIdempotencyLock,
  extractIdempotencyKey,
} = require('../shared/idempotency');
const { verifyWebhookSignature } = require('./webhook-verify');
const { closeRedis } = require('../shared/redis');
const { closeQueue } = require('../shared/queue');

// ===========================================================================
// SERVER 1: Webhook API (Render Web Service)
//
// ARCHITECTURE:
// This server is stateless — it holds NO database connections, processes NO
// business logic, and maintains NO session state. Its ONLY job is:
//
//   1. Validate the webhook came from the real payment gateway (HMAC check)
//   2. Check Redis for duplicate transactions (idempotency lock)
//   3. Push the payload into a BullMQ Redis queue (< 5ms)
//   4. Return 200 OK to the gateway (< 100ms total)
//
// WHY THIS MATTERS:
// - Payment gateways retry on timeout (5-10s). If your DB is slow, the
//   gateway retries → duplicate charges → customer complaints.
// - By returning 200 in < 100ms, we guarantee the gateway never retries.
// - The queue absorbs traffic spikes. 10,000 webhooks/second? BullMQ
//   handles it. Your database processes at its own pace.
// - Horizontal scaling is safe: idempotency locks in Redis prevent two
//   Render instances from processing the same webhook simultaneously.
// ===========================================================================

const app = express();

// Raw body needed for signature verification — must parse BEFORE json()
app.use(express.json({
  verify: (req, _res, buf) => {
    // Store raw body for HMAC verification
    req.rawBody = buf.toString('utf8');
  },
}));

// Trust Render's reverse proxy (X-Forwarded-For for rate limiting)
app.set('trust proxy', 1);

// ---------------------------------------------------------------------------
// Health check — Render calls this to determine if the service is alive.
// Must respond fast (< 500ms) or Render marks the instance as unhealthy
// and routes traffic away from it.
// ---------------------------------------------------------------------------
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ---------------------------------------------------------------------------
// POST /webhook/payment — Main webhook endpoint
//
// REQUEST FLOW:
//   1. Express parses JSON body                          ~2ms
//   2. HMAC signature verification                       ~1ms
//   3. Extract idempotency key from body                 ~0.1ms
//   4. Redis SETNX idempotency lock (atomic, 30s TTL)    ~3ms
//   5. BullMQ queue.add() (Redis LPUSH)                  ~5ms
//   6. Return 200 OK                                     ~1ms
//   TOTAL: ~12ms — well under the 100ms target
//
// WHAT CAN GO WRONG:
//   - Redis down → 503 (gateway will retry — acceptable)
//   - Queue full → BullMQ handles backpressure automatically
//   - Duplicate webhook → idempotency lock returns 200 (idempotent)
// ---------------------------------------------------------------------------
app.post('/webhook/payment', async (req, res) => {
  const startTime = Date.now();
  let transactionId = null;

  try {
    // STEP 1: Verify the webhook is from the real payment gateway
    if (!verifyWebhookSignature(req)) {
      logger.warn({ ip: req.ip }, 'Invalid webhook signature');
      return res.status(401).json({ error: 'Invalid signature' });
    }

    // STEP 2: Validate the payload has the minimum required fields
    const { transaction_id, status, amount, currency, payer_id } = req.body;
    if (!transaction_id || !status || !amount || !payer_id) {
      logger.warn({ body: req.body }, 'Missing required webhook fields');
      return res.status(400).json({ error: 'Missing required fields' });
    }

    transactionId = transaction_id;
    const idempotencyKey = extractIdempotencyKey(req.body);

    // STEP 3: Distributed idempotency lock via Redis SETNX
    //
    // WHY BEFORE THE QUEUE?
    // If we push to the queue first and then check idempotency, two
    // instances could both push the same job before either acquires the
    // lock. By locking FIRST, we ensure exactly one instance enqueues.
    //
    // WHY 30s TTL?
    // If the acquiring instance crashes after SETNX but before adding to
    // the queue, the lock auto-expires in 30s, allowing another instance
    // to pick it up. This prevents permanent deadlock.
    const { acquired, alreadyProcessing } = await acquireIdempotencyLock(transactionId);

    if (!acquired) {
      // Another instance is already handling this exact transaction.
      // Return 200 (not 409) because the gateway should NOT retry —
      // the payment IS being processed, just by another instance.
      logger.info(
        { transactionId, alreadyProcessing },
        'Duplicate webhook rejected (idempotency lock held)',
      );
      return res.status(200).json({
        status: 'already_processing',
        message: 'Transaction is being processed',
      });
    }

    // STEP 4: Push to BullMQ queue
    //
    // WHY BullMQ INSTEAD OF A SIMPLE REDIS LIST?
    // - Atomic job state tracking (waiting → active → completed)
    // - Built-in retry with exponential backoff (handles DB busy)
    // - Job deduplication, rate limiting, priorities
    // - Failed job inspection (Bull Board dashboard)
    const job = await getPaymentQueue().add(
      'process-payment',
      {
        transactionId,
        idempotencyKey,
        status,
        amount,
        currency: currency || 'USD',
        payerId: payer_id,
        payerEmail: req.body.payer_email || null,
        gatewayRef: req.body.gateway_ref || null,
        metadata: req.body, // Full payload for audit trail
        receivedAt: new Date().toISOString(),
      },
      {
        // Priority: completed > failed > pending (process outcomes first)
        priority: status === 'completed' ? 1 : status === 'failed' ? 2 : 3,
        // Deduplication: BullMQ won't add if a job with this ID exists
        // in waiting/active states. Prevents queue pollution from retries.
        jobId: `payment:${transactionId}`,
      },
    );

    const elapsedMs = Date.now() - startTime;

    logger.info(
      {
        transactionId,
        jobId: job.id,
        status,
        amount,
        elapsedMs,
      },
      `Webhook enqueued in ${elapsedMs}ms`,
    );

    // STEP 5: Return 200 OK immediately
    //
    // The payment gateway's retry policy is typically:
    //   - Retry after 1min, 5min, 30min, 2hr, 8hr
    // By responding in < 100ms, we NEVER trigger retries.
    res.status(200).json({
      status: 'accepted',
      jobId: job.id,
      elapsedMs,
    });
  } catch (err) {
    const elapsedMs = Date.now() - startTime;

    // If we acquired the lock but failed to enqueue, release it
    // so another instance can try.
    if (transactionId) {
      await releaseIdempotencyLock(transactionId).catch(() => {});
    }

    logger.error(
      { err: err.message, transactionId, elapsedMs },
      'Webhook processing failed',
    );

    // Return 503 so the gateway retries on a healthy instance.
    // On Render, health checks will eventually route traffic away from
    // a consistently failing instance.
    res.status(503).json({
      error: 'Temporary processing failure',
      retryable: true,
    });
  }
});

// ---------------------------------------------------------------------------
// Graceful Shutdown
//
// WHY?
// Render sends SIGTERM during deploys and scaling events. If you don't
// handle it, in-flight requests get killed mid-processing → data loss.
//
// SHUTDOWN SEQUENCE:
// 1. Stop accepting new requests (Express.close)
// 2. Finish in-flight requests (server.close callback)
// 3. Close BullMQ queue (flush pending jobs)
// 4. Close Redis connections (prevent socket leaks)
// 5. Exit process (Render restarts it)
// ---------------------------------------------------------------------------
const server = app.listen(process.env.PORT || 10000, () => {
  logger.info(
    { port: process.env.PORT || 10000 },
    'Payment API server started',
  );
});

let isShuttingDown = false;

async function gracefulShutdown(signal) {
  if (isShuttingDown) return;
  isShuttingDown = true;

  logger.info({ signal }, 'Graceful shutdown initiated');

  // Stop accepting new connections
  server.close(async () => {
    logger.info('HTTP server closed');

    try {
      await closeQueue();
      await closeRedis();
      logger.info('All connections closed');
      process.exit(0);
    } catch (err) {
      logger.error({ err: err.message }, 'Error during shutdown');
      process.exit(1);
    }
  });

  // Force kill after 10 seconds (Render's SIGTERM timeout is 30s)
  setTimeout(() => {
    logger.error('Forced shutdown after timeout');
    process.exit(1);
  }, 10000);
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

module.exports = app;
