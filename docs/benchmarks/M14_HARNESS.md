# M14 Benchmarks (backend performance harness)

This repo includes a small benchmark harness for **reflaxe.ocaml** to help track:

- **Runtime** performance of hot-path stdlib code emitted for OCaml.
- **Compiler-shaped** performance (typing/lowering a larger Haxe workload).

## Run

```bash
npm run bench
```

This writes JSON results to:

- `bench/results/m14-<timestamp>.json`
- `bench/results/m14-latest.json`

## Tuning

Environment variables:

- `M14_BENCH_REPS` (default: `10`) — runtime reps
- `M14_BENCH_COMPILE_REPS` (default: `3`) — compile reps
- `M14_STRINGBUF_N` (default: `200000`) — iterations for the `StringBuf` microbench

## Dependencies

The harness requires:

- `haxe` (stage0)
- `dune` + `ocamlc` (native build for the runtime microbench)
- `python3` (timer + JSON writer)

If `dune`/`ocamlc` are missing, the benchmark runner prints a skip message and exits successfully.

