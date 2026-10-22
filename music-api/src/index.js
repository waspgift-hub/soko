/**
 * SokoVibe Music Backend — Cloudflare Worker
 * Jamendo-powered music search, playback, recommendations, and AI-generated lyrics.
 */

const JAMENDO_API = "https://api.jamendo.com/v3.0";
const JAMENDO_TRACKS = JAMENDO_API + "/tracks/";
const JAMENDO_DEFAULT_LIMIT = 20;
const JAMENDO_MAX_LIMIT = 50;
const PROVIDER_TIMEOUT_MS = 8000;
const AI_MODEL = "@cf/meta/llama-3.1-8b-instruct";
const MAX_LYRICS_INPUT = 500;
const MAX_SEARCH_QUERY = 200;

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

function jsonResponse(data, status) {
  return new Response(JSON.stringify(data), {
    status: status || 200,
    headers: Object.assign({}, corsHeaders(), { "Content-Type": "application/json" }),
  });
}

function errorResponse(message, status, category) {
  var body = { error: message };
  if (category) body.error_category = category;
  return jsonResponse(body, status);
}

async function jamendoRequest(env, params) {
  var clientId = env.JAMENDO_CLIENT_ID;
  if (!clientId) {
    var err = new Error("Jamendo client ID is not configured");
    err.code = "CONFIG_MISSING";
    throw err;
  }

  var url = new URL(JAMENDO_TRACKS);
  url.searchParams.set("client_id", clientId);
  url.searchParams.set("format", "json");
  for (var key in params) {
    if (params[key] !== undefined && params[key] !== null && params[key] !== "") {
      url.searchParams.set(key, String(params[key]));
    }
  }

  var controller = new AbortController();
  var timeout = setTimeout(function() { controller.abort(); }, PROVIDER_TIMEOUT_MS);

  try {
    var resp = await fetch(url.toString(), {
      signal: controller.signal,
      headers: { "Accept": "application/json" },
    });

    if (!resp.ok) {
      var err = new Error("Jamendo returned HTTP " + resp.status);
      err.code = "PROVIDER_HTTP_ERROR";
      err.httpStatus = resp.status;
      throw err;
    }

    var body = await resp.json();

    if (body.headers) {
      var status = body.headers.status;
      var errMsg = body.headers.error_message;
      if (status === 0 || (errMsg && errMsg.length > 0 && status !== 1)) {
        var err = new Error(errMsg || "Jamendo API returned an error");
        err.code = "PROVIDER_ERROR";
        err.providerStatus = status;
        throw err;
      }
    }

    return body;
  } catch (e) {
    if (e.name === "AbortError") {
      var err = new Error("Jamendo request timed out");
      err.code = "PROVIDER_TIMEOUT";
      throw err;
    }
    throw e;
  } finally {
    clearTimeout(timeout);
  }
}

function mapTrack(track) {
  if (!track || !track.id) return null;
  return {
    id: String(track.id),
    title: track.name || "Untitled",
    artist: track.artist_name || "Unknown Artist",
    album: track.album_name || null,
    image: track.image || track.album_image || null,
    streaming_url: track.audio || null,
    duration: track.duration || null,
    license: track.license_ccurl || null,
    audiodownload: track.audiodownload || null,
    audiodownload_allowed: track.audiodownload_allowed === true || track.audiodownload_allowed === 1,
    source: "jamendo",
    share_url: track.shareurl || track.shorturl || null,
  };
}

async function checkJamendoConnectivity(env) {
  try {
    var body = await jamendoRequest(env, { limit: 1, order: "popularity_total" });
    var tracks = body.results || [];
    return { connected: true, sample_count: tracks.length };
  } catch (e) {
    return { connected: false, error_category: e.code || "UNKNOWN", message: e.message };
  }
}

function sanitizeString(str, maxLen) {
  if (typeof str !== "string") return "";
  return str.trim().substring(0, maxLen);
}

function isValidTrackId(id) {
  if (!id) return false;
  var s = String(id).trim();
  return /^\d+$/.test(s) && parseInt(s, 10) > 0;
}

async function handleHealth(env) {
  var jamendoConfigured = !!env.JAMENDO_CLIENT_ID;
  var aiConfigured = !!env.AI;
  var jamendoCheck = await checkJamendoConnectivity(env);

  return jsonResponse({
    status: jamendoCheck.connected ? "healthy" : "degraded",
    timestamp: new Date().toISOString(),
    service: "SokoVibe Music Backend",
    version: "2.0.0",
    jamendo: {
      configured: jamendoConfigured,
      connected: jamendoCheck.connected,
      ...(jamendoCheck.connected
        ? { sample_count: jamendoCheck.sample_count }
        : { error_category: jamendoCheck.error_category, message: jamendoCheck.message }),
    },
    ai: {
      configured: aiConfigured,
      model: aiConfigured ? AI_MODEL : null,
    },
  });
}

async function handleSearch(env, query, page, limit) {
  query = sanitizeString(query, MAX_SEARCH_QUERY);
  if (!query) {
    return errorResponse("Search query is required", 400, "VALIDATION_ERROR");
  }

  limit = Math.min(Math.max(parseInt(limit, 10) || JAMENDO_DEFAULT_LIMIT, 1), JAMENDO_MAX_LIMIT);
  page = Math.max(parseInt(page, 10) || 1, 1);
  var offset = (page - 1) * limit;

  try {
    var body = await jamendoRequest(env, {
      search: query,
      limit: limit,
      offset: offset,
      audioformat: "mp32",
      include: "licenses musicinfo",
      order: "relevance",
    });

    var tracks = (body.results || []).map(mapTrack).filter(Boolean);

    return jsonResponse({
      results: tracks,
      count: tracks.length,
      page: page,
      limit: limit,
      query: query,
    });
  } catch (e) {
    var status = e.code === "CONFIG_MISSING" ? 503
      : e.code === "PROVIDER_TIMEOUT" ? 504
      : e.code === "PROVIDER_HTTP_ERROR" ? 502
      : 502;
    return errorResponse(
      e.code === "CONFIG_MISSING" ? "Music provider is not configured" : "Failed to search tracks",
      status,
      e.code || "PROVIDER_ERROR"
    );
  }
}

async function handlePlay(env, trackId) {
  if (!isValidTrackId(trackId)) {
    return errorResponse("Invalid track ID", 400, "VALIDATION_ERROR");
  }

  try {
    var body = await jamendoRequest(env, {
      id: trackId,
      limit: 1,
      audioformat: "mp32",
      include: "licenses musicinfo",
    });

    var tracks = (body.results || []).map(mapTrack).filter(Boolean);

    if (tracks.length === 0) {
      return errorResponse("Track not found", 404, "NOT_FOUND");
    }

    var track = tracks[0];

    if (!track.streaming_url || !track.streaming_url.startsWith("https://")) {
      return errorResponse("Track has no usable audio stream", 404, "NO_STREAM");
    }

    return jsonResponse({ track: track });
  } catch (e) {
    var status = e.code === "CONFIG_MISSING" ? 503
      : e.code === "PROVIDER_TIMEOUT" ? 504
      : 502;
    return errorResponse(
      e.code === "CONFIG_MISSING" ? "Music provider is not configured" : "Failed to retrieve track",
      status,
      e.code || "PROVIDER_ERROR"
    );
  }
}

async function handleRecommend(env, body) {
  var mood = sanitizeString(body && body.mood, 50);
  var genre = sanitizeString(body && body.genre, 50);
  var language = sanitizeString(body && body.language, 30);
  var limit = Math.min(Math.max(parseInt(body && body.limit, 10) || 10, 1), JAMENDO_MAX_LIMIT);

  var searchParts = [mood, genre].filter(Boolean);
  var searchQuery = searchParts.join(" ") || "popular";

  var params = {
    limit: limit,
    audioformat: "mp32",
    include: "licenses musicinfo",
    order: "popularity_total",
  };

  if (searchParts.length > 0) {
    params.search = searchQuery;
  }

  if (language) {
    params.search = (searchQuery + " " + language).trim();
  }

  try {
    var jamendoBody = await jamendoRequest(env, params);
    var tracks = (jamendoBody.results || []).map(mapTrack).filter(Boolean);

    if (tracks.length === 0) {
      if (language) {
        params.search = searchQuery;
        var fallbackBody = await jamendoRequest(env, params);
        var fallbackTracks = (fallbackBody.results || []).map(mapTrack).filter(Boolean);
        if (fallbackTracks.length > 0) {
          return jsonResponse({
            recommendations: fallbackTracks,
            count: fallbackTracks.length,
            source: "jamendo",
            note: "Results matched mood/genre; language preference could not be applied.",
          });
        }
      }
      return jsonResponse({
        recommendations: [],
        count: 0,
        source: "jamendo",
        note: "No tracks found matching the given preferences.",
      });
    }

    return jsonResponse({
      recommendations: tracks,
      count: tracks.length,
      source: "jamendo",
    });
  } catch (e) {
    var status = e.code === "CONFIG_MISSING" ? 503
      : e.code === "PROVIDER_TIMEOUT" ? 504
      : 502;
    return errorResponse(
      e.code === "CONFIG_MISSING" ? "Music provider is not configured" : "Failed to get recommendations",
      status,
      e.code || "PROVIDER_ERROR"
    );
  }
}

async function handleLyrics(env, body) {
  var theme = sanitizeString(body && body.theme, MAX_LYRICS_INPUT);
  var genre = sanitizeString(body && body.genre, 50);
  var language = sanitizeString(body && body.language, 30);

  if (!theme) {
    return errorResponse("Theme is required for lyrics generation", 400, "VALIDATION_ERROR");
  }

  if (!env.AI) {
    return errorResponse("AI service is not configured", 503, "AI_NOT_CONFIGURED");
  }

  var prompt = 'Write completely original song lyrics about "' + theme + '" in a ' + (genre || "afrobeat") + ' style. Write the lyrics in ' + (language || "Swahili") + '. Include verse, chorus, and bridge sections. These must be original lyrics, not copied from any existing song or artist. Do not imitate or reference any real artist or band.';

  try {
    var response = await env.AI.run(AI_MODEL, {
      messages: [
        {
          role: "system",
          content: "You are a creative songwriter for the Soko Vibe music platform. You write only original lyrics. Never copy or imitate existing songs or named artists. Always label your output as AI-generated.",
        },
        { role: "user", content: prompt },
      ],
    });

    var lyricsText = "";
    if (typeof response === "string") {
      lyricsText = response;
    } else if (response && response.response) {
      lyricsText = response.response;
    } else if (response && response.result && response.result.response) {
      lyricsText = response.result.response;
    } else {
      lyricsText = JSON.stringify(response);
    }

    return jsonResponse({
      lyrics: lyricsText,
      ai_generated: true,
      theme: theme,
      genre: genre || "afrobeat",
      language: language || "Swahili",
    });
  } catch (e) {
    return errorResponse("Failed to generate lyrics", 502, "AI_ERROR");
  }
}

export default {
  async fetch(request, env) {
    var url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders() });
    }

    if (url.pathname === "/") {
      return jsonResponse({
        status: "ok",
        service: "SokoVibe Music Backend",
        version: "2.0.0",
        endpoints: [
          "GET /api/health",
          "GET /search?q=...",
          "POST /api/search",
          "GET /play/:trackId",
          "POST /api/recommend",
          "POST /api/lyrics",
        ],
      });
    }

    if (url.pathname === "/api/health" && request.method === "GET") {
      return handleHealth(env);
    }

    if (url.pathname === "/search" && request.method === "GET") {
      var q = url.searchParams.get("q") || "";
      var page = url.searchParams.get("page") || "1";
      var limit = url.searchParams.get("limit") || JAMENDO_DEFAULT_LIMIT;
      return handleSearch(env, q, page, limit);
    }

    if (url.pathname === "/api/search" && request.method === "POST") {
      try {
        var body = await request.json();
        var query = (body && (body.query || body.q)) || "";
        var page = (body && body.page) || "1";
        var limit = (body && body.limit) || JAMENDO_DEFAULT_LIMIT;
        return handleSearch(env, query, page, limit);
      } catch {
        return errorResponse("Invalid JSON body", 400, "VALIDATION_ERROR");
      }
    }

    var playMatch = url.pathname.match(/^\/play\/(\d+)$/);
    if (playMatch && request.method === "GET") {
      return handlePlay(env, playMatch[1]);
    }

    if (url.pathname === "/api/recommend" && request.method === "POST") {
      try {
        var body = await request.json();
        return handleRecommend(env, body);
      } catch {
        return errorResponse("Invalid JSON body", 400, "VALIDATION_ERROR");
      }
    }

    if (url.pathname === "/api/lyrics" && request.method === "POST") {
      try {
        var body = await request.json();
        return handleLyrics(env, body);
      } catch {
        return errorResponse("Invalid JSON body", 400, "VALIDATION_ERROR");
      }
    }

    return errorResponse("Not found", 404, "NOT_FOUND");
  },
};