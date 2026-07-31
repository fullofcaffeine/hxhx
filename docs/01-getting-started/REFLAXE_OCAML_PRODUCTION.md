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
haxelib run reflaxe.ocaml doctor --require native
```

This checks more than three version commands: it verifies Haxe and Reflaxe
package resolution, the current runtime-source layout, OCaml, Dune, findlib,
Opam, compiler-libs, optional hxhx availability, project lock presence, and
whether the versions match the exact hosted evidence lane. It is read-only.

Inside this monorepo, run the equivalent source-checkout command:

```bash
npm run doctor:reflaxe-ocaml -- --require native
```

Expected product baseline:

- `haxe --version` should report `4.3.7`
- hosted package receipts currently use OCaml `5.2.1` and Dune `3.24.0`

Compatible newer local OCaml/Dune versions are reported as warnings rather
than mislabeled as hosted evidence. Use `--json` when retaining the result in a
CI artifact.

## Create a starter project

The installed source package carries the same tested templates used by package
validation:

```bash
haxelib run reflaxe.ocaml new app my-app --name "My App"
haxelib run reflaxe.ocaml new library my-library --name "My Library"
```

Scaffolding is transactional and non-destructive: the destination parent must
exist, the destination itself must not exist, and no existing files are merged
or overwritten. The application template builds and runs a native executable.
The library template builds a library-only Dune project and keeps the current
inferred-interface feature clearly separate from a future curated export ABI.

The command does not fabricate binding, native-adapter, plugin, or target
projects before their typed manifest and shared SDK contracts exist. Requests
for those kinds fail before creating a directory and explain the missing safe
boundary.

## Daily build and watch workflow

An installed package provides a project-oriented runner for the normal edit,
compile, and execute loop:

```bash
haxelib run reflaxe.ocaml build
haxelib run reflaxe.ocaml build --run .out.reflaxe-ocaml-dune-build/default/out.exe
haxelib run reflaxe.ocaml watch --run .out.reflaxe-ocaml-dune-build/default/out.exe
```

Both commands run the project's `build.hxml` by default. `watch` discovers Haxe
classpaths and included HXML files, supports additional repeated
`--watch-path <path>` inputs, waits for a stable edit batch, and runs the native
artifact only after a successful build. `--project` and `--hxml` select another
project or build file; `--max-builds` gives automation a bounded stopping point.

Every batch still uses a fresh Haxe process while the persistent-server route
finishes its remaining evidence. The batch itself is transactional: Reflaxe
publishes the complete generated `out/` tree first, then Dune builds the public
tree with reusable state in `.out.reflaxe-ocaml-dune-build/`. A source-generation
failure therefore leaves the previous public tree and native cache usable.
Output and common cache/build directories are excluded, and a post-build input
snapshot prevents generated files from causing a feedback loop.

The source transaction ends when the complete generated tree is published.
When a subsequent Dune build fails, the command returns that failure and does
not run the program, while the published source remains available for
inspection and retry. This is intentionally not presented as a rollback:
Dune has already observed the public tree. Fix the native-build error and
rerun; clear the separate Dune state only when diagnosing with a cold native
build.

The authoring command requests a receipt-linked timing report and prints total
Haxe-child time, measured target subprocess time, and the native Dune duration.
Dune typechecking, compilation, and linking are currently one combined phase.
The report does not infer cache hits or claim to separate loading, startup, and
workload runtime. Use `--output <directory>` when the HXML does not emit to
`out/`.

## Inspect compiler-owned build artifacts

After a successful build, retain a human-readable explanation or a stable JSON
receipt:

```bash
haxelib run reflaxe.ocaml inspect
haxelib run reflaxe.ocaml inspect --require-lowering
haxelib run reflaxe.ocaml inspect --json
```

Every successful build writes `ocaml_artifact_manifest.json`. It records every
compiler-owned non-cache file, the component that produced it, its role, byte
count, SHA-256 digest, and whether it belongs in the reproducible source bundle.
The command rechecks that inventory and also validates Reflaxe's narrower
generated-module receipt, optional native timing, the compile profile, and the
runtime module-selection report. With
`-D ocaml_lowering_report` (already present in the starter templates), it also
summarizes the migrated typed assignment/update plans: source location,
semantic and carrier types, representation reason, observable effect schedule,
and runtime requirement IDs. It also lists the pre-emission storage decision
for every mutable static field: the generated cell name, its Haxe and OCaml
types, where the cell is declared, where initialization occurs, and which other
mutable static initializers it reads directly. A dependency cycle stops with a
source-level `ocaml-static-storage:initializer-cycle` error before Dune or the
OCaml compiler runs. A static cell whose OCaml storage type would only become
available after that cell's Haxe initialization point similarly stops with
`ocaml-static-storage:representation-order-incompatible`; the target does not
silently reorder startup behavior to make the generated file compile. Use
`--output <directory>` when the HXML does not emit to `out`.

Inspection is deliberately read-only and fail-closed. Missing, stale, modified,
or unattributed generated files fail; typed place lowering is optional unless
`--require-lowering` is selected. It does not parse generated OCaml or Dune text
to reconstruct compiler semantics. A valid artifact inventory still reports
source-bundle packaging as blocked because not every runtime file has a
source-operation explanation yet, and the structured native-dependency
inventory has not landed. Runtime-enabled builds now write
`ocaml_runtime_requirement_report.json`, which traces typed
assignments and updates to their checked runtime source files. It also traces
standard `StringMap`, `IntMap`, and `ObjectMap` declarations to the checked
`HxMap` and `HxIterator` sources selected before OCaml syntax generation. Calls
known only as the generic `IMap` interface are not included in that typed Map
claim. The report explicitly lists runtime references from other compiler paths
as unexplained, so the current runtime selection is not presented as a whole-
program semantic manifest. The place report likewise covers one migrated
semantic family rather than a whole-program IR. Program-wide representation,
native dependency, raw/unsafe, binding, and curated export-ABI inspection stay
marked unavailable until their owning typed manifests exist.

`ocaml_output` is a compiler-owned directory. Do not mix handwritten OCaml or
project files into it: the build now rejects unknown non-cache files so they
cannot silently enter a release bundle. Keep those sources separate until the
structured adapter and native-dependency workflow provides an explicit owner.

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
then run the separate copied cold-output, unchanged-warm, and one-file-change
authoring workload. Every workload executes, and each receipt records
host/toolchain/load metadata. A final job opens both receipts and emits
`RO_TARGET_PERF_PLATFORM_MATRIX:PASS` only when the package identity, clean
commit, v2 method, samples, output checks, generated-change inventory, and
isolation proof agree.

Download `reflaxe-ocaml-perf-matrix-<commit>` from the package workflow for the
verified per-host report. Read Linux and macOS values separately: hosted
runners are different machines, so the workflow intentionally refuses to use
their absolute timing difference as a product comparison. The older local
reference command remains available as `npm run test:reflaxe-ocaml:perf`; see
`docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md` for method and limitations.
Use `npm run test:reflaxe-ocaml:iteration-perf` for the focused authoring-loop
report. Its timings are intentionally report-only.

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
- `.out.reflaxe-ocaml-dune-build/default/out.exe` after a transactional native build

Operational rule:

- treat `out/` as generated output
- treat `.out.reflaxe-ocaml-dune-build/` as disposable Dune-owned build state
- do not hand-edit emitted `.ml` files as your source of truth

Reset only native build state with:

```bash
dune clean --root out --build-dir .out.reflaxe-ocaml-dune-build
```

That leaves generated source and reports intact. Regenerating or intentionally
removing `out/` is a separate source-publication action and does not implicitly
delete Dune's cache.

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
- `RO_TARGET_ITERATION_REPORT:PASS`
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
6. If performance matters, run the standalone perf lane locally. Use
   `npm run test:reflaxe-ocaml:iteration-perf` when diagnosing the
   cold-output/warm-unchanged/one-file-change authoring loop.
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
