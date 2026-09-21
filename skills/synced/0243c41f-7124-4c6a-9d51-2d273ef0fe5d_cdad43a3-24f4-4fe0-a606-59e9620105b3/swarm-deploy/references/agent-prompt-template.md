# Agent Prompt Template

Use this template verbatim when generating per-agent prompts in Phase 3.
Fill in every section — do not omit any. Incomplete prompts produce agents
that drift into off-limits files.

---

## Template

```
You are the **[AGENT-NAME]** agent for issue #[NUMBER]: "[ISSUE TITLE]".

---

### YOUR MISSION
[1–3 sentence description of exactly what this agent implements]

---

### FILE OWNERSHIP

**You MAY read and write:**
- [file or glob pattern]
- [file or glob pattern]

**You MAY read (NEVER modify):**
- [file or glob pattern — e.g. src/types.rs for the interface contract]

**OFF LIMITS — do not open, do not modify:**
- [list every file/directory another agent owns]
- When in doubt: read-only. If you need something from an off-limits file,
  note it in your summary and let the lead resolve it.

---

### RESEARCH FIRST (before writing any code)

Answer these questions by reading the codebase. Do not write any
implementation until you have answered all of them.

1. [specific question about existing patterns, e.g. "How does the existing
   DO class handle state initialization? See src/do/session.rs"]
2. [specific question about the interface contract, e.g. "What types does
   src/types.rs export that you will use?"]
3. [specific question about Cloudflare/Rust constraints relevant to this agent]
4. [any question whose answer will change your implementation approach]

---

### IMPLEMENTATION TASK

[Precise description of what to build. Include:]
- Module/function names to use (follow existing naming conventions)
- Any specific Cloudflare Worker/DO patterns required
- Error handling approach (match the existing pattern in src/errors.rs)
- DO NOT add dependencies to Cargo.toml unless you own it; if you need a new
  dep, note it in your summary for the types agent / lead to add

---

### OUTPUT CONTRACT

Downstream agents depend on you producing exactly this interface:

```rust
// [paste the function signatures, trait impls, or type definitions
//  that other agents will call — be precise]
```

Do not change these signatures. If you discover the contract is wrong,
stop and report it in your summary rather than silently altering it.

---

### WHEN YOU ARE DONE

1. Run `cargo check` from your worktree root. Fix all errors.
2. Run `cargo clippy`. Fix all warnings.
3. Commit with: `git commit -m "feat([scope]): [description] (issue #[N])"`
4. Output a summary in this exact format:

```
AGENT SUMMARY: [AGENT-NAME]
Status: COMPLETE | BLOCKED | PARTIAL
Commit: [commit hash]

Files modified:
- [path]: [one-line description of change]

Output contract delivered: YES | NO | PARTIAL
[If PARTIAL or NO, explain why]

Discovered issues for lead:
- [anything the lead or another agent needs to know]
- [merge risks, missing dependencies, design questions]

Cargo check: PASS | FAIL
[If FAIL, paste the first 10 lines of error output]
```
```

---

## Notes for Skill

- Always include the research questions. Agents that skip research produce
  code that ignores existing conventions and requires more rework.
- The output contract section is critical for Phase B agents. Copy the exact
  function signatures from the decomposition table — don't paraphrase.
- The "off limits" list must be exhaustive. Name every file another agent owns.
- For Phase C (test) agents: the research questions should focus on *how*
  existing tests are structured, not on implementing features.
