# SokoVibe Music Audio API

FastAPI service for resolving an authorized audio stream with `yt-dlp` without downloading the media file to disk.

## Endpoint

`GET /api/stream?query=Marioo%20Mi%20Amor`

Response fields:

- `title`
- `artist`
- `uploader`
- `duration`
- `thumbnail`
- `audio_url`
- `webpage_url`
- `source`
- `cached`

## Local

```bash
cd music_api
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Windows activation:

```powershell
.venv\Scripts\Activate.ps1
```

Open `/docs` for Swagger UI and `/health` for the health check.

## Redis

Set `REDIS_URL` to a Redis/Valkey connection URL. Without it, the API safely falls back to an in-process cache for development. For multiple production instances, use Redis/Valkey so all instances share the cache.

Optional environment variables:

```text
CACHE_TTL=300
YT_TIMEOUT=20
CORS_ORIGINS=https://your-app.example
REDIS_URL=redis://...
```

## Docker

```bash
docker build -t sokovibe-music-api ./music_api
docker run --rm -p 8000:8000 sokovibe-music-api
```

## Production notes

The returned `audio_url` is a provider-generated direct stream URL and may expire. Do not persist it as a permanent media URL; cache the resolved metadata only for a short TTL and resolve it again when needed.

Use this service only for audio you are authorized to access and stream. `yt-dlp` availability can change when upstream providers change their delivery or anti-bot systems.
