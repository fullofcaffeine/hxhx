# Second-pass review: optional Dynamic call carriers

## Outcome reviewed

A function declared with `?value:Dynamic` now receives the same generic object
carrier whether the caller omits the argument or supplies null, a primitive, or
an object. Haxe 4.3.7 exposes that parameter as `Null<Dynamic>` inside the
function body. This does not mean OCaml needs an option wrapped around another
value: the existing `Dynamic` `Obj.t` carrier already includes Haxe null.

## Architecture checks

- `OcamlRepresentationRegistry.isExactNullDynamic` recognizes only the core
  `Null` wrapper around exact `Dynamic`. It does not follow typedefs or broaden
  unrelated nullable types.
- The callable declaration normalizes that Haxe type shape to the existing
  `Dynamic` representation. No second carrier or unchecked compatibility route
  was introduced.
- Omission and an explicitly written null are separate conversions. Omission
  has no source expression and uses a source-free schedule step; explicit null
  remains a supplied argument in source order.
- Bool uses the checked, call-owned `HxRuntime.box_bool` occurrence introduced
  by `haxe_ocaml-0uwin.45`. Int, String, and nominal objects use the existing
  concrete-to-Dynamic conversion. Values already typed Dynamic preserve their
  carrier.
- Direct calls cover all requested value families. A computed optional-Dynamic
  function value also uses the same sealed primitive conversion matrix, closing
  the precheck mismatch that previously existed for Int and String.
- `Std.string` recognizes exact `Null<Dynamic>` as the same dynamic carrier.
  Its repeated target-syntax constructor was consolidated, so the legacy
  private-runtime inventory decreases from 387 to 386 rather than growing.

## Adversarial and behavior checks

The focused model rejects a wrong omitted proof, an omitted conversion without
the optional flag, and a wrong explicit-null proof. Existing common validation
still rejects non-trailing or multiple optional parameters, malformed schedules,
and declaration/boundary mismatches.

The native tracer compares itself with the installed Haxe 4.3.7 interpreter,
then compiles and runs generated OCaml. It covers omitted, explicit null, Bool,
Int, String, a nominal object payload, and a computed function value. The
lowering report contains seven sealed optional-Dynamic calls, and the runtime
report contains exactly one call-owned Boolean carrier requirement.

## Verification-cost finding

The broad runtime-use authority command did not reach its assertions within a
five-minute checkpoint. A process sample showed the Haxe compiler spending its
time in the package-wide null-safety traversal, and an older owned copy of the
same command had remained alive for twenty-four minutes. The process groups
were stopped cleanly. This is tracked by `haxe_ocaml-tqv34`; it is not evidence
of a semantic failure in this change. The focused runtime requirement test and
the native tracer both exercised the changed requirement path successfully.

## Closure judgment

The fix uses one typed carrier, keeps optional scheduling explicit, fails closed
before syntax when a plan is absent, and adds no generated-file repair. README
readiness remains unchanged because this closes one compatibility gap rather
than completing the target or Full1 portfolio. Oracle review was not needed:
the existing call plan and representation registry provided a bounded seam, and
the red tests converged without an unresolved architecture choice.
