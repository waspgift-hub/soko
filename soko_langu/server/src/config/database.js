// Data seam to the Firestore store. All exports resolve to the verified
// Firestore store, so business modules keep their BigInt/Date/$transaction
// semantics without any module changes.
const firestoreStore = require('../services/firestore-store');

let store = null;

/**
 * Returns the primary Store instance for reads and writes.
 * Cached as a singleton.
 */
function getStore() {
  if (!store) {
    store = firestoreStore.getStore();
  }
  return store;
}

/**
 * Returns a read-only view of the Store.
 * Attempts to perform writes (create, update, delete) via this store will throw.
 */
function getReadStore() {
  const primary = getStore();

  // Wrap the store in a proxy to intercept model access
  return new Proxy(primary, {
    get(target, prop) {
      const value = target[prop];
      if (typeof value === 'function') return value;

      // If we're accessing a model (e.g. store.user), wrap the model facade in a read-only proxy
      if (value && typeof value === 'object') {
        return new Proxy(value, {
          get(modelTarget, modelProp) {
            const method = modelTarget[modelProp];
            if (typeof method === 'function') {
              const writeMethods = ['create', 'update', 'upsert', 'delete', 'updateMany', 'deleteMany'];
              if (writeMethods.includes(modelProp)) {
                throw new Error(`[StoreFacade] Read-only violation: cannot call ${modelProp} on a read-only store.`);
              }
            }
            return method;
          }
        });
      }
      return value;
    }
  });
}

async function connectDatabase() {
  try {
    const store = getStore();
    await store.ping();
    console.log('[DB] Firestore connected');
    return store;
  } catch (error) {
    console.warn('[DB] Firestore unavailable (no credentials):', error.message);
    return null;
  }
}

async function disconnectDatabase() {
  // Firestore (firebase-admin) owns the pool; nothing to tear down here.
}

module.exports = { getStore, getReadStore, connectDatabase, disconnectDatabase };

