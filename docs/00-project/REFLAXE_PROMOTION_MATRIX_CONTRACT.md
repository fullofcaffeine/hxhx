# Reflaxe Promotion Matrix Contract

Last audited: 2026-07-03

This page is the canonical contract for building Reflaxe compilers to native OCaml through `reflaxe.ocaml`.

It is deliberately separate from:

- `docs/00-project/REFLAXE_OCAML_1_0_CONTRACT.md`
  - standalone target-product readiness
- `docs/00-project/FULL_1_0_CONTRACT.md`
  - strict `hxhx` compiler-equivalence claim

## Goal

The promotion matrix exists to prove which host/runtime paths are officially supported when a Reflaxe compiler is built through `reflaxe.ocaml`.

The goal is not only packaging viability. The long-term bar is that compiler or
backend logic authored in Haxe can be promoted through `reflaxe.ocaml` into a
native artifact that is competitive with direct OCaml compiler code, while
preserving the Haxe-first authoring workflow that makes Reflaxe targets easy to
prototype and maintain. For `hxhx`, this means the Haxe-authored compiler can
use `reflaxe.ocaml` for native compilation/bootstrap artifacts; it does not mean
`hxhx` itself is authored in Reflaxe. Reflaxe-specific target/plugin APIs should
remain a seam, not a hidden dependency of the compiler core, unless a future
architecture bead deliberately changes that boundary.

The accepted Oracle checkpoint for this boundary is
`docs/00-project/ORACLE_CHECKPOINT_REFLAXE_HXHX_FRAMEWORK_BOUNDARY_2026_07_03.md`.
Promotion evidence should therefore stay focused on native plugin/builtin
artifacts, target-core reuse, activation parity, and native artifact latency;
it should not imply Reflaxe owns `hxhx` compiler-core semantics.

The supported paths are:

1. `haxe + reflaxe.ocaml -> plugin`
2. `hxhx + reflaxe.ocaml -> built-in target`
3. `hxhx + reflaxe.ocaml -> plugin`

This contract owns:

- the terminology for those paths,
- the proof workloads,
- the evidence markers,
- and the performance/operational tradeoff document that tells users which path to choose.

## Ownership boundary

This contract owns:

- multi-host promotion proofs for real Reflaxe compiler workloads,
- the host/path comparison,
- canonical recommendation docs for choosing between promotion paths.

This contract does not own:

- standalone `reflaxe.ocaml` target-product readiness
- strict `hxhx Full 1.0` equivalence claims
- pretending all hosts share one binary ABI
- adding semantics that upstream `haxe 4.3.7` does not support

## Canonical terms

### `haxe + reflaxe.ocaml -> plugin`

- Host compiler: upstream `haxe 4.3.7`
- `reflaxe.ocaml` role: build the compiler artifact through the supported upstream host-adapter/plugin path
- Output expectation: a plugin-capable artifact produced through the documented upstream-host path

### `hxhx + reflaxe.ocaml -> built-in target`

- Host compiler: `hxhx`
- `reflaxe.ocaml` role: built-in target path inside `hxhx`
- Output expectation: the resulting compiler logic is shipped through the built-in target mode, not as a runtime dynlink plugin

### `hxhx + reflaxe.ocaml -> plugin`

- Host compiler: `hxhx`
- `reflaxe.ocaml` role: part of the build chain for a runtime-loadable plugin path
- Output expectation: plugin artifact plus manifest, loaded through the supported `hxhx` host path

## Built-in vs plugin

| Mode | Meaning | Primary upside | Primary cost |
| --- | --- | --- | --- |
| Built-in | Target/compiler logic ships inside the `hxhx` binary or distribution build | Simpler runtime deployment, lower dynlink/ABI exposure | Requires tighter repo/distribution coupling |
| Plugin | Target/compiler logic ships as a runtime-loaded artifact plus manifest | Better iteration and external distribution | More ABI/toolchain/runtime-host coupling |

## Proof workload policy

The promotion matrix must be proven with at least one real Reflaxe compiler workload.

Current pressure-test workload:

- `reflaxe.elixir`

Rules:

- sibling repos are pressure tests, not semantics authorities
- upstream `haxe 4.3.7` remains the semantics authority
- a path is not considered proven just because a toy example works
- a path is not considered production-ready just because a single manual session succeeded once

## Required evidence

Required per-path markers:

- `RPMX_HAXE_PLUGIN:PASS`
- `RPMX_HXHX_BUILTIN:PASS`
- `RPMX_HXHX_PLUGIN:PASS`

Required aggregate marker:

- `RO_PROMOTION_MATRIX:PASS`

The aggregate marker is valid only when:

1. the matrix contract is explicit,
2. all supported path proofs are green for the chosen workload family,
3. the performance/operational comparison exists,
4. the recommendation doc exists.

## Required comparison dimensions

The matrix is not complete without a decision document.

The comparison must cover:

- startup cost
- steady-state compile throughput
- native build/runtime cost where relevant
- comparison against a direct OCaml/native baseline where one is meaningful
- debugging ergonomics
- deployment complexity
- host coupling
- plugin/binary ABI exposure
- when to choose each path

## Host-adapter references

Implementation-level references live here:

- beginner guide:
  - `docs/01-getting-started/PROMOTE_REFLAXE_TO_NATIVE.md`
- reflaxe.elixir native-path decision:
  - `docs/00-project/REFLAXE_ELIXIR_NATIVE_PATH_DECISION.md`
- upstream-Haxe decision boundary:
  - `docs/00-project/REFLAXE_OCAML_UPSTREAM_PLUGIN_INTEGRATION_DECISION.md`
- host-adapter ABI/layout:
  - `docs/02-user-guide/HXHX_PROMOTION_HOST_ADAPTERS.md`
- plugin system behavior:
  - `docs/02-user-guide/COMPILER_PLUGIN_SYSTEM.md`
- backend layering / builtin backends:
  - `docs/02-user-guide/HXHX_BACKEND_LAYERING.md`
  - `docs/02-user-guide/HXHX_BUILTIN_BACKENDS.md`

This contract sits above those docs and decides what must be proven, not how every adapter is implemented.

## Non-goals

These are explicitly out of scope for this contract:

- shared cross-host binary compatibility for one artifact
- supporting every possible Reflaxe compiler before proving one real workload
- redefining `reflaxe.ocaml` standalone target readiness
- redefining `hxhx` Full 1.0 release criteria
- undocumented host permutations

## Recommendation rule

The public recommendation doc must end with a concrete default, not a neutral catalog.

It must say:

- which path is the default for performance-sensitive users,
- which path is the default for lowest operational complexity,
- and when users should switch from one path to another.

If the data is not strong enough to make that recommendation, the matrix is not done.
