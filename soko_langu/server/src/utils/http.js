// API contract §25 error envelope. `error` stays a top-level String code so the
// existing Flutter/browser clients keep parsing `body.error` unchanged while the
// structured `code`/`message`/`requestId` fields converge new consumers.
function jsonError(res, { status = 500, code = 'INTERNAL_ERROR', message = null, details = null }) {
  const requestId = res.req ? res.req.id || null : null;
  const payload = {
    success: false,
    data: null,
    error: code,
    code,
    message: message || code,
    requestId,
  };
  if (details !== null) payload.details = details;
  return res.status(status).json(payload);
}

module.exports = { jsonError };