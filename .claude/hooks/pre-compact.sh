#!/bin/bash
# Registered with async: true — writes session-state.json + injects summary into compact prompt without blocking compaction.

set -uo pipefail

command -v jq  >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

BRANCH=$(git branch --show-current 2>/dev/null) || BRANCH=""
IFS=$'\t' read -r COMMIT_HASH COMMIT_MSG < <(git log -1 --format='%h%x09%s' 2>/dev/null) || { COMMIT_HASH=""; COMMIT_MSG=""; }

ISSUE_NUM="null"
ISSUE_TITLE=""
if [ -n "${GH_TOKEN:-}" ] && command -v curl >/dev/null 2>&1; then
  REMOTE=$(git remote get-url origin 2>/dev/null) || true
  REPO=$(printf '%s' "$REMOTE" | sed -E 's#^(git@github\.com:|https?://github\.com/)##;s#\.git$##')
  case "$REPO" in
    */*)
      ISSUE_RESP=$(curl -sf \
        -H "Authorization: Bearer $GH_TOKEN" \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/search/issues?q=repo:${REPO}+is:issue+is:open+label:current-focus" \
        2>/dev/null) || ISSUE_RESP=""
      if [ -n "$ISSUE_RESP" ]; then
        IFS=$'\t' read -r ISSUE_NUM ISSUE_TITLE < <(printf '%s' "$ISSUE_RESP" | jq -r '.items[0] | [(.number // "null"), (.title // "")] | @tsv' 2>/dev/null) || { ISSUE_NUM="null"; ISSUE_TITLE=""; }
      fi
      ;;
  esac
fi

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || TS=""

STATE_FILE="docs/session-state.json"
mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE" 2>/dev/null || true

jq \
  --arg ts          "$TS" \
  --arg branch      "$BRANCH" \
  --arg hash        "$COMMIT_HASH" \
  --arg msg         "$COMMIT_MSG" \
  --argjson issue   "$ISSUE_NUM" \
  --arg title       "$ISSUE_TITLE" \
  '. + {
    "last_updated":                $ts,
    "branch":                      $branch,
    "last_commit_hash":            $hash,
    "last_commit_msg":             $msg,
    "current_focus_issue_number":  $issue,
    "current_focus_issue_title":   $title
  }' "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null \
  && mv "${STATE_FILE}.tmp" "$STATE_FILE" 2>/dev/null || true

JOURNEY_LAST=$([ -f docs/JOURNEY.md ] && grep '^## ' docs/JOURNEY.md | tail -1 || true)

jq -n \
  --arg branch  "$BRANCH" \
  --arg hash    "$COMMIT_HASH" \
  --arg msg     "$COMMIT_MSG" \
  --argjson issue "$ISSUE_NUM" \
  --arg title   "$ISSUE_TITLE" \
  --arg journey "$JOURNEY_LAST" \
  '{
    session_context: {
      branch:            $branch,
      last_commit:       ($hash + " " + $msg),
      current_focus_issue: (if $issue != null then $issue else "unknown" end),
      current_focus_title: $title,
      journey_last_entry: $journey,
      autonomy_contract: "CLAUDE.md §Inviolable Autonomy Contract applies. Never ask operator for manual actions outside documented vendor floors. Operator decisions go in chat only.",
      reminder: "After compaction: read CLAUDE.md §Session-start verification ritual; update current-focus issue before Stop."
    }
  }'

exit 0
