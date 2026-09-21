# Migrating `worker::Router` → `axum::Router`

Incremental. No big-bang rewrites.

## Steps

1. **Enable `http` feature** on `worker` crate. Update `Cargo.toml`:
   ```toml
   worker = { version = "0.5", features = ["http"] }
   ```

2. **Update fetch signature:**
   ```rust
   #[event(fetch)]
   async fn fetch(
       req: HttpRequest,
       env: Env,
       _ctx: Context,
   ) -> Result<http::Response<axum::body::Body>> { ... }
   ```

3. **Add minimal axum deps:**
   ```toml
   axum = { version = "0.8", default-features = false, features = ["http1", "json", "matched-path", "tokio", "query"] }
   tower = "0.5"
   tower-service = "0.3"
   ```

4. **Build the axum router with a fallback to the legacy `worker::Router`:**
   ```rust
   #[event(fetch)]
   async fn fetch(req: HttpRequest, env: Env, ctx: Context) 
       -> Result<http::Response<axum::body::Body>> 
   {
       let app = axum::Router::new()
           // Migrated routes go here, one at a time
           .route("/healthz", get(|| async { "ok" }))
           .with_state(AppState::new(env.clone()));
       Ok(app.call(req).await?)
   }
   ```

5. **Move handlers one at a time** from `worker::Router` to `axum::Router`. Each migration:
   - Replace `(Request, RouteContext)` signature with axum extractors.
   - Replace `Response::ok(...)` / `Response::from_html(...)` with `IntoResponse` return.
   - Add `#[worker::send]` if handler holds bindings across `.await`.
   - Compile + smoke test the path before moving the next.

6. **Remove `worker::Router`** when its route list is empty.

## Why not big-bang

A 30-handler rewrite is uncompilable for hours and untestable until the very end. Incremental keeps green at every commit.

## Done

- `worker::Router` not referenced anywhere in the crate.
- All routes on `axum::Router`.
- Fetch returns `Result<http::Response<axum::body::Body>>`.
- All previous handler behavior preserved (verify with smoke tests).
