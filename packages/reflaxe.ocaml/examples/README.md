# reflaxe.ocaml Examples

These examples are focused on the `reflaxe.ocaml` target itself.

Important detail:

- They are still exercised through `hxhx` in this repo (not by calling `haxe` directly in the example harness).
- This lets us test both:
  1. target behavior, and
  2. how `hxhx` wires target execution.

The exact route matters. The checked example scorecard in
`docs/00-project/TESTING_PRODUCT_SURFACES.json` records whether an example uses
the evaluated `--ocaml-eval` route or the native Stage3 bring-up route. A green
Stage3 example is not counted as standalone `reflaxe.ocaml` qualification.
The current set is classified as capability showcases rather than flagship
applications.

Run all example suites from repo root:

```bash
npm run test:examples
```

When adding or changing an example, also run the fast inventory guard:

```bash
npm run guard:example-coverage
```

Buildable examples should include `build.hxml`, `README.md`, and
`expected.stdout`. The runner compiles through the declared lane, builds the OCaml
artifact when applicable, runs it, and compares stdout. If an example needs checks
beyond stdout, add `test.hxml` or `test.sh`; the runner executes those
example-specific checks after the stdout diff.

Run heavier acceptance-only suites:

```bash
npm run test:acceptance
```

## Included examples

- `hxhx-target-ocaml`: minimal delegated target smoke example (`hxhx --ocaml-eval`).
- `hxhx-target-ocaml-stage3`: minimal native-lane smoke example (`hxhx --hxhx-stage3` + `--library reflaxe.ocaml`).
- `build-macro`: small `@:build` macro behavior check.
- `extlib-pmap`: external OCaml library interop (`extlib`) check (acceptance-only).
- `file-io`: filesystem and sys API smoke checks.
- `loop-control`: `break`/`continue` lowering checks.
- `mini-compiler`: parser/evaluator style compiler-shaped sample.
- `ocaml-native-collections`: `ocaml.*` wrapper surface checks.
- `hxhx-native-reflaxe-bench`: deterministic workload used by native benchmark comparisons.
