#!/bin/bash
set -e

# ── Validate required env vars ────────────────────────────────────
: "${SERVER_DATABASE_URL:?SERVER_DATABASE_URL is required (format: postgres://user:pass@host:5432/dbname)}"
: "${ELECTRIC_ROLE_PASSWORD:?ELECTRIC_ROLE_PASSWORD is required}"
: "${VIBEKANBAN_REMOTE_JWT_SECRET:?VIBEKANBAN_REMOTE_JWT_SECRET is required}"

# ── Export for supervisor children ────────────────────────────────
export SERVER_DATABASE_URL
export SERVER_LISTEN_ADDR="${SERVER_LISTEN_ADDR:-0.0.0.0:8081}"
export ELECTRIC_URL="${ELECTRIC_URL:-http://127.0.0.1:3000}"
export ELECTRIC_ROLE_PASSWORD
export ELECTRIC_PORT="${ELECTRIC_PORT:-3000}"
export VIBEKANBAN_REMOTE_JWT_SECRET
export SERVER_PUBLIC_BASE_URL="${SERVER_PUBLIC_BASE_URL:-http://localhost:8081}"
export RUST_LOG="${RUST_LOG:-info,remote=info}"

# Build ElectricSQL DATABASE_URL with electric_sync user
# Parse SERVER_DATABASE_URL and replace user with electric_sync
DB_PROTO=$(echo "$SERVER_DATABASE_URL" | sed -E 's|(^[^:]+)://.*|\1|')
DB_HOST_PORT=$(echo "$SERVER_DATABASE_URL" | sed -E 's|^[^:]+://[^@]+@([^/]+).*|\1|')
DB_NAME=$(echo "$SERVER_DATABASE_URL" | sed -E 's|^[^:]+://[^/]+/([^?]+).*|\1|')
export ELECTRIC_DATABASE_URL="${DB_PROTO}://electric_sync:${ELECTRIC_ROLE_PASSWORD}@${DB_HOST_PORT}/${DB_NAME}?sslmode=disable"

# Optional
export GITHUB_OAUTH_CLIENT_ID="${GITHUB_OAUTH_CLIENT_ID:-}"
export GITHUB_OAUTH_CLIENT_SECRET="${GITHUB_OAUTH_CLIENT_SECRET:-}"
export GOOGLE_OAUTH_CLIENT_ID="${GOOGLE_OAUTH_CLIENT_ID:-}"
export GOOGLE_OAUTH_CLIENT_SECRET="${GOOGLE_OAUTH_CLIENT_SECRET:-}"
export SELF_HOST_LOCAL_AUTH_EMAIL="${SELF_HOST_LOCAL_AUTH_EMAIL:-}"
export SELF_HOST_LOCAL_AUTH_PASSWORD="${SELF_HOST_LOCAL_AUTH_PASSWORD:-}"

# ── Create electric_sync role in Postgres ───────────────────────
echo "Setting up electric_sync role..."
/usr/local/bin/create-electric-role.sh

echo "Starting Vibe Kanban Cloud (remote + electric-sql)..."
echo "ElectricSQL DB URL: $ELECTRIC_DATABASE_URL"
echo "Remote listening on: $SERVER_LISTEN_ADDR"
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
