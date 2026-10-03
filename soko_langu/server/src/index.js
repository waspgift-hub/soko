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

const server = app.listen(PORT, () => {
  console.log(`[API] Soko Vibe API running on port ${PORT}`);
  console.log(`[API] Environment: ${config.nodeEnv}`);
  console.log(`[API] Health: http://localhost:${PORT}/health`);
});

// Graceful shutdown
const shutdown = async (signal) => {
  console.log(`[API] ${signal} received. Starting graceful shutdown...`);
  
  server.close(async () => {
    console.log('[API] HTTP server closed');
    
    // Close Redis (Firestore/firebase-admin owns its own pooled connection,
    // so there is no database handle left to tear down here).
    const { redis } = require('./config/redis');
    if (redis) {
      await redis.quit();
      console.log('[API] Redis connection closed');
    }
    
    process.exit(0);
  });
  
  // Force shutdown after 30s
  setTimeout(() => {
    console.error('[API] Forced shutdown after timeout');
    process.exit(1);
  }, 30000);
};

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Catch uncaught exceptions
process.on('uncaughtException', (err) => {
  console.error('[FATAL] Uncaught Exception:', err?.stack || err?.message || err);
});

process.on('unhandledRejection', (reason) => {
  console.error('[FATAL] Unhandled Rejection:', reason?.message || reason);
});
