#!/usr/bin/env bash
# Craft Agent login — prints setup instructions if ~/.craft/token.json is
# missing, otherwise reports the active identity. Mirrors loadout-run and
# watchman-run: Cloudflare Access service tokens don't expire until you
# revoke them, so this script never contacts the network.

set -euo pipefail

CRAFT_DIR="${HOME}/.craft"
TOKEN_FILE="${CRAFT_DIR}/token.json"

mkdir -p "$CRAFT_DIR"

if [[ -f "$TOKEN_FILE" ]]; then
  BASE=$(jq -r '.base // empty' "$TOKEN_FILE")
  CLIENT_ID=$(jq -r '.client_id // empty' "$TOKEN_FILE")
  CLIENT_SECRET=$(jq -r '.client_secret // empty' "$TOKEN_FILE")

  if [[ -n "$BASE" && -n "$CLIENT_ID" && -n "$CLIENT_SECRET" ]]; then
    echo "Craft Agent token present."
    echo "  base:      $BASE"
    echo "  client_id: ${CLIENT_ID:0:12}… (len=${#CLIENT_ID})"
    echo "  secret:    (redacted, len=${#CLIENT_SECRET})"
    exit 0
  fi

  echo "WARNING: $TOKEN_FILE exists but is missing one or more of base / client_id / client_secret." >&2
fi

cat <<'EOF' >&2
No Craft Agent token configured.

Craft Agent uses Cloudflare Access service tokens, not OAuth. Follow these
steps once (no expiry, no refresh):

  1. Go to the Cloudflare dashboard:
     https://one.dash.cloudflare.com → Zero Trust → Access → Service Auth

  2. Click "Create Service Token".
     - Name it something recognisable (e.g. "craft-agent — peter-laptop").
     - Duration: "Non-expiring" (unless your org policy mandates rotation).

  3. Copy the Client ID (ends with ".access") and Client Secret. You won't
     see the secret again — copy now.

  4. Grant the service token access to the craft.everygoodwork.dev
     application. Zero Trust → Access → Applications → craft → Policies →
     add a policy:
       Action: Service Auth
       Include: Service Token → <the one you just created>

  5. Save the credentials into ~/.craft/token.json:

     cat > ~/.craft/token.json <<'JSON'
     {
       "base":          "https://craft.everygoodwork.dev",
       "client_id":     "<paste Client ID>",
       "client_secret": "<paste Client Secret>"
     }
     JSON
     chmod 600 ~/.craft/token.json

  6. Re-run this script to confirm.

Once ~/.craft/token.json exists, every craft-agent call uses it
automatically via the CF-Access-Client-Id / CF-Access-Client-Secret
headers. To rotate, delete the old token in the dashboard and rewrite
the file.
EOF

exit 1
