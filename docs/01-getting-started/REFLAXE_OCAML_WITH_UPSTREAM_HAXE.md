# Using `reflaxe.ocaml` with upstream Haxe

This guide is for users who want to keep using upstream Haxe while targeting OCaml through `reflaxe.ocaml`.

Canonical product contract:

- `docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md`
- `docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md`

## What this gives you

- Upstream Haxe CLI/workflow.
- `reflaxe.ocaml` code generation/runtime.
- Native OCaml build path via dune.

Important boundary:

- for plugin-shaped native artifacts under upstream Haxe, the supported path is the explicit eval-host adapter lane
- this repo does not currently claim a true upstream compiler-target/native-target plugin ABI

Decision note:

- `docs/00-project/REFLAXE_OCAML_UPSTREAM_PLUGIN_INTEGRATION_DECISION.md`
- `docs/00-project/REFLAXE_OCAML_UPSTREAM_COMPILER_TARGET_PLUGIN_PROBE.md`

## Prerequisites

- Haxe `4.3.7`
- Node.js + npm (for local repo tooling/lix workflows)
- OCaml + dune + ocaml-findlib (if you want to build/run emitted OCaml)

macOS:

```bash
brew install ocaml dune ocaml-findlib
```

Linux (Debian/Ubuntu):

```bash
sudo apt-get update
sudo apt-get install -y ocaml dune ocaml-findlib
```

After installing `reflaxe.ocaml`, check the whole path from Haxe resolution to
native OCaml tools:

```bash
haxelib run reflaxe.ocaml doctor --require native
```

The default requirement is only `source`, so a machine that intentionally
emits OCaml for another builder can still receive an honest successful report.
Use `--require compiler` when the project needs `compiler-libs`, or `--json`
when CI or an editor needs the stable schema. An absent hxhx executable does
not break the upstream-Haxe workflow.

## Create an application or library

An installed package can create either tested starter layout:

```bash
haxelib run reflaxe.ocaml new app my-app --name "My App"
haxelib run reflaxe.ocaml new library my-library --name "My Library"
```

The command refuses an existing destination and commits a newly rendered
directory only after every template file is ready. The app produces a native
executable. The library produces a Haxe package and a library-only Dune build,
without claiming that current inferred `.mli` files are a curated public ABI.

Binding and handwritten-adapter scaffolds are intentionally withheld until the
typed OCaml interface, native-source ownership, and dependency manifests exist.
Plugin/target scaffolding remains with the shared stock-Haxe/hxhx plugin SDK.
Those unsupported kinds fail before creating files.

## Daily build and watch workflow

From an installed-package project that has a `build.hxml`, use:

```bash
haxelib run reflaxe.ocaml build
haxelib run reflaxe.ocaml build --run out/_build/default/out.exe
haxelib run reflaxe.ocaml watch --run out/_build/default/out.exe
```

The one-shot command runs the HXML in the project directory. The watch command
discovers classpaths and included HXML files, groups rapid edits into one stable
batch, rebuilds, and runs the artifact only after a successful build. Add
`--watch-path <path>` for native adapters or other inputs outside the discovered
roots.

The watcher deliberately starts a fresh Haxe process for each batch. Current
Reflaxe evidence found that persistent Haxe-server reuse could leave generated
output incomplete. Fast native iteration instead comes from Reflaxe avoiding
unchanged file rewrites and Dune reusing its incremental build cache. Generated
output and normal cache/build directories do not trigger rebuild loops.

Each authoring build requests a receipt-linked native timing report. Console
output separates the total Haxe child from measured target subprocesses and the
Dune build itself. Dune typechecking, compilation, and linking remain one
combined phase; cache hits, loading, startup, and workload runtime are not
guessed. Pass `--output <directory>` when the HXML emits somewhere other than
`out/`.

## Inspect what the build decided

Run inspection after a successful build:

```bash
haxelib run reflaxe.ocaml inspect
haxelib run reflaxe.ocaml inspect --require-lowering
haxelib run reflaxe.ocaml inspect --json
```

Each successful build writes `ocaml_artifact_manifest.json`, which covers every
compiler-owned non-cache file with its producer, role, byte count, SHA-256
digest, and source-bundle status. Inspection validates that complete inventory
as well as the narrower generated-module receipt, optional native timing,
compile profile, and current runtime module selection. A missing, changed, or
unattributed output file fails validation. Add
`-D ocaml_lowering_report` to a custom HXML to expose the
migrated typed place assignment/update plans; the starter templates already do
this. Those entries explain source positions, semantic-to-carrier types,
representation reasons, effect schedules, and runtime requirements.

The authority boundary is part of the output. The generated-file inventory is
valid, but it explicitly says source-bundle packaging is blocked until every
runtime need and native dependency has a locked explanation. Runtime-enabled
builds now explain runtime support used by typed assignments and updates, the
compiler-generated type registry, the declared `HxStdio` extern boundary, and
core packaging in
`ocaml_runtime_requirement_report.json`; other compiler paths remain visibly
unexplained. Today's runtime report is therefore not presented as a
complete whole-program explanation, and the typed place report covers only
assignments and updates rather than every compiler operation. Representation
registries, native dependencies, raw/unsafe proofs, bindings, and curated export
ABIs stay marked unavailable until their typed owners land. Inspection is
read-only and does not guess behavior by scanning generated OCaml or Dune files.

The output directory is compiler-owned. Keep handwritten OCaml sources outside
it for now; otherwise the build rejects them as unattributed rather than letting
them silently enter a package. The planned adapter/dependency workflow will
provide the explicit supported path for those files.

## Option A: use repo-local wiring in this monorepo

Inside this repo, `haxe_libraries/reflaxe.ocaml.hxml` already points to the
source layout used during development:

- `packages/reflaxe.ocaml/src/`
- `packages/reflaxe.ocaml/std/`
- `packages/reflaxe.ocaml/std/ocaml/_std/`
- `reflaxe.ocaml.CompilerInit.Start()`

That means local examples/tests can use `-lib reflaxe.ocaml` directly. No
`haxelib dev` step is needed for normal monorepo work.

The matching source-checkout diagnostic command is:

```bash
npm run doctor:reflaxe-ocaml -- --require native
```

Use that command in the monorepo rather than `haxelib run`: the source checkout
intentionally exposes target `_std` roots directly, while a published package
contains their flattened `.cross.hx` form.

Compile with:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

Build emitted OCaml natively:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

## Option B: use a released or locally built package outside this repo

Outside this monorepo, prefer the released haxelib package when available:

```bash
haxelib install reflaxe.ocaml
```

For unreleased checkout testing only, point an external app at this repo root
explicitly:

```bash
cd /path/to/my-haxe-app
haxelib dev reflaxe.ocaml /absolute/path/to/haxe.ocaml
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

That override is useful when `my-haxe-app` needs to validate a local
`reflaxe.ocaml` fix before a package is built or published. Use the repo root,
because its dev `extraParams.hxml` supplies `packages/reflaxe.ocaml/std` and
`packages/reflaxe.ocaml/std/ocaml/_std` directly. Do not point `haxelib dev` at
`packages/reflaxe.ocaml` unless you first build a flattened package; raw package
source keeps overrides in `_std`, and haxelib itself will not convert them to
`.cross.hx`.

Published or locally built packages are different: the Reflaxe package build
copies `std/ocaml/_std/*.hx` into the package classpath as `.cross.hx`, so the
package no longer needs the source `_std` classpath.

Why this is not the default recommendation:

- `haxelib dev` changes your local/global haxelib resolution state, so examples
  can start depending on an unchecked-out path by accident.
- pointing it at raw `packages/reflaxe.ocaml` skips Reflaxe's flattening step, so
  `_std` overrides are not converted to `.cross.hx`.
- pointing it at the repo root uses monorepo-only dev wiring that can hide bugs
  in the distributable package shape.
- release validation should exercise the flattened package zip, not only a dev
  checkout.

Prefer these instead:

- inside this repo: use `-lib reflaxe.ocaml` through
  `haxe_libraries/reflaxe.ocaml.hxml`
- for external pre-release validation: run
  `npm run test:reflaxe-ocaml:package-install`; it builds the deterministic ZIP,
  rejects checkout resolution, installs into a disposable haxelib repository,
  and builds/runs an external application with stock Haxe 4.3.7
- for normal users: install the released haxelib package

The proof writes `RO_PACKAGE_INSTALL_SMOKE:PASS` evidence under
`.artifacts/reflaxe-ocaml/package-install`. It records the exact host/toolchain;
one passing host does not silently become a cross-platform support claim.

CI additionally builds one immutable source ZIP and passes that exact download
to Ubuntu and macOS through
`.github/workflows/reflaxe-ocaml-package-matrix.yml`. Its aggregate
`RO_PACKAGE_ARTIFACT_MATRIX:PASS` marker is stronger than two independent
rebuilds because both host receipts must name the producer's commit and package
SHA. It records verified hosts only; Windows and a broader support policy remain
explicit follow-up work.

Those same installed-package jobs also run the six clean-build scenarios plus
the copied cold-output, unchanged-warm, and one-file-change authoring workload,
then upload raw per-host receipts. The aggregate
`RO_TARGET_PERF_PLATFORM_MATRIX:PASS` marker proves both hosts measured the
same clean ZIP outside the checkout, completed every raw sample, and matched
expected behavior. It does not compare Linux and macOS absolute speed because
the hosted runners have different hardware and scheduling conditions. See
`docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md` for the method, artifact
names, freshness policy, and current results.

## Common required define

`reflaxe.ocaml` expects:

```bash
-D ocaml_output=<output-dir>
```

Without it, target output is not selected.

## Relationship to `hxhx`

- `hxhx` is the primary compiler product in this repo.
- `reflaxe.ocaml` remains independently useful with upstream Haxe.
- We keep both in one repo right now because active development is still tightly coupled.

## Next doc

For the production-oriented install/use/troubleshooting path, use:

- `docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md`
