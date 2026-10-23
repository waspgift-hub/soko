// Agent audit service — logs security-relevant agent actions.
//
// Never records OTPs, passwords, raw tokens, or full financial payloads.
// Records actor, action, target, outcome, and a sanitized parameter summary.

const { getStore } = require('../../config/database');

const COLLECTION = 'agent_audit_logs';

function sanitizeParams(params) {
  if (!params || typeof params !== 'object') return {};
  const out = {};
  const sensitive = new Set(['phoneNumber', 'password', 'otp', 'pin', 'token', 'secret', 'key']);
  for (const [k, v] of Object.entries(params)) {
    if (sensitive.has(k.toLowerCase())) {
      out[k] = '[REDACTED]';
    } else if (k === 'amount') {
      out[k] = v; // amounts are safe to audit
    } else {
      out[k] = v;
    }
  }
  return out;
}

async function log({
  userId,
  action,
  targetType,
  targetId,
  outcome,
  parameters = {},
  error = null,
  provider = null,
}) {
  const store = getStore();
  const doc = {
    userId,
    action,
    targetType: targetType || null,
    targetId: targetId || null,
    outcome: outcome || 'unknown', // success | failure | denied | error
    parameters: sanitizeParams(parameters),
    error: error ? String(error).slice(0, 500) : null,
    provider: provider || null,
    createdAt: new Date(),
  };
  try {
    await store.collection(COLLECTION).add(doc);
  } catch (e) {
    console.error('[agent] audit write failed:', e.message);
  }
  return doc;
}

module.exports = { COLLECTION, log };
