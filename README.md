<p align="center">
  <img src="assets/hxhx-logo.png" alt="hxhx logo" width="560" />
</p>

# hxhx

[![CI](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml)
[![Compatibility Gate 1 Lite](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1-lite.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1-lite.yml)
[![Compatibility Gate 1](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1.yml)
[![Compatibility Gate 2](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2.yml)
[![Compatibility Gate 3](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.9.4-blue)](https://github.com/fullofcaffeine/hxhx/releases)

`hxhx` is a Haxe-in-Haxe compiler stack targeting Haxe `4.3.7` compatibility, paired with `reflaxe.ocaml` so the toolchain can bootstrap and ship native binaries under MIT.

## CI badges (plain English)

- **CI**: fast safety checks (guards + core tests) on regular changes.
- **Compatibility Gate 1 Lite**: per-commit upstream macro smoke (`stage3 no-emit`).
- **Compatibility Gate 1**: upstream unit macro compatibility baseline.
- **Compatibility Gate 2**: wider upstream `runci` macro workload checks.
- **Compatibility Gate 3**: target/workflow compatibility checks (`Macro`, `Js`, `Neko`, and opt-in targets).
- New contributor shortcut: start with `npm run ci:guards` and `npm test`; use gate docs for deeper validation: [docs/01-getting-started/TESTING.md](docs/01-getting-started/TESTING.md).

## Why this project exists

- **Hackability first:** compiler code should be readable and practical to extend.
- **Parity as a goal:** align behavior with upstream Haxe `4.3.7` through oracle-driven gates.
- **Permissive distribution path:** keep implementation provenance clean so embedding/commercial usage stays practical.
- **Performance path:** compile Reflaxe targets to native executables instead of relying only on eval workflows.

## Start here

- **Roadmap and milestones:** [docs/01-getting-started/HXHX_1_0_ROADMAP.md](docs/01-getting-started/HXHX_1_0_ROADMAP.md)
- **Acceptance criteria and gate definitions:** [docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md](docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md)
- **`reflaxe.ocaml` package README:** [packages/reflaxe.ocaml/README.md](packages/reflaxe.ocaml/README.md)
- **Use `reflaxe.ocaml` with upstream Haxe:** [docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md](docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md)
- **Backend architecture and contracts:** [docs/02-user-guide/HXHX_BACKEND_LAYERING.md](docs/02-user-guide/HXHX_BACKEND_LAYERING.md)
- **Macro host protocol:** [docs/02-user-guide/HXHX_MACRO_HOST_PROTOCOL.md](docs/02-user-guide/HXHX_MACRO_HOST_PROTOCOL.md)
- **Public release preflight checklist:** [docs/00-project/PUBLIC_RELEASE_PREFLIGHT.md](docs/00-project/PUBLIC_RELEASE_PREFLIGHT.md)
- **Stdlib reuse + provenance boundaries:** [docs/00-project/STD_LIB_POLICY.md](docs/00-project/STD_LIB_POLICY.md)

## Products in this repo

- `hxhx`: the primary compiler product (Haxe-in-Haxe).
- `reflaxe.ocaml`: an OCaml backend/runtime package used by `hxhx`, and also usable with upstream Haxe.
- Shared compiler/backend infrastructure developed together while the projects are still tightly coupled (`hxhx -> reflaxe.ocaml`).

## Monorepo strategy (for now)

We are keeping `hxhx` and `reflaxe.ocaml` in one monorepo because they still share bootstrap, runtime, and backend iteration loops. As coupling drops and gates stabilize, repo split/rename decisions can be revisited with lower risk.

## Using reflaxe.ocaml with upstream Haxe

See [docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md](docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md) for dedicated setup/usage.

## Environment setup

This repo has two “levels” of setup:

- **Emit-only** (generate `.ml` + dune scaffold): Node.js + Haxe (+ Lix).
- **Build/run** (produce a native executable): add OCaml + dune toolchain.

### Prerequisites

- **Node.js + npm** (used for Lix + dev tooling).
- **Haxe** (this repo targets Haxe **4.3.7** right now).
- **OCaml 5.2+ + dune** (required if you want to compile emitted OCaml or run stage0-free bootstrap flows).

macOS (Homebrew):

```bash
brew install ocaml dune ocaml-findlib
```

Linux (recommended, Debian/Ubuntu via opam):

```bash
sudo apt-get update
sudo apt-get install -y opam m4 pkg-config libgmp-dev
opam init -a --disable-sandboxing
opam switch create 5.2.1
eval "$(opam env)"
opam install -y dune ocamlfind
```

## reflaxe.ocaml usage (current scaffold)

This repo is set up for **Lix** (via `lix.client` / haxeshim-style `haxe_libraries`).

First-time setup:

```bash
npm install
npx lix download
```

Recommended local hooks (gitleaks + deterministic staged Haxe formatting):

```bash
npm run hooks:install
```

Pre-commit requirements:

- `gitleaks` available on `PATH` (or repo-local `./gitleaks` binary).
- `haxelib formatter` installed (`haxelib install formatter`).

Pre-commit now enforces:
- staged local-path leak guard
- staged gitleaks scan
- staged deterministic `.hx` auto-format

Manual formatting guard command:

```bash
npm run guard:hx-format
```

`npm run ci:guards` now includes the deterministic Haxe formatting check.

Manual secret scan guard command:

```bash
npm run guard:gitleaks
```

Manual machine-local path leak guard command:

```bash
npm run guard:local-paths
```

Public release preflight bundle:

```bash
npm run release:preflight
```

Contributor workflow details: `CONTRIBUTING.md`.
Release checklist: `docs/00-project/PUBLIC_RELEASE_PREFLIGHT.md`.

Generate `.ml` files into an output directory:

```bash
npx haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

`-D ocaml_output=<dir>` is required; it enables the compiler and selects the output folder.

By default, the target also emits a minimal `dune-project`, `dune`, and an executable entry module (`<exeName>.ml`) so the output directory is a runnable OCaml project.

### Build the emitted OCaml (native)

Option A (recommended): let the target invoke dune after emitting:

```bash
npx haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

Option B: build manually with dune:

```bash
cd out
dune build ./*.exe
```

Optional flags:

- `-D ocaml_no_dune` to disable dune scaffolding emission.
- `-D ocaml_dune_layout=exe|lib` to choose between an executable scaffold (default) or a library-only dune project.
- `-D ocaml_dune_exes=name:MainModuleId[,name2:MainModuleId...]` to emit a multi-executable dune stanza (`(executables ...)`) with one entry module per name.
- `-D ocaml_no_build` (or `-D ocaml_emit_only`) to skip post-emit build/run.
- `-D ocaml_build=native` (or `byte`) to force `dune build` after emitting (requires `dune` + `ocamlc` on PATH; fails hard if missing).
- `-D ocaml_run` to run the produced executable via `dune exec` after emitting (best-effort unless combined with `ocaml_build=...`).
- `-D ocaml_mli` (or `-D ocaml_mli=infer|all`) to generate inferred `*.mli` via `ocamlc -i` and rebuild with dune (requires `ocamlfind`).
- `-D ocaml_no_line_directives` to disable `# 1 "File.ml"` prefixes (default is enabled to improve dune error locations).
- `-D ocaml_sourcemap=directives` to emit additional line directives so dune/ocamlc errors can point back to `.hx` file/line (best-effort).

## hxhx (Haxe-in-Haxe) bring-up

`hxhx` is the long-term “Haxe-in-Haxe” compiler. Right now it is still partly staged, but it already provides stage0-free bootstrap paths, linked native Stage3 backends, and acceptance gates.
Linked Stage3 backends (`ocaml-stage3`, `js-native`) are now selected through a canonical builtin backend registry (`packages/hxhx-core/src/backend/BackendRegistry.hx`) with explicit descriptors (`TargetDescriptor`) and compatibility requirements (`TargetRequirements`).
Stage3 backend input is now named as a codegen contract (`GenIrProgram` v0 alias), and builtin backends now split emission into reusable target-core pilots (`packages/hxhx-core/src/backend/ocaml/OcamlTargetCore.hx`, `packages/hxhx-core/src/backend/js/JsTargetCore.hx`) to support plugin→builtin promotion without codegen rewrites.
The registry also has a provider seam (`registerProvider(regs)`) so plugin wrappers can participate in the same deterministic precedence model as builtins.
Stage3 loads provider declarations per request from `HXHX_BACKEND_PROVIDERS` / `-D hxhx_backend_provider=...` before backend resolution, and falls back to builtin registrations when none are declared.
`GenIrProgram` cast policy is now explicit: target-core emitters stay fully typed; boundary recovery uses shared helper `packages/hxhx-core/src/backend/GenIrBoundary.hx`, with additional casts only at narrow Stage3 reflection/bridge seams. See `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`.

### Current execution reality

- `--target ocaml-stage3` and `--target js-native` run linked Stage3 backends directly.
- standard JS output flags (`-js` / `--js`) auto-route through the linked `js-native` Stage3 backend when no conflicting non-JS target is present.
- bootstrap builds (`scripts/hxhx/build-hxhx.sh`, `scripts/hxhx/build-hxhx-macro-host.sh`) are stage0-free by default when committed snapshots are present.
- legacy delegated paths still exist for compatibility, and can be blocked with `HXHX_FORBID_STAGE0=1`.
- CI now includes explicit stage0-free smoke validation before the full test lane.

### Naming: `hxhx-core` vs `hxhx`

- `packages/hxhx-core` is the internal compiler core (parser/typer/lowering/backend contracts).
- `packages/hxhx` is the CLI/product entrypoint (the user-facing `hxhx` story).
- `packages/hxhx-macro-host` is the Stage4 macro host process package.

In practice: `hxhx` depends on `hxhx-core` and macro-host packages while keeping the external `hxhx` name stable.

Terminology note: in this repo, “compile Haxe” might mean compiling this backend, building the upstream compiler binary, or compiling Haxe projects. See `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1` for precise definitions and the Stage0→Stage2 bootstrapping model.

Build the `hxhx` example (requires `dune` + `ocamlc`):

```bash
bash scripts/hxhx/build-hxhx.sh
```

By default this builds the bootstrap snapshot as **bytecode** (`out.bc`) for portability (some platforms/architectures can fail to native-compile the large generated OCaml units).
To prefer a native build first, set `HXHX_BOOTSTRAP_PREFER_NATIVE=1` (it will fall back to bytecode if native fails).
Bootstrap build observability knobs:
- `HXHX_BOOTSTRAP_HEARTBEAT` (default `20`) prints periodic dune-build heartbeats; set `0` to disable.
- `HXHX_BOOTSTRAP_BUILD_TIMEOUT_SECS` (default `0`) sets an optional hard timeout for bootstrap dune builds.
The stage0-free bootstrap build runs in `packages/hxhx/bootstrap_work/` (a local workspace)
so committed snapshot files remain sharded and small in `bootstrap_out/`.


### Bootstrap stages (from-scratch model)

This repo intentionally treats `hxhx` as a staged bootstrap so it can serve as a didactic compiler-building reference:

1. **Stage0 (external compiler baseline)**  
   Use an existing `haxe` binary to compile our Haxe sources into OCaml output.
2. **Stage1 (first `hxhx` binary)**  
   Build that OCaml output with `dune` into a runnable `hxhx` executable.
3. **Stage2 (self-check)**  
   Use stage1 `hxhx` to build the next `hxhx` and compare behavior/codegen stability.
4. **Gate runners (upstream behavior oracle)**  
   Validate compatibility against upstream suites (Gate1/Gate2/display) using `vendor/haxe` as the oracle.

### HXHX 1.0 progress tracker (live)

If you are not deep into compiler internals, this is the section to watch.

Plain-English goal for `hxhx 1.0`:

- `hxhx` can act like a real Haxe compiler for Haxe `4.3.7` workloads
- macro-heavy workflows work without delegating back to stage0 `haxe`
- we keep clean MIT provenance rules while doing it

For a full non-expert walkthrough, read:
`docs/01-getting-started/HXHX_1_0_ROADMAP.md`

```mermaid
flowchart LR
  A["Can build hxhx reliably"] --> B["Can run core upstream tests"]
  B --> C["Display / IDE workflows work"]
  C --> D["Native RunCi flow works end-to-end"]
  D --> E["Replacement-ready + MIT guardrails"]
```

Current checklist (human-readable):

- [x] Build/bootstrap pipeline is stable enough for day-to-day work (`haxe.ocaml-xgv.10.4`)
- [x] Core upstream macro unit workload can run in non-delegating mode (`haxe.ocaml-xgv.10.1`)
- [x] Display workflows (used by IDE/tooling paths) are reproducible in non-delegating mode (`haxe.ocaml-xgv.10.3`, `haxe.ocaml-xgv.10.8`)
- [x] Native `RunCi` direct flow now runs end-to-end with stable stage markers (`haxe.ocaml-xgv.10.11`, `haxe.ocaml-xgv.10.22`)
- [x] Target-agnostic core design notes are now published (`haxe.ocaml-xgv.10.5`) — see `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
- [x] Monorepo layout cleanup is complete (`haxe.ocaml-xgv.10.6`)
- [x] Heavy-workload runtime tuning baseline landed (`haxe.ocaml-xgv.10.17`)
- [x] Gate1/Gate2/Gate3 cadence hardening now includes direct-by-default Macro mode, Python no-install mode, Java baseline documentation, weekly Linux scheduled baselines, and builtin fast-path smoke coverage (`haxe.ocaml-xgv.10.28`, `haxe.ocaml-xgv.10.29`, `haxe.ocaml-xgv.10.31`, `haxe.ocaml-xgv.10.32`, `haxe.ocaml-xgv.10.33`, `haxe.ocaml-xgv.10.34`, `haxe.ocaml-xgv.10.35`, `haxe.ocaml-xgv.10.36`, `haxe.ocaml-xgv.10.37`, `haxe.ocaml-xgv.10.38`)
- [x] M7 now has an explicit bundle runner (`fast`/`full`) so replacement-readiness is measurable with one command (`haxe.ocaml-xgv.10.40`)
- [ ] Final “replacement-ready” epic acceptance still pending (`haxe.ocaml-xgv.10`)

Quick status commands:

```bash
bd show haxe.ocaml-xgv.10
bd show haxe.ocaml-xgv.2
bd show haxe.ocaml-xgv.3
bd ready
```

Practical command map:

- Build stage1 from committed bootstrap snapshot:  
  `bash scripts/hxhx/build-hxhx.sh`
- Regenerate bootstrap snapshot from source (stage0 + verify):  
  `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh`
- Run stage2 reproducibility sanity rung:  
  `npm run test:upstream:stage2`
- Run non-delegating display end-to-end smoke:  
  `npm run test:upstream:display-stage3-emit-run-smoke`
- Run replacement-ready bundle (fast):  
  `npm run test:upstream:replacement-ready`
- Run replacement-ready bundle (full):  
  `npm run test:upstream:replacement-ready:full`
  - Host-aware default Gate3 target set inside this bundle: Linux=`Macro,Js,Neko`, macOS=`Macro,Neko` (override with `HXHX_GATE3_TARGETS=...`).

For deeper acceptance/terminology (replacement-ready, gate definitions), see
`docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md`.

Regenerate the committed `hxhx` bootstrap snapshot (maintainer workflow):

```bash
bash scripts/hxhx/regenerate-hxhx-bootstrap.sh
```

This script is now progress-visible by default:
- emits a Stage0 heartbeat every `20s` (`HXHX_STAGE0_HEARTBEAT`, set `0` to disable)
- fails fast if Stage0 emit stalls (`HXHX_STAGE0_FAILFAST_SECS`, default `900`)
- prints per-phase timings (emit/copy/verify) and copied file count
- cleans temporary stage0 logs by default (set `HXHX_KEEP_LOGS=1` to keep them)
- shards oversized bootstrap OCaml units into deterministic `<Module>.ml.partNNN` chunks + `<Module>.ml.parts` manifest files so no tracked bootstrap file exceeds GitHub's 50MB warning threshold

### Artifact cleanup (recommended)

Compiler/bootstrap workflows can produce large temporary outputs. Use these commands to reclaim space:

```bash
npm run clean:dry-run
npm run clean
npm run clean:tmp
npm run clean:deep
npm run clean:verbose
npm run clean:tmp:verbose
```

- `clean`: repo-local transient outputs (`out*`, fixture/example outputs, etc.)
- `clean:tmp`: stale stage0 temp logs in OS temp directories
- `clean:deep`: includes large bootstrap `_build` caches
- `clean:verbose` / `clean:tmp:verbose`: largest-first candidate listing + per-delete progress + actual reclaimed size report
- safe clean preserves tracked placeholders (for example fixture `out/.gitignore`) while removing untracked/ignored contents in those directories

Policy details: `docs/01-getting-started/CLEANUP_AND_CACHE_POLICY.md`

### Acceptance workload profiles

For compiler-shaped acceptance workloads:

```bash
# developer-friendly default (fast profile)
npm run test:acceptance

# include heavy workloads as well
npm run test:acceptance:full

# workload-only full profile with explicit heavy filter
WORKLOAD_PROFILE=full WORKLOAD_FILTER=hih-compiler npm run test:workloads
```

Runtime controls for `scripts/test-workloads.sh`:

- `WORKLOAD_PROGRESS_INTERVAL_SEC` (default `20`)
- `WORKLOAD_HEAVY_TIMEOUT_SEC` (default `600`)
- `WORKLOAD_TIMEOUT_SEC` (global override; `0` disables timeout)
- `WORKLOAD_FILTER=<substring>`

Each workload run now prints per-workload timing and a final summary line, which serves as the local baseline when tuning acceptance runtime.

Run upstream Gate 1 (requires a local Haxe checkout; defaults to the author’s path):

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:unit-macro
```

Gate 1 Lite CI (`.github/workflows/gate1-lite.yml`) runs on every push/PR and executes the upstream macro smoke rung (`test:upstream:unit-macro-stage3-no-emit`).
Full Gate 1 CI (`.github/workflows/gate1.yml`) runs weekly on Linux and remains manually triggerable via `workflow_dispatch` + `run_upstream_unit_macro=true`.
Gate 1 unit-macro rungs fail fast by default with no Darwin-specific retry fallback, and all Stage3 rungs (`no-emit`, `type-only`, `emit`) run with resolver widening enabled (`HXHX_RESOLVE_IMPLICIT_PACKAGE_TYPES=1`).
The Stage3 `emit` rung also enforces a warning-clean baseline for OCaml warning classes `20` (`ignored-extra-argument`), `21` (`nonreturning-statement`), and `26` (`unused-var`); any of these warnings fails the gate.

Run upstream Gate 2 (runci Macro target; heavier and more tool-dependent):

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:runci-macro
```

Gate 2 requires additional tooling beyond Gate 1 (at least `git`, `haxelib`, `neko`/`nekotools`, `python3`, `javac`, and a C compiler like `cc`/`clang`), and it can download external deps (e.g. `tink_core`) during the run.
You can override the upstream checkout via `HAXE_UPSTREAM_DIR=/path/to/haxe`.
For `HXHX_GATE2_MODE=stage3_emit_runner`, the runner now defaults to bootstrap snapshots for speed; set `HXHX_FORCE_STAGE0=1` only when you intentionally want a source-built `hxhx` repro pass.
For long native bring-up runs, you can tune guardrails:
- `HXHX_GATE2_RUNCI_TIMEOUT_SEC` (default `600`, set `0` to disable timeout)
- `HXHX_GATE2_RUNCI_HEARTBEAT_SEC` (default `20`, set `0` to disable progress heartbeats)
- `HXHX_GATE2_SKIP_DARWIN_SEGFAULT` (default `1`) turns a macOS `tests/misc/resolution` SIGSEGV (exit 139) into an explicit skipped-stage marker in direct mode; set `0` to force fail-fast while debugging.
- Direct/runner Gate2 logs now print both `subinvocations=<n>` and `last_subinvocation=<cmd>` to speed up failure triage.

Run upstream Gate 3 (selected `tests/runci` targets; heavier target matrix):

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
HXHX_GATE3_TARGETS="Macro,Js,Neko" npm run test:upstream:runci-targets
```

Run the linked builtin fast-path smoke (delegated vs builtin target path):

```bash
npm run test:hxhx:builtin-target-smoke
```

Run the dedicated JS-native emit+run lane only:

```bash
HXHX_BUILTIN_SMOKE_OCAML=0 HXHX_BUILTIN_SMOKE_JS_NATIVE=1 npm run test:hxhx:builtin-target-smoke
```

By default, Gate 3 runs `Macro` via the non-delegating Gate 2 direct pipeline while keeping non-Macro targets on the stage0-shim path.

To force the historical stage0-shim harness for `Macro`, set:

```bash
HXHX_GATE3_TARGETS="Macro,Js,Neko" HXHX_GATE3_MACRO_MODE=stage0_shim npm run test:upstream:runci-targets
```

Gate 3 CI (`.github/workflows/gate3.yml`) runs weekly on Linux with deterministic defaults (`targets=Macro,Js,Neko`, `macro_mode=direct`, `allow_skip=0`) and also supports manual `workflow_dispatch` overrides for `targets`, `allow_skip`, and `macro_mode`.
Builtin fast-path smoke CI (`.github/workflows/gate3-builtin.yml`) also runs weekly on Linux and supports manual `workflow_dispatch` (`reps`, `run_js_native`).
PR/push CI now includes Gate 1 Lite (`.github/workflows/gate1-lite.yml`) plus the dedicated `JS-native smoke` job in `.github/workflows/ci.yml` for non-delegating `--target js-native` emit+run coverage.
Gate 2 upstream Macro (`.github/workflows/gate2.yml`) now runs weekly on schedule (Linux baseline) and remains manually triggerable via `run_upstream_macro`.
M7 bundle workflow (`.github/workflows/gate-m7.yml`) is manually triggerable and runs the one-command replacement bundle (`fast` or `full`) with strict-skip control.

Gate 3 also applies a deterministic flake policy by default for `Js`: retry once (`HXHX_GATE3_RETRY_COUNT=1`) with a 3s delay.
Tune with `HXHX_GATE3_RETRY_COUNT`, `HXHX_GATE3_RETRY_TARGETS`, and `HXHX_GATE3_RETRY_DELAY_SEC` (set count to `0` to disable).
For long runs, Gate3 also exposes per-target observability controls:
- `HXHX_GATE3_TARGET_HEARTBEAT_SEC` (default `20`; set `0` to disable heartbeat lines)
- `HXHX_GATE3_TARGET_TIMEOUT_SEC` (default `0`; disabled, set to fail hung targets explicitly)
The weekly CI baseline sets `HXHX_GATE3_TARGET_TIMEOUT_SEC=3600` so hard hangs fail with a clear timeout marker.
On macOS, Gate 3 keeps the JS server stage enabled but relaxes async timeouts by default (`HXHX_GATE3_JS_SERVER_TIMEOUT_MS=60000`). Set `HXHX_GATE3_FORCE_JS_SERVER=1` to run without timeout patches (debug mode).
Python target runs default to no-install mode (`HXHX_GATE3_PYTHON_ALLOW_INSTALL=0`): both `python3` and `pypy3` must already be on `PATH`. Set `HXHX_GATE3_PYTHON_ALLOW_INSTALL=1` to allow upstream installer/network fallback.
Java is validated as an opt-in Gate3 target (`HXHX_GATE3_TARGETS=Java`, local baseline about 2 minutes) but stays out of the default target set for now to keep routine runs fast.

Run a focused Gate2 display rung (non-delegating Macro sequence, stop after display stage):

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:runci-macro-stage3-display
```

This runs a focused Gate2 Macro slice in direct Stage3 no-emit mode, skips `unit` for isolation, and exits immediately after `display` with explicit markers:
`macro_stage=display status=ok`, `gate2_display_stage=ok`, `gate2_stage3_no_emit_direct=ok stop_after=display`.

Run the dedicated non-delegating display smoke rung:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:display-stage3-no-emit
```

This validates both:
- direct `--display` request parsing/root inference (`hxhx --hxhx-stage3 --hxhx-no-emit`)
- and `--wait stdio` frame handling (non-delegating compiler-server protocol smoke)

Run the dedicated display full-emit warm-output stress rung:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:display-stage3-emit-stress
```

This repeatedly runs `tests/display/build.hxml` under
`hxhx --hxhx-stage3 --hxhx-emit-full-bodies --hxhx-no-run` while reusing the same
`--hxhx-out` directory to catch warm-output determinism/linking regressions.
Set `HXHX_DISPLAY_EMIT_STRESS_ITERS=<n>` to tune loop count (default: `10`).

Run the dedicated display full-emit + run smoke rung:

```bash
bash scripts/vendor/fetch-haxe-upstream.sh
npm run test:upstream:display-stage3-emit-run-smoke
```

This executes the same upstream display build with run enabled and enforces a non-crash contract:
it requires `run=ok` and fails on any non-zero exit. It also fails hard on segfault-shaped regressions.
On success it prints `display_utest_suite=ok` (validated from `-lib utest` plus a minimum
`resolved_modules` threshold; override with `HXHX_DISPLAY_EMIT_RUN_MIN_RESOLVED` if needed).

Quick target-preset smoke checks:

```bash
HXHX_BIN="$(bash scripts/hxhx/build-hxhx.sh | tail -n 1)"
"$HXHX_BIN" --target ocaml -- -cp src -main Main --no-output
"$HXHX_BIN" --target ocaml-stage3 --hxhx-no-emit -cp src -main Main

# Optional hard guard: fail if this invocation would delegate to stage0 `haxe`.
HXHX_FORBID_STAGE0=1 "$HXHX_BIN" --target ocaml-stage3 --hxhx-no-emit -cp src -main Main
```

Local Stage3 protocol regressions are covered by `npm run test:hxhx-targets`, including:
- `--wait stdio` framed requests
- `--wait <host:port>` + `--connect <host:port>` roundtrip request handling
- instance-field roundtrip in full-body mode (`this.x = ...`, `return this.x`, `new Main().ping()`) with compile+run validation
- js-native enum-switch + basic reflection helper smoke (`Type.resolveClass`, `Type.getClassName`, `Type.enumConstructor`, `Type.enumParameters`)
- js-native switch-expression lowering smoke (`switch (...) { case ...: ... }` with OR/bind patterns)
- js-native array-comprehension lowering smoke (`[for (...) ...]` for range + array iterables)
- js-native range-expression lowering smoke (`var items = 1...5` + `for (v in items)` roundtrip)
- js-native loop-control smoke (`while` + `continue` + `break` in the same function)
- js-native do/while smoke (`do { ... } while (...)` including false-once condition)
- js-native statement-level try/catch + throw/rethrow smoke (`caught:boom|rethrow:boom`)
- js-native ordered multi-catch typed dispatch smoke (`string:boom|int:7|dynamic2:true`)
- js-native checks auto-skip when the current `hxhx` binary does not expose `js-native` (the dedicated CI `JS-native smoke` lane still enforces that path)
- optional local fast path: set `HXHX_BIN=packages/hxhx/out/_build/default/out.bc` to skip rebuilding `hxhx` for each script rerun
- script default build mode uses stage0 (`HXHX_FORCE_STAGE0=1`); set `HXHX_FORCE_STAGE0=0` to validate the stage0-free bootstrap lane explicitly
- stage0 build-lane observability defaults: `HXHX_STAGE0_HEARTBEAT=30`, `HXHX_STAGE0_FAILFAST_SECS=7200`; optional memory cap: `HXHX_STAGE0_MAX_RSS_MB=<limit>`; optional lower-memory compile mode: `HXHX_STAGE0_NO_INLINE=1` (override test-lane defaults with `HXHX_TARGETS_STAGE0_HEARTBEAT_DEFAULT` / `HXHX_TARGETS_STAGE0_FAILFAST_DEFAULT`)
- CI split: the main `Tests` lane runs `npm run test:hxhx-targets` with `HXHX_FORCE_STAGE0=0` (stage0-free), while source-built stage0 behavior is validated in the separate `Stage0 Source Smoke` workflow (`.github/workflows/stage0-source-smoke.yml`, nightly/manual; tuned with `HXHX_STAGE0_OCAML_BUILD=byte`, `HXHX_STAGE0_DISABLE_PREPASSES=1`, and `HXHX_STAGE0_NO_INLINE=1`, plus enforced `>=8GB` swapfile capacity on ubuntu runners for memory headroom)
- Stage0 source-smoke telemetry:
  - workflow logs now print `stage0_peak_tree_rss_mb=<n>` and upload `stage0_source_build.log` as an artifact for each run
  - parse one log locally: `bash scripts/ci/extract-stage0-peak-rss.sh <stage0_source_build.log>`
  - aggregate recent GitHub baseline samples (default 5): `bash scripts/ci/stage0-source-rss-baseline.sh --allow-partial`
  - while success samples are sparse, include failed runs for diagnostics: `bash scripts/ci/stage0-source-rss-baseline.sh --include-failures --allow-partial`
- source-level Stage3 receiver-call regression (`other.add(n)` arity shape) is covered by `npm run test:m14:hih-emitter-receiver-call` (no stage0 bootstrap rebuild required)

## Two surfaces (design)

- Portable (default): keep Haxe stdlib semantics and portability; the target provides `packages/reflaxe.ocaml/std/_std` overrides and runtime helpers so users can target OCaml without writing OCaml-specific code.
- OCaml-native (opt-in): import `ocaml.*` for APIs that map more directly to OCaml idioms (e.g. `'a list`, `option`, `result`) while still using Haxe typing and tooling.

## Repo layout (monorepo)

This repo currently contains two products:

- `packages/reflaxe.ocaml/`: the OCaml backend (published as `reflaxe.ocaml`).
- `packages/hxhx/`: the `hxhx` compiler CLI/binary (Haxe-in-Haxe bring-up).

Supporting components:

- `packages/hxhx-core/`: internal staged compiler libraries used by `hxhx`.
- `packages/hxhx-macro-host/`: macro host process used for Stage4 bring-up.
- `examples/`: consumer projects and QA harnesses (compile → dune build → run).
- `workloads/`: compiler-shaped acceptance workloads (`npm run test:acceptance`).
- `vendor/haxe/` (ignored): optional upstream checkout used as a black-box behavior oracle in CI gates.

Rationale: keep backend + compiler iteration fast in one repo while making it obvious what is shippable (`packages/`), what is a consumer example (`examples/`), and what is a compiler-shaped acceptance workload (`workloads/`).

For explicit product boundaries and future split criteria, see `docs/00-project/BOUNDARIES.md`.

## Docs

- [Imperative → OCaml Lowering](docs/02-user-guide/IMPERATIVE_TO_OCAML_LOWERING.md) — how mutation/loops/blocks are lowered in portable vs OCaml-native surfaces.
- [Compatibility Matrix](docs/02-user-guide/COMPATIBILITY_MATRIX.md) — what works today (portable vs `ocaml.*`) and known limitations.
- [OCaml Tooling: Source Maps](docs/02-user-guide/OCAML_TOOLING_SOURCE_MAPS.md) — map OCaml compiler errors back to Haxe positions.
- [HXHX Builtin Backends](docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md) — design + current `--target` presets (`ocaml`, `ocaml-stage3`, `js`, `js-native`) for bundled vs builtin backend execution, strict CLI compatibility mode (`--hxhx-strict-cli`), and explicit legacy Flash/AS3 unsupported policy.
- [OCaml Interop: Labelled Args](docs/02-user-guide/OCAML_INTEROP_LABELLED_ARGS.md) — how to express `~label:` / `?label:` extern callsites from Haxe.
- [OCaml-native Mode](docs/02-user-guide/OCAML_NATIVE_MODE.md) — when/why to use `ocaml.*` and how the surface maps to `Stdlib`.
- [Optional `.mli` Generation](docs/02-user-guide/OCAML_TOOLING_MLI.md) — `.mli` inference via `ocamlc -i` for better OCaml tooling UX.
- [Error Mapping](docs/02-user-guide/OCAML_TOOLING_ERROR_MAPPING.md) — line directives to keep OCaml error locations stable under dune.

## Escape hatch

- `untyped __ocaml__("...")` injects raw OCaml snippets (intended for interop and early bring-up).

## License

MIT (see `LICENSE`).
