#!/bin/bash
# Second Stop hook — separated from enforce-current-focus-fresh.sh so state writes
# succeed even when GH_TOKEN is absent (that hook exits early without it).

set -uo pipefail

command -v jq  >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

INPUT=$(cat)
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

STATE_FILE="docs/session-state.json"

BRANCH=$(git branch --show-current 2>/dev/null) || BRANCH=""
IFS=$'\t' read -r HASH MSG < <(git log -1 --format='%h%x09%s' 2>/dev/null) || { HASH=""; MSG=""; }
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)   || TS=""

mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE" 2>/dev/null || true

jq \
  --arg ts     "$TS" \
  --arg branch "$BRANCH" \
  --arg hash   "$HASH" \
  --arg msg    "$MSG" \
  '. + {
    "last_updated":      $ts,
    "branch":            $branch,
    "last_commit_hash":  $hash,
    "last_commit_msg":   $msg
  }' "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null \
  && mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true

exit 0
