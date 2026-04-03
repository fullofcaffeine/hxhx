# reflaxe.ocaml Upstream Compiler-Target Plugin Seam Probe

Last reviewed: 2026-04-03

This note records the result of `haxe.ocaml-anoy.4.1`: whether upstream Haxe `4.3.7` exposes a real extension seam for a true compiler-target/native-target plugin path for `reflaxe.ocaml`, distinct from the already-supported eval-host adapter path.

## Result

Fail closed.

Upstream Haxe `4.3.7` does **not** expose a stable compiler-target plugin seam that is comparable to `hxhx` native backend loading.

What upstream Haxe does expose today is:

- eval-host plugin loading through `eval.vm.Context.loadPlugin`
- macro callback hooks such as:
  - `Context.onAfterInitMacros`
  - `Context.onAfterTyping`
  - `Context.onGenerate`
  - `Context.onAfterGenerate`
  - `Context.onTypeNotFound`

Those are real and useful seams, but they are not a true compiler-target/backend registration ABI.

## Evidence

### 1. The only actual plugin loader is in the eval host

The concrete upstream plugin-loading surface is:

- `vendor/haxe/std/eval/vm/Context.hx`
  - `eval.vm.Context.loadPlugin(filePath)`
- `vendor/haxe/src/macro/eval/evalStdLib.ml`
  - eval-side `StdContext.loadPlugin`
  - OCaml `Dynlink.loadfile`

That means upstream plugin loading is an eval-host runtime feature. It is not a generator/backend registration path.

### 2. The public macro hook surface is compiler-observer/configuration oriented

Upstream macro hooks are exposed in:

- `vendor/haxe/std/haxe/macro/Context.hx`
- wired in `vendor/haxe/src/typing/macroContext.ml`

Those callbacks let macros:

- inspect typed modules
- define new types
- patch metadata/configuration
- run code before or after generation

They do **not** provide:

- target registration
- backend replacement
- generator substitution
- a native plugin ABI for codegen providers

The upstream docs are explicit that `onGenerate` is mainly for information and metadata-level modification, not generator replacement.

### 3. Target identity is a closed enum

Upstream target selection is hard-coded in:

- `vendor/haxe/src/core/globals.ml`

`platform` is a closed OCaml variant:

- `Js`
- `Lua`
- `Neko`
- `Flash`
- `Php`
- `Cpp`
- `Cs`
- `Java`
- `Python`
- `Hl`
- `Eval`

There is no dynamic registration path such as:

- `register_target`
- `load_target_plugin`
- `register_generator`

or any equivalent public host API.

### 4. Backend initialization and generation dispatch are both closed matches

Backend initialization is hard-wired in:

- `vendor/haxe/src/compiler/compiler.ml`
  - `Setup.initialize_target`

Final generator dispatch is hard-wired in:

- `vendor/haxe/src/compiler/generate.ml`

That dispatch is a closed `match com.platform with ...` over built-in generators:

- `Genjs.generate`
- `Genlua.generate`
- `Genphp7.generate`
- `Gencpp.generate`
- `Gencs.generate`
- `Genjava.generate`
- `Genjvm.generate`
- `Genpy.generate`
- `Genhl.generate`
- eval interpreter special case

There is no host seam where an external backend can register itself into that dispatch table.

### 5. Target-specific behavior is broadly hard-wired across the compiler

The backend decision is not isolated to one file.

Current upstream source counts from the local `vendor/haxe` checkout:

- `com.platform` references: `84`
- `match com.platform` references: `32`

That means a hypothetical plugin target would not just need one load hook. It would need a stable capability contract across typing, filters, optimizer, native library handling, codegen, and target-specific policy surfaces.

## What would need to exist for a true compiler-target plugin path

For this path to be promoted from non-goal to experimental support, upstream Haxe would need all of the following:

### 1. Dynamic target identity / CLI registration

Instead of a closed `Globals.platform` enum, upstream would need a supported way to register:

- target id / name
- target output mode
- target-specific std path or package rules
- target-specific defines/capabilities

Without that, any “plugin target” is really just a private compiler fork.

### 2. Stable target capability contract

The current compiler depends on `com.platform` in many phases. A real extension seam would need a stable capability/provider interface that covers, at minimum:

- platform config
- optimization/analysis flags
- native library handling
- filtering/lowering behavior
- output path setup

Without that, external targets would have to patch upstream internals rather than extend them.

### 3. Generator registration seam

The compiler would need a supported backend registry or provider interface that replaces the current closed `match com.platform` dispatch in `compiler/generate.ml`.

That seam would need to let an external backend supply:

- target initialization
- final generation function
- any target-specific dump/report naming

### 4. Typed-phase hook with stable ownership boundary

Macro hooks happen around typing/generation, but they do not own the backend boundary.

A true target plugin path would need a documented phase seam between:

- finalized typed modules / post-filter IR
- backend-specific lowering / emit

That seam would need to specify what the plugin receives, what it may mutate, and what the host guarantees about ordering and invariants.

### 5. Host/plugin ABI outside eval-only loading

`eval.vm.Context.loadPlugin` is not enough.

A true compiler-target plugin path would need a supported host/plugin ABI for:

- loading backend providers
- version/ABI validation
- failure reporting
- lifecycle/registration ownership

without pretending eval VM dynlink is the same thing as backend loading.

## Concrete blockers today

These are the blockers that make the answer “no” right now:

1. No upstream API exists to register or substitute a target/backend.
2. Target identity is a closed enum in `Globals.platform`.
3. Target setup is hard-wired in `compiler.ml`.
4. Generator dispatch is hard-wired in `generate.ml`.
5. Target policy is scattered across dozens of `com.platform` branches.
6. The only real plugin loader is eval-host-specific and not documented as a backend ABI.
7. Public macro hooks are not a replacement for backend registration.

## Promotion threshold: non-goal to experimental support

This path may only move from non-goal to experimental support if upstream Haxe provides all of the following and they are stable enough to test without compiler patching:

1. A documented host API for registering or loading a backend/target provider.
2. A non-fork target identity model that does not require editing the closed platform enum.
3. A documented backend/generator dispatch seam.
4. A documented typed-phase ownership boundary for backend plugins.
5. A reproducible host/plugin ABI/versioning contract.
6. Enough upstream proof to exercise the path with a real workload, not just a toy plugin.

If any one of those is missing, the path stays a non-goal.

## Practical repo consequence

The supported upstream path remains:

- upstream Haxe eval-host adapter via `eval.vm.Context.loadPlugin`

This probe does **not** broaden that support claim.

For `reflaxe.ocaml`, that means:

- keep documenting upstream support as an eval-host adapter path
- keep native compiler-target/plugin claims scoped to `hxhx`
- do not advertise “upstream native backend plugins” unless upstream itself grows the missing extension seams above

## Related docs

- `docs/00-project/REFLAXE_OCAML_UPSTREAM_PLUGIN_INTEGRATION_DECISION.md`
- `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`
- `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`
