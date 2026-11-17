# `Dynamic` null read as a basic type

A `Dynamic` value that holds `null` and is read as `Int`, `Float`, or `Bool` must give `0`,
`0.0`, or `false`. That is the rule for static targets that the project decided on
2026-11-17 (`haxe_ocaml-9cqxj`), and the JVM, Java, C#, and C++ targets of upstream Haxe
4.3.7 print the same. The fixture also reads non-null values, which must keep their value.

Before the fix, the native program printed a large garbage number for `Int`, `4.94e-324` for
`Float`, and `true` for `Bool` (`haxe_ocaml-9cqxj.3`). The assignment applied a bare
`Obj.obj` (or the Boolean unbox) to the runtime's null marker. The read now takes its
conversion from the table `OcamlValueConversion`, which gives the default value for null.

`haxe --interp` is a dynamic target and prints `null` on the first line, so `test.sh`
compares only the second line, which holds no null, with it.

Run `PORTABLE_FIXTURE_ALLOWLIST=dynamic_null_basic_types bash scripts/test-portable.sh`.
