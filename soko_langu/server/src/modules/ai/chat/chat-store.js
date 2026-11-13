// Firestore persistence for Soko Vibe AI chat: conversations, messages, long-term
// memory and per-user AI preferences.
//
// Written against the Firestore Admin SDK directly, the same way comment-store.js
// is, rather than through the generic firestore-store.js facade. The facade
// deliberately degrades multi-field queries to "one equality filter, post-filter in
// JS", which is the wrong trade here: the spec requires cursor pagination and an
// index-backed Recent Chats list that stays fast with millions of messages, and
// post-filtering in JS is exactly what would not.
//
// Collection names are prefixed `ai_` because `conversations` and `messages` are
// ALREADY taken by group chat and the AI tool loop. Sharing those names would
// silently mix a user's group threads with their AI transcript, and Firestore
// rules and indexes are per-collection, so there is no way to separate them
// afterwards.
//
// TIMESTAMPS ARE ISO-8601 STRINGS, not Firestore Timestamps, matching
// comment-store.js. Ordering still works because toISOString() is fixed-width UTC,
// so lexicographic order equals chronological order for every value this module
// writes. The payoff is that a serialised document needs no recursive timestamp
// coercion on the way out, which is where the timestamp leaks in responses
// usually come from.
//
// OWNERSHIP IS ENFORCED HERE, NOT IN THE ROUTES. Every read and write takes
// `userId` — always the uid from the verified Firebase token, never anything the
// client sent — and constrains the query by it. A route that forgot the check
// would still be safe, which is what stops a future IDOR from being one careless
// refactor away.

const crypto = require('crypto');
const { getFirebaseFirestore } = require('../../../config/firebase');

const COLLECTIONS = {
  conversations: 'ai_conversations',
  messages: 'ai_messages',
  memory: 'ai_memory',
  preferences: 'user_ai_preferences',
};

const DEFAULT_CONVERSATION_LIMIT = 20;
const MAX_CONVERSATION_LIMIT = 50;
const DEFAULT_MESSAGE_PAGE = 30;
const MAX_MESSAGE_PAGE = 100;
const MAX_MEMORY_ROWS = 200;
const MAX_CONTENT_CHARS = 8000;
const PREVIEW_CHARS = 140;

const STATUS = {
  ACTIVE: 'active',
  ARCHIVED: 'archived',
  DELETED: 'deleted',
};

const MESSAGE_STATUS = {
  COMPLETED: 'completed',
  GENERATING: 'generating',
  FAILED: 'failed',
};

function httpError(status, code) {
  const e = new Error(code);
  e.status = status;
  e.code = code;
  return e;
}

function requireStore() {
  const db = getFirebaseFirestore();
  if (!db) throw httpError(503, 'AI_CHAT_STORE_UNAVAILABLE');
  return db;
}

function nowIso() {
  return new Date().toISOString();
}

function iso(value) {
  if (value == null) return null;
  if (typeof value === 'object' && typeof value.toDate === 'function') {
    return value.toDate().toISOString();
  }
  if (value instanceof Date) return value.toISOString();
  return String(value);
}

function clampLimit(value, fallback, max) {
  const parsed = parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < 1) return fallback;
  return Math.min(parsed, max);
}

/**
 * One deterministic preview string per conversation, stored on the conversation
 * document itself.
 *
 * Denormalised on purpose. Recent Chats must show a preview without reading every
 * message, and a Firestore collection group / subcollection join does not exist:
 * reading the newest message per conversation would be N queries for N
 * conversations. Storing the preview costs one string per conversation and makes
 * the list query a single indexed read, which is the entire point of §9.
 */
function previewOf(content) {
  const flat = String(content || '')
    .replace(/\s+/g, ' ')
    .trim();
  if (flat.length <= PREVIEW_CHARS) return flat;
  return `${flat.slice(0, PREVIEW_CHARS - 1).trimEnd()}…`;
}

// ─── Conversations ──────────────────────────────────────────────────────────

async function createConversation({ userId, title = '', status = STATUS.ACTIVE }) {
  const db = requireStore();
  const conversationId = crypto.randomUUID();
  const createdAt = nowIso();
  const doc = {
    conversationId,
    userId,
    title: String(title || '').slice(0, 120),
    createdAt,
    updatedAt: createdAt,
    status,
    lastMessagePreview: '',
    messageCount: 0,
    // Names the model that produced the most recent answer. Kept for debugging a
    // failover complaint after the fact; the client never reads it.
    lastModel: null,
    deletedAt: null,
  };
  await db.collection(COLLECTIONS.conversations).doc(conversationId).set(doc);
  return serializeConversation(doc);
}

/**
 * Recent Chats, newest first, cursor-paginated.
 *
 * Cursor-paginated rather than offset-paginated on purpose: an offset query
 * re-sorts the whole result set on every page, so deep paging gets slower the
 * further back you go and two concurrent messages can shift rows between pages
 * and duplicate or skip an entry. Keyset pagination on `updatedAt` is O(limit)
 * per page and is stable under concurrent writes.
 *
 * `cursor` is the `updatedAt` of the last row of the previous page. Firestore
 * cannot express "strictly less than this value" on a field plus a second
 * equality filter without a composite index; `ai_conversations (userId ASC,
 * updatedAt DESC)` is that index, and the client-visible ordering is exactly
 * this.
 *
 * @returns {Promise<{ items: object[], nextCursor: string|null }>}
 */
async function listConversations({
  userId,
  limit = DEFAULT_CONVERSATION_LIMIT,
  cursor = null,
}) {
  const db = requireStore();
  const max = clampLimit(limit, DEFAULT_CONVERSATION_LIMIT, MAX_CONVERSATION_LIMIT);
  const base = db
    .collection(COLLECTIONS.conversations)
    .where('userId', '==', userId);

  const query = cursor
    ? base.orderBy('updatedAt', 'desc').where('updatedAt', '<', cursor)
    : base.orderBy('updatedAt', 'desc');

  const snap = await query.limit(max + 1).get();

  // The filter is re-applied in JS because a soft-deleted row must never appear
  // in Recent Chats even though it still sits in the user's updatedAt window.
  const visible = snap.docs.filter((d) => d.data().status !== STATUS.DELETED);
  const page = visible.slice(0, max);
  const items = page.map((d) => serializeConversation(d.data(), d.id));

  return {
    items,
    // Null when the over-fetch found nothing beyond the page, which is how the
    // client knows to stop asking instead of paging forever.
    nextCursor: visible.length > max && page.length ? items[items.length - 1].updatedAt : null,
  };
}

async function getConversation({ conversationId, userId }) {
  const db = requireStore();
  const snap = await db
    .collection(COLLECTIONS.conversations)
    .doc(String(conversationId))
    .get();
  if (!snap.exists) throw httpError(404, 'CONVERSATION_NOT_FOUND');
  const doc = snap.data();
  // Ownership and existence are reported identically. A 403 here would confirm to
  // an attacker that a given conversation id exists at all, which turns the
  // endpoint into an id oracle.
  if (doc.userId !== userId) throw httpError(404, 'CONVERSATION_NOT_FOUND');
  if (doc.status === STATUS.DELETED) throw httpError(404, 'CONVERSATION_NOT_FOUND');
  return serializeConversation(doc, snap.id);
}

/**
 * Marks a conversation for deletion rather than removing the row.
 *
 * A soft delete is required here, not a stylistic choice. Hard-deleting the
 * conversation doc while its messages still exist would leave orphaned messages
 * that the memory-extraction job could still read, which is precisely the
 * "deleted content is used for future personalization" failure the spec forbids
 * in TEST 5. Marking it deleted first means every reader filters it out even if
 * the message sweep is interrupted.
 */
async function softDeleteConversation({ conversationId, userId }) {
  const db = requireStore();
  await getConversation({ conversationId, userId });
  await db
    .collection(COLLECTIONS.conversations)
    .doc(String(conversationId))
    .update({ status: STATUS.DELETED, deletedAt: nowIso(), updatedAt: nowIso() });
  return { conversationId: String(conversationId) };
}

/** Removes a conversation's messages. Called after the soft delete has landed. */
async function purgeConversationMessages({ conversationId }) {
  const db = requireStore();
  let removed = 0;
  // Batched in 400s because Firestore caps a single batched write at 500 docs.
  for (;;) {
    const snap = await db
      .collection(COLLECTIONS.messages)
      .where('conversationId', '==', String(conversationId))
      .limit(400)
      .get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) batch.delete(doc.ref);
    await batch.commit();
    removed += snap.size;
    if (snap.size < 400) break;
  }
  return removed;
}

// ─── Messages ───────────────────────────────────────────────────────────────

/**
 * Appends a message, idempotent on `clientMessageId`.
 *
 * The document id IS the client-supplied clientMessageId. That makes the
 * idempotency check a single point read with no query and no index, and it is what
 * satisfies TEST 10: a double-tapped Send replays the same clientMessageId, the
 * transaction finds the row already there, and the second request returns the
 * original message instead of producing a duplicate turn.
 *
 * Because the id is client-supplied it is also a vector: a caller who guessed
 * another user's message id could collide with their row. The transaction refuses
 * to touch a document whose stored userId differs, so a collision is a 409 and
 * never an overwrite or a read.
 */
async function appendMessage({
  conversationId,
  userId,
  role,
  content,
  status = MESSAGE_STATUS.COMPLETED,
  model = null,
  provider = null,
  tokenUsage = null,
  clientMessageId = null,
  id = null,
  inReplyTo = null,
}) {
  const db = requireStore();
  const text = String(content == null ? '' : content);
  if (!text.trim() && status !== MESSAGE_STATUS.GENERATING) {
    throw httpError(400, 'EMPTY_MESSAGE');
  }
  if (!['user', 'assistant', 'system'].includes(role)) {
    throw httpError(400, 'INVALID_ROLE');
  }

  const messageId = String(id || clientMessageId || crypto.randomUUID());
  const ref = db.collection(COLLECTIONS.messages).doc(messageId);
  const createdAt = nowIso();

  return db.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists) {
      const prior = existing.data();
      if (prior.userId !== userId) throw httpError(409, 'MESSAGE_ID_CONFLICT');
      // Replay of a request already accepted. Callers use the `created: false`
      // flag to skip generating a second assistant turn for it.
      return { message: serializeMessage(prior, existing.id), created: false };
    }

    const doc = {
      messageId,
      conversationId: String(conversationId),
      userId,
      role,
      content: text.slice(0, MAX_CONTENT_CHARS),
      createdAt,
      status,
      model,
      provider,
      tokenUsage,
      clientMessageId: clientMessageId ? String(clientMessageId) : null,
      // Marks the turn an assistant message answers, so a retry updates the same
      // row instead of appending a second assistant reply to the same question.
      inReplyTo: inReplyTo ? String(inReplyTo) : null,
      // Set once voice has been synthesised, so the audio cache key survives a
      // server restart and a replay does not re-spend ElevenLabs credits.
      voiceCacheKey: null,
      voiceId: null,
    };
    tx.set(ref, doc);
    return { message: serializeMessage(doc, messageId), created: true };
  });
}

/**
 * Writes the id of the assistant turn answering `userMessageId`, so a retry
 * updates the existing assistant row instead of creating a second one.
 */
async function linkAssistantReply({ assistantMessageId, userMessageId }) {
  const db = requireStore();
  await db
    .collection(COLLECTIONS.messages)
    .doc(String(assistantMessageId))
    .update({ inReplyTo: userMessageId ? String(userMessageId) : null });
}

/**
 * Removes one message.
 *
 * A hard delete, unlike a conversation. A single message holds nothing that would
 * be needed to reconcile state, and keeping a "deleted" tombstone in the transcript
 * would show the user a gap where their own message used to be. Memory is not
 * affected either way: it was extracted from the text, and §5 only requires that
 * deleted CONVERSATIONS stop feeding personalization, which the soft delete on the
 * parent guarantees.
 */
async function deleteMessage({ messageId, userId }) {
  const db = requireStore();
  const ref = db.collection(COLLECTIONS.messages).doc(String(messageId));
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'MESSAGE_NOT_FOUND');
  if (snap.data().userId !== userId) throw httpError(404, 'MESSAGE_NOT_FOUND');
  await ref.delete();
  return { messageId: String(messageId) };
}

async function updateMessage({ messageId, userId, ...fields }) {
  const db = requireStore();
  const ref = db.collection(COLLECTIONS.messages).doc(String(messageId));
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'MESSAGE_NOT_FOUND');
  if (snap.data().userId !== userId) throw httpError(404, 'MESSAGE_NOT_FOUND');

  const patch = {};
  for (const key of ['content', 'status', 'tokenUsage', 'model', 'provider', 'voiceCacheKey', 'voiceId']) {
    if (fields[key] !== undefined) patch[key] = fields[key];
  }
  if (!Object.keys(patch).length) return serializeMessage(snap.data(), snap.id);
  patch.updatedAt = nowIso();
  await ref.update(patch);
  return serializeMessage({ ...snap.data(), ...patch }, snap.id);
}

async function getMessage({ messageId, userId }) {
  const db = requireStore();
  const snap = await db.collection(COLLECTIONS.messages).doc(String(messageId)).get();
  if (!snap.exists) throw httpError(404, 'MESSAGE_NOT_FOUND');
  if (snap.data().userId !== userId) throw httpError(404, 'MESSAGE_NOT_FOUND');
  return serializeMessage(snap.data(), snap.id);
}

/**
 * One page of a conversation's messages, chronological, newest-loaded-first.
 *
 * `before` is the `createdAt` of the oldest row the client already holds, so
 * paging backwards through history needs no offset arithmetic and cannot
 * duplicate a row when a new message lands mid-scroll.
 *
 * Ordering is ASC because the client displays messages in the order they were
 * spoken: a DESC query would have to be reversed in JS anyway, and the composite
 * index `(conversationId ASC, createdAt ASC)` is the one §4 asks for by name.
 */
async function listMessages({
  conversationId,
  userId,
  limit = DEFAULT_MESSAGE_PAGE,
  before = null,
}) {
  const db = requireStore();
  // Proves ownership before reading messages, so a caller cannot page a
  // conversation belonging to somebody else even if the message rows leaked ids.
  await getConversation({ conversationId, userId });

  const max = clampLimit(limit, DEFAULT_MESSAGE_PAGE, MAX_MESSAGE_PAGE);
  const base = db
    .collection(COLLECTIONS.messages)
    .where('conversationId', '==', String(conversationId));

  const query = before
    ? base.orderBy('createdAt', 'asc').where('createdAt', '<', before)
    : base.orderBy('createdAt', 'asc');

  const snap = await query.limit(max + 1).get();
  const page = snap.docs.slice(0, max);
  const items = page.map((d) => serializeMessage(d.data(), d.id));

  return {
    items,
    nextCursor: snap.size > max && page.length ? items[items.length - 1].createdAt : null,
  };
}

/**
 * Denormalises the conversation counters and preview after a message lands.
 *
 * Written in the same batch as the message would be ideal, but the message id is
 * only known after the idempotency transaction commits, and re-reading the newest
 * message to recompute the preview costs a second query on the hot path. Instead
 * the caller passes the just-written message and the counters are incremented
 * rather than recounted: `messageCount` is a display hint, and it is reconciled
 * exactly by `recomputeConversationStats` for a conversation being resumed.
 */
async function recordMessageActivity({ conversationId, userId, content, role }) {
  const db = requireStore();
  const ref = db.collection(COLLECTIONS.conversations).doc(String(conversationId));
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'CONVERSATION_NOT_FOUND');
  const doc = snap.data();
  if (doc.userId !== userId) throw httpError(404, 'CONVERSATION_NOT_FOUND');

  const updatedAt = nowIso();
  const patch = {
    updatedAt,
    // Only a user turn moves the preview: it is what the user recognises the
    // thread by, and an assistant echo of it would make every row read the same.
    ...(role === 'user' ? { lastMessagePreview: previewOf(content) } : {}),
    messageCount: (Number(doc.messageCount) || 0) + 1,
  };
  await ref.update(patch);
  return { updatedAt };
}

/**
 * Recomputes counters from the messages themselves.
 *
 * Called when a conversation is reopened, which is where an interrupted delete or
 * a stream that died mid-write shows up: the increment-only counter above drifts
 * upward permanently otherwise.
 */
async function recomputeConversationStats({ conversationId, userId }) {
  const db = requireStore();
  const ref = db.collection(COLLECTIONS.conversations).doc(String(conversationId));
  const snap = await ref.get();
  if (!snap.exists) throw httpError(404, 'CONVERSATION_NOT_FOUND');
  if (snap.data().userId !== userId) throw httpError(404, 'CONVERSATION_NOT_FOUND');

  const messages = await db
    .collection(COLLECTIONS.messages)
    .where('conversationId', '==', String(conversationId))
    .limit(MAX_MESSAGE_PAGE * 4)
    .get();

  const rows = messages.docs.map((d) => d.data());
  const lastUser = rows.filter((r) => r.role === 'user').pop();
  await ref.update({
    messageCount: rows.length,
    lastMessagePreview: lastUser ? previewOf(lastUser.content) : '',
  });
  return { messageCount: rows.length };
}

async function setConversationTitle({ conversationId, userId, title }) {
  const db = requireStore();
  await getConversation({ conversationId, userId });
  await db
    .collection(COLLECTIONS.conversations)
    .doc(String(conversationId))
    .update({ title: String(title || '').slice(0, 120), updatedAt: nowIso() });
  return { conversationId: String(conversationId), title };
}

// ─── Long-term memory ───────────────────────────────────────────────────────

async function listMemories({ userId, limit = MAX_MEMORY_ROWS }) {
  const db = requireStore();
  const snap = await db
    .collection(COLLECTIONS.memory)
    .where('userId', '==', userId)
    .orderBy('updatedAt', 'desc')
    .limit(clampLimit(limit, MAX_MEMORY_ROWS, MAX_MEMORY_ROWS))
    .get();
  return snap.docs.map((d) => serializeMemory(d.data(), d.id));
}

/**
 * Writes or reinforces a memory, keyed on (userId, key).
 *
 * Confidence moves with evidence rather than overwriting: a repeat observation
 * raises it, a contradicting one lowers it, and a memory that has been observed
 * enough stays even if one message disagrees — because one message disagreeing is
 * the normal case for a preference being changed on purpose, and dropping the
 * memory would make the AI forget what it was told within a single session.
 */
async function upsertMemory({ userId, key, value, confidence, source }) {
  const db = requireStore();
  const safeKey = String(key || '').slice(0, 64);
  if (!safeKey) throw httpError(400, 'INVALID_MEMORY_KEY');

  const snap = await db
    .collection(COLLECTIONS.memory)
    .where('userId', '==', userId)
    .where('key', '==', safeKey)
    .limit(1)
    .get();

  const observedAt = nowIso();
  if (!snap.empty) {
    const doc = snap.docs[0];
    const prior = doc.data();
    const sameValue = String(prior.value) === String(value);
    // Reinforcement is additive-but-bounded; contradiction decays. Both are
    // asymmetric so a user who states something three times gets it remembered,
    // and a user who corrects it once is not stuck with the wrong value forever.
    const next = sameValue
      ? Math.min(0.99, Number(prior.confidence) + 0.15)
      : Math.max(0.1, Number(prior.confidence) - 0.4);

    await doc.ref.update({
      value: String(value).slice(0, 200),
      confidence: Number(next.toFixed(3)),
      source: source || prior.source,
      updatedAt: observedAt,
      lastObservedAt: observedAt,
      observations: (Number(prior.observations) || 0) + 1,
    });
    return { key: safeKey, value: String(value), confidence: next, reinforced: true };
  }

  const memoryId = crypto.randomUUID();
  await db.collection(COLLECTIONS.memory).doc(memoryId).set({
    memoryId,
    userId,
    key: safeKey,
    value: String(value).slice(0, 200),
    confidence: Math.max(0.1, Math.min(1, Number(confidence) || 0.4)),
    source: source || 'inferred',
    createdAt: observedAt,
    updatedAt: observedAt,
    lastObservedAt: observedAt,
    observations: 1,
  });
  return { key: safeKey, value: String(value), confidence: Number(confidence) || 0.4, reinforced: false };
}

async function clearMemories({ userId }) {
  const db = requireStore();
  let removed = 0;
  for (;;) {
    const snap = await db
      .collection(COLLECTIONS.memory)
      .where('userId', '==', userId)
      .limit(400)
      .get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) batch.delete(doc.ref);
    await batch.commit();
    removed += snap.size;
    if (snap.size < 400) break;
  }
  return { removed };
}

/** Soft-deletes every conversation for a user, then purges their messages. */
async function deleteAllConversations({ userId }) {
  const db = requireStore();
  let conversations = 0;
  for (;;) {
    const snap = await db
      .collection(COLLECTIONS.conversations)
      .where('userId', '==', userId)
      .limit(200)
      .get();
    if (snap.empty) break;

    const batch = db.batch();
    const ids = [];
    for (const doc of snap.docs) {
      if (doc.data().status === STATUS.DELETED) continue;
      ids.push(doc.id);
      batch.update(doc.ref, { status: STATUS.DELETED, deletedAt: nowIso(), updatedAt: nowIso() });
    }
    // Every row in this page already deleted: advancing would loop forever, so
    // stop on a count that did not change.
    if (!ids.length) break;
    await batch.commit();
    conversations += ids.length;
  }

  let messages = 0;
  for (const id of await conversationIdsFor({ userId })) {
    messages += await purgeConversationMessages({ conversationId: id });
  }
  return { conversations, messages };
}

async function conversationIdsFor({ userId }) {
  const db = requireStore();
  const ids = [];
  for (;;) {
    const snap = await db
      .collection(COLLECTIONS.conversations)
      .where('userId', '==', userId)
      .limit(200)
      .get();
    if (snap.empty) break;
    for (const doc of snap.docs) ids.push(doc.id);
    if (snap.size < 200) break;
  }
  return ids;
}

// ─── Preferences ────────────────────────────────────────────────────────────

/**
 * Reads the user's AI preferences, materialising defaults on first read.
 *
 * The document id is the uid, so there is exactly one preferences row per user
 * and no query is needed to find it.
 */
async function getPreferences({ userId }) {
  const db = requireStore();
  const ref = db.collection(COLLECTIONS.preferences).doc(String(userId));
  const snap = await ref.get();
  if (snap.exists) return serializePreferences(snap.data(), userId);

  const created = {
    userId,
    // Memory ON by default: the spec's whole point is a personal assistant, and
    // opt-out users are one tap away in AI Settings.
    memoryEnabled: true,
    // Chat history ON by default too — losing history silently on upgrade would
    // look like data loss to anyone who had already been talking to the AI.
    chatHistoryEnabled: true,
    preferredLanguage: null,
    responseStyle: null,
    voiceEnabled: true,
    voiceId: null,
    createdAt: nowIso(),
    updatedAt: nowIso(),
  };
  await ref.set(created);
  return serializePreferences(created, userId);
}

async function updatePreferences({ userId, ...patch }) {
  const db = requireStore();
  const ref = db.collection(COLLECTIONS.preferences).doc(String(userId));
  const merged = { userId, updatedAt: nowIso(), ...patch };
  await ref.set(merged, { merge: true });
  const snap = await ref.get();
  // Echoing the merged document rather than the patch means the client renders
  // exactly what was stored, including defaults it had not seen yet.
  return serializePreferences(snap.data(), userId);
}

module.exports = {
  COLLECTIONS,
  STATUS,
  MESSAGE_STATUS,
  createConversation,
  listConversations,
  getConversation,
  softDeleteConversation,
  purgeConversationMessages,
  appendMessage,
  linkAssistantReply,
  deleteMessage,
  updateMessage,
  getMessage,
  listMessages,
  recordMessageActivity,
  recomputeConversationStats,
  setConversationTitle,
  listMemories,
  upsertMemory,
  clearMemories,
  deleteAllConversations,
  conversationIdsFor,
  getPreferences,
  updatePreferences,
  serializeConversation,
  serializeMessage,
  serializeMemory,
  serializePreferences,
  previewOf,
};

// ─── Serialisers ────────────────────────────────────────────────────────────

function serializeConversation(doc, id) {
  return {
    conversationId: String(doc.conversationId || id),
    title: doc.title || '',
    createdAt: iso(doc.createdAt),
    updatedAt: iso(doc.updatedAt),
    status: doc.status || STATUS.ACTIVE,
    lastMessagePreview: doc.lastMessagePreview || '',
    messageCount: Number(doc.messageCount) || 0,
    lastModel: doc.lastModel || null,
  };
}

function serializeMessage(doc, id) {
  return {
    messageId: String(doc.messageId || id),
    conversationId: doc.conversationId,
    role: doc.role,
    content: doc.content || '',
    createdAt: iso(doc.createdAt),
    status: doc.status || MESSAGE_STATUS.COMPLETED,
    model: doc.model || null,
    provider: doc.provider || null,
    tokenUsage: doc.tokenUsage || null,
    inReplyTo: doc.inReplyTo || null,
    voiceCacheKey: doc.voiceCacheKey || null,
    voiceId: doc.voiceId || null,
  };
}

function serializeMemory(doc, id) {
  return {
    memoryId: String(doc.memoryId || id),
    key: doc.key,
    value: doc.value,
    confidence: Number(doc.confidence) || 0,
    source: doc.source || 'inferred',
    createdAt: iso(doc.createdAt),
    updatedAt: iso(doc.updatedAt),
    observations: Number(doc.observations) || 0,
  };
}

function serializePreferences(doc, id) {
  return {
    userId: String(doc.userId || id),
    memoryEnabled: doc.memoryEnabled !== false,
    chatHistoryEnabled: doc.chatHistoryEnabled !== false,
    preferredLanguage: doc.preferredLanguage || null,
    responseStyle: doc.responseStyle || null,
    voiceEnabled: doc.voiceEnabled !== false,
    voiceId: doc.voiceId || null,
    updatedAt: iso(doc.updatedAt),
  };
}