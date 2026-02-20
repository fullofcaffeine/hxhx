# Testing Strategy

This repo’s tests are intentionally split into **fast compiler checks** and **behavioral checks** that require an OCaml toolchain.

The goal is to:

- keep `npm test` fast enough for tight iteration
- still have realistic “this actually builds and runs under dune” coverage
- provide at least one **compiler-shaped acceptance workload** (not just unit tests / golden output)

## Quick start

From the repo root:

```bash
npm test
```

If you have `ocamlc` + `dune` installed, this also runs:

- portable conformance fixtures (`test/portable/**`)
- example apps (`examples/**`, except acceptance-only examples)

To run heavier acceptance checks:

```bash
npm run test:acceptance
```

By default this uses `WORKLOAD_PROFILE=fast` (developer-friendly) and skips marked heavy workloads.
Use the full profile when you need full compiler-shaped coverage:

```bash
npm run test:acceptance:full
```

## Cleanup after heavy runs

Long upstream/gate/bootstrap runs can leave sizeable temp/build artifacts.

From repo root:

```bash
npm run clean:dry-run
npm run clean
npm run clean:tmp
npm run clean:deep
```

Details and retention knobs (`HXHX_KEEP_LOGS`, `HXHX_LOG_DIR`) are documented in:
`docs/01-getting-started/CLEANUP_AND_CACHE_POLICY.md`

## Upstream Haxe acceptance gates (Haxe-in-Haxe path)

These are **not** part of `npm test` because they depend on:

- a local checkout of the upstream Haxe compiler repo
- extra toolchains / deps (`haxelib`, network for pinned libs, etc.)

Plain-English gate map:

- **Gate 1**: “core compatibility” — upstream unit macro suite.
- **Gate 2**: “bigger macro workflow” — upstream `runci` Macro target.
- **Gate 3**: “target matrix” — staged target workflows (`Macro`, `Js`, `Neko`, opt-in extras).

Gate 1 (unit macro suite) uses the upstream file:

- `tests/unit/compile-macro.hxml`

Run it via the `hxhx` harness:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:unit-macro
```

Notes:

- Today `npm run test:upstream:unit-macro` is a **native/non-delegating bring-up rung**:
  it routes the upstream `compile-macro.hxml` through `hxhx --hxhx-stage3 --hxhx-emit-full-bodies` to exercise
  resolver + typer + macro-host plumbing plus OCaml emit/build wiring without invoking a stage0 `haxe` binary.
  - The historical stage0-shim baseline remains available as:
    `npm run test:upstream:unit-macro-stage0`
  - CI cadence:
    - per-push/PR macro smoke in `.github/workflows/gate1-lite.yml` (`test:upstream:unit-macro-stage3-no-emit`)
    - weekly full Linux baseline in `.github/workflows/gate1.yml`, plus manual `workflow_dispatch` override (`run_upstream_unit_macro=true`).
  - Gate1 unit-macro rungs now fail fast across hosts (including macOS), and all Stage3 rungs (`no-emit`, `type-only`, `emit`) run with `HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES=1`.
  - The Stage3 `emit` rung fails on OCaml warning classes `20` (`ignored-extra-argument`), `21` (`nonreturning-statement`), and `26` (`unused-var`).
- By default, upstream gate runners look for `vendor/haxe`; override with `HAXE_UPSTREAM_DIR=/path/to/haxe`.
- “Replacement-ready” acceptance is defined in `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`.
  That document also clarifies what we mean by “compile Haxe” and how Stage0→Stage2 bootstrapping works.

Gate 2 (runci Macro target) runs the upstream `tests/runci/targets/Macro.hx` suite:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:runci-macro
```

Notes:

- This is **not** part of PR/push CI by default (it is network-heavy and relies on external toolchains).
  A Linux baseline run is executed weekly in `.github/workflows/gate2.yml`, and it remains manually triggerable via `workflow_dispatch` + `run_upstream_macro=true`.
- Host toolchain requirements and macOS sys-stage caveats are documented in `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`.
- Debugging: set `HXHX_GATE2_MISC_FILTER=<pattern>` to run only a subset of `tests/misc` fixtures.
- By default this uses a **non-delegating** Gate 2 mode (`HXHX_GATE2_MODE=stage3_no_emit_direct`): it runs the same stage
  sequence as upstream runci Macro, but routes every `haxe` invocation through `hxhx --hxhx-stage3 --hxhx-no-emit`.
  - To run the historical “stage0 shim” harness instead, set `HXHX_GATE2_MODE=stage0_shim`.
  - `HXHX_GATE2_MODE=stage3_emit_runner` is an experimental rung: it tries to compile+run the upstream RunCi runner under the
    Stage3 bootstrap emitter (intended to run upstream `tests/RunCi.hx` unmodified once Stage3 is ready).
    - This runner now defaults to bootstrap snapshots for faster iteration.
    - This runner treats OCaml warning classes `20` (`ignored-extra-argument`), `21` (`nonreturning-statement`), and `26` (`unused-var`) as hard failures.
    - Set `HXHX_FORCE_STAGE0=1` if you explicitly want to rebuild `hxhx` from source before running it.
    - Timeout/heartbeat knobs:
      - `HXHX_GATE2_RUNCI_TIMEOUT_SEC` (default `600`; set `0` to disable timeout)
      - `HXHX_GATE2_RUNCI_HEARTBEAT_SEC` (default `20`; set `0` to disable heartbeat lines)
      - Heartbeat line format: `gate2_stage3_emit_runner_heartbeat elapsed=<sec>s subinvocations=<n> last="<command>"`
      - `HXHX_GATE2_SKIP_DARWIN_SEGFAULT=1` (default) converts intermittent macOS `tests/misc/resolution` SIGSEGV (exit 139) into a deterministic skipped-stage marker in direct mode; set `0` to force fail-fast during debugging.
      - Gate2 summary now prints `subinvocations=<n>` and `last_subinvocation=<cmd>` for direct/runner modes.
- `HXHX_GATE2_MODE=stage3_emit_runner_minimal` is a bring-up rung that patches `tests/RunCi.hx` *in the temporary worktree*
  to a minimal harness so we can at least prove sub-invocation spawning.
- `HXHX_GATE2_MACRO_STOP_AFTER=<stage>` (direct mode only) stops the Macro sequence after a named stage and prints explicit markers.
  - Supported: `unit`, `display`, `sourcemaps`, `nullsafety`, `misc`, `resolution`, `sys`, `compiler_loops`, `threads`, `party`.
  - Useful for targeted iteration without running the full Gate2 matrix.

Focused display rung (non-delegating, direct Macro sequence up to display):

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:runci-macro-stage3-display
```

Success markers:
- `macro_stage=display status=ok`
- `gate2_display_stage=ok`
- `gate2_stage3_no_emit_direct=ok stop_after=display`

Notes:
- This focused rung sets `HXHX_GATE2_SKIP_UNIT=1` so it can isolate display semantics
  without being blocked by unrelated `tests/unit` bring-up gaps.

### Bootstrap stage map (quick reference)

Use this when you want the repo to function as a compiler-bootstrap example:

- **Stage0**: external `haxe` compiles repo Haxe sources to OCaml.
  - Main maintainer command: `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh`
- **Stage1**: build `hxhx` from committed bootstrap snapshot (`out.bc` / native fallback).
  - Command: `bash scripts/hxhx/build-hxhx.sh`
  - Observability knobs: `HXHX_BOOTSTRAP_HEARTBEAT=20` (default; set `0` to disable) and `HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS=0` (optional timeout).
- **Stage2**: stage1 builds stage2; compare behavior/codegen stability.
  - Command: `npm run test:upstream:stage2`
- **Gate checks**: validate against upstream behavior oracles.
  - Gate1: `npm run test:upstream:unit-macro`
  - Gate2: `npm run test:upstream:runci-macro`
  - Display end-to-end smoke: `npm run test:upstream:display-stage3-emit-run-smoke`

Dedicated display smoke rung (non-delegating Stage3 no-emit):

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:display-stage3-no-emit
```

Notes:

- This validates `--display <file@mode>` request handling directly through `hxhx --hxhx-stage3 --hxhx-no-emit`.
- It also includes a `--wait stdio` framed-protocol smoke check (non-delegating server lifecycle).
- It intentionally does **not** require full upstream display semantic parity yet.
- Socket server/client protocol regression coverage lives in `npm run test:hxhx-targets`
- Stage3 receiver-call over-application regression (`other.add(n)` should not become `add (this_) (other) (n)`) is covered by `npm run test:m14:hih-emitter-receiver-call` (source-level, no Stage0 rebuild needed).
- Backend registry descriptor/selection regression coverage is in `npm run test:m14:backend-registry`.
- OCaml target-core wrapper wiring regression coverage is in `npm run test:m14:target-core-wiring`.
- JS target-core wrapper wiring regression coverage is in `npm run test:m14:js-target-core-wiring`.
- Statement-level parser coverage for try/catch + throw is in `npm run test:m14:hih-try-throw-stmt`.
- JS statement lowering coverage for try/catch + throw is in `npm run test:m14:js-stmt-try-throw`.
- JS statement multi-catch dispatch lowering coverage is in `npm run test:m14:js-stmt-multi-catch`.
- JS expression lowering regressions are covered by `npm run test:m14:js-expr-new-array` and
  `npm run test:m14:js-expr-range` and `npm run test:m14:js-expr-array-comprehension` and
  `npm run test:m14:js-expr-switch`.
- `npm run test:hxhx-targets` validates runtime delegation guard behavior when the current
  `hxhx` binary exposes `HXHX_FORBID_STAGE0` shim enforcement.
- For quicker local reruns after a successful build, you can reuse an existing binary:
  `HXHX_BIN=packages/hxhx/out/_build/default/out.bc npm run test:hxhx-targets`.
- `npm run test:hxhx-targets` defaults to stage0 lane builds (`HXHX_FORCE_STAGE0=1`);
  set `HXHX_FORCE_STAGE0=0` to run against stage0-free bootstrap snapshots.
- Stage0 build-lane observability defaults:
  - default heartbeat is bounded (`HXHX_STAGE0_HEARTBEAT=30`)
  - default failfast is bounded (`HXHX_STAGE0_FAILFAST_SECS=7200`)
  - optional RSS guard (`HXHX_STAGE0_MAX_RSS_MB=<limit>`) hard-stops runaway stage0 builds.
  - optional lower-memory compile mode (`HXHX_STAGE0_NO_INLINE=1`) adds `--no-inline` to stage0 source builds.
  - override defaults for this test lane with:
    - `HXHX_TARGETS_STAGE0_HEARTBEAT_DEFAULT=<sec>`
    - `HXHX_TARGETS_STAGE0_FAILFAST_DEFAULT=<sec>`
- CI split for stability:
  - `Tests` runs `npm run test:hxhx-targets` with `HXHX_FORCE_STAGE0=0` (stage0-free bootstrap path).
  - `Gate 1 Lite` workflow (`.github/workflows/gate1-lite.yml`) runs the upstream macro smoke rung (`test:upstream:unit-macro-stage3-no-emit`) on every push/PR.
  - `Stage0 Source Smoke` workflow (`.github/workflows/stage0-source-smoke.yml`) separately validates
    stage0 source-build behavior (`HXHX_FORCE_STAGE0=1`) on a nightly/manual lane
    (tuned with `HXHX_STAGE0_OCAML_BUILD=byte`, `HXHX_STAGE0_DISABLE_PREPASSES=1`, and `HXHX_STAGE0_NO_INLINE=1`; the lane enforces `>=8GB` swapfile capacity on ubuntu runners to reduce OOM kills).
  - each Stage0 Source Smoke run emits `stage0_peak_tree_rss_mb=<n>` and uploads
    `stage0_source_build.log` as a workflow artifact.
  - local telemetry helpers:
    - parse one build log: `bash scripts/ci/extract-stage0-peak-rss.sh <stage0_source_build.log>`
    - aggregate recent GitHub samples (default 5): `bash scripts/ci/stage0-source-rss-baseline.sh --allow-partial`
    - include failed runs in the sample set for early diagnosis: `bash scripts/ci/stage0-source-rss-baseline.sh --include-failures --allow-partial`
  - current ubuntu-latest success baseline (5 samples, 2026-02-20): `min=15028MB`, `median=15103MB`, `avg=15134.4MB`, `max=15253MB`; CI policy keeps `HXHX_STAGE0_MAX_RSS_MB=0` (cap disabled) to avoid false-positive kills near runner limits.
- `npm run test:hxhx-targets` also validates request-scoped Stage3 provider loading:
  `HXHX_BACKEND_PROVIDERS=backend.js.JsBackend` must override `js-native` backend selection
  (`backend_selected_impl=provider/js-native-wrapper`) while fallback stays `builtin/js-native`.
- If the current `hxhx` binary does not expose `js-native`, `npm run test:hxhx-targets` skips
  js-native-only checks and prints explicit skip markers (dedicated js-native CI smoke still enforces the lane).
  (`--wait <host:port>` + `--connect <host:port>` roundtrip).

Dedicated display full-emit warm-output stress rung:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:display-stage3-emit-stress
```

Notes:

- This runs upstream `tests/display/build.hxml` repeatedly under
  `hxhx --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run`.
- It intentionally reuses the same `--hxhx-out` directory across iterations to catch
  warm-output determinism/linking regressions.
- Tune iteration count with `HXHX_DISPLAY_EMIT_STRESS_ITERS=<n>` (default: `10`).

Dedicated display full-emit + run smoke rung:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:display-stage3-emit-run-smoke
```

Notes:

- This runs upstream `tests/display/build.hxml` with execution enabled
  (`hxhx --hxhx-stage3 --hxhx-emit-full-bodies`, no `--hxhx-no-run`).
- It now requires successful execution (`run=ok`) and fails on any non-zero exit.
- It also explicitly fails hard on segfault-shaped regressions (`Segmentation fault` / `EXC_BAD_ACCESS` / rc `139`).
- On success it emits `display_utest_suite=ok` after validating this is the utest workload
  and that `resolved_modules` meets a minimum threshold (default `80`, configurable via
  `HXHX_DISPLAY_EMIT_RUN_MIN_RESOLVED`).

### Stage 2 reproducibility rung (Stage1 builds Stage2)

This is a local bootstrap sanity check:

- Build stage1 `hxhx` (native OCaml binary).
- Use that stage1 binary to build stage2.
- Compare behavior and (best-effort) emitted `.ml` output hashes.

Run:

```bash
npm run test:upstream:stage2
```

### Gate 3 (runci matrix for selected targets)

Gate 3 runs additional upstream `tests/runci` targets beyond `Macro`.

Select targets via `HXHX_GATE3_TARGETS` (comma-separated) or pass them as args:

```bash
HXHX_GATE3_TARGETS="Macro,Js,Neko" npm run test:upstream:runci-targets
```

Run the linked builtin target smoke (delegated `--target ocaml` vs builtin `--target ocaml-stage3`):

```bash
npm run test:hxhx:builtin-target-smoke
```

Run the JS-native emit+run lane only (no OCaml timing compare):

```bash
HXHX_BUILTIN_SMOKE_OCAML=0 HXHX_BUILTIN_SMOKE_JS_NATIVE=1 npm run test:hxhx:builtin-target-smoke
```

Notes:

- Full delegated-vs-builtin OCaml timing smoke is **not** part of PR/push CI by default (toolchain/runtime cost).
- Gate 3 CI workflow (`.github/workflows/gate3.yml`) runs weekly on Linux with deterministic defaults (`targets=Macro,Js,Neko`, `macro_mode=direct`, `allow_skip=0`).
  It is also manually triggerable with `workflow_dispatch` inputs for `targets`, `allow_skip`, and `macro_mode`.
- Builtin target smoke CI (`.github/workflows/gate3-builtin.yml`) runs on push/PR (main/master), and remains scheduled weekly plus manually triggerable with `workflow_dispatch` (`reps`, `run_js_native`).
- PR/push CI (`.github/workflows/ci.yml`) includes a dedicated `JS-native smoke` job (`HXHX_BUILTIN_SMOKE_OCAML=0`, `HXHX_BUILTIN_SMOKE_JS_NATIVE=1`).
- By default, missing target toolchains fail the run; set `HXHX_GATE3_ALLOW_SKIP=1` to skip missing deps.
- Flaky-target retry policy defaults to one retry for `Js` (`HXHX_GATE3_RETRY_COUNT=1`, `HXHX_GATE3_RETRY_TARGETS=Js`, `HXHX_GATE3_RETRY_DELAY_SEC=3`); set `HXHX_GATE3_RETRY_COUNT=0` to disable.
- Long-run observability/guardrails: `HXHX_GATE3_TARGET_HEARTBEAT_SEC=20` prints periodic progress (set `0` to disable) and `HXHX_GATE3_TARGET_TIMEOUT_SEC=0` controls per-target timeout (set a non-zero value to fail hard hangs). The weekly CI baseline sets `HXHX_GATE3_TARGET_TIMEOUT_SEC=3600`.
- On macOS, the upstream `Js` server stage remains enabled, but Gate 3 relaxes async timeouts (`HXHX_GATE3_JS_SERVER_TIMEOUT_MS=60000` by default). Set `HXHX_GATE3_FORCE_JS_SERVER=1` to run without timeout patches (debug mode).
- Python target runs default to no-install mode (`HXHX_GATE3_PYTHON_ALLOW_INSTALL=0`): both `python3` and `pypy3` must already be on `PATH`. Set `HXHX_GATE3_PYTHON_ALLOW_INSTALL=1` to allow upstream installer/network fallback.
- Java is validated as an opt-in Gate3 target (`HXHX_GATE3_TARGETS=Java`) and intentionally kept out of the default set (`Macro,Js,Neko`) to keep routine runs faster.
- `HXHX_GATE3_MACRO_MODE` controls how Gate 3 executes the `Macro` target:
  - `direct` (default): route `Macro` through the non-delegating Gate 2 direct runner (`--hxhx-stage3 --hxhx-no-emit`).
  - `stage0_shim`: use the historical stage0 RunCi harness path.
- For the `Macro` target, the runner applies the same stability knobs as Gate 2:
  - `HXHX_GATE2_SKIP_PARTY=1` (default) skips `tests/party` (network-heavy).
  - `HXHX_GATE2_SEED_UTEST_FROM_GLOBAL=1`, `HXHX_GATE2_SEED_HAXESERVER_FROM_GLOBAL=1`, `HXHX_GATE2_SEED_SOURCEMAP_FROM_GLOBAL=1`
    seed the local `.haxelib` repo from globally installed libs to avoid network installs when possible.

### M7 replacement-ready bundle

Use one command to run a curated replacement-readiness bundle with a clear PASS/FAIL summary:

```bash
npm run test:upstream:replacement-ready
```

Profiles:

- `fast` (default): `ci:guards`, `test:hxhx-targets`, focused Gate2 display rung, builtin target smoke.
- `full`: includes `fast` plus Gate1 unit-macro, Gate2 runci Macro, and Gate3 runci targets.
  - Host-aware default for Gate3 targets in this bundle: Linux=`Macro,Js,Neko`, macOS=`Macro,Neko` (override with `HXHX_GATE3_TARGETS=...`).

Examples:

```bash
# Full bundle
HXHX_M7_PROFILE=full npm run test:upstream:replacement-ready

# Full bundle, strict mode (fails on skipped upstream checks)
HXHX_M7_PROFILE=full HXHX_M7_STRICT=1 npm run test:upstream:replacement-ready
```

The manual workflow `.github/workflows/gate-m7.yml` runs the same bundle with inputs for `profile` and `strict`.

## Layers

### 1) “Build the backend” checks (fast, no dune required)

These checks run `haxe` compilations and/or compare emitted `.ml` text:

- **Printer tests**: ensure OCaml AST printing stays stable/valid.
- **Integration compile tests**: ensure the backend can compile representative Haxe code.
- **Snapshot tests** (`test/snapshot/**`): golden `.ml` output comparisons (compile-to-OCaml only; no dune build).

These catch regressions in:

- TypedExpr lowering (`OcamlBuilder`)
- printing/formatting (`OcamlASTPrinter`)
- module scheduling/ordering (`OcamlCompiler`)

### 2) “Runs under dune” checks (requires OCaml toolchain)

If `dune` and `ocamlc` are available, we additionally run:

- **Portable fixtures** (`test/portable/fixtures/**`): compile → dune build → run → diff stdout.
- **Examples** (`examples/**`): compile → dune build → run → diff stdout.

These catch regressions that pure snapshot tests can’t, like:

- OCaml type errors caused by ordering/dependencies
- missing runtime shims or incorrect OCaml stdlib usage
- runtime-level behavioral differences (null semantics, string handling, sys APIs)

### 3) Acceptance workloads (explicitly heavier)

`npm run test:acceptance` runs two heavier layers:

- acceptance-only examples under `examples/` (flagged with `ACCEPTANCE_ONLY`)
- compiler-shaped workloads under `workloads/`

Current workload set:

- `workloads/hih-workload` — Stage 1 multi-file "project compiler" workload
- `workloads/hih-compiler` — Stage 2/3 compiler-skeleton workload (marked heavy)

Profiles:

- `fast` (default): runs non-heavy workloads only
- `full`: runs all workloads, including heavy compiler-shaped ones

Commands:

```bash
# default acceptance path (developer-friendly)
npm run test:acceptance

# full acceptance path (includes heavy workloads)
npm run test:acceptance:full

# workload layer only (fast profile by default)
npm run test:workloads

# run only the heavy compiler workload explicitly
WORKLOAD_PROFILE=full WORKLOAD_FILTER=hih-compiler npm run test:workloads
```

Runtime controls (`scripts/test-workloads.sh`):

- `WORKLOAD_PROGRESS_INTERVAL_SEC` (default `20`) prints heartbeat lines during long compile steps
- `WORKLOAD_HEAVY_TIMEOUT_SEC` (default `600`) compile timeout budget for workloads marked with `HEAVY_WORKLOAD`
- `WORKLOAD_TIMEOUT_SEC` overrides compile timeout budget for all workloads (`0` disables timeout)
- `WORKLOAD_FILTER=<substring>` runs matching workloads only

Runtime baseline output:

- each workload prints `timing: compile=<sec> run=<sec> total=<sec>`
- the script ends with a global summary line including profile, run/skipped counts, and total seconds
