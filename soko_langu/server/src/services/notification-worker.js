// Async notification delivery (email + SMS) for NON-blocking sends.
//
// WHY a queue: the request path must never wait on a 15–30s provider call.
// OTP sends stay synchronous (the user is staring at a countdown and the
// rollback semantics need an immediate delivered/failed answer), but
// everything else — security mail, event SMS — goes here: enqueue, answer
// fast, let the worker retry with backoff. Idempotency keys dedupe
// double-submits; when Redis is down the job runs inline so dev/test and
// degraded prod still deliver instead of silently dropping.
const { getNotificationQueue } = require('./queue');

async function handleNotificationJob(job) {
  const data = (job && job.data) || {};
  if (job.name === 'email') {
    const { sendMail } = require('./mailer');
    const ok = await sendMail(data.to, data.subject, data.html);
    if (!ok) throw new Error('NOTIFICATION_EMAIL_FAILED');
    return { channel: 'email' };
  }
  if (job.name === 'sms') {
    const { sendSms } = require('./sms-service');
    const ok = await sendSms(data.to, data.message);
    if (!ok) throw new Error('NOTIFICATION_SMS_FAILED');
    return { channel: 'sms' };
  }
  throw new Error(`NOTIFICATION_UNKNOWN_JOB:${job.name}`);
}

// Enqueue a notification. Falls back to inline execution when the queue is
// unreachable (no Redis): degraded delivery beats silent loss, and tests/dev
// never need infrastructure to exercise the call sites.
async function enqueueNotification(name, data, { idempotencyKey = null } = {}) {
  const jobData = data || {};
  try {
    const queue = getNotificationQueue();
    await queue.add(name, jobData, {
      ...(idempotencyKey ? { jobId: idempotencyKey } : {}),
      attempts: 5,
      backoff: { type: 'exponential', delay: 30000 },
      removeOnComplete: 100,
      removeOnFail: 500,
    });
    return { queued: true };
  } catch (e) {
    console.error(`[NOTIFY] queue unavailable, sending ${name} inline:`, e.message);
    try {
      await handleNotificationJob({ name, data: jobData });
      return { queued: false, delivered: true };
    } catch (inlineErr) {
      console.error(`[NOTIFY] inline ${name} failed:`, inlineErr.message);
      return { queued: false, delivered: false };
    }
  }
}

let notificationWorker = null;

async function startNotificationWorker() {
  if (notificationWorker) return notificationWorker;
  try {
    const { Worker } = require('bullmq');
    const { getRedis } = require('../config/redis');
    const connection = getRedis();
    notificationWorker = new Worker('notifications', handleNotificationJob, { connection, concurrency: 5 });
    notificationWorker.on('completed', (job) => console.log(`[NOTIFY] job ${job.id} (${job.name}) completed`));
    notificationWorker.on('failed', (job, err) => console.error(`[NOTIFY] job ${job?.id} (${job?.name}) failed:`, err.message));
    notificationWorker.on('error', (err) => console.error('[NOTIFY] worker error:', err.message));
    console.log('[NOTIFY] Worker initialized (queue: notifications)');
    return notificationWorker;
  } catch (e) {
    console.error('[NOTIFY] worker start failed:', e.message);
    return null;
  }
}

async function closeNotificationWorker() {
  if (notificationWorker) {
    await notificationWorker.close().catch(() => {});
    notificationWorker = null;
  }
  const { closeNotificationQueue } = require('./queue');
  await closeNotificationQueue();
}

module.exports = { handleNotificationJob, enqueueNotification, startNotificationWorker, closeNotificationWorker };
