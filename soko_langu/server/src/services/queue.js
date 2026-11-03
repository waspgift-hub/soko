const { Queue } = require('bullmq');
const { getRedis } = require('../config/redis');

let mediaQueue = null;
let financeQueue = null;
let notificationQueue = null;

// Failed jobs retry with exponential backoff instead of being dropped on the
// first error. Keep finished-job history bounded so Redis memory stays flat.
const DEFAULT_JOB_OPTIONS = {
  attempts: 5,
  backoff: { type: 'exponential', delay: 5000 },
  removeOnComplete: 100,
  removeOnFail: 500,
};

function getMediaQueue() {
  if (!mediaQueue) {
    const connection = getRedis();
    mediaQueue = new Queue('media', { connection, defaultJobOptions: DEFAULT_JOB_OPTIONS });
  }
  return mediaQueue;
}

// Async notification delivery (security mail, event SMS). OTP sends stay
// synchronous — the user waits on the code and rollback needs an answer now.
function getNotificationQueue() {
  if (!notificationQueue) {
    const connection = getRedis();
    notificationQueue = new Queue('notifications', { connection, defaultJobOptions: DEFAULT_JOB_OPTIONS });
  }
  return notificationQueue;
}

function getFinanceQueue() {
  if (!financeQueue) {
    const connection = getRedis();
    financeQueue = new Queue('finance', { connection, defaultJobOptions: DEFAULT_JOB_OPTIONS });
  }
  return financeQueue;
}

/**
 * Register the repeating finance jobs. BullMQ keys repeatable jobs by the
 * custom jobId, so calling this from every process boot does not duplicate
 * schedules. The worker then honors them via the 'finance' queue.
 */
const FINANCE_SCHEDULE = [
  { name: 'finance.paymentExpire', every: 15 * 60 * 1000, jobId: 'recur:paymentExpire' },
  { name: 'finance.inspectionAutoRelease', every: 60 * 60 * 1000, jobId: 'recur:inspectionAutoRelease' },
  { name: 'finance.withdrawalProcess', every: 30 * 60 * 1000, jobId: 'recur:withdrawalProcess' },
  { name: 'finance.reconciliationRun', every: 60 * 60 * 1000, jobId: 'recur:reconciliationRun' },
  { name: 'finance.disputeEscalate', every: 30 * 60 * 1000, jobId: 'recur:disputeEscalate' },
  { name: 'finance.refundUnstuck', every: 30 * 60 * 1000, jobId: 'recur:refundUnstuck' },
];

async function ensureFinanceSchedule() {
  const queue = getFinanceQueue();
  for (const job of FINANCE_SCHEDULE) {
    await queue.add(
      job.name,
      {},
      {
        repeat: { every: job.every },
        jobId: job.jobId,
        removeOnComplete: 100,
        removeOnFail: 500,
      }
    );
  }
}

async function closeNotificationQueue() {
  if (notificationQueue) {
    await notificationQueue.close();
    notificationQueue = null;
  }
}

async function closeMediaQueue() {
  if (mediaQueue) {
    await mediaQueue.close();
    mediaQueue = null;
  }
}

async function closeFinanceQueue() {
  if (financeQueue) {
    await financeQueue.close();
    financeQueue = null;
  }
}

async function closeQueues() {
  await Promise.all([closeMediaQueue(), closeFinanceQueue(), closeNotificationQueue()]);
}

module.exports = {
  FINANCE_SCHEDULE,
  getMediaQueue,
  getFinanceQueue,
  getNotificationQueue,
  ensureFinanceSchedule,
  closeMediaQueue,
  closeFinanceQueue,
  closeNotificationQueue,
  closeQueues,
};