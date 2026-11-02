# Stage3 Null<Int> and Int values into Float destinations

`Main.hx` stores a `Null<Int>` value (and a `Null<Float>` value) into a Float
class field, an `Array<Float>` slot (with `push` and with an indexed write),
a Float local, a Float function parameter, and a Float return. It also stores
Int and `Null<Int>` values into the Float fields of an anonymous structure,
both in the object literal and with a field write, and Int literals into an
`Array<Float>` literal and a Float field. Each value is read back as a Float.

Before the fix, the native program crashed with SIGSEGV and printed nothing.
A `Null<Int>` value lives in a nullable carrier (an OCaml `Obj.t` holding an
immediate int, or the null sentinel), and Int values in anonymous Float
fields were stored as OCaml ints. A later Float read then dereferenced the
immediate int. Each of these destinations now unwraps the carrier and
converts the value to Float. A null value raises the runtime's Null Access
error.

It also stores `Null<Int>` values, null and present, into `Null<Float>`
destinations (a class field, an `Array<Null<Float>>` literal, `push` and
indexed write, a structure field, a local) and into an optional structure
field (`?o:Float`). Null stays null there, and a present Int becomes a boxed
Float.

Known divergence: upstream Haxe stores a null `Null<Int>` into any Float
destination without an error, and only a later arithmetic use fails. Native
Stage3 stores an unboxed OCaml float in a non-nullable Float local, class
field, array element, argument or return, and an OCaml float cannot hold
null. So storing a null `Null<Int>` there raises the runtime's Null Access
error at the store (haxe_ocaml-3405c). Structure fields, `Null<Float>`
destinations and optional fields keep null as upstream does.

Float results are printed after adding a fraction (`h.f + 0.25`), because
native printing of a whole-number Float such as `3.0` still differs from
upstream (haxe_ocaml-vzr17).

`npm run test:m14:stage3-nullable-int-to-float` checks that upstream Haxe
4.3.7 prints `expected.stdout`. It then builds the program with Stage3 and
requires the native executable to print the same text.
