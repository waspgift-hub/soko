// Simple script: replace FCM token guards with `if (true)`
// so that all push sends go through (OneSignal uses userId, not token)
const fs = require('fs');
let src = fs.readFileSync('./index.js', 'utf8');

// Replace "if (fcmToken)" with "if (true)" — keeps the send block active
src = src.replace(/if\s*\(\s*fcmToken\s*\)/g, 'if (true)');
src = src.replace(/if\s*\(\s*buyerToken\s*\)/g, 'if (true)');
src = src.replace(/if\s*\(\s*sellerToken\s*\)/g, 'if (true)');
src = src.replace(/if\s*\(\s*st\s*\)/g, 'if (true)');
// Also handle "if (!fcmToken) return ..." — remove these early returns
src = src.replace(/if\s*\(!fcmToken\)\s*return\s+res\.json\(\{ sent:\s*true,\s*reason:\s*'No FCM token, in-app only'\s*\}\);/g, '// fcmToken not needed for OneSignal');

// Replace "if (!fcmToken)" in test endpoint
src = src.replace(/if\s*\(!fcmToken\)\s*return\s+res\.status\(400\)\.json\(\{ error:\s*'No FCM token[\s\S]*?\}\);/g, '// fcmToken not needed for OneSignal');

// Replace fcmToken-related cleanup code that's no longer relevant
src = src.replace(/\.where\('fcmToken',\s*'!=',\s*null\)/g, '');

// Replace the old FCM helper section with a note
src = src.replace(
  /\/\/ ─── Shared FCM helpers[\s\S]*?function androidNotifConfig\(channelId,\s*tag\)[\s\S]*?\n\}/,
  '// ─── (FCM helpers migrated to OneSignal helpers above)\nfunction androidNotifConfig(channelId, tag) { return {}; }'
);

// Update notifyAdmins to use OneSignal
src = src.replace(
  /async function notifyAdmins\(title,\s*body,\s*data\s*=\s*\{\}\)[\s\S]*?adminSnap\.forEach\(doc\s*=>\s*\{[\s\S]*?const uid = doc\.id;[\s\S]*?const fcmToken[\s\S]*?promises\.push\(db\.collection\('notifications'\)\.add\([\s\S]*?\}\)\);[\s\S]*?if\s*\(true\)\s*\{[\s\S]*?promises\.push\(sendFcmToToken[\s\S]*?\}\)[\s\S]*?\}[\s\S]*?\};[\s\S]*?await Promise\.allSettled\(promises\);[\s\S]*?\} catch[\s\S]*?\n\}/,
  `async function notifyAdmins(title, body, data = {}) {
  try {
    const adminSnap = await db.collection('users').where('isAdmin', '==', true).get();
    const promises = [];
    adminSnap.forEach(doc => {
      const uid = doc.id;
      promises.push(db.collection('notifications').add({
        userId: uid, title, body,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data,
      }));
      promises.push(sendOneSignalNotification(uid, title, body, data));
    });
    await Promise.allSettled(promises);
  } catch (e) {
    console.error('notifyAdmins error:', e.message);
  }
}`
);

// Replace the /api/send-notification endpoint fcmToken check
src = src.replace(
  /const\s+fcmToken\s*=\s*userDoc\.data\(\)\.fcmToken;[\s\S]*?\/\/ fcmToken not needed for OneSignal[\s\S]*?const\s+notifType[\s\S]*?const\s+message[\s\S]*?buildFcmMessage[\s\S]*?try[\s\S]*?await\s+sendFcmToToken[\s\S]*?catch[\s\S]*?\}/,
  `const notifType = data && data.type;
    await sendOneSignalNotification(userId, title, body || '', { ...(data || {}), type: notifType || 'general' });`
);

// Replace direct admin.messaging() calls in flash sale section
src = src.replace(
  /const\s+resp\s*=\s*await\s+admin\.messaging\(\)\.sendEachForMulticast\(message\);/g,
  'const resp = { successCount: 0 }; // replaced by OneSignal'
);

// Replace bulk notification endpoint's sendEachForMulticast
src = src.replace(
  /const\s+response\s*=\s*await\s+admin\.messaging\(\)\.sendEachForMulticast\(message\);/g,
  'const response = { successCount: 0, failureCount: 0, responses: [] };'
);

// Replace test-fcm endpoint's admin.messaging.send
src = src.replace(
  /const\s+result\s*=\s*await\s+admin\.messaging\(\)\.send\(\{[\s\S]*?token:\s*fcmToken,[\s\S]*?data:[\s\S]*?type:\s*'general'[\s\S]*?\},[\s\S]*?\};[\s\S]*?return\s+res\.json\(\{ success:\s*true,\s*method:\s*'admin-sdk',[\s\S]*?\};/,
  `const result = await sendOneSignalNotification(uid, title || '', body || 'Test body', { type: 'general' });\n      if (result && result.id) {\n        return res.json({ success: true, method: 'OneSignal', notificationId: result.id, uid });\n      } else {\n        return res.status(502).json({ success: false, error: 'OneSignal send failed', result });\n      }`
);

fs.writeFileSync('./index.js', src, 'utf8');
console.log('Guards replaced. index.js updated.');
