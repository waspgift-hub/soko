// Circuit breaker for external providers (ClickPesa, SMS, OneSignal, Groq).
//
// Why: at 10M users a single provider outage must not cascade into HTTP 500s
// for the whole API. The breaker trips OPEN after `failureThreshold` consecutive
// failures, then lets callers fail FAST (no network round-trip) while a
// background probe periodically tries HALF-OPEN — one success re-closes it.
//
// Usage:
//   const breaker = createBreaker('clickpesa', { failureThreshold: 5 });
//   const res = await breaker.call(() => provider.initiateCollection(body));
//   // falls back to a provided fallback when the breaker is OPEN:
//   const res = await breaker.call(() => ..., () => fallbackValue());

const DEFAULT = {
  failureThreshold: 5,   // consecutive failures before tripping OPEN
  halfOpenProbeMs: 10_000, // probe interval while OPEN
  cooldownMs: 30_000,    // min time the breaker stays OPEN before probing
};

function createBreaker(name, opts = {}) {
  const cfg = { ...DEFAULT, ...opts };
  let state = 'closed';           // closed | open | half-open
  let consecutiveFailures = 0;
  let openedAt = 0;
  let probeClaimed = false;       // one half-open probe at a time

  function tripOpen() {
    state = 'open';
    openedAt = Date.now();
    consecutiveFailures = 0;
    probeClaimed = false;
    console.error(`[breaker] ${name} OPEN (provider unhealthy)`);
  }

  function tryClaimProbe() {
    // Open + cooldown elapsed -> the FIRST caller claims the single half-open
    // probe. Any concurrent caller fails fast; a burst must not all probe at once.
    if (state === 'open' && Date.now() - openedAt >= cfg.cooldownMs) {
      if (!probeClaimed) {
        probeClaimed = true;
        state = 'half-open';
        return true;
      }
      return false;
    }
    return false;
  }

  return {
    get state() {
      return state;
    },
    get name() {
      return name;
    },
    async call(fn, fallback) {
      if (state === 'open') {
        if (!tryClaimProbe()) {
          if (fallback) return fallback();
          const err = new Error(`${name} circuit open`);
          err.circuitOpen = true;
          throw err;
        }
        // half-open probe: let exactly one call through
      }

      try {
        const result = await fn();
        // Success closes the breaker (full close, then reset failure counter).
        consecutiveFailures = 0;
        probeClaimed = false;
        if (state === 'half-open') {
          state = 'closed';
          console.log(`[breaker] ${name} re-closed after probe success`);
        }
        return result;
      } catch (err) {
        consecutiveFailures += 1;
        if (state !== 'open' && consecutiveFailures >= cfg.failureThreshold) {
          tripOpen();
        } else if (state === 'half-open') {
          // Probe failed: straight back to OPEN, start a fresh cooldown.
          tripOpen();
        }
        throw err;
      }
    },
    // Manual trip for autoreset/health-card overrides (e.g. after config change).
    reset() {
      state = 'closed';
      consecutiveFailures = 0;
      probeClaimed = false;
    }
  };
}

module.exports = { createBreaker };