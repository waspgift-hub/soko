export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const headers = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Accept",
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store"
    };
    const json = (data, status = 200) =>
      new Response(JSON.stringify(data), { status, headers });
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });

    const clientId = env.JAMENDO_CLIENT_ID;
    const jamendo = async (path, params = {}) => {
      if (!clientId) throw new Error("Jamendo is not configured. Add the JAMENDO_CLIENT_ID Worker secret.");
      const target = new URL("https://api.jamendo.com/v3.0" + path);
      target.searchParams.set("client_id", clientId);
      target.searchParams.set("format", "json");
      target.searchParams.set("limit", String(params.limit || 25));
      target.searchParams.set("audioformat", "mp32");
      for (const [key, value] of Object.entries(params)) {
        if (value != null && key !== "limit") target.searchParams.set(key, String(value));
      }
      const response = await fetch(target, {
        headers: { Accept: "application/json" },
        signal: AbortSignal.timeout(10000)
      });
      if (!response.ok) throw new Error("Jamendo returned HTTP " + response.status);
      const payload = await response.json();
      if (payload.headers?.status === "failed") {
        throw new Error(payload.headers.error_message || "Jamendo API request failed");
      }
      return payload;
    };

    const mapTrack = track => ({
      id: String(track.id),
      title: track.name || "Unknown title",
      artist: track.artist_name || "Unknown artist",
      image: track.album_image || track.image || "",
      streaming_url: track.audio || "",
      duration: Number(track.duration || 0),
      license: track.license_ccurl || track.license || "",
      source: "Jamendo",
      album: track.album_name || "",
      artist_id: String(track.artist_id || ""),
      share_url: track.shareurl || ""
    });

    const fail = (error, status = 502) => {
      const message = error?.message || "Unexpected music service error";
      return json({ error: message, message }, status);
    };

    try {
      if (url.pathname === "/" || url.pathname === "/api/health") {
        let jamendoStatus = { configured: Boolean(clientId), status: "not_configured" };
        if (clientId) {
          try {
            const test = await jamendo("/tracks/", { limit: 1, order: "popularity_total" });
            jamendoStatus = {
              configured: true,
              status: "connected",
              tracksReturned: Array.isArray(test.results) ? test.results.length : 0
            };
          } catch (error) {
            jamendoStatus = { configured: true, status: "error", message: error.message };
          }
        }
        const healthy = jamendoStatus.status === "connected";
        return json({
          status: healthy ? "healthy" : "degraded",
          service: "Soko Vibe Music Backend",
          provider: "Jamendo",
          jamendo: jamendoStatus,
          timestamp: new Date().toISOString(),
          endpoints: ["/search?q=afrobeat", "/play/{trackId}", "/api/health", "/api/search", "/api/recommend", "/api/lyrics"]
        }, healthy || !clientId ? 200 : 503);
      }

      if (url.pathname === "/search" && request.method === "GET") {
        const query = (url.searchParams.get("q") || "").trim();
        if (!query) return json({ results: [] });
        if (query.length > 160) return json({ error: "Search query is too long." }, 400);
        const data = await jamendo("/tracks/", {
          search: query, limit: 25, include: "musicinfo", order: "relevance"
        });
        const results = (data.results || []).map(mapTrack).filter(track => track.id && track.streaming_url);
        return json({ results, source: "Jamendo", count: results.length });
      }

      const play = url.pathname.match(/^\/play\/([A-Za-z0-9_-]+)$/);
      if (play && request.method === "GET") {
        const data = await jamendo("/tracks/", { id: play[1], limit: 1 });
        const track = (data.results || [])[0];
        if (!track?.audio) return json({ error: "Track not found or no playable stream is available." }, 404);
        return json({
          id: String(track.id),
          streaming_url: track.audio,
          title: track.name || "",
          artist: track.artist_name || "",
          license: track.license_ccurl || track.license || "",
          source: "Jamendo"
        });
      }

      if (url.pathname === "/api/search" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const query = String(body.query || "").trim();
        if (!query) return json({ results: [] });
        const data = await jamendo("/tracks/", { search: query, limit: 25, include: "musicinfo", order: "relevance" });
        return json({ results: (data.results || []).map(mapTrack).filter(track => track.id && track.streaming_url), source: "Jamendo" });
      }

      if (url.pathname === "/api/recommend" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const query = [body.genre || "afrobeat", body.mood || "", body.language || ""].filter(Boolean).join(" ");
        const data = await jamendo("/tracks/", { search: query, limit: 10, order: "popularity_total" });
        return json({ recommendations: (data.results || []).map(mapTrack).filter(track => track.id && track.streaming_url), source: "Jamendo" });
      }

      if (url.pathname === "/api/lyrics" && request.method === "POST") {
        if (!env.AI) return json({ error: "Lyrics AI is not configured." }, 503);
        const body = await request.json().catch(() => ({}));
        const theme = String(body.theme || "love").slice(0, 200);
        const genre = String(body.genre || "afrobeat").slice(0, 100);
        const language = String(body.language || "Swahili").slice(0, 80);
        const lyrics = await env.AI.run("@cf/meta/llama-3.1-8b-instruct", {
          messages: [
            { role: "system", content: "Write original song lyrics with verse, chorus and bridge. Do not imitate a named artist." },
            { role: "user", content: "Write original lyrics about " + theme + " in " + genre + " style, in " + language + "." }
          ]
        });
        return json({ lyrics });
      }

      return json({ error: "Not found" }, 404);
    } catch (error) {
      return fail(error, error?.message?.includes("not configured") ? 503 : 502);
    }
  }
};
