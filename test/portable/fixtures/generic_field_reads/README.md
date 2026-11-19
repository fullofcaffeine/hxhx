# Reads of type-parameter fields at concrete types

`new Holder<Int>(42).value + 1` must give `43`, as in upstream Haxe 4.3.7. The fixture reads
a field declared as `T` at `Int`, `Float`, `Bool`, `String`, `Array<Int>`, `Int->Int`, and a
class type, and reads both fields of a class with two type parameters.

`reflaxe.ocaml` stores a field declared as `T` as an `Obj.t`. Generic code boxes a `Bool`
with `HxRuntime.box_bool` and other values with `Obj.repr`. A read at a concrete type kept
the `Obj.t`, so the OCaml build failed with "This field access has type Obj.t"
(`haxe_ocaml-9cqxj`, the `generic_class` column of the representation matrix). The read now
takes its conversion from the table `OcamlValueConversion`.

Writes after construction, such as `holder.value = 5`, are not covered yet
(`haxe_ocaml-9cqxj.1`).

Run `PORTABLE_FIXTURE_ALLOWLIST=generic_field_reads bash scripts/test-portable.sh`.
The portable runner builds and runs native output against expected.stdout.
The extra test compares the same program with upstream Haxe eval.
