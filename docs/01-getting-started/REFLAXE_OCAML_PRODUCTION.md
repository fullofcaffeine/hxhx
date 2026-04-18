# reflaxe.ocaml Production Guide

This is the operator-facing guide for using `reflaxe.ocaml` as a standalone OCaml target with upstream `haxe 4.3.7`.

Canonical product contract:

- `docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md`

Supporting evidence for the declared product scope:

- `docs/00-project/REFLAXE_OCAML_HAXE_4_3_7_MATRIX.md`
- `docs/00-project/REFLAXE_OCAML_RUNTIME_STDLIB_CLOSURE_AUDIT.md`
- `docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md`

Success marker for this documentation lane:

- `RO_PRODUCTION_DOCS:PASS`

Aggregate product-readiness marker for the declared standalone target scope:

- `RO_PRODUCTION_READY:PASS`

## What this guide is for

Use this guide when all of these are true:

- you want to keep upstream `haxe` as the host compiler,
- you want OCaml output through `-lib reflaxe.ocaml`,
- and you want a production-oriented install/use/troubleshooting reference instead of internal repo notes.

This guide is not the `hxhx` compiler guide.
If you want non-delegating compiler behavior, builtin targets, or plugin-host flows inside `hxhx`, use the `hxhx` docs instead.

## Product boundary

`reflaxe.ocaml` 1.0 means:

- upstream `haxe 4.3.7` can use `reflaxe.ocaml` as a real OCaml target for the declared scope,
- the target-owned runtime/stdlib surface for that scope is explicit,
- performance credibility exists for that standalone target path,
- and the install/use path is documented without relying on tribal knowledge.

It does not mean:

- `hxhx Full 1.0` compiler equivalence,
- plugin/promotion proof through every host shape,
- or non-delegating `hxhx` macro/runtime guarantees.

## Prerequisites

Required:

- Haxe `4.3.7`
- `reflaxe` `4.x`
- OCaml
- dune
- `ocaml-findlib`

Optional but common inside this monorepo:

- Node.js + npm
- Lix (`npx lix download`) for repo-local workflows

### Install toolchain

macOS:

```bash
brew install ocaml dune ocaml-findlib
```

Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y ocaml dune ocaml-findlib
```

Sanity-check the toolchain:

```bash
haxe --version
ocamlc -version
dune --version
```

Expected product baseline:

- `haxe --version` should report `4.3.7`

## Installation modes

### Mode A: local monorepo checkout via `haxelib dev`

This is the canonical developer/operator path when using this repo checkout directly.

```bash
haxelib dev reflaxe.ocaml /absolute/path/to/haxe.ocaml
```

Use this mode when:

- you want the freshest repo state,
- you are validating fixes before release packaging,
- or you are using the examples/docs in this monorepo.

### Mode B: repo-internal `haxe_libraries` wiring

Inside this monorepo, tests/examples already resolve `reflaxe.ocaml` through:

- `haxe_libraries/reflaxe.ocaml.hxml`

Use this mode when:

- you are running repo-local examples,
- CI/workflows are already rooted in this checkout,
- and you do not want to re-run `haxelib dev` for every local test loop.

## Canonical commands

### Emit OCaml only

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

What this does:

- upstream `haxe` hosts the compilation,
- `reflaxe.ocaml` emits OCaml sources into `out/`,
- no native build is requested yet.

### Emit and native-build

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

What this does:

- emits OCaml into `out/`,
- emits dune scaffolding,
- builds the native executable through dune.

### Run the native executable manually

```bash
cd out
dune build ./*.exe
dune exec ./out.exe
```

### Bytecode build instead of native

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=byte --no-output
```

Use bytecode when:

- you need a faster build/debug loop,
- or native codegen is not required for the current task.

## Required and common defines

Required:

- `-D ocaml_output=<dir>`

Common:

- `-D ocaml_build=native|byte`
- `-D ocaml_run`
- `-D ocaml_no_dune`
- `-D ocaml_dune_layout=exe|lib|plugin`
- `-D ocaml_dune_exes=name:MainModule[,name2:Main2]`
- `-D ocaml_plugin_run_main=1` for plugin layouts that need dynlink-time Haxe entrypoint side effects
- `-D ocaml_plugin_register_provider=<pluginId>:<providerType>` for `hxhx` backend-provider registration entry modules
- `-D ocaml_plugin_load_marker=<text>` for optional plugin smoke-test load evidence
- `-D ocaml_mli` or `-D ocaml_mli=infer|all`
- `-D ocaml_sourcemap=directives`
- `-D ocaml_profile=portable|metal`

Profile guidance:

- `portable` is the default and the mainstream recommendation
- `metal` is the strict performance-oriented lane and may reject unsupported dynamic/reflection-heavy constructs

See:

- `docs/02-user-guide/OCAML_PROFILE_CONTRACT.md`
- `docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md`

## Expected output layout

Typical generated tree:

- `out/*.ml`
- `out/*.mli` when enabled
- `out/dune`
- `out/dune-project`
- `out/_build/default/out.exe` after native build

Operational rule:

- treat `out/` as generated output
- do not hand-edit emitted `.ml` files as your source of truth

## Choosing between upstream `haxe + reflaxe.ocaml` and `hxhx`

| Need | Recommended path | Why |
| --- | --- | --- |
| Stable mainstream host behavior | upstream `haxe + reflaxe.ocaml` | Product scope under contract for `reflaxe.ocaml` |
| OCaml target output in an existing Haxe project | upstream `haxe + reflaxe.ocaml` | Smallest operational change |
| Non-delegating compiler/runtime validation | `hxhx` native lanes | Different product claim |
| Builtin target/plugin host experiments | `hxhx` workflows | Outside standalone `reflaxe.ocaml` target scope |

Hard rule:

- do not cite `hxhx Full 1.0` claims as proof that your upstream-Haxe `reflaxe.ocaml` path is production-ready
- do not cite standalone `reflaxe.ocaml` target docs as proof that `hxhx` is a drop-in Haxe replacement

## Common failure modes

### `Type not found : reflaxe.ocaml`

Cause:

- `haxelib dev reflaxe.ocaml /path/to/haxe.ocaml` was not run,
- or the repo-local `haxe_libraries` wiring is not available in your current project.

Fix:

```bash
haxelib dev reflaxe.ocaml /absolute/path/to/haxe.ocaml
```

Then rerun the compile command.

### `ocaml_output` missing / no OCaml output selected

Cause:

- `-D ocaml_output=<dir>` was omitted.

Fix:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

### dune / ocamlc not found

Cause:

- OCaml toolchain is incomplete.

Fix:

- install `ocaml`, `dune`, and `ocaml-findlib`
- verify with:

```bash
ocamlc -version
dune --version
```

### Native build fails but emit succeeds

Cause:

- the Haxe-to-OCaml compile step succeeded,
- but the downstream OCaml/dune build failed.

What to inspect:

- generated `out/` tree,
- dune error output,
- whether your project relies on constructs outside the declared target scope.

Next checks:

- compare against the declared validated examples in `docs/00-project/REFLAXE_OCAML_HAXE_4_3_7_MATRIX.md`
- verify that your usage stays within the target-owned runtime/stdlib closure in `docs/00-project/REFLAXE_OCAML_RUNTIME_STDLIB_CLOSURE_AUDIT.md`

### `metal` profile rejects code that `portable` accepts

Cause:

- `metal` is intentionally strict and fail-fast.

Fix:

- switch to `-D ocaml_profile=portable` for mainstream compatibility,
- or rewrite the rejected code to satisfy the metal verifier.

Reference:

- `docs/02-user-guide/OCAML_PROFILE_CONTRACT.md`

### Performance expectations look wrong

Cause:

- comparing against unrelated `hxhx` compiler benchmarks,
- or assuming cross-machine absolute numbers from the local reference host.

Fix:

- use `node scripts/ci/run-reflaxe-ocaml-perf.js`
- compare against `docs/00-project/REFLAXE_OCAML_PERF_BASELINE.json`
- treat the numbers as bounded expectations/regression indicators, not universal guarantees

## Evidence lanes to trust

For standalone `reflaxe.ocaml`, trust these product markers:

- `RO_HAXE_4_3_7_MATRIX:PASS`
- `RO_RUNTIME_STDLIB_CLOSURE:PASS`
- `RO_TARGET_PERF_CREDIBLE:PASS`
- `RO_PRODUCTION_DOCS:PASS`
- `RO_PRODUCTION_READY:PASS`

These are separate from `hxhx`-specific markers such as:

- `FULL1_MACRO_EVAL_PARITY:PASS`
- `FULL1_PERF_PARITY:PASS`
- `FULL1_RELEASE_GO:PASS`

## Operational checklist

Before calling the upstream-Haxe `reflaxe.ocaml` path production-ready for your use case:

1. Verify `haxe --version` is `4.3.7`.
2. Verify `haxelib dev reflaxe.ocaml ...` or repo-local library wiring is correct.
3. Run the canonical native build command on your project.
4. Confirm the output shape in `out/` looks normal.
5. Compare your workload class to the declared validation matrix.
6. If performance matters, run the standalone perf lane locally.
7. Before a release-facing claim, run the aggregate product-readiness check:
   `npm run test:reflaxe-ocaml:production-ready`.

Current local evidence artifacts for the aggregate marker:

- `.artifacts/reflaxe-ocaml/haxe-matrix/summary.json`
- `.artifacts/reflaxe-ocaml/perf/summary.json`

## Related docs

- `packages/reflaxe.ocaml/README.md`
- `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`
- `docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md`
- `docs/00-project/REFLAXE_OCAML_HAXE_4_3_7_MATRIX.md`
- `docs/00-project/REFLAXE_OCAML_RUNTIME_STDLIB_CLOSURE_AUDIT.md`
- `docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md`
