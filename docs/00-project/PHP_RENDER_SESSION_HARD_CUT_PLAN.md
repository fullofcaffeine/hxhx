# PHP Render-Session Hard-Cut Plan

This plan makes PHP code generation own its state for exactly one program and
one function. Its four implementation slices have now replaced all 45
process-wide “active PHP render” fields with explicit values carried by
PHP-owned renderers.

The practical result is simple: a failed PHP render cannot leave local types,
member lookups, or lambda-capture choices for the next compiler request. The
hard cut preserves the covered generated PHP behavior; it does not add PHP
language behavior, typed-module reuse, concurrent compilation, or a readiness
claim.

`PHP_RENDER_SESSION_HARD_CUT_PLAN:PASS`

## Smallest useful model

The intended lifetime is:

```text
sealed typed PHP program
  -> immutable PhpProgramRenderFacts
  -> immutable PhpModuleRenderFacts for one emitted module
  -> request-owned PhpProgramBodyRenderer
  -> immutable PhpFunctionLoweringPlan for one exact function
  -> PhpFunctionBodyRenderer instance
  -> explicitly derived PhpLexicalRenderScope values
  -> generated PHP bytes
```

A **render session** means the target-owned objects used while one program is
converted to PHP source. It does not mean a cache or a compiler server session.

A **lowering plan** means a sealed record of PHP-specific choices made before
printing syntax. For example, it can say that an already-resolved call needs
the PHP array helper or that an accessor must read its backing field directly.
The printer consumes that decision; it does not rediscover Haxe meaning from a
name or source-text type hint.

## Problem this plan removed

Before the hard cut, `PhpSourceTargetCore` delegated to the generic
`SourceTargetCommon.emitTarget` path. That path entered
`renderProgram(Php, ...)`, assigned program facts to static fields, entered
each function through nested `withPhp...` helpers, and let recursive
expression and statement helpers read those fields implicitly.

The retired shape was:

```text
renderProgram
  -> assign process-wide PHP program maps
  -> renderSupportClasses / renderFunctionStmts
  -> assign process-wide function and lexical maps
  -> renderStmts
  -> renderStmtWithLocals
  -> renderStmt / renderExpr
  -> PHP lookup helpers read the implicit active maps
  -> restore maps on the normal path
```

The nested helpers restored their own values after an exception, and
`CompilerRequestStaticState.reset` cleared all fields at request boundaries.
Those safeguards were not durable ownership: `renderProgram` itself had a long
manual save/restore list, every new early exit had to preserve it, and a future
concurrent request could have observed the same process-wide fields.

`PhpSourceTargetCore` now enters the required PHP-specific
`SourceTargetCommon.emitPhpTarget` facade. One `PhpProgramBodyRenderer` binds
the exact sealed program, module, class-graph, naming, overload, enum, alias,
and support facts. Every genuine typed function or initializer renderer
validates against that same owner. The generic source-target entry rejects PHP,
and `SourceTargetCommon` has no active PHP field or request-reset method.

The previous child, `haxe_ocaml-850ii.32.2.14`, corrected the semantic source
of local facts. PHP now starts ordinary functions from the exact
`TypedBackendLocalCatalog`, and target-side inference can fill only unknown
entries. This plan changes lifetime and access; it must not reverse that
semantic hard cut.

## State inventory and final owner

Every one of the 45 retired request-reset fields has an explicit owner. Slice
3 moved the 21 function and lexical fields; Slice 4 moved the remaining 24
program and support fields. A value was not placed in a context merely because
it used to be static.

### Immutable program facts

`PhpProgramRenderFacts` is built once from the sealed target-neutral program
and exact PHP program projection. It owns target namespaces and lookup tables
that are read throughout the program but do not change while a function
renders. `PhpModuleRenderFacts` then holds the immutable module-specific view,
such as imported aliases and local emitted names.

| Retired field | Meaning in the new owner |
| --- | --- |
| `phpRenderInstanceMethodsByType` | exact instance-method membership by owner type |
| `phpRenderInstanceMethodArgsByType` | exact instance-method argument facts |
| `phpRenderInstanceFieldsByType` | exact instance-field membership by owner type |
| `phpRenderInstanceFieldTypeHintsByType` | canonical projected field types |
| `phpRenderDynamicMethodsByType` | dynamic-method declarations by owner type |
| `phpRenderStaticMethodsByType` | static-method declarations by owner type |
| `phpRenderStaticOverloadsByType` | sealed static overload groups |
| `phpRenderInstanceOverloadsByType` | sealed instance overload groups |
| `phpRenderGenericStaticFunctionsByType` | generic static declarations by owner type |
| `phpRenderStaticCallableFieldsByType` | callable static fields by owner type |
| `phpRenderClassBaseTypes` | exact base-type relationships used by PHP lowering |
| `phpRenderStringExtensionMethodsByClass` | extension methods grouped by declaring class |
| `phpRenderKnownTypeNames` | target-visible known type identities |
| `phpRenderAbstractTypeNames` | target-visible abstract type identities |
| `phpRenderEmittedTypeNames` | canonical type identity to emitted PHP name |
| `phpRenderDuplicateTypeNames` | ambiguous short target names |
| `phpRenderInterfaceTypeNames` | exact interface identities |
| `phpRenderEnumConstructors` | exact constructor facts addressable in the module |
| `phpRenderAmbiguousEnumConstructors` | constructor names that require an owner |
| `phpRenderEnumConstructorsByEnum` | constructors grouped by exact enum identity |
| `phpRenderEnumAbstractValues` | exact enum-abstract value facts |
| `phpRenderAmbiguousEnumAbstractValues` | enum-abstract names that require an owner |
| `phpRenderTypeAliases` | canonical imported type aliases in `PhpModuleRenderFacts` |

These maps are immutable after construction. Accessors return immutable values
or copies where Haxe collections cannot enforce read-only access.

### Immutable module, class, and function plans

`PhpModuleRenderFacts` owns `phpRenderLocalTypeNames`, the module-local emitted
type spelling table. `PhpFunctionLoweringPlan` is built for one
`TypedBackendFunctionProjection`. It binds every function choice to the
function's stable identity and body revision. Module- or class-wide inputs are
copied or referenced through immutable records rather than selected through a
current-class static.

| Current field | Meaning in the new owner |
| --- | --- |
| `phpRenderStringExtensionMethodsByField` | extension methods selected for the current class/import scope |
| `phpRenderCurrentInstanceMethodNames` | exact instance methods available to this function |
| `phpRenderCurrentInstanceMethodArgs` | exact arguments for those instance methods |
| `phpRenderSameClassMethodNames` | class-member rewrite input |
| `phpRenderSameClassFieldNames` | class-field rewrite input |
| `phpRenderSameClassFieldTypeHints` | canonical class-field types |
| `phpRenderSameClassStaticFieldNames` | exact same-class static fields |
| `phpRenderSameClassName` | exact owner identity and emitted PHP class name |
| `phpRenderSameClassLocals` | exact projected local names that exclude member rewriting |
| `phpRenderLocalEnumConstructors` | exact enum constructors imported into the function scope |
| `phpRenderPreferredEnumName` | explicit enum owner when the typed projection requires one |
| `phpRenderDynamicCallFieldsByLocal` | precomputed dynamic-call facts bound to exact projected locals |
| `phpRenderCurrentFunctionName` | exact function identity plus accessor/backing-field plan |
| `phpRenderGenericConstructorSamples` | sealed specialization inputs for generic constructor lowering |

Where a row still describes semantic lookup today, the function plan must store
the selected result or an exact identity, not another request to search names
during printing. `TypedExactCallSource`,
`TypedExactEnumConstructorSource`, and the accepted typed-body lifecycle are
the existing pattern.

The plan key must include the function's stable declaration identity, exact
body revision, module/program revision, and PHP lowering schema revision. The
current source-shaped projection must expose those revisions from the sealed
typed owner before observation-mode plans can publish. The PHP target must not
substitute a source-text hash or its own name-based body identity.

### Explicit lexical rendering scopes

`PhpLexicalRenderScope` contains temporary information needed to print one
function body. Its `derive...` methods create a child value for a block, loop,
catch, switch case, or lambda. A child may not mutate its parent or a sibling.

| Current field | Meaning in the new owner |
| --- | --- |
| `phpRenderLocalTypes` | exact function local types plus bounded types for target-synthetic locals |
| `phpRenderLocalInits` | initializer shapes still required by PHP syntax lowering |
| `phpRenderRefCaptureLocals` | capture mode selected for the current statement/lambda |
| `phpRenderThisValueSlot` | whether the current function uses an explicit `$this` value carrier |
| `phpThisValueCaptureName` | the target-local carrier used inside one nested lambda |
| `phpRenderOptionalLambdaArgNamesByLocal` | required lambda parameter names by exact projected local |
| `phpRenderOptionalLambdaOptionalArgNamesByLocal` | optional lambda parameters by exact projected local |

The base local-type table comes from `PhpFunctionLocalFacts`; unknown
target-synthetic bindings may be added only through the existing
unknown-only rule. The explicit rest-argument PHP array carrier remains a
documented target representation. No child scope may replace a non-empty exact
semantic type.

## Architecture decision

Use a target-owned renderer instance plus precomputed facts:

```text
PhpSourceTargetCore
  -> builds PhpProgramRenderFacts
  -> derives PhpModuleRenderFacts
  -> builds/requests PhpFunctionLoweringPlan per strict projection
  -> creates PhpFunctionBodyRenderer
  -> renderer calls renderExpr(expr, lexicalScope)
     and renderStmt(stmt, lexicalScope)
```

The renderer instance owns only the immutable program and module facts, the
immutable function plan currently being rendered, and its output builder.
Recursive methods receive the lexical scope explicitly. There is no static
`currentPhpRenderer`, thread-local lookup, or request-global service locator.

This is a hybrid by design:

- semantic choices move into exact typed identities or sealed PHP lowering
  plans before syntax;
- immutable target naming and program tables remain on
  `PhpProgramRenderFacts`;
- genuinely lexical printer state remains an explicit
  `PhpLexicalRenderScope`; and
- syntax-only helpers may be shared only when they take all inputs as
  arguments and retain no request state.

### Fact provenance

Every field in the new records declares which owner supplied it:

- semantic types, calls, fields, enum constructors, declarations, captures,
  and body identity come from sealed typed facts;
- emitted PHP identifiers, namespaces, file paths, and runtime helper names are
  target-owned naming facts derived deterministically from those identities;
- lexical indentation, temporary target-local names, and output bytes belong
  only to the renderer instance and its child scopes.

A program or function record is not valid if a semantic row was reconstructed
from `HxModuleDecl`, source-text hints, or an unqualified name during target
rendering. Observation mode must report that missing fact and block the hard
cut instead of silently filling it.

## Alternatives considered

### Add an optional context parameter throughout `SourceTargetCommon`

Rejected as the durable architecture. It would carry PHP-only facts through a
five-target mega-file and require hundreds of recursive calls to preserve an
optional value. A missed call would silently fall back to an empty or stale
scope. A short-lived comparison branch may use an explicit parameter
internally, but production ownership must end behind `PhpSourceTargetCore`.

Slice 3 uses a materially different boundary: the shared recursive kernel
receives one required, closed render-frame value on every call. A PHP function
frame contains the target-owned `PhpFunctionBodyRenderer` and one explicit
`PhpLexicalRenderScope`; a program-only frame is a different constructor and
cannot answer function-state queries. There is no null/default context and no
implicit fallback when a caller forgets the frame—the Haxe call does not type
check. Production PHP ownership still starts behind `PhpSourceTargetCore`;
`SourceTargetCommon` retains only stateless multi-target algorithms.

### Put all fields in one object and keep one static current-context pointer

Rejected. The maps would be allocated per request, but access would still
depend on process-global dynamic scope. Failure isolation, reset completeness,
and concurrency safety would still rest on one mutable pointer.

### Precompute every PHP decision and keep a stateless printer

Accepted as a direction for semantic choices, but insufficient by itself.
Blocks, catches, switches, and lambdas still derive target-local lexical names
and capture syntax while printing. Those values need an explicit scoped
lifetime even after semantic lookup is sealed.

### Move every PHP helper in one patch

Rejected. An all-at-once move would be difficult to review and would make a
generated-output difference hard to localize. The migration uses hard cuts per
vertical slice: each selected production path moves completely, gains an
old-path prohibition guard, and does not keep permanent old/new rendering.

## Implementation sequence

### Slice 1 — pure target utilities

Move PHP-only name normalization, quoting, and syntax helpers that have no
compiler state into focused PHP modules. `SourceTargetCommon` may delegate
during this slice, but no new semantic behavior or process field is allowed.
Generated PHP must remain byte-identical.

This reduces the dependency surface for the renderer without pretending that
state ownership is fixed.

The first executable child, `haxe_ocaml-850ii.32.2.16`, moves string quoting
and deterministic associative-array formatting into `PhpSyntax`. The module
takes every value and output buffer explicitly and retains no request state.

The second executable child, `haxe_ocaml-850ii.32.2.17`, moves PHP reserved
type names, predefined superglobal value names, global-function spelling, and
PHP type-path spelling into `PhpName`. `SourceIdentifier` owns the one shared
ASCII identifier sanitizer used by PHP and the existing source-target facade,
so the extraction does not duplicate that base algorithm or churn every
non-PHP call site.

The third executable child, `haxe_ocaml-850ii.32.2.18`, supplies the identity
prerequisite for observation mode. `CompilerTypedTreeRevision` now computes one
exact function-body revision from the stable declaration identity, typed
parameter environment, and structural typed statements. This small
target-neutral owner avoids a dependency cycle between `TypedModule` and the
source-shaped backend adapter. The strict backend projection carries the
revision without recomputing it from projected source. The module implementation
revision consumes the same value, so module invalidation and future PHP function
plans cannot quietly disagree about which body they identify.

The fourth executable child, `haxe_ocaml-850ii.32.2.19`, supplies the complete
typed-program identity needed by those function plans. `MacroExpandedProgram`
seals one `CompilerTypedProgramRevision` from canonically sorted and merged
module revisions after revalidating every typed body. `PhpTypedProgramProjection`
carries that exact value without hashing projected source or PHP output.
Dependency edges, request configuration, PHP schema, target lowering, and
generated-output identities remain deliberately separate inputs rather than
being hidden inside one universal revision.

### Slice 2 — sealed facts and plans in observation mode

Introduce `PhpProgramRenderFacts`, `PhpModuleRenderFacts`,
`PhpFunctionLoweringPlan`, and `PhpLexicalRenderScope`. Build them from the
exact program/function projections, validate stable identities, and compare
their decisions with the current successful output. The existing renderer
still owns production output in this observation-only slice.

Any missing fact stops the cutover. It must be added at the typer, typed-body
projection, or PHP lowering-plan boundary rather than recovered from parsed
source during printing.

The first Slice 2 child, `haxe_ocaml-850ii.32.2.20`, observes the five
program-wide PHP type-name decisions that were previously available only as
mutable static maps: known type spellings, abstract membership, emitted names,
duplicate short names, and interface membership. `PhpProgramRenderFacts`
derives them from the exact projected classes and each typed module's
`sourceModulePath`; it never guesses a module from the main class name. The
record binds those facts to the sealed typed-program revision, sorts their
serialized form, and rejects both conflicting exact lookup assignments and two
exact types that flatten to one emitted PHP name. A short or package-local
convenience alias that names multiple secondary types is omitted rather than
chosen by traversal order; every exact module-qualified lookup remains
available. Query methods retain private backing maps and copy collection
results.

This is deliberately not a production cutover. The existing maps in
`SourceTargetCommon` still decide generated PHP. Observation construction is
lazy behind `getProgramRenderFacts()`, and a guard rejects any renderer call to
that method, so stricter observation validation cannot reject an ordinary PHP
compile before the cutover. Focused tests compare all five tables with the
legacy builders for an unambiguous representative program and separately test
ambiguous and invalid identities.

A post-slice call-graph check rejected an immediate five-map cutover.
`SourceTargetCommon` still contains roughly 300 recursive `renderExpr` call
sites, and the naming queries are reached from inside that shared five-target
renderer. Passing program facts through that graph now would be the optional
context-parameter alternative rejected above; storing one current fact record
would be the rejected singleton alternative. The next child therefore builds
the exact `PhpModuleRenderFacts` observation, followed by function-plan and
lexical-scope observations. Production naming switches only when a complete
PHP function or program/support path moves behind its PHP-owned renderer in
Slices 3 and 4. Each such hard cut must switch all naming queries used by that
path and remove the corresponding legacy owners; no new feature may add
another legacy consumer while removal is pending.

The second Slice 2 child, `haxe_ocaml-850ii.32.2.21`, observes the exact
module-specific naming view. `PhpModuleRenderFacts` binds local emitted type
spellings and resolved runtime-support import aliases to the typed-program
revision, matching merged typed-module revision, exact `sourceModulePath`, and
a PHP module-facts schema. It derives local types from strict projected
classes and aliases from `TyModuleDirective` providers; it does not infer a
module from its main class or reparse import text.

The observation also exposes one legacy lifetime error without changing
production yet: `phpProgramTypeAliasMap` unions aliases imported by every
module, while Haxe aliases are visible only in the module that declares them.
A black-box Haxe 4.3.7 fixture accepts `Data` in the module importing
`haxe.io.Bytes as Data` and rejects `Data` in a sibling module. The immutable
record therefore retains only its module's resolved aliases. The legacy union
remains the output authority until the PHP-owned renderer hard cut, where this
behavior difference needs a focused generated-output and runtime check.
`PhpRuntimeSupportTypeAlias` is already the single target-owned spelling
policy shared by the legacy and observed paths, so the observation duplicates
only lifetime/ownership, not the supported runtime-type list.

The third Slice 2 child, `haxe_ocaml-850ii.32.2.22`, closes a target-neutral
prerequisite discovered before building `PhpFunctionLoweringPlan`. The strict
function projection already carries exact function, body, local, and bare-field
identities, but its owning class projection previously exposed member
semantics mainly through a source-shaped `HxClassDecl`. Constructing the PHP
plan there would have put source-name and inheritance lookup back in the
target, only inside an immutable object.

`TypedBackendClassSemanticFacts` now snapshots the canonical nominal type and
source-module identities, exact superclass, declared `TyFieldInfo` facts, and
stable `TyDeclarationInfo` method signatures while `TypedClass` still owns
them. `TypedBackendClassProjection` carries the optional record beside its
temporary declaration. Bring-up modules created without a program semantic
index remain valid until a migrated backend explicitly calls
`requireSemanticFacts()`; that accessor then fails rather than guessing.
Production backends may not call it in this observation child.

This record deliberately contains declared members only. The PHP function plan
still needs to traverse an exact program-owned superclass graph to calculate
the inherited member closure. It may not reuse the legacy short-name
`classesByName` search. PHP spelling, class representation, enum scope, dynamic
call analysis, and lexical state also remain in their later target-owned
records.

The fourth Slice 2 child, `haxe_ocaml-850ii.32.2.23`, observes that exact
program-owned inheritance graph. `TypedBackendClassGraph` indexes nodes only by
canonical Haxe class identity and binds the graph to the sealed typed-program
revision. Each edge keeps the raw parent node identity separate from the
applied superclass type: `Base<String>` therefore points to the exact `Base`
node while retaining the `String` application for later substitution.

The graph reports an absent projected parent as an incomplete lineage rather
than treating it as a root. Its strict query fails at that edge, and
self-inheritance, multi-node cycles, unresolved non-nominal parents, and
conflicting duplicate nodes fail before publication. Construction remains
lazy through `PhpTypedProgramProjection`; the production PHP renderer may not
consume it in this child.

At the end of the fourth child, this was still not inherited-member lowering.
Generic argument substitution,
visibility rules, overload selection, extension methods, and target spelling
belong to the later PHP function plan. The observation graph supplies only the
exact target-neutral nodes and edges needed to make that plan possible without
the legacy short-name `classesByName` map.

The fifth Slice 2 child, `haxe_ocaml-850ii.32.2.24`, closes the structural
generic-inheritance prerequisite discovered when preparing the function plan.
The practical case is `Child extends Base<String>`: a field or method declared
with the parent's `T` must reach the child as `String`, including through
multiple generic superclass edges.

A self-authored Haxe 4.3.7 oracle fixture exposed a more basic identity problem
before that substitution was admitted. Haxe allows a method parameter to
shadow a class parameter with the same readable name:

```haxe
class Box<T> {
  function echo<T>(value:T):T;
}
```

Those two `T` declarations are different binders. `TyTypeParameterId` now
identifies each binder by its declaring nominal or method scope and ordinal,
while `TyType` still displays the source name for diagnostics. `TyperIndex`
resolves method scope after class scope so the inner `T` wins inside `echo`,
and semantic keys use the exact binder identity rather than
`type-parameter:T`.

`TyTypeSubstitution` then walks the structural semantic type constructors. It
never parses a type display or cache key. `TypedBackendClassGraph` composes the
applied arguments at each exact superclass edge and can return specialized
declared-member facts while leaving method-local binders untouched.

This remains observation-only. The production PHP renderer still uses its
legacy inheritance maps until `PhpFunctionLoweringPlan` and the complete
function-body renderer replace those lookups together. The narrow `HxParser`
change that retains main-class type parameters stays in the parser's existing
class-header owner; no target workaround or additional parser mega-file
responsibility was introduced.

The sixth and final Slice 2 child, `haxe_ocaml-850ii.32.2.25`, makes the
function boundary executable without changing generated PHP. One exact
projected function now selects an immutable `PhpFunctionLoweringPlan` containing
the program, module, class, function, and body revisions; the emitted PHP owner;
the exact current method; ordered parameter-binding identities; structurally
specialized child-to-root class groups; exact locals; and exact bare-field
reads. Rest-argument representation is selected through that binding order, not
by correlating source names. Inherited members remain grouped by their declaring
class and canonical identity. The plan does not flatten overrides or overloads
by readable name, so a later renderer cannot accidentally select a
same-short-name class or traversal-order winner.

Building the first multi-hop generic fixture exposed a stale duplicate input.
`TyClassInfo` already held the superclass with exact type-parameter binder
identities, while the older `TypedClass.resolvedExtends` projection still
contained unresolved type-argument spellings. `TypedBodySource` now supplies
only the semantic index to `TypedBackendClassSemanticFacts`; the backend no
longer tries to reconcile two competing superclass models.

`PhpLexicalRenderScope` then gives PHP syntax state an explicit request lifetime.
The root activates exact typed parameters. Entering a declaration activates its
planned local, while blocks, loops, catches, switch cases, and lambdas receive
independent child values. Initializers, reference captures, optional lambda
arguments, and the `$this` carrier are copied on derivation. Exact known types
and the explicit rest-array carrier cannot be replaced; only an unknown typed
local or a declared PHP-only temporary may receive a target representation hint.

This closes observation mode. A boundary guard requires both schemas and rejects
production calls to the plan accessor or lexical scope. The next child must
start the `PhpFunctionBodyRenderer` production hard cut. Another
observation-only prerequisite is allowed only if that hard cut proves a missing
target-neutral fact and records the exact failing fixture.

### Slice 3 — function-body renderer hard cut

Move ordinary functions, support-class functions, and the selected main
function to `PhpFunctionBodyRenderer`. The migrated production path must use
`renderExpr(expr, scope)` and `renderStmt(stmt, scope)` recursively and must not
read any of the function- or lexical-scope statics listed above.

Remove those statics and their reset entries in the same slice. Add a guard
that rejects calls from migrated PHP functions back into the legacy stateful
PHP body renderer. This slice is complete only when every genuine typed PHP
function body uses the new owner; a permanent old/new renderer choice for
those bodies is not allowed.

#### Pre-existing compatibility substitutions are not typed bodies

The cutover experiment found a finite set of older Stage3 branches that do not
render the projected Haxe body at all. They print hand-written PHP for named
upstream-suite fixtures:

- abstract-carrier behavior in `MyAbstractCounter`, `MyHash`, and
  `MySpecialString`;
- local-static persistence in `TestLocalStatic.basic`;
- map-comprehension behavior in `TestMapComprehension.testBasic`; and
- extractor-pattern behavior in `TestMatch.testExtractors`.

`phpStaticInitFallbackLines` is a separate static-initializer compatibility
substitution. It is now limited to one exact typed declaration,
`unit.PropBox#static:__init__()->unknown#0`, and one exact projected statement,
`STAT_X = 3`. The machine guard checks both the identity and statement shape.
For example, the projected `MySpecialString.substr` body calls the class method
recursively, while the replacement calls the PHP string runtime helper over a
hidden carrier. Moving either replacement into `PhpFunctionBodyRenderer` would
therefore hide a missing shared semantic model; it would not complete the
renderer cut.

These substitutions remain outside the Slice 3 typed-body claim. The
typed-backend boundary guard checks the exact 13 named identities and rejects
new entries. They are excluded from product, Full1, and shared-target evidence
and are owned for semantic retirement by `haxe.ocaml-f1cl.3.11.12`. Slice 3
may close when the genuine typed-body request-state cut is proven; the
quarantine may not expand and cannot be cited as authentic PHP compatibility.

#### Slice 3 implementation result

Slice 3 now hard-cuts every genuine typed PHP function body and typed field
initializer to one request-owned `PhpFunctionBodyRenderer`. Ordinary methods,
constructors, accessors, typed support functions, the selected main function,
and field initializers obtain a strict renderer from
`PhpTypedProgramProjection`. `SourceTargetCommon` remains the shared recursive
syntax kernel for this slice, but every PHP function call into that kernel
carries a required `SourceFunctionRenderFrame`. A PHP function frame contains
the renderer plus one immutable `PhpLexicalRenderScope`; the program-only frame
cannot answer function-state queries.

The cut removed 21 PHP function- and lexical-scope statics and their request
reset entries. The remaining 92 process-wide declarations across 11 compiler
files are individually classified by the request-state inventory; remaining
PHP program/support state belongs to Slice 4. The structural boundary guard
rejects the retired fields, a `Program(Php)` function-body entry, direct
observation-plan access from the syntax kernel, and callbacks from the
request-owned renderer into `SourceTargetCommon`.

The lifecycle fixture exercises direct, repeated, failed-then-successful,
reset, and A → B → A PHP requests. Equivalent inputs produce equivalent PHP
bytes and runtime behavior, while the middle B request produces distinct
output. The complete compiler shard passed 114 of 114 commands, the focused
source-native PHP smoke passed, and the full repository guard bundle passed
after the final regenerated snapshot.

#### Bootstrap and generated-diff review

The first full regeneration exposed two generated OCaml module cycles. The
fix kept ownership one-way: `SourceTargetCommon` invokes the facts-only PHP
renderer, `SourceFunctionRenderFrameTools` constructs the root PHP frame, and
the source-target enum now lives in dependency-free `SourceNativeTarget`.
Later native verification exposed three Haxe shapes that were legal at the
source level but unsafe after Reflaxe lowering: an alternative unary enum
pattern emitted as an OCaml wildcard, an optional concrete `Map` boxed as
`Obj.t`, and a parameter named `ref` shadowing OCaml's reference constructor.
Each was replaced in Haxe with equivalent explicit control flow, exact
non-optional types, or a non-conflicting semantic name. Generated OCaml was
never edited.

The final source-of-truth run completed stage0 emission in 731 seconds,
snapshot copy in under one second, sharding in 6 seconds, and native Dune
verification in 22 seconds; total regeneration time was 764 seconds. A
separate `HXHX_FORBID_STAGE0=1` build produced the native bootstrap
executable.

The bootstrap diff is intentionally broader than this child because the shared
checkout accumulated the preceding typed-identity, dependency-observation,
request-state, parser-bridge-retirement, C++/JS, and PHP hard-cut children
before the next official snapshot regeneration. `_GeneratedFiles.json`
accounts for the new Haxe-owned modules and the retired parser/runtime bridge
modules. Bootstrap-copy, handwritten-OCaml ownership, bridge-boundary, and
current-source-cache guards all pass. The diff therefore records one
deterministic regeneration boundary for those already-reviewed Haxe sources;
it is not evidence that Slice 3 independently changed every generated unit.

### Slice 4 — program/support renderer hard cut

Move PHP program scaffolding, support-class ownership, and the remaining
program-fact consumers behind `PhpSourceTargetCore`. Remove all remaining PHP
request-reset fields and their broad reset entries. The PHP branch in
`SourceTargetCommon` becomes temporary transport delegation and is then
deleted.

After this slice, `SourceTargetCommon.resetRequestState` has no PHP state to
clear. That is the request-lifetime closure gate; merely reducing 45 fields to
one does not satisfy it.

#### Slice 4 implementation result

Slice 4 now creates one `PhpProgramBodyRenderer` before PHP support or
executable output is rendered. It receives exact `PhpProgramRenderFacts`, one
validated `PhpModuleRenderFacts` record per source module, the exact typed
class graph, and request-owned copies of the remaining compatibility catalogs.
`PhpFunctionBodyRenderer` requires that same program owner, so support
functions, field initializers, and the selected entry function cannot mix
program or module revisions.

All 24 program/support `phpRender*` fields, the save/install/restore block,
`SourceTargetCommon.resetRequestState`, and its
`CompilerRequestStaticState` call are gone. The process-wide state inventory
now classifies 68 declarations in 10 files and rejects restoration of the
source-target reset lifecycle.

The complete source-native smoke exposed and closed the places where old
global tables had been hiding a dependency: exact class ownership for logical
name maps, enum-abstract facts, superclass ancestry, abstract unary methods,
duplicate short-name aliases, emitted generic type names, and static property
accessors. Each fix now reads the request owner; none reinstalls ambient state.
The failure and long-lived-request fixtures now exercise the new boundary
rather than failing before it exists. One non-entry support class reaches
function rendering after `PhpProgramBodyRenderer` is sealed, throws on a
deliberately invalid PHP intrinsic, publishes no target file, and is followed
by an equivalent successful request. The server fixture compares direct and
server bytes plus PHP exit/output behavior, performs a warm A → B → A sequence,
then cancels after PHP rendering has sealed staged output but before
publication. The cancelled transaction leaves the prior bytes intact, and the
next request reproduces the direct result. Reset equivalence is also green.

The wider evidence is also complete. The 114-command compiler shard passed in
349.843 seconds,
including non-PHP target, dependency-observation, and compilation-server
coverage. The official generator rebuilt all 407 bootstrap files from the
Haxe source with upstream Haxe 4.3.7: stage0 emission took 721 seconds,
snapshot finalization and sharding took 5 seconds, native Dune verification
took 19 seconds, and the full run took 749 seconds. A separate build with
`HXHX_FORBID_STAGE0=1` produced the native executable from that refreshed
snapshot. The final repository guard bundle passed after regeneration,
including the request-state inventory, typed-backend boundary,
handwritten-OCaml ownership, bridge retirement, source-target architecture,
mega-file, and 886-file formatting checks.

This closes the PHP request-lifetime cut; it does not make the finite
compatibility substitutions production semantics, enable typed-module cache
hits, or change README readiness. Those claims remain owned by their existing
retirement and product evidence gates.

## Invariants

1. One strict `TypedBackendFunctionProjection` selects one
   `PhpFunctionLoweringPlan`; missing or conflicting identities fail before
   printing.
2. Function plans carry exact body/program/schema revisions from the sealed
   typed owner; source text and target-local hashes are not revision authority.
3. `PhpProgramRenderFacts`, `PhpModuleRenderFacts`, and
   `PhpFunctionLoweringPlan` are immutable after validation.
4. A lexical child scope derives from one parent and cannot mutate its parent
   or siblings.
5. Exact non-empty local types cannot be replaced by target inference.
6. Every semantic call, member, enum, conversion, and representation choice
   used by the new renderer is selected before syntax. A missing fact stops the
   genuine typed body instead of inventing a fallback. The pre-existing finite
   compatibility substitutions remain outside this renderer and have the
   explicit retirement owner `haxe.ocaml-f1cl.3.11.12`.
7. A failed or cancelled render publishes no output and leaves no mutable value
   reachable by a later request.
8. Direct, cold-server, warm-server, repeated-warm, failed-then-successful, and
   reset requests produce the same PHP bytes, diagnostics, exit status, and
   executable behavior for equivalent inputs.
9. There is no process-global current renderer or parsed-body recovery. The
   finite Stage3 compatibility quarantine is not accepted target architecture,
   may not grow, and cannot earn readiness evidence while its retirement Bead
   remains open.
10. Generated OCaml is regenerated from Haxe sources only; it is never edited as
   the implementation.
11. Upstream Haxe 4.3.7 remains a black-box behavior and architecture oracle.
    Its GPL implementation and tests are not copied, translated, retyped, or
    mechanically adapted into the MIT shipping path.

## Required evidence

Each hard-cut slice needs the narrowest decisive evidence first, then the broad
gates appropriate to its reach:

- byte-for-byte generated PHP comparison for unchanged fixtures;
- a structural check that the compatibility quarantine contains exactly the
  previously known 13 named body identities plus the one exact static
  initializer identity and assignment shape, with no additions;
- nested/sibling shadowed locals, lambdas, loops, catches, switch bindings,
  optional/rest parameters, accessor backing fields, overloads, enum values,
  generic specializations, and target-synthetic locals;
- missing/conflicting projection failures before output;
- direct → repeated → injected failure/cancellation → next successful request;
- request reset and A → B → A sequences;
- source-native PHP compile/build/run behavior;
- `npm run test:m14:source-native-backend-smoke`;
- `npm run guard:native-server-request-state`;
- `npm run guard:source-native-target-family-plan`;
- the appropriate compiler shard;
- deterministic full bootstrap regeneration and a stage0-forbidden native
  build when Haxe compiler sources change;
- `npm run ci:guards`; and
- `git diff --check`.

The first hard cut also needs a generated-diff review. New target-owned modules
are expected; widespread unrelated temporary-name churn in
`backend_source_SourceTargetCommon.ml` is a stop signal.

## Deferred and non-claims

This plan does not:

- retire the finite PHP compatibility substitutions; that root semantic work
  belongs to `haxe.ocaml-f1cl.3.11.12`;
- admit typed-module or target-result caching;
- enable concurrent semantic requests;
- cache macro, plugin, or display state;
- strengthen the duplicate Stage3 OCaml emitter;
- change PHP language behavior or Full 1.0 scope;
- make the native server defaultable; or
- move README Goals or North Star readiness.

The PHP request-state child can close because the executable hard cuts removed
all source-target PHP request fields and reset hooks. The parent
`haxe_ocaml-850ii.32.2` remains open for the other process-wide compiler owners
still listed in the request-state inventory. This design and its internal
isolation evidence are not product-readiness evidence.
