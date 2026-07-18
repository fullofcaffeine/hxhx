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

Release-status clarification (2026-07-18): this existing aggregate proves the
historical example/package/performance bundle, but it is not currently a 1.0
authorization. The target remains an advanced preview while
`haxe_ocaml-9v1va` establishes validated place/evaluation lowering and
`haxe_ocaml-0uwin` makes runtime requirements fail closed. The canonical
contract records how the aggregate must be strengthened after those blockers
land.

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

The package's repository location is not part of the 1.0 product claim.
`reflaxe.ocaml` remains in this monorepo today, but its release-shaped evidence
must already work without resolving target source from the checkout. The
future extraction gate and the continuing downstream `hxhx` QA relationship
are defined in
`docs/00-project/REFLAXE_OCAML_REPOSITORY_EXTRACTION_GATE.md`.

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

### Mode A: repo-internal `haxe_libraries` wiring

Inside this monorepo, tests/examples already resolve `reflaxe.ocaml` through:

- `haxe_libraries/reflaxe.ocaml.hxml`

Use this mode when:

- you are running repo-local examples,
- CI/workflows are already rooted in this checkout,
- or you want the freshest repo state without reinstalling a haxelib on each edit.

This mode supplies the generated-Reflaxe-style source paths directly:

- `packages/reflaxe.ocaml/src/`
- `packages/reflaxe.ocaml/std/`
- `packages/reflaxe.ocaml/std/ocaml/_std/`

### Mode B: released or locally built package outside this repo

Outside this monorepo, prefer the flattened package produced by the Reflaxe
build/release path.

Use this mode when:

- you are using `reflaxe.ocaml` from another project,
- you want package-shaped behavior rather than source-checkout behavior,
- or you are validating release packaging.

For unreleased checkout testing only, use a temporary local override:

```bash
cd /path/to/my-haxe-app
haxelib dev reflaxe.ocaml /absolute/path/to/haxe.ocaml
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

Do not treat that as the normal monorepo workflow. It is an external-project
override for validating source changes before a package is built or published.
Use the repo root for that override because its dev `extraParams.hxml` adds the
source `_std` classpath. A flattened package build handles this differently by
turning `_std/*.hx` overrides into package `.cross.hx` files.

Why this mode is intentionally narrow:

- `haxelib dev` is machine-local state and can make another project depend on an
  unreleased checkout without making that dependency obvious in source control.
- raw package source does not run Reflaxe's build flattening, so `_std` files do
  not become `.cross.hx` files automatically.
- the repo-root override is a dev convenience, not proof that the package zip is
  correct.
- release-facing validation should use `bash scripts/release/build-haxelib-zip.sh`
  and test the generated package shape.

Better defaults:

- monorepo development: use the checked-in `haxe_libraries/reflaxe.ocaml.hxml`
  wiring
- external pre-release validation: run the isolated package proof below
- production/user installs: consume the released haxelib package

### Verify the installable package

From this repository, run:

```bash
npm run test:reflaxe-ocaml:package-install
```

This is stronger than compiling a repo-local example. It:

- builds the versioned haxelib ZIP twice and requires the same SHA-256,
- stages only tracked source files and rejects host/compiler outputs such as
  `.cmi`, `.cmo`, and `.cmxs`,
- proves an external application cannot compile before the target is installed,
- installs the ZIP into a disposable haxelib repository without resolving the
  target from this checkout,
- compiles the original external fixture with stock Haxe 4.3.7,
- asks Dune to build the generated OCaml natively, runs it, and compares stdout.

The success marker is `RO_PACKAGE_INSTALL_SMOKE:PASS`. Machine-readable evidence
is written to `.artifacts/reflaxe-ocaml/package-install/summary.json`, including
the source commit, package and generated-artifact hashes, toolchain versions,
installed relative path, and runtime result. The marker proves the recorded host
and toolchain only; it does not declare every operating system supported.

The maintained cross-host evidence lane is:

- `.github/workflows/reflaxe-ocaml-package-matrix.yml`

It builds the source ZIP once, uploads its clean commit/version/SHA manifest,
then gives that same downloaded artifact to Ubuntu and macOS jobs. Neither host
job may rebuild it. Both perform the disposable haxelib install and external
native application proof above. A final job opens both receipts, rejects mixed
package hashes or dirty provenance, and emits
`RO_PACKAGE_ARTIFACT_MATRIX:PASS`.

That marker is verified-host evidence: the recorded Linux and macOS hosts
verified one candidate. It does not silently declare all Linux distributions,
all macOS/toolchain versions, or Windows supported. The product owner must make
and maintain that broader support declaration separately.

The same host jobs then measure the installed ZIP instead of the checkout.
They copy the six canonical examples to external workspaces, retain three raw
build samples per example and nine raw run samples for each benchmark profile,
execute every workload, and record host/toolchain/load metadata. A final job
opens both receipts and emits `RO_TARGET_PERF_PLATFORM_MATRIX:PASS` only when
the package identity, clean commit, method, samples, output checks, and
isolation proof agree.

Download `reflaxe-ocaml-perf-matrix-<commit>` from the package workflow for the
verified per-host report. Read Linux and macOS values separately: hosted
runners are different machines, so the workflow intentionally refuses to use
their absolute timing difference as a product comparison. The older local
reference command remains available as `npm run test:reflaxe-ocaml:perf`; see
`docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md` for method and limitations.

This ZIP is the standalone Haxe target source package. It does not settle the
future native-plugin loader format: stock Haxe and `hxhx` still aim to share one
semantic plugin payload, with different thin loader shells allowed only for a
measured OCaml runtime/compiler/linker incompatibility.

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

For the current `hxhx + reflaxe.ocaml` status, use:

- `docs/01-getting-started/REFLAXE_OCAML_WITH_HXHX.md`

Hard rule:

- do not cite `hxhx Full 1.0` claims as proof that your upstream-Haxe `reflaxe.ocaml` path is production-ready
- do not cite standalone `reflaxe.ocaml` target docs as proof that `hxhx` is a drop-in Haxe replacement

## Common failure modes

### `Type not found : reflaxe.ocaml`

Cause:

- you are outside this repo and have not installed or selected a `reflaxe.ocaml` package,
- or the repo-local `haxe_libraries` wiring is not available in your current project.

Fix:

```bash
# Preferred for released/package-shaped use, once available.
haxelib install reflaxe.ocaml

# Temporary override for testing this unreleased checkout from another project.
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
- for release-shaped host evidence, open the latest
  `reflaxe-ocaml-perf-matrix-<commit>` artifact and compare a host only with
  repeated evidence from the same runner class

## Evidence lanes to trust

For standalone `reflaxe.ocaml`, trust these product markers:

- `RO_HAXE_4_3_7_MATRIX:PASS`
- `RO_RUNTIME_STDLIB_CLOSURE:PASS`
- `RO_TARGET_PERF_CREDIBLE:PASS`
- `RO_TARGET_PERF_PLATFORM_MATRIX:PASS`
- `RO_PRODUCTION_DOCS:PASS`
- `RO_PRODUCTION_READY:PASS`

These are separate from `hxhx`-specific markers such as:

- `FULL1_MACRO_EVAL_PARITY:PASS`
- `FULL1_PERF_PARITY:PASS`
- `FULL1_RELEASE_GO:PASS`

## Operational checklist

Before calling the upstream-Haxe `reflaxe.ocaml` path production-ready for your use case:

1. Verify `haxe --version` is `4.3.7`.
2. Verify repo-local library wiring, a released package install, or an explicit checkout override is correct.
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
