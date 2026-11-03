import asyncio
import os
import time
from typing import Any

import yt_dlp
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

try:
    from redis.asyncio import Redis
except ImportError:  # pragma: no cover
    Redis = None

APP_NAME = "SokoVibe Music Audio API"
CACHE_TTL = int(os.getenv("CACHE_TTL", "300"))
YT_TIMEOUT = int(os.getenv("YT_TIMEOUT", "20"))
REDIS_URL = os.getenv("REDIS_URL", "").strip()

app = FastAPI(title=APP_NAME, version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[x.strip() for x in os.getenv("CORS_ORIGINS", "*").split(",") if x.strip()],
    allow_credentials=False,
    allow_methods=["GET"],
    allow_headers=["*"],
)

_memory_cache: dict[str, tuple[float, dict[str, Any]]] = {}
redis: Any = None


@app.on_event("startup")
async def startup() -> None:
    global redis
    if REDIS_URL and Redis is not None:
        redis = Redis.from_url(REDIS_URL, decode_responses=True)
        await redis.ping()


@app.on_event("shutdown")
async def shutdown() -> None:
    global redis
    if redis is not None:
        await redis.aclose()
        redis = None


def cache_key(query: str) -> str:
    return "sokovibe:music:stream:" + query.casefold().strip()


async def cache_get(key: str) -> dict[str, Any] | None:
    if redis is not None:
        raw = await redis.get(key)
        if raw:
            import json
            return json.loads(raw)
        return None

    item = _memory_cache.get(key)
    if not item:
        return None
    expires_at, value = item
    if expires_at <= time.time():
        _memory_cache.pop(key, None)
        return None
    return value


async def cache_set(key: str, value: dict[str, Any]) -> None:
    if redis is not None:
        import json
        await redis.set(key, json.dumps(value), ex=CACHE_TTL)
        return
    _memory_cache[key] = (time.time() + CACHE_TTL, value)


def extract_audio(query: str) -> dict[str, Any]:
    options = {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "extract_flat": False,
        "format": "bestaudio/best",
        "skip_download": True,
        "socket_timeout": YT_TIMEOUT,
        "retries": 2,
        "fragment_retries": 2,
        "geo_bypass": True,
    }

    with yt_dlp.YoutubeDL(options) as ydl:
        info = ydl.extract_info(f"ytsearch1:{query}", download=False)

    entries = info.get("entries") if info else None
    if not entries:
        raise LookupError("Wimbo haujapatikana.")

    item = entries[0]
    audio_url = item.get("url")

    if not audio_url:
        audio_formats = [
            f for f in item.get("formats", [])
            if f.get("url")
            and f.get("acodec") not in (None, "none")
            and f.get("vcodec") == "none"
        ]
        if audio_formats:
            audio_url = max(
                audio_formats,
                key=lambda f: (f.get("abr") or 0, f.get("tbr") or 0),
            ).get("url")

    if not audio_url:
        raise LookupError("Direct audio stream haikupatikana.")

    return {
        "title": item.get("title"),
        "artist": item.get("artist") or item.get("creator") or item.get("uploader"),
        "uploader": item.get("uploader"),
        "duration": item.get("duration"),
        "thumbnail": item.get("thumbnail"),
        "audio_url": audio_url,
        "webpage_url": item.get("webpage_url"),
        "source": "yt-dlp",
    }


@app.get("/health")
async def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "service": "sokovibe-music-api",
        "cache": "redis" if redis is not None else "memory",
    }


@app.get("/api/stream")
async def stream(
    query: str = Query(..., min_length=2, max_length=200),
) -> dict[str, Any]:
    query = query.strip()
    if not query:
        raise HTTPException(status_code=400, detail="Query haiwezi kuwa tupu.")

    key = cache_key(query)
    cached = await cache_get(key)
    if cached:
        return {**cached, "cached": True}

    try:
        result = await asyncio.to_thread(extract_audio, query)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Imeshindikana kupata audio stream.") from exc

    await cache_set(key, result)
    return {**result, "cached": False}
