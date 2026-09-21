# Capturing a baseline

The dual-driver run, what the QC rows mean, how to attribute a delta, and how to record it.

## Run it (dual driver)

Run both **concurrently** so one window holds every hop. Close stray `/health` tabs first
(background reconnects inflate the `do/<verb>` wall tail on the single-threaded DO).

1. **Auth:** `bash ~/.claude/skills/craft-agent/scripts/login.sh`
2. **Server driver** (terminal, backgrounded): `bash scripts/drive.sh`
   It prints `t0`, fires the rounds, settles, and prints the `report.sh` command.
3. **Client driver** (you, via claude-in-chrome MCP), concurrently with step 2:
   - `tabs_create_mcp` → `navigate` to `https://craft.everygoodwork.dev/health`
   - `find` the "⚡ Trigger Ping" button (or screenshot for its coords)
   - Click it ~20 times, ~3s apart, in `browser_batch` chunks of ~5 clicks
     (`left_click` + `wait 3`). Keep batches short — a long batch can drop the extension
     connection mid-run; if it disconnects, screenshot to reconnect and resume with
     coordinate clicks.
   - This exercises `POST /command → dispatch` and the client-side timing ingest
     (`POST /qc/run`) — the rows the server driver alone can't produce.
   - Close your tab when done (`tabs_close_mcp`) so you don't leave a stale viewer.
4. **Read.** `GET /qc` is gated by `SessionAuth` (the `__Host-craft_session` cookie a
   signed-in browser holds) — a DIFFERENT trust boundary than the CF-Access service
   token that drove step 2/3's `/agent` calls. CF-Access headers do NOT satisfy
   `SessionAuth`; a bare `curl` against `/qc` 401s (craft#378). Two ways to read it:
   - **(preferred) From the still-open Chrome client-driver tab** — a same-origin
     `fetch()` executed there via the claude-in-chrome MCP `javascript_tool` carries the
     HttpOnly session cookie automatically, no export needed:
     ```js
     const from = <t0>, to = <t1>;
     const r = await fetch(`/qc?from=${from}&to=${to}`, { credentials: 'same-origin' });
     if (r.status !== 200) throw new Error(`GET /qc -> HTTP ${r.status}: ${await r.text()}`);
     const { rows } = await r.json();
     rows.map(x => ({ component: x.component, hop: x.endpoint || '(event)', n: x.samples,
       p50_wall: x.p50_wall, p95_wall: x.p95_wall, p99_wall: x.p99_wall,
       avg_cpu: Math.round(x.avg_cpu * 100) / 100, p95_cpu: x.p95_cpu }));
     ```
     Add `&raw=1` for per-observation rows.
   - **Or `report.sh`**, if you have already extracted the session cookie value manually
     (browser DevTools → Application → Cookies → `__Host-craft_session`) into
     `CRAFT_SESSION_COOKIE`: `CRAFT_SESSION_COOKIE=<value> bash report.sh <from> <to>`.
     Without it, `report.sh` refuses to run and names the auth failure — it never prints
     a silently-empty table. `RAW=1 CRAFT_SESSION_COOKIE=<value> bash report.sh ...` for
     per-observation rows.

For a quick CPU-only check, the server driver alone is enough (it produces the `do/<verb>`
headline) — but you still need step 4's browser read, since `report.sh` alone cannot
authenticate. The client driver's tab is what makes the full table + the UI-path
equivalence possible in one pass.

## What the rows mean

`report.sh` aggregates per `component × hop`. Wall = elapsed (includes I/O waits); cpu =
actual compute (the in-control number).

| component | meaning |
|---|---|
| `do` + `<verb>` | the Durable Object handler — **your code.** The headline. |
| `do` + `(event)` | DO lifecycle events (ws-close etc.); ~0. |
| `rpc` | the typed SystemBinding forwarding the call; ~0 cpu (pure forward). |
| `worker` + `/command` | the UI hop wrapping `dispatch`; ≈ do + ~0. |
| `worker` + `/agent` | the gateway holding all N pings of one round (high wall, expected). |
| `do` + `/health/events` | WS upgrade + snapshot fold — the **connect** cost (scales with history). |
| `worker` + `/health/events` | the held SSE down-channel stream (~minute wall, low cpu — the hold, not latency). |

## Control-boundary read (attribute a delta)

- `cpu` ↑ at `do/<verb>` → your code (serde / lite3 / query shape / render). In control.
- `cpu` ↑ at `do /health/events` → the per-connect `current_status` fold; scales with
  log/connection history → the LiveSet lever (craft#13).
- `wall` ↑ but `cpu` flat → storage commit / broadcast / placement → platform.
- `worker/command` wall ↑ but `do` flat → edge/network/RPC transport, not DO logic.
- `Outcome=overloaded` or growing `do/(event)` backlog → single-threaded DO saturation → shard.

## Record the run

Save a dated record at `docs/superpowers/baselines/YYYY-MM-DD-qc-baseline.md`: subject
(version + commit), the ACTION SCRIPT used, the table, and the one-line read of where the
time is. Banner-flag the previous record as superseded so nobody diffs against its stale
numbers. These files are the audit trail of *what we measured and why* — **never** the live
target. Always re-capture fresh (step 1) before judging a change.
