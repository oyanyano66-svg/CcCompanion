#!/usr/bin/env bash
# pet_state_hook.sh — PreToolUse hook, push tool→state mapping to /pet/state
# Tool info comes via stdin JSON: {"tool_name":"Bash","tool_input":{...}}

INPUT="$(cat)"
TOOL_NAME="$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tool_name',''))" 2>/dev/null)"

[ -z "$TOOL_NAME" ] && exit 0

SECRET="Vreix191k62CrUA6gBr4BcxRtK6g3puORwrqU3P44k0"
URL="http://127.0.0.1:8795/pet/state"

case "$TOOL_NAME" in
  Bash|bash)           STATE="building" ;;
  Edit|Write)          STATE="typing" ;;
  Read|Grep|Glob)      STATE="carrying" ;;
  Agent)               STATE="conducting" ;;
  *)                   STATE="thinking" ;;
esac

curl -sf -X POST "$URL" \
  -H "X-Auth-Token: $SECRET" \
  -H "Content-Type: application/json" \
  -d "{\"state\":\"$STATE\",\"reason\":\"$TOOL_NAME\"}" \
  --connect-timeout 2 --max-time 3 \
  >/dev/null 2>&1 &

exit 0
