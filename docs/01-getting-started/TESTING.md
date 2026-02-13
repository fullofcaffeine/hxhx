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

Gate 1 (unit macro suite) uses the upstream file:

- `tests/unit/compile-macro.hxml`

Run it via the `hxhx` harness:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:unit-macro
```

Notes:

- Today `npm run test:upstream:unit-macro` is a **native/non-delegating bring-up rung**:
  it routes the upstream `compile-macro.hxml` through `hxhx --hxhx-stage3 --hxhx-no-emit` to exercise
  resolver + typer + macro-host plumbing without invoking a stage0 `haxe` binary.
  - The historical stage0-shim baseline remains available as:
    `npm run test:upstream:unit-macro-stage0`
- By default, upstream gate runners look for `vendor/haxe`; override with `HAXE_UPSTREAM_DIR=/path/to/haxe`.
- “Replacement-ready” acceptance is defined in `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`.
  That document also clarifies what we mean by “compile Haxe” and how Stage0→Stage2 bootstrapping works.

Gate 2 (runci Macro target) runs the upstream `tests/runci/targets/Macro.hx` suite:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:runci-macro
```

Notes:

- This is **not** run in GitHub Actions CI by default (it is network-heavy and relies on external toolchains).
- Host toolchain requirements and macOS sys-stage caveats are documented in `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1`.
- Debugging: set `HXHX_GATE2_MISC_FILTER=<pattern>` to run only a subset of `tests/misc` fixtures.
- By default this uses a **non-delegating** Gate 2 mode (`HXHX_GATE2_MODE=stage3_no_emit_direct`): it runs the same stage
  sequence as upstream runci Macro, but routes every `haxe` invocation through `hxhx --hxhx-stage3 --hxhx-no-emit`.
  - To run the historical “stage0 shim” harness instead, set `HXHX_GATE2_MODE=stage0_shim`.
  - `HXHX_GATE2_MODE=stage3_emit_runner` is an experimental rung: it tries to compile+run the upstream RunCi runner under the
    Stage3 bootstrap emitter (intended to run upstream `tests/RunCi.hx` unmodified once Stage3 is ready).
    - This runner now defaults to bootstrap snapshots for faster iteration.
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
HXHX_GATE3_TARGETS="Macro,Js" npm run test:upstream:runci-targets
```

Notes:

- This is **not** run in CI by default (very toolchain/network dependent).
- Optional manual CI workflow: `.github/workflows/gate3.yml` (`Gate 3 (HXHX)`) with inputs for `targets` (default `Macro,Js`), `allow_skip`, and `macro_mode` (`stage0_shim`/`direct`).
- By default, missing target toolchains fail the run; set `HXHX_GATE3_ALLOW_SKIP=1` to skip missing deps.
- Flaky-target retry policy defaults to one retry for `Js` (`HXHX_GATE3_RETRY_COUNT=1`, `HXHX_GATE3_RETRY_TARGETS=Js`, `HXHX_GATE3_RETRY_DELAY_SEC=3`); set `HXHX_GATE3_RETRY_COUNT=0` to disable.
- On macOS, the upstream `Js` server stage remains enabled, but Gate 3 relaxes async timeouts (`HXHX_GATE3_JS_SERVER_TIMEOUT_MS=60000` by default). Set `HXHX_GATE3_FORCE_JS_SERVER=1` to run without timeout patches (debug mode).
- `HXHX_GATE3_MACRO_MODE` controls how Gate 3 executes the `Macro` target:
  - `stage0_shim` (default): use the existing stage0 RunCi harness path.
  - `direct`: route `Macro` through the non-delegating Gate 2 direct runner (`--hxhx-stage3 --hxhx-no-emit`).
- For the `Macro` target, the runner applies the same stability knobs as Gate 2:
  - `HXHX_GATE2_SKIP_PARTY=1` (default) skips `tests/party` (network-heavy).
  - `HXHX_GATE2_SEED_UTEST_FROM_GLOBAL=1`, `HXHX_GATE2_SEED_HAXESERVER_FROM_GLOBAL=1`, `HXHX_GATE2_SEED_SOURCEMAP_FROM_GLOBAL=1`
    seed the local `.haxelib` repo from globally installed libs to avoid network installs when possible.

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
