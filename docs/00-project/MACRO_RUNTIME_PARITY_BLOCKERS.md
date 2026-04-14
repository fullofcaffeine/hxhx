# Macro Runtime Parity Blockers

Last audited: 2026-03-08

This list tracks the explicit blockers for declaring `inproc` and `external-host` macro runtime modes parity-equivalent for production defaults.

Beginner summary:
- `external-host`: macros run in a separate `hxhx-macro-host` process.
- `inproc`: macros run inside `hxhx` directly.
- Today the default runtime mode is already `inproc`.
- The remaining work is to qualify that default for release, keep `external-host` as the explicit fallback/debug lane, and close the remaining parity gaps.

## Open blockers

No scoped macro runtime parity blockers remain open for the declared Full1 surface.
## Exit criteria to clear this list

1. `inproc` runs the same macro surfaces as `external-host` for the scoped compatibility matrix.
2. Weekly parity workflow stays green across both modes and all selected suites.
3. The current `inproc` default remains qualified for release with documented fallback policy and rollback plan.

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

## Recently resolved

| Blocker ID | Resolution | Landed in |
| --- | --- | --- |
| MRP-B1 | Inproc runtime now mirrors the current exact-string generated entrypoint set used by the Stage4 bring-up fixtures instead of stopping at builtin macros only. | `haxe.ocaml-bxlg.9.4` |
| MRP-B2 | External-host/runtime macro API coverage is now sufficient for the declared Full1 scope. The remaining previously material seams (typedef/abstract payload reconstruction, component/slot signature introspection, balanced inline-markup parsing, anonymous complex-type roundtrip, typed lambda parsing, and build-field snapshot fidelity) all have focused direct regressions and no longer require keeping the semantic closure bead open. Residual synthetic-fidelity polish moved to post-1.0 follow-up `haxe.ocaml-8nv.11.6`. | `haxe.ocaml-bxlg.9.5` |
| MRP-B3 | Macro runtime parity is now a release-aware reusable workflow and Gate Full1 consumes it before emitting Full1 aggregate pass markers. | `haxe.ocaml-bxlg.9.6` |
| MRP-B4 | Default runtime mode flipped to `inproc`; fallback/rollback policy documented (`HXHX_MACRO_RUNTIME_MODE=external-host` or `--hxhx-macro-runtime external-host`). | `haxe.ocaml-bxlg.9.3` |
