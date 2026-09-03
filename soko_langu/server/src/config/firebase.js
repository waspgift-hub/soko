const admin = require('firebase-admin');
const config = require('../config');

let firebaseApp = null;

function initializeFirebase() {
  if (firebaseApp) return firebaseApp;

  try {
    if (config.firebase.serviceAccountJson) {
      const serviceAccount = JSON.parse(config.firebase.serviceAccountJson);
      firebaseApp = admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
    } else if (config.firebase.projectId && config.firebase.privateKey && config.firebase.clientEmail) {
      firebaseApp = admin.initializeApp({
        credential: admin.credential.cert({
          projectId: config.firebase.projectId,
          privateKey: config.firebase.privateKey,
          clientEmail: config.firebase.clientEmail,
        }),
      });
    } else {
      console.warn('[Firebase] No credentials provided');
      return null;
    }

    console.log('[Firebase] Initialized');
    return firebaseApp;
  } catch (error) {
    console.error('[Firebase] Initialization failed:', error.message);
    return null;
  }
}

function getFirebaseApp() {
  if (!firebaseApp) {
    initializeFirebase();
  }
  return firebaseApp;
}

function getFirebaseAuth() {
  const app = getFirebaseApp();
  return app ? admin.auth() : null;
}

function getFirebaseFirestore() {
  const app = getFirebaseApp();
  return app ? admin.firestore() : null;
}

module.exports = {
  initializeFirebase,
  getFirebaseApp,
  getFirebaseAuth,
  getFirebaseFirestore,
};
