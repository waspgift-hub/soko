const Redis = require('ioredis');
const config = require('./index');

let redis = null;

function getRedis() {
  if (!redis) {
    redis = new Redis(config.redis.url, {
      maxRetriesPerRequest: null,
      retryStrategy(times) {
        return Math.min(times * 200, 5000);
      },
      lazyConnect: true,
    });
    
    redis.on('error', (error) => {
      console.error('[Redis] Connection error:', error.message);
    });
    
    redis.on('connect', () => {
      console.log('[Redis] Connected');
    });
  }
  return redis;
}

async function connectRedis() {
  try {
    const client = getRedis();
    await client.connect();
    return client;
  } catch (error) {
    console.error('[Redis] Connection failed:', error.message);
    return null;
  }
}

async function disconnectRedis() {
  if (redis) {
    await redis.quit();
    console.log('[Redis] Disconnected');
  }
}

// Idempotency lock helpers
async function acquireLock(key, ttlSeconds = 30) {
  if (!redis) return { acquired: true, skipped: true };
  try {
    const result = await redis.set(key, '1', 'EX', ttlSeconds, 'NX');
    return { acquired: result === 'OK', skipped: false };
  } catch (error) {
    console.warn('[Redis] Lock acquisition failed:', error.message);
    return { acquired: true, skipped: true };
  }
}

async function releaseLock(key) {
  if (!redis) return;
  try {
    await redis.del(key);
  } catch (error) {
    console.warn('[Redis] Lock release failed:', error.message);
  }
}

module.exports = { 
  getRedis, 
  connectRedis, 
  disconnectRedis,
  acquireLock,
  releaseLock,
};
