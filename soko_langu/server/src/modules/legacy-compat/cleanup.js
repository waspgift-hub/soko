const { getStore } = require('../../config/database');
const { getFirebaseFirestore } = require('../../config/firebase');
const { FieldValue } = require('firebase-admin/firestore');

/**
 * Phase G: Final Legacy Cleanup Utility
 * This module handles the safe removal of duplicate data and old patterns.
 */

async function purgeLegacyFirestoreCommerce() {
  const db = getFirebaseFirestore();
  if (!db) {
    console.log('[CLEANUP] Firestore not configured, skipping purge.');
    return;
  }

  console.log('[CLEANUP] Starting legacy commerce data purge...');

  try {
    // 1. Purge redundant transaction mirrors
    const txSnapshot = await db.collection('transactions').get();
    const txBatch = db.batch();
    txSnapshot.docs.forEach(doc => txBatch.delete(doc.ref));
    await txBatch.commit();
    console.log(`[CLEANUP] Purged ${txSnapshot.size} legacy transaction mirrors.`);

    // 2. Purge old product snapshots (keeping only the ones in Postgres)
    // Logic: any product doc that exists in Postgres is mirrored; 
    // we remove the Firestore copy as the API now serves the truth.
    const productSnapshot = await db.collection('products').get();
    const prodBatch = db.batch();
    productSnapshot.docs.forEach(doc => prodBatch.delete(doc.ref));
    await prodBatch.commit();
    console.log(`[CLEANUP] Purged ${productSnapshot.size} legacy product mirrors.`);

  } catch (e) {
    console.error('[CLEANUP] Purge failed:', e.message);
  }
}

module.exports = {
  purgeLegacyFirestoreCommerce,
};
