---
name: codex-run
description: Execute sandboxed JS workers on Codex with scoped capability bindings. Replaces codex-api. Triggers on /codex-run or when user asks to interact with Codex content programmatically.
---

# Codex Run

Execute sandboxed JavaScript workers on Codex via Dynamic Workers. One invocation replaces N API calls.

## Authentication

Tokens stored per wallet at `~/.codex/wallets/{wallet}.json`.
`~/.codex/token.json` always reflects the last-used wallet.

### Before any Gateway call — always run login first

**ALWAYS run this automatically. Do NOT prompt the user.** Silent refresh if token is valid/refreshable. Browser only if both tokens expired.

```bash
bash ~/.claude/skills/codex-run/scripts/login.sh
```

Read credentials after login:

```bash
TOKEN_FILE="$HOME/.codex/token.json"
ACCESS_TOKEN=$(jq -r '.access_token' "$TOKEN_FILE")
WALLET=$(jq -r '.wallet' "$TOKEN_FILE")
```

## How It Works

1. Write a JS worker that composes capability bindings to accomplish the user's task
2. Declare the minimum capabilities needed
3. Submit to `POST /run` on `https://codex.everygoodwork.io`
4. The Gateway validates the token, enforces scopes, sandboxes the code in a V8 isolate, and returns the result

## Submitting a Worker

```bash
curl -s -X POST "https://codex.everygoodwork.io/run" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "<worker source>",
    "capabilities": ["Content:list", "Status:get"]
  }'
```

Response: `{ "ok": true, "result": <whatever the worker returned> }` or `{ "ok": false, "error": "message" }`.

## Worker Script Pattern

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    // Compose capability bindings to accomplish the task
    return { /* results */ };
  }
}
```

## Available Capability Bindings

### Content (scoped to authenticated wallet)

All `Content.*` methods call the Wallet DO's RPC surface directly — no HTTP bounce. Returns are typed native JS objects; errors surface real `worker::Error` messages.

| Method | Capability | Description |
|--------|-----------|-------------|
| `this.env.Content.list()` | `Content:list` | List all content items. Returns `{items: [ContentEntry]}`. |
| `this.env.Content.get(slug)` | `Content:get` | Read full document. Returns `{slug, title, type, status, author, summary, version, created, updated, tags, hero_image, price, body}`. |
| `this.env.Content.create(doc)` | `Content:create` | Create new content `{title?, body?, type?, tags?, summary?, price?}`. Meta and body commit atomically. Returns `{slug, title, status, version, price}`. |
| `this.env.Content.update(slug, patch)` | `Content:update` | Partial update `{title?, body?, summary?, tags?, price?}` — meta and body commit atomically (codex#73 fixed by construction). Returns `{slug, title, status, version, price}`. |
| `this.env.Content.delete(slug)` | `Content:delete` | Permanent delete (auto-confirmed). Returns `{slug, purged, objects_deleted}`. |
| `this.env.Content.publish(slug)` | `Content:publish` | Publish — emits marketplace queue message. Returns `{slug, status: "published"}`. |
| `this.env.Content.expire(slug)` | `Content:expire` | Unpublish — emits marketplace queue message. Returns `{slug, status: "expired"}`. |
| `this.env.Content.redeemPromo(code)` | `Content:redeemPromo` | Redeem promo code — lookup + redeem + deposit, atomic. Returns `{success, seed_amount, balance, error}`. |

### Status

| Method | Capability | Description |
|--------|-----------|-------------|
| `this.env.Status.get()` | `Status:get` | Balance, billing, content count |
| `this.env.Status.rename(name)` | `Status:rename` | Update display name |

### Manage (requires manage-scoped token)

| Method | Capability | Description |
|--------|-----------|-------------|
| `this.env.Manage.deposit(amount, refHash, memo)` | `Manage:deposit` | Deposit funds |
| `this.env.Manage.drain(amount?)` | `Manage:drain` | Drain funds (null = drain all) |
| `this.env.Manage.redeemPromo(code)` | `Manage:redeemPromo` | Redeem promo (manage-scoped) — atomic lookup + redeem + deposit |
| `this.env.Manage.createPromo(code, label, seedAmount, maxUses)` | `Manage:createPromo` | Create promo code |
| `this.env.Manage.deactivatePromo(code)` | `Manage:deactivatePromo` | Deactivate promo code |

### Gift

| Method | Capability | Description |
|--------|-----------|-------------|
| `this.env.Gift.list()` | `Gift:list` | List gift vouchers (local purchase receipts) |
| `this.env.Gift.create(contentId, uses, opts?)` | `Gift:create` | Create gift voucher `{gift_name?, voucherid?}` |
| `this.env.Gift.refill(voucherId, additionalUses)` | `Gift:refill` | Top up existing voucher uses |
| `this.env.Gift.delete(voucherId)` | `Gift:delete` | Delete a gift voucher (no refund) |

### AI

| Method | Capability | Description |
|--------|-----------|-------------|
| `this.env.AI.run(model, input)` | `AI` | Workers AI inference |

## Scope-to-Capability Mapping

Token scopes are cumulative. `write` includes `read`. `publish` includes `write`. `manage` includes everything.

| Token Scope | Capabilities |
|-------------|-------------|
| `read` | Content:list, Content:get, Content:redeemPromo, Status:get |
| `write` | + Content:create, Content:update, Status:rename, Gift:list, Gift:create, Gift:refill, Gift:delete |
| `publish` | + Content:delete, Content:publish, Content:expire |
| `manage` | + all Manage:* bindings |

## Writing Worker Code

**Key rules:**
- Always `import { WorkerEntrypoint } from "cloudflare:workers"` and export default class extending it
- Access bindings via `this.env` (not just `env`)
- The `run()` method takes no arguments — all context comes from bindings
- Return a plain object — it becomes the `result` field in the response
- Errors throw and return as `{ "ok": false, "error": "message" }`
- Declare the MINIMUM capabilities needed — the Gateway rejects over-requesting
- Title must be set before calling `publish()`

## Examples

### List published content
```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const { items } = await this.env.Content.list();
    return items.filter(i => i.status === "published");
  }
}
// capabilities: ["Content:list"]
```

### Create and publish an article
```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const created = await this.env.Content.create({
      title: "My Article",
      body: "# Hello\n\nContent goes here.",
      type: "article"
    });
    await this.env.Content.publish(created.content_id);
    return { published: created.content_id };
  }
}
// capabilities: ["Content:create", "Content:publish"]
```

### Batch update all drafts with AI summaries
```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const { items } = await this.env.Content.list();
    const drafts = items.filter(i => i.status === "draft");
    const results = [];
    for (const d of drafts) {
      const doc = await this.env.Content.get(d.content_id);
      const ai = await this.env.AI.run("@cf/meta/llama-3.1-8b-instruct", {
        messages: [{ role: "user", content: `Summarize in one sentence: ${doc.body}` }]
      });
      await this.env.Content.update(d.content_id, { summary: ai.response });
      results.push({ title: d.title, summary: ai.response });
    }
    return { updated: results.length, results };
  }
}
// capabilities: ["Content:list", "Content:get", "Content:update", "AI"]
```

### Create a gift voucher for published content
```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const { items } = await this.env.Content.list();
    const published = items.find(i => i.status === "published");
    if (!published) return { error: "No published content" };
    const gift = await this.env.Gift.create(published.content_id, 5, {
      gift_name: "Share with friends"
    });
    return { content_id: published.content_id, ...gift };
  }
}
// capabilities: ["Content:list", "Gift:create"]
```
