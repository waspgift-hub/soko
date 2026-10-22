const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "public, max-age=60",
};

function json(data, status = 200, origin = "*") {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...JSON_HEADERS,
      "access-control-allow-origin": origin,
      "access-control-allow-methods": "GET, OPTIONS",
      "access-control-allow-headers": "Content-Type",
    },
  });
}

function corsOrigin(request) {
  // Public read-only music search API. Restrict this to your app/site origins if desired.
  return request.headers.get("Origin") || "*";
}

async function jamendo(path, params, env) {
  if (!env.JAMENDO_CLIENT_ID) {
    throw new Error("JAMENDO_CLIENT_ID is not configured in Worker secrets.");
  }
  const url = new URL(`https://api.jamendo.com/v3.0/${path}`);
  url.search = new URLSearchParams({
    client_id: env.JAMENDO_CLIENT_ID,
    format: "json",
    ...params,
  }).toString();

  const response = await fetch(url.toString(), {
    headers: { "accept": "application/json", "user-agent": "SokoVibeMusic/0.1.0" },
    signal: AbortSignal.timeout(9000),
  });
  if (!response.ok) throw new Error(`Jamendo upstream returned HTTP ${response.status}`);
  const payload = await response.json();
  if (payload.headers?.status !== "success" || !Array.isArray(payload.results)) {
    throw new Error("Jamendo returned an unexpected response.");
  }
  return payload.results;
}

function mapTrack(track) {
  return {
    id: String(track.id),
    title: track.name || "Unknown title",
    artist: track.artist_name || "Unknown artist",
    image: track.album_image || track.image || "",
    streaming_url: track.audio || "",
    duration: Number(track.duration || 0),
    license: track.license_ccurl || "",
    source: "Jamendo",
  };
}

export default {
  async fetch(request, env) {
    const origin = corsOrigin(request);
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "access-control-allow-origin": origin,
          "access-control-allow-methods": "GET, OPTIONS",
          "access-control-allow-headers": "Content-Type",
          "access-control-max-age": "86400",
        },
      });
    }
    if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405, origin);

    if (url.pathname === "/" || url.pathname === "/health") {
      return json({
        service: "SokoVibe Music API",
        status: "ok",
        provider: "Jamendo",
        endpoints: ["/health", "/search?q=keyword", "/play/:id"],
      }, 200, origin);
    }

    try {
      if (url.pathname === "/search") {
        const query = (url.searchParams.get("q") || "").trim();
        if (!query) return json({ results: [], message: "Provide a search query using ?q=..." }, 200, origin);
        if (query.length > 120) return json({ error: "query_too_long" }, 400, origin);
        const results = await jamendo("tracks", {
          namesearch: query,
          limit: "25",
          audioformat: "mp32",
          include: "musicinfo",
          order: "popularity_total",
        }, env);
        return json({ results: results.map(mapTrack), count: results.length, source: "Jamendo" }, 200, origin);
      }

      const playMatch = url.pathname.match(/^\/play\/([A-Za-z0-9_-]+)$/);
      if (playMatch) {
        const id = playMatch[1];
        const results = await jamendo("tracks", {
          id,
          limit: "1",
          audioformat: "mp32",
        }, env);
        if (!results.length || !results[0].audio) {
          return json({ error: "track_not_playable", message: "No playable stream was returned." }, 404, origin);
        }
        return json({
          id: String(results[0].id),
          streaming_url: results[0].audio,
          audiodownload: results[0].audiodownload || "",
          audiodownload_allowed: results[0].audiodownload_allowed === true || results[0].audiodownload_allowed === 1,
          source: "Jamendo",
          license: results[0].license_ccurl || "",
        }, 200, origin);
      }

      return json({ error: "not_found", endpoints: ["/health", "/search?q=keyword", "/play/:id"] }, 404, origin);
    } catch (error) {
      // Do not leak secrets or upstream response bodies.
      const message = error?.message?.includes("not configured")
        ? "Music provider is not configured. Set the JAMENDO_CLIENT_ID Worker secret."
        : "The music provider is temporarily unavailable. Please retry.";
      return json({ error: "upstream_error", message }, 502, origin);
    }
  },
};
