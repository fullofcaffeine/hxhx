# HXHX Self-Hosting Checklist (Beginner-Friendly)

This page answers one simple question:

When can we honestly say **"hxhx compiles hxhx"**?

## Quick answer

We are **not fully there yet**.

Today the bounded strict replacement bundle passes without stage0 delegation,
but we still rely on stage0 `haxe` to regenerate the full committed bootstrap
snapshot. That remaining regeneration dependency keeps this page from calling
the compiler strongly self-hosting.

Related status pages:

- 1.0 roadmap milestones and closure notes:
  - `docs/01-getting-started/HXHX_1_0_ROADMAP.md`
- Portable stdlib parity status:
  - `docs/02-user-guide/STDLIB_PORTABLE_PARITY_MATRIX.md`

## Status matrix (as of 2026-07-14)

Use this table as the short answer for "are we self-hosting yet?"

| Check | Why it matters | Current status | Evidence |
|---|---|---|---|
| Build `hxhx` with stage0 delegation blocked (`HXHX_FORBID_STAGE0=1`) | Proves we can build from committed snapshots without silently falling back to stage0 | Pass | `.github/workflows/ci.yml` job `stage0-free-smoke` |
| Run a stage3 compile path with stage0 blocked | Proves the compiler can do real work in stage0-forbidden mode | Pass | `.github/workflows/ci.yml` job `stage0-free-smoke` (`--ocaml --hxhx-no-emit`) |
| Run macro host selftest with stage0 blocked | Proves macro host bootstrap path works in stage0-forbidden mode | Pass | `.github/workflows/ci.yml` job `stage0-free-smoke` (`--hxhx-macro-selftest`) |
| Prototype native bootstrap refresh on a minimal subset with stage0 blocked | Proves the chosen refresh architecture can emit/build repo-owned Haxe through Stage3 without invoking stage0 | Pass | `npm run hxhx:probe:stage0-free-refresh` |
| Regenerate `packages/hxhx/bootstrap_out` without stage0 `haxe` | This is the major blocker for strong self-hosting | Not yet | `scripts/hxhx/regenerate-hxhx-bootstrap.sh` still uses stage0 emit |
| Replacement-ready gates pass with delegation blocked | Needed for strong release confidence | Pass for the bounded M7 scope | Exact-commit run `29321576340` at `30a0b371` emitted `M7_STRICT_STAGE0:PASS` and `M7_REPLACEMENT_READY:PASS`; this does not prove stage0-free bootstrap regeneration or the larger Full1 matrix |

Status meaning:

1. `Pass`: works today in normal CI.
2. `Partial`: some evidence exists, but not complete acceptance.
3. `Not yet`: still an open blocker.

Refresh this matrix from repo/CI signals:

```bash
npm run status:self-hosting
```

Strict replacement-ready definition used by this checklist:

```bash
HXHX_M7_STRICT=1 HXHX_FORBID_STAGE0=1 npm run test:upstream:replacement-ready:full
```

Expected strict marker:

- `M7_STRICT_STAGE0:PASS`

Strict replacement status criteria used on this page:

1. Run `HXHX_M7_STRICT=1 HXHX_FORBID_STAGE0=1 npm run test:upstream:replacement-ready:full`.
2. Require marker `M7_STRICT_STAGE0:PASS`.
3. Treat failures or skipped strict rungs as not closed for strong self-hosting.

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
   - a Stage3 compile path (`--ocaml --hxhx-no-emit`)
   - macro host selftest (`--hxhx-macro-selftest`)
3. We can block accidental delegation:
   - `HXHX_FORBID_STAGE0=1` is the guardrail.

## What is still missing for strong self-hosting

1. Stage0-free bootstrap refresh for `packages/hxhx/bootstrap_out` by default.
2. Make stage0-free execution the normal release path across the entire
   declared Full1 suite, target, macro, plugin, and performance matrix—not only
   the bounded M7 bundle.

## Bootstrap refresh architecture choice

The selected path is **native self-refresh**:

1. Build `hxhx` from committed bootstrap snapshots with `HXHX_FORBID_STAGE0=1`.
2. Use that binary's Stage3 full-body emitter to generate OCaml from repo-owned Haxe sources.
3. Only promote output into `packages/hxhx/bootstrap_out` after snapshot parity and guard checks pass.

Payload slicing of the existing stage0 Reflaxe compile graph is intentionally not the release path. It still depends on the stage0 macro/eval typed-payload wall, and it risks creating partially generated artifacts whose equivalence is harder to prove than a fully stage0-forbidden native refresh.

Promotion contract for the full path:

1. Stage0 remains blocked for the build and refresh probe (`HXHX_FORBID_STAGE0=1`, sentinel `HAXE_BIN`).
2. Dry-run output goes under ignored `.tmp/` paths first; committed snapshots are not mutated until validation passes.
3. The first scaling rung targets the real `hxhx.Main` source graph in Stage3 type-only mode.
4. The next rung targets the same `hxhx.Main` graph with Stage3 full-body emit/build but still writes only to ignored dry-run output.
5. Full promotion requires generated source parity checks, shard/finalization checks, and a clean diff review before replacing `packages/hxhx/bootstrap_out`.

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

# Prototype the native refresh path on a small repo-owned fixture.
npm run hxhx:probe:stage0-free-refresh

# Probe the real hxhx source graph without emitting or promoting snapshots.
HXHX_STAGE0_FREE_REFRESH_SCOPE=hxhx-type-only npm run hxhx:probe:stage0-free-refresh

# Probe full-body emission for the real hxhx source graph without promoting snapshots.
HXHX_STAGE0_FREE_REFRESH_SCOPE=hxhx-full-emit npm run hxhx:probe:stage0-free-refresh

# Build hxhx without allowing delegation.
HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used bash scripts/hxhx/build-hxhx.sh

# Verify a stage0-forbidden compile path.
HXHX_FORBID_STAGE0=1 HAXE_BIN=/definitely-not-used bash scripts/test-hxhx-targets.sh
```

Note:

- These checks prove important stage0-free behavior.
- They do **not** yet prove full strong self-hosting end-to-end.
