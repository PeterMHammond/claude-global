# Tower layers — middleware for cross-cutting concerns

The single biggest reason axum is on this stack. Anything done in N handler bodies should be done in 1 layer.

## `tower-http` provides

| Concern | Layer |
|---|---|
| CORS | `tower_http::cors::CorsLayer` |
| Tracing | `tower_http::trace::TraceLayer` |
| Request ID | `tower_http::request_id::{SetRequestIdLayer, PropagateRequestIdLayer}` |
| Body size limit | `tower_http::limit::RequestBodyLimitLayer` |
| Security headers | `tower_http::set_header::SetResponseHeaderLayer` |
| Timeout | `tower_http::timeout::TimeoutLayer` |
| Panic recovery | `tower_http::catch_panic::CatchPanicLayer` |

**Skip on Workers:** `CompressionLayer` (CF edge already compresses), `Server` headers (CF sets its own).

## Custom layer template

For things `tower-http` doesn't provide (auth, payment, rate limit). Pattern: `Layer` constructs a `Service`; `Service::call` does the work and either short-circuits or calls `inner`.

```rust
use std::{convert::Infallible, task::{Context, Poll}};
use axum::{
    extract::Request,
    http::StatusCode,
    response::{IntoResponse, Response},
};
use futures_util::future::BoxFuture;
use tower::{Layer, Service};

#[derive(Clone)]
pub struct PaymentLayer {
    state: AppState,
}
impl PaymentLayer {
    pub fn new(state: AppState) -> Self { Self { state } }
}

impl<S> Layer<S> for PaymentLayer {
    type Service = PaymentMiddleware<S>;
    fn layer(&self, inner: S) -> Self::Service {
        PaymentMiddleware { inner, state: self.state.clone() }
    }
}

#[derive(Clone)]
pub struct PaymentMiddleware<S> {
    inner: S,
    state: AppState,
}

impl<S> Service<Request> for PaymentMiddleware<S>
where
    S: Service<Request, Response = Response, Error = Infallible> + Clone + Send + 'static,
    S::Future: Send + 'static,
{
    type Response = Response;
    type Error = Infallible;
    type Future = BoxFuture<'static, Result<Response, Infallible>>;

    fn poll_ready(&mut self, cx: &mut Context<'_>) -> Poll<Result<(), Self::Error>> {
        self.inner.poll_ready(cx)
    }

    fn call(&mut self, mut req: Request) -> Self::Future {
        // Clone the inner ready service before move
        let clone = self.inner.clone();
        let mut inner = std::mem::replace(&mut self.inner, clone);
        let state = self.state.clone();
        Box::pin(async move {
            // 1. Cheap check first (header presence)
            let proof = match req.headers().get("x-payment") {
                Some(h) => h.clone(),
                None => return Ok((StatusCode::PAYMENT_REQUIRED, "x402 required").into_response()),
            };
            // 2. Verify proof (DB / chain / receipt store)
            let receipt = match verify_payment(&proof, &state).await {
                Ok(r) => r,
                Err(_) => return Ok((StatusCode::PAYMENT_REQUIRED, "invalid receipt").into_response()),
            };
            // 3. Inject typed proof for downstream extractors / handlers
            req.extensions_mut().insert(receipt);
            inner.call(req).await
        })
    }
}
```

Application:
```rust
let paid_routes = Router::new()
    .route("/premium/{id}", get(premium_handler))
    .layer(PaymentLayer::new(state.clone()));

let app = Router::new()
    .merge(public_routes)
    .nest("/api", paid_routes);
```

Handler reads injected data via `Extension` or a custom extractor:
```rust
async fn premium_handler(
    Extension(receipt): Extension<Receipt>,
    Path(id): Path<String>,
) -> impl IntoResponse { ... }
```

## Layer ordering

`.layer()` applies outermost-last. With multiple layers, use `ServiceBuilder` for clarity:

```rust
use tower::ServiceBuilder;

let app = Router::new()
    .route("/", get(handler))
    .layer(
        ServiceBuilder::new()
            .layer(TraceLayer::new_for_http())          // outermost: see everything
            .layer(SetRequestIdLayer::x_request_id(...)) // tag requests
            .layer(CorsLayer::permissive())              // CORS before auth
            .layer(AuthLayer::new(state.clone()))        // auth before business
    );
```

Outer layers see the request first and the response last.

## Layer vs extractor — the rule

- Gates access to a route group → **layer**.
- Just typed parsing for one handler → **extractor**.
- Both (cheap gate + typed proof) → **layer injects, extractor reads from extensions**.

## Common layers worth writing

- **AuthLayer** — verify session/JWT, inject `User` into extensions.
- **PaymentLayer** — verify x402 header, inject `Receipt`.
- **RateLimitLayer** — DO-backed bucket per IP/user; reject with 429.
- **TenantLayer** — pull tenant from host/path; inject into extensions.
- **CsrfLayer** — verify token on mutating methods.

## Done

- Auth, rate limit, payment, CORS, tracing, request-id all live in `.layer(...)` calls.
- Handler bodies contain only business logic.
- Route groupings reflect security tiers (public / authed / paid).
