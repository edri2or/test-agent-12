#!/usr/bin/env bash
#
# R-06 staging validation — n8n owner re-sync idempotency on container restart.
#
# Spins up n8nio/n8n:2.17.0 with N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true,
# captures the owner row from the SQLite DB, restarts the container with the
# SAME env, and asserts the password hash + createdAt are unchanged.
#
# Pass criteria:
#   1. Owner row exists after first boot.
#   2. After restart with same env, password and createdAt are bit-identical.
#
# This is a local Docker equivalent of the Railway re-deploy scenario. Railway
# performs the same container restart on deploy, so a Docker pass implies a
# Railway pass for the same n8n version.
#
# Re-run: before any n8n version bump and before promoting Railway template
# changes that touch the n8n service.

set -euo pipefail

CONTAINER=n8n-r06
DATA_DIR="$(pwd)/.n8n-r06"
IMAGE=n8nio/n8n:2.17.0
PASSWORD="staging-test-pw-do-not-reuse"
EMAIL="r06-test@local"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$DATA_DIR"
}
trap cleanup EXIT

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "FAIL: required command not found: $1" >&2
    exit 1
  fi
}
require docker
require sqlite3
require htpasswd

# htpasswd emits bcrypt with the $2y$ prefix (PHP); n8n's bcryptjs verify
# accepts $2a$ but rejects $2y$, so rewrite the prefix.
HASH=$(htpasswd -bnBC 10 "" "$PASSWORD" | tr -d ':\n' | sed 's/^[$]2y[$]/$2a$/')

mkdir -p "$DATA_DIR"
chmod 777 "$DATA_DIR"

start_n8n() {
  docker run --rm -d \
    --name "$CONTAINER" \
    -e N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true \
    -e N8N_INSTANCE_OWNER_EMAIL="$EMAIL" \
    -e N8N_INSTANCE_OWNER_PASSWORD_HASH="$HASH" \
    -e N8N_INSTANCE_OWNER_FIRST_NAME=Staging \
    -e N8N_INSTANCE_OWNER_LAST_NAME=R06 \
    -p 5679:5678 \
    -v "$DATA_DIR:/home/node/.n8n" \
    "$IMAGE" >/dev/null
}

wait_for_boot() {
  local i=0
  until curl -fsS http://localhost:5679/healthz >/dev/null 2>&1; do
    i=$((i+1))
    if [ "$i" -gt 60 ]; then
      echo "FAIL: n8n did not become healthy within 60s" >&2
      docker logs "$CONTAINER" >&2 || true
      exit 1
    fi
    sleep 1
  done
  # Owner sync runs slightly after /healthz responds; allow up to 15s
  for _ in $(seq 1 15); do
    if [ -f "$DATA_DIR/database.sqlite" ] && \
       sqlite3 "$DATA_DIR/database.sqlite" \
         "select count(*) from user where email='$EMAIL'" 2>/dev/null \
         | grep -q '^1$'; then
      return 0
    fi
    sleep 1
  done
  echo "FAIL: owner row never appeared in DB" >&2
  exit 1
}

read_owner_row() {
  sqlite3 "$DATA_DIR/database.sqlite" \
    "select password, createdAt from user where email='$EMAIL'"
}

echo "[R-06] First boot..."
start_n8n
wait_for_boot
ROW1=$(read_owner_row)
echo "[R-06] Owner row after first boot: $ROW1"

echo "[R-06] Stopping container..."
docker stop "$CONTAINER" >/dev/null

echo "[R-06] Second boot with identical env..."
start_n8n
wait_for_boot
ROW2=$(read_owner_row)
echo "[R-06] Owner row after second boot: $ROW2"

if [ "$ROW1" = "$ROW2" ]; then
  echo "[R-06] PASS — owner password + createdAt unchanged across restart (idempotent)"
  exit 0
else
  echo "[R-06] FAIL — owner row mutated across restart" >&2
  echo "  before: $ROW1" >&2
  echo "  after:  $ROW2" >&2
  exit 1
fi
