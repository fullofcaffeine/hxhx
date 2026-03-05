# hxhx (Haxe-in-Haxe compiler driver, Stage 0 shim)

This example produces the `hxhx` binary.

Today it is intentionally a **Stage 0 shim**:

- It is compiled to native OCaml via `reflaxe.ocaml`.
- It delegates actual compilation to an existing `haxe` binary (Stage 0), so we can:
  - validate the end-to-end harness (build → run → invoke upstream suites),
  - stabilize the intended CLI surface,
  - and then replace internals incrementally with real Haxe-in-Haxe compiler subsystems.

Long-term, `hxhx` becomes the real Haxe-in-Haxe compiler, and the delegation path is removed.

Stage0 usage policy (runtime/build/maintenance boundaries):

- `docs/00-project/STAGE0_POLICY.md`

## Build

From repo root (requires `dune` + `ocamlc`):

```bash
bash scripts/hxhx/build-hxhx.sh
```

This prints the built `hxhx` binary path (by default **bytecode** via `out.bc` for portability).

To build from stage0 source (instead of the committed `bootstrap_out` snapshot), set:

```bash
HXHX_FORCE_STAGE0=1 bash scripts/hxhx/build-hxhx.sh
```

To prefer native (may fail on some platforms/architectures for very large generated units), set:

```bash
HXHX_BOOTSTRAP_PREFER_NATIVE=1 HXHX_STAGE0_PREFER_NATIVE=1 bash scripts/hxhx/build-hxhx.sh
```

## Bootstrap snapshot (maintainers)

By default, `scripts/hxhx/build-hxhx.sh` builds from the committed OCaml snapshot under
`packages/hxhx/bootstrap_out/` so CI can build `hxhx` without requiring a stage0 `haxe`
binary on PATH.
During this path, the script copies `bootstrap_out` into `packages/hxhx/bootstrap_work/`,
rehydrates any sharded modules there, and runs `dune` in that workspace.


To regenerate the snapshot (requires stage0 `haxe`):

```bash
HAXE_BIN="$HOME/haxe/versions/4.3.7/haxe" bash scripts/hxhx/regenerate-hxhx-bootstrap.sh
```

Notes:

- This can take several minutes because it runs stage0 Haxe macros for codegen.
- For faster repeated loops, use a repo-owned Haxe server + incremental emit:
  - `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --use-repo-server --keep-repo-server --incremental --no-verify`
  - Optional skip when inputs are unchanged:
    - `bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --skip-if-unchanged --incremental --no-verify`
  - Repo-owned server helper:
    - `bash scripts/hxhx/haxe-server.sh start|status|stop`
- For progress logs from `reflaxe.ocaml`, set `HXHX_STAGE0_PROGRESS=1` (emits periodic `Context.warning(...)` markers during the stage0 build).
- For more detailed progress (per-class begin markers in the log file), set `HXHX_STAGE0_TELEMETRY=1` (adds `-D reflaxe_ocaml_telemetry`).
- For profiling, set `HXHX_BOOTSTRAP_DEBUG=1` to print `--times` output.
- For very verbose stage0 compiler logs (including typing/module loading), set `HXHX_STAGE0_VERBOSE=1` (passes `-v` to stage0 `haxe`).
- If your terminal/CI truncates logs, you can also capture progress markers to a file by setting `REFLAXE_OCAML_PROGRESS_FILE=/path/to/log.txt`.
- If you suspect stage0 performance issues are caused by output-shaping prepasses, you can try `HXHX_STAGE0_DISABLE_PREPASSES=1` (disables reflaxe.ocaml expression preprocessors for this stage0 run).
- Stage0 source builds support two `--connect` paths:
  - explicit override: `HAXE_CONNECT=<port>` (highest precedence)
  - helper-backed reuse: `HXHX_STAGE0_USE_REPO_SERVER=1` (starts/reuses `scripts/hxhx/haxe-server.sh` and injects `--connect <port>`)
  - optional helper cleanup policy: `HXHX_STAGE0_KEEP_REPO_SERVER=1` keeps a helper-started server alive after build (default is auto-stop if started by this build).
- For targeted cleanup when haxe servers pile up:
  - `--kill-repo-server` (safe: only repo-owned server)
  - `--kill-all-haxe-servers` (unsafe: kills all local haxe servers)
- Oversized generated bootstrap units are automatically sharded into deterministic `<Module>.ml.partNNN` chunks + `<Module>.ml.parts` manifest files to stay below GitHub's 50MB warning threshold.

If you need to rebuild `hxhx` from stage0 source (instead of the committed `bootstrap_out`), use:

```bash
HAXE_BIN="$HOME/haxe/versions/4.3.7/haxe" HXHX_FORCE_STAGE0=1 HXHX_STAGE0_PROGRESS=1 HXHX_STAGE0_TIMES=1 HXHX_STAGE0_VERBOSE=1 bash scripts/hxhx/build-hxhx.sh

# same, but with helper-managed --connect reuse
HAXE_BIN="$HOME/haxe/versions/4.3.7/haxe" HXHX_FORCE_STAGE0=1 HXHX_STAGE0_USE_REPO_SERVER=1 HXHX_STAGE0_KEEP_REPO_SERVER=1 bash scripts/hxhx/build-hxhx.sh
```

## Run

No args (example harness mode):

```bash
"$(bash scripts/hxhx/build-hxhx.sh)"
```

Delegate to Stage 0 `haxe`:

```bash
HAXE_BIN=haxe "$(bash scripts/hxhx/build-hxhx.sh)" -- compile.hxml
```


## Lanes and targets

List available lanes/backends:

```bash
"$(bash scripts/hxhx/build-hxhx.sh)" --hxhx-list-targets
```

Direct-flag contract:

- `--ocaml`: linked Stage3 OCaml backend fast-path (`Stage3Compiler`) with no `--library reflaxe.ocaml` requirement.
  - OCaml profile contract:
    - `-D ocaml_profile=portable` (default)
    - `-D ocaml_profile=metal` (runtime-layered mode; links only required runtime modules and runs a fail-fast metal verifier before emit)
    - migration/error code map: `docs/02-user-guide/OCAML_PROFILE_CONTRACT.md` (see “Metal verifier code map”)
    - runtime module matrix: `docs/02-user-guide/OCAML_RUNTIME_CAPABILITY_MATRIX.md`
    - any other value fails fast
- `--ocaml-eval`: stage0 delegated OCaml macro lane with reflaxe.ocaml injection.
- `--compat`: pure stage0 passthrough lane (no hxhx injection).
- Native JS lane: canonical Haxe `--js <file>` routed through linked `js-native` backend.
  - scoped support matrix (in-scope + out-of-scope semantics): `docs/02-user-guide/HXHX_JS_NATIVE_SCOPE_1_0.md`
- Removed flags: `--target` / `--hxhx-target`.

Delegation guard:

- Set `HXHX_FORBID_STAGE0=1` to fail any invocation path that would delegate to stage0 `haxe`.
- Native lanes (`--ocaml` and `--js <file>`) remain allowed under this guard.

Examples:

```bash
# Stage0 delegated OCaml macro lane
"$(bash scripts/hxhx/build-hxhx.sh)" --ocaml-eval -main Main -cp src

# Linked Stage3 OCaml fast-path (no emit build)
"$(bash scripts/hxhx/build-hxhx.sh)" --ocaml --hxhx-no-emit -cp src -main Main

# Linked Stage3 OCaml fast-path with explicit metal profile
"$(bash scripts/hxhx/build-hxhx.sh)" --ocaml --hxhx-no-emit -cp src -main Main -D ocaml_profile=metal

# Pure upstream passthrough lane
"$(bash scripts/hxhx/build-hxhx.sh)" --compat -- -cp src -main Main --js out/main.js

# Linked Stage3 JS lane (no-emit diagnostics)
"$(bash scripts/hxhx/build-hxhx.sh)" --js out/main.js --hxhx-no-emit -cp src -main Main

# Linked Stage3 JS lane (emit + run)
"$(bash scripts/hxhx/build-hxhx.sh)" --js out/main.js -cp src -main Main
```

## Strict CLI compatibility mode

Use `--hxhx-strict-cli` to enforce an upstream-style Haxe CLI surface:

- rejects hxhx-only flags like `--target` and `--hxhx-stage3`
- allows upstream-style flags like `--js`, `-cp`, `-main`, `-D`, `--no-output`
- only validates arguments **before** `--` (anything after `--` is forwarded verbatim)

Example:

```bash
"$(bash scripts/hxhx/build-hxhx.sh)" --hxhx-strict-cli --js out/main.js -cp src -main Main --no-output
```

## Benchmarking target modes

Use the hxhx benchmark harness to compare delegation vs linked fast-path overhead:

```bash
npm run hxhx:bench
```

This now reports:

- stage0 `haxe` baseline
- stage1 shim delegation baseline
- native `--ocaml` fast-path baseline
- native `--js <file>` emit baseline (`--hxhx-no-run` to isolate emitter/startup cost)

If the selected `hxhx` binary does not expose native `--js <file>`, the harness reports that row as skipped.
Set `HXHX_BENCH_FORCE_REBUILD_FOR_JS_NATIVE=1` to force a source rebuild and include the native JS row.

Benchmark bootstrap regeneration scenarios (cold/warm/skip):

```bash
npm run hxhx:bench:bootstrap-regen
```
