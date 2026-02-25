# Stdlib Coverage Plan (Portable / stdlib-first) — M11 → M16

This document tracks which parts of the Haxe standard library are:

- supported via **target runtime modules** (`packages/reflaxe.ocaml/std/runtime/*.ml`)
- supported via **extern overrides** (`packages/reflaxe.ocaml/std/_std/**/*.hx`)
- still missing / intentionally unsupported

The goal is to keep a “portable” surface where users can target OCaml without
needing OCaml knowledge, while still producing idiomatic OCaml output.

## 1.0 parity target (hard blocker)

Portable stdlib parity is tracked against the OCaml portable baseline for Haxe `4.3.7`:

- baseline manifest: `docs/00-project/STDLIB_PORTABLE_BASELINE_OCAML_4_3_7.json`
- tiered allowlist contract: `docs/00-project/STDLIB_PORTABLE_ALLOWLIST_OCAML_4_3_7.json`
- generated parity matrix: `docs/02-user-guide/STDLIB_PORTABLE_PARITY_MATRIX.md`
- generated closure worklist: `docs/00-project/STDLIB_PORTABLE_CLOSURE_WORKLIST_OCAML_4_3_7.json`

Closure-tracker workflow (M16.9):

- regenerate matrix + closure worklist:
  - `npm run stdlib:matrix:generate`
  - `npm run stdlib:closure:generate`
- sync closure buckets into beads under `haxe.ocaml-yfh.5`:
  - dry-run: `node scripts/stdlib/sync-portable-closure-beads.js`
  - apply: `npm run stdlib:closure:sync`

Definition used by this repo:

- `100% portable parity` = all modules in the baseline contract are covered by either:
  - explicit override/runtime/lowering support, or
  - validated passthrough behavior with fixture/oracle evidence.

Parity matrix taxonomy (explicit, machine-comparable):

- `override`: module has a tracked `_std` override in `packages/reflaxe.ocaml/std/_std/**`.
- `runtime_backed`: module behavior is backed by runtime implementation evidence.
- `lowering_intrinsic`: module behavior is handled directly by backend lowering/intrinsics.
- `passthrough_verified`: no local override, but behavior is verified with explicit fixture/oracle evidence.
- `passthrough_unverified`: module currently relies on upstream passthrough with no explicit evidence yet.

Evidence source for non-override statuses:

- `docs/00-project/STDLIB_PORTABLE_EVIDENCE_OCAML_4_3_7.json`

## Current priority modules

### Core runtime-backed types

- `Array<T>`: `packages/reflaxe.ocaml/std/_std/Array.hx` + `packages/reflaxe.ocaml/std/runtime/HxArray.ml`
- `String`: `packages/reflaxe.ocaml/std/_std/String.hx` + `packages/reflaxe.ocaml/std/runtime/HxString.ml`
- `Bytes`: runtime-backed via `packages/reflaxe.ocaml/std/runtime/HxBytes.ml` (lowered in codegen)
- `Date`: `packages/reflaxe.ocaml/std/_std/Date.hx` + `packages/reflaxe.ocaml/std/runtime/Date.ml`
- `Sys`: `packages/reflaxe.ocaml/std/_std/Sys.hx` + `packages/reflaxe.ocaml/std/runtime/HxSys.ml`
- `sys.FileSystem`: `packages/reflaxe.ocaml/std/_std/sys/FileSystem.hx` + `packages/reflaxe.ocaml/std/runtime/HxFileSystem.ml`

### Maps (`haxe.ds.*`, `haxe.ds.Map`, `haxe.Constraints.IMap`)

Implemented via:

- runtime: `packages/reflaxe.ocaml/std/runtime/HxMap.ml`
- codegen lowering for constructors + methods:
  `packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx` (`StringMap`/`IntMap`/`ObjectMap`/`IMap`)

### Regex (`EReg`)

- extern: `packages/reflaxe.ocaml/std/_std/EReg.hx`
- runtime: `packages/reflaxe.ocaml/std/runtime/EReg.ml`
- notes: `docs/02-user-guide/EREG_STRATEGY.md`

### Math

- extern: `packages/reflaxe.ocaml/std/_std/Math.hx`
- runtime: `packages/reflaxe.ocaml/std/runtime/Math.ml`

## How we validate

We use layered tests (mirrors the repo-wide strategy in `docs/01-getting-started/TESTING.md`):

1. Snapshots: `.ml` golden output (shape/regressions)
2. Portable fixtures: compile → dune build → run (behavior)
3. Acceptance examples: `examples/` (integration/compiler-shaped workloads)

M11 additions are primarily validated through portable fixtures.

For the expanded parity track:

- PR-lite: `npm run test:stdlib:portable:tier1`
  - validates the tier1 allowlist contract
  - runs portable fixtures under strict portable policy
- Nightly/full: `npm run test:stdlib:portable:full`
  - validates the full baseline contract
  - runs the tier1 lane
  - runs expanded M6 runtime/stdlib checks

Portable contract strictness policy:

- local development default keeps `ocaml_portable_native_surface=warn`
- stdlib parity gates run portable fixtures with `ocaml_portable_native_surface=error`
  so `ocaml.*` usage fails fast in portability lanes
