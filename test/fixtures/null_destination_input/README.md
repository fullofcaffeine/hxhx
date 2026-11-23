# Null destination input

An untyped argument whose first evidence is an assignment to a `Null<T>` field takes `Null<T>`, as in Haxe 4.3.7; an argument an earlier use already bound keeps its type. `haxe.io.Path.withExtension` has this shape.

Run `node_modules/.bin/haxe test/m14_null_destination_input_test.hxml`. The test compares input types with upstream, checks the wrapped types, and runs the native output.
