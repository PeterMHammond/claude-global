---
name: watchman-run
description: Execute sandboxed JS workers on Watchman's Dynamic Workers gateway. One invocation composes N WatchmanBinding RPC calls atomically inside Cloudflare. Triggers on /watchman-run or when the user asks to onboard, scan, rotate tokens, query findings, or batch-manage CF accounts watched by watchman.
---

# Watchman Run

Execute sandboxed JavaScript workers on Watchman via `POST /run`. Each worker script composes one or more `Watchman` binding methods — each of which is a thin marshalling layer over the canonical `trait Watchman` (`WatchmanImpl`) — in a single atomic execution inside Cloudflare.

**This is staff-only.** The endpoint sits behind Cloudflare Access on `watchman.everygoodwork.online/run`. The same `trait Watchman` powers the Phase 4.3 website; `/run` is the programmable mirror.

## Authentication

Cloudflare Access **service tokens** are the script-friendly auth path. A service token is a pair of long strings (Client ID + Client Secret) issued in the Cloudflare dashboard (Zero Trust → Access → Service Auth). It never expires on its own; revoke it in the dashboard to invalidate.

Credentials live at `~/.watchman/token.json`:

```json
{
  "base": "https://watchman.everygoodwork.online",
  "client_id": "<uuid>.access",
  "client_secret": "<long-random-string>"
}
```

### Before any Gateway call — always run login first

```bash
bash ~/.claude/skills/watchman-run/scripts/login.sh
```

The script prints setup instructions if no token is saved, and prints the active identity if one is. It never contacts the network — service tokens don't need refresh.

Read credentials after login:

```bash
TOKEN_FILE="$HOME/.watchman/token.json"
BASE=$(jq -r '.base' "$TOKEN_FILE")
CLIENT_ID=$(jq -r '.client_id' "$TOKEN_FILE")
CLIENT_SECRET=$(jq -r '.client_secret' "$TOKEN_FILE")
```

## How It Works

1. Write a JS worker that composes `Watchman` binding methods to accomplish the user's task.
2. Declare the minimum capabilities needed (currently `Watchman:read | Watchman:write | Watchman:execute`).
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
    "capabilities": ["Watchman:write"]
  }'
```

Response: `{ "ok": true, "result": <whatever the worker returned> }` or `{ "ok": false, "error": "message" }`.

## Worker Script Pattern

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    // Compose Watchman binding methods to accomplish the task
    return { /* results */ };
  }
}
```

## Available Capability Bindings

`env.Watchman` is the only binding. Six methods, all routed through the canonical `trait Watchman` in `src/api.rs`. The Phase 4.3 website calls the same trait methods.

### Watchman — Phase 4.1 surface

| Method | Capability | Notes |
|--------|------------|-------|
| `Watchman.accounts()` | `Watchman:read` | List all registered accounts. Returns `Array<AccountRegistryEntry>` with `{name, display_name, cloudflare_account_id, default_alert_to, enabled, added_at, added_by}` — token-free. |
| `Watchman.add_account({name, display_name, cloudflare_account_id, cloudflare_api_token, default_alert_to?})` | `Watchman:write` | Register a new account. Worker smoke-tests the plaintext token against `/accounts/{id}`, seals it under a per-tenant HKDF-derived AES-256-GCM key via `cf_tools::vault`, pushes identity to SystemDO("registry") and sealed token to AccountDO. Returns the persisted entry (token-free). |
| `Watchman.rotate_token({account, cloudflare_api_token})` | `Watchman:write` | Replace just the sealed token. Same smoke-test + seal pipeline as `add_account`. Returns `null` on success. |
| `Watchman.last_finding({account})` | `Watchman:read` | Return the most recent `Finding` from the account's `findings_today` buffer, or `null`. |
| `Watchman.force_alarm({account})` | `Watchman:execute` | Tick the account's StateTree once. Fires `cf_cost_scan` → emits readings + findings. Returns a `TickReport` `{account, started_at_ms, finished_at_ms, findings_count, services_scanned}`. |
| `Watchman.set_threshold({account, service, multiplier?, floor_micro_usd?})` | `Watchman:write` | Overlay a manual threshold on `ctx.config.thresholds.overrides`. `service` is a snake_case `ServiceKind` string. Both `multiplier` and `floor_micro_usd` optional — pass one or both. Returns the updated `AccountConfig`. |

### Scope-to-Capability Mapping

Only the `staff` scope exists today. All staff get every capability (`Watchman:read | Watchman:write | Watchman:execute`). Non-staff callers are rejected at the CF Access layer before any /run code runs.

## Writing Worker Code

**Key rules:**
- Always `import { WorkerEntrypoint } from "cloudflare:workers"` and export default class extending it
- Access bindings via `this.env` (not just `env`)
- The `run()` method takes no arguments — all context comes from bindings
- Return a plain object (or scalar) — it becomes the `result` field in the response
- Errors throw and return as `{ "ok": false, "error": "message" }`
- Declare the MINIMUM capabilities needed
- Every RPC you call runs in the parent Watchman Worker, not in the sandbox; they count toward the parent's CPU budget. Keep scripts tight.

## Examples

### List all accounts

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    return await this.env.Watchman.accounts();
  }
}
// capabilities: ["Watchman:read"]
```

### Onboard a new account

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    return await this.env.Watchman.add_account({
      name: "CARM",
      display_name: "CARM",
      cloudflare_account_id: "b4dd7117b02a79497ed0f09f4f917fbe",
      cloudflare_api_token: "v1.0_REPLACE_ME",
      default_alert_to: "peter@everygoodwork.online",
    });
  }
}
// capabilities: ["Watchman:write"]
```

### Force the first scan + return the latest finding

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const w = this.env.Watchman;
    const tick = await w.force_alarm({ account: "CARM" });
    const finding = await w.last_finding({ account: "CARM" });
    return { tick, finding };
  }
}
// capabilities: ["Watchman:execute", "Watchman:read"]
```

### Rotate a token

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    await this.env.Watchman.rotate_token({
      account: "CARM",
      cloudflare_api_token: "v1.0_NEW_TOKEN",
    });
    return { ok: true };
  }
}
// capabilities: ["Watchman:write"]
```

### Force-tighten a threshold (lower the floor so anomalies trip easier)

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    return await this.env.Watchman.set_threshold({
      account: "CARM",
      service: "workers_requests",
      multiplier: 1.5,
      floor_micro_usd: 50_000,
    });
  }
}
// capabilities: ["Watchman:write"]
```

## ServiceKind enum values (use in `set_threshold`)

Phase 4.1 service taxonomy:

```
workers_requests   — Worker invocation count
workers_cpu_ms     — Worker CPU time
do_requests        — Durable Object requests
do_duration        — DO active-time (µGB-seconds)
r2_storage         — R2 byte-ms (point-in-time × window)
```

Phase 4.2 will add: `r2_class_a_ops`, `r2_class_b_ops`, `kv_reads`, `kv_writes`, `d1_rows_read`, `d1_rows_written`, `workers_ai_neurons`, `queues_operations`.

## Operational state — Phase 4.1

- Worker URL: `https://watchman.everygoodwork.online`
- Source repo: `gitlab.com/everygoodwork/watchman`
- Single worker-secret prerequisite: `WATCHMAN_KEY_DERIVATION_SEED` — set once via `./scripts/bootstrap-encryption-key.sh` in the repo. The vault seed is the trust root for all per-account API tokens stored encrypted in AccountDO lite3 buffers.
- All onboarding + rotation happens through `/run` — no per-account `wrangler secret put` ceremony.
