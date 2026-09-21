# IntoResponse — templates and errors

Define once, use everywhere.

## Askama template wrapper

```rust
use askama::Template;
use axum::{
    http::{header, StatusCode},
    response::{IntoResponse, Response},
};

pub struct HtmlTemplate<T>(pub T);

impl<T: Template> IntoResponse for HtmlTemplate<T> {
    fn into_response(self) -> Response {
        match self.0.render() {
            Ok(html) => (
                [(header::CONTENT_TYPE, "text/html; charset=utf-8")],
                html,
            ).into_response(),
            Err(err) => (
                StatusCode::INTERNAL_SERVER_ERROR,
                format!("Template render failed: {err}"),
            ).into_response(),
        }
    }
}
```

Handler usage:
```rust
async fn home(State(s): State<AppState>) -> impl IntoResponse {
    HtmlTemplate(HomeTemplate { user: s.user.clone() })
}
```

## App-wide error type

```rust
use axum::{http::StatusCode, response::{IntoResponse, Response}};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum AppError {
    #[error("not found")]
    NotFound,
    #[error("unauthorized")]
    Unauthorized,
    #[error("forbidden")]
    Forbidden,
    #[error("payment required")]
    PaymentRequired,
    #[error("bad request: {0}")]
    BadRequest(String),
    #[error("conflict: {0}")]
    Conflict(String),
    #[error(transparent)]
    Worker(#[from] worker::Error),
    #[error(transparent)]
    Other(#[from] anyhow::Error),
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let status = match &self {
            Self::NotFound => StatusCode::NOT_FOUND,
            Self::Unauthorized => StatusCode::UNAUTHORIZED,
            Self::Forbidden => StatusCode::FORBIDDEN,
            Self::PaymentRequired => StatusCode::PAYMENT_REQUIRED,
            Self::BadRequest(_) => StatusCode::BAD_REQUEST,
            Self::Conflict(_) => StatusCode::CONFLICT,
            Self::Worker(_) | Self::Other(_) => StatusCode::INTERNAL_SERVER_ERROR,
        };
        // Log full detail server-side for 5xx; user gets short message
        if status.is_server_error() {
            worker::console_error!("{self:?}");
        }
        (status, self.to_string()).into_response()
    }
}
```

Handler usage:
```rust
async fn get_thing(
    Path(id): Path<u64>,
    State(s): State<AppState>,
) -> Result<Json<Thing>, AppError> {
    let thing = s.repo.find(id).await?
        .ok_or(AppError::NotFound)?;
    Ok(Json(thing))
}
```

## Why these two together

`HtmlTemplate` + `AppError` cover ~90% of handler return types. Once both exist, handlers become signature-driven: extractors in, typed return out, framework handles the HTTP plumbing.

## Done

- No `.render()` calls in handler files.
- No `.map_err(worker::Error::RustError(...))` in handlers.
- Handlers return `Result<T, AppError>` or `impl IntoResponse`.
- Server errors logged with full detail; client receives short message.
