# HXHX Benchmarks — Baseline (Gate 4)

This file records **baseline numbers** for the minimal `hxhx` benchmark harness:

- `bash scripts/hxhx/bench.sh`
- `npm run hxhx:bench`
- `bash scripts/hxhx/bench-native-reflaxe.sh`
- `npm run hxhx:bench:native-reflaxe`

## Quick glossary (beginner-friendly)

- **stage0**: your existing upstream Haxe compiler binary.
- **`--target ocaml`**: compatibility/delegation-friendly preset path.
- **`--target ocaml-stage3`**: linked Stage3 backend path (native, non-delegating direction).

Today `hxhx` is still a **stage0 shim** delegating to a stage0 `haxe` binary, so the only meaningful metric is *shim overhead*.
As `hxhx` becomes a real compiler, this suite must be expanded (macro-heavy projects, upstream `tests/runci`, curated real repos).

## Baseline (macOS arm64)

Recorded: 2026-02-01  
Commit: `d68e7cce8ffa1e6bf4b033084d58e71bc9a7cf01`  
OS: macOS 15.4 (24E248)  
CPU: Apple M2 Pro  
Node: v20.19.3  
Stage0 Haxe: 4.3.7  
OCaml: 5.4.0  
Dune: 3.21.0  
Reps: 10

```
stage0: haxe --version           avg=   102ms  best=    79ms  worst=   140ms  reps=10
stage1: hxhx --version           avg=   231ms  best=    89ms  worst=  1207ms  reps=10
stage0: no-output compile        avg=   135ms  best=   104ms  worst=   185ms  reps=10
stage1: no-output compile        avg=   139ms  best=   108ms  worst=   201ms  reps=10
```

## Harness row additions (2026-02-18)

The benchmark harness now always includes:

- `stage1: --target ocaml-stage3`
- `stage1: --target js-native emit`

When a selected `hxhx` binary does not expose `js-native`, the JS row is still recorded as a sample result in skipped form:

```
stage1: --target js-native emit  skipped  reason=target_unavailable
```

Set `HXHX_BENCH_FORCE_REBUILD_FOR_JS_NATIVE=1` to force a source rebuild and capture numeric js-native results on hosts where the current binary lacks that target.

## Native reflaxe bench gate

Use:

```bash
npm run hxhx:bench:native-reflaxe
```

This benchmark checks the same workload across:

1. `haxe --interp` (eval baseline)
2. `hxhx --target ocaml`
3. `hxhx --target ocaml-stage3`

Default pass rule:

- `ocaml-stage3` median runtime must be at least `30%` faster than `--interp`.

Controls:

- `HXHX_NATIVE_BENCH_MIN_SPEEDUP_PCT` (default: `30`)
- `HXHX_NATIVE_BENCH_BASELINE=interp|delegated|both` (default: `interp`)

## How to update

When updating this file, include:

- absolute date
- commit SHA
- host toolchain versions
- full benchmark output block
