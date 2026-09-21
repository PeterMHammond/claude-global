---
name: dead-code-audit
description: Two-phase audit that finds provably-dead code and collapsible abstractions in a Rust/workers-rs codebase, then removes them under compiler verification. Invoke manually with /dead-code-audit.
disable-model-invocation: true
---

# Dead code + abstraction audit

Two phases. **Never run both in one session.** Phase 1 writes findings to a file and stops.
Phase 2 runs in a fresh context and executes only what Phase 1 proved.

Scope: $ARGUMENTS (a crate, a module path, or the whole workspace). Default to the workspace
only if nothing is given.

---

## Phase 1 — Audit (read-only)

You are in plan mode. **Do not edit any file.** Output is `DEADCODE.md` and nothing else.

### The standard of proof

Every finding needs a command whose output proves it. If you cannot produce that command,
the finding goes in the LIKELY bucket for a human to judge — not in PROVEN, and never
into a diff. "This looks unused" is not a finding. A compiler warning is.

You will be tempted to pad the report. Don't. A short report of ten proven deletions is
worth more than fifty speculative ones, and speculative entries are how load-bearing code
gets deleted. Report zero findings in a bucket if that's the truth.

### Step 1: make the compiler talk

Rust's `dead_code` lint is blind to anything `pub` in a lib crate — everything public is
assumed reachable. That's why most Rust dead-code hunts find nothing. Break that first:

```bash
cargo clippy --workspace --all-targets --target wasm32-unknown-unknown -- \
  -W unreachable_pub -W unused_crate_dependencies -W dead_code
```

`unreachable_pub` names every `pub` item not actually reachable from the crate's public API.
Each one you demote to `pub(crate)` makes `dead_code` able to see it. **This cascades**:
deleting an item makes its callees dead too. Model the fixpoint in the report — for each
proven-dead item, walk its call graph and count what dies with it. Report the transitive
LOC, not the local LOC.

Then:

```bash
cargo machete --with-metadata          # unused deps, text scan, fast
cargo shear                            # unused deps, real parse, fewer false positives
cargo build --release --target wasm32-unknown-unknown
twiggy top -n 40 target/wasm32-unknown-unknown/release/*.wasm
twiggy dominators target/wasm32-unknown-unknown/release/*.wasm
```

`twiggy dominators` answers "what would actually shrink if I removed this" — use its retained
size, not shallow size, to rank findings. This is a Worker: bytes are cold-start latency.

### Step 2: reachability escape hatches — DO NOT flag these

These are reachable through macro expansion or the runtime, and the compiler's silence about
them means nothing:

- `#[event(fetch)]`, `#[event(scheduled)]`, `#[event(queue)]`, `#[event(start)]`
- `#[durable_object]` impls — `fetch`, `alarm`, `websocket_message`, `websocket_close`, `websocket_error`
- Anything `#[wasm_bindgen]` or `#[no_mangle]` or `#[used]`
- Struct fields that exist only for `Serialize`/`Deserialize`
- Askama `#[template(...)]` structs and their fields — fields are consumed by generated code
- `#[cfg]`-gated code for a target you didn't build
- Anything named in `wrangler.toml` / `wrangler.jsonc` bindings, routes, or migrations

If a finding touches any of these, drop it. Do not "verify by deleting and seeing if it builds"
— several of these fail at runtime, not compile time.

### Step 3: abstractions worth collapsing

Use countable criteria. Aesthetic judgments about "clean architecture" are out of scope.

| Pattern | Collapse when |
|---|---|
| trait | exactly 1 impl, no `dyn` use, no test double |
| generic param | instantiated at exactly 1 type across the workspace |
| private fn | exactly 1 call site and under ~10 lines |
| newtype | wraps one field, enforces no invariant (no private field + validating ctor) |
| error enum variant | never constructed anywhere |
| module | body is only `pub use` re-exports |
| wrapper fn | forwards its arguments unchanged |
| `Box<dyn Fn>` / trait object | only ever holds one concrete type |
| builder | struct has ≤3 fields, all required |
| `async fn` | contains no `.await` |
| `Arc<Mutex<T>>` | inside a Durable Object — the isolate is single-threaded; `RefCell` or `&mut` suffices |
| `Result<T, E>` | `E` has exactly one variant that is never matched on |

For each: give the call-site count or impl count that justifies it, and the net LOC delta.
An abstraction with one implementor *today* that has a second one on a plan you can see in
the repo is not a finding.

### Step 4: dead code the compiler cannot see

Grep-level, judgment required. **Report only. Never delete in Phase 2.** This is usually where
the real liability lives:

- KV / R2 / D1 / DO-storage keys written but never read, or read but never written
- SQL columns in DO SQLite schemas that nothing selects
- Askama blocks / templates / partials nothing includes
- Datastar: `data-signals` declared in a template but never read by any `data-*` binding, and
  never patched by any server-side `datastar-patch-signals`; SSE event types the client
  handles but the server never emits (and the reverse)
- HTTP routes with no caller in the repo and no external contract documenting them
- Feature flags whose value is constant at every call site
- Env vars / secrets read in code but absent from `wrangler.toml`, and vice versa

### Output

Write `DEADCODE.md`. Nothing else. Three buckets, each sorted by retained wasm bytes descending
(fall back to transitive LOC where twiggy has no entry):

```
## PROVEN — compiler or tool asserts it
- `src/foo/bar.rs:42` `fn parse_legacy_header`
  evidence: cargo clippy ... -W dead_code → "function is never used"
  cascade: also kills `HeaderKind` (28 LOC), `LEGACY_PREFIX` (1 LOC)
  removes: 94 LOC, ~1.2KB wasm retained
  risk: none — no macro/runtime reachability

## LIKELY — grep evidence, needs your call
- (same shape, plus: what would confirm it)

## ABSTRACTION — collapse candidates
- (same shape, plus: impl/call-site count, net LOC delta)
```

Then stop. Do not offer to start deleting. End your turn.

---

## Phase 2 — Execute (fresh session, `/clear` first)

Read `DEADCODE.md`. **Execute the PROVEN bucket only.** LIKELY and ABSTRACTION items require
the human to have marked them approved in the file first; treat unmarked ones as out of scope.

Working rules:

1. One commit per logical deletion, including its cascade. Never batch unrelated removals.
2. After every commit, all three must pass:
   ```bash
   cargo check --workspace --all-targets --target wasm32-unknown-unknown
   cargo clippy --workspace --all-targets --target wasm32-unknown-unknown -- -D warnings
   cargo test --workspace
   ```
   Paste the output. Don't assert success — show it.
3. Re-run `cargo clippy -- -W dead_code` after each commit. Deletions unlock new dead code.
   Loop until it reports nothing new, and note each new item you removed.
4. If a deletion breaks a test, **stop and report**. Do not fix the test. A failing test means
   the item wasn't dead and the audit was wrong.
5. Never change behavior while removing code. No renames, no signature changes, no "while I'm
   here" fixes. Mechanical removal only.
6. Record the before/after `.wasm` size:
   ```bash
   cargo build --release --target wasm32-unknown-unknown && \
     ls -l target/wasm32-unknown-unknown/release/*.wasm
   ```

Finish with a summary: commits made, LOC removed, wasm delta, and anything from PROVEN you
declined to remove and why.
