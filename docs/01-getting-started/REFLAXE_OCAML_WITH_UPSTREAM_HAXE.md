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

## Option A: use repo-local wiring in this monorepo

Inside this repo, `haxe_libraries/reflaxe.ocaml.hxml` already points to the
source layout used during development:

- `packages/reflaxe.ocaml/src/`
- `packages/reflaxe.ocaml/std/`
- `packages/reflaxe.ocaml/std/ocaml/_std/`
- `reflaxe.ocaml.CompilerInit.Start()`

That means local examples/tests can use `-lib reflaxe.ocaml` directly. No
`haxelib dev` step is needed for normal monorepo work.

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
