// Load shedding / graceful degradation.
//
// Why: at 10M users the API must protect itself from a synthetic flood (a
// runaway retry loop, a misbehaving webhook, a scripted crawl). When the event
// loop is saturated or heap usage is critical we answer 503 + Retry-After so
// the load balancer (Render) stops sending work this instance, and the instance
// keeps serving requests instead of dying under memory pressure.
//
// Health endpoint is exempt so platform probes can always tell us apart.
const { hostname } = require('os');

// Tune via env so rebalancing doesn't need a redeploy.
const EVENT_LOOP_LAG_MS = Number(process.env.EVENT_LOOP_LAG_MS || 1500);
const HEAP_CRITICAL_MB = Number(process.env.HEAP_CRITICAL_MB || 512);
const SHED_WHEN = process.env.SHED_LOAD === 'true'; // master switch, default off
const RETRY_SECONDS = Number(process.env.SHED_RETRY_AFTER || 10);

function heapUsedMB() {
  const mem = process.memoryUsage();
  return Math.round(mem.heapUsed / 1024 / 1024);
}

// Sample event-loop lag without blocking: setTimeout(0) whose measured delay
// tells us how far behind the loop is.
function measureEventLoopLag() {
  return new Promise((resolve) => {
    const start = process.hrtime.bigint();
    setImmediate(() => {
      const ns = process.hrtime.bigint() - start;
      resolve(Math.round(Number(ns) / 1e6));
    });
  });
}

function loadShedder() {
  let shedCount = 0;
  let lastShedAt = 0;

  return async function shed(req, res, next) {
    if (!SHED_WHEN || req.path === '/health' || req.method === 'HEAD') {
      return next();
    }

    const heap = heapUsedMB();
    let lag = 0;
    try {
      lag = await measureEventLoopLag();
    } catch (_) { /* measuring is best-effort */ }

    // Shed only when BOTH signals move (lag high AND heap high) to avoid
    // shedding on a single transient spike, with one exception: lag alone above
    // 5s (a true event-loop stall) also sheds.
    const critical = (lag > EVENT_LOOP_LAG_MS && heap > HEAP_CRITICAL_MB) || lag > EVENT_LOOP_LAG_MS * 3;

    if (!critical) return next();

    shedCount += 1;
    lastShedAt = Date.now();
    res.setHeader('Retry-After', String(RETRY_SECONDS));
    res.setHeader('X-Shed-Features', `${lag}ms,${heap}MB`);
    // Server-timing is free observability for the edge + logs.
    res.setHeader('Server-Timing', `load;desc="shed"`);
    return res.status(503).json({
      error: 'Service temporarily busy, retry shortly',
      code: 'load_shed',
    });
  };
}

// Small stats endpoint for the admin/health card to show shedding globally.
module.exports = { loadShedder, heapUsedMB, measureEventLoopLag, hostname };