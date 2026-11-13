// Agent API routes.
//
// All routes verify a Firebase Bearer token; the uid is the ONLY identity
// used. No handler reads a user id from the body/query, making IDOR
// structurally impossible.
//
// Endpoints:
//   POST   /api/agent/chat              run an agent turn (SSE stream)
//   POST   /api/agent/actions/:id/approve   approve a pending action
//   POST   /api/agent/actions/:id/deny      deny a pending action
//   POST   /api/agent/actions/:id/cancel    cancel a pending action
//   POST   /api/agent/actions/:id/execute   execute an approved action
//   GET    /api/agent/actions           list pending actions
//   GET    /api/agent/tools             list tool definitions (for client schema)
//   GET    /api/agent/permissions       list user's agent permissions
//   POST   /api/agent/permissions/grant   grant a permission
//   DELETE /api/agent/permissions/revoke  revoke a permission

const { Router } = require('express');
const { getFirebaseAuth } = require('../../config/firebase');
const agentService = require('./agent-service');
const agentTools = require('./agent-tools');
const { jsonError } = require('../../utils/http');
const sse = require('../ai/chat/sse-writer');

const router = Router();

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
    jsonError(res, { status: 401, code: expired ? 'TOKEN_EXPIRED' : 'INVALID_TOKEN', message: 'Invalid token' });
    return null;
  }
}

function guard(handler) {
  return async (req, res) => {
    const user = await requireUser(req, res);
    if (!user) return;
    try { await handler(req, res, user.id); } catch (err) {
      jsonError(res, { status: err.status || 500, code: err.code || 'AGENT_ERROR', message: err.message });
    }
  };
}

// ─── Chat (SSE) ──────────────────────────────────────────────

router.post(
  '/chat',
  guard(async (req, res, firebaseUid) => {
    const { text, messages, productContext, catalogStatus, locale = 'sw', model } = req.body || {};
    if (!text) {
      return jsonError(res, { status: 400, code: 'EMPTY_MESSAGE', message: 'text required' });
    }

    // The provider adapter is resolved lazily so the route stays independent of
    // which provider is configured. Falls back to the existing ai-gateway.
    const provider = require('../ai/ai-gateway');

    // runTurn appends the current user turn itself, so pass only prior history.
    const history = Array.isArray(messages) ? messages : [];

    let buffer = '';
    let streamed = false;
    let awaitingApproval = false;

    const stream = sse.open(res);
    const heartbeat = sse.heartbeat(stream);

    const FLUSH_INTERVAL_MS = 1000;
    let lastFlush = Date.now();
    let flushTimer = null;
    const scheduleFlush = () => {
      if (flushTimer) return;
      flushTimer = setTimeout(() => {
        flushTimer = null;
        lastFlush = Date.now();
        if (!buffer) return;
        // Partial progress is persisted by the client via the action lifecycle;
        // here we just keep streaming the text.
        scheduleFlush();
      }, FLUSH_INTERVAL_MS);
      if (typeof flushTimer.unref === 'function') flushTimer.unref();
    };

    const emitDelta = (t) => {
      buffer += t;
      streamed = true;
      stream.event('delta', { text: t });
      if (Date.now() - lastFlush >= FLUSH_INTERVAL_MS) scheduleFlush();
    };

    try {
      const result = await agentService.runTurn({
        firebaseUid,
        userMessage: text,
        messages: history,
        provider,
        onDelta: emitDelta,
        onActionProposal: async (pending) => {
          awaitingApproval = true;
          stream.event('action_proposal', {
            actionId: pending.actionId,
            actionType: pending.actionType,
            status: pending.status,
            parameters: pending.parameters,
            requiresMfa: pending.requiredMfa,
            expiresAt: pending.expiresAt,
          });
        },
        onToolResult: async ({ name, args, result }) => {
          stream.event('tool_result', { tool: name, args, result });
        },
      });

      if (result.awaitingApproval) {
        // Stop here — the client shows an approval card and the user approves
        // via /api/agent/actions/:id/approve, then /api/agent/actions/:id/execute.
        stream.event('done', {
          messageId: null,
          content: '',
          provider: result.provider,
          failedOver: result.failedOver,
          awaitingApproval: true,
          actions: result.actions,
          toolsUsed: result.toolsUsed,
        });
        return;
      }

      const content = result.content || buffer.trim() || result.text;
      if (!content) throw Object.assign(new Error('Empty completion'), { code: 'AGENT_EMPTY_COMPLETION' });

      stream.event('done', {
        messageId: null,
        content,
        provider: result.provider,
        failedOver: result.failedOver,
        actions: result.actions,
        toolsUsed: result.toolsUsed,
        sources: result.sources,
      });
    } catch (err) {
      console.error(`[agent] stream failed: ${err.message}`);
      stream.event('error', {
        code: err.code || 'AGENT_STREAM_FAILED',
        message: err.message,
        partial: buffer.trim(),
        retryable: true,
      });
    } finally {
      clearInterval(heartbeat);
      if (flushTimer) clearTimeout(flushTimer);
      stream.close();
    }
  })
);

// ─── Action lifecycle ────────────────────────────────────────

router.post(
  '/actions/:id/approve',
  guard(async (req, res, firebaseUid) => {
    const result = await agentService.approveAction({ actionId: req.params.id, firebaseUid, confirmedBy: firebaseUid });
    res.json({ success: true, data: result });
  })
);

router.post(
  '/actions/:id/deny',
  guard(async (req, res, firebaseUid) => {
    const { reason } = req.body || {};
    const result = await agentService.denyAction({ actionId: req.params.id, firebaseUid, reason });
    res.json({ success: true, data: result });
  })
);

router.post(
  '/actions/:id/cancel',
  guard(async (req, res, firebaseUid) => {
    const result = await agentService.cancelAction({ actionId: req.params.id, firebaseUid });
    res.json({ success: true, data: result });
  })
);

router.post(
  '/actions/:id/execute',
  guard(async (req, res, firebaseUid) => {
    // Idempotency key prevents duplicate execution on double-tap.
    const idempotencyKey = req.body?.idempotencyKey || `exec_${req.params.id}`;
    const result = await agentService.executePendingAction({ actionId: req.params.id, firebaseUid, idempotencyKey });
    res.json({ success: true, data: result });
  })
);

router.get(
  '/actions',
  guard(async (req, res, firebaseUid) => {
    const actions = await agentService.listActions({ firebaseUid, status: req.query.status });
    res.json({ success: true, data: actions });
  })
);

// ─── Tools & permissions ─────────────────────────────────────

router.get(
  '/tools',
  guard(async (req, res, firebaseUid) => {
    // The client fetches tool definitions to build its action-card schema.
    // We return only the public definition + impact + approval flags (never
    // the server-side run implementation).
    const defs = agentService.toolDefinitions().map((d) => {
      const tool = agentTools.get(d.function.name);
      return {
        name: d.function.name,
        description: d.function.description,
        parameters: d.function.parameters,
        impact: tool.impact,
        requiresApproval: tool.requiresApproval,
        requiresMfa: tool.requiresMfa,
        category: tool.category,
        timeoutMs: tool.timeoutMs,
      };
    });
    res.json({ success: true, data: defs });
  })
);

router.get(
  '/permissions',
  guard(async (req, res, firebaseUid) => {
    const perms = await agentService.listPerms({ firebaseUid });
    res.json({ success: true, data: perms });
  })
);

router.post(
  '/permissions/grant',
  guard(async (req, res, firebaseUid) => {
    const { scope, ttlMs, reason } = req.body || {};
    if (!scope) {
      return jsonError(res, { status: 400, code: 'MISSING_SCOPE', message: 'scope required' });
    }
    const result = await agentService.grant({ firebaseUid, scope, ttlMs, reason });
    res.json({ success: true, data: result });
  })
);

router.delete(
  '/permissions/revoke',
  guard(async (req, res, firebaseUid) => {
    const { scope, permissionId } = req.body || {};
    const result = await agentService.revoke({ firebaseUid, scope, permissionId });
    res.json({ success: true, data: result });
  })
);

module.exports = router;
