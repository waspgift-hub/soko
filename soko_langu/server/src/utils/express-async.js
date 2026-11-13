// Express 4 does not forward rejected promises from async handlers to the
// error middleware — a throwing async handler hangs the request until the
// proxy gives up (504). Every route/middleware handler flows through
// Layer#handle_request exactly once, so patching it catches all async
// rejections app-wide and routes them to the central error handler in app.js.
const Layer = require('express/lib/router/layer');

const originalHandleRequest = Layer.prototype.handle_request;

// Preserve the original body unchanged except: capture the handler's return
// value and, when it is a promise, forward rejections to next(err) so Express
// can run its normal error chain instead of stalling the socket.
Layer.prototype.handle_request = function handle_request(req, res, next) {
  const fn = this.handle;

  if (fn.length > 3) {
    // not a standard request handler
    return next();
  }

  try {
    const returned = fn(req, res, next);
    if (returned && typeof returned.catch === 'function') {
      returned.catch(next);
    }
  } catch (err) {
    next(err);
  }
};

module.exports = { originalHandleRequest };