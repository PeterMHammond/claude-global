# axum inside a Durable Object's `fetch`

DOs receive their own `fetch` events. Treat them as mini-workers with their own axum routers.

## Pattern

```rust
use worker::*;
use axum::{Router, routing::{get, post}};
use tower_service::Service;

#[durable_object]
pub struct Room {
    state: State,
    env: Env,
    router: Option<Router>,
}

impl DurableObject for Room {
    fn new(state: State, env: Env) -> Self {
        Self { state, env, router: None }
    }

    async fn fetch(&mut self, req: HttpRequest) 
        -> Result<http::Response<axum::body::Body>> 
    {
        let router = self.router.get_or_insert_with(|| {
            build_router(self.state.clone(), self.env.clone())
        });
        Ok(router.clone().call(req).await?)
    }
}

#[derive(Clone)]
struct RoomState {
    state: send::SendWrapper<State>,
    env: send::SendWrapper<Env>,
}

fn build_router(state: State, env: Env) -> Router {
    Router::new()
        .route("/subscribe/{room}", get(subscribe))
        .route("/publish/{room}", post(publish))
        .route("/admin/stats", get(stats))
        .with_state(RoomState {
            state: send::SendWrapper::new(state),
            env: send::SendWrapper::new(env),
        })
}

#[worker::send]
async fn subscribe(
    State(s): State<RoomState>,
    Path(room): Path<String>,
) -> Result<Response, AppError> { ... }
```

## Why route inside a DO

- Same audit checklist applies inside the DO: extractors, IntoResponse, error type, layers.
- Multi-endpoint DOs (subscribe, publish, admin, debug) become trivial.
- Admin/observability endpoints exposed cleanly per DO instance.

## Pitfalls

- **DO state is `!Send`** — wrap with `SendWrapper` like any other binding.
- **Cache the router** on `self` — rebuilding per request is wasted work. The `Option::get_or_insert_with` pattern above runs once per DO instance lifetime.
- **Cloning the router is cheap** — axum routers are `Clone` via internal `Arc`s; the `.clone().call(req)` is fine.
- **Don't share routers between DO instances** — each DO is isolated; the closure captures that instance's state.
- **DO `fetch` only sees URLs of the form `https://fake-host/path`** — the host is meaningless. Route on path only.

## Layers inside DOs

DO routers can have their own tower layers (e.g., admin-only auth on `/admin/*` routes, request tracing, panic recovery). Same patterns as the top-level worker router.

## Done

- DO `fetch` dispatches via `axum::Router`, not hand-written URL matching.
- Router cached on `self` (`Option<Router>` + `get_or_insert_with`).
- DO state and env passed via `SendWrapper`.
- Handler signatures use extractors and return `Result<T, AppError>` or `impl IntoResponse`.
