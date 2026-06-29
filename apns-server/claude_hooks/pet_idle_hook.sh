#!/usr/bin/env bash
# pet_idle_hook.sh — Stop hook, reset pet state to idle when Claude finishes

SECRET="Vreix191k62CrUA6gBr4BcxRtK6g3puORwrqU3P44k0"
URL="http://127.0.0.1:8795/pet/state"

curl -sf -X POST "$URL" \
  -H "X-Auth-Token: $SECRET" \
  -H "Content-Type: application/json" \
  -d '{"state":"idle","reason":"stop"}' \
  --connect-timeout 2 --max-time 3 \
  >/dev/null 2>&1 &

exit 0
