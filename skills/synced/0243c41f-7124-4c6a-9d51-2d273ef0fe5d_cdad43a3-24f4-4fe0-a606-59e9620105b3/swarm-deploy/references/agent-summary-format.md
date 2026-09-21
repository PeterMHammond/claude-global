# Agent Summary Format

When an agent completes, it outputs a structured summary. The lead uses these
summaries to decide whether to proceed to the next phase or intervene.

---

## Required Summary Format (agents output this)

```
AGENT SUMMARY: [AGENT-NAME]
Status: COMPLETE | BLOCKED | PARTIAL
Commit: [short commit hash]

Files modified:
- src/path/to/file.rs: [what changed]

Output contract delivered: YES | NO | PARTIAL
[explanation if not YES]

Discovered issues for lead:
- [issue 1]
- [issue 2, or "none"]

Cargo check: PASS | FAIL
[first 10 lines of errors if FAIL]
```

---

## Lead Interpretation Guide

### All agents: COMPLETE, cargo check: PASS
→ Proceed to next phase immediately.

### Any agent: BLOCKED
→ Stop. Read the discovered issues. Resolve the blocker manually before
  continuing. Do not start Phase C if any Phase B agent is BLOCKED.

### Any agent: PARTIAL
→ Read the discovered issues. Decide whether to:
  a) Have the agent continue with a corrected prompt
  b) Handle the missing piece in Phase C or manually
  c) Merge what exists and open a follow-up issue

### Any agent: cargo check FAIL
→ Do not merge that branch. Paste the error back to the agent with:
  "Fix the following cargo check errors. Your file ownership has not changed.
   Do not modify any off-limits files."

### Output contract NOT delivered
→ This is a blocking issue. Phase C agents and any agents that depend on
  this contract cannot proceed. Resolve before merging.

---

## Aggregated Phase Gate Check

Before merging Phase B and starting Phase C, verify:

```
Phase B Gate:
[ ] worker-handler: COMPLETE, cargo PASS, contract YES
[ ] durable-object: COMPLETE, cargo PASS, contract YES
[ ] No agent reported files modified outside their ownership list
[ ] No unresolved discovered issues that affect Phase C

→ If all checked: proceed to Phase C dispatch
→ If any unchecked: resolve before proceeding
```
