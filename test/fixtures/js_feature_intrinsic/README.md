# JavaScript feature-selected effects

The program enables one named feature and leaves another absent. Only the chosen
branches may run. Upstream Haxe 4.3.7 prints `enabled`, `branch`, and `absent`, with
its usual source-location prefixes. Neither line beginning with `wrong:` may print.

Run the upstream observer from the repository root:

```sh
mkdir -p .tmp/js-feature-intrinsic
node_modules/.bin/haxe -cp test/fixtures/js_feature_intrinsic -main Main \
  -js .tmp/js-feature-intrinsic/upstream.js -dce full
node .tmp/js-feature-intrinsic/upstream.js
```

Run `haxe test/m14_js_feature_intrinsic_test.hxml` for the local regression.
It currently fails because program-owned feature selection is not implemented.
The eventual check requires generated JavaScript behavior,
including ordered effects and both enabled and absent features.

The real JavaScript standard-library `Std.__init__` uses the same intrinsic with
source blocks. This fixture retains the failure without library-specific names.
It does not establish complete feature reachability or dead-code elimination.

Run `haxe test/m14_js_feature_upstream_contract_test.hxml` for the executable upstream
specification. It requires Haxe 4.3.7 and compares eleven programs in each of three
dead-code elimination modes: `full`, `std`, and `no`. Dead-code elimination removes
unused declarations; its mode changes which feature definitions remain relevant.

- A definition later in a retained function enables an earlier feature test.
- An unused user method contributes its definition under `std` and `no`, but not `full`.
- A definition inside an unselected feature branch still enables another feature.
- Two feature branches can enable each other's feature names through their definitions.
- A retained conditional function contributes its definition even when its runtime
  condition is false. That does not execute the definition's runtime operand.
- Definitions preserve their operand value and effects. Selection executes only the
  chosen branch; a missing two-argument selection has no effect.
- A selected method and its class wildcard are present; an unknown class wildcard is absent.
- Local functions and methods named like the intrinsics remain ordinary calls.
- Class initialization and methods retained with `@:keep` activate their definitions.
- An unused class initializer does not activate its definition under `full`.
  Initialization follows class retention instead of every loaded source declaration.
- An unused pure field initializer and an unused secondary class activate definitions
  under `std` and `no`, but not `full`.
- A call inside an absent feature branch still activates definitions from its method.
  The method's runtime effects do not execute.
- Transitive calls and method values activate definitions from their referenced methods.

These observations separate compilation-time feature discovery from runtime branch
effects. Scanning only the selected branches would disagree with upstream.
The expectation arrays are independent of generated JavaScript. The observer strips
only trace location prefixes and compares all remaining lines in order.
These upstream checks do not imply that the local compiler implements the contract.

Run `haxe test/m14_typed_feature_intrinsic_test.hxml` for the local typed-tree contract.
The compiler now preserves feature definitions and both selection branches as
explicit nodes within `untyped` expressions. It retains local and method shadowing,
source blocks, authored syntax, and revision sensitivity to names and branch order.
Quoted macro contents remain unchanged. Malformed feature nodes fail invariants.

These nodes must be resolved before control lowering or backend projection. Their
presence alone does not enable runtime feature selection or establish reachability.
The ordinary runtime regression remains required and currently fails at that boundary.

Run `haxe test/m14_typed_feature_selection_test.hxml` to check immutable branch
rewriting with explicitly supplied decisions. This is a component test, not proof
of feature discovery or dead-code elimination. Function-body cases run generated
JavaScript and compare effects and values with the upstream observations. The
original typed program retains its revision, and a second application changes nothing.

The aggregate selection test remains red at `FeatureFields.value`. The JavaScript
backend does not yet emit its lowered block initializer. Existing task
`haxe_ocaml-vwb4u` owns that target repair; its owner is unchanged. The field case
remains required, and its upstream output is checked in all three DCE modes.

`FeatureAbsentValue` records an upstream 4.3.7 defect. Compile it with the upstream
command above, replacing `Main` with `FeatureAbsentValue` and selecting `-dce no`.
Compilation succeeds, but `node --check` rejects the output: an absent two-argument
feature becomes an initializer with no value. The local selection test requires
an explicit value-required diagnostic instead of inventing a result. No runtime
equivalence claim applies to this invalid upstream JavaScript.

Run `haxe test/m14_typed_feature_discovery_test.hxml` for discovery from retained
typed declarations. Its all-retained component derives feature decisions for four
user-code fixtures, then executes them through generated JavaScript. No expected
feature-name list is supplied to those runtime checks.

Discovery scans both branches for definitions, preserves declaration ownership,
and returns stable decisions regardless of declaration order. It rejects copied
functions, foreign classes and decisions reused for another program. A retained
subset check excludes an unused method's definition; it tests the input contract,
not a completed full-DCE reachability algorithm.

`FeatureNames` establishes the secondary-type protocol: `Secondary.touch` is enabled,
while `FeatureNames.Secondary.touch` is absent. Semantic declaration identities
remain exact; the feature protocol uses the package and declared type name.

The aggregate discovery test remains red at the ordinary block-bodied local
function in `FeatureShadowing`. Discovery and selection leave that program unchanged;
the JavaScript source-function emission repair remains under `haxe_ocaml-o25kr`.
Full/std retention, standard-library provenance, production dispatch and complete
runtime acceptance remain required. The all-retained helper is not a DCE fallback.

Run `python3 scripts/ci/js-feature-origin-contract-test.py` to compare the same
authored library class in project and standard-library locations. The observer
uses a temporary SDK directory and leaves the installed SDK unchanged.
It checks eighteen combinations against pinned Haxe 4.3.7 and executes each JavaScript result.

An unused method defines `origin.library`. Project code enables this feature under
`std` and `no`, but not `full`. The SDK copy leaves it absent in all three modes.
Adding that SDK directory as an explicit classpath does not change its behavior.
Under `no`, upstream emits the unused SDK method but leaves its feature absent.
Thus emitted declarations alone cannot determine which feature definitions apply.
Calling the method enables its feature in every source location and DCE mode.
The feature test precedes that call, so activation cannot depend on runtime execution order.
The observer reports method emission as diagnostic evidence; ordered runtime output
is the acceptance contract. Production feature relevance remains unfinished.

Run `haxe test/m14_typed_feature_source_catalog_test.hxml` for local source classification.
The catalog binds the configured SDK root and selected classpath slots to one typed program.
Project overrides, SDK overrides, explicit SDK roots and secondary-type lookups retain their source classification.
A directory named `std-project` does not count as the configured `std` directory.
Foreign programs, copied modules, mismatched files, missing slots and relative configuration paths are rejected.
Synthetic modules need an explicit source contract before this production policy can classify them.
This component leaves resolver identities and cache admission unchanged.
Production dispatch and declaration reachability still need to consume the classification.

Run `haxe test/m14_typed_feature_member_closure_test.hxml` for exact member-reference traversal.
Starting with the entry method alone, the local pass follows owned declarations
through both feature branches and derives the expected `FeatureContract` runtime output.
It excludes the unreferenced method without a supplied feature-name list.
Copied entry functions are rejected. This pass does not choose initialization or
metadata roots, resolve virtual dispatch, or establish a complete DCE policy.

The required `FeatureReferences` runtime case now passes. Shared typing retains
the selected static method declaration, so discovery can follow method values.
The original local experiment printed `callback:off`; the integrated result prints
`callback:on`, matching upstream in all three modes. The runtime test remains required.
The shared representation comes from the unpublished `haxe_ocaml-pmsr1.1.2` work.
That task retains its owner and still requires its broader acceptance and integration.
The pass rejects callable member reads that lack exact declaration facts.

Run `haxe test/m14_typed_feature_roots_test.hxml` for the composed retention contract.
The policy selects the entry method, project declarations under `std`/`no`, and
members retained with `@:keep`. Reference traversal includes each retained class's initializer.
The test runs three retention cases and eighteen SDK/project cases through generated JavaScript.
No expected feature-name list is supplied. SDK selection uses ordinary module
resolution, and explicit SDK classpaths retain the same source classification.

The policy rejects unknown modes and copied entry functions. Dynamic method behavior
and broader retention acceptance remain required.
Production dispatch does not yet use this incomplete policy.

Run `haxe test/m14_typed_feature_class_values_test.hxml` for class-object references.
A selected class retains its resolved parent, implemented interfaces, and initialization.
Under `full`, this does not activate definitions in an unused instance method.
All three modes match upstream runtime output. Missing parent providers are rejected.
The traversal uses canonical semantic identities, including secondary-module ownership,
rather than matching the short names used by the feature protocol.

Run `haxe test/m14_typed_feature_dispatch_test.hxml` for parent and interface dispatch.
A referenced instance member retains implementations in retained descendant classes.
This includes a class object that is never instantiated, as upstream requires.
Under `full`, unused classes and unrelated same-named methods remain excluded.
An override can expose new class and method references, so traversal repeats until
no declaration queue grows. Only the actual runtime implementations execute.
Constructors do not participate in virtual-member matching.

Run `haxe test/m14_typed_feature_metadata_test.hxml` for retention metadata.
`@:keepInit` retains class initialization without retaining every method.
`@:keepSub` retains members through resolved descendant relationships.
An exposed class retains its private method's feature as well as its public method's feature.
All three modes pass feature decisions and generated JavaScript runtime checks.
Under `full`, emission now removes the unused field and its `field:effect` output.

Run `haxe test/m14_typed_emission_retention_test.hxml` for declaration removal and startup effects.
The compiler builds an immutable emission copy before selecting feature branches.
Both backend projection paths consume that copy's exact field and function inventories.
An unused primary class can disappear while a secondary class keeps its original module identity.
The original typed program and parsed declarations remain unchanged.

Feature relevance and emission retention have separate rules. With DCE disabled,
unused SDK methods remain emitted while their feature definitions stay inactive.
The SDK/project matrix checks this difference in all three modes.
Upstream also retains fields referenced inside unselected feature branches.
`FeatureEmission` verifies that those initializer effects still execute under `full`.

JavaScript calls retained `__init__` functions before assigning ordinary static field values.
`FeatureStartup` checks cross-class method availability, startup ordering, and once-only effects.
The target follows exact eager calls from initializers when ordering classes.
Dynamic calls, broader startup graphs, production integration, and real-library acceptance remain required.

Run `haxe test/m14_typed_feature_dynamic_test.hxml` for dynamic replacement and stored instance methods.
Replacing a dynamic method with a static method value passes all three DCE modes.
Both declarations contribute features, but only the replacement executes.

The explicit stored-instance-method runtime cases pass under all three DCE modes.
Shared typing now preserves explicit receiver selections and their callable types.
Feature discovery retains the selected method and enables its feature.
JavaScript preserves the original object, observes later field changes, and gives repeated reads equal function identity.
The fixture also requires single evaluation when the receiver comes from a function call.
`FeatureBoundContexts` checks constructor callbacks, static and instance field initializers,
parenthesized reads and calls, and stored methods before and after dynamic replacement.
Projection checks reject copied syntax, foreign occurrences, changed revisions, and mutated receivers.
`FeatureBoundInheritance` checks bare method capture inside a base class and calls through a child instance.
Both stored callbacks use the child's override and observe later changes to an inherited field.
These cases pass locally in all three DCE modes.
`FeatureBoundGeneric` checks stored callbacks from `GenericReceiver<String>`,
`GenericReceiver<Int>`, and a subclass with a fixed `String` ancestor argument.
The test checks exact callable argument and return types before running JavaScript.
All three selections keep their original declaration and concrete receiver types.
Method-declared parameters are tracked under `haxe_ocaml-s4lw2`.
`FeatureBoundMethodGeneric` requires separate captures to infer `String` and `Int` results.
The local test now verifies both concrete results and executes stored, direct, and parenthesized calls.
`FeatureBoundMethodGenericConflict` must fail when one capture receives incompatible calls.
`FeatureBoundMethodGenericAliasConflict` requires the same rejection through a copied callback.
Both local typing and the upstream observer verify these conflicts; the upstream check covers all three DCE modes.
`FeatureBoundExpected` checks written local types, aliases, direct callback arguments,
and distinct class/method parameters. Exact published callback types are asserted before emission.
`FeatureBoundSubtype` checks that a callback fixed to a base type accepts a derived argument
without changing its inferred parameter. Both fixtures pass locally in all three DCE modes.
Method constraints, optional/rest parameters, broader conversions, and unused captures still require acceptance evidence.
`FeatureBoundConstraint` and `FeatureBoundConstraintCapture` record a specific Haxe 4.3.7 distinction:
the captured identity method accepts a fresh `Int` inference even though its declaration constrains `T` to a base class.
The same argument in a direct call is rejected upstream by `FeatureBoundConstraintDirect`.
Local stored-callback behavior passes. Direct invalid calls now report a source type diagnostic before replay.
A valid direct subtype call preserves its concrete result type.
The cross-package `foreign.FeatureBoundConstraintForeign` case rejects an unrelated type with the same short name.
`haxe_ocaml-wnqhz` retains the remaining constraint forms, review, and integration requirements.
`FeatureBoundApplied` checks a method bound that refers to its receiver's class parameter.
Direct and inherited calls preserve the exact derived result type and print `child`.
`FeatureBoundAppliedConflict` rejects an `Int` argument with the upstream constraint diagnostic.
`FeatureBoundInterface` checks an inherited implementation of `BoundValue<String>`.
The call retains the concrete child result, and its runtime method returns `interface`.
`FeatureBoundInterfaceConflict` rejects an implementation with the wrong type argument.
`FeatureBoundInterfaceUndeclared` rejects a class with matching methods but no declared interface.
The local checks assert the exact result and bound identities before JavaScript execution.
`FeatureBoundCompound` requires both a class bound and an interface bound with `T:Base & Named`.
The call preserves its concrete result. Separate negative fixtures omit each required relationship.
The dependency test checks both bound providers and revision changes when only the second provider changes.
Broader contexts, review, and integration remain unfinished.
`FeatureBoundNull` checks null-only generic calls under `haxe_ocaml-wnqhz`.
Upstream accepts null-only generic calls with base, child, and `Int` result annotations.
It also permits a later assignment to determine an initially untyped local's concrete type.
Shared call inference now preserves these contexts through exact call occurrences and copied locals.
The fixture also covers parenthesized calls, argument and return contexts, and later subtype assignment.
The local test checks exact inferred call results before running JavaScript in all three DCE modes.
Broader generic-call cases, review, and integration remain unfinished.
`FeatureBoundUnused` is the required regression for unused calls, locals, and stored callbacks.
Upstream permits their open generic types and still executes both calls' observable effects.
The local solver now publishes distinct immutable identities for permitted open method parameters.
Unknown source types and variables that require concrete solutions still fail publication.
Tests cover alias direction, nested concrete requirements, and failed publication without state changes.
`FeatureBoundOptional` checks omitted trailing arguments and explicit null for a declared default.
It also calls a copied generic callback before calling the original value.
Capture inference retains the selected method signature so aliases share its omission rules.
Separate negative fixtures reject a missing required argument and an extra argument.
Rest arguments and optional arguments before required parameters still need separate coverage.

Run `haxe test/m14_instance_method_value_identity_test.hxml` for the shared declaration contract.
It checks same-named methods from different providers, exact dependency edges, callable signatures,
receiver preservation through rewriting, and separation from ordinary data fields.
Method-level generics, negative/shadowing cases, broader runtime identity checks, production integration,
and merge remain open under `haxe_ocaml-i1c2c`.
