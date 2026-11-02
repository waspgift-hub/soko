'use strict';

const { getFirebaseFirestore } = require('../../config/firebase');
const { logAuditEvent } = require('./audit');

const EVENTS = 'company_events';

function db() { return getFirebaseFirestore(); }

async function listEvents({ legalEntityId = '', from = '', to = '' } = {}) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  let q = d.collection(EVENTS).orderBy('start', 'asc');
  if (legalEntityId) q = q.where('legal_entity_id', '==', legalEntityId);
  const snap = await q.limit(300).get();
  let items = snap.docs.map((x) => ({ id: x.id, ...x.data() }));
  if (from) items = items.filter((e) => String(e.start || '') >= from);
  if (to) items = items.filter((e) => String(e.start || '') <= to);
  return items;
}

async function createEvent(data, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const doc = {
    legal_entity_id: data.legalEntityId || '',
    title: data.title,
    type: data.type || 'meeting',
    start: data.start,
    end: data.end || '',
    timezone: data.timezone || 'Africa/Dar_es_Salaam',
    attendees: data.attendees || [],
    recurrence: data.recurrence || '',
    reminders: data.reminders || [],
    notes: data.notes || '',
    created_by: actorUid,
    created_at: now,
    updated_at: now,
  };
  const ref = await d.collection(EVENTS).add(doc);
  await logAuditEvent({ actorUid, action: 'event.create', targetType: 'event', targetId: ref.id, legalEntityId: doc.legal_entity_id });
  return { id: ref.id, ...doc };
}

async function updateEvent(id, patch, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  const now = new Date().toISOString();
  const allowed = ['title', 'type', 'start', 'end', 'timezone', 'attendees', 'recurrence', 'reminders', 'notes'];
  const updates = { updated_at: now };
  for (const k of allowed) if (patch[k] !== undefined) updates[k] = patch[k];
  await d.collection(EVENTS).doc(id).update(updates);
  await logAuditEvent({ actorUid, action: 'event.update', targetType: 'event', targetId: id, metadata: { fields: Object.keys(updates) } });
  const snap = await d.collection(EVENTS).doc(id).get();
  return { id: snap.id, ...snap.data() };
}

async function deleteEvent(id, actorUid) {
  const d = db(); if (!d) throw new Error('FIRESTORE_NOT_CONFIGURED');
  await d.collection(EVENTS).doc(id).delete();
  await logAuditEvent({ actorUid, action: 'event.delete', targetType: 'event', targetId: id });
  return { id, deleted: true };
}

module.exports = { listEvents, createEvent, updateEvent, deleteEvent };
PY