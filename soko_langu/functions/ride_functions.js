const functions = require('firebase-functions');
const admin = require('firebase-admin');

const pricing = require('./ride/pricing');
const matching = require('./ride/matching');
const driver = require('./ride/driver');
const rider = require('./ride/rider');
const trip = require('./ride/trip');
const location = require('./ride/location');
const adminModule = require('./ride/admin');

// ─── PRICING ───
exports.estimateRideFare = functions.https.onCall(pricing.estimateRideFare);

// ─── DRIVER ───
exports.registerDriver = functions.https.onCall(driver.registerDriver);
exports.updateDriverStatus = functions.https.onCall(driver.updateDriverStatus);
exports.getDriverProfile = functions.https.onCall(driver.getDriverProfile);
exports.getDriverEarnings = functions.https.onCall(driver.getDriverEarnings);

// ─── RIDER ───
exports.createRideRequest = functions.https.onCall(rider.createRideRequest);
exports.getNearbyDrivers = functions.https.onCall(rider.getNearbyDrivers);
exports.getActiveRequest = functions.https.onCall(rider.getActiveRequest);

// ─── MATCHING ───
exports.acceptRide = functions.https.onCall(matching.acceptRide);
exports.rejectRide = functions.https.onCall(matching.rejectRide);

// ─── TRIP ───
exports.driverArrived = functions.https.onCall(trip.driverArrived);
exports.startTrip = functions.https.onCall(trip.startTrip);
exports.completeTrip = functions.https.onCall(trip.completeTrip);
exports.cancelRide = functions.https.onCall(trip.cancelRide);
exports.getRideHistory = functions.https.onCall(trip.getRideHistory);
exports.submitRating = functions.https.onCall(trip.submitRating);

// ─── LOCATION ───
exports.updateDriverLocation = functions.https.onCall(location.updateDriverLocation);
exports.getDriverLocation = functions.https.onCall(location.getDriverLocation);
exports.updateTripRoute = functions.https.onCall(location.updateTripRoute);

// ─── ADMIN ───
exports.getRideAdminStats = functions.https.onCall(adminModule.getRideAdminStats);

// ─── FIRESTORE TRIGGER: match driver when ride request is created ───
exports.onRideRequestCreated = functions.firestore
  .document('ride_requests/{requestId}')
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (data.status === 'requested') {
      await matching.matchDrivers(context.params.requestId);
    }
  });

// ─── FIRESTORE TRIGGER: handle match timeout ───
exports.onRideRequestUpdated = functions.firestore
  .document('ride_requests/{requestId}')
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();

    if (after.status === 'driver_found' && before.status !== 'driver_found') {
      await new Promise(resolve => setTimeout(resolve, 15000));
      await matching.handleMatchTimeout(context.params.requestId);
    }
  });
