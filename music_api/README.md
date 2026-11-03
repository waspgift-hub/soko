# SokoVibe Music API — FastAPI + yt-dlp

Searches the first result using `ytsearch1:` and returns metadata. A direct audio URL is returned only for exact channel IDs in `ALLOWED_CHANNEL_IDS`, after you have verified that SokoVibe has streaming rights for that content. Search results on YouTube are not a music licence.

## Endpoint
`GET /api/stream?query=Marioo%20Mi%20Amor`

JSON fields: `title`, `artist`, `uploader`, `duration` (seconds), `thumbnail`, `audio_url`, `streaming_eligible`, `source_url`, `source_domain`, `license_note`, `query`, `cached`. For a channel not allowlisted, `audio_url` is `null`. Extracted URLs expire and must not be stored as permanent catalogue URLs.

## Local run
Python 3.11+ recommended (3.12 works):
```bash
cd music_api
python -m venv .venv
# Linux/macOS
source .venv/bin/activate
# Windows PowerShell: .venv\\Scripts\\Activate.ps1
pip install -r requirements.txt
uvicorn main:app --reload --host 127.0.0.1 --port 8000
```
Open `http://127.0.0.1:8000/docs`, test `/health`, then `/api/stream?query=Harmonize%20Single%20Again`.

## Cache and configuration
Redis is optional. Set `REDIS_URL=redis://localhost:6379/0` to use Redis; otherwise a bounded in-memory cache is used. Defaults: `CACHE_TTL_SECONDS=900`, `YTDLP_SOCKET_TIMEOUT=12`, `MAX_CONCURRENT_LOOKUPS=3`. Set `ALLOWED_CHANNEL_IDS` to comma-separated verified channel IDs; it is empty by default. Set `CORS_ORIGINS` to your production app/backend origins.

## Render
Create a **new Web Service** from `waspgift-hub/soko` (do not replace the existing Node service):
- Root Directory: `music_api`
- Runtime: Python 3
- Build Command: `pip install -r requirements.txt`
- Start Command: `uvicorn main:app --host 0.0.0.0 --port $PORT`
- Health Check Path: `/health`

Add environment variables as needed: `ALLOWED_CHANNEL_IDS`, `REDIS_URL`, `CACHE_TTL_SECONDS`, `YTDLP_SOCKET_TIMEOUT`, `MAX_CONCURRENT_LOOKUPS`, `CORS_ORIGINS`.

## Ubuntu VPS
```bash
sudo apt update && sudo apt install -y python3 python3-venv python3-pip git
sudo git clone https://github.com/waspgift-hub/soko.git /opt/soko
cd /opt/soko/music_api
sudo python3 -m venv .venv
sudo .venv/bin/pip install -r requirements.txt
```
Create `/etc/sokovibe-music-api.env` (chmod 600) for environment variables. Create `/etc/systemd/system/sokovibe-music-api.service`:
```ini
[Unit]
Description=SokoVibe Music FastAPI
After=network-online.target
Wants=network-online.target

[Service]
User=www-data
WorkingDirectory=/opt/soko/music_api
EnvironmentFile=/etc/sokovibe-music-api.env
ExecStart=/opt/soko/music_api/.venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
```
Then run `sudo systemctl daemon-reload && sudo systemctl enable --now sokovibe-music-api` and test `curl http://127.0.0.1:8000/health`. Put Nginx/Caddy with HTTPS in front for public use. Ensure `/opt/soko` is readable by `www-data`; never commit secrets.

## Notes
The service does not download complete media files; yt-dlp is called with `download=False` and `skip_download=True`. Direct URLs can expire. This is a source adapter, not a substitute for licensed catalog APIs.
