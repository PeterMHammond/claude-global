---
name: swarm-deploy
description: >
  Multi-agent orchestrator for Claude Code. Accepts a GitLab issue number or a
  freeform task description, decomposes it into independent sub-tasks with
  non-overlapping file ownership, and deploys a parallel agent team using git
  worktrees so agents never step on each other's changes.

  ALWAYS use this skill when:
  - The user says "deploy agents", "spin up a team", "parallelize this", "swarm this issue"
  - An issue or feature involves 2+ distinct sub-components (e.g. Worker + DO + types + tests)
  - A task is too large for one Claude Code session to hold in context cleanly
  - The user provides a GitLab issue number and asks to start work
  - The user wants to implement multiple features in parallel
  - Any multi-part implementation task where file boundaries can be drawn

  This skill produces: a decomposition plan, file ownership map, worktree
  dispatch commands, per-agent prompt templates, and a merge checklist.
---

# Swarm Deploy — Multi-Agent Orchestrator

Decompose → Own → Isolate → Execute → Merge.

Every line of code is a liability. This skill ensures parallel agents only write
what they own, and the integration surface stays small.

---

## Phase 0: Intake

Determine input type and gather context.

### If given a GitLab issue number

```bash
# Fetch issue from GitLab (adjust remote/project as needed)
git remote get-url origin          # confirm project slug
glab issue view <ISSUE_NUMBER>     # requires `glab` CLI
# or via API:
curl "https://gitlab.com/api/v4/projects/<PROJECT_ID>/issues/<ISSUE_NUMBER>" \
     -H "PRIVATE-TOKEN: $GITLAB_TOKEN"
```

Extract from the issue:
- **Title** — the feature name
- **Description** — requirements, acceptance criteria
- **Labels** — scope hints (worker, do, auth, billing, etc.)
- **Linked issues / MRs** — upstream dependencies

If `glab` is unavailable, ask the user to paste the issue body.

### If given a freeform task

Treat the user's description as the issue body. Ask clarifying questions only
if a file ownership boundary is genuinely ambiguous. Do not ask for information
you can infer from the codebase.

### Codebase scan (always)

Before decomposing, run a targeted read of the codebase to understand the
existing module layout:

```bash
# Rust workspace layout
find . -name "Cargo.toml" | head -20
find src -name "mod.rs" -o -name "lib.rs" | sort

# Identify DO types
grep -r "DurableObject" src --include="*.rs" -l

# Identify Worker entry points
grep -r "#\[event(fetch)\]" src --include="*.rs" -l

# Current branch state
git status
git log --oneline -10
```

Read only what you need. Do not load every file — just enough to draw the
ownership map.

---

## Phase 1: Decompose

Break the issue into **independent work units**. A unit is independent if:
- It can be fully implemented without knowing the internal implementation of
  another unit (only the *interface* matters)
- It has a non-overlapping set of files it writes to
- It can be tested/compiled in isolation

### Decomposition rules

1. **One agent per domain.** Examples for a Cloudflare Workers/Rust project:
   - `worker-handler` — request routing, middleware, entry point
   - `durable-object` — DO class, state machine, SQLite operations
   - `types-contracts` — shared types, traits, error enums (`src/types.rs`, `src/errors.rs`)
   - `tests` — integration tests, mock workers
   - `config` — wrangler.toml, environment bindings

2. **Types/contracts first.** If agents share data structures, the types agent
   runs **first** (sequential Phase A) and commits before other agents start
   (parallel Phase B). This prevents type-mismatch conflicts.

3. **No agent touches `Cargo.toml` unless it is the designated dependency agent.**
   Dependency changes cause the worst merge conflicts. Assign one agent
   (usually the types agent) to own dependency additions.

4. **Maximum 5 parallel agents.** Beyond 5, coordination overhead and token
   cost outweigh the parallelism benefit. Group related micro-tasks.

### Output: Decomposition table

Produce this table before proceeding:

| Agent Name | Phase | Files Owned (write) | Files Read-Only | Blocked By | Output Contract |
|---|---|---|---|---|---|
| `types` | A | `src/types.rs`, `src/errors.rs`, `Cargo.toml` | — | — | Public types + traits |
| `worker-handler` | B | `src/lib.rs`, `src/routes/*.rs` | `src/types.rs` | `types` | Handler compiles |
| `durable-object` | B | `src/do/*.rs` | `src/types.rs` | `types` | DO state machine compiles |
| `tests` | C | `tests/*.rs` | all `src/` | `worker-handler`, `durable-object` | `cargo test` passes |

Get explicit confirmation from the user before proceeding to Phase 2.
**Do not dispatch agents until the user approves the decomposition table.**

---

## Phase 2: Verify Worktree Readiness

```bash
# Confirm Claude Code version supports --worktree flag (requires v2.1.49+)
claude --version

# Confirm clean working tree on main/trunk before branching
git status
git stash list   # should be empty ideally

# Add worktree directory to .gitignore if not already there
grep -q ".claude/worktrees" .gitignore || echo ".claude/worktrees/" >> .gitignore
```

If the working tree is dirty, ask the user whether to stash or commit before
continuing. Never dispatch agents from a dirty tree.

---

## Phase 3: Build Agent Prompts

For each agent in the decomposition table, produce a complete prompt using the
template in `references/agent-prompt-template.md`.

Key rules for every agent prompt:
- **Explicit file ownership list** — every file the agent MAY write, nothing else
- **Explicit off-limits list** — files it may read but must never modify
- **Interface contract** — what downstream agents depend on from this agent's output
- **Research directive** — specific questions to answer before writing code
  (codebase patterns, existing conventions, DO/Worker constraints)
- **Commit instruction** — conventional commit message format, what branch to commit to
- **"Phone home" instruction** — when done, output a structured summary for the
  lead to consume (see `references/agent-summary-format.md`)

Read `references/agent-prompt-template.md` now and use it to generate all agent
prompts before dispatching anything.

---

## Phase 4: Dispatch

### Phase A agents (sequential — types/contracts)

```bash
# Phase A runs first, in a single worktree, completes before B starts
claude --worktree feat/types-contracts
# Paste the types agent prompt
# Wait for completion and commit confirmation before proceeding
```

After Phase A commits, verify the interface compiles:

```bash
cd .claude/worktrees/feat/types-contracts
cargo check 2>&1 | tail -20
```

Only proceed to Phase B if `cargo check` passes.

### Phase B agents (parallel — independent features)

Each agent gets its own worktree. Dispatch all Phase B agents in a single
Claude Code message to trigger parallel execution:

```bash
# Dispatch simultaneously — Claude will parallelize these
claude --worktree feat/worker-handler
claude --worktree feat/durable-object
# (open each in a separate terminal tab or tmux pane)
```

Or if using Agent Teams (requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`):

```
Create an agent team named "issue-<NUMBER>".
Spawn teammate "worker-handler" with the following prompt: [...]
Spawn teammate "durable-object" with the following prompt: [...]
Both run in background. Use worktree isolation for each.
```

### Monitoring during parallel execution

Check in on each worktree periodically — do not leave agents fully unattended
for more than ~20 minutes on complex tasks:

```bash
# Quick status check across all active worktrees
git worktree list
# Check each branch for commits
for wt in $(git worktree list --porcelain | grep "worktree" | awk '{print $2}'); do
  echo "=== $wt ===" && git -C "$wt" log --oneline -3
done
```

Redirect any agent that has drifted into off-limits files immediately.

### Phase C agents (sequential — integration/tests)

Wait for all Phase B worktrees to commit before dispatching Phase C.

```bash
claude --worktree feat/tests
# Paste tests agent prompt, referencing all Phase B branches as read context
```

---

## Phase 5: Merge Protocol

Merge in dependency order: A → B (each) → C.

```bash
# Ensure main is up to date
git checkout main && git pull

# Merge Phase A first
git merge feat/types-contracts --no-ff -m "feat: shared types and contracts for issue #<N>"
cargo check   # must pass before proceeding

# Merge Phase B agents one at a time
git merge feat/worker-handler --no-ff -m "feat: worker handler for issue #<N>"
cargo check

git merge feat/durable-object --no-ff -m "feat: durable object for issue #<N>"
cargo check

# Merge Phase C
git merge feat/tests --no-ff -m "test: integration tests for issue #<N>"
cargo test

# Full build verification
cargo build --release 2>&1 | tail -30
```

### Conflict resolution guidance

- **`Cargo.toml` conflicts**: Merge dependency sections manually; keep both
  dependency additions; resolve version conflicts by picking the higher semver.
- **`src/lib.rs` / `mod.rs` conflicts**: These are usually just `mod` and `use`
  declarations — add both, then check for duplicates.
- **Logical conflicts** (two agents implemented the same function differently):
  Read both versions, pick the correct one, or synthesize. This requires human
  judgment — do not auto-resolve.

### Cleanup

```bash
# Remove worktrees after successful merge
git worktree remove .claude/worktrees/feat/types-contracts
git worktree remove .claude/worktrees/feat/worker-handler
git worktree remove .claude/worktrees/feat/durable-object
git worktree remove .claude/worktrees/feat/tests
git worktree prune
git branch -d feat/types-contracts feat/worker-handler feat/durable-object feat/tests
```

---

## Phase 6: Verification Checklist

Before closing the issue or opening a MR:

```bash
cargo check          # no errors
cargo clippy         # no warnings (treat as errors per project convention)
cargo test           # all tests pass
cargo build --release  # production build succeeds
wrangler deploy --dry-run  # wrangler config valid (if applicable)
```

Then open the MR:

```bash
glab mr create \
  --title "feat: <issue title>" \
  --description "Closes #<ISSUE_NUMBER>" \
  --target-branch main \
  --source-branch <current-branch>
```

---

## Quick Reference: Dispatch Command

For a fast "just do it" invocation, use this pattern in Claude Code:

```
Swarm issue #<N> (or: <task description>).

Phase A (sequential, blocking):
  - types agent: owns src/types.rs, src/errors.rs, Cargo.toml

Phase B (parallel):
  - worker-handler agent: owns src/lib.rs, src/routes/
  - do-agent: owns src/do/

Phase C (sequential, after B):
  - test agent: owns tests/

Use worktrees for all agents. Each agent must commit before the next phase
begins. Agents must not modify files outside their ownership list.
Do not start until I confirm the decomposition plan.
```

---

## Reference Files

Read these when generating agent prompts:
- `references/agent-prompt-template.md` — full per-agent prompt structure
- `references/agent-summary-format.md` — the structured output agents produce
- `references/conflict-patterns.md` — common merge conflict patterns and resolutions
