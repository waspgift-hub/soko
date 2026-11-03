const { Worker } = require('bullmq');
const { getRedisClient, closeRedis } = require('../shared/redis');
const { QUEUE_NAME } = require('../shared/queue');
const { processPayment } = require('./payment-processor');
const { getPrisma, closePrisma } = require('./prisma-client');
const logger = require('../shared/logger');

// ===========================================================================
// SERVER 2: Background Worker (Render Background Worker Service)
//
// ARCHITECTURE:
// This service has NO HTTP port. It runs as a Render "Background Worker"
// service (set type: `worker` in render.yaml). Render provisions it with
// a private network but no public URL.
//
// WHAT IT DOES:
// Continuously polls the Redis queue for payment jobs. When a job arrives:
//   1. Deserializes the payment payload
//   2. Updates the database via Prisma
//   3. Includes retry logic with exponential backoff
//   4. Logs every state transition for auditability
//
// WHY A SEPARATE PROCESS?
// Decoupling the API (fast, stateless) from the worker (stateful, retrying)
// means:
//   - API never blocks waiting for slow DB writes
//   - Worker can crash/restart without affecting API availability
//   - You can scale API and worker independently
//   - Database connection pool is only opened where needed (worker)
//
// RETRY STRATEGY:
// BullMQ handles retries at the queue level (configurable per queue).
// The worker ALSO implements manual retry for transient DB errors because:
//   - BullMQ retry restarts the entire job
//   - Manual retry handles connection timeouts within a single job execution
//
// CONCURRENCY:
// `concurrency: 5` means the worker processes up to 5 jobs in parallel.
// On Render free tier (512 MB RAM), keep this low. On paid plans, increase
// based on your DB connection pool size.
// ===========================================================================

// Manually retry transient database errors (connection timeout, pool exhaustion)
const MAX_MANUAL_RETRIES = 3;
const RETRY_BASE_DELAY_MS = 500;

function isTransientError(err) {
  // PostgreSQL transient errors (PGRST, Prisma, pg driver)
  const transientCodes = [
    'P1001', // Can't reach database server
    'P1002', // Database server timeout
    'P1008', // Operations timed out
    'P1017', // Server closed connection
    'P2024', // Timeout waiting for pool
    'ECONNREFUSED',
    'ETIMEDOUT',
    '57P01', // Admin shutdown (PostgreSQL)
    '57P02', // Crash shutdown
    '57P03', // Cannot connect now (PostgreSQL)
  ];

  return (
    transientCodes.includes(err.code) ||
    err.message?.includes('connection') ||
    err.message?.includes('timeout') ||
    err.message?.includes('pool')
  );
}

async function withRetry(fn, context) {
  let lastError;

  for (let attempt = 1; attempt <= MAX_MANUAL_RETRIES; attempt++) {
    try {
      return await fn();
    } catch (err) {
      lastError = err;

      if (attempt >= MAX_MANUAL_RETRIES || !isTransientError(err)) {
        throw err;
      }

      // Exponential backoff: 500ms, 1000ms, 2000ms
      const delay = RETRY_BASE_DELAY_MS * Math.pow(2, attempt - 1);
      logger.warn(
        {
          attempt,
          maxRetries: MAX_MANUAL_RETRIES,
          delay,
          error: err.message,
          code: err.code,
          ...context,
        },
        `Transient DB error — retrying in ${delay}ms`,
      );

      await new Promise((resolve) => setTimeout(resolve, delay));
    }
  }

  throw lastError;
}

// ---------------------------------------------------------------------------
// Worker Event Handlers
//
// These provide observability into worker health. On Render, these logs
// appear in the service's log stream, which you can monitor via Render
// Dashboard or pipe to an external logging service (Datadog, Logtail).
// ---------------------------------------------------------------------------

let processedCount = 0;
let failedCount = 0;

const worker = new Worker(
  QUEUE_NAME,
  async (job) => {
    const startTime = Date.now();

    logger.info(
      {
        jobId: job.id,
        transactionId: job.data.transactionId,
        attempt: job.attemptsMade + 1,
        maxAttempts: job.opts.attempts + 1,
      },
      'Processing payment job',
    );

    // Use manual retry for transient errors, letting BullMQ handle
    // non-transient failures (e.g., invalid data, business logic errors)
    const result = await withRetry(
      () => processPayment(job.data),
      { jobId: job.id, transactionId: job.data.transactionId },
    );

    processedCount++;

    logger.info(
      {
        jobId: job.id,
        transactionId: job.data.transactionId,
        processingMs: Date.now() - startTime,
        totalProcessed: processedCount,
      },
      'Payment job completed',
    );

    return result;
  },
  {
    connection: getRedisClient(),

    // ---------------------------------------------------------------
    // CONCURRENCY: How many jobs this worker processes in parallel
    //
    // RULE OF THUMB:
    //   concurrency ≤ DB connection pool size
    //
    // Prisma default pool: CPU_COUNT * 2 + 1 = 3 on free tier.
    // So concurrency: 3 is safe. Increase on paid plans with
    // larger connection pools.
    // ---------------------------------------------------------------
    concurrency: 3,

    // ---------------------------------------------------------------
    // LOCK DURATION: Max time a job can run before BullMQ considers
    // it stuck and re-queues it. 30 seconds is generous for a DB
    // write that should take < 1 second.
    // ---------------------------------------------------------------
    lockDuration: 30000,

    // ---------------------------------------------------------------
    // STALLED INTERVAL: How often BullMQ checks for stuck jobs.
    // A job is "stalled" if it's been active for longer than
    // lockDuration without completing.
    // ---------------------------------------------------------------
    stalledInterval: 15000,

    // ---------------------------------------------------------------
    // REMOVE ON COMPLETE: Keep completed jobs for 24 hours for
    // debugging, then auto-delete to save Redis memory.
    // ---------------------------------------------------------------
    removeOnComplete: { age: 86400 },

    // Keep failed jobs for 7 days for debugging and manual re-processing.
    removeOnFail: { age: 604800 },
  },
);

// ---------------------------------------------------------------------------
// Worker Event Listeners — observability without third-party APM
// ---------------------------------------------------------------------------

worker.on('completed', (job, result) => {
  logger.debug(
    { jobId: job.id, result },
    'Job completed event',
  );
});

worker.on('failed', (job, err) => {
  failedCount++;

  logger.error(
    {
      jobId: job?.id,
      transactionId: job?.data?.transactionId,
      error: err.message,
      code: err.code,
      attemptsMade: job?.attemptsMade,
      totalFailed: failedCount,
    },
    'Job failed (all retries exhausted)',
  );

  // At this point, the job is in the "failed" state in BullMQ.
  // You can:
  //   1. Monitor via Bull Board dashboard
  //   2. Set up alerts (Render Slack integration, PagerDuty)
  //   3. Manually retry via Bull Board or Redis CLI
  //   4. Add to a dead-letter queue for manual review
});

worker.on('error', (err) => {
  logger.error({ err: err.message }, 'Worker error (non-job)');
});

worker.on('stalled', (jobId) => {
  logger.warn({ jobId }, 'Job stalled (exceeded lock duration)');
});

// ---------------------------------------------------------------------------
// Health Reporting
//
// Since the worker has no HTTP port, we report health via:
//   1. Process exit codes (non-zero on fatal errors)
//   2. BullMQ's built-in Redis-based health tracking
//   3. Log output (Render captures this)
//
// Render marks a worker as "healthy" as long as the process is alive.
// If the worker crashes, Render automatically restarts it.
// ---------------------------------------------------------------------------

let isShuttingDown = false;

async function gracefulShutdown(signal) {
  if (isShuttingDown) return;
  isShuttingDown = true;

  logger.info(
    { signal, processedCount, failedCount },
    'Worker graceful shutdown initiated',
  );

  try {
    // Stop accepting new jobs (waits for in-flight jobs to finish)
    await worker.close();
    logger.info('Worker closed');

    // Disconnect Prisma (releases DB connection pool)
    await closePrisma();
    logger.info('Prisma disconnected');

    // Close Redis connections
    await closeRedis();
    logger.info('Redis disconnected');

    logger.info('Worker shutdown complete');
    process.exit(0);
  } catch (err) {
    logger.error({ err: err.message }, 'Error during worker shutdown');
    process.exit(1);
  }
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Keep the process alive and log periodic health stats
setInterval(() => {
  logger.info(
    {
      processed: processedCount,
      failed: failedCount,
      uptime: Math.floor(process.uptime()),
      memoryMB: Math.floor(process.memoryUsage().heapUsed / 1024 / 1024),
    },
    'Worker health stats',
  );
}, 60000); // Every 60 seconds

logger.info(
  { queue: QUEUE_NAME, concurrency: 3 },
  'Payment worker started — listening for jobs',
);
