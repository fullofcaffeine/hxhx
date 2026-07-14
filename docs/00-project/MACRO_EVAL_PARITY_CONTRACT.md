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
- `docs/00-project/FULL1_MACRO_EVAL_EVIDENCE_DECISION.md`
- `docs/00-project/PARITY_MAP_HAXE_4_3_7.md`
- `docs/00-project/PARITY_MAP_FULL_1_0.json`
- `.github/workflows/macro-runtime-parity-weekly.yml`
- `.github/workflows/full1-eval-native.yml`
- `.github/workflows/full1-macro-eval.yml`
- `.github/workflows/gate-full1.yml`

## Scope

Full 1.0 macro/eval closure covers the Haxe 4.3.7 macro and eval surfaces that are
declared in the Full 1.0 parity map.

The required evidence stack is:

1. Macro runtime parity across the scoped runtime modes.
2. Strict native eval/interp baseline for `tests/unit/compile-macro.hxml`.
3. An artifact-verified combined receipt after the macro and eval lanes complete
   without fallback.
4. Gate Full1 validation of that combined receipt.

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

The workflow must also complete its Haxe-authored project-macro-module job. That
job proves one real project macro can be generated, authenticated, loaded, and
run through both native modes. It is a required child of the aggregate marker,
but it does not claim that every possible project macro is already supported.

The contract-definition marker is separate:

- `FULL1_MACRO_EVAL_CONTRACT:PASS`

`FULL1_MACRO_EVAL_CONTRACT:PASS` only proves that the documented contract is present and
guarded. It does not substitute for any runtime, eval, or aggregate parity marker.

## Blocker Map

| Blocker | Status | Closure rule |
| --- | --- | --- |
| Macro runtime parity blockers | Behavior is green for the declared bounded matrix under `haxe_ocaml-vhk47.1` and `haxe_ocaml-vhk47.3`; artifact-built aggregation is in progress under `haxe_ocaml-vhk47.4` | Exact-commit run `29350539265` at `b2277951` keeps the two native modes and the authenticated Haxe-authored project macro green. The upgraded summary must now open those three proof packages before it emits `FULL1_MACRO_PARITY:PASS`. See `docs/00-project/MACRO_RUNTIME_PARITY_BLOCKERS.md`. |
| Native eval/interp baseline | Behavior is green; candidate-bound receipt upgrade is in progress under `haxe_ocaml-vhk47.4` | Exact-commit run `29350537630` at `b2277951` emitted `FULL1_EVAL_NATIVE:PASS` with stage0 forbidden. The run spent 478.9 seconds in the native eval runner, so its correctness evidence is valid while the speed increase remains a separate diagnostic concern. The v2 receipt must carry the exact candidate SHA, run ID, attempt, and Haxe 4.3.7 oracle identity. |
| Artifact-verified macro/eval aggregate | In progress under `haxe_ocaml-vhk47.4` | `.github/workflows/full1-macro-eval.yml` must download the verified macro and eval summaries for one exact run and emit `FULL1_MACRO_EVAL_PARITY:PASS` only after their contents agree. |
| Gate Full1 aggregate wiring | Contract/wiring foundation `haxe.ocaml-f1cl.4.3` is closed; artifact trust upgrade is in progress under `haxe_ocaml-vhk47.4` | `.github/workflows/gate-full1.yml` must open the combined macro/eval receipt. A reusable workflow result string cannot create the marker. |

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
- the artifact-verified combined macro/eval summary,
- the focused Macro/Eval or Gate Full1 run URL,
- all required markers listed above.

If any required marker is absent, the claim must be described as diagnostic or partial evidence,
not Full 1.0 macro/eval closure.
