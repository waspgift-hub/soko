const fs = require('fs');
let src = fs.readFileSync('./index.js', 'utf8');

// Simple replacements — no complex regexes
src = src.replace(/if \(fcmToken\)/g, 'if (true)');
src = src.replace(/if \(buyerToken\)/g, 'if (true)');
src = src.replace(/if \(sellerToken\)/g, 'if (true)');
src = src.replace(/if \(st\)/g, 'if (true)');
src = src.replace(/if \(token\)/g, 'if (true)');

// Remove fcmToken field queries
src = src.replace(/\.where\('fcmToken',\s*'!=',\s*null\)/g, '');

// Remove old FCM helpers section
src = src.replace(
  '// --- Shared FCM helpers (Android data-only to Flutter/Awesome Notifications) ---',
  '// --- (FCM helpers migrated to OneSignal helpers above) ---'
);

// Remove the old implementations that conflict with new ones
// (they have duplicate function names now since we added new versions above)
src = src.replace(
  /function stringifyFcmData[\s\S]*?\n\}/,
  'function stringifyFcmData() { return {}; }\n'
);
src = src.replace(
  /function buildFcmDataPayload[\s\S]*?\n\}/,
  'function buildFcmDataPayload() { return {}; }\n'
);

// Remove the old sendFcmToToken (since we added a new one above)
// but only the old FCM-specific one, not the backward-compat one
src = src.replace(
  /async function sendFcmToToken\(message, userIdForCleanup = null\) \{[\s\S]*?\n\}/,
  '// sendFcmToToken moved to OneSignal helpers above\n'
);

// Remove androidNotifConfig
src = src.replace(
  /function androidNotifConfig[\s\S]*?\n\}/,
  'function androidNotifConfig() { return {}; }\n'
);

fs.writeFileSync('./index.js', src, 'utf8');
console.log('done');
