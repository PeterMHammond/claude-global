---
name: loadout-run
description: Execute sandboxed JS workers on Loadout's Dynamic Workers gateway. One invocation composes N ProjectDO RPC calls atomically inside Cloudflare. Triggers on /loadout-run or when the user asks to automate, seed, or batch-edit loadout projects.
---

# Loadout Run

Execute sandboxed JavaScript workers on Loadout via `POST /run`. Each worker script composes one or more `Project` binding methods — each of which is a thin wrapper over a real `ProjectDO` RPC — in a single atomic execution inside Cloudflare.

**This is staff-only.** The endpoint sits behind Cloudflare Access on `loadout.cowelltactical.com/run`. Customers never touch it.

## Authentication

Cloudflare Access **service tokens** are the script-friendly auth path. A service token is a pair of long strings (Client ID + Client Secret) issued in the Cloudflare dashboard (Zero Trust → Access → Service Auth). It never expires on its own; revoke it in the dashboard to invalidate.

Credentials live at `~/.loadout/token.json`:

```json
{
  "base": "https://loadout.cowelltactical.com",
  "client_id": "<uuid>.access",
  "client_secret": "<long-random-string>"
}
```

### Before any Gateway call — always run login first

```bash
bash ~/.claude/skills/loadout-run/scripts/login.sh
```

The script prints setup instructions if no token is saved, and prints the active identity if one is. It never contacts the network — service tokens don't need refresh.

Read credentials after login:

```bash
TOKEN_FILE="$HOME/.loadout/token.json"
BASE=$(jq -r '.base' "$TOKEN_FILE")
CLIENT_ID=$(jq -r '.client_id' "$TOKEN_FILE")
CLIENT_SECRET=$(jq -r '.client_secret' "$TOKEN_FILE")
```

## How It Works

1. Write a JS worker that composes `Project` binding methods to accomplish the user's task.
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
    "capabilities": ["Project:create", "Project:applyTx"]
  }'
```

Response: `{ "ok": true, "result": <whatever the worker returned> }` or `{ "ok": false, "error": "message" }`.

## Worker Script Pattern

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    // Compose Project binding methods to accomplish the task
    return { /* results */ };
  }
}
```

## Available Capability Bindings

All binding methods are thin wrappers over `ProjectDO` / `AccountDO` / `ProjectsDO` RPCs — the same RPCs the browser UI drives. No new API surface exists; automating via `loadout-run` exercises the same production code path as the interactive configurator.

The **authoritative list** of bindings + capabilities lives in `loadout/entry.js` (`SCOPE_CAPS.staff`, `ProjectBinding`, `AccountBinding`, `ProjectsBinding`). The tables below cover the most-used surface; for anything not listed here, grep `entry.js` for the exact capability string before assuming a binding exists.

### Project — common methods

| Method | Capability | Notes |
|--------|------------|-------|
| `Project.create(name?)` | `Project:create` | Returns `{id}` — random 5-char base36 if `name` is omitted. DO materializes lazily on first RPC. |
| `Project.get(id)` | `Project:get` | Returns the full Configuration (`{items, measurements, identification, contact, global_notes, ...}`). |
| `Project.applyTx(id, tx)` | `Project:applyTx` | One atomic batch — add / update / remove items. See "applyTx payload" below. |
| `Project.layer(id, args)` | `Project:layer` | z-swap with neighbour: `{id, dir: "up"|"down", originator?}`. |
| `Project.undo(id)` / `Project.redo(id)` | `Project:undo` / `:redo` | Step viewed_seq. |
| `Project.setLabel(id, seq, text)` | `Project:setLabel` | Attach/clear a text label on commit `seq`. Empty string clears. |
| `Project.setDisplayName(id, name)` | `Project:setDisplayName` | Stamp an author/display name on every subsequent commit (renamed from `setAuthor`). |
| `Project.viewAt(id, seq)` | `Project:viewAt` | Park UI on commit `seq`. `0` = live head. |
| `Project.share(id, offsetMinutes?)` | `Project:share` | Full share flow: render PNG → KV write at `{id}/{YYYYMMDD}.png` → notify SSE → `{url}`. `offsetMinutes` is minutes west of UTC (defaults to 0). |
| `Project.renderPng(id)` | `Project:renderPng` | **Direct PNG render** without KV write. Returns `{pngBase64, seq}` — base64 so JSON transport works. Use for one-shot inspection (e.g. issue #78 verification) where you don't want a dated artefact in KV. |
| `Project.getMeta(id)` | `Project:getMeta` | Read `{state, head_seq, locks, owner_account_id, authorized_account_ids, section_status, ...}`. Useful for state + policy verification. |
| `Project.readSnapshot(id, atSeq)` | `Project:readSnapshot` | Frozen-view bundle at a specific commit (items + PII + lifecycle + origin in one round-trip). |
| `Project.renderWorkOrderPdf(id, atSeq)` | `Project:renderWorkOrderPdf` | Render the work-order PDF at `atSeq`. Returns base64 PDF bytes. |

### Project — workflow + PII methods

Pipeline transitions go through a single dispatcher:

- `Project.applyAction(id, {action, project_id, reason?, quote_vest?})` → `Project:applyAction`. The `action` is a snake_case string: `"request_quote"`, `"submit_quote"`, `"revise_quote"`, `"accept_quote"`, `"approve_order"`, `"mark_tracing_received"`, `"unmark_tracing_received"`, `"mark_shipped"`, `"revert_to_quote"`, `"revert_to_production"`, `"retry_quote"`, `"retry_approval"`, `"reset_to_design"`, `"archive"`, `"unarchive"`. The DO closure enforces per-action role gates — granting `Project:applyAction` doesn't grant the moon.

Per-section PII setters (separate capabilities so a scoped script can save just one section): `Project:setProfile`, `Project:getProfile`, `Project:setMeasurements`, `Project:getMeasurements`, `Project:setIdentificationPersonal`, `Project:getIdentificationPersonal`, `Project:setNotes`, `Project:setPatches`, `Project:setTracing`, `Project:getTracing`, `Project:setVestSpec`, `Project:setCustomerEmail`, `Project:setItemConfig`, `Project:getItemConfig`, `Project:setSharedConfig`, `Project:grantAccess`, `Project:seedItems`. See `entry.js` for signatures.

**`caller` is baked, never authored.** Every binding stamps the gateway's verified principal as `caller`. A script that sends its own `caller` field (any role) throws at the binding (#492 D6-7); the old staff downgrade to `customer` / `system` is gone. To act on an order or department AS its coordinator, use the catalog below.

### Loadout — the agent catalog (orders, departments, staff grants)

Capability `Loadout:call`. The same arcs the site buttons and `/mcp` `execute` reach, through one Rust dispatch (`src/agent.rs`). Raw mutation bindings for orders and departments (`createOrder`, `createDepartment`, `applyOrderAction`, `applyDepartmentAction`, `setParentDepartment`, `claimOrderSlot`) no longer exist on `/run`; reads (`getMeta`, `getDepartmentView`, `getOrderView`, `readOrder`) remain.

```javascript
// Staff /run does NOT run the Code Mode harness: `this.env.Loadout.call(name, argsJson)` returns a JSON STRING `{text, isError}`.
const call = async (name, args) => {
  const r = JSON.parse(await this.env.Loadout.call(name, JSON.stringify(args ?? {})));
  let text; try { text = JSON.parse(r.text); } catch { text = r.text; }
  return { ok: !r.isError, text };
};
const dept = await call("create_department", { name: "Test PD", coordinator_email: "coord@example.com" });
```

A bare `export default async (loadout) => …` program is the `/mcp` harness shape and FAILS on `/run` with an opaque runtime "internal error" (502). On `/run`, always the WorkerEntrypoint class. Capability names and arg keys: grep `wire_name` and the `*Args` structs in `src/agent.rs`; unknown keys are refused.

### Account

Keyed by **email** (not project id). Used for OTP login flows only — PII moved to ProjectDO in #128.

| Method | Capability | Notes |
|--------|------------|-------|
| `Account.requestCode(email)` | `Account:requestCode` | Send a 6-digit OTP via Cloudflare Email Workers. |
| `Account.verifyCode(email, code)` | `Account:verifyCode` | Verify — returns `{status: "verified", account_id, email}` or `{status: "invalid", remaining_attempts}`. |

### Projects (singleton registry / scheduler)

| Method | Capability | Notes |
|--------|------------|-------|
| `Projects.upsertProject(args)` | `Projects:upsertProject` | Idempotent upsert into the per-year bucket (`projects_<YYYY>`). |
| `Projects.getProject(id)` | `Projects:getProject` | Strongly-consistent read of one row. |
| `Projects.listProjects(args?)` | `Projects:listProjects` | Scheduler-ordered list. |
| `Projects.createManualProject(args)` | `Projects:createManualProject` | Staff manual-entry path (#132). |

### applyTx payload shape

```javascript
// Wire shape per `crate::durable_objects::project::ApplyTxArgs`.
// Both create and update use the same `items[]` list — no `add` field
// (a stray `{add: {...}}` is silently no-op'd; verify in entry.js if in doubt).
{
  originator: "automation-script",   // stamped onto affected items' originator
  items: [
    // CREATE: omit `id`, set `kind` to a kebab-case catalog slug.
    { kind: "callout-box", x: 0, y: 0, label: "first line\nsecond line" },
    { kind: "mag-open-top", x: 500, y: 1200 },

    // UPDATE: provide `id`, omit `kind`. Any subset of x/y/z/rx/ry/rz/w/h/label/note/zone/parent_vest.
    { id: "<uuid>", x: 1600, y: 800 },
    { id: "<uuid>", rz: 900 },        // 900 deci-degrees = 90°
    { id: "<uuid>", label: "" },       // empty string clears label
  ],
  removes: ["<uuid>", "<uuid>"],       // delete by id (note: plural `removes`, not `remove`)
}
```

Position units are **centi-inches** (1″ = 100). Rotation units are **deci-degrees** (90° = 900).

For z-order (raise / send-to-back), use `Project.layer(id, {id: "<uuid>", dir: "up"})` — separate RPC, not a field on `applyTx`.

## Scope-to-Capability Mapping

`/run` is the staff scope (`SCOPE_CAPS.staff`); `/user/run` is the customer scope (`SCOPE_CAPS.user`: canvas edits, a short op allowlist, and `Loadout:call` as the customer — the officer submit and the roster ops live there as arcs, not bare actions). Non-staff callers are rejected at the CF Access layer before any /run code runs.

## Writing Worker Code

**Key rules:**
- Always `import { WorkerEntrypoint } from "cloudflare:workers"` and export default class extending it
- Access bindings via `this.env` (not just `env`)
- The `run()` method takes no arguments — all context comes from bindings
- Return a plain object — it becomes the `result` field in the response
- Errors throw and return as `{ "ok": false, "error": "message" }`
- Declare the MINIMUM capabilities needed — the gateway rejects over-requesting
- Every RPC you call runs in the loadout Worker, not in the sandbox, so they count toward the parent Worker's CPU budget. Keep scripts tight.

## Examples

### Mint a project and place items

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const p = this.env.Project;
    const { id } = await p.create();
    await p.setDisplayName(id, "Demo Operator");
    await p.applyTx(id, {
      originator: "demo-script",
      items: [
        { kind: "vest-medium", x: 0, y: 0 },
        { kind: "mag-open-top", x: 500, y: 1200 },
      ],
    });
    return { id };
  }
}
// capabilities: ["Project:create","Project:setDisplayName","Project:applyTx"]
```

### Lifecycle test — create → add → undo → redo → label

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const p = this.env.Project;
    const { id } = await p.create();

    await p.applyTx(id, { items: [{ kind: "vest-medium", x: 0, y: 0 }] });
    await p.applyTx(id, { items: [{ kind: "mag-open-top", x: 500, y: 1200 }] });

    const before = await p.get(id);
    await p.undo(id);
    const after = await p.get(id);

    await p.redo(id);
    await p.setLabel(id, 2, "Initial pass");

    return {
      id,
      items_before_undo: before.items.length,
      items_after_undo: after.items.length,
    };
  }
}
// capabilities: ["Project:create","Project:get","Project:applyTx",
//                "Project:undo","Project:redo","Project:setLabel"]
```

### Render-and-inspect — rasterise a project to PNG without KV

Use `renderPng` (not `share`) when you want the PNG bytes back in the /run response and don't want to leave a dated `{id}/YYYYMMDD.png` artefact in KV. Decode the base64 client-side.

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const p = this.env.Project;
    const { id } = await p.create();
    await p.applyTx(id, {
      originator: "render-test",
      items: [
        { kind: "vest-medium", x: 0, y: 0 },
        { kind: "callout-box", x: 0, y: -200, label: "regression check\nline 2" },
      ],
    });
    const { pngBase64, seq } = await p.renderPng(id);
    return { id, seq, pngBase64 };
  }
}
// capabilities: ["Project:create","Project:applyTx","Project:renderPng"]
```

Decode locally:

```bash
jq -r '.result.pngBase64' run-response.json | base64 -d > out.png
```
