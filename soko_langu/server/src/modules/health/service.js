const { getPrisma } = require('../../config/database');
const { getRedis } = require('../../config/redis');

async function checkHealth() {
  const health = {
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    version: process.env.npm_package_version || '1.0.0',
    checks: {},
  };

  // Check database
  try {
    const prisma = getPrisma();
    await prisma.$queryRaw`SELECT 1`;
    health.checks.database = { status: 'ok', latency: 'fast' };
  } catch (error) {
    health.status = 'error';
    health.checks.database = { status: 'error', message: error.message };
  }

  // Check Redis
  try {
    const redis = getRedis();
    if (redis && redis.status === 'ready') {
      const start = Date.now();
      await redis.ping();
      const latency = Date.now() - start;
      health.checks.redis = { status: 'ok', latency: `${latency}ms` };
    } else {
      health.checks.redis = { status: 'warning', message: 'Not connected' };
    }
  } catch (error) {
    health.checks.redis = { status: 'error', message: error.message };
  }

  // Memory usage
  const memUsage = process.memoryUsage();
  health.memory = {
    rss: `${Math.round(memUsage.rss / 1024 / 1024)}MB`,
    heapUsed: `${Math.round(memUsage.heapUsed / 1024 / 1024)}MB`,
    heapTotal: `${Math.round(memUsage.heapTotal / 1024 / 1024)}MB`,
  };

  // Worker queue (set by worker process via app.locals)
  try {
    const app = require('../../app');
    if (app.app && app.app.locals.mediaQueueMetrics) {
      const counts = await app.app.locals.mediaQueueMetrics();
      health.checks.workerQueue = { status: 'ok', counts };
    }
  } catch (_) {}

  return health;
}

module.exports = { checkHealth };
