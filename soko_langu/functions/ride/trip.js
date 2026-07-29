const functions = require('firebase-functions');
const {
  RIDE_COLLECTIONS, RIDE_STATUS, DRIVER_STATUS,
  db, FieldValue, log,
  getDriver, getRideRequest, addTripEvent, notifyUser,
} = require('./helpers');

/**
 * Get full trip data from a request document.
 */
function buildTripFromRequest(requestId, requestData, driverData) {
  return {
    requestId,
    riderId: requestData.riderId,
    driverId: requestData.assignedDriverId,
    pickupLat: requestData.pickupLat,
    pickupLng: requestData.pickupLng,
    pickupName: requestData.pickupName,
    dropoffLat: requestData.dropoffLat,
    dropoffLng: requestData.dropoffLng,
    dropoffName: requestData.dropoffName,
    vehicleType: requestData.vehicleType,
    status: RIDE_STATUS.DRIVER_ACCEPTED,
    fare: requestData.fare,
    fareBreakdown: requestData.fareBreakdown,
    driverName: driverData?.displayName || 'Driver',
    driverPhone: driverData?.phone || '',
    vehicleModel: driverData?.vehicleModel || '',
    vehicleReg: driverData?.vehicleReg || '',
    vehicleColor: driverData?.vehicleColor || '',
    acceptedAt: FieldValue.serverTimestamp(),
    driverArrivedAt: null,
    tripStartedAt: null,
    completedAt: null,
    cancelledAt: null,
    cancelReason: null,
    cancelBy: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/**
 * Start the trip (driver confirms pickup).
 */
async function startTrip(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const driverId = context.auth.uid;
  const { requestId } = data;

  if (!requestId) {
    throw new functions.https.HttpsError('invalid-argument', 'requestId required');
  }

  const request = await getRideRequest(requestId);
  if (!request) {
    throw new functions.https.HttpsError('not-found', 'Ride request not found');
  }

  if (request.assignedDriverId !== driverId) {
    throw new functions.https.HttpsError('permission-denied', 'Not your ride');
  }

  if (request.status !== RIDE_STATUS.DRIVER_ARRIVED && request.status !== RIDE_STATUS.DRIVER_ARRIVING) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      `Cannot start trip from ${request.status} state`
    );
  }

  try {
    await db.runTransaction(async (transaction) => {
      const reqRef = db.collection(RIDE_COLLECTIONS.requests).doc(requestId);
      const snap = await transaction.get(reqRef);
      if (!snap.exists) throw new Error('Request gone');
      const current = snap.data();

      if (current.status !== RIDE_STATUS.DRIVER_ARRIVED && current.status !== RIDE_STATUS.DRIVER_ARRIVING) {
        throw new Error('Race condition: request state changed');
      }

      transaction.update(reqRef, {
        status: RIDE_STATUS.TRIP_STARTED,
        tripStartedAt: FieldValue.serverTimestamp(),
      });

      const driverData = await getDriver(driverId);

      const tripData = buildTripFromRequest(requestId, current, driverData);
      tripData.status = RIDE_STATUS.TRIP_STARTED;
      tripData.tripStartedAt = FieldValue.serverTimestamp();

      const tripRef = db.collection(RIDE_COLLECTIONS.trips).doc();
      transaction.set(tripRef, tripData);

      transaction.update(reqRef, { tripId: tripRef.id });

      const driverRef = db.collection(RIDE_COLLECTIONS.drivers).doc(driverId);
      transaction.update(driverRef, { currentTripId: tripRef.id });

      await addTripEvent(tripRef.id, 'trip_started', {
        requestId, driverId, riderId: request.riderId,
      });

      await notifyUser(
        request.riderId,
        'Trip Started',
        'Your trip has started. Sit back and relax!',
        { type: 'ride', requestId, tripId: tripRef.id, driverId }
      );

      log('info', `Trip ${tripRef.id} started for request ${requestId}`);
      return { tripId: tripRef.id, status: RIDE_STATUS.TRIP_STARTED };
    });
  } catch (error) {
    log('error', `Start trip failed: ${error.message}`, { requestId, driverId });
    throw new functions.https.HttpsError('aborted', error.message);
  }
}

/**
 * Driver marks arrival at pickup.
 */
async function driverArrived(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const driverId = context.auth.uid;
  const { requestId } = data;

  const request = await getRideRequest(requestId);
  if (!request) throw new functions.https.HttpsError('not-found', 'Request not found');
  if (request.assignedDriverId !== driverId) {
    throw new functions.https.HttpsError('permission-denied', 'Not your ride');
  }

  await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).update({
    status: RIDE_STATUS.DRIVER_ARRIVED,
    driverArrivedAt: FieldValue.serverTimestamp(),
  });

  await addTripEvent('pending', 'driver_arrived', { requestId, driverId, riderId: request.riderId });

  await notifyUser(
    request.riderId,
    'Driver Arrived',
    'Your driver has arrived at the pickup location!',
    { type: 'ride', requestId, driverId }
  );

  log('info', `Driver ${driverId} arrived for request ${requestId}`);
  return { success: true, status: RIDE_STATUS.DRIVER_ARRIVED };
}

/**
 * Complete the trip.
 */
async function completeTrip(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const driverId = context.auth.uid;
  const { requestId, tripId } = data;

  if (!requestId && !tripId) {
    throw new functions.https.HttpsError('invalid-argument', 'requestId or tripId required');
  }

  let trip;
  if (tripId) {
    const snap = await db.collection(RIDE_COLLECTIONS.trips).doc(tripId).get();
    trip = snap.exists ? { id: snap.id, ...snap.data() } : null;
  }

  const request = await getRideRequest(requestId || trip?.requestId);
  if (!request) throw new functions.https.HttpsError('not-found', 'Ride request not found');

  const tId = tripId || request.tripId;
  if (!tId) throw new functions.https.HttpsError('not-found', 'No active trip found');

  try {
    await db.runTransaction(async (transaction) => {
      const tripRef = db.collection(RIDE_COLLECTIONS.trips).doc(tId);
      const tripSnap = await transaction.get(tripRef);
      if (!tripSnap.exists) throw new Error('Trip not found');
      const tripData = tripSnap.data();

      if (tripData.status !== RIDE_STATUS.TRIP_STARTED && tripData.status !== RIDE_STATUS.IN_PROGRESS) {
        throw new Error(`Trip is in ${tripData.status} state`);
      }

      transaction.update(tripRef, {
        status: RIDE_STATUS.TRIP_COMPLETED,
        completedAt: FieldValue.serverTimestamp(),
      });

      const reqRef = db.collection(RIDE_COLLECTIONS.requests).doc(request.id);
      transaction.update(reqRef, {
        status: RIDE_STATUS.TRIP_COMPLETED,
        completedAt: FieldValue.serverTimestamp(),
      });

      const driverRef = db.collection(RIDE_COLLECTIONS.drivers).doc(driverId);
      transaction.update(driverRef, {
        status: DRIVER_STATUS.ONLINE,
        currentTripId: null,
        currentRequestId: null,
        totalRides: FieldValue.increment(1),
        totalEarnings: FieldValue.increment(request.fare || 0),
      });

      const locRef = db.collection(RIDE_COLLECTIONS.driverLocations).doc(driverId);
      transaction.update(locRef, { status: DRIVER_STATUS.ONLINE });

      const earningData = {
        driverId,
        tripId: tId,
        requestId: request.id,
        amount: request.fare || 0,
        type: 'trip_earning',
        createdAt: FieldValue.serverTimestamp(),
      };
      const earningRef = db.collection(RIDE_COLLECTIONS.earnings).doc();
      transaction.set(earningRef, earningData);

      await addTripEvent(tId, 'trip_completed', {
        requestId: request.id, driverId, riderId: request.riderId,
      });
    });

    await notifyUser(
      request.riderId,
      'Trip Completed',
      'Your trip has ended. Please rate your driver!',
      { type: 'ride', tripId: tId, requestId: request.id }
    );

    log('info', `Trip ${tId} completed for request ${request.id}`);
    return { success: true, status: RIDE_STATUS.TRIP_COMPLETED, tripId: tId };
  } catch (error) {
    log('error', `Complete trip failed: ${error.message}`, { tripId: tId });
    throw new functions.https.HttpsError('aborted', error.message);
  }
}

/**
 * Cancel a ride (by rider or driver).
 */
async function cancelRide(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const userId = context.auth.uid;
  const { requestId, reason } = data;

  if (!requestId) {
    throw new functions.https.HttpsError('invalid-argument', 'requestId required');
  }

  const request = await getRideRequest(requestId);
  if (!request) throw new functions.https.HttpsError('not-found', 'Request not found');

  if (request.riderId !== userId && request.assignedDriverId !== userId) {
    throw new functions.https.HttpsError('permission-denied', 'Not your ride');
  }

  const cancellableStates = [
    RIDE_STATUS.REQUESTED, RIDE_STATUS.SEARCHING,
    RIDE_STATUS.DRIVER_FOUND, RIDE_STATUS.DRIVER_ACCEPTED,
    RIDE_STATUS.DRIVER_ARRIVING, RIDE_STATUS.DRIVER_ARRIVED,
  ];

  if (!cancellableStates.includes(request.status)) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      `Cannot cancel ride in ${request.status} state`
    );
  }

  const cancelBy = request.riderId === userId ? 'rider' : 'driver';
  const driverId = request.assignedDriverId;

  try {
    await db.runTransaction(async (transaction) => {
      const reqRef = db.collection(RIDE_COLLECTIONS.requests).doc(requestId);
      const snap = await transaction.get(reqRef);
      if (!snap.exists) throw new Error('Request gone');
      const current = snap.data();
      if (!cancellableStates.includes(current.status)) {
        throw new Error(`Cannot cancel ride in ${current.status} state`);
      }

      transaction.update(reqRef, {
        status: RIDE_STATUS.CANCELLED,
        cancelReason: reason || 'cancelled_by_user',
        cancelBy,
        cancelledAt: FieldValue.serverTimestamp(),
      });

      if (driverId) {
        const driverRef = db.collection(RIDE_COLLECTIONS.drivers).doc(driverId);
        transaction.update(driverRef, {
          status: DRIVER_STATUS.ONLINE,
          lockedAt: null,
          lockedForRequest: null,
          currentRequestId: null,
        });

        const locRef = db.collection(RIDE_COLLECTIONS.driverLocations).doc(driverId);
        transaction.update(locRef, { status: DRIVER_STATUS.ONLINE });
      }

      const cancelRef = db.collection(RIDE_COLLECTIONS.cancellations).doc();
      transaction.set(cancelRef, {
        requestId,
        riderId: request.riderId,
        driverId,
        cancelBy,
        reason: reason || 'cancelled_by_user',
        status: request.status,
        createdAt: FieldValue.serverTimestamp(),
      });
    });

    if (driverId && cancelBy === 'rider') {
      await notifyUser(driverId, 'Ride Cancelled', 'The rider has cancelled the ride.', {
        type: 'ride', requestId,
      });
    }
    if (cancelBy === 'driver' && request.riderId) {
      await notifyUser(request.riderId, 'Ride Cancelled', 'The driver has cancelled the ride.', {
        type: 'ride', requestId,
      });
    }

    log('info', `Ride ${requestId} cancelled by ${cancelBy}`);
    return { success: true, status: RIDE_STATUS.CANCELLED };
  } catch (error) {
    log('error', `Cancel ride failed: ${error.message}`, { requestId });
    throw new functions.https.HttpsError('aborted', error.message);
  }
}

/**
 * Get ride history for a user.
 */
async function getRideHistory(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const userId = context.auth.uid;
  const { limit = 20, lastDocId } = data;

  let query = db
    .collection(RIDE_COLLECTIONS.requests)
    .where('riderId', '==', userId)
    .orderBy('createdAt', 'desc')
    .limit(limit + 1);

  if (lastDocId) {
    const lastDoc = await db.collection(RIDE_COLLECTIONS.requests).doc(lastDocId).get();
    if (lastDoc.exists) {
      query = query.startAfter(lastDoc);
    }
  }

  const snap = await query.get();

  const requests = [];
  let hasMore = false;
  snap.docs.forEach((doc, i) => {
    if (i < limit) {
      requests.push({ id: doc.id, ...doc.data() });
    } else {
      hasMore = true;
    }
  });

  return { requests, hasMore };
}

/**
 * Submit ride rating.
 */
async function submitRating(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }

  const userId = context.auth.uid;
  const { tripId, driverId, rating, comment } = data;

  if (!tripId || !driverId || !rating) {
    throw new functions.https.HttpsError('invalid-argument', 'tripId, driverId, and rating required');
  }

  if (rating < 1 || rating > 5) {
    throw new functions.https.HttpsError('invalid-argument', 'Rating must be between 1 and 5');
  }

  await db.collection(RIDE_COLLECTIONS.ratings).add({
    tripId, driverId, riderId: userId, rating, comment: comment || '',
    createdAt: FieldValue.serverTimestamp(),
  });

  const ratingsSnap = await db
    .collection(RIDE_COLLECTIONS.ratings)
    .where('driverId', '==', driverId)
    .get();

  const totalRating = ratingsSnap.docs.reduce((sum, d) => sum + (d.data().rating || 0), 0);
  const avgRating = ratingsSnap.size > 0 ? Math.round((totalRating / ratingsSnap.size) * 10) / 10 : 5.0;

  await db.collection(RIDE_COLLECTIONS.drivers).doc(driverId).update({
    rating: avgRating,
    ratingCount: ratingsSnap.size,
  });

  log('info', `Rating submitted for trip ${tripId}: ${rating}`);
  return { success: true, rating };
}

module.exports = {
  startTrip,
  driverArrived,
  completeTrip,
  cancelRide,
  getRideHistory,
  submitRating,
};
