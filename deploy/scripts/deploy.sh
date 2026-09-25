#!/bin/bash
# Soko Vibe - Production deployment
# Run from the VPS after the repository and .env.production are configured:
#   ./deploy/scripts/deploy.sh
#
# The script is intentionally non-destructive: it keeps Postgres/Redis volumes,
# runs Prisma migrations before the API is switched to the new image, and then
# verifies the local health endpoint.

set -euo pipefail

APP_DIR="${APP_DIR:-/opt/sokovibe}"
ENV_FILE="${ENV_FILE:-.env.production}"
HEALTH_URL="${HEALTH_URL:-http://localhost:3000/health}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-36}"
ROLLBACK_VERSION=""

cd "${APP_DIR}"

if [ ! -f "${ENV_FILE}" ]; then
  echo "[DEPLOY] Missing ${ENV_FILE}"
  exit 10
fi

if [ -f "${ENV_FILE}" ]; then
  set -a
  # shellcheck disable=SC1090
  . "${ENV_FILE}"
  set +a
fi

REQUIRED_ENV_VARS=(
  NODE_ENV PORT DATABASE_URL REDIS_URL
  FIREBASE_PROJECT_ID FIREBASE_CLIENT_EMAIL
  R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY
  CLICKPESA_API_KEY CLICKPESA_API_SECRET
  ADMIN_SECRET WEBHOOK_SECRET ENCRYPTION_KEY
  ALLOWED_ORIGINS
)

for key in "${REQUIRED_ENV_VARS[@]}"; do
  if [ -z "${!key:-}" ]; then
    echo "[DEPLOY] Missing required environment variable: ${key}"
    exit 11
  fi
done

if [ "${NODE_ENV}" != "production" ]; then
  echo "[DEPLOY] NODE_ENV must be production (got: ${NODE_ENV})"
  exit 12
fi

echo "=========================================="
echo "  Soko Vibe Production Deployment"
echo "  Commit: ${GIT_COMMIT:-current}"
echo "  Time:   $(date -Is)"
echo "=========================================="

if [ -f .current_version ]; then
  ROLLBACK_VERSION=$(cat .current_version || true)
fi

echo "[DEPLOY] Pulling latest main..."
git fetch --prune origin
git checkout main
git pull --ff-only origin main

CURRENT_VERSION=$(git rev-parse --short HEAD)
echo "[DEPLOY] Version: ${CURRENT_VERSION}"

echo "[DEPLOY] Validating Docker Compose configuration..."
docker compose --env-file "${ENV_FILE}" config >/dev/null

echo "[DEPLOY] Building production images..."
docker compose --env-file "${ENV_FILE}" build --pull api worker

echo "[DEPLOY] Starting database and Redis..."
docker compose --env-file "${ENV_FILE}" up -d postgres redis

echo "[DEPLOY] Applying Prisma migrations..."
docker compose --env-file "${ENV_FILE}" run --rm api npx prisma migrate deploy

echo "[DEPLOY] Starting API, worker and Nginx..."
docker compose --env-file "${ENV_FILE}" up -d --remove-orphans api worker nginx

echo "[DEPLOY] Waiting for API health..."
ATTEMPTS=0
while [ "${ATTEMPTS}" -lt "${MAX_ATTEMPTS}" ]; do
  if curl -fsS "${HEALTH_URL}" >/dev/null 2>&1; then
    echo "[DEPLOY] Health check passed."
    printf '%s\n' "$(git rev-parse HEAD)" > .current_version
    echo "[DEPLOY] Production deployment complete: ${CURRENT_VERSION}"
    exit 0
  fi
  ATTEMPTS=$((ATTEMPTS + 1))
  sleep 2
done

echo "[DEPLOY] ERROR: health check failed."

echo "[DEPLOY] Recent API logs:"
docker compose --env-file "${ENV_FILE}" logs --tail=80 api || true

# Application rollback is offered only when a previous version is known.
# Database migrations are forward-only: restore DB from backup before rolling
# back across a schema-breaking migration.
if [ -n "${ROLLBACK_VERSION}" ]; then
  echo "[DEPLOY] Rolling application containers back to ${ROLLBACK_VERSION}..."
  git checkout "${ROLLBACK_VERSION}"
  docker compose --env-file "${ENV_FILE}" build api worker
  docker compose --env-file "${ENV_FILE}" up -d --remove-orphans api worker nginx
fi

exit 1
