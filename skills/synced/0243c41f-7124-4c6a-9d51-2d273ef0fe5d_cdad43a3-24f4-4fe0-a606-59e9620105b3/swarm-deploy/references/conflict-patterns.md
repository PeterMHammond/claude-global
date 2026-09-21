# Conflict Patterns — Rust / Cloudflare Workers

Common merge conflicts when running parallel agents on a worker-rs project,
and how to resolve each one.

---

## Cargo.toml Conflicts

**Pattern:**
```toml
<<<<<<< HEAD
tokio = { version = "1", features = ["rt"] }
=======
tokio = { version = "1", features = ["rt", "macros"] }
>>>>>>> feat/durable-object
```

**Resolution:** Merge the feature sets. Take the union of all features listed:
```toml
tokio = { version = "1", features = ["rt", "macros"] }
```
For version conflicts: take the higher semver. Run `cargo update` afterward.

---

## `mod` Declarations in `lib.rs` / `mod.rs`

**Pattern:** Two agents both added `mod` declarations to the same file.
```rust
<<<<<<< HEAD
pub mod routes;
pub mod middleware;
=======
pub mod do_session;
pub mod do_ledger;
>>>>>>> feat/durable-object
```

**Resolution:** Keep all declarations. Order: types → worker → do → tests.
```rust
pub mod routes;
pub mod middleware;
pub mod do_session;
pub mod do_ledger;
```

---

## `use` / Import Conflicts

**Pattern:** Both agents added top-level `use` statements to `lib.rs`.

**Resolution:** Keep all `use` statements. Run `cargo check` — the compiler
will tell you if any are unused or duplicated.

---

## Type Redefinition Conflicts

**Pattern:** Two agents each defined the same type independently (because types
agent was skipped or the contract was incomplete).
```
error[E0428]: the name `PaymentError` is defined multiple times
```

**Resolution:**
1. Identify which definition is in `src/types.rs` (canonical).
2. Delete the other definition(s).
3. Update all `use` imports to point at `crate::types::PaymentError`.
4. This is a sign the decomposition was incomplete — note it for next time.

---

## Trait Impl Conflicts

**Pattern:** Two agents both implemented the same trait on the same type.
```
error[E0119]: conflicting implementations of trait `From<X>` for type `Y`
```

**Resolution:** One agent should not have implemented this. Read both impls,
keep the one in the file that owns the type, delete the other.

---

## wrangler.toml Binding Conflicts

**Pattern:** Two agents added `[[durable_objects.bindings]]` or `[[kv_namespaces]]`
entries and the TOML merged badly.

**Resolution:** TOML arrays must be contiguous. Rebuild the section manually
by taking all entries from both versions:
```toml
[durable_objects]
bindings = [
  { name = "SESSION", class_name = "SessionDO" },
  { name = "LEDGER", class_name = "LedgerDO" },
]
```

Run `wrangler deploy --dry-run` to verify.

---

## Logical Conflicts (same function, different implementations)

**Pattern:** Two agents each implemented `handle_payment_request()` differently.
There is no syntactic conflict — the later merge simply overwrites.

**Detection:** After merging, compare commit diffs:
```bash
git diff feat/worker-handler..feat/durable-object -- src/lib.rs
```

**Resolution:** This requires human judgment. Read both implementations,
understand the intent of each, and either:
- Pick the correct one
- Synthesize the best parts of both
- Note which agent misunderstood its scope and tighten the prompt for next time

This is the most dangerous conflict type because git does not catch it.
The defense is precise file ownership — agents should never implement
the same function.

---

## General Resolution Order

1. `src/types.rs`, `src/errors.rs` — resolve first, they affect everything else
2. `Cargo.toml` — resolve second, needed for compilation
3. `lib.rs` / `mod.rs` — structural, usually just additive
4. Domain files — usually clean if ownership was respected
5. `wrangler.toml` — verify bindings after everything else compiles

Run `cargo check` after each merge, not just at the end.
