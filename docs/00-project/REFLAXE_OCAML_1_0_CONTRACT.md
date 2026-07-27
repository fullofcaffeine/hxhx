# reflaxe.ocaml 1.0 Contract

Last audited: 2026-07-27

This page is the canonical product contract for `reflaxe.ocaml` as a standalone target.

Current release authorization: **no-go**. The existing
`RO_PRODUCTION_READY:PASS` aggregate proves the historical declared
example/package/performance bundle. Following the accepted native-power and
target-lowering and six-month architecture reviews, it is necessary but not
sufficient for a 1.0 release. The target must complete one validated semantic
path for place/evaluation (`haxe_ocaml-9v1va`, completed), representation,
storage, and capture (`haxe_ocaml-9bome`), calls and conversions
(`haxe_ocaml-taef5`, completed for the represented ordinary-Haxe foundation),
structured control effects (`haxe_ocaml-w32h3`), and fail-closed runtime
ownership (`haxe_ocaml-0uwin`). This aggregate must then open those results.
Target-native labelled calls, typed adapters, and native dependencies remain
owned by `haxe_ocaml-v8a9b` and block only a release scope that claims those
interop capabilities. Existing package, matrix, documentation, and performance
receipts remain valid within their recorded scope; they are not revoked or
silently reinterpreted.

The first twelve bounded control-effect slices are now executable. An ordinary
static Haxe function returning an exact `Int`, `Bool`, or represented `String`
can leave early from a nested branch, block, loop, or `try` body without the
OCaml generator reconstructing that behavior from target syntax. The
represented String carrier also preserves the target's existing runtime null
sentinel. Exact `Null<Int>` and `Null<Bool>` values can now leave early as
well: the selected `Obj.t` carrier—one OCaml runtime value capable of
distinguishing null, zero/false, and nonzero/true—is transported unchanged
instead of being boxed a second time. The compiler records and validates the
return target and exact input/output carrier before printing OCaml, and the
generated function catches only its own return signal. An ordinary static
`Void` function can likewise use `return;` from a nested branch, loop, `try`,
or `catch`. Because that statement carries no Haxe value, the compiler records
a payloadless function-exit decision and the runtime transports no invented
`Obj.t` value.

The third slice gives every ordinary `while` and `do ... while` loop a sealed
target before OCaml syntax is built. Each `break` or `continue` names the exact
innermost loop it affects, and an ordinary source `catch` rethrows the
compiler-private loop signal instead of intercepting it. Loop admission is
independent from return-carrier support, so the target is also sealed in
`Void`, `Float`, and other functions whose early-return payload family remains
unsupported. Stable record identities follow the final typed body's structural
path because Haxe-generated nodes can legitimately share the same source
position; source positions remain diagnostic evidence rather than a uniqueness
key. Nested anonymous functions keep independent return and loop boundaries.

The fourth slice moves exact `Int`, `Bool`, and represented `String` throws out
of OCaml syntax construction. Before printing target code, the compiler now
records the value carrier, the global Haxe exception channel, the runtime
boxing conversion, and a value-sensitive tag policy. The policy matters for a
nullable String: upstream Haxe 4.3.7 sends a null String to `Dynamic`, not
`String`, while a non-null String still matches `String`. A throw may propagate
across calls because its target is the global exception channel rather than a
lexically nearby catch. If one function also throws an unsupported payload such
as `Float`, that function publishes no throw decisions and remains wholly on
the older path.

The fifth slice fixes the order, type test, and bound value for complete catch
chains containing exact `Int`, exact `Bool`, represented `String`, and a final
`Dynamic` catch before OCaml syntax is built. For example, `catch (_:Int)`
followed by `catch (value:Bool)` tests `Int` first, then binds the exact Bool
value through its checked carrier; adding `catch (_:Dynamic)` last makes that
clause the catch-all. A null String still bypasses `String` and reaches
`Dynamic`, matching the upstream Haxe 4.3.7 oracle. Both compiler-owned Haxe
throws and target-native OCaml exceptions enter the recorded source order, but
an unmatched value leaves through its original exception channel. Private
return, break, and continue signals bypass source catches.

Admission is all-or-nothing for each `try`, not each function. A `try` with an
unsupported `Float`, enum, `haxe.Exception`, or `haxe.ValueException` catch
remains entirely on the older catch path, while a separate supported `try` in
the same function can use the sealed path. The lowering and public inspection
reports expose the admitted chains and reject corrupt order, tags, carriers,
conversions, result handling, or revision ownership. Result handling says
whether a branch's completed value is discarded because the typed `try` is
`Void`, or preserved because the branch exits through return/throw; this keeps
OCaml handler branches type-compatible without asking the printer to infer
control flow. This does not yet claim that the older catch families are safe
for 1.0.

The sixth slice seals nested `return;` in ordinary static `Void` functions
before OCaml syntax is built. The recorded decision names the exact function
boundary and selects a private payloadless runtime signal. Source catches
rethrow that signal, and the owning function alone turns it into `unit`, so a
`return;` inside a `try` or `catch` cannot be mistaken for a source exception.
A nested anonymous function retains its own return boundary rather than
returning from the outer function. The lowering report and public inspection
surface expose the proof, capability, revision, and absence of a payload, and
reject a record that substitutes the value-return mechanism. This slice does
not use an `Obj.t` payload, `Obj.magic`, or a target-printer guess to represent
the missing value.

The seventh slice preserves exact `Null<Int>` and `Null<Bool>` carriers across
early returns. For example, in a function that returns `Null<Int>`, an early
`return value;` now raises the private return signal with the existing
`Obj.t` value, while a final direct `return 7;` performs its one required
`Int`-to-`Null<Int>` conversion inside the same function boundary. The
same boundary leaves an already-nullable final fallback unchanged. The
function boundary returns an early carrier directly, without `Obj.obj`,
`Obj.magic`, or another `Obj.repr`, so null and zero/false remain distinct.
Source `catch` clauses rethrow the private signal before matching source
exceptions. The lowering report and public inspection expose the exact
nullable semantic type, carrier, representation, conversion, proof, and
revision, and reject a record that substitutes exact-value boxing.

The eighth slice adds the matching directional crossing for early exact
`Int` and `Bool` values. For example, this now has one defined path:

```haxe
static function choose(stop:Bool, early:Int, fallback:Null<Int>):Null<Int> {
	if (stop)
		return early;
	return fallback;
}
```

Before OCaml syntax is written, the compiler records that `early` starts as an
OCaml `int`, must become the function's `Null<Int>` `Obj.t` carrier, and must
be boxed exactly once before the private return signal is raised. The function
then catches that signal and returns the resulting `Obj.t` unchanged. The same
rule covers `Bool` to `Null<Bool>`, including false, and can coexist with an
already-nullable early return in the same function. An incompatible return,
such as a `Dynamic` value mixed into that family, rejects the whole function
before generated source or lowering evidence is published.

The ninth slice lets one already-proven monomorphic class local leave early
without falling back to `Obj.magic`. A **monomorphic class** in this slice is a
closed, non-generic user class for which the complete program has selected one
exact OCaml record layout. For example:

```haxe
static function choose(stop:Bool, earlyValue:Int, fallbackValue:Int):Counter {
	final early = new Counter(earlyValue);
	final fallback = new Counter(fallbackValue);
	if (stop)
		return early;
	return fallback;
}
```

Before OCaml syntax is written, the function-local plan proves that `early`
already uses the registered `Counter` record. The control record then carries
the same semantic type, target carrier, representation identity, layout
revision, and representation proof into the function's private return signal.
Generated OCaml uses `Obj.repr` once while control is in flight and `Obj.obj`
once at the exact `Counter` boundary. The recovered value remains the same
mutable object, so later field writes and aliases observe the same state.

This does not admit every class-shaped value. Class parameters, call-produced
locals, inheritance, interfaces, generics, extern classes, dynamic methods,
and the Haxe null sentinel remain on the older path. In particular,
`return null` from a class-valued function still needs a separate
null-to-nominal conversion contract; the record-carrier proof does not invent
that crossing. The lowering report and public inspector reject a control
record whose nominal layout revision or representation proof disagrees with
the program registry.

The tenth slice seals exact nullable primitive throws before OCaml syntax.
Upstream Haxe 4.3.7 distinguishes the value thrown, not merely its static
nullable type: a non-null `Null<Int>` reaches `catch (value:Int)`, a non-null
`Null<Bool>` reaches `catch (value:Bool)`, and null skips both concrete catches
and reaches `Dynamic`. The same distinction survives a function call and
rethrow.

`Null<Int>` can use its existing `Obj.t` carrier unchanged because a non-null
OCaml integer has an unambiguous runtime shape. `Null<Bool>` needs one explicit
control-boundary normalization: OCaml represents ordinary nullable Bool
storage with `Obj.repr`, where `true` can otherwise look like the integer `1`.
The sealed throw decision therefore preserves null, but unboxes and reboxes a
non-null Bool once into the runtime's existing unambiguous Bool exception
carrier. The shared exception channel then derives the concrete tag from the
actual payload. Generated syntax does not select catch compatibility, use
`Obj.magic`, or create a second exception mechanism.

The eleventh slice extends that same exception channel to one exact
whole-program-monomorphic class. A **whole-program-monomorphic class** here is
a concrete, non-extern, non-generic user class with no superclass, subclasses,
interfaces, or dynamic methods, for which the compiler has selected one OCaml
record layout. For example:

```haxe
final thrown = new Box(4);
final alias = thrown;
try {
	throw thrown;
} catch (_:Int) {
	trace("wrong");
} catch (caught:Box) {
	caught.value++;
	trace(caught == alias);
}
```

Before target syntax is written, the throw record names the exact `Box`
representation, layout revision, and representation proof. The payload crosses
the shared exception channel opaquely as `Obj.t`; the matching `Box` catch first
checks the runtime `Box` marker and then recovers the registered record type.
The catch therefore receives the same mutable object rather than a copy, and a
later rethrow preserves both the object identity and any field mutation.

Only `Dynamic` is attached as a static throw tag. For a real record, the
existing runtime derives `Box` from its `__hx_type` marker; for a class-typed
null, there is no `Box` marker, so the value skips `catch (_:Box)` and reaches
`Dynamic`, matching upstream Haxe 4.3.7. This avoids a stale type tag that could
make null look like an instance. The lowering report and public inspector bind
both throw and catch records to the same program-owned layout proof and reject
a stale or conflicting revision.

This is deliberately not general class-exception support. Inheritance,
interfaces, generics, extern classes, dynamic methods, `haxe.Exception`,
`haxe.ValueException`, enums, abstracts, nullable catch declarations, and
class values that lack an exact representation proof remain unadmitted. The
slice proves only the exception crossing and recovery boundary; it does not
claim that every operation on a class value is already free of older target
fallbacks.

The twelfth slice seals a throw whose static Haxe type is `Dynamic`. The
practical change is that this function no longer asks the OCaml syntax builder
how to box or classify `value`:

```haxe
static function fail(value:Dynamic):Void {
	throw value;
}
```

`Dynamic` already uses `Obj.t` in the target: one opaque OCaml carrier that can
hold the runtime value without choosing its source type again. The control plan
now records that exact carrier under the control-only identity
`control-representation:Dynamic:runtime-obj-v1` and selects
`preserve-dynamic-throw-carrier`. Generated syntax transports the carrier
unchanged. It neither applies `Obj.repr` a second time nor invents an exact tag
from the static `Dynamic` annotation.

Only `Dynamic` is attached as a static tag. The existing exception channel
examines the value already in the carrier: an integer reaches an `Int` catch, a
Bool reaches `Bool`, a non-null String reaches `String`, and an admitted
monomorphic-class record contributes its runtime class marker. Null contributes
no more specific tag and therefore reaches only the final `Dynamic` catch. A
`Dynamic` catch preserves the same carrier, so rethrowing that variable keeps
the runtime value and lets an outer exact catch classify it the same way.

This is exception-transport support, not a general `Dynamic` representation
claim. Dynamic fields, storage, calls, operators, reflection, public ABI, and
metal-profile admission keep their existing owners. The slice also does not
define `haxe.Exception` or `haxe.ValueException` wrapping, class-hierarchy
matching, enum/abstract payloads, Float payloads, or nested-function plan
ownership.

This is evidence for `haxe_ocaml-w32h3.1` through
`haxe_ocaml-w32h3.12`, not closure of the parent control-effects requirement.
Additional value-return payloads, other primitive-to-nullable and nullable
return carriers, wider nominal/exception families, cleanup effects, and the
complete runtime-requirement ledger remain unfinished.

Accepted architecture checkpoint:

- `docs/00-project/ORACLE_CHECKPOINT_REFLAXE_OCAML_NATIVE_POWER_IR_2026_07_18.md`
- `docs/00-project/ORACLE_CHECKPOINT_FEATURE_GATED_TYPED_BODY_LIFECYCLE_2026_07_19.md`
- `docs/00-project/ORACLE_CHECKPOINT_SIX_MONTH_ARCHITECTURE_2026_07_23.md`

It is deliberately separate from:

- `docs/00-project/FULL_1_0_CONTRACT.md`
  - strict `hxhx` compiler-equivalence claim
- `docs/00-project/REFLAXE_PROMOTION_MATRIX_CONTRACT.md`
  - multi-host promotion matrix for Reflaxe compilers

## Goal

`reflaxe.ocaml 1.0` means:

- upstream `haxe 4.3.7` can use `reflaxe.ocaml` as a real OCaml target for the declared scope,
- the target/runtime/stdlib surface needed for that scope is production-credible,
- the install/build/run workflow is documented and reproducible,
- and the claim is backed by explicit evidence instead of repo lore.

This is a target-product claim.
It is not a claim that `hxhx` is already `Full 1.0`.

## Ownership boundary

This contract owns:

- upstream `haxe 4.3.7` + `reflaxe.ocaml` compatibility for the declared scope,
- target-owned stdlib/runtime/lowering closure,
- target-level performance credibility,
- operator-facing docs for installation, use, and troubleshooting.

This contract does not own:

- `hxhx` `Scoped 1.0` or `Full 1.0` compiler claims,
- the broader Reflaxe compiler promotion matrix,
- cross-host plugin ABI policy beyond what `reflaxe.ocaml` itself needs as a target,
- behavior that upstream `haxe 4.3.7` does not support.

## Compatibility baseline

- Host compiler baseline: `Haxe 4.3.7`
- Semantic authority: upstream Haxe `4.3.7`
- Target under contract: `reflaxe.ocaml`
- Packaging mode under contract: `-lib reflaxe.ocaml`

Primary user workflow:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out --no-output
```

Native-build workflow:

```bash
haxe -cp src -main Main -lib reflaxe.ocaml -D ocaml_output=out -D ocaml_build=native --no-output
```

## Declared 1.0 scope

The declared `reflaxe.ocaml 1.0` scope includes:

1. Upstream Haxe host usage
   - `haxe 4.3.7` remains the controlling frontend and macro host.

2. OCaml output generation
   - deterministic OCaml project emission through the documented target entrypoint.

3. Dune build integration
   - emitted projects can be built through the documented dune path for the declared profiles.

4. Target-owned runtime and stdlib closure
   - the runtime shims, `_std` overrides, and lowering intrinsics required by the declared compatibility matrix.

5. Production-facing docs
   - users can install, invoke, and troubleshoot the target without relying on internal session history.

## Scope references

This contract relies on these narrower surfaces:

- upstream-use guide:
  - `docs/01-getting-started/REFLAXE_OCAML_WITH_UPSTREAM_HAXE.md`
- current compatibility summary:
  - `docs/02-user-guide/COMPATIBILITY_MATRIX.md`
- stdlib/runtime closure references:
  - `docs/02-user-guide/STDLIB_COVERAGE_PLAN.md`
  - `docs/02-user-guide/STDLIB_PORTABLE_PARITY_MATRIX.md`
  - `docs/02-user-guide/OCAML_RUNTIME_CAPABILITY_MATRIX.md`
- profile/build behavior:
  - `docs/02-user-guide/OCAML_PROFILE_CONTRACT.md`

## Required evidence

`reflaxe.ocaml 1.0` must be justified by explicit evidence lanes.

Required marker set:

- `RO_HAXE_4_3_7_MATRIX:PASS`
  - upstream `haxe 4.3.7` validation matrix for the declared target scope
  - source of truth:
    - `docs/00-project/REFLAXE_OCAML_HAXE_4_3_7_MATRIX.md`
    - `docs/00-project/REFLAXE_OCAML_HAXE_4_3_7_MATRIX.json`
- `RO_RUNTIME_STDLIB_CLOSURE:PASS`
  - target-owned stdlib/runtime/lowering closure audit is complete for the declared scope
  - source of truth:
    - `docs/00-project/REFLAXE_OCAML_RUNTIME_STDLIB_CLOSURE_AUDIT.md`
    - `docs/00-project/REFLAXE_OCAML_RUNTIME_STDLIB_CLOSURE_AUDIT.json`
- `RO_TARGET_PERF_CREDIBLE:PASS`
  - target-level performance evidence exists for upstream `haxe 4.3.7 + reflaxe.ocaml`
  - source of truth:
    - `docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md`
    - `docs/00-project/REFLAXE_OCAML_PERF_BASELINE.json`
- `RO_TARGET_ITERATION_REPORT:PASS`
  - a copied standalone project completed the declared cold-output,
    unchanged-warm, and one-file-change method without mutating tracked source
  - timings remain report-only until stable hosted trends justify a reviewed
    threshold; this marker proves method and behavior, not a speed budget
- `RO_PRODUCTION_DOCS:PASS`
  - operator-facing install/use/troubleshooting docs exist and match reality
  - source of truth:
    - `docs/01-getting-started/REFLAXE_OCAML_PRODUCTION.md`
- `RO_PRODUCTION_READY:PASS`
  - current aggregate marker for the historical declared product-level inputs;
    it does not authorize 1.0 until it also opens the semantic-safety
    prerequisites below
  - local evidence command:
    - `npm run test:reflaxe-ocaml:production-ready`

Required semantic-safety prerequisites before release authorization:

- an upstream-Haxe-oracle-backed place/evaluation/assignment slice is sealed
  before target syntax, including explicit occurrence counts and deterministic
  unsupported diagnostics (`haxe_ocaml-9v1va`);
- representation, local storage, closure capture, nullability, boxing, and
  boundary carriers come from one immutable registry rather than independent
  compiler and builder guesses (`haxe_ocaml-9bome`);
- represented ordinary non-extern calls, optional arguments, callbacks,
  receivers, constructors, coercions, and conversions use one typed call
  contract before OCaml syntax (`haxe_ocaml-taef5`, completed foundation);
- target-native labels, imported OCaml call shapes, typed adapters, and native
  package dependencies use that foundation only when the declared release scope
  admits them (`haxe_ocaml-v8a9b`);
- returns, throws, catches, loops, and other admitted non-local control behavior
  are explicit before target syntax and fail when the declared OCaml target
  model cannot represent them (`haxe_ocaml-w32h3`); its first eleven slices cover
  exact-`Int`, exact-`Bool`, represented-`String`, and the first
  constructor-produced monomorphic-class local early returns from
  ordinary static functions, including the existing String runtime null
  sentinel; carrier-preserving early returns of exact `Null<Int>` and
  `Null<Bool>` values; and payloadless early return from ordinary static
  `Void` functions without inventing a value. A direct final or nested early
  exact `Int` or `Bool` may cross once into its matching nullable carrier
  inside that function boundary; an already-nullable early value remains
  unchanged. The monomorphic-class slice binds the private crossing to the
  exact program-owned record layout and representation proof, while class
  parameters, call-produced locals, and null-to-nominal conversion remain
  deliberately unadmitted. The slices also cover exact lexical targets for `break` and
  `continue` in ordinary `while` and `do ... while` loops, and
  exact-`Int`/`Bool`/represented-`String` payloads entering the global Haxe
  exception channel with upstream-compatible runtime-value tags. Complete
  source-ordered catch chains over those exact primitive types, one exact
  whole-program-monomorphic class, and a final `Dynamic` catch are also sealed,
  including the separate target-native exception channel and private-control
  bypass. A nominal payload carries the program registry's exact layout proof,
  preserves object identity and mutation through rethrow, and derives its
  class tag only from a real runtime record so null still reaches `Dynamic`.
  Wider class hierarchies, `haxe.Exception`, `haxe.ValueException`, enums,
  abstracts, the remaining value/nullable return conversions, unsupported
  catches, and cleanup families are still release blockers;
- runtime requests fail for unknown, missing, stale, modified, or
  profile-illegal sources, and admitted selective requirements have a semantic
  reason plus checked closure (`haxe_ocaml-0uwin`);
- the aggregate checker and retained release receipt open those results rather
  than relying only on the historical example inventory.

These prerequisites do not make the full future native-power roadmap a 1.0
blocker. Generated bindings, advanced adapters, curated exported libraries,
and one upstream-Haxe/`hxhx` target core block only a public scope that claims
those capabilities. The first standalone 1.0 must still state its actual typed
OCaml-library interop scope; expanding that scope is a separate product
decision, not a silent implication of native output.

Supporting evidence:

- `RO_TARGET_PERF_PLATFORM:PASS`
  - one host measured the exact installed source ZIP outside the checkout with
    complete raw samples and verified runtime output
  - this is an input receipt, not a cross-platform result by itself
- `RO_TARGET_PERF_PLATFORM_MATRIX:PASS`
  - one clean source ZIP is installed and measured on Linux and macOS with the
    canonical six clean-build scenarios plus the standalone authoring-iteration
    workload, complete raw samples, verified behavior, host/toolchain metadata,
    and an aggregate that opens both receipts
  - source of truth:
    - `.github/workflows/reflaxe-ocaml-package-matrix.yml`
    - `docs/00-project/REFLAXE_OCAML_PERF_CREDIBILITY.md`
  - results are per host; this marker does not authorize cross-host absolute
    timing comparisons or replace `hxhx` compiler/plugin performance evidence
- `RO_PACKAGE_ARTIFACT_MATRIX:PASS`
  - one clean CI producer builds the deterministic source ZIP and Linux plus
    macOS consumers install, compile, build, and run that exact artifact
  - source of truth:
    - `.github/workflows/reflaxe-ocaml-package-matrix.yml`
  - this is verified-host evidence, not a blanket operating-system support
    declaration; Windows remains unclaimed until it has its own clean proof
- `RO_PACKAGE_INSTALL_SMOKE:PASS`
  - a deterministic, source-only ZIP installs into a disposable haxelib
    repository and builds/runs an external application with stock Haxe 4.3.7
  - local evidence command:
    - `npm run test:reflaxe-ocaml:package-install`
  - this marker is platform/toolchain-specific until the release owner retains
    the declared support matrix
- focused repo-local regressions
- portable fixtures
- benchmark snapshots

Supporting evidence is useful for diagnosis and iteration speed, but it does not replace the upstream-host target matrix.

## Production-ready statement

A truthful public statement at this layer looks like:

- `reflaxe.ocaml is production-ready for the declared Haxe 4.3.7 scope`

It must not be shortened into:

- `hxhx is Full 1.0`
- `the whole repo is 1.0`
- `all Reflaxe promotion paths are production-ready`

Those are separate claims with separate contracts.

## Non-goals

These are explicitly out of scope for this contract:

- proving `hxhx` compiler equivalence to upstream Haxe
- proving all Reflaxe compiler promotion paths
- proving every Haxe version beyond `4.3.7`
- sibling-repo-specific semantics that upstream Haxe `4.3.7` does not define
- undocumented host/plugin combinations

## Decision rules

- `upstream Haxe first`
  - upstream `4.3.7` remains the semantics authority
- `target product second`
  - fix target-level gaps before broadening host/promotion claims
- `no hidden scope inflation`
  - if a new requirement belongs to promotion or compiler equivalence, track it under the other contract instead of silently expanding this one
- `semantic safety before plausible output`
  - behavior inside the declared scope has one validated owner before OCaml
    syntax, and unsupported behavior fails at the Haxe source boundary rather
    than becoming unit, null, `Dynamic`, raw source, or an unsafe cast
- `evidence aggregate is not release authority by name alone`
  - a historical `RO_PRODUCTION_READY:PASS` receipt remains bounded to the
    inputs it opened; release authorization waits for every current required
    prerequisite in this contract
