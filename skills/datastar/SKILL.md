---
name: datastar
description: >
  Deep reference and architectural guidance for Datastar (data-star.dev) — the
  hypermedia-first frontend framework using SSE and data-* attributes. Use
  whenever the user mentions Datastar, data-star.dev, SSE HTML patching,
  idiomorph morphing, datastar-patch-elements, data-signals, data-on,
  data-indicator, Datastar Pro, Datastar Inspector, Stellar CSS, the Pro
  Bundler, or Rocket custom elements; or is building a hypermedia-driven UI
  with server-sent events. Also trigger for combining Datastar with Cloudflare
  Workers, Rust, worker-rs, Askama templates, WebSockets alongside Datastar,
  or Rocket components (ECharts, MapLibre, Globe.GL, canvas, QR codes, virtual
  scroll, headless service components, typed props). Contains the correct
  mental model (HTML patches primary, signals the exception), the full data-*
  attribute reference (21 free + 10 Pro), the full action reference (8 core +
  3 Pro), the SSE wire format, Cloudflare-specific patterns, and the shipping
  Rocket Pro API — `rocket(tag, { props, setup, onFirstRender, render, mode,
  renderOnPropChange, manifest })` with fluent codec props, setup-context
  helpers ($/$$/effect/cleanup/actions/emit/apply/observeProps), html/svg
  tagged templates, data-if/data-for directives, data-ref:* refs, shadow DOM
  modes, and component-local actions. Includes pointers into the local
  datastar-pro source, datastar-examples corpus, and data-star.dev doc-site.
  Covers WebSocket+SSE split architecture and the Datastar Inspector.
---

# Datastar Skill

Datastar — hypermedia-first frontend framework (data-star.dev).
Datastar core is currently v1.0.0-beta.11+. Datastar Pro is currently v1.0.0
(Rocket beta.1 — JavaScript call-based API; the previous template-based
`<template data-rocket:*>` API was alpha.7-only and has been removed).

---

## Core Mental Model — Read This First

**HTML patches are the primary mechanism. Signals are the exception.**

The server drives the DOM. Every meaningful state change starts as a backend
render and arrives as a `datastar-patch-elements` SSE event. Idiomorph (when
the server picks `mode: morph`, the historic default) or direct outerHTML/
innerHTML replacement (when it picks `mode: outer`/`inner`) merges it into the
existing DOM — preserving focus, scroll position, CSS transitions, input state.

Signals exist only for:
- Transient UI state with no server representation (`_showModal`, `_dropdownOpen`)
- Loading indicators (`data-indicator:loading`)
- Form field values in-flight before submission
- Optimistic UI before server confirms

**If you'd need to initialize a signal from the server on page load, it shouldn't
be a signal.** Render the correct HTML to begin with.

**The danger zone:** Using `datastar-patch-signals` to push `{user: {name:..., role:...}}`
from the server means you've built a JSON API and you're back in SPA territory.
Send HTML.

---

## Local Source & Doc Map (read these for ground truth)

When something in this skill conflicts with reality, the canonical sources are:

| Source | Path / URL | What it is |
|---|---|---|
| **Pro source repo** | `~/Projects/github/datastar-pro/` | The licensed Pro code (private, owned). Working dir of this skill's home project. |
| **Pro library** | `~/Projects/github/datastar-pro/library/src/pro/` | The 10 Pro attributes, 3 Pro actions, full Rocket runtime |
| **Pro Rocket runtime** | `~/Projects/github/datastar-pro/library/src/pro/rocket/runtime.ts` | The `rocket()` function, `SetupContext`, `FirstUpdateContext`, `RenderContext` types — read this for ground-truth Rocket API |
| **Pro Rocket codecs** | `~/Projects/github/datastar-pro/library/src/pro/rocket/codecs.ts` | Fluent codec API: `string.trim.maxLength(50)`, `number.clamp(0,100).step(5)`, `array(codec)`, `object({...})`, `oneOf(...)` |
| **Pro Rocket conditional** | `~/Projects/github/datastar-pro/library/src/pro/rocket/conditional.ts` | `data-if`/`data-else-if`/`data-else` template directives |
| **Pro Rocket for** | `~/Projects/github/datastar-pro/library/src/pro/rocket/for.ts` | `data-for` template directive |
| **Pro Rocket template** | `~/Projects/github/datastar-pro/library/src/pro/rocket/template.ts` | `html` / `svg` tagged template literals |
| **Datastar Inspector** | `~/Projects/github/datastar-pro/webcomponents/datastar-inspector/src/index.ts` | The `<datastar-inspector>` web component |
| **Pro README** | `~/Projects/github/datastar-pro/README.md` | Top-level summary — links to docs and download |
| **Rocket changelog** | `~/Projects/github/datastar-pro/CHANGELOG-ROCKET.md` | Per-release breaking changes (alpha → beta) |
| **Examples corpus** | `~/Projects/EveryGoodWork/temp/datastar-examples/` | 41 example `.md` files mirrored from data-star.dev/examples |
| **Live docs** | https://data-star.dev/ | Authoritative published docs and example pages |

**Pro source layout (file map):**

```
library/src/pro/
├── attributes/
│   ├── animate.ts             ← data-animate
│   ├── customValidity.ts      ← data-custom-validity
│   ├── matchMedia.ts          ← data-match-media
│   ├── onRaf.ts               ← data-on-raf
│   ├── onResize.ts            ← data-on-resize
│   ├── persist.ts             ← data-persist
│   ├── queryString.ts         ← data-query-string
│   ├── replaceUrl.ts          ← data-replace-url
│   ├── scrollIntoView.ts      ← data-scroll-into-view
│   └── viewTransition.ts      ← data-view-transition
├── actions/
│   ├── clipboard.ts           ← @clipboard
│   ├── fit.ts                 ← @fit
│   └── intl.ts                ← @intl
└── rocket/
    ├── index.ts               ← public exports: { rocket, publishRocketManifests, createCodec, ... }
    ├── runtime.ts             ← rocket() + custom-element class + lifecycle
    ├── codecs.ts              ← prop codec registry (string, number, bool, date, json, js, bin, array, object, oneOf)
    ├── template.ts            ← html`...` / svg`...` tagged literals
    ├── conditional.ts         ← data-if / data-else-if / data-else
    └── for.ts                 ← data-for

webcomponents/
└── datastar-inspector/
    └── src/index.ts           ← <datastar-inspector> dev tool (signals + events + persisted)
```

---

## Documentation Site Map (data-star.dev)

| Section | URL | What's there |
|---|---|---|
| Home | `/` | Landing page. Top nav: Guide, Reference, Examples, Essays, Pro, Shop |
| **Guide** | `/guide/getting_started` | CDN install, first attributes, SSE basics |
| | `/guide/reactive_signals` | Signal model, two-way binding, computed, text/class/attribute binding |
| | `/guide/datastar_expressions` | Expression syntax, `el`/`evt`, JS operators, "props down, events up" |
| | `/guide/backend_requests` | Signal transmission rules, SSE streaming, `@get`/`@post`/`@put`/`@patch`/`@delete` |
| | `/guide/the_tao_of_datastar` | Design philosophy: backend owns state, sparing signals |
| **Reference** | `/reference/attributes` | All 21 free + 10 Pro `data-*` attributes (canonical list — see attribute reference below) |
| | `/reference/actions` | All 8 core + 3 Pro `@actions` (canonical list — see action reference below) |
| | `/reference/sse_events` | SSE wire format: `datastar-patch-elements`, `datastar-patch-signals` |
| | `/reference/rocket` | **Rocket API reference (Pro)** — definitive spec for `rocket(tag, options)` |
| | `/reference/sdks` | Backend SDK list: Python, Go, TypeScript, Rust, PHP, Ruby, Java, Kotlin, .NET, Clojure, Scala, Haskell, Unison |
| | `/reference/security` | XSS, CSP `unsafe-eval` requirement, sensitive-data warnings |
| **Examples** | `/examples` | 27 free + 16 Pro example pages (mirror of `~/Projects/EveryGoodWork/temp/datastar-examples/`) |
| | `/examples/<slug>` | Individual example walkthrough |
| **Essays** | `/essays` | Design rationale, "htmx Sucks", "V1 and Beyond", "Greedy Developer?", etc. |
| **Pro** | `/pro` | Pro feature overview, pricing (Solo $349 / Team $1,299 / Enterprise) |
| | `/pro/sign-in` | GitHub OAuth gate for Pro tooling |
| | `/pro/bundler` | Custom-bundle generator (auth-required) |
| | `/pro/download` | Pro bundle downloads (auth-required) |
| Repo | `https://github.com/starfederation/datastar/` | Core (MIT-licensed) repo |
| Pro repo | `https://github.com/starfederation/datastar-pro/` | Pro (commercial) repo — license required |
| Discord | `https://discord.gg/bnRNgZjgPh` | Community + Pro support |

**Notes:**
- There is **no `/reference/plugins` page**. Plugin extension is via `action({...})` and `attribute({...})` registrations (see Custom Plugins section below).
- The Inspector, Stellar CSS docs, and Bundler are behind GitHub-OAuth auth on data-star.dev.

---

## Examples Catalog (local: `~/Projects/EveryGoodWork/temp/datastar-examples/`)

41 example `.md` files mirroring the published `/examples/<slug>` pages.
Read by feature when you need a concrete pattern reference.

### Free / core (27 files)

| File | What it teaches |
|---|---|
| `active_search.md` | Real-time search with `data-bind` + debounced `@get()` |
| `animations.md` | CSS transitions + View Transition API integration |
| `bad_apple.md` | High-rate SSE streaming into a single element |
| `bulk_update.md` | Multi-select checkboxes + `@put()` for bulk ops |
| `click_to_edit.md` | Inline edit-toggle without a separate route |
| `click_to_load.md` | Pagination via click-triggered SSE fragments |
| `custom_event.md` | `CustomEvent` between page and web components |
| `custom_plugin.md` | Custom action + attribute plugin registration |
| `dbmon.md` | High-frequency live-table SSE benchmark |
| `delete_row.md` | Optimistic delete with `@delete()` + confirmation guard |
| `edit_row.md` | Inline row edit form + `@patch()` |
| `event_bubbling.md` | Event delegation with `evt.target.closest(...)` |
| `file_upload.md` | Base64-encoded file uploads in JSON body |
| `form_data.md` | `contentType: 'form'` for multipart submissions |
| `infinite_scroll.md` | `data-on-intersect` sentinel-driven pagination |
| `inline_validation.md` | Real-time field validation via server round-trip |
| `lazy_load.md` | `data-init` + `@get()` deferred fragment load |
| `lazy_tabs.md` | Tab UI with on-demand panel fetch |
| `on_signal_patch.md` | `data-on-signal-patch` reactive listeners |
| `progress_bar.md` | SSE-streamed progress signal |
| `progressive_load.md` | Sequential prioritized fragment loads |
| `sortable.md` | SortableJS drag-drop + `@put()` reorder persist |
| `svg_morphing.md` | SVG namespace + element morphing |
| `templ_counter.md` | Server-rendered (Templ/Go) counter with signal updates |
| `title_update.md` | `document.title` updates via signal patches |
| `todomvc.md` | Full TodoMVC reference implementation |
| `web_component.md` | Two-way binding with native web components |

### Pro non-Rocket (1 file)

| File | What it teaches |
|---|---|
| `match_media.md` | `data-match-media:<name>` for responsive signal binding |

### Pro Rocket components (13 files)

| File | What it teaches |
|---|---|
| `rocket_counter.md` | Minimum MVP: `props`, `$$.count`, `setup`, `render` |
| `rocket_copy_button.md` | `@clipboard` action + `setTimeout` + `cleanup` |
| `rocket_conditional.md` | `data-if`/`data-else-if`/`data-else` mount/unmount; shadow `:host` |
| `rocket_password_strength.md` | Setup-only computed; nested mapped lists |
| `rocket_qr_code.md` | `renderOnPropChange: false` + library (qr-creator) ownership pattern |
| `rocket_echarts.md` | ECharts ESM import; `observeProps` per-prop update vs re-init |
| `rocket_starfield.md` | Canvas 2D + `requestAnimationFrame` + `ResizeObserver` |
| `rocket_globe.md` | Globe.GL + stringify-compare guard for heavy arcs |
| `rocket_openfreemap.md` | MapLibre/Leaflet + markers + cluster rebuild on config change |
| `rocket_flow.md` | **DEEP DIVE** — multi-component graph editor; declarative-child custom elements; viewport pan/zoom; pointer-capture drag; `serverUpdateTime` reconciliation pulse; rAF schedulers; `host.rocketInstanceId` ID scoping; SVG content projection; bezier edge routing; keyboard shortcuts (see Deep Dive section below) |
| `rocket_letter_stream.md` | Nested `data-for` with named aliases (`i`, `j`, `k`) |
| `rocket_projection.md` | Slot projection between light/shadow modes; `apply()` rescoping |
| `rocket_virtual_scroll.md` | Component-initiated SSE fetch; block recycling |

---

## Client-Side Signal Reactivity Gotchas (Datastar Pro, learned the hard way)

Datastar's proxy-based reactivity has **three asymmetries** that trip up
client-side code operating on nested signals (maps, arrays). Server-side
merge-patch hits them too, but because merge-patch always *mutates* existing
proxies in place these patterns rarely show up there. Client code often
*replaces* top-level values (`root._foo = {...}`) and that's where things break.

### 1. Top-level replacement orphans deep-path subscriptions

```js
// BROKEN — template binds to $_drag_state[id].x; client replaces the whole map.
// Template effect is subscribed on the OLD inner proxy's `.x` — new proxy has no
// listeners. Template never re-evaluates; items freeze at last rendered value.
root._drag_state = { ...root._drag_state, [id]: { x: newX, y: newY, rz: 0 } };
```

```js
// WORKS — mutate nested properties in place; existing subscribers fire.
root._drag_state[id].x = newX;
root._drag_state[id].y = newY;
```

**Pattern:** mirror the server's merge-patch mutation style. Delete keys you
want to drop, assign keys you want to add, never replace the whole top-level map.

```js
// Replacement-free "set" helper:
const setSelection = (nextMap) => {
  for (const k of Object.keys(root._selection)) {
    if (!nextMap[k]) delete root._selection[k];
  }
  for (const k of Object.keys(nextMap)) {
    if (!root._selection[k]) root._selection[k] = true;
  }
};
```

### 2. `ownKeys` trap fires on adds but NOT on deletes

```html
<!-- BROKEN — `Object.keys(...).length` subscribes via the ownKeys trap.
     Adding keys (setting properties) fires the subscription; DELETING keys
     does not. After a group-selection shrinks by deletion, this expression
     stays stuck at the old length. -->
<g data-show="Object.keys($_selection).length > 1">
```

**Pattern:** maintain a parallel flat-scalar size signal that you write on every
mutation. Scalar assignments always fire subscribers cleanly.

```js
// Maintain alongside $_selection writes:
root._selection_size = Object.keys(root._selection).length;
```

```html
<!-- WORKS — scalar read, fires on every assignment. -->
<g data-show="$_selection_size > 1">
```

### 3. Property-access (`get` trap) doesn't subscribe keys that didn't exist at first read

```html
<!-- BROKEN — when this binding first evaluated, $_selection['A'] was undefined.
     Datastar's get trap doesn't register a subscription for "key A when it
     becomes defined later". When you later `root._selection.A = true`, the
     binding doesn't re-fire. Item A never gets the class. -->
<g data-class:multi-selected="!!$_selection['A']">
```

This is the silent killer: the FIRST selected item often works (it was selected
at some point in the past, subscription got registered then). Subsequent
additions don't light up.

**Pattern:** use a top-level array and `.indexOf(id) >= 0` instead of
deep-property lookup. Array writes fire subscribers for every reader on every
replacement.

```html
<!-- WORKS — reads $_selected_order at the top level. Every array assignment
     fires every subscriber; .indexOf runs against the fresh value. -->
<g data-class:multi-selected="$_selected_order.indexOf('A') >= 0">
```

```js
// Replace the whole order array to trigger reactivity:
root._selected_order = [...ids];
```

### Summary: when to use which pattern

| Shape you need | Write pattern | Template read pattern |
|---|---|---|
| Scalar bool/number/string | Direct assignment (`root._flag = true`) | Direct (`$_flag`) |
| Nested map, stable schema (e.g. `$items[id].x`) | Mutate leaves in place (`root._items[id].x = n`) | Deep path (`$items[id].x`) |
| Dynamic key set (marking membership) | Mutate keys + maintain parallel size + ordered-list scalars | `$_order_list.indexOf(id) >= 0`, `$_size > 1` |
| Array-based list | Replace whole array (`root._list = [...next]`) | Top-level access (`$_list.length`, `$_list.indexOf(x)`) |

**Mental model:** Datastar's proxy subscriptions are *established at read time,
per access path*. Reads that never happened establish no subscriptions. Writes
that bypass the read path (outer replacement, key additions) can silently miss
subscribers downstream. When in doubt, mirror the server's merge-patch mutation
pattern and keep a top-level scalar "version" or "size" signal that every
binding can read.

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
<!-- Free / core via CDN -->
<script type="module"
  src="https://cdn.jsdelivr.net/gh/starfederation/datastar/bundles/datastar.js">
</script>

<!-- Self-hosted (recommended for production) -->
<script type="module" src="/static/datastar.js"></script>
```

Core bundle is ~12 KiB minified.

## ⚠️ Critical: ES Module URL Identity — Bare Paths Only

**This trap hangs the browser hard. Read before adding ANY page that loads
datastar-pro alongside component modules that import from it.**

ES modules are identified by their full URL. The browser keys the module
graph by URL, so `/js/datastar-pro.js?v=0.1.544` and `/js/datastar-pro.js`
are TWO DIFFERENT MODULES. If a page loads one URL via a `<script type="module">`
tag and a component module imports the other, the browser fetches and
evaluates **two complete copies of datastar-pro**. That means:

- **Two plugin registries** — every `data-on`, `data-bind`, `data-style`,
  etc. registered twice
- **Two `setTimeout(0)` initial scans** — both call `apply(documentElement)`
  on the same DOM
- **Two MutationObservers** — each reacts to the OTHER engine's bindings
- **Two separate `removals` cleanup maps** — neither knows the other
  already bound; both keep adding listeners
- **Two distinct `root` signal proxies** — buttons compiled by engine A
  write to its store; engine B's effects watching its own store never see
  the change

The two engines race over the same DOM, cascading through MutationObserver
events, infinite-looping before any `connectedCallback` finishes. The page
hangs so hard that chrome-devtools cannot connect (`Target closed`).
Symptoms look like a runaway `effect()` but no profiling tool can grab a
stack trace.

### The rule

**Use the bare path on the script tag for the engine AND for any module
that imports from it. NO `?v=` cache-bust query.**

```html
<!-- ✓ CORRECT -->
<script type="module" src="/js/datastar-pro.js"></script>
<script type="module" src="/js/my-component.js"></script>
```

```js
// my-component.js — import path matches the script-tag path exactly
import { rocket } from '/js/datastar-pro.js'
```

```html
<!-- ✗ BROKEN — query mismatch creates a second module instance -->
<script type="module" src="/js/datastar-pro.js?v=1.2.3"></script>
<script type="module" src="/js/my-component.js?v=1.2.3"></script>
```

```js
// my-component.js — bare import doesn't match the ?v=1.2.3 script tag
import { rocket } from '/js/datastar-pro.js'   // ← different URL = 2nd engine
```

### Why ES modules don't need cache-bust queries anyway

When you change `datastar-pro.js`, the file's content changes — but its URL
stays the same. The browser HTTP cache can be invalidated by setting
appropriate `Cache-Control` headers (or by physically renaming the file).
Adding `?v=…` works for normal `<link>` / `<img>` / non-module scripts
because each request is independent. For ES modules, the import statement
hardcodes the URL at write time and CANNOT pick up your `?v=…` template.
So either:

- The script tag and import path agree (no `?v=`) and updates rely on HTTP
  cache headers / hashed filenames — **the recommended path**
- You use an **import map** to indirect a bare specifier through to a
  versioned URL:

  ```html
  <script type="importmap">
  { "imports": { "datastar-pro": "/js/datastar-pro.js?v=1.2.3" } }
  </script>
  <script type="module" src="/js/datastar-pro.js?v=1.2.3"></script>
  ```

  ```js
  import { rocket } from 'datastar-pro'   // resolves via the import map
  ```

The import map is the only way to combine ES modules with URL cache-busters.
For most apps, the bare path + content-hashed CSS / etc. is simpler.

### Diagnosing the hang

The hang is too fast for chrome-devtools to connect, and the `connectedCallback`
never reaches its `console.log`. Static analysis of the engine source won't
reveal it. The methodology that finds it:

1. Build a static-server diagnostic harness (`/tmp/<name>/` with `python3 -m
   http.server`) that serves a copy of the deployed `datastar-pro.js` and
   the failing page.
2. Single-variable bisection: replicate the failing page; toggle ONE variable
   at a time across iterations. The first version that hangs identifies the
   trigger.
3. For this trap specifically: load `/js/datastar-pro.js?v=…` on the script
   tag while `import` says `/js/datastar-pro.js` — hangs in seconds. Drop
   the query — works in 22ms.

### Reference incident

`loadout` v0.1.540 / v0.1.542 / v0.1.544 — three Rocket-component wrap
attempts all hung the browser. Each attempt rewrote the DOM shape thinking
that was the bug. Every iteration carried `<script type="module"
src="/js/datastar-pro.js?v={{ version }}">` while the component module's
`import { rocket } from '/js/datastar-pro.js'` was bare. Two engines fighting
on the DOM. v0.1.546 dropped the query and the same Rocket-component code
loads in ~30ms.

The same warning was already in `loadout/templates/project.html:9-12`
("Bare path (no `?v=`). Browsers key the module graph by URL — a cache-bust
query here would register a separate module instance from the one our
helpers import, leaving two Datastar engines on the same DOM.") — a previous
person had hit it on the canvas page and documented it for the next person.
**Reading that warning before iterating would have saved hours.**

## Datastar Pro — Local Build

Source repo: `~/Projects/github/datastar-pro/` (licensed, private)

The Pro repo no longer ships pre-built JS — build from source. The Pro bundle
includes the core framework, all 10 Pro attributes, all 3 Pro actions, and
Rocket. There is no separate `datastar-pro-rocket.js`.

```bash
cd ~/Projects/github/datastar-pro
npx esbuild library/src/bundles/datastar-pro.ts --bundle --format=esm --minify \
  --define:ALIAS=null \
  --banner:js="// Datastar Pro – DATASTAR PRO MAY ONLY BE USED WITH A VALID LICENSE!" \
  --tsconfig=library/tsconfig.json --outfile=../../EveryGoodWork/creator/static/datastar-pro.js
```

**CRITICAL: `--define:ALIAS=null` is required.** `ALIAS` is a build-time constant
declared in `globals.d.ts` (`declare const ALIAS: string | null`). Without
`--define`, esbuild emits a bare `ALIAS` reference that throws `ReferenceError`
at runtime, killing Datastar entirely. The aliased bundle (`datastar-pro-aliased.ts`)
would use `--define:ALIAS=\"ds\"` for `data-ds-*` attributes.

For the Datastar Inspector web component, build separately:

```bash
cd ~/Projects/github/datastar-pro
npx esbuild webcomponents/datastar-inspector/src/index.ts --bundle --format=esm \
  --minify --tsconfig=webcomponents/datastar-inspector/tsconfig.json \
  --outfile=path/to/your/static/datastar-inspector.js
```

For pre-built bundles with no build step, sign in at
https://data-star.dev/pro/download (GitHub OAuth) — Pro tier required.

---

## data-* Attribute Reference (Free / Core)

21 attributes. Authoritative reference: `https://data-star.dev/reference/attributes`.

### Signal Management

```html
<!-- Initialize signals -->
<div data-signals="{count: 0, name: '', isOpen: false}">
<div data-signals:count="0">                        <!-- single signal -->

<!-- _ prefix = private, NEVER sent to server -->
<div data-signals="{userId: 42, _showModal: false}">

<!-- Modifier: only set if missing (preserves user-modified values) -->
<div data-signals__ifmissing="{count: 0}">

<!-- Two-way binding to form elements -->
<input data-bind:username />
<textarea data-bind:message></textarea>
<select data-bind:choice>...</select>

<!-- Modifiers: __prop (use property not value), __event (which event), __case -->
<input data-bind__event.input="username" />

<!-- Value form for nested paths (no `$` prefix — value is a literal signal path) -->
<input data-bind="form_data.email" />                 <!-- writes to $form_data.email -->
<input data-bind="$form_data.email" />                <!-- WRONG — creates a signal literally named "$form_data" -->

<!-- Bind events differ by element type (from bind.ts):
     - input[type=number|range]: 'input'
     - input[type=checkbox|radio|file]: 'change'
     - input (default), textarea: 'input'
     - select (single): 'change' only        ← NOT input
     - select[multiple]: 'change'
     A form-level `data-on:input__debounce` still fires on bubbled select input
     events, but the bind sync itself only happens on `change`. -->

<!-- Derived read-only signal — must be pure, no side effects -->
<div data-computed:fullName="$first + ' ' + $last">

<!-- Signal holding a DOM element reference (persists across patches) -->
<input data-ref:myInput />
<button data-on:click="$myInput.focus()">Focus</button>

<!-- Debug: dump all signals as JSON. __terse for compact format. -->
<pre data-json-signals></pre>
<pre data-json-signals="{include: /^form/, exclude: /password/}"></pre>
```

**Casing:** `data-signals:my-signal` → `$mySignal` (kebab → camelCase by default).
Override with `__case.kebab|camel|snake|pascal` modifier.

**Reserved:** Signal names cannot contain double underscores (`__` is the
modifier prefix).

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

<!-- Inline style: falsy reverts to original inline style -->
<div data-style:color="$theme === 'dark' ? '#fff' : null">
<div data-style="{'color': $fg, 'background-color': $bg}">

<!-- Hide until Datastar initializes -->
<div data-cloak data-signals="{show: false}">

<!-- Skip Datastar processing for this subtree (or just self with __self) -->
<div data-ignore>third-party widget here</div>
<div data-ignore__self>self ignored, children processed</div>

<!-- Skip idiomorph diff for this subtree — preserves imperative DOM
     (canvas/WebGL/3rd-party widgets). Needed inside Rocket components whose
     library (ECharts, MapLibre, Globe.GL, Three.js) owns its own DOM. -->
<canvas data-ignore-morph></canvas>

<!-- Preserve specific attributes during morph (preserves checked/focus/etc) -->
<input data-preserve-attr="checked focus" />
```

### Event Handling

```html
<!-- Standard events -->
<button data-on:click="$count++">
<input data-on:input="$search = el.value">
<form data-on:submit__prevent="@post('/submit')">  <!-- submit auto-prevents -->
<div data-on:keydown__window="$key = evt.key">

<!-- Event modifiers (double-underscore) -->
__prevent              → preventDefault()
__stop                 → stopPropagation()
__window               → attach to window
__document             → attach to document
__outside              → fire only when target is outside this element
__once                 → fire once only
__passive              → passive listener (scroll perf)
__capture              → use capture phase
__debounce.500ms       → debounce
__throttle.250ms       → throttle
__delay.100ms          → defer
__case.camel           → camelCase event name
__viewtransition       → wrap handler in document.startViewTransition

<!-- Loading indicator: true while in-flight, false when done -->
<!-- IMPORTANT: data-indicator MUST appear BEFORE the @get/@post that uses it -->
<button
  data-indicator:loading
  data-on:click="@get('/slow')"
  data-attr:disabled="$loading"
>Fetch</button>
<div data-show="$loading">⏳</div>

<!-- Side effect when dependencies change -->
<div data-effect="document.body.className = $theme">

<!-- One-time init (runs on load AND whenever attribute is patched in) -->
<div data-init="@get('/refresh')"></div>
<!-- Modifiers: __delay.500ms (defer), __viewtransition -->

<!-- Intersection Observer — runs when entering/exiting viewport -->
<div data-on-intersect="@get('/load-more')"></div>
<!-- Modifiers: __once, __exit (on leaving), __half (50% visible),
     __full (100% visible), __threshold.25 (custom %), __delay/__debounce/__throttle -->

<!-- Periodic execution (default 1000ms) -->
<div data-on-interval__duration.500ms="@get('/poll')"></div>
<!-- Modifier: __leading runs immediately before waiting interval -->

<!-- React to ANY signal patching — pair with patch-filter -->
<div data-on-signal-patch="console.log('signal changed:', patch)"
     data-on-signal-patch-filter="{include: /^form\./, exclude: /password/}"></div>
```

**There is NO `data-on:load`.** Use `data-init` for "run on element load."

---

## Actions Reference (Core)

8 core actions. Authoritative reference: `https://data-star.dev/reference/actions`.

### Synchronous helpers (3)

```
@peek(callable)                   Read signals without subscribing the caller
@setAll(value, {include, exclude}) Set all matching signals to value
@toggleAll({include, exclude})     Flip all matching boolean signals
```

### Backend actions (5)

```
@get('/url', options)             GET — signals as ?datastar=<json> query param
@post('/url', options)            POST — signals as JSON body
@put('/url', options)
@patch('/url', options)
@delete('/url', options)
```

All backend actions:
- Send the `Datastar-Request: true` header automatically
- Include all non-`_`-prefixed signals by default (filter via `filterSignals`)
- Auto-detect response Content-Type and dispatch accordingly (see "Response Content Types" below)

### Backend action options (full reference)

```js
@post('/url', {
  // Transmission
  contentType: 'json' | 'form',          // default 'json'; 'form' = multipart/form-data
  filterSignals: { include: /regex/, exclude: /regex/ },  // default exclude /(^_|\._)/
  selector: '#my-form',                  // CSS selector for form serialization
  payload: { /* override entire body */ }, // bypass signal transmission

  // Headers
  headers: { 'Authorization': 'Bearer ' + $token },

  // SSE behavior
  openWhenHidden: true,                  // GET defaults false; mutations default true

  // Retry
  retry: 'auto' | 'error' | 'always' | 'never',  // default 'auto'
  retryInterval: 1000,                   // ms before first retry
  retryScaler: 2,                        // exponential backoff multiplier
  retryMaxWait: 30000,                   // ms cap per retry
  retryMaxCount: 10,                     // max attempts

  // Cancellation
  requestCancellation: 'auto' | 'cleanup' | 'disabled' | abortController,
  // 'auto'    = new request on same element cancels old
  // 'cleanup' = also cancel on attribute removal
  // 'disabled' = no auto-cancellation
})
```

**Element-scoped cancellation:** Concurrent requests on *different* elements
do not cancel each other. Same-element requests do (under `'auto'`).

**Fetch lifecycle events** — every backend action dispatches a `datastar-fetch`
CustomEvent on the triggering element with `detail.type` of:
- `started` — request initiated
- `finished` — request completed
- `error` — network/processing error
- `retrying` — retry attempt
- `retries-failed` — all retries exhausted

---

## SSE Wire Format

`Content-Type: text/event-stream` — every event block ends with `\n\n`.
Two event types: `datastar-patch-elements` and `datastar-patch-signals`.

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
| `outer` (default) | Replace target's outer HTML. Idiomorph diff applied — preserves focus/scroll/state where IDs match. |
| `inner` | Morph the innerHTML — outer tag preserved. |
| `replace` | Hard outerHTML replace, no morph. |
| `prepend` | Insert before first child. |
| `append` | Insert after last child. |
| `before` | Insert before target. |
| `after` | Insert after target. |
| `remove` | Remove target from DOM (omit `data: elements`, or send `<x></x>` placeholder). |

**Selector:** If omitted, Datastar matches by top-level element ID.
**ID stability is critical** — place IDs on top-level patch targets AND on
internal stateful elements (inputs, scrollable containers) so morph preserves
their state across patches.

**Namespace** (optional): `data: namespace svg` or `data: namespace mathml`
when patching XML-namespaced content.

**View transitions:** `data: useViewTransition true` enables the View
Transition API for animated patches.

Multiple elements in one event:
```
event: datastar-patch-elements
data: selector #header
data: elements <div id="header">...</div>
data: elements <div id="footer">...</div>

```

### Patch Signals

```
event: datastar-patch-signals
data: signals {loading: false, count: 42}

```

- Set a signal value to `null` to **remove** it.
- `data: onlyIfMissing true` — only patch signals that don't exist yet
  (useful for initial seed data without overwriting user state).

### Execute Script (Server-Driven JS)

There is **no `datastar-execute-script` event type**. Execute server-driven JS
by appending a `<script>` element via `patch-elements`. Use
`data-effect="el.remove()"` for self-cleanup:

```
event: datastar-patch-elements
data: selector body
data: mode append
data: elements <script data-effect="el.remove()">window.history.replaceState({},'','/new-url')</script>

```

**The self-removing script pattern** — proven in CARM production for one-shot
side effects:

```rust
acc.add_event(
    sse::patch_elements(format!(
        r#"<script data-effect="el.remove()">window.history.replaceState({{}},'','/v2/{content_id}')</script>"#
    )).selector("body").mode(PatchMode::Append),
);
```

Use this for one-shot operations (URL updates after save, localStorage cleanup,
focus management). Do NOT use for reactive/continuous state — use
`data-replace-url` for that (see Pro Attributes section).

---

## Response Content Types

| Content-Type | What Datastar does |
|---|---|
| `text/event-stream` | Parse and apply SSE events (primary) |
| `text/html` | Morph top-level elements by ID. Honors `datastar-selector` / `datastar-mode` / `datastar-use-view-transition` response headers. |
| `application/json` | Merge as signal patch (RFC 7396) |
| `text/javascript` | Execute as script |

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

**Datastar is SSE-only and that's correct.** But when you have genuine binary/
bidirectional needs (audio, game ticks, WebRTC signaling), use both on
separate channels:

```
Browser
  ├── WebSocket ──▶ DO  ──▶ Deepgram   (audio up — binary pipe)
  └── Datastar SSE ◀── DO              (transcript/UI patches down)
       └── @post('/session/control')   (pause/stop/mode — normal HTTP)
```

The DO bridges them. WebSocket receives audio, forwards to Deepgram. When
Deepgram returns transcript events, DO writes `datastar-patch-elements` to the
SSE stream.

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
<button data-indicator:busy
        data-on:click="@post('/search')"
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

**Auto-save form with HTML5 validation (the canonical pattern)**

For schema-driven forms with debounced auto-save, lean on browser primitives. Do NOT invent
custom `_sending` / `_msg` / `_err` signal maps — Datastar already provides everything.

```html
<form data-signals="{ form_data: {{ data_json }} }"
      data-indicator="form_sending"
      data-on:input__debounce.1000ms="
          if (!el.checkValidity()) return;
          @post('/save')
      ">
  <label>
    <span>Stomach (in)</span>
    <input type="number" min="24" max="70" step="0.25" required
           data-bind="form_data.stomach_in"
           data-on:input="el.nextElementSibling.textContent =
                          el.validity.valid ? '' : el.validationMessage">
    <span class="field-msg" aria-live="polite"></span>
  </label>
</form>

<div data-show="$form_sending">Saving…</div>
```

The five primitives doing the work:

1. **`data-indicator="form_sending"`** — framework auto-sets `true` on STARTED, `false` on FINISHED,
   and clears on element morph cleanup. Eliminates stuck-Saving bugs from manual `$flag = true; @post()`
   patterns where SSE morphs interleave with the response.
2. **`if (!el.checkValidity()) return;`** — gate the auto-save POST on form validity. When invalid,
   no request goes out, no morph clobbers the error message, and the red `:invalid` border + inline
   message persist until the user fixes it. Pair with HTML5 attrs (`min`, `max`, `pattern`, `required`).
3. **`el.validationMessage` mirror** — there is NO `data-validation-message` built-in attribute.
   The native pattern is a one-line `data-on:input` that writes the browser's localized message
   into a sibling `<span>`. Empty string clears it. CSS `.field-msg:empty { display: none }` hides
   the gap when there's nothing to show.
4. **`data-bind="form_data.field"`** — value form for nested paths, no `$` prefix.
5. **Server response** — `patch-elements` (mode=outer) morphs the form chrome + `patch-signals`
   overwrites `form_data` with the server-canonical state (defends against /run-script-style
   bypasses that skip HTML5 validation). Server should NOT touch the indicator signal —
   `data-indicator` owns its lifecycle.

**Server side: brutal + typed.** Deserialize into a typed struct, `normalize()` to clamp/canonicalize
hostile values (the 1% of writes from scripts that bypass the browser). Never trust the wire even
though the browser was nice. The brutal-server / nice-client split keeps validation from round-tripping.

**Why not a manual flag?** Two failure modes seen in production: (1) the manual `$_sending = true`
gets stuck because the `patch-signals` clearing it loses to a morph that re-creates the indicator
element, and (2) the user's "this is not nextjs" reaction to gratuitous client signal state.
`data-indicator` is the canonical answer.

### ⚠️ Trap: `data-on:focus="el.select()"` + autofill = Chromium CPU lockup

**Do NOT add `data-on:focus="...el.select()..."` to inputs in auto-save forms.** This is not in
the canonical pattern above for a reason — it's a UX nicety (tap-to-replace) that locks up
the browser on Chromium when password managers (Proton Pass, 1Password, LastPass) interact
with the form.

The loop:
1. Autofill writes a value (`input` event with `isTrusted=false`)
2. Password manager calls `element.focus()` programmatically as part of its post-fill
   "stabilize" pass to verify the value stuck
3. Our `data-on:focus="setTimeout(() => el.select(), 0)"` fires — selects all text
4. `el.select()` fires a `selectionchange` event
5. Password manager's MutationObserver catches it, interprets it as "site is interfering
   with my fill", reasserts focus
6. Loop. CPU at 100%, browser locks, tab kill required.

**The naive guard does NOT work on Chromium:**

```html
<!-- BROKEN — Chrome reports isTrusted=true on programmatic .focus() calls
     made from inside trusted-event handler context, so this guard
     filters nothing and the loop fires anyway. Verified in loadout #156
     traces against ProtonPass on Chromium 147. -->
<input data-on:focus="if (evt.isTrusted) setTimeout(() => el.select(), 0)">
```

**Datastar's framework-level position aligns with no-guard:**
- v1.0.0-RC.1 (Jul 2026): added a `__trusted` modifier as opt-in
- v1.0.0-RC.5 (Aug 2026): **reversed the default and removed the modifier** —
  `data-on:*` now runs regardless of `isTrusted` provenance
- RC.8+ (current): no isTrusted filtering anywhere in the framework

The framework's stance: **handlers should be idempotent** (single textContent write per input
event = fine; `el.select()` firing `selectionchange` that the page reacts to = not fine), or
**don't attach side-effecting handlers to events password managers fire** (focus, blur,
selectionchange).

**Fix shape:**

```html
<!-- CORRECT — no data-on:focus at all. Tapping into a field puts the
     caret where you tapped; users use ⌘A or triple-click to select-all. -->
<input data-bind="form_data.full_name"
       data-on:input="el.nextElementSibling.textContent =
                      el.validity.valid ? '' : el.validationMessage">
```

Same trap applies to **JS that programmatically calls `.select()` after `.focus()`** — e.g. an
`effect()` that opens a section and runs `firstInput.focus(); firstInput.select();`. Drop the
`select()`; keep the `focus()` (essential for keyboard navigation).

Verification harness for this class of bug: build an isolated `/formtest` route that mirrors
the production form 1:1 with full event logging + a storm-killer that yanks inputs from the
DOM if a sustained focus/blur/sel cycle is detected. Bisect by URL toggle (`?focus_select=on`
re-emits the buggy attribute for regression testing). See loadout's
`src/routes/formtest.rs` + `templates/formtest.html` as reference (and the loadout memory
`feedback_instrument_dont_layer_defenses.md`).

**Append to list (infinite scroll / live feed)**
```
event: datastar-patch-elements
data: selector #feed
data: mode append
data: elements <div id="item-42">New item</div>

```

---

## Datastar Pro — Attributes (10 total)

Source: `~/Projects/github/datastar-pro/library/src/pro/attributes/`.
Authoritative docs: `https://data-star.dev/reference/attributes` (Pro section).

### `data-animate` — animate attribute values over time

```html
<!-- Single-attribute -->
<div data-animate:width__duration.500ms__ease.outcubic="$width + 'px'"></div>

<!-- Multi-attribute object form -->
<rect data-animate__duration.300ms="{
  x: $x + 'px', y: $y + 'px', opacity: $alpha
}"></rect>
```

**Modifiers:**
- `__duration.<time>` — e.g. `300ms`, `1.5s` (parsed via `tagToMs`)
- `__ease.<name>` — `linear`, `quadratic`, `cubic`, `elastic`, `inquad`, `outquad`, `inoutquad`,
  `incubic`, `outcubic`, `inoutcubic`, `inquart`, `outquart`, `inoutquart`,
  `inquint`, `outquint`, `inoutquint`, `insine`, `outsine`, `inoutsine`,
  `inexpo`, `outexpo`, `inoutexpo`, `incirc`, `outcirc`, `inoutcirc`,
  `inelastic`, `outelastic`, `inoutelastic`, `inback`, `outback`, `inoutback`,
  `inbounce`, `outbounce`, `inoutbounce`, `ingolden`, `outgolden`, `inoutgolden`
- `__delay.<time>`, `__loop`, `__pingpong`

**Gotchas:**
- Animated attributes must share the same suffix (cannot animate `0px` → `100%`)
- Uses `requestAnimationFrame`
- Cancels in-flight animations on interruption

### `data-custom-validity` — set custom HTML5 validation message

```html
<input data-bind:email
       data-custom-validity="$email.includes('@') ? '' : 'must include @'" />
```

Empty string = valid; non-empty = invalid (shown via native validation UI).
Only works on `<input>`, `<select>`, `<textarea>` — throws on other elements.

### `data-match-media` — sync media query state to a signal

```html
<div data-match-media:is-dark="prefers-color-scheme: dark"
     data-class:dark="$isDark"></div>

<div data-match-media:is-mobile="max-width: 768px">...</div>
```

Signal name follows kebab→camel rule. Auto-wraps query in parentheses if absent.
Cleanup resets the signal to `null`.

### `data-on-raf` — run on every requestAnimationFrame

```html
<div data-on-raf="$cursor.x = mouseX; $cursor.y = mouseY"></div>
```

Modifiers: timing modifiers + `__viewtransition`. Coalesces signal writes via
`beginBatch`/`endBatch`. **Use sparingly** — runs every frame.

### `data-on-resize` — react to element dimension changes

```html
<div data-on-resize="$size = el.getBoundingClientRect().width"></div>
```

Uses `ResizeObserver` (observes the element, not the viewport — distinct from
`data-match-media`). Modifiers: `__debounce`, `__throttle`, `__viewtransition`.

### `data-persist` — sync signals to localStorage / sessionStorage

```html
<!-- Persists ALL signals under key "datastar" -->
<div data-persist></div>

<!-- Custom storage key -->
<div data-persist:my-app></div>

<!-- Filtered + session storage -->
<div data-persist__session="{include: /^prefs/, exclude: /password/}"></div>
```

Loads from storage on first render, then writes reactively. Logs to
`console.error` on JSON parse failure. Use `__session` modifier for
sessionStorage (default is localStorage).

### `data-query-string` — sync URL query params ↔ signals

```html
<!-- Bidirectional: URL is source of truth on load, signals on change -->
<div data-query-string></div>

<!-- Filter to only relevant signals -->
<div data-query-string="{include: /^filter\./}"></div>

<!-- Push history entry instead of replace; omit empty -->
<div data-query-string__history__filter></div>
```

Type coerces `'true'`/`'false'`/numeric strings. Supports nested paths
(`foo.bar.baz` ↔ `$foo.bar.baz`). Doesn't update URL during browser
back/forward navigation.

### `data-replace-url` — reactively update URL via history.replaceState

```html
<!-- CORRECT — JS string expression -->
<div data-replace-url="'/v2/' + $contentId">

<!-- WRONG — /v2/ parsed as regex literal → SyntaxError -->
<div data-replace-url="/v2/some-id">
```

Source `replaceUrl.ts`: `requirement: { key: 'denied', value: 'must' }` — no
colon key allowed, value expression is required. Wrapped in `effect()` — fires
reactively on every morph/dependency change.

**When to use:** continuous URL sync (filters, pagination, tab state).
**When NOT to use:** one-shot URL updates after save — use the self-removing
script pattern instead. `data-replace-url` fires on every morph, not just the
triggering event.

### `data-scroll-into-view` — scroll target into viewport

```html
<div data-scroll-into-view></div>
<div data-scroll-into-view__smooth__vcenter__hcenter></div>
<div data-scroll-into-view__instant__vstart__focus></div>
```

**Modifiers:**
- Behavior: `__smooth` (default), `__instant`, `__auto`
- Horizontal: `__hstart`, `__hcenter` (default), `__hend`, `__hnearest`
- Vertical: `__vstart`, `__vcenter` (default), `__vend`, `__vnearest`
- Extras: `__focus` — calls `.focus()` after scroll

**Side effect:** sets `tabindex="0"` if not present (so `__focus` works).

### `data-view-transition` — set CSS view-transition-name

```html
<div data-view-transition="'page-' + $route"></div>
```

Sets `style="view-transition-name: ..."` reactively. Pairs with CSS
`::view-transition-old(name)` / `::view-transition-new(name)`. Warns on
browsers that don't support the View Transitions API.

---

## Datastar Pro — Actions (3 total)

Source: `~/Projects/github/datastar-pro/library/src/pro/actions/`.

### `@clipboard(text, isBase64?)` — write to clipboard

```html
<button data-on:click="@clipboard($code)">Copy</button>
<button data-on:click="@clipboard($encodedHtml, true)">Copy HTML</button>
```

If `isBase64` is true, decodes via `atob` before writing. Throws if
`navigator.clipboard` unavailable (insecure context, etc.). Returns a Promise
(usually fire-and-forget).

### `@fit(v, oldMin, oldMax, newMin, newMax, shouldClamp?, shouldRound?)` — range remap

```html
<!-- Map slider 0–100 to RGB 0–255, clamped + rounded -->
<div data-style:background-color="
  'rgb(' + @fit($r, 0, 100, 0, 255, true, true) + ',0,0)'
"></div>
```

Linear interpolation between two ranges. **No clamping by default** — pass
`shouldClamp=true` to constrain. Internally `inverseLerp` then `lerp`.
Like Processing's `map()` / p5's `map()`.

### `@intl(type, value, options?, locales?)` — format via JS Intl APIs

```html
<!-- Number -->
<span data-text="@intl('number', $price, {style: 'currency', currency: 'USD'})"></span>

<!-- Date -->
<span data-text="@intl('datetime', $when, {dateStyle: 'medium'})"></span>

<!-- Relative time (note `unit` in options) -->
<span data-text="@intl('relativeTime', -3, {unit: 'day'}, 'en-US')"></span>

<!-- Plural, list, displayNames -->
<span data-text="@intl('pluralRules', $count)"></span>
<span data-text="@intl('list', ['a', 'b', 'c'])"></span>
<span data-text="@intl('displayNames', 'fr', {type: 'language'})"></span>
```

**Supported `type` values:** `'datetime'`, `'number'`, `'pluralRules'`,
`'relativeTime'` (requires `unit` in options), `'list'`, `'displayNames'`
(requires `type` in options).

Default locale = `navigator.language` or `'en-US'`. Throws on unknown type
or invalid date.

---

## Datastar Pro — Datastar Inspector

Source: `~/Projects/github/datastar-pro/webcomponents/datastar-inspector/src/index.ts`.

A web-component dev tool for inspecting Datastar signals, SSE/signal-patch
events, and persisted storage in real time.

### Embed it

```html
<script type="module" src="/static/datastar-inspector.js"></script>

<datastar-inspector max-events-visible="50"></datastar-inspector>
```

It mounts a panel (in shadow DOM) and listens at the document level for:
- `datastar-fetch` — SSE fetch lifecycle (started/finished/error/retry)
- `datastar-signal-patch` — signal-tree updates
- `storage` — local/session storage changes

### Attributes / observed state

| Attribute / property | What it controls |
|---|---|
| `max-events-visible` | Cap on event list length (default 20). Prevents memory bloat. |
| `expanded`, `open`, `tab` | Panel visibility / active tab (persisted in sessionStorage under `datastar-inspector-state`). |
| `currentSignalsIncludeFilter` / `currentSignalsExcludeFilter` / `currentSignalsUseExactMatch` / `currentSignalsTableView` | Signal-list filtering and view options |
| `persistedDataIncludeFilter` / `persistedDataExcludeFilter` / `persistedDataUseExactMatch` / `persistedDataTableView` / `persistedDataUseSessionStorage` | Persist-data filtering and view options |
| `signalPatchEventCount` / `sseEventCount` | Live counters |
| `currentSignals` / `persistedData` | Live snapshots |
| `highlightedElements` | DOM elements highlighted for debugging |

**Gotcha:** Listens at document level — not isolated to a component subtree.
There's only one inspector per page; it sees everything.

---

## Datastar Pro — Bundler & Stellar CSS

### Bundler (`/pro/bundler`)

Web tool (auth-required) to generate custom Pro bundles containing only the
plugins you need. Reduces ship size for projects that don't use the full
attribute/action surface. Sign in with GitHub OAuth on data-star.dev.

### Stellar CSS

A lightweight CSS framework (alpha as of this writing) shipped under the Pro
license. Provides a configurable design system in CSS variables — no build
step required. Docs are gated behind GitHub OAuth at `data-star.dev/pro` →
"Stellar CSS".

---

## Rocket — Pro Custom Elements (shipping JS-call API)

Rocket is Datastar Pro's web-component framework. Components are registered by
calling `rocket(tag, options)` from JavaScript — there is **no template-based
`<template data-rocket:*>` syntax** (that was alpha.7-only and removed in
beta.1).

Source of truth: `~/Projects/github/datastar-pro/library/src/pro/rocket/runtime.ts`.

### Mental Model

Rocket sits **alongside** Datastar's SSE-first model, not instead of it. Server-
driven HTML patches still own the page. Rocket owns the **interior** of
components that have genuine client-side behavior — animations, canvas/WebGL,
3rd-party library integration, transient UI state with no server representation,
complex gesture handling.

| symbol | scope | sent to server |
|---|---|---|
| `$name` (template) / `$.name` (setup) | page-level signal (global) | yes (unless `_` prefix) |
| `$_name` (template) / `$._name` (setup) | page-level private signal | never |
| `$$name` (template) / `$$.name` (setup) | component-scoped signal (per instance, under `_rocket.<tag>.<id>.name`) | never |

**When Rocket is the right tool:**
- ✅ Reusable interactive widgets (counter, copy button, password strength, QR)
- ✅ JS libraries that own their own DOM (ECharts, MapLibre, Globe.GL, Three.js, CodeMirror)
- ✅ Canvas/SVG/WebGL animations (starfield, letter stream, SVG morph)
- ✅ Client-only state (animation progress, drag position, transient UI)
- ✅ Virtual scroll, drag-drop, graph editors — imperative UI that doesn't fit morph
- ✅ Headless service components (no visible render, `setup` owns observers + cleanup)

**When NOT to use Rocket:**
- ❌ Server-rendered HTML updated via SSE patches (that's the primary Datastar path)
- ❌ Simple show/hide, form bind, click-to-post — plain `data-*` is simpler and cheaper
- ❌ Anything where the server already renders the right HTML on page load

### The Component Shape

```js
import { rocket } from 'datastar-pro'  // or whatever your bundle exposes

rocket('my-counter', {
  // Public API — typed via fluent codecs. Becomes observed attributes.
  props: ({ number, string, oneOf }) => ({
    start: number.min(0).default(0),
    label: string.trim().default('Count'),
    size: oneOf('sm', 'md', 'lg').default('md'),
  }),

  // Render mode — 'light' (default), 'open' (open shadow), 'closed' (closed shadow)
  mode: 'light',

  // Re-render on prop change? Default: true. false skips re-render
  // (useful for library-owned DOM where setup/effects do all updates).
  renderOnPropChange: true,

  // Optional ref constructors — typecheck refs.input as HTMLInputElement
  refs: { input: HTMLInputElement, canvas: HTMLCanvasElement },

  // Optional metadata for IDE autocomplete / tooling
  manifest: {
    slots: [{ name: 'icon', description: 'Optional leading icon' }],
    events: [{ name: 'count-changed', kind: 'custom-event', bubbles: true, composed: true }],
  },

  // Per-instance setup. Runs on connectedCallback BEFORE first render.
  // ALL imperative wiring goes here.
  setup({ props, $, $$, effect, cleanup, actions, action,
          emit, emitCancellable, observeProps, overrideProp,
          defineHostProp, apply, adoptStyles, host, render }) {
    // Initialize component-local signals — creates $$count for templates
    $$.count = props.start

    // React to specific prop changes (without re-running every render)
    observeProps((oldProps, newProps) => {
      $$.count = newProps.start
    }, 'start')

    // Local action — callable as `actions.increment()` or `data-on:click="@increment()"`
    action('increment', () => { $$.count += 1 })

    // Reactive side effect — auto-cleaned on disconnect
    effect(() => {
      if ($$.count >= 100) emit('count-changed', { value: $$.count })
    })

    // Manual cleanup hook
    cleanup(() => {
      // anything that effect() didn't auto-handle (rAF, observers, listeners)
    })
  },

  // Runs ONCE after first render — refs are populated here.
  onFirstRender({ refs, host, $$, effect, cleanup, props }) {
    refs.input.focus()    // refs.input is the element with data-ref:input
  },

  // Render. Pure — no side effects. Returns DOM via tagged templates.
  render({ html, svg, props, host }) {
    return html`
      <button data-on:click="@increment()" class="size-${props.size}">
        ${props.label}: <span data-text="$$count"></span>
      </button>
      <input data-ref:input type="number" data-bind:start />
      <slot name="icon"></slot>
    `
  },
})
```

Usage anywhere on the page:

```html
<my-counter start="5" label="Hits" size="lg">
  <svg slot="icon">…</svg>
</my-counter>

<!-- Reactively bind props from page signals -->
<my-counter data-attr:start="$pageCount"></my-counter>
```

### `RocketDefinition` — full shape (verbatim from runtime.ts)

```ts
type RocketDefinition<Defs, Refs> = {
  refs?: Refs                                           // Record<name, ElementCtor>
  props?: (codecs: CodecRegistry) => Defs               // FUNCTION receiving codec registry
  manifest?: { slots?: [...], events?: [...] }
  setup?: (context: SetupContext<Props>) => void
  onFirstRender?: (context: FirstUpdateContext<Props, Refs>) => void
  render?: (context: RenderContext<Props>) => RocketRenderValue
  mode?: 'open' | 'closed' | 'light'
  renderOnPropChange?:
    | boolean
    | ((context: { host, props, changes }) => boolean)
}
```

### Props — fluent codec API

`props` is a **function** that receives the codec registry. Build prop
definitions using fluent codec chains.

```js
props: ({ string, number, bool, date, json, js, bin, array, object, oneOf }) => ({
  // String codec — chainable transforms
  name: string.trim.maxLength(50).default('anon'),
  slug: string.kebab,                          // forces kebab-case
  caps: string.upper.prefix('USER-'),

  // Number codec — clamp/step/round
  count: number.min(0).default(0),
  ratio: number.clamp(0, 1).default(0.5),
  steps: number.clamp(0, 10).step(1),
  pixels: number.fit(0, 100, 0, 255, true, true),  // remapped + clamped + rounded

  // Bool — empty attribute = true; missing = false (or default)
  enabled: bool.default(false),

  // Date — ISO 8601 parse; default = now if omitted
  startTime: date.default(() => new Date()),

  // Structured data
  config: json.default({}),                   // strict JSON parse
  spec: js.default({}),                       // JS-literal-ish (trailing commas, unquoted keys ok)
  payload: bin,                                // base64 → Uint8Array

  // Composition
  items: array(number).default([]),                          // homogeneous
  viewport: array(number, number, number).default([0,0,0]),  // tuple
  tags: array(string),
  profile: object({ name: string, age: number, active: bool }),

  // Enum / union
  level: oneOf('low', 'med', 'high').default('low'),
})
```

**Available codecs (from `library/src/pro/rocket/codecs.ts`):**

| Codec | Methods |
|---|---|
| `string` | `.trim`, `.upper`, `.lower`, `.kebab`, `.camel`, `.snake`, `.pascal`, `.title`, `.prefix(s)`, `.suffix(s)`, `.maxLength(n)`, `.default(v)` |
| `number` | `.min(n)`, `.max(n)`, `.clamp(lo, hi)`, `.step(s, base?)`, `.round`, `.ceil(d?)`, `.floor(d?)`, `.fit(inMin, inMax, outMin, outMax, clamped?, rounded?)`, `.default(v)` |
| `bool` | `.default(v)` |
| `date` | `.default(v)` |
| `json` | `.default(v)` |
| `js` | `.default(v)` (parses JS-literal-ish strings; trailing commas + unquoted keys ok; revives `function() {...}` strings) |
| `bin` | `.default(v)` (base64 ↔ `Uint8Array`) |
| `array(codec)` / `array(c1, c2, ...)` | `.default(v)` (homogeneous array OR tuple based on arity) |
| `object({ field: codec, ... })` | `.default(v)` |
| `oneOf(v1, v2, ...)` or `oneOf(c1, c2, ...)` | `.default(v)` (literal enum or codec union) |

All codecs also support `.docs({ description, label, control, placeholder })`
to feed manifests for IDE/tooling.

### Setup Context (verbatim from runtime.ts:99–146)

The `setup()` function receives a context object with these properties:

| Property | Type | What it does |
|---|---|---|
| `props` | `Props` | Decoded prop values (read-only here). |
| `$` | `Record<string, any>` | Datastar's global signal root. Read/write `$.foo` to share state across the page. |
| `$$` | `SetupSignal` (callable proxy) | Component-local signals. `$$.count = 0` declares a signal; templates read `$$count`. Function values become computed signals: `$$.total = () => $$.count + 1`. |
| `effect(fn)` | `() => void` | Reactive effect. Auto-disposed on disconnect; returns explicit dispose fn. |
| `cleanup(fn)` | `void` | Register a teardown callback (fires on disconnect). |
| `apply(root, merge?)` | `void` | Apply Datastar attributes to a subtree. `merge` defaults to `true`. Use after imperatively inserting Datastar-flavored DOM. |
| `adoptStyles(host, ...styles)` | `void` | Inject CSS into shadow root (via `adoptedStyleSheets`) or light DOM (via `<style>` prepend). |
| `emit(name)` / `emit(name, detail, options?)` | `boolean` | Dispatch bubbling+composed `Event` (no detail) or `CustomEvent` (with detail). |
| `emitCancellable(...)` | `boolean` | Like `emit` but cancellable; returns whether default was prevented. |
| `actions` | `Record<string, fn>` | Proxy to the GLOBAL action registry (call `actions.foo(arg)` to invoke `@foo`). |
| `action(name, fn)` | `void` | Register a COMPONENT-LOCAL action. Shadows globals for this instance. The fn receives `{ host, props, state, el, evt }, ...args`. |
| `observeProps(fn, ...names)` | `() => void` | Run `fn(oldProps, newProps)` when any of the named props change (or on every prop change if no names given). Returns disposer. |
| `overrideProp(name, getter?, setter?)` | `void` | Customize prop accessors — useful for live controls (sliders) where the displayed value differs from the stored value. |
| `defineHostProp(name, descriptor)` | `void` | Add arbitrary properties/methods to the host element beyond declared props. |
| `render(overrides?)` | `void` | Manually trigger a re-render. |
| `host` | `RocketHostWithProps<Props>` | Typed reference to the custom-element instance. |

`evt` is **not** part of the setup context — it's only present on action contexts.

### `onFirstRender` Context

Same as `SetupContext` plus:

| Property | Type | What it does |
|---|---|---|
| `refs` | `InstancesOf<Refs>` | Refs declared in `data-ref:<name>` elements. Typed by the `refs` map in `RocketDefinition`. **Only available here** — refs aren't populated when `setup()` runs. |

### Render Context (pure — no side-effect helpers)

| Property | Type |
|---|---|
| `html` | Tagged template literal — composes `Node`/iterable/primitive into a `DocumentFragment` |
| `svg` | Tagged template literal — same, but elements are SVG-namespaced |
| `props` | Decoded prop values |
| `host` | Typed host reference |

`render()` is **pure** — never put `addEventListener`, `setTimeout`, `fetch`,
or signal writes in `render`. Side effects belong in `setup()` and `effect()`.

### Render Modes

| mode | how to enable | style scoping | slot semantics |
|---|---|---|---|
| **Light** (default) | `mode: 'light'` (or omit) | Inherits page CSS. Uses scoped `data-rocket-host` attribute. | Uses Rocket's manual slot-projection: matching host children move into rendered `<slot>` positions. |
| **Open shadow** | `mode: 'open'` | Native shadow isolation; external JS can reach in. | Native web-component slots. |
| **Closed shadow** | `mode: 'closed'` | Native shadow isolation; external JS can't reach in. | Native web-component slots. |

**Light DOM is the default and is right for most cases.** It inherits page CSS,
participates in normal document styling, and lets server-rendered content
(forms, SVG children) work naturally.

Use shadow DOM when the component needs true style isolation — a drop-in
design-system widget. Avoid shadow when wrapping server-rendered SVG content
flow (SVG namespace can break across the boundary).

### Scoped Signals — `$$name`

Inside `render()`'s tagged-template output and in any `data-*` expression
within the rendered tree, `$$name` refers to **this instance's** signal under
`_rocket.<tag>.<instanceId>.name`. Rocket rewrites `$$` tokens to full signal
paths at mount.

```js
rocket('my-input', {
  setup({ $$ }) {
    $$.query = ''                              // declares the signal
  },
  render: ({ html }) => html`
    <input data-bind:query />
    <span data-text="$$query"></span>
    <template data-for="item, i in $$results">
      <li data-text="item.name"></li>
    </template>
  `,
})
```

In the setup script (`$$` is a callable proxy), use property access:

```js
setup({ $$, effect }) {
  $$.count = 0
  effect(() => console.log($$.count))    // $$.count read = subscription
}
```

**Escape the scope** (write a page-level signal from inside a Rocket template)
with `__root` modifier on the expression:

```html
<button data-on:click__root="$.globalCounter++">Bump page counter</button>
```

### Refs — `data-ref:<name>`

Decorate any element in `render()` output with `data-ref:<name>`. The element
is exposed as `refs.name` in `onFirstRender` (typed by the `refs` map).

```js
rocket('focus-on-mount', {
  refs: { input: HTMLInputElement },
  render: ({ html }) => html`<input data-ref:input />`,
  onFirstRender({ refs }) {
    refs.input.focus()
  },
})
```

Refs are not available in `setup()` — they're populated after the first render.

### Component-Local Actions

Register inside `setup` via `action(name, fn)`. Shadows globals for THIS
instance only. The function receives `{ host, props, state, el, evt }` plus
any args passed at the call site.

```js
setup({ $$, action }) {
  $$.x = 0
  action('snap', ({ evt }, gridSize) => {
    $$.x = Math.round($$.x / gridSize) * gridSize
  })
}

// In render():
// <button data-on:click="@snap(10)">Snap to 10</button>
```

From setup or other actions: `actions.snap(10)`.

### Lifecycle

`connectedCallback`:
1. Decode props via codec chain — written to `_rocket.<tag>.<instanceId>.*`
2. Build setup context (with `$`, `$$`, `effect`, `cleanup`, `actions`, etc.)
3. Run `setup(context)` — declare signals, register effects, observers, actions
4. Run first `render({...})` into the mount root (shadow root or host)
5. Apply Datastar attributes across the rendered tree
6. Hydrate refs from `data-ref:*` elements
7. Run `onFirstRender({ ...context, refs })`

On prop change (when `renderOnPropChange !== false`):
1. Run all `observeProps` callbacks
2. Coalesce into a single microtask: `#queueRender` → `#render`
3. Re-render through `render({...})`
4. Re-apply Datastar attributes across the rendered tree

`disconnectedCallback`:
1. All `cleanup(fn)` callbacks run (in registration order)
2. All `effect()` returned disposers fire
3. Component-local actions deregistered
4. Global actions called via `actions.*` get their cleanup map released
5. Instance state removed from signal tree (`_rocket.<tag>.<id>` cleared)

### The Architectural Rule (Adopted Loadout-Wide)

**Every client-side subsystem is exactly one of:**

1. **A Rocket component** — `rocket(tag, { setup, ... })` with `cleanup`
   discipline. Visible render is optional (set `render` to return an empty
   fragment, or a single `<slot>` for headless service components).
2. **A pure-function helper module** — no side effects at import time, no
   lifecycle, imported by a component.

**There is no third category.** No free-floating `DOMContentLoaded`, no
top-level `document.addEventListener`, no `queueMicrotask(init)` auto-bootstrap,
no module-top-level `effect(...)` or `new ResizeObserver(...)`. Every side
effect lives inside a component's `setup` and is released in `cleanup`.

One allowed exception: a module of **only** `action({...})` registrations (no
other exports) is a valid pure helper because those registrations are the
module's contract.

### Reference Implementation — `<loadout-canvas>`

`loadout/templates/fragments/loadout_canvas.html` +
`loadout/static/js/loadout-canvas.js` is the production-proven shape of a
headless service Rocket component. Study it when in doubt about the right
API patterns.

```js
// js/loadout-canvas.js
import { rocket } from '/static/datastar-pro.js'

rocket('loadout-canvas', {
  props: ({ string }) => ({
    workspaceId: string.default(''),
  }),
  mode: 'light',
  setup({ host, effect, cleanup, props }) {
    const stage = host.querySelector('.canvas-stage')
    const svg = stage?.querySelector('svg.canvas')
    if (!stage || !svg) return

    // …all gesture logic, viewport, keyboard, paint-order sync…
    const ro = new ResizeObserver(applyViewBox); ro.observe(svg)
    const disposePaintOrder = effect(() => { /* re-sort DOM */ })
    svg.addEventListener('pointerdown', onPointerDown)
    // …

    cleanup(() => {
      ro.disconnect()
      disposePaintOrder?.()
      svg.removeEventListener('pointerdown', onPointerDown)
      // …every listener / observer / effect disposed
    })
  },
  render: ({ html }) => html`<slot></slot>`,
})
```

```html
<!-- templates/fragments/loadout_canvas.html -->
<loadout-canvas workspace-id="{{ workspace_id }}">
  <main class="workspace">
    <!-- server-rendered workspace content — projected into the slot -->
  </main>
</loadout-canvas>
```

Zero visible render (just `<slot></slot>`), but owns gestures, viewport,
paint-order sync, and an exhaustive `cleanup`. Pattern-verifiable: every
resource registered in `setup` has a matching disposer.

### Pattern: Library Integration (ECharts, MapLibre, Globe.GL, QR, Canvas)

When a third-party library owns its own DOM, render the container **once** and
let the library drive updates via `effect()`. Set `renderOnPropChange: false`
so prop changes don't re-render and stomp the library's DOM.

```js
import qrCreator from 'https://cdn.jsdelivr.net/npm/qr-creator@1.0.0/+esm'

rocket('qr-code', {
  props: ({ string, number, oneOf }) => ({
    text: string.default('Hello'),
    size: number.clamp(50, 1000).default(200),
    errorLevel: oneOf('L', 'M', 'Q', 'H').default('L'),
    colorDark: string.default('#000000'),
    colorLight: string.default('#FFFFFF'),
  }),
  refs: { canvas: HTMLCanvasElement },
  renderOnPropChange: false,                    // library owns the canvas
  render: ({ html }) => html`<canvas data-ref:canvas></canvas>`,
  onFirstRender({ refs, effect, props }) {
    effect(() => {
      qrCreator.render({
        text: props.text, ecLevel: props.errorLevel,
        fill: props.colorDark, background: props.colorLight,
        size: props.size,
      }, refs.canvas)
    })
  },
})
```

Every reactive prop read inside `effect()` becomes a dependency — change any
of `props.text`, `props.size`, `props.errorLevel`, `props.colorDark`,
`props.colorLight` and the effect re-runs, pushing the new config into the
live canvas.

The ECharts variant typically splits into two effects: one for `option`
(calls `chart.setOption(...)` without re-init) and one for `theme` (calls
`echarts.init(...)` fresh because theme is baked into the instance).

### Pattern: Stringify-and-Compare Guard

Reactive proxies can fire an `effect()` on every read even when the value is
deep-equal. For expensive syncs (geometry updates, layer rebuilds, GeoJSON),
diff the JSON string before reacting:

```js
let prevArcs = ''
effect(() => {
  const next = JSON.stringify(props.arcs ?? [])
  if (next === prevArcs) return
  prevArcs = next
  globe.arcsData(JSON.parse(next))
})
```

Apply this for any signal where equality isn't cheap (arrays, nested objects,
large GeoJSON).

### Pattern: Canvas Animation with requestAnimationFrame

```js
rocket('star-field', {
  props: ({ number }) => ({
    starCount: number.min(1).default(500),
    speed: number.clamp(1, 100).default(50),
  }),
  refs: { canvas: HTMLCanvasElement },
  renderOnPropChange: false,
  render: ({ html }) => html`<canvas data-ref:canvas></canvas>`,
  onFirstRender({ refs, props, effect, cleanup }) {
    let aid = 0
    let ro

    const animate = () => {
      // …draw a frame using props.starCount / props.speed…
      aid = requestAnimationFrame(animate)
    }
    const reset = () => { /* resize + seed based on props.starCount */ }

    // effect auto-runs and re-runs whenever starCount changes
    effect(() => {
      props.starCount     // explicit read = subscription
      reset()
    })

    // Kick off animation loop once
    reset()
    aid = requestAnimationFrame(animate)
    ro = new ResizeObserver(reset)
    ro.observe(refs.canvas.parentElement || refs.canvas)

    cleanup(() => {
      cancelAnimationFrame(aid)
      ro?.disconnect()
    })
  },
})
```

Every resource registered in setup must be released in `cleanup` — rAF handle,
`ResizeObserver`, timeouts, library disposers, listeners on `window`/`document`.
Rocket auto-disposes `effect()` returns, but rAF handles and observer instances
are your responsibility.

### Pattern: Component Emits Events Back to the Page

Rocket components talk to the page by `emit`-ing CustomEvents from the host.
`emit` automatically sets `bubbles: true, composed: true` (so events escape
shadow boundaries).

```js
rocket('globe-view', {
  setup({ emit }) {
    // somewhere in an effect or click handler
    emit('marker-click', { name: entry.name, lat, lng })
  },
})
```

Page listens with `data-on:*`:

```html
<globe-view data-on:marker-click="$lastClicked = evt.detail.name"></globe-view>
```

For cancellable events (where the page can `evt.preventDefault()`), use
`emitCancellable` and check the return value.

### Pattern: Component-Initiated SSE Fetches (Virtual Scroll)

A component can make its own Datastar-protocol fetch and replay the SSE stream
into Datastar's dispatch pipeline — useful when pagination/scrolling needs
server data independent of page signals.

```js
rocket('virtual-scroll', {
  props: ({ string, number }) => ({
    url: string,
    bufferSize: number.min(1).default(50),
  }),
  refs: { viewport: HTMLDivElement },
  setup({ props, host, refs }) {
    async function loadBlock(startIndex) {
      const response = await fetch(props.url, {
        method: 'POST',
        headers: {
          Accept: 'text/event-stream, text/html, application/json',
          'Content-Type': 'application/json',
          'Datastar-Request': 'true',
        },
        body: JSON.stringify({
          startIndex, count: props.bufferSize, componentId: host.id,
        }),
      })
      // …read reader, split on \n\n, parse event/data lines, then:
      document.dispatchEvent(new CustomEvent('datastar-fetch', {
        detail: { type: eventName, el: host, argsRaw: { elements, selector, mode } },
      }))
    }
    // wire to scroll handlers, etc.
  },
  render: ({ html }) => html`<div data-ref:viewport>...</div>`,
})
```

Use this when a component needs server data on its own schedule (infinite
scroll, graph reconciliation). For normal flows, prefer `@get`/`@post` at
the page level.

### Template Directives Inside `render()`

Standard Datastar directives work inside the rendered tree. They're scoped to
the component (so `$$x` refers to component-local state).

```js
render: ({ html, props }) => html`
  <!-- Two-way bind, computed, indicator (all scoped) -->
  <input data-bind:query />
  <div data-computed:trimmed-query="$$query.trim()"></div>
  <div data-indicator:loading></div>

  <!-- Loops — must be on <template> -->
  <template data-for="item in $$items" data-key="item.id">
    <li data-text="item.name"></li>
  </template>

  <template data-for="row, j in $$rows">
    <template data-for="cell, k in row.cells">
      <span data-text="${j} + ':' + ${k} + ' = ' + cell.value"></span>
    </template>
  </template>

  <!-- Conditionals — must be on <template> -->
  <template data-if="$$step === 0"><div>Idle</div></template>
  <template data-else-if="$$step === 1"><div>Loading</div></template>
  <template data-else><div>Ready</div></template>

  <!-- Refs — exposed on refs.<name> in onFirstRender -->
  <canvas data-ref:canvas></canvas>

  <!-- Opt out of Datastar processing for a subtree -->
  <div data-ignore>third-party library DOM</div>
`
```

### ⚠️ Trap: Do NOT use `<template data-for>` inside SVG

The `<template data-for>` / `<template data-if>` directives work only in
**HTML context**. Inside an `<svg>` element, the HTML parser treats every
tag as SVG-namespaced — `<template>` becomes an SVG-namespaced unknown
element with no `.content` fragment. Datastar's loop processor never finds
it. Silent no-op.

**Fix: create SVG children imperatively from `setup` / `onFirstRender`.** Use
`render`'s `svg` tagged template for the empty container, and grow/shrink
its children inside an `effect()`:

```js
const SVG_NS = 'http://www.w3.org/2000/svg'

rocket('flow-edges', {
  setup({ host, $$, effect }) {
    $$.guides = []   // [ {x1,y1,x2,y2}, ... ]

    effect(() => {
      const layer = host.querySelector('#guides-layer')
      if (!layer) return
      const items = $$.guides

      // grow/shrink child pool
      while (layer.children.length < items.length) {
        const line = document.createElementNS(SVG_NS, 'line')
        line.setAttribute('class', 'guide')
        layer.appendChild(line)
      }
      while (layer.children.length > items.length) {
        layer.lastChild.remove()
      }

      for (let i = 0; i < items.length; i++) {
        const it = items[i]
        const ln = layer.children[i]
        ln.setAttribute('x1', it.x1); ln.setAttribute('y1', it.y1)
        ln.setAttribute('x2', it.x2); ln.setAttribute('y2', it.y2)
      }
    })
  },
  render: ({ svg }) => svg`<g id="guides-layer"></g>`,
})
```

**Rule:** every `<template data-for>` / `<template data-if>` must live in
HTML context. For dynamic SVG children, create them with
`document.createElementNS(SVG_NS, tag)` inside an `effect()`.

### ⚠️ Trap: Light-DOM `render` Clones Host Descendants on First Render

**The non-obvious detail that burns everyone once:** when a light-mode Rocket
component has children in its host markup AND a `render` function (any render —
including `html\`<slot></slot>\``), idiomorph deep-CLONES those children into
the live DOM on first render. Originals end up in detached fragment storage;
the live DOM contains CLONES.

**Any listener attached to a host descendant in `setup` is stranded** — the
listener stays bound to the orphaned original; events fire on the live clone
and never reach it. CSS keeps working because it matches the clone by class /
selector. Hover-works-but-click-doesn't is the diagnostic signature.

**Why it happens (lifecycle):**
- `setup` runs BEFORE `render` (`runtime.ts:1501-1502`).
- `setup` queries `host.querySelector(...)` — finds the original descendant
  still attached to the host. Listener attaches there.
- `#render` runs slot projection: `content.append(...this.childNodes)` MOVES
  the host's children into a fragment (`runtime.ts:1140`), then
  `slot.replaceWith(...children)` puts them where the slot was.
- `morph(host, fragment, 'inner')` runs (`runtime.ts:1167`).
- At this point the host is empty (children just moved out), so morph's
  `ctxPersistentIds` is empty — no IDs are shared between old and new.
- `morphChildren` falls through to `document.importNode(newChild, true)` —
  a deep clone (`patchElements.ts:422-427`). Even subtrees that contain IDs
  in their descendants take the line-411 branch, which `document.createElement`s
  a fresh wrapper and recurses.
- Either way: the clone is in the live host; the original (with the listener)
  is in detached storage.

**This trap fires for the OWN component, not just siblings.** The earlier
guidance that "the peer's OWN `host.querySelector` works fine because it
queries AFTER its own clone is live" is **wrong** — setup runs *before*
the morph that creates the clone.

**The trap (own component):**

```js
// BROKEN — listener attached to original svg in setup; render clones it.
rocket('my-canvas', {
  render: ({ html }) => html`<slot></slot>`,    // ← triggers morph + clone
  setup({ host, cleanup }) {
    const svg = host.querySelector('svg')        // ← original svg
    svg.addEventListener('pointerdown', handler) // 💥 stranded after morph
    cleanup(() => svg.removeEventListener('pointerdown', handler))
  },
})
```

**The trap (sibling reaching across):** Same root cause, different surface.
A sibling that does `document.querySelector('.peer-dom').addEventListener(...)`
in its own setup attaches to the peer's original (still in the DOM at that
moment). When the peer mounts and renders, its descendants get cloned, and
the sibling's listener is stranded on the orphan.

**Fixes, in order of preference:**

1. **Wrapper component with no chrome → OMIT `render` entirely.** Rocket's
   `#render` early-returns at `runtime.ts:1082-1085` when `render` is absent;
   the host's children are never morphed; `apply()` at `runtime.ts:1526`
   still binds Datastar's `data-*` attrs across the original tree. Imperative
   listeners attached in `setup` survive because their nodes were never
   moved. This is the right shape for any Rocket component whose only job
   is to wrap server-rendered markup with imperative behavior — there's no
   chrome to render.

   ```js
   rocket('my-canvas', {
     // No `render` — host's existing children stay in place untouched.
     setup({ host, cleanup }) {
       const svg = host.querySelector('svg')
       svg.addEventListener('pointerdown', handler)
       cleanup(() => svg.removeEventListener('pointerdown', handler))
     },
   })
   ```

2. **Declarative `data-on:*` on the rendered template.** When you DO need
   chrome rendered, use `data-on:*` instead of imperative `addEventListener`.
   Datastar's `apply()` runs post-morph and binds these against the live
   clones. Survives every re-mount.

   ```js
   rocket('my-canvas', {
     setup({ action }) {
       action('selectionPointerDown', ({ evt }) => { /* ... */ })
     },
     render: ({ html }) => html`
       <section class="canvas-stage"
                data-on:pointerdown__capture="@selectionPointerDown(evt)">
       </section>
     `,
   })
   ```

3. **Imperative wiring in `onFirstRender`, not `setup`.** `onFirstRender`
   runs AFTER `#render` (`runtime.ts:1547`), so `host.querySelector` finds
   the live clone. Listeners attached there work. Use this when you need
   imperative gesture wiring AND a rendered chrome together.

4. **Sibling reaching across → move the wiring INTO the peer's own setup.**
   The sibling exports pure helpers; the peer imports them and binds from
   its own setup against its own host's descendants — paired with fix 1 or 3
   above so the peer's setup-time queries land on nodes that survive its
   own morph.

5. **Sibling coordination via signals or CustomEvents.** Writes to `$.*` are
   reactive, no DOM reference sharing needed. Or dispatch CustomEvents to
   `document` / `window` and listen via `data-on:my-event__window`. Both
   work because they never touch peer-component DOM directly.

**What's ALWAYS safe:**
- `host.addEventListener(...)` — the host element is the custom-element
  instance itself, never cloned by morph (only its inner content is).
- `window.addEventListener(...)` / `document.addEventListener(...)` — those
  nodes aren't part of any component's morph surface.
- `effect(() => $.*)` — signal subscriptions don't depend on DOM identity.

**What's ALWAYS safe from anywhere:**
- `window.addEventListener(...)` / `document.addEventListener(...)` — those nodes aren't cloned.
- `effect(() => $.*)` — signal subscriptions are unaffected by DOM cloning.
- Dispatching `CustomEvent` to `document` / `window` and listening via `data-on:my-event__window`.

### Pattern: Conditional Branches (Mount/Unmount vs data-show)

Use `<template data-if>`/`<template data-else-if>`/`<template data-else>` for
true mount/unmount branching. The branch's DOM is removed when the condition
becomes false; its effects, listeners, and signal subscriptions are all
cleaned up.

```js
rocket('conditional-panel', {
  props: ({ number, bool }) => ({
    step: number.clamp(0, 2).default(0),
    showDetails: bool,
  }),
  render: ({ html, props }) => html`
    <section>
      <template data-if="$$step === 0"><div>Idle</div></template>
      <template data-else-if="$$step === 1"><div>Loading</div></template>
      <template data-else><div>Ready</div></template>

      <!-- data-show: stays mounted; only visibility toggles. State preserved. -->
      <aside data-show="$$showDetails">Still mounted, just hidden</aside>
    </section>
  `,
  setup({ $$, props }) {
    $$.step = props.step
    $$.showDetails = props.showDetails
  },
})
```

Pick mount/unmount (`data-if`) when the branch owns resources that should be
torn down on exit. Pick `data-show` when the element has ongoing state to
preserve (scroll position, form input, in-flight timers).

### Light vs Shadow — When to Pick

|                  | light (default) | shadow (`open` / `closed`) |
|------------------|---|---|
| style scope      | scoped via `data-rocket-host` attr + selector rewrite | native shadow isolation |
| page CSS         | applies | does NOT apply |
| slot content     | host children projected into `<slot>` (with `$$` rescoping) | native shadow slots |
| `:host` in style | rewritten to scope selector | native |
| when to pick     | inline widgets, forms, counters, controls that want native page feel; components hosting projected SVG | fully isolated design-system widgets; library integrations where library styles shouldn't leak |

For library integrations (ECharts, Globe, MapLibre) shadow mode is often right
— the library's styling stays isolated. For components that live inside SVG
content flow (like `loadout-canvas` wrapping server-rendered `<g>` elements),
light mode is required — shadow would break the SVG namespace.

### Rocket + SSE Integration Patterns

Rocket does not opt out of Datastar's SSE model; it plugs in at defined seams.

**1. Server patches the component wrapper.** The server renders
`<div id="chart-host"><echarts-view data-attr:option='...'></echarts-view></div>`
as a `datastar-patch-elements` event. The component mounts, reads props, done.

**2. Page signals flow in via `data-attr:*` (most common).** Page state lives
in page signals (`$view.zoom`, `$filters.query`). The component receives them
as props and reacts:

```html
<openfreemap-map
  data-attr:style-url="$styleUrl"
  data-attr:center="$view.center"
  data-attr:zoom="$view.zoom">
</openfreemap-map>
```

**3. Component emits events that trigger backend actions.**
```html
<file-dropper data-on:file-selected="@post('/upload')"></file-dropper>
```

**4. Component fetches its own SSE stream** — the virtual-scroll pattern (above).

---

## Deep Dive: Rocket Flow — Multi-Component Server-Reconciled Editor

`rocket_flow.md` is the richest example in the catalog. It builds a React-Flow-
style graph editor where **the server owns the topology** and Rocket provides
only the interactive layer. Every pattern below is reusable for any
canvas/whiteboard/timeline editor.

**Three cooperating components:**

| component | role | DOM output |
|---|---|---|
| `<flow-container>` | Editor shell (viewport, SVG, drag, selection) | Renders the canvas |
| `<flow-node>` | Declarative node wrapper | **Hidden** — emits events only |
| `<flow-edge>` | Declarative edge wrapper | **Hidden** — emits events only |

**Server-rendered HTML (arrives as `datastar-patch-elements`):**

```html
<flow-container data-attr:viewport="$viewport"
                data-attr:grid="32"
                data-attr:server-update-time="$serverTime">
  <flow-node id="a" x="0"   y="0"   label="Hello"></flow-node>
  <flow-node id="b" x="200" y="100" label="World">
    <svg>…custom SVG content…</svg>   <!-- light-DOM children optional -->
  </flow-node>
  <flow-edge source="a" target="b" animated></flow-edge>
</flow-container>
```

Rocket does **not** try to morph this HTML into SVG. The children are hidden
custom elements that translate their attributes into events the container
consumes.

### Pattern: Declarative-Child Custom Elements (hidden wrapper → emit snapshot)

The cleanest way to let the server drive a list of items inside an imperative
Rocket container. Each child is a Rocket component that:

1. Sets `host.style.display = 'none'` in `setup`.
2. Emits `<name>-register` on mount (via `queueMicrotask` so attributes are set).
3. Emits `<name>-update` on any prop or attribute change (`MutationObserver` + `effect`).
4. Emits `<name>-remove` in `cleanup`.

```js
rocket('flow-node', {
  props: ({ number, string }) => ({
    x: number, y: number, label: string,
    width: number.min(1).default(120),
    height: number.min(1).default(48),
  }),
  render: ({ html }) => html``,           // no visible render
  setup({ host, props, effect, cleanup, emit }) {
    host.style.display = 'none'

    const snapshot = () => ({
      id: host.getAttribute('id') ?? '',
      x: props.x, y: props.y, label: props.label,
      width: props.width, height: props.height,
      content: collectCustomContent() ?? createDefaultContent(),
    })

    // 1. MutationObserver catches raw attribute writes (incoming SSE patches)
    const observer = new MutationObserver(() =>
      queueMicrotask(() => emit('flow-node-update', snapshot())))
    observer.observe(host, {
      childList: true, subtree: true, characterData: true, attributes: true,
    })

    // 2. effect() catches reactive prop changes from `data-attr:*` bindings
    effect(() => {
      props.x; props.y; props.label; props.width; props.height   // touch to subscribe
      emit('flow-node-update', snapshot())
    })

    // 3. Register on mount (microtask so attrs are in place)
    queueMicrotask(() => emit('flow-node-register', snapshot()))

    cleanup(() => {
      observer.disconnect()
      emit('flow-node-remove', { id: host.getAttribute('id') })
    })
  },
})
```

**Why both MutationObserver AND `effect()`?** MutationObserver catches raw
attribute writes (e.g. `el.setAttribute('x', …)` from the parent's drag
handler, or incoming SSE patches that rewrite attributes). `effect()` catches
reactive prop changes from `data-attr:*` bindings to page signals. Together
they handle every source of change.

**Container side** — single `host` listener for each event:

```js
rocket('flow-container', {
  setup({ host, cleanup }) {
    const onRegister = (evt) => { /* …add to entries map, render… */ }
    const onUpdate   = (evt) => { /* …update entry, schedule render… */ }
    const onRemove   = (evt) => { /* …remove from entries map, render… */ }

    host.addEventListener('flow-node-register', onRegister)
    host.addEventListener('flow-node-update',   onUpdate)
    host.addEventListener('flow-node-remove',   onRemove)
    // …same 3 for flow-edge-*

    cleanup(() => {
      host.removeEventListener('flow-node-register', onRegister)
      // …
    })
  },
})
```

**Plus a hide-on-insert guard** so children never flash visible during
incoming SSE patches:

```js
const hideFlowChild = (node) => {
  if (node instanceof HTMLElement &&
      (node.tagName === 'FLOW-NODE' || node.tagName === 'FLOW-EDGE'))
    node.style.display = 'none'
}
const childObserver = new MutationObserver((mutations) => {
  for (const m of mutations) for (const n of m.addedNodes) hideFlowChild(n)
})
childObserver.observe(host, { childList: true })
queueMicrotask(() => Array.from(host.children).forEach(hideFlowChild))
```

**When to use:** any Rocket container that needs to render a server-controlled
list of items with rich per-item state — timeline clips, whiteboard shapes,
story scenes, transcript segments, scene cards. Keeps the server as source of
truth while letting the container own interactive rendering.

### Pattern: Server Reconciliation via `serverUpdateTime` Pulse

Optimistic UI needs a clean way to clear pending markers when the server's
authoritative state arrives. Use a `date`-typed prop that bumps on every
server broadcast:

```js
rocket('flow-container', {
  props: ({ date }) => ({
    serverUpdateTime: date.default(() => new Date()),
  }),
  setup({ observeProps, props }) {
    let lastServerUpdateTime = Number.NaN

    observeProps(() => {
      const next = props.serverUpdateTime.getTime()
      if (next === lastServerUpdateTime) return    // guard against spurious reruns
      lastServerUpdateTime = next
      clearPendingState()
      clearSelectedEdge()
    }, 'serverUpdateTime')
  },
})
```

**Why this works:** the server's SSE patch rewrites both (a) the canonical
node attributes (`x`, `y`) and (b) the container's `server-update-time`
attribute. MutationObservers on the children fire first → container snaps
nodes to authoritative positions. Then the prop change on the container fires
→ pending/faded classes clear. **User sees: position snap + un-fade in a
single frame.**

The guard (`if (next === lastServerUpdateTime) return`) is essential because
reactive proxy reads can fire `observeProps` even without a real value change.

**Use this anywhere** you have optimistic UI + server authority — save
indicators, move/resize handles, voting, edit conflicts. Beats tracking
per-item pending flags.

### Pattern: Viewport Math for SVG Pan + Zoom

Store the viewport as `[centerX, centerY, zoom]`. Every pan/zoom/resize
recomputes:

```js
const schedule = () => {
  if (frame) return
  frame = requestAnimationFrame(() => {
    frame = 0
    const [cx, cy, zoom] = viewport
    const rect = svg.getBoundingClientRect()
    metrics.screenWidth  = Math.max(1, rect.width)
    metrics.screenHeight = Math.max(1, rect.height)
    metrics.zoom         = zoom
    metrics.worldWidth   = metrics.screenWidth  / zoom
    metrics.worldHeight  = metrics.screenHeight / zoom
    metrics.minX         = cx - metrics.worldWidth  / 2
    metrics.minY         = cy - metrics.worldHeight / 2
    svg.setAttribute('viewBox',
      `${metrics.minX} ${metrics.minY} ${metrics.worldWidth} ${metrics.worldHeight}`)
    // …update background rect, grid pattern, emit viewport-change…
  })
}
```

**Pan** — only when pointer targets the SVG root or background rect (not a node):

```js
const pointerDown = (evt) => {
  if (evt.button !== 0 || (evt.target !== svg && evt.target !== background)) return
  evt.preventDefault()
  const origin = [...viewport]
  svg.setPointerCapture(evt.pointerId)
  const move = (e) => {
    const scale = 1 / origin[2]
    viewport = [
      origin[0] - (e.clientX - evt.clientX) * scale,
      origin[1] - (e.clientY - evt.clientY) * scale,
      origin[2],
    ]
    schedule()
  }
  // + pointerup/pointercancel to release capture and remove listeners
}
```

**Cursor-pinned zoom** — point under cursor stays put:

```js
const handleWheel = (evt) => {
  evt.preventDefault()
  const rect = svg.getBoundingClientRect()
  const zoom = metrics.zoom
  const nextZoom = clampZoom(zoom * 1.2 ** (-evt.deltaY / 120))
  if (nextZoom === zoom) return
  const px = evt.clientX - rect.left
  const py = evt.clientY - rect.top
  const focusX = metrics.minX + (px / rect.width)  * metrics.worldWidth
  const focusY = metrics.minY + (py / rect.height) * metrics.worldHeight
  const nextW  = metrics.screenWidth  / nextZoom
  const nextH  = metrics.screenHeight / nextZoom
  const minX   = focusX - (px / rect.width)  * nextW
  const minY   = focusY - (py / rect.height) * nextH
  viewport = [minX + nextW / 2, minY + nextH / 2, nextZoom]
  schedule()
}
svg.addEventListener('wheel', handleWheel, { passive: false })
```

Clamp: `Math.min(16, Math.max(0.05, zoom))`. Attach wheel as non-passive so
`preventDefault()` actually blocks page scroll.

Emit a `viewport-change` CustomEvent (via `emit` in setup context) so the
page can `@post` the new viewport to the server. Debounce by signature
string (`"${minX}|${minY}|${zoom}|${w}|${h}"`) to avoid event spam on
identical viewports.

### Pattern: Pointer-Capture Drag on SVG Elements

Canonical drag with pointer capture — works cleanly when cursor leaves the
element bounds:

```js
group.addEventListener('pointerdown', (evt) => {
  if (evt.button !== 0) return
  evt.preventDefault()
  evt.stopPropagation()                             // critical — don't also pan
  const pointerId = evt.pointerId
  const drag = { pointerId, startX: entry.x, startY: entry.y,
                 startClientX: evt.clientX, startClientY: evt.clientY }
  activeNodeDrags.set(pointerId, drag)
  group.setPointerCapture(pointerId)
  group.classList.add('is-dragging')
  emitNodeEvent(entry, 'flow-node-drag-start', { pointerId, origin: {x: startX, y: startY} })

  const move = (event) => {
    if (event.pointerId !== pointerId) return
    entry.x = drag.startX + (event.clientX - drag.startClientX) *
              (metrics.worldWidth / metrics.screenWidth)
    entry.y = drag.startY + (event.clientY - drag.startClientY) *
              (metrics.worldHeight / metrics.screenHeight)
    positionNode(entry)
    emitNodeEvent(entry, 'flow-node-drag', { pointerId, origin })
  }
  const finish = (event, type) => {
    if (event.pointerId !== pointerId) return
    activeNodeDrags.delete(pointerId)
    group.releasePointerCapture(pointerId)
    group.classList.remove('is-dragging')
    window.removeEventListener('pointermove', move, true)
    window.removeEventListener('pointerup', end, true)
    window.removeEventListener('pointercancel', cancel, true)
    if (type === 'cancel') {
      emitNodeEvent(entry, 'flow-node-drag-cancel', { pointerId, origin })
      return
    }
    emitNodeEvent(entry, 'flow-node-drag-end', { pointerId, origin, source: 'drag',
                                                  x: entry.x, y: entry.y })
    // write optimistic value back to the wrapper element —
    // its MutationObserver re-emits flow-node-update to keep container in sync
    entry.el.setAttribute('x', String(entry.x))
    entry.el.setAttribute('y', String(entry.y))
    emitNodeEvent(entry, 'flow-node-update', { pointerId, origin, source: 'drag',
                                                x: entry.x, y: entry.y })
  }
  const end    = (e) => finish(e, 'end')
  const cancel = (e) => finish(e, 'cancel')
  window.addEventListener('pointermove',   move,   true)
  window.addEventListener('pointerup',     end,    true)
  window.addEventListener('pointercancel', cancel, true)
})
```

**The crucial moves:**
- `stopPropagation()` on pointerdown so the container's pan handler doesn't also fire.
- `setPointerCapture` so drag keeps working when cursor leaves the shape.
- Convert screen pixels to world units via `metrics.worldWidth / metrics.screenWidth`.
- Attach `pointermove`/`pointerup`/`pointercancel` to **window in capture phase** (`true`)
  so fast drags that leave the SVG don't break.
- On drag-end, **write the optimistic value back to the wrapper element's attribute**
  — keeps the declarative model consistent with imperative render.
- The `source: 'drag'` field lets the page distinguish user-driven moves
  (should POST to server) from server-driven moves (should not).

### Pattern: rAF-Batched Render Schedulers

Coalesce expensive updates into one frame per rAF. Three independent
schedulers in `rocket_flow`:

```js
let frame = 0          // viewport/metrics
let graphFrame = 0     // node positions
let edgeFrameId = 0    // edge bezier paths

const schedule = () => {
  if (frame) return
  frame = requestAnimationFrame(() => { frame = 0; /* …work… */ })
}

const scheduleNodeRender = () => {
  if (graphFrame) return
  graphFrame = requestAnimationFrame(() => { graphFrame = 0; renderNodes() })
}

const scheduleEdgeRender = () => {
  if (!edges.size || edgeFramePending) return
  edgeFramePending = true
  edgeFrameId = requestAnimationFrame(() => {
    edgeFramePending = false; edgeFrameId = 0
    /* …repaint all edges… */
  })
}
```

Call them anywhere that needs a visual refresh — register/update/remove,
pan, zoom, resize. They collapse N calls in a single tick into one render
pass.

**Always `cancelAnimationFrame` in `cleanup`** for every frame id you track.

### Pattern: `host.rocketInstanceId` for Unique DOM IDs

SVG references like `url(#gridPattern)` must be globally unique. Multiple
instances of the same Rocket component would collide. Solution: scope every
internal ID with `host.rocketInstanceId`:

```js
setup({ host }) {
  const patternId = `flow-grid-${host.rocketInstanceId ?? ''}`
  gridPattern.id = patternId
  background.setAttribute('fill', `url(#${patternId})`)
}
```

Also useful for `<filter id="…">`, `<clipPath id="…">`, `<mask id="…">`,
`<linearGradient id="…">`, and ARIA `aria-controls`/`aria-describedby` inside
a component.

### Pattern: Debouncing Event Emission by Signature

Viewport events should only fire when the viewport actually changed. Track
the last emitted state as a stable string and compare:

```js
const signature = `${metrics.minX}|${metrics.minY}|${metrics.zoom}|${metrics.screenWidth}|${metrics.screenHeight}`
if (signature !== lastSignature) {
  lastSignature = signature
  emit('viewport-change', { minX, minY, zoom, width, height })
}
```

Cheaper than deep-equal checks. Good for any "only emit on actual change" case.

### Pattern: SVG Content Projection from Light-DOM Children

When declarative children carry custom SVG markup, you can't just
`append(child)` — HTML-parsed elements aren't in the SVG namespace, and some
attribute names need case correction (`viewBox`, `preserveAspectRatio`, etc.).
Use a recursive cloner:

```js
const SVG_NS = 'http://www.w3.org/2000/svg'
const SVG_ATTR_CASE_MAP = {
  viewbox: 'viewBox', preserveaspectratio: 'preserveAspectRatio',
  patternunits: 'patternUnits', /* …see full map in rocket_flow.md… */
}
const cloneNodeIntoSvg = (node) => {
  if (!node) return null
  if (node.nodeType === Node.TEXT_NODE) {
    const text = node.textContent ?? ''
    return text.trim() ? document.createTextNode(text) : null
  }
  if (node.tagName === 'SLOT' || node.tagName === 'SCRIPT' || node.tagName === 'STYLE') return null
  if (node.tagName === 'TEMPLATE') {
    const frag = document.createDocumentFragment()
    node.content.childNodes.forEach(c => { const cl = cloneNodeIntoSvg(c); if (cl) frag.append(cl) })
    return frag
  }
  const clone = document.createElementNS(SVG_NS, node.localName.toLowerCase())
  for (const attr of node.attributes) {
    clone.setAttribute(SVG_ATTR_CASE_MAP[attr.name.toLowerCase()] ?? attr.name, attr.value)
  }
  node.childNodes.forEach(c => { const cl = cloneNodeIntoSvg(c); if (cl) clone.append(cl) })
  return clone
}
```

Pair with a `createDefaultContent()` fallback when no light-DOM children are supplied.

### Pattern: Bezier Edge Routing

Minimal, looks right for both horizontal-dominant and vertical-dominant edges:

```js
const bezierPathPoints = (sx, sy, tx, ty) => {
  const dx = tx - sx, dy = ty - sy
  if (Math.abs(dx) >= Math.abs(dy)) {
    const midX = sx + dx * 0.5
    return { c1x: midX, c1y: sy, c2x: midX, c2y: ty }      // horizontal S-curve
  }
  const midY = sy + dy * 0.5
  return { c1x: sx, c1y: midY, c2x: tx, c2y: midY }        // vertical S-curve
}
// path 'd' = `M sx sy C c1x c1y, c2x c2y, tx ty`
```

### Pattern: Keyboard Shortcuts with Focus Restoration

Delete-edge workflow: click edge → `host.focus({ preventScroll: true })` →
Delete key fires `flow-edge-delete-request`. The focus call is essential —
without it, keydown never lands on the component.

```js
setup({ host, emit }) {
  host.setAttribute('tabindex', '0')
  host.addEventListener('keydown', (evt) => {
    if (!selectedEdgeKey || (evt.key !== 'Backspace' && evt.key !== 'Delete')) return
    evt.preventDefault()
    emit('flow-edge-delete-request', { id, sourceId, targetId })
  })
}
```

### Why this architecture is good for server-authoritative editors

- **Server owns the graph.** Nodes/edges are HTML attributes on custom elements.
  Undo/redo, multi-tab broadcast, conflict resolution, history — all server.
- **Rocket owns interaction.** Drag, pan, zoom, selection, rAF batching,
  optimistic UI, pointer capture — all in one place, zero server round-trips
  per frame.
- **Bubbling-event bus keeps components decoupled.** `flow-node` doesn't know
  about `flow-container`. You can swap the container, keep the nodes. Build
  different containers (mini-map, tree view) that listen to the same events.
- **Attribute-writeback keeps declarative and imperative in sync.** Drag writes
  `entry.el.setAttribute('x', …)`; MutationObserver re-emits; everyone agrees.
- **`serverUpdateTime` pulse** is a single, clean signal for "server
  acknowledged — clear optimistic state." No per-item pending bookkeeping.
- **Cleanup discipline.** Every listener, observer, rAF handle, pointer
  capture registered in `setup` is released in `cleanup`.

---

## Custom Plugins (Action + Attribute)

Datastar lets you register new `@actions` and `data-*` attributes via the
plugin API.

```js
import { action, attribute } from 'datastar'

// @alert('hi') — custom action
action({
  name: 'alert',
  apply(ctx, value) { alert(value) },
})

// data-alert="…" — custom attribute
attribute({
  name: 'alert',
  requirement: { key: 'denied', value: 'must' },   // no :key allowed; value required
  returnsValue: true,                              // expression returns a value via rx()
  apply({ el, rx }) {
    const cb = () => alert(rx())
    el.addEventListener('click', cb)
    return () => el.removeEventListener('click', cb)   // returned fn is the cleanup
  },
})
```

`requirement` shape:
- `{ key: 'denied' | 'allowed' | 'must', value: 'denied' | 'allowed' | 'must' }`
- `key` controls whether `data-xxx:my-key` is allowed
- `value` controls whether the attribute needs a value

`returnsValue: true` means the expression produces a value read via `rx()`
(re-evaluates on signal changes). Without it, `rx` runs the expression for
side effects only.

---

## StateTree + Datastar Integration

### Effects vs Transient Context for SSE Side-Effects

**CRITICAL:** If you use a StateTree engine with `strip_transient()`,
transient context fields (`#[serde(skip)]`) are wiped BEFORE the caller can
read them. Do NOT rely on transient flags like `ctx.saved` to trigger SSE
side-effects — they will always be `false` by the time
`broadcast_state_update` fires.

**Use `TaskResult::Effect` instead.** Effects travel through
`EventProcessingResult.execution_results`, which survives `strip_transient`.
Handle SSE side-effects in `handle_effects()`:

```rust
// In the task — emit an effect
Ok(TaskResult::Effect(Effect {
    effect_type: "save_ack".into(),
    payload: Value::String(format!("Saved as version {version}.")),
}))

// In handle_effects — dispatch SSE
"save_ack" => {
    if let Some(text) = effect.payload.as_str() {
        self.broadcast_context_msg("ai", text);
    }
    let content_id = self.context_data.borrow().content_id.clone().unwrap_or_default();
    if !content_id.is_empty() {
        let mut acc = sse::accumulator();
        acc.add_event(
            sse::patch_elements(format!(
                r#"<script data-effect="el.remove()">window.history.replaceState({{}},'','/v2/{content_id}')</script>"#
            )).selector("body").mode(PatchMode::Append),
        );
        if let Ok(msg) = acc.build() {
            self.broadcast_sse(&msg.to_sse_string());
        }
    }
}
```

**Rule:** `broadcast_state_update()` is a pure state broadcaster — no
parameters, no side-effects. All event-driven SSE side-effects (URL updates,
notifications, cleanup) go through `handle_effects`.

---

## Anti-Patterns

❌ Sending data objects as signals instead of rendering HTML
❌ Complex logic in expressions (extract to functions or web components)
❌ Elements without stable IDs (morphing won't work correctly)
❌ URL state (pagination, filters) in signals instead of the URL
❌ Using WebSockets for UI updates when SSE handles it fine
❌ Side effects in `data-computed` (use `data-effect` instead)
❌ Side effects in Rocket `render` (move to `setup` / `effect` / `onFirstRender`)
❌ Module-top-level `addEventListener`/`effect`/`ResizeObserver` (must live inside a component)
❌ Mutating `data-replace-url` for one-shot URL updates after save (use the self-removing script pattern)
❌ Cache-busting `<script type="module" src="datastar-pro.js?v=…">` while components `import` from the bare path — creates two engine instances and hangs the browser. See "Critical: ES Module URL Identity" above.

---

## Security

- Datastar does NOT escape values — sanitize all user data server-side before patching
- All signals from the browser are untrusted — validate like form fields
- `_` prefix is a convenience, not a security boundary
- Signal values are visible in source and modifiable by users — never store secrets in signals
- CSRF: include tokens in signal state or request headers
- `@` actions run in sandboxed `Function()` context — but `Function()` requires `unsafe-eval` in CSP:
  ```
  Content-Security-Policy: script-src 'self' 'unsafe-eval'
  ```
- Use `data-ignore` to prevent Datastar from processing untrusted content subtrees

---

## Quick Reference

```
Free attrs (21):
  Signals:     data-signals  data-bind  data-computed  data-ref  data-json-signals
  DOM:         data-text  data-show  data-class  data-attr  data-style
               data-cloak  data-ignore  data-ignore-morph  data-preserve-attr
  Events:      data-on  data-on-intersect  data-on-interval
               data-on-signal-patch  data-on-signal-patch-filter
               data-indicator  data-effect  data-init

Pro attrs (10):
  data-animate  data-custom-validity  data-match-media
  data-on-raf  data-on-resize  data-persist  data-query-string
  data-replace-url  data-scroll-into-view  data-view-transition

Core actions (8):
  Sync:        @peek  @setAll  @toggleAll
  Backend:     @get  @post  @put  @patch  @delete   (all support full options object)

Pro actions (3):
  @clipboard(text, isBase64?)  @fit(v, oMin, oMax, nMin, nMax, clamp?, round?)
  @intl(type, value, options?, locales?)

Signal rule:
  $name      page-level signal, sent to server
  $_name     page-level private signal, never sent
  $$name     Rocket-local signal (in template) / $$.name (in setup), never sent

Request:
  GET  → ?datastar={"k":"v"}
  POST → {"k": "v"} body                  (header: Datastar-Request: true)

SSE event types (only two):
  datastar-patch-elements   primary — HTML → idiomorph(or replace) → DOM
                            modes: outer (default), inner, replace, prepend,
                            append, before, after, remove
                            options: selector, mode, useViewTransition, namespace
  datastar-patch-signals    secondary — transient state only
                            options: onlyIfMissing

Rocket — shipping JS-call API:
  Define:    rocket('tag-name', {
               props: ({ string, number, bool, date, json, js, bin,
                         array, object, oneOf }) => ({
                 name: string.trim.maxLength(50).default(''),
                 count: number.clamp(0, 100).default(0),
                 ...
               }),
               refs: { input: HTMLInputElement },
               mode: 'light' | 'open' | 'closed',
               renderOnPropChange: true | false | (ctx) => boolean,
               manifest: { slots: [...], events: [...] },
               setup({ props, $, $$, effect, cleanup, actions, action,
                       emit, emitCancellable, observeProps, overrideProp,
                       defineHostProp, apply, adoptStyles, host, render }) {...},
               onFirstRender({ refs, ...same as setup }) {...},
               render({ html, svg, props, host }) { return html`...` },
             })

  Codecs (chainable):
    string  .trim .upper .lower .kebab .camel .snake .pascal .title
            .prefix(s) .suffix(s) .maxLength(n) .default(v)
    number  .min(n) .max(n) .clamp(lo,hi) .step(s,base?) .round
            .ceil(d?) .floor(d?) .fit(...) .default(v)
    bool .default(v)
    date .default(v)
    json .default(v)
    js .default(v)
    bin .default(v)
    array(c) | array(c1,c2,...) — homogeneous OR tuple, .default(v)
    object({field: codec}) .default(v)
    oneOf(v1,v2,...) | oneOf(c1,c2,...) .default(v)

  Setup scope:
    props (decoded), $ (page root), $$ (component-local callable proxy),
    effect, cleanup, apply, adoptStyles, emit, emitCancellable,
    actions, action, observeProps, overrideProp, defineHostProp,
    render, host

  onFirstRender scope:  setup scope + refs (typed by `refs` map)
  render scope:         html, svg, props, host  (PURE — no side effects)

  Signals:    $$name (template) / $$.name (setup) — auto-scoped to
              _rocket.<tag>.<instanceId>.name
              data-ref:<name> populates refs.<name> in onFirstRender

  Lifecycle:  connectedCallback → decode props → run setup → render → apply
              datastar → hydrate refs → onFirstRender
              prop change → observeProps → coalesce render → render → apply
              disconnectedCallback → cleanup callbacks → effect disposers →
              actions deregistered → instance state removed

  Render mode: light (default, with auto CSS scoping) | open | closed shadow
  Events:      emit('name'), emit('name', detail, options?), emitCancellable

Architectural rule:  every client-side subsystem is a Rocket component OR a pure
                     helper module. No top-level addEventListener/effect/
                     ResizeObserver anywhere.

Pro inventory paths (read for ground truth):
  Pro attrs:       ~/Projects/github/datastar-pro/library/src/pro/attributes/
  Pro actions:     ~/Projects/github/datastar-pro/library/src/pro/actions/
  Rocket runtime:  ~/Projects/github/datastar-pro/library/src/pro/rocket/runtime.ts
  Rocket codecs:   ~/Projects/github/datastar-pro/library/src/pro/rocket/codecs.ts
  Inspector:       ~/Projects/github/datastar-pro/webcomponents/datastar-inspector/src/index.ts
  Examples:        ~/Projects/EveryGoodWork/temp/datastar-examples/
  Live docs:       https://data-star.dev/

OLD template-based API (REMOVED in beta.1):
  <template data-rocket:name data-prop:* data-schema:* data-import:*>
    <script data-static>...</script>
    <script>...</script>
    ...rendered template markup...
  </template>

  → DOES NOT WORK in shipping Pro. If you see this in old code or docs,
  translate to the JS-call rocket(tag, {props, setup, render, ...}) shape above.
```
