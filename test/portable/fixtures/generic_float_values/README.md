# Float values in type-parameter fields

`new Holder<Float>(1).value * 2` must print `2`, as upstream Haxe 4.3.7 does. Generic code
stores the constructor argument `1` as `Obj.repr 1`, an unboxed OCaml int, while a read at
`Float` expected a boxed float. After generic field reads were converted (PR #213), the read
crashed with a segmentation fault (`haxe_ocaml-9cqxj`, found by an independent review).
The checked Float unbox now tests `Obj.is_int` and converts an int with `float_of_int`.
OCaml floats are always boxed, so the test cannot mistake a float for an int.

Run `PORTABLE_FIXTURE_ALLOWLIST=generic_float_values bash scripts/test-portable.sh`.
