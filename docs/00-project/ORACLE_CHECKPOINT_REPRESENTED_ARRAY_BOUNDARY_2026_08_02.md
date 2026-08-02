# Oracle Checkpoint: Represented Array Boundaries

Prepared: 2026-08-02

Status: focused architecture review accepted after local source reconciliation;
implementation is split into bounded follow-up Beads. This checkpoint adds no
compiler capability and does not move README readiness.

Owning decision Bead: `haxe_ocaml-w32h3.26`

Parent control-effects Bead: `haxe_ocaml-w32h3`

Reviewed repository candidate:
`8442d7a2719219a3b202ecf790be1a68e78b7b9f`

Oracle request: `orq_20260802T213810Z_a78ad063`

Review provenance:

- requested reviewer: GPT-5.6 Pro;
- reviewer label observed by `caf-oracle`: `Pro`;
- controlling prompt SHA-256:
  `5e4c34ac28590dc4a261017c9a89810b5ffabafe6c3beee863a2e1e9d3a62248`;
- checked evidence bundle SHA-256:
  `11f1703565ca4516da376cc2a5cbf1d490219309b9b6f9b2586085df982cba31`;
- captured response SHA-256:
  `56bdae5aed3f99a10cfb8075eed2aecbdfabe81f0f66ba05e7f794213859657f`.

## Outcome

The project should introduce one general description of a represented Haxe
array now, but it should **not** claim general `Array<T>` support.

The practical problem is visible in one existing case:

```haxe
final expected = [1];
throw expected;
```

The compiler already stores `expected` as `int HxArray.t`, which is the OCaml
runtime container used for an `Array<Int>`. The control planner nevertheless
recognizes `Array<Int>` again and independently chooses its carrier, conversion,
proof, and exception tags. Adding another branch for `Array<String>` would copy
that semantic decision into yet another place.

The accepted replacement is:

```text
final direct Array<Int> type
  -> one program-owned array descriptor
  -> one representation decision for each admitted storage domain
  -> local or literal producer references that exact decision and revision
  -> control transports the already represented array without choosing T
```

An **array descriptor** is an immutable compiler record describing one closed
array shape: its Haxe array and element identities, the already-proved element
storage representation, and the resulting `HxArray.t` carrier. It is subordinate
to the existing representation registry. It does not replace the registry or
create a second compiler.

The first implementation slice migrates the already-proven `Array<Int>` local
and throw behavior through that descriptor and deletes the exact control-owned
`Array<Int>` path. Behavior must remain unchanged. A later immediate slice adds
a represented array-literal producer using `Array<Int>` before any second
element family is considered.

## Why The Review Applies To Current Main

The response was checked against current source instead of being accepted from
its summary alone:

- `OcamlRepresentationRegistry` recognizes only direct `Array<Int>` and selects
  `int HxArray.t` independently for internal, mutable-local, and captured-local
  domains.
- `OcamlLocalRepresentationPlanner` separately tests exact `Array<Int>` source
  and carrier shapes.
- `OcamlPlaceAssignmentPlanner` directly asks for the exact `Array<Int>`
  representation while separately selecting `Int` in the `ArrayElement`
  storage domain.
- `OcamlControlPlan` repeats the exact semantic type, carrier, representation
  ID, conversion, proof, and `Dynamic`/`Array` tags.
- local, call, and control representation references currently carry IDs but
  not the exact representation revisions needed to reject a stale reference.
- `nestedUnsupportedGenericThrowClosure` throws a direct `Array<String>`
  literal. It is not a represented local, so adding only a String array
  representation would not close that failure.
- the runtime classifies every immediate OCaml value as its integer storage
  kind. Because OCaml Bool values are immediate too, `Array<Bool>` needs a
  focused runtime proof before it can become the next admitted family.
- String deliberately has no `ArrayElement` representation. Its Haxe null
  sentinel, sparse slots, out-of-bounds reads, and typed-store deoptimization
  therefore need a separate proof.

No open pull request owns or supersedes this decision on the reviewed candidate.

## Accepted Ownership Model

| Fact or action | Sole owner |
| --- | --- |
| Canonical direct Haxe array and element identity | Thin host-normalizing adapter |
| Closed, flat array shape and element representation binding | Registry-owned array descriptor |
| Outer array null, identity, alias, storage, mutation, and boxing policy | Existing domain-specific representation decision |
| Element null, default, carrier, and boxing policy | Representation decision in the `ArrayElement` domain |
| Local replacement and captured-cell behavior | Local storage and representation plans |
| Array operation evaluation order and get/set/update behavior | Existing operation-specific place plans |
| Ordered exception tags and private signal choice | Control plan, derived from the descriptor's static `Array` kind |
| Callable argument and result conversions | Call plan; still blocked for arrays |
| Runtime array operations | `HxArray.ml`, after the compiler has selected the operation |
| Runtime source identity and package closure | Runtime manifest and packager |

The descriptor must contain only serializable values. It must not retain Haxe
`Type` or `TypedExpr` objects, macro contexts, target builders, generated OCaml
syntax, or request-local object identity.

## Smallest Descriptor Contract

The initial descriptor records:

- stable descriptor ID, key, model revision, program revision, and content
  revision;
- canonical direct array and element semantic identities;
- source form `direct-builtin-array`, closed monomorphic element kind, no outer
  wrapper, and flat nesting;
- exact element representation ID, revision, carrier, and required
  `ArrayElement` domain;
- carrier family `HxArray`, the composed array carrier, selected runtime
  capability, and static runtime kind `Array`;
- bounded proof ID and claim; and
- sorted profile eligibility.

Each array-valued `OcamlRepresentationDecision` adds only the descriptor ID and
descriptor revision. Its own revision includes those fields. Existing null,
identity, alias, storage, mutation, boxing, default, proof, and profile fields
remain where they are.

Every migrated consumer adds `representationRevision` next to
`representationId`. Validation follows the graph instead of copying facts:

```text
local, literal, call, or control reference
  -> exact representation ID and revision
  -> exact array descriptor ID and revision
  -> exact ArrayElement representation ID and revision
```

This prevents a believable stale report from becoming valid merely because its
aggregate hash was recomputed.

## Initial Admission

| Source form | Decision |
| --- | --- |
| Direct, flat `Array<Int>` | Admit by migrating the existing proof without broadening behavior |
| Direct, flat `Array<Bool>` | Candidate only after an `ArrayElement` and `HxArray` runtime audit |
| Direct `Array<String>` | Block until String element null, sparse/OOB, deoptimization, and literal conversion are proved |
| `Array<Float>` and nullable Float forms | Keep behind the numeric review gate |
| Nullable elements, `Array<Dynamic>`, nominal or enum elements | Unsupported in the initial descriptor |
| Nested arrays | Unsupported; recursive descriptors need a separate checkpoint |
| `Null<Array<Int>>` | Unsupported; the outer nullable crossing is not proved |
| Typedef, abstract, generic, cast-produced, `Vector`, or extern forms | Unsupported; carrier similarity is not a semantic proof |
| Public or native ABI arrays | Unsupported; import/export ownership is separate |

“Direct” means that the source type is the built-in array with a closed element
type, not a typedef, abstract, type parameter, nested array, extern, or explicit
`Null<Array<T>>` wrapper. It does not claim that every Haxe array occurrence is
non-null.

## Boundary Decisions

| Boundary | Initial decision |
| --- | --- |
| Immutable local | Admit when its producer binds the exact descriptor-backed representation |
| Mutable or captured local | Admit only when all whole-array replacements use the same representation revision and the existing shared-cell rules hold |
| Instance or static field | Block |
| Array element storage | Require the exact `ArrayElement` representation first |
| `[]`, assignment, compound assignment, update | Keep separately operation-specific |
| Function argument, result, or return | Block until the call boundary owns both sides |
| Throw of a sealed represented local | Admit after the generic array hard cut |
| Throw of a direct array literal | Block until the literal-producer slice seals construction and evaluation order |
| Throw of a field or call result | Block until that producer is represented |
| `catch (value:Dynamic)` | May receive the same opaque array object |
| Typed `catch (value:Array<T>)` | Block; the runtime `Array` tag does not identify `T` |

A private throw can therefore precede array call-ABI support. It transports one
already represented value through the existing private exception channel and
does not expose an array argument, result, return, field, or typed catch.

## Hard-Cut Sequence

1. Add normalized direct/closed/flat array identity, the descriptor schema,
   deterministic registry/report data, and negative shape tests. Do not select
   new output yet.
2. Migrate the three existing `Array<Int>` representation decisions to the
   descriptor and bind the existing `Int` `ArrayElement` decision.
3. Make local planning resolve the descriptor and carry representation
   revisions. Preserve immutable, mutable, and captured replacement rules.
4. Make control consume a represented-array local reference and derive only the
   static `Array` kind needed for exception tags.
5. In that same hard-cut phase, delete exact `Array<Int>` carrier, conversion,
   proof, and inspection authority from control. Keep legitimately Int-specific
   array operations in their operation plans.
6. Add a separately owned direct `Array<Int>` literal producer. Prove ordered,
   exactly-once element construction and add a direct literal-throw tracer.
7. Harden public inspection against descriptor, representation, producer, and
   control corruption; rerun the complete portable and installed-package proof.
8. Audit Bool element storage as a later candidate. Keep String in a separate
   future element-representation task.

The hard cut removes semantic selection through these exact-family mechanisms:

- `isExactArrayInt`, `selectExactArrayInt`, and `exactArrayIntReason` as carrier
  or proof selectors;
- array-specific carrier recognition in local planning;
- direct exact-array selection from place planning, while retaining
  Int-specific operations;
- `BoxArrayIntThrowCarrier` and exact Array branches for throw tags, conversion,
  proof, matching, validation, and inspection; and
- `exactArrayIntThrowRepresentation`.

There must be one represented-array path after the cut, not selectable exact
and generic implementations. The new control conversion remains specific to
represented arrays; it is not a universal escape hatch for every represented
value.

## Required Evidence

The implementation children must record fresh candidate evidence for:

- Haxe 4.3.7 interpreter, JavaScript, and Neko behavior for creation, identity,
  aliasing, mutation, whole-array replacement, capture, throw, and Dynamic
  catch;
- the migrated `Array<Int>` local behavior, with the same generated carrier and
  no cloning or new wrapper;
- direct literal evaluation count and order before literal throws are admitted;
- immutable, mutable, captured, rebound, and aliased locals;
- explicit negatives for null arrays, nullable elements, unsupported type
  forms, calls, returns, fields, and typed catches;
- corruption of every descriptor edge, representation revision, producer
  reference, control conversion, runtime tag vector, and report binding;
- A-to-B-to-A registry reset determinism;
- OCaml compilation and runtime behavior;
- the complete portable portfolio and separate focused metal/profile checks;
- a fresh installed-package consumer; and
- formatting plus handwritten-OCaml ownership guards.

Historical evidence from `haxe_ocaml-w32h3.25` remains useful context, but it
does not count as execution evidence for a new implementation candidate.

## Stop And Request Another Architecture Review If

Stop the implementation before it:

- retains host compiler objects in the descriptor;
- substitutes an internal-value element decision for the required
  `ArrayElement` decision;
- parses target carrier text or generated syntax to recover an element type;
- adds `Obj.magic` to reconcile compiler facts;
- preserves exact and generic array semantic paths together;
- admits a literal without a sealed producer and evaluation schedule;
- treats the runtime `Array` tag as an element-type proof;
- accepts an ID while ignoring a mismatched revision;
- expands into recursive arrays, structural runtime types, typed array catches,
  public/native ABI, generalized casts or variance, a universal represented
  value IR, broad CFG/SSA, or target-syntax recovery.

No additional checkpoint is required for the flat descriptor, direct
`Array<Int>`, local/literal producers, opaque private throw, or deterministic
validation described here.

## Tracker And Readiness Disposition

- `haxe_ocaml-w32h3.26` owns this decision and may close only after the review
  is reconciled into this durable contract and bounded implementation children
  exist. Its closure proves a decision, not compiler capability.
- The first implementation child owns the descriptor, no-broadening
  `Array<Int>` registry/local migration, representation-revision binding,
  generic local throw hard cut, inspection, and corruption evidence.
- The immediate successor owns the direct `Array<Int>` literal producer and
  literal-to-control tracer.
- Bool and String remain deferred findings until those two slices provide the
  shared shape and producer boundary.
- `haxe_ocaml-w32h3` remains open. This decision does not claim generic arrays,
  array calls or returns, typed catches, nullable or nested arrays, control
  completion, or release readiness.
- README Goals and percentages do not change because planning alone adds no
  user-visible capability.

## Reconciliation Limits

Oracle inspected the checked evidence bundle but did not run repository tests.
The local reconciliation verified the material ownership and failure-boundary
claims against current source. It did not implement the descriptor, execute the
future validation matrix, or approve product readiness. Those are requirements
of the implementation children.
