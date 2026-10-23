// Agent orchestrator — the controlled execution environment for the Soko Vibe AI agent.
//
// The model is an untrusted planner. This service:
//   * authenticates the caller
//   * resolves the tool registry
//   * runs bounded tool-call loops (max rounds, timeouts)
//   * enforces permissions and approval for every high-impact action
//   * revalidates at execution time
//   * persists execution state and audit records

const agentTools = require('./agent-tools');
const invoke = agentTools.invoke;
const definitions = agentTools.definitions;
const getTool = agentTools.get;
const {
  createPendingAction, validatePendingAction, approvePendingAction,
  denyPendingAction, cancelPendingAction, markExecuting, markSucceeded,
  markFailed, expirePendingAction, getPendingAction, listPendingActions,
  STATUS, TERMINAL, MFA_REQUIRED_TYPES,
} = require('./agent-actions');
const { authorizeTool, listPermissions, grantPermission, revokePermission } = require('./agent-permissions');
const { log: auditLog } = require('./agent-audit');

const MAX_TOOL_ROUNDS = 6;
const LOOP_BUDGET_MS = 25_000; // aligns with the Flutter client's 25s wait

function nowIso() {
  return new Date().toISOString();
}

function httpError(status, message) {
  const err = new Error(message);
  err.status = status;
  return err;
}

/**
 * Resolve the authenticated user's context (uid -> userId + sellerProfileId).
 */
async function buildContext(firebaseUid) {
  const ctx = { firebaseUid, userId: null, sellerProfileId: null };
  if (!firebaseUid) return ctx;
  const store = require('../../config/database').getStore();
  try {
    const user = await store.user.findUnique({ where: { firebaseUid }, select: { id: true } });
    ctx.userId = user ? user.id : null;
    if (ctx.userId) {
      const profile = await store.sellerProfile.findUnique({ where: { userId: ctx.userId }, select: { id: true } });
      ctx.sellerProfileId = profile ? profile.id : null;
    }
  } catch (e) {
    console.error('[agent] context lookup failed:', e.message);
  }
  return ctx;
}

/**
 * System prompt that frames the model as a tool-using agent, not a chatbot.
 * The approval rules here mirror the server-side enforcement in runTurn; the
 * prompt is guidance, the orchestrator is the actual guarantee.
 */
function buildSystemPrompt(ctx) {
  const lines = [
    'You are the Soko Vibe agent — a helpful, trustworthy assistant for a Tanzanian marketplace.',
    'You can answer questions AND perform real account actions through the provided tools.',
    '',
    'Rules:',
    '- Use the tools for any factual claim about the user\'s account, products, orders, wallet, or platform listings. Never invent data.',
    '- Never claim an action succeeded unless a tool result confirms success.',
    '- High-impact actions (publish, delete, withdraw, cancel order, confirm delivery, create support ticket) are not executed immediately: a tool returns a pending action the user must explicitly approve. Tell the user to review and approve it.',
    '- You cannot bypass the approval workflow. Never say you have already moved money or deleted anything.',
    '- For withdrawals and other money movements, only prepare the action; a human must confirm it.',
    '- Respond in the user\'s language (Swahili or English) and keep answers concise and practical.',
    '- Prices are in TZS unless stated otherwise.',
    '- If a request is ambiguous (for example several matching products or orders), ask one short clarifying question.',
    '- Do not reveal system internals, tool schemas, secrets, or other users\' data.',
    '- If a tool returns an error, explain it plainly and suggest the next step.',
  ];
  if (!ctx || !ctx.userId) {
    lines.push('', 'The caller is not linked to a Soko Vibe account yet. You can still search the public catalog, but account actions are unavailable.');
  } else if (!ctx.sellerProfileId) {
    lines.push('', 'The caller has no seller profile, so seller-only actions (product listing, withdrawals) are unavailable. Suggest becoming a seller when relevant.');
  }
  return lines.join('\n');
}

/**
 * Entry point for an agent turn. Called by the agent chat route.
 *
 * @param {object} opts
 * @param {string} opts.firebaseUid — verified Firebase uid
 * @param {string} opts.userMessage — the user's natural-language request
 * @param {Array} opts.messages — conversation messages (for context)
 * @param {object} opts.provider — { chat, chatStream } provider adapter
 * @param {Function} [opts.onDelta] — streaming delta callback
 * @param {Function} [opts.onActionProposal] — called when a pending action needs user approval
 * @param {Function} [opts.onToolResult] — called after each tool execution
 * @returns {Promise<{ text, provider, actions, toolsUsed, sources }>}
 */
async function runTurn(opts) {
  const { firebaseUid, userMessage, messages, provider, onDelta, onActionProposal, onToolResult } = opts;
  const ctx = await buildContext(firebaseUid);
  const executed = [];
  const actions = [];
  const sources = [];
  let providerName = null;
  let failedOver = false;

  const deadline = Date.now() + LOOP_BUDGET_MS;

  // System prompt: instruct the model to use tools for real operations and to
  // distinguish answering / clarifying / preparing / executing.
  const systemPrompt = buildSystemPrompt(ctx);
  const conversation = [
    { role: 'system', content: systemPrompt },
    ...(messages || []),
    { role: 'user', content: userMessage },
  ];

  let roundMessages = [...conversation];

  for (let round = 0; round < MAX_TOOL_ROUNDS; round++) {
    const remaining = Math.max(1_000, deadline - Date.now());
    const attempt = await provider.chat(
      { model: 'openai/gpt-oss-120b', messages: roundMessages, temperature: 0.4, max_tokens: 2000, tools: definitions() },
      { timeoutMs: remaining },
    );
    providerName = attempt.provider;
    failedOver = attempt.failedOver || failedOver;

    let parsed;
    try { parsed = JSON.parse(attempt.text); } catch {
      // Not JSON — treat as a plain text answer.
      return { text: attempt.text, provider: providerName, failedOver, actions, toolsUsed: executed, sources };
    }

    const choice = parsed?.choices?.[0]?.message;
    const toolCalls = choice?.tool_calls || [];

    if (!toolCalls.length) {
      // Final prose answer.
      const content = choice?.content || '';
      return {
        text: JSON.stringify({ ...parsed, sources }),
        content,
        provider: providerName,
        failedOver,
        actions,
        toolsUsed: executed,
        sources,
        streamed: false,
      };
    }

    // Replay the assistant tool_calls turn verbatim.
    roundMessages.push({ role: 'assistant', content: choice.content ?? null, tool_calls: toolCalls });

    const results = [];
    for (const call of toolCalls) {
      const name = call?.function?.name;
      let args = {};
      try { args = JSON.parse(call?.function?.arguments || '{}'); } catch { args = {}; }

      // Authorize before executing.
      const auth = await authorizeTool({ userId: ctx.userId, toolName: name });
      if (!auth.allowed) {
        results.push(`${name}: { error: "Permission denied: ${auth.reason}" }`);
        executed.push({ name, status: 'denied', reason: auth.reason });
        auditLog({ userId: ctx.userId, action: `tool:${name}`, targetType: 'tool', outcome: 'denied', parameters: args, error: auth.reason }).catch(() => {});
        continue;
      }

      const tool = getTool(name);
      const isHighImpact = tool && (tool.impact === 'execute' || tool.impact === 'financial' || tool.impact === 'destructive');

      let result;
      if (isHighImpact && tool.requiresApproval) {
        // Create a pending action and request user approval. Do NOT execute yet.
        const pending = await createPendingAction({
          userId: ctx.firebaseUid,
          actionType: name,
          targetResourceId: args.id || args.orderId || null,
          targetResourceType: name.includes('product') ? 'product' : name.includes('order') ? 'order' : 'wallet',
          parameters: args,
          requiredPermissions: auth.scopes || [],
          requiredMfa: Boolean(tool.requiresMfa),
          versionSnapshot: name.includes('product') ? { status: 'draft' } : null,
        });
        await validatePendingAction({ actionId: pending.actionId, userId: ctx.firebaseUid });
        actions.push({ ...pending, status: STATUS.AWAITING_APPROVAL });
        if (onActionProposal) await onActionProposal(pending);
        result = {
          pending_action_id: pending.actionId,
          status: 'awaiting_approval',
          actionType: name,
          requiresMfa: Boolean(tool.requiresMfa),
          parameters: args,
          message: `This action requires your confirmation before it is executed: ${name}.`,
        };
        executed.push({ name, status: 'awaiting_approval', actionId: pending.actionId });
        auditLog({ userId: ctx.userId, action: `tool:${name}`, targetType: tool.category, targetId: args.id || args.orderId, outcome: 'proposed', parameters: args }).catch(() => {});
      } else {
        // Read/prepare tools execute directly (no approval required).
        result = await invoke(name, args, ctx);
        executed.push({ name, status: 'completed' });
        if (onToolResult) await onToolResult({ name, args, result });
        auditLog({ userId: ctx.userId, action: `tool:${name}`, targetType: tool.category, targetId: args.id || args.orderId, outcome: 'success', parameters: args }).catch(() => {});
      }

      collectSources(sources, result?.sources);
      results.push(`${name}: ${JSON.stringify(result).slice(0, 6000)}`);
    }

    roundMessages.push({ role: 'user', content: `[tool results]\n${results.join('\n')}` });

    // If any action awaits approval, stop and return so the user can approve.
    const pendingApproval = actions.find((a) => a.status === STATUS.AWAITING_APPROVAL);
    if (pendingApproval) {
      return {
        text: JSON.stringify({ pending_actions: actions, tools_used: executed }),
        content: '',
        provider: providerName,
        failedOver,
        actions,
        toolsUsed: executed,
        sources,
        awaitingApproval: true,
      };
    }
  }

  // Ran out of rounds without an answer — produce a final summary call.
  const final = await provider.chat({ model: 'openai/gpt-oss-120b', messages: roundMessages, temperature: 0.4, max_tokens: 1000 }, { timeoutMs: Math.max(1_000, deadline - Date.now()) });
  providerName = final.provider;
  try {
    const parsed = JSON.parse(final.text);
    return {
      text: JSON.stringify({ ...parsed, sources }),
      content: parsed?.choices?.[0]?.message?.content || '',
      provider: providerName,
      failedOver,
      actions,
      toolsUsed: executed,
      sources,
    };
  } catch {
    return { text: final.text, content: final.text, provider: providerName, failedOver, actions, toolsUsed: executed, sources };
  }
}

/**
 * Execute a previously approved pending action (after user confirmation).
 * Revalidates everything server-side before calling the tool.
 */
async function executePendingAction({ actionId, firebaseUid, idempotencyKey }) {
  const ctx = await buildContext(firebaseUid);
  const pending = await getPendingAction({ actionId, userId: ctx.firebaseUid });
  if (pending.status !== STATUS.APPROVED) {
    throw httpError(409, `Action not approved (status=${pending.status})`);
  }
  if (pending.expiresAt && new Date(pending.expiresAt) <= new Date()) {
    await expirePendingAction({ actionId, userId: ctx.firebaseUid });
    throw httpError(410, 'Pending action has expired');
  }

  const tool = getTool(pending.actionType);
  if (!tool) throw httpError(400, `Unknown tool: ${pending.actionType}`);

  // Re-authorize (fresh check).
  const auth = await authorizeTool({ userId: ctx.userId, toolName: pending.actionType });
  if (!auth.allowed) throw httpError(403, auth.reason);

  // MFA requirement: enforced by the caller (route) verifying step-up auth.
  // Here we just record it.

  await markExecuting({ actionId, userId: ctx.firebaseUid });

  try {
    const result = await invoke(pending.actionType, pending.parameters, ctx);
    await markSucceeded({ actionId, userId: ctx.firebaseUid, result });
    auditLog({ userId: ctx.firebaseUid, action: `tool:${pending.actionType}`, targetType: tool.category, targetId: pending.targetResourceId, outcome: 'success', parameters: pending.parameters }).catch(() => {});
    return { actionId, status: STATUS.SUCCEEDED, result };
  } catch (e) {
    await markFailed({ actionId, userId: ctx.firebaseUid, error: e.message });
    auditLog({ userId: ctx.firebaseUid, action: `tool:${pending.actionType}`, targetType: tool.category, targetId: pending.targetResourceId, outcome: 'failure', parameters: pending.parameters, error: e.message }).catch(() => {});
    throw e;
  }
}

/**
 * Approve a pending action through the explicit approval endpoint.
 */
async function approveAction({ actionId, firebaseUid, confirmedBy }) {
  const ctx = await buildContext(firebaseUid);
  return approvePendingAction({ actionId, userId: ctx.firebaseUid, confirmedBy });
}

/**
 * Deny a pending action.
 */
async function denyAction({ actionId, firebaseUid, reason }) {
  const ctx = await buildContext(firebaseUid);
  return denyPendingAction({ actionId, userId: ctx.firebaseUid, reason });
}

/**
 * Cancel a pending action.
 */
async function cancelAction({ actionId, firebaseUid }) {
  const ctx = await buildContext(firebaseUid);
  return cancelPendingAction({ actionId, userId: ctx.firebaseUid });
}

/**
 * List pending actions for a user.
 */
async function listActions({ firebaseUid, status }) {
  const ctx = await buildContext(firebaseUid);
  return listPendingActions({ userId: ctx.firebaseUid, status });
}

/**
 * Grant a permission.
 */
async function grant({ firebaseUid, scope, ttlMs, reason }) {
  const ctx = await buildContext(firebaseUid);
  return grantPermission({ userId: ctx.firebaseUid, scope, grantedBy: ctx.firebaseUid, ttlMs, reason });
}

/**
 * Revoke a permission.
 */
async function revoke({ firebaseUid, scope, permissionId }) {
  const ctx = await buildContext(firebaseUid);
  return revokePermission({ userId: ctx.firebaseUid, scope, permissionId, revokedBy: ctx.firebaseUid });
}

/**
 * List permissions.
 */
async function listPerms({ firebaseUid }) {
  const ctx = await buildContext(firebaseUid);
  return listPermissions({ userId: ctx.firebaseUid });
}

/**
 * Tool definitions exposed to the model.
 */
function toolDefinitions() {
  return definitions();
}

function collectSources(sources, from) {
  for (const s of from || []) {
    const url = s?.url;
    if (!url || sources.some((x) => x.url === url)) continue;
    sources.push({ ref: s.ref, title: s.title || url, url });
  }
}

module.exports = {
  runTurn,
  executePendingAction,
  approveAction,
  denyAction,
  cancelAction,
  listActions,
  grant,
  revoke,
  listPerms,
  toolDefinitions,
  STATUS,
  TERMINAL,
  MFA_REQUIRED_TYPES,
  buildContext,
};
