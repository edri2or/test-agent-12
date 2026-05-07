#!/bin/bash
# Stop-hook: blocks session end when the `current-focus` issue is older than
# the most recent local commit (agent made changes but didn't update the issue).
#
# Anti-infinite-loop: stop_hook_active=true (Claude Code hook protocol,
# https://docs.claude.com/en/docs/claude-code/hooks) causes this hook to yield,
# letting the session terminate after the model has already responded to one block.
#
# Soft-skips (exit 0) when enforcement would wedge the session: missing GH_TOKEN,
# jq/curl/git absent, no git remote, no open current-focus issue.

set -uo pipefail

INPUT=$(cat)

command -v jq >/dev/null 2>&1 || exit 0
STOP_HOOK_ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_HOOK_ACTIVE" = "true" ] && exit 0

[ -z "${GH_TOKEN:-}" ] && exit 0
command -v curl >/dev/null 2>&1 || exit 0
command -v git >/dev/null 2>&1 || exit 0
command -v date >/dev/null 2>&1 || exit 0

# Resolve owner/repo from the git remote rather than hard-coding. Match
# only github.com URLs; GitLab/Bitbucket/etc. fall through the */* check
# and soft-skip (we'd otherwise hit api.github.com with a non-existent
# repo and waste a search-API rate-limit slot per Stop event).
REMOTE=$(git remote get-url origin 2>/dev/null) || exit 0
REPO=$(printf '%s' "$REMOTE" | sed -E 's#^(git@github\.com:|https?://github\.com/)##;s#\.git$##')
case "$REPO" in
  */*) ;;            # owner/name — proceed
  *)   exit 0 ;;     # not a github remote — skip
esac

ISSUE_RESP=$(curl -sf \
  -H "Authorization: Bearer $GH_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/search/issues?q=repo:${REPO}+is:issue+is:open+label:current-focus") || exit 0
IFS=$'\t' read -r ISSUE_NUM ISSUE_UPDATED < <(printf '%s' "$ISSUE_RESP" | jq -r '.items[0] | [(.number // ""), (.updated_at // "")] | @tsv' 2>/dev/null)
[ -z "$ISSUE_NUM" ] && exit 0
[ -z "$ISSUE_UPDATED" ] && exit 0

LAST_COMMIT_TS=$(git log -1 --format=%cI 2>/dev/null) || exit 0
[ -z "$LAST_COMMIT_TS" ] && exit 0

# Normalise both timestamps to epoch seconds before comparing. ISO 8601
# strings with different timezone offsets do NOT sort lexicographically:
# "2026-05-02T18:40:43+03:00" > "2026-05-02T15:44:20Z" lex-compares as
# true even though the commit is actually 4 minutes EARLIER. `date -d`
# parses both forms and emits epoch seconds, normalising the offsets.
LAST_COMMIT_EPOCH=$(date -d "$LAST_COMMIT_TS" +%s 2>/dev/null) || exit 0
ISSUE_UPDATED_EPOCH=$(date -d "$ISSUE_UPDATED" +%s 2>/dev/null) || exit 0
if [ "$LAST_COMMIT_EPOCH" -gt "$ISSUE_UPDATED_EPOCH" ]; then
  jq -n \
    --arg num "$ISSUE_NUM" \
    --arg lct "$LAST_COMMIT_TS" \
    --arg iut "$ISSUE_UPDATED" \
    --arg repo "$REPO" \
    '{
      decision: "block",
      reason: ("STOP-BLOCK: per CLAUDE.md §Session-start verification ritual rule 5, the `current-focus` issue ("
        + $repo + "#" + $num
        + ") must be updated when state changes this session. Latest local commit ("
        + $lct + ") is newer than the issue updated_at (" + $iut
        + "). Call `mcp__github__issue_write` with method=update on this issue, bump the **Updated By** line to capture what landed this session and what the next Next Concrete Step is, then stop again. (This hook auto-yields on the next Stop after you update.)")
    }'
fi

exit 0
