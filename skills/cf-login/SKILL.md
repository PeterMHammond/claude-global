---
name: cf-login
description: Set up per-project, single-account Cloudflare wrangler login isolation for the current Workers repo — a scripts/wrangler.sh wrapper with a private .wrangler-home store, the gitignore entry, the CLAUDE.md rule, and a whoami check. Use on /cf-login, when a deploy says "Not logged in" or "authentication error [code 10000]", when logging into one project broke another's deploy, or when adopting a new Workers project. Never run bare `npx wrangler login` — that writes the machine-wide store every project shares.
---

# cf-login

One Cloudflare login per project, scoped to one account. `~/.config/.wrangler` holds a single OAuth
token for the whole machine; a login for project A overwrites project B's. The fix is a wrapper that
points wrangler's `XDG_CONFIG_HOME` at `<repo>/.wrangler-home` — the login lives with the project.

## Steps

1. `bash ~/.claude/skills/cf-login/scripts/setup.sh` from inside the repo. Idempotent. It installs
   `scripts/wrangler.sh` (skips an existing wrapper), ignores `.wrangler-home/`, appends the deploy
   rule to `CLAUDE.md`, and reports `login: OK <account>` or `login: NONE`.
2. On `login: NONE`, hand the user the one interactive step and stop — the browser callback is theirs:
   `! scripts/wrangler.sh login` — and tell them to choose ONLY this project's account on the consent
   screen; that picker is what scopes the token to one account.
3. When they say it is done, `scripts/wrangler.sh whoami` and report the account name it prints.
4. Commit the wrapper, `.gitignore` and `CLAUDE.md` with the project's commit convention (loadout and
   craft: `🔧 config: …` via /commit).

## Rules

- Every wrangler invocation in that project is `scripts/wrangler.sh …` from then on — deploy, tail,
  kv, secrets. Bare `npx wrangler` re-introduces the shared store.
- A project that already has a wrapper keeps it; the setup script detects `XDG_CONFIG_HOME=` and
  leaves it alone.
- If a login for another project was just made bare (`npx wrangler login`), copy it rather than
  redoing it: `cp -p ~/.config/.wrangler/config/default.toml <repo>/.wrangler-home/.wrangler/config/`
  (create the directory first). Only when that login was made for THIS project's account.
- Never read or print the token file; `whoami` is the only inspection.
