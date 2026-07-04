# North-Star Goals

This page records the long-term product direction for this repository. It is a planning contract, not a release claim.

The short version:

1. Make `reflaxe.ocaml` a stable OCaml target that works well with both upstream Haxe and `hxhx`.
2. Make `hxhx` a stable, MIT-licensed Haxe-in-Haxe compiler that is 1:1 compatible with Haxe `4.3.7`, or better where compatibility allows, including compiler performance and developer iteration speed.
3. Make Haxe easier to hack by implementing the compiler in Haxe: the compiler should be readable, editable, testable, and approachable to Haxe developers.
4. Make Haxe easy to bend without breaking Haxe: extensions should be pluggable, removable, and isolated from the baseline compiler contract.
5. Make it practical to create full Haxe-family compiler variations in Haxe when a project needs a real fork or dialect.
6. Make Reflaxe compilers easy to prototype as Reflaxe targets and then promote into native plugin or builtin target forms for upstream Haxe and/or `hxhx`.

## Goal 1: Stable `reflaxe.ocaml`

`reflaxe.ocaml` should be usable as a production OCaml target from two host paths:

- upstream Haxe `4.3.7` plus `-lib reflaxe.ocaml`, and
- `hxhx` native lanes once the relevant `hxhx` compatibility evidence is green.

Current planning owners:

- standalone upstream-Haxe product readiness: `haxe.ocaml-ro10`
- `hxhx + reflaxe.ocaml` production-route status: `haxe.ocaml-n5ae`
- public status board: README `Goals status` table

## Public Progress Tracking

The README `Goals status` table is the public progress board. Its ASCII bars
are coarse production-readiness indicators, not exact completion percentages.

Update the bars only when evidence changes readiness for an intended use case:

- a bead closes or opens a material release/compatibility gap,
- a local or CI gate changes the production-readiness picture,
- a release-contract document changes,
- or a user-facing workflow becomes more or less suitable for real projects.

If a checkpoint advances an internal burn-down blocker but does not change a
user-facing readiness claim, keep the bars unchanged and record that decision in
the relevant bead/checkpoint note.

## Goal 2: Stable `hxhx` parity

`hxhx` should become a practical drop-in equivalent to upstream Haxe `4.3.7` while staying MIT-compatible and clean-room in implementation.

The bar is not “passes our local smoke tests.” The bar is upstream-derived behavioral evidence:

- upstream suite gates for the declared compatibility scope,
- macro and plugin parity,
- no required stage0 fallback for correctness,
- performance parity or better for compiler workloads,
- materially faster edit-compile-test loops once `hxhx + reflaxe.ocaml` is native and stage0-free by default,
- faster Reflaxe-compiler promotion loops once stable Reflaxe targets can be compiled to native OCaml-backed plugin/builtin artifacts instead of repeatedly paying the full stage0/delegated path,
- release enforcement that blocks misleading public `1.0` claims.

Current planning owners:

- Full 1.0 closure: `haxe.ocaml-f1cl`
- native iteration latency/perf metric: `haxe.ocaml-5rjl`
- native iteration latency measurement contract:
  `docs/00-project/NATIVE_ITERATION_LATENCY_CONTRACT.md`
- strict upstream target gates: `haxe.ocaml-f1cl.3`, `haxe.ocaml-f1cl.3.1`, `haxe.ocaml-blsl`, `haxe.ocaml-sssk`
- Full 1.0 release go/no-go: `docs/00-project/FULL1_RELEASE_GO_NO_GO.md`
  (`haxe.ocaml-f1cl.6`)
- release enforcement: `scripts/release/full1-release-enforcement.js`
  (`haxe.ocaml-f1cl.7`)

Cpp Gate3 execution checkpoint:

- Strict Cpp Gate3 remains the active source/native target blocker.
- Bounded, non-semantic Cpp render/cache/inference optimizations may
  continue when they have focused smoke evidence and strict timing validation.
- New broad stdlib/runtime semantics must not be added directly to the Cpp
  emitter path or unclassified runtime support without a helper
  reachability/body-rendering policy, runtime-helper invariants, and
  behavior-oracle evidence where applicable.
- Internal Cpp frontier movement does not change README/North Star
  production-readiness bars until strict gates and public usability evidence
  change.

Iteration-speed note:

- Today, small compiler fixes can still pay heavy validation costs: stage0-based bootstrap regeneration, dune verification of large generated snapshots, repo-wide format checks, and aggregated guard scripts.
- The native `hxhx + reflaxe.ocaml` path should reduce the expensive stage0/reflaxe bootstrap loop over time, but full upstream-derived gates will remain heavier by design.
- Fully native Reflaxe compiler artifacts should make the normal "edit target -> build native plugin/builtin -> run focused smoke" loop faster than the current delegated bootstrap path. Do not assume this automatically: measure it separately from target-language compile time and from full upstream oracle gates.
- Treat latency as a product quality metric: measure focused local loops, snapshot regeneration, stage0-free rebuilds, native Reflaxe artifact loops, and Full 1.0 gates separately so "faster" is evidence-based rather than vibes-based.
- The machine-checked contract for those buckets is
  `docs/00-project/NATIVE_ITERATION_LATENCY_CONTRACT.md`.

## Goal 3: Hackable Haxe-in-Haxe compiler

One reason to build `hxhx` in Haxe is to make Haxe itself easier to understand and change.

The compiler should feel like a Haxe project, not a sealed artifact:

- compiler concepts should be documented in Haxe-facing terms,
- implementation seams should be small enough to edit without spelunking giant files,
- tests should make behavior changes safe to attempt,
- contributors should be able to prototype compiler changes without learning the upstream OCaml implementation first,
- architectural choices should optimize for clarity and maintainability as well as parity.

This does not weaken compatibility. The default compiler still has to behave like Haxe `4.3.7`; hackability is how we make that behavior easier to evolve and verify.

Current planning owners:

- Full 1.0 parity and release contract: `haxe.ocaml-f1cl`
- modular customization and variation architecture: `haxe.ocaml-vary`
- customization and variation architecture note:
  `docs/00-project/HXHX_CUSTOMIZATION_AND_VARIATION_ARCHITECTURE.md`
- mega-file gravity watch: `docs/00-project/MEGA_FILE_GRAVITY_WATCH.md`

## Goal 4: Pluggable compiler customization

We want a supported way to bend Haxe to project needs without turning baseline `hxhx` into an unreviewable fork.

The preferred model is:

- baseline `hxhx` stays Haxe-compatible by default,
- extensions are explicit and removable,
- extension hooks are stable enough for real users,
- plugin behavior is auditable in CI,
- custom behavior cannot silently weaken Haxe `4.3.7` compatibility claims.

Candidate mechanisms include compiler plugins, native target plugins, macro/runtime hooks, and explicit feature-gated extension points. The exact API surface should be designed under a dedicated architecture bead before being promoted as a public platform.

Current planning owner:

- modular compiler customization and dialect architecture: `haxe.ocaml-vary`
- architecture note:
  `docs/00-project/HXHX_CUSTOMIZATION_AND_VARIATION_ARCHITECTURE.md`

## Goal 5: Haxe-family compiler variations

Sometimes a project needs more than a plugin: it may need a custom Haxe-family language, policy set, target bundle, or distribution.

The repo should make that practical in Haxe by keeping the compiler understandable and modular:

- frontend, typer, macro host, backend, and target-runtime boundaries should be separable,
- variation points should be explicit instead of accidental edits to large files,
- forks/dialects should be able to reuse the baseline compiler while making intentional differences visible,
- the default `hxhx` release must remain Haxe-compatible unless a variation is explicitly selected.

This is related to plugin extensibility, but not identical: plugins should cover pluggable changes; compiler variations cover deliberate alternate compiler products.

Current planning owner:

- modular compiler customization and dialect architecture: `haxe.ocaml-vary`
- architecture note:
  `docs/00-project/HXHX_CUSTOMIZATION_AND_VARIATION_ARCHITECTURE.md`

## Goal 6: Reflaxe-to-native promotion

Reflaxe should stay the fast prototyping layer for compiler targets. Once a target is stable, there should be a clear path to promote it into native forms:

- an upstream Haxe plugin or host-adapter path where supported,
- an `hxhx` native plugin path,
- an `hxhx` builtin target path,
- eventually a reusable target core that can be packaged in more than one host shape without rewriting the backend.

The product bet is Haxe-first compiler authoring with native deployment. A
target author should be able to write compiler/backend logic in Haxe, keep the
tooling approachable to Haxe developers, and promote that logic through
`reflaxe.ocaml` into an OCaml-backed native artifact instead of rewriting the
compiler by hand in OCaml. `hxhx` follows the same Haxe-first principle: it is
not authored in Reflaxe, but its Haxe sources should be able to leverage
`reflaxe.ocaml` for native compilation and bootstrap loops. The shorthand is
"create `hxhx` with Reflaxe," not "author `hxhx` in Reflaxe": Reflaxe-specific
APIs belong naturally at target/backend/plugin seams unless an explicit
architecture decision moves them into compiler-core code.

There are three distinct levels of Reflaxe usage for `hxhx`:

- compile the ordinary Haxe-authored `hxhx` sources through `reflaxe.ocaml`
  into native artifacts; this is a desired bootstrap/native-compilation route,
- host or implement `hxhx` target backends/plugins with Reflaxe-style APIs;
  this is a natural extension point when it preserves the baseline Haxe
  contract,
- build the compiler core itself around the Reflaxe framework; this is possible
  as research, but not the default architecture because Reflaxe normally assumes
  a compiler has already parsed, typed, and exposed the Haxe AST.

The 2026-07-03 Oracle checkpoint accepted this boundary. Treat deeper
Reflaxe-shaped compiler-core work as quarantined research until a dedicated
architecture bead proves typed-AST ownership, macro/plugin lifecycle, bootstrap,
parity, and performance risks are controlled:
`docs/00-project/ORACLE_CHECKPOINT_REFLAXE_HXHX_FRAMEWORK_BOUNDARY_2026_07_03.md`.

The performance bar is intentionally ambitious:

- promoted Haxe-authored compiler artifacts should beat the delegated/stage0
  prototype loop for normal compiler and target-development work,
- where a direct OCaml implementation is a meaningful comparison, promoted
  artifacts should aim for the same performance class or better,
- `hxhx` and Reflaxe optimization work should be allowed to make generated
  compiler artifacts faster than a straightforward hand-written implementation
  when specialization or whole-pipeline knowledge makes that possible,
- and any "native is fast" recommendation must be backed by measured artifact
  build, load, compile, and focused-smoke timings rather than assumed from the
  packaging mode.

Current planning owners:

- promotion matrix: `haxe.ocaml-rpmx`
- Full 1.0 plugin parity inside `hxhx`: `haxe.ocaml-f1cl.8`
- native plugin hardening: `haxe.ocaml-anoy`
- native Reflaxe artifact-loop latency:
  `docs/00-project/NATIVE_ITERATION_LATENCY_CONTRACT.md`

## Operating Rule

When a task changes compatibility scope, plugin architecture, target promotion, release claims, or production-readiness wording, update this page or explicitly record why it remains unchanged. Keep the README `Goals status` table aligned with this document, but keep the README focused on what users can do today.
