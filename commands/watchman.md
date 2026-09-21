<purpose>
Report what Watchman knows, triage only what it could not adjudicate itself, and act.
</purpose>

<instructions>
Execute immediately — no preamble.

Watchman adjudicates its own findings against local authorities (cargo's sparse index, pacman's
signed package DB). Anything an authority vouches for never reaches you. So do NOT re-triage
attested findings, and do NOT hand-audit build.rs files wholesale — that job is now mechanical and
already done. Your job is the residue: what no authority would vouch for.

There is no status file, no bar widget, and no JSON. The approval loop — `watchman act`,
`watchman status`, `watchman decisions` and the Omarchy card — was deleted: consent is a signed
tag, and a finding is fixed, accepted into the baseline, or reported. Never look for
`~/.local/state/watchman/status.json`, and never pass `--json` — the flag does not exist.

## Step 1: Scan

```bash
~/.local/bin/watchman scan 2>/dev/null
```

If the binary is missing, build it first:
```bash
cargo build -p watchman-cli --release --manifest-path ~/Projects/EveryGoodWork/watchman/Cargo.toml && cp ~/Projects/EveryGoodWork/watchman/target/release/watchman ~/.local/bin/watchman
```

### The output format

The text report is the only output. Header lines begin with `#`; every other line is one finding of
seven tab-separated columns:

```
severity  module  lane  flags  title  description  recommendation
```

- `severity` — `CRITICAL` | `HIGH` | `MEDIUM` | `LOW`
- `module` — the scanner that raised it, snake_case (`registry_trust`, `posture`, …)
- `lane` — `compile_time` (runs during `cargo build`; refuses that tree at `watchman gate`) or
  `persistence` (survives a reboot, or changes what the shell trusts)
- `flags` — comma-joined, or `-`: `attested` (an authority vouched — ignore it), `compromised`,
  `blocking`, `held` (quarantine window, clears on its own), `drift`, `condition`

`scan` exits 1 when anything unattested is blocking, and 0 otherwise — that exit code is the
headline, not a failure. Narrow with awk rather than reading every line:

```bash
watchman scan | awk -F'\t' '!/^#/ && $4 ~ /blocking/ && $4 !~ /attested/'
watchman scan | awk -F'\t' '!/^#/ && $3 == "persistence" && $4 !~ /attested/'
watchman scan --quiet     # the summary line alone: critical/high/medium/low/total/blocking
```

The first header line carries the timestamp, hostname and duration; the second is the summary line.

The 6-hourly timer runs the same scan and notifies on drift. If the user asks whether the monitor
is alive, that is a separate question from the findings — answer it from the timer:

```bash
systemctl --user list-timers watchman-scan.timer; systemctl --user is-active watchman-scan.timer
```

A monitor that has silently stopped looks exactly like a monitor with nothing to report, so say so
plainly when the timer is dead.

Triage silently, and only the unvouched. Investigate for real when something is genuinely
unexplained: read the actual build.rs, check `git log -1 --format="%ar %s" -- <file>` to correlate
drift with recent work, read the actual hook or unit. Vendored/minified JS unicode findings are
noise.

## Step 2: Brief the user — short

**Watchman** — {relative time of last scan} | {duration}ms | {hostname}

Then only what matters:
- **Blocking** — name each one and its projects. Never a count alone; a count is not actionable.
- **Awaiting review** — unvouched persistence findings, one line each.
- **Gate-blocked trees** — which projects `watchman gate` will now refuse, if any.
- Otherwise: **All clear**, one sentence, with when it last looked.

Never pad with attested or inventory findings.

## Step 3: Offer actions with AskUserQuestion

Mandatory whenever anything needs a decision — never end with prose suggestions.

- Unvouched persistence findings → "Accept them" (`watchman baseline update --all-unvouched`),
  "Review first" (`watchman baseline diff`), "Leave it"
- A specific module's findings → "Accept just that module"
  (`watchman baseline update --module <name>`)
- Blocking yanked/withdrawn crates → "Audit the upgrade"
  (`watchman audit-upgrade --cargo <crate>`), "Leave it"
- A quarantined crate the user needs today → `watchman gate <path> --allow-fresh`, typed per
  invocation. There is no waiver file and nothing records the decision.
- Something genuinely suspicious → "Audit it" (read and analyse), "Leave it"
- Clean and current → ask nothing. End with "All clear."

NEVER offer or run `watchman baseline create` to clear findings. `create` is a first-run snapshot
and blesses everything at once, including things no authority vouched for. `update` with a selector
is the only accept path.

## Step 4: Execute the choice, then confirm the result changed

After accepting, re-run `watchman baseline diff` and state what is now outstanding.

## Arguments

- `/watchman` → scan, brief, act
- `/watchman diff` → `watchman baseline diff` — the lane-grouped review surface
- `/watchman accept` → `watchman baseline update --all-unvouched`, after showing what it will accept
- `/watchman gate [path]` → `watchman gate` in that tree; report why it refuses
- `/watchman wrangler` → `audit-upgrade` in the right project, analyse risk, offer choices
- `/watchman <module_name>` → single-module scan and analysis (`watchman scan --module <name>`)

`audit-upgrade` prints the same way: `#` headers, then `kind  name  from  to` rows. It and the
`advisories` module execute the tree they judge, so they run only inside a lab:
`lab run <lab name> -- watchman audit-upgrade <package>`. Outside one they refuse, and `advisories`
reports that it did not run rather than reporting nothing.
</instructions>
