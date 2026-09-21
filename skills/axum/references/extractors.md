# Custom extractors — `FromRequest` / `FromRequestParts`

axum's typed-input half. When the same parsing/validation appears in 3+ handlers, lift it.

## When to write one

- Authenticated user from session cookie / JWT
- Validated payment proof (e.g., x402 receipt)
- Datastar signals from query/body
- API key + tier lookup
- Typed pagination with defaults
- CSRF token verification
- Webhook signature verification (Stripe, GitHub, etc.)

## Pattern A — from request parts (no body)

`FromRequestParts` runs without consuming the body. Chain as many as you want per handler.

```rust
use axum::{
    async_trait,
    extract::FromRequestParts,
    http::request::Parts,
};

pub struct AuthedUser {
    pub id: u64,
    pub email: String,
}

#[async_trait]
impl<S: Send + Sync> FromRequestParts<S> for AuthedUser {
    type Rejection = AppError;
    async fn from_request_parts(parts: &mut Parts, _state: &S) 
        -> Result<Self, Self::Rejection> 
    {
        let token = parts.headers
            .get("authorization")
            .and_then(|h| h.to_str().ok())
            .and_then(|h| h.strip_prefix("Bearer "))
            .ok_or(AppError::Unauthorized)?;
        verify_token(token).await.map_err(|_| AppError::Unauthorized)
    }
}
```

Handler usage:
```rust
async fn protected(user: AuthedUser) -> impl IntoResponse {
    format!("hello {}", user.email)
}
```

## Pattern B — with access to state

When the extractor needs `State` (e.g., DB lookup), parameterize on the concrete state type:

```rust
#[async_trait]
impl FromRequestParts<AppState> for AuthedUser {
    type Rejection = AppError;
    async fn from_request_parts(parts: &mut Parts, state: &AppState) 
        -> Result<Self, Self::Rejection> 
    {
        let token = parts.headers.get("authorization") /* ... */;
        state.users.lookup(token).await.map_err(|_| AppError::Unauthorized)
    }
}
```

The extractor is now locked to `AppState` — that's the tradeoff for state access.

## Pattern C — consuming the body

`FromRequest` consumes the body. Only one body extractor per handler signature.

```rust
use axum::{extract::{FromRequest, Request}, Json};
use serde::de::DeserializeOwned;
use validator::Validate;

pub struct ValidatedJson<T>(pub T);

#[async_trait]
impl<T, S> FromRequest<S> for ValidatedJson<T>
where
    T: DeserializeOwned + Validate,
    S: Send + Sync,
{
    type Rejection = AppError;
    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        let Json(value) = Json::<T>::from_request(req, state).await
            .map_err(|e| AppError::BadRequest(e.to_string()))?;
        value.validate().map_err(|e| AppError::BadRequest(e.to_string()))?;
        Ok(ValidatedJson(value))
    }
}
```

## Pattern D — payment receipt (extractor-as-policy)

For protocols like x402, the extractor can both verify and inject the proof. Pairs well with a tower layer that does the cheap header-check; the extractor does the typed deserialization.

```rust
pub struct PaidRequest {
    pub receipt: PaymentReceipt,
}

#[async_trait]
impl FromRequestParts<AppState> for PaidRequest {
    type Rejection = AppError;
    async fn from_request_parts(parts: &mut Parts, state: &AppState) 
        -> Result<Self, Self::Rejection> 
    {
        // Layer already verified payment header; here we deserialize the proof
        let receipt = parts.extensions
            .get::<PaymentReceipt>()
            .cloned()
            .ok_or(AppError::PaymentRequired)?;
        Ok(PaidRequest { receipt })
    }
}
```

Handler:
```rust
async fn premium_endpoint(paid: PaidRequest) -> impl IntoResponse {
    // paid.receipt is typed; gating happened in the layer
}
```

## Layer vs extractor

- **Layer**: gates a group of routes, runs before handler resolution, can short-circuit response. Use for access control affecting many routes.
- **Extractor**: per-handler, runs as part of signature resolution. Use for typed parsing and per-handler validation.
- **Combined**: layer does the cheap check + injects data into request extensions; extractor pulls typed data out. Best of both.

## Pitfalls

- `FromRequest` consumes the body — only one per handler.
- `FromRequestParts` doesn't touch the body — chain freely.
- State-aware extractors lock the handler to that concrete state type.
- Extractor `Rejection` types implement `IntoResponse` — use your `AppError` so rejections produce the same response shape as handler errors.

## Done

- No `.headers().get(...)` for recurring patterns in handler bodies.
- No `req.text().await?` + `serde_json::from_str` for typed input.
- Auth, payment, validation logic lives in extractors (or layer+extractor pairs).
