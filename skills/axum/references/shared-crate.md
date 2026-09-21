# Shared crate for multi-worker monorepos

When 2+ workers share infrastructure, lift the common axum plumbing into a workspace crate.

## What belongs

- `HtmlTemplate<T: Template>` IntoResponse impl
- `AppError` enum + IntoResponse impl
- Common tower layers (request-id, structured logging, security headers)
- SSE helpers (Datastar event builders, KeepAlive defaults)
- `SendWrapper`-based state helpers
- Custom extractors shared across workers (`AuthedUser`, `PaidRequest`, etc.)
- Shared DTOs (User, Session, common types)

## What does NOT belong

- Worker-specific business logic.
- Concrete `AppState` — each worker's state differs; provide a `trait` if a pattern needs to be shared.
- DO definitions — those are per-worker by nature.
- Routes and handler functions.

## Layout

```
shared/
├── Cargo.toml
└── src/
    ├── lib.rs
    ├── response.rs        # HtmlTemplate, AppError
    ├── extractors.rs      # AuthedUser, PaidRequest, etc.
    ├── layers/
    │   ├── mod.rs
    │   ├── request_id.rs
    │   ├── tracing.rs
    │   ├── security_headers.rs
    │   └── payment.rs
    ├── sse.rs             # Datastar event helpers
    └── state.rs           # SendWrapper helpers, common traits
```

## Workspace setup

```toml
# /Cargo.toml
[workspace]
members = ["shared", "workers/*"]
resolver = "2"

# /workers/foo/Cargo.toml
[dependencies]
shared = { path = "../../shared" }
```

## Independent versioning (alternative)

If workers deploy on independent cadences, publish `shared` to a private registry and pin versions per worker. Lockstep is simpler; independent versioning is more flexible.

## Re-export hygiene

The shared crate should re-export anything a downstream worker needs so workers don't need to depend on axum/tower-http directly for shared types:

```rust
// shared/src/lib.rs
pub use axum;
pub use tower;
pub use tower_http;
pub use http;

pub mod response;
pub mod extractors;
pub mod layers;
pub mod sse;
pub mod state;

pub use response::{AppError, HtmlTemplate};
```

A new worker imports `shared::{AppError, HtmlTemplate, ...}` and gets everything.

## Done

- New worker can `cargo add shared` (path or registry) and have baseline plumbing in ~5 lines of `lib.rs`.
- `HtmlTemplate`, `AppError`, baseline layers consistent across all workers in the org.
- No duplication of these patterns in worker-specific code.
