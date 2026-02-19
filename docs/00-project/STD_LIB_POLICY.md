# Haxe Stdlib Policy (MIT + Clean-Room Boundaries)

This document defines how `hxhx`/`reflaxe.ocaml` use upstream Haxe stdlib code while preserving a permissive, clean-room compiler implementation.

## Scope

- **Baseline upstream tag:** `4.3.7`
- **Use case:** stdlib compatibility for supported targets.
- **Non-goal:** importing upstream compiler implementation details.

## Allowed upstream reuse

Upstream usage is intentionally narrow:

1. **Behavior oracle**
   - Use untracked `vendor/haxe` checkouts for behavior validation and compatibility tests.
2. **Stdlib reference/sync (MIT)**
   - Only stdlib content from `vendor/haxe/std/**` is eligible for selective reuse/sync.
   - Checked-in stdlib sync destination is:
     - `packages/reflaxe.ocaml/std/_std/**`

## Forbidden upstream reuse

The following upstream paths are never allowed to be vendored or copied into this repository:

- `vendor/haxe/src/**` (compiler implementation)
- `vendor/haxe/tests/**` (upstream tests/fixtures)
- `vendor/haxe/extra/**`
- Any non-stdlib path under `vendor/haxe/**`

## Attribution and notice rules

- Keep this repository MIT-licensed (`LICENSE` + `haxelib.json`).
- For stdlib sync changes, include the upstream source ref in the PR/commit/bead note:
  - upstream tag/commit
  - source path(s) in `vendor/haxe/std/**`
  - destination path(s) in `packages/reflaxe.ocaml/std/_std/**`
- Do not add copyleft license texts/headers to tracked source files.

## Sync workflow (upstream -> local stdlib overrides)

1. Refresh local upstream checkout (untracked):
   ```bash
   bash scripts/vendor/fetch-haxe-upstream.sh
   ```
2. Inspect upstream stdlib candidate(s) from:
   - `vendor/haxe/std/**`
3. Reimplement/sync into:
   - `packages/reflaxe.ocaml/std/_std/**`
4. Run guardrails and tests:
   ```bash
   npm run ci:guards
   npm test
   ```
5. Record provenance details in the bead/PR notes.

## CI guardrails enforcing this policy

- `scripts/ci/version-sync-check.js`
  - validates MIT metadata and that `vendor/haxe` remains untracked.
- `scripts/ci/upstream-stdlib-boundary-check.js`
  - enforces stdlib-only upstream vendoring boundaries.
  - rejects tracked `vendor/haxe/src/**`, `vendor/haxe/tests/**`, and other non-stdlib upstream paths.
  - enforces stdlib sync destination policy for checked-in overrides.
