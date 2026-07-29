const functions = require('firebase-functions');
const {
  RIDE_COLLECTIONS, DRIVER_STATUS,
  db, FieldValue, Timestamp, log,
} = require('./helpers');

/**
 * Register a new driver.
 */
async function registerDriver(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const uid = context.auth.uid;
  const {
    displayName, phone, vehicleModel, vehicleColor,
    vehicleReg, licenseNumber, vehicleType = 'car',
  } = data;

  if (!displayName || !phone || !vehicleModel || !vehicleReg || !licenseNumber) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Required fields: displayName, phone, vehicleModel, vehicleReg, licenseNumber'
    );
  }

  const existing = await db.collection(RIDE_COLLECTIONS.drivers).doc(uid).get();
  if (existing.exists) {
    throw new functions.https.HttpsError('already-exists', 'Driver already registered');
  }

  const driverData = {
    uid,
    displayName,
    phone,
    vehicleType,
    vehicleModel,
    vehicleColor: vehicleColor || '',
    vehicleReg,
    licenseNumber,
    status: DRIVER_STATUS.OFFLINE,
    totalRides: 0,
    totalEarnings: 0,
    rating: 5.0,
    ratingCount: 0,
    registeredAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  await db.collection(RIDE_COLLECTIONS.drivers).doc(uid).set(driverData);

  await db.collection(RIDE_COLLECTIONS.vehicles).doc(uid).set({
    driverId: uid,
    model: vehicleModel,
    color: vehicleColor || '',
    registration: vehicleReg,
    type: vehicleType,
    registeredAt: FieldValue.serverTimestamp(),
  });

  await db.collection(RIDE_COLLECTIONS.driverLocations).doc(uid).set({
    driverId: uid,
    status: DRIVER_STATUS.OFFLINE,
    latitude: null,
    longitude: null,
    lastUpdated: FieldValue.serverTimestamp(),
  });

  log('info', `Driver ${uid} registered successfully`);
  return { success: true, driverId: uid };
}

/**
 * Update driver online/offline status.
 */
async function updateDriverStatus(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const driverId = context.auth.uid;
  const { status, latitude, longitude } = data;

  if (status !== DRIVER_STATUS.ONLINE && status !== DRIVER_STATUS.OFFLINE) {
    throw new functions.https.HttpsError('invalid-argument', 'Status must be online or offline');
  }

  const driver = await db.collection(RIDE_COLLECTIONS.drivers).doc(driverId).get();
  if (!driver.exists) {
    throw new functions.https.HttpsError('not-found', 'Driver not registered');
  }

  const batch = db.batch();

  batch.update(db.collection(RIDE_COLLECTIONS.drivers).doc(driverId), {
    status,
    updatedAt: FieldValue.serverTimestamp(),
  });

  const locData = {
    status,
    lastUpdated: FieldValue.serverTimestamp(),
  };
  if (latitude && longitude) {
    locData.latitude = latitude;
    locData.longitude = longitude;
  }
  batch.update(db.collection(RIDE_COLLECTIONS.driverLocations).doc(driverId), locData);

  await batch.commit();

  log('info', `Driver ${driverId} status updated to ${status}`);
  return { success: true, status };
}

/**
 * Get driver profile.
 */
async function getDriverProfile(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const driverId = data.driverId || context.auth.uid;
  const driver = await db.collection(RIDE_COLLECTIONS.drivers).doc(driverId).get();
  if (!driver.exists) {
    throw new functions.https.HttpsError('not-found', 'Driver not found');
  }

  return { id: driver.id, ...driver.data() };
}

/**
 * Get driver earnings summary.
 */
async function getDriverEarnings(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const driverId = data.driverId || context.auth.uid;

  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const weekStart = new Date(today);
  weekStart.setDate(weekStart.getDate() - weekStart.getDay());

  const [todayEarnings, weeklyEarnings, totalEarnings] = await Promise.all([
    db.collection(RIDE_COLLECTIONS.earnings)
      .where('driverId', '==', driverId)
      .where('createdAt', '>=', Timestamp.fromDate(today))
      .get(),
    db.collection(RIDE_COLLECTIONS.earnings)
      .where('driverId', '==', driverId)
      .where('createdAt', '>=', Timestamp.fromDate(weekStart))
      .get(),
    db.collection(RIDE_COLLECTIONS.trips)
      .where('driverId', '==', driverId)
      .where('status', '==', 'completed')
      .get(),
  ]);

  const sum = (snap) => snap.docs.reduce((acc, d) => acc + (d.data().amount || 0), 0);

  return {
    today: sum(todayEarnings),
    weekly: sum(weeklyEarnings),
    total: sum(totalEarnings),
    totalRides: totalEarnings.size,
  };
}

module.exports = {
  registerDriver,
  updateDriverStatus,
  getDriverProfile,
  getDriverEarnings,
};
