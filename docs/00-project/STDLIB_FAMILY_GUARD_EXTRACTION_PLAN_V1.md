# Family Stdlib Guard Extraction Plan (v1)

This plan defines how we extract OCaml’s stdlib provenance/boundary guardrails into reusable family tooling (`reflaxe.family.std`).

## Goal

- Keep the current OCaml guard behavior unchanged.
- Extract reusable guard contracts so Go/Rust/OCaml (and future targets) use one policy model.
- Make CI integration deterministic and target-configured (no ad-hoc per-repo rewrites).

## Source assets (current OCaml implementation)

- Provenance ledger: `docs/00-project/STDLIB_PROVENANCE_LEDGER.json`
- Third-party notice: `THIRD_PARTY_NOTICES.md`
- Boundary guard: `scripts/ci/upstream-stdlib-boundary-check.js`
- Ledger guard: `scripts/ci/stdlib-provenance-ledger-check.js`
- Tier allowlist guard: `scripts/ci/portable-stdlib-tier-allowlist-check.js`
- Baseline manifest: `docs/00-project/STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json`
- Tier allowlist manifest: `docs/00-project/STDLIB_PORTABLE_ALLOWLIST_OCAML_4_3_7.json`

## Target reusable artifacts (`reflaxe.family.std`)

Required package layout:

- `contracts/portable-stdlib-allowlist-schema-v1.json`
- `contracts/provenance-ledger-schema-v1.json`
- `templates/THIRD_PARTY_NOTICES_STDLIB.md`
- `scripts/ci/check-upstream-stdlib-boundary.js`
- `scripts/ci/check-stdlib-provenance-ledger.js`
- `scripts/ci/check-portable-stdlib-allowlist.js`
- `docs/INTEGRATION.md`

All three checkers must accept a target config file path.

## Target config contract

Each compiler repo supplies one config JSON (example path: `docs/00-project/STDLIB_GUARD_CONFIG_<target>.json`) with:

- `targetId` (e.g. `ocaml`, `rust`, `go`)
- `upstreamVendorRoot` (e.g. `vendor/haxe`)
- `approvedVendorRoots`
- `forbiddenVendorRoots`
- `stdlibSyncTargets`
- `ledgerPath`
- `thirdPartyNoticesPath`
- `baselineManifestPath`
- `allowlistManifestPath`

This removes hardcoded paths from shared scripts.

## CI integration points

Per target repo (`npm run ci:guards` lane), required checks:

1. boundary guard (`check-upstream-stdlib-boundary.js`)
2. provenance ledger guard (`check-stdlib-provenance-ledger.js`)
3. allowlist guard (`check-portable-stdlib-allowlist.js`)

Required target-level outputs:

- `OK: upstream stdlib boundary ...`
- `OK: stdlib provenance ledger covers ...`
- `OK: tier allowlist is valid ...`

CI fails on first contract violation.

## Migration phases

### Phase 0 — Mirror (no behavior change)

- Copy current OCaml scripts/contracts into `reflaxe.family.std`.
- Add schema files + config contract.
- Keep OCaml repo using existing local scripts.

Exit criteria:

- Shared scripts pass snapshot validation against current OCaml fixtures/config.

### Phase 1 — OCaml adopts shared scripts

- Switch `package.json` guard commands to invoke shared scripts with OCaml config.
- Keep local wrappers only as thin forwarders (or remove entirely with hard cutover).

Exit criteria:

- `npm run ci:guards` behavior unchanged.
- No path-policy regressions.

### Phase 2 — Rust/Go onboard

- Add target configs in Rust/Go repos.
- Wire shared scripts into their CI guard lanes.

Exit criteria:

- Same three guard categories enforced in all family repos.

## Hard cutover policy

- No compatibility shim layer beyond a single migration commit.
- After shared adoption, remove duplicate local implementations.
- Guard script ownership becomes `reflaxe.family.std` only.

## Acceptance checklist

- Reuse plan exists for ledger + boundary checks (this document).
- Required artifacts/paths are explicitly listed (source + target sections).
- CI integration points are documented (command categories + expected outputs).
