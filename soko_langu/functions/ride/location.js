const functions = require('firebase-functions');
const {
  RIDE_COLLECTIONS, DRIVER_STATUS, RIDE_STATUS,
  db, FieldValue, log,
} = require('./helpers');

/**
 * Update driver's GPS location (called frequently by driver app).
 */
async function updateDriverLocation(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const driverId = context.auth.uid;
  const { latitude, longitude, heading, speed, accuracy } = data;

  if (latitude === undefined || longitude === undefined) {
    throw new functions.https.HttpsError('invalid-argument', 'latitude and longitude required');
  }

  const batch = db.batch();

  batch.update(db.collection(RIDE_COLLECTIONS.driverLocations).doc(driverId), {
    latitude,
    longitude,
    heading: heading || 0,
    speed: speed || 0,
    accuracy: accuracy || 0,
    lastUpdated: FieldValue.serverTimestamp(),
  });

  batch.set(db.collection(RIDE_COLLECTIONS.gpsHistory).doc(), {
    driverId,
    latitude,
    longitude,
    heading: heading || 0,
    speed: speed || 0,
    accuracy: accuracy || 0,
    timestamp: FieldValue.serverTimestamp(),
  });

  await batch.commit();
  return { success: true };
}

/**
 * Get driver's current location.
 */
async function getDriverLocation(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const { driverId } = data;
  if (!driverId) {
    throw new functions.https.HttpsError('invalid-argument', 'driverId required');
  }

  const loc = await db.collection(RIDE_COLLECTIONS.driverLocations).doc(driverId).get();
  if (!loc.exists) {
    throw new functions.https.HttpsError('not-found', 'Driver location not found');
  }

  return { driverId, ...loc.data() };
}

/**
 * Update trip route (waypoints collected during trip).
 */
async function updateTripRoute(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const uid = context.auth.uid;
  const { tripId, latitude, longitude } = data;

  if (!tripId || latitude === undefined || longitude === undefined) {
    throw new functions.https.HttpsError('invalid-argument', 'tripId, latitude, and longitude required');
  }

  const trip = await db.collection(RIDE_COLLECTIONS.trips).doc(tripId).get();
  if (!trip.exists) {
    throw new functions.https.HttpsError('not-found', 'Trip not found');
  }

  const tripData = trip.data();
  if (tripData.driverId !== uid && tripData.riderId !== uid) {
    throw new functions.https.HttpsError('permission-denied', 'Not your trip');
  }

  await db.collection(RIDE_COLLECTIONS.gpsHistory).add({
    tripId,
    driverId: tripData.driverId,
    latitude,
    longitude,
    timestamp: FieldValue.serverTimestamp(),
    type: 'route_point',
  });

  if (tripData.status === RIDE_STATUS.TRIP_STARTED || tripData.status === RIDE_STATUS.IN_PROGRESS) {
    const origin = { lat: tripData.pickupLat, lng: tripData.pickupLng };
    const dest = { lat: tripData.dropoffLat, lng: tripData.dropoffLng };
    const current = { lat: latitude, lng: longitude };

    const toDest = calculateDistance(current.lat, current.lng, dest.lat, dest.lng);
    const toPickup = calculateDistance(current.lat, current.lng, origin.lat, origin.lng);
    const totalDist = calculateDistance(origin.lat, origin.lng, dest.lat, dest.lng);

    let statusUpdate = {};
    if (toDest < 0.05) {
      statusUpdate.status = RIDE_STATUS.DESTINATION_REACHED;
    } else if (toPickup < 0.05 && tripData.status === RIDE_STATUS.DRIVER_ARRIVING) {
      statusUpdate.status = RIDE_STATUS.DRIVER_ARRIVED;
    } else if (tripData.status === RIDE_STATUS.DRIVER_ACCEPTED && toPickup < 0.3) {
      statusUpdate.status = RIDE_STATUS.DRIVER_ARRIVING;
    }

    if (Object.keys(statusUpdate).length > 0) {
      statusUpdate.updatedAt = FieldValue.serverTimestamp();
      await db.collection(RIDE_COLLECTIONS.trips).doc(tripId).update(statusUpdate);

      if (statusUpdate.status) {
        await db.collection(RIDE_COLLECTIONS.requests).doc(tripData.requestId).update(statusUpdate);
      }
    }
  }

  return { success: true };
}

function calculateDistance(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

module.exports = {
  updateDriverLocation,
  getDriverLocation,
  updateTripRoute,
};
