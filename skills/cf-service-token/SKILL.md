---
name: cf-service-token
description: Store, prove, rotate, and load Cloudflare Access service tokens (CF-Access-Client-Id/Secret) per app in the GNOME login keyring, for any project. Use on /cf-service-token, when a script needs an Access token, when an Access-gated fetch returns a 302 to cloudflareaccess.com or an "empty" result, when adding or rotating a service token, or when a project still keeps one in a plaintext .env file.
---

# cf-service-token

One keyring entry per app (`service=cf-service-token app=<app>`, keys `client_id` `client_secret` `url`). The
script is both the CLI and the loader: `~/.claude/skills/cf-service-token/scripts/cf-token.sh`.

## Set or rotate — the user runs it, never you

It prompts with hidden input via `/dev/tty`, proves the pair with a GET of the url (only a 200 counts), and stores
nothing on failure. Hand the user the command and wait; never ask for the secret in the conversation. #override

```bash
bash ~/.claude/skills/cf-service-token/scripts/cf-token.sh set <app> https://<host>/<access-gated-path>
bash ~/.claude/skills/cf-service-token/scripts/cf-token.sh set <app>     # rotation reuses the stored url
```

Pick a url the Access app protects and that answers 200 to a valid token (a board page, not an `/agent` POST door).
The token itself comes from Zero Trust → Access → Service Auth → Service Tokens, and must be on the app's Service
Auth policy.

## Check, list, remove — safe for you to run

```bash
bash ~/.claude/skills/cf-service-token/scripts/cf-token.sh check <app>   # ✔ on 200; ✘ + rotate hint otherwise
bash ~/.claude/skills/cf-service-token/scripts/cf-token.sh list          # apps + urls, never secrets
```

Access answers a bad token with a **302 to its login page, not a 401**. A scraper that greps the body reads that as
"nothing there". Run `check` before trusting any empty result from an Access-gated fetch.

## Load it in a project script

```bash
[[ -n "${CF_ACCESS_CLIENT_ID:-}" && -n "${CF_ACCESS_CLIENT_SECRET:-}" ]] || { . "$HOME/.claude/skills/cf-service-token/scripts/cf-token.sh" && cf_token <app>; } || exit 1
```

`cf_token` sets `CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` without exporting them. The leading guard lets a
cloud session that injects the pair as env vars run without this skill installed. Send the secret with
`-H @<(printf 'CF-Access-Client-Secret: %s\n' "$CF_ACCESS_CLIENT_SECRET")` so it stays out of `ps`.

## Migrating a plaintext token

Replace the project's `. ~/.foo.env` block with the loader line above, have the user run `set`, then `check`, then
tell them the plaintext file can be shredded (`shred -u`). Don't delete it yourself.
