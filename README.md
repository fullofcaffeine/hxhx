<p align="center">
  <img src="assets/hxhx-logo.png" alt="hxhx logo" width="560" />
</p>

# hxhx

[![CI](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml/badge.svg)](https://github.com/fullofcaffeine/hxhx/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.34.0-blue)](https://github.com/fullofcaffeine/hxhx/releases)

`hxhx` is a Haxe-in-Haxe compiler stack that is working toward Haxe `4.3.7`
compatibility. This repo also contains `reflaxe.ocaml`, a Reflaxe target for
compiling Haxe code to OCaml.

The practical user story today is:
- use `reflaxe.ocaml` with upstream Haxe to produce OCaml,
- try the native `hxhx` compiler path for supported experimental lanes,
- package Reflaxe targets as native artifacts for `hxhx`,
- embed `hxhx` as a compiler subprocess behind a stable command boundary.

The planned native-plugin product goes further: one Haxe-authored semantic
target core and versioned contract should work in both stock Haxe and `hxhx`.
That shared core is not available today. The reference toolchain will test one
combined `.cmxs`, but exact generated host shells are allowed because OCaml
interface/runtime identity is a packaging concern. The shells may not contain
target behavior. The project treats practical edit-compile-test latency as part
of that product: native execution and compiler-server caching count as progress
only when measured repeated builds stay equivalent to clean builds.

`hxhx` is not yet a production replacement for upstream Haxe. The first Full1
promise covers an explicit target/generator scope rather than every upstream
output; its remaining work is tracked in the technical roadmap and release
contracts.

## Goals status

This table is the short, public-facing status board for the main goals. It is
about production usability, not internal compiler milestones.

For the longer planning contract behind these rows, see
`docs/00-project/NORTH_STAR_GOALS.md`.

Progress bars and percentage ranges are coarse editorial readiness estimates.
One block is roughly ten percentage points. A range is used when the available
routes have materially different maturity or the next unresolved gate could
change the estimate. The values are not computed by adding unlike evidence
such as contract guards, focused regressions, upstream suites, packaged
products, and release candidates. The words beside each estimate, the strongest
current evidence, its freshness, the active owner Bead, and the "Not ready yet"
column control the claim.

Overall north-star readiness: `[###-------]` about 30–35% (coarse; not
additive).

| Goal | Progress | Production usability today | What to use now | Not ready yet |
| --- | --- | --- | --- | --- |
| `reflaxe.ocaml` with upstream `haxe` | `[#######---]` about 65–70% | **Advanced preview.** This remains the most usable route. The declared example/runtime matrix, deterministic source package, and isolated macOS/Ubuntu native application proofs exist. | Use upstream Haxe `4.3.7` plus `-lib reflaxe.ocaml`. Package `build` and `watch` use a fresh Haxe process by default; explicit local `--connect <port>` is an experimental frontend-reuse lane. Start with `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`. | Representation/storage/capture (`9bome`) and calls/conversions (`taef5`) are now closed. Product owner `haxe_ocaml-s7jry` still needs control effects (`w32h3`), fail-closed runtime ownership (`0uwin`), complete artifact/native-dependency authority, and fresh release evidence. Runtime ownership now checks typed String equality, direct standard String methods and fields, String null checks in typed `Reflect.compare`, typed String conversion, and seven standard `Reflect` field operations with Haxe's left-to-right evaluation order. Calls to the exact generic identity shape now preserve concrete `String`, `Int`, and `Bool` values without `Obj.t`. However, 225 legacy helper sites remain, so the readiness range is unchanged. Opt-in exact unchanged-request replay has passed compiler-scale qualification, but it is not yet a documented, supported, or default server feature; reuse after edits remains open. |
| `reflaxe.ocaml` with `hxhx` | `[##--------]` about 20–25% | **Experimental integration.** The current OCaml wrapper still calls the independent Stage3 emitter, so the route does not yet prove that native `hxhx` uses standalone `reflaxe.ocaml`. | Use it for native compiler and host integration experiments. Keep upstream Haxe plus standalone `reflaxe.ocaml` as the practical target baseline. | `haxe_ocaml-38gsp.1` must hard-cut to the real standalone core without Stage3 semantic repair. `38gsp.2` must then prove two native generations with stage0 forbidden. Full1 and product evidence remain separate gates. |
| `reflaxe.ocaml` as a native `hxhx` plugin | `[###-------]` about 25–30% | **Experimental promotion path.** Loader, registry, manifest, plugin-safe output, and scoped same-candidate route proofs exist. The current artifact still packages a Stage3 backend provider rather than the standalone target core. | Use the promotion workflow as loader/ABI evidence, not as the final native target product. | Complete `38gsp.1`, then `38gsp.2`; prove exact typed OCaml dependencies, lifecycle cleanup, target-core identity, evaluated/native equivalence, and phase-separated speed. |
| One native Reflaxe target core for stock Haxe and `hxhx` | `[#---------]` about 5–10% | **Reviewed planning contract only.** Stock Haxe has an exact-version eval-plugin seam and `hxhx` has an experimental native loader, but no supported shared semantic ABI/core exists. | Use the current host-specific lanes. Do not assume their `.cmxs`/`.cma` files are interchangeable. | M22 waits for Full1, `38gsp.1`, and `38gsp.2`. It must then prove exact stock profiles, typed capability parity, one semantic core through stock and `hxhx` shells plus builtin, lifecycle/reset safety, packaging/trust, and performance. A byte-identical container is an experiment, not the invariant. |
| `reflaxe.ocaml` as a builtin/native `hxhx` target | `[##--------]` about 15–20% | **Architecture proof.** The adapter shape exists, but the current builtin wrapper still delegates target semantics to Stage3 `EmitterStage`. | Use the promotion matrix to understand the intended plugin/builtin composition. Treat the current route as bootstrap and diagnostic evidence. | `38gsp.1` must establish the authentic target core. The builtin must then consume the same canonical request/service contract as the plugin; direct calls may optimize transport only. |
| `hxhx` as a MIT Haxe replacement | `[###-------]` about 25–30% | **Scoped replacement preview, not production-ready.** Stage0-forbidden Macro/JavaScript/Neko/plugin and macro/eval evidence exists for bounded lanes. The declared Full1 product still requires Haxe `4.3.7` suite and target compatibility, performance, and one candidate-bound release proof. | Use `hxhx` for scoped native lanes, experiments, and subprocess embedding where its documented surface matches your project. Read `docs/02-user-guide/compat/FULL1_TARGET_SCOPE.md`. | `haxe.ocaml-f1cl.3` and `.3.1` remain active; C++/Cppia and both HashLink forms are required. `haxe_ocaml-u6esu` still owns credible compiler performance evidence, and the aggregate release handoff remains a correct no-go. |
| `hxhx` as a hackable Haxe-in-Haxe compiler | `[####------]` about 35–40% | **Strong design intent with mixed implementation.** Package, phase, typed-body, request, and backend seams are real, while several very large mixed-purpose files and the Stage3 emitter still make routine changes harder than the north star. | Make changes through the focused package/test seams and preserve behavior-driven upstream-oracle coverage. | Retire duplicate Stage3 target semantics, keep extracting only real ownership boundaries, and continue the mega-file guard. A whole-compiler rewrite or speculative universal IR is not planned. |
| Pluggable Haxe customization and Haxe-family variants | `[#---------]` about 5–10% | **Architecture foundation only.** This is deliberately not an active supported product while baseline compatibility and one authentic target core are unfinished. | Use existing macro libraries, Reflaxe targets, and explicitly excluded experiments. Keep vanilla Haxe compatibility as the default. | Post-Full1 owners `haxe_ocaml-h5jta` and `.1` remain deferred. The future transform profile must stay separate from backend-target authority and reuse the same identity/packaging substrate. |
| Declared Full1 source/native target matrix | `[###-------]` about 30–40% | **Uneven target bring-up.** The required matrix is explicit and several lanes work, but the same-candidate aggregate is not green. | Use OCaml through standalone `reflaxe.ocaml`; treat other native/source targets per their individual scope and current evidence. | Matrix owners `haxe.ocaml-f1cl.3.1` and `.3.11` still require authentic per-target evidence. C++/Cppia and both HashLink forms remain blockers. JVM, Flash/SWF, and XML/JSON type descriptions are outside the first Full1 claim. |

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
the `hxhx` loader. M22 plans a shared semantic target ABI and core for stock
Haxe and `hxhx`; that future product must not require two target
implementations:

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
- `docs/01-getting-started/COMPILATION_SERVER.md`
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
semantic target ABI and run one Haxe-authored target core. Exact host shells may
differ only in preflight, loading, registration, schema conversion, lifecycle,
and error translation. A combined native container remains a measured
feasibility experiment. Current manifest-v1 artifacts predate that contract and
remain host-specific until the hard cutover is implemented.

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
