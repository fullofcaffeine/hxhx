# Generic module array snapshots

A static generic helper in a recursive module group saves a copy of a callback-returned `Array<T>` and returns a closure that compares later elements with `!=`. Callers specialize it with Int, Float, Bool, String, `Null<Int>`, and class elements.

Native output must match upstream Haxe eval. Rows check one producer call per observation, value equality for numbers and separately allocated equal strings, null preservation, and object identity rather than structural equality.

This reproduces the compiler bootstrap helper `TyFunctionInference.unchangedArray` (haxe_ocaml-896mh). It does not claim general generic-array transport such as `append<T>(Array<T>, T)`.

Run `PORTABLE_FIXTURE_ALLOWLIST=generic_module_array_snapshot bash scripts/test-portable.sh` from the repository root.
