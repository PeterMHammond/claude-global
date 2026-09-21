# Proving an outcome with the Replay Sandbox (Mode 2)

QC tells you *latency* changed. The Sandbox tells you *behavior* didn't (or did) — a
before/after `RunReport` diff over the **real runtime**, on a throwaway instance that never
touches production. Use it when a perf change must be proven byte-identical (same events,
same counts) and not just faster. All via `/agent` (see the craft-agent skill).

## The loop

1. **Capture a recording** of the real command stream:
   `Replay.captureRecording()` → `RecordedCommand[]` (keeps keys, payloads, `at_ms`).
2. **Load + play (baseline)** on a sandbox id, keep the report:
   `Sandbox.load(id, rec)` → `Sandbox.play(id)` → keep the `RunReport` as **baseline**.
3. **Change code, redeploy** (version-gate prod first).
4. **Play again (candidate)** on the same recording → keep the second `RunReport`.
5. **Diff:** `Sandbox.diff(id, baseline, candidate)` →
   `{ok, first_divergence, counts_match, decisions_match}`. Volatile ids/time are excluded,
   so a real before/after-code comparison is meaningful.
6. **Discard:** `Sandbox.discard(id)` when done.

## What the diff proves

- `ok` / `counts_match` / `decisions_match` true → the change is behavior-preserving; any
  QC latency delta is a pure perf win (or regression) with no semantic drift.
- `first_divergence` set → the change altered the event stream — investigate before
  claiming the perf number; you changed *what* it does, not just *how fast*.

## Safety

The sandbox is the **same DO class** keyed `replay-sandbox-<id>`, never the `system` key —
production is physically untouched (binding prefix + DO self-id check). `seek`/`step` are
non-destructive scrubbing; `play`/`fork` commit by truncating forward of the playhead and
re-executing through the genuine `run_command` path.
