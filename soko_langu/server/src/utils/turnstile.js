const config = require('../config');

const SITEVERIFY_URL = 'https://challenges.cloudflare.com/turnstile/v0/siteverify';

async function verifyTurnstile(req, { expectedAction } = {}) {
  const secret = config.turnstile && config.turnstile.secret;
  const hostnames = (config.turnstile && config.turnstile.hostnames) || [];

  if (!secret) {
    return { ok: false, status: 503, code: 'TURNSTILE_NOT_CONFIGURED', message: 'Bot verification is not configured.' };
  }

  const body = req.body || {};
  const token =
    body['cf-turnstile-response'] ||
    body.turnstileToken ||
    body.turnstile_token ||
    req.headers['cf-turnstile-response'] ||
    '';

  if (typeof token !== 'string' || token.length === 0 || token.length > 2048 || hostnames.length === 0) {
    return { ok: false, status: 403, code: 'TURNSTILE_FAILED', message: 'Bot verification failed. Please try again.' };
  }

  const remoteIp =
    (typeof req.ip === 'string' && req.ip) ||
    (req.connection && req.connection.remoteAddress) ||
    '';

  let result;
  try {
    const params = new URLSearchParams({ secret, response: token });
    if (remoteIp) params.set('remoteip', remoteIp);

    const response = await fetch(SITEVERIFY_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: params,
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) throw new Error(`siteverify ${response.status}`);
    result = await response.json();
  } catch (err) {
    return { ok: false, status: 403, code: 'TURNSTILE_FAILED', message: 'Bot verification failed. Please try again.' };
  }

  const hostnameOk = hostnames.includes(result.hostname);
  const actionOk = !expectedAction || result.action === expectedAction;

  if (!result || result.success !== true || !hostnameOk || !actionOk) {
    return { ok: false, status: 403, code: 'TURNSTILE_FAILED', message: 'Bot verification failed. Please try again.' };
  }

  return { ok: true, result };
}

function turnstileMiddleware(expectedAction) {
  return async (req, res, next) => {
    const verified = await verifyTurnstile(req, { expectedAction });
    if (!verified.ok) {
      return res.status(verified.status || 403).json({
        success: false,
        error: verified.code || 'TURNSTILE_FAILED',
        message: verified.message || 'Bot verification failed. Please try again.',
      });
    }
    req.turnstile = verified.result;
    return next();
  };
}

module.exports = {
  verifyTurnstile,
  turnstileMiddleware,
};
