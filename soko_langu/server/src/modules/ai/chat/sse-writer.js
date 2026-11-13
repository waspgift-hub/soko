// Server-to-client SSE for one AI turn.
//
// A thin writer around a res, not a framework. The only thing that needs care is
// framing — every event is `event: <name>\ndata: <json>\n\n`, one write per event,
// no buffering across events — because a client that receives two events as one
// chunk must still be able to split them.
//
// compression() is not a concern here: it explicitly excludes text/event-stream in
// its own isFiltered(), so deltas reach the client as they are written rather than
// sitting in a zlib buffer.

/**
 * Opens an SSE stream on [res].
 *
 * Disables the global 20s response timeout that app.js installs on every route.
 * That timeout exists to stop an ordinary request holding a worker open, but on a
 * stream it would fire mid-answer and try to write a JSON 504 body into a response
 * whose headers already promise an event stream — the client would see a malformed
 * tail and the whole turn would be discarded. The provider idle timeout in
 * provider-stream.js is the correct guard for a stream instead.
 *
 * @returns {{ event: (name: string, data: object) => void, close: () => void, closed: boolean }}
 */
function open(res) {
  res.setTimeout(0);
  res.status(200);
  res.set({
    'Content-Type': 'text/event-stream; charset=utf-8',
    'Cache-Control': 'no-cache, no-store, no-transform, must-revalidate',
    Connection: 'keep-alive',
    // Nginx in front of Render buffers proxied responses by default, which would
    // hold every delta until the stream closed and defeat the entire feature.
    'X-Accel-Buffering': 'no',
  });
  res.flushHeaders?.();
  if (typeof res.socket?.setNoDelay === 'function') {
    // Nagle batches small writes, so tokens would arrive in pairs and half a second
    // late. For a chat stream that is the whole perceived latency.
    res.socket.setNoDelay(true);
  }

  let closed = false;

  return {
    event(name, data) {
      if (closed || res.writableEnded) {
        closed = true;
        return;
      }
      try {
        res.write(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`);
      } catch (err) {
        closed = true;
        console.warn(`[ai] SSE write failed: ${err.message}`);
      }
    },
    close() {
      if (closed || res.writableEnded) {
        closed = true;
        return;
      }
      closed = true;
      res.end();
    },
    get closed() {
      return closed || res.writableEnded === true;
    },
  };
}

/**
 * One keep-alive comment, sent while waiting on a slow first token.
 *
 * An SSE connection with no bytes for the length of an upstream think looks dead to
 * mobile carriers and to Cloudflare's connection watchdog, and both will close it.
 * A comment frame is ignored by every EventSource client, so this costs nothing.
 */
function heartbeat(stream) {
  const timer = setInterval(() => {
    if (stream.closed) {
      clearInterval(timer);
      return;
    }
    try {
      stream.event('ping', { t: Date.now() });
    } catch {
      clearInterval(timer);
    }
  }, 15000);
  if (typeof timer.unref === 'function') timer.unref();
  return timer;
}

module.exports = { open, heartbeat };