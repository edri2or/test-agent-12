#!/bin/bash
# Reads docs/session-state.json and injects orientation as additionalContext after compaction.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

STATE_FILE="docs/session-state.json"
[ -f "$STATE_FILE" ] || exit 0

IFS=$'\t' read -r BRANCH HASH MSG ISSUE_NUM ISSUE_TITLE UPDATED < <(
  jq -r '[.branch, .last_commit_hash, .last_commit_msg, (.current_focus_issue_number | tostring), .current_focus_issue_title, .last_updated] | map(. // "") | @tsv' \
    "$STATE_FILE" 2>/dev/null
) || { BRANCH=""; HASH=""; MSG=""; ISSUE_NUM=""; ISSUE_TITLE=""; UPDATED=""; }

if [ -n "$ISSUE_NUM" ] && [ "$ISSUE_NUM" != "null" ]; then
  ISSUE_LINE="- Current focus issue: #${ISSUE_NUM} — ${ISSUE_TITLE}"
else
  ISSUE_LINE="- Current focus issue: unknown (run mcp__github__list_issues with label current-focus)"
fi

ORIENTATION="POST-COMPACTION ORIENTATION (from docs/session-state.json, saved ${UPDATED}):
- Branch: ${BRANCH}
- Last commit: ${HASH} ${MSG}
${ISSUE_LINE}
- MANDATORY: Read CLAUDE.md §Session-start verification ritual before any action.
- MANDATORY: Append a timestamped entry to docs/JOURNEY.md before making edits.
- MANDATORY: Update the current-focus issue before Stop (enforced by Stop hook).
- Autonomy contract: Never ask operator for manual actions outside documented vendor floors."

jq -n --arg ctx "$ORIENTATION" '{
  hookSpecificOutput: {
    hookEventName: "PostCompact",
    additionalContext: $ctx
  }
}'

exit 0
