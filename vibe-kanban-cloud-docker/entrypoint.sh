#!/bin/bash
set -e

echo "Starting Vibe Kanban Cloud (moccassins fork)..."

# Handle PUID and PGID for the /data directory
PUID=${PUID:-99}
PGID=${PGID:-100}
echo "Setting permissions for /data to PUID: $PUID and PGID: $PGID"
chown -R "$PUID":"$PGID" /data

# Start the docker daemon in the background
dockerd-entrypoint.sh &
DOCKER_PID=$!

echo "Waiting for internal Docker daemon to initialize..."
TIMEOUT=30
while ! docker info >/dev/null 2>&1; do
    sleep 1
    TIMEOUT=$((TIMEOUT-1))
    if [ $TIMEOUT -le 0 ]; then
        echo "❌ FATAL: Internal Docker daemon failed to start within 30 seconds."
        echo "Ensure the container is running in Privileged mode."
        exit 1
    fi
    if ! kill -0 $DOCKER_PID 2>/dev/null; then
        echo "❌ FATAL: Internal Docker daemon crashed prematurely."
        exit 1
    fi
done
echo "Internal Docker daemon is ready."

ENV_FILE="/data/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "First run: Generating secure secrets in /data/.env..."
    touch "$ENV_FILE"
    echo "DB_PASSWORD=$(openssl rand -hex 32)" >> "$ENV_FILE"
    echo "DB_NAME=remote" >> "$ENV_FILE"
    echo "DB_USER=remote" >> "$ENV_FILE"
    echo "VIBEKANBAN_REMOTE_JWT_SECRET=$(openssl rand -hex 32)" >> "$ENV_FILE"
    echo "ELECTRIC_ROLE_PASSWORD=$(openssl rand -hex 32)" >> "$ENV_FILE"
    chown "$PUID":"$PGID" "$ENV_FILE"
else
    echo "Existing configuration found in /data/.env. Loading secrets..."
fi

source "$ENV_FILE"

export DOMAIN="${DOMAIN:-localhost}"
export DB_PASSWORD DB_NAME DB_USER
export VIBEKANBAN_REMOTE_JWT_SECRET
export ELECTRIC_ROLE_PASSWORD
export SELF_HOST_LOCAL_AUTH_EMAIL="${SELF_HOST_LOCAL_AUTH_EMAIL:-}"
export SELF_HOST_LOCAL_AUTH_PASSWORD="${SELF_HOST_LOCAL_AUTH_PASSWORD:-}"
export GITHUB_OAUTH_CLIENT_ID="${GITHUB_OAUTH_CLIENT_ID:-}"
export GITHUB_OAUTH_CLIENT_SECRET="${GITHUB_OAUTH_CLIENT_SECRET:-}"
export GOOGLE_OAUTH_CLIENT_ID="${GOOGLE_OAUTH_CLIENT_ID:-}"
export GOOGLE_OAUTH_CLIENT_SECRET="${GOOGLE_OAUTH_CLIENT_SECRET:-}"
export RUST_LOG="${RUST_LOG:-info,remote=info}"

echo "Starting Vibe Kanban inner stack..."
cd /app

set +e
docker compose up -d
UP_STATUS=$?
set -e

if [ $UP_STATUS -ne 0 ]; then
    echo "--------------------------------------------------------"
    echo "❌ FATAL: docker-compose failed to start the stack."
    echo "Fetching logs for remote-server:"
    echo "------------------- REMOTE-SERVER LOGS -----------------"
    docker compose logs remote-server
    echo "--------------------------------------------------------"
    kill $DOCKER_PID
    wait $DOCKER_PID
    exit 1
fi

echo "Monitoring startup status..."
MAX_RETRIES=30
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "--------------------------------------------------------"
    echo "Service Status ($(date +%H:%M:%S)) - Attempt $((RETRY_COUNT+1))/$MAX_RETRIES"
    docker compose ps --format "table {{.Service}}\t{{.Status}}\t{{.Health}}"

    SERVER_CONTAINER=$(docker compose ps -q remote-server)
    if [ -n "$SERVER_CONTAINER" ]; then
        HEALTH=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$SERVER_CONTAINER" 2>/dev/null || echo "starting")

        if [ "$HEALTH" == "healthy" ]; then
            echo "--------------------------------------------------------"
            echo "✅ remote-server is HEALTHY. Vibe Kanban is ready!"
            echo "Access at: http://<IP>:8081"
            break
        fi

        if [ "$HEALTH" == "unhealthy" ] || [ "$HEALTH" == "exited" ]; then
            echo "--------------------------------------------------------"
            echo "❌ remote-server is $HEALTH!"
            echo "Fetching logs:"
            echo "------------------- REMOTE-SERVER LOGS -----------------"
            docker compose logs remote-server
            echo "--------------------------------------------------------"
            break
        fi
    fi

    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 10
done

echo "--------------------------------------------------------"
echo "Tailing logs (Ctrl+C to stop, container keeps running)..."
docker compose logs -f

kill $DOCKER_PID
wait $DOCKER_PID
