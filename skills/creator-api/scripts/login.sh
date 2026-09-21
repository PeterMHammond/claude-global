#!/usr/bin/env bash
# Creator API login — tries silent token refresh first, falls back to browser PKCE flow.
# Requires: bash, curl, openssl, jq, node (already present if Claude Code is installed)
#
# Usage:
#   login.sh                      — refresh/login the last-used wallet
#   login.sh cloudflare-chronicles — refresh/login a named profile
#   login.sh 0x3E370228...        — refresh/login by wallet address directly
#
# Tokens stored per-wallet at ~/.creator/wallets/{wallet}.json
# Named profiles in ~/.creator/profiles.json  { "cloudflare-chronicles": "0x3E37..." }
# ~/.creator/token.json always reflects the last-used wallet (backward compat)

set -euo pipefail

BASE="${CREATOR_BASE:-https://creator.everygoodwork.io}"
CLIENT_NAME="${CREATOR_CLIENT_NAME:-$(hostname)-cli}"
PORT=9876
REDIRECT_URI="http://localhost:${PORT}/callback"

CREATOR_DIR="${HOME}/.creator"
WALLETS_DIR="${CREATOR_DIR}/wallets"
PROFILES_FILE="${CREATOR_DIR}/profiles.json"
LAST_TOKEN="${CREATOR_DIR}/token.json"  # backward-compat symlink/copy

mkdir -p "$WALLETS_DIR"

# ── Resolve target wallet from argument ───────────────────────────────────────

TARGET_ARG="${1:-}"
TARGET_WALLET=""
TARGET_TOKEN_FILE=""

if [[ -n "$TARGET_ARG" ]]; then
  # Is it a wallet address?
  if [[ "$TARGET_ARG" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    TARGET_WALLET="$TARGET_ARG"
  else
    # Look up profile name
    if [[ -f "$PROFILES_FILE" ]]; then
      TARGET_WALLET=$(jq -r --arg name "$TARGET_ARG" '.[$name] // empty' "$PROFILES_FILE")
    fi
    if [[ -z "$TARGET_WALLET" ]]; then
      echo "ERROR: Unknown profile '$TARGET_ARG'. Known profiles:" >&2
      if [[ -f "$PROFILES_FILE" ]]; then
        jq -r 'to_entries[] | "  \(.key) → \(.value)"' "$PROFILES_FILE" >&2
      else
        echo "  (none registered yet)" >&2
      fi
      exit 1
    fi
  fi
  TARGET_TOKEN_FILE="${WALLETS_DIR}/${TARGET_WALLET}.json"
else
  # No arg — use last-used token
  TARGET_TOKEN_FILE="$LAST_TOKEN"
fi

# ── Fast path: valid or refreshable token ─────────────────────────────────────

try_refresh() {
  local token_file="$1"
  [[ -f "$token_file" ]] || return 1

  local stored_expires stored_refresh stored_client_id
  stored_expires=$(jq -r '.expires_at // 0' "$token_file")
  stored_refresh=$(jq -r '.refresh_token // empty' "$token_file")
  stored_client_id=$(jq -r '.client_id // empty' "$token_file")

  # Still valid
  if [[ "$(date +%s)" -lt "$stored_expires" ]]; then
    local wallet
    wallet=$(jq -r '.wallet' "$token_file")
    echo "Token still valid — authenticated as $wallet"
    echo "Expires: $(date -d @"$stored_expires" 2>/dev/null || date -r "$stored_expires" 2>/dev/null || echo "in $(( stored_expires - $(date +%s) ))s")"
    sync_last_token "$token_file"
    return 0
  fi

  # Try silent refresh
  if [[ -n "$stored_refresh" && -n "$stored_client_id" ]]; then
    echo "Access token expired — attempting silent refresh..."
    local refresh_resp new_access
    refresh_resp=$(curl -sf "$BASE/oauth/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=refresh_token&client_id=${stored_client_id}&refresh_token=${stored_refresh}" 2>/dev/null || echo "")
    new_access=$(echo "$refresh_resp" | jq -r '.access_token // empty' 2>/dev/null || echo "")

    if [[ -n "$new_access" ]]; then
      local new_refresh new_expires_in new_scope new_wallet new_expires_at
      new_refresh=$(echo "$refresh_resp" | jq -r '.refresh_token // empty')
      new_expires_in=$(echo "$refresh_resp" | jq -r '.expires_in')
      new_scope=$(echo "$refresh_resp" | jq -r '.scope')
      new_wallet=$(echo "$new_access" | cut -d: -f1)
      new_expires_at=$(( $(date +%s) + new_expires_in ))
      write_token "$token_file" "$new_access" "${new_refresh:-$stored_refresh}" "$stored_client_id" "$new_wallet" "$new_scope" "$new_expires_at"
      echo "Refreshed — authenticated as $new_wallet"
      echo "Expires: $(date -d @"$new_expires_at" 2>/dev/null || date -r "$new_expires_at" 2>/dev/null || echo "in ${new_expires_in}s")"
      sync_last_token "$token_file"
      return 0
    fi
    echo "Refresh failed — falling back to browser login..."
  fi

  return 1
}

write_token() {
  local file="$1" access="$2" refresh="$3" client_id="$4" wallet="$5" scope="$6" expires_at="$7"
  jq -n \
    --arg access_token "$access" \
    --arg refresh_token "$refresh" \
    --arg client_id "$client_id" \
    --arg wallet "$wallet" \
    --arg scope "$scope" \
    --arg base "$BASE" \
    --argjson expires_at "$expires_at" \
    '{access_token: $access_token, refresh_token: $refresh_token, client_id: $client_id, wallet: $wallet, scope: $scope, base: $base, expires_at: $expires_at}' \
    > "$file"
  chmod 600 "$file"
}

sync_last_token() {
  local source="$1"
  # Keep ~/.creator/token.json in sync with last-used wallet (backward compat)
  if [[ "$source" != "$LAST_TOKEN" ]]; then
    cp "$source" "$LAST_TOKEN"
    chmod 600 "$LAST_TOKEN"
  fi
}

register_profile() {
  local wallet="$1"
  local token_file="${WALLETS_DIR}/${wallet}.json"
  # Always persist per-wallet token
  if [[ "$TARGET_TOKEN_FILE" != "$token_file" ]]; then
    cp "$TARGET_TOKEN_FILE" "$token_file" 2>/dev/null || true
    chmod 600 "$token_file" 2>/dev/null || true
  fi
  # Prompt to name this wallet if not already profiled
  if [[ -f "$PROFILES_FILE" ]]; then
    local existing
    existing=$(jq -r --arg w "$wallet" 'to_entries[] | select(.value == $w) | .key' "$PROFILES_FILE" 2>/dev/null || echo "")
    if [[ -n "$existing" ]]; then
      return  # already has a profile name
    fi
  fi
  # Auto-register wallet address as its own profile key (can be aliased later)
  if [[ ! -f "$PROFILES_FILE" ]]; then
    echo '{}' > "$PROFILES_FILE"
  fi
  jq --arg wallet "$wallet" '.[$wallet] = $wallet' "$PROFILES_FILE" > "${PROFILES_FILE}.tmp" && mv "${PROFILES_FILE}.tmp" "$PROFILES_FILE"
}

# Try fast path first
try_refresh "$TARGET_TOKEN_FILE" && exit 0

# ── Browser consent flow ───────────────────────────────────────────────────────

# PKCE
VERIFIER=$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=')
CODE_CHALLENGE=$(printf '%s' "$VERIFIER" | openssl dgst -sha256 -binary | openssl base64 | tr '+/' '-_' | tr -d '=')
STATE=$(openssl rand -hex 16)

CALLBACK_FILE=$(mktemp)
node -e '
const http = require("http");
const fs = require("fs");
const s = http.createServer((req, res) => {
  if (!req.url.startsWith("/callback")) { res.writeHead(404); res.end(); return; }
  fs.writeFileSync("'"$CALLBACK_FILE"'", req.url);
  res.writeHead(200, {"Content-Type": "text/html"});
  res.end(`<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>Creator — Authorized</title>
<style>:root{color-scheme:light dark;--bg:light-dark(#f3f4f6,#111113);--card:light-dark(#ffffff,#1a1a1e);--text:light-dark(#1f2937,#f2f4f6);--text-muted:light-dark(#6b7280,#9ca3af);--border:light-dark(#e5e7eb,#2e2e32);--radius:6px;--ok:light-dark(#065f46,#4ade80);--ok-bg:light-dark(#d1fae5,#052e16)}
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:var(--bg);color:var(--text);line-height:1.5}
header{display:flex;justify-content:space-between;align-items:center;padding:12px 24px;background:var(--card);border-bottom:1px solid var(--border)}
header h1{font-size:18px;font-weight:600}
main{max-width:480px;margin:40px auto;padding:0 24px}
.card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:20px;text-align:center}
.check{display:inline-flex;align-items:center;justify-content:center;width:48px;height:48px;border-radius:50%;background:var(--ok-bg);color:var(--ok);font-size:24px;margin-bottom:16px}
h2{font-size:18px;font-weight:600;margin-bottom:8px}
p{color:var(--text-muted);font-size:14px}</style></head>
<body><header><h1>Creator</h1></header><main><div class="card"><div class="check">&#10003;</div><h2>Authorized</h2><p>You can close this tab and return to the terminal.</p></div></main></body></html>`);
  s.close(() => process.exit(0));
});
s.listen('"$PORT"', "127.0.0.1", () => console.log("Listening on localhost:'"$PORT"'..."));
' &
SERVER_PID=$!
sleep 0.5

if ! kill -0 "$SERVER_PID" 2>/dev/null; then
  echo "ERROR: Failed to start callback server on port $PORT" >&2
  exit 1
fi

trap 'kill $SERVER_PID 2>/dev/null || true; rm -f "$CALLBACK_FILE"' EXIT

ENCODED_REDIRECT=$(printf '%s' "$REDIRECT_URI" | sed 's/:/%3A/g; s/\//%2F/g')
ENCODED_CLIENT_NAME=$(printf '%s' "$CLIENT_NAME" | sed 's/ /+/g; s/:/%3A/g; s/\//%2F/g')
AUTH_URL="${BASE}/editor/consent?client_name=${ENCODED_CLIENT_NAME}&redirect_uri=${ENCODED_REDIRECT}&scope=read+write+publish&state=${STATE}&code_challenge=${CODE_CHALLENGE}&code_challenge_method=S256"

echo "Opening browser for Creator authorization..."
if command -v xdg-open &>/dev/null; then
  xdg-open "$AUTH_URL" 2>/dev/null
elif command -v open &>/dev/null; then
  open "$AUTH_URL"
else
  echo "Open this URL in your browser:"
  echo "$AUTH_URL"
fi

echo "Waiting for consent approval..."
wait "$SERVER_PID" 2>/dev/null || true

CALLBACK_PATH=$(cat "$CALLBACK_FILE")
AUTH_CODE=$(echo "$CALLBACK_PATH" | grep -o 'code=[^&]*' | cut -d= -f2)
RECV_STATE=$(echo "$CALLBACK_PATH" | grep -o 'state=[^&]*' | cut -d= -f2)
RECV_CLIENT_ID=$(echo "$CALLBACK_PATH" | grep -o 'client_id=[^&]*' | cut -d= -f2)

if [ -z "$AUTH_CODE" ]; then echo "ERROR: No auth code found in callback" >&2; exit 1; fi
if [ "$RECV_STATE" != "$STATE" ]; then echo "ERROR: State mismatch — possible CSRF" >&2; exit 1; fi
if [ -z "$RECV_CLIENT_ID" ]; then echo "ERROR: No client_id in callback" >&2; exit 1; fi

TOKEN_RESP=$(curl -sf "$BASE/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code&client_id=${RECV_CLIENT_ID}&code=${AUTH_CODE}&redirect_uri=${REDIRECT_URI}&code_verifier=${VERIFIER}")

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token')
REFRESH_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.refresh_token // empty')
EXPIRES_IN=$(echo "$TOKEN_RESP" | jq -r '.expires_in')
SCOPE=$(echo "$TOKEN_RESP" | jq -r '.scope')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
  echo "ERROR: Token exchange failed" >&2; echo "$TOKEN_RESP" >&2; exit 1
fi

WALLET=$(echo "$ACCESS_TOKEN" | cut -d: -f1)
EXPIRES_AT=$(($(date +%s) + EXPIRES_IN))

write_token "$TARGET_TOKEN_FILE" "$ACCESS_TOKEN" "$REFRESH_TOKEN" "$RECV_CLIENT_ID" "$WALLET" "$SCOPE" "$EXPIRES_AT"
register_profile "$WALLET"
sync_last_token "$TARGET_TOKEN_FILE"

echo ""
echo "Authenticated as $WALLET"
echo "Token stored at $TARGET_TOKEN_FILE"
echo "Scopes: $SCOPE"
echo "Expires: $(date -d @$EXPIRES_AT 2>/dev/null || date -r $EXPIRES_AT 2>/dev/null || echo "in ${EXPIRES_IN}s")"
