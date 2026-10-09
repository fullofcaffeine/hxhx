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

The Dynamic contract remains failing under `haxe_ocaml-8p3m5`. A mixed
`Array<Dynamic>` now preserves `[false,0,null,tail]`: allocation boxes the Boolean
before its type is erased. Passing the whole array through a `Dynamic` parameter
still prints `Array`. The required five-line expectation retains the contents for
mixed, Boolean, and integer arrays, including a Boolean-only literal assigned to
`Array<Dynamic>`. These assertions must not be weakened.

The contextual-array observer checks declarations, later assignments, parameters,
returns, nested arrays, and static initializers. Each destination supplies its
element type before storage is selected. The child expressions keep their own
types: a Boolean entering a Dynamic slot still needs a Boolean box. Both upstream
and the local typer must reject the separate `Array<Int> = [false]` fixture and
the Float-to-Int narrowing fixture. Element acceptance uses the shared directional
conversion rules; overload ranking does not authorize a storage conversion.

The combined string suite remains part of `test:m14:stage3-typed-local-projection`.
Scalar behavior is tracked by `haxe_ocaml-agc6n`. README Goals status is unchanged;
these local regressions do not prove complete string conversion or release parity.
