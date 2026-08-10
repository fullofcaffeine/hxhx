# Second-pass review: Array insertion, removal, and membership

## Outcome

The change is safe to close as a three-operation hard cut. Final typed calls to
`insert`, `remove`, and `contains` on the root Haxe `Array<T>` now carry their
meaning into OCaml syntax generation. The late builder cases are gone; syntax
only renders the checked target and its exact authorized runtime reference.

The review also found and fixed a pre-existing runtime equality defect. This
was necessary for a truthful Haxe-compatibility claim, but it did not create a
second compiler path: Array runtime operations now reuse the equality rule that
already serves Dynamic values.

## Type and operation identity

Selection requires the real root `Array` class, the exact final receiver type,
and the admitted argument count. A user class whose field happens to be named
`contains` cannot enter this path.

`insert` records formal parameters `Int` and `T`; its actual position must
still be exactly `Int`, while its value uses the Haxe typer's explicit
compatibility proof. `remove` and `contains` similarly keep both their formal
`T` and actual source type. This preserves valid calls such as inserting a
`String` into `Array<Dynamic>` without trying to reconstruct Haxe assignability
from display strings.

`insert` has an effect-only `Void` result. `remove` and `contains` return
`Bool`. None of the three private OCaml functions takes a synthetic trailing
`unit`. Focused corruption cases cover operation, parameters, actual types,
compatibility, result, unit convention, runtime symbol, and call result form.

## Evaluation and mutation behavior

The sealed schedule evaluates the receiver once, then each source argument
once in source order. The shared upstream/generated fixture observes
`receiver,position,value` for insertion and `receiver,argument` for removal
and membership.

The behavior oracle covers insertion in the middle, a negative position, and a
position beyond the end. It also covers first-match removal, missing removal,
found and missing membership, and mixed `Array<Dynamic>` values. Both upstream
Haxe and the native generated OCaml executable accept the same observations.

## Equality ownership

The vertical tracer added two separate class instances with identical fields.
Upstream Haxe correctly treated them as different identities, while generated
OCaml initially matched them because `HxArray` used OCaml's structural `=`.

`HxArray` now calls the existing `HxRuntime.dynamic_equals` helper for removal,
forward search, and reverse search. That helper compares numbers, Booleans, and
strings by Haxe value rules, and other objects by physical identity. The Array
module remains a narrow handwritten runtime primitive; the Haxe-authored
compiler still decides when each typed operation is used. The checked runtime
manifest records the new exact `HxArray.ml` digest, and the handwritten-OCaml
ownership guard remains green.

Although `indexOf` and `lastIndexOf` are not migrated by this Bead, they share
the corrected runtime comparison. Their late call-selection cases remain
visible in the inventory and are not counted as completed work here.

## Runtime authority, reports, and inventory

Every generated private reference has one immutable occurrence bound to the
exact call, source span, function revision, profile, requirement, and
`HxArray` symbol. Missing, duplicate, stale, wrong-owner, wrong-domain,
wrong-profile, wrong-symbol, and plain unowned references fail before output
publication.

The function-plan revision is `v89`, the call model is `v23`, the standard
Array proof is `v3`, and the lowering schema is 74. Public inspection validates
the expanded operation/type/result/unit data and passes its full corruption
matrix. Six checked lowering reports were regenerated through the two-run
deterministic updater and then passed in ordinary comparison mode.

The private-runtime inventory falls exactly from 346 to 343. Only the late
`insert`, `remove`, and `contains` builder rows disappeared. Optional/defaulted
searches, slicing, splicing, resize, callbacks, formatting, indexed access,
allocation, and internal compiler Array uses remain visible.

## Claim boundary

No generated OCaml was edited and no README goal moved. Requirements-only
runtime source selection is still incomplete, with 343 inventory entries
remaining. The Haxe-to-OCaml backend evidence passes independently.

The optional `npm run test:m14:hih-array-contains` command is stale and points
to a missing HXML; `haxe_ocaml-3b9uw` owns that testing-infrastructure repair.
Its missing fixture supplies no hxhx evidence and is not counted toward this
target-backend claim.

Oracle review was deliberately skipped. The typed-call seam was established,
the equality mismatch had a direct upstream oracle and an existing narrow
runtime helper, and focused plus vertical evidence converged without an
unresolved architecture choice.
