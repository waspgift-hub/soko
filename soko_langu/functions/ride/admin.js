const functions = require('firebase-functions');
const { RIDE_COLLECTIONS, RIDE_STATUS, db, FieldValue, Timestamp } = require('./helpers');

async function getRideAdminStats(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const adminDoc = await db.collection('users').doc(context.auth.uid).get();
  const isAdmin = adminDoc.data()?.isAdmin === true ||
    context.auth.token?.admin === true;
  if (!isAdmin) {
    throw new functions.https.HttpsError('permission-denied', 'Admin only');
  }

  const now = Timestamp.now();
  const todayStart = new Date(now.toDate().setHours(0, 0, 0, 0));
  const todayEnd = new Date(now.toDate().setHours(23, 59, 59, 999));
  const todayStartTs = Timestamp.fromDate(todayStart);
  const todayEndTs = Timestamp.fromDate(todayEnd);

  const weekStart = new Date(now.toDate());
  weekStart.setDate(weekStart.getDate() - weekStart.getDay());
  weekStart.setHours(0, 0, 0, 0);

  const activeStatuses = [
    RIDE_STATUS.DRIVER_ACCEPTED, RIDE_STATUS.DRIVER_ARRIVING,
    RIDE_STATUS.DRIVER_ARRIVED, RIDE_STATUS.TRIP_STARTED,
    RIDE_STATUS.IN_PROGRESS,
  ];

  const [
    activeTripsSnap,
    onlineDriversSnap,
    todayCompletedSnap,
    todayCancelledSnap,
    totalDriversSnap,
    pendingRequestsSnap,
    recentTripsSnap,
    allCancellationsSnap,
    ratingsSnap,
  ] = await Promise.all([
    db.collection(RIDE_COLLECTIONS.trips)
      .where('status', 'in', activeStatuses)
      .get(),
    db.collection(RIDE_COLLECTIONS.driverLocations)
      .where('status', '==', 'online')
      .get(),
    db.collection(RIDE_COLLECTIONS.trips)
      .where('status', '==', RIDE_STATUS.TRIP_COMPLETED)
      .where('completedAt', '>=', todayStartTs)
      .where('completedAt', '<=', todayEndTs)
      .get(),
    db.collection(RIDE_COLLECTIONS.cancellations)
      .where('createdAt', '>=', todayStartTs)
      .where('createdAt', '<=', todayEndTs)
      .get(),
    db.collection(RIDE_COLLECTIONS.drivers).get(),
    db.collection(RIDE_COLLECTIONS.requests)
      .where('status', 'in', [RIDE_STATUS.REQUESTED, RIDE_STATUS.SEARCHING])
      .get(),
    db.collection(RIDE_COLLECTIONS.trips)
      .orderBy('createdAt', 'desc')
      .limit(50)
      .get(),
    db.collection(RIDE_COLLECTIONS.cancellations).get(),
    db.collection(RIDE_COLLECTIONS.ratings).get(),
  ]);

  const todayRevenue = todayCompletedSnap.docs.reduce(
    (sum, doc) => sum + (doc.data().fare || 0), 0
  );

  const cancelByReason = {};
  allCancellationsSnap.docs.forEach(doc => {
    const reason = doc.data().reason || 'unknown';
    cancelByReason[reason] = (cancelByReason[reason] || 0) + 1;
  });

  const driverRatings = {};
  ratingsSnap.docs.forEach(doc => {
    const d = doc.data();
    const driverId = d.driverId;
    if (!driverRatings[driverId]) {
      driverRatings[driverId] = { total: 0, count: 0 };
    }
    driverRatings[driverId].total += d.rating || 0;
    driverRatings[driverId].count++;
  });

  const driverAvgRatings = {};
  Object.entries(driverRatings).forEach(([id, r]) => {
    driverAvgRatings[id] = r.count > 0 ? Math.round((r.total / r.count) * 10) / 10 : 0;
  });

  const topDrivers = Object.entries(driverAvgRatings)
    .filter(([, r]) => r >= 4.5)
    .sort(([, a], [, b]) => b - a)
    .slice(0, 10)
    .map(([id, rating]) => ({ driverId: id, rating }));

  const cancellationRate = totalDriversSnap.size > 0
    ? Math.round((allCancellationsSnap.size / totalDriversSnap.size) * 100) / 100
    : 0;

  const onlineDriverIds = new Set(onlineDriversSnap.docs.map(d => d.id));
  const onlineDrivers = [];
  for (const doc of onlineDriversSnap.docs) {
    const loc = doc.data();
    const driverDoc = await db.collection(RIDE_COLLECTIONS.drivers).doc(doc.id).get();
    const driver = driverDoc.exists ? driverDoc.data() : {};
    onlineDrivers.push({
      driverId: doc.id,
      displayName: driver.displayName || 'Unknown',
      phone: driver.phone || '',
      latitude: loc.latitude,
      longitude: loc.longitude,
      vehicleModel: driver.vehicleModel || '',
      vehicleReg: driver.vehicleReg || '',
      rating: driverAvgRatings[doc.id] || 0,
      totalRides: driver.totalRides || 0,
      lastUpdated: loc.updatedAt || loc.timestamp,
    });
  }

  const recentTrips = recentTripsSnap.docs.map(doc => ({
    id: doc.id,
    ...doc.data(),
  }));

  return {
    activeTrips: activeTripsSnap.docs.map(d => ({ id: d.id, ...d.data() })),
    activeTripsCount: activeTripsSnap.size,
    onlineDriversCount: onlineDriversSnap.size,
    onlineDrivers,
    totalDriversCount: totalDriversSnap.size,
    todayCompletedTrips: todayCompletedSnap.size,
    todayRevenue,
    todayCancellations: todayCancelledSnap.size,
    pendingRequests: pendingRequestsSnap.size,
    cancellationRate,
    cancelByReason,
    topDrivers,
    recentTrips,
  };
}

module.exports = { getRideAdminStats };
