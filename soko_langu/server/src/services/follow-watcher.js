// Follow/friend notification watcher: listens to ALL follower additions
// via collectionGroup and notifies the followed user (FOLLOW) plus both
// parties on mutual follow (FRIEND_CREATED). Runs inside the API process;
// failures never crash the server. Notifications are written with the
// admin SDK, which is the only writer allowed to notify other users.
const admin = require('firebase-admin');
const { getFirebaseFirestore } = require('../config/firebase');
const { sendOneSignalNotification } = require('../modules/legacy-compat/notify');

const NOTIFY_WINDOW_MS = 5 * 60 * 1000;
const notified = new Set();

function displayNameOf(userDoc) {
  if (!userDoc || !userDoc.exists) return 'Someone';
  const d = userDoc.data() || {};
  return d.displayName || d.name || 'Someone';
}

async function handleFollowerAdded(followerDoc) {
  try {
    const followedId = followerDoc.ref.parent.parent.id;
    const followerId = followerDoc.id;
    const key = `${followedId}<${followerId}`;
    if (notified.has(key)) return;
    notified.add(key);

    const store = getFirebaseFirestore();
    if (!store) return;

    const [followedDoc, followerDocSnap] = await Promise.all([
      store.collection('users').doc(followedId).get(),
      store.collection('users').doc(followerId).get(),
    ]);
    const followerName = displayNameOf(followerDocSnap);

    // Mutual? Check whether the followed user follows back.
    let mutual = false;
    try {
      const back = await store
        .collection('users')
        .doc(followedId)
        .collection('following')
        .doc(followerId)
        .get();
      mutual = back.exists;
    } catch (_) {}

    const notes = store.collection('notifications');
    const base = {
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (mutual) {
      const followedName = displayNameOf(followedDoc);
      await notes.add({
        ...base,
        userId: followedId,
        title: 'New friend!',
        body: `You and ${followerName} are now friends.`,
        data: { type: 'FRIEND_CREATED', actorId: followerId },
      });
      await notes.add({
        ...base,
        userId: followerId,
        title: 'New friend!',
        body: `You and ${followedName} are now friends.`,
        data: { type: 'FRIEND_CREATED', actorId: followedId },
      });
      await sendOneSignalNotification(
        followedId,
        'New friend!',
        `You and ${followerName} are now friends.`,
        { type: 'FRIEND_CREATED', actorId: followerId }
      ).catch(() => {});
    } else {
      await notes.add({
        ...base,
        userId: followedId,
        title: 'New follower',
        body: `${followerName} started following you.`,
        data: { type: 'FOLLOW', actorId: followerId },
      });
      await sendOneSignalNotification(
        followedId,
        'New follower',
        `${followerName} started following you.`,
        { type: 'FOLLOW', actorId: followerId }
      ).catch(() => {});
    }
    console.log(`[FOLLOW-WATCH] notified ${followedId} (mutual=${mutual})`);
  } catch (e) {
    console.error('[FOLLOW-WATCH] handle failed:', e.message);
  }
}

function startFollowWatcher() {
  try {
    const store = getFirebaseFirestore();
    if (!store) {
      console.log('[FOLLOW-WATCH] Firebase not configured, skipping');
      return null;
    }
    const query = store.collectionGroup('followers');
    const unsub = query.onSnapshot(
      (snap) => {
        snap.docChanges().forEach((change) => {
          if (change.type !== 'added') return;
          // Only fresh follows: startup backlog has old createTime.
          let createdMs = 0;
          try {
            createdMs = change.doc.createTime.toDate().getTime();
          } catch (_) {}
          if (!createdMs || Date.now() - createdMs > NOTIFY_WINDOW_MS) return;
          handleFollowerAdded(change.doc);
        });
      },
      (err) => console.error('[FOLLOW-WATCH] snapshot error:', err.message)
    );
    console.log('[FOLLOW-WATCH] started');
    return unsub;
  } catch (e) {
    console.error('[FOLLOW-WATCH] start failed:', e.message);
    return null;
  }
}

module.exports = { startFollowWatcher };
