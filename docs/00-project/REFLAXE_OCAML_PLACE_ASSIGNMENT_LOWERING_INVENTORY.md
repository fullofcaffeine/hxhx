# `reflaxe.ocaml` Place And Assignment Lowering Inventory

**Status:** implementation baseline for `haxe_ocaml-9v1va`

**Date:** 2026-07-18

**Architecture authority:**
[`ORACLE_CHECKPOINT_REFLAXE_OCAML_NATIVE_POWER_IR_2026_07_18.md`](ORACLE_CHECKPOINT_REFLAXE_OCAML_NATIVE_POWER_IR_2026_07_18.md)

## Practical outcome

Assignment and update behavior is not yet owned by one validated target model.
It is selected while `OcamlBuilder` is already constructing OCaml syntax, with
related storage and carrier choices split between that file and
`OcamlCompiler`. Before either component runs, Reflaxe's default
`EverythingIsExprSanitizer` also rewrites assignment expressions into an
assignment statement followed by another read of the left-hand side. The
upstream oracle added for this Bead exposes why that generic rewrite is not
semantics-preserving for effectful places.

The first implementation slice will therefore introduce one small typed
place/evaluation family before `OcamlExpr` construction. It will not introduce
a broad control-flow graph, mirror the Haxe typed tree, or create a shared
cross-target representation IR.

## Current ownership

| Decision | Current owner | Evidence and risk |
| --- | --- | --- |
| Assignment used as a value | Reflaxe `EverythingIsExprSanitizer.standardizeAssignValue` before target compilation | The generic pass inserts the assignment as a separate statement and returns a copied left-hand side. For `receiver().field = rhs`, that causes a second receiver evaluation. The OCaml target currently enables this pass through `ExpressionPreprocessorHelper.defaults()`. |
| Simple assignment | `OcamlBuilder.buildBinop`, approximately lines 4106-4250 | Local, instance, static, anonymous/dynamic, array, and bytes cases each construct target syntax directly. Several unhandled states return OCaml `unit`. |
| Compound assignment | `OcamlBuilder.buildBinop`, approximately lines 4251-4590 | Operator selection, receiver sharing, load, arithmetic, store, and result are repeated per place kind. Ref, field, and static stores currently return OCaml `unit` in expression position. |
| Prefix/postfix update | `OcamlBuilder.buildUnop`, approximately lines 5377-5707 | Numeric classification, nullable/Dynamic representation, place handling, store, and old/new result selection are intertwined. Unsupported states return `unit`. |
| Straight-line local assignment | `OcamlBuilder.buildBlockFromIndex`, from approximately line 5832 | A second path rewrites non-ref local assignment as OCaml `let` shadowing, so local storage and expression lowering do not share one durable plan. |
| Local mutation and capture | `collectMutatedLocalIds*` and `collectRefLocalIds*`, from approximately line 6309 | Correctness facts live in mutable traversal maps and are consumed later by syntax construction. This is follow-up Bead `haxe_ocaml-9bome`, but the first place model must leave it a stable home. |
| Field layout and carrier type | `OcamlCompiler` plus `OcamlBuilder` helpers | Record layout, `Obj.t`, null, default, receiver cast, and conversion choices are selected in more than one component. The place slice records references to the selected facts; it does not attempt the full representation migration. |
| Runtime need | `RuntimeUsageCollector` and `RuntimeCopier` after syntax construction | The structured scan is useful as a consistency check, but it cannot be the semantic source of truth and cannot see through opaque raw fragments. |
| Unsupported behavior | `guardrailError` plus `CUnit` branches | Errors are suppressed while compiling the current Haxe standard library. Bootstrap continuity must not become the release failure policy for an admitted place form. |

At the time of this inventory, `OcamlBuilder.hx` is 7,688 physical lines and
`OcamlCompiler.hx` is 3,555. New place, schedule, identity, and validation logic
must live in focused modules; the cutover should make the builder smaller rather
than create another semantic subsystem inside it.

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
`test/oracle/reflaxe_ocaml_place_evaluation_seed` runs 24 cases through
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

The first model must be small but reusable. It will represent:

1. a stable source origin and place occurrence identity;
2. the Haxe semantic value type separately from the selected OCaml carrier;
3. place kind plus explicit receiver/index/getter/setter occurrences;
4. an ordered schedule that can share or repeat each occurrence according to
   the oracle;
5. load, conversion, operator/call, store, and result steps;
6. conservative effects and semantic runtime-requirement identifiers;
7. a deterministic unsupported-state diagnostic.

Before report-only lowering can be trusted, the target adapter must preserve an
assignment/update occurrence as one semantic input node. It must not ask the
lowerer to infer that two already-separated expressions were formerly one
assignment. The bounded integration choices are:

- add an explicit Reflaxe sanitizer option that preserves assignment values and
  consume a pinned framework version containing it; or
- replace that one generic pass with a focused target-owned normalizer that
  preserves assignment/update nodes while retaining only the block-like
  rewrites the current target still needs.

Wrapping, pattern-matching, or recombining the already-split expressions in the
backend is rejected: receiver effects and stable expression identity have
already been lost at that point. Disabling every preprocessor in one step is
also outside this slice because unrelated target behavior currently depends on
the remaining normalization passes.

The report-only step will classify the fixture without changing emission. The
first hard cut will then admit ordinary numeric simple/compound/update forms
whose full place schedule is represented and validated. Properties remain
host-resolved calls rather than being guessed from field spelling. Abstract
operators remain exact host-selected calls/bodies rather than being treated as
ordinary numeric updates.

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
