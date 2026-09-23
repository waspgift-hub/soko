// Data seam to the Firestore store. All exports resolve to the verified
// Firestore store, so business modules keep their BigInt/Date/$transaction
// semantics without any module changes. PostgreSQL is not on any path.
const firestoreStore = require('../services/firestore-store');

let store = null;

function getStore() {
  if (!store) {
    store = firestoreStore.getStore();
  }
  return store;
}

// Firestore has no read replica; the verified store serves reads too.
function getReadStore() {
  return getStore();
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
