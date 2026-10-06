#!/usr/bin/env bash
# POST a program to craft's admin rail. Program source on stdin or --file; capabilities as CSV.
# Exists so the documented invocation matches an allowlisted path — a bare curl is an unmatched
# Bash command and falls to the permission classifier.
set -euo pipefail

TOKEN_FILE="${CRAFT_AGENT_TOKEN:-$HOME/.craft/token.json}"
[ -f "$TOKEN_FILE" ] || { echo "no token at $TOKEN_FILE — run login.sh" >&2; exit 1; }

CAPS="" FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --caps) CAPS="${2:-}"; shift 2 ;;
    --file) FILE="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

BASE=$(jq -r '.base' "$TOKEN_FILE")
CODE=$([ -n "$FILE" ] && cat "$FILE" || cat)

jq -n --arg code "$CODE" --arg caps "$CAPS" \
  '{code: $code, capabilities: (if $caps == "" then [] else ($caps | split(",")) end)}' \
| curl -s -X POST "${BASE}/-/agent" \
    -H "CF-Access-Client-Id: $(jq -r '.client_id' "$TOKEN_FILE")" \
    -H "CF-Access-Client-Secret: $(jq -r '.client_secret' "$TOKEN_FILE")" \
    -H "Content-Type: application/json" \
    --data-binary @-
