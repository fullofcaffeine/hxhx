# Haxe-in-Haxe Acceptance Criteria (What “Replacement-Ready” Means)

This document answers two related questions:

1) What does it mean for our **Haxe-in-Haxe** compiler to be “done enough”?
2) What would justify saying: **“this can replace the official Haxe compiler”** (for Haxe **4.3.7**)?

We treat the upstream Haxe repo as the **source of truth** for correctness and compatibility:

- Haxe compiler source: `/Users/fullofcaffeine/workspace/code/haxe.elixir.reference/haxe`
- Upstream test harnesses: `tests/unit/*` and `tests/runci/*` (see `tests/RunCi.hx`)

## Key point: “compile the test files” is necessary but not sufficient

In the upstream Haxe repo:

- Some tests only check that code **compiles**.
- Many tests require that the generated program **runs** and produces correct results.
- A large portion of “real-world readiness” is **macro execution**, **module resolution**, **display server**, and
  correct behavior of the analyzer/DCE pipeline.

So the acceptance criteria must include **compile + run** for the official test suites, not just “it compiles”.

## Definitions

### “Haxe-in-Haxe enough” (Phase A goal)

Means we can use our backend to run **compiler-shaped workloads** that resemble Haxe’s architecture:

- multi-module parsing and typing
- incremental rebuilds / module cache
- basic macro-like staging boundaries (even if macros are stubbed)

In this repo, that maps to acceptance workloads in `examples/` (e.g. `hih-workload`, `hih-compiler`).

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

### Gate 0 — Self-hosting sanity (repo-local)

Passes when:

- `npm run test:acceptance` succeeds (compile → dune build → run) for:
  - `examples/hih-workload` (Stage 1)
  - `examples/hih-compiler` (Stage 2 skeleton)

This is our “always runnable” smoke coverage.

### Gate 1 — Upstream “Macro” unit test suite (core semantics)

This is the first **real upstream gate**.

Passes when the Haxe-in-Haxe compiler can run the upstream unit tests in interpreter mode:

- `haxe/tests/unit/compile-macro.hxml` (upstream) succeeds and the resulting unit runner reports success.

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

### Gate 3 — Upstream full `tests/runci` matrix for claimed targets

Replacement-ready claims must be explicit about which targets we support.

Passes when:

- For each claimed target, the corresponding upstream `tests/runci/targets/*` suite passes.
- On at least one supported OS baseline (Linux is the usual baseline; Windows/macOS parity is a later requirement).

If we claim “full replacement”, this implies passing the same set of targets upstream CI runs (JS, Neko, HL, JVM/Java,
Python, Lua, PHP, C#, C++/hxcpp, etc.), which may require external toolchains.

### Gate 4 — Build + distribution parity

Passes when:

- We can build the compiler artifact as a distributable binary (or binaries) in a way compatible with upstream release
  expectations (versioning, `haxelib`, packaging, etc.).
- Performance is within an agreed tolerance (define and track via benchmarks).

## What “can replace the original compiler” means (strict version)

For Haxe **4.3.7**, we can credibly claim replacement when:

1) Gate 2 is solid (Macro runci passes), and
2) Gate 3 passes for the set of targets we claim, and
3) IDE/display workflows are supported to a practical degree, and
4) Macro-heavy real projects build successfully (use a curated set of external projects as an acceptance suite).

In other words: passing upstream CI (or an equivalent subset) is the strongest objective signal we can use.

## Recommended project QA strategy (mirrors upstream + our repo layers)

We keep three layers:

1) **Golden output** (snapshots): catch codegen shape regressions quickly.
2) **Portable fixtures** (compile → dune build → run): catch behavioral/runtime regressions.
3) **Acceptance workloads** (`examples/`): catch compiler-shaped integration issues early.

Then we add an upstream-facing layer:

4) **Upstream Haxe suite runner**: run `tests/unit` and `tests/runci` using the Haxe-in-Haxe compiler binary.

