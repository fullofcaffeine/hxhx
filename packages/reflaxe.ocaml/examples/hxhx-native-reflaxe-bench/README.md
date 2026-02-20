# hxhx-native-reflaxe-bench

This example is a small, deterministic workload used for two things:

1. It is a normal acceptance example (`npm run test:examples`).
2. It is the workload used by the native benchmark script:
   `bash scripts/hxhx/bench-native-reflaxe.sh`.

The program prints two lines:

- `bench_iters=<n>`
- `bench_result=<value>`

By default it uses `20000` iterations.

Supported `HXHX_BENCH_ITERS` values in this fixture:

- `20000` (default)
- `50000`
- `100000`
- `200000`
