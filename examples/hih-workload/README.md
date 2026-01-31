# hih-workload (Haxe-in-Haxe path, Stage 1)

This example is an **acceptance workload** that deliberately moves us closer to
“Haxe-in-Haxe enough”.

Unlike unit/snapshot tests, this is intended to be **compiler-like** and
**integration-heavy**:

- multi-file “project” compilation (reads sources from disk)
- lexing/parsing
- a tiny type-checking/symbol-table pass
- incremental rebuild logic using `sys.FileSystem.stat` (mtime)
- basic runtime usage: `Sys`, `FileSystem`, `File`, `Map`, `Bytes`, exceptions

## How to run

```bash
cd examples/hih-workload
haxe build.hxml -D ocaml_build=native
./out/_build/default/out.exe
```

## Stages toward compiling the full Haxe compiler

This repo tracks bootstrapping in stages:

1. **Stage 0**: `examples/mini-compiler` — single-file lexer/parser/evaluator.
2. **Stage 1**: `examples/hih-workload` — multi-file compilation + incremental rebuilds.
3. **Stage 2 (future)**: compile a real Haxe subproject (e.g. parser) largely unmodified.
4. **Stage 3 (future)**: compile a subset of the Haxe compiler itself.

The intent is to keep adding *realistic* compiler workloads without requiring the
entire Haxe compiler to compile on day 1.

Related docs:

- ML2HX subset contract: `docs/02-user-guide/ML2HX_SUBSET_CONTRACT.md`
- Imperative lowering: `docs/02-user-guide/IMPERATIVE_TO_OCAML_LOWERING.md`
