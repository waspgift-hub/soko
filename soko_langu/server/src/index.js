require('dotenv').config();
const { app } = require('./app');
const config = require('./config');

const PORT = config.port;

// Warm up shared connections (DB + Redis) without blocking boot.
// Health and first requests work regardless; failures only log.
const { initialize } = require('./app');
initialize().catch((e) => console.error('[INIT]', e.message));

// Follow/friend notifications (Firestore watcher, best-effort).
try {
  const { startFollowWatcher } = require('./services/follow-watcher');
  startFollowWatcher();
} catch (e) {
  console.error('[FOLLOW-WATCH] disabled:', e.message);
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
    
    // Close database connections
    const { prisma } = require('./config/database');
    if (prisma) {
      await prisma.$disconnect();
      console.log('[API] Database connections closed');
    }
    
    // Close Redis
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
