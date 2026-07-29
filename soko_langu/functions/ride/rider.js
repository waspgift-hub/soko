const functions = require('firebase-functions');
const {
  RIDE_COLLECTIONS, RIDE_STATUS,
  db, FieldValue, log, generateIdempotencyKey,
  addTripEvent, notifyUser,
} = require('./helpers');
const { calculateFare } = require('./pricing');
const { findNearbyDrivers, matchDrivers } = require('./matching');

/**
 * Create a new ride request.
 */
async function createRideRequest(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const riderId = context.auth.uid;
  const {
    pickupLat, pickupLng, pickupName,
    dropoffLat, dropoffLng, dropoffName,
    vehicleType = 'car',
    idempotencyKey,
  } = data;

  if (!pickupLat || !pickupLng || !dropoffLat || !dropoffLng) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Pickup and dropoff coordinates are required'
    );
  }

  const key = idempotencyKey || generateIdempotencyKey();

  const existingRequest = await db
    .collection(RIDE_COLLECTIONS.requests)
    .where('idempotencyKey', '==', key)
    .limit(1)
    .get();

  if (!existingRequest.empty) {
    const doc = existingRequest.docs[0];
    return { id: doc.id, ...doc.data(), duplicate: true };
  }

  const activeTrip = await db
    .collection(RIDE_COLLECTIONS.requests)
    .where('riderId', '==', riderId)
    .where('status', 'in', [
      RIDE_STATUS.REQUESTED, RIDE_STATUS.SEARCHING,
      RIDE_STATUS.DRIVER_FOUND, RIDE_STATUS.DRIVER_ACCEPTED,
      RIDE_STATUS.DRIVER_ARRIVING, RIDE_STATUS.DRIVER_ARRIVED,
      RIDE_STATUS.TRIP_STARTED, RIDE_STATUS.IN_PROGRESS,
    ])
    .limit(1)
    .get();

  if (!activeTrip.empty) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'You already have an active ride request'
    );
  }

  const fare = await calculateFare(pickupLat, pickupLng, dropoffLat, dropoffLng, vehicleType);

  const requestData = {
    riderId,
    pickupLat, pickupLng,
    pickupName: pickupName || 'Pickup Location',
    dropoffLat, dropoffLng,
    dropoffName: dropoffName || 'Dropoff Location',
    vehicleType,
    status: RIDE_STATUS.REQUESTED,
    fare: fare.fare,
    fareBreakdown: fare,
    assignedDriverId: null,
    matchedAt: null,
    acceptedAt: null,
    arrivedAt: null,
    tripStartedAt: null,
    completedAt: null,
    cancelledAt: null,
    cancelReason: null,
    cancelBy: null,
    timeoutCount: 0,
    idempotencyKey: key,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };

  const ref = await db.collection(RIDE_COLLECTIONS.requests).add(requestData);
  const requestId = ref.id;

  log('info', `Ride request ${requestId} created by rider ${riderId}`, {
    pickupLat, pickupLng, dropoffLat, dropoffLng,
  });

  matchDrivers(requestId);

  return { id: requestId, ...requestData, fare };
}

/**
 * Get nearby drivers for rider's map view.
 */
async function getNearbyDrivers(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const { latitude, longitude, radiusKm = 5 } = data;
  if (!latitude || !longitude) {
    throw new functions.https.HttpsError('invalid-argument', 'latitude and longitude required');
  }

  const drivers = await findNearbyDrivers(latitude, longitude, radiusKm);
  return { drivers };
}

/**
 * Get current active request for a rider.
 */
async function getActiveRequest(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const riderId = context.auth.uid;

  const activeStatuses = [
    RIDE_STATUS.REQUESTED, RIDE_STATUS.SEARCHING,
    RIDE_STATUS.DRIVER_FOUND, RIDE_STATUS.DRIVER_ACCEPTED,
    RIDE_STATUS.DRIVER_ARRIVING, RIDE_STATUS.DRIVER_ARRIVED,
    RIDE_STATUS.TRIP_STARTED, RIDE_STATUS.IN_PROGRESS,
  ];

  const snap = await db
    .collection(RIDE_COLLECTIONS.requests)
    .where('riderId', '==', riderId)
    .where('status', 'in', activeStatuses)
    .orderBy('createdAt', 'desc')
    .limit(1)
    .get();

  if (snap.empty) return { request: null };

  const doc = snap.docs[0];
  return { request: { id: doc.id, ...doc.data() } };
}

module.exports = {
  createRideRequest,
  getNearbyDrivers,
  getActiveRequest,
};
