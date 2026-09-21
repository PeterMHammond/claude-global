---
name: creator-api
description: Authenticate with and use the Creator API (content authoring on Cloudflare Workers) including the v2 session API for interactive StorySession testing. Triggers on /creator-login, /creator-api, or auto-detects when Creator API calls are needed.
---

# Creator API

Creator is the authoring backend for the Codex content marketplace at `creator.everygoodwork.io`. Full CRUD + publish via OAuth Bearer tokens.

## Authentication

Tokens are stored **per wallet** at `~/.creator/wallets/{wallet}.json`.
Named profiles live in `~/.creator/profiles.json`.
`~/.creator/token.json` always reflects the last-used wallet (backward compat).

### Known Profiles

| Profile | Wallet | Use for |
|---------|--------|---------|
| `cloudflare-chronicles` | `0x1C1Ee78b938Af5333D3a99BF659e9aa771d8A8D5` | Cloudflare Chronicles technical blog |
| `creator` | `0x3E370228B215d8baa9008a60Cc29F185375480D0` | Main creator account |
| `codex` | `0xd328e037E202aF43200829D89d9D6cDBC61c5Fd0` | Codex/personal articles |

### Before any API call — login with the right profile

```bash
# Use a named profile (silent refresh if token cached, browser only if expired)
bash ~/.claude/skills/creator-api/scripts/login.sh cloudflare-chronicles

# Or by wallet address directly
bash ~/.claude/skills/creator-api/scripts/login.sh 0x1C1Ee78b938Af5333D3a99BF659e9aa771d8A8D5

# Last-used wallet (no arg)
bash ~/.claude/skills/creator-api/scripts/login.sh
```

Read credentials after login:

```bash
# Determine which token to use
SCOPE="${CREATOR_TOKEN_SCOPE:-default}"
TOKEN_FILE="$HOME/.creator/tokens/$SCOPE.json"
[ ! -f "$TOKEN_FILE" ] && TOKEN_FILE="$HOME/.creator/token.json"

# Extract credentials
ACCESS_TOKEN=$(jq -r '.access_token' "$TOKEN_FILE")
WALLET=$(jq -r '.wallet' "$TOKEN_FILE")
BASE=$(jq -r '.base' "$TOKEN_FILE")
```

Or read directly from the per-wallet file:

```bash
TOKEN_FILE="$HOME/.creator/wallets/0x1C1Ee78b938Af5333D3a99BF659e9aa771d8A8D5.json"
ACCESS_TOKEN=$(jq -r '.access_token' "$TOKEN_FILE")
WALLET=$(jq -r '.wallet' "$TOKEN_FILE")
```

### Login — browser consent flow with automatic callback

Authentication requires Cloudflare Zero Trust. The script starts a localhost callback server, opens the browser to the consent page, catches the redirect automatically, and exchanges the code for a token. Silent refresh happens automatically when the token is cached — browser only opens if the refresh token is also expired.

Requires: bash, curl, openssl, jq, node (already present if Claude Code is installed)

```bash
bash ~/.claude/skills/creator-api/scripts/login.sh [profile-or-wallet]
```

The user sees "Authorized" in the browser and the token is stored automatically. No copy-pasting needed.

## API Reference

Base: `https://creator.everygoodwork.io/api/{wallet}/`

Every request needs: `-H "Authorization: Bearer $ACCESS_TOKEN"`

The `{wallet}` in the URL **must match** the wallet in the token. Mismatch = 403.

### Endpoints

| Operation | Method | Path | Body | Scope |
|-----------|--------|------|------|-------|
| Create | `POST` | `/api/{wallet}/` | JSON | write |
| Read | `GET` | `/api/{wallet}/{slug}` | none | read |
| Update | `PATCH` | `/api/{wallet}/{slug}` | JSON partial | write |
| Publish | `PUT` | `/api/{wallet}/{slug}` | none | publish |
| Expire | `DELETE` | `/api/{wallet}/{slug}` | none | publish |
| List | `GET` | `/api/{wallet}/` | none | read |
| Search | `GET` | `/api/search?q=` | none | read |

HTTP method IS the verb. No action strings in URLs.

### Create body

All fields required except `tags`, `hero_image`:

```json
{
  "title": "string",
  "slug": "kebab-case, ^[a-z0-9][a-z0-9-]*[a-z0-9]$, max 100",
  "type": "lesson|article|blog|howto|devotional|page|skill",
  "author": "string",
  "summary": "string",
  "body": "markdown string",
  "tags": ["optional", "array"],
  "hero_image": "optional string"
}
```

**Slug is permanent and must be written for bots, not humans.** The slug is the only thing crawlers, LLMs, and search indexes see in the URL. It cannot be changed after creation. Do NOT mirror a creative title — instead, describe the problem and resolution in natural language so it reads like a search query. The slug should tell a bot what question this content answers.

- Bad: `the-charset-that-wasnt-there` (narrative hook, meaningless to bots)
- Good: `how-to-fix-cloudflare-workers-charset-utf8-static-asset-headers` (describes the problem and fix)
- Good: `cloudflare-direct-upload-api-headers-config-not-working-fix` (reads like a search query)

### Update body (PATCH)

Any subset of create fields. Only included fields are updated.

### Content lifecycle

`POST` (draft) -> `PATCH` (update) -> `PUT` (publish) -> `DELETE` (expire)

### Billing

Wallet needs positive balance. Check: `GET /api/{wallet}/billing`. Deposit via `X-Payment` header:

```
X-Payment: {"amount":5000000,"tx_hash":"unique-id","network":"test"}
```

Amount in atomic USDC (6 decimals). 5000000 = $5.00.

### Error codes

| Code | Meaning |
|------|---------|
| 201 | Created |
| 200 | Success |
| 400 | Invalid slug or malformed request |
| 401 | Missing/invalid token — run login flow |
| 402 | Insufficient balance |
| 403 | Token wallet != URL wallet |
| 409 | Slug already exists |
| 404 | Not found |

---

## V2 Session API — Interactive StorySession Testing

The v2 session API gives programmatic access to the same StorySession DO that powers the v2 UI. Send slash commands, natural language intents, or direct tree actions — and get structured JSON responses instead of SSE/Datastar patches.

This is the primary tool for end-to-end testing of the AI-native editor.

### Endpoints

| Operation | Method | Path | Body | Scope |
|-----------|--------|------|------|-------|
| Status | `GET` | `/api/{wallet}/editor_v2/{content_id}/status` | none | read |
| Action | `POST` | `/api/{wallet}/editor_v2/{content_id}/action` | Signal JSON | write |

### Signal body (POST action)

```json
{
  "content": "markdown body (optional — document content to sync)",
  "input": "user text (optional — slash command or natural language)",
  "action": "tree_action_name (optional — direct action bypass)",
  "args": {}
}
```

**Three ways to interact:**
1. **Slash commands** via `input`: `/save`, `/publish`, `/title My Title`, etc.
2. **Natural language** via `input`: `"please save"`, `"what can I do?"`, etc. (routed through AI intent detection)
3. **Direct tree actions** via `action`: `"checkpoint_content"`, `"enter_publishing"`, etc. (bypasses slash/AI parsing)

Always include `content` when saving — it's the document body that gets persisted.

### SignalResult response

```json
{
  "state": "idle|writing|dictating|publish.verifying|publish.confirming|publish.executing",
  "doc_version": 2,
  "saved": false,
  "published": false,
  "save_rejected": false,
  "ai_response": "AI-generated text or null",
  "pub_title": "Current publish title or null",
  "pub_slug": "current-publish-slug or null"
}
```

### Status response

```json
{
  "state": "idle",
  "active_states": ["root", "root.session", "root.session.idle"],
  "connected_clients": 0,
  "buffer_bytes": 440,
  "stt_active": false,
  "transcript_blocks": 0
}
```

### Discovering available commands

Commands are dynamic — defined on the state tree, not hardcoded. Use these to discover what's available:

- **`/help`** — returns slash commands available in the current state
- **`/diag`** — framework diagnostics: state, context fields, SQLite tables, available actions, DO extras
- **`/diag sqlite:<table>`** — inspect a specific SQLite table (tables listed in `/diag` output)

**`/new`** is browser-only (client-side redirect). API equivalent: generate a fresh UUIDv7 content_id.

### Evaluators (auto-derived metadata)

When in `publish.verifying`:
- **Slug** auto-derives from title (kebab-case) if not explicitly set
- **Summary** auto-derives from first sentence of content if not explicitly set
- **Dirty detection** uses FNV-1a hash — content changes are detected automatically

### Dynamic E2E test script

Run with `bash ~/.claude/skills/creator-api/scripts/e2e.sh`.

It discovers commands dynamically via `/diag` and `/help` per state, so new commands and states are automatically covered. The script tests 8 phases:

1. **Session init** — fresh CID auto-initializes to idle
2. **`/diag`** — diagnostics return State, Available actions, SQLite tables, DO extras
3. **`/help`** — discovers commands per state (count validated, not hardcoded list)
4. **Content lifecycle** — `/save` with content, REST read-back, no-change rejection, direct action
5. **Publish flow** — `/publish` → `/title` → `/slug` → `/summary` → `/confirm` → `/back` → `/write`, with `/diag` and `/help` discovery at each state
6. **Natural language** — AI intent detection responds to free-text
7. **Unknown command** — graceful error for invalid `/commands`
8. **`/diag sqlite:`** — table inspection

To regenerate after code changes: just run `bash /tmp/creator-e2e.sh` — it creates a fresh content_id, runs all phases, and cleans up.
