---
name: craft-user-agent
description: Execute sandboxed JS workers on Craft's per-user /user/agent gateway as a specific signed-in user — authorized by OAuth 2.1 + PKCE and sender-constrained with DPoP (RFC 9449). One invocation composes the caller's own App/User/Construct DO RPCs, hard-bound to their identity. Triggers on /craft-user-agent or when the user asks to drive Craft AS a specific account — author a construct they own, create/join an app, configure their dashboard, or test the agent-OAuth/DPoP flow end to end.
---

# Craft User Agent

Execute sandboxed JavaScript workers on Craft via `POST /user/agent` — the
**per-user authoring gateway**, the customer-facing mirror of the staff
`/agent` control plane (`/craft-agent`). Where `/agent` is staff-only and addresses
*any* DO by key, `/user/agent` runs **as one signed-in user**: the gateway bakes
the caller's own `userKey` into every binding, so a script can only ever reach the
caller's own DOs and the constructs they own. The script never names the user — the
identity is the credential.

This is the path a real autonomous agent uses to act on a user's behalf. It is
authorized by **OAuth 2.1 + PKCE** and **sender-constrained with DPoP (RFC 9449)**:
the access token is bound to a holder key (`cnf.jkt`), and every call must carry a
fresh DPoP proof signed by that key — a stolen token without the private key is
inert.

For the staff admin/moderation surface (claim, quarantine, ban, Replay/Sandbox,
System diagnostics) use `/craft-agent` instead. For sibling business apps use
`/loadout-run`, `/carm-run`, or `/watchman-run`.

## Trust model (RFC 9449 sender-constraint)

`POST /user/agent` accepts exactly one identity: a DPoP-bound OAuth **access token**.
A browser session cookie is NOT an identity here — the gateway answers on every
hostname, including the UGC origin where author-supplied facet script runs, so an
ambient credential would have been borrowable by any construct's page (craft#315).
The token is sender-constrained:

1. **Holder-key binding.** The token is issued at `/oauth/token` only when the
   request carries a DPoP proof; the server stamps the proof key's RFC 7638
   thumbprint into the token as `cnf.jkt`. Refresh preserves the same `jkt`.
2. **Per-call proof.** Every `/user/agent` call uses `Authorization: DPoP <token>`
   (not `Bearer`) plus a `DPoP:` proof header signed by the holder key, binding the
   method (`htm`), URL (`htu`), token hash (`ath`), and a one-time `jti`. The gateway
   verifies the ES256 signature (WebCrypto), requires `cnf.jkt == thumbprint(proof
   key)`, and replays are rejected (`jti` is single-use within its window).
3. **Server nonce (§8).** The first call is answered `401 use_dpop_nonce` with a
   `DPoP-Nonce`; the client re-signs with the nonce and retries. `dpop.mjs run`
   does this automatically.
4. **Resource binding (RFC 8707).** The token is audience-bound to
   `https://craft.everygoodwork.dev/`; a token minted for another audience is rejected.
5. **ACL is still the authority.** DPoP only resolves *identity*. Authoring a
   construct still goes through its event-sourced ACL — a non-owner slug `403`s at
   the RPC regardless of a valid proof.

There is **no token-introspection oracle**: the gateway resolves the token via a
direct OAuthState DO stub RPC (RFC 7662 §2.1), not a public route.

## Authentication

The credential is a DPoP-bound access token plus its holder keypair, obtained once
and cached at `~/.craft/user-agent.json` (override with `CRAFT_USER_AGENT_STORE`).
The token is **inert without the cached private key** — treat the file as a secret
(the client writes it `chmod 600`).

### Login (once per session; tokens auto-refresh after)

The human-in-the-loop step is the email OTP — the user proves the account is theirs,
then self-authorizes their own agent.

```bash
SKILL=~/.claude/skills/craft-user-agent/scripts/dpop.mjs

# 1. Request a one-time PIN (arrives by email)
node "$SKILL" request-otp you@example.com

# 2. Exchange the PIN for a DPoP-bound token (generates the holder keypair,
#    runs PKCE consent, exchanges the code with a proof, caches everything)
node "$SKILL" login --email you@example.com --code 123456

# confirm
node "$SKILL" whoami
```

`login` performs: OTP verify → session cookie → ES256 keypair → PKCE `POST /consent`
→ `POST /oauth/token` **with a DPoP proof** → cache `{tokens, holder keypair}`. After
that, `run` refreshes the access token automatically (preserving the bound key) when
it expires.

## How it works

1. Write a JS worker that composes the caller's binding methods.
2. Declare the minimum capabilities needed (build caps require an email identity).
3. `node dpop.mjs run` mints a fresh DPoP proof, submits to `POST /user/agent`,
   transparently handles the `use_dpop_nonce` challenge, and refreshes the token
   if needed.
4. The gateway verifies the proof + `cnf.jkt`, enforces the capability allowlist,
   bakes the caller's `userKey` into the bindings, sandboxes the code, returns the result.

## Submitting a worker

```bash
SKILL=~/.claude/skills/craft-user-agent/scripts/dpop.mjs

# from a file
node "$SKILL" run --caps Craft:call --file worker.js

# or pipe the source on stdin
echo 'import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint { async run() {
  return JSON.parse(await this.env.Craft.call("get_my_account", "{}")).text;
} }' \
  | node "$SKILL" run --caps Craft:call
```

Response: `{ "ok": true, "result": <return value> }` or `{ "ok": false, "error": "message" }`.

## Worker script pattern

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    // Compose the caller's own binding methods.
    return { /* results */ };
  }
}
```

**Key rules** (same sandbox as `/craft-agent`):
- Always `import { WorkerEntrypoint } from "cloudflare:workers"` and `export default class extends` it.
- Access bindings via `this.env`; `run()` takes no arguments.
- Return a plain value — it becomes `result`. Throws become `{ ok: false, error }`.
- Declare the MINIMUM capabilities — over-requesting `403`s before any isolate runs.
- **Declare `Craft:call` and nothing else.** It grants the whole tool catalog. Sixteen
  per-verb caps also exist (`User:ping` + fifteen `Construct:*`), but they are a narrower,
  hand-maintained rail with no create verb on it — reach for them only to test that rail
  itself. `App:*` does not exist at all.
- **A refusal comes back as data, not a throw.** `call()` answers a JSON string
  `{text, isError}` — code that only try/catches will read a refusal as success.
- Every tool still re-checks the target's own ACL, so a slug you do not own refuses
  regardless of a valid proof.
- **Creating needs the `publish` scope**; authorize with `read write publish`.

## The capability surface — one name, the whole catalog

`/user/agent` is **code mode over the same tool catalog `/mcp` serves**. It is not a
separate, smaller surface: one program reaches every tool, so create → author →
verify costs a single round trip instead of one call each.

**`Craft:call` is the entire catalog in one capability.** Declare it and
`this.env.Craft` reaches every tool under its exact `/mcp` name.

The older **direct rail** still exists beside it — sixteen `<Binding>:<verb>` caps in
`SCOPE_CAPS.user` (`User:ping`, `Construct:set_ui`, `Construct:set_facet`, …). Two reasons
not to use it: a cap there grants the whole BINDING at its scope class rather than that one
verb, and it carries **no create verb**, so an agent that starts there cannot mint anything
(craft#280). `Construct:create_construct` and every `App:*` are refused with *Capability not
permitted* because they were never on the list. `Craft:call` is the answer to both.

```js
const call = async (name, args) =>
  JSON.parse(await this.env.Craft.call(name, JSON.stringify(args)));
```

`call(name, argsJson)` takes the tool name plus its arguments **as a JSON string**,
and answers a **JSON string** `{"text":"…","isError":false}`. Parse it and branch on
`isError` — **a refusal arrives that way, never as a thrown error.** Code that only
try/catches will read a refusal as success.

`run_authoring_program` is advertised by `tools/list` but is not in the catalog: it
IS this rail, offered to `/mcp` callers, so calling it from inside a program answers
`unknown tool`.

Discover the catalog with `tools/list` on `/mcp`, or call `describe_platform` once
per session and `describe_construct` per target. `export_construct("ttt")` returns a
working construct's declaration, verbatim facet and the shared `Self` contract — the
build plan to learn from before authoring your own.

## Scopes and runway

Creating anything needs the **`publish` scope** — ask for `read write publish` at
authorization. Without it `create_construct` answers `isError` naming the missing
scope.

Creating is not gated on credit, but what you create spends it. Claiming an account
grants 1 Credit of runway once. It is runway, not funding: funded-tier privileges
(`set_construct_visibility` → `protected`, a `sale` price) still refuse at that
balance. You **cannot** top it up on your own initiative — when it runs out, tell
your user and ask.

## Where a construct lives

A construct owns its **origin**: the slug is the hostname, not a path segment.
`chess.everygoodwork.io`, not `craft.everygoodwork.io/chess` (craft#284). Author-written
code therefore cannot read a sibling construct. A Spawner construct mints instances at
`{slug}-{id}.everygoodwork.io`.

## Examples

### Connectivity smoke

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const call = async (n, a) => JSON.parse(await this.env.Craft.call(n, JSON.stringify(a)));
    return (await call("get_my_account", {})).text;
  }
}
// caps: Craft:call
```

### Create a construct and author its behaviour — one round trip

```javascript
import { WorkerEntrypoint } from "cloudflare:workers";
export default class extends WorkerEntrypoint {
  async run() {
    const call = async (n, a) => JSON.parse(await this.env.Craft.call(n, JSON.stringify(a)));

    // Learn the Self contract from a working construct first.
    const plan = await call("export_construct", { slug: "ttt" });
    if (plan.isError) return plan.text;

    const made = await call("create_construct",
      { name: "My Game", players: 2, turns: "Sequential", cardinality: "Spawner" });
    if (made.isError) return made.text;          // a refusal is data, not a throw
    const slug = /"([a-z0-9-]+)"/.exec(made.text)[1];

    const authored = await call("author_construct_facet", { slug, code: MY_FACET });
    return authored.isError ? authored.text : { slug, url: `https://${slug}.everygoodwork.io` };
  }
}
// caps: Craft:call
```

A slug you do not own still refuses at the ACL regardless of a valid proof — DPoP
resolves *identity*, the construct's own event-sourced ACL remains the authority.

## DPoP acceptance matrix (regression check)

The client doubles as the live conformance check for the DPoP sender-constraint
(craft#48). After a `login`, these prove enforcement end to end:

- token exchange with a proof → token works on `/user/agent` (cnf-bound)
- matching proof + nonce → `200` authored as the user
- no proof → `401 use_dpop_nonce` (then auto-retry succeeds)
- wrong key / replayed `jti` / stale `iat` → `401`
- cnf-bound token presented as `Bearer` → `401` (scheme downgrade refused)
- refresh preserves the bound key; the refreshed token still requires a proof
- non-owned `setUi` with a valid proof → `403` (ACL is still the authority)
- `POST /oauth/introspect` → `404` (no introspection oracle)
