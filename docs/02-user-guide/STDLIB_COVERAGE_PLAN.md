# Stdlib Coverage Plan (Portable / stdlib-first) — M11

This document tracks which parts of the Haxe standard library are:

- supported via **target runtime modules** (`packages/reflaxe.ocaml/std/runtime/*.ml`)
- supported via **extern overrides** (`packages/reflaxe.ocaml/std/_std/**/*.hx`)
- still missing / intentionally unsupported

The goal is to keep a “portable” surface where users can target OCaml without
needing OCaml knowledge, while still producing idiomatic OCaml output.

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
