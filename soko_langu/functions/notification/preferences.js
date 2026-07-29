const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { NOTIFICATION_CHANNELS, NOTIFICATION_TYPES } = require('./channels');

const db = admin.firestore();

async function getNotificationPreferences(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const userId = context.auth.uid;
  const doc = await db.collection('notification_preferences').doc(userId).get();
  const defaults = {};
  for (const key of Object.keys(NOTIFICATION_CHANNELS)) {
    defaults[key] = true;
  }
  for (const key of Object.keys(NOTIFICATION_TYPES)) {
    defaults[key] = true;
  }
  return { preferences: doc.exists ? { ...defaults, ...doc.data() } : defaults };
}

async function setNotificationPreferences(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const userId = context.auth.uid;
  const { preferences } = data;
  if (!preferences || typeof preferences !== 'object') {
    throw new functions.https.HttpsError('invalid-argument', 'preferences object required');
  }
  await db.collection('notification_preferences').doc(userId).set(preferences, { merge: true });
  return { success: true };
}

module.exports = { getNotificationPreferences, setNotificationPreferences };
