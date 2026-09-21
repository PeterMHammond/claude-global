---
name: datastar
description: >
  Deep reference and architectural guidance for Datastar (data-star.dev) — the hypermedia-first
  frontend framework using SSE and data-* attributes. Use this skill whenever the user mentions
  Datastar, data-star.dev, SSE HTML patching, idiomorph morphing, datastar-patch-elements,
  data-signals, data-on, data-indicator, or is building a hypermedia-driven UI with server-sent
  events. Also trigger when the user asks about combining Datastar with Cloudflare Workers, Rust,
  worker-rs, Askama templates, or WebSockets alongside Datastar. This skill contains the correct
  mental model (HTML patches are primary, signals are the exception), the full data-* attribute
  reference, the SSE event wire format, Cloudflare-specific implementation patterns, and guidance
  on the WebSocket + SSE split architecture for audio/binary pipelines.
---

# Datastar Skill

Datastar v1.0.0-RC.8 — hypermedia-first frontend framework (data-star.dev)

---

## Core Mental Model — Read This First

**HTML patches are the primary mechanism. Signals are the exception.**

The server drives the DOM. Every meaningful state change starts as a backend render and arrives
as a `datastar-patch-elements` SSE event. Idiomorph morphs it into the existing DOM surgically —
preserving focus, scroll position, CSS transitions, input state.

Signals exist only for:
- Transient UI state with no server representation (`_showModal`, `_dropdownOpen`)
- Loading indicators (`data-indicator:loading`)
- Form field values in-flight before submission
- Optimistic UI before server confirms

**If you'd need to initialize a signal from the server on page load, it shouldn't be a signal.**
Render the correct HTML to begin with.

**The danger zone:** Using `datastar-patch-signals` to push `{user: {name:..., role:...}}` from
the server means you've built a JSON API and you're back in SPA territory. Send HTML.

---

## Communication Pattern

```
Browser                              Worker (Rust/CF)
──────                               ────────────────
data-on:click="@post('/action')"
  │
  ├── POST /action ────────────────▶  deserialize signals from body
  │   body: {"fieldA": "x", ...}      render HTML via Askama
  │                                   stream SSE response
  │◀── text/event-stream ─────────────
       event: datastar-patch-elements
       data: elements <div id="result">...</div>
```

No JSON API. No client-side routing. No state synchronization problem.

---

## Installation

```html
<!-- CDN -->
<script type="module"
  src="https://cdn.jsdelivr.net/gh/starfederation/datastar@v1.0.0-RC.8/bundles/datastar.js">
</script>

<!-- Self-hosted (recommended for production) -->
<script type="module" src="/static/datastar.js"></script>
```

---

## data-* Attribute Reference

### Signal Management

```html
<!-- Initialize signals -->
<div data-signals="{count: 0, name: '', isOpen: false}">
<div data-signals:count="0">                        <!-- single signal -->

<!-- _ prefix = private, NEVER sent to server -->
<div data-signals="{userId: 42, _showModal: false}">

<!-- Two-way binding to form elements -->
<input data-bind:username />
<textarea data-bind:message></textarea>
<select data-bind:choice>...</select>

<!-- Derived read-only signal -->
<div data-computed:fullName="$first + ' ' + $last">

<!-- Signal holding a DOM element reference -->
<input data-ref:myInput />
<button data-on:click="$myInput.focus()">Focus</button>
```

**Casing:** `data-signals:my-signal` → `$mySignal` (kebab → camelCase)

### DOM Reactivity

```html
<span data-text="$count"></span>
<span data-text="$n > 0 ? 'positive' : 'zero'"></span>

<!-- Show/hide — element stays in DOM -->
<div data-show="$isLoading">Loading...</div>
<!-- Prevent FOUC: -->
<div data-show="$visible" style="display:none">Content</div>

<!-- CSS class toggle -->
<div data-class:active="$isSelected">
<div data-class="{'active': $sel, 'error': $err}">

<!-- Any attribute -->
<button data-attr:disabled="$submitting">Submit</button>
<img data-attr:src="$url || '/default.png'" />

<!-- Hide until Datastar initializes -->
<div data-cloak data-signals="{show: false}">

<!-- Skip Datastar processing for this subtree -->
<div data-ignore>third-party widget here</div>
```

### Event Handling

```html
<!-- Standard events -->
<button data-on:click="$count++">
<input data-on:input="$search = el.value">
<form data-on:submit__prevent="@post('/submit')">
<div data-on:keydown__window="$key = evt.key">

<!-- Event modifiers (double-underscore) -->
__prevent     → preventDefault()
__stop        → stopPropagation()
__window      → attach to window
__once        → fire once only
__passive     → passive listener (scroll perf)
__case.camel  → camelCase event name

<!-- Loading indicator: true while in-flight, false when done -->
<button
  data-on:click="@get('/slow')"
  data-indicator:loading
  data-attr:disabled="$loading"
>Fetch</button>
<div data-show="$loading">⏳</div>

<!-- Side effect when dependencies change -->
<div data-effect="document.body.className = $theme">
```

---

## Actions Reference

```
@get('/url')                      GET — signals as ?datastar=<json>
@post('/url')                     POST — signals as JSON body
@put('/url')
@patch('/url')
@delete('/url')

@peek($signal)                    Read without reactive subscription
@setAll(val, {include: /regex/})  Set matching signals
@toggleAll({include: /regex/})    Toggle matching boolean signals
```

**Options (second arg to backend actions):**
```js
@post('/url', {
  headers: { 'Authorization': 'Bearer ' + $token },
  contentType: 'form',          // multipart/form-data
  selector: '#my-form',
  openWhenHidden: true,         // keep SSE alive when tab hidden
  requestCancellation: 'disabled',
  filterSignals: { include: /^form\./ }
})
```

All backend actions send `Datastar-Request: true` header.
All non-`_` signals are included by default.

---

## SSE Wire Format

`Content-Type: text/event-stream` — every event block ends with `\n\n`

### Patch Elements

```
event: datastar-patch-elements
data: elements <div id="result">Updated content</div>

```

With options:
```
event: datastar-patch-elements
data: selector #target
data: mode append
data: useViewTransition true
data: elements <div>new item</div>

```

**Patch modes:**
| mode | behavior |
|------|----------|
| `morph` (default) | idiomorph diff — only changes what changed |
| `outer` | replace element including tag |
| `inner` | replace innerHTML only |
| `replace` | outerHTML replace, no morph |
| `prepend` | insert before first child |
| `append` | insert after last child |
| `before` | insert before element |
| `after` | insert after element |
| `remove` | remove element from DOM |

Multiple elements in one event:
```
event: datastar-patch-elements
data: elements <div id="header">...</div>
data: elements <div id="footer">...</div>

```

### Patch Signals

```
event: datastar-patch-signals
data: signals {loading: false, count: 42}

```

Remove a signal: set to `null`
Only-if-missing: `data: onlyIfMissing true`

### Execute Script

```
event: datastar-patch-elements
data: mode append
data: selector body
data: elements <script>console.log("from server")</script>

```

---

## Response Content Types

| Content-Type | What Datastar does |
|---|---|
| `text/event-stream` | parse and apply SSE events (primary) |
| `text/html` | morph top-level elements by ID |
| `application/json` | merge as signal patch (RFC 7396) |
| `text/javascript` | execute as script |

---

## Cloudflare Workers / Rust (worker-rs) Implementation

**No official Rust worker-rs SDK.** Build a minimal helper.

### SSE Helper (put in cf-tools)

```rust
pub struct Sse;

impl Sse {
    pub fn patch_elements(html: &str) -> String {
        format!("event: datastar-patch-elements\ndata: elements {}\n\n", html)
    }

    pub fn patch_elements_mode(selector: &str, mode: &str, html: &str) -> String {
        format!(
            "event: datastar-patch-elements\ndata: selector {}\ndata: mode {}\ndata: elements {}\n\n",
            selector, mode, html
        )
    }

    pub fn patch_signals(json: &str) -> String {
        format!("event: datastar-patch-signals\ndata: signals {}\n\n", json)
    }

    pub fn remove(selector: &str) -> String {
        format!(
            "event: datastar-patch-elements\ndata: selector {}\ndata: mode remove\ndata: elements <x></x>\n\n",
            selector
        )
    }

    /// Apply required headers to a Response
    pub fn apply_headers(resp: &mut Response) -> worker::Result<()> {
        let h = resp.headers_mut();
        h.set("Content-Type", "text/event-stream")?;
        h.set("Cache-Control", "no-cache")?;
        h.set("X-Accel-Buffering", "no")?;  // prevent CF edge buffering
        Ok(())
    }
}
```

### Streaming Response Pattern

```rust
use futures_util::stream;

async fn handle_sse(_req: Request, _ctx: RouteContext<()>) -> Result<Response> {
    let stream = stream::unfold(0u32, |i| async move {
        if i >= 10 { return None; }
        let html = format!("<div id=\"counter\">{}</div>", i);
        let event = Sse::patch_elements(&html);
        // yield delay here if needed
        Some((Ok::<Vec<u8>, Error>(event.into_bytes()), i + 1))
    });

    let mut resp = Response::from_stream(stream)?;
    Sse::apply_headers(&mut resp)?;
    Ok(resp)
}
```

### Reading Signals

```rust
#[derive(serde::Deserialize, Default)]
struct MySignals {
    #[serde(default)] query: String,
    #[serde(default)] page: u32,
}

// POST/PUT/PATCH/DELETE — signals in JSON body
let signals: MySignals = req.json().await.unwrap_or_default();

// GET — signals in ?datastar=<json> query param
let raw = req.url()?.search_params().get("datastar").unwrap_or_default();
let signals: MySignals = serde_json::from_str(&raw).unwrap_or_default();
```

### Cloudflare-Specific Notes

- `X-Accel-Buffering: no` is critical — prevents CF edge from buffering the SSE stream
- No `Connection: keep-alive` needed — CF manages this
- CPU time limits don't count I/O wait — long SSE streams are fine
- No `async_stream!` macro (Tokio dep) — use `futures_util::stream::unfold`
- DO as SSE hub: one DO instance manages subscribers for a channel, broadcasts patches to all

---

## WebSocket + Datastar Split Architecture

**Datastar is SSE-only and that's correct.** But when you have genuine binary/bidirectional
needs (audio, game ticks, WebRTC signaling), use both on separate channels:

```
Browser
  ├── WebSocket ──▶ DO  ──▶ Deepgram   (audio up — binary pipe)
  └── Datastar SSE ◀── DO              (transcript/UI patches down)
       └── @post('/session/control')   (pause/stop/mode — normal HTTP)
```

The DO bridges them. WebSocket receives audio, forwards to Deepgram. When Deepgram
returns transcript events, DO writes `datastar-patch-elements` to the SSE stream.

**The WebSocket is invisible to the UI layer.** Datastar owns all DOM updates.
The user never interacts with the WebSocket directly.

```html
<!-- Browser side — completely decoupled -->
<div id="transcript"></div>
<div id="session-status"></div>

<script>
  // Audio pipe — has nothing to do with Datastar
  const ws = new WebSocket('/session/audio');
  navigator.mediaDevices.getUserMedia({ audio: true }).then(stream => {
    const recorder = new MediaRecorder(stream);
    recorder.ondataavailable = e => ws.send(e.data);
    recorder.start(100);
  });
</script>
```

---

## Patterns

**Loading indicator**
```html
<button data-on:click="@post('/search')" data-indicator:busy
        data-attr:disabled="$busy">Search</button>
<div data-show="$busy">⏳</div>
<div id="results"></div>
```

**Optimistic UI**
```html
<button data-on:click="$count++; @post('/increment')">
  <span data-text="$count"></span>
</button>
```

**Form submission**
```html
<form data-signals="{name: '', email: ''}"
      data-on:submit__prevent="@post('/submit')">
  <input data-bind:name />
  <input data-bind:email />
  <div id="errors"></div>
  <button>Submit</button>
</form>
```

**Append to list (infinite scroll / live feed)**
```
event: datastar-patch-elements
data: selector #feed
data: mode append
data: elements <div id="item-42">New item</div>

```

---

## Anti-Patterns

❌ Sending data objects as signals instead of rendering HTML
❌ Complex logic in expressions (extract to functions or web components)  
❌ Elements without stable IDs (morphing won't work correctly)
❌ URL state (pagination, filters) in signals instead of the URL
❌ Using WebSockets for UI updates when SSE handles it fine

---

## Security

- Datastar does NOT escape values — sanitize all user data server-side before patching
- All signals from the browser are untrusted — validate like form fields
- `_` prefix is a convenience, not a security boundary
- CSRF: include tokens in signal state or request headers
- `@` actions run in sandboxed `Function()` context

---

## Quick Reference

```
Signals:     data-signals  data-bind  data-computed  data-ref
DOM:         data-text  data-show  data-class  data-attr  data-cloak  data-ignore
Events:      data-on  data-indicator  data-effect
Actions:     @get @post @put @patch @delete  @peek @setAll @toggleAll

Signal rule: $name (sent)   $_name (private, never sent)

Request:     GET  → ?datastar={"k":"v"}
             POST → {"k": "v"} body

SSE events:  datastar-patch-elements   (primary — HTML → idiomorph → DOM)
             datastar-patch-signals    (secondary — transient state only)
```
