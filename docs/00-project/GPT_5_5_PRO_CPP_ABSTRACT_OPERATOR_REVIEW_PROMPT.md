# GPT-5.5 Pro C++ Abstract-Operator Architecture Review Prompt

Prepared: 2026-07-14

Repository baseline: `fullofcaffeine/hxhx` commit
`d33bc427484cece0d3f8196bc9890254f3848fb0`

Owning bead: `haxe_ocaml-ass5p`

Related strict-C++ beads:

- `haxe_ocaml-94hk1` - remaining strict C++ render attribution
- `haxe_ocaml-p3k4i` - expected types for empty generic constructors (closed)
- `haxe_ocaml-36ec` - incremental extraction from the C++ target mega-file

Status: architecture review request, not an implementation decision

Give this file to GPT-5.5 Pro with the repository at the exact commit above.
The reviewer should inspect the whole repository, then concentrate on the files
and evidence named below. This file is the controlling prompt.

## Read this first: the problem in plain language

The strict C++ target now gets far enough through the upstream Haxe 4.3.7 unit
suite to reach abstract unary operators. Haxe abstracts can define what an
operator means with metadata such as `@:op(-A)` and `@:op(++x)`.

The generated C++ currently ignores those declarations:

- unary minus is emitted as raw C++ `-value`, even when the value is a
  class-backed Haxe abstract whose declared helper must run;
- primitive-backed abstracts are stored as their underlying C++ primitive, but
  their semantic Haxe type and operator helper are lost at the operator site;
- prefix increment has already been rewritten by the parser into `value += 1`.

The first two problems have plausible C++-target seams. The third exposes a
compiler-model problem: after parsing, `++value` and source-written
`value += 1` are the same `EBinop("+=", value, 1)` node. They can legally select
different abstract operators, so a C++-only guess based on the right-hand
literal would be a band-aid and could miscompile valid Haxe.

We need an independent architecture recommendation before implementation.
The desired answer is the smallest sound ownership boundary for preserving
operator syntax, resolving `@:op` helpers, retaining abstract semantic types
when their runtime carrier is erased, and emitting correct C++ without forcing
every target to duplicate a partial Haxe typer.

## Your role

Act as an independent principal compiler architect and parity-evidence
reviewer. Inspect the uploaded repository as a whole, challenge the local
interpretation, and recommend a safe sequence of implementation slices.

This is a design review. Do not write implementation code for direct
transcription. Return a seam recommendation, invariants, tradeoffs, migration
slices, and a validation plan. Explain the result for Haxe contributors who are
not compiler specialists.

## Decision requested

Recommend where and how `hxhx` should represent and resolve Haxe abstract
operators, with an immediate path that unblocks the C++ strict frontier without
creating target-specific semantic debt.

The review must decide among, refine, or replace these layers:

1. **Syntax preservation** - whether the shared expression AST should retain
   distinct prefix/postfix increment and decrement nodes instead of normalizing
   prefix forms to compound assignment during parsing.
2. **Operator binding** - whether the typer should bind an operator expression
   to an exact declared abstract helper, or whether backends may resolve helpers
   from semantic type plus metadata.
3. **Carrier lowering** - how a backend should keep the Haxe abstract type while
   representing a primitive-backed value as `int`, `double`, or another native
   carrier.
4. **Mutation lowering** - how prefix/postfix result values and mutation happen
   exactly once for identifiers, fields, and array-access lvalues.
5. **Backend emission** - how C++ should invoke static and instance operator
   helpers and convert helper results back to the chosen runtime carrier.

If full typed operator binding is the correct long-term model but too large for
the next slice, define an explicit intermediate representation that is honest,
target-neutral, and removable. Do not recommend inferring original syntax from
`EBinop("+=", ..., 1)`.

## Non-negotiable project constraints

- Upstream Haxe 4.3.7 is the semantic oracle, not an implementation donor.
- Do not copy, translate, mechanically rewrite, or retype upstream Haxe
  compiler source.
- Do not vendor upstream Haxe compiler tests or fixtures. The repository runs
  them from an ignored checkout and adds original focused regressions.
- Shipping code and inbound dependencies must remain MIT-compatible.
- Full 1.0 claims require relevant upstream-suite results. Focused local tests
  support diagnosis but cannot replace that evidence.
- Full 1.0 correctness must be stage0-free. Upstream `haxe` may remain a
  black-box behavior oracle and an explicit bootstrap-maintenance tool.
- Preserve the hard-cutover policy; do not add compatibility layers for the
  current lossy AST.
- Parser, resolver, typer, typed-AST, and diagnostic semantics remain ordinary
  Haxe-authored `hxhx` core responsibilities. Do not move them into Reflaxe or
  target-plugin APIs.
- Backends may own target carrier choices and source emission, but backend
  convenience is not a reason to weaken Haxe semantics.
- Avoid adding substantial new logic to
  `packages/hxhx-core/src/backend/cpp/CppTargetCore.hx`, which is already 26,790
  lines. Recommend an extraction seam when new logic is independently testable.
- Do not hide the current failure with a fake generated class, a large inline
  runtime string stub, or a helper-name special case.
- Do not weaken, skip, or reinterpret the strict C++ gate to call this fixed.

## Evidence collected at the baseline

### Exact strict probe

An exact current-source, stage0-forbidden C++ probe ran the upstream Haxe 4.3.7
unit target with no retries, 20-second heartbeats, and a 480-second target
timeout. It reached the native C++ compiler and exited expected-red after 436
seconds.

The preceding empty-`Map` error was gone. The first C++ error became:

```text
TestMain.cpp:16597:18: error: invalid argument type
'std::shared_ptr<MyAbstract_MyVector>' to unary expression
    auto vec2 = (-vec);
```

The next two abstract-operator errors were:

```text
TestMain.cpp:16602:13: error: member reference base type 'int' is not a
structure or union
    eq((-my).get(), (-12));

TestMain.cpp:16605:10: error: member reference base type 'int' is not a
structure or union
    eq(my.get(), 13);
```

Independent later failures are map-comprehension lowering and custom abstract
array access. Keep those out of this review slice.

The focused method timings were:

- `TestXML.testBasic`: 0.556382894516 seconds
- `TestXML` class: 5.15337705612 seconds
- `TestType.testAbstractGeneric`: 0.270284175873 seconds
- `TestType.testAbstractUnop`: 0.185279130936 seconds

The local retained evidence paths, if supplied with the review bundle, are:

- `.artifacts/full1/cpp-strict-current/gate3-cpp-unfiltered-after-empty-map-expected-type.log`
- `.artifacts/full1/cpp-strict-current/gate3-cpp-unfiltered-after-empty-map-expected-type-artifacts/gate3-target-artifacts/Cpp/unit__bin__cpp__src__TestMain.cpp`

These ignored artifacts are diagnostic evidence, not source inputs.

### Generated shape

The relevant generated C++ is:

```cpp
void testAbstractUnop() {
  std::shared_ptr<MyAbstract_MyVector> vec =
      std::make_shared<MyAbstract_MyVector>(1, 2, 3);
  auto vec2 = (-vec);
  // ...
  auto my = 12;
  eq((-my).get(), (-12));
  // ...
  my += 1;
  eq(my.get(), 13);
}
```

The class-backed abstract's declared static helper is already emitted:

```cpp
static std::shared_ptr<MyAbstract_MyPoint3> invert(
    std::shared_ptr<MyAbstract_MyVector> t) {
  return std::make_shared<MyAbstract_MyPoint3>(
      -t->get_x(), -t->get_y(), -t->get_z());
}
```

The primitive-backed abstract helper class is emitted as an empty two-line
struct because the current target erases its instance methods and instead
inlines a few recognized method bodies at call sites.

### Parser evidence

`packages/hxhx-core/src/HxParser.hx` currently parses postfix `++`/`--` as
`EUnop("post++" | "post--", value)`, but parses prefix forms as compound
assignment:

```haxe
// Bring-up lowering: treat prefix increment/decrement as compound assignment.
// Expression-level old/new value distinction is deferred.
final op = (c == "+".code) ? "+=" : "-=";
EBinop(op, parseUnaryExpr(stop), EInt(1));
```

This is direct proof that source `++value` cannot be distinguished later from
source `value += 1` by inspecting `HxExpr` alone.

### Typer evidence

`packages/hxhx-core/src/TyperStage.hx` traverses `EUnop` but does not bind it to
an abstract operator helper. Unary numeric inference returns the operand's
numeric type and otherwise remains unknown. There is no typed operator-call
node carrying owner, helper, operands, result type, or mutation mode.

### C++ target evidence

`packages/hxhx-core/src/backend/cpp/CppTargetCore.hx`:

- emits unary `-`, `!`, `~`, and postfix increment/decrement as raw C++ syntax;
- retains original Haxe local hints in `CppRenderScope.localTypeHints`, even
  when `CppTypeModel` erases a primitive-backed abstract to its C++ carrier;
- has bounded class-backed and primitive-backed abstract helpers already;
- dispatches a small set of binary abstract operators today, but selects
  class-backed helpers by method names such as `add`, `scalar`, and
  `scalarAssign`, not by fully resolved `@:op` semantics;
- renders primitive-backed abstract helper structs without instance methods and
  recognizes a few instance method bodies for target-local inlining.

This means the unary failure is not isolated from the broader abstract
operator model. The review should say whether the existing binary name-based
dispatch should be migrated in the same architecture sequence or deliberately
left for a separate bead.

### Metadata evidence

Function metadata is preserved as source-shaped strings such as `@:op(-A)` and
`@:op(++x)` on `HxFunctionDecl`. The parser and lightweight scanner merge these
strings, but no shared helper currently parses an `@:op` declaration into a
typed operator descriptor.

## Upstream behavior that the implementation must reproduce

Use upstream Haxe 4.3.7 as a black-box oracle for an original repository-owned
fixture with names and structure that are not copied from upstream tests. The
fixture must cover at least:

- static unary minus on a class-backed abstract;
- instance unary minus on a primitive-backed abstract;
- prefix increment on a primitive-backed abstract;
- prefix versus postfix result and mutation behavior where the declared
  operator surface supports both;
- a compound-assignment case that proves `++x` is not confused with `x += 1`;
- side-effecting operand, receiver, property, and array-index evaluation counts,
  measured against upstream rather than assumed to be exactly once;
- ordinary numeric controls;
- an ordinary class with similarly named methods that is not treated as an
  abstract operator;
- helper methods whose names differ from `invert`, `incr`, `add`, and other
  existing C++ special cases, proving metadata-driven selection.

Do not copy upstream fixture source. The upstream suite remains the final
strict proof after focused behavior is green.

### Original oracle checkpoint: evaluation-count assumptions need correction

An original temporary fixture was run with upstream Haxe 4.3.7 through
`--interp`, generated JavaScript on Node, and generated Neko bytecode. All
three routes agreed:

- arbitrary-name class-backed and primitive-backed unary-minus helpers were
  selected once;
- distinct `@:op(++x)`, `@:op(x++)`, and `@:op(A += B)` declarations selected
  the prefix, postfix, and compound helpers respectively for a local;
- two overloaded increments on an array element evaluated a side-effecting
  index four times total, while the corresponding ordinary-`Int` array control
  evaluated it twice total;
- two overloaded increments on an ordinary field evaluated the side-effecting
  receiver twice total and selected the prefix/postfix helpers;
- the equivalent property shape called its getter and setter once per
  operation but did not select those abstract helpers in this fixture.

This is black-box behavior evidence from original source, not copied upstream
fixture or implementation material. It disproves the earlier blanket draft
assumption that every overloaded lvalue index is evaluated exactly once. The
review must distinguish required Haxe 4.3.7 compatibility from a deliberate
semantic improvement. A backend must not silently choose the latter while
claiming strict parity.

## Candidate architecture directions to challenge

These are hypotheses, not decisions. Rank, combine, or reject them.

### Direction A: preserve syntax, resolve operators in each backend

- Parse prefix increment/decrement as distinct `EUnop` modes.
- Update every backend to preserve existing ordinary numeric behavior.
- Let C++ inspect semantic Haxe hints plus `@:op` metadata and choose a helper.

Concern: this fixes the syntax loss but duplicates Haxe overload resolution and
diagnostics across backends.

### Direction B: preserve syntax, then bind an abstract operator in the typer

- Add explicit prefix/postfix syntax representation.
- Let the typer resolve the exact operator declaration and result type.
- Carry a typed operator descriptor or typed helper call into backend IR.
- Let each backend choose only the runtime carrier and call emission.

Concern: this is semantically cleaner but may be larger than the immediate C++
frontier. Define the minimum useful rung and how incomplete operator families
fail instead of silently falling back.

### Direction C: introduce a dedicated operator expression model

- Replace stringly `EUnop`/selected `EBinop` modes with a structured operator
  kind containing fixity, mutation, and old/new result semantics.
- Bind abstract helpers in a later typed phase.

Concern: this may create broad churn across parser, macro-expression quoting,
source targets, VM targets, tests, and bootstrap snapshots. Determine whether
increment/decrement can be cut over first without a half-compatible AST.

### Direction D: C++-only recovery from `+= 1`

- If a local's retained Haxe type is a primitive-backed abstract with
  `@:op(++x)`, reinterpret `EBinop("+=", local, 1)` as prefix increment.

The local assessment is that this is not parity-safe because original syntax
has already been lost. Accept this direction only if you can state a rigorous
invariant that proves no valid Haxe program can be misclassified. Convenience
for the current upstream test is not sufficient.

## Questions you must answer

1. Which phase should own exact `@:op` overload selection and diagnostics?
2. What expression/typed-IR shape should distinguish prefix, postfix, compound
   assignment, mutation target, helper declaration, and result type?
3. Is preserving `pre++`/`pre--` in `HxExpr` an appropriate first hard cutover,
   or should a structured operator kind replace the current string tags now?
4. How can the first slice update all affected backends without pretending that
   abstract-operator resolution is complete everywhere?
5. How should macro expression quoting/printing expose the new syntax shape?
6. How should the typer retain an abstract semantic type separately from its
   backend carrier, especially for primitive-backed abstracts?
7. Should class-backed abstract values continue to use wrapper objects in C++,
   or should their underlying carrier be represented directly? What invariants
   decide this per abstract?
8. How should static and instance operator helpers be normalized for backend
   calls?
9. For primitive-backed abstracts, should C++ emit target-native static helper
   functions, inline typed helper bodies, or use another representation?
10. How should prefix/postfix result, mutation, and lvalue evaluation counts be
    represented for identifiers, ordinary fields, properties, and array access,
    given the measured upstream differences above? Which behavior is required
    for Full1 parity, and which possible exactly-once improvement would require
    a separate explicit compatibility decision?
11. What should happen when an operator declaration is missing, ambiguous,
    generic, commutative, overloaded, or has an unsupported body?
12. Should the existing C++ binary helper-name dispatch be migrated immediately
    to the same model, or sequenced after unary correctness? Why?
13. Which new modules should own operator metadata parsing, binding, and C++
    emission so `CppTargetCore.hx` does not absorb another subsystem?
14. Which bootstrap snapshots are expected to change, and how can churn be
    bounded and provenance-reviewed?
15. What is the smallest sequence of reviewable beads and commits?
16. What exact local, current-source, strict upstream-suite, and CI evidence is
    necessary before closing `haxe_ocaml-ass5p`?

## Required invariants to evaluate

Challenge and refine this draft set:

- Prefix and postfix syntax survives parsing without inference from literal
  operands.
- Abstract operator selection uses declared `@:op` metadata and semantic types,
  never helper names.
- The selected declaration, operand conversion, result type, and mutation mode
  are explicit before target emission.
- Runtime carrier erasure does not erase the semantic abstract type.
- Helper invocation and operand evaluation do not duplicate work beyond the
  behavior selected by the shared lowering contract.
- Lvalue receiver/index evaluation follows measured upstream Haxe 4.3.7
  behavior for the strict compatibility profile; any exactly-once divergence
  is explicit, separately tested, and excluded from an unqualified parity
  claim.
- Prefix returns the new value and postfix returns the old value when the Haxe
  operator contract requires a value.
- Mutation is visible to the original lvalue and does not mutate a temporary.
- Ordinary numeric operators keep their current behavior.
- Ordinary classes cannot gain operator behavior from similarly named methods.
- Unsupported or ambiguous abstract operators fail with a deterministic
  compiler diagnostic rather than raw target compiler errors.
- All backends consume the same typed operator decision, or an explicitly
  documented interim boundary with a removal bead.
- Focused tests do not replace upstream Haxe 4.3.7 suite evidence.
- No implementation source or test fixture is copied from upstream Haxe.

## Required validation plan

Give concrete evidence tiers and stop conditions for:

1. parser tests proving distinct prefix/postfix/compound AST shapes;
2. typer tests proving metadata-driven helper binding, result type, ambiguity,
   and missing-operator diagnostics;
3. an original upstream Haxe 4.3.7 oracle fixture across interpreter plus at
   least two generated targets, including side-effecting local, ordinary-field,
   property, and array-index controls;
4. focused C++ source-shape assertions and executable stdout;
5. cross-backend ordinary increment/decrement regressions;
6. macro-expression quoting/printing compatibility;
7. official Haxe formatting and repository guards;
8. a freshly built current-source compiler with stage0 forbidden during proof;
9. the exact strict C++ upstream target with the old errors absent and the next
   independent frontier recorded;
10. bootstrap snapshot regeneration only if the shared parser/typed model
    requires it, including current-source and snapshot equivalence evidence;
11. CI on the exact pushed commit;
12. README Goals/North Star review without inflating readiness for an internal
    frontier fix.

Define explicit stop conditions for a design that would require broad semantic
fallbacks, target-specific syntax recovery, large generated snapshot churn
without a stable model, or another expansion of the C++ mega-file.

## Repository materials to inspect

Inspect the repository as a whole, then trace at least these paths:

- `AGENTS.md`
- `README.md`, especially the Goals status table
- `.beads/issues.jsonl`
- `docs/00-project/NORTH_STAR_GOALS.md`
- `docs/00-project/FULL_1_0_CONTRACT.md`
- `docs/00-project/CPP_RENDER_TYPE_FLOW_PLAN.md`
- `docs/00-project/CPP_HELPER_RENDERING_POLICY.md`
- `docs/00-project/CPP_TARGET_RUNTIME_POLICY.md`
- `docs/00-project/MEGA_FILE_GRAVITY_WATCH.md`
- `packages/hxhx-core/src/HxExpr.hx`
- `packages/hxhx-core/src/HxParser.hx`
- `packages/hxhx-core/src/ParserStage.hx`
- `packages/hxhx-core/src/ParserStageScanHelpers.hx`
- `packages/hxhx-core/src/TyperStage.hx`
- `packages/hxhx-core/src/EmitterStage.hx`
- `packages/hxhx-core/src/backend/cpp/CppRenderScope.hx`
- `packages/hxhx-core/src/backend/cpp/CppTypeModel.hx`
- `packages/hxhx-core/src/backend/cpp/CppAbstractProjection.hx`
- `packages/hxhx-core/src/backend/cpp/CppTargetCore.hx`
- `packages/hxhx-core/src/backend/js/JsExprEmitter.hx`
- `packages/hxhx-core/src/backend/js/JsTargetCore.hx`
- `packages/hxhx-core/src/backend/source/SourceTargetCommon.hx`
- `packages/hxhx-core/src/backend/vm/NekoTargetCore.hx`
- `test/M14CppNativeBackendSmokeIntegrationTest.hx`
- `test/M14HihCompoundAssignIntegrationTest.hx`
- `test/M14JsTargetCoreSysToolsIntegrationTest.hx`
- `scripts/ci/run-full1-suites-strict.js`

Use upstream Haxe 4.3.7 only as a behavior and architecture reference. Do not
return copied upstream implementation code or a transcription plan.

## Required response format

Return:

1. a short verdict on the correct ownership seam;
2. the recommended expression and typed-operator model;
3. the immediate C++ unblock slice;
4. the cross-backend migration sequence;
5. rejected alternatives and why they are unsafe;
6. invariants and deterministic failure behavior;
7. a bead/commit sequence with acceptance evidence;
8. a validation matrix from focused oracle through exact strict C++ and CI;
9. mega-file and bootstrap-snapshot risk controls;
10. any question that genuinely requires a human product decision.

Do not provide implementation code for direct transcription. The goal is a
safe way forward: seam selection, tradeoffs, invariants, sequencing, and proof.
