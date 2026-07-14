# hxhx — Build, Distribution, and Benchmarks (Gate 4)

`hxhx` is the long-term **Haxe-in-Haxe compiler**.

Today it ships **two execution lanes**:

- **compat/delegated lane** (`--ocaml-eval` and `--compat ...`): forwards compile work to stage0 `haxe`
- **native lane** (`--ocaml` / `--js <file>`): runs linked native backends in `hxhx`

Gate 4 exists so we can build and ship the `hxhx` binary with a predictable layout, and track performance baselines across both lanes.

Canonical lane truth table (delegation + stage0 requirements):

- `docs/02-user-guide/concepts/what_delegates_today.md`

## Quick glossary (beginner-friendly)

- **stage0 `haxe`**: your already-installed upstream Haxe compiler binary.
- **`hxhx --ocaml-eval`**: compatibility-friendly delegated OCaml lane with reflaxe.ocaml injection.
- **`hxhx --ocaml`**: linked Stage3 backend path. This is the native/non-delegating direction of travel.

## Version reporting (current behavior)

For compatibility with upstream tooling/tests:

- `hxhx --version` prints a SemVer-style compatibility version (e.g. `4.3.7`) without requiring stage0 delegation
- `hxhx --help` prints hxhx-supported-surface help (`--hxhx-help` remains an alias)

The “hxhx build artifact version” is the repo release tag / version used when packaging (see below).

## Build prerequisites

To build `hxhx` as a native OCaml binary:

- `dune`, `ocamlc` (and typically `ocamlopt` for native builds)
- a stage0 `haxe` (this repo targets `4.3.7`)
- Node.js + `npm` (for Lix toolchain management)

## Build stage1 locally

```bash
npm ci
npx lix download

bash scripts/hxhx/build-hxhx.sh
```

## Macro host discovery

Stage 4 macro bring-up uses a separate macro host process.

By default, `hxhx` looks for a sibling executable next to itself:

- `hxhx-macro-host`

Override with:

- `HXHX_MACRO_HOST_EXE=/path/to/hxhx-macro-host`

## Distribution artifact layout

`scripts/hxhx/build-dist.sh` produces a versioned artifact under:

- `dist/hxhx/<version>/<platform>-<arch>/`
  - `bin/hxhx` (the executable)
  - `bin/hxhx-macro-host` (Stage 4 macro host)
  - `README.md`, `LICENSE`, `CHANGELOG.md`
  - `BUILD_INFO.txt` (toolchain + timestamp)

And writes:

- `dist/hxhx/hxhx-<version>-<platform>-<arch>.tar.gz`
- `dist/hxhx/hxhx-<version>-<platform>-<arch>.tar.gz.sha256`

Build it:

```bash
HXHX_VERSION=0.8.0 \
  SOURCE_DATE_EPOCH=0 \
  bash scripts/hxhx/build-dist.sh
```

If `HXHX_VERSION` is not provided, the script uses `git describe --tags --always`.
If `SOURCE_DATE_EPOCH` is provided, the artifact metadata becomes more reproducible (and GNU tar packaging becomes more deterministic).

### Stage0 policy in dist builds

By default, dist packaging enforces stage0-free build behavior:

- `HXHX_DIST_FORBID_STAGE0=1` (default)
- internally builds `hxhx` and `hxhx-macro-host` with `HXHX_FORBID_STAGE0=1`
- any stage0 fallback attempt fails fast

Maintainer opt-out exists for debugging only:

```bash
HXHX_DIST_FORBID_STAGE0=0 bash scripts/hxhx/build-dist.sh
```

### CI / release usage (recommended)

For CI releases, prefer setting both:

- `HXHX_VERSION` to the release version (e.g. `1.2.3`)
- `SOURCE_DATE_EPOCH` to a stable timestamp (e.g. the tag commit time)

On Linux (GNU tar), this yields a more deterministic `.tar.gz` layout.
On macOS (bsdtar), the packaging is best-effort and may not be bit-reproducible (but the content/layout is the same).

## Benchmarks (baseline)

Because `hxhx` is currently a shim, the only meaningful performance metric is **shim overhead** on top of stage0.

Run the minimal benchmark harness:

```bash
HXHX_BENCH_REPS=10 bash scripts/hxhx/bench.sh
```

This reports:

- `haxe --version` vs `hxhx --version`
- `haxe --no-output` compile vs `hxhx --no-output` compile
- linked Stage3 OCaml fast-path: `--ocaml --hxhx-no-emit`
- linked Stage3 JS emit throughput row: `--js out.js --hxhx-no-run ...`

If the selected `hxhx` binary does not expose native `--js <file>` lane support, the harness reports that row as `skipped`.
Set `HXHX_BENCH_FORCE_REBUILD_FOR_JS_NATIVE=1` to force a source rebuild (`HXHX_FORCE_STAGE0=1`) and measure that native JS row.

As `hxhx` becomes a real compiler (stops delegating), this benchmark suite should be expanded and the acceptance gates should include real-world workloads (upstream `tests/runci`, macro-heavy projects, and curated external repos).

Baseline numbers live in: `docs/benchmarks/HXHX_BASELINE.md:1`.

Run the profile/plugin KPI harness (portable vs metal, builtin vs provider, plus macro overhead lane):

```bash
HXHX_KPI_REPS=3 npm run hxhx:bench:kpi
```

KPI baseline numbers live in: `docs/benchmarks/HXHX_KPI_BASELINE.md:1`.
KPI threshold policy lives in: `docs/benchmarks/HXHX_KPI_THRESHOLDS.md:1`.

## Generated-application native Reflaxe speed comparison

Use this when you want a direct, plain-English comparison of:

1. eval/interp baseline (`haxe --interp`)
2. `hxhx --ocaml-eval`
3. `hxhx --ocaml`

Command:

```bash
npm run hxhx:bench:native-reflaxe
```

Important defaults:

- workload: `packages/reflaxe.ocaml/examples/hxhx-native-reflaxe-bench`
- speed gate baseline: `interp`
- minimum speedup: `30%` (`HXHX_NATIVE_BENCH_MIN_SPEEDUP_PCT`)

Useful overrides:

```bash
# More reps
HXHX_NATIVE_BENCH_REPS=15 npm run hxhx:bench:native-reflaxe

# Compare against both baselines (interp + delegated)
HXHX_NATIVE_BENCH_BASELINE=both npm run hxhx:bench:native-reflaxe

# Increase workload size
HXHX_BENCH_ITERS=400000 npm run hxhx:bench:native-reflaxe
```

This older benchmark measures a normal generated Haxe application. It does not
measure how long a Reflaxe target author waits to build and load a plugin.

## Native plugin author-loop report

To measure the real plugin loop, use:

```bash
npm run hxhx:bench:native-plugin-loop
```

The runner first prepares a native `hxhx` executable outside the samples. It
then alternates two real, same-machine routes: upstream Haxe builds the OCaml
plugin, and stage0-forbidden `hxhx` builds it. Every sample must also load the
plugin, compile a small program through the registered backend, and run the
result successfully. The resulting `hxhx.native-plugin-loop.v1` JSON includes
the commit, machine/toolchains, artifact digests, raw timing samples, and exact
proof summaries.

The comparison is diagnostic and report-only. It does not claim that native
`hxhx` is already faster, and it does not change Full1 release thresholds.

Useful controls:

```bash
HXHX_NATIVE_PLUGIN_LOOP_REPS=3 npm run hxhx:bench:native-plugin-loop
HXHX_NATIVE_PLUGIN_LOOP_WARMUPS=0 npm run hxhx:bench:native-plugin-loop
HXHX_NATIVE_PLUGIN_LOOP_HXHX_BIN=/path/to/out.exe \
HXHX_NATIVE_PLUGIN_LOOP_HXHX_COMMIT="$(git rev-parse HEAD)" \
  npm run hxhx:bench:native-plugin-loop
```
