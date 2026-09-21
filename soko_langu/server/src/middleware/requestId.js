const crypto = require('crypto');

// API contract §25: every response carries a requestId so a support report or
// server log line can be correlated to the exact request. The id propagates
// from the caller's `x-request-id` when present (edge/worker passes it down),
// otherwise a fresh uuid. The `res.json` enrichment is additive — it never
// overwrites an existing requestId, so it cannot break existing payloads.
function requestId(req, res, next) {
  req.id = req.headers['x-request-id'] || crypto.randomUUID();
  res.setHeader('x-request-id', req.id);

  const originalJson = res.json.bind(res);
  res.json = (body) => {
    if (body && typeof body === 'object' && !Array.isArray(body)) {
      if (!body.requestId) {
        return originalJson({ ...body, requestId: req.id });
      }
    }
    return originalJson(body);
  };
  next();
}

module.exports = requestId;