#!/usr/bin/env bash
# Idempotent: install the per-project wrangler wrapper, ignore its store, pin the rule in CLAUDE.md,
# then report login state. Run from anywhere inside the repo.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not inside a git repo" >&2; exit 2; }
cd "$REPO"
[[ -f wrangler.toml || -f wrangler.jsonc || -f wrangler.json ]] || { echo "no wrangler config in $REPO — not a Workers project" >&2; exit 2; }

if [[ -f scripts/wrangler.sh ]] && grep -q 'XDG_CONFIG_HOME=' scripts/wrangler.sh; then
  echo "wrapper: scripts/wrangler.sh already present"
else
  mkdir -p scripts && cp "$HERE/wrangler.sh" scripts/wrangler.sh && chmod +x scripts/wrangler.sh
  echo "wrapper: installed scripts/wrangler.sh"
fi

if grep -qxF '.wrangler-home/' .gitignore 2>/dev/null; then
  echo "gitignore: .wrangler-home/ already ignored"
else
  printf '\n# Per-project wrangler OAuth store (scripts/wrangler.sh) — never commit a login.\n.wrangler-home/\n' >> .gitignore
  echo "gitignore: added .wrangler-home/"
fi

RULE='- Every wrangler command goes through `scripts/wrangler.sh` (deploy, tail, kv, secrets). Never bare `npx wrangler`: it uses the machine-wide login every project shares. Log in once with `scripts/wrangler.sh login`, choosing only this project'"'"'s account.'
if [[ -f CLAUDE.md ]] && grep -qF 'scripts/wrangler.sh' CLAUDE.md; then
  echo "CLAUDE.md: rule already present"
else
  printf '\n## Deploy\n\n%s\n' "$RULE" >> CLAUDE.md
  echo "CLAUDE.md: rule appended"
fi

# Report only — the login itself is interactive (browser + localhost callback) and is the user's step.
if out=$(scripts/wrangler.sh whoami 2>&1) && grep -q 'OAuth Token' <<<"$out"; then
  echo "login: OK"
  grep -E '│ [^│]+ │ [0-9a-f]{32} │' <<<"$out" | sed 's/^/login: /'
else
  echo "login: NONE — run:  ! scripts/wrangler.sh login   (pick only this project's account on the consent screen)"
fi
