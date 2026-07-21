<p align="center">
  <img src="assets/hxhx-logo.png" alt="hxhx logo" width="560" />
</p>

# hxhx

[![CI](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.23.4-blue)](https://github.com/fullofcaffeine/hxhx/releases)

`hxhx` is a Haxe-in-Haxe compiler stack that is working toward Haxe `4.3.7`
compatibility. This repo also contains `reflaxe.ocaml`, a Reflaxe target for
compiling Haxe code to OCaml.

The practical user story today is:
- use `reflaxe.ocaml` with upstream Haxe to produce OCaml,
- try the native `hxhx` compiler path for supported experimental lanes,
- package Reflaxe targets as native artifacts for `hxhx`,
- embed `hxhx` as a compiler subprocess behind a stable command boundary.

The planned native-plugin product goes further: one promoted Reflaxe plugin ABI
and payload should work in both stock Haxe and `hxhx`. That shared plugin is not
available today. The identical binary is the design target; thin host loader
shells are allowed only if measured OCaml runtime or compiler constraints make
them necessary, and the shells may not contain target behavior.

`hxhx` is not yet a production replacement for upstream Haxe. The first Full1
promise covers an explicit target/generator scope rather than every upstream
output; its remaining work is tracked in the technical roadmap and release
contracts.

## Goals status

This table is the short, public-facing status board for the main goals. It is
about production usability, not internal compiler milestones.

For the longer planning contract behind these rows, see
`docs/00-project/NORTH_STAR_GOALS.md`.

Progress bars are coarse editorial readiness indicators. They are not computed
percentages and must not add unlike evidence such as contract guards, focused
regressions, upstream suites, packaged products, and release candidates. The
words beside each bar, the strongest current evidence, its freshness, the
active owner bead, and the "Not ready yet" column control the claim.

Overall north-star readiness: `[####------]` (coarse; not additive).

| Goal | Progress | Production usability today | What to use now | Not ready yet |
| --- | --- | --- | --- | --- |
| `reflaxe.ocaml` with upstream `haxe` | `[#######---]` | **Advanced preview.** It is the most usable route here, and a production candidate only for the declared example/runtime matrix after validating your own application. A deterministic source-only ZIP now has isolated macOS and Ubuntu install/native external-app proofs. | Use upstream Haxe `4.3.7` plus `-lib reflaxe.ocaml`. Start with `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`. | Active product owner `haxe_ocaml-s7jry` still needs a declared supported-platform matrix, retained release provenance, sustained per-platform performance evidence, the validated place/evaluation slice `haxe_ocaml-9v1va`, and fail-closed semantic runtime ownership under `haxe_ocaml-0uwin`. The existing `RO_PRODUCTION_READY:PASS` receipt opens the older bounded evidence bundle, not those new release prerequisites. Isolated package proof `.1` and the same-ZIP macOS/Linux proof `.2` remain valid. |
| `reflaxe.ocaml` with `hxhx` | `[###-------]` | **Experimental.** Useful for validating the native compiler route, not the default production route. | Use this when testing `hxhx` compatibility or native compiler work. Start with `docs/01-getting-started/REFLAXE_OCAML_WITH_HXHX.md` and keep upstream Haxe available as the practical fallback. | Active product owner `haxe_ocaml-38gsp` depends on Full1 frontend evidence and the standalone target product. The completed definition foundation is `haxe.ocaml-n5ae`. |
| `reflaxe.ocaml` as a native `hxhx` plugin | `[###-------]` | **Experimental promotion path.** ABI, registry, promotion workflow, plugin-safe output, and a same-candidate three-route workload proof exist; broad supported packaging does not. | Reflaxe target authors can use the promotion docs to build and validate native plugin artifacts. | The Full1 workload outcome is complete under `haxe_ocaml-gskz9`. M22 owner `haxe_ocaml-bomhr` plans the future typed host-service SDK and still needs package/install, support/versioning, repeated real-target evidence, and release-grade artifact provenance. |
| One native Reflaxe plugin for stock Haxe and `hxhx` | `[#---------]` | **Planning contract only.** Stock Haxe currently has an eval-host adapter and `hxhx` has its own experimental native loader; they do not yet load one shared payload through one supported ABI. | Use the existing host-specific experimental lanes only. Do not assume their current `.cmxs`/`.cma` artifacts are interchangeable. | P0 M22 owner `haxe_ocaml-c4czv` must define and prove one versioned cross-host ABI, the same payload and behavior in both hosts, and install/upgrade/rollback evidence. Identical packaging is the default goal. A different thin loader shell is acceptable only after an exact OCaml runtime/compiler/linker incompatibility is recorded; semantic forks are forbidden. |
| `reflaxe.ocaml` as a builtin/native `hxhx` target | `[##--------]` | **Architecture proof.** The target-core/adapter design supports a builtin host shape, but it is not productized. | Use the promotion matrix docs to understand plugin versus builtin packaging. | M22 owner `haxe_ocaml-bomhr` must prove one semantic target core across host-neutral, plugin, and builtin forms, including typed service negotiation and real artifact evidence. Completed foundations: `haxe.ocaml-rpmx` and `haxe.ocaml-anoy`. |
| `hxhx` as a MIT Haxe replacement | `[###-------]` | **Not production-ready.** A fresh strict/full, stage0-forbidden replacement bundle is green for its bounded Macro/JavaScript/Neko and plugin scope. Macro/eval also has a same-commit proof that checks the uploaded evidence files before passing. The larger goal remains Haxe `4.3.7` compatibility for the declared Full1 target/generator scope, with credible compiler performance and practical edit-compile-test latency. It is not an all-target claim. | Use `hxhx` for scoped native lanes, experiments, and subprocess embedding where the supported scope matches your use case. Read `docs/02-user-guide/compat/FULL1_TARGET_SCOPE.md` before evaluating it for a project. | M7 run `29321576340` and macro/eval run `29353274632` are current green evidence, not a Full1 release candidate. `haxe.ocaml-f1cl` still owns same-candidate strict suites, the full required target matrix, performance, and release evidence. C++/Cppia and both HashLink forms remain required. The candidate-bound release handoff has correctly produced only a no-go receipt because real Full1 evidence is incomplete. |
| `hxhx` as a hackable Haxe-in-Haxe compiler | `[####------]` | **Active design principle.** The package/phase/backend seams are real, while concentrated implementation and test responsibilities still limit routine reviewability. | Use repo docs, focused tests, and beads to make changes through bounded seams. Keep behavior-driven tests ahead of large rewrites. | The temporary bridge inventory/guard (`haxe_ocaml-slobw`) and grouped source/C++ smoke retries (`haxe_ocaml-o2udb`) are complete foundations. Broader extraction remains profile/recurrence-triggered, with no compiler-wide rewrite or speculative neutral IR planned. |
| Pluggable Haxe customization and Haxe-family variants | `[#---------]` | **Architecture foundation only.** This is not a supported platform and must remain excluded from baseline evidence. | Use existing macro libraries, Reflaxe targets, and explicit `hxhx` experiments for bounded customization. Keep baseline Haxe compatibility as the default. | Post-Full1 successor `haxe_ocaml-h5jta` owns lifecycle, capability, reversibility, conflict, packaging, and baseline-exclusion evidence. Child `haxe_ocaml-h5jta.1` now owns the review candidate for Haxe-authored native compiler-transform plugins, beginning with a small cross-host example and progressing to a Coro-class proof. Planning adds no readiness. |
| Source/native target compilation beyond OCaml | `[####------]` | **Target bring-up.** The required matrix is now explicit, but the aggregate is not green. Required output includes C++ plus Cppia and both HashLink forms. | For OCaml output, use `reflaxe.ocaml` with upstream Haxe. Use the source-target lanes only for validation, experiments, and closing gate blockers. | Matrix owners `haxe.ocaml-f1cl.3.1` and `.3.11` require same-SHA per-target evidence. C++ is a mandatory Full1 target; the focused leaf `haxe_ocaml-94hk1` remains P2 until profiling proves the next high-leverage fix. JVM, Flash/SWF, and XML/JSON type descriptions are not part of the first Full1 claim. |

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

`HXHX_FORBID_STAGE0=1` does not mean the upstream compiler may never be used to
build `hxhx`. It means this compiler-under-test invocation must fail instead of
quietly asking the installed upstream `haxe` binary to do its work. That makes
the result evidence about `hxhx`, not about a hidden fallback.

Start here:
- `docs/01-getting-started/QUICKSTART_NATIVE.md`
- `docs/01-getting-started/WHAT_WORKS_TODAY.md`

### Package Reflaxe targets for native hosting

Use the promotion workflow when you are a Reflaxe target author and want to
build native plugin or builtin-host artifacts. The commands currently exercise
the `hxhx` loader. M22 plans a shared plugin ABI and payload for stock Haxe and
`hxhx`; that future product must not require two target implementations:

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
- `docs/01-getting-started/FAST_LOCAL_VALIDATION.md`
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
  - Planning only: `docs/00-project/HXHX_HAXE_FAMILY_VARIATION_WORKFLOW.md`
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

The M22 product contract requires stock Haxe and `hxhx` to expose one versioned
plugin ABI and load one promoted payload. Prefer one identical native binary.
If OCaml host-runtime or compiler identity prevents that packaging, generated
host loader shells may differ only as thin ABI adapters around the same payload
or reproducibly derived native core. Current manifest v1 artifacts predate that
contract and remain host-specific until the hard cutover is implemented.

For upstream `haxe` + `reflaxe.ocaml` plugin packaging, `-D ocaml_plugin_mode=1` now enables plugin-safe output defaults and can be combined with:
- `-D ocaml_module_prefix=<Prefix_>`
- `-D ocaml_emit_exclude_packages=<csv>`
- `-D ocaml_emit_exclude_paths=<csv>`

Those filters apply at emitted-artifact time so plugin packaging can omit host-provided units without changing typing.
`ocaml_module_prefix` renames emitted Haxe compilation units deterministically, which lets distinct promoted plugins avoid unit-name collisions without rewriting host/runtime-provided modules.

## Current status

- `reflaxe.ocaml` with upstream Haxe is the practical OCaml output path today.
- A single native Reflaxe plugin payload for stock Haxe and `hxhx` is planned,
  not currently supported; present host-adapter artifacts are not interchangeable.
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
