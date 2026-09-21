#!/usr/bin/env bash
# Loadout Run login — prints setup instructions if ~/.loadout/token.json is
# missing, otherwise reports the active identity. Unlike codex-run, there's
# no PKCE flow: Cloudflare Access service tokens don't expire until you
# revoke them, so this script never contacts the network.

set -euo pipefail

LOADOUT_DIR="${HOME}/.loadout"
TOKEN_FILE="${LOADOUT_DIR}/token.json"

mkdir -p "$LOADOUT_DIR"

if [[ -f "$TOKEN_FILE" ]]; then
  BASE=$(jq -r '.base // empty' "$TOKEN_FILE")
  CLIENT_ID=$(jq -r '.client_id // empty' "$TOKEN_FILE")
  CLIENT_SECRET=$(jq -r '.client_secret // empty' "$TOKEN_FILE")

  if [[ -n "$BASE" && -n "$CLIENT_ID" && -n "$CLIENT_SECRET" ]]; then
    echo "Loadout Run token present."
    echo "  base:      $BASE"
    echo "  client_id: ${CLIENT_ID:0:12}… (len=${#CLIENT_ID})"
    echo "  secret:    (redacted, len=${#CLIENT_SECRET})"
    exit 0
  fi

  echo "WARNING: $TOKEN_FILE exists but is missing one or more of base / client_id / client_secret." >&2
fi

cat <<'EOF' >&2
No Loadout Run token configured.

Loadout Run uses Cloudflare Access service tokens, not OAuth. Follow these
steps once (no expiry, no refresh):

  1. Go to the Cloudflare dashboard:
     https://one.dash.cloudflare.com → Zero Trust → Access → Service Auth

  2. Click "Create Service Token".
     - Name it something recognisable (e.g. "loadout-run — peter-laptop").
     - Duration: "Non-expiring" (unless your org policy mandates rotation).

  3. Copy the Client ID (ends with ".access") and Client Secret.

  4. Grant the service token access to the /run application. In the
     dashboard → Zero Trust → Access → Applications → loadout-run →
     Policies, add a policy:
       Action: Service Auth
       Include: Service Token → <the one you just created>

  5. Save the credentials into ~/.loadout/token.json:

     cat > ~/.loadout/token.json <<'JSON'
     {
       "base":          "https://loadout.cowelltactical.com",
       "client_id":     "<paste Client ID>",
       "client_secret": "<paste Client Secret>"
     }
     JSON
     chmod 600 ~/.loadout/token.json

  6. Re-run this script to confirm.

Once ~/.loadout/token.json exists, every loadout-run call uses it
automatically via the CF-Access-Client-Id / CF-Access-Client-Secret
headers. To rotate, delete the old token in the dashboard and rewrite
the file.
EOF

exit 1
