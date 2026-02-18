# hxhx (Haxe-in-Haxe compiler driver, Stage 0 shim)

This example produces the `hxhx` binary.

Today it is intentionally a **Stage 0 shim**:

- It is compiled to native OCaml via `reflaxe.ocaml`.
- It delegates actual compilation to an existing `haxe` binary (Stage 0), so we can:
  - validate the end-to-end harness (build → run → invoke upstream suites),
  - stabilize the intended CLI surface,
  - and then replace internals incrementally with real Haxe-in-Haxe compiler subsystems.

Long-term, `hxhx` becomes the real Haxe-in-Haxe compiler, and the delegation path is removed.

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
- For progress logs from `reflaxe.ocaml`, set `HXHX_STAGE0_PROGRESS=1` (emits periodic `Context.warning(...)` markers during the stage0 build).
- For more detailed progress (per-class begin markers in the log file), set `HXHX_STAGE0_PROFILE=1` (adds `-D reflaxe_ocaml_profile`).
- For profiling, set `HXHX_BOOTSTRAP_DEBUG=1` to print `--times` output.
- For very verbose stage0 compiler logs (including typing/module loading), set `HXHX_STAGE0_VERBOSE=1` (passes `-v` to stage0 `haxe`).
- If your terminal/CI truncates logs, you can also capture progress markers to a file by setting `REFLAXE_OCAML_PROGRESS_FILE=/path/to/log.txt`.
- If you suspect stage0 performance issues are caused by output-shaping prepasses, you can try `HXHX_STAGE0_DISABLE_PREPASSES=1` (disables reflaxe.ocaml expression preprocessors for this stage0 run).
- If you run a compilation server, you can pass `HAXE_CONNECT=<port>` to reuse it.
- Oversized generated bootstrap units are automatically sharded into deterministic `<Module>.ml.partNNN` chunks + `<Module>.ml.parts` manifest files to stay below GitHub's 50MB warning threshold.

If you need to rebuild `hxhx` from stage0 source (instead of the committed `bootstrap_out`), use:

```bash
HAXE_BIN="$HOME/haxe/versions/4.3.7/haxe" HXHX_FORCE_STAGE0=1 HXHX_STAGE0_PROGRESS=1 HXHX_STAGE0_TIMES=1 HXHX_STAGE0_VERBOSE=1 bash scripts/hxhx/build-hxhx.sh
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


## Target presets

List available presets:

```bash
"$(bash scripts/hxhx/build-hxhx.sh)" --hxhx-list-targets
```

Current presets:

- `--target ocaml`: stage0 delegation path with bundled/`-lib` injection for `reflaxe.ocaml`.
- `--target ocaml-stage3`: linked Stage3 backend fast-path (`Stage3Compiler`) with no `--library reflaxe.ocaml` requirement.
- `--target js`: stage0 delegation preset for JavaScript (`--js` is injected when missing).
- `--target js-native`: linked Stage3 JS backend MVP (non-delegating emit for a constrained subset; runs via `node` when available).
  - currently covered: enum-tag switch lowering + basic `Type` reflection helpers (`resolveClass`, `getClassName`, `enumConstructor`, `enumIndex`, `enumParameters`)
  - currently explicit unsupported: try/catch + throw/rethrow lowering (fails fast with a clear unsupported marker)
- Legacy Flash/AS3 targets are intentionally unsupported in `hxhx` (`--target flash|swf|as3`, `--swf`, and `--as3` all fail fast with a clear message).

Delegation guard:

- Set `HXHX_FORBID_STAGE0=1` to fail any invocation path that would delegate to stage0 `haxe`.
- Linked Stage3 builtins (`ocaml-stage3`, `js-native`) remain allowed under this guard.

Examples:

```bash
# Stage0 delegation path
"$(bash scripts/hxhx/build-hxhx.sh)" --target ocaml -- compile.hxml

# Linked Stage3 fast-path (no emit build)
"$(bash scripts/hxhx/build-hxhx.sh)" --target ocaml-stage3 --hxhx-no-emit -cp src -main Main

# Stage0 JS preset
"$(bash scripts/hxhx/build-hxhx.sh)" --target js -- -cp src -main Main

# Linked Stage3 JS preset (no-emit diagnostics)
"$(bash scripts/hxhx/build-hxhx.sh)" --target js-native --hxhx-no-emit -cp src -main Main

# Linked Stage3 JS preset (MVP emit + run)
"$(bash scripts/hxhx/build-hxhx.sh)" --target js-native --js out/main.js -cp src -main Main
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
- builtin `--target ocaml-stage3` fast-path baseline
- builtin `--target js-native` emit baseline (`--hxhx-no-run` to isolate emitter/startup cost)

If the selected `hxhx` binary does not expose `js-native`, the harness reports that row as skipped.
Set `HXHX_BENCH_FORCE_REBUILD_FOR_JS_NATIVE=1` to force a source rebuild and include the js-native row.
