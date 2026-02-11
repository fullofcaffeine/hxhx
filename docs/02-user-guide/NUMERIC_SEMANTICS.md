# Numeric Semantics (Int / Float) for `reflaxe.ocaml`

This document makes the OCaml target’s numeric behavior **explicit** and ties it
to tests in `test/portable/`.

## `Int` (Haxe) vs `int` (OCaml)

- **Haxe `Int`** is a **signed 32-bit** integer with wraparound overflow.
- **OCaml `int`** is **word-sized** (31-bit on 32-bit builds, 63-bit on 64-bit
  builds) and does **not** automatically wrap at 32 bits.

### Our policy (M11)

We represent Haxe `Int` values as OCaml `int`, but we implement all arithmetic
and bitwise operators through a small runtime module:

- Runtime: `packages/reflaxe.ocaml/std/runtime/HxInt.ml`
- Codegen lowering: `packages/reflaxe.ocaml/src/reflaxe/ocaml/ast/OcamlBuilder.hx`

This preserves the observable Haxe semantics while keeping the runtime
representation ergonomic (e.g. for `Sys.println`, array indices, etc.).

### What is covered

The following operations are 32-bit correct:

- `+`, `-`, `*`, integer division (`~/`), `%`
- `&`, `|`, `^`, `~`
- `<<`, `>>`, `>>>` (shift counts masked to `0..31`)

See fixture: `test/portable/fixtures/int32_semantics/`.

### What is intentionally unspecified

Haxe specifies that some conversions are “unspecified” when outside the signed
Int32 range (e.g. `Math.floor()` on very large values, converting infinities to
`Int`). We do not try to define additional guarantees there beyond “does not
crash in normal ranges”.

## `Float`

Haxe `Float` maps directly to OCaml `float` (IEEE-754 double precision).

Notes:
- `Int` ↔ `Float` comparisons are supported by promoting `Int` to `Float` where
  Haxe allows it.
