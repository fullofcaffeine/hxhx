# Haxe-in-Haxe Acceptance Criteria (What “Replacement-Ready” Means)

This document answers two related questions:

1) What does it mean for our **Haxe-in-Haxe** compiler to be “done enough”?
2) What would justify saying: **“this can replace the official Haxe compiler”** (for Haxe **4.3.7**)?

We treat the upstream Haxe repo as the **source of truth** for correctness and compatibility:

- Upstream checkout (default): `vendor/haxe` (fetch with `bash scripts/vendor/fetch-haxe-upstream.sh`)
- Override upstream checkout: `HAXE_UPSTREAM_DIR=/path/to/haxe`
- Upstream test harnesses: `tests/unit/*` and `tests/runci/*` (see `tests/RunCi.hx`)

## Key point: “compile the test files” is necessary but not sufficient

In the upstream Haxe repo:

- Some tests only check that code **compiles**.
- Many tests require that the generated program **runs** and produces correct results.
- A large portion of “real-world readiness” is **macro execution**, **module resolution**, **display server**, and
  correct behavior of the analyzer/DCE pipeline.

So the acceptance criteria must include **compile + run** for the official test suites, not just “it compiles”.

## Definitions

### Project naming

- `hxhx` is the end-user/compiler **product name** (CLI/binary).
- `hih-*` (“Haxe-in-Haxe”) packages are internal staged bring-up libraries that `hxhx` uses.

### What “compile Haxe” means (terminology)

In this repo, the phrase “compile Haxe” can refer to three different things:

1) **Compile `reflaxe.ocaml` (this repository)**:
   This is a Haxe library/backend that runs *inside* a Haxe compiler process.
   Practically, this means we need a working **stage0 `haxe` binary** to run tests and generate OCaml output, but we do **not** need to compile the upstream OCaml compiler source as part of normal development.

2) **Compile the upstream Haxe compiler itself** (the official `haxe` binary):
   Upstream Haxe is written in **OCaml**, so “compiling Haxe” can also mean “build the upstream OCaml compiler source with the OCaml toolchain”.
   In this repo we treat upstream primarily as a **behavioral oracle** (tests + reference implementation), not as a build dependency.

3) **Compile Haxe programs/projects**:
   This is what users generally mean. Long-term, `hxhx` is intended to be a `haxe`-compatible compiler binary that can compile real Haxe projects (including macros and IDE/display workflows) and run the upstream test suites.

### “Haxe-in-Haxe enough” (Phase A goal)

Means we can use our backend to run **compiler-shaped workloads** that resemble Haxe’s architecture:

- multi-module parsing and typing
- incremental rebuilds / module cache
- basic macro-like staging boundaries (even if macros are stubbed)

In this repo, that maps to acceptance workloads in `workloads/` (e.g. `hih-workload`, `hih-compiler`).

### “Replacement-ready” (Phase B / 1.0 goal)

Means we can replace `haxe` (the official OCaml compiler) as the **primary compiler binary** for Haxe 4.3.7 in
real projects.

This requires:

- CLI and semantics compatibility for “normal compilation”
- macro correctness (a large part of the ecosystem depends on it)
- tooling parity for IDE usage (`--display` and related behavior)
- cross-target correctness (at least for the targets we claim to support)

## Acceptance levels (gates)

These are ordered so we can land value continuously, while keeping the final “replacement” claim rigorous.

## Current bring-up status (snapshot)

As of **2026-02-08**, the repo is in “bootstrap + upstream harness wiring” mode:

- Gate 1 (`npm run test:upstream:unit-macro`): defaults to a **native/non-delegating bring-up rung**
  (Stage3 `--hxhx-emit-full-bodies` emit+build+run), intended to surface missing frontend/macro ABI behavior without invoking a stage0 `haxe` binary.
  - The historical stage0-shim baseline is still available as: `npm run test:upstream:unit-macro-stage0`.
  - CI cadence: weekly Linux baseline in `.github/workflows/gate1.yml` + manual `workflow_dispatch` override.
  - Gate1 unit-macro scripts now fail fast on non-zero exits across hosts, and all Stage3 rungs (`no-emit`, `type-only`, `emit`) run widening-enabled (`HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES=1`).
- Gate 2 (`npm run test:upstream:runci-macro`): defaults to a **non-delegating** rung (`HXHX_GATE2_MODE=stage3_no_emit_direct`).
  - An experimental rung exists (`stage3_emit_runner`) which now compiles+runs the upstream `tests/RunCi.hxml`
    under the Stage3 bootstrap emitter, but it does not yet execute the full Macro orchestration loop faithfully.
    (Expect low sub-invocation counts until enum/switch/using semantics are expanded.)
  - A bring-up rung exists (`stage3_emit_runner_minimal`) which patches RunCi in the temporary worktree to prove
    sub-invocation spawning deterministically.

### Gate 0 — Self-hosting sanity (repo-local)

Passes when:

- `npm run test:acceptance` succeeds (compile → dune build → run) for:
  - `workloads/hih-workload` (Stage 1)
  - `workloads/hih-compiler` (Stage 2 skeleton)

This is our “always runnable” smoke coverage.

### Stage 2 reproducibility rung (bootstrap sanity)

This is not a replacement gate by itself, but it’s a key bootstrap checkpoint:

- Build stage1 `hxhx` (native OCaml binary).
- Use that stage1 binary to build stage2.
- Check that stage2 behaves the same (and that stage1/stage2 codegen is stable enough for the current implementation).

Stage 3 (typing bring-up) design notes live in:

- `docs/02-user-guide/HXHX_STAGE3_TYPING.md:1`

Run:

- `npm run test:upstream:stage2`

### Gate 1 — Upstream “Macro” unit test suite (core semantics)

This is the first **real upstream gate**.

Passes when the Haxe-in-Haxe compiler can run the upstream unit tests in interpreter mode:

- `haxe/tests/unit/compile-macro.hxml` (upstream) succeeds and the resulting unit runner reports success.

#### Important note (current state)

Today, `npm run test:upstream:unit-macro` is already the **non-delegating** Gate 1 bring-up entrypoint.
It executes upstream `compile-macro.hxml` through native Stage3 with full emit/build/run, while keeping the
macro-host path stage0-free by default.

The historical stage0 baseline remains available for harness comparison/debugging:

- `npm run test:upstream:unit-macro-stage0`

The dedicated native alias is equivalent to the default entrypoint:

- `npm run test:upstream:unit-macro-native`

#### OCaml note: how we emulate upstream `--interp`

Upstream Gate 1 uses `--interp` as “compile + run”.

For OCaml (a native target), we emulate `--interp` as:

- compile to OCaml + generate dune project
- build native executable (`-D ocaml_build=native`)
- run the produced binary

Bring-up helper flags (shim-only):

- `--hxhx-ocaml-interp`: enables “interp-like” behavior for the OCaml target
- `--hxhx-ocaml-out <dir>`: forces `-D ocaml_output=<dir>` (useful for deterministic test runs)

Bring-up runner script:

- `bash scripts/hxhx/run-upstream-unit-macro-ocaml.sh`
  - Equivalent: `npm run test:upstream:unit-macro-ocaml`
  - Requires `dune` + `ocamlc` on `PATH`
  - Requires an upstream checkout at `vendor/haxe` or `HAXE_UPSTREAM_DIR=/path/to/haxe`

This runner still uses the stage0 `haxe` binary for compilation today; it exists to validate the
native build+run harness while the non-delegating compiler pipeline is under construction.

#### Upstream “static platform” checks (Null semantics)

Upstream unit tests sometimes treat “static platforms” as a proxy for “nullable primitives behave differently”.

Example (from `tests/unit/src/unit/TestReflect.hx`):

- On static platforms (`flash`, `cpp`, `java`, `cs`, `hl`) `Type.createEmptyInstance` yields `0` for `Int` fields.
- On dynamic platforms it yields `null`.

Our strategy (for Gate 1 bring-up) is:

- **Do not spoof** any of the upstream platform defines (`hl`, `cpp`, …). Doing so would pull in a large amount of
  platform-specific tests and APIs (e.g. `hl.F32`, `TestHL`) that are unrelated to OCaml.
- Instead, keep the OCaml target’s **portable** surface permissive enough that the upstream “dynamic branch” typechecks
  and runs under our runtime model.

When we flip the OCaml target’s “native surface” to be stricter about nullable primitives (and avoid boxing where
possible), we may need a small upstream-compat patch set for those specific tests, or upstream may accept an `ocaml`
define in the relevant conditionals.

Native Gate 1 currently runs through Stage3 full emit/build/run. That means this rung now exercises:

- macro host bootstrap + hook registration
- Stage3 typing/model passes on upstream-shaped inputs
- OCaml emission/build wiring for the upstream unit workload

Host bring-up note:

- Gate1 unit-macro scripts keep widening semantics exercised in routine runs for all Stage3 rungs (`no-emit`, `type-only`, `emit`) via `HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES=1`.
- Stage3 unit-macro scripts no longer apply a Darwin-specific retry fallback; non-zero exits fail fast.
- Stage3 `emit` enforces warning cleanliness for OCaml warning classes `20` (`ignored-extra-argument`), `21` (`nonreturning-statement`), and `26` (`unused-var`); any hit is treated as a gate failure.

Why this gate matters:

- `compile-macro.hxml` uses `--interp` and includes macro initialization (`--macro Macro.init()`).
- It exercises typing, the analyzer, macro execution hooks, and a broad set of language features.

### Gate 2 — Upstream `runci` “Macro” target (tooling + integration)

Upstream CI has an explicit “Macro” runci target: `tests/runci/targets/Macro.hx`.

Passes when we can run the equivalent of:

- `tests/RunCi.hx` with `TEST=Macro` (or by directly running the Macro target logic)

This target includes (non-exhaustive, based on upstream code):

- running `compile-macro.hxml`
- building/running the display server fixtures (`tests/display`)
- sourcemaps tests (`tests/sourcemaps`)
- null safety suites (`tests/nullsafety`)
- misc compiler checks (`tests/misc`)
- sys tests (`tests/sys`)
- “compiler loops” regression checks (`tests/misc/compiler_loops`)
- threads suite under `--interp`

This is the point where we’re no longer “just a compiler”: we’re a compiler **toolchain**.

#### Running Gate 2 locally (and sys-stage caveats)

In this repo, Gate 2 is exercised via:

- `npm run test:upstream:runci-macro` (wraps `scripts/hxhx/run-upstream-runci-macro.sh`)
  - CI cadence: weekly Linux baseline in `.github/workflows/gate2.yml` + manual `workflow_dispatch` override.

Today, `npm run test:upstream:runci-macro` defaults to a **non-delegating** Gate 2 mode:

- `HXHX_GATE2_MODE=stage3_no_emit_direct` (default): runs the same stage sequence as upstream runci Macro, but routes every
  `haxe` invocation through `hxhx --hxhx-stage3 --hxhx-no-emit` (stage0-free in the hot path).

Other useful modes:

- `HXHX_GATE2_MODE=stage0_shim`: historical baseline (execute upstream `RunCi.hxml` via stage0 `haxe`, with wrappers).
- `HXHX_GATE2_MODE=stage3_emit_runner`: experimental rung that compiles+executes upstream `tests/RunCi.hx` under the Stage3
  bootstrap emitter (goal: run it unmodified and route sub-invocations through Stage3 `--no-emit`).
  - This rung fails on OCaml warning classes `20` (`ignored-extra-argument`), `21` (`nonreturning-statement`), and `26` (`unused-var`).
- `HXHX_GATE2_MODE=stage3_emit_runner_minimal`: bring-up rung that patches `tests/RunCi.hx` *in the temporary worktree* to a
  minimal harness so we can prove sub-invocation spawning (not full runci acceptance).

CI workflow notes (scheduled + manual upstream job) live in:

- `docs/02-user-guide/HXHX_GATE2_WORKFLOW.md:1`

Host toolchain requirements (minimum):

- OCaml build tools: `dune`, `ocamlc`
- Neko tools: `neko`, `nekotools` (RunCi uses an echo server)
- `python3` (some sys fixtures)
- a C compiler (`cc`/`clang`/`gcc`) and `javac` (some misc/sys fixtures)

macOS note:

- Upstream `tests/sys` includes fixtures that intentionally create filenames that are invalid on macOS/APFS (e.g.
  surrogate codepoints), which can fail with `OSError: [Errno 92] Illegal byte sequence`.
- For now, our Gate2 runner **skips the sys stage on macOS** with an explicit message.
- To force attempting sys on macOS anyway, set `HXHX_GATE2_FORCE_SYS=1` (expected to fail today).

### Gate 3 — Upstream full `tests/runci` matrix for claimed targets

Replacement-ready claims must be explicit about which targets we support.

Passes when:

- For each claimed target, the corresponding upstream `tests/runci/targets/*` suite passes.
- On at least one supported OS baseline (Linux is the usual baseline; Windows/macOS parity is a later requirement).

Run a selectable subset locally via:

- `HXHX_GATE3_TARGETS="Macro,Js,Neko" npm run test:upstream:runci-targets`
- `npm run test:hxhx:builtin-target-smoke` (linked fast-path sentinel: compares delegated `--target ocaml` vs builtin `--target ocaml-stage3` on the same tiny workload)
- `HXHX_BUILTIN_SMOKE_OCAML=0 HXHX_BUILTIN_SMOKE_JS_NATIVE=1 npm run test:hxhx:builtin-target-smoke` (linked `js-native` emit+run smoke lane only)
- CI cadence: weekly Linux baseline via `.github/workflows/gate3.yml` with deterministic defaults (`targets=Macro,Js,Neko`, `macro_mode=direct`, `allow_skip=0`).
- Builtin target smoke cadence: weekly Linux baseline via `.github/workflows/gate3-builtin.yml` (manual dispatch supports `reps`, `run_js_native`).
- PR/push CI includes `JS-native smoke` (`.github/workflows/ci.yml`) so non-delegating `--target js-native` emit+run stays continuously checked.
- Optional CI dispatch: same workflow with manual overrides (`targets`, `allow_skip`, `macro_mode=direct|stage0_shim`).
- `HXHX_GATE3_MACRO_MODE=direct` (default) routes only the `Macro` target through the non-delegating Gate 2 direct runner while leaving other targets on the stage0-shim path.
- `HXHX_GATE3_MACRO_MODE=stage0_shim` keeps the historical stage0 RunCi harness path for `Macro` when needed for debugging/comparison.
- Gate 3 applies a deterministic flake policy by default for `Js`: `HXHX_GATE3_RETRY_COUNT=1`, `HXHX_GATE3_RETRY_TARGETS=Js`, `HXHX_GATE3_RETRY_DELAY_SEC=3` (set count to `0` to disable).
- On macOS, the upstream `Js` server stage remains enabled, but Gate 3 relaxes async timeouts (`HXHX_GATE3_JS_SERVER_TIMEOUT_MS=60000` by default). Set `HXHX_GATE3_FORCE_JS_SERVER=1` to run without timeout patches (debug mode).
- Python target runs default to no-install mode (`HXHX_GATE3_PYTHON_ALLOW_INSTALL=0`): both `python3` and `pypy3` must already be on `PATH`. Set `HXHX_GATE3_PYTHON_ALLOW_INSTALL=1` to allow upstream installer/network fallback.
- Java target has a validated Gate3 baseline via `HXHX_GATE3_TARGETS=Java`; default quick-run target set remains `Macro,Js,Neko` for runtime cost control.

If we claim “full replacement”, this implies passing the same set of targets upstream CI runs (JS, Neko, HL, JVM/Java,
Python, Lua, PHP, C#, C++/hxcpp, etc.), which may require external toolchains.

Notes:

- For `Macro`, our Gate 3 runner applies the same stability knobs as Gate 2:
  - `HXHX_GATE2_SKIP_PARTY=1` (default) skips the upstream `tests/party` stage (network-heavy/flaky).
  - `HXHX_GATE2_SEED_UTEST_FROM_GLOBAL=1`, `HXHX_GATE2_SEED_HAXESERVER_FROM_GLOBAL=1`, `HXHX_GATE2_SEED_SOURCEMAP_FROM_GLOBAL=1`
    seed the local `.haxelib` repo from globally installed libs to avoid network installs when possible.

### Gate 4 — Build + distribution parity

Passes when:

- We can build the compiler artifact as a distributable binary (or binaries) in a way compatible with upstream release
  expectations (versioning, `haxelib`, packaging, etc.).
- Performance is within an agreed tolerance (define and track via benchmarks).

See `docs/02-user-guide/HXHX_DISTRIBUTION.md:1`.

## What “can replace the original compiler” means (strict version)

For Haxe **4.3.7**, we can credibly claim replacement when:

1) Gate 2 is solid (Macro runci passes), and
2) Gate 3 passes for the set of targets we claim, and
3) IDE/display workflows are supported to a practical degree, and
4) Macro-heavy real projects build successfully (use a curated set of external projects as an acceptance suite).

In other words: passing upstream CI (or an equivalent subset) is the strongest objective signal we can use.

## Bootstrapping model (Stage0 → Stage1 → Stage2)

When we say `hxhx` is “bootstrapping”, we mean:

If you want a beginner-oriented “are we self-hosting yet?” checklist, see:

- `docs/01-getting-started/HXHX_SELF_HOSTING_CHECKLIST.md`

- **Stage0**: we start from an existing `haxe` binary (the upstream OCaml compiler you install via releases or build yourself).
- **Stage1**: use stage0 `haxe` to compile/build `hxhx` into a native OCaml binary.
- **Stage2**: use the stage1 `hxhx` binary to build the next `hxhx` binary (itself), and check that it behaves equivalently.

This bootstrapping is about `hxhx` becoming a self-hosting compiler; it does **not** mean `hxhx` compiles upstream’s OCaml compiler sources (Haxe does not compile OCaml).

### Note on “native code” and multi-target bootstrapping

Haxe historically compiles to **target source code** (or bytecode/IR) and relies on an external toolchain to produce a runnable artifact.
This does not make `hxhx` bootstrapping fundamentally different — it just means:

- `hxhx` must be available as a runnable compiler executable (Stage1/Stage2 binaries).
- The *way* that executable is produced depends on which backend we compile `hxhx` with:
  - OCaml backend → native OCaml executable via `dune`/`ocamlopt`.
  - A hypothetical Rust/C++ backend → native executable via `cargo`/`clang`/etc.

In all cases, the portability goal is the same:

- keep compiler core logic in Haxe,
- keep any “host runtime” shims small, justified, and replaceable,
- and avoid OCaml-only assumptions in compiler core so other native targets remain feasible.

## Recommended project QA strategy (mirrors upstream + our repo layers)

We keep three layers:

1) **Golden output** (snapshots): catch codegen shape regressions quickly.
2) **Portable fixtures** (compile → dune build → run): catch behavioral/runtime regressions.
3) **Acceptance workloads** (`examples/`): catch compiler-shaped integration issues early.

Then we add an upstream-facing layer:

4) **Upstream Haxe suite runner**: run `tests/unit` and `tests/runci` using the Haxe-in-Haxe compiler binary.
