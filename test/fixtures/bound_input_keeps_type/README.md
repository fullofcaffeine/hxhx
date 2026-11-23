# Bound input keeps type

A method body binds an untyped parameter (`switch (s)` gives `s : Item`) before a recursive call passes it a wider value (`Null<Item>`); the parameter stays `Item`, as in Haxe 4.3.7. `haxe.CallStack.itemToString` has this shape, with the pattern variable shadowing the parameter.

Run `node_modules/.bin/haxe test/m14_bound_input_keeps_type_test.hxml`. The test compares input types with upstream, checks the wrapped types, and runs the native output.
