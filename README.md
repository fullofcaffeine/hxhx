# reflaxe.ocaml

[![Version](https://img.shields.io/badge/version-0.8.0-blue)]

Haxe → OCaml target built on Reflaxe.

This repo is currently in early scaffolding (see `prd.md` for the roadmap).

## Environment setup

This repo has two “levels” of setup:

- **Emit-only** (generate `.ml` + dune scaffold): Node.js + Haxe (+ Lix).
- **Build/run** (produce a native executable): add OCaml + dune toolchain.

### Prerequisites

- **Node.js + npm** (used for Lix + dev tooling).
- **Haxe** (this repo targets Haxe **4.3.7** right now).
- **OCaml + dune** (required if you want to compile the emitted OCaml to a binary).

macOS (Homebrew):

```bash
brew install ocaml dune ocaml-findlib
```

Linux (example, Debian/Ubuntu):

```bash
sudo apt-get update
sudo apt-get install -y ocaml dune ocaml-findlib
```

## Usage (current scaffold)

This repo is set up for **Lix** (via `lix.client` / haxeshim-style `haxe_libraries`).

First-time setup:

```bash
npm install
npx lix download
```

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

`hxhx` is the long-term “Haxe-in-Haxe” compiler. Right now it is a **stage0 shim** that delegates to a system `haxe`, but it already provides a place to hang acceptance tests and bootstrapping gates.

### Naming: `hih-*` vs `hxhx`

- `hih-*` (“Haxe-in-Haxe”) packages are **internal implementation libraries** used for staged bring-up (parser/typer/emitter slices, small runtimes, test harness glue).
- `hxhx` is the **end-user/compiler product name** (the CLI/binary and the public “Haxe-in-Haxe” story).

In practice: `hxhx` depends on `hih-*` today, and we may rename/reshape the internal packages later without changing the external `hxhx` name.

Terminology note: in this repo, “compile Haxe” might mean compiling this backend, building the upstream compiler binary, or compiling Haxe projects. See `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md:1` for precise definitions and the Stage0→Stage2 bootstrapping model.

Build the `hxhx` example (requires `dune` + `ocamlc`):

```bash
bash scripts/hxhx/build-hxhx.sh
```

By default this builds the bootstrap snapshot as **bytecode** (`out.bc`) for portability (some platforms/architectures can fail to native-compile the large generated OCaml units).
To prefer a native build first, set `HXHX_BOOTSTRAP_PREFER_NATIVE=1` (it will fall back to bytecode if native fails).

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
- [ ] Native `RunCi` flow still needs to move past early bootstrap/harness steps (`haxe.ocaml-xgv.10.11`, in progress)
- [x] Target-agnostic core design notes are now published (`haxe.ocaml-xgv.10.5`) — see `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
- [x] Monorepo layout cleanup is complete (`haxe.ocaml-xgv.10.6`)
- [ ] Heavy workload runtime budget/profile tuning is in progress (`haxe.ocaml-xgv.10.17`)
- [ ] Final “replacement-ready” epic acceptance still pending (`haxe.ocaml-xgv.10`)

Quick status commands:

```bash
bd show haxe.ocaml-xgv.10
bd show haxe.ocaml-xgv.10.11
bd show haxe.ocaml-xgv.10.17
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

Local Stage3 protocol regressions are covered by `npm run test:hxhx-targets`, including:
- `--wait stdio` framed requests
- `--wait <host:port>` + `--connect <host:port>` roundtrip request handling
- instance-field roundtrip in full-body mode (`this.x = ...`, `return this.x`, `new Main().ping()`) with compile+run validation

## Two surfaces (design)

- Portable (default): keep Haxe stdlib semantics and portability; the target provides `packages/reflaxe.ocaml/std/_std` overrides and runtime helpers so users can target OCaml without writing OCaml-specific code.
- OCaml-native (opt-in): import `ocaml.*` for APIs that map more directly to OCaml idioms (e.g. `'a list`, `option`, `result`) while still using Haxe typing and tooling.

## Repo layout (monorepo)

This repo currently contains two products:

- `packages/reflaxe.ocaml/`: the OCaml backend (published as `reflaxe.ocaml`).
- `packages/hxhx/`: the `hxhx` compiler CLI/binary (Haxe-in-Haxe bring-up).

Supporting components:

- `packages/hih-compiler/`: internal staged compiler libraries used by `hxhx`.
- `tools/hxhx-macro-host/`: macro host process used for Stage4 bring-up.
- `examples/`: consumer projects and QA harnesses (compile → dune build → run).
- `workloads/`: compiler-shaped acceptance workloads (`npm run test:acceptance`).
- `vendor/haxe/` (ignored): optional upstream checkout used as a black-box behavior oracle in CI gates.

Rationale: keep backend + compiler iteration fast in one repo while making it obvious what is “shippable” (`packages/`), what is an internal tool (`tools/`), and what is a consumer example (`examples/`) versus a compiler-shaped acceptance workload (`workloads/`).

## Docs

- [Imperative → OCaml Lowering](docs/02-user-guide/IMPERATIVE_TO_OCAML_LOWERING.md) — how mutation/loops/blocks are lowered in portable vs OCaml-native surfaces.
- [Compatibility Matrix](docs/02-user-guide/COMPATIBILITY_MATRIX.md) — what works today (portable vs `ocaml.*`) and known limitations.
- [OCaml Tooling: Source Maps](docs/02-user-guide/OCAML_TOOLING_SOURCE_MAPS.md) — map OCaml compiler errors back to Haxe positions.
- [HXHX Builtin Backends](docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md) — design for bundling/linking targets and the proposed `--target` registry.
- [OCaml Interop: Labelled Args](docs/02-user-guide/OCAML_INTEROP_LABELLED_ARGS.md) — how to express `~label:` / `?label:` extern callsites from Haxe.
- [OCaml-native Mode](docs/02-user-guide/OCAML_NATIVE_MODE.md) — when/why to use `ocaml.*` and how the surface maps to `Stdlib`.
- [Optional `.mli` Generation](docs/02-user-guide/OCAML_TOOLING_MLI.md) — `.mli` inference via `ocamlc -i` for better OCaml tooling UX.
- [Error Mapping](docs/02-user-guide/OCAML_TOOLING_ERROR_MAPPING.md) — line directives to keep OCaml error locations stable under dune.

## Escape hatch

- `untyped __ocaml__("...")` injects raw OCaml snippets (intended for interop and early bring-up).

## License

MIT (see `LICENSE`).
