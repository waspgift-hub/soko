// Server-side session revocation ("logout from all devices").
//
// WHY this exists: Firebase checkRevoked cannot be enabled here — every OTP
// sign-in uses signInWithCustomToken and the revocation check throws for
// custom-token sessions (see middleware/auth.js). So revocation is enforced
// with the token's own auth_time instead: logout-all stamps
// session_revocations/{uid}.revokedAt, and requireFreshSession rejects any
// token minted BEFORE that stamp. Refreshed ID tokens keep the session's
// original auth_time, so revocation survives silent refreshes and bites on
// every route that mounts the check (money, admin, auth-sensitive).
const { getFirebaseFirestore } = require('../config/firebase');

function revocationsCol() {
  try {
    const db = getFirebaseFirestore();
    return db ? db.collection('session_revocations') : null;
  } catch (_) {
    return null;
  }
}

// Stamps "all sessions before now are dead" for a user. Returns true when the
// stamp landed; false means no Firestore (dev without credentials) and the
// caller should surface that instead of pretending revocation happened.
async function revokeUserSessions(uid) {
  const col = revocationsCol();
  if (!col || !uid) return false;
  await col.doc(String(uid)).set({ revokedAt: Date.now() }, { merge: true });
  return true;
}

async function getSessionRevokedAt(uid) {
  try {
    const col = revocationsCol();
    if (!col || !uid) return 0;
    const snap = await col.doc(String(uid)).get();
    const v = snap.exists ? snap.data().revokedAt : 0;
    return Number(v) || 0;
  } catch (_) {
    return 0;
  }
}

// True when the session behind authTimeSec (Firebase `auth_time`, seconds)
// predates the user's revocation stamp and must be rejected.
async function isSessionRevoked(uid, authTimeSec) {
  if (!uid || !authTimeSec) return false;
  const revokedAt = await getSessionRevokedAt(uid);
  return revokedAt > 0 && Number(authTimeSec) * 1000 < revokedAt;
}

module.exports = { revokeUserSessions, getSessionRevokedAt, isSessionRevoked };
