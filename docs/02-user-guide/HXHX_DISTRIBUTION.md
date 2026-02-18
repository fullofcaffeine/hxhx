# hxhx — Build, Distribution, and Benchmarks (Gate 4)

`hxhx` is the long-term **Haxe-in-Haxe compiler**.

Today it is still a **stage0 shim**:

- it is a native OCaml executable produced by `reflaxe.ocaml`
- it delegates compilation to a stage0 `haxe` binary (`HAXE_BIN` / PATH)

Gate 4 exists so we can build and ship the `hxhx` binary with a predictable layout, and track a minimal performance baseline.

## Version reporting (current behavior)

For compatibility with upstream tooling/tests:

- `hxhx --version` is **forwarded to stage0 `haxe`** and therefore prints the **stage0 Haxe version** (e.g. `4.3.7`)
- `hxhx --hxhx-help` prints shim-specific help

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
- linked Stage3 OCaml fast-path: `--target ocaml-stage3 --hxhx-no-emit`
- linked Stage3 JS emit throughput row: `--target js-native --hxhx-no-run --js ...`

If the selected `hxhx` binary does not expose `js-native`, the harness reports that row as `skipped`.
Set `HXHX_BENCH_FORCE_REBUILD_FOR_JS_NATIVE=1` to force a source rebuild (`HXHX_FORCE_STAGE0=1`) and measure the js-native row.

As `hxhx` becomes a real compiler (stops delegating), this benchmark suite should be expanded and the acceptance gates should include real-world workloads (upstream `tests/runci`, macro-heavy projects, and curated external repos).

Baseline numbers live in: `docs/benchmarks/HXHX_BASELINE.md:1`.
