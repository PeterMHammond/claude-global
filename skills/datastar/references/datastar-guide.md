# Datastar: How to Use It Correctly

Reference for building on Datastar with Cloudflare Workers (worker-rs), Askama, and SSE.
Compiled 2026-10-07.

## 0. Provenance and confidence

Every claim below comes from one of these sources. Where a claim rests on only one, it says so.

| Tag | Source | Confidence |
|---|---|---|
| **[src]** | Datastar library source as shipped in the local Pro checkout `~/Projects/github/datastar-pro` at `8f64418` (**v1.0.4**, 2026-09-21): `library/src/plugins/actions/fetch.ts`, `watchers/patchElements.ts`, `watchers/patchSignals.ts`, `engine/{engine,signals,errors,csp}.ts`, `attributes/*.ts`, `utils/*.ts`. Every [src] claim below was re-checked against this tree on 2026-10-07; `file:line` cites refer to it | Highest: this is what runs |
| **[adr]** | `sdk/ADR.md` in the same repo: the SSE wire-format and SDK specification | Highest |
| **[rs]** | Rust SDK, `starfederation/datastar-rust` v0.4.1 (commit `a50d81f`): event serialization and tests | Highest |
| **[docs]** | data-star.dev pages fetched in full: Getting Started, Attributes reference, Security, How-to "bind keydown", Active Search example, Essay "Free Launch" | High |
| **[ex]** | Local full-page scrapes of all 41 data-star.dev example pages, `~/Projects/EveryGoodWork/temp/datastar-examples/<slug>.md`; code blocks verbatim | High |
| **[cf]** | Cloudflare developer docs (http-headers reference, Workers streams) | High |
| **[build]** | Compiled and tested in this session: scratch worker-rs crate for `wasm32-unknown-unknown`, `datastar` 0.4.1 tests, craft-core-floor tests | Highest |

On 2026-10-07 every page previously tagged `docs~` (paraphrased) was re-fetched as raw HTML and checked; those tags are now `docs`, with the slug named where it matters.

Version: **v1.0.4** throughout (docs CDN pin and the local checkout agree). Datastar Pro is documented from the plugin source in `references/datastar-pro-addendum.md`; section 11 here is only the index.

Syntax is the v1 colon form (`data-on:click`, `data-bind:foo`, `data-signals:foo`). The older `data-on-click` / `data-signals-foo` forms are not used.

---

## 1. Mental model

1. **The backend is the source of truth.** The server renders HTML and the browser morphs it into the DOM. State lives on the server.
2. **HTML patches are primary; signals are the exception.** The Tao: "only use signals for user interactions (e.g. toggling element visibility) and for sending new state to the backend"; "favor fetching current state from the backend rather than pre-loading and assuming frontend state is current." (docs: the_tao_of_datastar)
3. **Morph is trusted.** "Morphing ensures that only modified parts of the DOM are updated, preserving state"; send large chunks, "all the way up to the `html` tag" (fat morph). (docs)
4. **One long-lived read stream, short write requests (CQRS).** `<div id="main" data-init="@get('/cqrs_endpoint')"><button data-on:click="@post('/do_something')">…</button></div>`. "A powerful pattern that makes real-time collaboration simple." (docs, verbatim)
5. **Prefer full-state ("fat morph") updates to incremental ones.** "Send the complete desired state of the main content area with each update instead of incremental changes like append, which are much more vulnerable to interruptions." (docs: how_tos/prevent_sse_connections_closing)
6. **No optimistic success.** "Rather than deceive the user, use loading indicators … and only confirm success from the backend." Under CQRS, show the indicator manually (`el.classList.add('loading'); @post(...)`) and let the backend's DOM update hide it. (docs)
7. **Let the browser do navigation.** "Each page is a resource. Use anchor tags and let the browser do what it is good at." (docs)
8. **Start with the defaults.** "The default configuration options are the recommended settings for the majority of applications." Compression: "ratios of 200:1 are not uncommon when compressing streams using Brotli." (docs)

Datastar is two things: (a) the backend patches the DOM and signal store by sending events, and (b) `data-*` attributes add reactivity in the frontend. No npm packages or dependencies. (docs)

---

## 2. Install

```html
<script type="module" src="/static/datastar.js"></script>
```

- CDN form: `https://cdn.jsdelivr.net/gh/starfederation/datastar@v1.0.4/bundles/datastar.js`; ESM import form `import 'https://cdn.jsdelivr.net/gh/starfederation/datastar@v1.0.4/bundles/datastar.js'` (docs). Self-hosting is recommended (docs).
- Rocket (web components) needs the separate `datastar-rocket.js` bundle, which already includes Datastar. Use it *instead of* `datastar.js`; a `datastar-rocket.d.ts` ships for TypeScript. (docs) Pro licensees use `datastar-pro.js`, which contains core + Pro plugins + Rocket (src bundles/datastar-pro.ts).
- Keep the module URL bare and stable: a `?v=` cache-buster on the `<script>` plus bare-path `import`s in components creates two engine instances (see SKILL.md "ES Module URL Identity").
- An aliased bundle (`datastar-aliased.js`) renames attributes to `data-star-*` for conflicts with legacy libraries; use `data-ignore` first if you can. (docs)
- Editor support: VS Code extension and IntelliJ plugin give autocomplete and diagnostics. (docs)

---

## 3. Attributes

All attributes are `data-*`. Form: `data-<plugin>[:<key>][__<modifier>[.<tag>]...]="<expression>"`. Parsing: `rawKey.split('__')`, then `name:key`, modifiers split on `.` **[src engine.ts]**.

### 3.1 Key vs value: two ways to name things
For attributes that name a signal (`bind`, `indicator`, `ref`, `computed`, `signals`), the name can be in the key or the value. Useful depending on your templating language. (docs)

```html
<input data-bind:foo />   <input data-bind="foo" />
```
`data-bind` and `data-indicator` are **exclusive**: provide the key *or* the value, not both and not neither **[src]**. `data-on` requires a key and value **[src]**.

### 3.2 Casing rules
- Attributes that **define signals** (`bind`, `signals`, `computed`, `indicator`, `ref`, ...): key is converted to **camelCase**. `data-signals:my-signal` defines `$mySignal`. (docs)
- Everything else (`class`, `attr`, `on`, `style`): key is **kebab-case** by default. `data-class:text-blue-700` toggles that class; `data-on:rocket-launched` listens for `rocket-launched`. (docs)
- Override with `__case.camel | .kebab | .snake | .pascal`. To listen for an event named `widgetLoaded`: `data-on:widget-loaded__case.camel`. (docs) `__case` is honored by `signals bind computed indicator ref class on`; **`data-attr` and `data-style` ignore it** (their key form never calls `modifyCasing`) **[src attr.ts:13-33, style.ts:16-38; `grep modifyCasing plugins/attributes/*.ts`]**.
- Signal names **cannot contain `__` in the key form** (`data-signals:a__b` splits on the modifier delimiter). In expressions (`$a__b`) and the value form (`data-bind="a__b"`) they work. **[src engine.ts:199,449]**

### 3.3 Reference table (open-source)

| Attribute | What it does | Notes |
|---|---|---|
| `data-signals` | Patches (adds/updates/removes) signals | `:foo`, `:foo.bar` (nested), or object form. `null`/`undefined` removes. `__ifmissing` only sets if absent (defaults). `__case`. "Values defined later in the DOM tree override those defined earlier." (docs) |
| `data-bind` | Two-way bind signal ↔ input/select/textarea/custom element | See 3.4. (docs, src) |
| `data-text` | Element text = expression | (docs) |
| `data-show` | Show/hide by truthiness | Add `style="display:none"` to avoid flicker before init. (docs) |
| `data-class` | Toggle classes | `data-class:foo="expr"` or `data-class="{a: $x, 'b-c': $y}"`. `__case` (kebab default). (docs) |
| `data-attr` | Set any attribute | `data-attr:aria-label="$foo"` or object form. (docs) |
| `data-style` | Set inline styles | `$cond && 'value'` restores the original inline value when falsy. Object form too. (docs) |
| `data-computed` | Read-only derived signal | **No side effects** in the expression; use `data-effect` for actions. Object form takes arrow fns. (docs) |
| `data-effect` | Run expression on load and whenever its signals change | Side effects live here. (docs) |
| `data-init` | Run expression when the attribute is initialized | On page load, when the element is patched in, or when the attribute value changes. `__delay.500ms`, `__viewtransition`. (docs) |
| `data-on` | Event listener | `evt` is available. See 3.5. (docs, src) |
| `data-on-intersect` | Run when element intersects viewport | `__once __exit __half __full __threshold.25 __delay __debounce __throttle __viewtransition`. (docs) |
| `data-on-interval` | Run on a timer (default 1s) | `__duration.500ms` (+ `.leading`), `__viewtransition`. No debounce/throttle/delay. (docs, src onInterval.ts:25-35) |
| `data-on-signal-patch` | Run when any signal is patched | `patch` variable available. `__delay __debounce __throttle`. (docs) |
| `data-on-signal-patch-filter` | `{include: /re/, exclude: /re/}` filter for the above | (docs) |
| `data-indicator` | Signal true while a request from *this element* is in flight | Create it **before** a `data-init` fetch on the same element (attribute order matters). (docs, src) |
| `data-ref` | Signal holding the element | `$foo.tagName`. (docs) |
| `data-json-signals` | Dump signals as JSON text (debugging) | `{include,exclude}` filters, `__terse`. (docs) |
| `data-ignore` | Datastar skips this element and descendants | `__self` ignores only the element. Use for third-party libs / unescapable input. (docs) |
| `data-ignore-morph` | Morph skips this element and children | See section 7. (docs, src) |
| `data-preserve-attr` | Keep the listed attributes' current values across a morph | Space-separated: `data-preserve-attr="open class"`. Read from the **incoming** element, so the server must send it on every patch or the attributes sync/remove like any other. (docs, src patchElements.ts:606-617) |

### 3.4 `data-bind` details
- Signal is created if missing; initial value comes from the element unless the signal was pre-defined. (docs)
- **Type is preserved from the pre-defined signal**: pre-defining `data-signals:foo-bar="0"` makes a `<select>` store the number `10`, not `"10"`. A pre-defined **array** collects multiple checkboxes. (docs)
- `type=file` → signal is `[{name, contents (base64), mime}]`; no `<form>` needed. For true multipart uploads use a form with `enctype="multipart/form-data"` and `contentType: 'form'`. (docs)
- Modifiers: `__prop.<prop>` binds a specific property, `__event.<evt>.<evt>` chooses which events sync back to the signal. Generic custom elements default to `value`/`change`. (docs)
- Radio: if no signal exists, binds adopt the currently checked radio's value **[src]**. Radios without `name` get one from the signal name **[src]**. Checkbox: the type follows the pre-defined signal; with no signal, `value="on"` binds a boolean and a custom value binds that value or `''` **[src bind.ts:169-191]**.
- `data-bind` does not read the event payload. To use `evt`, use `data-on`. (docs)

### 3.5 `data-on` details
- `evt` is the event object. Works with custom events too (`data-on:myevent="$x = evt.detail"`). (docs)
- Modifiers: `__once __passive __capture` (passed as `addEventListener` options for any event, custom included); `__prevent __stop`; `__window __document __outside` (`__outside` forces the `document` target); timing `__delay.<dur>`, `__debounce.<dur>[.leading][.notrailing]`, `__throttle.<dur>[.noleading][.trailing]` where `<dur>` is `500ms`, `1s`, or a bare number of ms; `__viewtransition`; `__case`. Combine freely: `data-on:click__window__debounce.500ms.leading`. (docs, src on.ts:20-69, utils/timing.ts:56-68)
- `data-on:submit` on a `<form>` **automatically calls `preventDefault()`** **[src]**. Don't add `__prevent` for that.
- Each listener runs inside a signal batch **[src]**.
- Datastar's own events (`datastar-fetch`, `datastar-signal-patch`) are always listened for on `document` regardless of where the attribute sits **[src]**.

### 3.6 Evaluation order
DOM is walked depth-first; attributes apply **in the order they appear** on the element. Attributes are re-applied after patches that add, remove or change them; a morph preserves existing attributes unless the attribute itself changed, so unchanged `data-*` attributes are **not** re-run. (docs)

### 3.7 Errors
Misuse throws a plain `Error` whose message is `<Reason>\nMore info: https://data-star.dev/errors/<snake_reason>?metadata=<json>\nContext: <json>`. Example: `data-text:foo` → reason `KeyNotAllowed`, URL `/errors/key_not_allowed`; the plugin name travels in the metadata. **[src errors.ts:16, engine.ts:312-334]**

---

## 4. Signals and expressions

### 4.1 Rules
- `$name` reads/writes a signal. Nested: `$user.name`. Arrays: `$items[$i]`. (docs, src)
- **Undefined reads create the signal as `''`.** Reading `$nope` makes it exist with an empty string. **[src signals.ts]** Declare signals up front.
- Signals whose name starts with `_` (any path segment, e.g. `$_x` or `$a._b`) are **not sent to the backend by default**. The default filter is `exclude: /(^|\.)_/`, and it belongs to fetch only: `@setAll`, `@toggleAll`, `data-json-signals` and `data-on-signal-patch` default to excluding nothing, so they do see `_` signals. **[src fetch.ts:40, signals.ts:761]** This is convenience, **not security** (docs: Security).
- `el` (element) is in every expression. `evt` in `data-on`. `patch` in `data-on-signal-patch`. (docs)
- Multiple statements: separate with `;`. The **last** statement is the value for value-returning attributes. Newlines alone don't separate. **[src genRx]**
- Template literals work: ``data-text="`Count: ${$count}`"``. Signals inside `${}` are rewritten only when the braces are not nested; `${ {a:$x}.a }` leaves `$x` unreplaced. **[src engine.ts:446-463]**

### 4.2 Tokenizer pitfall: hyphens in signal names
The signal branch of the substitution regex is `\$(\w+(?:[.-]\w+)*)`, which treats `-` between word characters as part of the name **[src engine.ts:430-460]**:

```text
$count-1      ->  $['count-1']   (a signal named "count-1", NOT $count minus 1)
$count - 1    ->  correct subtraction (spaces!)
$foo-$bar     ->  subtraction ($ is not \w, so the name stops)
$count--      ->  decrement works
```
Always put spaces around `-` before a digit or word. The same applies to `.`: `$a.b` is nested access.

### 4.3 Sending and receiving signals
- Backend actions send all non-underscore signals by default. `GET`/`DELETE`: JSON in the `datastar` query param. `POST/PUT/PATCH/QUERY`: JSON body. **[src]** (ADR lists GET/DELETE as query, PATCH/POST/PUT as body.)
- Keep `filterSignals` at default unless you have a reason (docs: the_tao_of_datastar "Start with the Defaults").
- Backend patches signals with a `datastar-patch-signals` event (RFC 7386 JSON Merge Patch): add/update by value, remove by `null`, nested objects recurse. **[adr]**
- Signal values are visible in the page and editable by users: never put secrets in signals; validate everything server-side. (docs: Security)

### 4.4 Computed vs effect vs on-signal-patch
- `data-computed:x="..."`: pure derived value. No actions, no side effects. (docs)
- `data-effect="..."`: runs now and whenever its dependencies change; where side effects go. (docs)
- `data-on-signal-patch`: fires on *any* patch (optionally filtered). (docs)

### 4.5 Keep expressions small
Put logic in a templating language, a web component (Rocket), or an external script; send props down and events up. (docs: guide/datastar_expressions)

---

## 5. Actions and the request protocol

### 5.1 List
`@` prefix inside expressions. **Backend actions:** `@get @post @put @patch @delete @query`. **Signal helpers:** `@peek(fn)` (read without subscribing), `@setAll(value, {include, exclude})`, `@toggleAll({include, exclude})`. **[src]** Pro adds `@clipboard @fit @intl` (docs: reference/actions; signatures in section 11).

`@query` uses the HTTP `QUERY` method: a safe, read-only request with the signals in the **body**. **[src]** (Rocket 0.5 doesn't support `QUERY`; Axum and Warp do. [rs])

### 5.2 Options (second argument) **[src fetch.ts]**

| Option | Default | Meaning |
|---|---|---|
| `contentType` | `'json'` | `'json'` sends signals; `'form'` sends the closest `<form>` (or `selector`) **instead of** signals |
| `selector` | `null` (closest form) | CSS selector of the form for `'form'` mode |
| `headers` | none | extra request headers |
| `filterSignals` | `{include:/.*/, exclude:/(^\|\.)_/}` (docs print the exclude as `/(^_\|\._).*/`; same set) | which signals to send |
| `openWhenHidden` | `false` for `@get`, `true` for all others | keep the stream open when the tab is hidden |
| `payload` | none | send this object instead of the signals |
| `requestCancellation` | `'auto'` | `'auto'` aborts a prior request with the same method + raw URL string; `'cleanup'` does that **and** aborts when the attribute is cleaned up (element removed); `'disabled'`; or pass your own `AbortController` (src fetch.ts:51-72) |
| `retry` | `'auto'` | `'auto'` / `'error'` / `'always'` / `'never'` (see 5.4) |
| `retryInterval` / `retryScaler` / `retryMaxWait` / `retryMaxCount` | `1000` / `2` / `30000` / `10` | exponential backoff |

### 5.3 What the request looks like **[src]**
- Headers: `Accept: text/event-stream, text/html, application/json` and `Datastar-Request: true`. `Content-Type: application/json` is set for JSON bodies on methods that have a body. Your `headers` option is merged last and can override all three. Use `Datastar-Request` to tell Datastar requests apart server-side. (fetch.ts:81-88)
- JSON mode: signals go in the body (`POST/PUT/PATCH/QUERY`) or in `?datastar=<json>` (`GET/DELETE`). Existing query-string params on the URL are preserved.
- Form mode: validates the form first (`reportValidity()` unless `novalidate`) and aborts if invalid. **No signals are sent in this mode.** Body is `application/x-www-form-urlencoded`, or multipart if the form has `enctype="multipart/form-data"`. For `GET/DELETE` the fields are appended to the query. The submitter's `name=value` is included if it has a name.
- Calling a form action from a non-submit element also blocks the form's native submission for the duration.

### 5.4 Response handling and retries **[src]**
- `204 No Content` is a valid reply to any backend action (docs: reference/actions).
- `200` + `text/event-stream` → parsed as SSE.
- `200` + `text/html` → one `datastar-patch-elements` patch; headers `datastar-selector`, `datastar-mode`, `datastar-namespace`, `datastar-use-view-transition` override defaults. (`viewTransitionSelector` is not available this way.)
- `200` + `application/json` → one `datastar-patch-signals` patch; `datastar-only-if-missing` header.
- `200` + `text/javascript` → executed as a script appended to `<head>` (not removed afterwards); optional `datastar-script-attributes` header (JSON object of attributes). **The fetch promise never resolves on this path** (`dispose(); return` with no `resolve()`, fetch.ts:651-652): `finished` never fires and a `data-indicator` on that element stays `true`. Source-read, not runtime-verified. Prefer an SSE patch that appends a `<script>`.
- Form mode with a failing `reportValidity()` has the same shape: `started` already fired, the promise is abandoned, the indicator sticks (fetch.ts:160-163, 470-473). Source-read.
- Any other content type is treated as an SSE stream, which yields no events. Events whose `event:` name does not start with `datastar` (including default `message` events) are dropped silently; `:` comment lines are ignored safely. (fetch.ts:110, 403)
- `responseOverrides` exists in the `FetchArgs` type but is never read in 1.0.4; do not rely on it. (fetch.ts:36-49)
- Non-`200`: no retry under `'auto'`; a `datastar-fetch` `error` event fires for status ≥ 400. Retry only if `retry: 'always'`, or `'error'` with a 4xx/5xx. `204` and redirects are never retried.
- **Network failure (fetch throws) retries up to `retryMaxCount` times with backoff regardless of mode** (unless aborted).
- **A cleanly finished SSE stream does not reconnect** unless `retry: 'always'`. A long-lived stream must be held open by the server.
- SSE `id:` is echoed back as `last-event-id` on retry; SSE `retry:` sets the base interval.
- Hidden tab: for `openWhenHidden: false` (default for `@get`), the request is aborted when the tab hides and **re-issued** when it shows. For a `data-init="@get(...)"` stream that holds server-side state, this means the stream restarts. Set `{openWhenHidden: true}` to keep it open. (src fetch.ts:497-515; docs: how_tos/prevent_sse_connections_closing)
- Fetch lifecycle events dispatch on `document` as `datastar-fetch` with `detail = {type, el, argsRaw}`, `type` ∈ `started | finished | error | retrying | retries-failed`; `error` carries `argsRaw.status`. Listen with `data-on:datastar-fetch`. A single `datastar-ready` fires on `document` when the engine starts observing. (fetch.ts:248-259, consts.ts:3, engine.ts:214-218)

---

## 6. SSE wire format (what the server sends)

### 6.1 Server requirements **[adr]**
Response headers: `Content-Type: text/event-stream`, `Cache-Control: no-cache`, and `Connection: keep-alive` on HTTP/1.1 only. Flush immediately; keep event order. Note compression middleware can interfere with flushing. (Brotli compresses SSE streams extremely well per the Tao page.)

### 6.2 Event framing **[adr, rs]**
```
event: datastar-patch-elements
id: 123                       (optional)
retry: 2000                   (optional; omitted when 1000)
data: <field> <value>         (one per line)
data: <field> <value>
<blank line>                  (ends the event)
```
Each `data:` line is `<field><space><value>`. Repeated fields are joined with `\n` by the client. **[src]**

### 6.3 `datastar-patch-elements`
Fields (only send non-defaults): `selector`, `mode`, `useViewTransition` (default `false`), `viewTransitionSelector` (default `document`), `namespace`, `elements` (one `data: elements ...` line **per line of HTML**). **[adr, docs: reference/sse_events]** Docs example of the full form:

```
event: datastar-patch-elements
data: selector #foo
data: mode inner
data: useViewTransition true
data: viewTransitionSelector #main
data: elements <div>
data: elements        Hello world!
data: elements </div>
```

```
event: datastar-patch-elements
data: elements <div id="feed"><span>1</span></div>

event: datastar-patch-elements
data: mode append
data: selector #mycontainer
data: elements <div>New content</div>

event: datastar-patch-elements
data: mode remove
data: selector #feed, #otherid

event: datastar-patch-elements
data: mode append
data: selector #vis
data: namespace svg
data: elements <circle id="c1" cx="10" r="5" fill="red"/>
```
(All four are from the ADR.)

**Modes** (exactly these eight; anything else throws `PatchElementsInvalidMode`) **[src]**:

| Mode | Morphed? | Behavior |
|---|---|---|
| `outer` (default) | yes | morph the whole target element, preserving state |
| `inner` | yes | morph target's children only |
| `replace` | no | replace element, resetting state |
| `prepend` / `append` | no | insert inside target at start / end |
| `before` / `after` | no | insert as sibling |
| `remove` | no | remove target; `elements` may be omitted |

Rules **[src]**:
- Without `selector`, only `outer`/`replace` work, and **each top-level element must have an `id`** matching an element in the DOM. A missing target logs `PatchElementsNoTargetsFound` and is skipped.
- With any other mode, `selector` is **required**.
- Elements are parsed inside a `<template>`, so `<tr>`, `<td>`, `<li>` etc. work as top-level elements.
- If the payload contains `</html>`, `</head>` or `</body>`, it patches the document, head or body.
- `namespace: svg|mathml` wraps the payload in the right parent so SVG/MathML parse correctly (or wrap it in `<svg>` yourself); any other value throws `PatchElementsInvalidNamespace`. (patchElements.ts:30, 60-62)
- `useViewTransition` is on only when the field is exactly `true` after trim; `1`/`yes` are false. (utils/text.ts:24 `isStringTrue`)
- Complete elements only, not fragments or bare text. (adr)
- `<script>` tags inside patched content are re-created and executed once per **new** script node. Under `outer`/`inner`, a `<script>` that soft-matches an existing script element is morphed in place and **not** re-run; use `append`/`replace` or a fresh `id` for scripts that must execute. (patchElements.ts:194-215, 540-547)

### 6.4 `datastar-patch-signals`
```
event: datastar-patch-signals
data: signals {"output":"Patched","user":{"name":"","email":""}}
```
`onlyIfMissing true` is an optional extra line (must be exactly `true`). The `signals` value is `JSON.parse`d first, falling back to a JS object literal. Remove with `null`. Plain objects merge recursively; **arrays replace wholesale**; patching an object onto a path holding a non-object resets that path to `{}` first; under `onlyIfMissing`, `null` entries are ignored rather than deleting. **[adr, src patchSignals.ts:9-19, signals.ts:722-749]**

### 6.5 ExecuteScript is just a patch
```
event: datastar-patch-elements
data: mode append
data: selector body
data: elements <script data-effect="el.remove()">console.log('Here')</script>
```
`autoRemove` (default true) is an SDK-side convenience that adds `data-effect="el.remove()"`; the library knows nothing of it. **[adr]** Craft's `execute_script` goes one step further and emits no `<script>` at all (section 13.2).

### 6.6 Reading signals on the server **[adr]**
`GET`, `DELETE`: URL-decoded JSON in query param `datastar`. `POST`, `PUT`, `PATCH`, `QUERY`: JSON body. Return an error on invalid JSON.

### 6.7 Multi-line safety (important)
A payload with newlines **must** be split into one `data: elements ...` line per line. A raw `format!("data: elements {html}\n\n")` with multi-line HTML breaks the event: the second line has no `data:` prefix, the event terminates at the first blank line, and the remainder is garbage. The official Rust SDK does this with `elements.lines()` [rs]. If you serialize yourself, do the same (section 13).

Also: every `data:` line needs a space after the field name. The client does `line.indexOf(' ')` to split key from value **[src fetch.ts:112-123]**; with no space it takes `line.slice(0,-1)` as the key, so the line is silently misfiled rather than rejected. Keep the trailing space on empty lines (`data: elements ` + nothing), or drop blank lines (safe except inside `<pre>`/`<textarea>`).

---

## 7. Morphing: how patching actually works

All **[src patchElements.ts]** unless noted.

- Nodes are matched by **ID sets**: an old and new node match when they share a descendant `id` that persists (same `id` and same `tagName` on both sides). Otherwise "soft match" by node type + tag name (and compatible `id`). Persistent-ID elements are moved (using `moveBefore` when the browser supports it) and morphed, rather than recreated. Duplicate IDs are excluded from persistence, so **use unique, stable IDs**. (patchElements.ts:310-347, 540-573)
- Attribute sync: attributes from new content are copied; attributes absent from new content are **removed** from the old element, except those listed in `data-preserve-attr`.
- Form controls:
  - `<input>` value is updated only if the `value` **attribute** differs between old and new; what the user typed is preserved when the server's attribute hasn't changed. `checked`/`disabled` sync from attribute presence. `type=file` is untouched. A `datastar-prop-change` event fires so `data-bind` re-reads the value.
  - `<textarea>` updates when its content differs from the old default value.
  - `<option selected>` syncs.
- `data-ignore-morph` skips an element and its subtree **only if both old and new have the attribute** (and always if an ancestor in the old DOM has it). To remove it, patch the element with the attribute removed. (docs, src)
- Existing `data-*` attributes are re-applied only if they changed, via the mutation observer. To force `data-init` or other attributes to re-run on an element that morphs in place, change the attribute value, or use `mode replace` (a new node is created and its attributes are applied fresh). (docs; replace behavior is inferred from the source)
- Elements removed from the DOM have their attribute cleanups run (listeners, effects).
- Single-target patches reuse the new node instead of deep-cloning. Multi-target (`selector` matching several) clones per target.

**Practical consequences**
- Give every patchable region a stable `id`.
- Keep the `id` the same across a swap to let CSS transitions run ([ex animations]).
- A third-party widget inside a patched region needs `data-ignore-morph` (Rocket examples do this for canvases/maps).

---

## 8. Recipes

Markup is verbatim from the example page named (`[ex slug]`) or how-to URL. Attribute values are trimmed to the attributes that matter.

### 8.1 Active search [ex active_search]
```html
<input
    type="text"
    placeholder="Search..."
    data-bind:search
    data-on:input__debounce.200ms="@get('/examples/active_search/search')"
/>
```
`GET` carries `$search` in `?datastar=`. The server returns the rows (patch the results container by id).

### 8.2 Loading indicator / disable while busy
```html
<button data-on:click="@get('/endpoint')" data-indicator:fetching
        data-attr:disabled="$fetching"></button>
<div data-show="$fetching">Loading...</div>
```
(docs: reference/attributes). The Click-to-Load guard, verbatim [ex click_to_load]:
```html
<button data-indicator:_fetching
        data-attr:aria-disabled="`${$_fetching}`"
        data-on:click="!$_fetching && @get('/examples/click_to_load/more')">Load More</button>
```
Note `_fetching`: an indicator named without `_` is sent to the backend like any signal.

### 8.3 Lazy load [ex lazy_load]
```html
<div id="graph" data-init="@get('/examples/lazy_load/graph')">Loading...</div>
```
"The graph is loaded by patching an element with the same ID": the response is `<div id="graph"><img src="..."></div>`.

### 8.4 Infinite scroll / click to load more
Infinite scroll [ex infinite_scroll]: the **last** element carries `data-on-intersect="@get('/examples/infinite_scroll/more')"`; "the result is then appended after it."

Load more (docs: how_tos/load_more_list_items), the one place the docs recommend `append` over the default `outer`:
```html
<div id="list"><div>Item 1</div></div>
<button id="load-more" data-signals:offset="1" data-on:click="@get('/how_tos/load_more/data')">Click to load another item</button>
```
```
event: datastar-patch-elements
data: selector #list
data: mode append
data: elements <div>Item 2</div>

event: datastar-patch-signals
data: signals {offset: 2}

event: datastar-patch-elements
data: selector #load-more
data: mode remove
```

### 8.5 Click to edit / edit row / delete row / bulk update
- Click-to-edit [ex click_to_edit]: view state has `Edit` → `@get('/examples/click_to_edit/edit')` and `Reset` → `@patch('/examples/click_to_edit/reset')`; edit state has inputs `data-bind:first-name` / `last-name` / `email`, `Save` → `@put('/examples/click_to_edit')`, `Cancel` → `@get('/examples/click_to_edit/cancel')`. Every button carries `data-indicator:_fetching data-attr:disabled="$_fetching"`. "There Is No Form … There Is No Client Side Validation": the PUT body is the signals, the server validates.
- Edit row [ex edit_row]: `Edit` → `@get('/examples/edit_row/0')` returns the **whole table** ("we are going to remove the edit buttons from other rows"); the row's `Save` is `@patch('/examples/edit_row/0')`, `Cancel` is `@get('/examples/edit_row/cancel')`.
- Delete row [ex delete_row]: `data-on:click="confirm('Are you sure?') && @delete('/examples/delete_row/0')" data-indicator:_fetching data-attr:disabled="$_fetching"`.
- Bulk update [ex bulk_update]: the container seeds the array with `data-signals__ifmissing="{_fetching: false, selections: Array(4).fill(false)}"`; rows have `<input type="checkbox" data-bind:selections>`; the header checkbox is `data-bind:_all data-on:change="$selections = Array(4).fill($_all)" data-effect="$selections; $_all = $selections.every(Boolean)"`; buttons `@put('/examples/bulk_update/activate|deactivate')`. The `data-effect` reads `$selections` first to subscribe to the array.

### 8.6 Inline validation [ex inline_validation]
```html
<input type="email" required data-bind:email
       data-on:keydown__debounce.500ms="@post('/examples/inline_validation/validate')" />
```
The event is `keydown`, not `input`. "Since it's easy to replace the whole form, the logic for displaying the validation results is kept simple."

### 8.7 Polling (docs: how_tos/poll_the_backend_at_regular_intervals)
```html
<div id="time" data-on-interval__duration.5s="@get('/endpoint')"></div>
<div id="time" data-on-interval__duration.5s.leading="@get('/endpoint')"></div>
```
The response replaces the element, so the **server can change the interval** by emitting a different `__duration`:
```
event: datastar-patch-elements
data: elements <div id="time" data-on-interval__duration.5s="@get('/endpoint')">
data: elements     {{ now }}
data: elements </div>
```
"Be careful not to add `.leading` to the modifier in the response, as it will cause the frontend to immediately send another request." "Push-based mechanisms are more efficient than polling."

### 8.8 Long-lived stream (CQRS)
```html
<div data-init="@get('/cqrs_endpoint')"></div>
<div id="main">...</div>
```
(docs: how_tos/prevent_sse_connections_closing, verbatim.) The how-to's advice is to **leave `openWhenHidden` at its default** and send fat morphs: "if the SSE connection is interrupted for any reason, the next event will contain the complete and correct state of the main content area." `{openWhenHidden: true}` is the Progress Bar example's choice ([ex progress_bar]: `data-init="@get('/examples/progress_bar/updates', {openWhenHidden: true})"`) for a stream whose server-side position must not restart. TodoMVC and Templ Counter use the plain form ([ex todomvc]: `<section id="todomvc" data-init="@get('/examples/todomvc/updates')">`).

### 8.9 Redirect from the backend (docs: how_tos/redirect_the_page_from_the_backend)
```
event: datastar-patch-elements
data: elements <div id="indicator">Redirecting in 3 seconds...</div>

event: datastar-patch-elements
data: selector body
data: mode append
data: elements <script>window.location.href = "/guide"</script>
```
"Existing signals will not persist to the new page." Firefox replaces rather than pushes history when the redirect runs inside a `<script>`; wrap it: `setTimeout(() => window.location = '/guide')` (issue #529). Craft's `sse::redirect(url)` does the escaping and the optional delay (section 13.2).

### 8.10 Forms and file upload [ex form_data, file_upload]
```html
<form id="myform">
    <input type="checkbox" name="checkboxes" value="foo" />
    <button data-on:click="@get('/endpoint', {contentType: 'form'})">Submit GET request</button>
    <button data-on:click="@post('/endpoint', {contentType: 'form'})">Submit POST request</button>
</form>
<button data-on:click="@get('/endpoint', {contentType: 'form', selector: '#myform'})">Submit GET request from outside the form</button>
<form data-on:submit="@get('/endpoint', {contentType: 'form'})"><input type="text" name="foo" required /><button>Submit form</button></form>
```
"No signals are sent to the backend in this type of request." (docs, src)
- Signal-based upload: `<input type="file" data-bind:files multiple/>` then `<button data-on:click="$files.length && @post('/examples/file_upload')" data-attr:disabled="!$files.length">`. "We don't need a form because everything is encoded as signals"; contents arrive base64.
- Real multipart: `<form enctype="multipart/form-data"><input type="file" name="file" /><button data-on:click="@post('/endpoint', {contentType: 'form'})">`. (docs: reference/actions)

### 8.11 Key bindings (docs: how_tos/bind_keydown_events_to_specific_keys)
```html
<div data-on:keydown__window="(evt.key === 'Enter' || (evt.ctrlKey && evt.key === 'l')) && alert('Key pressed')"></div>
<div data-on:keydown__window="evt.key === 'Enter' && (evt.preventDefault(), alert('Key pressed'))"></div>
```

### 8.12 DRY repeated actions (docs: how_tos/keep_datastar_code_dry)
"This should be solved using your templating language": `{% set action = "@get('/endpoint')" %}` then `data-on:click="{{ action }}"`. Or delegate:
```html
<div data-on:click="evt.target.tagName == 'BUTTON' && ($id = evt.target.dataset.id) && @get('/endpoint')">
    <button data-id="1">Click me</button>
</div>
```
Use `closest('button[data-id]')` when buttons have child elements (that form is from 8.17).

### 8.13 Update the page title [ex title_update]
```
event: datastar-patch-elements
data: selector title
data: elements <title>08:30:36</title>
```

### 8.14 SVG [ex svg_morphing]
```
event: datastar-patch-elements
data: namespace svg
data: elements <circle id="circle" cx="100" r="50" cy="75"></circle>
```
Key points from the page: "SVG elements must be wrapped in an outer `<svg>` container. The inner `<svg>` element should have the target ID … Multiple SVG elements can be updated in a single morph operation. CSS transitions work with SVG morphing." The Progress Bar example "sends down a new progress bar svg every 500 milliseconds" [ex progress_bar].

### 8.15 Signals-only streaming [ex bad_apple]
```html
<label data-signals="{_percentage: 0, _contents: ''}" data-init="@get('/examples/bad_apple/updates')">
    <span data-text="`Percentage: ${$_percentage.toFixed(2)}%`"></span>
    <input type="range" min="0" max="100" step="0.01" disabled data-attr:value="$_percentage" />
</label>
<pre data-text="$_contents"></pre>
```
"No need to generate HTML elements, as the contents are already bound to existing elements" (30 fps).

### 8.16 Third-party libraries and web components
- Widget emits a DOM event; `data-on:` copies it into a signal and the widget stays decoupled. [ex sortable]: `<div id="sortContainer" data-on:reordered="$orderInfo = event.detail.orderInfo">`. [ex web_component]: `<reverse-component data-on:reverse="$_reversed = evt.detail.value" data-attr:name="$_name">`.
- Custom plugin [ex custom_plugin]: `action({ name: 'alert', apply(ctx, value) { alert(value) } })` and `attribute({ name: 'alert', requirement: { key: 'denied', value: 'must' }, returnsValue: true, apply({ el, rx }) { const cb = () => alert(rx()); el.addEventListener('click', cb); return () => el.removeEventListener('click', cb) } })`. "Documentation is in progress."
- [ex match_media] (**Pro**): `<div data-match-media:is-dark="prefers-color-scheme: dark" data-class:dark="$isDark">`; the value is raw text, no `$`, quotes optional.

### 8.17 Event bubbling / single listener [ex event_bubbling]
```html
<div id="event-bubbling-container" data-on:click="$key = evt.target.closest('button[data-id]')?.dataset.id ?? $key">
```
CSS: `pointer-events: none` on the container and on button contents, `user-select: none` on buttons, "so nested elements like `<br>` don't become the click target."

### 8.18 Details worth stealing from other examples
- DBmon: swap which signal an input binds by driving the attribute itself: `data-attr:data-bind:mutation-rate="$_editing"`; `data-on:blur="@put('/examples/dbmon/inputs'); $_editing = false"`.
- TodoMVC: `data-on:keydown="evt.key === 'Enter' && $input.trim() && @patch('/examples/todomvc/-1') && ($input = '');"`.
- Lazy Tabs: "the selected tab is a part of the application state … simply include the tab markup in the returned HTML fragment."
- On Signal Patch: `data-on-signal-patch="$counterChanges.push(patch)" data-on-signal-patch-filter="{include: /^counter$/}"` with `<pre data-json-signals__terse="{include: /^counterChanges/}">`.
- Animations: keep the `id` stable and CSS transitions run between old and new; fade out by sending `opacity: 0` with a transition duration.

---

## 9. Examples index (all 41 pages on data-star.dev/examples; local copies in `temp/datastar-examples/`)

| Example | Technique |
|---|---|
| Active Search | `data-bind` + `data-on:input__debounce` + `@get` |
| Animations | stable `id` across swaps, CSS transitions, view transitions |
| Bad Apple | stream signal patches only; `data-text`/`data-attr:value` bound |
| Bulk Update | array-bound checkboxes, `@put`, re-render table |
| Click To Edit | `@get` edit view, `@put` save, `@patch` reset, no form |
| Click To Load | `data-indicator` guard, append rows |
| Custom Event | `data-on:myevent="$x = evt.detail"` |
| Custom Plugin | `@alert` action + `data-alert` attribute |
| DBmon | long-lived `data-init` stream, blur → `@put` inputs, swap `data-bind` attr |
| Delete Row | `confirm() && @delete` |
| Edit Row | per-row edit, whole-table replace, `@patch` save |
| Event Bubbling | one container listener |
| File Upload | `data-bind:files`, base64 signals |
| Form Data | `contentType: 'form'` |
| Infinite Scroll | `data-on-intersect` on last element |
| Inline Validation | `keydown__debounce.500ms` → `@post` |
| Lazy Load | `data-init` swap same id |
| Lazy Tabs | tab state is server-rendered markup |
| Match Media (**Pro**) | `data-match-media` |
| On Signal Patch | `data-on-signal-patch` + filter + `data-json-signals__terse` |
| Progress Bar | stream SVG, `openWhenHidden: true` |
| Progressive Load | SSE composes a page progressively |
| Sortable | external lib dispatches event |
| SVG Morphing | `namespace svg`, id-targeted patches |
| Templ Counter | global vs user counter via `@patch`, streamed |
| Title Update | patch `title` |
| TodoMVC | `data-init` stream + `@post/@patch/@put` |
| Web Component | attribute down, event up |
| Rocket × 13 (each page badged **Pro**, "Rocket is a Pro feature, currently in beta") | Conditional, Copy Button, Counter, ECharts, Flow, Globe, Letter Stream, OpenFreeMap, Password Strength, Projection, QR Code, Starfield, Virtual Scroll (see 10) |

Exactly six how-tos: `bind_keydown_events_to_specific_keys`, `keep_datastar_code_dry`, `load_more_list_items`, `poll_the_backend_at_regular_intervals`, `prevent_sse_connections_closing`, `redirect_the_page_from_the_backend` (all covered above).

---

## 10. Rocket (web components): beta.2

Status, stated as facts rather than a label: the `datastar-rocket.js` bundle is published in the MIT `starfederation/datastar` repo at v1.0.4 (header `Datastar v1.0.4 + Rocket beta.2`) and is also inside `datastar-pro.js`; the source lives in the commercial `datastar-pro` repo under `library/src/rocket/`; every Rocket example page still says "Rocket is a Pro feature, currently in beta"; the reference page says only "currently in beta and its API is subject to change." The "Free Launch" essay's free/MIT wording was not re-fetched and is **unverified**. [src bundles/*.ts, ex rocket_*, docs reference/rocket]

Counter, verbatim [ex rocket_counter]:
```js
import { rocket } from 'datastar'

rocket('my-counter', {
  mode: 'light',
  props: ({ number }) => ({ count: number.step(1).min(0) }),
  setup({ $$, observeProps, props }) {
    $$.counter = props.count
    observeProps(() => { $$.counter = props.count }, 'count')
  },
  render: ({ html }) => html`<button data-on:click="$$counter++" data-text="'Count: ' + $$counter"></button>`,
})
```

Definition fields (docs, src runtime.ts:203-221): `refs`, `props`, `manifest`, `setup`, `onFirstRender` (refs available), `render`, `mode` (`'open'|'closed'|'light'`; omitted → `'open'` shadow DOM), `renderOnPropChange` (`boolean`, default `true`, or `({host, props, changes}) => boolean`).
Codecs: `string number bool date json js bin array(codec | c1, c2…) object oneOf createCodec`; chain members are getters where they take no argument (`string.trim.lower.kebab.maxLength(48)`, `number.clamp(0,100).round.default(50)`). A throwing decoder `console.warn`s and falls back to the codec default. Prop names are JS-style and reflect to kebab attributes (`startDate` ↔ `start-date`).
Setup context (docs, src runtime.ts:107-143): `props $ $$ effect apply adoptStyles cleanup emit emitCancellable actions action observeProps overrideProp defineHostProp render host`. **`props` is a plain object, not a signal source**: `effect(() => props.x)` runs once; react with `observeProps((props, changes) => …, 'x')`. `$$name` is rewritten to `$._rocket.<tag_>.<id>.name` (host `id` or a generated one; duplicates get `_2`); that path starts with `_rocket`, so the default fetch filter drops these signals. Structural attributes, on `<template>` only: `data-if / data-else-if / data-else`, `data-for="$$list" | "item in $$list" | "item, i in $$list"`; rows reconcile by index, no identity preservation in this version. `__root` applies only to signal-name attributes (`data-bind data-computed data-indicator data-ref data-signals`), not to `data-on` or `data-text`.
Patterns from the examples: wrap libraries (ECharts, MapLibre, Globe.GL) by creating them in `onFirstRender`, mark their container `data-ref:x data-ignore-morph`, update via `observeProps`, tear down with `cleanup`, set `renderOnPropChange: false` (or a predicate) when the library owns the DOM. Servers drive a component by patching its attributes; the Flow example listens for `flow-node-*` events and takes `serverUpdateTime`. A server may also patch **inside** a host: `datastar-scope-children` rescopes raw `$$` in the patched children (src runtime.ts:751-802).

For your stack: Rocket is optional. The core guidance is that complex client logic belongs in web components driven by Datastar, and Rocket is the sanctioned way (docs). SKILL.md carries the full API and the traps learned in Loadout and Flow.

---

## 11. Datastar Pro (licensed; full detail in `datastar-pro-addendum.md`)

Pro v1.0.4 adds 10 attributes (`data-animate data-custom-validity data-match-media data-on-raf data-on-resize data-persist data-query-string data-replace-url data-scroll-into-view data-view-transition`), 3 actions (`@clipboard(text, isBase64?)`, `@fit(v, oldMin, oldMax, newMin, newMax, shouldClamp=false, shouldRound=false)`, `@intl(type, value, options?, locale?)`), the `<datastar-inspector>` web component, and the bundler. The addendum documents each from `library/src/pro/**` with cites and records the bugs found by running them: three `data-animate` easings throw, `@intl('relativeTime')` needs `{unit: ['day']}`, `@clipboard` returns `undefined`, the Inspector's persisted-key scan looks for `data-persist-` instead of `data-persist:`.

---

## 12. Security

- **Escape all user input** in server-rendered HTML. Datastar evaluates `data-*` expressions as JavaScript, so unescaped user data in an attribute is script execution. Use your template engine's escaping (Askama auto-escapes `{{ }}` in HTML templates) and **never interpolate user data into expression strings**; pass it through signals instead. (docs)
- If you can't escape something, wrap it in `data-ignore`. (docs)
- Signals are visible and editable client-side. No secrets. Validate on the backend. (docs)
- **CSP**: by default Datastar uses `Function()`, so CSP needs `script-src 'self' 'unsafe-eval'`. Alternative **CSP mode**: put a per-response cryptographic nonce in `<html data-nonce="...">` matching `script-src 'nonce-...'`; Datastar reads then removes the attribute. Patch responses don't need the nonce. This does **not** make untrusted attribute content safe. With Trusted Types, Datastar creates a policy named `datastar` (allow with `trusted-types datastar; require-trusted-types-for 'script'`); it does not sanitize. (docs)
- CSRF and auth are your responsibility: signals and headers (`headers` option) are the carriers.

---

## 13. Implementation notes for worker-rs + Askama

Everything in this section was compiled for `wasm32-unknown-unknown` with `worker = "0.8.6"` (features `http`, `axum`), `futures 0.3`, `askama 0.15`, `serde_json`, and tested natively on 2026-10-07 **[build]**. Scratch crate: `/tmp/claude-1000/-home-peter-Projects-github/27670ca9-60fa-4acb-a1be-83ff998cc794/scratchpad/rs-check/` (session-temporary). The production reference is craft: `~/Projects/EveryGoodWork/craft-core/crates/craft-core-floor/src/{datastar,sse_event,sse_bridge}.rs` (13.2).

### 13.1 Three options for producing events
**A. Hand-roll (12 lines, no dependency).** BUILDS. Fits "every line is a liability" if you only need patch-elements/patch-signals.

```rust
/// One Datastar SSE event. Multi-line values become one `data:` line per line.
pub fn sse(kind: &str, fields: &[(&str, &str)]) -> String {
    let mut out = format!("event: datastar-{kind}\n");
    for (name, value) in fields {
        for line in value.lines() {
            out.push_str(&format!("data: {name} {line}\n"));
        }
    }
    out.push('\n');
    out
}
// sse("patch-elements", &[("elements", &html)])
// sse("patch-elements", &[("selector", "#list"), ("mode", "append"), ("elements", &row)])
// sse("patch-elements", &[("selector", "#row-7"), ("mode", "remove")])
// sse("patch-signals",  &[("signals", r#"{"count":3}"#)])
```
`value.lines()` yields empty strings for blank lines, which still produces `data: elements ` with the trailing space the client needs. Verified: an Askama template with a blank line and an indented `<pre>` goes through `sse()` and a Rust port of `fetch.ts` parsing (lines 114-123, 391-432) as **one** event whose `elements` equals the template output; the bytes are identical to what the `datastar` crate emits for the same HTML **[build]**.

**B. The official `datastar` crate (v0.4.1 is current on crates.io; MIT; edition 2024).** BUILDS for wasm32 with `default-features = false`; its 12 unit tests pass **[build]**. Framework integrations (`axum`, `rocket`, `warp`) are optional features. API as it actually is: `PatchElements::new(html).selector("#x").mode(ElementPatchMode::Append)`, `PatchElements::new_remove("#x")`, `PatchSignals::new(json).only_if_missing(true)`, plus `.id(..)` and `.retry(Duration)` on each; **neither `PatchElements` nor `PatchSignals` implements `Display`**: serialize with `.into_datastar_event().to_string()` (or `DatastarEvent::from(x)`). Field order is `selector` then `mode`; `retry:` is omitted at 1000 ms; each event ends `\n\n`. No signal reader; use serde.

**C. craft-core-floor (your production builder).** `craft_core::datastar::sse::{message, accumulator, patch_elements, patch_signals, patch_signals_raw, redirect, execute_script}` with a typestate `SseMessageBuilder<Empty|WithEvents>` (cannot `build()` with zero events), `SseAccumulator`, `SseMessage::to_sse_string()`; `PatchMode` (8 variants, `ALL`, `parse`), `Namespace`, and a `Selector` newtype that replaces control characters so a selector can never inject an SSE line. Non-default fields only (`mode` omitted when `outer`, `namespace` when `html`, `useViewTransition`/`onlyIfMissing` only when true). `id:`/`retry:` are emitted once per message before the first event (legal SSE; the crate puts them per event). 24 `sse` tests pass **[build]**.

### 13.2 Responding
- Finite reply (several events then done): one `String` of events with `Content-Type: text/event-stream`, `Cache-Control: no-cache`. The client parses the whole body as SSE. Craft: `TryFrom<SseMessage> for Response`.
- Long-lived stream: `worker::Response::from_stream` (worker 0.8.6 `response.rs:97`):
  ```rust
  pub fn from_stream<S>(stream: S) -> Result<Self>
  where S: TryStream + 'static, S::Ok: Into<Vec<u8>>, S::Error: Into<Error>
  ```
  No `Send`/`Unpin` bound; the body becomes a JS `ReadableStream`. An `mpsc::Receiver<worker::Result<String>>` is accepted directly. Minimal in-DO fan-out (compiled):
  ```rust
  use futures::channel::mpsc;
  use worker::{Response, Result};

  pub struct Subscriber { tx: mpsc::Sender<Result<String>> }

  impl Subscriber {
      pub fn send(&mut self, event: String) -> bool { self.tx.try_send(Ok(event)).is_ok() }
  }

  pub fn open_stream() -> Result<(Subscriber, Response)> {
      let (tx, rx) = mpsc::channel::<Result<String>>(64);
      let mut response = Response::from_stream(rx)?;
      let headers = response.headers_mut();
      headers.set("Content-Type", "text/event-stream")?;
      headers.set("Cache-Control", "no-cache")?;
      Ok((Subscriber { tx }, response))
  }
  ```
  Dropping `Subscriber` closes the channel and ends the stream; `try_send` failing `is_disconnected()` is "client went away". This is carm's `ConnectionManager` shape (`carm/src/cf_datastar.rs`).
- Craft's shape is different and preferred for hibernation: the Worker opens a WebSocket to the DO stub and `sse_bridge` turns DO text frames into an `async_stream::stream!` of pre-framed SSE strings, so the DO never holds the HTTP response. Every 25 s (`KEEPALIVE_INTERVAL`) it emits a keepalive: viewer legs get `datastar-patch-signals {}` (a no-op the Datastar client and Inspector see), machine legs get the SSE comment `: keep-alive`; two unanswered radio checks end the stream. Streams open with `retry: 1000` (`RECONNECT_RETRY`) so a dropped network reconnects quickly (5.4). `async-stream` compiles on wasm32 (it does not depend on tokio).
- Craft gzips the stream when `Accept-Encoding` allows (`SseEncoding::negotiate`): `ResponseBuilder::new().with_encode_body(EncodeBody::Manual).from_stream(...)`, `flush()` after every event so frames are not held in the encoder, `Content-Encoding: gzip`, `Vary: Accept-Encoding`.
- Craft's `execute_script` and `redirect` emit **no `<script>`**: `<div hidden data-effect="try { … } finally { el.remove() }"></div>` with the JS attribute-escaped and the URL JSON-encoded with `</` broken. The code runs through Datastar's evaluator (so CSP nonce mode covers it), removes itself even if it throws, and cannot be re-executed by a later morph.
- `openWhenHidden`: leave the default and send fat morphs unless the stream holds server-side position (8.8).
- **`X-Accel-Buffering: no` is not needed and not honored on Cloudflare.** It is on the documented list of response headers Cloudflare removes ("Removed response headers": X-Accel-Buffering, X-Accel-Charset, X-Accel-Limit-Rate, X-Accel-Redirect, Alt-Svc), https://developers.cloudflare.com/fundamentals/reference/http-headers/. Workers stream `ReadableStream` bodies by default, https://developers.cloudflare.com/workers/runtime-apis/streams/. Both carm and craft currently set it; it is dead weight. **[cf]**
- Askama alone cannot be tested against a live client here; the parser port above is the evidence.

### 13.3 Reading signals
- `GET`/`DELETE`: `serde_json::from_str` on the URL query param `datastar`.
- `POST`/`PUT`/`PATCH`/`QUERY`: JSON body. [adr, src]
- Form mode: normal urlencoded/multipart; **no signals** are sent. [src]
- Detect Datastar requests with the `Datastar-Request: true` header. [src]
- Treat all of it as untrusted input. The docs show "No example found for Rust" for signal reading; serde is the answer.

### 13.4 Askama
Render a fragment template per patchable region, each with a root element carrying a stable `id`. Return that rendered string through `sse("patch-elements", &[("elements", &html)])` or `sse::patch_elements(html)`. Askama's multi-line output is why the line-splitting in 13.1 matters, and why the old `format!("data: elements {}\n\n", html)` helper was wrong.

### 13.5 Design checklist for your Workers
1. Every patch target has a unique, stable `id`.
2. One `data-init="@get('/updates')"` stream per page, writes via `@post/@put/@patch/@delete`.
3. Full-region morphs, not incremental appends, so a dropped stream self-heals.
4. Signals only for transient UI state, with `_` prefix for client-only; never for data the server owns.
5. Datastar is SSE-only for UI; if you need binary/bidirectional channels (audio, game ticks), run a WebSocket separately and have the Durable Object turn results into patch events (matches your existing split-architecture note).

---

## 14. Pitfall checklist

1. `$count-1` is a signal named `count-1`. Write `$count - 1`.
2. Reading an undeclared `$signal` silently creates it as `''`. Declare with `data-signals` first.
3. Multi-line HTML in one `data:` line breaks the event (6.7).
4. No `selector` + mode other than `outer`/`replace` → error. No `id` on a top-level element → "no targets found".
5. The patch mode `morph` does not exist in current Datastar; use `outer` (which morphs).
6. `data-ignore-morph` must be on both old and new (or removed by a patch).
7. Morph preserves existing `data-*` attributes; `data-init` won't re-run unless the attribute changes or you use `replace`.
8. `@get` closes (and re-issues) its request when the tab hides unless `openWhenHidden: true`.
9. A finished stream doesn't reconnect; a dropped network does retry (up to 10).
10. Form mode sends no signals.
11. `data-indicator` must be created before a `data-init` fetch on the same element (attribute order).
12. `data-computed` must be pure; side effects go in `data-effect`.
13. `data-on:submit` already calls `preventDefault`.
14. `_`-prefixed signals aren't sent by default, but that is **not** a security boundary.
15. Same method+URL requests cancel each other by default (`requestCancellation: 'auto'`); set `'disabled'` if you need them concurrent.
16. Signal names can't contain `__` in the key form (`data-signals:a__b`); expressions and value form are fine.
17. Don't put user data in `data-*` expressions; use signals.
18. `data-preserve-attr` is read from the incoming HTML: send it on every patch of that element.
19. A `text/javascript` response or a failed form validation leaves the fetch promise unresolved: `finished` never fires and `data-indicator` sticks on. Return SSE instead; validate before calling the action.
20. `datastar-patch-signals` merges objects but **replaces arrays**; send the whole array.
21. A `<script>` morphed onto an existing `<script>` under `outer`/`inner` is not re-executed; `append` it or give it a new `id`.
22. `__case` is ignored on `data-attr` and `data-style`.
23. `data-text="$maybeNull"` renders the literal string `null`.

---

## 15. Discrepancies found in the previous SKILL.md (pre-2026-10-07) and their resolution

All confirmed against the sources above and fixed in SKILL.md on 2026-10-07.

| Previous skill said | Verified | Fix |
|---|---|---|
| Core "v1.0.0-beta.11+", Pro "v1.0.0", Rocket beta.1 | Core and Pro are v1.0.4; Rocket beta.2 (`CHANGELOG-ROCKET.md`) | Header, install pin |
| `mode: morph` is "the historic default", `outer`/`inner` are direct replacement | `morph` is not a mode (`PatchElementsInvalidMode`); `outer` (default) and `inner` morph; `replace` is the hard replacement (patchElements.ts:18-27) | Mental model, modes table, quick ref |
| `Sse::patch_elements` = `format!("...elements {}\n\n", html)` | Breaks on multi-line HTML (6.7) | Worker-rs section replaced with craft-core-floor + compiled helpers |
| `Sse::remove` sends `data: elements <x></x>` | `elements` may be omitted with `mode remove` (patchElements.ts:243) | Modes table |
| `data-cloak` | Not a plugin in `bundles/datastar.ts` and not in the attribute reference; use `data-show` + `style="display:none"` | Removed; 21 attrs = 17 plugins + 4 engine attrs |
| `contentType: 'form'` = `multipart/form-data` | urlencoded unless the form has `enctype="multipart/form-data"`; **no signals** sent (fetch.ts:140-205) | Options block, examples catalog row |
| `X-Accel-Buffering: no` "critical" on Cloudflare | Cloudflare strips it (removed-headers list) **[cf]** | Dropped; follow-up to remove from carm and craft-core |
| `datastar-fetch` dispatches "on the triggering element" | Dispatches on `document`, `detail.el` names the element (fetch.ts:248-259) | Actions section |
| 8 core actions | 9: `@query` added | Actions, quick ref |
| "No `async_stream!` macro (Tokio dep)" | `async-stream` has no tokio dependency; craft uses it on wasm32 | Cloudflare notes |
| Rocket is "Pro Custom Elements"; default `mode` light; `effect(() => props.x)` re-runs; `observeProps((old, new))`; `actions.local()` reaches local actions; `data-on:click__root`; `data-key` on `data-for`; light-DOM style scoping; `emit` returns boolean; `refs` in setup; source under `src/pro/rocket` | See section 10 and `E-rocket` findings D1-D10: all wrong against runtime.ts beta.2 | Rocket sections corrected in place, lessons preserved |
| Pro: animate easings list, `@intl` relativeTime `{unit: 'day'}`, `@clipboard` returns Promise, Inspector attributes and build command, "fires on every morph" for `data-replace-url` | See `datastar-pro-addendum.md` "Corrections" C1-C19 | Pro sections corrected in place |
| Execute script via `data: elements <script data-effect="el.remove()">` | Correct and kept (CARM pattern); craft's script-free `effect_element` added as the alternative | SSE section |

Everything else checked (signal wire format, content types, `_` prefix behavior, request shapes, `data-indicator` ordering, `@peek/@setAll/@toggleAll`, the ES-module URL identity incident, the signal reactivity gotchas, the Rocket traps) matches the source and stays.

---

## 16. Sources

- Local source of truth: `~/Projects/github/datastar-pro` at `8f64418` (v1.0.4): `library/src/**` (free plugins, Pro plugins, Rocket, bundles), `webcomponents/datastar-inspector/`, `CHANGELOG-ROCKET.md`. The docs-site source is **not** in this checkout.
- Local examples corpus: `~/Projects/EveryGoodWork/temp/datastar-examples/*.md` (41 pages, verbatim code).
- Docs site, raw HTML fetched 2026-10-07: https://data-star.dev/guide/getting_started, /guide/the_tao_of_datastar, /reference/attributes, /reference/actions, /reference/sse_events, /reference/security, /reference/rocket, /how_tos/* (6), /examples (index)
- Library and SDK spec: https://github.com/starfederation/datastar (`library/src/**`, `sdk/ADR.md`)
- Rust SDK: https://github.com/starfederation/datastar-rust (crate `datastar` 0.4.1, built and tested here)
- Cloudflare: https://developers.cloudflare.com/fundamentals/reference/http-headers/ (removed response headers), https://developers.cloudflare.com/workers/runtime-apis/streams/
- Production reference: `~/Projects/EveryGoodWork/craft-core/crates/craft-core-floor/src/{datastar,sse_event,sse_bridge}.rs`; `~/Projects/EveryGoodWork/carm/src/cf_datastar.rs`
- Error explainer pages: https://data-star.dev/errors/<snake_reason>

Still unverified: Rocket's license wording (the "Free Launch" essay was not re-fetched; example pages say Pro); the `text/javascript` and form-validation indicator hang (source-read, not run in a browser); live end-to-end of the Askama payload against a browser client (parser port only).
