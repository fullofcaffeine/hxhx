# Oracle Checkpoint: `reflaxe.ocaml` Native Power And Target Lowering

Prepared: 2026-07-18

Status: GPT-5.6 Pro architecture review accepted with two semantic corrections;
implementation split into bounded follow-up Beads

Owning decision Bead: `haxe_ocaml-1cixm`

Primary implementation Bead: `haxe_ocaml-9v1va`

Review provenance:

- controlling prompt:
  `docs/00-project/GPT_5_6_PRO_REFLAXE_OCAML_NATIVE_POWER_IR_REVIEW_PROMPT.md`;
- local evidence:
  `docs/00-project/REFLAXE_OCAML_NATIVE_POWER_IR_LOCAL_AUDIT.md`;
- reviewed candidate: `83fda5964773c03804088fb2e2ec1dcbc2de8d31`;
- review archive SHA-256:
  `561f9b40da8d7e473c4a4a2898ac5d14d2eba3978d68b1db143e378cd86e4b7b`;
- the reviewer verified all 29 packaged payloads and the committed identities of
  the eight supplied reference repositories.

## Outcome

The product goal is accepted, but it must be described precisely:

> Haxe authors should have practical direct-OCaml capability through ordinary
> Haxe, typed target APIs, generated bindings, and small typed adapters. The
> compiler must reject boundaries that Haxe cannot represent faithfully.

This is not a claim that Haxe acquires OCaml's module or type system, that every
OCaml interface can become a Haxe extern, or that arbitrary raw OCaml is an
ordinary supported workflow.

The accepted target pipeline is:

```text
host-typed Haxe program
  -> normalized OCaml-target input with stable identities
  -> small typed OCaml-specific lowered model
  -> OcamlExpr and OCaml module syntax
  -> semantic-free printer
```

The local pre-review hypothesis is refined as follows:

- **Direction B remains the migration method:** introduce one closed,
  behavior-sensitive vertical slice at a time.
- **Direction C-lite is now the durable boundary:** every migrated slice is a
  node family in one small typed OCaml-lowered model, not a permanent side
  table.
- `OcamlExpr` remains the target-syntax AST.
- A broad C-style control-flow graph is not justified.
- A shared cross-target representation IR is rejected.
- A big-bang rewrite of `OcamlBuilder` is not authorized.

The first hard cutover remains bounded to place, evaluation, assignment, and
update behavior under `haxe_ocaml-9v1va`. Unrelated expression families stay on
the current path until their own behavior-backed cutover.

This architecture decision adds no current capability and does not move any
README or North Star readiness bar.

## Soundness Review

The review's central diagnosis is sound and matches the live candidate:

- `OcamlCompiler` selects carriers, defaults, class/interface layouts, and
  dispatch shapes, then supplies its type mapper to `OcamlBuilder`.
- `OcamlBuilder` separately consumes and sometimes reconstructs representation
  facts while deciding storage, capture, mutation, calls, coercions, native
  surfaces, runtime helpers, and final syntax.
- raw interpolation renders child `OcamlExpr` values into text before final
  printing, so those children no longer remain structurally inspectable;
- `guardrailError` suppresses errors while the current Haxe standard library is
  compiled, while several unsupported branches continue with unit or null-like
  placeholders;
- `RuntimeUsageCollector` is a useful structured syntax scan, but it sees the
  result of semantic decisions rather than the reasons for them;
- `RuntimeCopier` currently ignores requested runtime modules that do not exist
  in its available-module set;
- `OcamlMliGenerator` invokes `ocamlc -i` and explicitly presents the result as
  a starting point for later curation, not a stable public interface contract;
- `GenIrProgram` explicitly remains an alias for the typed, macro-expanded
  program rather than a normalized neutral IR;
- the native `hxhx` OCaml path still delegates to a large independent emitter,
  so sharing a target-core name does not yet establish semantic convergence.

These are interacting ownership facts, not a line-count argument. Permanent
representation, place, call, runtime, and ABI side tables would need the same
program, declaration, expression, local, and boundary identities. Making the
shared lowered artifact explicit is easier to validate than rebuilding it
implicitly through cross-linked tables.

### Corrections To The Review

Two phrases in the response are not adopted as universal rules.

#### Evaluation is not universally exactly once

The response sometimes describes place setup, array indexes, and compound
updates as evaluated exactly once. The stronger invariant elsewhere in the
same response is the accepted one:

> Evaluate each receiver, index, getter, setter, operand, and helper exactly as
> often, and in exactly the order, required by measured Haxe behavior.

This distinction is observable. The accepted C++ abstract-operator checkpoint
and its repo-owned Haxe 4.3.7 fixtures prove that an overloaded indexed read and
write can evaluate an index separately. The existing shared implementation
therefore deliberately does not memoize that overloaded array/index place.

The OCaml place model must consequently record an **occurrence schedule**. It
must be able to share one evaluated receiver/index through a temporary or emit
multiple explicit occurrences. It must never impose a blanket target-local
memoization policy.

#### Prefix/postfix spelling does not universally choose old/new results

For ordinary numeric increment and decrement, the lowered plan records the
Haxe-defined mutation and old/new result behavior. For an overloaded abstract
operator, however, prefix/postfix spelling preserves syntax and participates
in declaration selection; the selected static call or inline helper body owns
mutation and result semantics. A static postfix helper may leave the operand
unchanged, and an inline instance helper may return a value or `Void` according
to its body.

The OCaml target must consume the host-resolved call or structurally lowered
body. It must not manufacture assign-back, reference ABI, or old/new behavior
from fixity.

## Responsibility Boundary

| Concern | Final owner |
| --- | --- |
| Haxe typing, overload resolution, resolved calls/fields, macro results | Host compiler |
| Stable source/type/declaration/local/expression identities | Thin host-normalizing adapter |
| OCaml carrier, layout, null, boxing, and boundary representation | One target-owned representation registry |
| Evaluation order, places, mutation, and target control mechanism | Typed OCaml-lowered functions and expressions |
| Exact call kind and conversions | Lowered call/conversion plans referenced by nodes |
| Haxe semantic need for runtime support | Semantic lowering at the decision point |
| Runtime dependency closure, source hashes, and copying | Checked runtime manifest and packager |
| OCaml package/source dependencies | Structured native dependency/source manifest |
| Imported `.mli` bindings | Versioned typed binding importer |
| Public `.mli` exports | Explicit export ABI planner and checker |
| OCaml expression/module syntax | Existing target-syntax AST |
| Formatting and precedence | `OcamlASTPrinter` |

The printer must never receive unresolved Haxe types, representation
alternatives, capture analysis, runtime-selection logic, dependency resolution,
or fallback policy.

## Small Typed OCaml-Lowered Model

The accepted model is deliberately smaller than both the source typed tree and
the C target's `HxcIR`.

It is:

- target-owned and OCaml-specific;
- immutable after sealing;
- structurally recursive for migrated expression families;
- keyed by deterministic identities within one normalized program revision;
- explicit about source semantic type versus selected OCaml carrier;
- explicit about ordered effects, assignable places, calls, conversions,
  control transfers, runtime requirements, and source origin;
- mechanically lowerable into `OcamlExpr` and module syntax.

It is not:

- a mirror of every Haxe `TypedExpr` node;
- a universal Reflaxe or compiler-wide IR;
- a whole-program SSA/CFG with blocks, phi nodes, dominance, or liveness;
- an annotation layer placed on `OcamlExpr`;
- one new mega-file containing all target decisions.

Focused modules should own representation, places/schedules, calls/conversions,
runtime requirements, native dependencies, bindings, exports, and validators.
The lowered nodes reference immutable program-wide records by stable identity
instead of copying them or rediscovering them.

### Relationship To The Modern Reflaxe Template

The governing rule is: **the compiler must be as powerful as needed to meet the
product goals, while avoiding complexity that has no demonstrated job**. In
architecture terms, that means using a sufficient target-owned model that makes
measured semantic gaps explicit and independently validatable, then expanding
it whenever new correctness, interop, performance, or tooling requirements
demand more power. This constrains unjustified machinery, not user capability,
target access, generated-code quality, performance ambition, or future growth.
Its Pattern B discipline describes how this migration proceeds. However, the
generic project note that labels `reflaxe.ocaml` as a durable
target-AST-plus-plans compiler is not the final decision for this repository.

This distinction is a product invariant, not wordplay:

| Maximize for users and generated programs | Minimize inside the compiler |
| --- | --- |
| Haxe language coverage and practical OCaml access | Duplicate representations of the same semantic fact |
| Typed native APIs, adapters, and deliberate low-level escape hatches | Competing lowerers and target-side retyping |
| Idiomatic, readable, efficient OCaml | Passes, graph machinery, and node kinds without a proven invariant |
| Correctness, diagnostics, inspection, and reproducibility | Unsafe fallback, raw repair, and speculative abstraction |
| Ability to grow when new evidence requires it | Up-front complexity that slows current development without proving more behavior |

The place bug is the concrete example. Direct construction of `OcamlExpr` was
not sufficient because it could not independently preserve and validate the
receiver, old-value load, RHS, store, and result. The compiler therefore grew a
typed lowered place family. A whole SSA/CFG layer would not currently prove
more for that operation: ordered OCaml `let` expressions already represent its
validated schedule directly. If future control families require dominance,
edge arguments, liveness, or shared cleanup edges, the architecture expands at
that evidence boundary. The architecture is deliberately expandable, not
capped.

The whole-repository review found that representation, storage, calls,
mutation, runtime requirements, native boundaries, and future exports already
share identities and invariants across `OcamlCompiler`, `OcamlBuilder`, layout,
and packaging. Permanent disconnected plans would reconstruct an implicit
lowered program. That evidence crosses the template's own escalation threshold.
The resulting synthesis is therefore:

- **destination:** the small typed OCaml-specific lowered model documented
  here (C-lite, without SSA or a broad CFG);
- **migration method:** Pattern-B-shaped vertical slices, each with one closed
  family, one owner, one validator, and a hard cutover;
- **syntax boundary:** `OcamlExpr` remains structural OCaml syntax and never
  absorbs Haxe semantic ownership;
- **non-goal:** no universal Reflaxe IR, generic pass framework, or whole-
  compiler rewrite.

Every new lowered family must state the source fact that target syntax would
lose, its typed closed payload, producer, one consumption owner, legal lifetime,
validator, deterministic failure, and executable parity evidence. Its current
phase contract is:

```text
normalized host input
  -> construct and seal one typed lowered family
  -> validate its semantic and profile invariants
  -> mechanically construct OcamlExpr
  -> reject any surviving semantic family before printing
```

Source-shaped atomic children are temporary migration payloads only when an
invariant scan proves they hide no admitted place, mutation, or bindable
operator. A stored fact must support validation, mechanical lowering, a shared
registry, or a deterministic inspection contract; otherwise it should be
removed instead of becoming a debug-only flag cloud.

The template also exposed an independent infrastructure gap: `OcamlExpr`
consumers currently repeat constructor traversal. Bead `haxe_ocaml-i9bnd`
tracks one exhaustive immediate-child schema, raw-node policy, and constructor-
coverage tests. That work is deliberately separate from semantic cutovers and
does not replace the lowered model.

### Required Durable Identities

The model needs deterministic identities for at least:

- normalized program revision;
- source module, declaration, and expression;
- semantic type, field, method, function, and local;
- lowered node, temporary, target symbol, and assignable place;
- runtime requirement, native dependency, import/export boundary, and unsafe
  proof.

Host object identity and memory addresses are not durable identities. Exact
cross-host ID spelling may differ while adapters are introduced, but equivalent
normalized inputs must ultimately provide a deterministic mapping and equal
target-plan digests.

### Semantic Types And Carriers

A Haxe semantic type and an OCaml storage/call carrier are different facts.
One semantic value may use different carriers in internal storage, captured
storage, `Dynamic`, a native import, or a public export. Conversely, two source
types may happen to share an OCaml carrier without gaining interchangeable
semantics.

Each representation key therefore includes its domain, for example:

- internal value;
- mutable or captured storage;
- `Dynamic` box;
- native imported boundary;
- public exported boundary;
- runtime payload.

Every crossing between domains uses an explicit conversion plan. `Obj.magic`
is not a general reconciliation mechanism. Any retained unsafe operation needs
a named carrier proof, owner, origin, permitted profile, tests, inventory entry,
and exit criterion.

## First Vertical Slice

`haxe_ocaml-9v1va` seeds the model with place, evaluation, assignment, and
update nodes.

The first slice should cover the smallest oracle-backed family that proves
reuse across:

- mutable locals;
- instance fields;
- static cells;
- arrays or bytes;
- anonymous/dynamic fields;
- simple assignment;
- compound assignment;
- ordinary pre/post update where currently supported;
- resolved abstract-operator call/inline behavior where that syntax reaches
  the target input.

A place represents the original storage, not merely an OCaml left-hand-side
expression. Its lowered schedule records:

- the receiver/index/getter/setup occurrences required by the source behavior;
- which occurrences are intentionally shared through temporaries;
- how to load and store;
- semantic and carrier types;
- effects, aliasing, identity, and source origin;
- conversions and assignment-expression result.

The workflow for the slice is:

1. add repo-owned Haxe 4.3.7 behavior and negative fixtures;
2. add stable plan/report data without changing emission;
3. compare the plan with current generated output;
4. hard-cut only the admitted family to the new lowered path;
5. delete its old semantic branch in the same phase;
6. validate target syntax, native execution, profiles, and deterministic
   diagnostics.

Unsupported states in the migrated family fail before OCaml compilation. They
must not become unit, null, `Dynamic`, raw syntax, `Obj.magic`, or the original
untranslated expression.

The next evidence-backed slice is local storage, capture, and ref introduction.
Representation unification, calls/conversions, control effects, and runtime
requirements follow as separate bounded owners. No selectable permanent
old/new semantic path is permitted.

## Runtime Requirement Model

The structured post-AST scan remains valuable as a consistency checker. It is
not the future source of truth.

Semantic lowering records a requirement when it decides, for example, that a
value needs Haxe-array growth, `Dynamic` field lookup, arbitrary-value
exception wrapping, reflection identity, or a null compatibility carrier.

Each root requirement records:

- stable requirement and source identities;
- semantic capability and subject type/symbol;
- the lowering or representation decision that caused it;
- active profile;
- direct, generated-local, or shared-runtime implementation selection;
- runtime capability version and dependency roots.

A locked manifest maps semantic capability to implementation feature, runtime
source modules, transitive dependencies, versions, hashes, and licenses.
Validation must fail for unknown, missing, stale, or modified runtime sources.
Raw fragments and adapters declare their own requirements; syntax scanning may
check those declarations but may not invent the authoritative dependency graph.

`portable-full` may remain an explicit transition mode while actual semantic
roots are still reported. `portable-selective` can become the default only
after completeness and tamper evidence. `metal` never falls back to portable,
raw, or unchecked unsafe behavior.

## Escape-Hatch Ladder

There is no automatic fallback down this ladder:

| Level | Supported role |
| --- | --- |
| 1. Compiler-owned direct/intrinsic lowering | Ordinary Haxe semantics expressed directly and validated by the target |
| 2. Typed one-to-one `ocaml.*` facade | Exact target-native modules, values, labels, optionals, and carriers |
| 3. Haxe-friendly wrapper | Completion-friendly Haxe API over an exact facade |
| 4. Generated `.mli` binding | Representable first-order external OCaml interfaces |
| 5. Handwritten `.ml`/`.mli` adapter | Typed boundary for OCaml features Haxe cannot express faithfully |
| 6. Scoped raw injection | Explicit experimental last resort, never implicit and never metal |

A failed binding or lowering does not silently widen to `Dynamic`, use
`Obj.t`, inject raw source, or emit a placeholder. Diagnostics name the lowest
safe next level. A GADT or generative functor, for example, normally requires a
small first-order adapter rather than a false Haxe extern.

The Haxe standard library, `ocaml.*`, Haxe-friendly wrappers, external
bindings, handwritten adapters, compatibility runtime, and public export
wrappers remain separate ownership and packaging layers.

## Imports, Exports, And Native Packaging

Production `.mli` imports should use a toolchain-pinned typed interface reader,
such as compiler-libs over `.mli`, `.cmi`, or `.cmti`. Regular expressions and
`ocamlc -i` output are not stable binding inputs. The importer preserves
ordinary functions, labels/optionals, tuples, records, closed variants,
exceptions, opaque types, and first-order generics, while rejecting or routing
advanced module/type-system features to adapters.

Native dependencies and source units use structured records for:

- Dune library and opam package identity;
- version, source origin, and digest;
- supported OCaml/platform range;
- link mode, local source units, and deliberate C stubs;
- owner, visibility, profile eligibility, and license.

Generated Dune and opam files render this model; free-form strings are not the
semantic source of truth.

Haxe-authored public OCaml APIs require explicit export selection. The export
planner chooses stable public representations, generates adapter modules and a
curated `.mli`, keeps private records/dispatch/runtime details hidden, checks
the implementation against the contract, diffs released ABIs, and compiles an
independent OCaml consumer. An inferred private implementation interface does
not automatically become the public API.

Advanced adapters, broad ecosystem binding coverage, and cross-version native
plugin ABI promises are not prerequisites for the first narrow standalone
release unless its declared public scope claims them.

## One Target Core Across Hosts

Upstream Haxe and `hxhx` should provide thin adapters into the same target
core. Their normalized input contains immutable typed bodies, resolved
relationships, stable identities, source spans, metadata, and program
revision. It contains no OCaml representation decisions.

The target core alone owns representation, lowering, runtime requirements,
dependencies, exports, syntax construction, and target reports. It must not
make per-expression host callbacks to recover ordinary type, field, capture,
metadata, or source facts.

Given equivalent normalized input, target configuration, runtime manifest,
dependency lock, and supported toolchain, both hosts must produce equal
representation/lowered/runtime/dependency/export digests and equivalent
behavior.

This is distinct from a shared cross-target IR. `GenIrProgram` remains an
honest typed-program alias until at least two targets prove a genuinely
target-neutral transform with common invariants and differential tests.

The current Stage3 OCaml emitter is not the convergence seam. The eventual
hard cutover makes `hxhx` another adapter into this target core and removes its
independent semantic lowering ownership. Any surviving Stage3 layer is
bootstrap orchestration only.

For native plugin packaging, one payload on the pinned reference toolchain
remains the goal. Binary compatibility across arbitrary OCaml compiler versions
is not implied. If host constraints force different thin loader shells, the
M22 evidence rules still require the same ABI and semantic payload/core.

## Developer Workflow Contract

The architecture must be visible through one coherent target-author workflow,
not only through internal tests. The eventual command group should support:

- scaffolding an application, library, binding, adapter, and native plugin;
- watching Haxe inputs, regenerating only affected OCaml units, and invoking a
  focused Dune build or test;
- inspecting lowered computations, representations, runtime reasons,
  dependencies, raw authority, unsafe proofs, and export ABI;
- importing, checking, updating, and explaining `.mli` bindings;
- adding and checking owned `.ml`/`.mli` adapter units;
- generating, checking, and diffing curated exports;
- comparing one focused package through upstream Haxe and `hxhx`;
- diagnosing Haxe, OCaml, Dune, opam, compiler-libs, manifest, lock, and
  platform compatibility;
- locking, optionally vendoring, installing, packaging, and reproducing a clean
  build;
- measuring cold, warm, one-file, native compile, link, load, startup, and
  runtime costs.

Checked-in sources include user Haxe, handwritten adapters/interfaces,
dependency and binding manifests, selected locks, explicit export contracts,
and provenance/license records. Generated OCaml, generated bindings and export
adapters, Dune/opam renderings, source maps, and semantic reports remain
inspectable but are not hand-edited. Object files, compiled interfaces, caches,
and broad transient reports remain build artifacts.

The ordinary edit/test loop must not rebuild all of `hxhx`, regenerate
bootstrap snapshots, run every backend, or rebuild unrelated runtime modules.
Broad parity and packaging gates remain release evidence, not the default inner
loop. Latency reports must separate Haxe-to-OCaml generation, OCaml
parse/typecheck/compile, link, plugin load, startup, and program execution so
the slow phase has a clear owner.

## CFG And Shared-IR Thresholds

Do not introduce a broad CFG merely because the source has loops, exceptions,
or Coro transforms. OCaml directly supports ordered expression evaluation,
closures, exceptions, matches, and expression-valued control.

A bounded function-local block form is reconsidered only after repeated
evidence that correctness needs dominance, edge arguments, liveness across
edges, shared cleanup/failure edges, or state transitions that cannot be
validated in a structured tree.

A cross-target transform is reconsidered only after two targets independently
demonstrate the same source-semantic operation, invariants, identities, and
target-independent validation. Similar node names are not evidence.

## Migration Ownership

| Sequence | Bead | Bounded outcome |
| ---: | --- | --- |
| 0 | `haxe_ocaml-1cixm` | Accept this architecture and close the review decision |
| 1 | `haxe_ocaml-9v1va` | Seed the lowered model with place/evaluation/assignment semantics |
| 2 | `haxe_ocaml-9bome` | Unify representation, local storage, capture, null, and unsafe-proof ownership |
| 3 | `haxe_ocaml-taef5` | Give calls, labels/optionals, callbacks, and conversions one typed contract |
| 4 | `haxe_ocaml-w32h3` | Represent return, loop transfer, throw, and private target mechanisms explicitly |
| 5 | `haxe_ocaml-0uwin` | Make runtime requirements semantic, manifest-driven, and fail closed |
| 6 | `haxe_ocaml-v8a9b` | Productize typed imports, adapters, and native dependencies |
| 7 | `haxe_ocaml-7sgtj` | Generate curated public OCaml export ABIs |
| 8 | `haxe_ocaml-bomhr` and `haxe_ocaml-fa0zh` | Put upstream Haxe and `hxhx` behind one target core without a shared target IR |
| 9 | `haxe_ocaml-1hd2w`, `haxe_ocaml-zof2e`, and `haxe_ocaml-850ii` | Productize the fast workflow, SDK docs, and latency evidence |
| Cross-cutting infrastructure | `haxe_ocaml-i9bnd` | Make every `OcamlExpr` child visible through one exhaustive traversal contract without changing target semantics |
| Release | `haxe_ocaml-s7jry` | Gate only the declared standalone product scope with honest dependencies |

Each implementation Bead must recheck its own `thinking:xhigh` threshold and
land in reviewable hard-cutover slices. This review is architectural input; it
does not replace per-slice behavior fixtures, tests, CI, or closure review.

## Validation And Stop Conditions

The target needs validators at four boundaries:

1. normalized input: revisions, stable identities, resolved references, and
   complete host facts;
2. lowered semantics: representations, place schedules, calls, conversions,
   control targets, runtime reasons, and profile legality;
3. target syntax: target symbols, planned runtime/native references, and no
   undeclared raw or unsafe operations;
4. package and ABI: locks, source hashes, export contracts, and toolchain
   compatibility.

Required evidence grows from focused unit and Haxe-oracle fixtures to lowered
artifact snapshots, generated-code shape, OCaml typechecking, native execution,
runtime tamper tests, profile negatives, binding/adapter/export consumers,
cross-host digests, determinism, provenance, and performance.

Stop and redesign if implementation requires any of these:

- a lowered tree that merely mirrors `TypedExpr` without target invariants;
- permanent disconnected tables with pervasive cross-lookups;
- representation choices still made independently in compiler and builder;
- semantic runtime correctness still inferred from syntax;
- blanket exactly-once evaluation or blanket overloaded update rules;
- unresolved or unsupported semantics lowered to unit, null, `Dynamic`, raw, or
  `Obj.magic`;
- target semantics in a host-neutral plugin envelope;
- another target-lowering mega-file;
- two permanent production semantic paths;
- broad CFG or cross-target IR without the evidence thresholds above;
- public `.mli` files exposing private carriers or runtime details;
- generated bindings that misrepresent advanced OCaml types;
- unexplained boxes, refs, wrappers, dispatch, runtime calls, or unsafe casts;
- an ordinary inner loop that requires broad bootstrap regeneration or every
  backend gate.

## Product Defaults From This Checkpoint

The architecture records these defaults. Exact version ranges, platform lists,
maintainer names, and numeric performance thresholds remain evidence-backed
decisions for their owning Beads.

| Decision | Default |
| --- | --- |
| Public wording | “Practical direct-OCaml capability through typed APIs and adapters,” not OCaml language equivalence |
| OCaml support | One pinned primary toolchain plus a small explicitly tested compatibility range |
| Advanced OCaml types | Adapter-first for functors, GADTs, first-class modules, locally abstract types, and higher-rank APIs |
| Portable runtime | Keep full mode explicit during transition; make selective normal only after completeness/tamper proof |
| Metal safety | No raw injection and no unchecked generated `Obj.magic`; proof-only internals need separate review |
| Raw authority | Named owner, review, typed boundary, declared effects/dependencies, inventory, profile check, and exit test |
| Public exports | Explicit selection only; never export every public Haxe declaration automatically |
| Dependencies | Structured declarations plus a reproducible lock and an explicit offline/vendoring policy |
| Native plugin ABI | Compatibility is tied to the exact declared OCaml/runtime/platform key; no cross-version implication |
| Performance | Collect stable reports first, then set explicit red lines before broad performance claims |
| Licensing | Machine-readable source ownership and MIT-compatibility checks for copied or linked native sources |
| “Idiomatic OCaml” | Judge direct forms and explainable boxes/refs/wrappers/runtime/unsafe operations, not visual taste alone |

## Release Scope

This checkpoint does not silently redefine `reflaxe.ocaml 1.0` as complete
OCaml ecosystem or advanced type-system support.

It does establish concrete safety dependencies for any declared release
surface that exercises them:

- behavior-sensitive place/evaluation/update semantics must have an
  oracle-backed validated owner;
- runtime/profile claims must fail closed for unknown or stale requirements;
- packaging or public-library claims need structured dependency/source or
  curated export evidence appropriate to the declared scope;
- unsupported behavior must fail at the Haxe source boundary instead of
  surviving as a plausible OCaml placeholder.

The first lowered slice and the fail-closed runtime work are therefore
release-relevant. Full binding generation, advanced adapters, broad exports,
one cross-host target core, and the later optimization roadmap block only the
product claims that actually include them.

README Goals and North Star progress bars remain unchanged. Architecture
review, Bead planning, and a successful toy build are not production evidence.
