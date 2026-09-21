---
name: axum
description: Master axum on Cloudflare workers-rs — audit, refactor, optimize, scaffold. Use this skill whenever the user wants to audit, review, refactor, refine, optimize, iterate on, or master axum usage in a workers-rs project; wants to migrate from worker::Router to axum; asks about IntoResponse for Askama templates; wants tower middleware (CORS, auth, tracing, rate limiting, payment protocols like x402); wonders whether something should be a tower layer or a custom extractor; wants to add SSE, custom FromRequest extractors, or axum routers inside Durable Objects; wants to scaffold a new workers-rs+axum project; or wants to run a continuous refinement loop until the project is fully optimized. Trigger on phrases like "audit my worker", "refine the worker", "optimize axum", "iterate until done", "/axum", "/axum loop", "are we using axum properly", "should this be a tower layer", "IntoResponse for...", "#[worker::send]", "scaffold a workers-rs project", "migrate from worker::Router", "axum inside a Durable Object", or any request to improve handler ergonomics, middleware composition, binding state management, or binary size in a workers-rs project.
---

# axum on workers-rs — master skill

Two modes. Both share the same checklist and reference files.

## Modes

- **AUDIT** — survey → report. No code changes. Triggered by "audit", "review", general questions.
- **REFINE** — loop: propose → approve → apply → verify → re-survey. Exit on convergence or user stop. Triggered by "refine", "optimize", "iterate", "loop", "/axum loop".

For new projects ("scaffold", "new worker"): skip audit, use `references/scaffold.md`.
For greenfield additions to an existing worker ("add x402", "add auth"): skip full audit, use the relevant reference directly.

## Survey

```bash
rg -A2 '^worker|^axum|^tower' Cargo.toml
rg -l '#\[event\(fetch\)\]' --type rust
rg 'worker::Router|Router::new\(\)|\.get_async\(|\.post_async\(' --type rust
rg 'async fn.*-> (Result<Response>|impl IntoResponse|Response<)' --type rust
rg 'use askama|#\[derive\(Template\)\]|\.render\(\)|Response::from_html' --type rust
rg 'text/event-stream|Sse::new|datastar-patch' --type rust
rg 'env\.(kv|bucket|durable_object|d1|queue|secret_store)\(' --type rust
rg '#\[worker::send\]|SendWrapper|SendFuture' --type rust
rg '#\[durable_object\]|impl DurableObject' --type rust
rg '\.map_err\(.*worker::Error|Result<Response>' --type rust
rg 'req\.url\(\)\?\.query_pairs|req\.text\(\)\.await|req\.headers\(\)\.get' --type rust
```

## Checklist — priority order, definition-of-done, reference

Severity rubric: CRITICAL blocks others; HIGH high-leverage refactor; MEDIUM cleanup; LOW polish.

1. **`http` feature on `worker`** — CRITICAL prerequisite.
   - Detect: `worker = "..."` lacking `features = ["http"]`; fetch returns `Result<Response>` not `Result<http::Response<...>>`.
   - Done: feature enabled, fetch signature uses `HttpRequest` and returns `Result<http::Response<axum::body::Body>>`.

2. **`axum::Router` over `worker::Router`** — HIGH.
   - Detect: `worker::Router`, `.get_async`, `.post_async`, `.run(req, env)` in a project with >1 route or middleware needs.
   - Done: all routes on `axum::Router`; fetch dispatches via `router.call(req).await`.
   - Exception: single-endpoint webhook/cron — note and skip.
   - → `references/migration.md`

3. **`IntoResponse` for templates** — HIGH.
   - Detect: `.render()` or `Response::from_html` in >1 handler file.
   - Done: `HtmlTemplate<T: Template>` impl defined once; all template handlers return it.
   - → `references/responses.md`

4. **`IntoResponse` for app errors** — HIGH.
   - Detect: `.map_err(worker::Error::RustError(...))` in handlers; `Result<Response>` returns; manual error response building.
   - Done: `AppError` enum with `IntoResponse` impl; handlers return `Result<T, AppError>`.
   - → `references/responses.md`

5. **SSE via `axum::response::sse::Sse`** — HIGH (when SSE present).
   - Detect: hand-written `text/event-stream` headers/body; missing keep-alive.
   - Done: handler returns `Sse<impl Stream>`; keep-alive configured; DO lifecycle correct.
   - → `references/sse.md`

6. **State for non-`Send` bindings** — HIGH.
   - Detect: per-handler `let kv = env.kv(...)`; `Arc<Mutex<Env>>`; `with_state(env)` without wrapping.
   - Done: bindings wrapped in `SendWrapper` inside state struct, or injected via `.layer(Extension(SendWrapper::new(...)))`.

7. **`#[worker::send]` where required** — MEDIUM (compile-blocking when missing).
   - Detect: compile errors "future cannot be sent"; handlers calling `env.kv/bucket/d1/...` without the attribute.
   - Done: attribute on every binding-touching async handler.

8. **Tower layers for cross-cutting concerns** — HIGH (highest leverage item).
   - Detect: auth, payment (x402), rate-limit, tracing, CORS, request-id logic in handler bodies.
   - Done: each concern is a `tower::Layer` applied via `.layer(...)` on router/sub-router; handlers contain only business logic.
   - → `references/tower-layers.md`

9. **Extractors over manual parsing** — MEDIUM.
   - Detect: `req.url()?.query_pairs()`, `req.text().await? + serde_json::from_str`, `req.headers().get(...)` in handlers.
   - Done: `Path`, `Query`, `Json`, `TypedHeader`, custom `FromRequest` cover all handler inputs.
   - → `references/extractors.md`

10. **Binary size hygiene** — MEDIUM (HIGH if over 1 MiB gzipped).
    - Detect: `default-features = true` on axum; `tower-http = { features = ["full"] }`; release profile not size-optimized; `.wasm.gz` over 1 MiB.
    - Done: features explicit-minimal; release profile size-optimized; `.wasm.gz` under cold-start cliff.
    - → `references/scaffold.md`

11. **Durable Objects expose axum routers** — MEDIUM (when DOs present).
    - Detect: DO `fetch` method with hand-written URL matching.
    - Done: DO `fetch` dispatches via cached `axum::Router`.
    - → `references/durable-objects.md`

12. **Shared-crate centralization** — LOW (HIGH in a multi-worker monorepo).
    - Detect: same `HtmlTemplate`, `AppError`, baseline layers duplicated across workers.
    - Done: one import provides baseline plumbing.
    - → `references/shared-crate.md`

## REFINE loop

```
loop:
  survey                                            # rg block above
  findings = checklist(survey)
  if findings.filter(CRITICAL|HIGH).empty():
    report "converged"; exit
  next = findings.sort_by(priority).first()
  propose(next)                                     # severity, file:line, before → after (minimal), expected verify result
  await explicit user approval ("go" / "yes" / "apply")
  apply(next)
  verify:
    cargo check --target wasm32-unknown-unknown
    cargo test                                      # if tests exist
    check .wasm.gz size delta                       # via wrangler deploy --dry-run
  if verify fails:
    revert; report failure; exit
  continue
```

**Loop rules:**
- Never apply without explicit approval.
- Never skip verification.
- Never continue past a verification failure — revert and surface to user.
- "stop" / "pause" exits cleanly mid-loop.
- One change per iteration. Atomicity matters for verify + revert.

## Output

**AUDIT mode** — prioritized findings list. For each: severity, `file:line`, current → improved snippet (minimal delta), one-sentence why.

**REFINE mode** — one proposal per turn. Severity, `file:line`, before, after, expected verification result. Wait for go.

## Reference index

| Topic | File |
|---|---|
| Incremental migration from `worker::Router` | `references/migration.md` |
| `IntoResponse` for templates + app errors | `references/responses.md` |
| Custom `FromRequest` extractors | `references/extractors.md` |
| Tower middleware layers | `references/tower-layers.md` |
| Server-Sent Events | `references/sse.md` |
| axum inside Durable Objects | `references/durable-objects.md` |
| New project scaffold (Cargo.toml, profile, entrypoint) | `references/scaffold.md` |
| Shared crate for multi-worker monorepos | `references/shared-crate.md` |
