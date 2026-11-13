require('dotenv').config();
const { app } = require('./app');
const config = require('./config');

const PORT = config.port;

// Fail closed: a production boot with a missing or placeholder admin secret
// would leave the single shared-secret admin gate open to anyone guessing
// the default. Short secrets only warn — an exit there could take down a
// deployment whose rotation is still scheduled.
if (config.nodeEnv === 'production') {
  const s = config.security.adminSecret;
  if (!s || /change[_-]?this|placeholder|default/i.test(s)) {
    console.error('[FATAL] Refusing to boot: ADMIN_SECRET is missing or a placeholder in production.');
    process.exit(1);
  }
  if (s.length < 32) {
    console.error('[SECURITY] ADMIN_SECRET is shorter than 32 characters — rotate to a long random value.');
  }
}

// Warm up shared connections (DB + Redis) without blocking boot.
// Health and first requests work regardless; failures only log.
const { initialize } = require('./app');
initialize().catch((e) => console.error('[INIT]', e.message));

// Finance safety-net scheduler. Registers the repeating jobs and, in the
// default single-instance deployment, runs the finance worker in-process.
// Set FINANCE_WORKER_IN_PROCESS=false when a dedicated worker is deployed.
const { scheduleFinanceJobs, startFinanceWorker } = require('./services/finance-runner');
scheduleFinanceJobs().catch((e) => console.error('[FINANCE] schedule:', e.message));
if (config.finance.workerInProcess) {
  startFinanceWorker().catch((e) => console.error('[FINANCE] in-process worker:', e.message));
}

// Notification worker (async security mail/SMS). Same pattern: in-process by
// default, NOTIFICATION_WORKER_IN_PROCESS=false for a dedicated worker.
// BullMQ guards against double-processing when both run.
if (process.env.NOTIFICATION_WORKER_IN_PROCESS !== 'false') {
  const { startNotificationWorker } = require('./services/notification-worker');
  startNotificationWorker().catch((e) => console.error('[NOTIFY] in-process worker:', e.message));
}

// In-process daily engagement scheduler (best-effort). On Render free tier the
// web service sleeps after ~15 min of inactivity, so this only fires while the
// service is awake. For reliable daily delivery, also configure an external
// cron (e.g. cron-job.org) to POST to
//   https://soko-langu-server.onrender.com/api/v1/cron/daily-engagement
// with header  x-cron-secret: <CRON_SECRET or ADMIN_SECRET>
// every day at 09:00 Africa/Dar_es_Salaam. Disable with
// DAILY_ENGAGEMENT_SCHEDULER=false.
if (process.env.DAILY_ENGAGEMENT_SCHEDULER !== 'false') {
  const _secret = process.env.CRON_SECRET || process.env.ADMIN_SECRET;
  let _lastRunDay = null;
  const _tick = async () => {
    try {
      const eat = new Date(new Date().toLocaleString('en-US', { timeZone: 'Africa/Dar_es_Salaam' }));
      const dayKey = `${eat.getFullYear()}-${String(eat.getMonth() + 1).padStart(2, '0')}-${String(eat.getDate()).padStart(2, '0')}`;
      if (eat.getHours() === 9 && eat.getMinutes() < 30 && _lastRunDay !== dayKey && _secret) {
        _lastRunDay = dayKey;
        const r = await fetch(`http://127.0.0.1:${PORT}/api/v1/cron/daily-engagement`, {
          method: 'POST',
          headers: { 'x-cron-secret': _secret, 'Content-Type': 'application/json' },
          body: '{}',
        });
        const t = await r.text();
        console.log('[DAILY-ENGAGEMENT] triggered:', r.status, t.slice(0, 200));
      }
    } catch (e) {
      console.error('[DAILY-ENGAGEMENT] tick failed:', e?.message || e);
    }
  };
  setInterval(_tick, 30 * 60 * 1000);
  setTimeout(_tick, 60 * 1000).unref?.();
}

const server = app.listen(PORT, () => {
  console.log(`[API] Soko Vibe API running on port ${PORT}`);
  console.log(`[API] Environment: ${config.nodeEnv}`);
  console.log(`[API] Health: http://localhost:${PORT}/health`);
});

// Graceful shutdown
let shuttingDown = false;
const shutdown = async (signal) => {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`[API] ${signal} received. Starting graceful shutdown...`);

  try {
    // Stop accepting new work first: close idle keep-alive sockets immediately
    // so in-flight handlers drain against a still-open listening socket.
    server.closeAllConnections?.();
    await new Promise((resolve) => {
      server.close(() => resolve());
      // Safety: if the close callback never fires, don't hang forever.
      setTimeout(resolve, 5000).unref();
    });

    // Stop background workers BEFORE tearing down shared state so a worker
    // never outlives the Redis handle it may still be touching during drain.
    try {
      if (config.finance.workerInProcess) {
        const { closeFinanceWorker } = require('./services/finance-runner');
        await closeFinanceWorker();
      }
    } catch (_) {}
    try {
      if (process.env.NOTIFICATION_WORKER_IN_PROCESS !== 'false') {
        const { closeNotificationWorker } = require('./services/notification-worker');
        await closeNotificationWorker();
      }
    } catch (_) {}

    console.log('[API] HTTP server closed');

    const { redis } = require('./config/redis');
    if (redis) {
      await redis.quit();
      console.log('[API] Redis connection closed');
    }
  } finally {
    process.exit(0);
  }
};

let forceShutdownTimer = null;
const armForceShutdown = () => {
  if (forceShutdownTimer) return;
  forceShutdownTimer = setTimeout(() => {
    console.error('[API] Forced shutdown after timeout');
    process.exit(1);
  }, 30000);
  forceShutdownTimer.unref?.();
};

process.on('SIGTERM', () => { armForceShutdown(); shutdown('SIGTERM'); });
process.on('SIGINT', () => { armForceShutdown(); shutdown('SIGINT'); });
process.on('SIGQUIT', () => { armForceShutdown(); shutdown('SIGQUIT'); });

// Catch uncaught exceptions
process.on('uncaughtException', (err) => {
  console.error('[FATAL] Uncaught Exception:', err?.stack || err?.message || err);
});

process.on('unhandledRejection', (reason) => {
  console.error('[FATAL] Unhandled Rejection:', reason?.message || reason);
});
