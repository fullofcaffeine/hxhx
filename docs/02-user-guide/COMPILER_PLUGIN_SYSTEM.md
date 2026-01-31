# Compiler “Plugin System” Compatibility (Macros and Hook Points)

In practice, the “plugin system” of the Haxe compiler is mostly the **macro + hook surface**:

- `--macro ...` CLI macros
- `@:build` / `@:autoBuild` build macros
- macro-time APIs that let libraries **hook into compilation**

If we want a Haxe-in-Haxe compiler to be **replacement-ready**, we must support the macro/hook behaviors that real
projects depend on.

This doc defines what “plugin system support” means for `reflaxe.ocaml`’s Haxe-in-Haxe path.

## Source of truth

Behavior is defined by upstream Haxe:

- macro API surface: `std/haxe/macro/Context.hx`, `std/haxe/macro/Compiler.hx`
- CI harness: `tests/RunCi.hx` and `tests/runci/targets/Macro.hx`
- unit entrypoint for macro-heavy behavior: `tests/unit/compile-macro.hxml`

See also `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1` for the acceptance gates that rely on these.

## What we mean by “plugin system”

For this project, “plugin system support” is:

1) **Macro execution works** for non-trivial projects:
   - macro modules compile and run
   - macros can inspect/construct types and expressions
   - macros can emit new fields/types and influence compilation

2) **Macro hook points work**, i.e. the compiler calls user-provided callbacks at the correct times and with correct data:
   - examples include (not exhaustive): “after typing”, “on generate”, “on type not found”

3) **CLI macros behave like upstream**:
   - `--macro Macro.init()` and similar patterns

4) **Build macros behave like upstream**:
   - `@:build(...)` and `@:autoBuild(...)` on types

## Non-goals (initially)

We will stage this intentionally:

- Supporting every macro API edge case immediately is not required for “Phase A — Haxe-in-Haxe enough”.
- Perfect parity for display server behavior is a later gate.

However, Gate 1 (upstream `compile-macro.hxml`) is *macro heavy*, so we should expect macro work early.

## Implementation staging (recommended)

Use the acceptance gates as the “plugin system” rollout sequence:

1) **Gate 0 (repo-local acceptance examples)**:
   - `examples/hih-compiler` grows macro stubs into real macro execution for a small subset.

2) **Gate 1 (upstream `tests/unit/compile-macro.hxml`)**:
   - implement the minimal macro/hook surface required for this suite to pass.

3) **Gate 2 (upstream runci “Macro” target)**:
   - implement the remaining macro/hook + tooling behaviors for integration-level parity.

## Testing the plugin system

We should avoid “ad-hoc macro tests” that drift from upstream.

Instead, prefer:

- a small repo-local acceptance example that uses a build macro and asserts runtime behavior (fast regression signal),
- plus the upstream gates (`compile-macro.hxml`, then `runci Macro`) as the long-term oracle.

