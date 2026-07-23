require('dotenv').config();
const admin = require('firebase-admin');

const sa = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON);
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const ONE_SIGNAL_APP_ID = process.env.ONE_SIGNAL_APP_ID;
const ONE_SIGNAL_REST_API_KEY = process.env.ONE_SIGNAL_REST_API_KEY;

async function broadcast() {
  const title = 'Soko Vibe Tangu Wapalila!';
  const body = 'Asante kwa kutumia Soko Vibe. Tunakuletea huduma bora zaidi!';

  const usersSnap = await db.collection('users').get();
  const userIds = usersSnap.docs.map(doc => doc.id);
  let sent = 0;

  // Send via OneSignal in batches of 2000
  const BATCH_SIZE = 2000;
  for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
    const batch = userIds.slice(i, i + BATCH_SIZE);
    try {
      const resp = await fetch('https://onesignal.com/api/v1/notifications', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Basic ${ONE_SIGNAL_REST_API_KEY}` },
        body: JSON.stringify({
          app_id: ONE_SIGNAL_APP_ID,
          include_external_user_ids: batch,
          headings: { en: title },
          contents: { en: body },
          data: { type: 'general' },
          android_sound: 'soko_notification',
          android_icon: 'ic_notification',
          priority: 10,
        }),
      });
      const result = await resp.json();
      if (result.id) {
        sent += batch.length;
        console.log(`Sent to ${batch.length} users, batch id=${result.id}`);
      } else {
        console.error('Batch failed:', JSON.stringify(result));
      }
    } catch (e) {
      console.error('Batch error:', e.message);
    }
  }

  // Write in-app notifications
  let inAppCount = 0;
  const batch = db.batch();
  for (const uid of userIds) {
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

  console.log(`OneSignal pushes: ${sent}`);
  console.log(`In-app notifications: ${inAppCount}`);
  console.log('Broadcast complete!');
}

broadcast().catch(console.error);
