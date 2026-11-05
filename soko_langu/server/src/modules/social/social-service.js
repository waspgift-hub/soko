const { getFirebaseFirestore } = require('../../config/firebase');
const { getStore } = require('../../config/database');

function db() {
  const d = getFirebaseFirestore();
  if (!d) throw new Error('FIRESTORE_UNAVAILABLE');
  return d;
}

function err(code, status = 400) {
  const e = new Error(code);
  e.code = code;
  e.status = status;
  return e;
}

async function isPrivate(targetId) {
  const snap = await db().collection('users').doc(targetId).get();
  if (!snap.exists) throw err('USER_NOT_FOUND', 404);
  const v = snap.data().visibility || {};
  return v.isPrivate === true;
}

async function hasBlock(a, b) {
  const [x, y] = await Promise.all([
    db().collection('users').doc(a).collection('blocked').doc(b).get(),
    db().collection('users').doc(b).collection('blocked').doc(a).get(),
  ]);
  return x.exists || y.exists;
}

async function follow(uid, targetId) {
  if (uid === targetId) throw err('CANNOT_FOLLOW_SELF');
  if (await hasBlock(uid, targetId)) throw err('BLOCKED');
  const followingRef = db().collection('users').doc(uid).collection('following').doc(targetId);
  const existing = await followingRef.get();
  if (existing.exists) return { status: 'following' };
  const reqRef = db().collection('users').doc(uid).collection('followRequestsSent').doc(targetId);
  const reqSnap = await reqRef.get();
  if (reqSnap.exists) return { status: 'requested' };

  const private = await isPrivate(targetId);
  if (private) {
    const payload = { requesterId: uid, targetId, createdAt: new Date().toISOString() };
    const batch = db().batch();
    batch.set(db().collection('users').doc(targetId).collection('followRequests').doc(uid), payload);
    batch.set(reqRef, payload);
    await batch.commit();
    return { status: 'requested' };
  }

  await db().runTransaction(async (t) => {
    const mePub = db().collection('userPublic').doc(uid);
    const themPub = db().collection('userPublic').doc(targetId);
    // Firestore transactions require every read to happen before any write.
    const [meDoc, themDoc] = await Promise.all([t.get(mePub), t.get(themPub)]);
    const now = new Date().toISOString();
    t.set(followingRef, { followerId: uid, followingId: targetId, createdAt: now });
    t.set(db().collection('users').doc(targetId).collection('followers').doc(uid), { followerId: uid, followingId: targetId, createdAt: now });
    t.set(mePub, { followingCount: (meDoc.data()?.followingCount || 0) + 1 }, { merge: true });
    t.set(themPub, { followerCount: (themDoc.data()?.followerCount || 0) + 1 }, { merge: true });
  });
  return { status: 'following' };
}

async function unfollow(uid, targetId) {
  const followingRef = db().collection('users').doc(uid).collection('following').doc(targetId);
  const snap = await followingRef.get();
  if (!snap.exists) return { status: 'not_following' };
  await db().runTransaction(async (t) => {
    const mePub = db().collection('userPublic').doc(uid);
    const themPub = db().collection('userPublic').doc(targetId);
    // Reads must precede writes inside a Firestore transaction.
    const [meDoc, themDoc] = await Promise.all([t.get(mePub), t.get(themPub)]);
    t.delete(followingRef);
    t.delete(db().collection('users').doc(targetId).collection('followers').doc(uid));
    const meCount = Math.max(0, (meDoc.data()?.followingCount || 0) - 1);
    const themCount = Math.max(0, (themDoc.data()?.followerCount || 0) - 1);
    t.set(mePub, { followingCount: meCount }, { merge: true });
    t.set(themPub, { followerCount: themCount }, { merge: true });
  });
  return { status: 'unfollowed' };
}

async function accept(uid, requesterId) {
  const reqRef = db().collection('users').doc(uid).collection('followRequests').doc(requesterId);
  const snap = await reqRef.get();
  if (!snap.exists) throw err('NO_REQUEST', 404);
  await db().runTransaction(async (t) => {
    const mePub = db().collection('userPublic').doc(uid);
    const themPub = db().collection('userPublic').doc(requesterId);
    // Reads must precede writes inside a Firestore transaction.
    const [meDoc, themDoc] = await Promise.all([t.get(mePub), t.get(themPub)]);
    const now = new Date().toISOString();
    t.delete(reqRef);
    t.delete(db().collection('users').doc(requesterId).collection('followRequestsSent').doc(uid));
    t.set(db().collection('users').doc(uid).collection('followers').doc(requesterId), { followerId: requesterId, followingId: uid, createdAt: now });
    t.set(db().collection('users').doc(requesterId).collection('following').doc(uid), { followerId: requesterId, followingId: uid, createdAt: now });
    t.set(mePub, { followerCount: (meDoc.data()?.followerCount || 0) + 1 }, { merge: true });
    t.set(themPub, { followingCount: (themDoc.data()?.followingCount || 0) + 1 }, { merge: true });
  });
  return { status: 'accepted' };
}

async function reject(uid, requesterId) {
  await db().batch().delete(db().collection('users').doc(uid).collection('followRequests').doc(requesterId))
    .delete(db().collection('users').doc(requesterId).collection('followRequestsSent').doc(uid)).commit();
  return { status: 'rejected' };
}

async function cancel(uid, targetId) {
  await db().batch().delete(db().collection('users').doc(uid).collection('followRequestsSent').doc(targetId))
    .delete(db().collection('users').doc(targetId).collection('followRequests').doc(uid)).commit();
  return { status: 'cancelled' };
}

async function block(uid, targetId) {
  if (uid === targetId) throw err('CANNOT_BLOCK_SELF');
  // remove existing follows both directions
  const iFollow = await db().collection('users').doc(uid).collection('following').doc(targetId).get();
  const theyFollow = await db().collection('users').doc(uid).collection('followers').doc(targetId).get();
  const batch = db().batch();
  batch.delete(db().collection('users').doc(uid).collection('following').doc(targetId));
  batch.delete(db().collection('users').doc(targetId).collection('followers').doc(uid));
  batch.delete(db().collection('users').doc(uid).collection('followers').doc(targetId));
  batch.delete(db().collection('users').doc(targetId).collection('following').doc(uid));
  batch.delete(db().collection('users').doc(uid).collection('followRequests').doc(targetId));
  batch.delete(db().collection('users').doc(targetId).collection('followRequests').doc(uid));
  batch.delete(db().collection('users').doc(uid).collection('followRequestsSent').doc(targetId));
  batch.delete(db().collection('users').doc(targetId).collection('followRequestsSent').doc(uid));
  if (iFollow.exists) {
    // decrement via direct set after commit (best effort); use transaction instead below
  }
  batch.set(db().collection('users').doc(uid).collection('blocked').doc(targetId), { blockerId: uid, blockedId: targetId, createdAt: new Date().toISOString() });
  await batch.commit();
  // adjust counters
  if (iFollow.exists) {
    const mePub = db().collection('userPublic').doc(uid);
    const themPub = db().collection('userPublic').doc(targetId);
    const [me, them] = await Promise.all([mePub.get(), themPub.get()]);
    await mePub.set({ followingCount: Math.max(0, (me.data()?.followingCount || 0) - 1) }, { merge: true });
    await themPub.set({ followerCount: Math.max(0, (them.data()?.followerCount || 0) - 1) }, { merge: true });
  }
  if (theyFollow.exists) {
    const mePub = db().collection('userPublic').doc(uid);
    const themPub = db().collection('userPublic').doc(targetId);
    const [me, them] = await Promise.all([mePub.get(), themPub.get()]);
    await mePub.set({ followerCount: Math.max(0, (me.data()?.followerCount || 0) - 1) }, { merge: true });
    await themPub.set({ followingCount: Math.max(0, (them.data()?.followingCount || 0) - 1) }, { merge: true });
  }
  return { status: 'blocked' };
}

async function unblock(uid, targetId) {
  await db().collection('users').doc(uid).collection('blocked').doc(targetId).delete();
  return { status: 'unblocked' };
}

module.exports = { follow, unfollow, accept, reject, cancel, block, unblock };
