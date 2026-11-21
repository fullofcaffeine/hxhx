# Abstract field operator

A read of an unknown field on an abstract with an `@:op(a.b)` method calls that method with the field name, as in Haxe 4.3.7: `table.width` is `table.resolve("width")`.

Run `node_modules/.bin/haxe test/m14_abstract_field_operator_test.hxml`.
