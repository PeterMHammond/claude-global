#!/usr/bin/env bash
# Creator API token refresh — no browser required
# Uses stored refresh_token to get a new access_token silently.
# Falls back to full login flow if refresh_token is missing or expired.
set -euo pipefail

SCOPE="${CREATOR_TOKEN_SCOPE:-default}"
TOKEN_FILE="${HOME}/.creator/tokens/${SCOPE}.json"
[ ! -f "$TOKEN_FILE" ] && TOKEN_FILE="${HOME}/.creator/token.json"

if [ ! -f "$TOKEN_FILE" ]; then
  echo "No token file found — running full login flow"
  exec bash "$(dirname "$0")/login.sh"
fi

REFRESH_TOKEN=$(jq -r '.refresh_token // empty' "$TOKEN_FILE")
CLIENT_ID=$(jq -r '.client_id // empty' "$TOKEN_FILE")
BASE=$(jq -r '.base' "$TOKEN_FILE")

if [ -z "$REFRESH_TOKEN" ] || [ -z "$CLIENT_ID" ]; then
  echo "No refresh_token or client_id in token file — running full login flow"
  exec bash "$(dirname "$0")/login.sh"
fi

TOKEN_RESP=$(curl -sf "$BASE/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=refresh_token&client_id=${CLIENT_ID}&refresh_token=${REFRESH_TOKEN}")

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Refresh failed — running full login flow"
  exec bash "$(dirname "$0")/login.sh"
fi

NEW_REFRESH=$(echo "$TOKEN_RESP" | jq -r '.refresh_token // empty')
EXPIRES_IN=$(echo "$TOKEN_RESP" | jq -r '.expires_in')
SCOPE_VAL=$(echo "$TOKEN_RESP" | jq -r '.scope')
WALLET=$(echo "$ACCESS_TOKEN" | cut -d: -f1)
EXPIRES_AT=$(($(date +%s) + EXPIRES_IN))

# Preserve existing fields, update access_token, refresh_token, expires_at
jq \
  --arg access_token "$ACCESS_TOKEN" \
  --arg refresh_token "${NEW_REFRESH:-$REFRESH_TOKEN}" \
  --arg wallet "$WALLET" \
  --arg scope "$SCOPE_VAL" \
  --argjson expires_at "$EXPIRES_AT" \
  '. + {access_token: $access_token, refresh_token: $refresh_token, wallet: $wallet, scope: $scope, expires_at: $expires_at}' \
  "$TOKEN_FILE" > "${TOKEN_FILE}.tmp" && mv "${TOKEN_FILE}.tmp" "$TOKEN_FILE"

chmod 600 "$TOKEN_FILE"

echo "Token refreshed for $WALLET"
echo "Expires: $(date -d @$EXPIRES_AT 2>/dev/null || date -r $EXPIRES_AT 2>/dev/null || echo "in ${EXPIRES_IN}s")"
