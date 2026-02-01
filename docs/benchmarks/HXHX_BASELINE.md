# HXHX Benchmarks — Baseline (Gate 4)

This file records **baseline numbers** for the minimal `hxhx` benchmark harness:

- `bash scripts/hxhx/bench.sh`
- `npm run hxhx:bench`

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

## How to update

When updating this file, include:

- absolute date
- commit SHA
- host toolchain versions
- full benchmark output block

