# `reflaxe.ocaml` Place And Assignment Lowering Inventory

**Status:** implementation baseline for `haxe_ocaml-9v1va`

**Date:** 2026-07-18

**Architecture authority:**
[`ORACLE_CHECKPOINT_REFLAXE_OCAML_NATIVE_POWER_IR_2026_07_18.md`](ORACLE_CHECKPOINT_REFLAXE_OCAML_NATIVE_POWER_IR_2026_07_18.md)

## Practical outcome

The first hard-cut family now owns value-producing simple assignment to an
ordinary record-backed `Int` instance field when the right-hand side is also an
exact semantic `Int`. It preserves the atomic typed assignment before
Reflaxe's generic `EverythingIsExprSanitizer`, seals a typed place and ordered
occurrence schedule, validates it, and only then constructs `OcamlExpr`.
`receiver().field = rhs()` now evaluates the receiver and right-hand side once,
stores once, and returns the assigned value without rereading the place.

Other assignment and update behavior is still selected while `OcamlBuilder` is
constructing OCaml syntax, with related storage and carrier choices split
between that file and `OcamlCompiler`. Those forms remain migration debt, not
evidence that the first typed family is broad enough to infer their semantics.
This slice introduces neither a broad control-flow graph, a mirror of the Haxe
typed tree, nor a shared cross-target representation IR.

## Current ownership

| Decision | Current owner | Evidence and risk |
| --- | --- | --- |
| Assignment used as a value | Reflaxe `EverythingIsExprSanitizer.standardizeAssignValue` before target compilation | The generic pass inserts the assignment as a separate statement and returns a copied left-hand side. For `receiver().field = rhs`, that causes a second receiver evaluation. The OCaml target currently enables this pass through `ExpressionPreprocessorHelper.defaults()`. |
| Exact `Int` instance-field simple assignment | `OcamlPlaceAssignmentPlanner`, validator, and emitter before `OcamlExpr` construction | One admitted family has a stable origin, representation facts, occurrence schedule, result contract, and fail-closed invariant. Its old instance-field branch is guarded against use. |
| Other simple assignment | `OcamlBuilder.buildBinop`, approximately lines 4106-4250 | Local, static, anonymous/dynamic, array, bytes, and deliberately unadmitted instance-field cases still construct target syntax directly. Several unhandled states return OCaml `unit`. |
| Compound assignment | `OcamlBuilder.buildBinop`, approximately lines 4251-4590 | Operator selection, receiver sharing, load, arithmetic, store, and result are repeated per place kind. Ref, field, and static stores currently return OCaml `unit` in expression position. |
| Prefix/postfix update | `OcamlBuilder.buildUnop`, approximately lines 5377-5707 | Numeric classification, nullable/Dynamic representation, place handling, store, and old/new result selection are intertwined. Unsupported states return `unit`. |
| Straight-line local assignment | `OcamlBuilder.buildBlockFromIndex`, from approximately line 5832 | A second path rewrites non-ref local assignment as OCaml `let` shadowing, so local storage and expression lowering do not share one durable plan. |
| Local mutation and capture | `collectMutatedLocalIds*` and `collectRefLocalIds*`, from approximately line 6309 | Correctness facts live in mutable traversal maps and are consumed later by syntax construction. This is follow-up Bead `haxe_ocaml-9bome`, but the first place model must leave it a stable home. |
| Field layout and carrier type | `OcamlCompiler` plus `OcamlBuilder` helpers | Record layout, `Obj.t`, null, default, receiver cast, and conversion choices are selected in more than one component. The place slice records references to the selected facts; it does not attempt the full representation migration. |
| Runtime need | `RuntimeUsageCollector` and `RuntimeCopier` after syntax construction | The structured scan is useful as a consistency check, but it cannot be the semantic source of truth and cannot see through opaque raw fragments. |
| Unsupported behavior | `guardrailError` plus `CUnit` branches | Errors are suppressed while compiling the current Haxe standard library. Bootstrap continuity must not become the release failure policy for an admitted place form. |

At the baseline inventory, `OcamlBuilder.hx` was 7,688 physical lines and
`OcamlCompiler.hx` was 3,555. After the first cutover, they are 7,628 and 3,561
lines respectively. Place planning, validation, reporting, and emission live in
focused `lowered/` modules. Existing source-position caching also moved out of
the builder, so the semantic cutover reduced the mega-file by 60 lines overall
instead of adding another responsibility to it.

## Place coverage already attempted by the emitter

| Place kind | Simple assignment | Compound assignment | Ordinary update | Important current limitation |
| --- | --- | --- | --- | --- |
| Local | Ref-cell path plus separate block-shadowing path | Ref-cell path | Ref-cell path | Storage classification and lowering are split. |
| Static field | Mutable ref cell | Mutable ref cell | Mutable ref cell | Invalid/immutable cases can diagnose and still produce `unit`. |
| Instance field | Mutable record field | Mutable record field | Mutable record field | Receiver and result behavior are constructed independently in each branch. |
| Property | Usually host-resolved accessor call | Usually host-resolved getter/operator/setter calls | Usually host-resolved getter/setter calls | Setter return value is semantically significant and must remain explicit. |
| Array element | `HxArray.set` | `get`, operation, `set` | `get`, operation, `set` | Receiver/index sharing is a local syntax convention rather than a validated schedule. |
| Bytes element | `HxBytes.set` | `get`, operation, `set` | `get`, operation, `set` | Setter result differs from ordinary array helper conventions. |
| Anonymous field | `HxAnon.set` | No complete dedicated path | No ordinary typed path | Some named shapes intentionally return `unit`. |
| Dynamic field | `HxAnon.set` through `Obj.repr` | No complete dedicated path | Dynamic numeric path | Dynamic tagging, place semantics, and unsafe carrier operations are coupled. |

Abstract overloads are a separate semantic category. Prefix or postfix spelling
does not authorize the target to invent old/new return behavior or writeback.
Once the host selects an abstract helper, the target must consume the exact call
or structurally lowered inline body.

## Frozen Haxe 4.3.7 behavior

The fixture at
`test/oracle/reflaxe_ocaml_place_evaluation_seed` runs 25 cases through
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
- Ordinary prefix update returns the new value; ordinary postfix update returns
  the old value.
- A property setter may return a value different from both the value passed to
  it and the value it stores. Simple assignment, compound assignment, and
  prefix update return the setter result in this fixture. Postfix update returns
  the old getter result.

These facts prohibit reconstructing an assignment result by rereading the place
after the store.

## Reproduced current target failure

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
The reproducible target command is documented in the fixture README. This is a
known red implementation frontier, not an expected-output update.

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

The initial hard cut admits only:

- simple assignment to an ordinary, non-extern, non-interface, record-backed
  instance field;
- exact primitive Haxe `Int` on both the field and right-hand side;
- the current direct OCaml `int` field carrier and record receiver carrier;
- receiver, right-hand-side, store, and assigned-result occurrences in that
  order, each with an explicit count of one;
- no compatibility-runtime requirement.

It deliberately does not follow Haxe abstracts to their underlying `Int`, and
it does not admit nullable or `Dynamic` right-hand sides. Those require explicit
representation or conversion facts rather than an `Obj.magic`-backed guess.
The inspection artifact is deterministic: fixtures with
`expected.lowering.json` compile twice and must produce byte-identical reports.

The next cutovers will extend this same node family to the remaining oracle-
proven simple, compound, and update cases only when each full schedule and
result rule is represented and validated. Properties remain host-resolved calls
rather than being guessed from field spelling. Abstract operators remain exact
host-selected calls or bodies rather than being treated as ordinary numeric
updates.

### First-cut validation checkpoint

The focused executable fixture
`test/portable/fixtures/place_instance_field_assign` proves the event order,
mutation, assigned result, generated target shape, exact lowered report, and
repeat-build determinism. The final admitted policy also passed every portable
fixture: the broad run first exposed an accidentally admitted nullable/Dynamic
right-hand side in `haxe_io_bucket01_basic`; narrowing the policy to exact
semantic `Int` fixed that modeling error, and the complete corpus then passed.

The checkpoint also passes the Haxe 4.3.7 three-route Oracle, M3, M4 native,
M5 class, M6 array, M6 bytes, source-map integration, official Haxe formatting,
and the mega-file-gravity guard. The report and implementation are internal
correctness evidence, so the README Goals and North Star progress bars remain
unchanged.

The following are deliberately deferred:

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
