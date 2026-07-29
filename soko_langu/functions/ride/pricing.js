const functions = require('firebase-functions');
const { RIDE_COLLECTIONS, db, log } = require('./helpers');

const BASE_FARE = 2000;
const PER_KM_RATE = 500;
const PER_MIN_RATE = 100;
const MIN_FARE = 2500;
const NIGHT_SURGE_MULTIPLIER = 1.25;
const RAIN_SURGE_MULTIPLIER = 1.15;
const PEAK_HOUR_MULTIPLIER = 1.2;

const PEAK_HOURS = [
  { start: 6, end: 9 },
  { start: 16, end: 20 },
];

function isPeakHour() {
  const hour = new Date().getHours();
  return PEAK_HOURS.some(p => hour >= p.start && hour < p.end);
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

async function calculateFare(pickupLat, pickupLng, dropoffLat, dropoffLng, vehicleType = 'car') {
  const distanceKm = calculateDistance(pickupLat, pickupLng, dropoffLat, dropoffLng);
  const estimatedMinutes = Math.max(Math.round((distanceKm / 30) * 60), 5);

  let base = BASE_FARE;
  let perKm = PER_KM_RATE;
  let perMin = PER_MIN_RATE;

  const vehicleConfigs = {
    bike: { base: 1000, perKm: 250, perMin: 50 },
    car: { base: 2000, perKm: 500, perMin: 100 },
    van: { base: 3000, perKm: 700, perMin: 150 },
    premium: { base: 4000, perKm: 900, perMin: 200 },
  };

  const config = vehicleConfigs[vehicleType] || vehicleConfigs.car;
  base = config.base;
  perKm = config.perKm;
  perMin = config.perMin;

  let fare = base + distanceKm * perKm + estimatedMinutes * perMin;

  let surgeMultiplier = 1.0;
  if (isPeakHour()) surgeMultiplier = Math.max(surgeMultiplier, PEAK_HOUR_MULTIPLIER);
  fare *= surgeMultiplier;

  fare = Math.max(fare, MIN_FARE);
  fare = Math.round(fare / 100) * 100;

  return {
    fare,
    distanceKm: Math.round(distanceKm * 10) / 10,
    estimatedMinutes,
    base,
    distanceCost: Math.round(distanceKm * perKm),
    timeCost: Math.round(estimatedMinutes * perMin),
    surgeMultiplier,
    currency: 'TZS',
  };
}

/**
 * HTTPS Callable: estimateRideFare
 * Provides fare estimate without creating a ride request.
 */
async function estimateRideFare(data, context) {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'Login required');
  }
  const { pickupLat, pickupLng, dropoffLat, dropoffLng, vehicleType } = data;
  if (!pickupLat || !pickupLng || !dropoffLat || !dropoffLng) {
    throw new functions.https.HttpsError('invalid-argument', 'Pickup and dropoff coordinates required');
  }
  return calculateFare(pickupLat, pickupLng, dropoffLat, dropoffLng, vehicleType);
}

module.exports = {
  calculateFare,
  estimateRideFare,
  calculateDistance,
};
