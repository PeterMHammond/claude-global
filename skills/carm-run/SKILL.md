---
name: carm-run
description: Execute sandboxed JS workers on carm-editor's Dynamic Workers gateway. One invocation composes N PageDO RPC calls atomically inside Cloudflare. Triggers on /carm-run or when the user asks to automate, seed, or batch-edit carm-editor articles by slug.
---

# Carm Run

Execute sandboxed JavaScript workers on carm-editor via `POST /run`. Each worker script composes one or more `Page` binding methods — each of which is a thin wrapper over a real `PageDO` RPC — in a single atomic execution inside Cloudflare.

**This is staff-only.** The endpoint sits behind Cloudflare Access on `edit.carm.org/run`. Customers never touch it.

## Authentication

Cloudflare Access **service tokens** are the script-friendly auth path. A service token is a pair of long strings (Client ID + Client Secret) issued in the Cloudflare dashboard (Zero Trust → Access → Service Auth). It never expires on its own; revoke it in the dashboard to invalidate.

Credentials live at `~/.carm-editor/token.json`:

```json
{
  "base": "https://edit.carm.org",
  "client_id": "<uuid>.access",
  "client_secret": "<long-random-string>"
}
```

### Before any Gateway call — always run login first

```bash
bash ~/.claude/skills/carm-run/scripts/login.sh
```

The script prints setup instructions if no token is saved, and prints the active identity if one is. It never contacts the network — service tokens don't need refresh.

Read credentials after login:

```bash
TOKEN_FILE="$HOME/.carm-editor/token.json"
BASE=$(jq -r '.base' "$TOKEN_FILE")
CLIENT_ID=$(jq -r '.client_id' "$TOKEN_FILE")
CLIENT_SECRET=$(jq -r '.client_secret' "$TOKEN_FILE")
```

## How It Works

1. Write a JS worker that composes `Page` binding methods to accomplish the user's task.
2. Declare the minimum capabilities needed.
3. Submit to `POST /run` on the configured base URL.
4. The gateway decodes the CF Access JWT, enforces the capability allowlist, sandboxes the code in a V8 isolate, and returns the result.

## Submitting a Worker

```bash
curl -s -X POST "${BASE}/run" \
  -H "CF-Access-Client-Id: ${CLIENT_ID}" \
  -H "CF-Access-Client-Secret: ${CLIENT_SECRET}" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "<worker source>",
    "capabilities": ["Page:get", "Page:update"]
  }'
```

Response: `{ "ok": true, "result": <whatever the worker returned> }` or `{ "ok": false, "error": "message" }`.

## Worker Script Pattern

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    // Compose Page binding methods to accomplish the task.
    // Each method takes the article slug as its first argument.
    return { /* results */ };
  }
}
```

## Available Capability Bindings

Two tiers — `Catalog` for D1-backed catalog reads (no DO involvement, fast existence checks), `Page` for per-article DO operations (full version-history surface). The **authoritative list** lives in `carm-editor/entry.js` (`SCOPE_CAPS.staff`).

### Catalog — D1 articles catalog

The `Catalog` binding mirrors the same D1 SQL the site's HTTP routes already run. Use it to find out *whether* a slug exists before reaching for `Page:*` — calling Page methods on a nonexistent slug materializes a (dead) DO, which Catalog avoids entirely.

| Method | Capability | Notes |
|--------|------------|-------|
| `Catalog.lookup(slug)` | `Catalog:lookup` | Returns `{slug, title, status} \| null`. Single D1 row. Mirrors `routes/index.rs:43-46`. |
| `Catalog.list({status, limit, offset, from, until, date_column})` | `Catalog:list` | Returns an array of `{slug, title, status, created_at, updated_at}`. Defaults: `status="draft"`, `limit=20`, `offset=0`, `date_column="created_at"`. Pass `status: null` for all statuses. `limit` capped at 200. **Date range:** pass `from` and/or `until` (ISO date / datetime strings — TEXT columns sort lexicographically, so ISO 8601 just works). `date_column` selects which column to filter and order by — only `"created_at"` or `"updated_at"` accepted (both indexed). |

### Page — keyed by article slug

The `Page` binding is keyed by the article's URL slug (e.g. `"what-is-christian-apologetics"`). The DO is materialized lazily on first access.

| Method | Capability | Notes |
|--------|------------|-------|
| `Page.get(slug, version?)` | `Page:get` | Returns `{article, has_been_published} | null`. Omit `version` (or pass `null`) for the latest; pass an integer for that specific historical snapshot. |
| `Page.create(slug, input)` | `Page:create` | Returns `{outcome: "created", slug, version} \| {outcome: "already_exists"}`. `input` shape: `{title, content}`. |
| `Page.update(slug, input)` | `Page:update` | Returns `{slug, version, word_count, versions[]}`. `input` shape: `{article: <Article>}`. The `article` payload follows the full `Article` struct (see `src/models/article.rs`). |
| `Page.publish(slug, input)` | `Page:publish` | Returns `{slug, published_version, versions[]}`. `input` shape: `{version: number \| null}`. `null` publishes the latest draft. |
| `Page.unpublish(slug)` | `Page:unpublish` | Removes the article from public surfaces (KV `WEBSITE`, Vectorize index, `featured-content` rotation) and appends an `"unpublished"` audit row to the version history. Reversible via `publish`. |
| `Page.preview(slug)` | `Page:preview` | Materializes a 7-day preview snapshot of the latest draft to KV under `<slug>-preview`. Returns `{slug, preview_url, expires_at}`. `Page:update` already writes this key implicitly on every save — call this only after `Page:create` (which writes no preview) or to refresh an expiring preview without editing content. The `preview_url` is `https://carm.org/<slug>-preview`. |

**Audit-trail actor** — every method that records an actor (`update`, `create`, `publish`, `unpublish`) auto-stamps the audit row with `"Claude"` (the canonical audit name for /run automation). Scripts cannot pass or override `user_email`; whatever a script puts in that field is replaced. Browser SSO writes go through HTTP routes (not /run) and use the staff email instead.

### Vectors — Vectorize semantic search

The `Vectors` binding wraps Workers AI (BGE-base-en-v1.5, same model used at index-write time) plus the `website_bge-base-en-v1_5` Vectorize index. It mirrors `cf_extras.rs:VectorizeService::search` — embed the query, then query the index — but exposes it through /run instead of forcing a separate HTTP route.

| Method | Capability | Notes |
|--------|------------|-------|
| `Vectors.search(query, {topK})` | `Vectors:search` | Returns `[{id, score, slug, title, summary}, ...]` sorted by score descending. `topK` defaults to 5, capped at 50. **Raw matches** — Vectorize may return slugs that have since been deleted or unpublished; cross-check via `Catalog.lookup` if your workflow needs guaranteed-live results. |

### Article struct (input/output shape)

The `article` field in `update` input (and the `article` field inside an `ArticleWithStatus` response) matches the full `Article` struct:

```javascript
{
  id: "<ULID>",                  // optional on create
  version: 1,                    // u16
  slug: "what-is-...",           // URL slug
  title: "...",                  // article title
  content: "<p>...</p>",         // HTML body
  created_at: "2020-05-15 14:30:00",
  updated_at: "2026-05-04 12:00:00",
  published: "2020-05-15 14:30:00",
  updated_by: "matt.slick",
  url: "https://carm.org/...",
  image_url: "/path/to/img.jpg",
  image_alt: "...",
  author_name: "Matt Slick",
  author_info: "...",
  word_count: 1234,
  // OpenGraph fields: og_title, og_description, og_url, og_image, og_type, og_site_name
  // ...see src/models/article.rs for the complete field list
}
```

Most fields default to empty strings on the Rust side; only `slug`, `title`, and `content` are practically required for a viable article. Word count is recomputed server-side on update.

### `versions[]` shape (returned by update / publish)

```javascript
[
  { number: 3, updated_by: "matt.slick", updated_at: "2026-05-04 12:00:00", status: "draft" },
  { number: 2, updated_by: "matt.slick", updated_at: "2026-05-04 11:00:00", status: "published" },
  { number: 1, updated_by: "matt.slick", updated_at: "2026-05-04 10:00:00", status: "draft" }
]
```

Newest first. `status` is `"draft"` or `"published"`. Times are UTC strings — caller is responsible for any locale conversion.

## Scope-to-Capability Mapping

Only the `staff` scope exists today. All staff get every capability; non-staff callers are rejected at the CF Access layer before any /run code runs.

## Writing Worker Code

**Key rules:**
- Always `import { WorkerEntrypoint } from "cloudflare:workers"` and export default class extending it
- Access bindings via `this.env` (not just `env`)
- The `run()` method takes no arguments — all context comes from bindings
- Return a plain object — it becomes the `result` field in the response
- Errors throw and return as `{ "ok": false, "error": "message" }`
- Declare the MINIMUM capabilities needed — the gateway rejects over-requesting
- Every RPC you call runs in the carm-editor Worker, not in the sandbox, so they count toward the parent Worker's CPU budget. Keep scripts tight.
- The `Page` binding is keyed by **slug**, not article id. The DO name IS the slug.

## Examples

### Check whether a slug exists (no DO touched)

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const row = await this.env.Catalog.lookup("gospel");
    return row;   // { slug: "gospel", title: "The Gospel", status: "published" } | null
  }
}
// capabilities: ["Catalog:lookup"]
```

### Site-equivalent safe read (Catalog gate then Page read)

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const slug = "gospel";
    const cat = await this.env.Catalog.lookup(slug);
    if (!cat) return { found: false };
    const r = await this.env.Page.get(slug);
    return { found: true, catalog: cat, version: r.article.version, title: r.article.title };
  }
}
// capabilities: ["Catalog:lookup","Page:get"]
```

### List the latest 10 drafts

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    return await this.env.Catalog.list({ limit: 10 });
    // → [{slug, title, status, created_at, updated_at}, ...]
  }
}
// capabilities: ["Catalog:list"]
```

### Articles created in a date range

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    return await this.env.Catalog.list({
      status: "published",
      from: "2026-04-01",
      until: "2026-04-30",
      date_column: "created_at",
      limit: 100,
    });
  }
}
// capabilities: ["Catalog:list"]
```

Filter by `updated_at` instead by passing `date_column: "updated_at"` — useful for "what changed last week" reports. Bounds are inclusive on both ends; omit `from` or `until` for an open-ended range.

### Semantic search — find articles related to a topic

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const results = await this.env.Vectors.search(
      "what does the Bible teach about the Trinity",
      { topK: 5 }
    );
    return results;
    // → [{id, score, slug, title, summary}, ...]
  }
}
// capabilities: ["Vectors:search"]
```

### Semantic search + catalog cross-check (drop stale slugs)

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const matches = await this.env.Vectors.search("apologetics method", { topK: 10 });
    const live = await Promise.all(matches.map(async (m) => {
      if (!m.slug) return null;
      const cat = await this.env.Catalog.lookup(m.slug);
      return cat?.status === "published" ? { ...m, catalog: cat } : null;
    }));
    return live.filter(Boolean);
  }
}
// capabilities: ["Vectors:search", "Catalog:lookup"]
```

> ⚠️ **Caveat — D1 partial-index state.** Until the production article import is complete, the D1 `articles` table only holds *new* articles authored through the editor. Legacy articles (the bulk of `carm.org`) live in KV `WEBSITE` and the Vectorize index, but **not** in D1. So `Catalog.lookup` returns `null` for those slugs even though they render fine on the public site, and this composition pattern will drop them as "stale." See the migration notes at the top of `src/page_data.rs` for the full plan; once the backfill runs, this caveat goes away. Until then, treat `Catalog.lookup` as a gate for *editor-authored* articles only — not as a source of truth for "is this article live?"

### Read the latest version of an article

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const article = await this.env.Page.get("what-is-christian-apologetics");
    if (!article) return { found: false };
    return {
      found: true,
      version: article.article.version,
      title: article.article.title,
      published: article.has_been_published,
      word_count: article.article.word_count,
    };
  }
}
// capabilities: ["Page:get"]
```

### Create a new article

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const result = await this.env.Page.create("test-article-slug", {
      title: "Test Article",
      content: "<p>Hello, world.</p>",
    });
    return result;
  }
}
// capabilities: ["Page:create"]
```

Returns `{outcome: "created", slug, version}` on success or `{outcome: "already_exists"}` if the slug is taken.

### Read → edit → save round-trip

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const slug = "what-is-christian-apologetics";
    const page = this.env.Page;

    const before = await page.get(slug);
    if (!before) return { error: "not found" };

    const updated = {
      ...before.article,
      content: before.article.content + "\n<p>Edit appended by carm-run.</p>",
    };

    const out = await page.update(slug, { article: updated });

    return {
      slug: out.slug,
      new_version: out.version,
      word_count: out.word_count,
      version_count: out.versions.length,
    };
  }
}
// capabilities: ["Page:get","Page:update"]
```

### Create → preview → publish (atomic /run workflow)

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const slug = "test-preview-flow";
    const page = this.env.Page;

    const created = await page.create(slug, {
      title: "Test Preview Flow",
      content: "<p>Draft body.</p>",
    });
    if (created.outcome !== "created") return { error: created.outcome };

    // Page.create writes no preview KV — materialize one now so a human
    // can review at https://carm.org/<slug>-preview before publish.
    const preview = await page.preview(slug);

    return {
      slug: created.slug,
      version: created.version,
      preview_url: preview.preview_url,
      expires_at: preview.expires_at,
    };
  }
}
// capabilities: ["Page:create","Page:preview"]
```

After a human approves the preview, run a follow-up worker with `Page:publish` to ship it.

### Publish the latest draft

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const out = await this.env.Page.publish("what-is-christian-apologetics", {
      version: null,                  // null = latest draft
    });
    return { published: out.published_version, history: out.versions };
  }
}
// capabilities: ["Page:publish"]
```

To publish a specific historical version, pass that version number instead of `null`.

### Audit script — list version history without mutating

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const slug = "what-is-christian-apologetics";
    const latest = await this.env.Page.get(slug);
    if (!latest) return { found: false };
    // Walk backwards through every version to gather authorship/timing.
    const history = [];
    for (let v = latest.article.version; v >= 1; v--) {
      const snap = await this.env.Page.get(slug, v);
      if (!snap) break;
      history.push({
        version: snap.article.version,
        updated_by: snap.article.updated_by,
        updated_at: snap.article.updated_at,
      });
    }
    return { slug, latest_version: latest.article.version, history };
  }
}
// capabilities: ["Page:get"]
```

Be careful: a deep history walks issue N round-trips inside the parent Worker, all counted against its CPU budget. Use versioned `Page:get` sparingly.

### Decoding base64 PDF/PNG payloads (when methods return them)

The current `PageBinding` surface returns plain JSON; no methods return binary payloads today. If a future binding adds one (e.g. a render-to-PDF method), the convention will mirror loadout-run: base64-encoded in the JSON response, decoded locally with:

```bash
jq -r '.result.pdfBase64' run-response.json | base64 -d > out.pdf
```

## Troubleshooting

- **`401 Cloudflare Access authentication required`** — the gateway didn't get a valid `Cf-Access-Jwt-Assertion`. Almost always means the service-token policy isn't attached to the `/run` Access app yet. Check Cloudflare dashboard → Zero Trust → Access → Applications → carm-editor.
- **`403 Capability "Page:foo" not permitted`** — typo in the capability string, or the method doesn't exist yet. Compare exact strings against `entry.js` `SCOPE_CAPS.staff`.
- **`502 Bad Gateway` with body `{ok: false, error: "..."}`** — the inner script threw. The error message is the exception's message; the full stack is in the carm-editor Worker logs (Cloudflare dashboard → Workers → carm-editor → Logs).
- **`SQL execution failed: no such table: articles`** — the slug's Page DO has never been initialized. Either you typo'd the slug, or this is genuinely a new article and you need `create` first (which seeds the schema).
- **`429 Rate limit exceeded`** — 60 calls per 60 seconds per identity. Wait or batch differently.
