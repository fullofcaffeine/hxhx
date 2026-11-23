# Array null argument

An `Array<Null<Int>>` is passed where an `Array<Int>` is expected, as in Haxe 4.3.7, which compares invariant type arguments with `type_eq` and follows `Null`. A null slot read through the `Int` view prints `null` under `--interp` and the frozen Stage3 emitter; static targets (reflaxe.ocaml, haxe_ocaml-9cqxj) give 0.

Run `node_modules/.bin/haxe test/m14_array_null_argument_test.hxml`. The test compares input types with upstream and runs the native output.
