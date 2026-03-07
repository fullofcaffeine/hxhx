# Macro Runtime Parity Blockers

Last audited: 2026-03-06

This list tracks the explicit blockers for declaring `inproc` and `external-host` macro runtime modes parity-equivalent for production defaults.

Beginner summary:
- `external-host`: macros run in a separate `hxhx-macro-host` process.
- `inproc`: macros run inside `hxhx` directly.
- Today the default runtime mode is already `inproc`.
- The remaining work is to qualify that default for release, keep `external-host` as the explicit fallback/debug lane, and close the remaining parity gaps.

## Open blockers

| Blocker ID | Gap | Why it matters | Tracking |
| --- | --- | --- | --- |
| MRP-B2 | Macro API surface is still incomplete (`haxe.macro.Context` / `haxe.macro.Compiler` methods are partially implemented in bring-up layers). Recent slices now cover `Compiler.getConfiguration()`, a narrow exact-module `Compiler.include(...)` rung, compiler-owned resource storage through `Context.addResource()` / `Context.getResources()`, compiler-owned message snapshots through `Context.warning()` / `Context.info()` / `Context.getMessages()` / `Context.filterMessages()`, `Context.getClassPath()`, `Context.resolvePath()`, `Context.currentPos()`, `Context.getDisplayMode()`, `Context.containsDisplayPosition()`, `Context.getPosInfos()`, `Context.makePosition()`, a no-op compatibility rung for `Context.timer()`, compiler-seeded local-context queries (`getLocalModule()`, `getLocalMethod()`, `getLocalType()`, `getExpectedType()`, `getCallArguments()`, `getLocalClass()`, `getLocalImports()`, `getLocalUsing()`, `getLocalTVars()`), existence-only `Context.getModule()` through real classpath resolution, a narrow runtime `Context.makeExpr()` / `Context.signature()` slice for basic values, and a builtin-only runtime type slice for `Context.getType()`, `Context.resolveType()`, `Context.typeof()`, `Context.toComplexType()`, `Context.follow()`, `Context.followWithAbstracts()`, `Context.unify()`, and `TypeTools.toString()` / `TypeTools.toComplexType()` / `TypeTools.follow()` / `TypeTools.followWithAbstracts()` / `TypeTools.unify()` in external-host mode. A narrow synthetic typed-expression rung is now present for `Context.typeExpr()` / `Context.getTypedExpr()` plus `TypedExprTools.map()` / `iter()` / `mapWithType()` / `toString()` over literal, parenthesized, and simple-binop forms. Parser-backed `Context.parse()` / `Context.parseInlineString()` now cover a narrow local-expression subset (literals, idents, field/call chains, unary/binops, ternary, `new`, arrays, anon objects, `cast`, `untyped`). Rich typed module metadata, typed reflection, package-recursive include semantics, and broader typed-expression/parse support remain open. | Upstream macro compatibility claims are limited until API coverage expands. | `haxe.ocaml-bxlg.9.5` |
| MRP-B3 | Full upstream macro workloads and display checks are scheduled, not PR-required. | Regressions can land between scheduled runs and be detected later. | `haxe.ocaml-bxlg.9.2` |
## Exit criteria to clear this list

1. `inproc` runs the same macro surfaces as `external-host` for the scoped compatibility matrix.
2. Weekly parity workflow stays green across both modes and all selected suites.
3. The current `inproc` default remains qualified for release with documented fallback policy and rollback plan.

## Recently resolved

| Blocker ID | Resolution | Landed in |
| --- | --- | --- |
| MRP-B1 | Inproc runtime now mirrors the current exact-string generated entrypoint set used by the Stage4 bring-up fixtures instead of stopping at builtin macros only. | `haxe.ocaml-bxlg.9.4` |
| MRP-B4 | Default runtime mode flipped to `inproc`; fallback/rollback policy documented (`HXHX_MACRO_RUNTIME_MODE=external-host` or `--hxhx-macro-runtime external-host`). | `haxe.ocaml-bxlg.9.3` |
