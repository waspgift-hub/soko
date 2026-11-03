/**
 * Webhook outbox (Layer-2 idempotency).
 *
 * Append-only receipt of provider webhook events. A unique dedup_key (provider
 * event id, or a sha256 of the payload when no id is present) makes re-delivery
 * and multi-instance concurrency at-most-once:
 *
 *   received -> processing -> processed
 *   received/processing -> failed (attempts++, retryable)
 *   processed  -> duplicate (ack 200, no-op)
 *
 * If the webhook_events table has not been provisioned yet (fresh deploy), the
 * module degrades to an in-process, ephemeral dedupe map instead of crashing.
 */
const crypto = require('crypto');
const { getPrisma } = require('../../config/database');

const TABLE_MISSING_CODE = 'P2021';

// Ephemeral fallback used only when the DB table is absent (pre-migration).
const eventCache = new Map();
const CACHE_TTL_MS = 60 * 1000;

function isTableMissingError(e) {
  return !!e && (e.code === TABLE_MISSING_CODE || /does not exist/i.test(String(e.message || '')));
}

function buildDedupKey(providerName, webhookId, payload) {
  if (webhookId) return `${providerName}:${String(webhookId).slice(0, 200)}`;
  const raw = JSON.stringify(payload ?? {});
  return `${providerName}:sha256:${crypto.createHash('sha256').update(raw).digest('hex')}`;
}

function cacheGet(key) {
  const entry = eventCache.get(key);
  if (!entry) return null;
  if (entry.expiresAt < Date.now()) {
    eventCache.delete(key);
    return null;
  }
  return entry;
}

function cacheSet(dedupKey, status) {
  const entry = { dedupKey, status, expiresAt: Date.now() + CACHE_TTL_MS, id: null };
  eventCache.set(dedupKey, entry);
  return entry;
}

/**
 * Record a webhook event; returns the existing row when the event was already
 * seen so callers can de-dupe by status.
 */
async function recordWebhookEvent({ provider, dedupKey, type, rawPayload, signature, orderReference }) {
  const prisma = getPrisma();
  try {
    const existing = await prisma.webhookEvent.findUnique({ where: { dedupKey } });
    if (existing) return existing;
    return await prisma.webhookEvent.create({
      data: {
        provider,
        dedupKey,
        type,
        status: 'received',
        rawPayload,
        signature,
        orderReference: orderReference || null,
      },
    });
  } catch (e) {
    if (isTableMissingError(e)) {
      const cached = cacheGet(dedupKey);
      if (cached) return cached;
      return cacheSet(dedupKey, 'received');
    }
    throw e;
  }
}

async function markWebhookProcessing(event) {
  const prisma = getPrisma();
  if (!event || !event.id) return;
  try {
    await prisma.webhookEvent.update({
      where: { id: event.id },
      data: { status: 'processing' },
    });
  } catch (e) {
    if (isTableMissingError(e)) return;
    throw e;
  }
}

async function markWebhookProcessed(event) {
  if (!event || !event.dedupKey) return;
  if (event.id) {
    try {
      await getPrisma().webhookEvent.update({
        where: { id: event.id },
        data: { status: 'processed', processedAt: new Date() },
      });
      return;
    } catch (e) {
      if (!isTableMissingError(e)) throw e;
    }
  }
  const cached = cacheGet(event.dedupKey);
  if (cached) cached.status = 'processed';
}

async function markWebhookFailed(event, error) {
  if (!event || !event.dedupKey) return;
  if (event.id) {
    try {
      await getPrisma().webhookEvent.update({
        where: { id: event.id },
        data: {
          status: 'failed',
          attempts: { increment: 1 },
          lastError: error && error.message ? String(error.message).slice(0, 500) : 'unknown',
        },
      });
      return;
    } catch (e) {
      if (!isTableMissingError(e)) throw e;
    }
  }
  const cached = cacheGet(event.dedupKey);
  if (cached) cached.status = 'failed';
}

module.exports = {
  buildDedupKey,
  recordWebhookEvent,
  markWebhookProcessing,
  markWebhookProcessed,
  markWebhookFailed,
  WEBHOOK_STATUS_RECEIVED: 'received',
  WEBHOOK_STATUS_PROCESSING: 'processing',
  WEBHOOK_STATUS_PROCESSED: 'processed',
  WEBHOOK_STATUS_FAILED: 'failed',
};