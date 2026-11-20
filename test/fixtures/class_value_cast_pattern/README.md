# Class value cast pattern

A switch on a class value can match `cast` patterns with a dotted type path (`case cast haxe.ds.StringMap:`), as `haxe.Serializer` does. Upstream Haxe 4.3.7 reads the path as a type, not as a qualified enum constructor.

Run `node_modules/.bin/haxe test/m14_class_value_cast_pattern_test.hxml`. The test compares types and types the full program; it does not run native output, because frozen Stage3 does not lower class-value patterns (haxe_ocaml-lncpt).
