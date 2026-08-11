// Lightweight in-memory TTL cache.
//
// Purpose: cut Firestore reads on hot public endpoints (most-rated, trending,
// autocomplete) so the Spark free tier's 50K reads/day isn't exhausted by a
// handful of repeat visitors. Single-instance cache — Render free runs one
// process, so no cross-instance invalidation is needed. TTL is short enough
// that stale data is not a correctness problem.

const store = new Map();

function get(key) {
  const entry = store.get(key);
  if (!entry) return undefined;
  if (entry.expiresAt <= Date.now()) {
    store.delete(key);
    return undefined;
  }
  return entry.value;
}

function set(key, value, ttlMs) {
  store.set(key, { value, expiresAt: Date.now() + ttlMs });
  prune();
  return value;
}

function del(key) {
  store.delete(key);
}

// Drop expired entries and bail once a max size is exceeded so the 512MB free
// plan doesn't OOM from unbounded growth. Prunes lazily on each write.
const MAX_ENTRIES = 500;
function prune() {
  if (store.size < MAX_ENTRIES) return;
  const now = Date.now();
  for (const [key, entry] of store) {
    if (entry.expiresAt <= now) store.delete(key);
  }
  if (store.size >= MAX_ENTRIES) {
    // Still over budget — drop oldest by expiresAt.
    const oldest = [...store.entries()]
      .sort((a, b) => a[1].expiresAt - b[1].expiresAt)
      .slice(0, Math.floor(MAX_ENTRIES / 4));
    for (const [key] of oldest) store.delete(key);
  }
}

module.exports = { get, set, del, prune };
