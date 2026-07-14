# Macro/Eval Parity Contract

Last audited: 2026-07-14

This page defines the Full 1.0 macro/eval closure contract. It is intentionally separate from
the broader Full 1.0 contract so macro runtime parity, native eval evidence, aggregate gate
semantics, and non-goals stay measurable.

Machine marker for this contract:

- `FULL1_MACRO_EVAL_CONTRACT:PASS`

Related contract surfaces:

- `docs/00-project/FULL_1_0_CONTRACT.md`
- `docs/00-project/MACRO_RUNTIME_PARITY_BLOCKERS.md`
- `docs/00-project/PARITY_MAP_HAXE_4_3_7.md`
- `docs/00-project/PARITY_MAP_FULL_1_0.json`
- `.github/workflows/macro-runtime-parity-weekly.yml`
- `.github/workflows/full1-eval-native.yml`
- `.github/workflows/gate-full1.yml`

## Scope

Full 1.0 macro/eval closure covers the Haxe 4.3.7 macro and eval surfaces that are
declared in the Full 1.0 parity map.

The required evidence stack is:

1. Macro runtime parity across the scoped runtime modes.
2. Strict native eval/interp baseline for `tests/unit/compile-macro.hxml`.
3. Gate Full1 aggregate success after the macro and eval lanes complete without fallback.

## Required Markers

The contract is not release-satisfied unless the evidence run includes all of these markers:

- `MACRO_RUNTIME_PARITY_WEEKLY:PASS`
- `FULL1_MACRO_PARITY:PASS`
- `FULL1_EVAL_NATIVE:PASS`
- `FULL1_MACRO_EVAL_PARITY:PASS`

The external-host child evidence must also contain:

- `MACRO_RUNTIME_EXTERNAL_HOST_ARTIFACT:PASS`

That child marker proves one candidate-bound host survived its receipt and
protocol checks. It does not replace either aggregate macro marker above.

The contract-definition marker is separate:

- `FULL1_MACRO_EVAL_CONTRACT:PASS`

`FULL1_MACRO_EVAL_CONTRACT:PASS` only proves that the documented contract is present and
guarded. It does not substitute for any runtime, eval, or aggregate parity marker.

## Blocker Map

| Blocker | Status | Closure rule |
| --- | --- | --- |
| Macro runtime parity blockers | Open under `haxe_ocaml-vhk47.1` and `haxe_ocaml-vhk47.3` | The external-host lifecycle needs a fresh same-candidate aggregate, and project-defined Haxe macros need a stage0-free authenticated module path. See `docs/00-project/MACRO_RUNTIME_PARITY_BLOCKERS.md`. |
| Native eval/interp baseline | Open until `haxe.ocaml-f1cl.4.2` is closed | `.github/workflows/full1-eval-native.yml` or the local runner must emit `FULL1_EVAL_NATIVE:PASS` from a stage0-forbidden run. |
| Gate Full1 aggregate wiring | Open until `haxe.ocaml-f1cl.4.3` is closed | `.github/workflows/gate-full1.yml` must emit `FULL1_MACRO_EVAL_PARITY:PASS` only after the macro and eval evidence lanes pass without silent fallback. |

## Non-Goals

The following are explicitly not part of this contract unless the Full 1.0 scope manifest is
changed first:

- Raw source-host Reflaxe custom-target discovery for arbitrary `compile.hxml` files.
- Sibling compiler behavior that upstream Haxe 4.3.7 does not support.
- Replacing upstream-suite evidence with repo-local focused regressions.
- Treating `--compat` or stage0 delegation as native Full 1.0 macro/eval evidence.

## Claim Rule

A Full 1.0 macro/eval claim must cite:

- the exact commit SHA,
- the upstream Haxe 4.3.7 checkout or ref used as oracle input,
- the artifact bundle for macro runtime parity,
- the artifact bundle for native eval,
- the Gate Full1 run URL or local aggregate summary,
- all required markers listed above.

If any required marker is absent, the claim must be described as diagnostic or partial evidence,
not Full 1.0 macro/eval closure.
