<p align="center">
  <img src="assets/hxhx-logo.png" alt="hxhx logo" width="560" />
</p>

# hxhx

[![CI](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.15.22-blue)](https://github.com/fullofcaffeine/hxhx/releases)

`hxhx` is a Haxe-in-Haxe compiler stack that is working toward Haxe `4.3.7`
compatibility. This repo also contains `reflaxe.ocaml`, a Reflaxe target for
compiling Haxe code to OCaml.

The practical user story today is:
- use `reflaxe.ocaml` with upstream Haxe to produce OCaml,
- try the native `hxhx` compiler path for supported experimental lanes,
- package Reflaxe targets as native artifacts for `hxhx`,
- embed `hxhx` as a compiler subprocess behind a stable command boundary.

`hxhx` is not yet a general drop-in replacement for upstream Haxe. That full
replacement goal is tracked separately in the technical roadmap and release
contracts.

## Goals status

This table is the short, public-facing status board for the main goals. It is
about production usability, not internal compiler milestones.

For the longer planning contract behind these rows, see
`docs/00-project/NORTH_STAR_GOALS.md`.

| Goal | Production usability today | What to use now | Not ready yet |
| --- | --- | --- | --- |
| `reflaxe.ocaml` with upstream `haxe` | Most usable path in this repo for producing OCaml from Haxe. Treat it as production-candidate: validate your own app and runtime needs before shipping. | Use upstream Haxe `4.3.7` plus `-lib reflaxe.ocaml`. Start with `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`. | A public 1.0 claim still depends on the release contract, runtime/stdlib closure evidence, and app-level validation. |
| `reflaxe.ocaml` with `hxhx` | Experimental. Useful for validating the native compiler path, not the default production route. | Use this when testing `hxhx` compatibility or native compiler work. Start with `docs/01-getting-started/REFLAXE_OCAML_WITH_HXHX.md` and keep upstream Haxe available as the practical fallback. | Full `hxhx` equivalence, release enforcement, and upstream-suite evidence are still being burned down. |
| `reflaxe.ocaml` as a native `hxhx` plugin | In progress. The promotion workflow and plugin-safe output mode exist, but this is not yet the broad production packaging story. | Reflaxe target authors can use the promotion docs to build and validate native plugin artifacts. | Native plugin loading, host API coverage, and release evidence still need to mature before this is the default recommendation. |
| `reflaxe.ocaml` as a builtin/native `hxhx` target | In progress. The design supports builtin host adapters as a separate packaging shape from plugins. | Use the promotion matrix docs to understand plugin vs builtin packaging. | The long-term goal is one reusable target core that can be packaged as plugin or builtin without rewriting the backend. That is not fully productized yet. |
| `hxhx` as a MIT drop-in Haxe replacement | Not production-ready. This is the major long-term goal: Haxe `4.3.7`-equivalent behavior, no required upstream-Haxe fallback, and credible performance. | Use `hxhx` for scoped native lanes, experiments, and subprocess embedding where the supported scope matches your use case. | Do not claim full drop-in compatibility until the upstream-derived Full 1.0 gates and performance evidence pass. |
| `hxhx` as a hackable Haxe-in-Haxe compiler | Active design principle. The compiler should become easier for Haxe developers to read, test, modify, and reason about than the historical upstream implementation. | Use repo docs, focused tests, and beads to make changes through bounded seams. Keep behavior-driven tests ahead of large rewrites. | Full hackability still requires more modular architecture, smaller compiler components, and clearer extension boundaries without sacrificing upstream parity. |
| Pluggable Haxe customization and Haxe-family variants | Planning track. This is a north-star architecture goal, not a supported user platform yet. | Use existing macro libraries, Reflaxe targets, and explicit `hxhx` experiments for bounded customization. Keep baseline Haxe compatibility as the default. | We still need a stable extension/dialect architecture so project-specific behavior can be plugged in, removed, or shipped as a deliberate variation without weakening baseline Haxe `4.3.7` claims. |
| Source/native target compilation beyond OCaml | Early implementation. PHP, Python, and Java now have strict upstream target-gate evidence; Java also has strict sys-suite evidence. C# and Lua now emit their upstream unit seams in no-run mode, and C++ has a first source-smoke target-core boundary. This is still target bring-up, not a production support claim. | For OCaml output, use `reflaxe.ocaml` with upstream Haxe. Use the source-target lanes only for validation, experiments, and closing gate blockers. | The desired end state is `hxhx` plus native Reflaxe target cores that can be packaged for upstream Haxe, `hxhx` plugin loading, or builtin `hxhx` targets. C++/hxcpp parity, C#/Lua runtime parity, and broader target parity still need evidence before this can become a user-facing production path. |

## Start here

If you are new, start with:
- `docs/01-getting-started/START_HERE.md`
- `docs/01-getting-started/WHAT_WORKS_TODAY.md`
- `docs/01-getting-started/CHOOSE_YOUR_LANE.md`
- `docs/00-project/GLOSSARY.md`

Those docs answer the first questions most users have:
1. What can I use today?
2. Should I use upstream Haxe, `hxhx`, or both?
3. How do I compile Haxe to OCaml?
4. How do I try native `hxhx` without relying on upstream Haxe?
5. Where do I find the deeper compiler and CI details?

If a term is unfamiliar, use `docs/01-getting-started/TERMS_YOU_MUST_KNOW.md`
or `docs/00-project/GLOSSARY.md`.

## Quick setup

```bash
npm install
npx lix download
HXHX_BIN="$(bash scripts/hxhx/build-hxhx.sh | tail -n 1)"
"$HXHX_BIN" --version
```

## Intended use cases

### Compile Haxe to OCaml today

Use `reflaxe.ocaml` with upstream Haxe when you want the most practical path for
turning Haxe code into OCaml output:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

Start here:
- `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`
- `packages/reflaxe.ocaml/README.md`

### Try the native hxhx compiler

Use `hxhx` when you want to test this repo's Haxe-in-Haxe compiler path. This
example compiles a JS entry point with upstream-Haxe fallback disabled:

```bash
HXHX_FORBID_STAGE0=1 "$HXHX_BIN" --js out/main.js -cp src -main Main --hxhx-no-run
```

Start here:
- `docs/01-getting-started/QUICKSTART_NATIVE.md`
- `docs/01-getting-started/WHAT_WORKS_TODAY.md`

### Package Reflaxe targets for native hxhx hosting

Use the promotion workflow when you are a Reflaxe target author and want to
build native plugin or builtin-host artifacts for `hxhx`:

- `docs/01-getting-started/PROMOTE_REFLAXE_TO_NATIVE.md`
- `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`

### Embed hxhx in another tool

Use `hxhx` as a subprocess when another tool needs a stable compiler command
boundary:

- `docs/02-user-guide/EMBEDDING.md`

## What is intentionally not in this README

Maintainer-only test loops, bootstrap regeneration, performance probes, release
gate internals, and targeted regression commands live in technical docs instead
of the public quickstart:

- `docs/01-getting-started/TESTING.md`
- `docs/00-project/CI_GATES.md`
- `docs/00-project/STAGE0_POLICY.md`
- `docs/benchmarks/HXHX_KPI_BASELINE.md`

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
  - `docs/01-getting-started/REFLAXE_OCAML_WITH_HXHX.md`
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

## Core concepts

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

## Current status

- `reflaxe.ocaml` with upstream Haxe is the practical OCaml output path today.
- Native `hxhx` is usable for scoped compiler experiments and selected lanes, not
  yet as a universal Haxe replacement.
- Native JS output has a documented scope:
  - `docs/02-user-guide/HXHX_JS_NATIVE_SCOPE_1_0.md`
- Full upstream Haxe `4.3.7` compatibility is an active project goal and must be
  proven by the release gates before it is claimed publicly:
  - `docs/01-getting-started/HXHX_1_0_ROADMAP.md`
  - `docs/00-project/FULL_1_0_CONTRACT.md`
  - `docs/00-project/CI_GATES.md`

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
