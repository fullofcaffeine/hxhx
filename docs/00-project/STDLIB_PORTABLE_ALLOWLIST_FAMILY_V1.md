# Portable Stdlib Allowlist Contract (Family v1)

This document defines the shared contract for portable stdlib allowlists used by sibling Reflaxe compilers.

## Contract artifacts

- Schema (machine-readable): `docs/00-project/STDLIB_PORTABLE_ALLOWLIST_SCHEMA_V1.json`
- OCaml manifest (current implementation mapping): `docs/00-project/STDLIB_PORTABLE_ALLOWLIST_OCAML_4_3_7.json`
- OCaml baseline source set: `docs/00-project/STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json`
- CI validator: `scripts/ci/portable-stdlib-tier-allowlist-check.js`
- Guard extraction plan: `docs/00-project/STDLIB_FAMILY_GUARD_EXTRACTION_PLAN_V1.md`

## v1 rules

- `schemaVersion` is the structural schema version (v1 = `1`).
- `familyContract` is fixed to `reflaxe.family.std.portable_allowlist`.
- `contractVersion` uses semver.
- `tiers.tier1` and `tiers.tier2` are required.
- tier module names must be fully-qualified stdlib module ids.
- `tier1` must be a subset of `tier2`.
- every allowlist module must exist in the referenced baseline manifest.

## Versioning policy

- **Patch** (`x.y.Z`): non-structural edits (module membership/documentation) that do not change schema fields.
- **Minor** (`x.Y.z`): additive contract changes that remain backward compatible (for example, adding `tier3` support while keeping `tier1`/`tier2` behavior).
- **Major** (`X.y.z`): breaking contract changes (field rename/removal, semantic changes to tier meaning, rule changes that invalidate existing manifests).
- Any major schema break requires a new schema file (`..._V2.json`) and explicit migration notes.

## OCaml baseline mapping (v1)

- Contract target: `ocaml`
- Haxe baseline: `4.3.7`
- Allowlist tiers currently implemented:
  - tier1: PR-lite portable stdlib gate
  - tier2: expanded parity scope
- Validation commands:
  - `npm run guard:stdlib-portable-tier1-allowlist`
  - `node scripts/ci/portable-stdlib-tier-allowlist-check.js --tier tier2`
