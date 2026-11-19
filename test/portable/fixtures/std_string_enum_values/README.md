# Print enum values with Std.string

`Std.string(Green)` must print `Green`, as upstream Haxe 4.3.7 does. The fixture also
covers an enum with arguments, string concatenation, and `Null<Color>` values that hold a
value or `null`.

A constant enum constructor is an OCaml immediate. When the printer received it through
a plain `Obj.repr`, the runtime could not tell it from an `Int` and printed `1`
(`haxe_ocaml-oxjcd`). A `Null<Color>` value took the static conversion path, which had
no enum printer and emitted the literal text `<unsupported>`. Both now enter
`HxDynamic.toStdString` through the enum box that names the enum.

Run `PORTABLE_FIXTURE_ALLOWLIST=std_string_enum_values bash scripts/test-portable.sh`.
The portable runner builds and runs native output against expected.stdout.
The extra test compares the same program with upstream Haxe eval.
