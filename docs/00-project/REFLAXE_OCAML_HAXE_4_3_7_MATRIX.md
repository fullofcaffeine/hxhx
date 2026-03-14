# reflaxe.ocaml Upstream Haxe 4.3.7 Validation Matrix

Last audited: 2026-03-13

This page defines the declared upstream-Haxe validation matrix for `reflaxe.ocaml` as a standalone target product.

Canonical contract:

- `docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md`

Machine-readable manifest:

- `docs/00-project/REFLAXE_OCAML_HAXE_4_3_7_MATRIX.json`

Deterministic runner:

- `scripts/ci/run-reflaxe-ocaml-haxe-matrix.js`

## Goal

Prove that upstream `haxe 4.3.7` can drive `reflaxe.ocaml` through a representative product matrix without relying on `hxhx` as the host compiler.

This matrix is target-product evidence.
It is not a `hxhx Full 1.0` proof.

## Validation command

From repo root:

```bash
node scripts/ci/run-reflaxe-ocaml-haxe-matrix.js
```

Success marker:

- `RO_HAXE_4_3_7_MATRIX:PASS`

Primary artifact:

- `.artifacts/reflaxe-ocaml/haxe-matrix/summary.json`

## Declared workloads

| ID | Example | What it proves |
| --- | --- | --- |
| `ro-hx-01` | `packages/reflaxe.ocaml/examples/build-macro` | upstream-Haxe build macros + target output + native run |
| `ro-hx-02` | `packages/reflaxe.ocaml/examples/file-io` | portable runtime/file system/sys/io integration |
| `ro-hx-03` | `packages/reflaxe.ocaml/examples/ocaml-native-collections` | explicit `ocaml.*` native surface under upstream host |
| `ro-hx-04` | `packages/reflaxe.ocaml/examples/loop-control` | portable control-flow/runtime behavior through native build/run |

## Why this matrix

The workload set is intentionally small but representative:

- one macro-bearing example,
- one portable runtime / file-system example,
- one OCaml-native surface example,
- one pure control-flow / runtime correctness example.

That gives a product-level signal without conflating this target matrix with the much larger `hxhx` compiler-equivalence matrix.

## Rules

- Host compiler must be upstream `haxe 4.3.7`.
- The runner must execute from repo-owned examples and compare runtime output to checked-in expectations.
- Hidden fallback to a different host/compiler is a failure.
- A single green manual session is not enough; the deterministic runner is the evidence lane.
