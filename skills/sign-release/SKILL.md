---
name: sign-release
triggers:
  - /sign-release
description: Review and sign a release from a host-ground clone, under watchman's Z5 seam — the lab built and pushed an agent branch, the human signs a tag with the YubiKey from a clone outside every lab. Use on /sign-release <project> <version> [branch], or whenever a lab session reports an agent/release-* branch ready to sign. One prompt from verdict to the sudo lines: never inside a lab, compiles nothing on host ground (airlock run builds in the recipe lab), opens the key only after Peter answers Yes, never runs sudo.
---

# sign-release

The lab builds, the human signs. A lab's tree holds `.git/config` and hooks the lab wrote, so
signing there hands the key to whatever wrote them. The review happens in a clone outside every
lab, `~/review/<project>`, and the only things that leave it are a signed tag and a push of it.

Arguments: `<project>` (e.g. `craft`), `<version>` (`YYYY.MMDD.HHMM`, no leading zeros, e.g. `2026.0101.930`), optional `<branch>` (default
`agent/release-<version>`), and from the review lab's block: `sha=<full sha>` (the reviewed head)
and `text=yes|no` (whether a shipped text file changed). Refuse if `WATCHMAN_LAB` is set: this
runs on host ground only. This is the one prompt: it carries the release from the verdict to the
sudo lines, and stops only for the Yes at the key and for sudo, which it never runs.

`text` is the review lab's note of whether a shipped text file changed; `watchman ship` shows
those files as a diff in its plan and its one line applies them, so `text` adds no step.

## Fence

- Never `cargo`, `wrangler`, `bun` or a project script on host ground. The gate ran in the lab; `airlock run` builds in the recipe lab.
- Never edit a file. Never run `sudo`.
- Never open the key unasked. Before `git tag -s`, AskUserQuestion exactly "Ready to sign this code change?" with Yes and No only; on Yes run the tag and push in the same turn, on No wait.
- Report brass tacks: outcome first, three sentences unless asked for depth.

## Steps

1. **Clone or refresh.** `~/review/<project>` absent: `git clone https://gitlab.com/everygoodwork/<project>.git ~/review/<project>`. Present: `git -C ~/review/<project> fetch https://gitlab.com/everygoodwork/<project>.git "+refs/heads/*:refs/remotes/origin/*" --tags` (host ground goes over HTTPS; a clone made in a lab carries an SSH alias that does not resolve here). Confirm no `core.hooksPath` and an empty `.git/hooks` of executables; a hook here is a stop.
2. **Fix the range on the last tag, never on `origin/main`.** `base="$(git -C ~/review/<project> describe --tags --abbrev=0 --match 'v*' "$sha^")"`. A trunk-based project pushes the release onto main itself, so `origin/main..sha` and `git diff origin/main origin/<branch>` are both EMPTY there and every check built on them passes while reading nothing. The last release tag is the only base that spans the new work under either seam.
3. **Diff.** `git diff $base $sha`. Walk every hunk in plain words. Expected for a version-only release: the bump in `Cargo.toml` and its echo in `Cargo.lock`. A dependency move, a script change, or anything not named in the lab's report is a stop, named. An empty diff is a stop: it means the base is wrong, not that the release is clean.
4. **The sha is the verdict.** `sha=` is the head the review lab said `sign` on. Refuse unless
   `origin/<branch>` is exactly that sha. Confirm the range is non-empty before believing it.
   No `sha=` means no verdict: stop and ask for the review lab's block. This session reviews
   nothing itself: the reviewer is confined, it is not.
   If the commit message carries `release-check passed over tree <id>` (craft#777), refuse unless `<id>` equals `git -C ~/review/<project> rev-parse "$sha^{tree}"`: a pass over another tree is no pass.
5. **Already signed?** If `v<version>` exists, verifies, and names `sha`, say so and go to step 7 — never re-sign an existing good tag.
6. **Sign.** Ask the one question. On Yes run, in that turn:
   ```
   git -C ~/review/<project> tag -s v<version> origin/<branch> -m "<version>"
   git -C ~/review/<project> push https://gitlab.com/everygoodwork/<project>.git v<version>
   git -C ~/review/<project> verify-tag v<version>
   git -C ~/review/<project> push https://gitlab.com/everygoodwork/<project>.git v<version>^{commit}:main
   ```
   The YubiKey asks for PIN and touch. Show the Good signature line. Main follows the tag by
   fast-forward, here, on host ground.
7. **Ship.** Every project with a recipe in `/etc/watchman/airlock`, whatever it is:
   `watchman ship <project> --tag v<version> < /dev/null 2>&1 | cat`. The recipe's declarations,
   never its name, decide how it ends (watchman#81); its last line is the ONE line Peter pastes.
   A second run of the same recipe is refused by the lock (watchman#80), so never start one
   while another is live. No recipe: say so and stop.
8. **Hand over one line.** Print that last line exactly, alone in one fenced block, and say only
   which prompts it opens: `sudo watchman install … --expect <digest>` (sudo password; it
   installs, applies recipes, renders profiles, hardens and restarts the proxy) and/or
   `watchman publish … --expect <digest>` (the YubiKey, then the recipe's publish lines). Before
   handing it over, read the plan above it for a `KEY CHANGE` or `NEW KEY` line and name it
   first. Nothing in this step runs here, and no other session runs it either: the coordinator
   relays it to Peter, who pastes it in his own terminal. A failed publish names the lines it did not run;
   hand those over as they print. Publication is Peter's own `glab` login, never a lab token.
