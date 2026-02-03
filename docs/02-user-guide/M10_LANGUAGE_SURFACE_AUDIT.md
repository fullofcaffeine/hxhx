# M10 Language Surface Audit (Portable Mode)

This document is a **checklist-driven map** from:

- Haxe language/runtime semantics we need to support in **portable mode**, to
- upstream Haxe tests that validate those semantics (unit + runci), to
- concrete bd issues for anything still missing.

Primary upstream reference checkout:

- `/Users/fullofcaffeine/workspace/code/haxe.elixir.reference/haxe`

## How to use this doc

1) Pick an unchecked item.
2) Run/inspect the referenced upstream tests to understand expected behavior.
3) Implement the backend/runtime change + add a repo-local fixture (snapshot or portable).
4) Check the item and close the bd task.

Repo-local testing layers are defined in `docs/01-getting-started/TESTING.md:1`.

## Core semantics

### Expressions & values

- [x] Constants, locals, `let` sequencing (M2+).
- [x] Function literals and calls, including `unit` call convention (M2+).
- [x] String concatenation via `Std.string` semantics (M6).
- [x] Enums + constructor calls + `match` lowering (M4).
- [x] Anonymous structure literals `{ ... }` (M10) via `HxAnon` runtime.
  - Upstream refs: `tests/unit/src/unit/TestNull.hx`, `tests/unit/src/unit/TestMatch.hx` (many structural shapes).
- [ ] Type expressions / class values (`TTypeExpr`) and minimal `Type.*` reflection subset.
  - bd: `haxe.ocaml-eli`
  - Upstream refs: `tests/unit/src/unit/TestType.hx`, `tests/unit/src/unit/TestDCE.hx`

### Operators

- [x] Numeric ops (Int/Float) incl. int→float promotion in comparisons (M2/M6).
  - Upstream refs: `tests/unit/src/unit/TestOps.hx`, `tests/unit/src/unit/TestBasetypes.hx`
- [x] `==` / `!=` basic behavior for supported types (best-effort; still evolving).
- [ ] `++` / `--` beyond Int (Float, nullable primitives).
  - (Currently guarded: “++/-- supports Int only”.)
  - Upstream refs: `tests/unit/src/unit/TestOps.hx`
  - bd: `haxe.ocaml-co7`

### Control flow

- [x] `if` / `else`.
- [x] `switch` lowering (M4/M6).
- [x] `while` loops (M2) + `break`/`continue` via control exceptions (M9).
- [ ] `do { ... } while (cond)` semantics (currently lowered as `while`).
  - bd: `haxe.ocaml-4dw`
  - Upstream refs: `tests/runci/System.hx`, `tests/unit/src/unit/issues/Issue2763.hx`, `tests/unit/src/unit/issues/Issue3115.hx`, `tests/unit/src/unit/issues/Issue4421.hx`

### Exceptions

- [x] `throw` and `try/catch` (M10) including typed catches via tagged throws.
  - Repo docs: `docs/02-user-guide/TRY_CATCH_AND_EXCEPTIONS.md:1`
  - Upstream refs: `tests/unit/src/unit/TestExceptions.hx`
- [ ] Full exception hierarchy parity (stack traces, rethrow semantics, etc.).
  - bd: `haxe.ocaml-56s`

## Object model

- [x] Classes (record-backed “C-like” instances) (M5).
- [x] Single inheritance and method override via dispatch records (M10).
- [x] Interfaces + interface-typed dynamic dispatch (M10).
  - Upstream refs: `tests/unit/src/unit/TestInterface.hx`
- [ ] Method-as-value / bound closure semantics (taking `obj.method` as a value).
  - bd: `haxe.ocaml-d3c`
  - Upstream refs: `tests/unit/src/unit/TestInterface.hx`, `tests/unit/src/unit/TestOps.hx`

## Anonymous structures / structural typing

Portable strategy:

- ad-hoc `{ ... }` objects lower to `HxAnon` (string-keyed `Obj.t` table).
- some “stdlib-shaped” anonymous structures lower to real OCaml records for idioms/perf
  (currently: `sys.FileStat`).

Checklist:

- [x] `{ ... }` literal creation + field reads/writes via `HxAnon`.
- [x] Iterator structural type `{ hasNext, next }` maps to an OCaml record (`HxIterator.t`).
- [x] `sys.FileStat` remains an OCaml record (runtime `HxFileSystem.file_stat`) for idiomatic access.
  - Upstream refs: `tests/unit/src/unit/TestIO.hx` and runci system tests (sys suite).
- [ ] Dynamic field access on `Dynamic` / “unknown” objects (FDynamic + Reflect).
  - bd: `haxe.ocaml-k7o`
  - Upstream refs: `tests/unit/src/unit/MyAbstract.hx`, `tests/unit/src/unit/TestDCE.hx`

## Stdlib/runtime surface (portable)

This is not exhaustive; it’s the set we currently validate continuously via fixtures/snapshots.

- [x] `Array` core ops used by portable fixtures.
  - Repo fixtures: `test/portable/fixtures/*`
  - Upstream refs: `tests/unit/src/unit/TestOps.hx`, `tests/unit/src/unit/TestBasetypes.hx`
- [x] `String` core ops used by portable fixtures.
- [x] `Bytes` subset used by portable fixtures.
- [x] `Map` subset (`StringMap`, `IntMap`, `ObjectMap`) used by portable fixtures.
- [x] `Sys`, `sys.io.File`, `sys.FileSystem` subset used by portable fixtures.

## Notes (what this audit is not)

- This is not the “replacement-ready” acceptance criteria for `hxhx`.
  See `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1` for that, including Gate 1/2/3.
