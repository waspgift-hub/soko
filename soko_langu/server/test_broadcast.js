require('dotenv').config();
const admin = require('firebase-admin');

const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

async function broadcast() {
  const title = 'Soko Vibe Tangu Wapalila!';
  const body = 'Asante kwa kutumia Soko Vibe. Tunakuletea huduma bora zaidi!';

  const usersSnap = await db.collection('users').get();
  let topicSent = 0;
  let tokenSent = 0;
  let inAppCount = 0;
  const batch = db.batch();

  for (const doc of usersSnap.docs) {
    const uid = doc.id;
    const fcmToken = doc.data().fcmToken;

    if (fcmToken || uid) {
      const msg = {
        data: { title, body, type: 'general' },
        notification: { title, body },
        android: { priority: 'high', notification: { channel_id: 'general_notifications_v3', sound: 'soko_notification' } },
      };

      // Try topic first (more reliable)
      if (uid) {
        try {
          await admin.messaging().send({ ...msg, topic: `user_${uid}` });
          topicSent++;
          continue;
        } catch (e) {
          // Topic failed
        }
      }

      // Fallback to token
      if (fcmToken) {
        try {
          await admin.messaging().send({ ...msg, token: fcmToken });
          tokenSent++;
        } catch (e) {
          // Token stale
        }
      }
    }

    // In-app notification
    batch.set(db.collection('notifications').doc(), {
      userId: uid,
      title,
      body,
      data: { type: 'general' },
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    inAppCount++;
  }

  if (inAppCount > 0) await batch.commit();

  console.log(`Sent: ${topicSent} via topic, ${tokenSent} via token`);
  console.log(`In-app notifications: ${inAppCount}`);
  console.log('Broadcast complete!');
}

broadcast().catch(console.error);
