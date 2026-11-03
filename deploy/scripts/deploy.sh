#!/bin/bash
# Soko Vibe - Deployment Script
# Usage: ./deploy.sh [commit_hash]

set -euo pipefail

APP_DIR="/opt/sokovibe"
COMMIT="${1:-HEAD}"
HEALTH_URL="http://localhost:3000/health"
HEALTH_TIMEOUT=30
ROLLBACK_VERSION=""

echo "=========================================="
echo "  Soko Vibe Deployment"
echo "  Commit: ${COMMIT}"
echo "  Time: $(date)"
echo "=========================================="

cd "${APP_DIR}"

# Save current version for rollback
if [ -f .current_version ]; then
  ROLLBACK_VERSION=$(cat .current_version)
  echo "[DEPLOY] Rollback version saved: ${ROLLBACK_VERSION}"
fi

# 1. Pull latest code
echo "[DEPLOY] Pulling code..."
git fetch origin
git checkout "${COMMIT}"

# 2. Install dependencies
echo "[DEPLOY] Installing dependencies..."
cd soko_langu/server
npm ci --omit=dev

# 3. Run database migrations
echo "[DEPLOY] Running migrations..."
if [ -f "prisma/schema.prisma" ]; then
  npx prisma migrate deploy
fi

# 4. Build and restart services
echo "[DEPLOY] Restarting services..."
cd "${APP_DIR}"
docker compose down --timeout 30
docker compose up -d --build

# 5. Wait for health check
echo "[DEPLOY] Waiting for health check..."
ATTEMPTS=0
MAX_ATTEMPTS=30

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
  if curl -sf "${HEALTH_URL}" > /dev/null 2>&1; then
    echo "[DEPLOY] Health check passed!"
    echo "${COMMIT}" > .current_version
    echo "[DEPLOY] Deployment complete!"
    exit 0
  fi
  
  ATTEMPTS=$((ATTEMPTS + 1))
  echo "[DEPLOY] Attempt ${ATTEMPTS}/${MAX_ATTEMPTS}..."
  sleep 2
done

# 6. Health check failed - rollback
echo "[DEPLOY] ERROR: Health check failed after ${MAX_ATTEMPTS} attempts!"

if [ -n "${ROLLBACK_VERSION}" ]; then
  echo "[DEPLOY] Rolling back to ${ROLLBACK_VERSION}..."
  git checkout "${ROLLBACK_VERSION}"
  docker compose down --timeout 30
  docker compose up -d --build
  
  # Verify rollback
  sleep 5
  if curl -sf "${HEALTH_URL}" > /dev/null 2>&1; then
    echo "[DEPLOY] Rollback successful!"
    exit 1
  else
    echo "[DEPLOY] CRITICAL: Rollback also failed!"
    exit 2
  fi
else
  echo "[DEPLOY] No rollback version available"
  exit 1
fi
