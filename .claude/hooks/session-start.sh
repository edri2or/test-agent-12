#!/bin/bash
set -euo pipefail

# Only run in remote (Claude Code on the web) environments.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

if [ ! -f node_modules/.package-lock.json ] || [ package-lock.json -nt node_modules/.package-lock.json ]; then
  npm install --no-audit --no-fund --loglevel=error
fi

BRANCH=$(git branch --show-current 2>/dev/null) || BRANCH=""

STATE_FILE="${CLAUDE_PROJECT_DIR}/docs/session-state.json"
if [ ! -f "$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || TS=""
  IFS=$'\t' read -r HASH MSG < <(git log -1 --format='%h%x09%s' 2>/dev/null) || { HASH=""; MSG=""; }
  jq -n \
    --arg schema  "session-state.v1" \
    --arg note    "Machine-readable session state. Written by pre-compact.sh and write-session-state.sh. Read by post-compact.sh and session-start.sh. Do not edit manually." \
    --arg ts      "$TS" \
    --arg branch  "$BRANCH" \
    --arg hash    "$HASH" \
    --arg msg     "$MSG" \
    '{
      "_schema":                    $schema,
      "_note":                      $note,
      "last_updated":               $ts,
      "branch":                     $branch,
      "last_commit_hash":           $hash,
      "last_commit_msg":            $msg,
      "current_focus_issue_number": null,
      "current_focus_issue_title":  "",
      "recent_workflow_runs":       [],
      "open_prs_this_session":      [],
      "journey_last_entry_date":    "",
      "pending_operator_decisions": []
    }' > "$STATE_FILE" 2>/dev/null || true
fi

BOOTSTRAP_FILE="${CLAUDE_PROJECT_DIR}/docs/bootstrap-state.md"
[ -f "$BOOTSTRAP_FILE" ] || exit 0
command -v date >/dev/null 2>&1 || exit 0
LAST_VERIFIED=$(grep 'Last verified:' "$BOOTSTRAP_FILE" | head -1 | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
[ -n "$LAST_VERIFIED" ] || exit 0
LAST_EPOCH=$(date -d "$LAST_VERIFIED" +%s 2>/dev/null) || exit 0
NOW_EPOCH=$(date +%s 2>/dev/null) || exit 0
DAYS_OLD=$(( (NOW_EPOCH - LAST_EPOCH) / 86400 ))
if [ "$DAYS_OLD" -gt 7 ]; then
  echo "SESSION-START WARNING: docs/bootstrap-state.md is ${DAYS_OLD} days old. Consider refreshing the GCP snapshot." >&2
fi
