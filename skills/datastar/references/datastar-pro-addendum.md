# Datastar Pro Addendum (from source)

Source: `~/Projects/github/datastar-pro/` v1.0.4, commit 8f64418. Paths below are relative to `library/src/`. Private: Peter holds a Pro license.

Verified by reading source; items marked `[runtime-verified]` were also executed (esbuild / node). Items marked `[unverified]` could not be checked from the checkout.

## Engine rules shared by every attribute

| Rule | Behavior | Cite |
|---|---|---|
| Key / value requirement | `must` / `denied` / `allowed` (default) per side; string form applies to both. Violations throw `KeyRequired`, `KeyNotAllowed`, `ValueRequired`, `ValueNotAllowed` | engine/engine.ts:L295-333 |
| Modifiers | `__label.tag1.tag2` -> `mods.get('label') = Set{tag1,tag2}` | engine/engine.ts:L192-209 |
| Time tags | `tagToMs` reads the FIRST tag only: `300ms`, `1.5s`, bare number = ms. Put the time tag first | utils/tags.ts:L1-12 |
| `returnsValue: true` | Last `;`-statement of the expression is auto-returned | engine/engine.ts:L385-420 |
| Errors | `Error` whose message is `Reason\nMore info: https://data-star.dev/errors/<snake_reason>?metadata=...` | engine/errors.ts:L5-17 |
| `data-ignore` / `data-ignore__self` | Element and subtree skipped; name is aliased like every other attribute | engine/engine.ts:L114-117 |

## Pro attributes

| Attribute | Key | Value | Reactive | Cite |
|---|---|---|---|---|
| `data-animate` | allowed (attr name) | must (number+suffix, or object when no key) | effect | pro/attributes/animate.ts:L11-17 |
| `data-custom-validity` | denied | must (string) | effect | pro/attributes/customValidity.ts:L8-14 |
| `data-match-media` | must (signal name) | must (raw media query, NOT an expression) | listener | pro/attributes/matchMedia.ts:L9-15 |
| `data-on-raf` | denied | must | every frame | pro/attributes/onRaf.ts:L10-16 |
| `data-on-resize` | denied | must | ResizeObserver | pro/attributes/onResize.ts:L10-16 |
| `data-persist` | allowed (storage key) | allowed (`{include, exclude}`) | effect | pro/attributes/persist.ts:L9-14 |
| `data-query-string` | denied | allowed (`{include, exclude}`) | effect + popstate | pro/attributes/queryString.ts:L10-17 |
| `data-replace-url` | denied | must (URL string) | effect | pro/attributes/replaceUrl.ts:L8-15 |
| `data-scroll-into-view` | denied | denied | once at apply | pro/attributes/scrollIntoView.ts:L24-27 |
| `data-view-transition` | denied | must (string) | effect | pro/attributes/viewTransition.ts:L9-16 |

### `data-animate`

`<rect data-animate:width__duration.500ms__ease.outcubic="$w + 'px'">` or `<rect data-animate__duration.300ms="{x: $x, opacity: $alpha}">`

| Modifier | Tags | Default | Cite |
|---|---|---|---|
| `__duration` | time | 1000ms | L18-22 |
| `__ease` | one easing name (first tag) | `linear` | L23-30 |
| `__delay` | time | 0 | L31-35 |
| `__loop` | none | off; restarts from start value | L68-80 |
| `__pingpong` | none | off; swaps start/end each cycle | L73-77 |

Easing names: `linear quadratic cubic elastic inquad outquad inoutquad incubic outcubic inoutcubic inquart outquart inoutquart inquint outquint inoutquint insine outsine inoutsine inexpo outexpo inoutexpo incirc outcirc inoutcirc inelastic outelastic inoutelastic inback outback inoutback inbounce outbounce inoutbounce ingolden outgolden inoutgolden` (L133-295).

Behavior: start value = current attribute, or `0<suffix>` when absent (L44); equal start/target sets directly (L45-48); new target cancels in-flight rAF (L59); value regex `^-?\d*\.?\d+[a-z%]*$` (L119); key is the raw attribute name passed to `setAttribute`, so camelCase SVG attributes like `viewBox` cannot be targeted (attribute keys arrive lowercased).

Errors: `AnimateInvalidEasing {easing, available}` (L26), `AnimateSuffixMismatch` (L51), `AnimateInvalidValue {value}` (L126).

Bug `[runtime-verified]`: `inbounce`, `inoutbounce`, `inoutgolden` reference `Easing.outBounce` / `inBounce` / `inGolden` / `outGolden` (camelCase) but keys are lowercase -> `TypeError: Easing.outBounce is not a function` on the first frame (L267, L285-286, L292-293). `outbounce`, `ingolden`, `outgolden` work.

### `data-custom-validity`

`<input data-bind:email data-custom-validity="$email.includes('@') ? '' : 'Needs @'">`

Element must be `input|select|textarea` else `CustomValidityInvalidElement` (L16-26). Expression must return a string else `CustomValidityInvalidExpression` (L29-33). Empty string = valid.

### `data-match-media`

`<div data-match-media:is-dark="prefers-color-scheme: dark">` -> `$isDark`

| Modifier | Tags | Default | Cite |
|---|---|---|---|
| `__case` | `camel` / `snake` / `pascal` | camel | utils/text.ts:L68-77 |

Value is read raw: trimmed, surrounding quotes stripped, wrapped in `()` if it has no parens (L17-21). `matchMedia` failure is swallowed -> signal `false` (L23-26). Cleanup sets the signal to `null`, not removed (L36).

### `data-on-raf` / `data-on-resize`

`<canvas data-on-raf__throttle.16ms="@draw()">` / `<div data-on-resize__debounce.100ms="$w = el.clientWidth">`

| Modifier | Tags | Cite |
|---|---|---|
| `__viewtransition` | none; wraps in `document.startViewTransition` when supported | utils/view-transitions.ts:L7-18 |
| `__delay` | time | utils/timing.ts:L49-53 |
| `__debounce` | time, `leading`, `notrailing` (trailing on by default) | utils/timing.ts:L55-61 |
| `__throttle` | time, `noleading`, `trailing` (leading on by default) | utils/timing.ts:L63-69 |

Signal writes inside the expression are batched (`beginBatch`/`endBatch`, onRaf.ts:L17-24). `on-resize` runs once on observe (ResizeObserver spec) and disconnects on cleanup (L27-36). `on-raf` cancels the frame on cleanup (L33-37). Wrap order: viewtransition inner, timing outer.

### `data-persist`

`<div data-persist>` / `<div data-persist:prefs__session="{include: /^ui\./, exclude: /token/}">`

| Modifier | Default | Cite |
|---|---|---|
| `__session` | localStorage; tag switches to sessionStorage | L14 |

Storage key = raw key or `datastar` (L13). On apply: synchronously `mergePatch`es the whole parsed JSON, filter NOT applied on load (L17-25); parse failure -> `console.error`, no throw (L22-24). Then an effect writes `filtered(rx())` as JSON on every change (L27-31). `include`/`exclude` accept RegExp or string, matched against dotted paths; defaults `/.*/` and `/(?!)/` (engine/signals.ts:L760-782).

### `data-query-string`

`<div data-query-string__history__filter="{include: /^filter\./}">`

| Modifier | Behavior | Cite |
|---|---|---|
| `__history` | `pushState` instead of `replaceState`; registers `popstate` handler that re-reads URL into signals | L17, L69-77, L110-114 |
| `__filter` | omit falsy values from the URL | L97 |

Load: for each path in the filtered signal tree that has a URL param, coerce `true`/`false`/numeric, else string (L43-62). Only paths already present in signals are read; unknown params are ignored. Write: rebuilds the entire `?` string from filtered signals, so non-signal params (e.g. `utm_*`) are dropped (L85-115); `null` and arrays: arrays serialize as `path.0=`, `null` is skipped (L94-100). URL not written during popstate (L81-83).

### `data-replace-url`

`<div data-replace-url="'/items/' + $id">`

Resolves against `location.href` (relative paths allowed) and calls `history.replaceState` on every dependency change (L16-21). A bare `/v2/x` value parses as a regex literal; quote it.

### `data-scroll-into-view`

`<li data-scroll-into-view__instant__vstart__focus>`

| Group | Tags | Default | Cite |
|---|---|---|---|
| behavior | `smooth` `instant` `auto` | smooth | L29, L33-35 |
| inline | `hstart` `hcenter` `hend` `hnearest` | center | L31, L36-39 |
| block | `vstart` `vcenter` `vend` `vnearest` | center | L30, L40-43 |
| extra | `focus` | off | L50-52 |

Runs once when the attribute is applied; not an effect. Sets `tabindex="0"` when `el.tabIndex` is 0/falsy (L45-47); a `-1` is left alone.

### `data-view-transition`

`<div data-view-transition="'card-' + $id">`

Silently no-op when `startViewTransition` is unsupported (L17-19). Sets `style.viewTransitionName` only when the value is truthy; never clears it (L20-25).

## Pro actions

| Action | Signature | Returns | Errors | Cite |
|---|---|---|---|---|
| `@clipboard` | `(text, isBase64 = false)` | `undefined` (promise not returned or awaited) | `ClipboardNotAvailable` | pro/actions/clipboard.ts:L7-16 |
| `@fit` | `(v, oldMin, oldMax, newMin, newMax, shouldClamp = false, shouldRound = false)` | number | none | pro/actions/fit.ts:L8-25 |
| `@intl` | `(type, value, options, locales?)` | string | `IntlInvalidDate`, `IntlTypeNotSupported` | pro/actions/intl.ts:L7-61 |

`@intl` types (L17-59): `datetime`, `number`, `pluralRules`, `relativeTime`, `list`, `displayNames`. Locale = `locales || navigator.language || 'en-US'` (L16).

`@intl` caveats `[runtime-verified]`:
- `options` is positionally required for `relativeTime` and `displayNames` (`options.unit` / `options.type` dereference -> TypeError when omitted); other types accept `undefined`.
- `relativeTime` reads `options.unit?.[0]` (L38): a string `unit: 'day'` yields `'d'` -> `RangeError: Invalid unit argument`. Pass an array: `@intl('relativeTime', -3, {unit: ['day']})`.
- `displayNames` defaults `type` to `language` (L50).

Examples: `@clipboard($code)`, `@fit($r, 0, 100, 0, 255, true, true)`, `@intl('number', $price, {style: 'currency', currency: 'USD'})`.

## Datastar Inspector

Source: `webcomponents/datastar-inspector/src/index.ts` (+ `template.html`), tsconfig at `webcomponents/tsconfig.json`.

| Fact | Detail | Cite |
|---|---|---|
| Element | `<datastar-inspector max-events-visible="50"></datastar-inspector>`, open shadow DOM | L2086, L37 |
| Observed attributes | only `max-events-visible` (default 20, must be > 0) | L8-10, L15, L82-88, L126-137 |
| Tabs | `currentSignals`, `signalPatchEvent`, `sseEvent`, `persistedData` | template.html:L768-783 |
| Listens | `document` `datastar-signal-patch`, `document` `datastar-fetch`, `window` `storage` | L73-80 |
| SSE tab filter | shows only `detail.type` starting `datastar-` (SSE event names); lifecycle `started/finished/error/retrying/retries-failed` are dropped | L823-826; plugins/actions/fetch.ts:L248-259 |
| Signals tab | rebuilt by replaying `datastar-signal-patch` events, not read from the engine; patches before the element connects are missed. Load the inspector before Datastar | L698-718 |
| Persisted tab | keys derived by scanning DOM for `data-persist*` attributes; reads local or session storage per toggle | L1452-1478, L1437-1440 |
| Highlight | hovering a signal path highlights elements whose `data-*` values reference `$path` | L1190-1240 |
| UI state | `sessionStorage['datastar-inspector-state']`: expanded, open, tab, filters, table views, storage toggle | L39-70, L897-913 |
| Theme | follows `prefers-color-scheme` | L104-110 |
| Needs Pro bundle? | No. It imports nothing from the library and reads only public document events; works with the free bundle | L1-5 |
| Aliased bundles | `ALIAS` is declared but unused (L3); persist-key scan hardcodes `data-persist`, so the Persisted tab is empty under an alias | L1457-1470 |

Bug (by reading, not run): key scan matches `data-persist-<key>` but the real attribute is `data-persist:<key>`, so only the default `datastar` key is counted (L1459-1470).

Build `[runtime-verified]`:

```bash
npx esbuild webcomponents/datastar-inspector/src/index.ts --bundle --format=esm --minify \
  --loader:.html=text --tsconfig=webcomponents/tsconfig.json --outfile=<static>/datastar-inspector.js
```

Without `--loader:.html=text` esbuild fails on `import datastarTemplate from './template.html'`. No `--define:ALIAS` needed. Output 64.5 kB minified.

## Bundles and aliasing

| Bundle (`bundles/`) | Free plugins (21 attrs + 4 actions + 2 watchers) | Pro plugins (10 + 3) | Rocket export | Cite |
|---|---|---|---|---|
| `datastar-core.ts` | none; exports engine + signals API only | no | no | L1-17 |
| `datastar.ts` | yes | no | no | L19-41 |
| `datastar-aliased.ts` | yes | no | no | identical source to `datastar.ts` |
| `datastar-rocket.ts` / `-aliased.ts` | yes | no | yes | L44-52 |
| `datastar-pro.ts` / `-aliased.ts` | yes | yes | yes | L42-54, L57-65 |

Free plugin list (every non-core bundle): actions `peek setAll toggleAll fetch`; attributes `attr bind class computed effect indicator init jsonSignals on onIntersect onInterval onSignalPatch ref show signals style text`; watchers `patchElements patchSignals` (datastar.ts:L19-41).

Pro adds over `datastar.ts`: the 13 Pro plugins above plus `rocket`, `createCodec`, `publishRocketManifests` and types `Codec`, `CodecDocs`, `CodecRegistry`, `RocketDefinition` from `@rocket` (datastar-pro.ts:L42-65). Every bundle also exports `action actions attribute watcher` and `beginBatch computed effect endBatch filtered getPath mergePatch mergePaths root signal startPeeking stopPeeking`.

Aliasing:

| Fact | Detail | Cite |
|---|---|---|
| Mechanism | build-time constant `ALIAS: string \| null` (`globals.d.ts`), substituted with esbuild `--define` | globals.d.ts:L1 |
| Effect | `aliasify(name)` -> `data-<ALIAS>-<name>`; `unaliasify` drops any `data-*` attribute not prefixed `<ALIAS>-` | utils/text.ts:L79-86; engine/engine.ts:L168-169, L270-271 |
| Scope | attribute names only, including `data-ignore`. `$signal` and `@action` syntax unchanged | engine/engine.ts:L114 |
| `*-aliased.ts` sources | byte-identical to their twins except comment wrapping; the alias is only the define value | `diff` of the two files |
| Without `--define:ALIAS=...` | bare `ALIAS` reference -> `ReferenceError` at load | utils/text.ts:L80 |
| Published alias value | `data-star-*` on data-star.dev downloads `[unverified]`; nothing in the checkout fixes the value | none |

Custom bundle: copy `datastar-core.ts`, add `import '@plugins/...'` / `import '@pro/...'` lines for the plugins wanted, optionally re-export from `@rocket` last (the Rocket runtime must evaluate after engine and plugins, datastar-pro.ts:L56), build with `--tsconfig=library/tsconfig.json --define:ALIAS=null` (or `'--define:ALIAS="star"'`). The hosted Bundler at data-star.dev/pro/bundler does this in the browser `[unverified]`.

Measured `[runtime-verified]`, esm + minify: `datastar.ts` 33.9 kB, `datastar-pro.ts` 72.6 kB, `datastar-pro-aliased.ts` with `ALIAS="star"` 72.7 kB.

## Stellar CSS

Nothing in the checkout: no `.css`, no `stellar` file or directory. README.md only links `https://data-star.dev/pro#stellar-css`. Not documentable from source.

## Other checkout contents

`CHANGELOG-ROCKET.md` (Rocket beta.2 is current; alpha.8 and earlier are the obsolete attribute-driven API). `LICENSE.md` commercial license. No `package.json`, no build scripts: all builds are ad hoc esbuild.

## Corrections to SKILL.md Pro sections

Line numbers refer to `/home/peter/.claude/skills/datastar/SKILL.md`.

| # | Line | SKILL.md says | Source says |
|---|---|---|---|
| C1 | 492-497 | Inspector build: `--tsconfig=webcomponents/datastar-inspector/tsconfig.json`, no loader flag | tsconfig lives at `webcomponents/tsconfig.json`; `--loader:.html=text` is required or esbuild errors `[runtime-verified]` |
| C2 | 1134-1139 | lists `inbounce`, `inoutbounce`, `inoutgolden` as usable | they throw `TypeError` on first frame (camelCase lookup bug) `[runtime-verified]` |
| C3 | 1143 | "Cancels in-flight animations on interruption" (fine) but omits defaults | duration 1000ms, ease `linear`, delay 0; absent attribute starts at `0<suffix>` |
| C4 | 1159-1160 | match-media example treats the value like an expression | value is raw text: no `$`, no quotes needed; quotes are stripped; `__case` modifier available |
| C5 | 1174-1175 | on-resize modifiers: `__debounce`, `__throttle`, `__viewtransition` | also `__delay`; same set as on-raf |
| C6 | 1189-1190 | persist "Loads from storage on first render" with filter | load is unfiltered `mergePatch` of the whole stored object; filter applies only on write |
| C7 | 1207-1209 | query-string "Doesn't update URL during browser back/forward" | true only with `__history`; without it there is no popstate handler. Also: write rebuilds the whole query string, dropping non-signal params; `__filter` omits falsy values |
| C8 | 1219 | replace-url "fires on every morph" | fires when a dependency signal changes (effect), not on morph as such |
| C9 | 1243 | "Sets tabindex="0" if not present" | sets when `el.tabIndex` is falsy (0 or absent); existing `-1` is left alone; runs once, not reactive |
| C10 | 1254 | view-transition "Warns on browsers that don't support" | silent no-op, no warning; never clears the name when the value becomes falsy |
| C11 | 1268-1270 | clipboard "Returns a Promise" | returns `undefined`; `writeText` promise is dropped, rejections are unhandled |
| C12 | 1285-1301 | `@intl(type, value, options?, locales?)`; relativeTime example `{unit: 'day'}` | `options` required for `relativeTime` and `displayNames`; `unit` must be an array (`['day']`), a string yields `RangeError` `[runtime-verified]` |
| C13 | 1322-1325 | Inspector shows "SSE fetch lifecycle (started/finished/error/retry)" | only SSE event types starting `datastar-` (`datastar-patch-elements`, `datastar-patch-signals`); lifecycle events are filtered out |
| C14 | 1329-1337 | table of "Attributes / observed state" lists class fields as attributes | only `max-events-visible` is an attribute; the rest are internal fields, not settable from HTML |
| C15 | 1339-1340 | "only one inspector per page" | not enforced in source; multiple instances each listen independently. Omit or tag as advice |
| C16 | 1310-1318 | (missing) | Inspector needs no Pro bundle; signals tab is replay-based so load it before Datastar; persisted-key scan bug (`data-persist-` vs `data-persist:`) |
| C17 | 1345-1350 | Bundler described only as hosted tool | custom bundle is a copy of `datastar-core.ts` plus imports; `*-aliased.ts` sources are identical to non-aliased, alias is the `--define` value |
| C18 | 1352-1358 | Stellar CSS "alpha as of this writing" | nothing in the checkout; cannot be verified from source |
| C19 | 470-473 | "Pro bundle includes core, 10 attrs, 3 actions, Rocket" | correct; add that `datastar-rocket.ts` (free plugins + Rocket, no Pro plugins) also exists |
