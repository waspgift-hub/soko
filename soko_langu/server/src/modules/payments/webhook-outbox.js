// Webhook outbox facade.
//
// The authoritative implementation lives in `src/services/commerce-store.js`
// (commerce-store.recordWebhookEvent / markWebhookStatus), which claim the
// dedup key INSIDE a Firestore transaction via `create()` — a read-then-set
// check there is a time-of-check/time-of-use race that two concurrent deliveries
// of the same ClickPesa event would both lose. The webhooks collection is part of
// the commerce data domain, so it is owned here rather than in a generic store.
//
// Re-exported under the historical names so callers (payment-service) keep their
// existing surface; behaviour is now the atomic one described in the Phase 3/5
// money-safety requirements.
const commerce = require('../../services/commerce-store');

function buildDedupKey(providerName, webhookId, payload) {
  if (webhookId) return `${providerName}:${String(webhookId).slice(0, 200)}`;
  const crypto = require('crypto');
  const raw = JSON.stringify(payload ?? {});
  return `${providerName}:sha256:${crypto.createHash('sha256').update(raw).digest('hex')}`;
}

async function recordWebhookEvent({ provider, dedupKey, type, rawPayload, signature, orderReference } = {}) {
  const claimed = await commerce.recordWebhookEvent({
    provider,
    dedupKey,
    type,
    rawPayload,
    signature,
    orderReference,
  });
  // `claimed` carries `{ claimed, duplicate, id, status, orderReference }` from
  // the transaction outcome. Callers branch on `claimed === false` (loser of the
  // race) or `duplicate === true` (re-delivery of an already-processed event).
  if (claimed && claimed.claimed === false) {
    return claimed;
  }
  return claimed;
}

async function markWebhookProcessing(event) {
  return commerce.markWebhookStatus(event, commerce.WEBHOOK_STATUS_PROCESSING);
}

async function markWebhookProcessed(event) {
  return commerce.markWebhookStatus(event, commerce.WEBHOOK_STATUS_PROCESSED);
}

async function markWebhookFailed(event, error) {
  return commerce.markWebhookStatus(event, commerce.WEBHOOK_STATUS_FAILED, { error });
}

module.exports = {
  buildDedupKey,
  recordWebhookEvent,
  markWebhookProcessing,
  markWebhookProcessed,
  markWebhookFailed,
  WEBHOOK_STATUS_RECEIVED: commerce.WEBHOOK_STATUS_RECEIVED,
  WEBHOOK_STATUS_PROCESSING: commerce.WEBHOOK_STATUS_PROCESSING,
  WEBHOOK_STATUS_PROCESSED: commerce.WEBHOOK_STATUS_PROCESSED,
  WEBHOOK_STATUS_FAILED: commerce.WEBHOOK_STATUS_FAILED,
};
