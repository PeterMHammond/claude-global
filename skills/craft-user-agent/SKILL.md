---
name: craft-user-agent
description: Drive CRAFT as a signed-in account with the `craft` CLI (everygoodwork/craft-cli) — Code Mode programs and raw workers on /-/user/agent, a construct's facet and files authored and published from its own repo, room doors (connect, send, pay, ware), site check/build, live proofs and machine players. Triggers on /craft-user-agent, "use craft to …", "publish this construct", "author a construct", "drive CRAFT from the CLI". For the staff /-/agent plane use craft-agent; for releases and tenant installs use craft-deploy.
---

# craft CLI

`craft` is one compiled binary that every lab uses. It is a tool, never a hub: a construct's source, look and
publish program live in the construct's own repo (Cowell: cowelltactical; EveryGoodWork's: everygoodwork/constructs).
No `.mjs`/`.js` runner, no `dpop.mjs`, no repo script, no `craft publish` verb. If a step seems to need a script,
write a Code Mode program for `craft run`; if the CLI truly lacks a door, file it on craft-cli.

## Sign in

```sh
craft login --email you@example.com </dev/null   # emails a 6-digit PIN (10 min); the sign-in parks
printf '123456\n' | craft login --finish          # PIN line 1, voucher line 2 if any; never on argv
craft login --device                              # or: link + code to approve in a browser
craft whoami && craft ping
```

| Env | Default | Purpose |
|---|---|---|
| `CRAFT_BASE` | `https://craft.everygoodwork.io` | app host; Cowell's is `https://account.cowelldesign.online` |
| `CRAFT_STORE` | `~/.craft/craft.toml` | credential (token + holder key, 0600); one file per identity |

## Author and publish (one program)

```sh
craft run --code-mode --file program.js     # export default async (craft) => { … }; each call -> { text, isError }
craft run --caps User:get_dashboard --file w.js   # raw WorkerEntrypoint with declared caps (exclusive with --code-mode)
```

A construct folder holds `facet.js` plus a flat `files/` of hosted files, content-hashed names for cacheable
assets. Publishing is one program, in this order:
1. `author_construct_file` for each changed hashed file (inert until named).
2. `author_construct_facet`; `set_construct_capabilities` with the whole list if it changed.
3. `try_construct_facet` with a real verb; abort on `isError`.
4. `publish_construct`.
5. Unhashed files (`index.html`) last, so a failed step leaves the live shell untouched.
6. Proof: the publish result and `facet_error` null from `get_construct_view`. No file read-backs.

Publish only a reviewed sha, with Peter's go. The content brake is 120 calls per caller per UTC hour, and
`read_construct_file` counts. `craft run` waits 300 s; `sent, no answer` (exit 3) means read state before retrying.

## Rooms

```sh
craft room connect --room URL [--construct ID]          # typed frame lines out, `VERB key=value` lines in
craft room send --room URL VERB key=value …             # one checked command
craft pay --room URL --kind play|copy|sale|own
craft ware --room URL
```

A room on a construct's own domain needs `--construct ID`. Verbs and keys are checked against the room's
`/-/describe` before sending.

## Sites, proofs, players

- `craft check [DIR]`: H1–H22 over facet.js + files/; `craft build [DIR]`: render content.toml + assets into files/.
- `craft prove --origin URL [--page FILE]`: read-only live checks, no sign-in.
- `craft play login|watch|run|soak|walk|model`: machine players on fresh rooms; never a room real people use.
- `craft author PROMPT --model NAME --model-base URL`: local-model authoring loop.

## Gotchas

- `export_construct` is owner-gated; owner-only verbs refuse the wrong identity as "not owner": `whoami` first.
- One program, not many calls: each run is a billable isolate.
