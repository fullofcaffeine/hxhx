# reflaxe.ocaml Examples

These examples are focused on the `reflaxe.ocaml` target itself.

Important detail:

- They are still exercised through `hxhx` in this repo (not by calling `haxe` directly in the example harness).
- This lets us test both:
  1. target behavior, and
  2. how `hxhx` wires target execution.

Run all example suites from repo root:

```bash
npm run test:examples
```

Run heavier acceptance-only suites:

```bash
npm run test:acceptance
```

## Included examples

- `hxhx-target-ocaml`: minimal compatibility-lane smoke example (`hxhx --target ocaml`).
- `hxhx-target-ocaml-stage3`: minimal native-lane smoke example (`hxhx --hxhx-stage3` + `--library reflaxe.ocaml`).
- `build-macro`: small `@:build` macro behavior check.
- `extlib-pmap`: external OCaml library interop (`extlib`) check (acceptance-only).
- `file-io`: filesystem and sys API smoke checks.
- `loop-control`: `break`/`continue` lowering checks.
- `mini-compiler`: parser/evaluator style compiler-shaped sample.
- `ocaml-native-collections`: `ocaml.*` wrapper surface checks.
- `hxhx-native-reflaxe-bench`: deterministic workload used by native benchmark comparisons.
