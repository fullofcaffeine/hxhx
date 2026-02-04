# Stdlib Coverage Plan (Portable / stdlib-first) — M11

This document tracks which parts of the Haxe standard library are:

- supported via **target runtime modules** (`std/runtime/*.ml`)
- supported via **extern overrides** (`std/_std/**/*.hx`)
- still missing / intentionally unsupported

The goal is to keep a “portable” surface where users can target OCaml without
needing OCaml knowledge, while still producing idiomatic OCaml output.

## Current priority modules

### Core runtime-backed types

- `Array<T>`: `std/_std/Array.hx` + `std/runtime/HxArray.ml`
- `String`: `std/_std/String.hx` + `std/runtime/HxString.ml`
- `Bytes`: runtime-backed via `std/runtime/HxBytes.ml` (lowered in codegen)
- `Date`: `std/_std/Date.hx` + `std/runtime/Date.ml`
- `Sys`: `std/_std/Sys.hx` + `std/runtime/HxSys.ml`
- `sys.FileSystem`: `std/_std/sys/FileSystem.hx` + `std/runtime/HxFileSystem.ml`

### Maps (`haxe.ds.*`, `haxe.ds.Map`, `haxe.Constraints.IMap`)

Implemented via:

- runtime: `std/runtime/HxMap.ml`
- codegen lowering for constructors + methods:
  `src/reflaxe/ocaml/ast/OcamlBuilder.hx` (`StringMap`/`IntMap`/`ObjectMap`/`IMap`)

### Regex (`EReg`)

- extern: `std/_std/EReg.hx`
- runtime: `std/runtime/EReg.ml`
- notes: `docs/02-user-guide/EREG_STRATEGY.md`

### Math

- extern: `std/_std/Math.hx`
- runtime: `std/runtime/Math.ml`

## How we validate

We use layered tests (mirrors the repo-wide strategy in `docs/01-getting-started/TESTING.md`):

1. Snapshots: `.ml` golden output (shape/regressions)
2. Portable fixtures: compile → dune build → run (behavior)
3. Acceptance examples: `examples/` (integration/compiler-shaped workloads)

M11 additions are primarily validated through portable fixtures.

