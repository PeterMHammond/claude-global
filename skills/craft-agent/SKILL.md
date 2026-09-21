---
name: craft-agent
description: Execute sandboxed JS workers on Craft's admin /-/agent gateway — the admin control plane. One invocation composes N Durable Object RPC calls atomically inside Cloudflare. Triggers on /craft-agent or when the user asks to administer, moderate, claim, quarantine, re-kind, badge, ban, probe, or batch-drive Craft's reference-architecture surface.
---

# Craft Agent

Execute sandboxed JavaScript workers on Craft via `POST /-/agent`. Each worker script composes one or more binding methods — each a thin wrapper over a real Durable Object RPC — in a single atomic execution inside Cloudflare.

Craft is a **reference architecture** for the construct-pattern substrate (State / World / Action / Construct). `/craft-agent` is the programmable mirror of that surface: every binding the gateway exposes maps 1:1 to a DO RPC that the rest of the worker uses. There is no `/-/agent`-only API.

`POST /-/agent` is the **admin control plane** — System diagnostics, the Replay/Sandbox inspector, the trust-and-safety moderation surface (claim, re-kind, transfer, quarantine, badge, account suspend/ban), and **construct export** (download any construct's recreate-from-scratch definition as a build plan / training aid — see `Construct.export`). The per-user authoring gateway (`POST /-/user/agent`, DPoP-bound token identity only, bakes the caller's own key) is a separate concern and is **not** covered here — but it exposes the *owner-scoped* `Construct.export` too (you export only what you author), so a non-staff authoring AI pulls build plans through its own gateway. See the `craft-user-agent` skill.

For sibling business apps that use the same Dynamic Workers pattern, prefer `/loadout-run`, `/carm-run`, or `/watchman-run` — they each target their own gateway with their own bindings.

## Trust model

`POST /-/agent` sits behind Cloudflare Access on `craft.everygoodwork.io/-/agent`, and the gateway is admin-only on three independent layers (craft#43):

> **The Access application is `craft-admin`** (craft#676). Its audience tag is never copied into the worker: at first use per isolate the worker asks the Access API, with `CRAFT_API_TOKEN`, for the app named exactly `craft-admin` and pins that `aud`. A recreated app is picked up by the next isolate; an app renamed away from `craft-admin` fails every call closed.

1. **In-worker JWT verification.** The `Cf-Access-Jwt-Assertion` header's RS256 signature is verified against the team JWKS, then `iss` (the team, its certificate URL pinned), `exp`, and `aud` (the derived `craft-admin` tag, mandatory outside local dev). A forged header is rejected regardless of host or path — auth no longer rides on the edge stripping a client copy.
2. **Host bind.** `/-/agent` only answers on `craft.everygoodwork.io` — an exact-label match, not a suffix, so the gateway never answers on a construct origin, a minted instance origin, or the apex. Since craft#453 the shell is one reserved label beside the constructs on `everygoodwork.io`, so the bind is the whole separation; the zone is no longer doing any of that work.
3. **Capability allowlist.** Every requested capability must be in `SCOPE_CAPS.admin`; over-requesting 403s before any isolate runs.

The admin rail holds every capability below. Anyone else is rejected at the CF Access layer before any `/-/agent` code runs.

## Authentication

Cloudflare Access **service tokens** are the script-friendly auth path. A service token is a pair of long strings (Client ID + Client Secret) issued in the Cloudflare dashboard (Zero Trust → Access → Service Auth). It never expires on its own; revoke it in the dashboard to invalidate. The token's `common_name` becomes the caller identity in the gateway logs.

Credentials live at `~/.craft/token.json`:

```json
{
  "base": "https://craft.everygoodwork.io",
  "client_id": "<uuid>.access",
  "client_secret": "<long-random-string>"
}
```

### Before any Gateway call — always run login first

```bash
bash ~/.claude/skills/craft-agent/scripts/login.sh
```

The script prints setup instructions if no token is saved, and prints the active identity if one is. It never contacts the network — service tokens don't need refresh.

Read credentials after login:

```bash
TOKEN_FILE="$HOME/.craft/token.json"
BASE=$(jq -r '.base' "$TOKEN_FILE")
CLIENT_ID=$(jq -r '.client_id' "$TOKEN_FILE")
CLIENT_SECRET=$(jq -r '.client_secret' "$TOKEN_FILE")
```

## How It Works

1. Write a JS worker that composes binding methods to accomplish the task.
2. Declare the minimum capabilities needed.
3. Submit to `POST /-/agent` on the configured base URL.
4. The gateway verifies the CF Access JWT, enforces the capability allowlist, sandboxes the code in a V8 isolate, and returns the result.

## Submitting a Worker

```bash
curl -s -X POST "${BASE}/-/agent" \
  -H "CF-Access-Client-Id: ${CLIENT_ID}" \
  -H "CF-Access-Client-Secret: ${CLIENT_SECRET}" \
  -H "Content-Type: application/json" \
  -d '{
    "code": "<worker source>",
    "capabilities": []
  }'
```

Response: `{ "ok": true, "result": <whatever the worker returned> }` or `{ "ok": false, "error": "message" }`.

## Worker Script Pattern

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    // Compose binding methods to accomplish the task
    return { /* results */ };
  }
}
```

**Key rules:**
- Always `import { WorkerEntrypoint } from "cloudflare:workers"` and export default class extending it
- Access bindings via `this.env` (not just `env`)
- The `run()` method takes no arguments — all context comes from bindings
- Return a plain object — it becomes the `result` field in the response
- Errors throw and return as `{ "ok": false, "error": "message" }`
- Declare the MINIMUM capabilities needed — the gateway rejects over-requesting
- A capability is `<Binding>:<method-tag>`. The tag is the snake_case RPC name (e.g. `Construct:set_kind`); the JS method on the binding is camelCase (`Construct.setKind(…)`). They intentionally differ — the cap is an allowlist string, the method is the call.
- **A cap grants the whole BINDING, not that one method.** Declaring `Construct:set_kind` provisions `env.Construct` with every method on it. The tag is what the allowlist checks (over-request → `403`), not a per-method filter — so declare the minimum for honesty and review, and read the binding table below for what you actually hold. Staff caps are ACL-**bypassing**; the DO does not second-guess you.
- **The un-compensable `UserAdmin` verbs are the same exception on the MONEY rail** (craft#399, craft#417). `UserAdmin.grantCredits` and `UserAdmin.issueCredit` MINT platform credit, `UserAdmin.releaseCredential` unbinds the identity an account is reached by, `UserAdmin.unregisterConstruct` unlinks the owner-index row the burn walk bills from, and `UserAdmin.designateSystemAccount` exempts an account from purge/dormancy/ceiling enforcement for good; no sibling verb ON THAT BINDING puts any of the five back. So each is handed over only to a script that DECLARED it: with any other `UserAdmin:*` cap the method is not on the binding at all (`TypeError: … is not a function`), not a 403. FIVE INDEPENDENT AXES, not a ladder — `grantCredits` reaches an account by principal, `issueCredit` reaches a MAILBOX that may hold no account at all, `releaseCredential` mints nothing, `unregisterConstruct`'s only compensator (`Construct.claim`) lives on a DIFFERENT binding nothing co-grants, and `designateSystemAccount` has no compensator ANYWHERE — there is no un-designate — so none of them carries another, and declaring all five is the only way to hold all five. The rest of the binding stays on one object because every verb on it IS compensable by a sibling there: `reinstate` lifts `suspend` and `ban`, `resendInvite` peeks a live voucher non-consumingly and moves no credit, and `tos_state`/`resolveCredential` read.
- **The two erase verbs are the exception, and they are exceptions on purpose.** `Construct.purge` and `Construct.purgeForced` erase a construct's history and no sibling verb puts it back, so each is handed over only to a script that DECLARED it: with any other `Construct:*` cap the method is not on the binding at all (`TypeError: … is not a function`), not a 403. `Construct:purge_forced` carries `purge` with it — it erases past every refusal `purge` honours — and `Construct:purge` never carries the forced door. **`Construct:restore_wal` is the third such cap, on a SEPARATE axis** (craft#203): restoring is not less than erasing and not more than it — it MINTS a construct's owner, roster, awards and balances onto a slug that held none of them, and no sibling verb takes that back. It composes over whichever erase rung was declared rather than ordering against it, so a token gets exactly the decisions it named.
- Every RPC you call runs in the craft Worker, not in the sandbox, so they count toward the parent Worker's CPU budget. Keep scripts tight.

## Available Capability Bindings

Bindings land in lockstep with each Durable Object as it ships. This section documents only bindings that are actually wired into `entry.js` and have a corresponding RPC on the live DO — never anticipated surface. The `env` binding key (what the script calls) is the first column; the capability string you declare is the second.

### System — system singleton (SystemDO, keyed `"system"`)

System-level diagnostics + health surface. Single instance per worker. State lives in split `lite3::OwnedBuffer`s — a slow-changing `projection` (started/last-ping/init history) plus append-only `events`, `commands`, and `lifecycle` logs over `cf_tools::event_log` (each entry UUIDv7-stamped). Mutating calls broadcast a Datastar SSE patch to every connected `/-/health` subscriber.

| Method | Capability | Returns | Notes |
|---|---|---|---|
| `System.status()` | `System:status` | `StatusReport` (see shape below) | Read-only diagnostics: `version`, `started_at_ms`, `last_initiated_ms` (most recent hibernation wake), `last_ping_at_ms`, `now_ms_utc`, `head_event_id`, `initiated_history[]`, the merged `recent_timeline[]` (init / connect / reconnect / close / ping in chronological order), the raw `recent_events[]` / `recent_commands[]` / `recent_lifecycle[]` logs, the live presence (`connected_viewers`, `socket_count`, `viewers[]`), and `cadence` (`"frequent"`/`"occasional"`/`"rare"` idle-backoff tier). All event ids are **UUIDv7 strings** — compare as strings, never `Number`. All timestamps are UTC ms — viewers format client-side via `new Date(ms).toLocaleString()`. |
| `System.dispatch(command, payload?, actor?, key?)` | `System:dispatch` | `{status, event_id?}` | **The generic command channel — THE way to post any command** (commands are dynamic strings, never a method-per-verb). `command` is `entity.verb` — and the WHOLE identity: the mutation address law retired the vestigial `target` argument, which was written to the log as an empty string at every hop. e.g. `System.dispatch("ping", "", cid, key)` IS a ping — the same WAL event + `/-/health` SSE broadcast the ⚡ in-page button fires. Pass a **stable** `key` (string) to make retries idempotent — a repeat returns the cached outcome as `{status:"replayed", event_id}`. **Omit `key`** and one is minted (`crypto.randomUUID()`), a non-idempotent one-shot. `actor` is the issuing client's stable id (`cid`) — pass it to attribute the command to a distinct viewer in the timeline/roster; omit → `anon`. `status` is `"rejected"` when the StateTree did not authorise the command (a no-op, no event), `"applied"` on a fresh event, `"replayed"` on an idempotency hit. `event_id` is the minted event (UUIDv7 string) when the DO surfaces it; absent on `rejected` and on the generic framework path. There is no separate render payload — the SSE broadcast is the sole renderer. |
| `System.events()` | `System:events` | `EventRow[]` — `[{id, label, at_ms}, …]` | Raw event-log dump, oldest-first, capped at the DO's retention (1000). Deliberately analytics-free: the sandbox gets the raw log and derives its own metrics in JS. |
| `System.export()` | `System:export` | `LogExport` — `{events, commands, lifecycle, wakes}` | Full four-log dump — the replay oracle's input (same as `Replay.capture()`). Use to seed an authored scenario. |
| `System.computeProbe(target, sinceMs, untilMs)` | `System:compute_probe` | `{namespace_id, verdict, rows:[{target, object_id, requests, micro_gb_seconds}, …]}` | craft#137/#344 staff diagnostic. `target` is `{Constructs:["slug", …]}` — each resolved to its live `CONSTRUCT_DO` object id in-Worker — or `{Principals:["<64-hex>", …]}`, which ARE the `USER_DO` object ids (a principal is minted by `newUniqueId`, never hashed); anything else is refused by the decode. Pulls RAW GraphQL compute usage for `[sinceMs, untilMs)` — zero markup, never a settlement path. `verdict:"none_found"` is the ABSENCE of evidence (an idle object and a wrong namespace id are indistinguishable), never a clearance that billing is running. |
| `System.fleetErrors(slugsJson, minRatePpm?)` | `System:fleet_errors` | `ConstructErrorSummary[]` — `[{slug, total, window_errors, window_runs, rate_ppm, prev_rate_ppm, last_error_ms}, …]` | craft#236 staff fleet health: which of these constructs are FAILING, worst first. Reads the same bounded folded error record the owner's dashboard reads, through the MESSAGE-FREE projection — counts and the current hour's failure rate only, never the facet's exception text. `slugsJson` is a JSON array of slugs (≤200 per call — the fan-out is one DO read each); candidates come from the error rows `qc-tail` writes, readable at `System.qcRead(null, null, null, "errors")` (`GET /qc` is gone — craft#497). `minRatePpm` drops healthy rows server-side (omit → every slug asked about). A construct that cannot answer is OMITTED, never reported healthy. |
| `System.qcRead(from?, to?, tag?, shape?)` | `System:qc_read` | `{rows:[…]}` — `QcAggRow[]` \| `QcRawRow[]` \| `QcErrorRow[]` by `shape` | craft#497 **staff fleet telemetry** — the read that used to be `GET /qc`. That door served every construct's endpoint URLs, request volumes, wall/CPU percentiles and error profile to ANY established craft session, and a session carries no staff concept to predicate on, so it was DELETED rather than guarded; the reader lives here, where the in-worker-verified CF Access assertion is the trust root — the same ruling `/replay/*` took. `from`/`to` are unix **seconds**; omit both for the last hour. A window wider than **31 days** is REFUSED, never clamped — every call spends a real billed Analytics Engine SQL query against the server-held `CRAFT_API_TOKEN`, so an unbounded scan is somebody's bill. `tag` filters one QC run (`blob6`). `shape` is `"aggregate"` (default: p50/p95/p99 wall + cpu per component × endpoint), `"raw"` (per-observation rows, ≤1000) or `"errors"` (failing endpoints worst-first, ≤200 — the candidate source for `System.fleetErrors`). Read-only; craft's only aimable AE read. |
| *(none — Rust-only)* | `System:record_platform_burn` | `null` | craft#264/#545, the platform-cost meter: appends one PLATFORM-borne cost row (`{service, count, micro, at_ms, tx_hash}`) to the SystemDO burn journal — a unit craft is invoiced for that no customer ledger can honestly carry, since neither party to the money owes CDP's per-settle facilitator fee. NOT gas: Coinbase's relayer pays that, proven on-chain (craft#545). The caller passes `{service, count, tx_hash}` only — the DO prices it, because CDP's first 1,000 settles a month are free and only the DO holds that running count. Driven automatically by the x402 settle path on a SUCCESSFUL on-chain transfer only, best-effort (a failed cost record must never fail the transaction whose cost it records). A log row, never a balance move — the platform holds no credits to debit. **No `SystemBinding` method exposes it, so no script can call it:** the capability is auto-derived (every `SYSTEM_METHODS` entry mints one) and buys nothing past the System binding a staff caller already holds. |
| `System.platformPrincipal()` | `System:platform_principal` | `principal \| null` | **Which account is the platform's own** — the directory entry the seed path reads so a platform surface is adopted onto that account at birth instead of being seeded ownerless and billing nobody. A POINTER, never the verdict: whether an account is exempt from enforcement is folded on the account itself (`AccountEvent::SystemAccountDesignated`), and this says only where to look. `null` on an environment where nobody has been designated yet — seeding still works there, it just leaves the surface un-owned until the first designation. |
| `System.ingestProbe()` | `System:ingest_probe` | `string` (JSON) | **Is the large-ingest rail's parent key honoured by R2** (craft#437 wave 2). Reports which parent is in hand (`r2_api_token` when `CRAFT_R2_ACCESS_KEY_ID`/`CRAFT_R2_SECRET_ACCESS_KEY` are set, else `craft_api_token`), lists `craft-content` as that key over the S3 API, then mints a five-minute temporary credential for a probe key under `in/probe/` and HEADs it: `404 NoSuchKey` means R2 honours credentials minted from this parent; `400 InvalidArgument` means R2 does not know it as an R2 API token. Pure — nothing is written, no DO is woken. |
| `System.beginMirror(construct, name)` | `System:begin_mirror` | `string` (JSON) | **Start the mirror** (craft#437 wave 4). `name` is a VIDEO leaf already in the construct's album. Returns AT ONCE, having enqueued the arc — every stage runs on the `craft-mirror` queue, none in a DO. The pipeline hands Stream a signed six-hour view of that exact R2 object at `/-/mirror-source/{token}` (`craft-content` keeps no public door, and R2 signs a presigned URL per method while Stream needs both HEAD and ranged GET), copies it in through the Stream WORKERS BINDING (no API token) with a 10% poster and a +31d scheduled deletion as the backstop. The pipeline then polls to `pctComplete` 100 with a rendition count stable across two 30s polls, crawls the ladder into `{owner}/ladder/{uid}/`, verifies every path each track's own mirrored playlist names against a strongly-consistent R2 LIST, records ONE `LadderAdded` leaf, and deletes the Stream video. Staff-side because the crawl spends `(renditions + 1) x duration` Stream delivery-minutes that wave 6 has not yet metered. Returns the construct, leaf and deadline; the uid appears in the `[mirror]` logs once Stream takes the copy. |
| `System.dropStreamVideo(uid)` | `System:drop_stream_video` | `string` (JSON) | **Drop ONE Cloudflare Stream video by uid** (craft#437 wave 4) — the compensator for a mirror that died after the copy. The pipeline's own delete stage runs only behind a passing verify, so an arc that failed anywhere upstream leaves a video no craft credential can otherwise reach: the Workers binding is the only door, and it lives in the deployed build. Names ONE video and takes no policy — this is not a sweep, because the `scheduledDeletion` set at copy (+31d) is what guarantees termination with nobody looking. Safe by construction: Stream never holds an original — wave 2 keeps the master content-addressed in R2 forever — so the most this costs is a re-encode. Refuses a uid Stream would not have minted. |
| *(none — Rust-only)* | `System:record_platform_principal` | `null` | The write half of the directory above, relayed by `UserAdmin.designateSystemAccount` so the account latch and the pointer cannot disagree about who the platform is. Best-effort: a failed relay leaves the account correctly exempt but undiscoverable, and re-calling the idempotent designation verb repairs it. Auto-derived from `SYSTEM_METHODS` like `record_platform_burn`; no `SystemBinding` method exposes it, so no script can call it. Its parameter is a `DesignatedPrincipal` (craft#442), minted only by `AccountView::designated` off a latched fold — the pointer is structurally unable to name an undesignated account rather than checked against one. |
| `System.mintCreditVoucher(code, amountMicro, uses, expiresAtMs, description)` | `System:mint_voucher` | mint outcome | Voucher book: the URL delivery of a credit gift — `uses` redemptions of `amountMicro`, once per account. **There is no `tier`:** a redeemed credit folds to `GiftSource::Issued` and is indistinguishable from a dollar the holder bought — same balance, same `lifetime_funding()` latch, same gates. **`expiresAtMs` is REQUIRED** — a positive epoch-ms, at most one year out; a voucher has no spelling for "never", because credit standing unattended in the book is a liability. `uses` is the single→multi dial: 1 is a personal gift link, n a shareable campaign. `description` is what the code is FOR, shown on `/redeem/{code}` and carried onto the redeemer's WAL. `issuedBy` is the VERIFIED gateway identity, baked — never a script argument. Play-pool mint is `ConstructDO`-only, never bound here. |
| `System.peekVoucher(code, account, nowMs?)` | `System:peek_voucher` | non-consuming voucher read | Staff probe: what a code grants + whether `account` already took it. Read-only — never consumes a use. |
| `System.redeemVoucher(code, account, nowMs?)` | `System:redeem_voucher` | redemption outcome | Consumes one use of `code` for `account`. |
| `System.revokeVoucher(code)` | `System:revoke_voucher` | `null` | **The kill switch** — marks the code dead in the book so nothing can redeem it again. `by` is the VERIFIED gateway identity, baked — never a script argument, the same law the mint applies to `issuedBy`, because the book IS the audit record. |
| `System.amendVoucher(code, expiresAtMs, addUses)` | `System:amend_voucher` | `AmendOutcome` | **Change a LIVE code's terms without re-minting it.** SINGLE-MINT means a code is that code forever, so this mutates the row it already has: extends or shortens `expiresAtMs`, and **ADDS** to the remaining uses (never replaces). Pass `null` for either to leave it alone; passing neither is an error. It cannot reach **the amount** — that is what a holder was promised. A **revoked** code is refused: the kill switch is not editable. `by` is the VERIFIED gateway identity, baked. `AmendOutcome` = `Amended{remaining_uses,expires_at_ms}` \| `Revoked` \| `Legacy` \| `NothingToDo` \| `NotFound`. |
| `System.listVouchers(limit?)` | `System:list_vouchers` | `[code, Voucher][]` | What is outstanding. The book was previously unauditable in practice — you could not list codes without already knowing them. Defaults to 100. |
| `System.voucherRedeemers(code, limit?)` | `System:voucher_redeemers` | `[account, at_ms][]` | Who took this code, and when. Defaults to 100. |
| `System.voucherHistory(limit?)` | `System:voucher_history` | `[Uuid, VoucherEvent][]` | The operator journal — every mint, amend and revoke, appended to the SystemDO `EventLog`, so issuance history is replayable rather than inferred from a mutable row. Defaults to 100. |

### Replay — deterministic event-source replay (read-only; SystemDO RPCs)

The Replay Inspector surface: replay recorded/authored event streams through the **pure** engine (`project` / `event_wire` / `replay_commands`) and diff vs a committed golden. Every method is **read-only** — it never mutates the `system` DO (the engine is pure over provided/embedded data; `capture`/`inspect` only read the log). Same bytes as the host golden tests. The `/replay` page itself is GONE — craft#199 removed it for dumping the SystemDO log anonymously; these bindings are the surviving read, behind CF Access.

| Method | Capability | Returns | Notes |
|---|---|---|---|
| `Replay.list()` | `Replay:list` | `string[]` | Names of all committed scenarios. |
| `Replay.runNamed(name)` | `Replay:run` | `ScenarioReport` | Run a committed (embedded) scenario by name → `{ result: { projection, wires, decisions }, diff }`. `diff` is present iff the scenario has a golden (`{projection_ok, wires_ok, decisions_ok, first_divergence}`). |
| `Replay.run(scenario)` | `Replay:run` | `ScenarioReport` | Run an authored scenario object: `{ name, seed:{events,commands,lifecycle,wakes}, steps:[…], ctx:{now_ms,socket_count,started_at_ms,version}, golden? }`. `steps` are `{"New":{id,label,at_ms,command?}}` / `{"Cloned":{from,tweak}}` / `{"Recorded":id}`. |
| `Replay.capture()` | `Replay:capture` | `LogExport` | Read-only snapshot of the live log → use as a scenario `seed`. (Same as `System.export()`.) |
| `Replay.captureRecording()` | `Replay:capture` | `RecordedCommand[]` | Read-only command stream **with** original idempotency keys, payloads, and `at_ms` (vs `capture()`, which drops them) — the Mode-2 sandbox seed. Feed straight into `Sandbox.load(id, recording)`. |
| `Replay.inspect(fromId, toId?)` | `Replay:inspect` | `[[id, wire], …]` | Read-only per-event wires over a recorded id range `(fromId, toId]` — the deterministic down-channel replay, as data. |

Event ids everywhere are **UUIDv7 strings**; `data-ms` in a wire is the id's own first-48-bit ms timestamp. The engine is deterministic: the same scenario yields byte-identical `result` every call.

### Fleet — the archive frontier (read-only; no Durable Object is woken) and the at-rest reseal

The archive-frontier read (craft#673 A4). It reads what already exists — the resolve keyspace's own construct projections, and the archive objects' own keys — so it costs a KV listing per page plus one R2 listing per construct, and wakes nothing. An object id is arithmetic over the name, and an archive's extent comes from the KEYS rather than from a stored cursor, which drifts the moment one object goes missing and then reads as a complete backup. This is the read to take BEFORE a risky release: it names, per construct, whether there is an archive to restore from and the exact prefix `Construct.restoreWal` takes.

| Method | Capability | Returns | Notes |
|---|---|---|---|
| `Fleet.walFrontier(cursor?, limit?)` | `Fleet:wal_frontier` | `{rows, scanned, next?}` | One page of the roll. Each row is `{construct, address, object_id, frontier}`. `frontier.state` is `empty` (nothing in cold storage — an erase would take this history), `archived` (with `incarnations[]`, each `{genesis, prefix, segments, first_key, last_key}` — `prefix` is what `Construct.restoreWal` takes verbatim), or `unreadable` (the objects are there and craft-core's own key reader refuses them — never reported as absence). `limit` is clamped to 100 constructs a page; `scanned` counts the resolve-keyspace rows read, always more than the constructs among them. Page on `next` until it is absent. |
| `Fleet.resealAtRest(cursor?, limit?)` | `Fleet:reseal_at_rest` | `{constructs, oauth, failed, scanned, next?}` | craft#676 rotation: re-seals every construct's credential vault row and every account's OAuth grant props key that opens only under `CRAFT_SECRET_PREVIOUS` under `CRAFT_SECRET`'s derived keys. Unlike the frontier it WAKES each construct and each account's OAuth shard a page names and WRITES ciphertext — never plaintext, never a row in the answer. `constructs`/`oauth` are `{already_current, resealed}`; `failed[]` is `{subject, error}` for every construct or principal that refused (an unbound or unreadable `CRAFT_SECRET` or `CRAFT_SECRET_PREVIOUS` refuses), every row that opens under neither root (`subject` is `{construct or principal}/{row id}`), and every shard too large for one scan. One page walks the `c/` projections, then the `a/` credential aliases (principals deduplicated within a page); `limit` is clamped to 100 subjects. Page on `next` until absent, and repeat whole passes until one reseals zero and fails zero before `CRAFT_SECRET_PREVIOUS` is unbound. A token that named only `Fleet:wal_frontier` gets a binding without this method. Idempotent. |

### Sandbox — runtime-faithful Replay (Mode 2; throwaway isolated SystemDO)

The **VCR over the real runtime**. A recording (from `Replay.captureRecording()` or authored as `RecordedCommand[]`) is loaded into an isolated `replay-sandbox-<id>` instance — the **same SystemDO class, never the `system` key** — where `play`/`fork` re-execute commands through the *genuine* `run_command` path (real SQLite storage, idempotency ledger, broadcast). **Production is never touched** (two layers: the binding hardcodes the `replay-sandbox-` prefix + validates `<id>` against `/^[A-Za-z0-9_-]{1,64}$/`; the DO self-verifies `id_from_name(key)==state.id`). All ids are **UUIDv7 strings**.

The mental model: **`seek` is non-destructive scrubbing; `play` commits** — it truncates the stale future forward of the playhead, then re-executes forward *as if new*. `fork` injects an off-recording command (in-place, or `branch` into a second sandbox leaving the original live). `diff` of two `RunReport`s is the evidence (volatile ids/time excluded → a before/after-code-change comparison is meaningful).

| Method | Capability | Returns | Notes |
|---|---|---|---|
| `Sandbox.load(id, recording)` | `Sandbox:write` | `SandboxStatus` | Load a `RecordedCommand[]` (`{command,payload,cid,key,at_ms}`); playhead → 0, playback cleared. |
| `Sandbox.status(id)` | `Sandbox:read` | `SandboxStatus` | `{key, playhead, recording_len, queued[], events}`. |
| `Sandbox.recording(id)` | `Sandbox:read` | `RecordedCommand[]` | The immutable loaded recording (for branching). |
| `Sandbox.seek(id, k)` | `Sandbox:read` | `SandboxStatus` | Scrub the playhead to recording position `k` (clamped). **Non-destructive.** |
| `Sandbox.step(id, n)` | `Sandbox:read` | `SandboxStatus` | Relative scrub by `n`. Non-destructive. |
| `Sandbox.play(id, to?)` | `Sandbox:run` | `RunReport` | **Commit:** truncate forward of the playhead, then re-execute `recording[playhead..to]` (to defaults to the end) through the real runtime. Returns `{executed[], projection, counts:{commands_executed,events_appended,replayed_hits,wakes}, from, to}`. |
| `Sandbox.fork(id, command, payload, actor, key?)` | `Sandbox:run` | `RunReport` | In-place fork: truncate forward of the playhead, then execute ONE off-recording command. `payload` is opaque (object → stringified, or a string). |
| `Sandbox.branch(from, to, at?)` | `Sandbox:run` | `SandboxStatus` | Clone `from`'s recording into a new sandbox `to` (optionally seek to `at`), leaving the original live. |
| `Sandbox.export(id)` | `Sandbox:read` | `LogExport` | The playback four-log dump. |
| `Sandbox.diff(id, baseline, candidate)` | `Sandbox:read` | `RunDiff` | `{ok, first_divergence, counts_match, decisions_match}`. Routed through the (warm) sandbox `id`; the same pure comparator CI uses. |
| `Sandbox.discard(id)` | `Sandbox:write` | `null` | Free the throwaway sandbox (clears recording + playback). Call when done. |

Typical agent loop: `Replay.captureRecording()` → `Sandbox.load(id, rec)` → `Sandbox.play(id)` (keep the `RunReport` as **baseline**) → *change code, redeploy* → `Sandbox.play(id)` again (**candidate**) → `Sandbox.diff(id, baseline, candidate)` → conclude → `Sandbox.discard(id)`.

### Construct — admin moderation of any construct (`env.Construct`; ConstructDO, keyed by slug)

The trust-and-safety + publish admin plane for a construct. A construct's ACL (`owner`/`members`) and lifecycle are event-sourced on its own `ConstructDO` WAL; these bindings append admin events to that WAL by slug, exactly as `construct_rpc(env, slug)` does inside the worker. Every method here is **staff-only and deliberately NOT a web route** — the consensual owner-facing paths (`/edit`, `/-/reset`, the two-step offer/accept transfer) live on the construct's own origin (craft#498); this binding is the override of last resort.

| Method | Capability | Returns | Notes |
|---|---|---|---|
| `Construct.claim(slug, account)` | `Construct:claim` | `boolean` | **Adopt an un-owned construct** (craft#34). Backfills `Owned { account }` onto a slug that has no `Owned` event (pre-ACL forks like `/pong`, `/gospel`, or any abandoned slug), recording `account` — which MUST be a PRINCIPAL (the 64-hex UserDO id, NEVER an email; the DO refuses non-principals loudly). Resolve an email to its principal via the `CREDENTIAL_ALIAS` KV: `wrangler kv key get "<email>" --namespace-id 8b0c5d26c6094fb9ae9fe1d013706677 --remote` — as owner. `true` = newly owned; **`false` = already owned** (no-op — no theft vector). Additive: the UI + every prior event survive. After a claim the owner can `/edit` and `/reset`. |
| `Construct.setUi(slug, html)` | `Construct:set_ui` | `null` | **Push a construct's UI bypassing the ACL** (craft#31). Overwrites `ui` in CONSTRUCTS KV + refreshes the cache + broadcasts to viewers. The deploy path for PLATFORM construct UIs (e.g. the Editor at slug `editor`, which is un-owned so the ACL-gated `/edit` would reject). The owner-scoped, ACL-checked counterpart is `Construct.setUi` on the **per-user** `/-/user/agent` gateway — distinct binding, distinct scope. |
| `Construct.seedConstruct(slug, spec)` | `Construct:seed_construct` | `boolean` | **Atomic facet-construct create** (craft#107) — full manifest (Facet UI + players/turns/cardinality/host_caps) + genesis ownership + ONE scan, in a single call. Replaces the chained `claim`→`setUi`→`setPlayers`→`setKind`→`setFacet` rebuild recipe (and its throwaway placeholder scan). `spec`: `{ name, owner (a PRINCIPAL — 64-hex UserDO id, never an email), players, turns, cardinality, facet, host_caps? }`. A bad spec/owner/wire-name throws with the named field. |
| `Construct.restampStaff(slug)` | `Construct:restamp_staff` | `boolean` | Re-assert Staff provenance on a pre-V8 staff-door construct (the bool→Provenance migration could only guess `User`). No parameter — this call IS the staff door stamping its own fact. `false` = already Staff (idempotent). |
| `Construct.setPlayers(slug, players, turns)` | `Construct:set_players` | `boolean` | **Declare multiplayer shape** — player slots + turns policy; platform seats + gates derive from this, a facet never re-implements it. Same RPC (`admin_set_players`) as the user-scoped `/-/user/agent` `Construct.setPlayers`, minus its ACL check. |
| `Construct.setRules(slug, rulesJson)` | `Construct:set_rules` | `boolean` | Full declarative seat/turn/per-action gate as typed `TurnSettings` JSON; `evaluate_gate` reads it, `turn:false` verbs (`newgame`/`reset`) pass off-turn. Returns `true` iff the JSON parsed into `TurnSettings`. |
| `Construct.setFacet(slug, code)` | `Construct:set_facet` | `null` | ACL-bypassing staff write of a construct's facet source (`admin_set_facet`) — the same content-addressed archive-then-publish seam `setUi`/`rollbackFacet` use, without the owner-scoped ACL check the per-user `/-/user/agent` counterpart (`Construct.setFacet`) applies. |
| `Construct.rollbackFacet(slug, hash)` | `Construct:rollback_facet` | `null` | **Roll a facet back to an archived version by content hash** (ACL-bypassing; the T&S "restore known-good" tool — quarantine's surgical cousin). Every facet save archives content-addressed at `facet:{slug}@{hash}` (`craft_tools::blob`); this reads those bytes and re-publishes through the one `persist_facet` seam (re-scan + `Published` record). LOUD error on an unknown hash. |
| `Construct.setKind(slug, kind)` | `Construct:set_kind` | `boolean` | **Re-kind a construct's cardinality** (craft#12). `kind` is a `ConstructKind` name (`"Spawner"` mints a fresh instance per visit, `"Shared"` renders one canonical instance, `"Personal"`, …). The publish-plane promotion path for a legacy `Personal` construct, no re-fork. `false` = unknown kind name. |
| `Construct.purge(slug)` | `Construct:purge` | `null` | **`/craft-agent` CAN hard-delete a construct — this is that door.** TOTAL erasure of a dead/test construct (fleet hygiene). Before storage is dropped it best-effort unlinks the owner's index row AND every member/pending-offer's share row, so no account is left holding a sidebar card to a slug that no longer resolves — then erases the KV projection + draft + DO storage itself (shared content-addressed blobs are untouched). Idempotent, but **there is no undo**: resolve the true owner and confirm the slug is genuinely dead (an `Construct.export` that fails with "own manifest: construct not found" is the check — see `UserAdmin.unregisterConstruct`'s worked example) BEFORE calling, never after. |
| `Construct.purgeForced(slug, reason)` | `Construct:purge_forced` | `null` | **The ABUSE door — hard-delete even when `purge` refuses.** `purge` will not erase a construct whose event stream does not fold, nor one whose WAL is not fully archived; both are costs the construct's OWN owner controls by appending, so a legal/T&S takedown must not be blockable by its target. This erases anyway. `reason` is REQUIRED (an empty one is refused) and is written into the KV tombstone alongside the door and the archive that was actually taken (`Complete` / `Partial` / `None`), so a forced erase is structurally distinguishable from a clean one forever after. Use `Construct.purge` first — reach for this ONLY once it has refused, and say why. |
| `Construct.rename(slug, name)` | `Construct:rename` | dispatch outcome | Set the marketplace display name via the structural `rename` command (folds a `Renamed` event) — the ACL-bypassing staff counterpart of `POST /-/rename`. That route's `rename` action is `Always`-gated, so the web route is the only owner boundary there; this staff path is gated purely by the cap allowlist. Idempotent per `(slug, name)` (dispatched with a stable idempotency key). |
| `Construct.forceTransfer(slug, account)` | `Construct:force_transfer` | `null` | **Override an existing owner** (craft#31 §8). Unlike `claim` (which no-ops if owned), this reassigns ownership to `account` regardless. The staff override path (account deletion / handoff); the consensual path is the two-step offer/accept web route. Since craft#549 it is a full CONVEYANCE, not a fold flip: the seller relinquishes (their burn walk stops billing it) and the buyer registers an OWNED card, and the seller's standing rooms of it move with it. **REFUSES a room** (409, craft#550) — a room is the effect of a rental and never changes hands; the refusal is structural, so it holds for any transfer door. Read both sides with `UserAdmin.billingStanding` before and after. |
| `Construct.repairRoomOwner(slug)` | `Construct:repair_room_owner` | `RoomOwnerOutcome` | **Put a ROOM's `Owned` fold back to the principal its own address derives from** (craft#555). NOT a transfer and never through `Conveyable`: the door takes ONE argument, the room, and no recipient exists to aim — `enduring_suffix(template, P) == suffix` is the address read backwards, and P is found in the room's own ownership trail (mint `owned`, every `ownership_transferred` side), never supplied. Returns `"agreed"` (fold and address already agree — nothing appended) or `{repaired: {from}}` (one `owned` row appended, filed `Staff`; the edit ACL follows the fold, the moved-to account's owner sockets are severed). REFUSES (409) a construct (`not a room`) and a room whose suffix derives from no principal it ever named (a legacy 5-char draw, or a pre-derivation 8-char draw) — nothing is appended either way. Nothing else moves: address, log, album, places, term and the owner/billing index all stay. Idempotent, so it runs over every enduring room with no candidate list. Cost: one wake of the room's own DO plus one read of its log. |
| `Construct.rebuildFacetKv(slug)` | `Construct:rebuild_facet_kv` | `{keys, bytes}` | **Rebuild a construct's derived facet KV from its own event log.** `Self.kv` (`FACET_KV`) is a DERIVED read-model, written transactionally beside every `KvPut`/`KvDelete` event — but a WAL restore (`Construct.restoreWal`) lands the full history and folds the view, and used to leave FACET_KV empty (the fold intentionally never touches those two events). This reads every event in id order, clears FACET_KV, and replays it with the same `facet_kv_state` fn `restoreWal` now runs automatically after every import. Idempotent — run it on any construct, restored or not, with no ill effect. Returns the live key count and total value bytes. |
| `Construct.registerOwnerCard(slug)` | `Construct:register_owner_card` | `owner` (principal) | **Put a construct on its owner's index — its sidebar card and the burn walk's bill — whatever its `Carded` receipt says.** A `Construct.restoreWal` into a new slug imports the source's receipt, so the wake never cards the new key; every restore now relays the card itself, and this door heals constructs restored before that. Idempotent. REFUSES (409) an unowned or ephemeral construct (it bills nobody) and a room (its bill lands on its payer's index, craft#552). Read `UserAdmin.billingStanding` after. |
| `Construct.setCustomName(slug, name)` | `Construct:staff_set_custom_name` | `NameOutcome` | **Set, change or clear the name a ROOM answers at** (craft#538 R14). Same shape as `forceTransfer` and `quarantine`: a staff door, no settle, no owner ACL — and it appends the SAME `CustomNamed` fold event the paid door appends, so there is one name authority rather than two. Pass `""` to CLEAR. `slug` is the room's DO key (`{template}-{room}`); a CONSTRUCT is refused (`not_a_room`) — a construct is addressed by its own host and names itself. The name is vetted against `RESERVED_ROOM_NAMES`, the construct owner's own held-back list and the impersonation tiers, and refused if somebody else already holds it (`taken` — first-pay-wins, craft#538 R12). On success the KV alias is filed and the room's DRAWN address begins serving a **302** to the new one. |
| `Construct.recordLadder(slug, uid, durationMs, tracks)` | `Construct:add_ladder` | `null` | **Record a mirrored ladder as ONE album leaf** (craft#437 wave 3) — the mirror's RECORD stage. `uid` is Stream's video id and the segment prefix's own segment (1-64 lowercase alphanumerics, refused otherwise — it is an R2 key). `tracks` is `[{kind: {video:{height}} | {audio:{kbps}} | "sidecar", objects, bytes}]`, what the verify counted against each track's OWN playlist; the leaf's object count and total bytes derive from it, and they BILL — `media_bytes` sums them and the listable price floors on them. Latest-wins per uid: a re-mirror replaces the shape rather than doubling it. Staff-side because the counts are the platform's measurement, never an owner's declaration. Freed by `remove_ware_part` on the repair plane, which drops the leaf AND deletes its prefix. |
| `Construct.quarantine(slug, reason)` | `Construct:quarantine` | `null` | **The kill switch** (craft#21). Appends a `Quarantined` event then severs every open viewer socket — the construct is disabled INSTANTLY everywhere (commands rejected, UI → disabled notice), not just KV-eventual. `reason` is the staff audit note (WAL-only). Reversible. |
| `Construct.unquarantine(slug)` | `Construct:unquarantine` | `null` | Lift a quarantine (craft#21). Appends a compensating `Unquarantined` event and restores the UI; the WAL history (including the original `Quarantined` reason) is preserved. |
| `Construct.dmcaNotice(slug, notice)` | `Construct:dmca_notice` | `DmcaOutcome` — `{infringements, owner_terminated, restore_at_ms}` | **File a §512(c)(3) takedown notice** (craft#233). `notice` is `{work, material, complainant, signature, good_faith, accurate_under_penalty_of_perjury}` — every element the statute names, each its own field. Rust PARSES it at the boundary: a missing element is a 400 that says WHICH one ("it does not state the good-faith belief statement (§512(c)(3)(A)(v))"), never an accepted-and-lost record. A complete filing lands as a dated WAL row (the record IS the safe-harbour evidence), takes the material down through `quarantine`'s own rail (sockets severed, media 410, family cascaded — there is no second severance path), places the LEGAL HOLD that stops the room's own term-and-reap, and files ONE strike on the owner's account. Crossing the published repeat-infringer limit BANS that account with the cascade `UserAdmin.ban` uses. Compensated by `dmcaRetractNotice`. |
| `Construct.dmcaCounterNotice(slug, counter)` | `Construct:dmca_counter_notice` | `DmcaOutcome` | **File the subscriber's §512(g)(3) counter-notice.** `counter` is `{material, subscriber, signature, mistake_or_misidentification, consents_to_jurisdiction, accepts_service}`, refused by element exactly as the notice is. Records the filing and ARMS the restoration deadline (12 business days — inside §512(g)(2)(C)'s 10-to-14 window, weekend-skipping, with slack for holidays) on the construct's own alarm slot; when it fires the material comes back and the strike goes with it, with no human in the loop. **REFUSES (409) a construct that is not under a takedown** — there would be nothing to restore. Moves the count by itself: the `infringements` it returns is a read. |
| `Construct.dmcaRetractNotice(slug, reason)` | `Construct:dmca_retract_notice` | `DmcaOutcome` | **The notice was withdrawn, or resolved for the uploader** (craft#233) — `dmcaNotice`'s compensating sibling, and the reason a staff token may hold the filing verb at all: a notice raises a termination counter on an account the operator does not own, and §512(f) makes a knowing misrepresentation actionable. Takes back exactly ONE strike, and only one this construct still owes (a second call after the restoration clock already fired is a no-op, never a decrement of some other notice's strike), then lifts the takedown. Leaves the legal hold standing — `releaseLegalHold` is that fact's own verb. |
| `Construct.releaseLegalHold(slug, reason)` | `Construct:release_legal_hold` | `null` | **Release the §512 legal hold — the matter is closed** (craft#233). While the hold stands the construct has NO reap deadline at all: craft#553 gave every room a term and a reap, so expiry (not a purge) is how this material would normally vanish, and the hold is what stops that clock, the KV projection's own `expiration_ttl` included. Deliberately never lifted by the restoration clock — a timer that released a legal hold would be a timer that destroys evidence. Idempotent. |
| `Construct.verify(slug)` | `Construct:verify` | `null` | Append a `Verified` event bound to the construct's CURRENT UI content hash, then broadcast. "Genuine?" — the first rung of the trust pipeline (`verify` → `certify`; distinct from the decorative `grantAward`). A later content swap invalidates the verdict (new hash, old event). |
| `Construct.certify(slug)` | `Construct:certify` | `null` | Append a `Certified` event bound to the construct's CURRENT UI content hash, then broadcast. "Meets the rubric?" — the second rung of the trust pipeline, same hash-binding and invalidation-on-swap as `verify`. |
| `Construct.grantAward(slug, emoji, label)` | `Construct:grant_award` | `null` | **Grant a decorative reward badge** — stackable, orthogonal to the trust pipeline (`verify`/`certify`/`record_scan` are the trust verdicts; this is not one of them). `emoji` and `label` are free text you choose (no enum). |
| `Construct.revokeAward(slug, label)` | `Construct:revoke_award` | `null` | Revoke an award by its exact `label`. |
| `Construct.rescan(slug)` | `Construct:rescan` | `boolean` | **Re-enqueue a deep scan** of the construct's current UI (craft#23). The DO re-enqueues `{ slug, ui_hash }` to SCAN_QUEUE; the headless-browser + AI consumer re-classifies and posts a fresh verdict. `false` if there's no UI to scan. The manual trigger for a re-review. |
| `Construct.recordScan(slug, uiHash, modelJson, offHosts?, consoleErrors?, neurons?)` | `Construct:record_scan` | `ScanOutcome` — `{trust, current}` | Post a scan verdict DIRECTLY, bypassing the browser+AI consumer — the only way to exercise the `content_review` guard's adversarial cases (a `csae` category under a "Reviewed" recommendation; a forbidden "Certified"), since that guard lives in the wasm-only craft crate where no host test can reach it and the normal `rescan` path only ever delivers whatever the real model happened to say. Grants no new privilege beyond what staff already hold (`verify`/`certify`/`quarantine`). **The verdict is authoritative and a `Reject` AUTO-QUARANTINES** — drive this at a throwaway construct only. |
| `Construct.scanAudit(slug)` | `Construct:scan_audit` | `ScanAuditRecord[]` | Audit trail of deep-scan passes — evidence (off-origin hosts, console errors, AI notes) per scan; newest-first, capped at 50. |
| `Construct.moderationQueue(slug)` | `Construct:moderation_queue` | `ModerationQueue` | **The T&S triage read** (craft#235) — `{reports, appeals, open_reports, overdue_appeals}` folded off this construct's own WAL. There is no second store: a report is the `Reported` row a viewer filed at `/-/report`, an appeal the `Appealed` row its owner filed at `/-/appeal`, and each carries the outcome that closed it. Every appeal past its deadline with no outcome comes back `overdue: true` — that count is the number this rail exists to make visible rather than silent. |
| `Construct.closeModeration(slug, subject, upheld, note)` | `Construct:close_moderation` | `true` | **Answer one filing** (craft#235). `subject` is the report or appeal's row id from `moderationQueue`; `upheld` is the verdict; `note` is the recorded reason (required). Refuses an id this construct never recorded, and one already answered. It ENFORCES nothing — `quarantine`/`unquarantine` are the enforcement verbs, and upholding a report is carried out through them. |
| `Construct.export(slug)` | `Construct:export` | `{slug, name, declares, facet, contract, recreate}` | **Download a construct's recreate-from-scratch definition** — the author-declared knobs (`declares`: `players`, `turns`, `spawns`, `host_caps`, `ui`) + the **verbatim facet code** + the shared facet `contract` + one-line `recreate` instructions. NOTHING runtime-derived (no event stream, no render — a played stream is a *consequence* of the construct, not an input to rebuild it). The staff binding is ACL-BYPASSING — it exports ANY construct, including un-owned platform/system ones. The owner-scoped, ACL-checked counterpart is `Construct.export(slug)` on the **per-user** `/-/user/agent` gateway (same `authoring_allows(SET_UI)` gate as `setFacet` — you may export only a construct you author; another user's source returns a 403). Use it to hand an AI a construct as a working build plan / training aid. |
| `Construct.exportStream(slug, after?, limit?)` | `Construct:export_stream` | `{rows, next, total}` | **The construct's RAW event stream** (craft#203) — the backup/recovery read, and a categorically different thing from `export`: that is a rebuild *recipe*, this is every message, every membership change and every principal that ever acted there. `rows` are `{id, event}` verbatim and unfiltered (`applied_page` drops kinds; a backup that omits kinds is not a backup). `after` = the previous page's `next` (`""` from the beginning), `total` rides EVERY page so a truncated export is distinguishable from a finished one, `limit` is clamped server-side at 250 — page on `next`, never on `rows.length`. An unparseable `after` is an ERROR, never a silent restart. ACL-BYPASSING like `export`, so a platform-owned or abandoned construct is recoverable; and unlike every other admin read it does NOT fold the stream first — a construct whose events no longer fold is exactly the one whose history most needs getting out. The owner-scoped counterpart is `Construct.export_stream(caller, …)`, gated on the same `SET_UI` leaf as `setFacet` **minus** `export`'s `example`-award public branch. The same rows the R2 archive stores, so what you read here is what a recovery re-folds. |
| `Construct.restoreWal(slug, prefix, rows, reason)` | `Construct:restore_wal` | `{slug, source, genesis, rows, owner, name}` | **The READER leg of the backup (craft#203) — fold an archived WAL back into a FRESH construct.** `prefix` is the `_wal/{slug}/{genesis}/` string the erase record prints; `rows` is the row count that record declared reached cold storage and is LOAD-BEARING (the surviving keys tile themselves whether or not an object was deleted from under them, so the count is the only witness that cold storage still holds what it was told to); `reason` is REQUIRED and is written to a permanent per-act `restore:{slug}:{restored_ms}` record BEFORE anything lands. **REFUSES a target that holds any history of its own** — a merge interleaves two streams by id and afterwards neither can be told apart or taken back out, so restore into a fresh slug. A separate cap on its own CLASS, exactly like the two erase verbs, and on a SEPARATE axis from them: with any other `Construct:*` cap the method is not on the binding at all. Returning at all is the guarantee — the DO re-folds its own restored stream and refuses unless the bytes match the archive's fold. |
| `Construct.getView(slug)` | `Construct:get_view` | `ConstructView` | **ACL-bypassing read of a construct's folded view** (craft#267) — source, members, caps, trust tier, and the `state_provenance` triple. The staff plane could not read this at all until now, which is how craft#260 came to be verified by a child reloading a page. Pure read. |
| `Construct.describe(slug)` | `Construct:describe` | `ConstructDescriptor` | **ACL-bypassing read of a construct's DECLARED command surface** (craft#267) — what an agent may drive and with what payload. The structured sibling of `getView`. Pure read. |
| `Construct.auditPage(slug, limit?, before?)` | `Construct:audit_page` | `{rows, next}` | **The construct's governance trail** (craft#240) — every fact that grants, revokes or re-terms who may reach it and with what authority: `owned`, `member_added`/`member_removed`, `ownership_offered`/`ownership_accepted`/`ownership_transferred`, `role_granted`/`role_revoked`/`role_granted_until`, `pass_granted`, `price_set`, `audience_set`, `source_visibility_set`, `quarantined`/`unquarantined`, `serving_suspended`/`serving_resumed`. Oldest→newest. ACL-BYPASSING like `export` — reads ANY construct's trail, which is what a T&S review of a construct nobody will hand over needs. `row.actor` is ALWAYS empty: the WAL recorded WHAT changed, never WHO filed it, so this answers "what changed and when" (`id` is UUIDv7 — it sorts by mint time), never "who did it". `limit` budgets RAW events (clamped server-side), NOT rows returned — page on `next` until it comes back empty, never on `rows.length`; a window of pure gameplay answers `rows: []` with a live cursor. The owner-scoped counterpart is the web route `GET /-/audit`, gated on the same owner-only `ADD_MEMBER` leaf `add_member` enforces. |

### UserAdmin — account-level moderation (`env.UserAdmin`; UserDO, keyed by account)

The account-level trust-and-safety kill switch, **one level up from `Construct.quarantine`** (craft#22), plus the account-side ledger and index surface. Addresses an arbitrary account's `UserDO[account]` by key (exactly as `user_rpc(env, account)` does in Rust) — distinct from the self-scoped per-user `User:` caps (those bake the caller's own key), so this is staff-only and never a web route. `suspend`/`ban` restrict the account (the top-priority `restricted` leaf blocks every account command) AND cascade-quarantine the account's owned constructs; `reinstate` lifts both. Those three are idempotent; **the two credit verbs deliberately are NOT** — a repeated call grants again.

`account` is a **PRINCIPAL** (the 64-hex UserDO id), never an email — emails are credentials, not accounts. Resolve one with `resolveCredential` first.

| Method | Capability | Returns | Notes |
|---|---|---|---|
| `UserAdmin.suspend(account, reason)` | `UserAdmin:suspend` | `null` | Suspend an account (reversible hold). `reason` is the staff audit note (WAL-only). Restricts every command + cascade-quarantines owned constructs. |
| `UserAdmin.ban(account, reason)` | `UserAdmin:ban` | `null` | Ban an account (terminal verdict — same enforcement as `suspend`, distinct event). |
| `UserAdmin.reinstate(account)` | `UserAdmin:reinstate` | `null` | Reinstate a suspended/banned account — lifts the restriction AND cascade-un-quarantines its owned constructs. |
| `UserAdmin.unregisterConstruct(account, slug)` | `UserAdmin:unregisterConstruct` | `null` | **Drop a dead slug from an account's owner index** — the account-side counterpart of `Construct.purge`. `admin_purge` already unlinks the index, but it reads the owner from the CONSTRUCT's folded view and guards on `!owner.is_empty()`, so once a DO is emptied the row is unreachable by re-purging. A construct purged before that unlink shipped (2472bd1, 2026-07-23) leaves a row naming nothing: a dead sidebar card, a 404 route, and a slug the burn walk still wakes a DO to `billing_probe` every sweep. This is the only door to those rows. Idempotent (the fold retains-out by key). **Verify the slug is actually dead first** — a staff `Construct.export` that fails with "own manifest: construct not found" is the check; never unregister a construct that still resolves. |
| `UserAdmin.resolveCredential(email)` | `UserAdmin:resolveCredential` | `principal \| null` | Email → principal. Warms `CREDENTIAL_ALIAS` KV first, falls back to the `CredentialRegistry` shard. `null` = no account bound to that address. |
| `UserAdmin.releaseCredential(email)` | `UserAdmin:releaseCredential` | `{released, email, principal?}` | **Unbind an address from the account holding it** — the only way an account becomes un-claimed, and so the only way the platform ever reclaims one. There is NO account-delete verb and deliberately so: identity-of-record is never destroyed by hand (`user.rs`'s idle reaper is explicit about this). This frees the address AND folds the credential out via `revoke_credential`; an account left holding no credentials is un-claimed, which is what `should_idle_evict` gates on (`!claimed`), so the existing 7-day idle TTL reaps the DO on its own alarm. **Nothing is deleted synchronously.** Registry-first internally: the shard is the uniqueness Authority, so a half-failure frees the address while the account merely stays claimed (harmless, retryable) rather than the reverse (an evicting account behind an address that still resolves to it). Idempotent — an unbound address returns `{released:false}` with a reason, never an error. |
| `UserAdmin.grantCredits(account, micro, description)` | `UserAdmin:grantCredits` | grant outcome | Staff comp on a PRINCIPAL: appends `CreditsGifted{Issued{by, description}}`, counts toward `funded()`. `description` is open text recording what it was for — a reward, a stipend, an apology are all THIS call, never a verb per occasion. `by` is baked from the verified CF Access identity, never a script argument. µUSDC (1 Credit = `1_000_000`). NOT idempotent. |
| `UserAdmin.issueCredit(emails, micro, description)` | `UserAdmin:issueCredit` | `{micro, deliveries[]}` | The same grant addressed to **MAILBOXES** instead of principals — the right shape when the recipient may have no account yet. Per address: resolve → credit-or-invite → email either way. An address with an account is credited; one without is minted a single-use credit voucher whose `/redeem` link lands the IDENTICAL `Issued{by, description}` fact. Outcomes are **externally tagged**: `deliveries[0].Invited.code`, never `.code`. A failed send leaves a durable grant and `notified:false`. NOT idempotent — a retry double-grants. |
| `UserAdmin.resendInvite(email, code)` | `UserAdmin:resendInvite` | `{email, micro, description}` | **Re-send a LIVE invitation** after `issueCredit` reported `notified:false` — the grant landed, the email did not. A notification, NEVER a grant: the voucher is peeked non-consumingly, so `remaining_uses`/`expires_at_ms` are untouched and no credit moves. The amount and reason are READ off the voucher, so a resend cannot misstate what somebody was given, and a code that is not live cannot be re-advertised. Naturally idempotent — the exact opposite of `issueCredit`. Throws `409` naming the actual state: unknown code, expired, **already redeemed** (the recipient HAS the credit; only the email failed), or a play-pass pool. INVITE branch only — an address that already holds an account has the credit on its meter, so its recovery is to re-issue or write to them. |
| `UserAdmin.tos_state(account)` | `UserAdmin:tos_state` | `{accepted_tos_hash, live_hash, current}` | Staff diagnostic read (craft#51). |
| `UserAdmin.roomBudget(account, template, ceilingMicro)` | `UserAdmin:roomBudget` | `RoomAdmission` | **craft#430's mint boundary, asked** — would this account carry one more room from `template` at `ceilingMicro`? Writes nothing and mints nothing, so it is safe to aim at a live account. `"Admitted"` or `{Refused: …}`, where `{Refused:{Committed:{committed, budget}}}` names what that template's still-standing rooms already hold of the account's declared budget and what the budget is — so passing a ceiling LARGER than the budget is how you read both numbers back. `{Refused:"NoRunway"}` is an account that is dark (ceiling breached or credits gone); `{Refused:"Tripped"}` is that one template's own breaker. This is the bound the per-colo `SPAWN_LIMITER` never was: it lives in the payer's own single-threaded DO, so a caller spread across every datacentre meets one answer. |
| `UserAdmin.billingStanding(account, construct)` | `UserAdmin:billingStanding` | `{card, rooms}` | **Is this account BILLED for `construct`** (craft#549) — the burn walk's own two halves: `card` is `"owned"` (the row `AccountView::constructs` sums from — this account pays), `"shared"` (a COLLABORATOR pointer the walk skips, which is exactly what a half-moved sale used to hand the buyer while the seller kept paying) or `"none"`; `rooms` is how many of that construct's standing rooms sit on this ledger. The read half of the index `unregisterConstruct` writes to and shipped without — its own worked example names `list_my_constructs`, a read staff never had. Pure: no `note_active`, no alarm, safe to aim at a live account. Ask it of BOTH parties across an ownership move and the two answers must not agree. |
| `UserAdmin.designateSystemAccount(account)` | `UserAdmin:designateSystemAccount` | `boolean` | **Mark `account` as the platform's own** (craft#435). Appends `SystemAccountDesignated`, which `AccountView::is_system_account` reads to exempt this account from `grace_expired`, `ceiling_breached`, and `is_billing_dormant` — the platform's own account is never purged, never dormancy-latched, never ceiling-capped. **The exemption stops at enforcement: billing is untouched.** Burn still accrues, every construct the account owns still meters exactly as before — this waives no bill, it only stops the platform paying itself down to zero and getting reaped for it. There is no un-designate: a fifth axis on its own cap, absent from the binding unless declared, same law as `grantCredits`/`issueCredit`/`releaseCredential`/`unregisterConstruct`. `true` = newly designated; **`false` = already designated (no-op, no second append, never an error)**. Either way it then ADOPTS every platform-owned construct — the six `PlatformPath` surfaces plus `platform`, the app host's own accounting identity — onto this account (craft#442), so this ONE call is the whole bootstrap and no per-surface `Construct.claim` follows it. It is the one step a fresh environment cannot do for itself: which account is the platform's is not derivable, and `System.platformPrincipal()` returning `null` is how an environment says it is still undone. |

### Craft — Code Mode catalog dispatch (`env.Craft`; AuthoringBinding)

One method routes a named catalog tool through the same Rust dispatch `/-/mcp` uses (craft#109) — one catalog, one dispatch path. `caller`/`caps` are baked into the isolate's `ctx.props` from the VERIFIED CF Access identity at gateway construction time, never taken from the script.

| Method | Capability | Returns | Notes |
|---|---|---|---|
| `Craft.call(name, argsJson)` | `Craft:call` | tool-specific result | Dispatch catalog tool `name` with `argsJson` (object or JSON string) through the Code Mode authority seam. Runs per-identity ACL like the user surface, **NOT an admin bypass** — unlike every other cap on this list, this one grants the SAME catalog a claimed-email user reaches, executed as staff's own baked identity; the tool itself self-gates on the baked `CallerCaps` at the Rust dispatch seam. |
| `Craft.call(name, argsJson)` | `Craft:repair` | tool-specific result | craft#511 REPAIR: the SAME method, acting as the TARGET CONSTRUCT'S OWNER instead of as staff — the staff path for every author-facing write verb (files, facet, ui, manifest, media, roles, members, marketplace), which no `admin_*` twin covers. Declaring it **requires `reason` (1-500 chars) in the POST body**, or the gateway 403s at the door. Before each write, `ConstructEvent::StaffRepaired { verb, reason }` is appended to the target's own WAL filed by `EventActor::Staff`, and the owner identity the call then acts as IS that append's return value — a failed record refuses the write. Reads, construct-MINTING verbs (`create_construct`, `copy_construct`) and account verbs (`set_display_name`, wallet, vouchers) are untouched: they run as staff, exactly as with `Craft:call`. The reason is per RUN and folded into the isolate hash. |

### Scope-to-Capability Mapping

Only the `admin` scope exists on `/-/agent`. The admin rail MAY declare every capability above (System + Replay + Fleet archive frontier and reseal + Sandbox + Construct admin + UserAdmin + Craft catalog dispatch + Craft repair). Non-admin callers are rejected at the CF Access layer before any `/-/agent` code runs. What a declared cap actually PROVISIONS is the binding, at the class selected by what was declared — see the two exceptions in **Key rules** above (`Construct`'s erase/restore ladders, `UserAdmin`'s mint/unbind axes), where the method is absent rather than refused.

## Examples

### Read system diagnostics

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    return await this.env.System.status();
  }
}
// capabilities: ["System:status"]
```

Response shape (abridged — log/timeline arrays trimmed to one row each):
```json
{
  "ok": true,
  "result": {
    "version": "2.0.306",
    "started_at_ms": 1779494700462,
    "initiated_history": [1779549737409, 1779549769260],
    "last_initiated_ms": 1779549769260,
    "last_ping_at_ms": 1779633930970,
    "now_ms_utc": 1779634900000,
    "head_event_id": "019e5ad4-5bd9-74b2-a657-5b0b536e0259",
    "recent_events": [{ "id": "019e5ad4-5bd9-74b2-a657-5b0b536e0259", "label": "Ping (key=6dbb8a7e)", "at_ms": 1779633930970 }],
    "connected_viewers": 4,
    "socket_count": 0,
    "viewers": [{ "cid": "b23efa", "connected_at_ms": 1779634682476 }],
    "cadence": "rare"
  }
}
```

`connected_viewers` is presence by **recency** (tabs that reconnected within their advertised `retry:` window), while `socket_count` is the raw count of live bridge sockets — these diverge by design when the idle backoff has closed sockets but the tabs are still open (above: 4 viewers, 0 live sockets, `cadence: "rare"`).

### Trigger a ping (visible on /-/health pages)

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    // Omit key for a one-shot ping, or pass a stable key for idempotent retries.
    return await this.env.System.dispatch("ping", "", "", undefined);
  }
}
// capabilities: ["System:dispatch"]
```

Response shape: `{ "wire": "<sse morph string>", "accepted": true, "event_id": "019e5ad5-1955-7682-a644-0e59e12ad12f", "replayed": false }`. The `event_id` is a **UUIDv7 string** (compare as strings, never coerce to `Number`); it is `null` on a replay or a rejected command. Open `https://craft.everygoodwork.io/-/health` in a browser, then submit the script — the "last ping" row morphs to your local time immediately, no reload.

### Adopt an abandoned construct, then re-kind it

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const owner = "<64-hex principal — resolve the email via the CREDENTIAL_ALIAS KV first, never pass an email>";
    const claimed = await this.env.Construct.claim("pong", owner); // false if already owned
    const reKinded = await this.env.Construct.setKind("pong", "Shared");
    return { claimed, reKinded };
  }
}
// capabilities: ["Construct:claim", "Construct:set_kind"]
```

### Trust-and-safety: quarantine a construct, badge another, rescan

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const killed = await this.env.Construct.quarantine("phishy-slug", "reported: fake login");
    const awarded = await this.env.Construct.grantAward("gospel", "🐟", "family_friendly");
    const rescanned = await this.env.Construct.rescan("starter");
    return { killed, awarded, rescanned };
  }
}
// capabilities: ["Construct:quarantine", "Construct:grant_award", "Construct:rescan"]
```

### Download a construct as a build plan / training aid

Pull a live construct's complete definition (declaration + verbatim facet + the contract) so it can be used as a worked plan to recreate it or to learn how constructs are built. `ttt` is the canonical specimen — multiplayer, declared turns, event-sourced, replayable.

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() { return await this.env.Construct.export("ttt"); }
}
// capabilities: ["Construct:export"]
```

One-liner to download it straight to a file (after `login.sh` — see Authentication):

```bash
jq -n '{code:"import { WorkerEntrypoint } from \"cloudflare:workers\";\nexport default class extends WorkerEntrypoint { async run() { return await this.env.Construct.export(\"ttt\"); } }", capabilities:["Construct:export"]}' \
| curl -s -X POST "${BASE}/-/agent" \
    -H "CF-Access-Client-Id: ${CLIENT_ID}" -H "CF-Access-Client-Secret: ${CLIENT_SECRET}" \
    -H "Content-Type: application/json" --data-binary @- \
| jq '.result' > ttt.construct.json
```

The resulting `ttt.construct.json` is self-contained: `declares` (what to set), `facet` (the code to submit verbatim), `contract` (the `Self` API + doctrine), and `recreate` (the authoring rail). Hand it to an AI and it has everything to build the construct again — no other craft context required.

`quarantine` is instant + global (event-sourced + live-socket sever); `unquarantine` reverses it with the WAL history intact.

### Account-level kill switch: ban an account (cascades to its constructs)

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    // `account` must be a PRINCIPAL — idFromString throws on an email; resolve first.
    const principal = await this.env.UserAdmin.resolveCredential("badactor@example.com");
    if (!principal) return { skipped: "no account bound to that address" };
    // ban restricts every command + cascade-quarantines owned constructs; reinstate lifts both.
    return await this.env.UserAdmin.ban(principal, "repeat phishing");
  }
}
// capabilities: ["UserAdmin:resolveCredential", "UserAdmin:ban"]
```

### Clear orphan owner-index rows (dead sidebar cards / 404 routes)

Rows in `list_my_constructs` naming constructs that no longer exist. Each one is a dead card, a 404 route, and a slug the burn walk wakes a DO to `billing_probe` every sweep. **The script is self-guarding**: it re-verifies each slug is actually dead immediately before dropping its row, so a wrong candidate list can never unregister a live construct.

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const principal = await this.env.UserAdmin.resolveCredential("owner@example.com");
    const candidates = ["ap63h", "qhova", "mdt6s"]; // from list_my_constructs
    const dropped = [], keptAlive = [];
    for (const slug of candidates) {
      let dead = false;
      try {
        await this.env.Construct.export(slug); // ACL-bypassing; resolves iff a manifest exists
      } catch {
        dead = true; // "own manifest: construct not found"
      }
      if (!dead) { keptAlive.push(slug); continue; } // NEVER unregister a live construct
      await this.env.UserAdmin.unregisterConstruct(principal, slug);
      dropped.push(slug);
    }
    return { dropped, keptAlive };
  }
}
// capabilities: ["UserAdmin:resolveCredential", "Construct:export", "UserAdmin:unregisterConstruct"]
```

Distinguish the cause before reaching for this. A missing manifest means the construct was REMOVED, never that it was never authored — `relay_construct` writes the manifest at birth, so a freshly minted slug exports immediately. Rows like these are pre-`2472bd1` (2026-07-23) purge residue, from before `admin_purge` learned to unlink the index.

### Push a platform construct UI (ACL-bypassing staff deploy)

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    // Staff path for un-owned PLATFORM constructs; for one YOU own, use /-/user/agent's setUi.
    await this.env.Construct.setUi("editor", "<div>…new editor chrome…</div>");
    return { ok: true };
  }
}
// capabilities: ["Construct:set_ui"]
```

### Replay regression: measure a code change

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const id = "smoke";
    const rec = await this.env.Replay.captureRecording();
    await this.env.Sandbox.load(id, rec);
    const baseline = await this.env.Sandbox.play(id);
    // … redeploy code, run again as a second invocation, then diff …
    return { commands: baseline.counts.commands_executed, events: baseline.counts.events_appended };
  }
}
// capabilities: ["Replay:capture", "Sandbox:write", "Sandbox:run"]
```
