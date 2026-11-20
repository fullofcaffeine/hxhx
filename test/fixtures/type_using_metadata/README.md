# Type using metadata

A type's `@:using` metadata adds static extensions to its values, as in Haxe 4.3.7: `result.resolve()` for `@:using(pk.Res.ResTools) enum Res<T>`.

Run `node_modules/.bin/haxe test/m14_type_using_metadata_test.hxml`. `pk/Res.hx` declares a generic enum with `@:using`; `pk/Meter.hx` an abstract whose provider takes its `to` type. The test types the program but does not run it natively: frozen Stage3 cannot emit generic enums.
