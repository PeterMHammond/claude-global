<purpose>
Run a production triage loop on a Cloudflare Worker: tail prod, identify ONE
real bug, fix it, smoke-test it locally and remotely, deploy, and verify. Then
optionally repeat for N cycles. Surgical-precision bug fixing — never trial-
and-error. One bug per cycle.
</purpose>

<arguments>
- `/triage-prod`              → run a single cycle, pause for confirmation at each gate
- `/triage-prod 5`            → run up to 5 cycles, pause between cycles
- `/triage-prod 5 --auto`     → fully unattended: find → fix → smoke → deploy → commit → push → next, until 5 done or smoke fails
- `/triage-prod --reset`      → wipe `/tmp/$(basename "$PWD")-triage/triage_loop_state.json` before starting
- `/triage-prod --status`     → print state file (cycles done, last commit/version) and exit

Defaults: single cycle, attended mode (you confirm before deploy + commit).
</arguments>

<state>
State file: `/tmp/$(basename "$PWD")-triage/triage_loop_state.json` (per-project
— CARM and carm-editor have separate histories, keyed by repo basename. Lives
in `/tmp` so it's out-of-repo by default; `cycle_history` is lost on reboot,
which is fine — the loop is ephemeral. Create the directory on first write:
`mkdir -p /tmp/$(basename "$PWD")-triage`). Schema:

```json
{
  "target_cycles": 5,
  "completed_cycles": 4,
  "current_cycle": 5,
  "started_at": "2026-05-08",
  "cycle_history": [
    { "cycle": 1, "issue": 62, "commit": "e2ba581",
      "version_id": "e36313cd-…", "summary": "…" }
  ]
}
```

On start: load if present, else create. After each successful cycle: append to
`cycle_history`, increment `completed_cycles`. Stop when `completed_cycles ==
target_cycles`. **Always update state BEFORE moving to the next cycle** — if I
crash mid-loop, you can see exactly what shipped.
</state>

<instructions>

## The 13-step cycle

### 1. Open the site + start wrangler tail

- `mcp__chrome-devtools__navigate_page` to the production URL
- `./node_modules/.bin/wrangler tail --format pretty` in background (Bash run_in_background)
- Tail for ~30-60s. Drive the site naturally (homepage → article → search).

### 2. Identify ONE real bug

Skim the tail. Look for:

- `Exception`, `panic`, `error`, repeated 500/503
- Spike of identical paths (e.g. /apple-touch-icon-* or /tag/*)
- Duplicate fires per page load (extra SSE loaders, unnecessary POSTs)
- Slow handler durations (over a few hundred ms for content routes)
- Layered work being burned on requests that just bounce (perf bug)

**Pick the highest-impact one.** Kill the tail before fixing — don't
let live traffic distract you while the editor is open.

### 3. Create a GitLab issue

`glab issue create` with body sections:

- **Symptom** — what you see in the tail (literal log lines)
- **Root cause** — your understanding (cite file:line in the codebase)
- **Impact** — events/min × extrapolation (per day, per month)
- **Fix plan** — surgical, one-file when possible
- **Detection note** — what tail/dashboard signal will go silent
- **Value gained** — concrete benefits when resolved (signal restored,
  cost reduced, UX, correctness, security). This block also goes in the
  PR body and the closing issue note.

### 4. Fix locally — surgical precision

**4a. Pattern-extraction gate (do this BEFORE writing any code):**

For every new function, helper, or block of logic you're about to add,
find a sibling that already exists in the codebase and use it as the
template. Training-data conventions are overwhelmingly demo/tutorial
code that diverges from production patterns — don't fall back on them.

Concrete checklist:

```bash
# 1. Search the same file you're editing for related helpers
grep -nE 'fn [a-z_]+\(' src/lib.rs            # all top-level fns

# 2. Search the project for similar names / shapes
grep -rn 'is_allowed\|is_legitimate\|needs_' src/ | head

# 3. Search across production codebases for the same pattern
#    (CARM, carm-editor, craft, broker, cf-tools, lite3-rs, statetree)
grep -rn '<the-pattern-name>' ../carm-editor/src/ ../craft/src/ ../cf-tools/

# 4. For Cloudflare API patterns (KV / DO / R2 / queues / AE), check
#    cf-tools first — utility may already exist
ls ../cf-tools/src/
```

State explicitly in your fix-plan comment or commit body:

> "Mirrors `<existing function>` at `<file:line>`. Same shape, different
> trigger condition / different layer."

If you genuinely can't find a sibling, **justify why** before inventing:
"No existing pattern for X because <reason>. Closest is `<fn>` which does
Y differently."

This rule caught the cycle 5 design itself — `needs_article_redirect()`
mirrors the slug-resolution at `src/routes/article.rs:17-32`. Same
segment-splitting, same WordPress-pagination strip, same `meaningful`
slice. Just at an earlier pipeline layer.

**4b. Implementation rules:**

- **Read documentation/source FIRST.** Never trial-and-error.
- One file when possible. Smallest diff that fixes the root cause.
- **Never recreate Worker requests.** Use `Request::clone_mut()` to unlock
  immutable headers if needed.
- Match existing patterns in the file (`is_legitimate_file_type`,
  `is_allowed_path`, etc.). The sibling you found in 4a is your template.

### 5. Test locally — curl matrix THEN Chrome smoke

This is two distinct phases. The curl matrix is cheap and catches the
adjacent regressions Chrome smoke can miss.

**5a. Start dev server:**

```
./node_modules/.bin/wrangler dev --port 8787 --env development
```

`--env development` is the only working combo for this repo:

- Plain `--local` hits the remote KV proxy → 302 Moved Temporarily
- `--remote` fails on bindings without `id`
- `--env development` works

Wait for "Ready on http://localhost:8787" (use Bash with `until curl -sS -o
/dev/null http://localhost:8787/ 2>/dev/null; do sleep 1; done`).

**5b. Curl matrix (mandatory for any path-routing/redirect change):**

If your fix touches any of: routing, path filters, redirects, route
registrations, request short-circuits — build a curl matrix that hits
*every* registered sub-route of the form your fix touches. Example for a
redirect short-circuit:

```
echo "=== Should fire ==="
curl -sS -o /dev/null -w "tag/foo                              → %{http_code} loc=%header{location}\n" http://localhost:8787/tag/foo

echo "=== Must NOT fire (every adjacent route handler) ==="
curl -sS -o /dev/null -w "/                                    → %{http_code}\n" http://localhost:8787/
curl -sS -o /dev/null -w "/single-slug                         → %{http_code}\n" http://localhost:8787/article-slug
curl -sS -o /dev/null -w "/search                              → %{http_code}\n" http://localhost:8787/search
curl -sS -o /dev/null -w "POST /<slug>/reading                 → %{http_code}\n" -X POST http://localhost:8787/article-slug/reading
curl -sS -o /dev/null -w "/<slug>/user/data                    → %{http_code}\n" http://localhost:8787/article-slug/user/data
# ... one line per registered route in lib.rs
```

**Build the matrix from the actual route registrations** (`grep -nE
'\.(get_async|post_async)' src/lib.rs`), not from memory. Memory will
miss a route. The curl matrix MUST cover every line that comes back.

If any "must NOT fire" line redirects/302s/breaks → STOP and fix before
proceeding to Chrome smoke. This is the cheapest place to catch a
regression.

**5c. Chrome DevTools MCP smoke suite — four steps, snapshot at each:**

| Step | Path | Verify |
|------|------|--------|
| Homepage | `/` | popular articles render, search box focused |
| Article preview | `/<known-article-slug>` | title, author, intro paragraph, Turnstile iframe present |
| Reading progress | `POST /<slug>/reading` body=`{"scrollTop":100,"scrollHeight":4000,"viewportHeight":800,"headerHeight":120,"isCompletionTrigger":false}` | 200 "Progress tracked" |
| Search | submit a query from `/` | results render, count > 0 |

This is production code — never deploy untested.

### 6. Bump patch version

Edit `Cargo.toml` `version = "x.y.Z"` → `x.y.Z+1`. `Cargo.lock`
auto-updates on deploy.

### 7. Deploy

```
./node_modules/.bin/wrangler deploy
```

Capture the `Current Version ID:` line — it goes in the issue close note.

**In `--auto` mode:** deploy without asking. **In attended mode:** the
matrix and smoke results are now in chat; ask `AskUserQuestion` "Deploy
v<new>?" before running this step.

### 8. Verify in production

- `wrangler tail --format pretty` again, 30-60s
- Re-run the same 4-step Chrome smoke against `https://<prod-host>`
- Re-run a *trimmed* version of your curl matrix against prod (just the
  paths your fix targets — confirms the deployed binary matches local)
- Count tail events matching the original symptom — should be zero

If the original signal is still firing, **do not commit**. Roll forward
or revert; do not paper over.

### 9. Cost-reviewer (mandatory)

Spawn the `cost-reviewer` subagent on the staged changes. No exceptions
(this is in the project CLAUDE.md as a hard rule).

### 10. Commit with `Closes #N`

Use `/commit` skill. Footer must include `Closes #N` so the issue
auto-closes on push.

### 11. Push to main

`git push`. Trunk-based — no feature branches. Push auto-closes the
linked issue via the `Closes #N` trailer.

### 12. Add an issue close note

`glab issue note <N>` with:

- Commit SHA + deploy version ID
- Before/after metric (events/min before → 0 after, extrapolated to
  per-day / per-month)
- **Value gained** — repeated from the issue body, with the actual
  observed numbers slotted in

### 13. Update state and STOP (or loop)

- Append to `cycle_history`, increment `completed_cycles`
- If `completed_cycles == target_cycles` → say `"done"` and stop
- If more cycles remain:
  - **`--auto`**: immediately start the next cycle from step 1
  - **attended**: print the cycle summary and wait for `next` from the user

## Examples — actual cycles run on CARM

These illustrate the kinds of bugs to look for and the smoke-test
discipline that caught regressions. Each was found in a 30-60s tail.

### Cycle 2 — Pure perf optimization (gate POSTs behind threshold)

- **Symptom**: tail showed POST /reading firing on every scroll pixel
- **Root cause**: no debouncing in the Datastar `@post('/reading', ...)` binding
- **Fix**: 5% scroll-delta threshold gate (`templates/fragments/article.html`,
  one expression change)
- **Result**: ~95% reduction in /reading POSTs without losing progress fidelity
- **Commit**: `2c9d6e5`

### Cycle 4 — Static-asset shortcut beats Worker handler

- **Symptom**: iOS Safari probing /apple-touch-icon-precomposed.png,
  /apple-touch-icon-180x180.png, etc. — each running the full Worker stack
- **Root cause**: Worker had no /apple-touch-* handler, so requests fell
  through 9 layers to the article handler's asset-extension 404
- **Fix**: add a single icon to `/static/` + `<link rel="apple-touch-icon">`
  in the layout. The Cloudflare assets CDN serves the file before the Worker
  is even invoked.
- **Lesson**: for any well-known probe path (favicons, manifest.json,
  robots.txt, browserconfig.xml), ship a static asset rather than building
  a Worker handler.
- **Commit**: `005e64b`

### Cycle 5 — Layer 0.5 short-circuit + the bug the smoke caught

- **Symptom**: tail showed full bot-analytics + x402 + DO routing burned on
  legacy WordPress URLs (`/tag/foo`, `/category/jesus`, `/<slug>/page/2/`)
  that the article handler always 302s anyway
- **Root cause**: article handler's redirect happens at the END of the
  pipeline (`src/routes/article.rs:28`), after 9+ layers of work
- **Fix v1**: add `needs_article_redirect()` at Layer 0.5, mirroring the
  article handler's slug-resolution logic. 302 before any expensive work.
- **Smoke caught a regression**: the curl matrix showed `POST /<slug>/reading`
  302'ing to `/reading`. My exclusion list covered 3- and 4-segment routes
  but missed `/:page/reading` (2 segments). Rewrote as a `match
  segments.len()` keyed off the actual `.post_async()` registrations in
  `src/lib.rs:327-330`.
- **Lesson 1 (THE big one)**: when mirroring a handler's logic at an
  earlier layer, build your exclusion list from the **actual route
  registrations in lib.rs**, not from memory or comments. Comments rot;
  registrations don't. `grep -nE '\.(get_async|post_async)'
  src/lib.rs` is the source of truth.
- **Lesson 2**: the curl matrix is non-negotiable for routing changes.
  Chrome smoke alone won't hit the POST endpoints; the matrix does.
- **Commit**: `<this cycle's commit>`

## Cost-conscious subagent dispatch

Three roles run during a cycle — assign each to the cheapest model that
preserves output quality.

| Role | Examples | Model | How to invoke |
|---|---|---|---|
| **Orchestrator** | This loop, root-cause judgment, design decisions, ambiguity | Opus 4.7 (parent) | Default — runs as me |
| **Specialist** | `cost-reviewer` (Cloudflare cost traps), `researcher` (read code, summarize patterns), `Plan` (architectural plans) | Sonnet 4.6 | Pre-configured via agent frontmatter (`~/.claude/agents/*.md`) — `Agent` tool picks up automatically |
| **Pattern-matcher** | Curl-matrix runner (run N curls, tabulate codes), tail-log scanner (grep for known error shapes), smoke-suite assertion checker | Haiku 4.5 | **Pass `model: "haiku"`** explicitly when spawning `Agent` |

**When to override with explicit `model` in the Agent call:**

- **Downgrade to `model: "haiku"`**: any subagent whose job is "run this
  list, return a structured table" — pure pattern-matching, no novel
  reasoning. The curl matrix in step 5b and the prod tail scan in step 8
  are the prime candidates. Example:

  ```
  Agent({
    description: "Run curl matrix",
    subagent_type: "general-purpose",
    model: "haiku",
    prompt: "Run these 12 curl commands against http://localhost:8787, return a table of {path, status, location_header}. Flag any path in the 'must NOT redirect' section that returns 3xx."
  })
  ```

- **Upgrade to `model: "opus"`**: if a Sonnet specialist hits a genuinely
  ambiguous case (researcher reports "no sibling pattern found,"
  cost-reviewer flags something with multiple plausible interpretations),
  re-spawn with `model: "opus"` for that specific call.

- **Default (no override)**: the agent's frontmatter wins. `cost-reviewer`
  and `researcher` are already Sonnet — don't pass `model` for them
  unless upgrading per above.

**`--auto` mode rule**: Auto mode never silently upgrades a downgraded
model to save speed. If a Haiku subagent reports an unclear result, halt
the loop and surface it to the user — don't auto-retry with Opus, that
defeats the cost discipline.

## Common bug-pattern signals in tail

- **Duplicate fires per page load** → vestigial code path, kill it
- **Identical 302/redirect on every request to a path** → short-circuit
  candidate (move the redirect earlier in the pipeline)
- **404s for asset extensions** → static asset shortcut
- **Repeated `/some-path/user/data` 403s** → bot scraping; nothing to fix,
  but confirms the auth gate is working
- **POSTs every scroll/keystroke** → debounce or threshold-gate

## Things that are NOT bugs (don't waste a cycle)

- Cloudflare's own probes (`/cdn-cgi/*`)
- Bots hitting `/wp-admin/`, `/.env`, `/.git/config` — the gospel-404 is
  doing its job
- Single 500s without a stack — investigate but only file an issue if
  reproducible

## Rules and quirks

- **Pattern extraction before implementation** — every new function or
  block must name its sibling in the codebase. No sibling? Re-research.
  Don't fall back on training-data conventions; they look right but
  diverge from production patterns.
- **Trunk-based**: commit directly to main. No feature branches. The push
  auto-closes the issue.
- **Never `--no-verify`** the commit hook. If it fails, fix the underlying
  issue.
- **Never `git reset --hard` or `git push --force`** without explicit
  user permission.
- **`--auto` mode never bypasses the cost-reviewer subagent.** It only
  bypasses the deploy/commit/push confirmations.
- **`--auto` mode stops on**: smoke-test failure, cost-reviewer flagging
  a regression, prod tail still showing the original symptom after deploy,
  pre-commit hook failure, or `target_cycles` reached.
- **One bug per cycle.** Resist scope creep. If you see a related issue
  during fixing, file a separate ticket and link it; don't roll it into
  the current cycle.
- **Always include "Value gained"** in the issue body, the commit
  message footer, and the close note. This is how we measure ROI.

</instructions>
