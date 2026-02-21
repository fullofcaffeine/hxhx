# HXHX Self-Hosting Checklist (Beginner-Friendly)

This page answers one simple question:

When can we honestly say **"hxhx compiles hxhx"**?

## Quick answer

We are **not fully there yet**.

Today we can do a lot of stage0-free work, but we still rely on stage0 `haxe` for some bootstrap regeneration paths.

## Status matrix (as of 2026-02-21)

Use this table as the short answer for "are we self-hosting yet?"

| Check | Why it matters | Current status | Evidence |
|---|---|---|---|
| Build `hxhx` with stage0 delegation blocked (`HXHX_FORBID_STAGE0=1`) | Proves we can build from committed snapshots without silently falling back to stage0 | Pass | `.github/workflows/ci.yml` job `stage0-free-smoke` |
| Run a stage3 compile path with stage0 blocked | Proves the compiler can do real work in stage0-forbidden mode | Pass | `.github/workflows/ci.yml` job `stage0-free-smoke` (`--target ocaml-stage3 --hxhx-no-emit`) |
| Run macro host selftest with stage0 blocked | Proves macro host bootstrap path works in stage0-forbidden mode | Pass | `.github/workflows/ci.yml` job `stage0-free-smoke` (`--hxhx-macro-selftest`) |
| Regenerate `packages/hxhx/bootstrap_out` without stage0 `haxe` | This is the major blocker for strong self-hosting | Not yet | `scripts/hxhx/regenerate-hxhx-bootstrap.sh` still uses stage0 emit |
| Replacement-ready gates pass with delegation blocked | Needed for strong release confidence | Partial | We have stage0-free smoke evidence, but not full strong-self-hosting gate closure yet |

Status meaning:

1. `Pass`: works today in normal CI.
2. `Partial`: some evidence exists, but not complete acceptance.
3. `Not yet`: still an open blocker.

Refresh this matrix from repo/CI signals:

```bash
npm run status:self-hosting
```

## Two meanings of "self-hosting"

There are two useful definitions:

1. **Weak self-hosting**
   - A built `hxhx` binary can compile `hxhx` source code in some workflows.
2. **Strong self-hosting**
   - We can do the full compiler lifecycle (including bootstrap refresh) **without** stage0 `haxe`.

This repo tracks the **strong** definition as the real goal.

## What is already true

1. We have a stage0-free CI smoke lane:
   - `.github/workflows/ci.yml` -> job `stage0-free-smoke`
2. That lane checks:
   - building `hxhx` with `HXHX_FORBID_STAGE0=1`
   - a Stage3 compile path (`--target ocaml-stage3 --hxhx-no-emit`)
   - macro host selftest (`--hxhx-macro-selftest`)
3. We can block accidental delegation:
   - `HXHX_FORBID_STAGE0=1` is the guardrail.

## What is still missing for strong self-hosting

1. Stage0-free bootstrap refresh for `packages/hxhx/bootstrap_out` by default.
2. Stage0-free macro + gate paths as the normal/primary route (not just smoke/partial lanes).
3. Stable acceptance evidence in replacement gates with stage0 delegation blocked.

## Definition of done (practical)

We can call strong self-hosting done when all of this is true:

1. `HXHX_FORBID_STAGE0=1` is set, and core developer workflows still pass.
2. Bootstrap refresh no longer needs stage0 `haxe`.
3. Gate lanes we claim for release pass in that mode.

## Commands you can run now

These commands are useful reality checks:

```bash
# Print the current status matrix from repo/CI signals.
npm run status:self-hosting

# Run the same local smoke flow as CI stage0-free-smoke.
npm run test:self-hosting-smoke

# Build hxhx without allowing delegation.
HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used bash scripts/hxhx/build-hxhx.sh

# Verify a stage0-forbidden compile path.
HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used bash scripts/test-hxhx-targets.sh
```

Note:

- These checks prove important stage0-free behavior.
- They do **not** yet prove full strong self-hosting end-to-end.
