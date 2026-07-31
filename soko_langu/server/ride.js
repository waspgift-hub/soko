const express = require('express');
const admin = require('firebase-admin');
const axios = require('axios');

const router = express.Router();
const db = admin.firestore();

async function authenticate(req) {
  const authHeader = req.headers.authorization || req.headers['Authorization'] || '';
  if (!authHeader.startsWith('Bearer ')) return null;
  try {
    const decoded = await admin.auth().verifyIdToken(authHeader.slice(7));
    return decoded;
  } catch { return null; }
}

function requireAuth(req, res) {
  const token = req.headers.authorization?.startsWith('Bearer ')
    ? req.headers.authorization.slice(7)
    : null;
  if (!token) { res.status(401).json({ error: 'Unauthorized' }); return null; }
  return token;
}

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
  REQUESTED: 'requested', SEARCHING: 'searching', DRIVER_FOUND: 'driver_found',
  DRIVER_ACCEPTED: 'driver_accepted', DRIVER_ARRIVING: 'driver_arriving',
  DRIVER_ARRIVED: 'driver_arrived', TRIP_STARTED: 'trip_started',
  IN_PROGRESS: 'in_progress', DESTINATION_REACHED: 'destination_reached',
  TRIP_COMPLETED: 'trip_completed', PAYMENT_COMPLETED: 'payment_completed',
  RECEIPT_GENERATED: 'receipt_generated', CANCELLED: 'cancelled',
};

const DRIVER_STATUS = { OFFLINE: 'offline', ONLINE: 'online', BUSY: 'busy', LOCKED: 'locked' };
const FieldValue = admin.firestore.FieldValue;
const DRIVER_PAYOUT_PERCENT = 0.85;

async function addTripEvent(tripId, event, data = {}) {
  await db.collection(RIDE_COLLECTIONS.tripEvents).add({
    tripId, event, data, timestamp: FieldValue.serverTimestamp(),
  });
}

async function notifyUser(uid, title, body, data = {}) {
  try {
    await db.collection('notifications').add({
      userId: uid, title, body, data, isRead: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch { /* non-critical */ }
  // FCM push via OneSignal handled by listener.js
}

function calculateDistance(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

const VEHICLE_TYPES = {
  bike: { baseFare: 1000, perKm: 500, perMin: 100, minFare: 2000, icon: 'pedal_bike' },
  car: { baseFare: 2000, perKm: 800, perMin: 200, minFare: 3500, icon: 'directions_car' },
  van: { baseFare: 3000, perKm: 1000, perMin: 250, minFare: 5000, icon: 'airport_shuttle' },
  premium: { baseFare: 5000, perKm: 1500, perMin: 350, minFare: 8000, icon: 'stars' },
};

function calculateFare(distanceKm, durationMin, vehicleType, surge = 1.0) {
  const config = VEHICLE_TYPES[vehicleType] || VEHICLE_TYPES.car;
  const raw = config.baseFare + config.perKm * distanceKm + config.perMin * durationMin;
  const withSurge = raw * surge;
  return Math.max(Math.round(withSurge), config.minFare);
}

// ─── Helper: wrap callable → Express ───
function wrap(fn) {
  return async (req, res) => {
    try {
      const decoded = await authenticate(req);
      if (!decoded) return res.status(401).json({ error: 'Unauthorized' });
      const result = await fn(req.body || {}, { auth: { uid: decoded.uid }, rawRequest: req });
      res.json(result);
    } catch (e) {
      console.error(`[RIDE] ${fn.name || 'handler'} error:`, e.message);
      res.status(400).json({ error: e.message });
    }
  };
}

function wrapAdmin(fn) {
  return async (req, res) => {
    try {
      const decoded = await authenticate(req);
      if (!decoded) return res.status(401).json({ error: 'Unauthorized' });
      const userDoc = await db.collection('users').doc(decoded.uid).get();
      if (userDoc.data()?.isAdmin !== true) {
        return res.status(403).json({ error: 'Admin only' });
      }
      const result = await fn(req.body || {}, { auth: { uid: decoded.uid } });
      res.json(result);
    } catch (e) {
      console.error(`[RIDE ADMIN] ${fn.name} error:`, e.message);
      res.status(400).json({ error: e.message });
    }
  };
}

// ════════════════════════════════════════════════════════════
// PRICING
// ════════════════════════════════════════════════════════════
router.post('/estimate-fare', async (req, res) => {
  try {
    const { pickupLat, pickupLng, dropoffLat, dropoffLng, vehicleType = 'car' } = req.body;
    if (pickupLat == null || pickupLng == null || dropoffLat == null || dropoffLng == null) {
      return res.status(400).json({ error: 'pickupLat, pickupLng, dropoffLat, dropoffLng required' });
    }
    const distance = calculateDistance(pickupLat, pickupLng, dropoffLat, dropoffLng);
    const durationMin = Math.max(Math.round(distance / 40 * 60), 5);
    const now = new Date();
    const hour = now.getHours();
    const isPeak = (hour >= 7 && hour <= 9) || (hour >= 16 && hour <= 19);
    const surge = isPeak ? 1.2 : 1.0;

    const fares = {};
    for (const [type] of Object.entries(VEHICLE_TYPES)) {
      fares[type] = calculateFare(distance, durationMin, type, surge);
    }

    res.json({
      distance: Math.round(distance * 100) / 100,
      durationMin,
      surge,
      isPeak,
      fares,
      vehicleTypes: Object.entries(VEHICLE_TYPES).map(([k, v]) => ({ type: k, ...v })),
    });
  } catch (e) {
    console.error('[RIDE] estimate-fare error:', e.message);
    res.status(400).json({ error: e.message });
  }
});

// ════════════════════════════════════════════════════════════
// DRIVER
// ════════════════════════════════════════════════════════════
router.post('/register-driver', wrap(async (data, ctx) => {
  const uid = ctx.auth.uid;
  const { displayName, phone, vehicleType, vehicleModel, vehicleReg, vehicleColor } = data;
  if (!displayName || !phone || !vehicleType) {
    throw new Error('displayName, phone, and vehicleType required');
  }
  const existing = await db.collection(RIDE_COLLECTIONS.drivers).doc(uid).get();
  if (existing.exists) throw new Error('Driver already registered');

  await db.collection(RIDE_COLLECTIONS.drivers).doc(uid).set({
    userId: uid, displayName, phone, vehicleType, vehicleModel: vehicleModel || '',
    vehicleReg: vehicleReg || '', vehicleColor: vehicleColor || '',
    status: DRIVER_STATUS.OFFLINE, rating: 5.0, ratingCount: 0,
    totalRides: 0, totalEarnings: 0, currentTripId: null,
    currentRequestId: null, createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { success: true, driverId: uid };
}));

router.post('/update-driver-status', wrap(async (data, ctx) => {
  const uid = ctx.auth.uid;
  const { status } = data;
  if (![DRIVER_STATUS.ONLINE, DRIVER_STATUS.OFFLINE].includes(status)) {
    throw new Error('Status must be online or offline');
  }
  await db.collection(RIDE_COLLECTIONS.drivers).doc(uid).update({
    status, updatedAt: FieldValue.serverTimestamp(),
  });
  if (status === DRIVER_STATUS.ONLINE) {
    await db.collection(RIDE_COLLECTIONS.driverLocations).doc(uid).set({
      status: DRIVER_STATUS.ONLINE, updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  } else {
    await db.collection(RIDE_COLLECTIONS.driverLocations).doc(uid).delete().catch(() => {});
  }
  return { success: true, status };
}));

router.post('/get-driver-profile', wrap(async (data, ctx) => {
  const uid = ctx.auth.uid;
  const doc = await db.collection(RIDE_COLLECTIONS.drivers).doc(uid).get();
  if (!doc.exists) throw new Error('Driver not found');
  return { driver: { id: doc.id, ...doc.data() } };
}));

router.post('/get-driver-earnings', wrap(async (data, ctx) => {
  const uid = ctx.auth.uid;
  // single-field filter only, to avoid requiring a composite index; totals computed in JS
  const snap = await db.collection(RIDE_COLLECTIONS.earnings)
    .where('driverId', '==', uid)
    .limit(1000).get();
  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfWeek = new Date(startOfToday);
  startOfWeek.setDate(startOfToday.getDate() - startOfToday.getDay());
  const earnings = [];
  let total = 0, today = 0, week = 0;
  for (const d of snap.docs) {
    const e = d.data();
    const amt = e.amount || 0;
    total += amt;
    const ts = e.createdAt && typeof e.createdAt.toDate === 'function' ? e.createdAt.toDate() : null;
    if (ts && ts >= startOfToday) today += amt;
    if (ts && ts >= startOfWeek) week += amt;
    earnings.push({ id: d.id, ...e });
  }
  earnings.sort((a, b) => {
    const ta = a.createdAt && typeof a.createdAt.toMillis === 'function' ? a.createdAt.toMillis() : 0;
    const tb = b.createdAt && typeof b.createdAt.toMillis === 'function' ? b.createdAt.toMillis() : 0;
    return tb - ta;
  });
  return { earnings, total, today, week, count: earnings.length };
}));

// ════════════════════════════════════════════════════════════
// RIDER
// ════════════════════════════════════════════════════════════
router.post('/create-ride-request', wrap(async (data, ctx) => {
  const uid = ctx.auth.uid;
  const { pickupLat, pickupLng, pickupName, dropoffLat, dropoffLng, dropoffName, vehicleType = 'car' } = data;
  if (pickupLat == null || pickupLng == null || dropoffLat == null || dropoffLng == null) {
    throw new Error('pickup and dropoff coordinates required');
  }

  const existing = await db.collection(RIDE_COLLECTIONS.requests)
    .where('riderId', '==', uid)
    .where('status', 'in', [RIDE_STATUS.REQUESTED, RIDE_STATUS.SEARCHING, RIDE_STATUS.DRIVER_FOUND, RIDE_STATUS.DRIVER_ACCEPTED])
    .limit(1).get();
  if (!existing.empty) {
    throw new Error('You already have an active ride request');
  }

  const distance = calculateDistance(pickupLat, pickupLng, dropoffLat, dropoffLng);
  const durationMin = Math.max(Math.round(distance / 40 * 60), 5);
  const now = new Date();
  const hour = now.getHours();
  const isPeak = (hour >= 7 && hour <= 9) || (hour >= 16 && hour <= 19);
  const surge = isPeak ? 1.2 : 1.0;
  const fare = calculateFare(distance, durationMin, vehicleType, surge);
  const fareBreakdown = {
    baseFare: VEHICLE_TYPES[vehicleType].baseFare,
    distanceFare: Math.round(VEHICLE_TYPES[vehicleType].perKm * distance),
    timeFare: Math.round(VEHICLE_TYPES[vehicleType].perMin * durationMin),
    surgeMultiplier: surge,
    surgeAmount: Math.round(fare - (fare / surge)),
    total: fare,
  };

  const reqRef = await db.collection(RIDE_COLLECTIONS.requests).add({
    riderId: uid, pickupLat, pickupLng, pickupName: pickupName || 'Pickup',
    dropoffLat, dropoffLng, dropoffName: dropoffName || 'Dropoff',
    vehicleType, status: RIDE_STATUS.REQUESTED, fare, fareBreakdown,
    distance: Math.round(distance * 100) / 100, durationMin,
    createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
  });

  // Match a nearby driver before responding so the rider sees driver_found immediately
  let matchedStatus = RIDE_STATUS.SEARCHING;
  try {
    const matched = await matchDrivers(reqRef.id);
    if (matched) matchedStatus = RIDE_STATUS.DRIVER_FOUND;
  } catch (e) {
    console.error('[RIDE] match after create failed:', e.message);
  }

  return {
    requestId: reqRef.id, fare, fareBreakdown, distance,
    durationMin, surge, isPeak, status: matchedStatus,
  };
}));

router.post('/get-nearby-drivers', wrap(async (data, ctx) => {
  const { latitude, longitude, radiusKm = 5 } = data;
  if (latitude == null || longitude == null) throw new Error('latitude and longitude required');
  const latDelta = radiusKm / 111;
  const lngDelta = radiusKm / (111 * Math.cos((latitude * Math.PI) / 180));
  const snap = await db.collection(RIDE_COLLECTIONS.driverLocations)
    .where('status', '==', DRIVER_STATUS.ONLINE)
    .where('latitude', '>=', latitude - latDelta)
    .where('latitude', '<=', latitude + latDelta)
    .get();
  const drivers = [];
  for (const doc of snap.docs) {
    const loc = doc.data();
    const dist = calculateDistance(latitude, longitude, loc.latitude, loc.longitude);
    if (dist <= radiusKm) {
      const driverDoc = await db.collection(RIDE_COLLECTIONS.drivers).doc(doc.id).get();
      const driver = driverDoc.exists ? driverDoc.data() : {};
      drivers.push({
        driverId: doc.id, distance: Math.round(dist * 100) / 100,
        displayName: driver.displayName, vehicleType: driver.vehicleType,
        vehicleModel: driver.vehicleModel, vehicleColor: driver.vehicleColor,
        rating: driver.rating, latitude: loc.latitude, longitude: loc.longitude,
      });
    }
  }
  drivers.sort((a, b) => a.distance - b.distance);
  return { drivers, count: drivers.length };
}));

router.post('/get-active-request', wrap(async (data, ctx) => {
  const uid = ctx.auth.uid;
  const activeStatuses = [RIDE_STATUS.REQUESTED, RIDE_STATUS.SEARCHING, RIDE_STATUS.DRIVER_FOUND, RIDE_STATUS.DRIVER_ACCEPTED, RIDE_STATUS.DRIVER_ARRIVING, RIDE_STATUS.DRIVER_ARRIVED, RIDE_STATUS.TRIP_STARTED, RIDE_STATUS.IN_PROGRESS];
  const snap = await db.collection(RIDE_COLLECTIONS.requests)
    .where('riderId', '==', uid)
    .where('status', 'in', activeStatuses)
    .orderBy('createdAt', 'desc').limit(1).get();
  if (snap.empty) return { request: null };
  const doc = snap.docs[0];
  return { request: { id: doc.id, ...doc.data() } };
}));

// ════════════════════════════════════════════════════════════
// MATCHING (called by driver)
// ════════════════════════════════════════════════════════════
router.post('/accept-ride', wrap(async (data, ctx) => {
  const driverId = ctx.auth.uid;
  const { requestId } = data;
  if (!requestId) throw new Error('requestId required');
  const request = await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).get();
  if (!request.exists) throw new Error('Request not found');
  const r = request.data();
  if (r.assignedDriverId !== driverId) throw new Error('Not assigned to you');
  if (r.status !== RIDE_STATUS.DRIVER_FOUND) throw new Error(`Ride is in ${r.status} state`);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(request.ref);
    if (!snap.exists) throw new Error('Request gone');
    const current = snap.data();
    if (current.status !== RIDE_STATUS.DRIVER_FOUND || current.assignedDriverId !== driverId) {
      throw new Error('Race condition');
    }
    tx.update(request.ref, { status: RIDE_STATUS.DRIVER_ACCEPTED, acceptedAt: FieldValue.serverTimestamp() });
    const driverRef = db.collection(RIDE_COLLECTIONS.drivers).doc(driverId);
    tx.update(driverRef, { status: DRIVER_STATUS.BUSY, currentRequestId: requestId });
    await db.collection(RIDE_COLLECTIONS.driverLocations).doc(driverId).update({ status: DRIVER_STATUS.BUSY }).catch(() => {});
  });

  await addTripEvent('pending', 'ride_accepted', { requestId, driverId, riderId: r.riderId });
  await notifyUser(r.riderId, 'Driver Accepted', 'Your driver has accepted the ride. They are on the way!', { type: 'ride', requestId, driverId });
  return { success: true, status: RIDE_STATUS.DRIVER_ACCEPTED };
}));

router.post('/reject-ride', wrap(async (data, ctx) => {
  const driverId = ctx.auth.uid;
  const { requestId } = data;
  if (!requestId) throw new Error('requestId required');
  await db.collection(RIDE_COLLECTIONS.drivers).doc(driverId).update({ status: DRIVER_STATUS.ONLINE, lockedAt: null, lockedForRequest: null });
  const request = await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).get();
  if (request.exists) {
    const r = request.data();
    if (r.status === RIDE_STATUS.DRIVER_FOUND && r.assignedDriverId === driverId) {
      await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).update({
        status: RIDE_STATUS.SEARCHING, assignedDriverId: FieldValue.delete(), matchedAt: FieldValue.delete(),
      });
      await matchDrivers(requestId, [driverId]).catch(() => {});
    }
  }
  await notifyUser(data.riderId || '', 'Driver Rejected', 'A driver rejected your request.', { type: 'ride', requestId });
  return { success: true };
}));

// ════════════════════════════════════════════════════════════
// TRIP
// ════════════════════════════════════════════════════════════
router.post('/driver-arrived', wrap(async (data, ctx) => {
  const driverId = ctx.auth.uid;
  const { requestId } = data;
  if (!requestId) throw new Error('requestId required');
  const request = await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).get();
  if (!request.exists) throw new Error('Request not found');
  const r = request.data();
  if (r.assignedDriverId !== driverId) throw new Error('Not your ride');

  await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).update({
    status: RIDE_STATUS.DRIVER_ARRIVED, driverArrivedAt: FieldValue.serverTimestamp(),
  });
  await addTripEvent('pending', 'driver_arrived', { requestId, driverId, riderId: r.riderId });
  await notifyUser(r.riderId, 'Driver Arrived', 'Your driver has arrived!', { type: 'ride', requestId, driverId });
  return { success: true, status: RIDE_STATUS.DRIVER_ARRIVED };
}));

router.post('/start-trip', wrap(async (data, ctx) => {
  const driverId = ctx.auth.uid;
  const { requestId } = data;
  if (!requestId) throw new Error('requestId required');
  const request = await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).get();
  if (!request.exists) throw new Error('Request not found');
  const r = request.data();
  if (r.assignedDriverId !== driverId) throw new Error('Not your ride');
  if (r.status !== RIDE_STATUS.DRIVER_ARRIVED && r.status !== RIDE_STATUS.DRIVER_ARRIVING) {
    throw new Error(`Cannot start from ${r.status}`);
  }

  let tripId;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(request.ref);
    if (!snap.exists) throw new Error('Request gone');
    const current = snap.data();
    if (current.status !== RIDE_STATUS.DRIVER_ARRIVED && current.status !== RIDE_STATUS.DRIVER_ARRIVING) {
      throw new Error('State changed');
    }
    tx.update(request.ref, { status: RIDE_STATUS.TRIP_STARTED, tripStartedAt: FieldValue.serverTimestamp() });
    const tripData = {
      requestId, riderId: r.riderId, driverId,
      pickupLat: r.pickupLat, pickupLng: r.pickupLng, pickupName: r.pickupName,
      dropoffLat: r.dropoffLat, dropoffLng: r.dropoffLng, dropoffName: r.dropoffName,
      vehicleType: r.vehicleType, status: RIDE_STATUS.TRIP_STARTED,
      fare: r.fare, fareBreakdown: r.fareBreakdown,
      tripStartedAt: FieldValue.serverTimestamp(),
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
    };
    const tripRef = db.collection(RIDE_COLLECTIONS.trips).doc();
    tx.set(tripRef, tripData);
    tripId = tripRef.id;
    tx.update(request.ref, { tripId });
    tx.update(db.collection(RIDE_COLLECTIONS.drivers).doc(driverId), { currentTripId: tripId });
  });

  await addTripEvent(tripId, 'trip_started', { requestId, driverId, riderId: r.riderId });
  await notifyUser(r.riderId, 'Trip Started', 'Your trip has started!', { type: 'ride', requestId, tripId, driverId });
  return { success: true, tripId, status: RIDE_STATUS.TRIP_STARTED };
}));

router.post('/complete-trip', wrap(async (data, ctx) => {
  const driverId = ctx.auth.uid;
  const { requestId, tripId } = data;
  if (!requestId && !tripId) throw new Error('requestId or tripId required');
  const request = await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).get();
  if (!request.exists) throw new Error('Request not found');
  const r = request.data();
  const tId = tripId || r.tripId;
  if (!tId) throw new Error('No active trip');

  await db.runTransaction(async (tx) => {
    const tripRef = db.collection(RIDE_COLLECTIONS.trips).doc(tId);
    const tripSnap = await tx.get(tripRef);
    if (!tripSnap.exists) throw new Error('Trip not found');
    const t = tripSnap.data();
    if (t.status !== RIDE_STATUS.TRIP_STARTED && t.status !== RIDE_STATUS.IN_PROGRESS) {
      throw new Error(`Trip is in ${t.status} state`);
    }
    const driverPayout = Math.round((r.fare || 0) * DRIVER_PAYOUT_PERCENT);
    tx.update(tripRef, { status: RIDE_STATUS.TRIP_COMPLETED, completedAt: FieldValue.serverTimestamp() });
    tx.update(request.ref, { status: RIDE_STATUS.TRIP_COMPLETED, completedAt: FieldValue.serverTimestamp() });
    tx.update(db.collection(RIDE_COLLECTIONS.drivers).doc(driverId), {
      status: DRIVER_STATUS.ONLINE, currentTripId: null, currentRequestId: null,
      totalRides: FieldValue.increment(1), totalEarnings: FieldValue.increment(driverPayout),
    });
    await db.collection(RIDE_COLLECTIONS.driverLocations).doc(driverId).update({ status: DRIVER_STATUS.ONLINE }).catch(() => {});
    const earningRef = db.collection(RIDE_COLLECTIONS.earnings).doc();
    tx.set(earningRef, {
      driverId, tripId: tId, requestId: request.id, amount: driverPayout,
      platformFee: (r.fare || 0) - driverPayout, type: 'trip_earning',
      status: 'pending', createdAt: FieldValue.serverTimestamp(),
    });
  });

  await addTripEvent(tId, 'trip_completed', { requestId, driverId, riderId: r.riderId });
  await notifyUser(r.riderId, 'Trip Completed', 'Your trip has ended. Please rate your driver!', { type: 'ride', tripId: tId, requestId });
  return { success: true, status: RIDE_STATUS.TRIP_COMPLETED, tripId: tId };
}));

router.post('/cancel-ride', wrap(async (data, ctx) => {
  const userId = ctx.auth.uid;
  const { requestId, reason } = data;
  if (!requestId) throw new Error('requestId required');
  const request = await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).get();
  if (!request.exists) throw new Error('Request not found');
  const r = request.data();
  if (r.riderId !== userId && r.assignedDriverId !== userId) throw new Error('Not your ride');

  const cancellableStates = [RIDE_STATUS.REQUESTED, RIDE_STATUS.SEARCHING, RIDE_STATUS.DRIVER_FOUND, RIDE_STATUS.DRIVER_ACCEPTED, RIDE_STATUS.DRIVER_ARRIVING, RIDE_STATUS.DRIVER_ARRIVED];
  if (!cancellableStates.includes(r.status)) throw new Error(`Cannot cancel from ${r.status}`);

  const cancelBy = r.riderId === userId ? 'rider' : 'driver';
  const driverId = r.assignedDriverId;

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(request.ref);
    if (!snap.exists) throw new Error('Request gone');
    const current = snap.data();
    if (!cancellableStates.includes(current.status)) throw new Error('State changed');
    tx.update(request.ref, {
      status: RIDE_STATUS.CANCELLED, cancelReason: reason || 'cancelled_by_user',
      cancelBy, cancelledAt: FieldValue.serverTimestamp(),
    });
    if (driverId) {
      tx.update(db.collection(RIDE_COLLECTIONS.drivers).doc(driverId), {
        status: DRIVER_STATUS.ONLINE, lockedAt: null, lockedForRequest: null, currentRequestId: null,
      });
      await db.collection(RIDE_COLLECTIONS.driverLocations).doc(driverId).update({ status: DRIVER_STATUS.ONLINE }).catch(() => {});
    }
    tx.set(db.collection(RIDE_COLLECTIONS.cancellations).doc(), {
      requestId, riderId: r.riderId, driverId, cancelBy, reason: reason || 'cancelled_by_user',
      status: r.status, createdAt: FieldValue.serverTimestamp(),
    });
  });

  if (driverId && cancelBy === 'rider') {
    await notifyUser(driverId, 'Ride Cancelled', 'The rider cancelled the ride.', { type: 'ride', requestId });
  }
  if (cancelBy === 'driver' && r.riderId) {
    await notifyUser(r.riderId, 'Ride Cancelled', 'The driver cancelled the ride.', { type: 'ride', requestId });
  }
  return { success: true, status: RIDE_STATUS.CANCELLED };
}));

router.post('/submit-rating', wrap(async (data, ctx) => {
  const userId = ctx.auth.uid;
  const { tripId, driverId, rating, comment } = data;
  if (!tripId || !driverId || !rating) throw new Error('tripId, driverId, rating required');
  if (rating < 1 || rating > 5) throw new Error('Rating 1-5');

  await db.collection(RIDE_COLLECTIONS.ratings).add({
    tripId, driverId, riderId: userId, rating, comment: comment || '',
    createdAt: FieldValue.serverTimestamp(),
  });

  const snap = await db.collection(RIDE_COLLECTIONS.ratings).where('driverId', '==', driverId).get();
  const total = snap.docs.reduce((s, d) => s + (d.data().rating || 0), 0);
  const avg = snap.size > 0 ? Math.round((total / snap.size) * 10) / 10 : 5.0;
  await db.collection(RIDE_COLLECTIONS.drivers).doc(driverId).update({ rating: avg, ratingCount: snap.size });
  return { success: true, rating };
}));

router.post('/get-ride-history', wrap(async (data, ctx) => {
  const userId = ctx.auth.uid;
  const { limit: limitVal = 20, lastDocId } = data;
  let query = db.collection(RIDE_COLLECTIONS.requests)
    .where('riderId', '==', userId)
    .orderBy('createdAt', 'desc')
    .limit(limitVal + 1);
  if (lastDocId) {
    const lastDoc = await db.collection(RIDE_COLLECTIONS.requests).doc(lastDocId).get();
    if (lastDoc.exists) query = query.startAfter(lastDoc);
  }
  const snap = await query.get();
  const requests = [];
  let hasMore = false;
  snap.docs.forEach((doc, i) => {
    if (i < limitVal) requests.push({ id: doc.id, ...doc.data() });
    else hasMore = true;
  });
  return { requests, hasMore };
}));

// ════════════════════════════════════════════════════════════
// LOCATION
// ════════════════════════════════════════════════════════════
router.post('/update-driver-location', wrap(async (data) => {
  const uid = data._uid || data.driverId;
  const { latitude, longitude } = data;
  if (latitude == null || longitude == null) throw new Error('latitude and longitude required');
  // keep busy/locked drivers marked as such; the 10s ping from the app must not flip them back to online
  const driverDoc = await db.collection(RIDE_COLLECTIONS.drivers).doc(uid).get();
  const driverStatus = driverDoc.exists ? driverDoc.data().status : DRIVER_STATUS.ONLINE;
  const locationStatus = driverStatus === DRIVER_STATUS.ONLINE ? DRIVER_STATUS.ONLINE : driverStatus;
  await db.collection(RIDE_COLLECTIONS.driverLocations).doc(uid).set({
    latitude, longitude, status: locationStatus,
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });
  return { success: true };
}));

router.post('/get-driver-location', async (req, res) => {
  try {
    const { driverId } = req.body;
    if (!driverId) return res.status(400).json({ error: 'driverId required' });
    const doc = await db.collection(RIDE_COLLECTIONS.driverLocations).doc(driverId).get();
    if (!doc.exists) return res.json({ location: null });
    res.json({ location: { driverId, ...doc.data() } });
  } catch (e) {
    res.status(400).json({ error: e.message });
  }
});

// ════════════════════════════════════════════════════════════
// ADMIN STATS
// ════════════════════════════════════════════════════════════
router.post('/admin-stats', wrapAdmin(async (data) => {
  const now = admin.firestore.Timestamp.now();
  const todayStart = admin.firestore.Timestamp.fromDate(new Date(now.toDate().setHours(0, 0, 0, 0)));
  const weekStart = admin.firestore.Timestamp.fromDate(new Date(new Date(now.toDate()).setDate(now.toDate().getDate() - now.toDate().getDay())));

  const activeStatuses = [RIDE_STATUS.DRIVER_ACCEPTED, RIDE_STATUS.DRIVER_ARRIVING, RIDE_STATUS.DRIVER_ARRIVED, RIDE_STATUS.TRIP_STARTED, RIDE_STATUS.IN_PROGRESS];
  const [activeTrips, onlineDrivers, todayCompleted, todayCancelled, totalDrivers, pendingRequests, allCancellations, allRatings] = await Promise.all([
    db.collection(RIDE_COLLECTIONS.trips).where('status', 'in', activeStatuses).get(),
    db.collection(RIDE_COLLECTIONS.driverLocations).where('status', '==', 'online').get(),
    db.collection(RIDE_COLLECTIONS.trips).where('status', '==', RIDE_STATUS.TRIP_COMPLETED).where('completedAt', '>=', todayStart).get(),
    db.collection(RIDE_COLLECTIONS.cancellations).where('createdAt', '>=', todayStart).get(),
    db.collection(RIDE_COLLECTIONS.drivers).get(),
    db.collection(RIDE_COLLECTIONS.requests).where('status', 'in', [RIDE_STATUS.REQUESTED, RIDE_STATUS.SEARCHING]).get(),
    db.collection(RIDE_COLLECTIONS.cancellations).get(),
    db.collection(RIDE_COLLECTIONS.ratings).get(),
  ]);

  const todayRevenue = todayCompleted.docs.reduce((s, d) => s + (d.data().fare || 0), 0);
  const cancelByReason = {};
  allCancellations.docs.forEach(d => { const r = d.data().reason || 'unknown'; cancelByReason[r] = (cancelByReason[r] || 0) + 1; });

  const driverRatings = {};
  allRatings.docs.forEach(d => {
    const dd = d.data(); const id = dd.driverId;
    if (!driverRatings[id]) driverRatings[id] = { total: 0, count: 0 };
    driverRatings[id].total += dd.rating || 0; driverRatings[id].count++;
  });
  const topDrivers = Object.entries(driverRatings)
    .filter(([, r]) => r.count > 0 && (r.total / r.count) >= 4.5)
    .map(([id, r]) => ({ driverId: id, rating: Math.round((r.total / r.count) * 10) / 10 }))
    .sort((a, b) => b.rating - a.rating).slice(0, 10);

  const onlineDriverDocs = await Promise.all(onlineDrivers.docs.map(async (doc) => {
    const loc = doc.data();
    const dr = await db.collection(RIDE_COLLECTIONS.drivers).doc(doc.id).get();
    const d = dr.exists ? dr.data() : {};
    return { driverId: doc.id, displayName: d.displayName || 'Unknown', phone: d.phone || '', latitude: loc.latitude, longitude: loc.longitude, vehicleModel: d.vehicleModel || '', vehicleReg: d.vehicleReg || '', rating: driverRatings[doc.id] ? Math.round((driverRatings[doc.id].total / driverRatings[doc.id].count) * 10) / 10 : 0, totalRides: d.totalRides || 0 };
  }));

  return {
    activeTrips: activeTrips.docs.map(d => ({ id: d.id, ...d.data() })),
    activeTripsCount: activeTrips.size, onlineDriversCount: onlineDrivers.size,
    onlineDrivers: onlineDriverDocs, totalDriversCount: totalDrivers.size,
    todayCompletedTrips: todayCompleted.size, todayRevenue, todayCancellations: todayCancelled.size,
    pendingRequests: pendingRequests.size, cancelByReason, topDrivers,
    cancellationRate: totalDrivers.size > 0 ? Math.round((allCancellations.size / totalDrivers.size) * 100) / 100 : 0,
  };
}));

// ════════════════════════════════════════════════════════════
// DRIVER RIDES
// ════════════════════════════════════════════════════════════
router.post('/get-driver-rides', wrap(async (data, ctx) => {
  const { driverId, limit: limitVal = 50 } = data;
  const uid = driverId || ctx.auth.uid;
  const snap = await db.collection(RIDE_COLLECTIONS.requests)
    .where('assignedDriverId', '==', uid)
    .orderBy('createdAt', 'desc')
    .limit(limitVal).get();
  const rides = snap.docs.map(d => ({ id: d.id, ...d.data() }));
  return { rides };
}));

// ════════════════════════════════════════════════════════════
// PAY RIDE
// ════════════════════════════════════════════════════════════
router.post('/pay-ride', wrap(async (data, ctx) => {
  const riderId = ctx.auth.uid;
  const { rideId } = data;
  if (!rideId) throw new Error('rideId required');
  const request = await db.collection(RIDE_COLLECTIONS.requests).doc(rideId).get();
  if (!request.exists) throw new Error('Request not found');
  const r = request.data();
  if (r.riderId !== riderId) throw new Error('Only the rider can pay for this ride');
  if (r.status === RIDE_STATUS.PAYMENT_COMPLETED) {
    return { success: true, status: RIDE_STATUS.PAYMENT_COMPLETED, alreadyPaid: true };
  }
  if (r.status !== RIDE_STATUS.TRIP_COMPLETED && r.status !== RIDE_STATUS.RECEIPT_GENERATED) {
    throw new Error(`Cannot pay from ${r.status} state`);
  }

  const fare = r.fare || 0;
  const driverPayout = Math.round(fare * DRIVER_PAYOUT_PERCENT);
  const platformFee = fare - driverPayout;
  const tId = r.tripId;
  if (!tId) throw new Error('No trip found for this ride');

  await db.runTransaction(async (tx) => {
    const riderSnap = await tx.get(db.collection('users').doc(riderId));
    if (!riderSnap.exists) throw new Error('Wallet not found');
    if ((riderSnap.data().walletBalance || 0) < fare) throw new Error('Insufficient wallet balance');

    tx.update(request.ref, {
      status: RIDE_STATUS.PAYMENT_COMPLETED, paidAt: FieldValue.serverTimestamp(),
      paymentMethod: 'Wallet', driverPayout, platformFee,
    });
    tx.update(db.collection('users').doc(riderId), {
      walletBalance: FieldValue.increment(-fare),
    });
    tx.set(db.collection('transactions').doc(), {
      type: 'ride_payment', rideId, tripId: tId,
      riderId, driverId: r.assignedDriverId || '',
      amount: fare, driverPayout, platformFee,
      status: 'completed', paymentMethod: 'Wallet',
      createdAt: FieldValue.serverTimestamp(),
    });
    if (r.assignedDriverId) {
      tx.set(db.collection('users').doc(r.assignedDriverId), {
        walletBalance: FieldValue.increment(driverPayout),
      }, { merge: true });
    }
  });

  const earnSnap = await db.collection(RIDE_COLLECTIONS.earnings).where('tripId', '==', tId).limit(5).get();
  for (const doc of earnSnap.docs) {
    await doc.ref.update({
      amount: driverPayout, platformFee,
      status: 'paid', paidAt: FieldValue.serverTimestamp(),
    });
  }

  await addTripEvent(tId, 'payment_completed', { rideId, riderId, amount: fare, driverPayout });
  await notifyUser(r.assignedDriverId || '', 'Payment Received', `You received TZS ${driverPayout.toLocaleString()} for the ride.`, { type: 'ride', rideId, amount: driverPayout });
  return { success: true, status: RIDE_STATUS.PAYMENT_COMPLETED, driverPayout, platformFee };
}));

// ════════════════════════════════════════════════════════════
// DIRECTIONS — uses free OSRM (OpenStreetMap)
// ════════════════════════════════════════════════════════════
router.get('/directions', async (req, res) => {
  try {
    const { origin, destination } = req.query;
    if (!origin || !destination) return res.status(400).json({ error: 'Missing origin or destination' });
    const [olat, olng] = origin.split(',').map(Number);
    const [dlat, dlng] = destination.split(',').map(Number);
    if (isNaN(olat) || isNaN(olng) || isNaN(dlat) || isNaN(dlng))
      return res.status(400).json({ error: 'Invalid coordinates' });
    const url = `https://router.project-osrm.org/route/v1/driving/${olng},${olat};${dlng},${dlat}?overview=full&geometries=geojson`;
    const resp = await axios.get(url, { headers: { 'User-Agent': 'SokoLangu/1.0' }, timeout: 15000 });
    const data = resp.data;
    if (data.code !== 'Ok') {
      return res.status(502).json({ error: 'OSRM route error', message: data.message || data.code });
    }
    const route = data.routes[0];
    const coords = (route.geometry?.coordinates || []).map(c => ({ lat: c[1], lng: c[0] }));
    res.json({
      distanceKm: Math.round(route.distance / 10) / 100,
      durationMin: Math.round(route.duration / 60),
      polyline: coords,
      startAddress: origin,
      endAddress: destination,
    });
  } catch (e) {
    console.error('[RIDE] Directions error:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// ════════════════════════════════════════════════════════════
// GEOCODE — uses free Nominatim (OpenStreetMap)
// ════════════════════════════════════════════════════════════
router.get('/geocode', async (req, res) => {
  try {
    const { query } = req.query;
    if (!query) return res.status(400).json({ error: 'Missing query' });
    const url = `https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(query)}&format=json&limit=5`;
    const resp = await axios.get(url, { headers: { 'User-Agent': 'SokoLangu/1.0' }, timeout: 10000 });
    const data = resp.data;
    const results = (data || []).map(r => ({
      address: r.display_name,
      lat: parseFloat(r.lat),
      lng: parseFloat(r.lon),
    }));
    res.json({ results });
  } catch (e) {
    console.error('[RIDE] Geocode error:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// ════════════════════════════════════════════════════════════
// REVERSE GEOCODE — uses free Nominatim (OpenStreetMap)
// ════════════════════════════════════════════════════════════
router.get('/reverse-geocode', async (req, res) => {
  try {
    const { latlng } = req.query;
    if (!latlng) return res.status(400).json({ error: 'Missing latlng' });
    const [lat, lng] = latlng.split(',').map(Number);
    if (isNaN(lat) || isNaN(lng)) return res.status(400).json({ error: 'Invalid latlng' });
    const url = `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json`;
    const resp = await axios.get(url, { headers: { 'User-Agent': 'SokoLangu/1.0' }, timeout: 10000 });
    const data = resp.data;
    res.json({ address: data.display_name || '' });
  } catch (e) {
    console.error('[RIDE] Reverse geocode error:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// ════════════════════════════════════════════════════════════
// MATCHING TRIGGER — auto-match drivers
// ════════════════════════════════════════════════════════════
async function matchDrivers(requestId, excludeDriverIds = []) {
  const request = await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).get();
  if (!request.exists) return false;
  const r = request.data();
  if (r.status !== RIDE_STATUS.REQUESTED && r.status !== RIDE_STATUS.SEARCHING) return false;

  await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).update({ status: RIDE_STATUS.SEARCHING });

  const latDelta = 5 / 111;
  const lngDelta = 5 / (111 * Math.cos((r.pickupLat * Math.PI) / 180));
  const nearby = await db.collection(RIDE_COLLECTIONS.driverLocations)
    .where('status', '==', DRIVER_STATUS.ONLINE)
    .where('latitude', '>=', r.pickupLat - latDelta)
    .where('latitude', '<=', r.pickupLat + latDelta)
    .get();

  const drivers = [];
  for (const doc of nearby.docs) {
    const loc = doc.data();
    const dist = calculateDistance(r.pickupLat, r.pickupLng, loc.latitude, loc.longitude);
    if (dist <= 5) drivers.push({ driverId: doc.id, distance: dist, latitude: loc.latitude, longitude: loc.longitude });
  }
  drivers.sort((a, b) => a.distance - b.distance);

  if (drivers.length === 0) {
    await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).update({
      status: RIDE_STATUS.CANCELLED, cancelReason: 'no_drivers_available',
    });
    await notifyUser(r.riderId, 'No Drivers Available', 'Sorry, no drivers nearby. Please try again.', { type: 'ride', requestId });
    return false;
  }

  for (const driver of drivers.slice(0, 5)) {
    if (excludeDriverIds.includes(driver.driverId)) continue;
    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(request.ref);
        if (!snap.exists) throw new Error('gone');
        const cur = snap.data();
        if (cur.status !== RIDE_STATUS.SEARCHING) throw new Error('state changed');
        const driverSnap = await tx.get(db.collection(RIDE_COLLECTIONS.drivers).doc(driver.driverId));
        if (!driverSnap.exists || driverSnap.data().status !== DRIVER_STATUS.ONLINE) throw new Error('driver unavailable');
        tx.update(request.ref, { status: RIDE_STATUS.DRIVER_FOUND, assignedDriverId: driver.driverId, matchedAt: FieldValue.serverTimestamp() });
        tx.update(db.collection(RIDE_COLLECTIONS.drivers).doc(driver.driverId), { status: DRIVER_STATUS.LOCKED, lockedAt: FieldValue.serverTimestamp(), lockedForRequest: requestId });
      });
      return true;
    } catch { /* try next driver */ }
  }

  await db.collection(RIDE_COLLECTIONS.requests).doc(requestId).update({
    status: RIDE_STATUS.CANCELLED, cancelReason: 'drivers_unavailable',
  });
  await notifyUser(r.riderId, 'No Drivers Available', 'Could not find a driver. Please try again.', { type: 'ride', requestId });
  return false;
}

module.exports = { router, matchDrivers };
