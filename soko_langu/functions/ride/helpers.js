const admin = require('firebase-admin');
const functions = require('firebase-functions');

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;

const RIDE_COLLECTIONS = {
  drivers: 'ride_drivers',
  vehicles: 'ride_vehicles',
  driverDocuments: 'ride_driver_documents',
  driverLocations: 'ride_driver_locations',
  requests: 'ride_requests',
  trips: 'ride_trips',
  tripEvents: 'ride_trip_events',
  gpsHistory: 'ride_gps_history',
  ratings: 'ride_ratings',
  receipts: 'ride_receipts',
  cancellations: 'ride_cancellations',
  earnings: 'ride_earnings',
  analytics: 'ride_analytics',
  logs: 'ride_logs',
};

const RIDE_STATUS = {
  REQUESTED: 'requested',
  SEARCHING: 'searching',
  DRIVER_FOUND: 'driver_found',
  DRIVER_ACCEPTED: 'driver_accepted',
  DRIVER_ARRIVING: 'driver_arriving',
  DRIVER_ARRIVED: 'driver_arrived',
  TRIP_STARTED: 'trip_started',
  IN_PROGRESS: 'in_progress',
  DESTINATION_REACHED: 'destination_reached',
  TRIP_COMPLETED: 'trip_completed',
  PAYMENT_COMPLETED: 'payment_completed',
  RECEIPT_GENERATED: 'receipt_generated',
  CANCELLED: 'cancelled',
};

const DRIVER_STATUS = {
  OFFLINE: 'offline',
  ONLINE: 'online',
  BUSY: 'busy',
  LOCKED: 'locked',
};

function log(level, message, data = {}) {
  const entry = { level, message, timestamp: Timestamp.now(), ...data };
  db.collection(RIDE_COLLECTIONS.logs).add(entry).catch(() => {});
  if (level === 'error') {
    console.error(`[RIDE] ${message}`, JSON.stringify(data));
  } else {
    console.log(`[RIDE] ${message}`, JSON.stringify(data));
  }
}

function generateIdempotencyKey() {
  return `${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

async function notifyUser(uid, title, body, data = {}) {
  const topic = `user_${uid}`;
  const msg = {
    topic,
    notification: { title, body },
    data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
    android: { priority: 'high', notification: { sound: 'default' } },
    apns: { payload: { aps: { sound: 'default' } } },
  };
  try {
    await admin.messaging().send(msg);
  } catch {
    try {
      const userDoc = await db.collection('users').doc(uid).get();
      const token = userDoc.data()?.fcmToken;
      if (token) {
        await admin.messaging().send({ ...msg, topic: undefined, token });
      }
    } catch {
      // Token stale
    }
  }
  try {
    await db.collection('notifications').add({
      userId: uid, title, body, data, isRead: false, createdAt: FieldValue.serverTimestamp(),
    });
  } catch {
    // Non-critical
  }
}

async function getDriver(driverId) {
  const doc = await db.collection(RIDE_COLLECTIONS.drivers).doc(driverId).get();
  return doc.exists ? { id: doc.id, ...doc.data() } : null;
}

async function getRideRequest(requestId) {
  const doc = await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).get();
  return doc.exists ? { id: doc.id, ...doc.data() } : null;
}

async function getTrip(tripId) {
  const doc = await db.collection(RIDE_COLLECTIONS.trips).doc(tripId).get();
  return doc.exists ? { id: doc.id, ...doc.data() } : null;
}

async function addTripEvent(tripId, event, data = {}) {
  await db.collection(RIDE_COLLECTIONS.tripEvents).add({
    tripId, event, data, timestamp: FieldValue.serverTimestamp(),
  });
}

module.exports = {
  RIDE_COLLECTIONS,
  RIDE_STATUS,
  DRIVER_STATUS,
  db,
  FieldValue,
  Timestamp,
  log,
  generateIdempotencyKey,
  notifyUser,
  getDriver,
  getRideRequest,
  getTrip,
  addTripEvent,
};
