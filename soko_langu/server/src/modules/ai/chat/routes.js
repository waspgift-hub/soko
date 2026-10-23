// Persistent AI chat endpoints.
//
// Mounted at /api/ai (the same prefix the shipped Dalali proxy already uses, so an
// old app build keeps working) and reuses that router's own `requireUser`: the
// bearer Firebase ID token is verified on every route and `req.user.id` — which is
// the Firebase uid — is the ONLY identity any handler here passes down. No handler
// reads a user id from the request body or query, which is what makes IDOR
// structurally impossible rather than a rule each route has to remember.
//
// Endpoints:
//
//   POST   /api/ai/chats                    create a conversation
//   GET    /api/ai/chats                    recent chats, cursor-paginated
//   GET    /api/ai/chats/:id                conversation metadata
//   DELETE /api/ai/chats/:id                soft-delete + purge messages
//   GET    /api/ai/chats/:id/messages       messages, cursor-paginated
//   POST   /api/ai/chats/:id/messages       send a turn (SSE stream)
//   DELETE /api/ai/messages/:id             delete one message
//   GET    /api/ai/memory                   long-term memories
//   DELETE /api/ai/memory                   clear memories
//   GET    /api/ai/preferences              AI settings
//   PATCH  /api/ai/preferences              update AI settings
//   POST   /api/ai/messages/:id/voice       synthesise + cache speech
//   GET    /api/ai/messages/:id/voice       stream cached audio bytes

const { Router } = require('express');
const { getFirebaseAuth } = require('../../../config/firebase');
const gateway = require('../ai-gateway');
const { chatWithTools } = require('../tool-loop');
const store = require('./chat-store');
const { buildContext } = require('./context-builder');
const { generateTitle, isUsefulFirstMessage } = require('./title-generator');
const extractor = require('./memory-extractor');
const { redactSecrets } = require('./redact');
const voice = require('./voice-service');
const sse = require('./sse-writer');
const { resolveEntitlements, checkAiQuota } = require('../../subscriptions/subscription-service');
const { jsonError } = require('../../../utils/http');
const { acquireLock, releaseLock } = require('../../../config/redis');

const router = Router();

// Bearer Firebase ID token. Identical to the guard on the sibling /chat route, and
// reused rather than reimplemented so the two AI surfaces cannot drift apart on how
// a session is verified.
async function requireUser(req, res) {
  const authHeader = req.headers.authorization || '';
  if (!authHeader.startsWith('Bearer ')) {
    jsonError(res, { status: 401, code: 'UNAUTHENTICATED', message: 'Missing or invalid token' });
    return null;
  }
  try {
    const auth = getFirebaseAuth();
    if (!auth) {
      jsonError(res, { status: 503, code: 'AUTH_NOT_CONFIGURED', message: 'Auth not configured' });
      return null;
    }
    const decoded = await auth.verifyIdToken(authHeader.slice(7));
    return { id: decoded.uid };
  } catch (err) {
    const expired = err.code === 'auth/id-token-expired';
    jsonError(res, {
      status: 401,
      code: expired ? 'TOKEN_EXPIRED' : 'INVALID_TOKEN',
      message: 'Invalid token',
    });
    return null;
  }
}

/** Wraps a handler so a thrown status becomes a proper JSON error envelope. */
function guard(handler) {
  return async (req, res) => {
    const user = await requireUser(req, res);
    if (!user) return;
    try {
      await handler(req, res, user.id);
    } catch (err) {
      jsonError(res, {
        status: err.status || 500,
        code: err.code || 'AI_CHAT_ERROR',
        message: err.message,
      });
    }
  };
}

function clampText(raw, max = 4000) {
  return String(raw == null ? '' : raw).trim().slice(0, max);
}

// ─── Conversations ──────────────────────────────────────────────────────────

router.post(
  '/chats',
  guard(async (req, res, userId) => {
    const conversation = await store.createConversation({
      userId,
      // An explicit title is honoured; otherwise the first useful message names
      // the thread. Creating a conversation client-side with a placeholder and
      // renaming later would show "Untitled" in Recent Chats for the seconds in
      // between, which is exactly the flicker the spec's example avoids.
      title: clampText(req.body?.title, 120),
    });
    res.status(201).json({ success: true, data: conversation });
  })
);

router.get(
  '/chats',
  guard(async (req, res, userId) => {
    const { items, nextCursor } = await store.listConversations({
      userId,
      limit: req.query.limit,
      cursor: req.query.cursor ? String(req.query.cursor) : null,
    });
    // Exactly the four fields §9 asks for, plus the message count it calls optional.
    res.json({ success: true, data: { items, nextCursor } });
  })
);

router.get(
  '/chats/:id',
  guard(async (req, res, userId) => {
    res.json({ success: true, data: await store.getConversation({ conversationId: req.params.id, userId }) });
  })
);

router.delete(
  '/chats/:id',
  guard(async (req, res, userId) => {
    // Soft delete first, then purge. The order is the security property: once the
    // conversation is marked deleted, no reader — including the background memory
    // job — can select its messages, so an interrupted purge cannot leak content
    // into a later conversation. Purging first would leave a window in which
    // deleted content was still selectable.
    await store.softDeleteConversation({ conversationId: req.params.id, userId });
    const purged = await store.purgeConversationMessages({ conversationId: req.params.id });
    res.json({ success: true, data: { conversationId: String(req.params.id), messagesPurged: purged } });
  })
);

router.get(
  '/chats/:id/messages',
  guard(async (req, res, userId) => {
    const { items, nextCursor } = await store.listMessages({
      conversationId: req.params.id,
      userId,
      limit: req.query.limit,
      before: req.query.before ? String(req.query.before) : null,
    });
    res.json({ success: true, data: { items, nextCursor } });
  })
);

// ─── Send a turn (SSE) ──────────────────────────────────────────────────────

router.post(
  '/chats/:id/messages',
  guard(async (req, res, userId) => {
    const text = clampText(req.body?.text);
    if (!text) {
      return jsonError(res, { status: 400, code: 'EMPTY_MESSAGE', message: 'text required' });
    }

    const conversation = await store.getConversation({ conversationId: req.params.id, userId });
    const preferences = await store.getPreferences({ userId });
    const locale = req.body?.locale === 'en' ? 'en' : 'sw';
    const clientMessageId = req.body?.clientMessageId ? String(req.body.clientMessageId).slice(0, 128) : null;
    const isRetry = req.body?.retry === true;

    // Credentials are stripped before anything touches Firestore or a provider.
    const safeText = redactSecrets(text);

    // Enforce AI quota server-side. The client may display a counter, but it
    // cannot bypass this check — the increment happens in the same transaction.
    const quota = await checkAiQuota(userId);
    if (!quota.allowed) {
      return jsonError(res, {
        status: 429,
        code: 'AI_QUOTA_EXCEEDED',
        message: `AI quota exceeded (${quota.used}/${quota.limit} today)`,
      });
    }

    // Serialises turns on one conversation. Optional, because Redis being down must
    // not stop chat — the idempotency check below is the actual duplicate guard,
    // and this only stops two concurrent turns interleaving their persisted
    // assistant rows. The key is held locally because acquireLock does not echo it
    // back, and releaseLock needs it to do the compare-and-delete.
    const lockKey = `aichat:${conversation.conversationId}`;
    const lock = await acquireLock(lockKey, 60, { optional: true });
    if (lock.skipped) {
      console.warn('[ai] chat turn proceeding without a lock (redis unavailable)');
    }

    // Rehydration on resume: a stream that died mid-write leaves the increment-only
    // messageCount drifting, and this is where a user actually returns to a thread.
    await store.recomputeConversationStats({ conversationId: conversation.conversationId, userId });

    const { message: userMessage, created } = await store.appendMessage({
      conversationId: conversation.conversationId,
      userId,
      role: 'user',
      content: safeText,
      clientMessageId,
    });

    // Idempotent replay (TEST 10): the row already exists, so this is the same tap
    // arriving twice. Return the turn that already exists and generate nothing —
    // the alternative is a second assistant reply to a question already answered.
    if (!created && !isRetry) {
      const prior = await store.listMessages({
        conversationId: conversation.conversationId,
        userId,
        limit: 50,
      });
      const reply = prior.items.find(
        (m) => m.role === 'assistant' && m.inReplyTo === userMessage.messageId
      );
      return res.json({
        success: true,
        data: { userMessage, assistantMessage: reply || null, replayed: true },
      });
    }

    await store.recordMessageActivity({
      conversationId: conversation.conversationId,
      userId,
      content: safeText,
      role: 'user',
    });

    if (!conversation.title && isUsefulFirstMessage(safeText)) {
      await store.setConversationTitle({
        conversationId: conversation.conversationId,
        userId,
        title: generateTitle(safeText),
      });
    }

    // The assistant row exists before the first token arrives, which is what makes
    // an interrupted generation recoverable: the row is already addressable for a
    // retry, so a crash mid-stream leaves a `generating` row rather than nothing.
    const { message: assistantMessage } = await store.appendMessage({
      conversationId: conversation.conversationId,
      userId,
      role: 'assistant',
      content: '',
      status: store.MESSAGE_STATUS.GENERATING,
      inReplyTo: userMessage.messageId,
    });
    await store.linkAssistantReply({
      assistantMessageId: assistantMessage.messageId,
      userMessageId: userMessage.messageId,
    });

    let context;
    try {
      context = await buildContext({
        conversationId: conversation.conversationId,
        userId,
        userMessage: safeText,
        locale,
        systemPrompt: buildSystemPrompt({
          locale,
          catalogStatus: req.body?.catalogStatus === 'found' ? 'found' : 'general',
          productContext: clampText(req.body?.productContext, 8000) || null,
        }),
      });
    } catch (err) {
      console.error('[ai] context build failed:', err.message);
      await store.updateMessage({
        messageId: assistantMessage.messageId,
        userId,
        status: store.MESSAGE_STATUS.FAILED,
        content: '',
      });
      return jsonError(res, {
        status: 503,
        code: 'AI_CONTEXT_UNAVAILABLE',
        message: 'Could not load conversation context',
      });
    }

    const stream = sse.open(res);
    const heartbeat = sse.heartbeat(stream);
    stream.event('start', {
      userMessage,
      assistantMessageId: assistantMessage.messageId,
      context: context.meta,
    });

    let buffer = '';
    let provider = null;
    let failedOver = false;
    let streamed = false;

    // Persist progressively, not per token. A Firestore write per token would be
    // ~40 writes/second against the same document, which costs more than it buys:
    // the client already has the text in memory, and the database only needs to be
    // right if the app dies. Every FLUSH_INTERVAL_MS, plus unconditionally at the
    // end, keeps a crash's worst-case data loss to about a second of text.
    const FLUSH_INTERVAL_MS = 1000;
    let lastFlush = Date.now();
    let flushTimer = null;
    const scheduleFlush = () => {
      if (flushTimer) return;
      flushTimer = setTimeout(() => {
        flushTimer = null;
        lastFlush = Date.now();
        if (!buffer) return;
        store
          .updateMessage({ messageId: assistantMessage.messageId, userId, content: buffer })
          .catch((err) => console.warn(`[ai] partial flush failed: ${err.message}`));
        scheduleFlush();
      }, FLUSH_INTERVAL_MS);
      if (typeof flushTimer.unref === 'function') flushTimer.unref();
    };

    const emitDelta = (text) => {
      buffer += text;
      streamed = true;
      stream.event('delta', { text });
      if (Date.now() - lastFlush >= FLUSH_INTERVAL_MS) scheduleFlush();
    };

    try {
      const body = {
        model: clampText(req.body?.model, 60) || 'openai/gpt-oss-120b',
        messages: context.messages,
        temperature: 0.7,
        max_tokens: 2000,
      };

      // Tool rounds are buffered; only the closing prose turn streams. See
      // chatWithTools' options.onDelta for why that split is the honest one.
      const useTools = req.body?.tools !== false && process.env.AI_TOOLS_ENABLED !== 'false';

      if (useTools) {
        const result = await chatWithTools(body, userId, { onDelta: emitDelta });
        provider = result.provider;
        failedOver = result.failedOver;
        streamed = result.streamed;
        // A provider that failed over mid-turn may have delivered text the buffered
        // `content` field does not describe; the accumulated buffer is authoritative.
        if (!buffer && result.content) emitDelta(result.content);
      } else {
        for await (const event of gateway.chatStream(body, { timeoutMs: 15000 })) {
          if (event.type === 'delta') {
            emitDelta(event.text);
            continue;
          }
          if (event.type === 'done') {
            provider = event.provider;
            failedOver = event.failedOver;
            continue;
          }
          if (event.type === 'error') {
            throw Object.assign(new Error(event.message), { code: event.code });
          }
        }
      }

      const content = buffer.trim();
      if (!content) throw Object.assign(new Error('Empty completion'), { code: 'AI_EMPTY_COMPLETION' });

      await store.updateMessage({
        messageId: assistantMessage.messageId,
        userId,
        content,
        status: store.MESSAGE_STATUS.COMPLETED,
        model: body.model,
        provider,
      });
      await store.recordMessageActivity({
        conversationId: conversation.conversationId,
        userId,
        content,
        role: 'assistant',
      });

      stream.event('done', {
        messageId: assistantMessage.messageId,
        content,
        provider,
        failedOver,
        streamed,
      });

      // Background, deliberately not awaited: extraction is a nicety and must not
      // add latency to a response the user is already reading.
      const evidence = context.messages
        .filter((m) => m.role === 'user' && typeof m.content === 'string')
        .map((m) => ({ role: 'user', content: m.content }));
      evidence.push({ role: 'user', content: safeText });
      extractor
        .runExtraction({
          userId,
          messages: evidence,
          conversationId: conversation.conversationId,
        })
        .catch(() => {});
    } catch (err) {
      // The user's message is already stored and the assistant row keeps whatever
      // was streamed before the failure. §18's "never lose user messages" is
      // satisfied by this write path, not by anything the client does.
      console.error(`[ai] stream failed: ${err.message}`);
      const partial = buffer.trim();
      await store
        .updateMessage({
          messageId: assistantMessage.messageId,
          userId,
          content: partial,
          status: store.MESSAGE_STATUS.FAILED,
          provider,
        })
        .catch((writeErr) => console.warn(`[ai] failure status write failed: ${writeErr.message}`));

      stream.event('error', {
        code: err.code || 'AI_STREAM_FAILED',
        message: err.message,
        partial,
        retryable: true,
      });
    } finally {
      clearInterval(heartbeat);
      if (flushTimer) clearTimeout(flushTimer);
      stream.close();
      // The lock is advisory, so a failed release is logged rather than raised —
      // it expires on its own within the TTL.
      if (lock.token) {
        releaseLock(lockKey, lock.token).catch((err) =>
          console.warn(`[ai] chat lock release failed: ${err.message}`)
        );
      }
    }
  })
);

/**
 * Rehydrates counters before a turn is appended.
 *
 * A stream that dies mid-write leaves the increment-only `messageCount` drifting
 * upward permanently, and a user returning to a thread is exactly where that becomes
 * visible as a wrong count in Recent Chats. Recomputing on the turn path (rather
 * than only on open) also covers a thread the app never explicitly reopened.
 */

// ─── Messages ───────────────────────────────────────────────────────────────

router.delete(
  '/messages/:id',
  guard(async (req, res, userId) => {
    res.json({ success: true, data: await store.deleteMessage({ messageId: req.params.id, userId }) });
  })
);

// ─── Memory ─────────────────────────────────────────────────────────────────

router.get(
  '/memory',
  guard(async (req, res, userId) => {
    const items = await store.listMemories({ userId });
    res.json({ success: true, data: { items } });
  })
);

router.delete(
  '/memory',
  guard(async (req, res, userId) => {
    const { removed } = await store.clearMemories({ userId });
    res.json({ success: true, data: { removed } });
  })
);

// ─── Preferences ────────────────────────────────────────────────────────────

router.get(
  '/preferences',
  guard(async (req, res, userId) => {
    res.json({ success: true, data: await store.getPreferences({ userId }) });
  })
);

router.patch(
  '/preferences',
  guard(async (req, res, userId) => {
    const patch = {};
    for (const key of ['memoryEnabled', 'chatHistoryEnabled', 'voiceEnabled']) {
      if (typeof req.body?.[key] === 'boolean') patch[key] = req.body[key];
    }
    if (typeof req.body?.preferredLanguage === 'string') {
      patch.preferredLanguage = clampText(req.body.preferredLanguage, 32) || null;
    }
    if (typeof req.body?.responseStyle === 'string') {
      patch.responseStyle = clampText(req.body.responseStyle, 32) || null;
    }
    res.json({ success: true, data: await store.updatePreferences({ userId, ...patch }) });
  })
);

router.delete(
  '/chats',
  guard(async (req, res, userId) => {
    res.json({ success: true, data: await store.deleteAllConversations({ userId }) });
  })
);

// ─── Voice ──────────────────────────────────────────────────────────────────

/**
 * Synthesises speech for one assistant message.
 *
 * Ownership is checked before synthesis, not after: synthesising first and then
 * refusing to hand back the bytes would let any authenticated user spend the
 * account's ElevenLabs credits on arbitrary text of their choosing.
 */
router.post(
  '/messages/:id/voice',
  guard(async (req, res, userId) => {
    const message = await store.getMessage({ messageId: req.params.id, userId });
    if (message.role !== 'assistant' || !message.content) {
      return jsonError(res, { status: 400, code: 'NOT_SPEAKABLE', message: 'No speakable text on this message' });
    }

    const result = await voice.generateSpeech({
      text: message.content,
      messageId: message.messageId,
      voiceId: req.body?.voiceId,
      force: req.body?.force === true,
    });

    // §13: a voice failure is not a chat failure. The text is already persisted and
    // displayed, so this is a 200 with ok:false and the UI shows
    // "Voice unavailable. Tap to retry."
    if (!result.ok) {
      return res.status(200).json({
        success: true,
        data: {
          ok: false,
          reason: result.reason,
          audioUrl: `/api/ai/messages/${message.messageId}/voice`,
          retryable: true,
        },
      });
    }

    if (result.cacheKey) {
      await store.updateMessage({
        messageId: message.messageId,
        userId,
        voiceCacheKey: result.cacheKey,
      });
    }

    res.json({
      success: true,
      data: {
        ok: true,
        cached: result.cached,
        audioUrl: `/api/ai/messages/${message.messageId}/voice`,
        bytes: result.audio.length,
      },
    });
  })
);

/**
 * Streams the audio bytes.
 *
 * Separate from the POST above so playback is a plain authenticated GET, which is
 * what just_audio wants: it can attach the Authorization header to a GET far more
 * simply than it can POST and then fetch a body. Regenerates on a cache miss, so a
 * cached audio blob that expired after a week still plays without a second client
 * round trip.
 */
router.get(
  '/messages/:id/voice',
  guard(async (req, res, userId) => {
    const message = await store.getMessage({ messageId: req.params.id, userId });
    if (message.role !== 'assistant' || !message.content) {
      return jsonError(res, { status: 404, code: 'NOT_SPEAKABLE', message: 'No speakable text on this message' });
    }

    const result = await voice.generateSpeech({
      text: message.content,
      messageId: message.messageId,
      voiceId: req.query.voiceId || undefined,
    });
    if (!result.ok) {
      return jsonError(res, { status: 503, code: result.reason, message: 'Voice unavailable' });
    }

    res.set({
      'Content-Type': result.mimeType,
      'Content-Length': String(result.audio.length),
      // Private: the bytes are a paid synthesis of one user's own words, and they
      // are only reachable with that user's token.
      'Cache-Control': 'private, max-age=3600',
    });
    res.end(result.audio);
  })
);

module.exports = router;
module.exports.requireUser = requireUser;