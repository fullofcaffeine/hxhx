# `reflaxe.ocaml` Place And Assignment Lowering Inventory

**Status:** implementation baseline for `haxe_ocaml-9v1va`

**Date:** 2026-07-18

**Architecture authority:**
[`ORACLE_CHECKPOINT_REFLAXE_OCAML_NATIVE_POWER_IR_2026_07_18.md`](ORACLE_CHECKPOINT_REFLAXE_OCAML_NATIVE_POWER_IR_2026_07_18.md)

## Practical outcome

The first hard-cut family now owns value-producing simple assignment, `+=`, and
both fixities of `++` and `--` for an ordinary record-backed `Int` instance
field. An assignment RHS must also be an exact semantic `Int`. The target
preserves the atomic typed operation before Reflaxe's generic
`EverythingIsExprSanitizer`, seals a typed place and ordered occurrence
schedule, validates it, and only then constructs `OcamlExpr`.
`receiver().field = rhs()` evaluates the receiver and right-hand side once,
stores once, and returns the assigned value without rereading the place. For
`receiver().field += rhs()`, the plan saves the old field value before the RHS,
performs Haxe `Int` addition, stores once, and returns the computed value.
`receiver().field++` returns the saved old value after the store, while
`++receiver().field` returns the computed value.
Decrement follows the same fixity contract with an explicit delta of minus one.
Value-producing simple assignment to an exact-`Int` mutable static is also
sealed before syntax when the cell belongs to the current type or another OCaml
module. Its receiver-free schedule is RHS, ref-cell store, then the shared RHS
result; the plan selects local versus qualified target access explicitly.
Exact nominal `Array<Int>` simple assignment now also seals the array receiver,
index, RHS, store, and shared RHS result in source order. It uses the direct
`int HxArray.t` carrier without an `Obj.magic` cast and records the semantic
`haxe-array-element-set` runtime requirement before syntax construction.
Exact primitive-`Int` `+=` on that same array place additionally seals the old
element load before the RHS, Haxe `Int` addition, one store, and the computed
result. This remains an exact nominal carrier cut; other array-like abstracts
are not reclassified as `Array<Int>`.

Other assignment and update behavior is still selected while `OcamlBuilder` is
constructing OCaml syntax, with related storage and carrier choices split
between that file and `OcamlCompiler`. Those forms remain migration debt, not
evidence that the first typed family is broad enough to infer their semantics.
This slice introduces neither a broad control-flow graph, a mirror of the Haxe
typed tree, nor a shared cross-target representation IR.

## Current ownership

| Decision | Current owner | Evidence and risk |
| --- | --- | --- |
| Assignment used as a value | Target preservation for admitted forms; Reflaxe `EverythingIsExprSanitizer.standardizeAssignValue` for the remainder | The generic pass inserts an assignment as a separate statement and returns a copied left-hand side. Target metadata now protects the admitted simple and `+=` forms; other forms still carry the original risk until migrated. |
| Exact `Int` instance-field simple assignment | `OcamlPlaceAssignmentPlanner`, validator, and emitter before `OcamlExpr` construction | One admitted family has a stable origin, representation facts, occurrence schedule, result contract, and fail-closed invariant. Its old instance-field branch is guarded against use. |
| Exact primitive-`Int` instance-field `+=` | The same typed place model before `OcamlExpr` construction | The plan records receiver, old-value load, RHS, `int-add`, store, computed result, and the semantic `haxe-int32-add` runtime requirement. The legacy branch is guarded against use. |
| Exact primitive-`Int` instance-field `++` / `--` | The same typed place model before `OcamlExpr` construction | Source token, signed delta, and prefix/postfix fixity are separate facts. Every schedule records one receiver, load, Haxe `int-add`, store, and the fixity-selected old or computed result. |
| Exact `Int` static simple assignment | The same typed place model before `OcamlExpr` construction | Current-type and cross-module mutable ref cells record stable symbol, representation, local/qualified access, RHS, store, and assigned result without inventing a receiver occurrence. |
| Exact nominal `Array<Int>` simple assignment | The same typed place model before `OcamlExpr` construction | The plan records canonical array/element/index identities, diagnostic display types, the direct typed HxArray carrier, receiver/index/RHS order, one store, the assigned result, and its runtime capability. Typedef- or abstract-backed array syntax is deliberately not inferred to have the same carrier. |
| Exact primitive-`Int` `Array<Int>` `+=` | The same typed place model before `OcamlExpr` construction | Receiver and index setup feed one old-element load, the RHS, Haxe `Int` addition, one store, and the shared computed result. `HxArray` get/set and `HxInt` addition requirements are recorded before syntax. |
| Other simple assignment | `OcamlBuilder.buildBinop`, approximately lines 4106-4250 | Local, same-module cross-type static, anonymous/dynamic, bytes, non-Int or non-nominal array, and deliberately unadmitted instance-field cases still construct target syntax directly. Several unhandled states return OCaml `unit`. |
| Other compound assignment | `OcamlBuilder.buildBinop`, approximately lines 4251-4590 | Other operators and place kinds still repeat operator selection, receiver sharing, load, arithmetic, store, and result. Ref, field, and static stores can still return OCaml `unit` in expression position. |
| Other prefix/postfix update | `OcamlBuilder.buildUnop`, approximately lines 5377-5707 | Other place kinds, Float, nullable, Dynamic, and abstract handling still combine numeric classification, representation, place mutation, and old/new result selection. Unsupported states can return `unit`. |
| Straight-line local assignment | `OcamlBuilder.buildBlockFromIndex`, from approximately line 5832 | A second path rewrites non-ref local assignment as OCaml `let` shadowing, so local storage and expression lowering do not share one durable plan. |
| Local mutation and capture | `collectMutatedLocalIds*` and `collectRefLocalIds*`, from approximately line 6309 | Correctness facts live in mutable traversal maps and are consumed later by syntax construction. This is follow-up Bead `haxe_ocaml-9bome`, but the first place model must leave it a stable home. |
| Field layout and carrier type | `OcamlCompiler` plus `OcamlBuilder` helpers | Record layout, `Obj.t`, null, default, receiver cast, and conversion choices are selected in more than one component. The place slice records references to the selected facts; it does not attempt the full representation migration. |
| Runtime need | `RuntimeUsageCollector` and `RuntimeCopier` after syntax construction | The structured scan is useful as a consistency check, but it cannot be the semantic source of truth and cannot see through opaque raw fragments. |
| Unsupported behavior | `guardrailError` plus `CUnit` branches | Errors are suppressed while compiling the current Haxe standard library. Bootstrap continuity must not become the release failure policy for an admitted place form. |

At the baseline inventory, `OcamlBuilder.hx` was 7,688 physical lines and
`OcamlCompiler.hx` was 3,555. After the current cutovers, they are 7,642 and 3,561
lines respectively. Place planning, validation, reporting, and emission live in
focused `lowered/` modules. Existing source-position caching also moved out of
the builder, so the semantic cutovers reduced the mega-file by 46 lines overall
instead of adding another responsibility to it.

## Place coverage already attempted by the emitter

| Place kind | Simple assignment | Compound assignment | Ordinary update | Important current limitation |
| --- | --- | --- | --- | --- |
| Local | Ref-cell path plus separate block-shadowing path | Ref-cell path | Ref-cell path | Storage classification and lowering are split. |
| Static field | Mutable ref cell | Mutable ref cell | Mutable ref cell | Invalid/immutable cases can diagnose and still produce `unit`. |
| Instance field | Mutable record field | Mutable record field | Mutable record field | Receiver and result behavior are constructed independently in each branch. |
| Property | Usually host-resolved accessor call | Usually host-resolved getter/operator/setter calls | Usually host-resolved getter/setter calls | Setter return value is semantically significant and must remain explicit. |
| Array element | Typed place path for exact nominal `Array<Int>`; `HxArray.set` otherwise | Typed place path for exact primitive-`Int` `+=`; builder-local `get`, operation, `set` otherwise | `get`, operation, `set` | Other compound operators, update, and non-direct carriers still rely on builder-local scheduling. |
| Bytes element | `HxBytes.set` | `get`, operation, `set` | `get`, operation, `set` | Setter result differs from ordinary array helper conventions. |
| Anonymous field | `HxAnon.set` | No complete dedicated path | No ordinary typed path | Some named shapes intentionally return `unit`. |
| Dynamic field | `HxAnon.set` through `Obj.repr` | No complete dedicated path | Dynamic numeric path | Dynamic tagging, place semantics, and unsafe carrier operations are coupled. |

Abstract overloads are a separate semantic category. Prefix or postfix spelling
does not authorize the target to invent old/new return behavior or writeback.
Once the host selects an abstract helper, the target must consume the exact call
or structurally lowered inline body.

## Frozen Haxe 4.3.7 behavior

The fixture at
`test/oracle/reflaxe_ocaml_place_evaluation_seed` runs 26 cases through
interpreter, JavaScript/Node, and Neko. Run it with:

```bash
npm run test:reflaxe-ocaml:place-oracle
```

The following event schedules are the accepted OCaml contract. `receiver`,
`array`, and `dynamic` identify receiver evaluation; `index`, `get`, `set:*`,
and `rhs` are independently observable effects.

| Place | Simple assignment | Compound assignment | Postfix update | Prefix update |
| --- | --- | --- | --- | --- |
| Local | `rhs` | `rhs` | none | none |
| Static | `rhs` | `rhs` | none | none |
| Instance field | `receiver,rhs` | `receiver,rhs` | `receiver` | `receiver` |
| Property | `receiver,rhs,set:7` | `receiver,get,rhs,set:13` | `receiver,get,set:11` | `receiver,get,set:11` |
| Array | `array,index,rhs` | `array,index,rhs` | `array,index` | `array,index` |
| Dynamic field | `dynamic,rhs` | `dynamic,rhs` | `dynamic` | `dynamic` |

Neko alone reports `index,array,rhs` for simple array assignment. Interpreter
and JavaScript agree on `array,index,rhs`, which also follows source order, so
that is the selected OCaml behavior. The Neko output is retained separately;
it is evidence of an upstream target disagreement, not permission for a target-
local fallback.

### Assignment-result observations

- Plain local, static, field, array, and dynamic assignment returns the assigned
  right-hand-side value.
- Compound assignment returns the computed value after the operator.
- Ordinary instance-field compound assignment loads the old field value before
  evaluating its right-hand side. If that right-hand side mutates the same
  field, the operator still uses the saved old value and the final store
  overwrites the intervening mutation.
- Ordinary array compound assignment establishes the receiver and index, then
  loads the old element before evaluating the RHS. An RHS mutation of that same
  element is likewise overwritten by the operator result derived from the saved
  old value.
- Ordinary prefix update returns the new value; ordinary postfix update returns
  the old value.
- A property setter may return a value different from both the value passed to
  it and the value it stores. Simple assignment, compound assignment, and
  prefix update return the setter result in this fixture. Postfix update returns
  the old getter result.

These facts prohibit reconstructing an assignment result by rereading the place
after the store.

## Baseline target failure closed by the first compound cutover

Before this inventory was written, the same fixture was compiled through the
current target. Generated OCaml failed to typecheck because an instance-field
compound assignment was emitted as a record-field store of type `unit`, then
used where the Haxe expression required `int`:

```text
__assign_16 has type unit but int was expected
```

Inspection also showed simple field assignment followed by a second receiver
evaluation to recover the expression result. That would turn one upstream
`receiver` event into two if native compilation were allowed to continue.
The exact primitive-`Int` instance-field `+=` cutover now closes this failure,
and the exact nominal `Array<Int>` `+=` cutover closes the corresponding array
schedule. Other compound operators and place kinds remain separate frontiers
and must not be inferred from these results.

## First admitted semantic family

The first model is deliberately small but reusable. It represents:

1. a stable source origin and place occurrence identity;
2. the Haxe semantic value type separately from the selected OCaml carrier;
3. place kind plus explicit receiver/index/getter/setter occurrences;
4. an ordered schedule that can share or repeat each occurrence according to
   the oracle;
5. load, conversion, operator/call, store, and result steps;
6. conservative effects and semantic runtime-requirement identifiers;
7. a deterministic unsupported-state diagnostic.

The target adapter now preserves each admitted occurrence with target-owned
metadata before the destructive generic rewrite. It does not pattern-match or
recombine the already-split output. The preservation policy and planner share
the same admission predicate, while a legacy-branch guard fails if an admitted
shape ever arrives without its stable origin.

The current hard cuts admit only:

- simple assignment to an ordinary, non-extern, non-interface, record-backed
  instance field;
- exact primitive Haxe `Int` on both the field and right-hand side;
- the current direct OCaml `int` field carrier and record receiver carrier;
- receiver, right-hand-side, store, and assigned-result occurrences in that
  order, each with an explicit count of one;
- exact primitive-`Int` `+=` on that same place, with receiver, old-value load,
  RHS, `int-add`, store, and computed result in Oracle-proven order;
- exact primitive-`Int` prefix and postfix increment/decrement on that place,
  with source token, signed delta, and fixity retained independently from the
  explicit load, `int-add`, store, and old/computed result choice;
- exact primitive-`Int` simple assignment to a directly writable static on the
  current type or in another module, with no receiver occurrence and an
  explicit local/qualified OCaml ref-cell access decision;
- exact primitive-`Int` simple assignment through direct nominal `Array<Int>`,
  with receiver, index, RHS, store, and reused RHS result occurrences in that
  order and no target cast;
- exact primitive-`Int` `+=` through direct nominal `Array<Int>`, with receiver,
  index, old-element load, RHS, `int-add`, store, and reused computed result in
  Oracle-proven order;
- no compatibility-runtime requirement for field/static simple assignment,
  one `haxe-int32-add` requirement mapped to `HxInt` for `+=` and updates, and
  one `haxe-array-element-set` requirement mapped to `HxArray` for the admitted
  simple array store. Array `+=` records get, Haxe `Int` addition, and set as
  separate semantic requirements and selects both `HxArray` and `HxInt`.

It deliberately does not follow Haxe abstracts to their underlying `Int`, and
it does not admit nullable or `Dynamic` right-hand sides. Those require explicit
representation or conversion facts rather than an `Obj.magic`-backed guess.
The inspection artifact is deterministic: fixtures with
`expected.lowering.json` compile twice and must produce byte-identical reports.
Schema version 3 retains the structured update facts from version 2 and adds a
closed static-field report shape with symbol access and forward-declaration
facts rather than asking emission to rediscover storage.
Schema version 4 adds the array-element place, an explicit index occurrence,
canonical receiver/index identities alongside diagnostic display spellings,
selected `HxArray` get/set symbols, and semantic runtime requirements. The
array compound plan uses that existing closed shape and adds no schema version.
Lowered identities use function identity plus structural ordinal; source paths
and byte offsets remain diagnostic provenance and do not determine semantic
identity.

The next cutovers will extend this same node family to the remaining oracle-
proven simple and compound place/operator combinations, plus update cases, only
when each full schedule and result rule is represented and validated.
Properties remain host-resolved calls rather than being guessed from field
spelling. Abstract operators remain exact host-selected calls or bodies rather
than being treated as ordinary numeric updates.

### First-cut validation checkpoint

The focused executable fixture
`test/portable/fixtures/place_instance_field_assign` proves the event order,
mutation, assigned result, generated target shape, exact lowered report, and
repeat-build determinism. Its compound RHS temporarily writes `100` to the same
field; the lowered old-value load still produces and stores `14`, proving the
load happens before the RHS. The same fixture proves postfix `14/15` and prefix
`16/16` results, postfix decrement `16/15`, and prefix decrement `14/14`, with
one receiver event each. Selective-runtime mode includes `HxInt` from the
recorded runtime intent. The final admitted policy also passes
every portable fixture. During development, broad native compilation caught an
inherited-field carrier mismatch: the corrected plan now selects the derived
record from the semantic receiver type while retaining the base declaration as
field ownership. This removes the legacy inner receiver cast instead of adding
new `Obj.magic` use. Earlier broad sweeps also caught both an over-broad
nullable/Dynamic RHS policy and an operator guard that initially treated `-=`
as admitted `+=`; each was narrowed at the shared policy/model boundary.

The checkpoint also passes the Haxe 4.3.7 three-route Oracle, M3, M4 native,
M5 class, M6 array, M6 bytes, source-map integration, official Haxe formatting,
and the mega-file-gravity guard. The report and implementation are internal
correctness evidence, so the README Goals and North Star progress bars remain
unchanged.

The focused executable fixture
`test/portable/fixtures/place_static_field_assign` separately proves current-
type local access and cross-module qualified access. Both plans contain only
RHS, store, and assigned-result occurrences, compile twice to byte-identical
reports, and execute with exactly one RHS event. An attempted same-module
cross-type case exposed an existing ordering flaw: the current late
`requestForwardMutableStatic` request is discovered after the owning type may
already have emitted its initializer. That case remains unadmitted, and
`haxe_ocaml-stthl` owns a program/module-level two-phase static storage plan.

The focused executable fixture
`test/portable/fixtures/place_array_simple_assign` proves the accepted
`array,index,rhs` order, one store, the assigned result, direct typed HxArray
carrier, semantic runtime requirement, and repeat-build report determinism.
The legacy path previously evaluated the RHS first and, after Reflaxe split the
assignment-as-value expression, evaluated the array receiver and index again to
recover the result. The hard cut removes both errors. The fixture also includes
`haxe.ds.Vector<Int>` as a negative control: it still executes through its
existing `Obj.t HxArray.t` carrier but contributes no typed array-place plan.
The complete portable corpus caught that distinction when an early alias-
following policy tried to classify Vector as direct `Array<Int>`; the final
policy admits only a nominal Array carrier and adds no `Obj.magic`.

`test/portable/fixtures/place_array_compound_assign` proves receiver and index
setup followed by an old-element load before an RHS that temporarily stores
`100`. The sealed operation still computes, stores, and returns `23`, and the
report records the `HxArray` get/set plus `HxInt` addition requirements. The RHS
simple store is itself an admitted nested plan, so the two-plan report also
proves structural recursive lowering and repeat-build determinism. A native
`Array<Float>` `+=` control executes through the existing path without adding a
third plan, keeping the admission boundary exact.

Upstream Haxe's typed dump shows that complex compound lvalues arrive with
compiler-generated `base` and `index` setup locals. The place plan consumes
those normalized local reads; their original receiver/index calls remain
ordered immediately before the plan in the host typed body. The current local
storage path still initializes the generated `base` through an outer
`Obj.magic`, while the admitted array operation itself consumes the direct
`int HxArray.t` carrier and adds no further cast. Removing that earlier unsafe
local-storage conversion belongs to `haxe_ocaml-9bome`'s shared representation
registry, not to a second representation rule in the place emitter.

The following are deliberately deferred:

- other place/update forms;
- same-module cross-type mutable statics and static compound/update lowering
  until `haxe_ocaml-stthl` plans ref-cell declarations before type emission;
- full capture and local-storage unification (`haxe_ocaml-9bome`);
- the shared representation registry and removal of broad `Obj.magic` use;
- general call/conversion lowering (`haxe_ocaml-taef5`);
- control effects and any evidence-based function-local block form;
- typed OCaml imports, adapters, and stable exports;
- upstream-Haxe/hxhx host convergence.

## Hard-cut and stop rules

For each admitted place/update form:

- add the semantic plan and validator first;
- preserve the atomic host assignment/update node before Reflaxe's destructive
  assignment-value rewrite;
- compare its deterministic report with current generated behavior;
- make target syntax a mechanical rendering of the sealed plan;
- delete the old branch in the same bounded phase;
- fail at the Haxe source site if required semantics are not representable.

Stop and redesign if the slice requires a permanent old/new mode, hides a
semantic choice in `OcamlExpr`, assumes every effect occurs exactly once,
reconstructs a property or abstract helper from spelling, grows
`OcamlBuilder`, or needs target-wide CFG facts to express these tree-shaped
operations.
