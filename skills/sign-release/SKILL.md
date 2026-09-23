---
name: sign-release
triggers:
  - /sign-release
description: Review and sign a release from a host-ground clone, under watchman's Z5 seam — the lab built and pushed an agent branch, the human signs a tag with the YubiKey from a clone outside every lab. Use on /sign-release <project> <version> [branch], or whenever a lab session reports an agent/release-* branch ready to sign. Never inside a lab; never builds; never runs git tag or git push itself.
---

# sign-release

The lab builds, the human signs. A lab's tree holds `.git/config` and hooks the lab wrote, so
signing there hands the key to whatever wrote them. The review happens in a clone outside every
lab, `~/review/<project>`, and the only things that leave it are a signed tag and a push of it.

Arguments: `<project>` (e.g. `craft`), `<version>` (e.g. `2.152.5`), optional `<branch>` (default
`agent/release-<version>`). Refuse if `WATCHMAN_LAB` is set: this runs on host ground only.

## Fence

- Never build, never run `cargo`, `wrangler`, `bun` or any project script. The gate ran in the lab.
- Never edit a file. Never run `sudo`.
- Never run `git tag` or `git push`. Print them; the human types them and touches the key.
- Report brass tacks: outcome first, three sentences unless asked for depth.

## Steps

1. **Clone or refresh.** `~/review/<project>` absent: `git clone git@gitlab.com:everygoodwork/<project>.git ~/review/<project>`. Present: `git -C ~/review/<project> fetch origin`. Confirm no `core.hooksPath` and an empty `.git/hooks` of executables; a hook here is a stop.
2. **Diff.** `git diff origin/main origin/<branch>`. Walk every hunk in plain words. Expected for a version-only release: the bump in `Cargo.toml` and its echo in `Cargo.lock`. A dependency move, a script change, or anything not named in the lab's report is a stop, named.
3. **Gate proof.** Ask for the lab session's release-check result for the branch's head commit. Green end to end, or a stop. A BLIND gate has two causes: a host the airlock refused is granted through the watchman card and the gate re-run in the lab; a credential a lab cannot hold by design is not a gate and leaves the script, named in the tag message. Neither is a waiver.
4. **Sign.** On the human's word, print exactly:
   ```
   git -C ~/review/<project> tag -s v<version> origin/<branch> -m "<version>"
   git -C ~/review/<project> push origin v<version>
   ```
   The YubiKey asks for a touch. Then `git -C ~/review/<project> verify-tag v<version>` and show the Good signature line.
5. **Hand back to the lab.** Print the message for the lab session: clone `v<version>` fresh inside the lab, build there, deploy from there. Never the working tree, never `build/`: a lab's working tree is never signed, packaged or deployed. Merging to main is a fast-forward from the signed tag, done by the human on host ground.

The whole process and its rulings: `watchman/docs/superpowers/specs/2026-09-22-signed-release-process.md`.

## Not this skill

The version bump, the gate, the push to `agent/*`, and the deploy all belong to the lab session.
Splitting the gate so production probes run on the host is refused: a probe belongs where the
build is, over a host the airlock was told to allow.
