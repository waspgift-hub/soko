// Firebase App Check verification for OTP send endpoints.
//
// Strategy: a valid `x-firebase-appcheck` (or `body.appCheckToken`) is always
// verified and an invalid one is always rejected. Whether a MISSING token is a
// hard failure is controlled by OTP_REQUIRE_APP_CHECK — default false so the
// migration to App Check doesn't lock out old app builds; set it true once the
// app-wide App Check attestation (Play Integrity / DeviceCheck) ships and the
// store builds are thin. Absent that flag, the middleware still kills the most
// common attack vector: bot/SMS-bombing clients that spoof/fake the header.
const admin = require('firebase-admin');
const { getFirebaseApp } = require('../config/firebase');

const REQUIRE = process.env.OTP_REQUIRE_APP_CHECK === 'true';

function verifyAppCheck(req, res, next) {
  const token = req.get('x-firebase-appcheck') || (req.body && req.body.appCheckToken);

  if (!token) {
    if (REQUIRE) {
      return res.status(401).json({ error: 'app_check_required', success: false });
    }
    return next();
  }

  const app = getFirebaseApp();
  if (!app) {
    return res.status(503).json({ error: 'auth_not_configured', success: false });
  }

  admin.appCheck(app)
    .verifyToken(token, { consume: false })
    .then(() => next())
    .catch((e) => {
      console.error('[APP-CHECK] token rejected:', e.message);
      res.status(401).json({ error: 'app_check_invalid', success: false });
    });
}

module.exports = { verifyAppCheck };