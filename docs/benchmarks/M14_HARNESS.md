# M14 Benchmarks (backend performance harness)

This repo includes a small benchmark harness for **reflaxe.ocaml** to help track:

- **Runtime** performance of hot-path stdlib code emitted for OCaml.
- **Compiler-shaped** performance (typing/lowering a larger Haxe workload).
- **Portable vs metal** runtime deltas on the same workloads.

## Run

```bash
npm run bench
```

This writes JSON results to:

- `bench/results/m14-<timestamp>.json`
- `bench/results/m14-latest.json`

CI includes a report-only M14 lane (`.github/workflows/m14-perf-report.yml`) that uploads these JSON files as artifacts and publishes a portable/metal ratio summary.

## Tuning

Environment variables:

- `M14_BENCH_REPS` (default: `10`) — runtime reps
- `M14_BENCH_COMPILE_REPS` (default: `3`) — compile reps
- `M14_PROFILES` (default: `portable,metal`) — profile lanes to benchmark
- `M14_RUNTIME_MODE` (default: `full`) — runtime module planning mode (`full|selective|none`)
- `M14_STRINGBUF_N` (default: `200000`) — iterations for the `StringBuf` microbench
- `M14_INT_ARRAY_N` (default: `50000`) — input size for `int_array_sum` microbench
- `M14_ANON_ITERATIONS` (default: `300000`) — loop count for `anon_getset` microbench

## Runtime microbenches

- `stringbuf` — `StringBuf` append hot-path
- `int_array_sum` — typed integer array accumulation
- `anon_getset` — anonymous object field get/set loop

The JSON report now includes per-profile benchmark rows and
`runtime_profile_ratios` (`portable_over_metal`) for matched runtime benchmarks.

Defaulting to `M14_RUNTIME_MODE=full` keeps profile comparisons stable while selective runtime planning is still evolving.

## Dependencies

The harness requires:

- `haxe` (stage0)
- `dune` + `ocamlc` (native build for the runtime microbench)
- `python3` (timer + JSON writer)

If `dune`/`ocamlc` are missing, the benchmark runner prints a skip message and exits successfully.
