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
[![Version](https://img.shields.io/badge/version-0.15.0-blue)](https://github.com/fullofcaffeine/hxhx/releases)

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
6. understanding plugin vs builtin target modes,
7. embedding `hxhx` via a supported subprocess contract.

Lane chooser + mini glossary shortcuts:
- `docs/01-getting-started/CHOOSE_YOUR_LANE.md`
- `docs/01-getting-started/TERMS_YOU_MUST_KNOW.md`

## Quick setup

```bash
npm install
npx lix download
npm run ci:guards
npm test
```

If you are working on the heavy Stage3 generic-function arity regression specifically, run it outside the
default loop:

```bash
npm run test:m14:heavy
```

Build `hxhx` from committed bootstrap snapshots:

```bash
bash scripts/hxhx/build-hxhx.sh
```

This default build path only hydrates sharded snapshot files into a temporary bootstrap
workspace and runs `dune`; it no longer performs semantic patching of generated OCaml
during the build itself.

Performance tip for heavy bootstrap/source maintenance runs:

```bash
# If `which haxe` points to a Lix shim, prefer native stage0 explicitly.
HAXE_BIN="$HOME/haxe/versions/4.3.7/haxe" bash scripts/hxhx/regenerate-hxhx-bootstrap.sh --fast

# Regeneration owns snapshot finalization before the committed bootstrap snapshot is
# re-sharded and verified.

# Keep dune worker count deterministic (useful for memory-pressure tuning).
HXHX_DUNE_JOBS=4 bash scripts/hxhx/build-hxhx.sh

# Compare wrapper vs native stage0 policy and worker counts in one run.
HXHX_BOOTSTRAP_BENCH_SCENARIOS=warm HXHX_BOOTSTRAP_BENCH_DUNE_JOBS=auto,2,4 HXHX_BOOTSTRAP_BENCH_COMPARE_STAGE0_POLICIES=1 npm run hxhx:bench:bootstrap-regen

# If source builds use --connect and appear stuck, auto-retry sooner.
HXHX_FORCE_STAGE0=1 HXHX_STAGE0_USE_REPO_SERVER=1 HXHX_STAGE0_CONNECT_IDLE_SECS=90 bash scripts/hxhx/build-hxhx.sh
```

Defaults stay `HXHX_BOOTSTRAP_STAGE0_HAXE_POLICY=prefer-native` and `HXHX_DUNE_JOBS=auto`; use fixed workers only when tuning for host-specific memory constraints.

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
  - `docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md`
  - `docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md`
- **Native promotion workflow (Reflaxe -> native plugin/builtin host adapters)**
  - `docs/01-getting-started/PROMOTE_REFLAXE_TO_NATIVE.md`
  - `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`
  - `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
  - `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
  - `docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md`
  - `docs/01-getting-started/REFLAXE_ELIXIR_TODO_PROMOTION_PILOT.md`
  - Note: `reflaxe.elixir` is exercised via external fetched workflow (copyleft-safe boundary), not vendored/bundled sources in this repo.
- **Embedding workflow (`hxhx` as subprocess)**
  - `docs/02-user-guide/EMBEDDING.md`
  - Runnable example: `npm run hxhx:example:embedding-subprocess`

## Core concepts (recommended before deep docs)

- `docs/02-user-guide/concepts/execution_modes.md`
- `docs/02-user-guide/concepts/native_mode_pipeline.md`
- `docs/02-user-guide/concepts/targets_backends_plugins.md`
- `docs/02-user-guide/concepts/what_delegates_today.md`

## Plugin vs builtin target (high level)

- **Plugin target** (OCaml dynlink artifact: `.cmxs` / `.cma`): native artifact loaded at runtime through manifest.
- **Builtin target**: target linked and shipped inside `hxhx` binaries.

Current direction: keep target-core logic reusable so promotion is packaging/load choice, not backend rewrite.

For upstream `haxe` + `reflaxe.ocaml` plugin packaging, `-D ocaml_plugin_mode=1` now enables plugin-safe output defaults and can be combined with:
- `-D ocaml_module_prefix=<Prefix_>`
- `-D ocaml_emit_exclude_packages=<csv>`
- `-D ocaml_emit_exclude_paths=<csv>`

Those filters apply at emitted-artifact time so plugin packaging can omit host-provided units without changing typing.
`ocaml_module_prefix` renames emitted Haxe compilation units deterministically, which lets distinct promoted plugins avoid unit-name collisions without rewriting host/runtime-provided modules.

## Current status (concise)

- Compatibility baseline: **Haxe `4.3.7`**.
- Scoped replacement bundle and stage0-forbidden policy checks are wired and tracked.
- Native JS lane (`--js <file>`) exists as a scoped MVP lane with explicit in/out-of-scope matrix:
  - `docs/02-user-guide/HXHX_JS_NATIVE_SCOPE_1_0.md`
- Full upstream compatibility gates (Gate 1/2/3) run on weekly/manual cadence (see `docs/00-project/CI_GATES.md`).
- Full1 strict suite scaffolding uses a stable bootstrap-based matrix plus a non-blocking source-build probe lane for `server`/`optimization` (`FULL1_SOURCE_BUILD_PROBE:*` evidence in CI artifacts).
- Full1 also has a bootstrap-source reconciliation diagnostic lane that classifies `server`/`optimization` outcomes on the same commit (`FULL1_BOOTSTRAP_SOURCE_RECONCILIATION:*`).
- Semantic-diff PR canary is now scoped to stdlib/runtimegen-sensitive changes and always publishes triage artifacts (`semantic-diff-pr-artifacts`).
- Macro runtime mode parity is tracked weekly in both `external-host` and `inproc` lanes (see `.github/workflows/macro-runtime-parity-weekly.yml` and `docs/00-project/MACRO_RUNTIME_PARITY_BLOCKERS.md`).
- Native lanes default to in-process macro runtime (`inproc`); fallback/rollback remains available with `HXHX_MACRO_RUNTIME_MODE=external-host`.

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
