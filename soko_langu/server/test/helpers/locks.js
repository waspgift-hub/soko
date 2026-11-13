// Test-only lock stub.
//
// Every money path now acquires a Redis lock with FAIL-CLOSED semantics: if
// Redis is unreachable, the operation refuses rather than proceeding
// unprotected. Hermetic tests have no Redis, so they must install a lock
// implementation before the service modules under test are required (those
// modules destructure `acquireLock`/`requireLock` at require time).
//
// Use `stubLocksAlwaysAvailable()` for the normal case. Use
// `stubLocksFailing(reason)` to assert the fail-closed path.
const redisConfig = require('../../src/config/redis');

let previous = null;

/** In-process lock that always succeeds. Traces keys for assertions. */
function stubLocksAlwaysAvailable({ trace } = {}) {
  previous = null;
  redisConfig.__setLockImpl({
    async acquireLock(key, ttl) {
      if (trace) trace.acquired.push({ key, ttl });
      return { acquired: true, skipped: false, token: `test-${key}` };
    },
    async releaseLock(key, token) {
      if (trace) trace.released.push({ key, token });
    },
  });
}

/** Lock that never acquires — simulates Redis down or key contention. */
function stubLocksFailing(reason = 'redis_unavailable') {
  redisConfig.__setLockImpl({
    async acquireLock() {
      return { acquired: false, skipped: false, token: null, reason };
    },
    async releaseLock() {},
  });
}

/** Restores real Redis behaviour. */
function restoreLocks() {
  redisConfig.__setLockImpl(null);
  void previous;
}

module.exports = {
  stubLocksAlwaysAvailable,
  stubLocksFailing,
  restoreLocks,
};