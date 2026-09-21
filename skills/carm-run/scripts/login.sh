#!/usr/bin/env bash
# Carm Run login — prints setup instructions if ~/.carm-editor/token.json is
# missing, otherwise reports the active identity. Cloudflare Access service
# tokens don't expire until you revoke them, so this script never contacts
# the network.

set -euo pipefail

CARM_DIR="${HOME}/.carm-editor"
TOKEN_FILE="${CARM_DIR}/token.json"

mkdir -p "$CARM_DIR"

if [[ -f "$TOKEN_FILE" ]]; then
  BASE=$(jq -r '.base // empty' "$TOKEN_FILE")
  CLIENT_ID=$(jq -r '.client_id // empty' "$TOKEN_FILE")
  CLIENT_SECRET=$(jq -r '.client_secret // empty' "$TOKEN_FILE")

  if [[ -n "$BASE" && -n "$CLIENT_ID" && -n "$CLIENT_SECRET" ]]; then
    echo "Carm Run token present."
    echo "  base:      $BASE"
    echo "  client_id: ${CLIENT_ID:0:12}… (len=${#CLIENT_ID})"
    echo "  secret:    (redacted, len=${#CLIENT_SECRET})"
    exit 0
  fi

  echo "WARNING: $TOKEN_FILE exists but is missing one or more of base / client_id / client_secret." >&2
fi

cat <<'EOF' >&2
No Carm Run token configured.

Carm Run uses Cloudflare Access service tokens, not OAuth. Follow these
steps once (no expiry, no refresh):

  1. Go to the Cloudflare dashboard:
     https://one.dash.cloudflare.com → Zero Trust → Access → Service Auth

  2. Click "Create Service Token".
     - Name it something recognisable (e.g. "carm-run — peter-laptop").
     - Duration: "Non-expiring" (unless your org policy mandates rotation).

  3. Copy the Client ID (ends with ".access") and Client Secret.

  4. Grant the service token access to the /run path. In the
     dashboard → Zero Trust → Access → Applications → carm-editor →
     Policies, add a policy:
       Action: Service Auth
       Include: Service Token → <the one you just created>

     (If carm-editor's Access app currently protects the whole hostname,
     either add the service-token policy to the existing app, or split
     /run into its own Access application targeting the path
     `edit.carm.org/run` so customer/staff browser SSO is unaffected.)

  5. Save the credentials into ~/.carm-editor/token.json:

     cat > ~/.carm-editor/token.json <<'JSON'
     {
       "base":          "https://edit.carm.org",
       "client_id":     "<paste Client ID>",
       "client_secret": "<paste Client Secret>"
     }
     JSON
     chmod 600 ~/.carm-editor/token.json

  6. Re-run this script to confirm.

Once ~/.carm-editor/token.json exists, every carm-run call uses it
automatically via the CF-Access-Client-Id / CF-Access-Client-Secret
headers. To rotate, delete the old token in the dashboard and rewrite
the file.
EOF

exit 1
