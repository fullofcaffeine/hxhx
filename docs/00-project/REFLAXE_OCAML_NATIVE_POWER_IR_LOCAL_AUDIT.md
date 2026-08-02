# `reflaxe.ocaml` Native Power And Target-Lowering Audit

Status: local pre-review evidence. Its Direction B hypothesis was refined by
the accepted independent checkpoint into a small typed OCaml-lowered model
entered through Direction B-shaped vertical slices. This remains planning, not
a current capability claim.

Prepared: 2026-07-18

Owning decision bead: `haxe_ocaml-1cixm`

Accepted review outcome:

- `docs/00-project/ORACLE_CHECKPOINT_REFLAXE_OCAML_NATIVE_POWER_IR_2026_07_18.md`

Related implementation and product owners:

- `haxe_ocaml-9v1va` - extract the first validated semantic-lowering plan;
- `haxe_ocaml-s7jry` - release-grade standalone `reflaxe.ocaml`;
- `haxe_ocaml-bomhr` - shared native Reflaxe target/plugin SDK;
- `haxe_ocaml-h5jta.1` - Haxe-authored compiler-transform and target SDK;
- `haxe_ocaml-850ii` - native developer-loop latency evidence.

## Practical Goal

A Haxe developer should be able to build an OCaml application, compiler,
backend, or plugin without giving up the practical capabilities available to
an OCaml developer. That does **not** mean pretending that Haxe and OCaml have
the same type system or syntax. It means the supported toolchain provides a
clear path for every real need:

1. ordinary Haxe and the Haxe standard library lower to direct, efficient
   OCaml wherever their semantics agree;
2. typed `ocaml.*` APIs expose OCaml's standard library and target-specific
   facilities when the source intentionally chooses OCaml;
3. typed bindings expose external OCaml libraries;
4. small handwritten `.ml`/`.mli` adapters cover features that Haxe cannot
   express faithfully;
5. raw target snippets remain a rare, explicit, auditable last resort.

The generated result should look like code an experienced OCaml developer
could reasonably have written: direct functions and modules where possible,
native records and variants where sound, predictable names, useful `.mli`
interfaces, and compatibility runtime modules only for actual Haxe semantic
gaps.

This is a goal. The repository does not currently prove that full capability,
generated-code quality, external-library workflow, or exported OCaml ABI.

## Current Pipeline

The upstream-Haxe `reflaxe.ocaml` route currently has this effective shape:

```text
Haxe TypedExpr
  -> OcamlBuilder
  -> OcamlExpr and related OCaml syntax nodes
  -> OcamlASTPrinter
  -> generated .ml files
  -> RuntimeUsageCollector / RuntimeCopier
  -> dune build and executable/library artifacts
```

At the reviewed candidate, the main files have these sizes:

| File | Lines | Current responsibility summary |
| --- | ---: | --- |
| `OcamlBuilder.hx` | 7,688 | Typed-expression traversal, evaluation scheduling, mutation analysis, representation, coercion, intrinsic/runtime selection, native interop, and target-AST construction |
| `OcamlCompiler.hx` | 3,555 | Reflaxe integration, module/type/class layout, statics, object dispatch, target types, output/build assembly, and runtime collection |
| `CompilationContext.hx` | 468 | Per-compilation state, feature and runtime observations, profile/build facts |
| `OcamlExpr.hx` | 116 | Structured OCaml expression syntax |
| `OcamlASTPrinter.hx` | 656 | OCaml rendering and precedence/layout decisions |
| `RuntimeUsageCollector.hx` | 204 | Post-construction scan of structured target syntax for `Hx*` module references |
| `RuntimeCopier.hx` | 430 | Runtime source inventory, dependency closure, selection, copying, and reports |

The line counts are evidence of concentration, not proof that an intermediate
representation is necessary. The architectural concern is the number of
semantic decisions that currently exist only during recursive syntax
construction.

## What The Existing OCaml AST Does Well

`OcamlExpr` is already a real structured target-syntax tree. It represents:

- constants and identifiers;
- source-position wrappers;
- functions, application, labelled and optional arguments;
- integer and floating-point operators;
- `let`, `if`, `match`, `try`, sequence, and `while`;
- records, fields, tuples, lists, assignments, annotations, and raises;
- a deliberately explicit `ERaw` escape hatch.

This is materially better than concatenating OCaml strings throughout the
compiler. The printer mostly receives already selected OCaml constructs and
does not need to rediscover Haxe semantics. It also gives runtime collection a
structured artifact to inspect.

In the broad computer-science sense, any compiler tree between input and text
can be called an IR. For this decision, however, the useful distinction is:

- **target syntax AST:** says which OCaml constructs will be printed;
- **target semantic lowering plan or IR:** records and validates why those
  constructs preserve the typed Haxe program.

`OcamlExpr` currently satisfies the first role. It does not yet satisfy the
second role comprehensively.

## Information The Current AST Does Not Preserve

Most `OcamlExpr` nodes do not carry:

- the originating Haxe semantic type and stable declaration/local identity;
- the chosen OCaml representation of the value;
- null, identity, aliasing, mutation, or capture policy;
- value-versus-place information for assignable expressions;
- an explicit evaluation schedule for receivers, indexes, arguments, and
  temporaries;
- whether a call is direct Haxe code, an OCaml extern, an intrinsic, a runtime
  compatibility helper, dynamic dispatch, or an exported ABI adapter;
- the reason a runtime capability is required;
- proof that a use of `Obj.magic`, boxing, a ref cell, or a wrapper is necessary;
- a validator-visible contract between semantic lowering and syntax emission.

`EAnnot` can carry an OCaml type annotation on one expression, and `EPos`
carries source provenance, but neither is a complete semantic record. `ERaw`
is intentionally opaque. The list node still describes itself as an early
array placeholder, which is another sign that target syntax and Haxe
representation policy have not been fully separated.

## Semantic Decisions Concentrated In The Builder

The current builder makes or participates in decisions across several
independent families:

### Values And Representations

- primitive, nullable, `Dynamic`, anonymous-object, enum, class, and abstract
  classification;
- `Obj.t`, `Obj.repr`, `Obj.magic`, null-sentinel, native value, record, variant,
  list, array, ref-cell, and wrapper choices;
- default values and missing optional-argument encodings;
- boxing, unboxing, equality, numeric conversion, and assignment coercion.

### Mutation And Evaluation

- which locals must become OCaml refs;
- captured mutable locals and receiver/state threading;
- locals, fields, statics, properties, array elements, and dynamic lvalues;
- temporary insertion and sequencing for blocks, calls, assignments, and
  compound operations;
- statement-versus-value treatment and early-return control.

### Calls And Native Interop

- direct, instance, static, super, closure, dynamic, extern, intrinsic, and
  runtime-helper calls;
- `@:native` path lookup;
- `@:ocamlLabel` labelled and optional arguments;
- special OCaml shapes for `List`, `Option`, `Result`, refs, native collections,
  selected standard-library operations, and raw `__ocaml__` injection.

### Haxe Compatibility

- exceptions and catches;
- arrays, maps, strings, reflection, type objects, enums, and object dispatch;
- optional/default/rest arguments;
- loops, switches, pattern reconstruction, and expression-valued control flow;
- runtime helper selection for behavior that direct OCaml syntax does not
  provide.

Many individual choices are reasonable. The risk is that their prerequisites
and cross-family invariants are implicit in traversal order and nested helper
logic instead of being sealed and checked before printing.

## Runtime Selection Today

The current runtime path is substantially more disciplined than output token
scanning:

1. generated OCaml is represented structurally;
2. `RuntimeUsageCollector` walks module items, expressions, patterns, and types;
3. qualified names whose module root starts with `Hx` are marked;
4. `RuntimeCopier` combines those observations with manual seeds and the
   runtime's transitive dependencies;
5. deterministic reports explain the selected files and inclusion reasons.

Free-form raw expressions are intentionally not inspected. A token-scan merge
exists only as an explicitly enabled debug fallback.

The remaining architectural gap is timing and intent. A target syntax name is
observed after representation and call selection have already happened. A
stronger design would normally record a semantic requirement such as
`haxe_dynamic_field_lookup`, `nullable_primitive_box`, or
`portable_array_storage` when that decision is selected, then map the reason to
runtime modules. That would let validation prove that:

- every runtime module has a semantic reason;
- no required module is hidden in raw output;
- representation and runtime decisions agree;
- a runtime-free or selective build fails with named source-level blockers;
- target syntax names are emission details rather than the planning API.

The review must decide whether this reason ledger belongs in several narrow
plans or in a broader typed lowering IR.

## Current Native And Escape-Hatch Surface

The repository already supports part of the desired ladder:

- typed extern classes and fields can map through `@:native`;
- extern parameters can use `@:ocamlLabel` for labelled or optional-labelled
  OCaml arguments;
- `packages/reflaxe.ocaml/std/ocaml` exposes selected OCaml arrays, buffers,
  bytes, characters, hash tables, maps, sets, lists, options, refs, results,
  sequences, and target-specific support modules;
- additional OCaml runtime modules can be copied into output and built with
  dune;
- raw `__ocaml__` reaches `ERaw` as a last-resort target-code injection path;
- the proposed `@:ocamlAllowRaw` policy makes a portable-only low-level
  authority island explicit and never bypasses `metal` rejection.

Important gaps remain:

- there is no complete, stable `.mli`-to-Haxe binding workflow;
- external dune/opam dependency declarations do not yet have a closed,
  validated authoring and lock contract comparable to a mature target SDK;
- handwritten `.ml`/`.mli` adapter ownership, copying, hashing, interface
  checking, and packaging are not one documented supported workflow;
- generated Haxe modules do not yet expose a deliberately stable, audited
  OCaml-facing ABI separate from internal optimized representations;
- OCaml features that Haxe cannot model directly do not yet have a complete
  typed facade/adapter policy;
- raw authority remains a design policy rather than a full analyzer;
- current `ocaml.*` coverage is useful but not equivalent to the OCaml standard
  library or ecosystem;
- code quality and performance are measured in selected lanes, not yet against
  a broad direct-OCaml corpus.

## Required Library Layers

The product needs these layers to remain distinct:

| Layer | Source-facing purpose | Expected lowering/packaging owner |
| --- | --- | --- |
| Haxe standard library | Portable Haxe semantics | Haxe API plus direct OCaml lowering or narrowly selected compatibility runtime |
| `ocaml.*` target facade | Intentional access to OCaml-native APIs and types | Typed externs, abstracts, metadata, and target intrinsics |
| Haxe-friendly OCaml wrappers | Safer/completion-friendly APIs over target facilities | Normal Haxe library code over the exact facade, without changing target behavior |
| External OCaml bindings | Typed access to opam/dune libraries | Generated or handwritten Haxe externs plus validated dependency/interface manifests |
| Handwritten OCaml adapter | Features or ABI shapes Haxe cannot express faithfully | Small `.ml`/`.mli` modules with explicit Haxe externs and deterministic build ownership |
| Haxe compatibility runtime | Only semantic gaps between Haxe and direct OCaml | Compiler-selected modules with semantic inclusion reasons and transitive closure |
| Exported OCaml library surface | OCaml callers consuming Haxe-authored code | Stable `.mli` adapters that isolate callers from private generated representations |
| Raw target injection | Last-resort compiler/target author escape hatch | Scoped, documented, rejected by strict metal paths, and absent from normal app APIs |

Collapsing these layers would create misleading behavior. In particular:

- the Haxe standard library should not become an `ocaml.*` facade;
- the target facade should not silently promise cross-target portability;
- the compatibility runtime should not become a dumping ground for ordinary
  OCaml library bindings;
- exported OCaml ABI should not expose an unstable internal class or `Dynamic`
  representation;
- raw injection should not compensate for missing typed interop indefinitely.

## Portable And Metal Profiles

The existing `ocaml_profile=portable|metal` contract is independent of the
authoring ladder:

- `portable` is the default Haxe-semantics lane. Its runtime is currently full
  by default, with optional selective planning and an auto-metalization planner
  in native Stage3 paths;
- `metal` is strict and selective. It rejects unsupported dynamic, reflection,
  and raw/untyped surfaces rather than silently falling back.

Typed target-native APIs can be valid in either profile when selected
explicitly, but they affect source portability and must be reported or rejected
according to policy. A raw-authority marker must never weaken global `metal`
checks. The unpublished `@:haxeMetal` annotation was removed because it did not
own representation, lowering, or native API authority; see
`OCAML_METAL_SOURCE_BOUNDARY_DECISION_2026_08_02.md`.

The architecture review must not use “metal” as shorthand for “write arbitrary
OCaml.” Metal is a statically proven representation/runtime policy, not an
escape from validation.

## Two OCaml Backend Routes

The repository currently contains both:

- the Reflaxe backend used with upstream Haxe typed expressions; and
- a native `hxhx` OCaml route under `packages/hxhx-core/src/backend/ocaml`, with
  its own target core, verifier, portable-metalization planner, and Stage3
  emitter integration.

The long-term product requires one semantic OCaml target core with thin host
adapters. It must not preserve two independent answers for null representation,
mutation, native calls, runtime requirements, or emitted source merely because
one route started in Reflaxe and the other in Stage3.

This does **not** imply that the target-specific lowering structure should be
merged with the M22 host-neutral backend program or plugin wire ABI. Those
artifacts have different jobs:

- the host-neutral program freezes Haxe/compiler meaning at a plugin boundary;
- the OCaml target-lowering layer decides how that meaning is represented and
  evaluated in OCaml;
- `OcamlExpr` records final target syntax;
- the printer renders syntax.

## Reference Repositories

The independent package uses committed snapshots only. Dirty or untracked
working-tree files are excluded.

| Repository | Commit | Relevant lesson | Limitation as a reference |
| --- | --- | --- | --- |
| `haxe.rust` | `8e4973032b4ef6868a92661084758e48fbc14522` | Typed extern/native ladder, dependency and extra-source ownership, scoped raw authority, representation plans, semantic runtime reasons, native quality gates | Rust ownership, lifetimes, traits, and Cargo are not OCaml semantics |
| `haxe.c` | `ca89384f447ccbb66cbc22a953f2a6475e391df5` | Broad validated `HxcIR`, explicit values/places/order/conversions/failure/cleanup/lifetimes, semantic-free C AST | C lacks managed memory, exceptions, ADTs, and expression semantics that OCaml already provides |
| `haxe.go` | `07467e5a84d733ec30ca718f2dbdbcf48c8cae4d` | Native facade/raw authority/runtime-selection pressure test and compact target AST | Go representation and package/runtime rules differ from OCaml |
| `haxe.ruby` | `79059c98644e0de2c14326fe149305628ee78ed3` | Direct readable source generation and compact semantic runtime pressure test | Dynamic Ruby does not require OCaml's static representation proofs |
| `haxe.elixir.codex` | `79255c533f33896c0d29de25a704b96e40363961` | Modular AST builders/transformers/analyzers and a deliberately narrow loop IR | BEAM process and data semantics do not transfer directly |
| Reflaxe framework | `73a983112e039daad46b37912ab238df6bf0cf53` | Actual target framework, expression filtering, typed-input integration, output ownership | It does not by itself decide OCaml representation or native ABI policy |
| Coro | `45ad2c61271d6302aaf502ed2df741ceb0ce8dc6` | Small real native compiler-plugin workload and lower-level OCaml escape-hatch pressure test | Historical Haxe 4-era example; not a current ABI or semantics authority |
| historical `ocaml-haxe` | `d1f54aa3c99210c0f5e8ef036af8108db7919341` | Prior OCaml extern-generation and standard-library exposure experiments | Incomplete historical implementation; not a current product authority |

Sibling targets are pressure tests, not Haxe semantic authorities. Upstream
Haxe 4.3.7 remains the behavior oracle. Upstream compiler source is deliberately
not included in this review archive because target-lowering ownership can be
decided from the repository and target references without expanding the
clean-room review surface.

## Why `haxe.c` Has A Broad IR

The C target must make many source-language facts explicit before it can emit
safe, portable C:

- C does not define function-argument evaluation order;
- expressions and assignable storage need distinct value/place treatment;
- object lifetime, allocation, ownership, and cleanup are compiler concerns;
- exceptions and `finally` need explicit failure and cleanup edges;
- numeric conversions and overflow behavior need a selected implementation;
- control flow often needs normalized blocks and terminators;
- C declarations, layout, dispatch, linkage, and ABI cannot be inferred safely
  from surface syntax alone.

`HxcIR` is therefore a target-owned semantic boundary before the C AST. It is
not evidence that every Reflaxe target needs an equally broad program IR.

OCaml already provides deterministic expression evaluation, garbage
collection, closures, exceptions, algebraic data types, pattern matching,
modules, and expression-valued control flow. The OCaml target still needs to
resolve Haxe-specific mutation, identity, null, dynamic, dispatch, and
representation gaps, but its normalization burden is smaller.

## Local Hypothesis Before Independent Review

This section records the hypothesis that was sent for review; it is not the
final decision. The review agreed with the bounded migration method but found
that the candidate already has enough cross-consumer representation, place,
call, runtime, and future ABI coupling to justify one explicit small typed
OCaml-lowered model now. See the accepted checkpoint above.

The smallest credible direction is:

1. keep `OcamlExpr` as the structured target-syntax AST;
2. keep `OcamlASTPrinter` semantic-free;
3. extract one closed, behavior-sensitive family from `OcamlBuilder` under
   `haxe_ocaml-9v1va`;
4. represent that family's decisions in a typed, immutable, validated plan
   before constructing `OcamlExpr`;
5. add stable semantic runtime reasons at the same decision point;
6. repeat only when another family needs the same treatment;
7. introduce a broader target-specific lowering IR only when several plans
   demonstrably need shared value/place identities, evaluation schedules,
   representation facts, and cross-pass validation.

Likely first plan candidates are nullable/dynamic representation and coercion,
or mutable-place/capture lowering. The final choice must be driven by a bounded
semantic regression and existing duplicate decisions, not by file size alone.

The local hypothesis rejects two extremes:

- continuing to grow `OcamlBuilder` with unrecorded decisions;
- copying the full C IR architecture before OCaml-specific evidence justifies
  it.

The independent review is asked to challenge this hypothesis. Several narrow
plans may prove too fragmented. If representation, place, call, runtime, and
export decisions require one shared typed tree, the right answer may be a
target-specific `OcamlLowered*` layer between Haxe typed input and
`OcamlExpr`. Conversely, if each decision can be sealed locally and final
syntax remains structurally sufficient, a broad tree would add cost without
new correctness.

## Evidence Threshold For A Broader Target IR

A broader IR is justified when multiple implemented semantic plans show at
least several of these needs:

- the same stable value/place identity must be referenced by multiple passes;
- one evaluation schedule must be validated independently of syntax emission;
- representation decisions must be consumed by calls, mutation, runtime
  selection, interfaces, and exported ABI;
- cross-node validation cannot be expressed as a local plan invariant;
- more than one backend host must consume exactly the same lowered structure;
- useful optimization requires target semantic facts that `OcamlExpr` loses;
- diagnostics need a pre-syntax artifact showing why boxing, `Obj.magic`, a
  runtime helper, or a temporary was selected;
- runtime and native-library manifests must be derived from decisions rather
  than rendered names;
- the builder remains a second typer even after bounded family extractions.

A broader IR is **not** justified only because:

- another target has one;
- one source file is large;
- “IR” sounds more compiler-like;
- the syntax AST is called an AST instead of an IR;
- a speculative optimizer might be useful later.

## Candidate Invariants

The independent review should correct these, but any accepted design is
expected to preserve at least the following intent:

### Semantic Ownership

- Haxe typing and overload decisions remain owned by the host/compiler typed
  program, not rediscovered from printed OCaml or strings.
- OCaml representation and native-library decisions are selected once in a
  target-owned layer and are identical across upstream-Haxe and `hxhx` host
  adapters.
- The printer does not decide mutation, boxing, runtime use, call kind, or
  representation.

### Evaluation And Mutation

- Haxe-observable receiver, index, argument, getter, setter, and side-effect
  order is explicit before printing.
- A mutable Haxe place reaches the original storage; a detached temporary does
  not silently absorb the write.
- Captured mutation and ref-cell introduction have named reasons and are not
  inferred independently in several emitters.

### Representation

- Every value has one semantic Haxe type even when its OCaml carrier differs.
- Null, identity, aliasing, dynamic, and dispatch policy are explicit.
- `Obj.magic` is a narrowly justified boundary operation, never a universal
  repair for an inconsistent plan.
- Internal optimized representation can change without silently breaking an
  exported OCaml `.mli` contract.

### Runtime And Interop

- Every compatibility runtime module is reachable from a deterministic
  semantic requirement and transitive dependency closure.
- A target-native facade or external library is not misclassified as Haxe
  compatibility runtime.
- External source and dependencies have deterministic ownership, hashes,
  versions, and failure diagnostics.
- Raw injection is explicit, source-attributed, absent from strict metal code,
  and never required for ordinary supported APIs.

### Output Quality

- Generated `.ml` and `.mli` are deterministic, formatted, warning-clean under
  the declared policy, and source-mapped.
- Direct OCaml syntax is preferred when it preserves Haxe semantics.
- Runtime, boxing, wrappers, and allocation are measurable and explainable.
- Unsupported semantics fail before `ocamlc`/`ocamlopt` reports an opaque
  generated-source type error.

## Decisions Still Open

The architecture review must decide:

1. whether the first extraction should be a family-specific plan or the root of
   a typed target-lowering tree;
2. what minimal semantic identities and annotations are needed;
3. whether value/place and evaluation scheduling should be universal or only
   attached to mutation-sensitive nodes;
4. how representation plans interact with `OcamlExpr` type annotations;
5. whether runtime requirements are attached to decisions, nodes, functions,
   modules, or a program ledger;
6. how `.mli` imports and exported interfaces fit the same representation
   model;
7. which OCaml features receive typed Haxe facades, generated bindings,
   handwritten adapters, intrinsics, or explicit unsupported diagnostics;
8. how the upstream-Haxe Reflaxe route and native `hxhx` route converge on one
   semantic implementation;
9. which generated-code quality and direct-OCaml comparison gates block a
   supported 1.0 claim;
10. the exact evidence that permits or rejects a broader OCaml IR.

## Scope And Readiness

This audit changes no compiler behavior, public flags, supported profiles,
plugin ABI, runtime selection, generated output, or release claim. It does not
increase any README readiness bar. It records the evidence and the questions
needed for an independent architecture checkpoint before implementation.
