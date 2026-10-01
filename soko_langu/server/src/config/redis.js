const Redis = require('ioredis');
const crypto = require('crypto');
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
//
// The lock value is a per-acquisition random token, not a constant. That is
// what makes releaseLock safe: with a constant value, any process holding a
// reference to the key could DEL it, including one that FAILED to acquire the
// lock and is running its critical section anyway. The token plus the
// compare-and-delete below means a process can only ever release a lock it
// actually owns.
async function acquireLock(key, ttlSeconds = 30) {
  if (!redis) return { acquired: true, skipped: true, token: null };
  const token = crypto.randomUUID();
  try {
    const result = await redis.set(key, token, 'EX', ttlSeconds, 'NX');
    return { acquired: result === 'OK', skipped: false, token: result === 'OK' ? token : null };
  } catch (error) {
    console.warn('[Redis] Lock acquisition failed:', error.message);
    return { acquired: true, skipped: true, token: null };
  }
}

// Compare-and-delete: only remove the key if it still holds our token. A plain
// DEL would also delete a successor's lock when our TTL expired mid-flight and
// someone else already took the key.
const RELEASE_IF_OWNER = `
if redis.call("get", KEYS[1]) == ARGV[1] then
  return redis.call("del", KEYS[1])
else
  return 0
end
`;

async function releaseLock(key, token) {
  if (!redis) return;
  if (!token) return;
  try {
    await redis.eval(RELEASE_IF_OWNER, 1, key, token);
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
