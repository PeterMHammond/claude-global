---
name: fix-issue
description: Pick the most-active unassigned GitLab issue, search for dupes/related work, research production code, plan, implement, curl-matrix + Chrome smoke test, deploy, verify in prod, commit, push, close with metrics. Same surgical-precision discipline as /triage-prod, applied to issue-tracker work instead of tail-discovered bugs. Supports [N] batch count and --auto for unattended loops.
---

## Arguments

- `/fix-issue`               → most-active unassigned issue: fix → deploy → verify → commit → push → close
- `/fix-issue <id>`          → specific issue by ID
- `/fix-issue 5`             → loop: pick most-active, fix, then next, ... up to 5; pause between
- `/fix-issue 5 --auto`      → fully unattended loop: smoke → deploy → commit → push → close → next
- `/fix-issue --status`      → print state file (issues done, last commit/version) and exit
- `/fix-issue --reset`       → wipe `.claude/fix_issue_loop_state.json`
- `/fix-issue --dry-run <id>` → research + plan only, no implementation

Defaults: single issue, carried through commit, push, and close once verified. `--auto` only removes the pause between loop iterations.

## State

Per-project file at `<project-root>/.claude/fix_issue_loop_state.json`:

```json
{
  "target_issues": 5,
  "completed_issues": 2,
  "started_at": "2026-05-09",
  "history": [
    { "issue": 58, "title": "...", "commit": "abc1234", "version_id": "uuid",
      "before_metric": "...", "after_metric": "...", "summary": "..." }
  ]
}
```

Update **after** each successful close, **before** picking the next. State persists across sessions so an interrupted loop can be resumed.

## Workflow

### Step 0 — Situational awareness

Always run first. Don't pick an issue blindly.

```bash
git log --oneline -15
git branch -a --sort=-committerdate | head -10
glab issue list --assignee=@me --per-page 5     # what am I already on?
glab issue list --label status::in-progress      # what other sessions are doing
```

If another session is mid-issue, do not duplicate effort. Note recent
commits — your fix should build on the latest state.

### Step 1 — Pick the most-active unassigned issue

**Activity-first ordering, NOT strict priority.** A high-priority issue
with no recent activity has gone stale; an active P2 with comments today
has live context.

```bash
glab issue list --order updated_at --sort desc --per-page 30
```

From that list, pick the **first issue** that satisfies:
- ✅ Unassigned (`Assignees:` empty in `glab issue view`)
- ✅ Not labeled `status::in-progress`
- ✅ Not labeled `blocked` or `needs-info`
- ✅ Acceptance criteria are clear (if not, post a clarification comment, skip, continue)

If a higher-priority issue is in the top 10 by activity, prefer it over
a lower-priority one — but never reach past activity for a stale P0
that's been quiet for weeks (it's likely waiting on something).

Override: `/fix-issue <id>` uses the explicit ID and skips this step.

### Step 2 — Search for dupes and related issues (NEW — critical)

**Before claiming, check whether this work overlaps another issue.**

```bash
# Pull keywords from the title (3-5 most distinctive words)
glab issue list --search "<keyword1> <keyword2>" --state all --per-page 20

# Same labels, recent activity
glab issue list --label "<primary-label>" --order updated_at --sort desc

# Search for the file/component the issue mentions
glab issue list --search "<filename or component>" --state all
```

For each match decide:

- **Exact duplicate** → comment on the older issue with `Duplicate of #<newer>` (or vice versa), close the dup with `glab issue close --comment "Duplicate of #N — see <link>"`. Return to Step 1.
- **Related, same root cause** → bundle into one fix. Note both IDs in the commit footer (`Closes #A, #B`).
- **Related, different root cause** → proceed independently, but link in the commit body so reviewers see the relationship.
- **Same surface, different request** → proceed independently.

Skipping this step is the most common cause of duplicate work and
churn. Don't.

### Step 3 — Claim the issue

```bash
glab issue view <id>          # confirm you read it
glab issue update <id> --assignee @me --label status::in-progress
```

The label prevents other sessions from picking it up.

### Step 4 — Research production code (pattern extraction is the goal)

The output of this step is a **named sibling pattern** for every new
piece of logic you're about to add. Not a vague sense of the codebase —
specific files, specific line numbers, specific function shapes you
will mirror.

Use the `researcher` subagent. Multiple researcher calls in parallel
when the issue spans repos.

Tell each researcher *which project*, *what to look for*, and **what
sibling pattern to return**:

| Issue domain | Project to research | What to look for | Pattern expected back |
|---|---|---|---|
| Routing, KV keys, request pipeline | carm/ | Layer ordering, route registrations | "Mirror `<fn>` at `src/lib.rs:N`" |
| Submission, OAuth, publish pipeline | carm-editor/ | Publish flow, OAuth handshake | "Mirror handler at `<file:N>`" |
| Durable Objects, hibernation | craft/ | DO lifecycle, flush_buffer pattern | "Use `flush_buffer` from `craft/<file:N>`" |
| Frontmatter, wallet metadata | broker/ | Article schema, x402 fields | "Field shape from `broker/<file:N>`" |
| Utility functions | cf-tools/ | **Don't reinvent — search first** | "Use `cf-tools::<fn>` (already exists)" |
| State machines | statetree/ | Transition patterns | "Mirror state machine at `statetree/<file:N>`" |

**The pattern-extraction rule from CLAUDE.md is mandatory, not advisory.**
Training-data conventions are overwhelmingly demo/tutorial code that
diverges from production patterns. Find the sibling FIRST, use it as
the template, then write.

If the researcher reports back "no existing pattern" — **don't accept
that at face value**. Push back: "Search for X, Y, Z shapes. Check
craft/, broker/, cf-tools/. What's the closest analog?" Real
greenfield is rare; the closest analog is usually still a better
template than tutorial code.

### Step 5 — Plan

Synthesize research into a fix plan. The plan must:

- Cite specific files and line numbers from production code for every
  pattern reused
- If introducing a new pattern, justify why nothing existing works
- Identify which files will change (drives the agent-team decision)
- Identify what the **smoke test** will be (Step 8) — what specific
  behavior in the live app will prove this fix works?
- Identify what the **acceptance criteria** are from the issue body —
  smoke test must cover them

Decide: single session vs agent team:
- **Single session**: fix is in one file or sequential steps
- **Agent team** (3-4 teammates, delegate mode): fix spans multiple
  layers that can be built in parallel, each teammate owns DIFFERENT
  files. Use `/swarm-deploy` skill if available.

In `--dry-run` mode: print the plan and stop.

### Step 6 — Implement

**6-zero. Dispatch the review team — the default, not an option.**

You coordinate; teammates do the work: implementer → reviewer (applying the
`/rust-review` checklist) → fixer → re-reviewer, looping until Approved. Nobody
reviews their own work. Step 4's research report is the brief. Full role prompts
and rules: **The review team** section below.

Hand-code it yourself only for a typo, a version bump, or a one-line copy change
— and say which. Steps 6a/6b below are the brief you hand the implementer, not
instructions you execute.

**6a. Pattern-extraction gate (do this BEFORE writing any code):**

Step 4 surfaced sibling patterns. This step uses them. For every
function, helper, or block you're about to add, name the sibling out
loud:

> "Adding `<new_fn>` mirroring `<sibling_fn>` at `<file:line>`. Same
> shape, different trigger / different layer / different field set."

If you can't name a sibling: STOP and re-research. Don't fall back on
training-data conventions — they look right but diverge from
production patterns. The cycle 5 lesson on CARM was exactly this —
`needs_article_redirect()` only worked because it explicitly mirrored
`routes/article.rs:17-32`, including the WordPress-pagination strip.
Inventing it from scratch would have missed edges.

Quick searches when in doubt:

```bash
grep -rn '<keyword>' src/                     # this project
grep -rn '<keyword>' ../cf-tools/src/         # shared utility?
grep -rn 'fn <similar_name>' ../carm-editor/  # cross-project pattern
```

**6b. Implementation rules:**

- Trunk-based: work directly on `main`, no branches
- Match existing patterns. The sibling you named in 6a is your template.
- One file when possible. Smallest diff that fixes the root cause.
- **Never recreate Worker requests.** Use `Request::clone_mut()` to
  unlock immutable headers if needed.
- Before writing any utility function: check `cf-tools` first.
- For Cloudflare patterns (KV / DO / R2 / queues / AE / Vectorize):
  search across CARM, carm-editor, craft, broker — the production
  shape almost always exists somewhere.

### Step 7 — Build / type-check / clippy

**This is the ONLY test run.** Not one per agent, not one per issue in a batch —
one, here, on the main tree, after every agent has finished editing. Subagents
edit and stop; see "Sizing the team" for why.

```bash
cargo build           # must compile clean
cargo test            # all tests pass
cargo clippy          # no warnings
```

For frontend: `bun run check` or equivalent. **Type-checking and tests
verify code correctness, not feature correctness** — Step 8 verifies
features.

### Step 8 — Local verification (curl matrix + Chrome smoke)

This is where most cycles silently fail. Two phases.

**8a. Start dev server:**
```bash
./node_modules/.bin/wrangler dev --port 8787 --env development
```
`--env development` is the only working combo (plain `--local` 302s
on remote KV; `--remote` fails on bindings). Wait for "Ready on..."
before testing.

**8b. Curl matrix — mandatory for ANY routing / handler / redirect /
short-circuit / path-filter change.**

Build the matrix from the actual route registrations:
```bash
grep -nE '\.(get_async|post_async|put_async|delete_async)' src/lib.rs
```
Hit *every* registered route at least once with curl, capturing status
+ Location header. Categories:

- "Should fire" — paths your fix is supposed to affect
- "Must NOT fire" — adjacent paths, sibling routes, paths your fix is
  supposed to leave alone
- Edge cases — empty paths, path-traversal attempts, paths with dots,
  asset extensions

If any "must NOT fire" line breaks: STOP, fix, re-run the matrix.
This catches regressions Chrome smoke can miss (especially POST
endpoints).

**8c. Chrome DevTools MCP smoke suite — four steps minimum,
acceptance-criteria coverage required:**

| Step | Path | Verify |
|------|------|--------|
| Homepage | `/` | popular articles render, search box focused |
| Article preview | `/<known-slug>` | title, author, intro, Turnstile iframe |
| Reading progress | `POST /<slug>/reading` | 200 "Progress tracked" |
| Search | submit query from `/` | results render, count > 0 |

Plus: a step (or steps) covering each acceptance criterion in the
issue body. If the issue says "homepage search box is no longer covered
at iPad width," add a step that resizes to iPad width and confirms the
search box is uncovered.

For non-Worker issues (carm-editor publish flow, broker frontmatter
parser, etc.): adapt — same discipline, different surface.

### Step 9 — Cost review (NEVER skip)

```
Spawn cost-reviewer subagent on staged changes.
```

Per project CLAUDE.md, this is a hard rule. `--auto` mode does NOT
skip this. If cost-reviewer flags anything → fix and re-run before
proceeding.

### Step 10 — If shipping code: bump version + deploy

Skip this for issues that are pure docs / configuration / test-only.

For Worker issues:
```bash
# Edit Cargo.toml: x.y.Z → x.y.Z+1
./node_modules/.bin/wrangler deploy
# Capture: Current Version ID: <uuid>
```

Weigh the blast radius first. Dev, staging, preview, or internal tooling: deploy. If it changes live production behavior, data, or real users, use `AskUserQuestion` to say what it affects before you deploy.

### Step 11 — Production verification

**Dispatch the prod verifier (role 7) when correctness cannot be seen in the
diff** — wire formats, auth flows, prod-only state, TTL/cache behavior. Fresh
context, read-only, `wrangler tail` as a second channel, and the prohibition
clause: name the constructs it may write, forbid all other prod writes, require
report-and-stop. Give it the falsifiable assertion, never the expected answer.

Verify inline yourself only when the acceptance criteria are plain HTTP responses
the curl matrix already covers.

```bash
./node_modules/.bin/wrangler tail --format pretty   # background, ~30-60s
```

While the tail runs:
- Re-run the curl matrix from Step 8b against `https://<prod-host>`
  (trimmed to the paths your fix targets)
- Re-run the Chrome MCP smoke suite against the production URL
- Verify each acceptance criterion against production
- Count tail events matching the original symptom: should be zero

If the symptom is still firing on prod after deploy: **DO NOT COMMIT**.
The deploy didn't take, or the fix doesn't address the root cause.
Roll forward (find what's missing) or revert.

### Step 12 — Summary, then commit

Print this summary and go straight on to Step 13. Don't wait for the user.

```
Implementation verified — committing.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Issue: #<id> — <title>
Files changed: <list>
Build: ✅ clean
Tests: ✅ passing
Local smoke: ✅ <N> steps passed
Cost review: ✅ pass
Deploy: ✅ v<new> as <version-id>
Prod smoke: ✅ <N> steps passed
Original-symptom event count (post-deploy): 0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Step 13 — Commit with `Closes #N`

Use the `/commit` skill. Footer must include `Closes #<id>` so the push
auto-closes the issue. If multiple issues bundled in this fix:
`Closes #A, #B, #C`.

### Step 14 — Push to main

`git push origin main`. The `Closes` trailer auto-closes the linked
issues.

### Step 15 — Add issue close note: the WHY

The commit carries the WHAT; don't restate the diff. Record the reasoning a future reader can't get from the code.

```bash
glab issue note <id> --message "## Resolution

**Root cause:** <why it broke / why it was needed>
**Decision:** <approach taken and why; alternatives rejected and why>
**Pattern source:** <production project / file:line>
**Verified:** <tests + smoke steps + prod evidence>
**Commit:** <sha> · **Deploy:** <version uuid>
**Follow-ups:** <anything deferred, or none>

## Before / after metrics
- <metric name>: <before> → <after> (extrapolated to <per-day> / <per-month>)

## Value gained
- <signal restored / cost reduced / UX / correctness / security>"
```

### Step 16 — Update state, loop or stop

- Append to `history`, increment `completed_issues`
- If `completed_issues == target_issues` → say `"done"` and stop
- If more issues remain:
  - **`--auto`**: immediately go to Step 1 for the next issue
  - **attended**: print summary and wait for `next` from the user

## The review team (Step 6 + Step 11 deep dive)

Seven roles, each a fresh subagent with one job and no inherited context.
**Nobody reviews their own work.** You coordinate — you do not hand-code the fix.

Distilled from two proven runs: craft `e553d797` (2026-07-22, `craft-ready` head
field — research → implement → cost → prod-verify) and craft `450a6778`
(2026-07-17, facet KV Task 2 — implement → review → fix → re-review).

Not the same thing as **Agent Teams** (delegate mode, 3-4 teammates, parallel
work across layers with different file ownership — see `EveryGoodWork/CLAUDE.md`).
This is sequential dispatch: one role at a time, each handing off to the next.

| # | Role | Agent | Model | Job |
|---|------|-------|-------|-----|
| 1 | Researcher | `researcher` | sonnet | Map the seam and **every** consumer. Read-only. |
| 2 | Implementer | `general-purpose` | sonnet | Make the change. Exact scope, hard do-nots. |
| 3 | Reviewer | `general-purpose` | opus | Spec + quality via `/rust-review`. Reports, never fixes. |
| 4 | Fixer | `general-purpose` | sonnet | Apply findings. Numbered, prescribed. |
| 5 | Re-reviewer | `general-purpose` | opus | Confirm each finding by number. Catch regressions. |
| 6 | Cost reviewer | `cost-reviewer` | sonnet | Cloudflare cost of the staged diff. Never skip. |
| 7 | Prod verifier | `general-purpose` | sonnet | Drive the **live system** after deploy. Read-only, fenced. |

Roles 3–5 loop until the reviewer returns **Approved**. Two failed fix passes on
the same finding means the finding is wrong or the design is — stop and bring it
to Peter rather than dispatch a third fixer.

**The roles are a checklist of jobs, not a per-issue pipeline.** Run them ONCE
over a converged changeset — see "The coordination model" below. Roles 1–2 fan out
across issues; roles 3–6 run once, after the merge, on the whole diff.

Skip the team for a typo, a version bump, or a one-line copy change — and say so.

### The coordination model — parallel edits, ONE convergence

Default shape for any batch of work, whether it is one issue or five:

```
N implementers in parallel   — disjoint files, edit only, NO builds, NO tests
        ↓  (converge)
one build                    — main tree, main thread
one test run                 — Step 7, the only one
one assessment               — whole merged diff: review + cost, in parallel
        ↓
one fixer  →  re-verify  →  commit
```

**Why this beats per-issue loops.** Each issue running its own
implement → review → fix → re-review chain multiplies agents by issue count and
verifies the same tree N times. Converging first means the reviewer reads the
*whole* changeset — which is the only way to catch interactions between two
issues' edits. Three per-issue reviewers structurally cannot see them.

**Isolation: only when you actually need it.** Disjoint file ownership already
keeps parallel agents apart, and then "merge" is a no-op — they are editing one
tree in different places. Use a worktree only when two agents must touch the SAME
file, or when one must build deliberately broken code. Otherwise you pay a merge
step and a cold `target/` for nothing.

**Errors surface late and in a pile — that is the accepted trade.** The single
build may report three agents' compile errors at once. Attribute by file (you
assigned ownership, so you know whose is whose) and fix in one pass. That is
cheaper than N agents each proving their own edit compiles.

**What survives the collapse: independence.** The assessment reviewer still
re-derives from scratch rather than trusting the implementers — see "What NOT to
cut" below. It was independence that found the bugs, not head-count.

### Sizing the team — agent count IS the cost

**The clock is model round-trips, not compute.** Measured on craft-core, warm:
`cargo test --features full` 3s · `clippy --all-targets --features full` 8s ·
the whole pre-commit gate incl. the 11-tier lattice 10s · alternating clippy
feature profiles ~1s (cargo fingerprints them separately — there is no rebuild
thrash to design around). A 40-tool-call agent costs ~5 minutes no matter how
fast the tests are. On 2026-08-07 the #345/#346/#349 arc spent ~45 minutes across
**11 agents and ~250 tool calls**, against ~5 minutes of actual build and test.

So the lever is how many agents you dispatch, and it is the one thing you control.

**Batch by repo and class, not by issue number.** Three issues that are all
dead-code deletion in one crate are ONE implementer and ONE reviewer, not three of
each. Split only when the files differ *and* the failure modes differ. In that arc
#346 and #349 were both pure deletion in craft-core — merging them would have
saved four agents.

**Earn the full seven roles.** Run them when the diff touches money, ACL/RBAC,
wire format, auth, or prod-only state. Everything else gets implement → one review
→ commit. A dead-function deletion or a field rename does not need a fixer and a
re-reviewer standing by.

**One test run per issue — Step 7, and nowhere else.** In that arc ten agents each
ran the suite plus both clippy profiles: thirty redundant passes that also collided
on cargo's build lock (`Blocking waiting for file lock on build directory`). Every
agent prompt says *make your edit and stop*; the main thread verifies once, at the
end, on the main tree.

**What NOT to cut.** Independent re-derivation is the expensive part and it is the
part that pays. In that same arc the reviewers — re-deriving instead of trusting
the implementer — found a `saturating_add` whose mutation returns a **$0 price
floor**, and a `capabilities()` line whose deletion left all 622 tests green.
Neither was in any issue. Cut agent *count*; never cut a reviewer's mandate to
verify from scratch rather than accept a teammate's finding.

### Token discipline — paste into every role prompt

> **Output contract.** Report only what bears on the task. No preamble, no
> restating the assignment, no list of files you read, no narration of your
> process, no "what went well". Findings and facts only, each one line, with
> `file:line`. Quote code only where exact text is required — never to
> illustrate. Hard cap: 400 words. If you finish early, stop; padding is a defect.

Enforce it on yourself too. Between dispatches, one line — tool results carry the
record. Never relay a teammate's report in full; give the verdict and the findings
that change what happens next.

### Artifacts

Write to `<repo>/.team/<issue>/` so each role reads files rather than inheriting a
conversation:

- `brief.md` — Step 4 research + the requirements
- `diff.txt` — `git diff` captured before each review
- `report.md` — implementer's report, appended by each later role

The implementer's report must state **what they were unsure about and how they
tested**. The reviewer reads that first — a self-declared doubt is the highest
yield lead on the page.

### Hard rules — every prompt

- **Never commit.** No `git add`, no `git commit`, no `--no-verify`. Peter ships.
- **Name the files the teammate may touch.** Everything else is out of bounds,
  especially files another session holds dirty.
- **No version bumps** by subagents. The main thread owns `Cargo.toml`.
- **Always specify the model** — omitting it inherits the session model.
- **Give the falsifiable assertion, not the expected answer.** "Report whether
  `cursor == head`" — never "confirm that `cursor == head`."
- **Agents edit. Agents do not run tests.** Put it in every prompt: *"Make your
  edit and stop. Do not run cargo test, cargo clippy, or cargo build."* There is
  ONE test run per issue — Step 7, on the main tree, after every agent has
  finished. Ten agents each verifying is ten redundant passes that also collide on
  cargo's build lock, and it buys nothing the single run does not.
- **Worktrees are for isolation, never for building.** File-path ownership already
  keeps parallel edits apart, so a worktree is rarely needed at all — and building
  in one is the expensive mistake: a fresh worktree has no `target/`, so
  `cargo test --features full` costs **62s and 3.2G** cold against **3s** warm in
  the shared tree. If an agent works in a worktree, its changes come back to the
  main tree and get built there.
- **Sabotage-verification is part of Step 7, not a reviewer's private run.**
  Proving a test bites means breaking its subject and building the broken code —
  the one check that cannot be folded into a clean final build. So it happens at
  the end, alone, with no other agent running. Never mid-review: on 2026-08-07 a
  reviewer sabotaged the shared tree while two fixers were building in it, and
  both reported a phantom "order-dependent" failure while the diagnostics read as
  a gutted ACL.
- **Forbid `git checkout` / `restore` / `stash` / `reset` outright** in every
  prompt on a shared checkout — "if you think you need one, stop and report."
  That same reviewer finished by running `git checkout --` over three agents'
  uncommitted work; it recovered on luck. Verify each teammate's artifacts are
  still present yourself; never accept a self-reported checksum as proof.

### 1 — Researcher

Read-only, cites `file:line`, enumerates **consumers** not just the emit site —
this is what stops a wire-format change from silently breaking a facet. Ask for:
definition sites with exact code shape; every consumer across `src/`, `entry.js`,
`assets/`, facet JS, docs, sibling repos; whether each tolerates an added field
(`serde(default)` / duck-typed JS); local naming vocabulary; sibling patterns.

End with *"Do NOT edit anything. Return the report as your final message."*

### 2 — Implementer

Give it the **current code beside the target code**, not a description. The
July 22 prompt showed the existing `let resume = delivered.or_else(...)` block
verbatim next to what it should become — that precision is why it landed in four
minutes.

State the reason behind each constraint: *"keep the head read where no `.await`
sits between replay and emit, so the read stays race-free"* beats *"don't add an
await."* A teammate who knows why will preserve the property when the code fights
back.

If no host test harness exists for the touched code, say so and say what to do
instead — extract the pure logic into a crate that host-compiles and test *that*.
Never let it invent a test it cannot run.

### 3 — Reviewer — `/rust-review` goes here

> Read `~/.claude/skills/rust-review/SKILL.md` and apply its Analysis Checklist to
> this diff. Sections 1 (clones), 4 (simplification), 13 (guard elimination), 14
> (signature contracts), 15 (hot path) are mandatory; apply the rest where the
> diff touches them. Follow its philosophy — **foundation over fixes**: a boolean
> return often signals a missing enum, a validated `&str` a missing newtype.
> Report the redesign, not the patch.

Also hand it: the brief, the implementer's report, `diff.txt`; *"read surrounding
context in the file, do not rely on the diff alone"* (a diff cannot show that a
new helper duplicates one forty lines up); the global constraints as an explicit
attention lens; severity grades **Critical / Important / Minor** with `file:line`;
and *"do not implement fixes — report findings."*

Once the loop closes, run `/rust-review` yourself over the whole changeset. The
per-task reviewer sees one diff; `/rust-review` follows findings across file
boundaries and is the only pass that catches a consolidation spanning two tasks.

### 4 — Fixer

Findings **numbered**, each with severity and the prescribed fix. Where the
reviewer proposed code, include it. Where the fix is a judgment call, say so and
let the fixer decide — flagged in its report. Fix Critical and Important; Minor is
Peter's call unless trivially cheap.

### 5 — Re-reviewer

> Confirm each finding (1..N) is genuinely resolved: ✅/❌ per number. Then check
> the fixes introduced nothing new — no stray `.unwrap()`/`.clone()`/`panic!` in
> non-test code, and the invariants named in the brief still hold. Overall:
> **Approved** / **Changes needed**. Keep it tight.

Re-naming the invariants matters. The July 17 re-reviewer was told to re-check
that no `.await` had crept between `append_event` and `store.put` — a property the
fix pass could plausibly have broken while relocating code.

### 6 — Cost reviewer

Never hand it a bare diff. Hand it the **hypothesis**: which operation got more
expensive, how often it runs, against what multiplier. *"One extra `SELECT id
ORDER BY id DESC LIMIT 1` per accept, on every agent connect and every ~55s
cycle-roll reconnect, up to 8 muxed sockets per MCP session."* Given the
multiplier it returns a number; given a diff it returns an opinion.

### 7 — Prod verifier

After deploy — the role that catches what no amount of diff-reading can.

- **Fence it. This clause is not optional:**
  > Read-only against the repo: do NOT edit files, do NOT deploy. You may write to
  > these constructs only: `<names>`. **All other writes to production are
  > forbidden** — including `__drain`, `__describe`, `__upgrade` and any sibling
  > unauthenticated route you discover. If verification appears to require a write
  > outside that list, **report and stop**.
- Point it at the auth path rather than handing it a token — the scripts, the DPoP
  helper, the login flow. It will find and refresh its own credentials.
- Demand a **second channel**: `wrangler tail` running during the test, so a silent
  500 cannot hide behind a plausible-looking response.
- Give the reasoning for **both** outcomes, so agreement is not the cheapest path.
- Time-box with an escape hatch: *"Do not burn more than ~10 minutes on auth
  gymnastics. If blocked, report exactly what blocked you and what you verified
  instead."*

Read its side observations. The July 22 verifier volunteered, unasked, that
keyproof's agent-visible log was empty — which became a real finding about
`AgentEvent::project`.

## Cost-conscious subagent dispatch

Three roles run during a cycle — assign each to the cheapest model that
preserves output quality.

| Role | Examples | Model | How to invoke |
|---|---|---|---|
| **Orchestrator** | This loop, plan decisions, judging acceptance criteria, dup/related-search synthesis | Opus 4.7 (parent) | Default — runs as me |
| **Specialist** | `researcher` (Step 4), `cost-reviewer` (Step 9), `Plan` agent for complex fix-plans, swarm-deploy team leads | Sonnet 4.6 | Pre-configured via `~/.claude/agents/*.md` frontmatter — `Agent` picks up automatically |
| **Pattern-matcher** | Curl-matrix runner, tail-log scanner, smoke-suite assertion checker, AC-bullet → smoke-step expander | Haiku 4.5 | **Pass `model: "haiku"`** explicitly when spawning |

**When to override with explicit `model` in the Agent call:**

- **Downgrade to `model: "haiku"`**: structured grunt work — running a
  curl matrix and tabulating codes, scanning a tail buffer for a known
  set of error shapes, expanding an issue's AC list into a smoke
  checklist. Example:

  ```
  Agent({
    description: "Curl matrix vs prod",
    subagent_type: "general-purpose",
    model: "haiku",
    prompt: "Run these 8 curls against https://carm.org, return {path, status, location}. Flag any deviation from the expected status table."
  })
  ```

- **Upgrade to `model: "opus"`**: when a Sonnet specialist hits real
  ambiguity. researcher returns "no sibling pattern" → re-spawn with
  Opus to push harder before accepting that conclusion. cost-reviewer
  flags something with multi-interpretation cost models → upgrade.

- **Default (no override)**: agent frontmatter wins. `cost-reviewer` and
  `researcher` are both Sonnet already.

**`--auto` mode rule**: Auto mode never silently upgrades a downgraded
model. A Haiku subagent reporting unclear results halts the loop —
don't paper over with an Opus retry, that defeats the cost discipline.
Surface it.

**Why this matters for the loop**: across 5 issues × multiple subagents
each, model choice is the difference between $0.50 and $5.00 per cycle.
Same output, different bill. Pattern-matchers don't need Opus's reasoning
budget for a `curl | grep` task.

## Search-for-related discipline (Step 2 deep dive)

The single highest-leverage habit. Three minutes of `glab issue list
--search` saves hours of duplicate work.

Common patterns:
- **Exact duplicate** — same title, same symptom, same component.
  Close the older one as a dup, work the newer one (it has fresher
  context).
- **Same surface area, different angle** — e.g. one issue says "search
  box covered at iPad width" and another says "search button hard to
  reach on tablet." Likely one fix; bundle.
- **Symptom + cause split across two issues** — e.g. "duplicate
  /user/data fires" and "404 page makes extra requests." Cycle 3 of
  the triage loop showed these were the SAME bug. Close one as
  duplicate.
- **Related but distinct** — e.g. one issue is a perf gate, another is
  a security concern in the same handler. Don't bundle; do them in
  the right order (security first), and link in commit bodies.

Don't be lazy here. Issue #66 in CARM started life as a duplicate of
#65 — catching that early saved a wasted cycle.

## Smoke-test discipline (Step 8 deep dive)

The big lesson from the production triage loop's cycle 5: **the curl
matrix is non-negotiable for routing changes, and it must be built
from the actual route table, not from comments or memory.**

When mirroring or modifying a handler's logic at a different pipeline
layer, your exclusion list must be keyed off `grep -nE
'\.(get_async|post_async)' src/lib.rs`. Comments rot; route
registrations don't.

The smoke suite's job is **not** to validate the happy path (cargo
test does that). Its job is to **catch the adjacent regression** —
the route you forgot, the segment count you miscounted, the POST
handler your GET-only test missed. Treat every smoke run as a hunt
for what your code broke that you didn't intend to touch.

## --auto mode rules

- Skips: deploy confirmation, commit confirmation, push confirmation,
  next-issue confirmation
- Never skips: cost-reviewer, build/test/clippy, curl matrix, Chrome
  smoke, production verification
- Stops on:
  - Any smoke step failure
  - Cost-reviewer flagging a regression
  - cargo build/test/clippy non-zero exit
  - Pre-commit hook failure
  - Production tail still firing the original symptom after deploy
  - Acceptance criteria unclear (post comment, skip, continue to next
    issue)
  - `target_issues` reached
- After stop: print the state file path so the loop can be resumed
  later

## Examples

### Example A — Bundling a duplicate (saves a cycle)

`/fix-issue` picks #66 ("2× /user/data fires per page"). Step 2 search:

```bash
glab issue list --search "user/data fires" --state all
glab issue list --search "duplicate SSE" --state all
```

Surfaces #65 ("404 page extra fetches"). Reading both, the same
underlying SSE-loader-on-404 bug. Close #66 as duplicate of #65,
work #65, footer commit with `Closes #65, #66`.

### Example B — Activity-first beats priority-first

Top of the activity-sorted list:
1. #58 P2 "homepage search box covered at iPad-width" (commented 2h ago)
2. #46 P3 "RSS feed at /feed" (last activity 1d)
3. #43 P1 "RPC-migrate UserV1" (last activity 5d)
4. #42 P2 "UserV1 cleanup" (last activity 5d)

Pick #58 — fresh context, recent dialogue, smaller scope. The P1
isn't dead; just not active right now. (If `--auto` and #58 has
unclear AC, comment-and-skip → #46 next.)

### Example C — Frontend layout issue, smoke-test focus

Issue #58: "Homepage search box covered by popular-articles row at
iPad width." Acceptance criteria: search box visible at 768-1024px
viewport widths.

- Step 8c: Chrome MCP `mcp__chrome-devtools__resize_page` to 768x1024,
  navigate to `/`, take_snapshot → confirm search box is in the
  visible area, not occluded by the popular-articles region. Repeat
  at 900px and 1024px.
- Step 11: same on `https://carm.org/` after deploy.

The smoke test for a layout bug is *visual*, but the discipline is
the same: every acceptance criterion gets a verification step.

## Rules

- **Pattern extraction before implementation** — every new function or
  block must name its sibling in the codebase. No sibling? Re-research.
  Don't fall back on training-data conventions; they look right but
  diverge from production patterns.
- **Activity-first ordering** beats strict priority — don't waste
  cycles on stale P0s
- **Step 2 (dup/related search) is mandatory** — don't skip it
- **Never ship a regression** — if a fix breaks anything, revert,
  re-research, re-plan
- **Never `--no-verify`, `--no-gpg-sign`, or `--force-with-lease`
  to main** without explicit user permission
- **Acceptance criteria → smoke step coverage** — every AC bullet
  needs a verification step
- **One issue per cycle** in attended mode (unless bundling dups
  per Step 2)
- **`--auto` mode never bypasses cost-reviewer or smoke tests** — only
  the confirmation prompts
- **State file is the source of truth** — always update it before
  starting the next issue
- **Verified work ships**: commit, push, and close without asking; `--auto` only skips the pause between loop iterations
- If issue is unclear: `glab issue comment <id> --body "Needs
  clarification: <question>"`, unassign, skip, continue
- If a fix needs shared utility changes (cf-tools): commit the shared
  change first, then the consuming change
- Cross-reference: use `/triage-prod` for tail-discovered bugs;
  `/fix-issue` for issue-tracker work. Both share the smoke
  discipline.
