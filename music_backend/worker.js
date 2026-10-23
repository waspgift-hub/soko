const RATE_WINDOW_MS = 60_000;
const RATE_MAX = 90;
const requestBuckets = new Map();

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Accept",
    "Access-Control-Max-Age": "86400",
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff"
  };
}

function json(data, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders(), ...extraHeaders }
  });
}

function httpsUrl(value) {
  if (typeof value !== "string" || !value.trim()) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" && url.hostname ? url.toString() : null;
  } catch {
    return null;
  }
}

function mapTrack(track) {
  const audio = httpsUrl(track.audio);
  const downloadUrl = httpsUrl(track.audiodownload);
  return {
    id: String(track.id ?? ""),
    title: String(track.name ?? "Unknown title"),
    artist: String(track.artist_name ?? "Unknown artist"),
    album: track.album_name ? String(track.album_name) : null,
    image: httpsUrl(track.album_image || track.image),
    streaming_url: audio,
    duration: Number.isFinite(Number(track.duration)) ? Number(track.duration) : null,
    license: httpsUrl(track.license_ccurl || track.license),
    audiodownload: downloadUrl,
    audiodownload_allowed: track.audiodownload_allowed === true && Boolean(downloadUrl),
    source: "jamendo",
    share_url: httpsUrl(track.shareurl)
  };
}

function errorResponse(code, message, status) {
  return json({ error: code, message }, status);
}

// Best-effort per-isolate abuse guard. A globally consistent limiter requires a
// shared service such as a Durable Object; none is configured for this Worker.
function rateLimited(request) {
  const now = Date.now();
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const key = ip.slice(0, 80);
  let bucket = requestBuckets.get(key);
  if (!bucket || now - bucket.start >= RATE_WINDOW_MS) bucket = { start: now, count: 0 };
  bucket.count += 1;
  requestBuckets.set(key, bucket);
  if (requestBuckets.size > 2000) {
    for (const [k, v] of requestBuckets) if (now - v.start >= RATE_WINDOW_MS) requestBuckets.delete(k);
  }
  return bucket.count > RATE_MAX;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders() });
    if (!["GET", "POST"].includes(request.method)) {
      return errorResponse("METHOD_NOT_ALLOWED", "Use GET or POST.", 405);
    }
    if (rateLimited(request)) {
      return errorResponse("RATE_LIMITED", "Too many requests. Please retry shortly.", 429);
    }

    const clientId = env.JAMENDO_CLIENT_ID;
    const jamendo = async (path, params = {}) => {
      if (!clientId) {
        const error = new Error("CONFIG_MISSING");
        error.code = "CONFIG_MISSING";
        throw error;
      }
      const target = new URL("https://api.jamendo.com/v3.0" + path);
      target.searchParams.set("client_id", clientId);
      target.searchParams.set("format", "json");
      target.searchParams.set("audioformat", "mp32");
      for (const [key, value] of Object.entries(params)) {
        if (value !== undefined && value !== null) target.searchParams.set(key, String(value));
      }
      let response;
      try {
        response = await fetch(target.toString(), {
          headers: { Accept: "application/json" },
          signal: AbortSignal.timeout(8000)
        });
      } catch (cause) {
        const error = new Error(cause?.name === "TimeoutError" || cause?.name === "AbortError" ? "PROVIDER_TIMEOUT" : "PROVIDER_ERROR");
        error.code = cause?.name === "TimeoutError" || cause?.name === "AbortError" ? "PROVIDER_TIMEOUT" : "PROVIDER_ERROR";
        throw error;
      }
      if (!response.ok) {
        const error = new Error("PROVIDER_ERROR");
        error.code = "PROVIDER_ERROR";
        throw error;
      }
      let payload;
      try { payload = await response.json(); } catch {
        const error = new Error("PROVIDER_ERROR");
        error.code = "PROVIDER_ERROR";
        throw error;
      }
      const providerStatus = String(payload?.headers?.status || "").toLowerCase();
      if (providerStatus && providerStatus !== "success") {
        const error = new Error("PROVIDER_ERROR");
        error.code = "PROVIDER_ERROR";
        throw error;
      }
      if (!Array.isArray(payload?.results)) {
        const error = new Error("PROVIDER_ERROR");
        error.code = "PROVIDER_ERROR";
        throw error;
      }
      return payload;
    };

    const parseBody = async () => {
      const contentLength = Number(request.headers.get("Content-Length") || 0);
      if (contentLength > 8192) throw Object.assign(new Error("VALIDATION_ERROR"), { code: "VALIDATION_ERROR" });
      try {
        const body = await request.json();
        if (!body || typeof body !== "object" || Array.isArray(body)) throw new Error();
        return body;
      } catch {
        throw Object.assign(new Error("VALIDATION_ERROR"), { code: "VALIDATION_ERROR" });
      }
    };

    const runSearch = async (query, page, limit) => {
      if (!query || !query.trim()) throw Object.assign(new Error("VALIDATION_ERROR"), { code: "VALIDATION_ERROR" });
      const q = query.trim();
      if (q.length > 200) throw Object.assign(new Error("VALIDATION_ERROR"), { code: "VALIDATION_ERROR" });
      const p = Number(page ?? 1);
      const l = Number(limit ?? 20);
      if (!Number.isInteger(p) || p < 1 || p > 10000 || !Number.isInteger(l) || l < 1 || l > 50) {
        throw Object.assign(new Error("VALIDATION_ERROR"), { code: "VALIDATION_ERROR" });
      }
      const data = await jamendo("/tracks/", {
        search: q, limit: l, offset: (p - 1) * l,
        include: "licenses musicinfo", order: "relevance"
      });
      const results = data.results.map(mapTrack).filter(track => track.id && track.streaming_url);
      return { results, count: results.length, page: p, limit: l, query: q, source: "jamendo" };
    };

    try {
      if (url.pathname === "/" && request.method === "GET") {
        return json({
          status: "ok", service: "SokoVibe Music Backend", version: "2.1.0",
          endpoints: ["/api/health", "/search?q=afrobeat", "POST /api/search", "/play/{trackId}", "POST /api/recommend", "POST /api/lyrics"]
        });
      }

      if (url.pathname === "/api/health" && request.method === "GET") {
        const aiConfigured = Boolean(env.AI);
        if (!clientId) {
          return json({
            status: "degraded", service: "SokoVibe Music Backend", version: "2.1.0",
            timestamp: new Date().toISOString(),
            jamendo: { configured: false, connected: false },
            ai: { configured: aiConfigured, model: aiConfigured ? "@cf/meta/llama-3.1-8b-instruct" : null }
          }, 503);
        }
        try {
          const test = await jamendo("/tracks/", { limit: 1, order: "popularity_total" });
          const connected = test.results.length > 0;
          return json({
            status: connected ? "healthy" : "degraded",
            service: "SokoVibe Music Backend", version: "2.1.0",
            timestamp: new Date().toISOString(),
            jamendo: { configured: true, connected, tracksReturned: test.results.length },
            ai: { configured: aiConfigured, model: aiConfigured ? "@cf/meta/llama-3.1-8b-instruct" : null }
          }, connected ? 200 : 503);
        } catch (error) {
          return json({
            status: "degraded", service: "SokoVibe Music Backend", version: "2.1.0",
            timestamp: new Date().toISOString(),
            jamendo: { configured: true, connected: false, error: error.code || "PROVIDER_ERROR" },
            ai: { configured: aiConfigured, model: aiConfigured ? "@cf/meta/llama-3.1-8b-instruct" : null }
          }, error.code === "CONFIG_MISSING" ? 503 : 502);
        }
      }

      if (url.pathname === "/search" && request.method === "GET") {
        const query = url.searchParams.get("q") || "";
        if (!query.trim()) return errorResponse("VALIDATION_ERROR", "Query parameter q is required.", 400);
        return json(await runSearch(query, url.searchParams.get("page"), url.searchParams.get("limit")));
      }

      if (url.pathname === "/api/search" && request.method === "POST") {
        const body = await parseBody();
        const result = await runSearch(String(body.query || ""), body.page, body.limit);
        return json(result);
      }

      const playMatch = url.pathname.match(/^\/play\/(\d+)$/);
      if (playMatch && request.method === "GET") {
        const data = await jamendo("/tracks/", { id: playMatch[1], limit: 1, include: "licenses musicinfo" });
        const track = data.results[0];
        if (!track) return errorResponse("NOT_FOUND", "Track was not found.", 404);
        const mapped = mapTrack(track);
        if (!mapped.streaming_url) return errorResponse("NO_STREAM", "No playable audio is available for this track.", 404);
        return json({ track: mapped, ...mapped });
      }

      if (url.pathname === "/api/recommend" && request.method === "POST") {
        const body = await parseBody();
        const mood = String(body.mood || "").trim().slice(0, 80);
        const genre = String(body.genre || "afrobeat").trim().slice(0, 80);
        const language = String(body.language || "").trim().slice(0, 80);
        const query = [genre, mood, language].filter(Boolean).join(" ");
        const limit = Number(body.limit ?? 10);
        if (!Number.isInteger(limit) || limit < 1 || limit > 50) return errorResponse("VALIDATION_ERROR", "limit must be between 1 and 50.", 400);
        const data = await jamendo("/tracks/", { search: query, limit, order: "popularity_total", include: "licenses musicinfo" });
        const recommendations = data.results.map(mapTrack).filter(track => track.id && track.streaming_url);
        return json({ recommendations, count: recommendations.length, source: "jamendo" });
      }

      if (url.pathname === "/api/lyrics" && request.method === "POST") {
        if (!env.AI) return errorResponse("CONFIG_MISSING", "Lyrics generation is not configured.", 503);
        const body = await parseBody();
        const theme = String(body.theme || "love").trim();
        const genre = String(body.genre || "afrobeat").trim();
        const language = String(body.language || "Swahili").trim();
        if (!theme || !genre || !language || theme.length > 200 || genre.length > 100 || language.length > 80) {
          return errorResponse("VALIDATION_ERROR", "Theme, genre or language is invalid or too long.", 400);
        }
        let output;
        try {
          output = await env.AI.run("@cf/meta/llama-3.1-8b-instruct", {
            messages: [
              { role: "system", content: "Write original song lyrics with verse, chorus and bridge. Do not imitate a named artist or reproduce existing song lyrics." },
              { role: "user", content: "Write original lyrics about " + theme + " in " + genre + " style, in " + language + "." }
            ]
          });
        } catch {
          return errorResponse("AI_ERROR", "Lyrics generation failed. Please retry.", 502);
        }
        const lyrics = typeof output === "string" ? output : (output?.response || output?.result || "");
        if (!String(lyrics).trim()) return errorResponse("AI_ERROR", "Lyrics generation returned an empty result.", 502);
        return json({ lyrics: String(lyrics), ai_generated: true, theme, genre, language });
      }

      return errorResponse("NOT_FOUND", "Endpoint not found.", 404);
    } catch (error) {
      if (error?.code === "VALIDATION_ERROR") return errorResponse("VALIDATION_ERROR", "Request input is invalid. Check required fields and limits.", 400);
      if (error?.code === "CONFIG_MISSING") return errorResponse("CONFIG_MISSING", "Music provider is not configured.", 503);
      if (error?.code === "PROVIDER_TIMEOUT") return errorResponse("PROVIDER_TIMEOUT", "Music provider timed out. Please retry.", 504);
      if (error?.code === "PROVIDER_ERROR") return errorResponse("PROVIDER_ERROR", "Music provider request failed.", 502);
      return errorResponse("INTERNAL_ERROR", "Unexpected backend error.", 500);
    }
  }
};
