# Standard string conversion

Run `npm run test:m14:stage3-string-conversion` from the repository root.
The suite compares authored Haxe with pinned upstream Haxe 4.3.7 and native
Stage3 output. It keeps independent expected files for scalar and array behavior.

`npm run test:m14:stage3-bool-string` checks the 22 lines in `expected.stdout`.
Booleans must print `true` or `false`, while integers still print `0` or `1`.
The cases cover literals, locals, comparisons, function results, Dynamic storage,
nullable Boolean parameters, null, strings, and a static field initializer.
The effectful argument must print `effect` once before its converted result.

The scalar test also verifies that another function, a copied expression, or a
mutated operand cannot supply a call argument's type. The compiler retains each
argument's exact typed occurrence through its source-shaped backend projection.
The OCaml target then selects the existing Boolean boxing or nullable conversion
operation before invoking the string runtime.

`npm run test:m14:stage3-array-string` checks typed arrays and then arrays passed
through `Dynamic`. The observer loads real standard-library declarations, so
`Array` has a resolved identity. Typed arrays now use the runtime's array formatter
with an element converter selected from the typed argument. The fourteen-line contract
covers integers, Booleans, strings, empty and nested arrays, null, aliases, and an
effectful function result. Literal elements run in source order, and generated
temporary names must not shadow an authored local.

The Dynamic contract under `haxe_ocaml-8p3m5` requires contents after whole-array
type erasure. A mixed `Array<Dynamic>` preserves `[false,0,null,tail]`: allocation
boxes the Boolean before its type is erased. Each native array retains an element
formatter selected by Haxe from its exact type. Passing the array through a
`Dynamic` parameter preserves that same array and formatter. The five-line expectation covers
mixed, Boolean, and integer arrays, including a Boolean-only literal assigned to
`Array<Dynamic>`. These assertions must not be weakened.

`DynamicArrayIdentityMain` extends that contract with aliases retained before
mutation. Boolean and integer arrays must keep distinct formatting in the same
process. Nested and initially empty arrays must reflect later typed writes through
their erased aliases. The original array identity, one function-call effect, and
nullable-array conversion also remain observable. The twelve-line expectation is
checked independently against upstream before native execution.

`ArrayProducerMain` checks construction, copy, concat, slice, splice, filter, and
map results after erasure. Operations that preserve element types also preserve
their formatter, including empty results that later receive elements. Map selects
a new formatter from its result type. Nullable Boolean elements and mutations of
Dynamic elements remain distinct from integer values. Run this observer alone with
`haxe test/m14_stage3_array_producer_string_test.hxml`; the array suite also requires it.

The contextual-array observer checks declarations, later assignments, parameters,
returns, nested arrays, and static initializers. Each destination supplies its
element type before storage is selected. The child expressions keep their own
types: a Boolean entering a Dynamic slot still needs a Boolean box. Both upstream
and the local typer must reject the separate `Array<Int> = [false]` fixture and
the Float-to-Int narrowing fixture. Element acceptance uses the shared directional
conversion rules; overload ranking does not authorize a storage conversion.

The combined string suite remains part of `test:m14:stage3-typed-local-projection`.
The array suite first runs `m14_typed_array_access_projection_test.hxml`.
Its `ArrayAccessMain` observer checks indexed reads, assignment results, and
compound-update ordering against upstream and native OCaml. A right operand
changes the same array slot; the compound update must still use the old value.
Projection checks retain Boolean, integer, and Dynamic types and reject copied,
foreign, removed, and mutated occurrences in functions and field initializers.
The separate static-initializer/function-order defect is tracked by
`haxe_ocaml-j6aof`; it is not hidden by these indexed-access checks.

Scalar behavior is tracked by `haxe_ocaml-agc6n`. README Goals status is unchanged;
these local regressions do not prove complete string conversion or release parity.
