---
name: release-handoff
triggers:
  - /release-handoff
description: Hand finished lab work off for review the way the airlock seam requires — rebase onto origin/main, get the three gates green, push one agent branch, then print one block pinned to one sha that carries the /review-release line. Use on /release-handoff, or whenever work in a lab is ready for review, ready to sign, or ready to release. The lab never tags, never signs, never pushes main.
---

# release-handoff

The review agent is a separate lab (`Projects/review`) with a read-only clone and no key: its
GitLab grant is `GET /everygoodwork/` plus `git-upload-pack` on `watchman`, `craft` and
`craft-core`, so it can fetch one pushed commit and nothing else. Unpushed work is invisible to it,
and a block that names no sha names nothing. This skill ends in that block and stops.

Refuse unless `WATCHMAN_LAB` is set and is not `Projects/review`: this runs in the project's own
lab. Host ground signs (`/sign-release`); the review lab reviews (`/review-release`).

## Fence

- Never `git push origin main`, never `git tag`, never `--no-verify`, never `commit.gpgsign` — the lab has no key by design (Z5).
- Never `git remote set-url origin`. The lab shares one `.git` with host ground and the alias resolves only here; use the alias as an explicit push URL if a push needs it.
- Never `git config --global` anything: in a lab that file is regenerated on every entry. Identity goes repo-local (watchman#61).
- Never amend or rebase a branch a reviewer already holds; see step 6.
- Ask nothing after the block. The next move is Peter's paste.

## Steps

1. **Rebase onto origin/main.** `git fetch origin && git rebase origin/main`. Main moves only by
   signed tags, and a review built beside one would miss it.

2. **Green on the branch**, all three, in this order:
   ```
   watchman gate && cargo test --release --locked -- --nocapture && watchman scan --quiet
   ```
   Keep the three result lines verbatim for the block — the gate verdict, the cargo totals, the
   scan summary. Then `grep -c 'skipped:'` the test output: what a lab could not measure is stated,
   not hidden.

3. **Commit and push one agent branch.** The lab HOME has no git identity, so set it repo-local
   once, from the repo's own history:
   ```
   git config --local user.name "$(git log -1 --format='%an')" && git config --local user.email "$(git log -1 --format='%ae')"
   git push origin HEAD:agent/<branch-name>
   ```
   Add no trailers — no `Co-Authored-By`, no `Claude-Session`. One that slipped in is cosmetic:
   say so and carry on, never rewrite history or hold the release for it. The
   deploy key pushes `agent/*` only: a push refused on `main` or a tag is the seam working, not a
   problem to route around.

4. **Print exactly this block and stop.** Every placeholder filled:

   ```
   branch   agent/<branch-name>
   head     <full sha>
   gate     <the watchman gate line>
   tests    <the cargo test totals>
   scan     <the scan summary line>
   skipped  <count>
   ```

   Review Lab, in a `Projects/review` session:
   ```
   /review-release <project> <full sha> agent/<branch-name>
   ```
   `<project>` is the repository name as the review lab's grant spells it: `watchman`, `craft` or
   `craft-core`. The reviewer runs the `/rust-review` checklist against that sha and reports coded
   findings. A defect comes back here on this branch; style notes wait for the tag message.

5. **The block is pinned to the sha.** If the head moves after printing, print the whole block
   again with the new sha. Never a correction line: a stale block sends Peter to review one commit
   and sign another.

6. **While a review is out, never amend or rebase the published branch in place.** Build the
   replacement as ordinary commits, get it green, then move the ref once, last:
   ```
   git push --force-with-lease=agent/<branch-name>:<exact prior sha> origin HEAD:agent/<branch-name>
   ```
   The explicit prior sha is the point. A bare `--force-with-lease` trusts a remote-tracking ref
   this lab may have refreshed, and will overwrite a reviewer's push.

## Red between steps 2 and 4

- The lab's own blindness — root-owned ground, pacman, loopback, a check that reads
  `/etc/watchman` — is a bug in the check, not a finding: fix it on this branch and name it in the
  block.
- A grant that looks missing may only be bound to an older shell. Re-measure with
  `lab run <name> -- <cmd>`, a fresh entry, before reporting it absent.
- If the airlock refused a host, name the host in the block and wait. The grant is Peter's click.
