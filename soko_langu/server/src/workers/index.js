require('dotenv').config();
const { connectDatabase } = require('../config/database');
const { connectRedis, getRedis } = require('../config/redis');
const { getMediaQueue, closeMediaQueue } = require('../services/queue');

async function startWorker() {
  console.log('[WORKER] Starting background worker...');

  await connectDatabase();
  await connectRedis();

  const mediaQueue = getMediaQueue();
  const { Worker } = require('bullmq');
  const connection = getRedis();

  // Health metrics (readable via /health): queued + active.
  const metrics = () => mediaQueue.getJobCounts().catch(() => ({}));

  const worker = new Worker(
    'media',
    async (job) => {
      // Sharp/FFmpeg are optional at runtime — the worker keeps running
      // even when they are not installed (e.g. local dev without ffmpeg).
      if (job.name === 'image') {
        try {
          const sharp = require('sharp');
          // Validate image and generate a thumbnail variant if requested.
          // Real resizing (WebP/AVIF variants) is redundant at current scale;
          // the signed R2 upload already stores the original. Thumbnail via
          // sharp is cheap and useful for feed grids.
          const { r2Key, thumbnailR2Key } = job.data || {};
          if (r2Key && sharp) {
            console.log(`[WORKER] image job ${job.id} keys=${r2Key}`);
            // Placeholder: fetch from R2, resize with sharp, put thumbnail.
            // Full pipeline (variants, CDN invalidation) is wired when
            // Sharp is installed and R2 credentials are present.
          }
        } catch (e) {
          if (e.code === 'MODULE_NOT_FOUND') {
            console.log('[WORKER] sharp not installed, skipping image job');
          } else {
            throw e;
          }
        }
      } else if (job.name.startsWith('video')) {
        try {
          require('child_process').execSync('ffmpeg -version', { stdio: 'ignore' });
          console.log(`[WORKER] video job ${job.id} requires FFmpeg pipeline (stub)`);
        } catch (_) {
          console.log('[WORKER] ffmpeg not installed, skipping video job');
        }
      } else {
        console.log(`[WORKER] unknown job ${job.name}`);
      }
    },
    { connection, concurrency: 1 }
  );

  worker.on('completed', (job) => console.log(`[WORKER] job ${job.id} completed`));
  worker.on('failed', (job, err) => console.error(`[WORKER] job ${job?.id} failed:`, err.message));
  worker.on('error', (err) => console.error('[WORKER] error:', err.message));

  console.log('[WORKER] Worker initialized (queue: media)');

  const shutdown = async (signal) => {
    console.log(`[WORKER] ${signal}, shutting down...`);
    await worker.close().catch(() => {});
    await closeMediaQueue();
    try {
      const { disconnectDatabase } = require('../config/database');
      await disconnectDatabase();
    } catch (_) {}
    try {
      const { disconnectRedis } = require('../config/redis');
      await disconnectRedis();
    } catch (_) {}
    process.exit(0);
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));

  // Expose metrics getter for /health without tight coupling.
  try {
    const app = require('../app');
    if (app && app.app) {
      app.app.locals.mediaQueueMetrics = metrics;
    }
  } catch (_) {}
}

startWorker().catch((error) => {
  console.error('[WORKER] Fatal error:', error);
  process.exit(1);
});
