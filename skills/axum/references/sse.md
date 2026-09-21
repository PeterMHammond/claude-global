# SSE on workers-rs with axum

For Datastar `datastar-patch-elements`, live updates, streaming responses.

## Basic pattern

```rust
use axum::{
    extract::State,
    response::sse::{Event, KeepAlive, Sse},
};
use futures_util::stream::{Stream, StreamExt};
use std::{convert::Infallible, time::Duration};

#[worker::send]
async fn live(
    State(state): State<AppState>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    let stream = state.bus.subscribe()
        .map(|patch: String| Ok(
            Event::default()
                .event("datastar-patch-elements")
                .data(patch)
        ));
    Sse::new(stream).keep_alive(
        KeepAlive::new()
            .interval(Duration::from_secs(15))
            .text("keep-alive")
    )
}
```

## With Durable Object as the source

DO holds connections; the worker's SSE handler subscribes via the DO stub:

```rust
#[worker::send]
async fn live(
    State(state): State<AppState>,
    Path(room): Path<String>,
) -> Result<Sse<impl Stream<Item = Result<Event, Infallible>>>, AppError> {
    let stub = state.env
        .durable_object("ROOM")?
        .id_from_name(&room)?
        .get_stub()?;
    let resp = stub.fetch_with_str(&format!("https://do/subscribe/{room}")).await?;
    let stream = response_to_event_stream(resp);
    Ok(Sse::new(stream).keep_alive(KeepAlive::default()))
}
```

Where `response_to_event_stream` wraps the DO's response body into a `Stream<Item = Result<Event, _>>`. Typical implementation: read framed messages from the body and map each to an `Event`.

## Lifecycle gotchas

- **CF idle termination**: Workers terminate idle responses around ~30s. Keep-alive interval of 15s is safe.
- **DO hibernation**: SSE keeps the *client* connected, but if the source DO hibernates, the stream source disappears. Use `webSocketHibernation` correctly on the DO side, or have the client auto-reconnect.
- **`ctx.wait_until`**: cleanup work (e.g., unsubscribe from the bus) should run via `ctx.wait_until` so the Worker isn't killed before it finishes.
- **CPU budget**: SSE handlers count against CPU time while actively writing. Bursty patches are fine; tight loops will starve.
- **Backpressure**: if your source produces faster than the client reads, the `Stream` queue grows. Bound it (channel with capacity) or drop old patches.

## Datastar specifics

The `event` field must be `datastar-patch-elements` (or `datastar-patch-signals`); Datastar's client filters on event name. Data is the HTML patch payload.

```rust
Event::default()
    .event("datastar-patch-elements")
    .data(html_patch)
```

## Done

- No hand-written `Content-Type: text/event-stream` headers in handlers.
- Every SSE handler has explicit `keep_alive(...)`.
- Stream is a real `Stream` impl, not single-shot pseudo-async.
- `#[worker::send]` on SSE handlers (they always touch bindings).
- Cleanup runs via `ctx.wait_until` for any subscriptions held across the stream.
