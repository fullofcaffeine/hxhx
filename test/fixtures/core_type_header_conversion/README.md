# Core type header conversion

A `@:coreType` abstract's header conversions are casts, as in Haxe 4.3.7: `Tools.release(async)` for `release(handle:Handle)` with `@:coreType abstract Async to Handle`.

Run `node_modules/.bin/haxe test/m14_core_type_header_conversion_test.hxml`. The test types the program but does not run it natively: a core type has no values that a program can create.
