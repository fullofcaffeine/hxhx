# ML2HX Subset Contract (OCaml → Haxe Translation Shapes)

This doc defines the **subset of Haxe constructs** and **coding patterns** that an eventual `ml2hx` (OCaml → Haxe)
translator should emit so that the resulting Haxe code:

- compiles cleanly with `reflaxe.ocaml`
- produces idiomatic OCaml (as much as the current milestone allows)
- stays readable and maintainable for humans

This is a *contract*, not an implementation: it’s what the generated Haxe should look like.

## Goal: two surfaces, not a compiler mode switch

We maintain two “surfaces” that the translator can target:

1) **Portable / stdlib-first surface (default)**  
   Generated code should use Haxe stdlib APIs where possible and preserve Haxe semantics. This is the surface that
   lets users “target OCaml without knowing OCaml”.

2) **OCaml-native surface (opt-in)**  
   Generated code may use target-specific typed APIs (e.g. `ocaml.List`, `ocaml.Option`, `ocaml.Result`) so that the
   backend can emit direct OCaml idioms (`[]`, `(::)`, `Some/None`, `Ok/Error`), while still benefiting from Haxe’s
   typing and tooling.

The translator chooses the surface by the APIs it emits, not by a global flag.

## Current backend constraints (important)

The contract must reflect the current target’s capabilities:

- Prefer **classes** over Haxe structural `typedef` objects in core IR for now  
  Structural typing / anonymous structures are not fully supported yet (tracked separately). Generated code should
  represent “records” as classes with explicit constructors and accessors.
- Avoid relying on **statement-only early returns** inside expression positions  
  Patterns like `if (cond) return v;` currently need careful lowering. Prefer explicit `else` branches or structure code
  so the `return` is in tail position (tracked separately).
- Avoid `++/--` on instance fields for now; prefer `x = x + 1`  
  (tracked separately).

As the backend matures, we will relax these restrictions and update this contract.

## Module and naming mapping

### Modules

- Each OCaml module becomes a **single Haxe module file**.
- Use a stable mapping for module names:
  - `Foo_bar` (flat OCaml module) → `Foo_bar.hx`
  - `Foo.Bar` (nested) → either `Foo/Bar.hx` (preferred) or a flattened module with documented mapping

### Identifiers

- Avoid emitting OCaml reserved keywords as Haxe identifiers when they would round-trip to OCaml identifiers
  (e.g. `end`, `type`, `module`, ...). Prefer a prefix strategy (`hx_end`) at translation time.

## Core data shapes

### Algebraic data types (enums)

Portable surface:

- Emit Haxe `enum` for OCaml variants.
- Prefer payloads as explicit constructor parameters.

OCaml-native surface:

- When the OCaml type is known to be a standard shape, prefer:
  - `ocaml.Option<T>` for `option`
  - `ocaml.Result<T, E>` for `result`
  - `ocaml.List<T>` for `list`

### Records / product types

Until structural typing is supported end-to-end:

- Represent OCaml records as **Haxe classes** with:
  - constructor `new(...)`
  - private `final` fields
  - explicit `getX()` methods (or properties only once property lowering is stable)

Rationale:

- The current portable lowering represents instances as OCaml records (`type t = { mutable ... }`), but relying on Haxe
  anonymous objects requires more compiler support than we have today.

### Maps

Portable surface:

- Prefer `haxe.ds.StringMap<T>` / `haxe.ds.IntMap<T>` / `haxe.ds.ObjectMap<K, V>` over `Map<K,V>` where the key kind is known.

Rationale:

- These map to `HxMap.*_map` runtime types and avoid `Obj.t` plumbing.

## Control flow shapes

### Pattern matching

Prefer `switch` over cascaded `if`s when translating OCaml `match`.

- Multi-case arms should be emitted as multi-case `switch` where possible.
- If a `match` binds variant payloads, use `switch` patterns that expose the payload variables (or restructure into
  helper functions when necessary).

### Loops

Prefer `while` + explicit index for sequences/arrays in portable surface:

- `while (i < xs.length) { ...; i = i + 1; }`

Avoid:

- `for (x in xs)` until iterator lowering is known-good for the workload.

## Nullability policy (portable surface)

Portable mode must preserve Haxe `null` semantics where the stdlib expects it (e.g. `Sys.getEnv`).

Translator rules:

- Use `null` only where the Haxe API contract requires it.
- Prefer `ocaml.Option<T>` on the OCaml-native surface when the original OCaml API is option-typed.

## Bootstrapping stages

This contract is meant to support staged bring-up:

1. Stage 1: compiler-shaped workloads (`workloads/hih-workload`)
2. Stage 2: reimplement a meaningful compiler subsystem
3. Stage 3: macro execution pipeline
4. Stage 4: production-grade Haxe-in-Haxe compiler (Haxe 4.3.7)
