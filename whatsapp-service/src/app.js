const express = require('express');
const config = require('./config');
const { normalizePhone } = require('./phone');
const { sendText, checkToken, WhatsAppError } = require('./whatsapp');
const { logMessage } = require('./logger');
const { requireApiKey, apiRateLimit, errorHandler } = require('./middleware');

const MAX_BODY_LENGTH = 4096;

function validateMessage(message) {
  if (typeof message !== 'string' || message.trim().length === 0) {
    return 'message is required';
  }
  if (message.length > MAX_BODY_LENGTH) {
    return `message must be at most ${MAX_BODY_LENGTH} characters`;
  }
  return null;
}

async function deliver(rawPhone, message, source) {
  const to = normalizePhone(rawPhone);
  if (!to) {
    logMessage({ to: String(rawPhone), ok: false, errorCode: 'INVALID_PHONE', bodyLength: message.length, source });
    return { to: String(rawPhone), ok: false, code: 'INVALID_PHONE', error: 'Invalid phone number' };
  }
  try {
    const { wamid, waId } = await sendText(to, message);
    logMessage({ to, ok: true, wamid, bodyLength: message.length, source });
    return { to, ok: true, wamid, waId };
  } catch (err) {
    const code = err instanceof WhatsAppError ? err.code : 'INTERNAL_ERROR';
    logMessage({ to, ok: false, errorCode: code, bodyLength: message.length, source });
    return { to, ok: false, code, error: err.message, graphCode: err.graphCode };
  }
}

// Runs tasks with a fixed number of workers so a large bulk list cannot burst
// past Meta's throughput limits.
async function runPool(items, limit, worker) {
  const results = new Array(items.length);
  let next = 0;
  async function lane() {
    while (next < items.length) {
      const i = next;
      next += 1;
      results[i] = await worker(items[i]);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, lane));
  return results;
}

function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json({ limit: '256kb' }));
  app.use('/api', apiRateLimit);

  app.get('/api/status', async (req, res, next) => {
    try {
      const token = await checkToken();
      res.json({
        success: true,
        service: 'whatsapp-service',
        apiVersion: config.version,
        phoneNumberId: config.phoneNumberId || null,
        ...token,
      });
    } catch (err) {
      next(err);
    }
  });

  app.post('/api/send-message', requireApiKey, async (req, res, next) => {
    try {
      const { to, message } = req.body || {};
      const problem = validateMessage(message);
      if (problem) return res.status(400).json({ success: false, code: 'INVALID_MESSAGE', error: problem });
      if (!normalizePhone(to)) {
        return res.status(400).json({ success: false, code: 'INVALID_PHONE', error: 'Invalid phone number' });
      }
      if (!config.isConfigured) {
        return res.status(503).json({ success: false, code: 'NOT_CONFIGURED', error: 'USER_ACCESS_TOKEN or PHONE_NUMBER_ID is not set' });
      }

      const result = await deliver(to, message, 'send-message');
      if (!result.ok) {
        const status = result.code === 'INVALID_PHONE' ? 400 : 422;
        return res.status(status).json({ success: false, ...result });
      }
      return res.json({ success: true, to: result.to, wamid: result.wamid, waId: result.waId });
    } catch (err) {
      next(err);
    }
  });

  app.post('/api/send-bulk', requireApiKey, async (req, res, next) => {
    try {
      const { recipients, message } = req.body || {};
      const problem = validateMessage(message);
      if (problem) return res.status(400).json({ success: false, code: 'INVALID_MESSAGE', error: problem });
      if (!Array.isArray(recipients) || recipients.length === 0) {
        return res.status(400).json({ success: false, code: 'INVALID_RECIPIENTS', error: 'recipients must be a non-empty array' });
      }
      if (recipients.length > config.bulkMaxRecipients) {
        return res.status(400).json({
          success: false,
          code: 'TOO_MANY_RECIPIENTS',
          error: `At most ${config.bulkMaxRecipients} recipients per request`,
        });
      }
      if (!config.isConfigured) {
        return res.status(503).json({ success: false, code: 'NOT_CONFIGURED', error: 'USER_ACCESS_TOKEN or PHONE_NUMBER_ID is not set' });
      }

      const unique = [...new Set(recipients.map((r) => String(r).trim()))];
      const results = await runPool(unique, config.bulkConcurrency, (raw) => deliver(raw, message, 'send-bulk'));
      const sent = results.filter((r) => r.ok).length;

      return res.json({
        success: true,
        total: unique.length,
        duplicatesRemoved: recipients.length - unique.length,
        sent,
        failed: unique.length - sent,
        results,
      });
    } catch (err) {
      next(err);
    }
  });

  app.use(errorHandler);
  return app;
}

module.exports = { createApp, runPool, validateMessage };
