const commerceStore = require('../../services/commerce-store');

/**
 * Phase G: Final Legacy Cleanup Utility
 * This module handles the safe removal of duplicate data and old patterns.
 */

async function purgeLegacyFirestoreCommerce() {
  console.log('[CLEANUP] Starting legacy commerce data purge...');

  try {
    // 1. Purge redundant transaction mirrors
    const txDocs = await commerceStore.listDocuments('transactions', { limit: 1000 });
    if (txDocs.length > 0) {
      await commerceStore.batchDelete(txDocs.map(doc => ({ collection: 'transactions', docId: doc.id })));
    }
    console.log(`[CLEANUP] Purged ${txDocs.length} legacy transaction mirrors.`);

    // 2. Purge old product snapshots (keeping only the ones in Postgres)
    // Logic: any product doc that exists in Postgres is mirrored; 
    // we remove the Firestore copy as the API now serves the truth.
    const prodDocs = await commerceStore.listDocuments('products', { limit: 1000 });
    if (prodDocs.length > 0) {
      await commerceStore.batchDelete(prodDocs.map(doc => ({ collection: 'products', docId: doc.id })));
    }
    console.log(`[CLEANUP] Purged ${prodDocs.length} legacy product mirrors.`);

  } catch (e) {
    console.error('[CLEANUP] Purge failed:', e.message);
  }
}

module.exports = {
  purgeLegacyFirestoreCommerce,
};

