#!/bin/bash

set -uo pipefail

command -v jq  >/dev/null 2>&1 || exit 0
command -v npm >/dev/null 2>&1 || exit 0

CMD=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[ -z "$CMD" ] && exit 0

case "$CMD" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

if ! OUTPUT=$(npm run build:check 2>&1); then
  jq -n \
    --arg out "$OUTPUT" \
    '{
      decision: "block",
      reason:   "TypeScript check must pass before committing.",
      hookSpecificOutput: {
        hookEventName:     "PreToolUse",
        additionalContext: ("tsc errors — fix before retrying git commit:\n" + $out)
      }
    }'
  exit 0
fi

exit 0
