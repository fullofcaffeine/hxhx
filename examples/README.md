# Examples

These apps exist to:

- Provide real-world usage samples.
- Act as QA/acceptance tests (compile → dune build → run).

Run them all from the repo root:

```bash
npm run test:examples
```

Some examples are intentionally heavier and are **skipped** by `test:examples`.
Run those with:

```bash
npm run test:acceptance
```

## Included examples

- `mini-compiler`: small parser/evaluator smoke test (compiler-ish workload).
- `build-macro`: exercises `@:build` macro expansion (plugin/macro surface smoke test).
- `loop-control`: exercises `break`/`continue` lowering (prevents infinite-loop regressions).
- `ocaml-native-collections`: exercises `ocaml.*` wrappers over `Stdlib` collections (`Array`, `Hashtbl`, `Seq`, `Bytes`).
- `hih-workload` (acceptance-only): multi-file “project” compile with parsing, typechecking, and incremental rebuilds (Haxe-in-Haxe path Stage 1).
- `hih-compiler` (acceptance-only): Stage 2 skeleton for a production-grade Haxe-in-Haxe compiler (Haxe 4.3.7 + macros).
