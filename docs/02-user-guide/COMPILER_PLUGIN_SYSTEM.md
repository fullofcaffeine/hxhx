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
- **Executing macros inside `hxhx` itself** is not a Gate 0 requirement. Until the Haxe-in-Haxe compiler grows a real
  macro interpreter/runtime, macros are executed by the *stage0* Haxe compiler (upstream OCaml), and `reflaxe.ocaml`
  must correctly compile the resulting typed output.

However, Gate 1 (upstream `compile-macro.hxml`) is *macro heavy*, so we should expect macro work early.

## API surface (what we consider “plugin system” APIs)

The authoritative list lives in upstream:

- `std/haxe/macro/Context.hx`
- `std/haxe/macro/Compiler.hx`

For our planning and acceptance gates, we group APIs by “hook points” vs “macro utilities”.

### Hook points (the “plugin” part)

These are the callbacks libraries use to extend compilation:

- `Context.onGenerate`
- `Context.onAfterGenerate`
- `Context.onAfterTyping`
- `Context.onAfterInitMacros`
- `Context.onTypeNotFound`
- `Context.onMacroContextReused`

### Build macro essentials (what most `@:build` macros use)

- `Context.getBuildFields`
- `Context.getLocalClass` / `Context.getLocalType` / `Context.getLocalModule`
- `Context.currentPos`
- `Context.parse` / `Context.parseInlineString` (optional, but common)
- `Context.defineType` / `Context.defineModule` (for “codegen at compile-time” style macros)
- `Context.resolveType` / `Context.toComplexType` (type plumbing)

### Configuration macro essentials (`--macro` in init phase)

- `Compiler.define`, `Compiler.addClassPath`, `Compiler.include/exclude`
- `Compiler.addGlobalMetadata`, `Compiler.keep`, `Compiler.nullSafety`
- `Context.defined`, `Context.definedValue`, `Context.getDefines`

## Repo-local acceptance workload (Gate 0)

To keep us honest early, we have a tiny build-macro example that compiles to OCaml and runs under dune:

- `examples/build-macro/`

This does **not** prove `hxhx` can execute macros yet; it proves that:

- `@:build` macros can generate fields for code that targets `reflaxe.ocaml`, and
- our backend/runtime can compile and run the resulting program.

## Implementation staging (recommended)

Use the acceptance gates as the “plugin system” rollout sequence:

Design details for Stage 4 (native macro execution + ABI boundary) live in:

- `docs/02-user-guide/HXHX_STAGE4_MACROS_AND_PLUGIN_ABI.md:1`

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

## ABI versioning (Stage 4 bring-up)

Stage 4’s first macro execution model runs macros in an out-of-process “macro host” and communicates over a
versioned, line-based RPC protocol.

Contract (current bring-up):

- Macro host prints `hxhx_macro_rpc_v=1` as its first line (server banner).
- Compiler replies `hello proto=1`.
- Macro host replies `ok`.

This is intentionally small but **strict**: if the version mismatches, `hxhx` must fail fast with a clear error.

Why this matters

- It lets us evolve the macro/plugin boundary (hooks, emitted artifacts, typed AST transport) without silently
  breaking older builds.
- It gives the repo a stable “plugin ABI” concept even before we support upstream’s full macro surface.

Tests

- `scripts/test-hxhx-targets.sh` exercises:
  - handshake + stub APIs (`--hxhx-macro-selftest`)
  - fixture macro libraries that behave like compiler plugins (hooks + defines + classpath injection + emission)
