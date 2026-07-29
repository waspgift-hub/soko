const functions = require('firebase-functions');
const { getNotificationPreferences, setNotificationPreferences } = require('./notification/preferences');

exports.getNotificationPreferences = functions.https.onCall(getNotificationPreferences);
exports.setNotificationPreferences = functions.https.onCall(setNotificationPreferences);
