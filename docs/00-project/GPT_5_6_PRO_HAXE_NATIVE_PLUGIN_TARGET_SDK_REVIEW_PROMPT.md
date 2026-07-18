# GPT-5.6 Pro Haxe-Authored Native Plugin and Target SDK Review Prompt

Prepared: 2026-07-18

Owning architecture bead: `haxe_ocaml-h5jta.1`

Related owners:

- `haxe_ocaml-h5jta` - Stage4 customization and variation lifecycle
- `haxe_ocaml-bomhr` - M22 post-freeze Reflaxe backend/target SDK
- `haxe_ocaml-c4czv` - shared stock-Haxe/`hxhx` native target-plugin ABI
- `haxe_ocaml-9v1va` - first validated `reflaxe.ocaml` semantic-lowering plan
- `haxe_ocaml-850ii` - native developer-loop latency policy

Give this file to GPT-5.6 Pro with the exact review package. Treat this file as
the controlling prompt. Record the package SHA-256 and candidate commit in the
review response.

## Plain-language problem

We want Haxe developers to write serious compiler extensions in Haxe and ship
them as efficient native OCaml artifacts through `reflaxe.ocaml`.

There are two related products:

1. A Haxe-authored compiler-transform plugin that can load in stock Haxe 4.3.7
   and `hxhx`, participate in the supported macro/hook lifecycle, inspect typed
   programs, report diagnostics, and perform validated typed-body rewrites.
2. A Haxe-authored Reflaxe compiler/target that starts in the normal evaluated
   Reflaxe development lane, then promotes without a semantic rewrite to a
   stock-Haxe native activation, an `hxhx` native backend plugin, or a builtin
   `hxhx` target.

The desired developer experience should be substantially better than writing
and packaging a Haxe compiler plugin directly in OCaml. Advanced authors must
still have typed, explicit escape hatches for small handwritten OCaml modules.

The desired generated-code bar is also high: `reflaxe.ocaml` should emit OCaml
that an experienced OCaml developer would recognize as clear, idiomatic,
efficient code. Runtime modules, dynamic boxing, `Obj.magic`, and generic Haxe
scaffolding should appear only when source-language semantics actually require
them.

We need an independent architecture review before implementation. The risky
questions are typed-tree ownership, cross-host ABI representation, program
identity and revisioning, patch validation, macro/plugin phase ordering,
compiler-server reset behavior, OCaml dynlink compatibility, and the boundary
between compiler transforms and target backends.

## Your role

Act as an independent principal compiler architect, OCaml runtime/ABI reviewer,
Haxe macro/plugin expert, developer-tooling designer, and parity-evidence
reviewer.

Inspect the supplied focused repository sources, Beads records, current plans,
official Haxe 4.3.7 plugin evidence, the local Coro source, and the sibling
Reflaxe compiler summaries. Challenge the local plan instead of merely
approving it.

This is an architecture review. Do not provide implementation code for direct
transcription. Return a seam recommendation, explicit invariants, rejected
shortcuts, staged migration, developer workflow, and validation plan in
beginner-readable language.

## Decisions requested

### 1. Validate or replace the two-profile split

The local recommendation uses two separately versioned semantic profiles over
one shared native artifact/tooling substrate:

- `compiler-transform/v1`: Stage4/macro lifecycle, typed snapshots, diagnostics,
  and validated rewrite operations before optimization/backend freeze;
- `backend-target/v1`: M22 frozen backend program/facts, target emission, build
  plans, and backend diagnostics.

Decide whether this is the correct ownership model. If not, provide a safer
model that still avoids a mutable general compiler context and semantic
duplication in every host.

### 2. Define honest stock-Haxe 4.3.7 integration

Stock Haxe 4.3.7 provides native eval-VM plugin loading through
`eval.vm.Context.loadPlugin` and macro hooks such as `Context.onAfterTyping`.
Its target/platform dispatch is closed; it does not expose a stable dynamic
target registration API.

Decide how each product should activate in stock Haxe:

- compiler-transform plugin through the official native plugin/macro lifecycle;
- Reflaxe target payload through the existing Reflaxe macro/eval integration,
  without falsely claiming a newly registered native platform.

Identify any necessary upstream host patch, adapter, or packaging constraint
and distinguish supported product work from research.

### 3. Decide the cross-host ABI and payload boundary

The product goal is one semantic payload for stock Haxe and `hxhx`, with one
identical loadable binary attempted first on the reference toolchain. Stock
Haxe's own plugin API requires the same Haxe/OCaml build environment.

Review these possible boundaries:

- identical `.cmxs` against an intentionally shared ABI module set;
- small host `.cmxs` shells around one identical native shared library and C ABI;
- canonical serialized snapshots/requests over in-process function calls;
- an out-of-process worker using the same protocol, with dynlink as a later
  transport optimization;
- another design you can justify.

Specify what “same payload” and “ABI-compatible” must mean. Name the exact
experiment that decides whether different loader shells are justified. Loader
shells cannot contain plugin or target semantics.

### 4. Define a sound Coro-capable typed rewrite model

The local proposal sends a candidate-bound immutable typed snapshot with stable
semantic IDs and receives an all-or-nothing validated patch tied to the same
program revision.

Decide:

- whether a snapshot/patch model is sound for Coro-class transforms;
- the minimum identity model for modules, fields, declarations, locals,
  expressions, and semantic types;
- whether the plugin returns typed nodes, a typed transformation plan, an
  untyped/macro AST that the host retypes, or another representation;
- how generated locals, closures, state machines, declaration references,
  metadata, and source positions are represented;
- which transformations require host services;
- which validation happens before patch application;
- how partial failure is prevented;
- how program revisions and downstream invalidation work;
- how stock Haxe and `hxhx` can apply the same semantic transform despite
  different private compiler representations.

Do not assume that host object identity, traversal order, or source offsets are
stable semantic identities.

### 5. Define lifecycle and compiler-server semantics

Specify registration ordering, per-compilation plugin instances, reset, cache
scope, cancellation, timeout, crash recovery, and unloading/restart policy.

The design must prevent callbacks, typed handles, defines, classpaths, plugin
state, and transformed bodies from leaking into a later compiler-server
request. It should support both an isolated worker and an in-process fast path
without giving them different language behavior.

### 6. Review the example sequence

The proposed ladder is:

1. a Haxe-authored equivalent of the official Haxe example: greeting, position,
   and one explicitly scoped after-typing field-body rewrite in both hosts;
2. a real small Reflaxe target across evaluated, stock native activation,
   `hxhx` plugin, and `hxhx` builtin forms;
3. a bounded Coro seed with one suspension/resume state machine;
4. a Coro-class plugin admitting loops, closures, mutable captures,
   exceptions, nested control flow, side effects, and negative cases.

Decide whether each rung proves the right seam and which behavior must be added
before moving on. Identify any smaller fixture that would expose a fatal ABI or
lifecycle flaw earlier.

### 7. Design the best Haxe-first author workflow

The plan proposes one shared Haxe-authored SDK driver used by stock-Haxe and
`hxhx` entry points, with separate `compiler-plugin` and `target` command
families.

Review the desired workflow:

- init/scaffold;
- watch and incremental compile;
- build and link;
- inspect generated OCaml, ABI, runtime plan, and cache decisions;
- test both hosts and all declared activation forms;
- doctor/toolchain diagnosis;
- package, sign, install, upgrade, rollback, and publish;
- generate/check typed `.mli` boundaries for handwritten OCaml escape hatches.

Recommend the artifact layout, manifest ownership, cache keys, tiered test
loop, error messages, source mapping, and cold/warm/one-file performance
measurements. The normal inner loop must not rebuild all of `hxhx`, regenerate
bootstrap snapshots, or run broad repository guards.

### 8. Review idiomatic OCaml and runtime-quality gates

The current OCaml target has a structured `OcamlExpr` AST and printer, plus a
compiler-tracked runtime usage collector. It also has a roughly 7.7k-line
`OcamlBuilder` that still combines semantic analysis, representation choices,
runtime selection, and AST construction. `ERaw` is an explicit escape hatch.

Define objective gates for “experienced OCaml developer quality,” including:

- structured, formatted `.ml`/`.mli` output and readable names;
- warning policy;
- module/function/record/variant choices;
- allocation, boxing, refs, `Obj.magic`, exceptions, closure, and tail-call
  policy;
- runtime module selection and transitive dependency evidence;
- generated source and binary size;
- plugin load/startup and execution cost;
- shape snapshots and semantic runtime tests;
- precisely scoped comparisons with a direct handwritten OCaml equivalent.

Say which gates should block a supported plugin/target SDK and which should
remain report-only initially. Do not recommend a broad compiler IR merely
because sibling targets have one; require evidence from actual OCaml semantic
plans.

### 9. Extract the right lessons from sibling Reflaxe targets

The local audit covered:

- `haxe.elixir.codex`: deep target AST, builder, transformers, and printer, but
  several large concentrated modules;
- `haxe.rust`: AST-first emission, runtime austerity, warning/format quality,
  and strict target-native expectations, with a very large compiler module;
- `haxe.go`: small target AST/printer plus a large compiler and selective
  runtime/reporting policy;
- `haxe.ruby`: direct idiomatic output and a compact semantic runtime, again
  with concentrated compiler logic.

Identify principles that transfer to OCaml and language-specific techniques
that should not. Explicitly consider OCaml's managed memory, exceptions,
algebraic data types, modules, expression orientation, and runtime linking.

### 10. Return an implementation and evidence sequence

Recommend reviewable beads/commits from architecture freeze to supported
product proof. Name dependencies between shared tooling, transform ABI, target
ABI, examples, Coro, OCaml lowering quality, performance, docs, and release
claims.

For every phase, state:

- user-visible outcome;
- owning compiler layer;
- invariants introduced;
- narrow test/evidence first;
- broad evidence later;
- stop/redesign condition;
- deliberately deferred scope.

## Non-negotiable constraints

- Upstream Haxe 4.3.7 is the baseline behavior and lifecycle oracle, not an
  implementation donor.
- Do not copy, translate, mechanically rewrite, or retype upstream Haxe
  compiler source.
- Do not vendor upstream Haxe compiler tests. Run them from ignored checkouts
  and add repo-owned focused fixtures.
- Selective reuse of permissively licensed upstream Haxe standard-library code
  follows the repository provenance policy; do not conflate it with compiler
  source.
- Shipping code and dependencies remain MIT-compatible.
- `../Coro` is MIT-licensed. A derived port must retain required notice and
  source provenance; it cannot smuggle upstream compiler implementation code.
- Baseline `hxhx` remains Haxe 4.3.7-compatible by default. Plugins are explicit,
  removable, auditable, and excluded from baseline evidence when active.
- Use the hard-cutover policy. Do not preserve an ambiguous old plugin CLI or
  permanent ABI v1/v2 compatibility dispatch.
- Compiler transforms belong to Stage4/customization. Backend target work
  belongs to M22 only after the backend program is frozen.
- Reflaxe APIs do not become parser, resolver, typer, module-graph, macro
  lifecycle, or baseline-diagnostic owners.
- No raw mutable compiler context, private compiler object, hidden global, or
  host object identity crosses the supported ABI.
- No semantic fork between stock Haxe and `hxhx`.
- Missing required capabilities fail before plugin semantics execute.
- Native plugins are trusted code; the ABI is not a security sandbox.
- Avoid mega-file gravity. New independently testable logic goes in focused
  modules, not `OcamlBuilder` or orchestration mega-files.
- Do not claim native, idiomatic, fast, cross-host, or supported from build
  success alone. Evidence must validate behavior and exact artifacts.
- Do not increase README/North Star readiness for planning, scaffolding, or toy
  examples.

## Focused evidence in the package

The review package should include:

- this controlling prompt and the proposed SDK plan;
- M22 plan and customization/Stage4 boundary docs;
- current host-adapter and promotion guides;
- official Haxe 4.3.7 plugin example and `eval.vm.Context.loadPlugin`
  declaration as review-only external evidence;
- `../Coro` README, Haxe loader, native plugin source, license, and focused test
  inventory as review-only external evidence;
- current `reflaxe.ocaml` target AST, printer, runtime usage collector, selected
  builder seams, runtime/profile docs, and performance baseline;
- current `hxhx` macro/backend plugin host and manifest seams;
- selected sibling Reflaxe AST/compiler/printer policies and a source-size
  inventory;
- relevant Beads records and an evidence summary;
- file manifest and SHA-256 checksums.

The archive is intentionally focused rather than a complete repository. Mark
any repository-wide conclusion that depends on supplied inventories rather
than direct inspection.

## Required response format

Return:

1. verdict and corrected architecture;
2. shared substrate versus profile-specific responsibilities;
3. stock-Haxe and `hxhx` activation model;
4. ABI/payload/loader-shell recommendation;
5. typed snapshot, patch, revision, and lifecycle model;
6. example and Coro migration ladder;
7. developer workflow and packaging plan;
8. idiomatic OCaml/runtime quality contract;
9. transferable sibling-target lessons;
10. rejected alternatives;
11. semantic, ABI, lifecycle, provenance, and performance invariants;
12. deterministic failure behavior;
13. bead/commit sequence;
14. validation matrix;
15. explicit stop conditions;
16. human product decisions, if any.

Do not provide implementation code for direct transcription.
