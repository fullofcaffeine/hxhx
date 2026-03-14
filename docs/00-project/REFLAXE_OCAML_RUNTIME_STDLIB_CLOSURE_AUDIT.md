# reflaxe.ocaml Runtime / Stdlib Closure Audit

Last audited: 2026-03-13

This audit defines what counts as target-level closure for `reflaxe.ocaml` within its declared standalone product scope.

Canonical contract:

- `docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md`

Machine-readable audit:

- `docs/00-project/REFLAXE_OCAML_RUNTIME_STDLIB_CLOSURE_AUDIT.json`

Checker:

- `scripts/ci/reflaxe-ocaml-closure-audit-check.js`

Success marker:

- `RO_RUNTIME_STDLIB_CLOSURE:PASS`

## Purpose

This audit prevents two failure modes:

1. pretending `reflaxe.ocaml` is product-ready without an explicit inventory of target-owned runtime/stdlib responsibility
2. silently expanding the target-product claim to absorb promotion or `hxhx` compiler-equivalence work

## Status vocabulary

- `covered`
  - this surface is inside the declared product scope and has explicit documentation/evidence references
- `scoped_out`
  - this surface is intentionally outside the standalone target-product claim and is owned elsewhere

## Current audit result

All entries in the declared standalone product scope are now classified as either:

- `covered`, or
- `scoped_out`

There are no implicit “unknown” buckets in the machine-readable audit.

## Audit rows

See the JSON manifest for the exact machine-readable rows.

The current covered areas are:

- portable surface contract
- OCaml-native surface contract
- runtime module inventory
- core target-owned stdlib overrides
- dune/build integration
- upstream-Haxe validation examples

The current scoped-out areas are:

- multi-host promotion proofs
- strict `hxhx Full 1.0` compiler-equivalence proof

## Rule

If a future requirement belongs to promotion or strict compiler equivalence, do not add it here.

Track it in:

- `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`, or
- `docs/00-project/FULL_1_0_CONTRACT.md`

instead of inflating the standalone target-product audit.
