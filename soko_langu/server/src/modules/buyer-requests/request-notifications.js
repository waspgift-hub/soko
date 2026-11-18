// Buyer-request notifications.
//
// One inbox write (`notifications`) plus one OneSignal push, reusing the
// existing delivery path rather than introducing a second notification system.
// Preference gating is best-effort: a missing prefs document means "default
// allow", and a delivery failure must never roll back the request action.
const { getFirebaseFirestore } = require('../../config/firebase');
const { createNotification } = require('../notifications/notification-service');
const { sendOneSignalNotification } = require('../legacy-compat/notify');

// Both categories already exist in the orchestrator catalogue.
function categoryFor(role) {
  return role === 'seller' ? 'seller' : 'buyer';
}

async function loadPrefs(userId) {
  try {
    const db = getFirebaseFirestore();
    if (!db) return null;
    const snap = await db.collection('user_notification_preferences').doc(userId).get();
    return snap.exists ? snap.data() : null;
  } catch (e) {
    console.error('[buyer-requests] prefs read failed:', e?.message || e);
    return null;
  }
}

function allows(prefs, category, key) {
  if (!prefs) return true;
  if (prefs.pushEnabled === false) return false;
  const categories = prefs.categoryPreferences || {};
  if (categories[category] === false) return false;
  if (key && categories[key] === false) return false;
  return true;
}

/**
 * @param {object} opts
 * @param {string} opts.userId Firebase UID (OneSignal external id).
 * @param {'buyer'|'seller'} opts.role Category used for preference gating.
 * @param {string} opts.title Localized title.
 * @param {string} opts.body Localized body.
 * @param {string} opts.type Stable machine type (`buyer_request.offer_received`).
 * @param {object} opts.data Deep-link payload; always includes requestId.
 * @param {string} [opts.preferenceKey] Optional secondary opt-out key.
 */
async function notifyUser({ userId, role = 'buyer', title, body, type, data = {}, preferenceKey = null }) {
  if (!userId || !title) return null;
  const category = categoryFor(role);
  const prefs = await loadPrefs(userId);
  const allowed = allows(prefs, category, preferenceKey);

  if (allowed) {
    // The inbox is the durable record; it is written even when push is off.
    try {
      await createNotification({
        userId,
        title,
        body,
        type: type.toUpperCase(),
        data: { ...data, route: data.route || `/buyer-requests/${data.requestId || ''}` },
      });
    } catch (e) {
      console.error('[buyer-requests] inbox write failed:', e?.message || e);
    }
    // Push is opt-out and time-insensitive for request activity; OneSignal
    // channel importance is configured on the client, not forced here.
    sendOneSignalNotification(userId, title, body, {
      ...data,
      type,
      category,
    }).catch((e) => console.error('[buyer-requests] push failed:', e?.message || e));
  }
  return { delivered: allowed };
}

function sellerViewedRequest({ buyerUid, seller, request }) {
  return notifyUser({
    userId: buyerUid,
    role: 'buyer',
    title: 'Muuzaji ameangalia ombi lako',
    body: `${seller.storeName || seller.displayName || 'Muuzaji'} imefungua ombi lako la ${request.title}.`,
    type: 'buyer_request.viewed',
    preferenceKey: 'buyerRequestViews',
    data: {
      requestId: request.id,
      sellerUid: seller.uid,
      sellerName: seller.displayName,
      sellerAvatarUrl: seller.avatarUrl,
      sellerKycApproved: Boolean(seller.kycApproved),
      screen: 'buyer_request_detail',
    },
  });
}

function offerReceived({ buyerUid, seller, request, offer }) {
  return notifyUser({
    userId: buyerUid,
    role: 'buyer',
    title: 'Ofa mpya kwenye ombi lako',
    body: `${seller.storeName || seller.displayName || 'Muuzaji'} ametuma ofa la TZS ${Number(offer.price || 0).toLocaleString('en-US')} kwa ${request.title}.`,
    type: 'buyer_request.offer_received',
    data: {
      requestId: request.id,
      offerId: offer.id,
      sellerUid: seller.uid,
      sellerKycApproved: Boolean(seller.kycApproved),
      screen: 'buyer_request_detail',
      tab: 'offers',
    },
  });
}

function offerWithdrawn({ buyerUid, seller, request }) {
  return notifyUser({
    userId: buyerUid,
    role: 'buyer',
    title: 'Ofa imeondolewa',
    body: `${seller.storeName || seller.displayName || 'Muuzaji'} ameondoa ofa kwenye ombi lako la ${request.title}.`,
    type: 'buyer_request.offer_withdrawn',
    data: { requestId: request.id, sellerUid: seller.uid, screen: 'buyer_request_detail' },
  });
}

function offerDecided({ sellerUid, request, accepted }) {
  return notifyUser({
    userId: sellerUid,
    role: 'seller',
    title: accepted ? 'Ofa yako imekubaliwa' : 'Ofa yako haijachaguliwa',
    body: accepted
      ? `Mteja amekubali ofa yako kwa ${request.title}. Fungua ombi kuanza mazungumzo.`
      : `Mteja amechagua ofa nyingine kwa ${request.title}. Ombi limefungwa kama limekamilika.`,
    type: accepted ? 'buyer_request.offer_accepted' : 'buyer_request.offer_declined',
    data: { requestId: request.id, screen: 'buyer_request_detail' },
  });
}

function limitReached({ buyerUid, request }) {
  return notifyUser({
    userId: buyerUid,
    role: 'buyer',
    title: 'Kikomo cha wauzaji kimefikiwa',
    body: `Ombi lako la ${request.title} limepokea ofa ${request.offersCount}/${request.offerLimit}. Ofa mpya zimezuiwa.`,
    type: 'buyer_request.limit_reached',
    data: {
      requestId: request.id,
      offersCount: request.offersCount,
      offerLimit: request.offerLimit,
      screen: 'buyer_request_detail',
    },
  });
}

function expiringSoon({ buyerUid, request, hoursLeft }) {
  return notifyUser({
    userId: buyerUid,
    role: 'buyer',
    title: 'Ombi lako linaisha muda',
    body: `Ombi lako la ${request.title} litaisha baada ya saa ${hoursLeft}.`,
    type: 'buyer_request.expiring_soon',
    data: { requestId: request.id, screen: 'buyer_request_detail' },
  });
}

function expired({ buyerUid, request }) {
  return notifyUser({
    userId: buyerUid,
    role: 'buyer',
    title: 'Ombi lako limeisha muda',
    body: `Ombi la ${request.title} halipokei ofa mpya. Unaweza kulifungua upya au kuongeza muda.`,
    type: 'buyer_request.expired',
    data: { requestId: request.id, screen: 'buyer_request_detail' },
  });
}

function requestUpdated({ sellerUids, request, changed }) {
  return Promise.allSettled(
    sellerUids.map((uid) => notifyUser({
      userId: uid,
      role: 'seller',
      title: 'Masharti ya ombi yamebadilika',
      body: `Mteja amebadilisha ${changed.slice(0, 3).join(', ')} kwenye ombi la ${request.title}. Tafuta maelezo mapya kabla ya kuendelea.`,
      type: 'buyer_request.updated',
      data: {
        requestId: request.id,
        version: request.version,
        changedFields: changed,
        screen: 'buyer_request_detail',
      },
    })),
  );
}

function requestClosed({ sellerUids, request }) {
  return Promise.allSettled(
    sellerUids.map((uid) => notifyUser({
      userId: uid,
      role: 'seller',
      title: 'Ombi limefungwa',
      body: `Mteja amefunga ombi la ${request.title}. Ofa mpya hazipokelewi.`,
      type: 'buyer_request.closed',
      data: { requestId: request.id, screen: 'buyer_request_detail' },
    })),
  );
}

function moderated({ buyerUid, request, action, reason }) {
  const message = action === 'suspended'
    ? `Ombi lako la ${request.title} limesitishwa. Sababu: ${reason || 'uhakiki wa maudhui'}.`
    : `Ombi lako la ${request.title} limerejeshwa na linaweza kupokea ofa tena.`;
  return notifyUser({
    userId: buyerUid,
    role: 'buyer',
    title: action === 'suspended' ? 'Ombi limesitishwa' : 'Ombi limerejeshwa',
    body: message,
    type: action === 'suspended' ? 'buyer_request.moderated' : 'buyer_request.restored',
    data: { requestId: request.id, screen: 'buyer_request_detail' },
  });
}

module.exports = {
  notifyUser,
  sellerViewedRequest,
  offerReceived,
  offerWithdrawn,
  offerDecided,
  limitReached,
  expiringSoon,
  expired,
  requestUpdated,
  requestClosed,
  moderated,
};
