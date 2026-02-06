# HXHX Stage 3: Typing Architecture (No Macros)

Stage 3 is the point where `hxhx` stops being “a parser + module resolver” and becomes **a real compiler frontend**:
it can *type* Haxe code.

This document is a design guide for implementing that typer in a way that:

- stays compatible with upstream Haxe **4.3.7** semantics over time
- remains incrementally bootstrappable (CI-friendly subsets first)
- keeps the “escape hatches” we need to ship continuously (native OCaml hooks where justified)

> Terminology note: In this repo’s bootstrap plan, “Stage 3” means “typing bring-up”.
> Macro execution and plugin ABI are Stage 4 (see `docs/02-user-guide/COMPILER_PLUGIN_SYSTEM.md:1`).

## Goals

Stage 3 is “done enough” when:

1) `examples/hih-compiler` can parse + resolve + **type** a meaningful subset of Haxe syntax.
2) The typer has a stable internal API that can evolve toward upstream parity:
   - module cache / incremental typing boundaries
   - error reporting with source positions
   - a typed AST suitable for later analyzer/DCE passes
3) The subset is chosen to directly support the next acceptance workloads:
   - eventually typing the upstream Haxe compiler sources (not yet executing macros)
   - Gate 0 repo-local acceptance remains fast and deterministic

## Non-goals (Stage 3)

- **Macro execution** (`--macro`, `@:build`, `Context.*`) is Stage 4.
- **Display server parity** (`--display`) is later (Gate 2+ work).
- Full upstream type system parity (abstracts, overload resolution corner cases, complex generic constraints) is not required
  immediately, but the architecture must leave room for it.

## Source of truth: upstream Haxe’s typer

When “Haxe semantics” are ambiguous, treat upstream Haxe as the oracle:

- Upstream compiler implementation (OCaml): `vendor/haxe/src/`
- Upstream tests (behavioral oracle): `vendor/haxe/tests/unit`, `vendor/haxe/tests/runci`

Locally, prefer using a pinned checkout at `vendor/haxe` (ignored by git) created by:

- `bash scripts/vendor/fetch-haxe-upstream.sh`

## Pipeline overview (Stage 2 → Stage 3)

Stage 2 (today) provides:

- lexing + parsing (tiny subset) → `ParsedModule`
- module graph resolution (imports/classpaths) → `ResolvedModule`

Stage 3 adds:

- `TyperStage` that converts parsed modules into typed modules:
  - builds a module scope (types, fields, imports)
  - types expressions and statements
  - produces a typed AST with explicit types on nodes

Proposed stage API sketch:

- `ParserStage.parseModule(path, contents) -> ParsedModule`
- `ResolverStage.resolve(entrypoints, classpaths) -> Array<ResolvedModule>`
- `TyperStage.typeModules(mods, config) -> Array<TypedModule>`

The types and AST nodes must be stable enough that later stages can be added without reshaping everything (analyzer, codegen,
macro boundary, display server).

## Core data model

### Positions and error reporting

Every syntax node that can meaningfully error must retain:

- file path
- line/column spans (or token offsets + line table)

Errors must be structured (not only strings) so the CLI/display layer can render them:

- error kind (unknown identifier, type mismatch, missing field, ...)
- primary position + optional related positions (e.g. “defined here”)

Stage 3 should standardize an internal error type and ensure all stages throw/return it consistently.

### Types

The Stage 3 typer should mirror upstream’s conceptual representation even if we implement a reduced subset first.

Minimum viable `HxType` set:

- primitives: `Int`, `Float`, `Bool`, `String`, `Void`
- `Dynamic`
- nullable wrapper (model `Null<T>` explicitly)
- class/enum/typedef references (nominal types with optional type parameters)
- function type (`(args) -> ret`)
- monomorph / type variable (for inference)

Architectural requirement: unification must be a first-class operation (monomorphs unify, can be constrained).
That’s the “hinge” that later features depend on (generics, abstracts, overload selection, constraint solving).

### Symbols

Stage 3 introduces explicit symbol tables:

- **Module scope**: imported modules, declared types, `typedef` aliases, using extensions (later).
- **Type scope**: fields, methods, statics, constructors, type parameters.
- **Local scope**: variables + captured variables + function parameters.

The minimal invariant: *name lookup is deterministic* and does not depend on parse ordering quirks.

## Typing algorithm (incremental subset)

The actual upstream typer is complex. Stage 3 should land it in rungs:

### Rung 1: type a single module with no imports

Support:

- class with static `main`
- local variable declarations
- literals (`null`, ints, floats, strings, bool)
- simple arithmetic + comparisons
- blocks + `if` + `return`

This rung is enough to start producing a typed AST and to validate unification.

### Rung 2: resolve identifiers across modules

Add:

- import-based module/type lookup
- `A.B` field access where `A` is a module/type/expr

This rung depends on the Stage 2 `ResolverStage` being correct and stable.

### Rung 3: functions and calls (signatures first)

Add:

- parsing function signatures (name, args, return type annotation)
- typing function bodies
- typing calls and selecting a function type

This rung is where the typer becomes a “compiler” in practice: it can type the same compilation units that later codegen uses.

### Rung 4: structural typing, abstracts, and difficult edges

Defer until the Stage 3 foundation is stable:

- anonymous structures / record types
- abstracts + implicit casts + `@:from/@:to`
- overload resolution edge cases
- complex generic constraints

The goal is not to do everything at once; it’s to preserve a shape that can scale to everything.

## Macro boundary (intentionally absent in Stage 3)

Even though Stage 3 does not *execute* macros, its architecture must prepare for the Stage 4 boundary:

- typed modules need to be representable both “pre-macro” and “post-macro”
- `TyperStage` should accept a “macro provider” interface that Stage 3 stubs out:
  - Stage 3: provider returns “no expansions”
  - Stage 4: provider executes macros and returns expanded AST

This keeps macro integration from forcing a total refactor later.

## Escape hatches (why we keep them)

We keep **native OCaml hooks** in Stage 2 to make progress while still moving toward Haxe-in-Haxe:

- `native.NativeLexer` and `native.NativeParser` exist to validate the integration seam and to match upstream’s suggested
  bootstrap strategy.

Stage 3 should avoid adding a native OCaml typer hook unless it is strictly needed for velocity, because a native hook can
easily become a permanent dependency and stall “real” bootstrapping.

If we ever add a native hook, it must:

- have a versioned protocol
- be optional (feature flag / build option)
- have tests that ensure Haxe and native paths agree on the supported subset

## Testing strategy (Stage 3)

Prefer tests that match the repo layers described in `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`:

- **Golden output**: dump typed AST in a stable text format for a small fixture module set.
- **Portable fixtures**: compile → dune build → run → stdout diff (the current `examples/*` model).
- **Upstream suites**: once typing is stable, start running upstream unit tests in small, curated chunks.

Stage 3 acceptance recommendation:

- Extend `examples/hih-compiler` so it prints a deterministic “typed summary”:
  - list typed functions (name + inferred/declared signature)
  - list typed locals (name + type) for a tiny fixture

This gives us confidence in typing semantics without needing macros yet.

## How this unlocks `hxhx` bootstrapping

Stage 3 typing is the bridge to “real” `hxhx`:

- Without typing, `hxhx` cannot reliably typecheck the compiler sources (or plugins) and can’t run upstream suites.
- With typing (even a subset), we can:
  - reimplement compiler subsystems in Haxe incrementally
  - start validating those subsystems against upstream tests
  - build toward Stage 4 macros/plugin ABI without re-architecting the frontend
