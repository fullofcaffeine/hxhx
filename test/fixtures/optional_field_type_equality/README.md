# Optional field type equality

Arrays whose element types differ only by `Null` or field optionality are the same type, as in Haxe 4.3.7. An array built from object literals with a `tag:Null<Int>` field matches `Array<{name:String, ?tag:Int}>` and `Array<{name:String, tag:Int}>`, and `Array<Null<Int>>` matches `Array<Int>`. `haxe.macro.ExprTools.map` builds its `EObjectDecl` fields this way.

Run `node_modules/.bin/haxe test/m14_optional_field_type_equality_test.hxml`. The test compares input types with upstream and runs the native output.
