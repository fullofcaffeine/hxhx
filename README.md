<p align="center">
  <img src="assets/hxhx-logo.png" alt="hxhx logo" width="560" />
</p>

# hxhx

[![CI](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml)
[![Compatibility Gate 1 Lite](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1-lite.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1-lite.yml)
[![Compatibility Gate 2 Lite](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2-lite.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2-lite.yml)
[![Compatibility Gate 3 Builtin](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3-builtin.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3-builtin.yml)
[![JS Oracle Smoke](https://github.com/fullofcaffeine/hxhx/actions/workflows/js-oracle-smoke.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/js-oracle-smoke.yml)
[![Compatibility Gate 1](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate1.yml)
[![Compatibility Gate 2](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate2.yml)
[![Compatibility Gate 3](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/gate3.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.14.0-blue)](https://github.com/fullofcaffeine/hxhx/releases)

`hxhx` is a Haxe-in-Haxe compiler stack targeting Haxe `4.3.7` compatibility.
This repo also contains `reflaxe.ocaml` and native promotion tooling so Reflaxe targets can be compiled to native plugin artifacts.

## Start here

If you are new, read:
- `docs/README.md`
- `docs/01-getting-started/START_HERE.md`
- `docs/00-project/GLOSSARY.md`
- `docs/00-project/CI_GATES.md`

That guide gives a beginner path for:
1. building/running `hxhx`,
2. choosing compat vs native quickstart lanes,
3. checking what works today at a glance,
4. using upstream `haxe` with `reflaxe.ocaml`,
5. promoting a Reflaxe target/compiler to native plugin artifacts,
6. understanding plugin vs builtin target modes.

## Quick setup

```bash
npm install
npx lix download
npm run ci:guards
npm test
```

Build `hxhx` from committed bootstrap snapshots:

```bash
bash scripts/hxhx/build-hxhx.sh
```

## Pick your workflow

- **`hxhx` compiler workflow**
  - `docs/01-getting-started/QUICKSTART_COMPAT.md`
  - `docs/01-getting-started/QUICKSTART_NATIVE.md`
  - `docs/01-getting-started/WHAT_WORKS_TODAY.md`
  - `docs/01-getting-started/HXHX_1_0_ROADMAP.md`
  - `docs/01-getting-started/HXHX_SELF_HOSTING_CHECKLIST.md`
  - `docs/02-user-guide/HAXE_IN_HAXE_ACCEPTANCE.md`
- **`reflaxe.ocaml` with mainstream Haxe**
  - `packages/reflaxe.ocaml/README.md`
  - `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`
- **Native promotion workflow (Reflaxe -> native plugin/builtin host adapters)**
  - `docs/01-getting-started/PROMOTE_REFLAXE_TO_NATIVE.md`
  - `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
  - `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
  - `docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md`
  - `docs/01-getting-started/REFLAXE_ELIXIR_TODO_PROMOTION_PILOT.md`
  - Note: `reflaxe.elixir` is exercised via external fetched workflow (copyleft-safe boundary), not vendored/bundled sources in this repo.

## Core concepts (recommended before deep docs)

- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/native_mode_pipeline.md`
- `docs/02-user-guide/concepts/targets_backends_plugins.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`

## Plugin vs builtin target (high level)

- **Plugin target** (OCaml dynlink artifact: `.cmxs` / `.cma`): native artifact loaded at runtime through manifest.
- **Builtin target**: target linked and shipped inside `hxhx` binaries.

Current direction: keep target-core logic reusable so promotion is packaging/load choice, not backend rewrite.

## Current status (concise)

- Compatibility baseline: **Haxe `4.3.7`**.
- Scoped replacement bundle and stage0-forbidden policy checks are wired and tracked.
- Native JS preset (`--target js`) exists as a scoped MVP lane with explicit in/out-of-scope matrix:
  - `docs/02-user-guide/HXHX_JS_NATIVE_SCOPE_1_0.md`
- Full upstream compatibility gates (Gate 1/2/3) run on weekly/manual cadence (see `docs/00-project/CI_GATES.md`).

## Command catalog

For full command reference (tests, gates, promotion, plugin matrix):
- `docs/01-getting-started/TESTING.md`

## Environment prerequisites

- Node.js + npm
- Haxe `4.3.7`
- OCaml `5.2+`, `dune`, `ocaml-findlib`

macOS:

```bash
brew install ocaml dune ocaml-findlib
```

Linux (opam):

```bash
sudo apt-get update
sudo apt-get install -y opam m4 pkg-config libgmp-dev
opam init -a --disable-sandboxing
opam switch create 5.2.1
eval "$(opam env)"
opam install -y dune ocamlfind
```

## Additional docs

- `docs/00-project/BOUNDARIES.md`
- `docs/00-project/DYNAMIC_UNTYPED_POLICY.md`
- `docs/00-project/STAGE0_POLICY.md`
- `docs/00-project/STD_LIB_POLICY.md`
- `docs/01-getting-started/CLEANUP_AND_CACHE_POLICY.md`
- `docs/00-project/PUBLIC_RELEASE_PREFLIGHT.md`
