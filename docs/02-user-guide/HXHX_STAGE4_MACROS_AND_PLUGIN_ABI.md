# HXHX Stage 4: Native Macro Execution + Plugin ABI (Design)

Stage 4 is when `hxhx` stops being “a compiler that can type code” and becomes a **compiler ecosystem**:

- it **executes macros** (including build macros like `@:build`, CLI macros like `--macro`, and macro libraries)
- it supports the practical “plugin system” hook points (`Context.onAfterTyping`, `Context.onGenerate`, …)
- it can load macro backends such as `reflaxe.ocaml` / `reflaxe.elixir` without delegating to stage0

This doc defines the execution model and the ABI boundary we will implement.

## Why this is hard (and why the ABI matters)

In upstream Haxe, macros run on a dedicated macro platform (historically Neko, later HL / interpreter), and the compiler
and macros interact through a well-defined API (`haxe.macro.Context`, `haxe.macro.Compiler`) and a compiler-managed
execution model (macro initialization order, reuse, caching, error reporting, etc.).

For `hxhx`, the objective is different:

- we want **native** compilation (OCaml toolchain) and to keep the compiler fast and reproducible
- we want macro execution to be compatible enough to pass upstream gates (see `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`)
- we want to support real-world “compiler plugins” that are implemented as macro libraries (Reflaxe targets)

This forces an explicit boundary between:

- the **compiler core** (parsing/typing/analyzer/codegen)
- the **macro runtime** (execution + `Context` / `Compiler` APIs)
- the **plugin loader** (how we load user macro code and connect it to the compiler)

## Terms

- **Stage0 `haxe`**: upstream OCaml compiler binary.
- **`hxhx`**: our Haxe-in-Haxe compiler binary (built to native OCaml via `reflaxe.ocaml`).
- **Macro module**: Haxe code compiled for “macro context” (`--macro`, `@:build`, etc.).
- **Macro host**: the runtime that executes macro code and exposes `haxe.macro.*` APIs.
- **Plugin ABI**: the interface between compiler core and macro host (and between macro host and loaded macro modules).

## The three viable macro execution models

Stage 4 should explicitly pick one *initial* model, while leaving room for a later optimization.

### Model A (recommended first): Out-of-process macro host (RPC)

**Idea:** run macros in a separate `hxhx-macro` process and communicate via a versioned protocol.

Pros:

- isolation: macro crashes/leaks don’t corrupt the compiler process
- restartability: can reset macro context deterministically between compilations
- easier to mirror upstream “macro server” behaviors (reuse, caching, display hooks)
- avoids OCaml native `Dynlink` complexity in the first implementation

Cons:

- protocol work (serialization of types/exprs/positions)
- overhead vs in-process calls (mitigated by batching + caching)

This model defines the **Stage 4 Plugin ABI** as an RPC protocol:

- compiler core ↔ macro host: request/response messages
- macro host ↔ macro modules: direct calls within macro host process

### Model B (later optimization): In-process macros via OCaml `Dynlink` (`.cmxs`)

**Idea:** compile macro modules to OCaml and dynlink them into the running `hxhx` binary.

Pros:

- fastest path (no serialization; direct function calls)
- enables “builtin” backends and tighter integration (see `docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md:1`)

Cons:

- platform/toolchain complexity (`.cmxs` build, ABI stability, path handling)
- harder to reset macro context safely (state must be carefully isolated)

This model defines the Plugin ABI as an OCaml module signature (stable entrypoints + shared data model).

### Model C (long-term): Embed a Haxe macro interpreter/eval in `hxhx`

**Idea:** implement Haxe macro execution without compiling macro code to OCaml.

Pros:

- closest to “Haxe in Haxe” purity
- avoids OCaml dynlink and avoids RPC serialization

Cons:

- largest implementation effort (essentially porting upstream eval machinery)

## Chosen rollout (Stage 4 plan)

We start with **Model A** (RPC macro host), then optionally add **Model B** as a fast-path once correctness is stable:

1) Implement the macro host protocol and the minimal macro API surface to pass Gate 1.
2) Expand hook points + display/tooling behaviors to pass Gate 2.
3) Add dynlink/builtin fast-path only once macro semantics are stable (performance work should not destabilize correctness).

## What gets compiled/linked (concrete artifact story)

### Stage 4 with Model A

- `hxhx` (native OCaml executable)
  - contains compiler core
  - contains protocol client for talking to macro host
- `hxhx-macro` (native OCaml executable)
  - contains macro runtime + `haxe.macro.*` API implementations
  - loads user macro modules (compiled-to-OCaml or via an internal macro interpreter, depending on rung)

Macro modules are compiled (by `hxhx`) into a macro-host-consumable form:

- initial rung: compile macro modules to OCaml and link them into `hxhx-macro` (simplest)
- later rung: compile macro modules to `.cmxs` and load into `hxhx-macro` dynamically

### How this interacts with `--library` and `--target`

- `--library` (`-lib`) remains the *language-level* mechanism: it adds macro code to the compilation universe.
- `--target <id>` (our distribution shim) remains a *preset mechanism* that injects the right `--library`/`-D` flags.

See `docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md:1` for the registry semantics. Stage 4 extends it with:

- when macro execution is native, bundled macro backends are loaded by the macro host
- builtin backends become possible as “linked plugins” with no classpath scan (fast-path)

## Plugin ABI: required interactions (minimum viable)

The macro host must support (minimum viable, for Gate 1):

- initialize macro context (once per compilation)
- execute CLI macros (`--macro`)
- execute build macros (`@:build`, `@:autoBuild`)
- provide `Context.*` calls used by upstream unit tests:
  - `Context.getBuildFields`, `Context.getLocalClass/Type/Module`, `Context.currentPos`
  - `Context.resolveType`, `Context.toComplexType`
  - hook points: `Context.onAfterTyping`, `Context.onGenerate` (even if no-op initially)

### ABI surface sketch (RPC)

The protocol must carry:

- positions (file + spans)
- macro-time AST (expressions, fields, types) in a stable, versioned encoding
- diagnostics (errors + related positions)

And the request set must include:

- “type this macro module”
- “run this macro entrypoint”
- “expand build macro for this class”
- “invoke Context.* API X”

The intent is not to freeze a public API immediately, but to make the boundary **explicit** and **testable**.

Protocol details for the Stage 4 (Model A) bring-up live in:

- `docs/02-user-guide/HXHX_MACRO_HOST_PROTOCOL.md:1`

## Acceptance mapping

Stage 4 is considered “meaningfully implemented” when:

- Gate 1 passes (upstream `tests/unit/compile-macro.hxml`)
- Gate 2 passes (upstream `tests/runci` Macro target, including display fixtures)

See:

- `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`
- `docs/02-user-guide/COMPILER_PLUGIN_SYSTEM.md:1`

## Notes on “do we need a flag to build native?”

OCaml targets ultimately produce native code via the OCaml toolchain (typically dune).

For user ergonomics:

- `reflaxe.ocaml` already supports `-D ocaml_build=native` for “generate `.ml` and build a native binary”.
- `hxhx` should default to native builds where it is acting as a build tool (examples/acceptance already do this).

In other words: we should not require a separate “two-step” flag for typical usage; the compiler/tooling should do the
right thing by default, while still allowing advanced users to keep intermediate `.ml` output.
