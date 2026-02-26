# Haxe Stdlib Policy (MIT + Clean-Room Boundaries)

This document defines how `hxhx`/`reflaxe.ocaml` use upstream Haxe stdlib code while preserving a permissive, clean-room compiler implementation.

## Scope

- **Baseline upstream tag:** `4.3.7`
- **Use case:** stdlib compatibility for supported targets.
- **Non-goal:** importing upstream compiler implementation details.
- **Portable parity baseline contract:**
  - `docs/00-project/STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json`
  - `docs/00-project/STDLIB_PORTABLE_ALLOWLIST_OCAML_4_3_7.json` (tiered PR/nightly scope)
  - generated from upstream `vendor/haxe/std/**` using platform-agnostic + `sys` policy.

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
- Keep the required provenance artifacts current:
  - `THIRD_PARTY_NOTICES.md`
  - `docs/00-project/STDLIB_PROVENANCE_LEDGER.json`
    - Every tracked file under `packages/reflaxe.ocaml/std/_std/**` must have a ledger entry.

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
   npm run guard:stdlib-portable-baseline
   npm test
   ```
5. Update provenance artifacts:
   - update `THIRD_PARTY_NOTICES.md` if third-party notice scope changes
   - update `docs/00-project/STDLIB_PROVENANCE_LEDGER.json` for all touched `_std` files
6. Record provenance details in the bead/PR notes.

## CI guardrails enforcing this policy

- `scripts/ci/version-sync-check.js`
  - validates MIT metadata and that `vendor/haxe` remains untracked.
- `scripts/ci/upstream-stdlib-boundary-check.js`
  - enforces stdlib-only upstream vendoring boundaries.
  - rejects tracked `vendor/haxe/src/**`, `vendor/haxe/tests/**`, and other non-stdlib upstream paths.
  - enforces stdlib sync destination policy for checked-in overrides.
- `scripts/ci/stdlib-provenance-ledger-check.js`
  - ensures `THIRD_PARTY_NOTICES.md` exists and includes the stdlib notice.
  - ensures every tracked `_std` override file has coverage in the provenance ledger.
- `scripts/ci/portable-stdlib-baseline-check.js`
  - verifies the committed portable baseline contract matches deterministic generation from upstream std.
- `scripts/ci/portable-stdlib-tier-allowlist-check.js`
  - verifies tiered allowlist contract integrity (`tier1`/`tier2`) against the baseline manifest.
  - enforces the family allowlist schema + contract metadata:
    - `docs/00-project/STDLIB_PORTABLE_ALLOWLIST_SCHEMA_V1.json`
    - `docs/00-project/STDLIB_PORTABLE_ALLOWLIST_FAMILY_V1.md`

Family extraction roadmap:

- `docs/00-project/STDLIB_FAMILY_GUARD_EXTRACTION_PLAN_V1.md`
  - defines the guard extraction/migration plan from OCaml-local scripts to shared family tooling.
