---
name: qc-loop
description: >
  Data-driven performance loop for the craft project. Use when asked to optimize, speed
  up, stress-test, or measure a craft hop (ping/pong, /command dispatch, connect-fold, any
  DO RPC), or to check whether a change made a measurable difference. Triggers: "run the qc
  loop", "is X faster", "optimize the ping path", "stress test pong", "did that help",
  "baseline this". Enforces measure-first discipline over the QC telemetry (GET /qc) + the
  /agent gateway + Chrome /health driver.
---

# qc-loop

The loop for changing craft performance **only when the data says to**. Never theorize a
fix, change code, and hope. Measure → decide → change → re-measure → prove.

Built on the external telemetry path (craft writes nothing internal): the qc-tail Worker
writes per-hop rows to Analytics Engine; `GET /qc` reassembles them. You drive load, then
read truth from outside the box.

## The five steps (do them in order)

1. **Capture a FRESH baseline.** Never trust a committed baseline file as the current
   number — code drifts, baselines go stale (a committed "9ms ping" was really 2.4ms after
   a fold was dropped). Old baselines are a *record of what we measured and why*, not a live
   target. Re-run the live capture every time. → `references/capture.md`.
2. **Analyze per `component × hop`.** Read `do/<verb>` cpu+wall, the `rpc`/`worker`
   wrappers, and the connect/SSE hops. Attribute with the control-boundary read in
   `references/capture.md`. Write down where the time actually is.
3. **Decide from the data alone.** Honor the hard rules below. Most "obvious" optimizations
   are below the noise floor or target a hop that isn't the cost. The honest output is
   sometimes "this path is already optimal; the real cost is elsewhere" — say that.
4. **Implement** the one change the data justifies. Match existing craft patterns (no
   band-aids, find the sibling pattern first).
5. **Deploy + re-run the IDENTICAL capture, then prove the outcome.** Version-gate first
   (confirm prod serves the new version, discard warmup). Diff candidate vs baseline per
   `component × hop`. Optionally prove determinism with a `Sandbox.play` before/after
   RunReport diff (`references/sandbox-diff.md`). Save the run as a dated record under
   `docs/superpowers/baselines/YYYY-MM-DD-qc-baseline.md` (`references/capture.md`).

## Hard rules (the discipline — violating these is how you fail)

- **Kill your tails.** When you're spiraling theories (cache? serde? brotli?), STOP. Go
  back to step one and walk the path from the first call. The cost is upstream of the
  symptom, behind an assumption you forgot you made. (Cloudflare Chronicles: *Stop Chasing
  Your Tails*.)
- **CPU noise floor ≈ 0.25–1.8ms.** Identical builds vary that much at `do/<verb>`. NEVER
  claim a sub-ms cpu win as proven. Only multi-ms deltas clear the noise. 9→2.4ms is real;
  2.4→2.1ms is noise.
- **`wall ≫ cpu` means storage/broadcast/platform**, not your code. Don't chase wall with
  code — it's the SQLite commit + SSE fan-out through the DO output gate.
- **A DO cannot time itself** (Cloudflare freezes the clock during sync compute). All
  measurement is external — that's why this loop exists. Never add internal telemetry.
- **No win is "proven" from one window.** Re-run; confirm the delta repeats.

## Tools

- `scripts/drive.sh` — server driver: fires `ROUNDS × PINGS` actions via `/agent`,
  records `t0`/`t1`, settles, prints the exact `GET /qc` window. Defaults to ping/pong;
  override the action for any hop (see its header). Dependency-light (no `bc`).
- `scripts/report.sh <from> <to> [tag]` — queries `GET /qc` and prints the aggregate
  table. Needs `CRAFT_SESSION_COOKIE` set (see Auth below) — without it, it refuses to
  run and names the missing credential rather than printing an empty table.
- Chrome client driver (the UI `/command → dispatch` path) is driven by you via the
  claude-in-chrome MCP — `references/capture.md` has the click sequence, and is also
  the preferred way to read `GET /qc` itself (see Auth below).

Auth — TWO separate trust boundaries, do not conflate them:
- **`/agent`** (drive.sh, the staff gateway): CF-Access service token —
  `bash ~/.claude/skills/craft-agent/scripts/login.sh` first.
- **`GET /qc`** (report.sh / the browser read): `SessionAuth`, the `__Host-craft_session`
  cookie a signed-in browser holds. The CF-Access token above does NOT satisfy it. Read
  `/qc` from the already-authenticated Chrome client-driver tab via a same-origin
  `fetch()` (carries the HttpOnly cookie automatically — `references/capture.md` step
  4), or export the cookie value into `CRAFT_SESSION_COOKIE` for `report.sh`.

## Per the project workflow

Deploy to verify in prod, report the before/after with evidence, then commit and push via /commit without asking. (CLAUDE.md git workflow.)
