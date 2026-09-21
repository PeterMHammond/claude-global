# New workers-rs + axum project scaffold

From zero, with the patterns in place from line one.

## Cargo.toml

```toml
[package]
name = "my-worker"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["cdylib"]

[dependencies]
worker = { version = "0.5", features = ["http"] }
worker-macros = "0.5"

# axum minimal — add features only when used
axum = { version = "0.8", default-features = false, features = ["http1", "json", "matched-path", "tokio", "query"] }
tower = "0.5"
tower-service = "0.3"
tower-http = { version = "0.6", features = ["cors", "trace"] }  # never "full"
http = "1"

# Serde + errors
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "1"
anyhow = "1"

# Optional — add only when used
# askama = "0.12"          # templates
# futures-util = "0.3"     # SSE streams
# async-trait = "0.1"      # custom extractors
# validator = "0.18"       # validated extractors

[profile.release]
opt-level = "z"
lto = true
codegen-units = 1
strip = true
panic = "abort"
```

## Directory layout

```
my-worker/
├── Cargo.toml
├── wrangler.toml
└── src/
    ├── lib.rs         # entrypoint
    ├── state.rs       # AppState
    ├── error.rs       # AppError
    ├── handlers/
    │   ├── mod.rs
    │   └── home.rs
    └── layers/        # custom tower layers (when needed)
        └── mod.rs
```

## src/lib.rs

```rust
use worker::*;
use axum::Router;
use tower_service::Service;

mod state;
mod error;
mod handlers;

pub use error::AppError;

#[event(fetch)]
async fn fetch(
    req: HttpRequest,
    env: Env,
    _ctx: Context,
) -> Result<http::Response<axum::body::Body>> {
    let app = build_router(env);
    Ok(app.call(req).await?)
}

fn build_router(env: Env) -> Router {
    use axum::routing::get;
    Router::new()
        .route("/", get(handlers::home::index))
        .route("/healthz", get(|| async { "ok" }))
        .with_state(state::AppState::new(env))
        .layer(tower_http::trace::TraceLayer::new_for_http())
}
```

## src/state.rs

```rust
use worker::{Env, send::SendWrapper};

#[derive(Clone)]
pub struct AppState {
    pub env: SendWrapper<Env>,
}

impl AppState {
    pub fn new(env: Env) -> Self {
        Self { env: SendWrapper::new(env) }
    }
}
```

## src/error.rs

See `references/responses.md` for the full `AppError` pattern. Minimal starter:

```rust
use axum::{http::StatusCode, response::{IntoResponse, Response}};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("not found")]
    NotFound,
    #[error(transparent)]
    Worker(#[from] worker::Error),
    #[error(transparent)]
    Other(#[from] anyhow::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let status = match &self {
            Self::NotFound => StatusCode::NOT_FOUND,
            _ => StatusCode::INTERNAL_SERVER_ERROR,
        };
        if status.is_server_error() {
            worker::console_error!("{self:?}");
        }
        (status, self.to_string()).into_response()
    }
}
```

## src/handlers/home.rs

```rust
use axum::extract::State;
use crate::{state::AppState, error::AppError};

#[worker::send]
pub async fn index(State(_s): State<AppState>) -> Result<&'static str, AppError> {
    Ok("hello")
}
```

## wrangler.toml

```toml
name = "my-worker"
main = "build/worker/shim.mjs"
compatibility_date = "2026-01-01"

[build]
command = "cargo install -q worker-build && worker-build --release"
```

## Verify scaffold

```bash
cargo check --target wasm32-unknown-unknown
wrangler deploy --dry-run --outdir /tmp/wbuild
ls -lh /tmp/wbuild/*.wasm.gz
```

`.wasm.gz` should be well under 500 KiB at scaffold (leaves room to grow under the 1 MiB cold-start cliff).

## Done

- All files above exist and compile.
- `cargo check --target wasm32-unknown-unknown` clean.
- `wrangler deploy --dry-run` succeeds.
- `.wasm.gz` under 500 KiB.
- `/healthz` returns 200 in `wrangler dev`.
