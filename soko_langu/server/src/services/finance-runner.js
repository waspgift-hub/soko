const { Worker } = require('bullmq');
const { getRedis } = require('../config/redis');
const { getFinanceQueue, ensureFinanceSchedule } = require('./queue');
const { runFinanceJob } = require('../jobs/finance-jobs');

let financeWorker = null;

/**
 * Register the repeating finance schedule (idempotent per jobId).
 */
async function scheduleFinanceJobs() {
  try {
    await ensureFinanceSchedule();
  } catch (e) {
    console.error('[FINANCE] schedule failed:', e.message);
  }
}

/**
 * Start a BullMQ worker for the 'finance' queue. Safe to call from both the
 * API process (in-process mode) and a dedicated worker process: BullMQ picks
 * exactly one worker per job, and every job is idempotent anyway.
 */
async function startFinanceWorker() {
  if (financeWorker) return financeWorker;
  try {
    const connection = getRedis();
    financeWorker = new Worker(
      'finance',
      async (job) => {
        const result = await runFinanceJob(job.name, job.data || {});
        if (result) console.log(`[FINANCE] ${job.name} → ${JSON.stringify(result)}`);
        return result;
      },
      { connection, concurrency: 1 }
    );
    financeWorker.on('completed', (job) => console.log(`[FINANCE] job ${job.id} (${job.name}) completed`));
    financeWorker.on('failed', (job, err) => console.error(`[FINANCE] job ${job.id} (${job?.name}) failed:`, err.message));
    financeWorker.on('error', (err) => console.error('[FINANCE] worker error:', err.message));
    console.log('[FINANCE] Worker initialized (queue: finance)');
    return financeWorker;
  } catch (e) {
    console.error('[FINANCE] worker start failed:', e.message);
    return null;
  }
}

async function closeFinanceWorker() {
  if (financeWorker) {
    await financeWorker.close().catch(() => {});
    financeWorker = null;
  }
  const { closeFinanceQueue } = require('./queue');
  await closeFinanceQueue();
}

module.exports = { scheduleFinanceJobs, startFinanceWorker, closeFinanceWorker };