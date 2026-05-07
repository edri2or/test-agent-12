#!/bin/bash
# FILE_TO_CHECK env var (not shell arg) avoids injection when passing paths to node -e.

set -uo pipefail

command -v jq   >/dev/null 2>&1 || exit 0
command -v node >/dev/null 2>&1 || exit 0

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"

INPUT=$(cat)
FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null <<< "$INPUT")
[ -z "$FILE" ] && exit 0
[ -f "$FILE" ] || exit 0

case "$FILE" in
  */node_modules/*)   exit 0 ;;
  *package-lock.json) exit 0 ;;
esac

block() {
  local reason="$1"
  local detail="$2"
  jq -n \
    --arg reason "$reason" \
    --arg detail "$detail" \
    --arg file   "$FILE" \
    '{
      decision: "block",
      reason:   $reason,
      hookSpecificOutput: {
        hookEventName:     "PostToolUse",
        additionalContext: ("Validation failed for " + $file + ":\n" + $detail + "\nFix the errors above, then proceed.")
      }
    }'
  exit 0
}

case "$FILE" in
  *.ts|*.tsx)
    command -v npm >/dev/null 2>&1 || exit 0
    OUTPUT=$(npm run build:check 2>&1) || {
      block "TypeScript check failed" "$OUTPUT"
    }
    ;;

  *.json)
    OUTPUT=$(FILE_TO_CHECK="$FILE" node -e \
      'try{JSON.parse(require("fs").readFileSync(process.env.FILE_TO_CHECK,"utf8"))}catch(e){process.stderr.write(e.message+"\n");process.exit(1)}' \
      2>&1) || {
      block "JSON syntax error" "$OUTPUT"
    }
    ;;

  *.yml|*.yaml)
    [ -d "node_modules/js-yaml" ] || exit 0  # dev dep, available after npm install
    OUTPUT=$(FILE_TO_CHECK="$FILE" node -e \
      'const y=require("js-yaml"),fs=require("fs");try{y.load(fs.readFileSync(process.env.FILE_TO_CHECK,"utf8"))}catch(e){process.stderr.write(e.message+"\n");process.exit(1)}' \
      2>&1) || {
      block "YAML syntax error" "$OUTPUT"
    }
    ;;
esac

exit 0
