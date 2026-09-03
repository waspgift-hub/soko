require('dotenv').config();
const { connectDatabase } = require('../config/database');
const { connectRedis } = require('../config/redis');

async function startWorker() {
  console.log('[WORKER] Starting background worker...');
  
  await connectDatabase();
  await connectRedis();
  
  console.log('[WORKER] Worker initialized');
  
  // Worker will process jobs from Redis queue
  // Implement job processors here
}

startWorker().catch((error) => {
  console.error('[WORKER] Fatal error:', error);
  process.exit(1);
});
