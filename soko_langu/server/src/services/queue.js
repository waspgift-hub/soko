const { Queue } = require('bullmq');
const { getRedis } = require('../config/redis');

let mediaQueue = null;
let financeQueue = null;

function getMediaQueue() {
  if (!mediaQueue) {
    const connection = getRedis();
    mediaQueue = new Queue('media', { connection });
  }
  return mediaQueue;
}

function getFinanceQueue() {
  if (!financeQueue) {
    const connection = getRedis();
    financeQueue = new Queue('finance', { connection });
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
  await Promise.all([closeMediaQueue(), closeFinanceQueue()]);
}

module.exports = {
  getMediaQueue,
  getFinanceQueue,
  ensureFinanceSchedule,
  closeMediaQueue,
  closeFinanceQueue,
  closeQueues,
};