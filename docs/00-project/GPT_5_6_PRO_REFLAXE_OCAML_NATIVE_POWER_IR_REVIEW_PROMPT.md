# GPT-5.6 Pro `reflaxe.ocaml` Native Power And Target-Lowering Review

Prepared: 2026-07-18

Owning architecture bead: `haxe_ocaml-1cixm`

Related owners:

- `haxe_ocaml-9v1va` - first validated semantic-lowering extraction;
- `haxe_ocaml-s7jry` - standalone `reflaxe.ocaml` product;
- `haxe_ocaml-bomhr` - native Reflaxe target/plugin promotion;
- `haxe_ocaml-h5jta.1` - Haxe-authored compiler-transform and target SDK;
- `haxe_ocaml-850ii` - native compiler-development latency evidence.

Give this file to GPT-5.6 Pro with the exact review archive. Treat this file as
the controlling prompt. Record the package SHA-256, candidate commit, and
reference commits in the response.

## Plain-Language Problem

`reflaxe.ocaml` should let a Haxe developer build serious OCaml applications,
compiler components, Reflaxe targets, and native plugins with the practical
power they would have when writing OCaml directly. Haxe should provide the
normal productive authoring language and tooling. When Haxe cannot express an
OCaml feature faithfully, the system should offer a typed, explicit escape
hatch instead of forcing an unsafe compiler trick or a rewrite of the whole
project in OCaml.

The desired authoring ladder is:

1. ordinary Haxe and the Haxe standard library;
2. direct, idiomatic OCaml lowering when semantics agree;
3. typed `ocaml.*` facades for target-specific APIs;
4. Haxe-friendly wrappers over those exact facades;
5. generated or handwritten bindings for external OCaml libraries;
6. small `.ml`/`.mli` adapters for features Haxe cannot model;
7. raw target injection only as a scoped, documented last resort.

The generated OCaml should be efficient, readable, and idiomatic enough that
an experienced OCaml developer would recognize the implementation choices.
Compatibility runtime code should appear only when Haxe semantics genuinely
need it. `Obj.magic`, dynamic boxes, wrapper objects, allocation, and generic
runtime calls must be explicit, explainable costs rather than the default
translation strategy.

The architecture question is not simply “should a compiler have an IR?” The
repository already has a structured `OcamlExpr` target-syntax AST. The open
question is whether correctness and code quality need:

- focused immutable semantic plans before that AST;
- a typed OCaml-specific target-lowering tree;
- a broader program/CFG IR similar in scope to `haxe.c`;
- an extension of `OcamlExpr` itself;
- or another boundary.

We need an independent decision before implementation.

## Your Role

Act as an independent principal compiler architect, OCaml compiler/runtime and
library expert, Haxe/Reflaxe target expert, FFI/ABI designer, generated-code
quality reviewer, and developer-tooling designer.

Inspect the full committed repository snapshot, the local architecture audit,
the relevant Beads records, and every supplied reference Repomix. Challenge the
local hypothesis instead of merely approving it. Distinguish facts visible in
the candidate from inferences and future product goals.

This is a design review. Do not provide implementation code for direct
transcription. Return ownership boundaries, data-model guidance, invariants,
rejected shortcuts, staged migration, and validation criteria in
beginner-readable language.

## Current Candidate Facts To Verify

The local audit reports:

- `OcamlBuilder.hx` is approximately 7,688 lines and currently combines
  typed-expression traversal, evaluation scheduling, mutation analysis,
  representation/coercion, intrinsic/runtime selection, native interop, and
  `OcamlExpr` construction;
- `OcamlCompiler.hx` is approximately 3,555 lines and also owns class/object
  layout, target type mapping, statics, dispatch, default representations,
  output/build assembly, and runtime collection;
- `OcamlExpr` is a structured 116-line OCaml expression tree with a separate
  printer and an explicit `ERaw` node;
- most `OcamlExpr` nodes do not retain the Haxe semantic type, stable identity,
  representation choice, value/place distinction, evaluation schedule, call
  kind, runtime reason, or justification for `Obj.magic`/boxing/wrappers;
- runtime inference currently walks the completed target AST for referenced
  `Hx*` module names, then computes a transitive runtime-source closure;
- raw expressions are opaque to that collector, with token scanning retained
  only as a debug fallback;
- selected `ocaml.*` standard-library facades, `@:native`, and
  `@:ocamlLabel` exist;
- the full `.mli` binding/import/export, external dune/opam dependency,
  handwritten adapter, and stable generated-library ABI workflows are not yet
  complete product contracts;
- the repository has a Reflaxe/upstream-Haxe backend route and a separate
  native `hxhx` OCaml route, so semantic convergence is still an architectural
  requirement;
- `portable` and `metal` are existing runtime/representation profiles, not
  synonyms for “Haxe-only” and “arbitrary OCaml”;
- `@:ocamlAllowRaw` is a proposed portable authority policy and must never
  bypass strict `metal` or `@:haxeMetal` rejection.

Correct any inaccurate inventory before using it as a premise.

## Desired Capability Contract To Review

Interpret “the same power as direct OCaml” as practical capability, not false
language equivalence:

- normal Haxe authors should not need OCaml syntax for supported Haxe and
  standard-library behavior;
- target authors should have typed access to OCaml modules, functions,
  labelled/optional arguments, records, variants, exceptions, refs, collections,
  callbacks, and other representable facilities;
- external OCaml packages should be usable through reproducible typed bindings
  and deterministic dune/opam ownership;
- features Haxe cannot faithfully express—possibly advanced module/functor,
  GADT, locally abstract type, first-class module, polymorphic-variant, phantom
  type, or unusual ABI surfaces—should be accessible through a small typed
  adapter boundary;
- Haxe-authored code intended for OCaml callers should be exportable through a
  stable `.mli` surface that does not expose private generated representations;
- the compiler should select a compatibility runtime only for Haxe behavior
  that direct OCaml constructs cannot preserve;
- the normal developer workflow should support fast edit/build/test/inspect,
  not require a full `hxhx` bootstrap or broad repository gate on each change.

Decide whether this is the right product contract. Identify any part that is
impossible, misleading, or should be explicitly scoped.

## Decisions Requested

### 1. Define “Direct-OCaml Capability” Precisely

Provide a capability contract that can be tested and documented without
claiming that Haxe has OCaml's type system.

Decide:

- what ordinary application authors can expect;
- what target/compiler/plugin authors can expect;
- which OCaml features can have exact typed Haxe representations;
- which require generated bindings or handwritten adapters;
- which cannot safely cross the boundary and need deterministic diagnostics;
- whether any supported lane may require raw target code;
- what evidence is required before saying the target provides the practical
  power of direct OCaml.

Give concrete examples of capability categories, but do not write code for
transcription.

### 2. Define The Escape-Hatch Ladder

Review and correct this proposed order:

1. compiler-owned direct/intrinsic lowering for ordinary Haxe semantics;
2. typed one-to-one `ocaml.*` facade;
3. Haxe-friendly semantic wrapper over that facade;
4. generated binding from an OCaml `.mli` or another typed manifest;
5. handwritten `.ml`/`.mli` adapter plus a typed Haxe extern;
6. narrowly scoped raw injection only when every typed option is inadequate.

For each level, specify:

- who owns type checking;
- what metadata or manifest is required;
- how source maps and diagnostics work;
- how dependencies and source files enter dune builds;
- how profile portability is reported;
- what makes the boundary stable or intentionally unstable;
- what negative tests prevent a lower-level escape hatch from becoming the
  default API.

Compare this with the supplied committed `haxe.rust` interop, extra-source,
Cargo, representation, runtime-reason, and raw-authority designs. Transfer only
principles that fit OCaml.

### 3. Separate The Library And Runtime Layers

Define non-overlapping ownership for:

- normal Haxe standard-library APIs and semantics;
- target-specific `ocaml.*` standard-library facades;
- Haxe-friendly wrappers for common OCaml facilities;
- external OCaml package bindings;
- handwritten OCaml adapters;
- internal Haxe-compatibility runtime modules;
- OCaml-facing libraries exported from Haxe-authored code.

Decide how each layer is versioned, documented, tested, packaged, and selected.
Explain how the compiler can lower Haxe standard-library calls directly to
OCaml without conflating those calls with the public `ocaml.*` facade.

The runtime must not become a general foreign-library bucket, and a foreign
library must not be mistaken for Haxe runtime support.

### 4. Decide What `OcamlExpr` Is And Is Not

Answer explicitly:

- Is `OcamlExpr` already sufficient as the only target IR if the builder is
  modularized and validated?
- Should semantic annotations be added to `OcamlExpr`, or would that corrupt a
  clean target-syntax boundary?
- Should immutable plans exist beside `OcamlExpr`?
- Should there be a typed `OcamlLoweredExpr`/program layer between Haxe typed
  input and target syntax?
- Is a broader block/CFG representation justified for any OCaml semantics, or
  would expression-oriented OCaml make it needless?
- Which information must survive until syntax construction, and which should
  be consumed and erased earlier?
- Where should a validator run, and what exactly should it reject?

Do not answer by terminology alone. Tie the recommendation to concrete
compiler responsibilities and consumers.

### 5. Choose Among The Architecture Directions

Evaluate at least these directions:

**Direction A — direct builder modularization**

Keep `TypedExpr -> OcamlExpr`, extract focused helpers, and add local assertions.

**Direction B — narrow immutable semantic plans**

Keep `OcamlExpr`, but select and validate representation, places/evaluation,
calls, runtime reasons, and/or ABI boundaries in separately owned plans before
constructing syntax.

**Direction C — typed OCaml target-lowering tree**

Introduce a structurally recursive OCaml-specific semantic tree carrying the
facts needed across those decisions, then lower it mechanically to
`OcamlExpr`.

**Direction D — broad OCaml program/CFG IR**

Adopt a target-owned program representation with blocks, values, places,
terminators, effects, and validation comparable in scope to `haxe.c`'s HxcIR.

**Direction E — shared cross-target or host-neutral IR**

Reuse or expand the `hxhx` backend/plugin program so OCaml-specific
representation and evaluation decisions live in a generalized compiler IR.

You may recommend a hybrid or another direction. State the immediate choice,
the migration path, and the measured evidence threshold for escalating to a
broader representation later.

The local hypothesis favors Direction B as the first extraction and permits
Direction C only when implemented plans prove shared identities/invariants are
needed. It rejects Direction D as an assumption copied from C and Direction E
as a conflation of host ABI with target lowering. Challenge that hypothesis.

### 6. Compare `haxe.c` Without Copying Its Product Assumptions

The supplied committed `haxe.c` snapshot has a broad validated `HxcIR` because
C requires explicit answers for evaluation order, values versus places,
conversions, allocation/lifetimes, cleanup/failure edges, control flow, layout,
dispatch, and ABI.

Identify:

- which of those responsibilities also require an explicit OCaml lowering
  artifact;
- which OCaml already provides safely;
- which Haxe-to-OCaml gaps are different rather than smaller;
- whether exceptions, early exits, mutation, captured variables, dynamic
  values, OO dispatch, or exported ABIs require block-level normalization;
- which HxcIR invariants transfer as principles;
- which would add accidental C-shaped complexity.

Do not propose a line-for-line or concept-for-concept adaptation.

### 7. Define The Minimum Sound Semantic Model

Without providing implementation code, describe the minimum records, identities,
and relationships required by your recommended direction.

Consider:

- stable source declaration, local, expression, and target-symbol identity;
- Haxe semantic type versus selected OCaml carrier type;
- representation kind and reason;
- nullability, identity, aliasing, mutation, capture, and escape facts;
- value versus assignable place;
- ordered receiver/index/argument evaluation and temporary sharing;
- direct, closure, dynamic, intrinsic, runtime, extern, and adapter calls;
- conversions and coercions;
- runtime capability reasons and transitive dependencies;
- native library/package/source ownership;
- exported interface representation versus internal representation;
- source spans and diagnostics;
- program revision or cache identity when used through `hxhx` plugins.

State which facts are program-wide, per type, per declaration, per function,
per node, or transient. State which facts must never reach the printer.

### 8. Resolve Mutation And Evaluation Semantics

Review the current concentration of ref-local detection, captured mutation,
lvalue classification, temporary insertion, assignment coercion, and
expression-versus-statement control in `OcamlBuilder`.

Recommend:

- whether a reusable place model is needed;
- how locals, fields, statics, properties, arrays, and future abstract access
  are represented;
- when receivers and indexes are repeated versus shared;
- how Haxe-observable evaluation order is proved;
- how mutable captures map to OCaml refs or another carrier;
- where return/break/continue/throw and expression-valued control flow are
  normalized;
- whether the answer is a local lowering plan, structural expression tree, or
  blocks/CFG.

Do not permit the printer or a target-library helper to invent these semantics.

### 9. Resolve Representation, `Dynamic`, Null, And `Obj.magic`

Define a representation decision contract for primitives, nullable primitives,
strings, arrays, anonymous structures, classes, interfaces, enums, abstracts,
functions, type parameters, `Dynamic`, and exported values.

Specify:

- what can use direct native OCaml carriers;
- when wrappers or boxed `Obj.t` values are semantically necessary;
- when refs are required;
- what identity and aliasing guarantees apply;
- how conversions are selected;
- whether `Obj.magic` can ever be a supported implementation operation and what
  proof/allowlist it requires;
- how internal representations remain decoupled from stable `.mli` exports;
- which unsupported cases must fail before OCaml compilation.

The goal is not to ban all runtime support or boxing. It is to make every such
cost selected, validated, and explainable.

### 10. Move Runtime Planning To Semantic Reasons

Review the current structured AST name scan and transitive runtime copier.

Decide:

- whether target-AST collection remains a useful consistency check;
- where semantic runtime requirements should first be recorded;
- the taxonomy and granularity of reasons;
- how reasons map to runtime modules and features;
- how raw snippets, native adapters, and exported wrappers declare needs;
- how `portable` full/default and selective modes should evolve;
- how `metal` proves absence of unsupported fallback;
- how reports explain root source fact -> semantic decision -> runtime module ->
  transitive dependency;
- how tampering, missing modules, stale manifests, or unexplained references
  fail deterministically.

### 11. Design Imports, Exports, And External OCaml Packaging

Recommend the supported workflow for:

- importing an OCaml `.mli` into completion-friendly Haxe types;
- resolving modules, nested modules, labelled/optional arguments, variants,
  records, exceptions, callbacks, and generics;
- declaring dune libraries, opam packages, versions, feature/configuration
  choices, and local OCaml sources;
- generating and checking `.mli` for Haxe-authored exports;
- isolating a stable exported ABI from internal target optimization;
- linking native compiler/plugin artifacts;
- inspecting exact sources, dependencies, hashes, and interface decisions;
- packaging reproducible libraries and executables.

State which advanced OCaml type-system features a generator can preserve,
which need an adapter, and which should be rejected. Avoid a stringly dependency
or raw-source bag.

### 12. Converge Upstream-Haxe And `hxhx` OCaml Routes

The target should have one semantic implementation usable through:

- upstream Haxe plus the Reflaxe library/macro route;
- native `hxhx` target/plugin routes;
- eventual builtin `hxhx` activation.

Define:

- the shared target core input boundary;
- the responsibilities of each host adapter;
- how typed identities and services are normalized;
- how one lowering implementation and one runtime/library planner are reused;
- how source maps, diagnostics, build manifests, and output compare;
- how host-only conditionals are quarantined;
- how to prevent Stage0/Stage3 semantic drift.

Do not merge target-specific OCaml representation into the M22 host-neutral
plugin wire format merely to reuse a name called “IR.” Coordinate with the
separate Haxe-authored native plugin/target SDK plan in the full repository,
but keep the two reviews' responsibilities distinct.

### 13. Define Idiomatic-OCaml Quality Gates

Turn “an experienced OCaml developer could have written it” into measurable
evidence. Consider:

- deterministic `ocamlformat`-compatible `.ml` and `.mli`;
- warning-clean builds under a declared warning policy;
- readable stable names and source mapping;
- direct functions/modules/records/variants/pattern matches where semantics
  permit;
- allocation, closure, boxing, ref, wrapper, `Obj.magic`, exception, dispatch,
  and runtime-helper inventories;
- generated source size, binary size, compile time, startup, throughput, and
  allocation profiles;
- runtime-free and selective-runtime fixtures;
- direct handwritten OCaml comparison fixtures with matched behavior and
  clearly declared non-equivalent representations;
- code-shape snapshots plus executable semantic tests;
- review rubrics that avoid subjective “looks idiomatic” approval.

State which gates block a supported 1.0 contract, which block only `metal`, and
which begin as report-only trend metrics.

### 14. Design The Developer Workflow

The target should provide a better development experience than direct OCaml
plugin authoring while preserving lower-level control.

Recommend commands and artifact ownership for:

- project/binding/adapter/plugin scaffolding;
- watch and incremental Haxe -> OCaml compilation;
- generated-source inspection;
- representation, runtime, native dependency, and raw-authority reports;
- `.mli` generation/checking;
- dune build and test;
- focused cross-host plugin/target tests;
- doctor/toolchain diagnosis;
- package/install/publish/reproduce;
- cold, warm, one-file, link, and load timing.

The normal inner loop must not rebuild all of `hxhx`, regenerate bootstrap
snapshots, or run broad parity suites. Broad gates remain release evidence.

### 15. Return A Reviewable Migration Sequence

Recommend small behavior beads/commits from the current pipeline to the final
architecture. The sequence must start from observed regressions and preserve a
working target at each hard cutover.

For every phase, state:

- user-visible outcome;
- owning compiler layer;
- new data/invariant;
- narrow test first;
- broader validation later;
- generated snapshot and mega-file implications;
- deliberately deferred scope;
- stop/redesign condition.

Include where `haxe_ocaml-9v1va` should extract the first semantic family and
what evidence determines whether the next step remains another plan or becomes
a typed target-lowering tree.

## Local Hypothesis To Challenge

The current local recommendation is:

- keep Haxe semantic typing in the host/compiler typed program;
- keep `OcamlExpr` as an OCaml syntax AST;
- keep the printer semantic-free;
- extract one closed representation- or mutation-sensitive family into an
  immutable validated plan;
- record semantic runtime reasons when that plan is selected;
- repeat only for evidence-backed families;
- promote the plans into a typed OCaml-lowering tree only if they need shared
  identities, ordering, representation facts, or cross-pass validation;
- do not introduce a C-shaped CFG or a generalized cross-target IR without
  OCaml-specific proof;
- keep one shared semantic OCaml target core behind upstream-Haxe and `hxhx`
  adapters;
- provide direct lowering, typed facades, binding generation, handwritten
  adapters, and scoped raw authority as a deliberate capability ladder.

Potential correction already anticipated: separate plans may fragment one
semantic truth. If representation, places, calls, runtime, exports, and
optimization all consume the same facts, Direction C may be the smallest sound
boundary now rather than later. Decide this from the candidate, not preference.

## Rejected Shortcuts To Audit

Reject or explicitly justify any proposal that relies on:

- growing `OcamlBuilder` indefinitely because OCaml has a good type checker;
- treating successful `ocamlopt` compilation as proof of Haxe semantics;
- using `Obj.magic` to reconcile independently chosen representations;
- selecting runtime modules only by scanning rendered identifiers or text;
- placing ordinary OCaml library bindings in the Haxe compatibility runtime;
- exposing internal generated records/wrappers as a stable public ABI;
- making raw `__ocaml__` the normal answer for missing APIs;
- allowing a raw-authority marker to bypass `metal`;
- stringly opam/dune dependency fragments without a validated grammar and lock;
- generating externs that claim to model OCaml features Haxe cannot type;
- silently coercing unsupported `.mli` constructs to `Dynamic`;
- keeping different semantic lowerers for upstream Haxe and `hxhx`;
- reusing the host/plugin wire program as an OCaml representation IR;
- copying HxcIR merely because it is sophisticated;
- refusing any IR merely because OCaml is high-level;
- moving new subsystems into the existing mega-files;
- increasing readiness bars from design documents or toy builds.

## Non-Negotiable Constraints

- Upstream Haxe 4.3.7 is the behavior oracle, not an implementation donor.
- Do not copy, translate, mechanically rewrite, or retype upstream Haxe
  compiler source.
- Do not vendor upstream Haxe compiler tests. Use ignored oracle checkouts and
  repo-owned focused fixtures.
- Selective permissively licensed Haxe standard-library reuse follows the
  repository provenance policy and is distinct from compiler source.
- Shipping code and dependencies remain MIT-compatible.
- Use a hard cutover. Do not preserve permanent ambiguous old/new lowering or
  binding paths.
- Ordinary supported Haxe code preserves Haxe semantics even when a more
  idiomatic OCaml rewrite would observably differ.
- Haxe semantic type identity is not replaced by an OCaml carrier type.
- The printer never becomes a typer, representation selector, runtime planner,
  mutation planner, or native binder.
- Unsupported semantics fail before native compilation with source-level,
  actionable diagnostics.
- `Dynamic`, `Any`, raw snippets, and `Obj.magic` are never broad internal
  compiler APIs or catch-all fallbacks.
- `metal` has no implicit fallback to portable or raw behavior.
- Native target APIs are explicit source portability choices.
- Runtime support is selected only for named semantic requirements and their
  validated dependency closure.
- Upstream-Haxe and `hxhx` activation use one semantic OCaml target core.
- Reflaxe does not become the parser, resolver, typer, macro-lifecycle, or
  baseline diagnostic owner inside `hxhx`.
- Avoid mega-file gravity. New independently testable planning, validation,
  binding, ABI, and runtime logic belongs in focused modules.
- Do not claim idiomatic, native, fast, runtime-free, direct-OCaml-capable, or
  ABI-stable from build success alone.
- Planning and review do not increase README or North Star readiness.

## Reference Interpretation

The package includes committed Repomix snapshots for:

- the complete `haxe.ocaml` candidate;
- `haxe.rust` for typed native escape hatches, representation/runtime plans,
  dependency/source ownership, and raw authority;
- `haxe.c` for the strongest local example of a broad target-semantic IR;
- `haxe.go`, `haxe.ruby`, and `haxe.elixir.codex` for contrasting target AST,
  runtime, modularization, and idiomatic-output designs;
- the Reflaxe framework for the actual target plugin API and transformation
  boundary;
- Coro for a concrete native compiler-plugin and lower-level OCaml workload;
- historical `ocaml-haxe` for prior extern/stdlib exposure experiments.

Sibling compilers are design pressure tests, not semantic authorities. Their
working trees may contain unrelated changes; the package contains only the
exact commits named in its manifest.

Upstream Haxe compiler source is intentionally excluded. The full candidate
already contains the repository's behavior/provenance constraints and the
separate plugin-SDK review material. This review can decide target lowering,
interop, and runtime ownership without expanding the clean-room source surface.

## Required Response Format

Return:

1. verdict and corrected responsibility table;
2. precise direct-OCaml capability contract and explicit limitations;
3. escape-hatch ladder and deterministic failure policy;
4. Haxe stdlib, `ocaml.*`, external binding, adapter, runtime, and export
   ownership model;
5. decision on `OcamlExpr`, semantic plans, typed target IR, CFG IR, and shared
   IR alternatives;
6. minimum semantic data model and identity/lifetime of each fact;
7. evaluation, mutation, control-flow, and place lowering model;
8. representation, null, `Dynamic`, boxing, wrapper, and `Obj.magic` contract;
9. semantic runtime-requirement model;
10. `.mli` import/export and dune/opam/source packaging design;
11. upstream-Haxe/`hxhx` convergence seam;
12. idiomatic generated-OCaml and direct-native performance contract;
13. developer workflow and tooling plan;
14. lessons that transfer from each supplied reference and those that do not;
15. rejected alternatives and why;
16. semantic, representation, runtime, ABI, provenance, and performance
    invariants;
17. deterministic diagnostics and internal invariant failures;
18. bead/commit migration sequence with dependencies and deferred scope;
19. validation matrix from focused semantic fixtures through release evidence;
20. explicit stop/redesign conditions;
21. human product decisions, if any.

Mark any conclusion that depends on inference rather than direct source
evidence. Do not provide implementation code for direct transcription.
