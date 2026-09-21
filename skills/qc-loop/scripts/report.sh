#!/usr/bin/env bash
# qc-loop report: query GET /qc for a window and print the per-hop aggregate table.
# Usage: bash report.sh <from_unix_s> <to_unix_s> [tag]
#        RAW=1 bash report.sh <from> <to> [tag]   # per-observation rows instead
#
# Auth: `/qc` is gated by SessionAuth — the `__Host-craft_session` cookie a signed-in
# browser holds. That is a DIFFERENT trust boundary than the CF-Access service token
# in ~/.craft/token.json, which only authenticates the /agent STAFF gateway (drive.sh's
# boundary). CF-Access headers do not satisfy SessionAuth, and curl cannot mint an
# HttpOnly cookie on its own, so this script needs the cookie handed to it explicitly:
#   1. (preferred) Read via the already-open, signed-in Chrome client-driver tab
#      instead of this script — a same-origin `fetch()` executed there carries the
#      HttpOnly cookie automatically. See references/capture.md step 4.
#   2. Or export the cookie value from that same browser (DevTools → Application →
#      Cookies → __Host-craft_session) into CRAFT_SESSION_COOKIE, then run this script.
set -euo pipefail

FROM=${1:?usage: report.sh <from> <to> [tag]}
TO=${2:?usage: report.sh <from> <to> [tag]}
TAG=${3:-}

: "${CRAFT_SESSION_COOKIE:?GET /qc requires a signed-in craft_session cookie (SessionAuth) - the CF-Access service token in ~/.craft/token.json does NOT satisfy it (that token is the /agent staff gateway, a separate trust boundary). Read via the browser client-driver tab (references/capture.md step 4) or set CRAFT_SESSION_COOKIE to the __Host-craft_session cookie value.}"

TOKEN_FILE="$HOME/.craft/token.json"
BASE=$(jq -r '.base' "$TOKEN_FILE")

url="${BASE}/qc?from=${FROM}&to=${TO}"
[ -n "$TAG" ] && url="${url}&tag=${TAG}"
[ "${RAW:-0}" = "1" ] && url="${url}&raw=1"

resp=$(curl -s -w $'\n%{http_code}' "$url" -H "Cookie: __Host-craft_session=${CRAFT_SESSION_COOKIE}")
http_code=$(tail -n1 <<<"$resp")
body=$(sed '$d' <<<"$resp")

if [ "$http_code" != "200" ]; then
  echo "AUTH/REQUEST FAILURE: GET /qc returned HTTP ${http_code} (expected 200)." >&2
  echo "Body: ${body}" >&2
  exit 1
fi

if [ "${RAW:-0}" = "1" ]; then
  echo "$body" | jq .
  exit 0
fi

{
  printf 'component\thop\tn\tp50_wall\tp95_wall\tp99_wall\tavg_cpu\tp95_cpu\n'
  echo "$body" | jq -r '.rows[] | [.component, (.endpoint|if .=="" then "(event)" else . end),
    .samples, .p50_wall, .p95_wall, .p99_wall, ((.avg_cpu*100|round)/100), .p95_cpu] | @tsv'
} | column -t -s$'\t'
