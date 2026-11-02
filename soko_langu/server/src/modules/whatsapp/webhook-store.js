// Persistence for WhatsApp Cloud API webhooks.
//
// Meta retries a delivery until it gets a 2xx, so every write is keyed by
// Meta's own ids (message wamid, status id + status). A retry therefore
// overwrites the same document instead of creating a duplicate. Events land in
// the existing `whatsapp_webhook_logs` collection (see firestore.rules) so the
// admin panel can audit them without a new rules change.
const { getFirebaseFirestore } = require('../../config/firebase');

const COLLECTION = 'whatsapp_webhook_logs';

// Firestore allows at most 500 writes per batch and an id may not contain "/".
// A single Meta payload is normally well below this, but splitting keeps a
// bulk burst from failing the whole delivery.
const BATCH_SIZE = 400;
const MAX_DOC_ID = 400;

function docId(prefix, id) {
  const safe = String(id || '').replace(/\//g, '_').slice(0, MAX_DOC_ID);
  return `${prefix}_${safe}`;
}

function metaDate(timestamp) {
  const seconds = Number(timestamp);
  return Number.isFinite(seconds) && seconds > 0 ? new Date(seconds * 1000) : null;
}

// One human-readable line is enough for the admin log and keeps the stored
// payload small; the full message object is still kept in `payload`.
function previewOf(message) {
  const m = message || {};
  if (m.text && m.text.body) return m.text.body;
  if (m.button && m.button.text) return m.button.text;
  if (m.interactive) {
    const i = m.interactive;
    if (i.button_reply && i.button_reply.title) return i.button_reply.title;
    if (i.list_reply && i.list_reply.title) return i.list_reply.title;
  }
  const media = m[m.type];
  if (media && media.caption) return media.caption;
  if (media && media.filename) return media.filename;
  return `[${m.type || 'unknown'}]`;
}

async function commitInChunks(db, events) {
  for (let i = 0; i < events.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const event of events.slice(i, i + BATCH_SIZE)) {
      const data = { ...event.data, receivedAt: new Date() };
      batch.set(db.collection(COLLECTION).doc(event.docId), data, { merge: true });
    }
    await batch.commit();
  }
}

// `events` are already normalized by the controller:
//   { kind: 'message'|'status'|'error', docId, data }
// Returns the number written so the caller can log a delivery summary.
async function persistEvents(events) {
  if (!events.length) return { stored: 0 };

  const db = getFirebaseFirestore();
  if (!db) {
    throw new Error('FIRESTORE_UNAVAILABLE');
  }

  await commitInChunks(db, events);
  return { stored: events.length };
}

module.exports = { previewOf, metaDate, docId, persistEvents, COLLECTION };
