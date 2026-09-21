---
name: rust-review
triggers:
  - /rust-review
  - /rusty
  - rusty
description: Deep Rust code review for recent changes. Analyzes for refactoring opportunities, modern patterns, unnecessary clones, hot-path performance, and best practices. Invoke with /rust-review, /rusty, or just "rusty" after commits or code changes.
---

# Rust Review

Use extended thinking for thorough analysis. #override

## Philosophy

**Foundation over fixes.** When identifying issues, look deeper than the symptom:
- A boolean return often signals a missing enum
- A number check often signals unmodeled state
- A scattered `if/else` often signals logic that belongs in an `impl` block
- A validated `&str` or `f64` parameter signals a missing newtype
- An `is_*` flag guarding a method signals a missing typestate
- A fight with the borrow checker signals a signature claiming more than the body touches

Don't patch - redesign. Ask: "What is this code *trying* to represent?" Then use Rust's type system to make that representation explicit. The fix should strengthen the architecture, not just silence the immediate problem.

**Build for the future.** Solutions should:
- Make invalid states unrepresentable
- Force exhaustive handling via `match`
- Centralize state transition logic in `impl` blocks
- Create types that other code can build upon

**Debug with evidence.** When fixing issues:
- Don't blame established working patterns without proof (if it works in project A but not B, the issue is likely in B's new code)
- Version-keyed storage (e.g., `key_v{VERSION}`) can mask corrupt state - bumping version fixes symptoms without finding root cause
- Verify the actual fix before committing; correlation is not causation

## Scope

**Start** with recent changes, **follow** wherever the findings lead.

1. Identify changed `.rs` files (uncommitted + recent commits)
2. Analyze those files against the full checklist
3. **If a finding requires changes to other files — make them.** Don't stop at file boundaries. If consolidating a constant means editing `models.rs` and three consumers, edit all four. If extracting shared logic means refactoring the parent module, refactor it.
4. After fixing, re-scan touched files for cascading opportunities

```bash
# Changed files (starting point)
git diff --name-only; git diff --staged --name-only; git ls-files --others --exclude-standard -- '*.rs'
```

## Analysis Checklist

For each changed `.rs` file:

### 1. Clone Analysis
- Identify every `.clone()` call
- Determine if clone is necessary or if borrowing/references work
- **Clone to silence the borrow checker (E0499/E0502)**: not a fix — the signature claimed more than the body needs. See §14 before cloning, `mem::take`ing, or reaching for `RefCell`
- Check for implicit clones via `to_string()`, `to_owned()`, `into()`
- Suggest ownership restructuring when clones indicate design issues
- **Signature smell**: `fn method(&self) -> OwnedType` that clones fields → change to `fn method(self)` to move instead
- **Repeated clones**: If cloning same field multiple times, extract a reference first (`let x = &self.field;`)
- **Redundant fields**: Flag structs with two fields holding the same value (e.g., `wallet` and `from` both storing address)
- **Take by ref, clone at construction**: Change `fn foo(val: Value)` to `fn foo(val: &Value)` and clone inside only when storing; caller shouldn't clone just to pass ownership
- **Return consumed data**: If function consumes a struct but caller needs a field after, return that field instead of forcing caller to clone beforehand: `fn process(task: Task) -> (Result, String)` returns the `network` the caller needs
- **Rc for shared ownership**: When same data goes into multiple structs, use `Rc<T>` with `Rc::clone()` instead of deep cloning; add `features = ["rc"]` to serde for serialization

### 2. Modern Rust Patterns
- Use `?` over `.unwrap()` where error handling is appropriate
- Prefer `if let` / `let else` over match for single-arm cases
- Prefer `map_or(default, fn)` over `.map(fn).unwrap_or(default)` - cleaner, single method
- Prefer `map_or(default, fn)` over `.map_err(...)?` when a default is acceptable
- Use `Option::map`, `and_then`, `unwrap_or_else` over explicit matches
- Apply iterator chains over manual loops
- Use `impl Trait` in arguments/returns where appropriate
- Leverage `Default` trait implementations
- Use `From`/`Into` for type conversions
- Apply `AsRef`/`Borrow` for flexible function signatures

### 3. Type System Usage
- Flag `(Value, bool)` returns - should be an enum modeling the state transition
- Flag raw number checks (`if n == 0`) - should match on semantic enum
- Ensure state transitions are first-class types, not derived booleans
- Look for enum `impl` blocks with constructor methods (`from_*`) to centralize logic
- **Guard stacks at the top of a function** — see §13; every guard is a bad state the type system was allowed to represent
- **Constants for fixed infrastructure** - well-known addresses (USDC contracts, chain IDs) should be `const`, not env vars with fallback to empty/default
- **No magic numbers** - string literals like `"10000"` should be named constants (`DEFAULT_PRICE_USDC_ATOMIC`)

### 4. Simplification
- Remove redundant type annotations
- **Labeled blocks for fail-fast**: Replace nested `if let` pyramids with labeled blocks:
  ```rust
  // Bad: pyramid of doom
  if let Some(a) = opt_a {
      if let Some(b) = opt_b {
          if let Ok(c) = result_c {
              // use a, b, c
          }
      }
  }

  // Good: flat fail-fast
  'block: {
      let Some(a) = opt_a else { break 'block };
      let Some(b) = opt_b else { break 'block };
      let Ok(c) = result_c else { break 'block };
      // use a, b, c
  }
  ```
- **Boolean guards → `?` pipeline** — `if !condition { return Err(e); }` is C-style. Use `condition.then_some(()).ok_or_else(|| e)?` to keep booleans in the `?` chain. An entire validation function should read as a continuous `?` pipeline, not alternating `let` bindings and `if/return` guards. **But apply §13 first** — the best `?` pipeline is the one you deleted. Only pipeline the guards that survive the §13 test; converting a guard that shouldn't exist just makes a liability prettier.
- Collapse nested `if` statements
- Replace `if x { true } else { false }` with `x`
- Use `matches!` macro for boolean match expressions
- Apply destructuring in function signatures and let bindings
- Prefer direct math over multi-step derivations (`interval - (now % interval)` not `((now / interval) + 1) * interval - now`)
- **Inline one-off logic** - don't extract functions for operations used once; see §6 Call Graph Analysis for the full methodology
- **Trust data contracts** - use `unwrap()` when invariants are guaranteed, don't handle impossible cases
- **Strongly-typed JSON** - use `#[derive(Serialize, Deserialize)]` structs instead of `serde_json::json!()` macro; the struct IS the schema
- **Minimal documentation** - doc comments should only cover what isn't obvious from the code; avoid restating function names, obvious parameters, or including example code that duplicates the signature; tokens cost money
- **Use constants directly** - don't create intermediate `let x = CONST;` then use `x`; just use `CONST` directly
- **No redundant processing** - `checksum_address(ALREADY_CHECKSUMMED_CONST)` is wasteful; trust const definitions
- **No decorative comments** - avoid `// ========` section dividers; they waste tokens
- **Chain operations** - `Url::parse(url).ok()?.host()?.to_string()` not spread across multiple `let` bindings
- **Single destructure** - if calling `.as_ref().map(|x| x.field)` multiple times, destructure once with `match` or `if let`
- **No duplicate extraction** - if a value is already in scope, don't re-extract it from another source
- **Trust downstream limits** - don't truncate/validate when the receiving system handles it (e.g., Workers AI input limits)
- **No name-mismatch adapters** - if an intermediate struct exists *solely* to rename fields between layers (UI calls it `body`, domain calls it `content`), rename at the source to match the domain model. Kill the adapter type, the `into_*()` conversion, and any defensive logic that only existed because of the mismatch. See §12.
- **No reinventing crate APIs** - before writing custom encoding, formatting, or conversion logic, check what the crate already provides. A `const` alphabet table + manual division loop is the smell. Example: `uuid::Uuid::now_v7().simple().to_string()` replaced an entire custom Base62 encoder that also introduced a case-sensitivity bug.

### 5. Consolidation Sweep

**Every line is a liability — compute, context window, comprehension, cost. The cheapest, fastest, most bug-free code is the code that doesn't exist.**

**Principle: plan the simple path upfront.** Don't build complexity then refactor it away — think it through before writing. Direct code that does the job in fewer lines with zero loss of clarity is always better. Every wrapper, module, alias, intermediate variable, response body, and dependency must earn its existence.

**Before accepting any code, ask:** *Why are we doing this? Is it needed? Is there a simpler way? Can we eliminate it entirely?* Follow the chain — questioning a JSON response body led to removing the body → removing the helper function → removing the `serde_json` dependency. One "why" eliminated an entire crate. The deepest simplification comes from questioning whether something should exist at all, not from making it smaller.

**Three red flags that something should not exist:**
1. **It's a single-line function** — if removing the function and inlining changes nothing about clarity, it shouldn't be a function. But go deeper: if the inlined version also looks wrong, the CONCEPT is wrong. A `deny()` function wrapping `Error::RustError(String::new())` isn't just an unnecessary wrapper — it reveals that you're manufacturing errors where none belong.
2. **HTTP already has a standard for this** — auth failure is a 401 Response, not an `Error`. Rate limiting is a 429 Response, not an `Error`. Bad input is a 400 Response, not an `Error`. If you're constructing `Error::RustError(...)` for a client-caused condition, you're using the wrong type. `Error` is for infrastructure failures (DO unreachable, KV timeout). Client failures are Responses with status codes.
3. **You're constructing a string nobody reads** — `"authentication failed".into()` or even `String::new()` going into an error that callers catch and discard. If the consumer ignores the value, the value shouldn't be constructed. Follow this signal: if you empty the string and nothing breaks, the string was never needed. If the string was never needed, the error wrapping it was never needed. If the error was never needed, the function returning it was never needed.

**The correct pattern:** Functions that validate but don't own the HTTP response return `Option<T>`, not `Result<T, Error>`. Validation succeeds (`Some`) or fails (`None`). The caller — who owns the HTTP response — decides the status code. `.ok()?` converts library Results to Option. `.then_some(())?` gates booleans. No error types manufactured, no strings allocated, no wrappers written.

This sweep catches what slipped through. Walk every module and ask:

- **Scattered constants** — grep for `pub const` outside `models.rs`. If used across modules, centralize. One place to find them, one place to change them.
- **Duplicate sibling logic** — compare handlers that do similar work (signup vs login, create vs update). If 5+ lines are identical, extract once. Return a struct carrying everything both callers need so they don't re-derive values. Name it for what it proves (`VerifiedWallet` not `SiweResult`).
- **One-value types** — `OkResponse { ok: true }` is never `false`. Delete the struct, inline `Response::from_json(&serde_json::json!({"ok": true}))` at the two call sites. A one-liner used twice doesn't need a function — the call is already self-documenting.
- **Fragmented modules** — new files follow the existing grouping. Auth logic → `auth/`. Routes → `routes/`. Before creating a new top-level module, ask: which existing module owns this concern?
- **Unnecessary indirection** — `mod keys { pub const X: &str = "x"; }` wrapping literals used once → inline them. `let x = foo(); bar(x)` on adjacent lines → `bar(foo())`. Two `use` lines from the same module → merge.

**The test:** for every module, type, constant, and function — *"Does removing this make the code shorter with zero loss of clarity?"* If yes, remove it.

### 6. Call Graph Analysis (Single-Caller Collapse)

Walk the call graph from each entry point (e.g., `fetch`, queue consumer, scheduled handler). At every function call, ask: **how many call sites does this function have?**

**Methodology:**
1. Start at the entry point
2. Walk depth-first into each function it calls
3. For each function: grep for its name — if exactly one call site, it's a collapse candidate
4. Inline the body into the caller, remove the function
5. Repeat up the call chain — collapsing one function often reveals the next

**What to flag:**

- **Free functions with one call site** — not an abstraction, it's obfuscation; fragments understanding and inflates token count
  ```rust
  // Bad: fn only called from one place
  fn zero_trust_email(req: &Request, env: &Env) -> Option<String> { ... }
  let email = zero_trust_email(&req, &env);

  // Good: inline it, the logic is right here where it's used
  let email = req.headers().get("Cf-Access-Authenticated-User-Email").ok().flatten()
      .or_else(|| env.var("DEV_EMAIL").ok().map(|v| v.to_string()));
  ```

- **Derived parameters** — if a parameter can be computed from another parameter already in scope, remove it; let the function derive it
  ```rust
  // Bad: path is derived from req, which is already passed
  fn zero_trust_callback(req: &Request, env: &Env, ctx: &Context, path: &str)

  // Good: derive inside
  fn zero_trust_callback(req: &Request, env: &Env, ctx: &Context) {
      let path = req.path();
  ```

- **Extraction logic as free functions instead of from_source()** — if a function constructs a type by reading from a request/env/header, it belongs on the type as an associated function
  ```rust
  // Bad: free function that constructs SessionData
  fn verify_session(req: &Request, env: &Env) -> Result<SessionData>

  // Good: construction belongs on the type
  impl SessionData {
      pub fn from_request(req: &Request, env: &Env) -> Result<Option<Self>>
  }
  ```

- **Wrapper functions that just rename** — `get_session_token()` that only reads a cookie by name adds a layer without adding meaning; the cookie name is an implementation detail of the type, not of the caller

**The test:** Could a reader understand the calling function without jumping to the definition? If the function body is short, obvious, and not reused — the answer is yes, after inlining. If it's called in 5 places — leave it.

**Why this matters:** Every unnecessary function boundary is a context switch. It fragments the logic across the file, requires the reader (human or AI) to jump to definitions, and increases the surface area of the codebase. Inlining single-callers makes the code read like a story — top to bottom, no detours.

### 7. HTTP Standards & Production Hardening

This is not a demo. HTTP status codes exist for a reason — use them precisely.

- **Never let `Error::RustError` reach the client** — workers-rs converts unhandled `Err(Error::RustError(...))` into 500 Internal Server Error. A 500 signals a bug in YOUR code, not a problem with the request. If the client did something wrong, return the correct 4xx. If a shared function returns `Err`, callers must catch it with `let else` and return the proper HTTP response — never blindly `?` propagate internal errors into 500s.
- **Status code precision:**
  - **400** — malformed request (bad JSON, missing fields, invalid format)
  - **401** — authentication failed (bad signature, expired nonce, wallet mismatch) — NEVER 500
  - **403** — authenticated but not authorized (no account, TOS not accepted, wrong wallet for resource)
  - **404** — resource doesn't exist
  - **429** — rate limited
- **Opaque error messages on auth paths** — never reveal which validation step failed. "authentication failed" for all of: expired nonce, replayed nonce, bad signature, wallet mismatch. Attackers get nothing to differentiate failure modes.
- **No information leakage** — don't expose internal error details (`signature verification failed: InvalidRecoveryId`), stack traces, or library error messages to clients. Log them server-side, return generic messages.
- **Response bodies earn their bytes** — if the status code says it all (`200` + `Set-Cookie`), the body is noise. `Response::ok("")` not `Response::from_json({"ok": true})`.
- **CSRF on all mutating methods** — POST, PUT, PATCH, DELETE. Not just POST.

### 8. Robustness (Internal)
- Check error handling completeness
- Identify potential panics (unwrap, expect, indexing)
- Verify lifetime annotations are minimal but sufficient
- Look for missing `#[must_use]` on functions returning values
- **Serde defaults on wrappers**: When struct wraps types with `Default`, add `#[serde(default)]` to fields for graceful deserialization
- **Endpoint response consistency**: When introducing wrapper structs, ensure ALL related endpoints return the same type (grep for return sites)

### 9. Idioms
- Consistent naming (snake_case, SCREAMING_SNAKE_CASE)
- Appropriate visibility modifiers
- Module organization follows Rust 2018+ conventions
- Documentation on public items

### 10. Cloudflare Workers (when applicable)
- **CRITICAL**: Never create new `Request` objects when forwarding to Durable Objects
- Use `req` directly or `req.clone_mut()` if headers need modification
- `Request::new_with_init()` is an anti-pattern - it discards all telemetry
- If reading body AND forwarding: clone BEFORE `req.json().await?`
- Prefer header-based routing over body parsing when possible
- **KV direct serialization** - `kv.put(key, &struct)` not `kv.put(key, serde_json::to_string(&struct)?)`; KV accepts Serialize directly
- **Queue direct serialization** - `q.send(task)` not `serde_json::to_string(&task)` then `q.send(&json)`; use typed `MessageBatch<T>`
- **Typed queue messages** - For multiple message types, use untagged enum: `#[serde(untagged)] enum QueueTask { A(TypeA), B(TypeB) }`
- **Service binding with fallback** - Try binding first, fall back to Fetch for DNS origins:
  ```rust
  match env.service(&binding) {
      Ok(s) => s.fetch_request(req).await,
      Err(_) => Fetch::Request(req).send().await,
  }
  ```
- **Binding naming** - Use lowercase, strip `www.`: `host.strip_prefix("www.").unwrap_or(&host).replace('.', "_")`

### 11. Process Discipline
- **Interview before implementing** - When refactoring, ask clarifying questions before jumping in; understand requirements first
- **Check git history first** - Before reimplementing, check how it worked: `git show <commit>:path/to/file.rs`
- **Don't step backwards** - When refactoring to a new convention (e.g., lowercase), don't revert to old patterns just because they existed
- **Minimal code** - Every line must be justified; if you can't explain why it's needed, remove it
- **NEVER band-aid** - When something is broken, find and fix the root cause; never mask symptoms with workarounds like "if error contains X then ignore"; investigate WHY the error occurs and eliminate it at the source

### 12. Name-Mismatch Adapter Detection

When you see an intermediate struct whose only purpose is renaming fields between boundaries, the entire struct is a symptom of a naming misalignment — not a design need.

**The smell:** A type with `into_*()` or `from_*()` that maps fields 1:1 with different names between source (UI, API, wire format) and destination (domain model).

**The test:** Remove the intermediate type mentally. If the only obstacle is that field names don't match, the fix is renaming at the source — not building conversion machinery.

**What to check:**
- Does the adapter struct have fields that map 1:1 to the target struct?
- Does the conversion method contain only field renaming + trivial transforms (like empty-string-to-None)?
- Could the trivial transforms live on the target type instead (e.g., a serde `deserialize_with` helper)?
- Is there a second call site that already deserializes directly into the target type, proving the adapter is unnecessary?

**Why this matters:** A single naming mismatch can spawn an entire adapter type, a conversion method, and defensive logic — all of which are pure liability. Renaming the source to match the domain model eliminates the type, the conversion, and the defensive code in one stroke. The complexity was never in the conversion — it was in the name.

### 13. Guard Elimination — Make Bad States Unrepresentable

**The detector: a stack of guard clauses at the top of a function.** Every guard is a confession: the signature accepts a state that must never exist — a runtime apology for a compile-time failure. And it's per-call-site; forgetting the guard at one caller is a bug that ships. The target: `fn send_invoice(conn: &Connection<Open>, email: Email, amount: Money)` — not one check remains, because not one bad state can be written down.

**Trigger this section whenever you see:**
- Two or more `if …  { return Err(…) }` / `bail!` / `ensure!` lines before the real work begins
- A `&str` / `String` parameter that the body validates (empty, format, length, charset)
- `f64` / `f32` holding money, or any bare numeric that the body range-checks (`<= 0`, `> MAX`)
- A `bool` field named `is_*` / `has_*` / `*_open` / `*_ready` that some method reads before acting
- A method that `panic!`s or returns `Err` because the receiver is "in the wrong state"
- A struct of `Option` fields where certain combinations are nonsense

**Apply in order — each level deletes guards the previous one could not** (full examples: `references/patterns.md`):

**Level 1 — Enums over flag-and-Option soup.** `bool` + parallel `Option`s encodes 3 real states in 8 representable combinations; the other 5 are bugs you can type. `enum Invoice { Pending, Paid(Receipt), Failed(String) }` admits exactly the real ones, with data inside the variant that owns it. Consume with `match`, never a getter that re-derives state — add a variant later and the compiler names every site that must handle it.

**Level 2 — Newtypes with fallible constructors (parse, don't validate).** Move validation from *every call* to *one construction*: `Email::parse(raw)` is the only way to build an `Email`; `Money { minor_units: i64, currency }` — never `f64`, which can't represent 10 cents exactly and carries no currency (flag on sight). Two requirements or it doesn't work: inner field **private** (`pub struct Email(pub String)` is a `String` wearing a hat), and the constructor is **the only** door in — no `From<String>` that skips validation. Parse at the system boundary (request deserialization, config load, DB read); never let the raw primitive travel inward.

**Level 3 — Typestate for lifecycle guarantees.** When the guard is about *what has happened yet* — connected, authenticated, committed — zero-sized marker types forbid the call instead of reporting it: `Connection<Closed>::connect(self) -> Connection<Open>`. Transitions **consume** `self`, so the stale handle is gone; downstream takes `&Connection<Open>` and inherits the guarantee for free. **Cost check first:** use it when the lifecycle is real (2–4 states, enforced across module boundaries, misuse expensive). Skip it when the state never escapes one function, callers would need `Box<dyn>`/runtime tags to hold either state, or the generic would infect a dozen unrelated signatures — then a Level-1 enum with `match` is the honest answer.

**What legitimately survives:** guards against genuinely external, untrusted input at the boundary (that's where `Email::parse` lives — the check moved, it didn't vanish), and I/O-time conditions no type can promise (the socket died mid-flight). Everything else should have been made unrepresentable.

**The test for each guard:** *"Could I change a parameter's type so this check is impossible to fail?"* If yes, change the type and delete the check. Then chase it upstream — the guard doesn't disappear, it relocates to the one place the value is born.

### 14. Signature Contracts — Borrow Only What You Touch

**Rust's golden rule: a function is checked against its signature alone.** The compiler never reads another function's body to decide whether a call is legal. That's the source of Rust's best property — errors stay local, and changing a body cannot break callers — and it's why Rust proves memory safety where Java and C# cannot: `&mut` in the signature *is* the exclusivity claim, no body analysis required.

The cost is the other edge of the same blade. **A signature that asks for more than the body uses becomes a lie the compiler enforces against you.** `x_mut(&mut self)` and `y_mut(&mut self)` each claim the WHOLE struct — calling both is E0499 even though the fields are disjoint. You can see the bodies touch different fields; the compiler reads `&mut self` twice and stops.

**Flag these:**
- `&mut self` on a method whose body never mutates → `&self` (needlessly locks out every concurrent reader)
- `&self` / `&mut self` on a method that touches exactly one field → take that field
- Per-field `_mut()` accessors (`x_mut`, `cache_mut`, `state_mut`) — each one launders a whole-struct borrow through a signature that looks narrow
- `.clone()` inserted to silence **E0499** (two mutable borrows) or **E0502** (mutable + immutable) — see §1; the clone is a band-aid on an over-broad signature
- `RefCell` / `Rc<RefCell<_>>` introduced in single-threaded code to escape a borrow conflict — that trades a compile error for a runtime panic
- A struct that produces borrow conflicts repeatedly — its fields are unrelated concerns sharing one lock

**Fix in this order — cheapest first** (full examples: `references/patterns.md`):

1. **Access the fields directly in the body.** Borrow splitting *works within a single function body* — `let Point { x, y } = self;` yields two disjoint `&mut i32`. The conflict only appears when the projection goes *through a call*, so the usual fix is to stop calling the accessor, not to change the caller's signature.
2. **Hand back both at once** when callers genuinely need two fields across a call boundary: `fn xy_mut(&mut self) -> (&mut i32, &mut i32)`. One borrow, two disjoint results — the signature now tells the truth. (`slice::split_at_mut` is the same trick in std.)
3. **Narrow the signature to the fields it touches** — the method becomes a free or associated function taking `&mut i32, &i32`. Buys maximum precision; costs method ergonomics and leaks field structure to the caller. Use when the function is genuinely about the fields, not about the type.
4. **Split the struct.** Chronic conflicts mean the type bundles concerns that should be separate values with separate borrows.

**Never** reach for `.clone()`, `RefCell`, or `unsafe` to escape a borrow conflict. Each converts a compile-time complaint into a runtime cost, a runtime panic, or a soundness hole — and none of them fix the signature that caused it.

**The test:** *"Does this signature claim exactly what the body touches — no more?"* When the borrow checker rejects code you know is safe, the answer is no. Don't fight it; correct the claim.

### 15. Hot-Path Performance

Small tweaks with measured order-of-magnitude wins. Scan any loop that runs per-item over unbounded data (log lines, sessions, events, rows) — that's the hot path. Full examples: `references/patterns.md`.

- **No allocations in hot loops** — `to_string()` / `clone()` / owned `String` map keys inside a per-item loop multiply into millions of heap allocations. Borrow instead: key the map by `&str` slices into the source data, and convert to owned only the handful of values that leave the function (10 allocations at the return, not 20M in the loop — a measured 30% cut).
- **Dead `.collect()`** — collecting into a `Vec` that is immediately iterated, summed, or discarded materializes the whole sequence for nothing. Keep the chain lazy to its terminal operation.
- **One lookup, not three** — `contains_key` + `insert` + `get_mut` hashes the same key three times per item. `map.entry(key).or_default() += 1` finds the slot once (measured 12% cut).
- **Removal cost** — `Vec::remove(i)` shifts every later element to preserve order. Order irrelevant → `swap_remove(i)` is O(1) (measured 7000x on a 1M-element sweep). Removing many by predicate → `retain` / `retain_mut`: one pass, order preserved.
- **Use every core — native targets only** — a CPU-bound loop with independent iterations first becomes an iterator chain (`fold`), then Rayon parallelizes it: `par_iter`/`par_lines` + per-core `fold` + `reduce` to merge (measured 7x on 12 cores). **Never on wasm32/Workers** — the runtime is single-threaded; there the levers are fewer allocations and fewer round-trips.
- **Measure, don't assume** — every claim above came from a baseline. Time before and after (`std::time::Instant`, criterion, hyperfine); report the numbers or don't call it an optimization.

## Execution: Find → Fix → Verify → Repeat

This skill is designed to run repeatedly until the code is clean. Each invocation is a refinement pass.

**Each pass:**
1. **Find** — run the full analysis checklist (§1–§15) against changed files, following into any file as needed
2. **Fix** — apply every finding directly. Don't ask, don't list before/after — just fix it. Use Edit tool.
3. **Verify** — `cargo check` must pass after fixes. If it doesn't, fix the compilation error immediately.
4. **Measure** — run `git diff --stat` to count lines added/removed across all touched files
5. **Report** — summary with:
   - One line per fix, highlighting anything clever (e.g., "extracted `verify_siwe` — eliminated 25 duplicate lines across signup + verify")
   - **Line count: +N / -M (net: ±X)** — the scoreboard. Negative net = success.

**On subsequent runs (`/rusty` again):**
- Re-scan the same files plus anything touched by previous fixes
- Look for issues the previous fixes may have revealed (collapsing a function often exposes the next one)
- If nothing found, report **"Clean pass — no findings."** and stop

**The goal:** the user keeps running `/rusty` until they get a clean pass. Like smelting — each pass burns away more dross until only the metal remains.

## Patterns Reference

Consult `references/patterns.md` for detailed patterns and anti-patterns with examples.
