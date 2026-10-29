Check that a rest parameter behaves like upstream Haxe in native OCaml output.

A rest parameter such as `...parts:String` lets callers pass any number of
values. Haxe gives the method body a `haxe.Rest<String>` value, the standard
library abstract over an array. The fixture uses that value through each of its
everyday operations:

- `toArray()` with a fixed parameter before the rest parameter (`join`),
- `toArray()` with no fixed parameters (`bracket`),
- `length`, an indexed read, and a `for` loop over the values (`describe`).

Each method is called with zero, one, and several values. The call site packs
those values into the rest value; the method body must not see a plain array.

Run `haxe test/m14_stage3_rest_parameter_test.hxml` (or
`npm run test:m14:stage3-rest-parameter`) to compare upstream Haxe with the
generated native OCaml executable.
