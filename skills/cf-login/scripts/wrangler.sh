#!/usr/bin/env bash
# Wrangler against THIS project's Cloudflare login, not the machine-wide one. `wrangler login` writes
# ONE OAuth token into ~/.config/.wrangler, so logging in for any other project silently takes this
# project's access with it (auth error 10000). XDG_CONFIG_HOME is the variable wrangler honours.
# Log in once with: scripts/wrangler.sh login  — and pick ONLY this project's account on the consent screen.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec env XDG_CONFIG_HOME="$REPO/.wrangler-home" npx wrangler "$@"
