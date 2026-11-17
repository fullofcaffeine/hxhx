# Enum values cast to `Null<Enum>`

`(Green : Null<Color>)` must give a `Null<Color>` value that holds `Green`, as upstream
Haxe 4.3.7 does. The fixture uses that cast in a local, an argument, a return value, a
typedef of `Null<Color>`, a captured local, a structure field, and a `Dynamic` local. It
also casts `Null<Color>` back to `Color` before a `switch`.

`reflaxe.ocaml` stores `Null<Color>` as an `Obj.t` that holds the native variant. The
cast lowering did not list the pair `Color` to `Null<Color>`, so it kept the native
variant, and the OCaml build failed with "This expression has type color but an
expression was expected of type Obj.t" (`haxe_ocaml-9cqxj`). Casts and assignments now
take this conversion from one table, `OcamlValueConversion`.

Run `PORTABLE_FIXTURE_ALLOWLIST=null_enum_casts bash scripts/test-portable.sh`.
The portable runner builds and runs native output against expected.stdout.
The extra test compares the same program with upstream Haxe eval.
