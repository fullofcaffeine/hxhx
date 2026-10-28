Keep one native representation for nullable `Int` and `Float` values.

Haxe lets a `Null<Int>` hold either `null` or an integer. OCaml `int` cannot
hold a null sentinel, so the native program carries a nullable primitive as an
`Obj.t`: `HxRuntime.hx_null` for null and the ordinary Dynamic box
(`Obj.repr`) for a value. `Std.parseInt` already returns that carrier. The
fixture checks the places where a value crosses between the two shapes:

- a ternary whose branches mix `Std.parseInt` with a plain `0` (the version
  parser from the Stage3 end-to-end job, which previously failed to compile),
- a plain assignment of `41` and of `null` into a `Null<Int>` local,
- arithmetic on nullable locals after a null check,
- `==` and `!=` between a nullable value and `null` or a literal,
- a `Null<Float>` local through the same assignment, arithmetic, and equality,
- functions that return `Null<Int>` from branches that disagree about nullability,
- a nullable local passed to a required `Int` parameter (unwrapped at the call),
- an optional `?size:Int` parameter that receives nothing, a plain `8`, and a
  nullable local, and an optional `?scale:Int = 3` parameter whose present
  value is unwrapped on entry. Optional Int, Float, and Bool parameters travel
  in the carrier, so an omitted argument's null sentinel never has to be read
  as a primitive.

Reading a null through arithmetic or a required primitive parameter raises the
runtime's Null Access exception; upstream targets disagree about null
arithmetic, so the fixture only reads values after a null check. The parser
receives already split version parts because this root-only harness emits no
`String.split` provider. Integral float literals such as `3.0` are avoided
because of the separate literal defect tracked in haxe_ocaml-l26hl.

Run `haxe test/m14_stage3_nullable_int_carrier_test.hxml` (or
`npm run test:m14:stage3-nullable-int-carrier`) to compare upstream Haxe with
the generated native OCaml executable.
