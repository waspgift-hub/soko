const functions = require('firebase-functions');
const {
  RIDE_COLLECTIONS, RIDE_STATUS, DRIVER_STATUS,
  db, FieldValue, Timestamp, log, generateIdempotencyKey,
  getDriver, addTripEvent, notifyUser,
} = require('./helpers');
const { calculateDistance } = require('./pricing');

const MATCH_TIMEOUT_MS = 15000;
const MAX_RETRY_DRIVERS = 5;
const SEARCH_RADIUS_KM = 5;

/**
 * Find nearby available drivers within the search radius.
 */
async function findNearbyDrivers(pickupLat, pickupLng, radiusKm = SEARCH_RADIUS_KM) {
  const latDelta = radiusKm / 111;
  const lngDelta = radiusKm / (111 * Math.cos((pickupLat * Math.PI) / 180));

  const driversQuery = await db
    .collection(RIDE_COLLECTIONS.driverLocations)
    .where('status', '==', DRIVER_STATUS.ONLINE)
    .where('latitude', '>=', pickupLat - latDelta)
    .where('latitude', '<=', pickupLat + latDelta)
    .get();

  const nearby = [];
  for (const doc of driversQuery.docs) {
    const loc = doc.data();
    const driverId = doc.id;
    const distance = calculateDistance(pickupLat, pickupLng, loc.latitude, loc.longitude);
    if (distance <= radiusKm) {
      nearby.push({ driverId, distance, latitude: loc.latitude, longitude: loc.longitude });
    }
  }

  nearby.sort((a, b) => a.distance - b.distance);
  return nearby.slice(0, MAX_RETRY_DRIVERS);
}

/**
 * Atomically lock a driver's status to prevent double assignment.
 * Uses Firestore transaction with optimistic locking.
 */
async function lockDriver(driverId, requestId) {
  try {
    await db.runTransaction(async (transaction) => {
      const driverRef = db.collection(RIDE_COLLECTIONS.drivers).doc(driverId);
      const driverSnap = await transaction.get(driverRef);
      if (!driverSnap.exists) throw new Error('Driver not found');

      const driver = driverSnap.data();
      if (driver.status !== DRIVER_STATUS.ONLINE && driver.status !== DRIVER_STATUS.LOCKED) {
        throw new Error(`Driver ${driverId} is not available (status: ${driver.status})`);
      }

      transaction.update(driverRef, {
        status: DRIVER_STATUS.LOCKED,
        lockedAt: FieldValue.serverTimestamp(),
        lockedForRequest: requestId,
      });
    });
    return true;
  } catch (error) {
    log('warn', `Failed to lock driver ${driverId}: ${error.message}`, { driverId, requestId });
    return false;
  }
}

/**
 * Unlock a driver (make them available again).
 */
async function unlockDriver(driverId) {
  try {
    await db.collection(RIDE_COLLECTIONS.drivers).doc(driverId).update({
      status: DRIVER_STATUS.ONLINE,
      lockedAt: null,
      lockedForRequest: null,
    });
  } catch (error) {
    log('error', `Failed to unlock driver ${driverId}: ${error.message}`, { driverId });
  }
}

/**
 * Match a ride request with nearby drivers.
 * Called after a ride request is created.
 */
async function matchDrivers(requestId) {
  const request = await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).get();
  if (!request.exists) {
    log('error', 'Ride request not found for matching', { requestId });
    return;
  }

  const rideData = request.data();
  if (rideData.status !== RIDE_STATUS.REQUESTED && rideData.status !== RIDE_STATUS.SEARCHING) {
    log('warn', `Ride request ${requestId} is not in matching state (${rideData.status})`);
    return;
  }

  await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).update({
    status: RIDE_STATUS.SEARCHING,
    matchingStartedAt: FieldValue.serverTimestamp(),
  });

  const nearbyDrivers = await findNearbyDrivers(rideData.pickupLat, rideData.pickupLng);
  log('info', `Found ${nearbyDrivers.length} nearby drivers for request ${requestId}`, {
    requestId, driverCount: nearbyDrivers.length,
  });

  if (nearbyDrivers.length === 0) {
    await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).update({
      status: RIDE_STATUS.CANCELLED,
      cancelReason: 'no_drivers_available',
      cancelledAt: FieldValue.serverTimestamp(),
    });
    await notifyUser(
      rideData.riderId,
      'No Drivers Available',
      'Sorry, there are no drivers nearby right now. Please try again shortly.',
      { type: 'ride', requestId }
    );
    return;
  }

  let matched = false;
  let matchedDriver = null;

  for (const driver of nearbyDrivers) {
    const locked = await lockDriver(driver.driverId, requestId);
    if (!locked) continue;

    const assigned = await tryAssignDriver(requestId, driver.driverId, rideData);
    if (assigned) {
      matched = true;
      matchedDriver = driver;
      break;
    } else {
      await unlockDriver(driver.driverId);
    }
  }

  if (!matched) {
    await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).update({
      status: RIDE_STATUS.CANCELLED,
      cancelReason: 'drivers_unavailable',
      cancelledAt: FieldValue.serverTimestamp(),
    });
    await notifyUser(
      rideData.riderId,
      'No Drivers Available',
      'We could not find an available driver. Please try again.',
      { type: 'ride', requestId }
    );
    log('warn', `No drivers could be matched for request ${requestId}`);
  }

  return matchedDriver;
}

/**
 * Try to assign a specific driver to a ride request atomically.
 * Uses transaction to prevent race conditions.
 */
async function tryAssignDriver(requestId, driverId, rideData) {
  try {
    return await db.runTransaction(async (transaction) => {
      const requestRef = db.collection(RIDE_COLLECTIONS.requests).doc(requestId);
      const requestSnap = await transaction.get(requestRef);

      if (!requestSnap.exists) return false;
      const currentRequest = requestSnap.data();

      if (currentRequest.status !== RIDE_STATUS.SEARCHING && currentRequest.status !== RIDE_STATUS.REQUESTED) {
        return false;
      }

      if (currentRequest.assignedDriverId && currentRequest.assignedDriverId !== driverId) {
        return false;
      }

      transaction.update(requestRef, {
        status: RIDE_STATUS.DRIVER_FOUND,
        assignedDriverId: driverId,
        matchedAt: FieldValue.serverTimestamp(),
      });

      return true;
    });
  } catch (error) {
    log('warn', `Assign driver ${driverId} to request ${requestId} failed: ${error.message}`);
    return false;
  }
}

/**
 * Handle ride request acceptance timeout.
 */
async function handleMatchTimeout(requestId) {
  const request = await getRequest(requestId);
  if (!request) return;

  if (request.status !== RIDE_STATUS.DRIVER_FOUND && request.status !== RIDE_STATUS.DRIVER_ACCEPTED) {
    return;
  }

  const elapsed = Date.now() - (request.matchedAt?.toMillis() || Date.now());
  if (elapsed < MATCH_TIMEOUT_MS) return;

  const driverId = request.assignedDriverId;
  if (driverId) {
    await unlockDriver(driverId);
  }

  await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).update({
    status: RIDE_STATUS.SEARCHING,
    assignedDriverId: null,
    matchedAt: null,
    timeoutCount: FieldValue.increment(1),
  });

  await matchDrivers(requestId);
}

async function getRequest(requestId) {
  const doc = await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).get();
  return doc.exists ? { id: doc.id, ...doc.data() } : null;
}

/**
 * Accept a ride request (called by driver).
 */
async function acceptRide(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const { requestId } = data;
  if (!requestId) {
    throw new functions.https.HttpsError('invalid-argument', 'requestId required');
  }

  const driverId = context.auth.uid;
  const driver = await getDriver(driverId);
  if (!driver) {
    throw new functions.https.HttpsError('not-found', 'Driver profile not found');
  }

  const request = await getRequest(requestId);
  if (!request) {
    throw new functions.https.HttpsError('not-found', 'Ride request not found');
  }

  if (request.assignedDriverId !== driverId) {
    throw new functions.https.HttpsError('failed-precondition', 'This ride was not assigned to you');
  }

  if (request.status !== RIDE_STATUS.DRIVER_FOUND) {
    throw new functions.https.HttpsError('failed-precondition', `Ride is in ${request.status} state`);
  }

  try {
    await db.runTransaction(async (transaction) => {
      const requestRef = db.collection(RIDE_COLLECTIONS.requests).doc(requestId);
      const requestSnap = await transaction.get(requestRef);
      if (!requestSnap.exists) throw new Error('Request gone');
      const current = requestSnap.data();

      if (current.status !== RIDE_STATUS.DRIVER_FOUND || current.assignedDriverId !== driverId) {
        throw new Error('Race condition: request state changed');
      }

      if (current.timeoutCount > 0 && Date.now() - (current.matchedAt?.toMillis() || 0) > MATCH_TIMEOUT_MS) {
        throw new Error('Match expired');
      }

      transaction.update(requestRef, {
        status: RIDE_STATUS.DRIVER_ACCEPTED,
        acceptedAt: FieldValue.serverTimestamp(),
      });

      const driverRef = db.collection(RIDE_COLLECTIONS.drivers).doc(driverId);
      transaction.update(driverRef, {
        status: DRIVER_STATUS.BUSY,
        currentRequestId: requestId,
      });

      const driverLocRef = db.collection(RIDE_COLLECTIONS.driverLocations).doc(driverId);
      transaction.update(driverLocRef, {
        status: DRIVER_STATUS.BUSY,
      });
    });

    await addTripEvent('pending', 'ride_accepted', {
      requestId, driverId, riderId: request.riderId,
    });

    await notifyUser(
      request.riderId,
      'Driver Accepted',
      `${driver.displayName || 'Driver'} has accepted your ride. They are on the way!`,
      { type: 'ride', requestId, driverId }
    );

    log('info', `Driver ${driverId} accepted request ${requestId}`);
    return { success: true, status: RIDE_STATUS.DRIVER_ACCEPTED };
  } catch (error) {
    log('error', `Accept ride failed: ${error.message}`, { requestId, driverId });
    throw new functions.https.HttpsError('aborted', error.message);
  }
}

/**
 * Reject a ride request (called by driver).
 */
async function rejectRide(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const { requestId } = data;
  if (!requestId) {
    throw new functions.https.HttpsError('invalid-argument', 'requestId required');
  }

  const driverId = context.auth.uid;
  const request = await getRequest(requestId);
  if (!request) {
    throw new functions.https.HttpsError('not-found', 'Ride request not found');
  }

  if (request.assignedDriverId !== driverId) {
    throw new Error('This ride was not assigned to you');
  }

  await unlockDriver(driverId);
  await notifyUser(request.riderId, 'Driver Rejected', 'A driver rejected your request. Searching for another...', {
    type: 'ride', requestId,
  });

  await matchDrivers(requestId);
  log('info', `Driver ${driverId} rejected request ${requestId}`);

  return { success: true, message: 'Ride rejected' };
}

module.exports = {
  findNearbyDrivers,
  matchDrivers,
  acceptRide,
  rejectRide,
  lockDriver,
  unlockDriver,
  handleMatchTimeout,
};
