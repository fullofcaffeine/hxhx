# Macro Runtime Parity Blockers

Last audited: 2026-07-14

This list tracks the explicit blockers for declaring `inproc` and `external-host` macro runtime modes parity-equivalent for production defaults.

Beginner summary:
- `external-host`: macros run in a separate `hxhx-macro-host` process.
- `inproc`: macros run inside `hxhx` directly.
- Today the default runtime mode is already `inproc`.
- The host lifecycle is verified, and the first real project-defined Haxe macro
  now passes through both stage0-free paths on a clean CI machine.
- Exact-commit run `29349360051` proves this bounded loading path. It does not
  mean every project macro or the complete Full1 macro/eval contract is done.

## Open blockers

There are no open runtime-mode blockers in this bounded list. The parent Full1
macro/eval lane still has separate work, including native eval and a complete
same-candidate release aggregate.

The accepted lifecycle and its claim limits are explained in
`docs/00-project/MACRO_HOST_LIFECYCLE_DECISION.md`.

## Exit criteria to clear this list

1. `inproc` runs the same macro surfaces as `external-host` for the scoped compatibility matrix.
2. The external job prepares one candidate-bound host with stage0 forbidden and
   proves that unit, runci, display, and protocol checks reuse its digest.
3. Project-defined Haxe macro code has a stage0-free route into the reusable
   external host.
4. Weekly parity workflow stays green across both modes and all selected suites.
5. The current `inproc` default remains qualified for release with documented fallback policy and rollback plan.

## Current xhigh review

2026-03-08 closure review outcome:

- `MRP-B2` is now functionally sufficient for the declared Full1 scope.
- The previously material semantic seams now have focused direct green regressions:
  - `Context.getType()` typedef/abstract payload reconstruction:
    `test:m14:runtime-applied-type-metadata`
  - `Context.getModule()` field-type reconstruction plus `followWithAbstracts()` for
    component/slot-style flows:
    `test:m14:runtime-component-signature`
  - `Context.parseInlineString()` for balanced inline-markup splice bodies:
    `test:m14:runtime-inline-markup-parse`
  - anonymous-structure `resolveComplexType()` / `toComplexType()` roundtrip, including
    typedef-backed `final` field preservation:
    `test:m14:runtime-anonymous-complex`
  - parser/typeExpr lambda seam:
    `test:m14:runtime-typed-lambda`
  - build-field snapshot fidelity:
    `test:m14:runtime-build-fields`
- Upstream Haxe 4.3.7 remains the compatibility oracle. Sibling Reflaxe repos remain pressure tests only.
- Residual synthetic-fidelity improvements that are not required for honest Full1 closure are now tracked as post-1.0 work in `haxe.ocaml-8nv.11.6`.
- `MRP-B3` release/gate wiring is closed: macro runtime parity is reusable, release-aware, and consumed by Gate Full1.

2026-07-14 lifecycle review outcome:

- The prior semantic API work remains closed; it should not be reopened to own a
  host-artifact lifecycle failure.
- The generic committed host is accepted as the near-term artifact for the
  selected external-host aggregate when its commit, snapshot tree, digest,
  protocol handshake, and stage0-forbidden policy are recorded and revalidated.
- This lifecycle evidence does not prove arbitrary project macros. That distinct
  Full1 obligation is now `MRP-B6` / `haxe_ocaml-vhk47.3`.

2026-07-14 project-module implementation checkpoint:

- One repo-owned no-argument Haxe macro is compiled by the current `hxhx`
  candidate into bytecode and native OCaml plugin forms without editing the
  generated OCaml.
- Both macro modes validate the same candidate/ABI/expression/digest receipt and
  produce the same program output as the upstream Haxe 4.3.7 oracle.
- Focused local evidence emits `PROJECT_MACRO_MODULE:PASS`, including negative
  checks for wrong candidate, wrong ABI, changed digest, changed expression, and
  missing files.
- This is one bounded loading-path proof, not support for every project macro.
  Exact-commit run `29349360051` repeated the proof on a clean Linux runner,
  passed both established macro-runtime jobs, and emitted the aggregate Full1
  macro marker.

## Recently resolved

| Blocker ID | Resolution | Landed in |
| --- | --- | --- |
| MRP-B1 | Inproc runtime now mirrors the current exact-string generated entrypoint set used by the Stage4 bring-up fixtures instead of stopping at builtin macros only. | `haxe.ocaml-bxlg.9.4` |
| MRP-B2 | External-host/runtime macro API coverage is now sufficient for the declared Full1 scope. The remaining previously material seams (typedef/abstract payload reconstruction, component/slot signature introspection, balanced inline-markup parsing, anonymous complex-type roundtrip, typed lambda parsing, and build-field snapshot fidelity) all have focused direct regressions and no longer require keeping the semantic closure bead open. Residual synthetic-fidelity polish moved to post-1.0 follow-up `haxe.ocaml-8nv.11.6`. | `haxe.ocaml-bxlg.9.5` |
| MRP-B3 | Macro runtime parity is now a release-aware reusable workflow and Gate Full1 consumes it before emitting Full1 aggregate pass markers. | `haxe.ocaml-bxlg.9.6` |
| MRP-B4 | Default runtime mode flipped to `inproc`; fallback/rollback policy documented (`HXHX_MACRO_RUNTIME_MODE=external-host` or `--hxhx-macro-runtime external-host`). | `haxe.ocaml-bxlg.9.3` |
| MRP-B5 | Exact-commit run `29334023225` built one generic host from the candidate's committed snapshot with stage0 forbidden, recorded and revalidated its commit/tree/digest/protocol receipt, reused it for unit/runci/display/protocol checks, and passed both external-host and in-process jobs without recursive or lazy rebuilding. | `haxe_ocaml-vhk47.1` |
| MRP-B6 | Exact-commit run `29349360051` at `3806c611` generated one repo-owned Haxe project macro as authenticated bytecode/native plugins, loaded and ran it through both native macro modes without stage0, passed the established two-mode macro matrix, and emitted `FULL1_MACRO_PARITY:PASS`. Project evidence artifact `8317497905` has digest `sha256:aa3c83f4b56e9cba8c1dd661e0319928447ccbd56620f298b778cc1a42248766`; summary artifact `8317500638` has digest `sha256:b294cbc5c7b9383cf9d4fb1494cc0ae0ecd4570253f0bc601e7165573b78d839`. | `haxe_ocaml-vhk47.3` |
