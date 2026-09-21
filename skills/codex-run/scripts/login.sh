#!/usr/bin/env bash
# Codex API login — tries silent token refresh first, falls back to browser PKCE flow.
# Usage:
#   login.sh                      — refresh/login the last-used wallet
#   login.sh 0x3E370228...        — refresh/login by wallet address directly
#   login.sh my-profile           — refresh/login a named profile

set -euo pipefail

BASE="${CODEX_BASE:-https://codex.everygoodwork.io}"
CLIENT_NAME="${CODEX_CLIENT_NAME:-$(hostname)-cli}"
PORT=9876
REDIRECT_URI="http://localhost:${PORT}/callback"

CODEX_DIR="${HOME}/.codex"
WALLETS_DIR="${CODEX_DIR}/wallets"
PROFILES_FILE="${CODEX_DIR}/profiles.json"
LAST_TOKEN="${CODEX_DIR}/token.json"

mkdir -p "$WALLETS_DIR"

TARGET_ARG="${1:-}"
TARGET_WALLET=""
TARGET_TOKEN_FILE=""

if [[ -n "$TARGET_ARG" ]]; then
  if [[ "$TARGET_ARG" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    TARGET_WALLET="$TARGET_ARG"
  else
    if [[ -f "$PROFILES_FILE" ]]; then
      TARGET_WALLET=$(jq -r --arg name "$TARGET_ARG" '.[$name] // empty' "$PROFILES_FILE")
    fi
    if [[ -z "$TARGET_WALLET" ]]; then
      echo "ERROR: Unknown profile '$TARGET_ARG'" >&2
      exit 1
    fi
  fi
  TARGET_TOKEN_FILE="${WALLETS_DIR}/${TARGET_WALLET}.json"
else
  TARGET_TOKEN_FILE="$LAST_TOKEN"
fi

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
  if [[ "$source" != "$LAST_TOKEN" ]]; then
    cp "$source" "$LAST_TOKEN"
    chmod 600 "$LAST_TOKEN"
  fi
}

try_refresh() {
  local token_file="$1"
  [[ -f "$token_file" ]] || return 1

  local stored_expires stored_refresh stored_client_id
  stored_expires=$(jq -r '.expires_at // 0' "$token_file")
  stored_refresh=$(jq -r '.refresh_token // empty' "$token_file")
  stored_client_id=$(jq -r '.client_id // empty' "$token_file")

  if [[ "$(date +%s)" -lt "$stored_expires" ]]; then
    local wallet
    wallet=$(jq -r '.wallet' "$token_file")
    echo "Token still valid — authenticated as $wallet"
    sync_last_token "$token_file"
    return 0
  fi

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
      new_wallet=$(jq -r '.wallet' "$token_file")
      new_expires_at=$(( $(date +%s) + new_expires_in ))
      write_token "$token_file" "$new_access" "${new_refresh:-$stored_refresh}" "$stored_client_id" "$new_wallet" "$new_scope" "$new_expires_at"
      echo "Refreshed — authenticated as $new_wallet"
      sync_last_token "$token_file"
      return 0
    fi
    echo "Refresh failed — falling back to browser login..."
  fi

  return 1
}

try_refresh "$TARGET_TOKEN_FILE" && exit 0

# Browser consent flow
VERIFIER=$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=')
CODE_CHALLENGE=$(printf '%s' "$VERIFIER" | openssl dgst -sha256 -binary | openssl base64 | tr '+/' '-_' | tr -d '=')
STATE=$(openssl rand -hex 16)

CALLBACK_FILE=$(mktemp)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
node -e '
const http = require("http");
const fs = require("fs");
const path = require("path");
const template = fs.readFileSync(path.join("'"$SCRIPT_DIR"'", "callback.html"), "utf8");
const html = template.replace(/__BASE__/g, "'"$BASE"'");
const s = http.createServer((req, res) => {
  if (!req.url.startsWith("/callback")) { res.writeHead(404); res.end(); return; }
  fs.writeFileSync("'"$CALLBACK_FILE"'", req.url);
  res.writeHead(200, {"Content-Type": "text/html"});
  res.end(html);
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

AUTH_URL="${BASE}/consent?client_name=$(printf '%s' "$CLIENT_NAME" | sed 's/ /+/g')&redirect_uri=$(printf '%s' "$REDIRECT_URI" | sed 's/:/%3A/g; s/\//%2F/g')&scope=read+write+publish&state=${STATE}&code_challenge=${CODE_CHALLENGE}&code_challenge_method=S256"

echo "Opening browser for Codex authorization..."
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

if [ -z "$AUTH_CODE" ]; then echo "ERROR: No auth code in callback" >&2; exit 1; fi
if [ "$RECV_STATE" != "$STATE" ]; then echo "ERROR: State mismatch" >&2; exit 1; fi
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

if [[ -z "$TARGET_WALLET" ]]; then
  TARGET_WALLET="$WALLET"
  TARGET_TOKEN_FILE="${WALLETS_DIR}/${WALLET}.json"
fi

write_token "$TARGET_TOKEN_FILE" "$ACCESS_TOKEN" "$REFRESH_TOKEN" "$RECV_CLIENT_ID" "$WALLET" "$SCOPE" "$EXPIRES_AT"
sync_last_token "$TARGET_TOKEN_FILE"

echo ""
echo "Authenticated as $WALLET"
echo "Token stored at $TARGET_TOKEN_FILE"
echo "Scopes: $SCOPE"
echo "Expires: $(date -d @$EXPIRES_AT 2>/dev/null || date -r $EXPIRES_AT 2>/dev/null || echo "in ${EXPIRES_IN}s")"
