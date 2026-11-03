import asyncio
import json
import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Any
from urllib.parse import urlparse

import yt_dlp
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from starlette.concurrency import run_in_threadpool

try:
    import redis.asyncio as redis
except ImportError:
    redis = None

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
log = logging.getLogger("sokovibe-music-api")
TTL = max(1, int(os.getenv("CACHE_TTL_SECONDS", "900")))
TIMEOUT = max(3, int(os.getenv("YTDLP_SOCKET_TIMEOUT", "12")))
MAX_LOOKUPS = max(1, int(os.getenv("MAX_CONCURRENT_LOOKUPS", "3")))
REDIS_URL = os.getenv("REDIS_URL", "").strip()
# Channel IDs must be explicitly approved after streaming rights are verified.
ALLOWED_CHANNEL_IDS = {x.strip() for x in os.getenv("ALLOWED_CHANNEL_IDS", "").split(",") if x.strip()}
memory: dict[str, tuple[float, dict[str, Any]]] = {}
cache_lock = asyncio.Lock()
lookup_slots = asyncio.Semaphore(MAX_LOOKUPS)
redis_client = None


@asynccontextmanager
async def lifespan(_: FastAPI):
    global redis_client
    if REDIS_URL and redis is not None:
        try:
            redis_client = redis.from_url(REDIS_URL, decode_responses=True)
            await redis_client.ping()
            log.info("Redis cache connected")
        except Exception:
            log.exception("Redis unavailable; falling back to memory cache")
            redis_client = None
    yield
    if redis_client is not None:
        await redis_client.aclose()


app = FastAPI(
    title="SokoVibe Music API",
    version="1.0.0",
    description="Search music metadata; direct stream URLs are exposed only for rights-approved channels.",
    lifespan=lifespan,
)
origins = [x.strip() for x in os.getenv("CORS_ORIGINS", "*").split(",") if x.strip()]
app.add_middleware(CORSMiddleware, allow_origins=origins, allow_credentials=False,
                   allow_methods=["GET", "OPTIONS"], allow_headers=["*"])


def cache_key(query: str) -> str:
    return "sokovibe:stream:v1:" + query.casefold().strip()


async def cache_get(key: str):
    if redis_client is not None:
        try:
            raw = await redis_client.get(key)
            if raw:
                return json.loads(raw)
        except Exception:
            log.exception("Redis read failed")
    async with cache_lock:
        entry = memory.get(key)
        if not entry:
            return None
        expires, value = entry
        if expires <= time.monotonic():
            memory.pop(key, None)
            return None
        return value.copy()


async def cache_set(key: str, value: dict):
    if redis_client is not None:
        try:
            await redis_client.set(key, json.dumps(value), ex=TTL)
            return
        except Exception:
            log.exception("Redis write failed")
    async with cache_lock:
        now = time.monotonic()
        for old_key, (expires, _) in list(memory.items()):
            if expires <= now:
                memory.pop(old_key, None)
        if len(memory) >= 500:
            memory.pop(next(iter(memory)), None)
        memory[key] = (now + TTL, value.copy())


def lookup_first(query: str) -> dict[str, Any]:
    options = {
        "format": "bestaudio/best",
        "noplaylist": True,
        "extract_flat": False,
        "skip_download": True,
        "quiet": True,
        "no_warnings": True,
        "socket_timeout": TIMEOUT,
        "retries": 1,
        "extractor_retries": 1,
        "playlist_items": "1",
    }
    with yt_dlp.YoutubeDL(options) as ydl:
        info = ydl.extract_info(f"ytsearch1:{query}", download=False)
    entries = (info or {}).get("entries") or []
    item = next((x for x in entries if x), None)
    if item is None:
        raise LookupError("No matching result was found")

    channel_id = str(item.get("channel_id") or item.get("uploader_id") or "")
    page_url = item.get("webpage_url") or item.get("original_url") or ""
    host = (urlparse(page_url).hostname or "").lower() or None
    authorized = bool(channel_id and channel_id in ALLOWED_CHANNEL_IDS)
    stream_url = item.get("url") if authorized else None
    return {
        "title": item.get("title") or "Unknown title",
        "artist": item.get("artist") or item.get("creator") or item.get("uploader") or "Unknown artist",
        "uploader": item.get("uploader") or item.get("channel") or "Unknown uploader",
        "duration": int(item["duration"]) if item.get("duration") is not None else None,
        "thumbnail": item.get("thumbnail"),
        "audio_url": stream_url,
        "streaming_eligible": bool(authorized and stream_url),
        "source_url": page_url or None,
        "source_domain": host,
        "license_note": (
            "Approved channel; confirm your licence covers streaming, territories and use in your app."
            if authorized else
            "Direct stream URL withheld: verify rights, then add this exact channel ID to ALLOWED_CHANNEL_IDS."
        ),
    }


@app.get("/health")
async def health():
    return {"status": "ok", "service": "sokovibe-music-api",
            "cache": "redis" if redis_client is not None else "memory"}


@app.get("/api/stream")
async def stream(query: str = Query(..., min_length=2, max_length=180)):
    query = " ".join(query.split())
    if len(query) < 2:
        raise HTTPException(status_code=422, detail="query must contain at least 2 characters")
    key = cache_key(query)
    cached = await cache_get(key)
    if cached is not None:
        cached["cached"] = True
        return cached
    try:
        async with lookup_slots:
            result = await asyncio.wait_for(run_in_threadpool(lookup_first, query), timeout=TIMEOUT + 8)
        result.update({"query": query, "cached": False})
        await cache_set(key, result)
        return result
    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="Music search timed out; please retry.")
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except yt_dlp.utils.DownloadError:
        log.exception("yt-dlp search failed")
        raise HTTPException(status_code=502, detail="Music source could not be reached or searched.")
    except Exception:
        log.exception("Unexpected lookup error")
        raise HTTPException(status_code=500, detail="Unexpected server error while searching for music.")
