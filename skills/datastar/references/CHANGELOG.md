# datastar skill changelog

## 2026-10-07 — v1.0.4 refresh

Verified against `~/Projects/github/datastar-pro` at `8f64418` (v1.0.4, Rocket beta.2), the 41 example-page scrapes, raw data-star.dev HTML, Cloudflare docs, and a wasm32 scratch build. Method: five parallel verifiers (core source, Pro source, Rust build, docs, Rocket runtime), each writing a cited report; corrections applied in place; nothing removed that the source did not contradict.

### New files
- `references/datastar-guide.md` — the core reference, every claim tagged `[src file:line]`, `[docs page]`, `[ex slug]`, `[adr]`, `[rs]`, `[cf]`, `[build]`.
- `references/datastar-pro-addendum.md` — 10 Pro attributes, 3 actions, Inspector, bundles/aliasing, from plugin source; 19 corrections to the old Pro sections; runtime-verified bugs.
- `references/CHANGELOG.md` — this file.

### SKILL.md corrections (core)
- Versions: core/Pro v1.0.4, Rocket beta.2 (was beta.11+/1.0.0/beta.1). CDN pin `@v1.0.4`.
- `morph` is not a patch mode; `outer` (default) and `inner` morph, `replace` is the hard swap. Modes table rebuilt from patchElements.ts:18-27 with selector/id rules and error names.
- `remove` omits `data: elements`; the `<x></x>` placeholder advice is gone.
- `data-cloak` does not exist in v1.0.4 (not in `bundles/datastar.ts`, not in the reference). FOUC guard is `data-show` + `style="display:none"`.
- 21 attributes = 17 plugins + 4 engine/morph attributes. `__case` ignored by `data-attr`/`data-style`. `__` ban is key-form only. `data-preserve-attr` is read from the incoming element. `data-on-interval` takes `__viewtransition`. Timing tags are per modifier (debounce `.leading/.notrailing`, throttle `.noleading/.trailing`).
- 9 core actions: `@query` added (QUERY method, signals in body).
- `contentType: 'form'` is urlencoded unless the form has `enctype="multipart/form-data"`, and sends **no** signals. `selector` default `null`. `requestCancellation: 'cleanup'` also keeps the same-method+URL abort; the cancel key is method + URL, not the element.
- `datastar-fetch` dispatches on `document` with `detail.el`, not on the element.
- Retry/visibility rules written from fetch.ts: network throw retries even under `'never'`; finished streams do not reconnect without `'always'`; `openWhenHidden` false for `@get` only.
- Source-read hazard recorded: `text/javascript` responses and failed form validation never resolve the fetch promise, so `data-indicator` sticks.
- Patch-signals: arrays replace wholesale; `onlyIfMissing` ignores `null`.
- Scripts morphed onto an existing `<script>` under `outer`/`inner` are not re-run.
- Response content types table: `datastar-namespace` header, 204, unknown types.
- Worker-rs section rewritten around craft-core-floor (`datastar.rs`, `sse_event.rs`, `sse_bridge.rs`) with the compiled 12-line `sse()` helper, the worker 0.8.6 `Response::from_stream` signature and a compiled mpsc handler, the `datastar` 0.4.1 crate's real API (`.into_datastar_event().to_string()`), per-event-flushed gzip, 25 s keepalive, `retry: 1000`, script-free `execute_script`/`redirect`.
- `X-Accel-Buffering: no` removed as a recommendation: Cloudflare strips it (documented "Removed response headers"). Follow-up: delete it from `carm/src/cf_datastar.rs` and `craft-core-floor/src/datastar.rs`.
- "`async_stream!` needs tokio" removed; `async-stream` builds on wasm32 and craft uses it.
- Source map: Rocket moved from `library/src/pro/rocket/` to `library/src/rocket/`; free engine/plugin paths, bundles, craft SSE paths and the Rust SDK added. Examples catalog rows corrected (form_data, inline_validation keydown, edit_row `@patch`, title_update, progress_bar, bad_apple, delete_row).
- Security: CSP nonce mode (`<html data-nonce>`), Trusted Types policy `datastar`, aliased `data-star-nonce`.

### SKILL.md corrections (Pro), see addendum C1-C19
- Inspector build command (`--loader:.html=text`, `webcomponents/tsconfig.json`); only `max-events-visible` is an attribute; events tab shows `datastar-*` SSE events only; no Pro bundle needed; persisted-key scan bug.
- `data-animate` defaults and the three easings that throw; `data-match-media` value is raw text; `data-on-resize` takes `__delay`; `data-persist` loads unfiltered; `data-query-string` popstate only with `__history` and rewrites the whole query string; `data-replace-url` fires on dependency change, not "every morph"; `data-scroll-into-view` tabIndex rule and runs once; `data-view-transition` is a silent no-op when unsupported.
- `@clipboard` returns `undefined`; `@intl` `options` required for `relativeTime`/`displayNames` and `unit` must be an array.
- Bundler: aliasing is the esbuild `--define` value, aliased sources are identical; bundle matrix; sizes. Stellar CSS: nothing in the checkout.

### SKILL.md corrections (Rocket), see E-rocket D1-D10
- Rocket ships in the free `datastar-rocket.js` (MIT repo) and in `datastar-pro.js`; source is in the commercial repo; example pages still badge it Pro. Heading no longer says "Pro Custom Elements".
- Default `mode` is `'open'` shadow DOM. `props` is a plain object: every `effect(() => props.x)` pattern became `observeProps(fn, 'x')` (QR, star-field, flow-node, stringify-guard rationale). `observeProps` callback is `(props, changes)`.
- `actions.*` reaches only the global registry; local actions via `@name()` in templates. `__root` applies only to signal-name attributes. `data-key` on `data-for` does not exist in beta.2. No light-DOM style scoping or `:host` rewrite. `emit` returns `void`; `refs` only in `onFirstRender`.
- Verbatim `RocketDefinition` and `SetupContext` refreshed from runtime.ts:203-221 / 107-143; codec table (getters without parens); all stale `runtime.ts`/`patchElements.ts` line refs updated.
- `<loadout-canvas>` snippet fixed to omit `render` (the skill's own light-DOM clone trap).
- beta.2 surface added: DOM-based interpolation, primitive render values, `datastar-scope-children`, `createCodec`, `publishRocketManifests`, `host.rocketSignalPath`, `$$('name', init)`, multi-name `emit`, `id_2` dedupe.

### Review pass
A sixth agent with no authorship reviewed the four files: 26 random cites opened and confirmed, 13 cross-document consistency points agree, all nine lesson sections intact. Fixed from its list: six cites whose line numbers exceeded the file (attr/style, onInterval, timing, text, errors, csp), two broken table rows, eight over-long or wrapped code comments, one stale "RC.8+ (current)" anchor. A cite gate (every `file.ts:line` ≤ file length) now passes.

### Preserved unchanged (confirmed against source)
Mental model, signal reactivity gotchas (ownKeys/get traps), ES-module URL identity incident, `data-on:focus` + autofill CPU trap, self-removing script pattern (CARM), WebSocket + SSE split architecture, StateTree integration, Loadout architectural rule, Flow deep dive patterns, SVG `data-for` trap, light-DOM clone trap and its five fixes.

### Still unverified
- Rocket license wording ("Free Launch" essay not re-fetched; example pages say Pro).
- The indicator hang on `text/javascript` / failed form validation (source-read, not run in a browser).
- Askama payload end-to-end against a browser (verified against a Rust port of the client parser and the `datastar` crate's output, 27 tests green).
- Published alias value `data-star-*` (docs claim; the checkout only shows the `--define` mechanism).
